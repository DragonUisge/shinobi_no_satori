-- Shinobi no Satori - Armour Registration
-- Abilities:
--   Chestplate: increased melee damage
--   Headwear:   wall/ceiling walking + night vision
--   Hakama:     water walking (sprint on water) + speed boost
-- Stats: low armour rating, high heal chance, unbreakable

-- ============================================================
-- Tracking tables for abilities
-- ============================================================
local chestplate_users    = {} -- players wearing the chestplate (bonus damage)
local headwear_users      = {} -- players wearing the headwear (wall-run + night vision)
local hakama_users        = {} -- players wearing the hakama (water walk)

-- ============================================================
-- Settings
-- ============================================================
local S                   = minetest.settings

local HIDE_FROM_CREATIVE  = S:get_bool("sns.hide_from_creative", true)
local ARMOUR_HEAL         = tonumber(S:get("sns.armour_heal")) or 18
local DAMAGE_MULTIPLIER     = tonumber(S:get("sns.damage_multiplier")) or 1.8
local NIGHT_VISION_RATIO    = tonumber(S:get("sns.night_vision_ratio")) or 0.6
local SPEED_BOOST           = tonumber(S:get("sns.speed_boost")) or 0.6
local FALL_DAMAGE_REDUCTION = tonumber(S:get("sns.fall_damage_reduction")) or 0.5
local WATER_WALK_INTERVAL = 0.1
local SET_BONUS           = S:get("sns.set_bonus") or "both"
local SCOUT_COOLDOWN      = tonumber(S:get("sns.set_bonus_scout_cooldown")) or 20.0

local creative_group      = HIDE_FROM_CREATIVE and 1 or 0

local colour = minetest.settings:get("sns.armour_colour") or "cyan"

-- ============================================================
-- Chestplate of Shinobi — increased melee damage
-- ============================================================
armor:register_armor("sns:epic_chestplate", {
    description = "Chestplate of Shinobi",
    inventory_image = "sns_chestplate_inv_" .. colour .. ".png",
    texture = "sns_chestplate_equipped_" .. colour .. ".png",
    preview = "sns_chestplate_inv_" .. colour .. ".png",
    groups = {
        armor_torso = 1,
        armor_heal = ARMOUR_HEAL,
        armor_use = 0, -- unbreakable
        not_in_creative_inventory = creative_group,
    },
    armor_groups = { fleshy = 10 },
    on_equip = function(player, index, stack)
        local name = player:get_player_name()
        chestplate_users[name] = true
        check_full_set(player)
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        chestplate_users[name] = nil
        clear_full_set(player)
    end,
})

-- Bonus damage: intercept punches from chestplate wearers
minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    if not hitter or not hitter:is_player() then return end
    local name = hitter:get_player_name()
    if chestplate_users[name] then
        -- Deal extra damage (the original damage still applies, we add on top)
        local bonus = math.floor(damage * (DAMAGE_MULTIPLIER - 1))
        if bonus > 0 then
            player:set_hp(player:get_hp() - bonus, { type = "punch" })
        end
    end
end)

-- Reduce fall damage for chestplate wearers
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if reason and reason.type == "fall" and hp_change < 0 then
        local name = player:get_player_name()
        if chestplate_users[name] then
            return math.ceil(hp_change * (1 - FALL_DAMAGE_REDUCTION))
        end
    end
    return hp_change
end, true)

-- ============================================================
-- Headwear of Shinobi — night vision + something like noclip
-- ============================================================
armor:register_armor("sns:epic_headwear", {
    description = "Headwear of Shinobi",
    inventory_image = "sns_headwear_inv_" .. colour .. ".png",
    texture = "sns_headwear_equipped_" .. colour .. ".png",
    preview = "sns_headwear_inv_" .. colour .. ".png",
    groups = {
        armor_head = 1,
        armor_heal = ARMOUR_HEAL,
        armor_use = 0,
        not_in_creative_inventory = creative_group,
    },
    armor_groups = { fleshy = 8 },
    on_equip = function(player, index, stack)
        local name = player:get_player_name()
        headwear_users[name] = true
        -- Night vision: override day/night ratio to always bright
        player:override_day_night_ratio(NIGHT_VISION_RATIO)
        check_full_set(player)
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        headwear_users[name] = nil
        -- Remove night vision
        player:override_day_night_ratio(nil)
        clear_full_set(player)
    end,
})

