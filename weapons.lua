-- Shinobi no Satori – Weapons
-- Fire Shuriken: throwing star that ignites enemies
-- Ice  Shuriken: throwing star that freezes enemies
--   Flight mode is controlled by the 'shinobi_shuriken_mode' setting:
--   • "drop"   — (default) sticks in a wall for ~2 s then drops as item;
--              or falls to the ground if range is reached in mid-air
--   • "return" — boomerang: curves back and returns to the thrower's inventory

local S = minetest.settings

-- ============================================================
-- Settings
-- ============================================================
local SHURIKEN_SPEED       = tonumber(S:get("shinobi_shuriken_speed"))       or 22
local SHURIKEN_RANGE       = tonumber(S:get("shinobi_shuriken_range"))       or 18
local SHURIKEN_DAMAGE      = tonumber(S:get("shinobi_shuriken_damage"))      or 6
local SHURIKEN_FREEZE_TIME = tonumber(S:get("shinobi_shuriken_freeze_time")) or 3.0
local SHURIKEN_BURN_TIME   = tonumber(S:get("shinobi_shuriken_burn_time"))   or 4.0
local SHURIKEN_HIT_RADIUS  = tonumber(S:get("shinobi_shuriken_hit_radius")) or 1.8
local SHURIKEN_COOLDOWN    = tonumber(S:get("shinobi_shuriken_cooldown"))    or 1.0
local SHURIKEN_MODE        = S:get("shinobi_shuriken_mode") or "drop"

-- ============================================================
-- Ice block visual entity
-- ============================================================
minetest.register_entity("shinobi_no_satori:ice_block", {
    initial_properties = {
        visual              = "cube",
        textures            = {
            "shinobi_ice_ent.png", "shinobi_ice_ent.png",
            "shinobi_ice_ent.png", "shinobi_ice_ent.png",
            "shinobi_ice_ent.png", "shinobi_ice_ent.png",
        },
        visual_size         = { x = 1, y = 2 },
        physical            = false,
        collide_with_objects = false,
        pointable           = false,
        static_save         = false,
        use_texture_alpha   = true,
        glow                = 8,
    },
    _target     = nil,   -- ObjectRef of the frozen entity
    _center_y   = 0,     -- Y offset from target origin to block center

    on_step = function(self, dtime)
        -- Ice block stays put; just self-destruct if target is gone
        -- (unfreeze_entity handles clean removal, this is a safety net)
        if not self._target or not self._target:get_pos() then
            self.object:remove()
        end
    end,
})

-- ============================================================
-- Frozen-entity management
-- ============================================================
-- Stores original physics / velocity so we can restore them later.
local frozen_entities = {}   -- objref hash → { timer, glow, obj, ice_ent }

local ZERO_VEL = { x = 0, y = 0, z = 0 }

local function freeze_entity(obj)
    local id = obj:get_luaentity() and tostring(obj:get_luaentity()) or tostring(obj)

    -- Already frozen: damage was already dealt by the caller, nothing else to do
    if frozen_entities[id] then
        return
    end

    local props = obj:get_properties()
    local glow  = props.glow or 0

    obj:set_properties({ glow = 12 })
    obj:set_velocity(ZERO_VEL)

    -- Pause AI (creatura / mobs_redo)
    local lua = obj:get_luaentity()
    if lua then
        if lua._movement_data then
            lua._frozen_by_shuriken = true
        end
        if lua.state then
            lua._old_state = lua.state
            lua.state      = "stand"
        end
        if lua.set_velocity then
            lua._old_set_velocity = lua.set_velocity
            lua.set_velocity      = function() end
        end
    end

    -- ---- Spawn ice-block entity sized to this entity's collisionbox ----
    local cb       = props.collisionbox or { -0.5, 0, -0.5, 0.5, 1.8, 0.5 }
    local w        = (cb[4] - cb[1])
    local h        = (cb[5] - cb[2])
    local d        = (cb[6] - cb[3])
    local vs_x     = math.max(w, d) * 1.05
    local vs_y     = h               * 1.05
    local center_y = (cb[2] + cb[5]) / 2

    local opos    = obj:get_pos()
    local ice_ent = minetest.add_entity(
        { x = opos.x, y = opos.y + center_y, z = opos.z },
        "shinobi_no_satori:ice_block"
    )
    if ice_ent then
        local ie = ice_ent:get_luaentity()
        if ie then
            ie._target   = obj
            ie._center_y = center_y
        end
        ice_ent:set_properties({ visual_size = { x = vs_x, y = vs_y } })

        -- Attach the ice block TO the mob (mob = parent) so the block follows
        -- the mob without inheriting/distorting its visual_size.
        -- Offset +center_y moves the block up to the collisionbox centre.
        ice_ent:set_attach(obj, "", { x = 0, y = center_y * 10, z = 0 }, { x = 0, y = 0, z = 0 })
    end

    minetest.sound_play("shinobi_freeze", {
        pos              = opos,
        gain             = 1.0,
        max_hear_distance = 16,
    }, true)

    frozen_entities[id] = {
        obj     = obj,
        timer   = SHURIKEN_FREEZE_TIME,
        glow    = glow,
        ice_ent = ice_ent,
    }
