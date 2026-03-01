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

local HIDE_FROM_CREATIVE  = S:get_bool("shinobi_hide_from_creative", true)
local ARMOUR_HEAL         = tonumber(S:get("shinobi_armour_heal")) or 18
local DAMAGE_MULTIPLIER   = tonumber(S:get("shinobi_damage_multiplier")) or 1.8
local NIGHT_VISION_RATIO  = tonumber(S:get("shinobi_night_vision_ratio")) or 0.6
local SPEED_BOOST         = tonumber(S:get("shinobi_speed_boost")) or 0.6
local WATER_WALK_INTERVAL = 0.1

local creative_group      = HIDE_FROM_CREATIVE and 1 or 0

-- ============================================================
-- Chestplate of Shinobi — increased melee damage
-- ============================================================
armor:register_armor("shinobi_no_satori:epic_chestplate", {
    description = "Chestplate of Shinobi",
    inventory_image = "shinobi_chestplate_inv.png",
    texture = "shinobi_chestplate_equipped.png",
    preview = "shinobi_chestplate_preview.png",
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
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        chestplate_users[name] = nil
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

-- ============================================================
-- Headwear of Shinobi — night vision + wall-running
-- ============================================================
armor:register_armor("shinobi_no_satori:epic_headwear", {
    description = "Headwear of Shinobi",
    inventory_image = "shinobi_headwear_inv.png",
    texture = "shinobi_headwear_equipped.png",
    preview = "shinobi_headwear_preview.png",
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
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        headwear_users[name] = nil
        -- Remove night vision
        player:override_day_night_ratio(nil)
    end,
})

-- ============================================================
-- Hakama of Shinobi — water walking + speed boost
-- ============================================================
armor:register_armor("shinobi_no_satori:epic_hakama", {
    description = "Hakama of Shinobi",
    inventory_image = "shinobi_hakama_inv.png",
    texture = "shinobi_hakama_equipped.png",
    preview = "shinobi_hakama_preview.png",
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
    end,
    on_unequip = function(player, index, stack)
        local name = player:get_player_name()
        hakama_users[name] = nil
    end,
})

-- ============================================================
-- Wall-phasing system (headwear ability)
-- ============================================================
local prev_place = {} -- RMB edge detection

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
minetest.register_entity("shinobi_no_satori:wall_ghost", {
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
    local ghost = minetest.add_entity(pos, "shinobi_no_satori:wall_ghost")
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
-- Globalstep: wall-phasing + water walking
-- ============================================================
local wt_timer = 0

minetest.register_globalstep(function(dtime)
    -- ---- Water walking tick ----
    wt_timer = wt_timer + dtime
    local do_wt = wt_timer >= WATER_WALK_INTERVAL
    if do_wt then wt_timer = 0 end

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos  = player:get_pos()
        if not pos then goto continue end

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

        -- ========== WATER WALKING (hakama) ==========
        if hakama_users[name] and do_wt then
            local controls   = player:get_player_control()
            local below      = { x = pos.x, y = pos.y - 0.3, z = pos.z }
            local feet       = { x = pos.x, y = pos.y, z = pos.z }
            local node_below = minetest.get_node(below)
            local node_feet  = minetest.get_node(feet)
            local def_below  = minetest.registered_nodes[node_below.name]
            local def_feet   = minetest.registered_nodes[node_feet.name]

            local in_water   = (def_below and def_below.liquidtype ~= "none") or
                (def_feet and def_feet.liquidtype ~= "none")

            if in_water and controls.aux1 and (controls.up or controls.left or controls.right) then
                -- Sprinting on water: cancel gravity
                player:set_physics_override({ gravity = 0 })
                local vel = player:get_velocity()
                if vel and vel.y < 0 then
                    player:add_velocity({ x = 0, y = -vel.y, z = 0 })
                end
            else
                player:set_physics_override({ gravity = 1 })
            end
        end

        ::continue::
    end
end)

-- Clean up on player leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    chestplate_users[name] = nil
    headwear_users[name]   = nil
    hakama_users[name]     = nil
    prev_place[name]       = nil
    if active_ghosts[name] then
        if active_ghosts[name]:get_pos() then
            active_ghosts[name]:remove()
        end
        active_ghosts[name] = nil
    end
end)
