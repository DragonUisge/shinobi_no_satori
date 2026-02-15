-- Shinobi no Satori Quest Logic

local modpath = minetest.get_modpath("shinobi_no_satori")
local worldpath = minetest.get_worldpath()

local quest_progress_file = worldpath .. "/shinobi_quest_progress.json"
local quest_data = {}

local BOSS_HP = tonumber(minetest.settings:get("shinobi_boss_hp")) or 1000

-- Helper function to save quest progress
local function save_progress()
    local file = io.open(quest_progress_file, "w")
    if file then
        local json = minetest.write_json(quest_data)
        if not json or json == "null" then json = "{}" end
        file:write(json)
        file:close()
    else
        minetest.log("error", "[shinobi_no_satori] Could not save quest progress.")
    end
end

-- Helper function to load quest progress
local function load_progress()
    local file = io.open(quest_progress_file, "r")
    if file then
        local data = file:read("*a")
        file:close()
        if not data or data == "" or data == "null" then
            quest_data = {}
            return
        end
        local success, parsed_data = pcall(minetest.parse_json, data)
        if success and type(parsed_data) == "table" then
            quest_data = parsed_data
        else
            minetest.log("error", "[shinobi_no_satori] Could not parse quest progress file. Creating a new one.")
            quest_data = {}
            save_progress()
        end
    else
        -- File doesn't exist, create it
        quest_data = {}
        save_progress()
    end
end

-- Load progress when the mod is loaded
load_progress()

-- Track boss objects in memory (not saved to file)
local active_bosses = {} -- player_name -> boss ObjectRef

-- Quest rewards table — each entry is one reward cycle (chest → boss → next chest)
local quest_rewards = {
    {
        item = "shinobi_no_satori:epic_chestplate",
        name = "Chestplate of Shinobi",
        image = "shinobi_chestplate_inv.png",
        desc = {
            "Forged in the dying breath of a fallen warlord,",
            "this chestplate pulses with an ancient fury.",
            "Those who wear it feel the rage of a thousand",
            "silent warriors flowing through their strikes.",
            "",
            "§ Your hits shall carry the wrath of the fallen.",
        },
        hud_text = "A fragment of forgotten power binds itself to your soul...\n" ..
            "The armour whispers of battles yet to come.\n" ..
            "You feel your strikes grow heavier — deadlier.",
    },
    {
        item = "shinobi_no_satori:epic_headwear",
        name = "Headwear of Shinobi",
        image = "shinobi_headwear_inv.png",
        desc = {
            "Woven from the threads of twilight itself,",
            "this mask once veiled the face of a phantom",
            "who walked between worlds unseen,",
            "defying the very walls that trapped mortal men.",
            "",
            "§ Walls bend to your will. Darkness reveals its secrets.",
            "§ Face a wall and press [Sneak]+[Right Click] to run up it.",
            "§ Press [Jump] to backflip off, or reach the top.",
        },
        hud_text = "The veil of the unseen falls upon you...\n" ..
            "Your feet find grip where none should exist.\n" ..
            "The night opens its eyes — and you see through them.",
    },
    {
        item = "shinobi_no_satori:epic_hakama",
        name = "Hakama of Shinobi",
        image = "shinobi_hakama_inv.png",
        desc = {
            "Cut from the silk of a river spirit's robe,",
            "these hakama remember the dance of currents.",
            "Water is no longer an obstacle — it becomes",
            "a path, solid beneath feet swift as the wind.",
            "",
            "§ Sprint across water. Move with the speed of shadow.",
        },
        hud_text = "The river spirit's gift wraps around your legs...\n" ..
            "Water hardens beneath your stride. The wind yields.\n" ..
            "You are no longer bound by the earth alone.\n\n" ..
            "The set is complete. You have claimed all that was promised.",
    },
}

-- Helper: spawn (or respawn) the boss for a player
local function spawn_boss(player_name)
    local pdata = quest_data[player_name]
    if not pdata or not pdata.structure_pos then return end
    local sp = pdata.structure_pos
    local dragon_pos = {x = sp.x + 57, y = sp.y + 5, z = sp.z + 57}
    local dragon_obj = minetest.add_entity(dragon_pos, "waterdragon:pure_water_dragon")
    if dragon_obj then
        active_bosses[player_name] = dragon_obj
        local dragon_entity = dragon_obj:get_luaentity()
        local player = minetest.get_player_by_name(player_name)
        if dragon_entity and player then
            dragon_entity._target = player
            dragon_entity.hp = BOSS_HP
        end
    end
    pdata.stage = "fighting_boss"
    save_progress()
    minetest.log("action", "[shinobi_no_satori] Spawned boss for " .. player_name)