end

local function unfreeze_entity(id, data)
    local obj = data.obj

    -- Detach and remove ice block (it is a child of the mob)
    if data.ice_ent and data.ice_ent:get_pos() then
        data.ice_ent:set_detach()
        data.ice_ent:remove()
    end

    if not obj or not obj:get_pos() then
        frozen_entities[id] = nil
        return
    end

    obj:set_properties({ glow = data.glow })

    local lua = obj:get_luaentity()
    if lua then
        lua._frozen_by_shuriken = nil
        if lua._old_state then
            lua.state      = lua._old_state
            lua._old_state = nil
        end
        if lua._old_set_velocity then
            lua.set_velocity      = lua._old_set_velocity
            lua._old_set_velocity = nil
        end
    end

    frozen_entities[id] = nil
end

-- Tick frozen timers; also keep velocity locked while frozen
minetest.register_globalstep(function(dtime)
    for id, data in pairs(frozen_entities) do
        data.timer = data.timer - dtime

        local obj = data.obj
        if obj and obj:get_pos() then
            obj:set_velocity(ZERO_VEL)
        end

        if data.timer <= 0 then
            unfreeze_entity(id, data)
        end
    end
end)

-- ============================================================
-- Burn helper
-- ============================================================
local function ignite_entity(obj)
    if not obj or not obj:get_pos() then return end

    -- Try mcl_burning first (MineClone)
    if minetest.global_exists("mcl_burning") and mcl_burning.set_on_fire then
        mcl_burning.set_on_fire(obj, SHURIKEN_BURN_TIME)
        return
    end

    -- Fallback: manual fire damage over time
    local lua = obj:get_luaentity()
    local id  = lua and tostring(lua) or tostring(obj)

    -- Avoid stacking burn
    if lua and lua._shuriken_burning then return end
    if lua then lua._shuriken_burning = true end

    local elapsed = 0
    local timer_func
    timer_func = function()
        elapsed = elapsed + 1.0
        if elapsed > SHURIKEN_BURN_TIME then
            if lua then lua._shuriken_burning = nil end
            return
        end
        if not obj:get_pos() then
            if lua then lua._shuriken_burning = nil end
            return
        end

        -- 1 HP fire damage per second
        obj:punch(obj, 1.0, {
            full_punch_interval = 1.0,
            damage_groups = { fleshy = 2, fire = 2 },
        })

        -- Fire particles
        local pos = obj:get_pos()
        if pos then
            minetest.add_particlespawner({
                amount   = 6,
                time     = 0.5,
                minpos   = vector.add(pos, vector.new(-0.3, 0, -0.3)),
                maxpos   = vector.add(pos, vector.new(0.3, 1.2, 0.3)),
                minvel   = vector.new(-0.2, 0.5, -0.2),
                maxvel   = vector.new(0.2, 1.5, 0.2),
                minacc   = vector.new(0, 0.3, 0),
                maxacc   = vector.new(0, 0.6, 0),
                minexptime = 0.3,
                maxexptime = 0.8,
                minsize  = 1.0,
                maxsize  = 2.5,
                texture  = "shinobi_fire_particle.png",
                glow     = 14,
            })
        end

        minetest.after(1.0, timer_func)
    end

    minetest.after(1.0, timer_func)
end

-- ============================================================
-- Hit tracker — avoid hitting the same entity twice per throw
-- ============================================================
local function make_hit_set()
    local set = {}
    return {
        has  = function(obj) return set[tostring(obj)] ~= nil end,
        add  = function(obj) set[tostring(obj)] = true end,
    }
end

