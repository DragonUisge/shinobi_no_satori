-- Shinobi no Satori – Dungeon Traps
-- Trap nodes for the ninja dungeon schematic.
--
-- Nodes registered here (place these in your schematic):
--   shinobi_no_satori:spike_floor       — damages players who stand on it
--   shinobi_no_satori:collapse_floor    — crumbles 1.5 s after a player steps near
--   shinobi_no_satori:dart_wall         — shoots darts periodically (use facedir!)
--   shinobi_no_satori:sand_trigger      — invisible ceiling node; sand wall falls when player approaches
--   shinobi_no_satori:dungeon_zone      — invisible marker; revokes fly/noclip while inside
--   shinobi_no_satori:dungeon_chest     — one-time reward chest (elite armour + shurikens + rank)

-- Global title table shared with armour.lua (populated from saved data on load)
shinobi_player_titles = {}

local S = minetest.settings

local DART_INTERVAL = tonumber(S:get("shinobi_dart_interval")) or 3.0
local DART_SPEED    = tonumber(S:get("shinobi_dart_speed"))    or 20
local DART_DAMAGE   = tonumber(S:get("shinobi_dart_damage"))   or 4
local SPIKE_DAMAGE  = 4  -- HP removed per second by spike floor (bypasses armour)

-- ============================================================
-- 1. Spike Floor
-- Deals SPIKE_DAMAGE HP/s via ABM — bypasses 3d_armor absorption.
-- ============================================================
minetest.register_node("shinobi_no_satori:spike_floor", {
    description = "Spike Floor",
    tiles = { "shinobi_spike_floor_top.png", "shinobi_spike_floor_side.png" },
    groups = { cracky = 2 },  -- no damage_per_second: handled by ABM to bypass armour
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_abm({
    label     = "Spike floor damage (armour bypass)",
    nodenames = { "shinobi_no_satori:spike_floor" },
    interval  = 1.0,
    chance    = 1,
    action    = function(pos, node)
        local top = pos.y + 0.5  -- top surface of the node
        for _, obj in ipairs(minetest.get_objects_inside_radius(pos, 1.5)) do
            if obj:is_player() then
                local pp = obj:get_pos()
                -- Only damage if player is actually standing on (or just above) the node
                if pp and pp.y >= top and pp.y <= top + 1.3 then
                    local hp = obj:get_hp()
                    if hp > 0 then
                        obj:set_hp(math.max(0, hp - SPIKE_DAMAGE))
                    end
                end
            end
        end
    end,
})

-- ============================================================
-- 2. Crumbling Floor
-- Collapses 1.5 s after a player steps nearby.
-- ============================================================
local collapsing = {}   -- position hash → true while countdown is running

minetest.register_node("shinobi_no_satori:collapse_floor", {
    description = "Crumbling Floor",
    tiles = { "shinobi_collapse_floor.png" },
    groups = { cracky = 3 },
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_abm({
    label    = "Crumbling floor trigger",
    nodenames = { "shinobi_no_satori:collapse_floor" },
    interval = 0.4,
    chance   = 1,
    action   = function(pos, node)
        local hash = minetest.hash_node_position(pos)
        if collapsing[hash] then return end

        local near = minetest.get_objects_inside_radius(pos, 1.2)
        for _, obj in ipairs(near) do
            if obj:is_player() then
                collapsing[hash] = true

                -- Dust crack particles
                minetest.add_particlespawner({
                    amount     = 10,
                    time       = 1.4,
                    minpos     = vector.add(pos, vector.new(-0.5, 0.5, -0.5)),
                    maxpos     = vector.add(pos, vector.new( 0.5, 0.6,  0.5)),
                    minvel     = vector.new(-1, 0.5, -1),
                    maxvel     = vector.new( 1, 2.0,  1),
                    minexptime = 0.4,
                    maxexptime = 0.9,
                    minsize    = 0.5,
                    maxsize    = 1.2,
                    texture    = "default_stone.png",
                })

                minetest.after(1.5, function()
                    if minetest.get_node(pos).name == "shinobi_no_satori:collapse_floor" then
                        minetest.remove_node(pos)
                        minetest.sound_play("default_gravel_footstep", {
                            pos = pos, gain = 1.0, max_hear_distance = 16,
                        }, true)
                    end
                    collapsing[hash] = nil
                end)

                break
            end
        end
    end,
})

-- ============================================================
-- 3. Dart Trap Wall
-- Shoots a dart projectile every DART_INTERVAL seconds.
-- Place with facedir so the "front" face points toward the
-- corridor (the dart fires out of the front face).
-- ============================================================
minetest.register_entity("shinobi_no_satori:dart", {
    initial_properties = {
        visual              = "upright_sprite",
        textures            = { "shinobi_dart.png" },
        visual_size         = { x = 0.25, y = 0.25 },
        physical            = false,
        collide_with_objects = false,
        pointable           = false,
        static_save         = false,
    },
    _dir = nil,
    _age = 0,

    on_step = function(self, dtime)
        self._age = self._age + dtime
        if self._age > 6 then self.object:remove(); return end

        local pos = self.object:get_pos()
        if not pos then self.object:remove(); return end

        -- Wall collision
        local dir  = self._dir or vector.new(0, 0, 1)
        local ahead = vector.add(pos, vector.multiply(dir, 0.4))
        local n    = minetest.get_node(ahead)
        local ndef = minetest.registered_nodes[n.name]
        if ndef and ndef.walkable then
            self.object:remove()
            return
        end

        -- Player hit
        for _, obj in ipairs(minetest.get_objects_inside_radius(pos, 0.7)) do
            if obj ~= self.object and obj:is_player() then
                obj:punch(self.object, 1.0, {
                    full_punch_interval = 1.0,
                    damage_groups = { fleshy = DART_DAMAGE },
                })
                self.object:remove()
                return
            end
        end
    end,
})

minetest.register_node("shinobi_no_satori:dart_wall", {
    description = "Dart Trap Wall",
    -- Tile order: top, bottom, X+, X-, Z- (back), Z+ (front/dart exit)
    -- tile[6] = Z+ = the face the dart exits from when facedir_to_dir gives +Z
    tiles = {
        "shinobi_dart_wall_top.png",   -- 1: top
        "shinobi_dart_wall_top.png",   -- 2: bottom
        "shinobi_dart_wall_side.png",  -- 3: X+
        "shinobi_dart_wall_side.png",  -- 4: X-
        "shinobi_dart_wall_side.png",  -- 5: Z- (back)
        "shinobi_dart_wall_side.png", -- 6: Z+ (front, dart exits here)
    },
    paramtype2 = "facedir",
    groups = { cracky = 2 },
    sounds = default.node_sound_stone_defaults(),

    on_construct = function(pos)
        minetest.get_node_timer(pos):start(DART_INTERVAL)
    end,

    on_timer = function(pos, elapsed)
        if minetest.get_node(pos).name ~= "shinobi_no_satori:dart_wall" then
            return false
        end

        local node      = minetest.get_node(pos)
        local dir       = minetest.facedir_to_dir(node.param2)
        local spawn_pos = vector.add(pos, dir)

        -- Only spawn if the space in front is clear
        local sn  = minetest.get_node(spawn_pos)
        local snd = minetest.registered_nodes[sn.name]
        if snd and not snd.walkable then
            local obj = minetest.add_entity(spawn_pos, "shinobi_no_satori:dart")
            if obj then
                local lua = obj:get_luaentity()
                if lua then lua._dir = dir end
                obj:set_velocity(vector.multiply(dir, DART_SPEED))
                obj:set_rotation(vector.new(0, math.atan2(-dir.x, -dir.z), 0))
            end

            minetest.sound_play("shinobi_shuriken_throw", {
                pos = pos, gain = 0.4, max_hear_distance = 20,
            }, true)
        end

        return true  -- reschedule with same interval
    end,
})

-- ============================================================
-- 4. Sand Ceiling Trigger
-- Invisible node placed at ceiling level.
-- When a player approaches from below, sand falls downward
-- filling the corridor — creating a wall only the Headwear of
-- Shinobi (wall-walk) can pass through.
-- ============================================================
minetest.register_node("shinobi_no_satori:sand_trigger", {
    description     = "Sand Trap Trigger (place on ceiling)",
    drawtype        = "airlike",
    paramtype       = "light",
    sunlight_propagates = true,
    walkable        = false,
    pointable       = false,  -- pointable so admins can remove it
    diggable        = true,
    buildable_to    = false,
    groups          = { not_in_creative_inventory = 1 },
    inventory_image = "shinobi_sand_trigger_inv.png",
})

local sand_triggered = {}  -- position hash → true

minetest.register_abm({
    label     = "Sand ceiling trap trigger",
    nodenames = { "shinobi_no_satori:sand_trigger" },
    interval  = 0.5,
    chance    = 1,
    action    = function(pos, node)
        local hash = minetest.hash_node_position(pos)
        if sand_triggered[hash] then return end

        local nearby = minetest.get_objects_inside_radius(pos, 5)
        for _, obj in ipairs(nearby) do
            if obj:is_player() then
                local ppos = obj:get_pos()
                if ppos and ppos.y <= pos.y then
                    local dx = ppos.x - pos.x
                    local dz = ppos.z - pos.z
                    if dx*dx + dz*dz <= 16 then   -- within 4 blocks horizontally
                        sand_triggered[hash] = true

                        -- Drop sand downward, one block at a time for visual effect
                        local function drop_next(p)
                            if pos.y - p.y > 20 then return end
                            local n    = minetest.get_node(p)
                            local ndef = minetest.registered_nodes[n.name]
                            if not ndef or ndef.walkable then return end  -- hit the floor
                            minetest.set_node(p, { name = "default:sand" })
                            minetest.after(0.05, drop_next, vector.new(p.x, p.y - 1, p.z))
                        end

                        -- Brief delay before first block so the player sees it coming
                        minetest.after(0.3, drop_next, vector.new(pos.x, pos.y - 1, pos.z))

                        minetest.sound_play("default_sand_footstep", {
                            pos = pos, gain = 1.2, max_hear_distance = 24,
                        }, true)
                    end
                end
                break
            end
        end
    end,
})

-- ============================================================
-- 5. Dungeon Zone Marker
-- Invisible node placed throughout the dungeon (walls, floor,
-- ceiling). Any player inside the zone has fly and noclip
-- privileges temporarily revoked; they are restored on exit.
-- ============================================================
minetest.register_node("shinobi_no_satori:dungeon_zone", {
    description     = "Dungeon Zone Marker (invisible, no-fly)",
    drawtype        = "airlike",
    paramtype       = "light",
    sunlight_propagates = true,
    walkable        = false,
    pointable       = false,
    diggable        = true,
    buildable_to    = false,
    groups          = { not_in_creative_inventory = 1 },
    inventory_image = "shinobi_dungeon_zone_inv.png",
})

local suspended_privs = {}   -- player_name → { fly=bool, noclip=bool } or {} if none to revoke
local dungeon_timer   = 0

minetest.register_globalstep(function(dtime)
    dungeon_timer = dungeon_timer + dtime
    if dungeon_timer < 0.5 then return end
    dungeon_timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos  = player:get_pos()
        if not pos then goto continue end

        local in_dungeon = minetest.find_node_near(
            pos, 8, { "shinobi_no_satori:dungeon_zone" }) ~= nil

        if in_dungeon and not suspended_privs[name] then
            local privs = minetest.get_player_privs(name)
            if privs.fly or privs.noclip then
                suspended_privs[name] = {
                    fly    = privs.fly    or false,
                    noclip = privs.noclip or false,
                }
                privs.fly    = nil
                privs.noclip = nil
                minetest.set_player_privs(name, privs)
                minetest.chat_send_player(name, minetest.colorize(
                    "#ffcc00", "[Dungeon] Flight is sealed within these walls. Face them with honour."))
            else
                suspended_privs[name] = {}  -- mark as inside, nothing to restore
            end

        elseif not in_dungeon and suspended_privs[name] then
            local saved = suspended_privs[name]
            suspended_privs[name] = nil
            if saved.fly or saved.noclip then
                local privs = minetest.get_player_privs(name)
                if saved.fly    then privs.fly    = true end
                if saved.noclip then privs.noclip = true end
                minetest.set_player_privs(name, privs)
                minetest.chat_send_player(name, minetest.colorize(
                    "#aaffaa", "[Dungeon] You have left the dungeon. Flight restored."))
            end
        end

        ::continue::
    end
end)

-- Restore privs if the player disconnects inside the dungeon
minetest.register_on_leaveplayer(function(player)
    local name  = player:get_player_name()
    local saved = suspended_privs[name]
    if saved and (saved.fly or saved.noclip) then
        local privs = minetest.get_player_privs(name)
        if saved.fly    then privs.fly    = true end
        if saved.noclip then privs.noclip = true end
        minetest.set_player_privs(name, privs)
    end
    suspended_privs[name] = nil
end)

-- ============================================================
-- 6. Dungeon Progress Persistence
-- ============================================================
local dungeon_progress_file = minetest.get_worldpath() .. "/shinobi_dungeon_progress.json"
local dungeon_data = {}

local function save_dungeon_progress()
    local file = io.open(dungeon_progress_file, "w")
    if file then
        local j = minetest.write_json(dungeon_data)
        file:write(j and j ~= "null" and j or "{}")
        file:close()
    end
end

local function load_dungeon_progress()
    local file = io.open(dungeon_progress_file, "r")
    if file then
        local raw = file:read("*a")
        file:close()
        if raw and raw ~= "" and raw ~= "null" then
            local ok, parsed = pcall(minetest.parse_json, raw)
            if ok and type(parsed) == "table" then
                dungeon_data = parsed
            end
        end
    end
    -- Populate global title table
    for name, d in pairs(dungeon_data) do
        if type(d) == "table" and d.rank then
            shinobi_player_titles[name] = d.rank
        end
    end
end

load_dungeon_progress()

-- ============================================================
-- 6.5 Dungeon Spawning & Entry
-- /dungeon  — places shinobi_dungeon.mts 100 blocks underground
-- under the player (once per player), then teleports to the entrance.
-- Subsequent calls just re-teleport to the same dungeon.
-- ============================================================
local modpath_d    = minetest.get_modpath("shinobi_no_satori")
local DUNGEON_SCHEM = modpath_d .. "/schems/shinobi_dungeon.mts"
local DUNGEON_DEPTH = 100   -- blocks below player feet to dungeon top

-- Read .mts binary header to get schematic dimensions.
-- Header layout: "MTSM"(4) + version(u16) + size_x(u16) + size_y(u16) + size_z(u16)
local function read_mts_size(filepath)
    local f = io.open(filepath, "rb")
    if not f then return nil end
    local h = f:read(12)
    f:close()
    if not h or #h < 12 then return nil end
    if h:sub(1, 4) ~= "MTSM" then return nil end
    local function u16(i) return h:byte(i) * 256 + h:byte(i + 1) end
    return { x = u16(7), y = u16(9), z = u16(11) }
end

local DUNG_SIZE = read_mts_size(DUNGEON_SCHEM)
if DUNG_SIZE then
    minetest.log("action", ("[shinobi_no_satori] Dungeon schematic: %dx%dx%d"):format(
        DUNG_SIZE.x, DUNG_SIZE.y, DUNG_SIZE.z))
else
    minetest.log("warning", "[shinobi_no_satori] Could not read dungeon schematic size!")
end

-- Scan all four outer-wall centre columns for the entrance.
-- Returns the first position where the edge cell is passable for 2 blocks
-- above a solid floor — i.e. a door/opening at the schematic boundary.
local function find_dungeon_entrance(sp, sz)
    local W, H, D = sz.x, sz.y, sz.z
    local cx = sp.x + math.floor(W / 2)
    local cz = sp.z + math.floor(D / 2)

    -- Four wall-centre columns; try all to find whichever has an opening.
    local cols = {
        { x = cx,         z = sp.z       },   -- front wall
        { x = cx,         z = sp.z + D-1 },   -- back wall
        { x = sp.x,       z = cz         },   -- left wall
        { x = sp.x + W-1, z = cz         },   -- right wall
    }

    local function solid(p)
        local nd = minetest.registered_nodes[minetest.get_node(p).name]
        return not nd or nd.walkable ~= false
    end
    local function open(p)
        local nd = minetest.registered_nodes[minetest.get_node(p).name]
        return nd and nd.walkable == false
    end

    for _, col in ipairs(cols) do
        for dy = 1, H - 2 do
            local yb = sp.y + dy - 1
            local yf = sp.y + dy
            local yh = sp.y + dy + 1
            if solid({ x = col.x, y = yb, z = col.z })
            and open ({ x = col.x, y = yf, z = col.z })
            and open ({ x = col.x, y = yh, z = col.z }) then
                return { x = col.x, y = yf, z = col.z }
            end
        end
    end
    return nil
end

local function load_dungeon_area(sp, sz)
    minetest.load_area(
        { x = sp.x - 5,       y = sp.y - 5,       z = sp.z - 5 },
        { x = sp.x + sz.x + 5, y = sp.y + sz.y + 5, z = sp.z + sz.z + 5 }
    )
end

local function teleport_to_dungeon(player, sp, sz, announce)
    minetest.after(0.5, function()
        local p = minetest.get_player_by_name(player:get_player_name())
        if not p then return end
        local name = p:get_player_name()

        local entrance = find_dungeon_entrance(sp, sz)
        local tp_pos
        if entrance then
            tp_pos = entrance
        else
            -- Fallback: horizontal centre, 2 blocks above schematic floor
            tp_pos = { x = sp.x + math.floor(sz.x / 2), y = sp.y + 2,
                       z = sp.z + math.floor(sz.z / 2) }
            minetest.log("warning", "[shinobi_no_satori] Entrance scan found nothing for "
                .. name .. " — using centre fallback at " .. minetest.pos_to_string(tp_pos))
        end

        p:set_pos(tp_pos)

        if announce then
            local hid = p:hud_add({
                type      = "text",
                position  = { x = 0.5, y = 0.5 },
                text      = "The dungeon awaits...\nFace its trials with honour.",
                number    = 0x4FC3F7,
                scale     = { x = 100, y = 20 },
                alignment = { x = 0, y = 0 },
            })
            minetest.after(4, function(pn, h)
                local pl = minetest.get_player_by_name(pn)
                if pl then pl:hud_remove(h) end
            end, name, hid)
        else
            minetest.chat_send_player(name, minetest.colorize(
                "#ffcc00", "[Dungeon] You descend once more into the shadows..."))
        end

        minetest.log("action", ("[shinobi_no_satori] %s teleported to dungeon entrance %s"):format(
            name, minetest.pos_to_string(tp_pos)))
    end)
end

local function enter_dungeon(player)
    local name  = player:get_player_name()
    local pdata = dungeon_data[name]

    -- Already placed — just teleport back in.
    if pdata and pdata.structure_pos and DUNG_SIZE then
        local sp = pdata.structure_pos
        load_dungeon_area(sp, DUNG_SIZE)
        teleport_to_dungeon(player, sp, DUNG_SIZE, false)
        return
    end

    if not DUNG_SIZE then
        minetest.chat_send_player(name,
            minetest.colorize("#ff4444", "[Dungeon] Could not read schematic — tell an admin."))
        return
    end

    local ppos = player:get_pos()
    local W, H, D = DUNG_SIZE.x, DUNG_SIZE.y, DUNG_SIZE.z

    -- Centre schematic under the player; align to 16-block chunks.
    local sp = {
        x = math.floor((ppos.x - W / 2) / 16) * 16,
        y = math.floor(ppos.y) - DUNGEON_DEPTH - H,
        z = math.floor((ppos.z - D / 2) / 16) * 16,
    }

    minetest.place_schematic(sp, DUNGEON_SCHEM, "0", nil, true)
    load_dungeon_area(sp, DUNG_SIZE)

    dungeon_data[name]               = dungeon_data[name] or {}
    dungeon_data[name].structure_pos = { x = sp.x, y = sp.y, z = sp.z }
    save_dungeon_progress()

    minetest.log("action", ("[shinobi_no_satori] Dungeon placed for %s at %s"):format(
        name, minetest.pos_to_string(sp)))

    teleport_to_dungeon(player, sp, DUNG_SIZE, true)
end

minetest.register_chatcommand("dungeon", {
    description = "Enter the Shinobi Dungeon (spawned 100 m underground on first use)",
    func = function(name, _)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found." end
        enter_dungeon(player)
        return true
    end,
})

-- ============================================================
-- 7. Dungeon Reward Chest
-- Same appearance as the arena quest chest.
-- Each player may claim the reward exactly once.
-- ============================================================
local DUNGEON_RANK  = "Jonin"
local DUNGEON_ITEMS = {
    { name = "shinobi_no_satori:fire_shuriken",      count = 50 },
    { name = "shinobi_no_satori:ice_shuriken",       count = 50 },
    { name = "shinobi_no_satori:lightning_shuriken", count = 50 },
    { name = "shinobi_no_satori:elite_chestplate",   count = 1  },
    { name = "shinobi_no_satori:elite_headwear",     count = 1  },
    { name = "shinobi_no_satori:elite_hakama",       count = 1  },
}

local function give_or_drop(player, item_name, count)
    local stack = ItemStack({ name = item_name, count = count })
    local inv   = player:get_inventory()
    if inv:room_for_item("main", stack) then
        inv:add_item("main", stack)
    else
        minetest.item_drop(stack, nil, player:get_pos())
    end
end

local armour_colour = minetest.settings:get("shinobi_armour_colour") or "cyan"

minetest.register_node("shinobi_no_satori:dungeon_chest", {
    description = "Dungeon Reward Chest",
    drawtype    = "nodebox",
    stack_max   = 1,
    node_box    = { type = "fixed", fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 } },
    tiles = {
        "shinobi_quest_chest_top.png",
        "shinobi_quest_chest_side.png", "shinobi_quest_chest_side.png",
        "shinobi_quest_chest_side.png", "shinobi_quest_chest_side.png",
        "shinobi_quest_chest_front.png",
    },
    paramtype2 = "facedir",
    groups     = { choppy = 2, oddly_breakable_by_hand = 1 },

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local pname = clicker:get_player_name()
        local pdata = dungeon_data[pname]

        if pdata and pdata.chest_claimed then
            minetest.chat_send_player(pname, minetest.colorize(
                "#aaaaaa", "[Dungeon] You have already claimed this reward, " .. DUNGEON_RANK .. "."))
            return
        end

        -- Record claim
        dungeon_data[pname] = dungeon_data[pname] or {}
        dungeon_data[pname].chest_claimed = true
        dungeon_data[pname].rank          = DUNGEON_RANK
        shinobi_player_titles[pname]      = DUNGEON_RANK
        save_dungeon_progress()

        -- Set ranked nametag immediately
        clicker:set_nametag_attributes({
            text    = minetest.colorize("#FFD700", "[" .. DUNGEON_RANK .. "]") .. " " .. pname,
            bgcolor = false,
        })

        -- Give all rewards
        for _, r in ipairs(DUNGEON_ITEMS) do
            give_or_drop(clicker, r.name, r.count)
        end

        -- Formspec
        local fs = "formspec_version[4]size[10,8]"
            .. "bgcolor[#00000000;false]"
            .. "box[0,0;10,8;#1a1200EE]"
            .. "box[0,0;10,0.06;#FFD700FF]box[0,7.94;10,0.06;#FFD700FF]"
            .. "box[0,0;0.06,8;#FFD700FF]box[9.94,0;0.06,8;#FFD700FF]"
            .. "image[0.3,0.8;3.5,3.5;shinobi_chestplate_inv_" .. armour_colour .. ".png]"
            .. "style_type[label;font_size=*1.4;textcolor=#FFD700]"
            .. "label[4.2,0.5;— Trial Concluded —]"
            .. "style_type[label;font_size=*1.05;textcolor=#FFF9C4]"
            .. "label[4.2,1.2;You have endured the shadows,]"
            .. "label[4.2,1.8;survived what none expected,]"
            .. "label[4.2,2.4;and emerged unbroken.]"
            .. "style_type[label;font_size=*1;textcolor=#CFD8DC]"
            .. "label[4.2,3.2;§ 50 × Fire Shuriken]"
            .. "label[4.2,3.75;§ 50 × Ice Shuriken]"
            .. "label[4.2,4.3;§ 50 × Lightning Shuriken]"
            .. "label[4.2,4.85;§ Elite Armour of Shinobi (full set)]"
            .. "style_type[label;font_size=*1.25;textcolor=#FFD700]"
            .. "label[4.2,5.7;Rank granted: JONIN]"
            .. "style[close_btn;bgcolor=#FFD700;textcolor=#1a1200;border=false]"
            .. "button[7.3,7.2;2.3,0.55;close_btn;Close]"
        minetest.show_formspec(pname, "shinobi_no_satori:dungeon_reward", fs)

        minetest.log("action", "[shinobi_no_satori] " .. pname
            .. " claimed dungeon reward → rank " .. DUNGEON_RANK)
    end,
})

-- ============================================================
-- Restore ranked nametag on join
-- ============================================================
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    -- Delay so armor on_equip fires first (it may hide the nametag for full-set bonus)
    minetest.after(2.5, function()
        local p = minetest.get_player_by_name(name)
        if not p then return end
        local d = dungeon_data[name]
        if d and d.rank then
            shinobi_player_titles[name] = d.rank
            -- Only set if the nametag is currently showing the plain name
            -- (full-set bonus sets it to "", so we don't override that)
            local attrs = p:get_nametag_attributes()
            if attrs and attrs.text ~= "" then
                p:set_nametag_attributes({
                    text    = minetest.colorize("#FFD700", "[" .. d.rank .. "]") .. " " .. name,
                    bgcolor = false,
                })
            end
        end
    end)
end)

minetest.log("action", "[shinobi_no_satori] Dungeon traps loaded")