-- ============================================================
-- Hakama of Shinobi — water walking + speed boost
-- ============================================================
armor:register_armor("sns:epic_hakama", {
    description = "Hakama of Shinobi",
    inventory_image = "sns_hakama_inv_" .. colour .. ".png",
    texture = "sns_hakama_equipped_" .. colour .. ".png",
    preview = "sns_hakama_inv_" .. colour .. ".png",
    groups = {
        armor_legs = 1,
        armor_heal = ARMOUR_HEAL,
        armor_use = 0,
        physics_speed = SPEED_BOOST,
        not_in_creative_inventory = creative_group,
    },
    armor_groups = { fleshy = 8 },
    on_equip = function(player, index, stack)
        local name = player:get_player_name()
        hakama_users[name] = true
        check_full_set(player)
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        hakama_users[name] = nil
        clear_full_set(player)
    end,
})

-- ============================================================
-- Full-set bonus
-- ============================================================
local full_set_users = {}   -- name → true when all 3 pieces worn
local scout_cooldowns = {}  -- name → last activation timestamp
local scout_active = {}     -- name → true while scout camera is running
local active_scout_decoys = {}  -- name → ObjectRef
local scout_data = {}           -- name → { orig_textures, decoy_pos }
local scout_hp_cache = {}       -- entity_id → hp, for mob damage watchdog

-- Ghost entity for the scout: the decoy body left behind
minetest.register_entity("sns:scout_decoy", {
    initial_properties = {
        visual = "mesh",
        mesh = "3d_armor_character.b3d",
        textures = { "character.png", "blank.png", "blank.png" },
        visual_size = { x = 1, y = 1 },
        -- Physical so it rests on the ground; collisionbox sized for a prone body
        physical = true,
        collisionbox = { -0.35, 0.0, -0.7, 0.35, 0.4, 0.7 },
        collide_with_objects = false,
        pointable = true,   -- must be true to receive on_punch
        static_save = false,
        glow = 0,
        backface_culling = false,
        use_texture_alpha = true,
        makes_footstep_sound = false,
    },
    _owner = nil,
    on_activate = function(self, staticdata, dtime_s)
        -- Lay animation: frames 162-166 in the standard character model
        self.object:set_animation({ x = 162, y = 166 }, 15, 0, true)
        self.object:set_velocity({ x = 0, y = 0, z = 0 })
    end,
    on_step = function(self, dtime)
        if not self._owner then self.object:remove(); return end
        -- Keep still and track position so end_scout can teleport back even if
        -- the entity gets unloaded while the shadow is far away.
        self.object:set_velocity({ x = 0, y = 0, z = 0 })
        local p = self.object:get_pos()
        if p then
            local data = scout_data[self._owner]
            if data then data.decoy_pos = vector.copy(p) end
        end
    end,
    on_deactivate = function(self, removal)
        -- Entity is being unloaded (chunk leaving active range).
        -- Final position is already stored by on_step; nothing extra needed.
    end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
        -- Decoy was hit — burst particles then snap the shadow back.
        local opos = self.object:get_pos()
        if opos then
            minetest.add_particlespawner({
                amount     = 24,
                time       = 0.4,
                minpos     = vector.add(opos, vector.new(-0.4, 0.2, -0.4)),
                maxpos     = vector.add(opos, vector.new( 0.4, 1.6,  0.4)),
                minvel     = vector.new(-2, 1, -2),
                maxvel     = vector.new( 2, 4,  2),
                minexptime = 0.3,
                maxexptime = 0.8,
                minsize    = 1.0,
                maxsize    = 2.5,
                texture    = "sns_shadow_particle.png^[colorize:#000000:200",
                glow       = 4,
            })
        end
        if self._owner then
            local owner_player = minetest.get_player_by_name(self._owner)
            if owner_player and scout_active[self._owner] then
                end_scout(owner_player)
            end
        end
    end,
})

