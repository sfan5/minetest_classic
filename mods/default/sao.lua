-- Original references:
-- how it works https://github.com/minetest/minetest/blob/stable-0.3/src/content_sao.cpp
-- how it looks https://github.com/minetest/minetest/blob/stable-0.3/src/content_cao.cpp

--
-- helpers
--

assert(minetest.has_feature("object_step_has_moveresult"))

local gravity = tonumber(minetest.settings:get("movement_gravity")) or 9.81

local function limit_interval(self, prop, dtime, wanted_interval)
	self[prop] = self[prop] + dtime
	if self[prop] < wanted_interval then
		return false
	end
	self[prop] = self[prop] - wanted_interval
	return true
end

-- Y is copied, X and Z change is limited
local function accelerate_xz(vel, target_vel, max_increase)
	local d_wanted = vector.subtract(target_vel, vel)
	d_wanted.y = 0
	local dl = vector.length(d_wanted)
	dl = math.min(dl, max_increase)
	local d = vector.multiply(vector.normalize(d_wanted), dl)
	return vector.new(vel.x + d.x, target_vel.y, vel.z + d.z)
end

local function distance_xz(a, b)
	local x = a.x - b.x
	local z = a.z - b.z
	return math.sqrt(x * x + z * z)
end

local function checkFreePosition(p0, size)
	local nodes = minetest.find_nodes_in_area(p0,
		vector.add(vector.add(p0, size), -1), "air", true)
	if not nodes.air then
		return false
	end
	return #nodes.air == size.x * size.y * size.z
end

local function checkWalkablePosition(p0)
	local node = minetest.get_node(vector.offset(p0, 0, -1, 0))
	return node.name ~= "air"
end

local function checkFreeAndWalkablePosition(p0, size)
	return checkFreePosition(p0, size) and checkWalkablePosition(p0)
end