end

-- Function to swap the arena schematic (e.g. from chest version to boss version)
local function swap_arena(player_name, schematic_name)
    local pdata = quest_data[player_name]
    if not pdata or not pdata.structure_pos then return end
    local schematic_path = modpath .. "/schems/" .. schematic_name
    minetest.place_schematic(pdata.structure_pos, schematic_path, "0", nil, true)
    minetest.log("action", "[shinobi_no_satori] Swapped arena for " .. player_name .. " to " .. schematic_name)
end

-- Register the special quest chest
minetest.register_node("shinobi_no_satori:quest_chest", {
    description = "Ancient Chest",
    drawtype = "nodebox",
    not_in_creative_inventory = true,
    stack_max = 1,
    node_box = {
        type = "fixed",
        fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
    },
    tiles = {
        "shinobi_quest_chest_top.png", "shinobi_quest_chest_side.png", "shinobi_quest_chest_side.png",
        "shinobi_quest_chest_side.png", "shinobi_quest_chest_side.png", "shinobi_quest_chest_front.png"
    },
    paramtype2 = "facedir",
    groups = { choppy = 2, oddly_breakable_by_hand = 1, chest = 1 },
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local player_name = clicker:get_player_name()
        local pdata = quest_data[player_name]

        if not pdata or pdata.stage ~= "chest_spawned" then
            return
        end

        -- Determine which reward to give based on reward_index
        local ri = pdata.reward_index or 1
        local reward = quest_rewards[ri]
        if not reward then
            return
        end

        minetest.log("action", "[shinobi_no_satori] Player " .. player_name ..
            " opened quest chest (reward #" .. ri .. ": " .. reward.name .. ")")

        -- Show a formspec panel with the current reward
        local formspec = "formspec_version[4]" ..
            "size[10,7]" ..
            "bgcolor[#00000000;false]" ..
            "box[0,0;10,7;#1a1a2eEE]" ..
            "box[0,0;10,0.06;#4FC3F7FF]" ..
            "box[0,6.94;10,0.06;#4FC3F7FF]" ..
            "box[0,0;0.06,7;#4FC3F7FF]" ..
            "box[9.94,0;0.06,7;#4FC3F7FF]" ..
            "image[0.5,0.8;4,4;" .. reward.image .. "]" ..
            "style_type[label;font_size=*1.3;textcolor=#81D4FA]" ..
            "label[4.5,0.6;-- " .. reward.name .. " --]" ..
            "style_type[label;font_size=*1;textcolor=#CFD8DC]" ..
            "box[4.5,1.1;5,0.03;#4FC3F788]"
        for i, line in ipairs(reward.desc) do
            formspec = formspec .. "label[4.5," .. (0.9 + i * 0.55) .. ";" .. line .. "]"
        end
        formspec = formspec ..
            "style[close_btn;bgcolor=#4FC3F7;textcolor=#1a1a2e;border=false]" ..
            "button[7.5,6.2;2,0.5;close_btn;Close]"
        minetest.show_formspec(player_name, "shinobi_no_satori:chest_reward", formspec)

        -- Give the reward item immediately
        local inv = clicker:get_inventory()
        if inv:room_for_item("main", reward.item) then
            inv:add_item("main", reward.item)
        else
            minetest.item_drop(ItemStack(reward.item), nil, clicker:get_pos())
        end

        minetest.set_node(pos, {name = "air"})

        local reward_hud_text = reward.hud_text or
            "An ancient power stirs within you...\nBut the shadows demand a price."

        -- Check if this is the last reward (no boss after it)
        local is_last_reward = (quest_rewards[ri + 1] == nil)

        if is_last_reward then
            pdata.stage = "quest_complete"
            save_progress()
            -- HUD will show after formspec is closed
            pdata._pending_final = true
            pdata._pending_hud_text = reward_hud_text
        else
            pdata.stage = "received_reward"
            save_progress()
            pdata._pending_boss = true
            pdata._pending_hud_text = reward_hud_text
        end
    end,
})