local function has_full_set(name)
    return chestplate_users[name] and headwear_users[name] and hakama_users[name]
end

local function apply_full_set(player)
    local name = player:get_player_name()
    if full_set_users[name] then return end  -- already applied
    full_set_users[name] = true

    if SET_BONUS == "nameonly" then
        player:set_nametag_attributes({ text = "", bgcolor = false })
    elseif SET_BONUS == "invisible" then
        player:set_properties({ visual_size = { x = 0, y = 0 } })
    elseif SET_BONUS == "both" then
        player:set_nametag_attributes({ text = "", bgcolor = false })
        player:set_properties({ visual_size = { x = 0, y = 0 } })
    end
    -- "scout" has no passive effect; it is activated on keypress
end

local function remove_full_set(player)
    local name = player:get_player_name()
    if not full_set_users[name] then return end
    full_set_users[name] = nil

    -- Respect dungeon rank title when restoring nametag
    local title   = sns.player_titles and sns.player_titles[name]
    local display = title and (minetest.colorize("#FFD700", "[" .. title .. "]") .. " " .. name) or name
    player:set_nametag_attributes({ text = display, bgcolor = false })
    player:set_properties({ visual_size = { x = 1, y = 1 } })

    -- End any active scout session
    if scout_active[name] then
        end_scout(player)
    end
end

-- Called from each armor on_equip / on_unequip
local function check_full_set(player)
    local name = player:get_player_name()
    if has_full_set(name) then
        apply_full_set(player)
    else
        remove_full_set(player)
    end
end

local function clear_full_set(player)
    remove_full_set(player)
end

-- ---- Scout camera ----
local function end_scout(player)
    local name = player:get_player_name()
    scout_active[name] = nil

    -- Grab last known decoy position before destroying it
    local return_pos
    local data = scout_data[name]
    if data then return_pos = data.decoy_pos end
    if not return_pos then
        -- Fallback: try the live entity
        if active_scout_decoys[name] and active_scout_decoys[name]:get_pos() then
            return_pos = active_scout_decoys[name]:get_pos()
        end
    end

    -- Destroy decoy
    if active_scout_decoys[name] and active_scout_decoys[name]:get_pos() then
        active_scout_decoys[name]:remove()
    end
    active_scout_decoys[name] = nil

    -- Teleport shadow back to where the decoy was lying
    if return_pos then
        player:set_pos(return_pos)
    end

    -- Restore player appearance and armor groups
    if data and data.orig_textures then
        player:set_properties({ textures = data.orig_textures })
    end
    if data and data.orig_armor_groups then
        player:set_armor_groups(data.orig_armor_groups)
    end
    if armor and armor.update_player_visuals then
        armor:update_player_visuals(player)
    end
    scout_data[name] = nil
    player:hud_set_flags({ wield = true })
end

local function begin_scout(player)
    local name = player:get_player_name()
    if scout_active[name] then return end

    local now = minetest.get_us_time() / 1e6
    if scout_cooldowns[name] and (now - scout_cooldowns[name]) < SCOUT_COOLDOWN then
        return
    end
    scout_cooldowns[name] = now
    scout_active[name] = true

    local pos = player:get_pos()

    -- Spawn a decoy with the player's REAL skin + armor appearance
    local decoy = minetest.add_entity(pos, "sns:scout_decoy")
    if decoy then
        local ent = decoy:get_luaentity()
        if ent then ent._owner = name end
        local tex = { "character.png", "blank.png", "blank.png" }
        if armor and armor.textures then
            local at = armor.textures[name]
            if at then
                tex = { at.skin or "character.png",
                        at.armor or "blank.png",
                        at.wielditem or "blank.png" }
            end
        end
        decoy:set_properties({ textures = tex })
        -- Face the same direction as the player
        decoy:set_yaw(player:get_look_horizontal())
        active_scout_decoys[name] = decoy
    end

    -- Save current textures, beginning decoy pos, and armor groups,
    -- then paint the player solid black with no armor protection.
    local orig_props = player:get_properties()
    scout_data[name] = {
        orig_textures    = orig_props.textures,
        orig_armor_groups = player:get_armor_groups(),
        decoy_pos        = vector.copy(pos),
    }

    local black = "character.png^[colorize:#000000:255"
    player:set_properties({ textures = { black } })
    player:set_armor_groups({ fleshy = 100 })  -- no armor reduction
    player:hud_set_flags({ wield = false })
