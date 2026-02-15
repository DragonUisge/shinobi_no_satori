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
local WALL_WALK_SPEED     = tonumber(S:get("shinobi_wall_walk_speed")) or 4.0
local NIGHT_VISION_RATIO  = tonumber(S:get("shinobi_night_vision_ratio")) or 0.6
local SPEED_BOOST         = tonumber(S:get("shinobi_speed_boost")) or 0.6
local WATER_WALK_INTERVAL = 0.1
local WALL_WALK_INTERVAL  = 0.05 -- tighter tick for smooth wall movement
local WALL_GRAVITY        = 18   -- pull toward surface (blocks/s²)
local SURFACE_STICK_DIST  = 1.0  -- how far to check for adjacent surface
local SURFACE_CHECK_DIST  = 1.5  -- how far to look for surface under feet
local WALL_ACTIVATE_RANGE = 1.5  -- how far from a wall activation works

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
-- Wall-walking system (headwear ability)
-- ============================================================
-- State per player: { normal = {x,y,z}, active = bool }
-- normal: unit vector pointing AWAY from the surface the player walks on
-- floor = {0,1,0}, ceiling = {0,-1,0}, walls = ±x / ±z
local wall_walkers = {}
local prev_place   = {} -- track previous RMB state for edge detection

-- 6 possible surface normals (axis-aligned only)
local NORMALS      = {
    floor   = { x = 0, y = 1, z = 0 },
    ceiling = { x = 0, y = -1, z = 0 },
    north   = { x = 0, y = 0, z = 1 },
    south   = { x = 0, y = 0, z = -1 },
    east    = { x = 1, y = 0, z = 0 },
    west    = { x = -1, y = 0, z = 0 },
}

-- ---- Vector helpers ----
local function vec_add(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
local function vec_sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function vec_mul(v, s) return { x = v.x * s, y = v.y * s, z = v.z * s } end
local function vec_dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vec_len(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function vec_norm(v)
    local l = vec_len(v)
    if l < 0.001 then return { x = 0, y = 0, z = 0 } end
    return { x = v.x / l, y = v.y / l, z = v.z / l }
end
local function vec_cross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x,
    }
end
local function vec_eq(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end

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

-- Find which wall/ceiling is adjacent to the player
-- Returns the surface normal or nil
local function find_adjacent_surface(pos, exclude_floor)
    -- Check all 6 directions: look for a walkable node adjacent to player
    local checks = {
        { dir = { x = 0, y = -1, z = 0 },   normal = NORMALS.floor },
        { dir = { x = 0, y = 1, z = 0 },    normal = NORMALS.ceiling },
        { dir = { x = 0, y = 0, z = -1 },   normal = NORMALS.north },   -- wall to south, normal points north
        { dir = { x = 0, y = 0, z = 1 },    normal = NORMALS.south },
        { dir = { x = -1, y = 0, z = 0 },   normal = NORMALS.east },
        { dir = { x = 1, y = 0, z = 0 },    normal = NORMALS.west },
    }
    for _, c in ipairs(checks) do
        if not (exclude_floor and vec_eq(c.normal, NORMALS.floor)) then
            local check_pos = vec_add(pos, vec_mul(c.dir, SURFACE_STICK_DIST))
            if is_walkable(check_pos) then
                return c.normal
            end
        end
    end
    return nil
end

-- Build a local coordinate frame on the surface
-- Returns forward_vec, right_vec relative to the surface plane
local function get_surface_frame(player, normal)
    -- Player's look direction (horizontal yaw only for consistency)
    local yaw = player:get_look_horizontal()
    local look_h = { x = -math.sin(yaw), y = 0, z = math.cos(yaw) }

    -- Project look direction onto the surface plane
    -- plane_forward = look_h - (look_h . normal) * normal
    local d = vec_dot(look_h, normal)
    local forward = vec_sub(look_h, vec_mul(normal, d))
    forward = vec_norm(forward)

    -- If forward is zero (looking straight into/away from surface), pick arbitrary
    if vec_len(forward) < 0.001 then
        -- Use world up projected, or world X if on ceiling/floor
        if math.abs(normal.y) > 0.9 then
            forward = { x = -math.sin(yaw), y = 0, z = math.cos(yaw) }
        else
            forward = { x = 0, y = 1, z = 0 }
            local d2 = vec_dot(forward, normal)
            forward = vec_sub(forward, vec_mul(normal, d2))
            forward = vec_norm(forward)
        end
    end

    local right = vec_cross(forward, normal)
    right = vec_norm(right)

    return forward, right
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
        -- Remove if owner left or stopped wall-walking
        if not self._owner then
            self.object:remove()
            return
        end
        local player = minetest.get_player_by_name(self._owner)
        if not player then
            self.object:remove()
            return
        end
        local ww = wall_walkers[self._owner]
        if not ww or not ww.active then
            self.object:remove()
            return
        end
    end,
})

