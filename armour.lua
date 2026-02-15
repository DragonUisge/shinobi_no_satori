-- Shinobi no Satori - Armor Registration
-- Abilities:
--   Chestplate: increased melee damage
--   Headwear:   wall-running (hold jump near wall while sprinting) + night vision
--   Hakama:     water walking (sprint on water) + speed boost
-- Stats: low armor rating, high heal chance, unbreakable

-- ============================================================
-- Tracking tables for abilities
-- ============================================================
local chestplate_users = {}   -- players wearing the chestplate (bonus damage)
local headwear_users = {}     -- players wearing the headwear (wall-run + night vision)
local hakama_users = {}       -- players wearing the hakama (water walk)

-- ============================================================
-- Settings
-- ============================================================
local S = minetest.settings

local HIDE_FROM_CREATIVE = S:get_bool("shinobi_hide_from_creative", true)
local ARMOR_HEAL         = tonumber(S:get("shinobi_armor_heal")) or 18
local DAMAGE_MULTIPLIER  = tonumber(S:get("shinobi_damage_multiplier")) or 1.8
local WALL_RUN_SPEED     = tonumber(S:get("shinobi_wall_run_speed")) or 6.0
local NIGHT_VISION_RATIO = tonumber(S:get("shinobi_night_vision_ratio")) or 0.6
local SPEED_BOOST        = tonumber(S:get("shinobi_speed_boost")) or 0.6
local WATER_WALK_INTERVAL = 0.1

local creative_group = HIDE_FROM_CREATIVE and 1 or 0

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
        armor_heal = ARMOR_HEAL,
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
        armor_heal = ARMOR_HEAL,
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
        armor_heal = ARMOR_HEAL,
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
-- Globalstep: wall-running + water walking
-- ============================================================
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < WATER_WALK_INTERVAL then return end
    timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos = player:get_pos()
        if not pos then return end

        -- ---- Wall-running (headwear) ----
        if headwear_users[name] then
            local controls = player:get_player_control()
            -- Must be sprinting (aux1) + holding jump + moving forward
            if controls.aux1 and controls.jump and (controls.up or controls.left or controls.right) then
                -- Check for a wall nearby (within 0.8 blocks horizontally)
                local look_dir = player:get_look_dir()
                local front = {
                    x = pos.x + look_dir.x * 0.8,
                    y = pos.y + 0.5,
                    z = pos.z + look_dir.z * 0.8,
                }
                local node_front = minetest.get_node(front)
                local def = minetest.registered_nodes[node_front.name]
                if def and def.walkable then
                    -- There's a wall in front — run up it
                    local vel = player:get_velocity()
                    if vel and vel.y < WALL_RUN_SPEED then
                        player:add_velocity({ x = 0, y = WALL_RUN_SPEED * dtime * 10, z = 0 })
                    end
                end
            end
        end

        -- ---- Water walking (hakama) ----
        if hakama_users[name] then
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
                player:set_physics_override({gravity = 0})
                local vel = player:get_velocity()
                if vel and vel.y < 0 then
                    player:add_velocity({ x = 0, y = -vel.y, z = 0 })
                end
            else
                -- Restore normal gravity
                player:set_physics_override({gravity = 1})
            end
        end
    end
end)

-- Clean up on player leave
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    chestplate_users[name] = nil
    headwear_users[name] = nil
    hakama_users[name] = nil
end)