end

-- ============================================================
-- Scout action guards  (digging / placing / damage)
-- ============================================================

-- Prevent shadow from digging: re-place the node immediately after
minetest.register_on_dignode(function(pos, oldnode, digger)
    if not digger or not digger:is_player() then return end
    local name = digger:get_player_name()
    if not scout_active[name] then return end
    -- Re-place the node and give back the item that was dug
    minetest.set_node(pos, oldnode)
    local inv = digger:get_inventory()
    local drops = minetest.get_node_drops(oldnode.name, "")
    for _, drop in ipairs(drops) do
        if inv:room_for_item("main", drop) then
            inv:remove_item("main", drop)
        end
    end
end)

-- Prevent shadow from placing: remove the placed node immediately
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack)
    if not placer or not placer:is_player() then return end
    local name = placer:get_player_name()
    if not scout_active[name] then return end
    minetest.set_node(pos, oldnode)
    -- Give the item back
    local inv = placer:get_inventory()
    if inv then
        inv:add_item("main", newnode.name)
    end
end)

-- Prevent shadow from dealing damage to players
minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    if not hitter or not hitter:is_player() then return end
    if scout_active[hitter:get_player_name()] then
        return true  -- cancel the punch
    end
end)
-- For non-player entities (mobs etc.) there is no equivalent callback;
-- damage prevention is handled via the HP watchdog in globalstep below.

-- Shadow takes damage normally but armor gives no protection
-- (we override armor_groups in globalstep, so no cancel here)

-- ============================================================
-- Wall-phasing system (headwear ability)
-- ============================================================
local prev_place = {} -- RMB edge detection
local prev_scout_key = {} -- Sneak+Jump edge detection for scout