-- Spawn or update the ghost entity for a wall-walking player
local active_ghosts = {} -- name -> ObjectRef of ghost

local function spawn_ghost(player)
    local name = player:get_player_name()
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
        active_ghosts[name] = ghost
        -- Hide the real player
        player:set_properties({
            visual_size = { x = 0, y = 0 },
            makes_footstep_sound = false,
        })
    end
end

local function remove_ghost(player)
    local name = player:get_player_name()
    if active_ghosts[name] and active_ghosts[name]:get_pos() then
        active_ghosts[name]:remove()
    end
    active_ghosts[name] = nil
    -- Restore player visibility
    player:set_properties({
        visual_size = { x = 1, y = 1 },
        makes_footstep_sound = true,
    })
end

-- Compute the rotation (in radians) for the ghost based on surface normal
local function normal_to_rotation(normal, yaw)
    -- Rotation = { x = pitch, y = yaw, z = roll } in radians
    -- Floor (default): no extra rotation
    -- Ceiling: flip upside down (pitch = pi)
    -- Walls: tilt 90° so feet point toward wall
    local pi = math.pi
    if normal.y > 0.9 then
        -- Floor
        return { x = 0, y = -yaw, z = 0 }
    elseif normal.y < -0.9 then
        -- Ceiling: upside down
        return { x = pi, y = -yaw, z = 0 }
    elseif normal.z > 0.9 then
        -- North wall: feet point south (-Z)
        return { x = -pi / 2, y = 0, z = 0 }
    elseif normal.z < -0.9 then
        -- South wall: feet point north (+Z)
        return { x = pi / 2, y = 0, z = 0 }
    elseif normal.x > 0.9 then
        -- East wall: feet point west (-X)
        return { x = 0, y = 0, z = pi / 2 }
    elseif normal.x < -0.9 then
        -- West wall: feet point east (+X)
        return { x = 0, y = 0, z = -pi / 2 }
    end
    return { x = 0, y = -yaw, z = 0 }
end

-- ---- Engage / disengage wall-walking ----
local function engage_wall_walk(player, normal)
    local name = player:get_player_name()
    wall_walkers[name] = { normal = normal, active = true }
    -- Cancel all existing velocity
    local vel = player:get_velocity()
    if vel then
        player:add_velocity({ x = -vel.x, y = -vel.y, z = -vel.z })
    end
    -- Teleport player slightly into the wall so surface checks pass
    local pos = player:get_pos()
    local stick_pos = vec_add(pos, vec_mul(normal, -0.3))
    stick_pos.y = stick_pos.y + 0.5 -- lift off the floor
    player:set_pos(stick_pos)
    -- Disable gravity and jump but keep speed (we control movement via add_velocity)
    player:set_physics_override({ gravity = 0, jump = 0 })
    spawn_ghost(player)
end

local function disengage_wall_walk(player)
    local name = player:get_player_name()
    wall_walkers[name] = nil
    player:set_physics_override({ gravity = 1, speed = 1, jump = 1 })
    -- Cancel lateral velocity so the player drops cleanly
    local vel = player:get_velocity()
    if vel then
        player:add_velocity({ x = -vel.x, y = 0, z = -vel.z })
    end
    remove_ghost(player)
end

-- ============================================================
-- Globalstep: wall-walking + water walking
-- ============================================================
local ww_timer = 0
local wt_timer = 0