local function explodeSquare(p0, size)
	-- FIXME: callbacks / indestructability?
	local positions = {}
	for dx = 0, size.x - 1 do
	for dy = 0, size.y - 1 do
	for dz = 0, size.z - 1 do
		positions[#positions+1] = vector.offset(p0, dx, dy, dz)
	end
	end
	end
	minetest.bulk_set_node(positions, {name="air"})
end

--
-- ItemSAO
--

if not default.modernize.new_item_entity then
	minetest.log("warning", "old ItemSAO unimplemented")
end

--
-- RatSAO
--

local RatSAO = {
	initial_properties = {
		physical = true,
		collide_with_objects = false,
		collisionbox = {-1/3, 0, -1/3, 1/3, 2/3, 1/3},
		selectionbox = {-1/3, 0, -1/3, 1/3, 1/2, 1/3},
		visual = "mesh",
		mesh = "rat.obj",
		textures = {"rat.png"},
		backface_culling = false,
	},

	is_active = false,
	inactive_interval = 0,
	oldpos = vector.zero(),
	counter1 = 0,
	counter2 = 0,
	sound_timer = 0,
}

function RatSAO:on_activate(staticdata, dtime_s)
	self.object:set_yaw(math.random(0, 6))
	self.object:set_acceleration(vector.new(0, -gravity, 0))
	self.object:set_armor_groups({punch_operable=1})
end

function RatSAO:on_step(dtime, moveresult)
	if not self.is_active then
		-- FIXME physics are actually turned off if inactive
		if not limit_interval(self, "inactive_interval", dtime, 0.5) then
			return
		end
	end

	-- Move around if some player is close
	local pos = self.object:get_pos()
	self.is_active = false
	for _, player in ipairs(minetest.get_connected_players()) do
		if vector.distance(player:get_pos(), pos) < 10 then
			self.is_active = true
		end
	end

	local vel = self.object:get_velocity()
	if not self.is_active then
		vel.x = 0
		vel.z = 0
	else
		-- Move around
		local yaw = self.object:get_yaw()
		local dir = vector.new(math.cos(yaw), 0, math.sin(yaw))
		local speed = 2
		vel.x = speed * dir.x
		vel.z = speed * dir.z

		if moveresult.touching_ground and vector.distance(self.oldpos, pos)
			< dtime * speed / 2 then
			self.counter1 = self.counter1 - dtime
			if self.counter1 < 0 then
				self.counter1 = self.counter1 + 1
				vel.y = 5
			end
		end

		self.counter2 = self.counter2 - dtime
		if self.counter2 < 0 then
			self.counter2 = self.counter2 + math.random(0, 300) / 100
			self.object:set_yaw(yaw + math.random(-100, 100) / 100 * math.pi)
		end

		self.sound_timer = self.sound_timer - dtime
		if self.sound_timer < 0 then
			if moveresult.touching_ground and default.modernize.sounds then
				minetest.sound_play("rat", {
					pos = pos,
				}, true)
			end
			self.sound_timer = self.sound_timer + 0.1 * math.random(40, 70)
		end
	end
	self.object:set_velocity(vel)

	self.oldpos = pos
end

function RatSAO:on_punch(hitter)
	local item = "default:rat"
	minetest.log("action", hitter:get_player_name() .. " picked up " .. item)
	if not minetest.is_creative_enabled(hitter:get_player_name()) then
		hitter:get_inventory():add_item("main", item)
	end
	self.object:remove()
end

minetest.register_entity("default:rat", RatSAO)

--
-- Oerkki1SAO
--

local Oerkki1SAO = {
	initial_properties = {
		hp_max = 20,
		physical = true,
		collide_with_objects = false,
		collisionbox = {-1/3, 0, -1/3, 1/3, 5/3, 1/3},
		selectionbox = {-1/3, 0, -1/3, 1/3, 2, 1/3},
		visual = "mesh",
		mesh = "oerkki1.obj",
		textures = {"oerkki1.png"},
		backface_culling = false,
		damage_texture_modifier = "^oerkki1_damaged.png", -- we're lucky this works
	},

	is_active = false,
	inactive_interval = 0,
	oldpos = vector.zero(),
	counter1 = 0,
	counter2 = 0,
	age = 0,
	after_jump_timer = 0,
	attack_interval = 0,
	is_hidden = false,
}

function Oerkki1SAO:on_activate(staticdata, dtime_s)
	if core.settings:get("only_peaceful_mobs") then
		self.object:remove()
		return
	end

	self.object:set_acceleration(vector.new(0, -gravity, 0))
	self.object:set_armor_groups({brittle=100})
end

function Oerkki1SAO:on_step(dtime, moveresult)
	if not self.is_active then
		-- FIXME physics are actually turned off if inactive
		if not limit_interval(self, "inactive_interval", dtime, 0.5) then
			return
		end
	end

	self.age = self.age + dtime
	if self.age > 120 then
		self.object:remove()
		return
	end

	self.after_jump_timer = self.after_jump_timer - dtime

	-- Move around if some player is close
	local pos = self.object:get_pos()
	local player_is_close = false
	local player_is_too_close = false
	local near_player_pos
	for _, player in ipairs(minetest.get_connected_players()) do
		local dist = vector.distance(player:get_pos(), pos)
		if dist < 0.6 then
			if not default.modernize.disable_oerkki_delete then
				self.object:remove()
				return
			end
			player_is_too_close = true
			near_player_pos = player:get_pos()
		elseif dist < 15 and not player_is_too_close then
			player_is_close = true
			near_player_pos = player:get_pos()
		end
	end

	self.is_active = player_is_close

	local vel = self.object:get_velocity()
	local target_vel = vector.new(vel)
	if not player_is_close then
		target_vel = vector.zero()
	else
		-- Move around
		local ndir = vector.subtract(near_player_pos, pos)
		ndir.y = 0
		ndir = vector.normalize(ndir)

		local yaw = self.object:get_yaw()
		local nyaw = math.atan2(ndir.z, ndir.x)
		if nyaw < yaw - math.pi then
			nyaw = nyaw + 2 * math.pi
		elseif nyaw > yaw + math.pi then
			nyaw = nyaw - 2 * math.pi
		end
		self.object:set_yaw(0.95*yaw + 0.05*nyaw)
		yaw = nil

		local speed = 2
		if (moveresult.touching_ground or self.after_jump_timer > 0) and not player_is_too_close then
			yaw = self.object:get_yaw()
			local dir = vector.new(math.cos(yaw), 0, math.sin(yaw))
			target_vel.x = speed * dir.x
			target_vel.z = speed * dir.z
		end

		if moveresult.touching_ground and vector.distance(self.oldpos, pos)
			< dtime * speed / 2 then
			self.counter1 = self.counter1 - dtime
			if self.counter1 < 0 then
				self.counter1 = self.counter1 + 0.2
				-- Jump
				target_vel.y = 5
				self.after_jump_timer = 1
			end
		end

		self.counter2 = self.counter2 - dtime
		if self.counter2 < 0 then
			self.counter2 = self.counter2 + math.random(0, 300) / 100
			yaw = self.object:get_yaw()
			self.object:set_yaw(yaw + math.random(-100, 100) / 200 * math.pi)
		end

		-- Damage close players
		local once = true
		for _, player in ipairs(minetest.get_connected_players()) do
			local playerpos = player:get_pos()
			if math.abs(pos.y - playerpos.y) < 1.5 and
				distance_xz(pos, playerpos) < 1.5 then
				if once and not limit_interval(self, "attack_interval", dtime, 0.5) then
					break
				end
				once = false
				player:set_hp(player:get_hp() - 2)
			end
		end

		-- Disappear at low light levels
		local hidden = minetest.get_node_light(vector.round(pos)) <= 2
		if self.is_hidden ~= hidden then
			self.object:set_properties({is_visible = not hidden})
			self.is_hidden = hidden
		end
	end

	if vector.distance(vel, target_vel) > 4 or player_is_too_close then
		self.object:set_velocity(accelerate_xz(vel, target_vel, dtime * 8))
	else
		self.object:set_velocity(accelerate_xz(vel, target_vel, dtime * 4))
	end

	self.oldpos = pos

	-- Do collision damage
	if moveresult.collides and #moveresult.collisions > 0 then
		local tolerance = 30
		local factor = 0.5
		local speed_diff = vector.subtract(moveresult.collisions[1].old_velocity,
			moveresult.collisions[#moveresult.collisions].new_velocity)
		-- Increase effect in X and Z
		speed_diff.x = speed_diff.x * 2
		speed_diff.z = speed_diff.z * 2
		local l = vector.length(speed_diff)
		if l > tolerance then
			local damage = math.round((l - tolerance) * factor)
			self.object:set_hp(self.object:get_hp() - damage)
		end
	end
end

function Oerkki1SAO:on_punch(hitter, time_from_last_punch)
	if (time_from_last_punch or 0) <= 0.5 then
		return true
	end

	local dir = vector.subtract(self.object:get_pos(), hitter:get_pos())
	dir = vector.normalize(dir)
	self.object:set_velocity(vector.add(self.object:get_velocity(),
		vector.multiply(dir, 12)))
end

minetest.register_entity("default:oerkki1", Oerkki1SAO)

--
-- FireflySAO
--

local FireflySAO = {
	initial_properties = {
		physical = true,
		collide_with_objects = false,
		collisionbox = {-1/3, -2/3, -1/3, 1/3, 4/3, 1/3},
		selectionbox = {-1/3, 0, -1/3, 1/3, 1/2, 1/3},
		visual = "mesh",
		mesh = "firefly.obj",
		textures = {"firefly.png"},
		backface_culling = false,
		glow = minetest.LIGHT_MAX,
	},

	is_active = false,
	inactive_interval = 0,
	oldpos = vector.zero(),
	counter1 = 0,
	counter2 = 0,
}

function FireflySAO:on_activate(staticdata, dtime_s)
	-- Apply (less) gravity
	self.object:set_acceleration(vector.new(0, -3, 0))
	self.object:set_armor_groups({punch_operable=1})
end

function FireflySAO:on_step(dtime, moveresult)
	if not self.is_active then
		-- FIXME physics are actually turned off if inactive
		if not limit_interval(self, "inactive_interval", dtime, 0.5) then
			return
		end
	end

	-- Move around if some player is close
	local pos = self.object:get_pos()
	self.is_active = false
	for _, player in ipairs(minetest.get_connected_players()) do
		if vector.distance(player:get_pos(), pos) < 10 then
			self.is_active = true
		end
	end

	local vel = self.object:get_velocity()
	if not self.is_active then
		vel.x = 0
		vel.z = 0
	else
		-- Move around
		local yaw = self.object:get_yaw()
		local dir = vector.new(math.cos(yaw), 0, math.sin(yaw))
		local speed = 0.5
		vel.x = speed * dir.x
		vel.z = speed * dir.z

		if moveresult.touching_ground and vector.distance(self.oldpos, pos)
			< dtime * speed / 2 then
			self.counter1 = self.counter1 - dtime
			if self.counter1 < 0 then
				self.counter1 = self.counter1 + 1
				vel.y = 5
			end
		end

		self.counter2 = self.counter2 - dtime
		if self.counter2 < 0 then
			self.counter2 = self.counter2 + math.random(0, 300) / 100
			self.object:set_yaw(yaw + math.random(-100, 100) / 100 * math.pi)
		end
	end
	self.object:set_velocity(vel)

	self.oldpos = pos
end

function FireflySAO:on_punch(hitter)
	local item = "default:firefly"
	minetest.log("action", hitter:get_player_name() .. " picked up " .. item)
	if not minetest.is_creative_enabled(hitter:get_player_name()) then
		hitter:get_inventory():add_item("main", item)
	end
	self.object:remove()
end

minetest.register_entity("default:firefly", FireflySAO)

--
-- MobV2SAO
--

local MobV2SAO = {
	initial_properties = {
		physical = false,
		visual = "sprite",
		damage_texture_modifier = "^[colorize:#ff0000",
	},

	props = nil,
	random_disturb_timer = 0,
	disturbing_player = "",
	disturb_timer = 0,
	falling = false,
	shooting_timer = 0,
	shooting = false,
	shoot_reload_timer = 0,
	shoot_y = 0, -- not the same as props.shoot_y
	next_pos = nil,
	walk_around_timer = 0,
	walk_around = false,
	--
	sprite_type = "",
	sprite_y = 0,
	walking = false,
	walking_unset_timer = 0,
	last_sprite_row = -1,
	bright_shooting = false,
	player_hit_timer = 0,
}

local MobV2SAO_props = { -- defaults
	is_peaceful = false,
	move_type = "ground_nodes",
	age = 0,
	die_age = -1,
	size = {x = 1, y = 2},
	shoot_type = "fireball",
	shoot_y = 0,
	mindless_rage = false,
	--
	looks = "dummy_default",
	player_hit_damage = 0,
	player_hit_distance = 1.5,
	player_hit_interval = 1.5,
}

-- !(dx == 0 && dy == 0) && !(dx != 0 && dz != 0 && dy != 0)
local MobV2SAO_dps = {
	{x=-1,y=-1,z=0}, {x=-1,y=0,z=-1}, {x=-1,y=0,z=0},
	{x=-1,y=0,z=1},  {x=-1,y=1,z=0},  {x=0,y=-1,z=-1},
	{x=0,y=-1,z=0},  {x=0,y=-1,z=1},  {x=0,y=1,z=-1},
	{x=0,y=1,z=0},   {x=0,y=1,z=1},   {x=1,y=-1,z=0},
	{x=1,y=0,z=-1},  {x=1,y=0,z=0},   {x=1,y=0,z=1},
	{x=1,y=1,z=0}
}

default.spawn_mobv2 = function(pos, props)
	local staticdata = minetest.write_json(props, false)
	return minetest.add_entity(pos, "default:mobv2", staticdata)
end

default.get_mob_dungeon_master = function()
	return {
		looks = "dungeon_master",
		hp = 30,
		shoot_type = "fireball",
		shoot_y = 0.7,
		player_hit_damage = 1,
		player_hit_distance = 1,
		player_hit_interval = 0.5,
		mindless_rage = math.random(0, 100) == 0,
	}
end

function MobV2SAO:getPos()
	-- Because we can't do offset rendering we move the position higher by the
	-- sprite_y and subtract it for internal calculations
	return vector.offset(self.object:get_pos(), 0, -self.sprite_y, 0)
end

function MobV2SAO:setPos(pos)
	self.object:set_pos(vector.offset(pos, 0, self.sprite_y, 0))
end

function MobV2SAO:setLooks(looks)
	local selection_size = {x=0.4, y=0.4}
	local selection_y = 0
	local texture_name
	local sprite_size
	local lock_full_brightness = false
	local simple_anim_frames
	local simple_anim_frametime

	self.sprite_y = 0

	if looks == "dungeon_master" then
		texture_name = "dungeon_master.png"
		self.sprite_type = "humanoid_1"
		sprite_size = {x=2, y=3}
		self.sprite_y = 0.85
		selection_size = {x=0.4, y=2.6}
		selection_y = -0.4
	elseif looks == "fireball" then
		texture_name = "fireball.png"
		self.sprite_type = "simple"
		sprite_size = {x=1, y=1}
		simple_anim_frames = 3
		simple_anim_frametime = 0.1
		lock_full_brightness = true
	else
		texture_name = "stone.png"
		self.sprite_type = "simple"
		sprite_size = {x=1, y=1}
		simple_anim_frames = 3
		simple_anim_frametime = 0.333
	end

	--

	local toset = {
		textures = { texture_name .. "^[makealpha:128,0,0^[makealpha:128,128,0" },
		visual_size = sprite_size,
		selectionbox = {-selection_size.x, selection_y, -selection_size.x,
			selection_size.x, selection_size.y + selection_y, selection_size.x},
	}

	toset.selectionbox[2] = toset.selectionbox[2] - self.sprite_y
	toset.selectionbox[5] = toset.selectionbox[5] - self.sprite_y

	if self.sprite_type == "humanoid_1" then
		toset.spritediv = {x=6, y=5}
	elseif self.sprite_type == "simple" then
		toset.spritediv = {x=1, y=simple_anim_frames}
	end
	if lock_full_brightness then
		toset.glow = minetest.LIGHT_MAX
	end

	self.object:set_properties(toset)

	if self.sprite_type == "simple" then
		-- enable animation
		self.object:set_sprite({x=0, y=0}, simple_anim_frames, simple_anim_frametime)
	end
end

function MobV2SAO:on_activate(staticdata, dtime_s)
	self.disturb_timer = 10000

	self.props = table.copy(MobV2SAO_props)
	local my_props = minetest.parse_json(staticdata)
	assert(type(my_props) == "table")
	for k, v in pairs(my_props) do
		self.props[k] = v
	end
	if core.settings:get("only_peaceful_mobs") and not self.props.is_peaceful then
		self.object:remove()
		return
	end

	-- Only read on init, since the engine takes care of saving these normally
	if self.props.speed then
		self.object:set_velocity(self.props.speed)
		self.props.speed = nil
	end
	if self.props.hp then
		self.object:set_hp(self.props.hp)
		self.props.hp = nil
	end
	self:setLooks(self.props.looks)

	self.object:set_armor_groups({fleshy=100})
end

function MobV2SAO:get_staticdata()
	return minetest.write_json(self.props, false)
end

function MobV2SAO:on_death()
	minetest.log("action",
		string.format("A %s mob dies at %s",
		(self.props.is_peaceful and "peaceful" or "non-peaceful"),
		minetest.pos_to_string(vector.round(self:getPos()))
	))
end

function MobV2SAO:stepVisuals(dtime, pos)
	-- this code was in the CAO in 0.3 so encapsulated here

	if self.sprite_type == "humanoid_1" then
		local row = 0
		local frames, frametime = 1, 0
		if self.shooting then
			row = 3
		elseif self.walking then
			-- note: set only via timer so the animation isn't interrupted
			row = 1
			frames, frametime = 2, 0.5
		end
		if row ~= self.last_sprite_row then
			self.object:set_sprite({x=0, y=row}, frames, frametime, true)
			self.last_sprite_row = row
		end
	end

	-- Damage close players
	if self.props.player_hit_damage and self.player_hit_timer <= 0 then
		local any = false
		for _, player in ipairs(minetest.get_connected_players()) do
			local playerpos = player:get_pos()
			if math.abs(pos.y - playerpos.y) < self.props.player_hit_distance and
				distance_xz(pos, playerpos) < self.props.player_hit_distance then
				any = true
				player:set_hp(player:get_hp() - self.props.player_hit_damage)
			end
		end
		if any then
			self.player_hit_timer = self.props.player_hit_interval
		end
	end

	self.walking_unset_timer = self.walking_unset_timer + dtime
	if self.walking_unset_timer >= 1 then
		self.walking = false
	end

	if self.shooting ~= self.bright_shooting then
		self.object:set_properties({
			glow = self.shooting and minetest.LIGHT_MAX or 0,
		})
		self.bright_shooting = self.shooting
	end
end

function MobV2SAO:on_step(dtime, moveresult)
	self.props.age = self.props.age + dtime
	if self.props.die_age >= 0 and self.props.age >= self.props.die_age then
		self.object:remove()
		return
	end

	local pos = self:getPos()

	self.random_disturb_timer = self.random_disturb_timer + dtime
	if self.random_disturb_timer >= 5 then
		self.random_disturb_timer = 0
		for _, player in ipairs(minetest.get_connected_players()) do
			if vector.distance(player:get_pos(), pos) < 16 then
				if math.random(0, 3) == 0 then
					minetest.log("action",
						string.format("Mob at %s got randomly disturbed by %s",
						minetest.pos_to_string(vector.round(pos)),
						player:get_player_name()
					))
					self.disturbing_player = player:get_player_name()
					self.disturb_timer = 0
					break
				end
			end
		end
	end

	local d_player_distance, d_player_norm, d_player_dir
	if self.disturbing_player ~= "" then
		local player = minetest.get_player_by_name(self.disturbing_player)
		local offset = vector.subtract(player:get_pos(), pos)
		d_player_distance = vector.length(offset)
		d_player_norm = vector.normalize(offset)
		d_player_dir = math.atan2(d_player_norm.z, d_player_norm.x)
	end

	self.disturb_timer = self.disturb_timer + dtime

	if not self.falling then
		self.shooting_timer = self.shooting_timer - dtime
		if self.shooting_timer <= 0 and self.shooting then
			self.shooting = false

			if self.props.shoot_type == "fireball" then
				local yaw = self.object:get_yaw()
				local dir = vector.new(math.cos(yaw), 0, math.sin(yaw))
				dir.y = self.shoot_y
				dir = vector.normalize(dir)
				local speed = vector.multiply(dir, 10)
				local shoot_pos = vector.offset(pos, 0, self.props.shoot_y, 0)
				minetest.log("info", "Mob shooting fireball from " ..
					minetest.pos_to_string(shoot_pos) .. " at speed " ..
					minetest.pos_to_string(speed))
				if default.modernize.sounds then
					minetest.sound_play("fireball", {
						pos = shoot_pos,
					}, true)
				end
				default.spawn_mobv2(shoot_pos, {
					looks = "fireball",
					speed = speed,
					die_age = 5,
					move_type = "constant_speed",
					hp = 1000,
					player_hit_damage = 9,
					player_hit_distance = 2,
					player_hit_interval = 1,
				})
			end
		end

		self.shoot_reload_timer = self.shoot_reload_timer + dtime

		local reload_time = self.disturb_timer < 15 and 3 or 15

		local shoot_without_player = self.props.mindless_rage == true

		if not self.shooting and self.shoot_reload_timer >= reload_time and
			not self.next_pos and
			(self.disturb_timer < 60 or shoot_without_player) then
			if self.disturb_timer < 60 and d_player_norm and
				d_player_distance < 16 and math.abs(d_player_norm.y) < 0.8 then
				self.object:set_yaw(d_player_dir)
				self.shoot_y = d_player_norm.y
			else
				self.shoot_y = math.random(-30, 10) * 0.01
			end
			self.shoot_reload_timer = 0
			self.shooting = true
			self.shooting_timer = 1.5
		end
	end

	if self.props.move_type == "ground_nodes" then
		if not self.shooting then
			self.walk_around_timer = self.walk_around_timer - dtime
			if self.walk_around_timer <= 0 then
				self.walk_around = not self.walk_around
				if self.walk_around then
					self.walk_around_timer = 0.1 * math.random(10, 50)
				else
					self.walk_around_timer = 0.1 * math.random(30, 70)
				end
			end
		end

		-- Move
		if self.next_pos then
			local diff = vector.subtract(self.next_pos, pos)
			self.object:set_yaw(math.atan2(diff.z, diff.x))

			local dir = vector.normalize(diff)
			local speed = self.falling and 3 or 0.5
			dir = vector.multiply(dir, dtime * speed)
			local arrived = false
			if vector.length(dir) > vector.length(diff) then
				dir = diff
				arrived = true
			end
			pos = vector.add(pos, dir)
			self:setPos(pos)

			if vector.distance(pos, self.next_pos) < 0.1 or arrived then
				self.next_pos = nil
			end
		end

		if self.next_pos and not self.walking then -- if we moved any
			self.walking = true
			self.walking_unset_timer = 0
		end

		local pos_i = vector.round(pos)
		local size_blocks = vector.new(math.round(self.props.size.x),
			math.round(self.props.size.y), math.round(self.props.size.x))
		local pos_size_off = vector.zero()
		if self.props.size.x >= 2.5 then
			pos_size_off.x = -1
			pos_size_off.y = -1
		end

		if not self.next_pos then
			-- Check whether to drop down
			local tmp = vector.offset(vector.add(pos_i, pos_size_off), 0, -1, 0)
			if checkFreePosition(tmp, size_blocks) then
				self.next_pos = pos_i:offset(0, -1, 0)
				self.falling = true
			else
				self.falling = false
			end
		end

		if self.walk_around and not self.next_pos then
			-- Find some position where to go next
			table.shuffle(MobV2SAO_dps)
			for _, dps in ipairs(MobV2SAO_dps) do
				local p = vector.add(pos_i, dps)
				if checkFreeAndWalkablePosition(vector.add(p, pos_size_off), size_blocks) then
					self.next_pos = p
					break
				end
			end
		end
	elseif self.props.move_type == "constant_speed" then
		local pos_i = vector.round(pos)
		local size_blocks = vector.new(math.round(self.props.size.x),
			math.round(self.props.size.y), math.round(self.props.size.x))
		local pos_size_off = vector.zero()
		if self.props.size.x >= 2.5 then
			pos_size_off.x = -1
			pos_size_off.y = -1
		end

		if not checkFreePosition(vector.add(pos_i, pos_size_off), size_blocks) then
			if default.modernize.sounds then
				minetest.sound_play("explode", {
					pos = pos_i,
				}, true)
			end

			if not minetest.settings:get_bool("no_mob_griefing", false) then
				explodeSquare(pos_i, vector.new(3, 3, 3))
			end

			self.object:remove()
			return
		end
	end

	self:stepVisuals(dtime, pos)
end

function MobV2SAO:on_punch(hitter, time_from_last_punch)
	if (time_from_last_punch or 0) <= 0.5 then
		return true
	end

	self.disturb_timer = 0
	self.disturbing_player = hitter:get_player_name()
	self.next_pos = nil -- Cancel moving immediately

	local dir = vector.subtract(self:getPos(), hitter:get_pos())
	dir = vector.normalize(dir)
	self.object:set_yaw(math.atan2(dir.z, dir.x) + math.pi)
	local new_pos = vector.add(self:getPos(), dir)
	do
		local pos_i = vector.round(new_pos)
		local size_blocks = vector.new(math.round(self.props.size.x),
			math.round(self.props.size.y), math.round(self.props.size.x))
		local pos_size_off = vector.zero()
		if self.props.size.x >= 2.5 then
			pos_size_off.x = -1
			pos_size_off.y = -1
		end
		if checkFreePosition(vector.add(pos_i, pos_size_off), size_blocks) then
			self:setPos(new_pos)
		end
	end
end

--function MobV2SAO:on_rightclick()
--	print(dump(self))
--end

minetest.register_entity("default:mobv2", MobV2SAO)