-- ---- Vector helpers ----
local function vec_add(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
local function vec_mul(v, s) return { x = v.x * s, y = v.y * s, z = v.z * s } end
local function vec_len(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function vec_norm(v)
    local l = vec_len(v)
    if l < 0.001 then return { x = 0, y = 0, z = 0 } end
    return { x = v.x / l, y = v.y / l, z = v.z / l }
end

-- Check if a position has a walkable node
local function is_walkable(pos)
    local node = minetest.get_node({
        x = math.floor(pos.x),
        y = math.floor(pos.y),
        z = math.floor(pos.z)
    })
    local def = minetest.registered_nodes[node.name]
    return def and def.walkable
end


-- Convert approach direction into a rotation with feet toward the wall
local function wall_dir_to_rotation(wall_dir)
    local pi = math.pi
    local abs_x = math.abs(wall_dir.x)
    local abs_z = math.abs(wall_dir.z)
    if abs_z >= abs_x then
        if wall_dir.z > 0 then
            return { x =  pi / 2, y = 0, z = 0 }  -- feet toward +Z
        else
            return { x = -pi / 2, y = 0, z = 0 }  -- feet toward -Z
        end
    else
        if wall_dir.x > 0 then
            return { x = 0, y = 0, z = -pi / 2 }  -- feet toward +X
        else
            return { x = 0, y = 0, z =  pi / 2 }  -- feet toward -X
        end
    end
end

-- ---- Visual ghost entity ----
-- We hide the real player model and show a rotated entity instead
minetest.register_entity("sns:wall_ghost", {
    initial_properties = {
        visual = "mesh",
        mesh = "3d_armor_character.b3d",
        textures = { "character.png", "blank.png", "blank.png" },
        visual_size = { x = 1, y = 1 },
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
        glow = 2,
        backface_culling = false,
        use_texture_alpha = true,
        makes_footstep_sound = false,
    },
    on_step = function(self, dtime)
        -- Remove if owner left
        if not self._owner then
            self.object:remove()
            return
        end
        local player = minetest.get_player_by_name(self._owner)
        if not player then
            self.object:remove()
            return
        end
        
        -- Default to player's position so it tracks even if falling
        local pos = player:get_pos()
        if pos then
            self.object:set_pos(pos)
        end
    end,
})

-- Spawn or update the ghost entity for a wall-walking player
local active_ghosts = {} -- name -> ObjectRef of ghost

local pending_ghost_removals = {}
local function spawn_ghost(player, wall_dir)
    local name = player:get_player_name()
    -- Cancel any pending removal
    pending_ghost_removals[name] = (pending_ghost_removals[name] or 0) + 1

    -- Remove existing ghost
    if active_ghosts[name] and active_ghosts[name]:get_pos() then
        active_ghosts[name]:remove()
    end

    local pos = player:get_pos()
    local ghost = minetest.add_entity(pos, "sns:wall_ghost")
    if ghost then
        local ent = ghost:get_luaentity()
        if ent then
            ent._owner = name
        end
        -- Copy skin + armor textures from 3d_armor
        local tex = { "character.png", "blank.png", "blank.png" }
        if armor and armor.textures then
            local at = armor.textures[name]
            if at then
                tex = { at.skin or "character.png",
                    at.armor or "blank.png",
                    at.wielditem or "blank.png" }
            end
        end
        ghost:set_properties({ textures = tex })
        if wall_dir then
            ghost:set_rotation(wall_dir_to_rotation(wall_dir))
        end
        active_ghosts[name] = ghost
        -- Hide the real player and make them small so they don't clip walls
        player:set_properties({
            visual_size = { x = 0, y = 0 },
            collisionbox = { -0.3, 0.0, -0.3, 0.3, 0.45, 0.3 },
            makes_footstep_sound = false,
        })
    end
end

local function remove_ghost(player)
    local name = player:get_player_name()
    local ticket = (pending_ghost_removals[name] or 0) + 1
    pending_ghost_removals[name] = ticket

    -- Delay ghost removal and collisionbox restore by 0.5s to allow sliding under walls
    minetest.after(0.5, function()
        if pending_ghost_removals[name] ~= ticket then return end

        if active_ghosts[name] and active_ghosts[name]:get_pos() then
            active_ghosts[name]:remove()
        end
        active_ghosts[name] = nil
        
        local p = minetest.get_player_by_name(name)
        if p then
            -- Restore player visibility and collision
            p:set_properties({
                visual_size = { x = 1, y = 1 },
                collisionbox = { -0.3, 0.0, -0.3, 0.3, 1.7, 0.3 },
                makes_footstep_sound = true,
            })
        end
    end)
end


-- ============================================================
-- Water walking loop (every WATER_WALK_INTERVAL via minetest.after)
-- ============================================================
local function water_walk_tick()
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        if hakama_users[name] then
            local pos = player:get_pos()
            if pos then
                local controls = player:get_player_control()
                local function node_at(y_off)
                    local n = minetest.get_node({ x = pos.x, y = pos.y + y_off, z = pos.z })
                    local d = minetest.registered_nodes[n.name]
                    return d and d.liquidtype ~= "none"
                end
                local on_water = node_at(-0.1) or node_at(0.0) or node_at(0.3)
                local moving = controls.up or controls.down or controls.left or controls.right
                if on_water and moving and controls.aux1 then
                    local vel = player:get_velocity()
                    if vel and vel.y ~= 0 then
                        player:add_velocity({ x = 0, y = -vel.y, z = 0 })
                    end
                    player:set_physics_override({ gravity = 0 })
                else
                    player:set_physics_override({ gravity = 1 })
                end
            end
        end
    end
    minetest.after(WATER_WALK_INTERVAL, water_walk_tick)
end
minetest.after(WATER_WALK_INTERVAL, water_walk_tick)

-- ============================================================
-- Globalstep: wall-phasing + scout
-- ============================================================
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos  = player:get_pos()
        if pos then

        -- ========== FULL-SET BONUS: SCOUT ACTIVATION ==========
        if SET_BONUS == "scout" and full_set_users[name] then
            local controls = player:get_player_control()
            local scout_key = controls.sneak and controls.jump
            local was_scout_key = prev_scout_key[name] or false
            if scout_key and not was_scout_key then
                if scout_active[name] then
                    end_scout(player)
                else
                    begin_scout(player)
                end
            end
            prev_scout_key[name] = scout_key
        end

        -- ========== SCOUT: ENFORCE BLACK TEXTURE + BARE ARMOR ==========
        -- 3d_armor may call update_player_visuals at any time; re-enforce
        -- the black appearance and armor_groups every tick.
        if scout_active[name] then
            local black = "character.png^[colorize:#000000:255"
            local props = player:get_properties()
            if props.textures and props.textures[1] ~= black then
                player:set_properties({ textures = { black } })
            end
            -- Ensure armor gives no protection while in shadow form
            local ag = player:get_armor_groups()
            if (ag.fleshy or 0) ~= 100 then
                player:set_armor_groups({ fleshy = 100 })
            end
        end

        -- ========== SCOUT: MOB HP WATCHDOG ==========
        -- Cache HP of all entities within punch range of a scout player.
        -- If any entity's HP dropped since last tick, restore it.
        -- (register_on_punchplayer handles player targets; this covers mobs.)
        if scout_active[name] then
            local watched = {}
            for _, obj in ipairs(minetest.get_objects_inside_radius(pos, 5)) do
                if obj ~= player and not obj:is_player() then
                    local id = tostring(obj)
                    watched[id] = obj
                    local hp = obj:get_hp()
                    local cached = scout_hp_cache[id]
                    if cached and hp < cached then
                        obj:set_hp(cached)
                    end
                    scout_hp_cache[id] = obj:get_hp()
                end
            end
            -- Evict cache entries no longer near this scout
            for id, _ in pairs(scout_hp_cache) do
                if not watched[id] then
                    scout_hp_cache[id] = nil
                end
            end
        end

        -- ========== WALL PHASING (headwear) ==========
        if headwear_users[name] then
            local controls  = player:get_player_control()
            local is_placing = controls.place
            local was_placing = prev_place[name] or false

            if controls.sneak and is_placing and not was_placing then
                local look_dir = player:get_look_dir()
                local wall_dir = vec_norm({ x = look_dir.x, y = 0, z = look_dir.z })

                if vec_len(wall_dir) > 0.001 then
                    -- Check for a solid block at chest height directly ahead
                    local check = vec_add(pos, vec_mul(wall_dir, 0.8))
                    check.y = check.y + 0.6 -- chest height

                    if is_walkable(check) then
                        -- Teleport 0.3 blocks into the wall
                        local new_pos = vec_add(pos, vec_mul(wall_dir, 0.3))
                        player:set_pos(new_pos)
                        spawn_ghost(player, wall_dir)
                        remove_ghost(player) -- queues restore after 0.5s
                    end
                end
            end
            prev_place[name] = is_placing
        end

        end  -- pos guard
    end
end)

-- Clean up on player leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    chestplate_users[name] = nil
    headwear_users[name]   = nil
    hakama_users[name]     = nil
    full_set_users[name]   = nil
    scout_active[name]     = nil
    scout_cooldowns[name]  = nil
    scout_data[name]       = nil
    prev_place[name]       = nil
    prev_scout_key[name]   = nil
    if active_ghosts[name] then
        if active_ghosts[name]:get_pos() then
            active_ghosts[name]:remove()
        end
        active_ghosts[name] = nil
    end
    if active_scout_decoys[name] then
        if active_scout_decoys[name]:get_pos() then
            active_scout_decoys[name]:remove()
        end
        active_scout_decoys[name] = nil
    end
end)

