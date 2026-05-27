-- Shinobi no Satori – Quest Logic (rewritten)
--
-- Flow per reward cycle:
--   1. Player arrives at arena → chest is ready (stage = "chest_spawned")
--   2. Player right-clicks chest → formspec shows reward info, item is given,
--      chest node removed.  stage → "received_reward"
--   3. Player closes formspec → arena swapped to boss version, boss spawns.
--      stage → "fighting_boss"
--   4. Player kills all bosses → arena swapped back to chest version with the
--      next reward, stage → "chest_spawned".  Cycle repeats.
--   5. After the final reward the quest ends: stage → "quest_complete".
--
-- Arena containment:
--   During a boss fight neither the player nor any boss may leave the arena.
--   If EITHER exits the boundary, BOTH are teleported back to the centre.
--
-- Despawn ≠ kill:
--   If a boss entity disappears while its last recorded HP was still > 0 (i.e.
--   the engine unloaded the chunk), it is considered despawned, NOT killed.
--   A respawn is scheduled instead.  Only HP reaching ≤ 0 counts as a kill.

local modpath             = minetest.get_modpath("sns")
local worldpath           = minetest.get_worldpath()

-- ============================================================
-- Persistence
-- ============================================================
local quest_progress_file = worldpath .. "/sns_quest_progress.json"
local quest_data          = {}

local function save_progress()
    local file = io.open(quest_progress_file, "w")
    if file then
        local json = minetest.write_json(quest_data)
        if not json or json == "null" then json = "{}" end
        file:write(json)
        file:close()
    else
        minetest.log("error", "[sns] Could not save quest progress.")
    end
end

local function load_progress()
    local file = io.open(quest_progress_file, "r")
    if file then
        local data = file:read("*a")
        file:close()
        if not data or data == "" or data == "null" then
            quest_data = {}
            return
        end
        local ok, parsed = pcall(minetest.parse_json, data)
        if ok and type(parsed) == "table" then
            quest_data = parsed
        else
            minetest.log("error", "[sns] Could not parse quest file – resetting.")
            quest_data = {}
            save_progress()
        end
    else
        quest_data = {}
        save_progress()
    end
end

load_progress()

-- ============================================================
-- Arena geometry  (schematic dimensions: X=117, Y=53, Z=59)
-- ============================================================
local ARENA_W      = 117 -- schematic X size
local ARENA_D      = 59  -- schematic Z size
local ARENA_H      = 53  -- schematic Y size
local ARENA_MARGIN = 5   -- containment inset from each wall
local ARENA_FLOOR  = 4   -- Y offset of walkable floor above structure_pos

-- structure_pos is the bottom-left-front corner placed by minetest.place_schematic.
-- Centre of the arena floor:
local function arena_center(sp)
    return {
        x = sp.x + math.floor(ARENA_W / 2), -- 58
        y = sp.y + ARENA_FLOOR + 1,
        z = sp.z + math.floor(ARENA_D / 2), -- 29
    }
end

local function in_arena(pos, sp)
    return pos.x >= sp.x + ARENA_MARGIN
        and pos.x <= sp.x + ARENA_W - ARENA_MARGIN
        and pos.z >= sp.z + ARENA_MARGIN
        and pos.z <= sp.z + ARENA_D - ARENA_MARGIN
        and pos.y >= sp.y - 2
        and pos.y <= sp.y + ARENA_H + 4
end

local function load_arena(sp)
    minetest.load_area(
        { x = sp.x - 5, y = sp.y - 5, z = sp.z - 5 },
        { x = sp.x + ARENA_W + 5, y = sp.y + ARENA_H + 5, z = sp.z + ARENA_D + 5 }
    )
end

-- Find the actual walkable floor at the horizontal center of the arena.
-- Scans upward from sp.y until it finds the first passable node with at least
-- 2 blocks of clearance above a solid node (entity needs ≥2 blocks headroom).
-- Single-block decorative gaps (pillars, cross-beams) are skipped.
-- Falls back to the static ARENA_FLOOR estimate if the area is not yet loaded.
local function find_spawn_pos(sp)
    local cx = sp.x + math.floor(ARENA_W / 2)
    local cz = sp.z + math.floor(ARENA_D / 2)
    local found_solid = false
    for dy = 0, ARENA_H + 2 do
        local node = minetest.get_node({ x = cx, y = sp.y + dy, z = cz })
        if node.name ~= "ignore" then
            local ndef     = minetest.registered_nodes[node.name]
            local is_solid = (ndef == nil) or (ndef.walkable ~= false)
            if is_solid then
                found_solid = true
            elseif found_solid then
                local node2 = minetest.get_node({ x = cx, y = sp.y + dy + 1, z = cz })
                if node2.name ~= "ignore" then
                    local ndef2     = minetest.registered_nodes[node2.name]
                    local is_solid2 = (ndef2 == nil) or (ndef2.walkable ~= false)
                    if not is_solid2 then
                        return { x = cx, y = sp.y + dy, z = cz }
                    end
                end
                found_solid = true
            end
        end
    end
    return { x = cx, y = sp.y + ARENA_FLOOR + 1, z = cz }