minetest.register_globalstep(function(dtime)
    -- ---- Wall-walking tick (high frequency) ----
    ww_timer = ww_timer + dtime
    local do_ww = ww_timer >= WALL_WALK_INTERVAL
    if do_ww then ww_timer = 0 end

    -- ---- Water walking tick ----
    wt_timer = wt_timer + dtime
    local do_wt = wt_timer >= WATER_WALK_INTERVAL
    if do_wt then wt_timer = 0 end

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos  = player:get_pos()
        if not pos then goto continue end

        -- ========== WALL-WALKING (headwear) ==========
        if headwear_users[name] and do_ww then
            local controls = player:get_player_control()
            local ww = wall_walkers[name]

            if ww and ww.active then
                -- ---- ACTIVE wall-walking ----

                -- JUMP → disengage
                if controls.jump then
                    -- Push player away from surface before disengaging
                    local push = vec_mul(ww.normal, 4)
                    player:add_velocity(push)
                    disengage_wall_walk(player)
                    goto continue
                end

                -- Check if surface still exists (check at player center and above/below)
                local inv_normal = vec_mul(ww.normal, -1)
                local check1 = vec_add(pos, vec_mul(inv_normal, SURFACE_CHECK_DIST))
                local check2 = vec_add(vec_add(pos, { x = 0, y = 0.8, z = 0 }), vec_mul(inv_normal, SURFACE_CHECK_DIST))
                local surface_ok = is_walkable(check1) or is_walkable(check2)

                if not surface_ok then
                    -- Surface gone — check for transition to adjacent surface
                    local new_normal = find_adjacent_surface(pos, false)
                    if new_normal and not vec_eq(new_normal, ww.normal) then
                        -- Transition to new surface!
                        ww.normal = new_normal
                    else
                        -- Give a small grace: try one more position slightly behind
                        local behind = vec_add(pos, vec_mul(inv_normal, 0.5))
                        if is_walkable(behind) then
                            -- Still ok, pull closer
                            player:add_velocity(vec_mul(inv_normal, 3))
                        else
                            -- No surface at all — fall
                            disengage_wall_walk(player)
                            goto continue
                        end
                    end
                end

                -- Apply surface gravity: pull toward surface
                local pull = vec_mul(ww.normal, -WALL_GRAVITY * dtime)
                player:add_velocity(pull)

                -- Cancel velocity component along normal (don't drift away from surface)
                local vel = player:get_velocity()
                if vel then
                    local normal_component = vec_dot(vel, ww.normal)
                    if normal_component > 0.5 then
                        -- Moving away from surface, cancel it completely
                        player:add_velocity(vec_mul(ww.normal, -normal_component))
                    end
                end

                -- Compute movement from controls
                local forward, right = get_surface_frame(player, ww.normal)
                local move = { x = 0, y = 0, z = 0 }

                if controls.up then move = vec_add(move, forward) end
                if controls.down then move = vec_sub(move, forward) end
                if controls.left then move = vec_sub(move, right) end
                if controls.right then move = vec_add(move, right) end

                move = vec_norm(move)
                if vec_len(move) > 0.01 then
                    -- Edge detection: check if there's a surface ahead in movement direction
                    local ahead = vec_add(pos, vec_mul(move, 1.0))
                    local ahead_feet = vec_add(ahead, vec_mul(ww.normal, -SURFACE_CHECK_DIST))

                    if not is_walkable(ahead_feet) then
                        -- Moving toward edge — check for a perpendicular surface to transition to
                        -- Look in the -normal direction from ahead position (wrapping around corner)
                        local corner_check = vec_add(ahead, vec_mul(ww.normal, -1.5))
                        local wrap_dir = vec_mul(move, -1) -- opposite of movement = new normal candidate

                        -- Normalize wrap_dir to nearest axis
                        local abs_x, abs_y, abs_z = math.abs(wrap_dir.x), math.abs(wrap_dir.y), math.abs(wrap_dir.z)
                        local new_norm
                        if abs_x >= abs_y and abs_x >= abs_z then
                            new_norm = { x = wrap_dir.x > 0 and 1 or -1, y = 0, z = 0 }
                        elseif abs_y >= abs_x and abs_y >= abs_z then
                            new_norm = { x = 0, y = wrap_dir.y > 0 and 1 or -1, z = 0 }
                        else
                            new_norm = { x = 0, y = 0, z = wrap_dir.z > 0 and 1 or -1 }
                        end

                        -- Check if the wrap-around surface exists
                        local wrap_check = vec_add(ahead, vec_mul(new_norm, -SURFACE_CHECK_DIST))
                        if is_walkable(wrap_check) then
                            ww.normal = new_norm
                            -- Small teleport to wrap around the corner
                            local new_pos = vec_add(pos, vec_mul(move, 0.5))
                            player:set_pos(new_pos)
                        end
                        -- If no wrap surface, just stop at edge (don't apply movement)
                    else
                        -- Clear path — apply movement velocity
                        local move_vel = vec_mul(move, WALL_WALK_SPEED)
                        -- Replace existing lateral velocity instead of adding
                        local cur_vel = player:get_velocity() or { x = 0, y = 0, z = 0 }
                        local normal_part = vec_mul(ww.normal, vec_dot(cur_vel, ww.normal))
                        -- New velocity = movement + normal component (gravity/stick)
                        local new_vel = vec_add(move_vel, normal_part)
                        local correction = vec_sub(new_vel, cur_vel)
                        player:add_velocity(correction)
                    end
                else
                    -- No movement input — dampen lateral velocity to stop sliding
                    local cur_vel = player:get_velocity()
                    if cur_vel then
                        local normal_part = vec_mul(ww.normal, vec_dot(cur_vel, ww.normal))
                        local lateral = vec_sub(cur_vel, normal_part)
                        player:add_velocity(vec_mul(lateral, -0.5))
                    end
                end

                -- Update ghost entity position and rotation
                local ghost = active_ghosts[name]
                if ghost and ghost:get_pos() then
                    ghost:set_pos(pos)
                    local yaw = player:get_look_horizontal()
                    ghost:set_rotation(normal_to_rotation(ww.normal, yaw))
                end
            else
                -- ---- NOT wall-walking: check for activation ----
                -- Activation: holding sneak + just pressed RMB (place) while facing a wall
                local was_placing = prev_place[name] or false
                local is_placing  = controls.place

                if controls.sneak and is_placing and not was_placing then
                    -- Check for a wall in front of the player (at least 2 blocks tall)
                    local look_dir = player:get_look_dir()
                    local wall_dir = { x = look_dir.x, y = 0, z = look_dir.z }
                    wall_dir = vec_norm(wall_dir)

                    -- Search for wall at multiple distances
                    local found_wall = false
                    for dist = 0.8, WALL_ACTIVATE_RANGE, 0.3 do
                        local front_low = {
                            x = pos.x + wall_dir.x * dist,
                            y = pos.y + 0.3,
                            z = pos.z + wall_dir.z * dist,
                        }
                        local front_high = {
                            x = pos.x + wall_dir.x * dist,
                            y = pos.y + 1.3,
                            z = pos.z + wall_dir.z * dist,
                        }
                        if is_walkable(front_low) and is_walkable(front_high) then
                            found_wall = true
                            break
                        end
                    end

                    if found_wall then
                        -- Determine which axis-aligned normal matches the wall
                        local abs_x, abs_z = math.abs(wall_dir.x), math.abs(wall_dir.z)
                        local normal
                        if abs_x >= abs_z then
                            normal = { x = wall_dir.x > 0 and -1 or 1, y = 0, z = 0 }
                        else
                            normal = { x = 0, y = 0, z = wall_dir.z > 0 and -1 or 1 }
                        end
                        engage_wall_walk(player, normal)
                    end
                end
                prev_place[name] = is_placing
            end
        elseif wall_walkers[name] then
            -- Headwear removed while wall-walking — disengage
            disengage_wall_walk(player)
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
                if not wall_walkers[name] then
                    player:set_physics_override({ gravity = 0 })
                end
                local vel = player:get_velocity()
                if vel and vel.y < 0 then
                    player:add_velocity({ x = 0, y = -vel.y, z = 0 })
                end
            else
                -- Restore normal gravity (only if not wall-walking)
                if not wall_walkers[name] then
                    player:set_physics_override({ gravity = 1 })
                end
            end
        end

        ::continue::
    end
end)

-- Clean up on player leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    chestplate_users[name] = nil
    if wall_walkers[name] then
        disengage_wall_walk(player)
    end
    headwear_users[name] = nil
    hakama_users[name]   = nil
    prev_place[name]     = nil
    if active_ghosts[name] then
        if active_ghosts[name]:get_pos() then
            active_ghosts[name]:remove()
        end
        active_ghosts[name] = nil
    end
end)