-- ============================================================
-- Elite Armour of Shinobi  (Dungeon Reward)
-- Same abilities as the base set but with stronger stats:
--   • Higher armour absorption
--   • Higher heal chance (faster natural regen)
--   • Higher speed bonus
--   • Full set: raises max HP to ELITE_HP_MAX
-- ============================================================
local ELITE_HEAL    = tonumber(S:get("sns.elite_armour_heal")) or 30
local ELITE_SPEED   = tonumber(S:get("sns.elite_speed_boost")) or 0.9
local ELITE_HP_MAX  = tonumber(S:get("sns.elite_hp_max"))      or 30

local elite_cp_users = {}
local elite_hw_users = {}
local elite_hk_users = {}
local elite_set_users = {}

local function has_elite_full_set(name)
    return elite_cp_users[name] and elite_hw_users[name] and elite_hk_users[name]
end

local function apply_elite_set(player)
    local name = player:get_player_name()
    if elite_set_users[name] then return end
    elite_set_users[name] = true
    player:set_properties({ hp_max = ELITE_HP_MAX })
    -- Partially top-up HP so the player feels the expansion immediately
    local hp = player:get_hp()
    player:set_hp(math.min(hp + 5, ELITE_HP_MAX))
end

local function remove_elite_set(player)
    local name = player:get_player_name()
    if not elite_set_users[name] then return end
    elite_set_users[name] = nil
    player:set_properties({ hp_max = 20 })
    local hp = player:get_hp()
    if hp > 20 then player:set_hp(20) end