-- ============================================================
-- Fire Shuriken entity  (burn only, no freeze)
-- ============================================================
minetest.register_entity("shinobi_no_satori:fire_shuriken", {
    initial_properties = {
        visual            = "upright_sprite",
        textures           = { "shinobi_fire_shuriken.png" },
        visual_size        = { x = 0.5, y = 0.5 },
        physical           = false,
        collide_with_objects = false,
        pointable          = false,
        static_save        = false,
        glow               = 10,
    },

    _thrower     = nil,   -- player ObjectRef
    _origin      = nil,   -- launch position
    _dir         = nil,   -- initial direction (normalised)
    _dist        = 0,     -- distance travelled so far
    _returning   = false, -- true once we passed the apex ("return" mode only)
    _stopped     = false, -- true once shuriken is embedded/dropped
    _hit_wall    = false, -- true if stopped by hitting a wall (vs. range reached mid-air)
    _stop_timer  = 0,     -- time since stopping
    _hit_set     = nil,   -- already-hit entities
    _age         = 0,
    _spin        = 0,     -- visual rotation accumulator

    on_activate = function(self, staticdata, dtime_s)
        self._hit_set = make_hit_set()
    end,

    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then self.object:remove(); return end

        self._age = self._age + dtime

        -- Safety: remove if alive too long (flight only; stopped state has its own timer)
        if not self._stopped and self._age > 8 then
            self.object:remove()
            return
        end

        -- Spin the sprite (only while in flight)
        if not self._stopped then
            self._spin = self._spin + dtime * 12  -- radians/s
            self.object:set_rotation({ x = math.pi/2, y = self._spin, z = 0 })
        end

        -- -------------------------------------------------------
        -- Stopped state ("drop" mode)
        -- -------------------------------------------------------
        if self._stopped then
            self._stop_timer = self._stop_timer + dtime
            if self._hit_wall then
                -- Embedded in wall: stay still, drop as item after 2 s
                self.object:set_velocity(ZERO_VEL)
                if self._stop_timer >= 2.0 then
                    minetest.add_item(pos, ItemStack(self._item_name))
                    self.object:remove()
                end
            else
                -- Mid-air: simulate gravity until landing
                local vel = self.object:get_velocity()
                local new_vy = math.max((vel and vel.y or 0) - 20 * dtime, -20)
                self.object:set_velocity({ x = 0, y = new_vy, z = 0 })
                local node_below = minetest.get_node({ x = pos.x, y = pos.y - 0.6, z = pos.z })
                if minetest.registered_nodes[node_below.name]
                   and minetest.registered_nodes[node_below.name].walkable then
                    minetest.add_item(pos, ItemStack(self._item_name))
                    self.object:remove()
                    return
                end
                -- Safety fallback after 8 s
                if self._stop_timer > 8 then
                    minetest.add_item(pos, ItemStack(self._item_name))
                    self.object:remove()
                end
            end
            return
        end

        -- -------------------------------------------------------
        -- Movement: outward phase → returning phase
        -- -------------------------------------------------------
        local thrower = self._thrower
        if not thrower or not thrower:is_player() then
            self.object:remove()
            return
        end

        if not self._returning then
            -- Fly along initial direction
            self._dist = self._dist + SHURIKEN_SPEED * dtime
            if self._dist >= SHURIKEN_RANGE then
                if SHURIKEN_MODE == "return" then
                    self._returning = true
                else
                    -- Reached max range mid-air: start falling immediately
                    self._stopped  = true
                    self._hit_wall = false
                    self.object:set_velocity({ x = 0, y = -4, z = 0 })
                end
            end
            if not self._stopped then
                self.object:set_velocity(vector.multiply(self._dir, SHURIKEN_SPEED))
            end
        else
            -- Curve back to the thrower
            local tpos = thrower:get_pos()
            if not tpos then self.object:remove(); return end
            tpos.y = tpos.y + 1.2  -- aim at chest height

            local to_player = vector.subtract(tpos, pos)
            local dist_to_player = vector.length(to_player)

            if dist_to_player < 1.5 then
                -- Arrived — return to inventory
                self:_return_to_player()
                return
            end

            local dir = vector.normalize(to_player)
            -- Accelerate a bit when returning for a satisfying snap-back
            local speed = math.min(SHURIKEN_SPEED * 1.4, SHURIKEN_SPEED + dist_to_player * 2)
            self.object:set_velocity(vector.multiply(dir, speed))
        end

        -- -------------------------------------------------------
        -- Entity collision check
        -- -------------------------------------------------------
        local objs = minetest.get_objects_inside_radius(pos, SHURIKEN_HIT_RADIUS)
        for _, obj in ipairs(objs) do
            if obj ~= self.object and obj ~= thrower and not self._hit_set.has(obj) then
                local is_player = obj:is_player()
                local lua = obj:get_luaentity()

                -- Skip other shuriken and non-entity items
                if lua and (lua.name == "shinobi_no_satori:fire_shuriken"
                         or lua.name == "shinobi_no_satori:ice_shuriken") then
                    goto continue
                end
                if lua and lua.name == "__builtin:item" then
                    goto continue
                end
                if lua and lua.name == "__builtin:falling_node" then
                    goto continue
                end

                -- Valid target
                self._hit_set.add(obj)

                -- Deal punch damage
                obj:punch(thrower, 1.0, {
                    full_punch_interval = 1.0,
                    damage_groups = { fleshy = SHURIKEN_DAMAGE },
                }, vector.direction(pos, obj:get_pos()))

                -- Burn only
                ignite_entity(obj)

                -- Fire impact particles
                local opos = obj:get_pos()
                if opos then
                    minetest.add_particlespawner({
                        amount   = 12,
                        time     = 0.2,
                        minpos   = vector.add(opos, vector.new(-0.3, 0, -0.3)),
                        maxpos   = vector.add(opos, vector.new(0.3, 1.5, 0.3)),
                        minvel   = vector.new(-1.5, 0.5, -1.5),
                        maxvel   = vector.new(1.5, 2.5, 1.5),
                        minexptime = 0.3,
                        maxexptime = 0.7,
                        minsize  = 0.8,
                        maxsize  = 2.0,
                        texture  = "shinobi_fire_particle.png",
                        glow     = 14,
                    })
                end

                ::continue::
            end
        end

        -- -------------------------------------------------------
        -- Wall collision
        -- -------------------------------------------------------
        if not self._returning and not self._stopped then
            local vel = self.object:get_velocity()
            if vel then
                local ahead = vector.add(pos, vector.multiply(vector.normalize(vel), 0.5))
                local node  = minetest.get_node(ahead)
                if minetest.registered_nodes[node.name]
                   and minetest.registered_nodes[node.name].walkable then
                    if SHURIKEN_MODE == "return" then
                        self._returning = true
                    else
                        -- Stick into wall
                        self._stopped  = true
                        self._hit_wall = true
                        self.object:set_velocity(ZERO_VEL)
                    end
                end
            end
        end
    end,

    _item_name = "shinobi_no_satori:fire_shuriken",

    _return_to_player = function(self)
        local thrower = self._thrower
        if thrower and thrower:is_player() then
            local inv = thrower:get_inventory()
            local stack = ItemStack(self._item_name)
            if inv and inv:room_for_item("main", stack) then
                inv:add_item("main", stack)
            else
                -- Drop at player's feet if inventory is full
                local tpos = thrower:get_pos()
                if tpos then
                    minetest.add_item(tpos, stack)
                end
            end
        end
        self.object:remove()
    end,
})