-- Handle formspec close — show HUD message and trigger boss
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "shinobi_no_satori:chest_reward" then return false end
    if not fields.close_btn and not fields.quit then return true end

    local pname = player:get_player_name()
    local pdata = quest_data[pname]
    if not pdata then return true end

    local hud_text = pdata._pending_hud_text
    if not hud_text then return true end

    if pdata._pending_final then
        -- Final reward — show completion HUD
        pdata._pending_final = nil
        pdata._pending_hud_text = nil
        local final_hud = player:hud_add({
            type = "text", position = {x = 0.5, y = 0.5},
            text = hud_text .. "\n\n" ..
                "Silence falls. The last echo of the trial fades into eternity.\n" ..
                "The spirits of the ancient shinobi acknowledge you.\n\n" ..
                "You are now... Shinobi no Satori.",
            number = 0x4FC3F7, scale = {x = 100, y = 20},
            alignment = {x = 0, y = 0}, size = {x = 1, y = 1},
        })
        minetest.after(10, function(pn, hid)
            local pl = minetest.get_player_by_name(pn)
            if pl then pl:hud_remove(hid) end
        end, pname, final_hud)
    elseif pdata._pending_boss then
        -- More rewards ahead — show pre-boss HUD, then spawn boss
        pdata._pending_boss = nil
        pdata._pending_hud_text = nil
        local pre_boss_hud_id = player:hud_add({
            type = "text", position = {x = 0.5, y = 0.5},
            text = hud_text .. "\n\n" ..
                "...but such power does not come without a trial.",
            number = 0xB3E5FC, scale = {x = 100, y = 20},
            alignment = {x = 0, y = 0}, size = {x = 1, y = 1},
        })

        minetest.after(5, function(pn, hid)
            local pl = minetest.get_player_by_name(pn)
            if pl then pl:hud_remove(hid) end

            if minetest.get_modpath("waterdragon") then
                swap_arena(pn, "shinobi_arena_boss.mts")
                spawn_boss(pn)
            end
        end, pname, pre_boss_hud_id)
    end
    return true
end)

-- Function to spawn the quest structure from a schematic (handles large schematics)
local function spawn_quest_structure(player)
    local player_name = player:get_player_name()
    local player_pos = player:get_pos()
    if not player_pos then return end

    local structure_pos = {x = player_pos.x, y = player_pos.y + 100, z = player_pos.z}
    local schematic_path = modpath .. "/schems/shinobi_arena_chest.mts"

    quest_data[player_name].structure_pos = structure_pos
    save_progress()

    minetest.place_schematic(structure_pos, schematic_path, "0", nil, true)
    minetest.log("action", "[shinobi_no_satori] Placed arena schematic at " .. minetest.pos_to_string(structure_pos))
end

minetest.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    if not quest_data[player_name] then
        local hud_id = player:hud_add({
            type = "text", position = { x = 0.5, y = 0.5 },
            text = "O " .. player_name .. "...\nThe heavens tremble. An ancient trial descends from above.\nLook to the sky — a shadow-forged arena awaits the worthy.\nYour path to becoming Shinobi no Satori begins now.",
            number = 0xE1F5FE, scale = { x = 100, y = 20 }, alignment = { x = 0, y = 0 }, size = { x = 1, y = 1 },
        })

        minetest.after(8, function(player_name, hud_id)
            local current_player = minetest.get_player_by_name(player_name)
            if not current_player then return end
            current_player:hud_remove(hud_id)
            quest_data[player_name] = { stage = "started", reward_index = 1 }
            save_progress()
            spawn_quest_structure(current_player)
        end, player_name, hud_id)
    end
end)

minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local player_name = player:get_player_name()
        local player_quest_data = quest_data[player_name]

        -- Detect player arriving at the arena
        if player_quest_data and player_quest_data.stage == "started" and player_quest_data.structure_pos then
            local player_pos = player:get_pos()
            local sp = player_quest_data.structure_pos

            -- Check if player is roughly within the arena bounds
            if player_pos.y >= sp.y and player_pos.y <= sp.y + 60 and
               math.abs(player_pos.x - sp.x) <= 120 and
               math.abs(player_pos.z - sp.z) <= 120 then

                player_quest_data.stage = "chest_spawned"
                save_progress()
                minetest.log("action", "[shinobi_no_satori] Player " .. player_name .. " reached the arena. Chest is ready.")
            end
        elseif player_quest_data and player_quest_data.stage == "fighting_boss" then
            local boss = active_bosses[player_name]
            if not boss then
                -- No boss reference at all (e.g. server restart) — respawn
                if minetest.get_modpath("waterdragon") then
                    spawn_boss(player_name)
                end
            elseif not boss:get_pos() then
                -- Boss despawned (unloaded) — NOT a kill!
                -- Respawn the boss and teleport player closer to prevent it again
                active_bosses[player_name] = nil
                local despawn_hud = player:hud_add({
                    type = "text", position = {x = 0.5, y = 0.5},
                    text = "The beast dissolves into mist...\nBut the darkness is not so easily escaped.\nIt reforms. It hungers. It returns.",
                    number = 0x29B6F6, scale = {x = 100, y = 20}, alignment = {x = 0, y = 0}, size = {x = 1, y = 1},
                })
                minetest.after(4, function(pn, hid)
                    local pl = minetest.get_player_by_name(pn)
                    if pl then pl:hud_remove(hid) end
                end, player_name, despawn_hud)
                local sp = player_quest_data.structure_pos
                if sp then
                    local center = {x = sp.x + 57, y = sp.y + 3, z = sp.z + 57}
                    player:set_pos(center)
                end
                if minetest.get_modpath("waterdragon") then
                    spawn_boss(player_name)
                end
            else
                -- Boss exists, check distance — pull player closer if too far
                local boss_pos = boss:get_pos()
                local player_pos = player:get_pos()
                local dist = vector.distance(player_pos, boss_pos)
                if dist > 80 then
                    -- Player is drifting too far, pull them back
                    local dir = vector.direction(boss_pos, player_pos)
                    local near_pos = vector.add(boss_pos, vector.multiply(dir, 20))
                    near_pos.y = math.max(near_pos.y, boss_pos.y)
                    player:set_pos(near_pos)
                end

                -- Check HP — real kill
                local lua_ent = boss:get_luaentity()
                if lua_ent and lua_ent.hp and lua_ent.hp <= 0 then
                    boss:remove()
                    active_bosses[player_name] = nil

                    -- Advance to next reward
                    local ri = player_quest_data.reward_index or 1
                    player_quest_data.reward_index = ri + 1

                    if quest_rewards[ri + 1] then
                        -- More rewards remain — swap arena back to chest version
                        player_quest_data.stage = "chest_spawned"
                        swap_arena(player_name, "shinobi_arena_chest.mts")
                        local victory_hud = player:hud_add({
                            type = "text", position = {x = 0.5, y = 0.5},
                            text = "The beast falls silent. Its essence scatters into the void.\n" ..
                                "You have endured the trial... but the shadows stir once more.\n" ..
                                "A new offering emerges from the ancient chest.",
                            number = 0x80DEEA, scale = {x = 100, y = 20},
                            alignment = {x = 0, y = 0}, size = {x = 1, y = 1},
                        })
                        minetest.after(6, function(pn, hid)
                            local pl = minetest.get_player_by_name(pn)
                            if pl then pl:hud_remove(hid) end
                        end, player_name, victory_hud)
                    else
                        -- All rewards claimed — quest complete, swap arena one last time
                        player_quest_data.stage = "quest_complete"
                        swap_arena(player_name, "shinobi_arena_chest.mts")
                        local final_hud = player:hud_add({
                            type = "text", position = {x = 0.5, y = 0.5},
                            text = "Silence falls. The last echo of battle fades into eternity.\n" ..
                                "You have walked the path that few dare tread.\n" ..
                                "The spirits of the ancient shinobi acknowledge you.\n\n" ..
                                "You are now... Shinobi no Satori.",
                            number = 0x4FC3F7, scale = {x = 100, y = 20},
                            alignment = {x = 0, y = 0}, size = {x = 1, y = 1},
                        })
                        minetest.after(10, function(pn, hid)
                            local pl = minetest.get_player_by_name(pn)
                            if pl then pl:hud_remove(hid) end
                        end, player_name, final_hud)
                    end
                    save_progress()
                end
            end
        end
    end
end)

minetest.register_chatcommand("shintp", {
    description = "Teleport to the quest chest or falling chest entity.",
    privs = { server = true },
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end

        -- Try to find the chest node near the structure
        local pdata = quest_data[name]
        if pdata and pdata.structure_pos then
            local sp = pdata.structure_pos
            local found = minetest.find_node_near(sp, 120, {"shinobi_no_satori:quest_chest"})
            if found then
                player:set_pos({x=found.x, y=found.y+1, z=found.z})
                return true, "Teleported to quest chest at " .. minetest.pos_to_string(found)
            end
        end

        -- Fallback: teleport to structure_pos
        if pdata and pdata.structure_pos then
            player:set_pos(pdata.structure_pos)
            return true, "No chest found. Teleported to arena at " .. minetest.pos_to_string(pdata.structure_pos)
        end

        return false, "No quest data found. Start the quest first."
    end,
})

minetest.register_chatcommand("rquest", {
    description = "Reset your Shinobi no Satori quest progress.",
    params = "[player_name]",
    privs = { server = true },
    func = function(name, param)
        local target_player = param and param ~= "" and param or name
        if quest_data[target_player] then
            quest_data[target_player] = nil
            save_progress()
            minetest.chat_send_player(name, "Quest progress for " .. target_player .. " has been reset.")
            return true
        else
            minetest.chat_send_player(name, "No quest progress found for " .. target_player .. " to reset.")
            return true
        end
    end,
})