end

local function check_elite_set(player)
    if has_elite_full_set(player:get_player_name()) then
        apply_elite_set(player)
    else
        remove_elite_set(player)
    end
end

-- Elite Chestplate
armor:register_armor("sns:elite_chestplate", {
    description = "Elite Chestplate of Shinobi",
    inventory_image = "sns_chestplate_inv_" .. colour .. ".png",
    texture         = "sns_chestplate_equipped_" .. colour .. ".png",
    preview = "sns_chestplate_inv_" .. colour .. ".png",
    groups = {
        armor_torso = 1,
        armor_heal  = ELITE_HEAL,
        armor_use   = 0,
    },
    armor_groups = { fleshy = 18 },
    on_equip = function(player, index, stack)
        local name = player:get_player_name()
        chestplate_users[name] = true
        elite_cp_users[name]   = true
        check_full_set(player)
        check_elite_set(player)
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        chestplate_users[name] = nil
        elite_cp_users[name]   = nil
        clear_full_set(player)
        remove_elite_set(player)
    end,
})

-- Elite Headwear
armor:register_armor("sns:elite_headwear", {
    description = "Elite Headwear of Shinobi",
    inventory_image = "sns_headwear_inv_" .. colour .. ".png",
    texture         = "sns_headwear_equipped_" .. colour .. ".png",
    preview = "sns_headwear_inv_" .. colour .. ".png",
    groups = {
        armor_head = 1,
        armor_heal = ELITE_HEAL,
        armor_use  = 0,
    },
    armor_groups = { fleshy = 14 },
    on_equip = function(player, index, stack)
        local name = player:get_player_name()
        headwear_users[name] = true
        elite_hw_users[name] = true
        player:override_day_night_ratio(NIGHT_VISION_RATIO)
        check_full_set(player)
        check_elite_set(player)
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        headwear_users[name] = nil
        elite_hw_users[name] = nil
        player:override_day_night_ratio(nil)
        clear_full_set(player)
        remove_elite_set(player)
    end,
})

-- Elite Hakama
armor:register_armor("sns:elite_hakama", {
    description = "Elite Hakama of Shinobi",
    inventory_image = "sns_hakama_inv_" .. colour .. ".png",
    texture         = "sns_hakama_equipped_" .. colour .. ".png",
    preview = "sns_hakama_inv_" .. colour .. ".png",
    groups = {
        armor_legs   = 1,
        armor_heal   = ELITE_HEAL,
        armor_use    = 0,
        physics_speed = ELITE_SPEED,
    },
    armor_groups = { fleshy = 14 },
    on_equip = function(player, index, stack)
        local name = player:get_player_name()
        hakama_users[name]   = true
        elite_hk_users[name] = true
        check_full_set(player)
        check_elite_set(player)
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        hakama_users[name]   = nil
        elite_hk_users[name] = nil
        clear_full_set(player)
        remove_elite_set(player)
    end,
})

minetest.log("action", "[sns] Armour loaded")