-- ============================================================
-- Cooldown tracker
-- ============================================================
local shuriken_cooldown = {} -- player name → timestamp of last throw

-- ============================================================
-- Fire Shuriken item
-- ============================================================
minetest.register_craftitem("shinobi_no_satori:fire_shuriken", {
    description      = "Shuriken of Fire",
    inventory_image  = "shinobi_fire_shuriken_inv.png",
    stack_max        = 20,

    on_use = function(itemstack, player, pointed_thing)
        if not player or not player:is_player() then return end
        local name = player:get_player_name()

        -- Cooldown check
        local now = minetest.get_us_time() / 1e6
        if shuriken_cooldown[name] and (now - shuriken_cooldown[name]) < SHURIKEN_COOLDOWN then
            return
        end
        shuriken_cooldown[name] = now

        local pos = player:get_pos()
        pos.y = pos.y + 1.5  -- throw from head height

        local dir = player:get_look_dir()

        local obj = minetest.add_entity(pos, "shinobi_no_satori:fire_shuriken")
        if not obj then return end

        local lua = obj:get_luaentity()
        lua._thrower  = player
        lua._origin   = vector.new(pos)
        lua._dir      = vector.new(dir)
        lua._dist     = 0
        lua._returning = false

        obj:set_velocity(vector.multiply(dir, SHURIKEN_SPEED))

        -- Throw sound
        minetest.sound_play("shinobi_shuriken_throw", {
            pos    = pos,
            gain   = 0.6,
            max_hear_distance = 16,
        }, true)

        -- Consume from stack
        itemstack:take_item()
        return itemstack
    end,
})