end

-- ============================================================
-- HUD helper
-- ============================================================
local function show_hud(player, text, colour, duration)
    local hid = player:hud_add({
        type      = "text",
        position  = { x = 0.5, y = 0.5 },
        text      = text,
        number    = colour,
        scale     = { x = 100, y = 20 },
        alignment = { x = 0, y = 0 },
        size      = { x = 1, y = 1 },
    })
    minetest.after(duration or 5, function(pn, h)
        local pl = minetest.get_player_by_name(pn)
        if pl then pl:hud_remove(h) end
    end, player:get_player_name(), hid)
end

-- ============================================================
-- Dynamic boss pool (scans all registered entities once)
-- ============================================================
local boss_pool = {}

local boss_blacklist = {
    ["__builtin:item"]                = true,
    ["__builtin:falling_node"]        = true,
    ["sns:wall_ghost"]                = true,
    ["sns:fire_shuriken"]             = true,
    ["sns:ice_shuriken"]              = true,
    ["waterdragon:rare_water_dragon"] = true,
    ["pochie_mod:pochie"]             = true,
}

local function get_entity_hp(def)
    if type(def.max_health) == "number" and def.max_health > 0 then return def.max_health end
    if type(def.hp_max) == "number" and def.hp_max > 0 then return def.hp_max end
    if type(def.max_hp) == "number" and def.max_hp > 0 then return def.max_hp end
    if type(def.hp) == "number" and def.hp > 0 then return def.hp end
    if type(def.health) == "number" and def.health > 0 then return def.health end
    if def.initial_properties then
        local ip = def.initial_properties
        if type(ip.hp_max) == "number" and ip.hp_max > 0 then return ip.hp_max end
    end
    return nil
end

-- Strict monster check — only entities that are explicitly declared hostile
-- by their mod author, or Creatura mobs with confirmed attack behaviour.
-- Vague heuristics (keyword names, "has animations") are intentionally excluded.
local function is_monster(def)
    -- 1. Mobs Redo / MineClone / most mods: explicit type field
    if def.type == "monster" then return true end
    -- 2. Explicit hostile flag used by some frameworks
    if def.hostile == true then return true end
    -- 3. Mobs Redo pattern: requires BOTH damage > 0 AND an attack_type
    if type(def.damage) == "number" and def.damage > 0
        and def.attack_type and def.attack_type ~= "" then
        return true
    end
    -- 4. Creatura / custom mobs: utility_stack contains attack/fight/melee AND has HP
    if def.utility_stack and type(def.utility_stack) == "table" then
        local hp = get_entity_hp(def)
        if hp and hp >= 100 then
            for _, entry in ipairs(def.utility_stack) do
                if type(entry) == "table" and entry[1] then
                    local u = tostring(entry[1]):lower()
                    if u:find("attack") or u:find("fight") or u:find("melee") then
                        return true
                    end
                end
            end
        end
    end
    -- 5. Last-resort fallback: entity deals damage to players (catches mobs that
    --    register damage but omit attack_type or hostile fields).
    if type(def.damage) == "number" and def.damage > 0 then return true end
    return false
end