-- ============================================================
-- Ice Shuriken entity  (freeze only, no burn)
-- ============================================================
minetest.register_entity("shinobi_no_satori:ice_shuriken", {
    initial_properties = {
        visual             = "upright_sprite",
        textures           = { "shinobi_ice_shuriken.png" },
        visual_size        = { x = 0.5, y = 0.5 },
        physical           = false,
        collide_with_objects = false,
        pointable          = false,
        static_save        = false,
        glow               = 12,
    },

    _thrower     = nil,
    _origin      = nil,
    _dir         = nil,
    _dist        = 0,
    _returning   = false,
    _stopped     = false, -- true once shuriken is embedded/dropped
    _hit_wall    = false, -- true if stopped by hitting a wall (vs. range reached mid-air)
    _stop_timer  = 0,     -- time since stopping
    _hit_set     = nil,
    _age         = 0,
    _spin        = 0,
    _item_name   = "shinobi_no_satori:ice_shuriken",

    on_activate = function(self, staticdata, dtime_s)
        self._hit_set = make_hit_set()
    end,

    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then self.object:remove(); return end

        self._age = self._age + dtime
        -- Safety: remove if alive too long (flight only; stopped state has its own timer)
        if not self._stopped and self._age > 8 then
            self.object:remove()
            return
        end

        -- Spin the sprite (only while in flight)
        if not self._stopped then
            self._spin = self._spin + dtime * 12
            self.object:set_rotation({ x = math.pi/2, y = self._spin, z = 0 })
        end

        -- -------------------------------------------------------
        -- Stopped state ("drop" mode)
        -- -------------------------------------------------------
        if self._stopped then
            self._stop_timer = self._stop_timer + dtime
            if self._hit_wall then
                -- Embedded in wall: stay still, drop as item after 2 s
                self.object:set_velocity(ZERO_VEL)
                if self._stop_timer >= 2.0 then
                    minetest.add_item(pos, ItemStack(self._item_name))
                    self.object:remove()
                end
            else
                -- Mid-air: simulate gravity until landing
                local vel = self.object:get_velocity()
                local new_vy = math.max((vel and vel.y or 0) - 20 * dtime, -20)
                self.object:set_velocity({ x = 0, y = new_vy, z = 0 })
                local node_below = minetest.get_node({ x = pos.x, y = pos.y - 0.6, z = pos.z })
                if minetest.registered_nodes[node_below.name]
                   and minetest.registered_nodes[node_below.name].walkable then
                    minetest.add_item(pos, ItemStack(self._item_name))
                    self.object:remove()
                    return
                end
                -- Safety fallback after 8 s
                if self._stop_timer > 8 then
                    minetest.add_item(pos, ItemStack(self._item_name))
                    self.object:remove()
                end
            end
            return
        end

        -- -------------------------------------------------------
        -- Movement
        -- -------------------------------------------------------
        local thrower = self._thrower
        if not thrower or not thrower:is_player() then
            self.object:remove()
            return
        end

        if not self._returning then
            self._dist = self._dist + SHURIKEN_SPEED * dtime
            if self._dist >= SHURIKEN_RANGE then
                if SHURIKEN_MODE == "return" then
                    self._returning = true
                else
                    -- Reached max range mid-air: start falling immediately
                    self._stopped  = true
                    self._hit_wall = false
                    self.object:set_velocity({ x = 0, y = -4, z = 0 })
                end
            end
            if not self._stopped then
                self.object:set_velocity(vector.multiply(self._dir, SHURIKEN_SPEED))
            end
        else
            local tpos = thrower:get_pos()
            if not tpos then self.object:remove(); return end
            tpos.y = tpos.y + 1.2

            local to_player = vector.subtract(tpos, pos)
            local dist_to_player = vector.length(to_player)

            if dist_to_player < 1.5 then
                self:_return_to_player()
                return
            end

            local dir = vector.normalize(to_player)
            local speed = math.min(SHURIKEN_SPEED * 1.4, SHURIKEN_SPEED + dist_to_player * 2)
            self.object:set_velocity(vector.multiply(dir, speed))
        end

        -- -------------------------------------------------------
        -- Entity collision — freeze only, NO burn
        -- -------------------------------------------------------
        local objs = minetest.get_objects_inside_radius(pos, SHURIKEN_HIT_RADIUS)
        for _, obj in ipairs(objs) do
            if obj ~= self.object and obj ~= thrower and not self._hit_set.has(obj) then
                local lua = obj:get_luaentity()

                if lua and (lua.name == "shinobi_no_satori:fire_shuriken"
                         or lua.name == "shinobi_no_satori:ice_shuriken") then
                    goto continue
                end
                if lua and lua.name == "__builtin:item" then
                    goto continue
                end
                if lua and lua.name == "__builtin:falling_node" then
                    goto continue
                end

                self._hit_set.add(obj)

                -- Punch damage
                obj:punch(thrower, 1.0, {
                    full_punch_interval = 1.0,
                    damage_groups = { fleshy = SHURIKEN_DAMAGE },
                }, vector.direction(pos, obj:get_pos()))

                -- Freeze only if the punch wasn't lethal
                if obj:get_pos() then
                    freeze_entity(obj)
                end

                -- Icy impact particles
                local opos = obj:get_pos()
                if opos then
                    minetest.add_particlespawner({
                        amount   = 14,
                        time     = 0.25,
                        minpos   = vector.add(opos, vector.new(-0.4, 0, -0.4)),
                        maxpos   = vector.add(opos, vector.new(0.4, 1.6, 0.4)),
                        minvel   = vector.new(-1.2, 0.3, -1.2),
                        maxvel   = vector.new(1.2, 2.0, 1.2),
                        minexptime = 0.4,
                        maxexptime = 0.9,
                        minsize  = 0.6,
                        maxsize  = 1.8,
                        texture  = "shinobi_ice_particle.png",
                        glow     = 12,
                    })
                end

                ::continue::
            end
        end

        -- Wall collision
        if not self._returning and not self._stopped then
            local vel = self.object:get_velocity()
            if vel then
                local ahead = vector.add(pos, vector.multiply(vector.normalize(vel), 0.5))
                local node  = minetest.get_node(ahead)
                if minetest.registered_nodes[node.name]
                   and minetest.registered_nodes[node.name].walkable then
                    if SHURIKEN_MODE == "return" then
                        self._returning = true
                    else
                        -- Stick into wall
                        self._stopped  = true
                        self._hit_wall = true
                        self.object:set_velocity(ZERO_VEL)
                    end
                end
            end
        end
    end,

    _return_to_player = function(self)
        local thrower = self._thrower
        if thrower and thrower:is_player() then
            local inv = thrower:get_inventory()
            local stack = ItemStack(self._item_name)
            if inv and inv:room_for_item("main", stack) then
                inv:add_item("main", stack)
            else
                local tpos = thrower:get_pos()
                if tpos then
                    minetest.add_item(tpos, stack)
                end
            end
        end
        self.object:remove()
    end,
})