minetest.register_on_mods_loaded(function()
    local candidates = {}
    local total, n_bl, n_nohp, n_lowhp, n_nh = 0, 0, 0, 0, 0

    for name, def in pairs(minetest.registered_entities) do
        total = total + 1
        local d = setmetatable({ _entity_name = name }, { __index = def })

        if boss_blacklist[name] or name:find("^sns:") then
            n_bl = n_bl + 1
        else
            local hp = get_entity_hp(def)
            if not hp then
                n_nohp = n_nohp + 1
            elseif hp < 80 then
                n_lowhp = n_lowhp + 1
            elseif not is_monster(d) then
                n_nh = n_nh + 1
                minetest.log("info", "[sns] Skipped " .. name .. " (HP=" .. hp .. ") — not a monster")
            else
                table.insert(candidates, { name = name, hp = hp })
            end
        end
    end

    minetest.log("action", ("[sns] Entity scan: %d total, %d blacklisted, " ..
        "%d no-HP, %d low-HP, %d not-hostile, %d candidates"):format(
        total, n_bl, n_nohp, n_lowhp, n_nh, #candidates))

    table.sort(candidates, function(a, b) return a.hp > b.hp end)

    for _, c in ipairs(candidates) do
        local count
        if c.hp >= 1000 then
            count = 1
        elseif c.hp >= 500 then
            count = 2
        elseif c.hp >= 200 then
            count = 3
        else
            count = 4
        end
        table.insert(boss_pool, { entity = c.name, count = count, hp = c.hp })
    end

    -- Second pass: if nothing passed the strict filter, accept any entity
    -- that can deal damage (damage > 0) — last resort so the quest isn't broken.
    if #boss_pool == 0 then
        minetest.log("warning", "[sns] Strict filter returned 0 candidates —"
            .. " falling back to damage > 0 check")
        local fb_candidates = {}
        for name, def in pairs(minetest.registered_entities) do
            if not (boss_blacklist[name] or name:find("^sns:")) then
                local hp = get_entity_hp(def)
                if hp and hp >= 80
                    and type(def.damage) == "number" and def.damage > 0 then
                    table.insert(fb_candidates, { name = name, hp = hp })
                end
            end
        end
        table.sort(fb_candidates, function(a, b) return a.hp > b.hp end)
        for _, c in ipairs(fb_candidates) do
            local count = (c.hp >= 1000) and 1 or (c.hp >= 500) and 2
                or (c.hp >= 200) and 3 or 4
            table.insert(boss_pool, { entity = c.name, count = count, hp = c.hp })
        end
    end

    if #boss_pool > 0 then
        minetest.log("action", "[sns] Boss pool (" .. #boss_pool .. " entries):")
        for i, b in ipairs(boss_pool) do
            minetest.log("action", ("  #%d: %s (HP=%d, count=%d)"):format(i, b.entity, b.hp, b.count))
        end
    else
        minetest.log("warning", "[sns] No suitable boss entities found!")
    end
end)

-- Pick boss for a given fight cycle, escalating from strongest to weaker.
-- cycle 1 → strongest (pool[1]), cycle 2 → second strongest (pool[2]), etc.
-- Clamps to the pool size so it never goes out of bounds.
local function pick_boss(cycle)
    if #boss_pool == 0 then return nil end
    return boss_pool[math.min(cycle, #boss_pool)]
end

local colour = minetest.settings:get("sns.armour_colour")

-- ============================================================
-- Quest rewards table
-- ============================================================
local quest_rewards = {
    {
        item     = "sns:epic_chestplate",
        name     = "Chestplate of Shinobi",
        image    = "sns_chestplate_inv_" .. (colour or "cyan") .. ".png",
        desc     = {
            "Forged in the dying breath of a fallen warlord,",
            "this chestplate pulses with an ancient fury.",
            "Those who wear it feel the rage of a thousand",
            "silent warriors flowing through their strikes.",
            "",
            "§ Your hits shall carry the wrath of the fallen.",
        },
        hud_text = "A fragment of forgotten power binds itself to your soul...\n"
            .. "The armour whispers of battles yet to come.\n"
            .. "You feel your strikes grow heavier — deadlier.",
    },
    {
        item     = "sns:epic_headwear",
        name     = "Headwear of Shinobi",
        image    = "sns_headwear_inv_" .. (colour or "cyan") .. ".png",
        desc     = {
            "Woven from the threads of twilight itself,",
            "this mask once veiled the face of a phantom",
            "who walked between worlds unseen,",
            "defying the very walls that trapped mortal men.",
            "",
            "§ Walls bend to your will. Darkness reveals its secrets.",
            "§ Face a wall and press [Sneak]+[Right Click] to go through it.",
        },
        hud_text = "The veil of the unseen falls upon you...\n"
            .. "Your feet find grip where none should exist.\n"
            .. "The night opens its eyes — and you see through them.",
    },
    {
        item     = "sns:epic_hakama",
        name     = "Hakama of Shinobi",
        image    = "sns_hakama_inv_" .. (colour or "cyan") .. ".png",
        desc     = {
            "Cut from the silk of a river spirit's robe,",
            "these hakama remember the dance of currents.",
            "Water is no longer an obstacle — it becomes",
            "a path, solid beneath feet swift as the wind.",
            "",
            "§ Sprint across water. Move with the speed of shadow.",
        },
        hud_text = "The river spirit's gift wraps around your legs...\n"
            .. "Water hardens beneath your stride. The wind yields.\n"
            .. "You are no longer bound by the earth alone.\n\n"
            .. "The set is complete. You have claimed all that was promised.",
    },
}

-- ============================================================
-- Arena schematic swap
-- ============================================================
local function swap_arena(player_name, schematic_name)
    local pdata = quest_data[player_name]
    if not pdata or not pdata.structure_pos then return end
    minetest.place_schematic(
        pdata.structure_pos,
        modpath .. "/schems/" .. schematic_name,
        "0", nil, true
    )
    minetest.log("action", "[sns] Arena swapped for " .. player_name
        .. " → " .. schematic_name)
end

-- ============================================================
-- Active boss tracking (in-memory only, rebuilt on restart)
--
-- active_bosses[player_name] = {
--   bosses     = { { obj=ObjRef, last_hp=N, killed=bool }, ... },
--   respawning = bool,   -- true while a respawn is scheduled
-- }
-- ============================================================
local active_bosses = {}

-- Per-player HUD warn cooldowns (boolean flag cleared by minetest.after).
local warn_cooldown = {} -- player_name → true while on cooldown

local function can_warn(pname)
    return not warn_cooldown[pname]
end
local function set_warn_cooldown(pname, ticks)
    local seconds = (ticks or 12) * 0.5 -- ticks were 0.5s each
    warn_cooldown[pname] = true
    minetest.after(seconds, function()
        warn_cooldown[pname] = nil
    end)
end

-- ============================================================
-- Spawn boss entities for player_name.
-- Assumes pdata.boss_entity / boss_count are already set.
-- Appends new entries to active_bosses[player_name].bosses.
-- ============================================================
local function do_spawn_boss(player_name)
    local pdata = quest_data[player_name]
    if not pdata or not pdata.structure_pos or pdata.stage ~= "fighting_boss" then return end

    local sp = pdata.structure_pos
    load_arena(sp)

    -- Use dynamic floor scan so bosses land on the actual walkable floor,
    -- not a hardcoded Y estimate that may be inside a wall or on the roof.
    local center = find_spawn_pos(sp)
    local entity = pdata.boss_entity
    local count  = pdata.boss_count or 1
    local player = minetest.get_player_by_name(player_name)

    minetest.log("action", ("[sns] Spawn floor Y=%d for %s"):format(
        center.y, player_name))

    local spawned = {}
    for i = 1, count do
        local bpos = { x = center.x + (i - 1) * 3, y = center.y, z = center.z }
        local node_at = minetest.get_node(bpos).name
        minetest.log("action", ("[sns] Trying add_entity %s at %s (node=%s)"):format(
            entity, minetest.pos_to_string(bpos), node_at))
        local obj = minetest.add_entity(bpos, entity)
        if obj then
            table.insert(spawned, { obj = obj, last_hp = obj:get_hp() or 100, last_pos = bpos, killed = false })
            minetest.log("action",
                ("[sns] Boss spawned at %s"):format(minetest.pos_to_string(bpos)))
        else
            minetest.log("warning", ("[sns] add_entity returned nil for %s at %s"):format(
                entity, minetest.pos_to_string(bpos)))
        end
    end

    local ab = active_bosses[player_name]
    if not ab then
        active_bosses[player_name] = { bosses = {}, respawning = false }
        ab = active_bosses[player_name]
    end

    if #spawned > 0 then
        for _, b in ipairs(spawned) do
            table.insert(ab.bosses, b)
        end
        ab.respawning        = false
        pdata._spawn_retries = nil
        minetest.log("action", ("[sns] Spawned %dx %s for %s"):format(
            #spawned, entity, player_name))
    else
        -- Entity placement failed — retry with back-off
        local retries = (pdata._spawn_retries or 0) + 1
        pdata._spawn_retries = retries
        if retries <= 4 then
            minetest.log("warning", ("[sns] Spawn attempt %d failed for %s"
                .. " — retry in 6 s"):format(retries, player_name))
            minetest.after(6, do_spawn_boss, player_name)
        else
            minetest.log("error", "[sns] All spawn attempts failed for "
                .. player_name .. " — skipping fight")
            ab.respawning        = false
            pdata._spawn_retries = nil
            -- Advance quest so the player isn't permanently stuck
            local ri             = pdata.reward_index or 1
            pdata.reward_index   = ri + 1
            if quest_rewards[ri + 1] then
                pdata.stage = "chest_spawned"
                swap_arena(player_name, "sns_arena_chest.mts")
            else
                pdata.stage = "quest_complete"
            end
            save_progress()
        end
    end
end

-- Pick a boss from the pool, initialise tracking state, enter fighting_boss stage.
local function start_boss_fight(player_name)
    local pdata = quest_data[player_name]
    if not pdata then return end

    local ri        = pdata.reward_index or 1
    local boss_info = pick_boss(ri)
    if not boss_info then
        minetest.log("warning", "[sns] Boss pool empty — no fight for " .. player_name)
        minetest.chat_send_player(player_name,
            "The trial is waived.")
        -- Advance quest so the player isn't permanently stuck
        pdata.reward_index = ri + 1
        if quest_rewards[pdata.reward_index] then
            pdata.stage = "chest_spawned"
            swap_arena(player_name, "sns_arena_chest.mts")
        else
            pdata.stage = "quest_complete"
        end
        save_progress()
        return
    end

    minetest.chat_send_player(player_name,
        "The trial begins — face your challenger.")
    minetest.log("action", "[sns] Chosen boss for " .. player_name
        .. ": " .. boss_info.entity .. " (HP=" .. boss_info.hp .. ") x" .. boss_info.count)

    pdata.boss_entity = boss_info.entity
    pdata.boss_count  = boss_info.count
    pdata.boss_kills  = 0 -- persistent kill counter
    pdata.stage       = "fighting_boss"
    save_progress()

    -- Create tracking entry *before* spawning so the globalstep never sees nil
    active_bosses[player_name] = { bosses = {}, respawning = false }

    minetest.log("action", "[sns] Starting boss fight for " .. player_name
        .. ": " .. boss_info.entity .. " x" .. boss_info.count)
    do_spawn_boss(player_name)
end

-- ============================================================
-- Advance quest after all bosses are defeated
-- ============================================================
local function on_all_bosses_defeated(player_name)
    local pdata = quest_data[player_name]
    if not pdata then return end

    active_bosses[player_name] = nil

    local ri = pdata.reward_index or 1
    pdata.reward_index = ri + 1
    local player = minetest.get_player_by_name(player_name)

    if quest_rewards[ri + 1] then
        pdata.stage = "chest_spawned"
        swap_arena(player_name, "sns_arena_chest.mts")
        if player then
            show_hud(player,
                "The beast falls silent. Its essence scatters into the void.\n"
                .. "You have endured the trial... but the shadows stir once more.\n"
                .. "A new offering emerges from the ancient chest.",
                0x4FC3F7, 7)
        end
    else
        pdata.stage = "quest_complete"
        swap_arena(player_name, "sns_arena_chest.mts")
        if player then
            show_hud(player,
                "Silence falls. The last echo of battle fades into eternity.\n"
                .. "You have walked the path that few dare tread.\n"
                .. "The spirits of the ancient sns acknowledge you.\n\n"
                .. "You are now... Shinobi no Satori.",
                0x4FC3F7, 12)
        end
    end
    save_progress()
end

-- ============================================================
-- Quest chest node
-- ============================================================
minetest.register_node("sns:quest_chest", {
    description               = "Ancient Chest",
    not_in_creative_inventory = 1,
    drawtype                  = "nodebox",
    stack_max                 = 1,
    node_box                  = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 } },
    tiles                     = {
        "sns_quest_chest_top.png",
        "sns_quest_chest_side.png", "sns_quest_chest_side.png",
        "sns_quest_chest_side.png", "sns_quest_chest_side.png",
        "sns_quest_chest_front.png",
    },
    paramtype2                = "facedir",
    groups                    = { choppy = 2, oddly_breakable_by_hand = 1, chest = 1, not_in_creative_inventory = 1 },

    on_rightclick             = function(pos, node, clicker, itemstack, pointed_thing)
        local pname = clicker:get_player_name()
        local pdata = quest_data[pname]
        if not pdata or pdata.stage ~= "chest_spawned" then return end

        local ri     = pdata.reward_index or 1
        local reward = quest_rewards[ri]
        if not reward then return end

        minetest.log("action", "[sns] " .. pname
            .. " opened quest chest (reward #" .. ri .. ": " .. reward.name .. ")")

        -- Build formspec
        local fs = "formspec_version[4]size[10,7]"
            .. "bgcolor[#00000000;false]"
            .. "box[0,0;10,7;#1a1a2eEE]"
            .. "box[0,0;10,0.06;#4FC3F7FF]box[0,6.94;10,0.06;#4FC3F7FF]"
            .. "box[0,0;0.06,7;#4FC3F7FF]box[9.94,0;0.06,7;#4FC3F7FF]"
            .. "image[0.5,0.8;4,4;" .. reward.image .. "]"
            .. "style_type[label;font_size=*1.3;textcolor=#81D4FA]"
            .. "label[4.5,0.6;-- " .. reward.name .. " --]"
            .. "style_type[label;font_size=*1;textcolor=#CFD8DC]"
            .. "box[4.5,1.1;5,0.03;#4FC3F788]"
        for i, line in ipairs(reward.desc) do
            fs = fs .. "label[4.5," .. (0.9 + i * 0.55) .. ";" .. line .. "]"
        end
        fs = fs .. "style[close_btn;bgcolor=#4FC3F7;textcolor=#1a1a2e;border=false]"
            .. "button[7.5,6.2;2,0.5;close_btn;Close]"
        minetest.show_formspec(pname, "sns:chest_reward", fs)

        -- Give item immediately
        local inv = clicker:get_inventory()
        local stack = ItemStack(reward.item)
        if inv:room_for_item("main", stack) then
            inv:add_item("main", stack)
            minetest.log("action", "[sns] " .. pname .. " received: " .. stack:to_string())
        else
            minetest.item_drop(stack, nil, clicker:get_pos())
            minetest.chat_send_player(pname, "Inventory full! Item dropped at your feet: " .. stack:to_string())
        end
        minetest.log("action", "[sns] Gave reward: " .. stack:to_string() .. " to " .. pname)

        -- Remove chest
        minetest.set_node(pos, { name = "air" })

        -- Store pending info for formspec close handler
        pdata._pending_hud    = reward.hud_text or "An ancient power stirs within you..."
        pdata._is_last_reward = (quest_rewards[ri + 1] == nil)
        pdata.stage           = "received_reward"
        save_progress()
    end,
})

-- ============================================================
-- Formspec close → start boss fight (or end quest if last reward)
-- ============================================================
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "sns:chest_reward" then return false end
    if not fields.close_btn and not fields.quit then return true end

    local pname = player:get_player_name()
    local pdata = quest_data[pname]
    if not pdata or pdata.stage ~= "received_reward" then return true end

    local hud_text        = pdata._pending_hud or ""
    local is_last         = pdata._is_last_reward
    pdata._pending_hud    = nil
    pdata._is_last_reward = nil

    if is_last then
        -- Final reward — no boss fight follows
        pdata.stage = "quest_complete"
        save_progress()
        show_hud(player,
            hud_text .. "\n\n"
            .. "Silence falls. The last echo of the trial fades into eternity.\n"
            .. "The spirits of the ancient sns acknowledge you.\n\n"
            .. "You are now... Shinobi no Satori.",
            0x4FC3F7, 12)
    else
        -- Show pre-boss dramatic text, then swap arena and spawn boss
        local hid = player:hud_add({
            type      = "text",
            position  = { x = 0.5, y = 0.5 },
            text      = hud_text .. "\n\n...but such power does not come without a trial.",
            number    = 0xB3E5FC,
            scale     = { x = 100, y = 20 },
            alignment = { x = 0, y = 0 },
            size      = { x = 1, y = 1 },
        })
        -- 2 s dramatic pause → swap arena → 5 s for chunk load → spawn boss
        minetest.after(2, function(pn, h)
            local pl = minetest.get_player_by_name(pn)
            if pl then pl:hud_remove(h) end
            local pd = quest_data[pn]
            if not pd then return end
            swap_arena(pn, "sns_arena_boss.mts")
            minetest.after(5, start_boss_fight, pn)
        end, pname, hid)
    end
    return true
end)

-- ============================================================
-- Place arena on first join
-- ============================================================
local function spawn_quest_structure(player)
    local pname = player:get_player_name()
    local ppos  = player:get_pos()
    if not ppos then return end

    local sp = { x = ppos.x, y = ppos.y + 100, z = ppos.z }
    quest_data[pname].structure_pos = sp
    save_progress()

    load_arena(sp)
    minetest.place_schematic(sp, modpath .. "/schems/sns_arena_chest.mts", "0", nil, true)
    minetest.log("action", "[sns] Placed arena for " .. pname
        .. " at " .. minetest.pos_to_string(sp))
end

minetest.register_on_joinplayer(function(player)
    local pname = player:get_player_name()
    if not quest_data[pname] then
        local hid = player:hud_add({
            type      = "text",
            position  = { x = 0.5, y = 0.5 },
            text      = "O " .. pname .. "...\n"
                .. "The heavens tremble. An ancient trial descends from above.\n"
                .. "Look to the sky — a shadow-forged arena awaits the worthy.\n"
                .. "Your path to becoming Shinobi no Satori begins now.",
            number    = 0xE1F5FE,
            scale     = { x = 100, y = 20 },
            alignment = { x = 0, y = 0 },
            size      = { x = 1, y = 1 },
        })
        minetest.after(8, function(pn, h)
            local pl = minetest.get_player_by_name(pn)
            if not pl then return end
            pl:hud_remove(h)
            quest_data[pn] = { stage = "started", reward_index = 1 }
            save_progress()
            spawn_quest_structure(pl)
        end, pname, hid)
    elseif quest_data[pname].stage == "received_reward" then
        -- Server restarted while formspec was open: treat as closed,
        -- start boss fight directly (item was already given).
        local pdata           = quest_data[pname]
        pdata._pending_hud    = nil
        pdata._is_last_reward = nil
        if pdata._is_last_reward then
            pdata.stage = "quest_complete"
            save_progress()
        else
            -- Resume: swap arena and spawn boss
            swap_arena(pname, "sns_arena_boss.mts")
            minetest.after(5, start_boss_fight, pname)
        end
    end
end)

-- ============================================================
-- Main quest loop  (runs every STEP_INTERVAL seconds via minetest.after)
-- ============================================================
local STEP_INTERVAL = 0.5

local function quest_tick()
    for _, player in ipairs(minetest.get_connected_players()) do
        local pname = player:get_player_name()
        local pdata = quest_data[pname]
        if not pdata then
            -- nothing to do for this player
            -- --------------------------------------------------------
            -- Stage: waiting for player to arrive at arena
            -- --------------------------------------------------------
        elseif pdata.stage == "started" and pdata.structure_pos then
            local pp = player:get_pos()
            local sp = pdata.structure_pos
            if pp.y >= sp.y - 5 and pp.y <= sp.y + ARENA_H + 10
                and math.abs(pp.x - (sp.x + math.floor(ARENA_W / 2))) < ARENA_W
                and math.abs(pp.z - (sp.z + math.floor(ARENA_D / 2))) < ARENA_D then
                pdata.stage = "chest_spawned"
                save_progress()
                minetest.log("action", "[sns] " .. pname .. " reached the arena.")
            end

            -- --------------------------------------------------------
            -- Stage: active boss fight
            -- --------------------------------------------------------
        elseif pdata.stage == "fighting_boss" then
            local sp = pdata.structure_pos
            if not sp then
                -- no arena position recorded; nothing to do
            else
                -- Keep arena loaded
                load_arena(sp)

                local ab = active_bosses[pname]

                -- ---- Server-restart recovery: no in-memory tracking ----
                if not ab then
                    -- Were all bosses already killed before the restart?
                    if (pdata.boss_kills or 0) >= (pdata.boss_count or 1) then
                        on_all_bosses_defeated(pname)
                    else
                        local center   = arena_center(sp)
                        local expected = pdata.boss_entity
                        local found    = {}
                        if expected then
                            for _, obj in ipairs(minetest.get_objects_inside_radius(center, 80)) do
                                local ent = obj:get_luaentity()
                                if ent and ent.name == expected then
                                    local hp = obj:get_hp() or 0
                                    if hp > 0 then
                                        table.insert(found, { obj = obj, last_hp = hp, killed = false })
                                    end
                                end
                            end
                        end
                        if #found > 0 then
                            active_bosses[pname] = { bosses = found, respawning = false }
                            minetest.log("action", "[sns] Reclaimed " .. #found
                                .. " boss(es) for " .. pname .. " after restart")
                        else
                            active_bosses[pname] = { bosses = {}, respawning = true }
                            minetest.log("warning", "[sns] No bosses found after restart for "
                                .. pname .. " — respawning")
                            minetest.after(2, do_spawn_boss, pname)
                        end
                        ab = active_bosses[pname]
                    end
                end

                -- ---- Process boss list (ab may be freshly set above) ----
                if ab then
                    -- Classify each boss as: alive | just-killed | despawned.
                    local alive       = {}
                    local n_killed    = 0
                    local n_despawned = 0

                    for _, b in ipairs(ab.bosses) do
                        if not b.killed then
                            local pos = b.obj:get_pos()
                            if pos then
                                local hp = b.obj:get_hp() or 0
                                if hp <= 0 then
                                    b.killed = true
                                    n_killed = n_killed + 1
                                    pcall(function() b.obj:remove() end)
                                else
                                    b.last_hp  = hp
                                    b.last_pos = pos
                                    table.insert(alive, b)
                                end
                            else
                                local lp = b.last_pos
                                if (b.last_hp or 1) <= 0
                                    or (lp and in_arena(lp, sp)) then
                                    b.killed = true
                                    n_killed = n_killed + 1
                                else
                                    n_despawned = n_despawned + 1
                                end
                            end
                        end
                    end

                    ab.bosses = alive

                    if n_killed > 0 then
                        pdata.boss_kills = (pdata.boss_kills or 0) + n_killed
                        save_progress()
                    end

                    -- ---- Victory check ----
                    local kills_needed = pdata.boss_count or 1
                    if (pdata.boss_kills or 0) >= kills_needed and not ab.respawning then
                        on_all_bosses_defeated(pname)
                    else
                        -- ---- Despawn: schedule respawn ----
                        if n_despawned > 0 and not ab.respawning then
                            ab.respawning = true
                            if can_warn(pname) then
                                set_warn_cooldown(pname)
                                show_hud(player,
                                    "The beast dissolves into shadow...\n"
                                    .. "But the darkness is not so easily escaped.\n"
                                    .. "It gathers again within the arena.",
                                    0x29B6F6, 5)
                            end
                            minetest.after(4, function(pn)
                                local pd = quest_data[pn]
                                if pd and pd.stage == "fighting_boss" then
                                    do_spawn_boss(pn)
                                end
                            end, pname)
                        end

                        -- ---- Boundary enforcement ----
                        local pp          = player:get_pos()
                        local player_dead = (player:get_hp() <= 0)
                        local out_reason  = nil

                        if not player_dead and pp and not in_arena(pp, sp) then
                            out_reason = "player"
                        else
                            for _, b in ipairs(alive) do
                                local bpos = b.obj:get_pos()
                                if bpos and not in_arena(bpos, sp) then
                                    out_reason = "boss"
                                    break
                                end
                            end
                        end

                        if out_reason then
                            local c = arena_center(sp)
                            if out_reason == "player" then
                                player:set_pos({ x = c.x + 2, y = c.y, z = c.z + 2 })
                            end
                            for i, b in ipairs(alive) do
                                if b.obj:get_pos() then
                                    b.obj:set_pos({ x = c.x - (i - 1) * 3, y = c.y, z = c.z })
                                end
                            end
                            if can_warn(pname) then
                                set_warn_cooldown(pname)
                                local msg = out_reason == "player"
                                    and "The arena holds you. There is no escape from the trial."
                                    or "The beast is drawn back by an unseen force."
                                show_hud(player, msg, 0x4FC3F7, 4)
                            end
                        end
                    end -- victory/despawn/boundary block
                end     -- ab guard
            end         -- sp guard
        end             -- stage elseif
    end                 -- player loop
    minetest.after(STEP_INTERVAL, quest_tick)
end
minetest.after(STEP_INTERVAL, quest_tick)

-- ============================================================
-- Chat commands
-- ============================================================
minetest.register_chatcommand("shintp", {
    description = "Teleport to quest chest or arena.",
    privs       = { server = true },
    func        = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end
        local pdata = quest_data[name]
        if pdata and pdata.structure_pos then
            local sp    = pdata.structure_pos
            local found = minetest.find_node_near(sp, 120, { "sns:quest_chest" })
            if found then
                player:set_pos({ x = found.x, y = found.y + 1, z = found.z })
                return true, "Teleported to quest chest at " .. minetest.pos_to_string(found)
            end
            player:set_pos(sp)
            return true, "No chest found. Teleported to arena at " .. minetest.pos_to_string(sp)
        end
        return false, "No quest data found."
    end,
})

minetest.register_chatcommand("rquest", {
    description = "Reset Shinobi no Satori quest progress.",
    params      = "[player_name]",
    privs       = { server = true },
    func        = function(name, param)
        local target = (param ~= "" and param) or name
        active_bosses[target] = nil
        if quest_data[target] then
            quest_data[target] = nil
            save_progress()
            minetest.chat_send_player(name, "Quest progress for " .. target .. " has been reset.")
        else
            minetest.chat_send_player(name, "No quest progress found for " .. target .. ".")
        end
        return true
    end,
})

-- /shindebug — dump current quest state and boss pool to chat (server priv)
minetest.register_chatcommand("shindebug", {
    description = "Print Shinobi quest debug info.",
    privs       = { server = true },
    func        = function(name)
        local lines = {}

        -- Boss pool
        if #boss_pool == 0 then
            lines[#lines + 1] = "§ BOSS POOL: EMPTY — no mobs qualify as bosses!"
        else
            lines[#lines + 1] = "§ BOSS POOL (" .. #boss_pool .. " entries):"
            for i, b in ipairs(boss_pool) do
                lines[#lines + 1] = ("  #%d %s  HP=%d  count=%d"):format(i, b.entity, b.hp, b.count)
            end
        end

        -- Quest state for every online player (or just caller if no data)
        local targets = {}
        for pn, _ in pairs(quest_data) do targets[#targets + 1] = pn end
        if #targets == 0 then
            lines[#lines + 1] = "§ No quest data on record."
        end
        for _, pn in ipairs(targets) do
            local pd = quest_data[pn]
            lines[#lines + 1] = ("§ [%s] stage=%s  reward_idx=%d"):format(
                pn, tostring(pd.stage), pd.reward_index or 1)
            if pd.structure_pos then
                local sp = pd.structure_pos
                lines[#lines + 1] = ("    structure_pos=%s"):format(minetest.pos_to_string(sp))
                local c = arena_center(sp)
                lines[#lines + 1] = ("    arena_center=%s"):format(minetest.pos_to_string(c))
                -- Show what node is at spawn pos
                local spos = find_spawn_pos(sp)
                lines[#lines + 1] = ("    find_spawn_pos=%s  node_there=%s"):format(
                    minetest.pos_to_string(spos),
                    minetest.get_node(spos).name)
                local node_below = minetest.get_node({ x = spos.x, y = spos.y - 1, z = spos.z }).name
                lines[#lines + 1] = ("    node_below_spawn=%s"):format(node_below)
            else
                lines[#lines + 1] = "    structure_pos=nil"
            end
            if pd.stage == "fighting_boss" then
                lines[#lines + 1] = ("    boss_entity=%s  boss_count=%d  boss_kills=%d"):format(
                    tostring(pd.boss_entity), pd.boss_count or 0, pd.boss_kills or 0)
                local ab = active_bosses[pn]
                if ab then
                    lines[#lines + 1] = ("    active_bosses: %d alive, respawning=%s"):format(
                        #ab.bosses, tostring(ab.respawning))
                    for i, b in ipairs(ab.bosses) do
                        local bpos = b.obj and b.obj:get_pos()
                        lines[#lines + 1] = ("      boss#%d pos=%s last_hp=%d killed=%s"):format(
                            i,
                            bpos and minetest.pos_to_string(bpos) or "nil(removed)",
                            b.last_hp or 0, tostring(b.killed))
                    end
                else
                    lines[#lines + 1] = "    active_bosses: nil (in-memory tracking lost)"
                end
            end
        end

        for _, l in ipairs(lines) do
            minetest.chat_send_player(name, l)
        end
        return true
    end,
})

-- /shinspawn — force-spawn boss for yourself right now (server priv)
minetest.register_chatcommand("shinspawn", {
    description = "Force (re)spawn boss for current player.",
    privs       = { server = true },
    func        = function(name)
        local pdata = quest_data[name]
        if not pdata then
            return false, "No quest data."
        end
        if pdata.stage ~= "fighting_boss" then
            return false, "Not in fighting_boss stage (stage=" .. tostring(pdata.stage) .. ")."
        end
        if not pdata.structure_pos then
            return false, "No structure_pos stored."
        end
        -- Clear old tracking so do_spawn_boss rebuilds it
        active_bosses[name] = { bosses = {}, respawning = false }
        pdata._spawn_retries = nil
        minetest.chat_send_player(name, "[sns] Force-spawning boss now...")
        do_spawn_boss(name)
        return true, "Spawn triggered."
    end,
})