-- ============================================================
-- Ice Shuriken item
-- ============================================================
minetest.register_craftitem("shinobi_no_satori:ice_shuriken", {
    description      = "Shuriken of Ice",
    inventory_image  = "shinobi_ice_shuriken_inv.png",
    stack_max        = 20,

    on_use = function(itemstack, player, pointed_thing)
        if not player or not player:is_player() then return end
        local name = player:get_player_name()

        local now = minetest.get_us_time() / 1e6
        if shuriken_cooldown[name] and (now - shuriken_cooldown[name]) < SHURIKEN_COOLDOWN then
            return
        end
        shuriken_cooldown[name] = now

        local pos = player:get_pos()
        pos.y = pos.y + 1.5

        local dir = player:get_look_dir()

        local obj = minetest.add_entity(pos, "shinobi_no_satori:ice_shuriken")
        if not obj then return end

        local lua = obj:get_luaentity()
        lua._thrower   = player
        lua._origin    = vector.new(pos)
        lua._dir       = vector.new(dir)
        lua._dist      = 0
        lua._returning = false

        obj:set_velocity(vector.multiply(dir, SHURIKEN_SPEED))

        minetest.sound_play("shinobi_shuriken_throw", {
            pos    = pos,
            gain   = 0.6,
            max_hear_distance = 16,
        }, true)

        itemstack:take_item()
        return itemstack
    end,
})

minetest.log("action", "[shinobi_no_satori] Shuriken weapons loaded")
