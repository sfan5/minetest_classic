--[[
	Minetest Classic
	Copyright (c) 2022 sfan5 <sfan5@live.de>

	SPDX-License-Identifier: LGPL-2.1-or-later
--]]

-- IMPORTANT: this mod is called 'cl_default' so it doesn't show up in dependency
-- resolution for 'default' (which is claimed by Minetest Game).
-- It still registers in-game content with the default prefix for simplicity and compatibility reasons.

rawset(_G, "default", {})

local S = minetest.get_translator("default")
default.get_translator = S

-- Original references:
-- nodes https://github.com/minetest/minetest/blob/stable-0.3/src/content_mapnode.cpp#L104
-- crafting https://github.com/minetest/minetest/blob/stable-0.3/src/content_craft.cpp#L30
-- items https://github.com/minetest/minetest/blob/stable-0.3/src/content_inventory.cpp
-- tools https://github.com/minetest/minetest/blob/stable-0.3/src/inventory.h#L308
-- meta/formspec https://github.com/minetest/minetest/blob/stable-0.3/src/content_nodemeta.cpp
-- selection boxes https://github.com/minetest/minetest/blob/stable-0.3/src/game.cpp#L348
-- interact handlers https://github.com/minetest/minetest/blob/stable-0.3/src/server.cpp#L2238
-- LBM https://github.com/minetest/minetest/blob/stable-0.3/src/environment.cpp#L622

-- Node compatibility list that still exists in the engine today:
-- https://github.com/luanti-org/luanti/blob/stable-5/src/content_mapnode.cpp#L123

-- v v v v v v v v v
-- Lots of old content (including playable releases) can be found here:
-- http://packages.8dromeda.net/minetest/
-- ^ ^ ^ ^ ^ ^ ^ ^ ^

-- TODOs:
-- come up with some sane item groups to use
-- generate failed dungeons in water (like an U)
-- do stone deserts appear naturally?
-- sound ideas: furnace, eating
-- falling sand/gravel
-- investigate long vertical shafts (mgv6 fail?)
-- some particle effects
-- option to make mobs not perfectly flat? (think extruded mesh)

-- long-term TODOs?:
-- consider adding unfinished features like firefly spawn & standing signs
-- texture animations for some
-- 3d model signs and torches
-- maybe 3d model mobs

--
-- Modernize setting
--

-- note: this table contains the default values
default.modernize = {
	-- 'waving' set on suitable nodes
	node_waving = true,
	-- glass uses glasslike drawtype instead of allfaces
	glasslike = true,
	-- Breathbar/drowning is enabled
	drowning = true,
	-- Lava is not renewable
	lava_non_renewable = false,
	-- Allows the engine shadowmapping to be used
	allow_shadows = true,
	-- Allows the minimap to be used
	allow_minimap = false,
	-- Allows the player to zoom
	allow_zoom = false,
	-- Keeps the (new) item entity from the engine instead of emulating the old one
	new_item_entity = true,
	-- Don't delete Oerkki if the player gets too close
	disable_oerkki_delete = true,
	-- Replace some textures that look out of place/unfinished
	fix_textures = true,
	-- Enable sounds
	sounds = true,
	-- Add a wieldhand texture instead of having it invisible
	wieldhand = true,
	-- Allows PvP
	pvp = false,
	-- Use engine's dynamic skybox with sun and moon
	new_skybox = false,
	-- Allow directly dropping items in the world, otherwise only rightclick works
	allow_drop = true,

	-- TODO disable_rightclick_drop, glasslike_framed
}

do
	local warned = {}
	setmetatable(default.modernize, {
		__index = function(self, key)
			if not warned[key] then
				minetest.log("warning",
					("Undeclared modernize flag accessed: %q"):format(key))
				warned[key] = true
			end
		end,
	})
end

local function parse_flagstr(dest, s)
	local flags = string.split(s, ",", false)
	for _, flag in ipairs(flags) do
		flag = flag:gsub("^%s*", ""):gsub("%s*$", "")
		if flag:sub(1, 2) == "no" and rawget(dest, flag:sub(3)) ~= nil then
			dest[flag:sub(3)] = false
		elseif rawget(dest, flag) ~= nil then
			dest[flag] = true
		else
			minetest.log("warning",
				("Ignoring unknown modernize flag: %q"):format(flag))
		end
	end
end

-- luacheck: ignore 511
if false then
	local t1, t2 = {}, {}
	for k, v in pairs(default.modernize) do
		if v then
			t1[#t1+1] = k
		end
		t2[#t2+1] = k
	end
	table.sort(t1)
	table.sort(t2)
	print("== put in settingtypes.txt ==")
	print("modernize (Modernize flags) flags " .. table.concat(t1, ",") .. " " .. table.concat(t2, ","))
	print("== put in minetest.conf.example ==")
	print("#modernize = " .. table.concat(t1, ","))
	print("====")
end

do
	local s = minetest.settings:get("modernize")
	if (s or "") ~= "" then
		-- reset and parse user setting
		for k, _ in pairs(default.modernize) do
			default.modernize[k] = false
		end
		parse_flagstr(default.modernize, s)
	end
	local n, ntot = 0, 0
	for _, value in pairs(default.modernize) do
		n = n + (value and 1 or 0)
		ntot = ntot + 1
	end
	print(("Minetest Classic: %d/%d modernization flags enabled"):format(n, ntot))
end

--
-- Misc code
--

-- returns drop_count, objref
default.item_to_entity = function(pos, itemstack)
	if itemstack:get_name() == "default:rat" then
		return 1, minetest.add_entity(pos, "default:rat")
	elseif itemstack:get_name() == "default:firefly" then
		return 1, minetest.add_entity(pos, "default:firefly")
	end
	return itemstack:get_count(), minetest.add_item(pos, itemstack)
end

local old_item_place = minetest.item_place
minetest.item_place = function(itemstack, placer, pointed_thing, ...)
	local itemstack, pos = old_item_place(itemstack, placer, pointed_thing, ...)
	-- When rightclicking a node with an item the item is dropped on top:
	-- FIXME this might break on_rightclick if we're not careful
	if pos == nil and pointed_thing.type == "node" and
		not minetest.registered_nodes[itemstack:get_name()] then
		pos = vector.new(pointed_thing.above)
		pos.x = pos.x + math.random(-200, 200) / 1000
		pos.z = pos.z + math.random(-200, 200) / 1000
		local drop_count, obj = default.item_to_entity(pos, itemstack)
		if obj then
			local ret = itemstack
			if not minetest.is_creative_enabled(placer:get_player_name() or "") then
				ret:take_item(drop_count)
			end
			return ret, nil
		end
	end
	return itemstack, nil
end

if not default.modernize.allow_drop then
	local old_item_drop = minetest.item_drop
	minetest.item_drop = function(itemstack, dropper, ...)
		if dropper and dropper:is_player() then
			return itemstack
		end
		return old_item_drop(itemstack, dropper, ...)
	end
end

minetest.register_on_joinplayer(function(player)
	player:set_properties({
		pointable = default.modernize.pvp,
		nametag_bgcolor = "#00000000",
		zoom_fov = default.modernize.allow_zoom and 15 or 0,
	})
	if not default.modernize.allow_minimap then
		player:hud_set_flags({minimap = false})
	end
	if default.modernize.pvp then
		player:set_armor_groups({fleshy = 75})
	end
	player:set_physics_override({sneak_glitch = true})
	if player.set_lighting and default.modernize.allow_shadows then
		player:set_lighting({
			shadows = { intensity = 0.33 },
			bloom = { intensity = 0.05 },
			volumetric_light = { strength = 0.2 },
		})
	end
end)

-- TODO: once supported by the engine this should be migrated to a bulk LBM
minetest.register_lbm({
	label = "Convert to grass",
	name = ":default:convert_to_grass",
	nodenames = {"default:dirt"},
	run_at_every_load = true,
	action = function(pos, node, dtime_s)
		if dtime_s == nil then
			return -- (since 5.7.0)
		end
		-- This originally operated on blocks so the above node for the topmost node
		-- would not be available, meaning the conversion could never happen for it
		if pos.y % 16 == 15 then
			return
		end
		if dtime_s > 300 then
			local p1 = vector.offset(pos, 0, 1, 0)
			local above = minetest.get_node(p1)
			if minetest.get_item_group(above.name, "air_equivalent") > 0 and minetest.get_node_light(p1, 0.5) >= 13 then
				node.name = "default:dirt_with_grass"
				minetest.swap_node(pos, node)
			end
		end
	end,
})

minetest.register_globalstep(function()
	if not minetest.settings:get_bool("footprints") then
		return
	end
	for _, player in ipairs(minetest.get_connected_players()) do
		local bottompos = vector.round(vector.offset(player:get_pos(), 0, -1/4, 0))
		local n = minetest.get_node(bottompos)
		if n.name == "default:dirt_with_grass" then
			-- A long argument could be had whether you are allowed to trample
			-- over someone else's protected lawn. Let's just say no.
			if not minetest.is_protected(bottompos, player:get_player_name()) then
				n.name = "default:dirt_with_grass_footsteps"
				minetest.swap_node(bottompos, n)
			end
		end
	end
end)

minetest.register_on_newplayer(function(player)
	if not minetest.settings:get_bool("give_initial_stuff") then
		return
	end
	if minetest.is_creative_enabled(player:get_player_name()) then
		return
	end
	local inv = player:get_inventory()
	local items = {
		"default:pick_steel",
		"default:torch 99",
		"default:axe_steel",
		"default:shovel_steel",
		"default:cobble 99",
	}
	for _, item in ipairs(items) do
		inv:add_item("main", item)
	end
end)

--
-- Skybox
--

local light_decode_table = {8, 11, 14, 18, 22, 29, 37, 47, 60, 76, 97, 123, 157, 200, 255}
local function time_to_daynight_ratio(tod)
	local daylength, nightlength, daytimelength = 16, 6, 8
	local t = (tod % 24000) / math.floor(24000 / daylength)
	if t < nightlength / 2 or t >= daylength - nightlength / 2 then
		return 350
	elseif t >= daylength / 2 - daytimelength / 2 and t < daylength / 2 + daytimelength / 2 then
		return 1000
	else
		return 750
	end
end

local skybox3_color = {
	[""] = "#aac8e6",
	["_dawn"] = "#263c58",
	["_night"] = "#0a0f16",
}

default.set_skybox = function(player, brightness)
	local t = "_night"
	if brightness >= 0.5 then
		t = ""
	elseif brightness >= 0.2 then
		t = "_dawn"
	end
	-- multiply with #aac8e6, which is bgcolor_bright in game.cpp
	local fog_color = string.format("#%02x%02x%02x", math.floor(brightness * 170),
		math.floor(brightness * 200), math.floor(brightness * 230))
	local params = {
		fog = {
			fog_start = 0.4,
		},
	}
	if default.modernize.new_skybox then
		params.type = "regular"
		params.fog.fog_color = fog_color -- (since 5.9.0)
		params.sky_color = {
			day_sky = "#5191d0",
			day_horizon = "#aac8e6",
			dawn_sky = "#465d7d",
			dawn_horizon = "#263c58",
			night_sky = "#121820",
			night_horizon = "#0a0f16",
			indoors = skybox3_color[t],
		}
	else
		params.type = "skybox"
		params.base_color = fog_color
		params.textures = {
			"skybox2" .. t .. ".png",
			"skybox3" .. t .. ".png",
			"skybox1" .. t .. ".png",
			"skybox1" .. t .. ".png",
			"skybox1" .. t .. ".png",
			"skybox1" .. t .. ".png"
		}
	end
	player:set_sky(params)
end

local last_brightness = -1

minetest.register_globalstep(function()
	local tod_f = minetest.get_timeofday()
	local ratio = time_to_daynight_ratio(tod_f * 24000)
	local index = math.floor(ratio * #light_decode_table / 1000)
	index = math.min(index, #light_decode_table - 1)
	local brightness = light_decode_table[index + 1] / 255

	if math.abs(last_brightness - brightness) < 0.03 then
		return
	end
	last_brightness = brightness
	for _, player in ipairs(minetest.get_connected_players()) do
		default.set_skybox(player, brightness)
	end
end)

minetest.register_on_joinplayer(function(player)
	if last_brightness ~= -1 then
		default.set_skybox(player, last_brightness)
	end
	if default.modernize.new_skybox then
		player:set_sun({ texture = "" })
		player:set_moon({ texture = "" })
		player:set_stars({
			count = 14 * 4,
			star_color = "#ffffff",
			scale = 0.8,
		})
	else
		-- keep sun and moon but set invisible texture, needed for shadow support
		player:set_sun({ texture = "blank.png", sunrise_visible = false })
		player:set_moon({ texture = "blank.png" })
		player:set_stars({ visible = false })
	end
	local clouds = {
		color = "#f0f0ff",
		speed = {x=-2, z=0},
	}
	player:set_clouds(clouds)
end)

--
-- Dig groups
--

-- equivalent to setDirtLikeDiggingProperties, uses "dirt" group
-- starting at level 1
default.dirt_levels = { 0.75, 1.0, 1.75 }

-- equivalent to setStoneLikeDiggingProperties, uses "stone" group
default.stone_levels = { 0.5, 0.8, 0.9, 1.0, 1.5, 3.0, 5.0 }

-- equivalent to setWoodLikeDiggingProperties, uses "wood" group
default.wood_levels = { 0.1, 0.15, 0.25, 0.5, 0.75, 1.0 }

-- dig_hand = 1 <=> 0.5s
-- dig_hand = 2 <=> instant

-- dig_mese = 1 <=> instant (only diggable with mese pick)

-- TODO custom uses calculation wear = 65535 / uses * toughness

--
-- Sounds
--

local function extend(parent, tbl)
	assert(type(parent) == type(tbl) and type(tbl) == "table")
	assert(parent ~= tbl)
	return setmetatable(tbl, { __index = parent })
end

--[[
Quick history lesson:
* footstep, dig, dug and place sounds were added in 0.4.dev-20120326
  The dig sound got a default of "__group" that automatically picks a
  sound named `default_dig_<groupname>`, this feature still exists today (yuck)
* the place sound was un-hardcoded in 0.4.6
* swimming and tool break sounds were added to Minetest Game in 0.4.15
* environmental sound (flowing water) was added to MTG in 5.1.0

Observations:
* The first win32 build that has working sound for me is 0.4.6, though
  earlier releases can be fixed by copying over wrap_oal.dll from newer ones
* Some of the sounds defined in 0.4.0 are missing and were only added later,
  e.g. default_break_glass in 0.4.4
* A big sound redesign in MTG happened in 0.4.8

To give a nostalgic feeling(*) the sounds here are taken from 0.4.7 with select
ones from newer versions. Dig sounds are mapped according to what the __group
automatism would choose for most of the nodes. Environment sounds are not implemented.
(*): The sounds are pretty bad so this might be revisited
--]]

default.node_sound = {}

do
	local warned = {}
	setmetatable(default.node_sound, {
		__index = function(self, key)
			if not warned[key] then
				minetest.log("warning",
					("Undeclared key in default.node_sound accessed: %q"):format(key))
				warned[key] = true
			end
		end,
	})
end

default.node_sound.default = {
	dig   = {name = ""}, -- disable automatic group-based handling
	dug   = {name = "default_dug_node",   gain = 1.0},
	place = {name = "default_place_node", gain = 0.5},
}

default.node_sound.stone = extend(default.node_sound.default, {
	footstep = {name = "default_hard_footstep", gain = 0.2},
	dig      = {name = "default_dig_cracky",    gain = 1.0},
})

default.node_sound.dirt = extend(default.node_sound.default, {
	footstep = {name = "default_dirt_footstep", gain = 1.0}, -- (from 0.4.8)
	dig      = {name = "default_dig_crumbly",   gain = 1.0},
})

default.node_sound.grass = extend(default.node_sound.dirt, {
	footstep = {name = "default_grass_footstep", gain = 0.4},
})

default.node_sound.sand = extend(default.node_sound.default, {
	footstep = {name = "default_grass_footstep", gain = 0.25},
	dig      = {name = "default_dig_crumbly",    gain = 1.0},
	dug      = {name = ""},
})

default.node_sound.gravel = extend(default.node_sound.dirt, {
	footstep = {name = "default_gravel_footstep", gain = 0.45},
})

default.node_sound.wood = extend(default.node_sound.default, {
	footstep = {name = "default_hard_footstep", gain = 0.3},
	dig      = {name = "default_dig_choppy",    gain = 1.0},
})

default.node_sound.leaves = extend(default.node_sound.default, {
	footstep = {name = "default_grass_footstep", gain = 0.25},
	dig      = {name = "default_dig_crumbly",    gain = 0.4},
	dug      = {name = ""},
})

default.node_sound.glass = extend(default.node_sound.default, {
	footstep = {name = "default_hard_footstep",  gain = 0.25},
	dig      = {name = "default_dig_cracky",     gain = 1.0},
	dug      = {name = "default_break_glass",    gain = 1.0},
})

default.node_sound.water = extend(default.node_sound.default, {
	footstep = {name = "default_water_footstep", gain = 0.2}, -- (from 0.4.15)
})

default.node_sound.other = {
	dig = {name = "default_dig_dig_immediate", gain = 1.0},
}

default.tool_sound = {
	breaks = {name = "default_tool_breaks", gain = 1.0}, -- (from 0.4.15)
}

if not default.modernize.sounds then
	for k, _ in pairs(default.node_sound) do
		default.node_sound[k] = {}
	end
	default.tool_sound = {}
end

--
-- Nodes
--

-- Note: is_ground_content is set like in 0.3 to ensure better matching mapgen
-- behavior (e.g. caves should carve through dungeons).

do
	local groups = table.copy(minetest.registered_nodes["air"].groups)
	groups.air_equivalent = 1
	minetest.override_item("air", {
		groups = groups,
	})
end

minetest.register_node(":default:stone", {
	description = S("Stone"),
	tiles = { "stone.png" },
	groups = { stone = 4 },
	drop = "default:cobble",
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:dirt_with_grass", {
	description = S("Dirt With Grass"),
	tiles = { "grass.png", "mud.png", "grass_side.png" },
	groups = { dirt = 2 },
	drop = "default:dirt",
	sounds = default.node_sound.grass,
})

minetest.register_node(":default:dirt_with_grass_footsteps", {
	description = S("Dirt With Grass and Footsteps"),
	tiles = {
		default.modernize.fix_textures and "grass_footsteps.png" or "grass_footsteps_old.png",
		"mud.png", "grass_side.png"
	},
	groups = { dirt = 2, not_in_creative_inventory = 1 },
	drop = "default:dirt",
	sounds = default.node_sound.grass,
})

minetest.register_node(":default:dirt", {
	description = S("Dirt"),
	tiles = { "mud.png" },
	groups = { dirt = 2 },
	sounds = default.node_sound.dirt,
})

minetest.register_node(":default:sand", {
	description = S("Sand"),
	tiles = { "sand.png" },
	groups = { dirt = 2 },
	sounds = default.node_sound.sand,
})

minetest.register_node(":default:gravel", {
	description = S("Gravel"),
	tiles = { "gravel.png" },
	groups = { dirt = 3 },
	sounds = default.node_sound.gravel,
})

minetest.register_node(":default:sandstone", {
	description = S("Sandstone"),
	tiles = { "sandstone.png" },
	groups = { dirt = 2 },
	drop = "default:sand",
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:clay", {
	description = S("Clay"),
	tiles = { "clay.png" },
	groups = { dirt = 2 },
	drop = "default:lump_of_clay 4",
	sounds = default.node_sound.dirt,
})

minetest.register_node(":default:brick", {
	description = S("Brick"),
	tiles = { "brick.png" },
	groups = { stone = 4 },
	drop = "default:clay_brick 4",
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:tree", {
	description = S("Tree Trunk"),
	tiles = { "tree_top.png", "tree_top.png", "tree.png" },
	groups = { wood = 6 },
	sounds = default.node_sound.wood,
})

minetest.register_node(":default:jungletree", {
	description = S("Jungle Tree Trunk"),
	tiles = { "jungletree_top.png", "jungletree_top.png", "jungletree.png" },
	groups = { wood = 6 },
	is_ground_content = false,
	sounds = default.node_sound.wood,
})

minetest.register_node(":default:junglegrass", {
	description = S("Jungle Grass"),
	drawtype = "mesh",
	mesh = "plantlike1_3.obj", -- scaled 1.3x
	use_texture_alpha = "clip",
	tiles = {
		{ name = "junglegrass.png", backface_culling = true }
	},
	inventory_image = "junglegrass.png",
	wield_image = "junglegrass.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	groups = { wood = 1 },
	is_ground_content = false,
	sounds = default.node_sound.leaves,
})

minetest.register_node(":default:leaves", {
	description = S("Leaves"),
	tiles = { "leaves.png" },
	special_tiles = { "leaves.png" },
	groups = { wood = 2 },
	drawtype = "allfaces_optional",
	waving = default.modernize.node_waving and 1 or nil,
	paramtype = "light",
	is_ground_content = false,
	drop = {
		items = {
			{ items = {"default:sapling"}, rarity = 20 },
			{ items = {"default:leaves"} }
		}
	},
	sounds = default.node_sound.leaves,
})

minetest.register_node(":default:cactus", {
	description = S("Cactus"),
	tiles = { "cactus_top.png", "cactus_top.png", "cactus_side.png" },
	groups = { wood = 5 },
	sounds = default.node_sound.wood,
})

minetest.register_node(":default:papyrus", {
	description = S("Papyrus"),
	drawtype = "plantlike",
	-- Note: Minetest 0.3 actually rotates the faces of plantlike differently
	-- by a single degree than the current engine. Nobody will ever notice this.
	tiles = {"papyrus.png"},
	inventory_image = "papyrus.png",
	wield_image = "papyrus.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	groups = { wood = 3 },
	sounds = default.node_sound.leaves,
})

minetest.register_node(":default:bookshelf", {
	description = S("Bookshelf"),
	tiles = { "wood.png", "wood.png", "bookshelf.png" },
	groups = { wood = 5 },
	sounds = default.node_sound.wood,
})

minetest.register_node(":default:glass", {
	description = S("Glass"),
	drawtype = default.modernize.glasslike and "glasslike" or "allfaces",
	tiles = { "glass.png" },
	paramtype = "light",
	sunlight_propagates = true,
	groups = { wood = 2 },
	sounds = default.node_sound.glass,
})

minetest.register_node(":default:fence_wood", {
	description = S("Fence"),
	drawtype = "fencelike",
	tiles = { "wood.png" },
	inventory_image = "fence.png",
	wield_image = "fence.png",
	selection_box = { type = "regular" },
	paramtype = "light",
	groups = { wood = 5 },
	sounds = default.node_sound.wood,
})

minetest.register_node(":default:rail", {
	description = S("Rail"),
	drawtype = "raillike",
	sunlight_propagates = true,
	walkable = false,
	tiles = {
		"rail.png", "rail_curved.png",
		"rail_t_junction.png", "rail_crossing.png"
	},
	inventory_image = "rail.png",
	wield_image = "rail.png",
	paramtype = "light",
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, -0.5+1/16, 0.5},
	},
	groups = { wood = 5 },
	sounds = default.node_sound.other,
})

minetest.register_node(":default:ladder", {
	description = S("Ladder"),
	drawtype = "signlike",
	sunlight_propagates = true,
	walkable = false,
	climbable = true,
	tiles = { "ladder.png" },
	inventory_image = "ladder.png",
	wield_image = "ladder.png",
	paramtype = "light",
	paramtype2 = "wallmounted",
	legacy_wallmounted = true,
	selection_box = {
		type = "wallmounted",
		wall_top = {-0.5, 0.42, -0.5, 0.5, 0.49, 0.5},
		wall_bottom = {-0.5, -0.49, -0.5, 0.5, -0.42, 0.5},
		wall_side = {-0.49, -0.5, -0.5, -0.42, 0.5, 0.5},
	},
	groups = { wood = 4 },
	sounds = default.node_sound.wood,
	-- TODO check movement details
})

-- exists in 0.3 as legacy, but we need this as a separate node
minetest.register_node(":default:coalstone", {
	description = S("Stone with Coal"),
	tiles = { "stone.png^mineral_coal.png" },
	groups = { stone = 5 },
	drop = "default:lump_of_coal 2",
	sounds = default.node_sound.stone,
})

-- does not exist as a separate node in 0.3, but we need it as one
minetest.register_node(":default:ironstone", {
	description = S("Stone with Iron"),
	tiles = { "stone.png^mineral_iron.png" },
	groups = { stone = 5 },
	drop = "default:lump_of_iron 2",
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:wood", {
	description = S("Wood"),
	tiles = { "wood.png" },
	groups = { wood = 5 },
	sounds = default.node_sound.wood,
})

minetest.register_node(":default:mese", {
	description = S("Mese"),
	tiles = { "mese.png" },
	groups = { stone = 1 },
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:cloud", {
	description = S("Cloud"),
	tiles = { "cloud.png" },
	groups = { dig_mese = 1, not_in_creative_inventory = 1 },
	sounds = default.node_sound.default,
})

minetest.register_node(":default:water_flowing", {
	description = S("Water"),
	drawtype = "flowingliquid",
	waving = default.modernize.node_waving and 3 or nil,
	tiles = { "water.png" },
	special_tiles = {
		{ name = "water.png", backface_culling = false },
		{ name = "water.png", backface_culling = true },
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	paramtype2 = "flowingliquid",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = default.modernize.drowning and 1 or nil,
	liquidtype = "flowing",
	liquid_alternative_flowing = "default:water_flowing",
	liquid_alternative_source = "default:water_source",
	liquid_viscosity = 1,
	post_effect_color = {a = 64, r = 100, g = 100, b = 200},
	groups = { not_in_creative_inventory = 1 },
	sounds = default.node_sound.water,
})

minetest.register_node(":default:water_source", {
	description = S("Water Source"),
	drawtype = "liquid",
	waving = default.modernize.node_waving and 3 or nil,
	tiles = {
		{ name = "water.png", backface_culling = false },
		{ name = "water.png", backface_culling = true },
	},
	use_texture_alpha = "blend",
	paramtype = "light",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = default.modernize.drowning and 1 or nil,
	liquidtype = "source",
	liquid_alternative_flowing = "default:water_flowing",
	liquid_alternative_source = "default:water_source",
	liquid_viscosity = 1,
	post_effect_color = {a = 64, r = 100, g = 100, b = 200},
	groups = { },
	sounds = default.node_sound.water,
})

-- Note: Lava is does not seem to properly emit light in 0.3.
-- I didn't care to replicate this.

minetest.register_node(":default:lava_flowing", {
	description = S("Lava"),
	drawtype = "flowingliquid",
	tiles = { "lava.png" },
	special_tiles = {
		{ name = "lava.png", backface_culling = false },
		{ name = "lava.png", backface_culling = true },
	},
	use_texture_alpha = "clip",
	paramtype = "light",
	light_source = minetest.LIGHT_MAX - 1,
	paramtype2 = "flowingliquid",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	liquidtype = "flowing",
	liquid_alternative_flowing = "default:lava_flowing",
	liquid_alternative_source = "default:lava_source",
	liquid_viscosity = 7,
	liquid_renewable = not default.modernize.lava_non_renewable,
	damage_per_second = 4 * 2,
	post_effect_color = {a = 192, r = 255, g = 64, b = 0},
	groups = { not_in_creative_inventory = 1 },
})

minetest.register_node(":default:lava_source", {
	description = S("Lava Source"),
	drawtype = "liquid",
	tiles = {
		{ name = "lava.png", backface_culling = false },
		{ name = "lava.png", backface_culling = true },
	},
	use_texture_alpha = "clip",
	paramtype = "light",
	light_source = minetest.LIGHT_MAX - 1,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	liquidtype = "source",
	liquid_alternative_flowing = "default:lava_flowing",
	liquid_alternative_source = "default:lava_source",
	liquid_viscosity = 7,
	liquid_renewable = not default.modernize.lava_non_renewable,
	damage_per_second = 4 * 2,
	post_effect_color = {a = 192, r = 255, g = 64, b = 0},
	groups = { },
})

minetest.register_node(":default:torch", {
	description = S("Torch"),
	drawtype = "torchlike",
	tiles = { "torch_on_floor.png", "torch_on_ceiling.png", "torch.png" },
	inventory_image = "torch_on_floor.png",
	wield_image = "torch_on_floor.png",
	paramtype = "light",
	paramtype2 = "wallmounted",
	legacy_wallmounted = true,
	sunlight_propagates = true,
	walkable = false,
	light_source = minetest.LIGHT_MAX - 1,
	selection_box = {
		type = "wallmounted",
		wall_top = {-0.16, -0.16, -0.16, 0.16, 0.5, 0.16},
		wall_bottom = {-0.16, -0.5, -0.16, 0.16, 0.16, 0.16},
		wall_side = {-0.5, -0.33, -0.16, -0.5+0.33, 0.33, 0.16},
	},
	groups = { dig_hand = 2, air_equivalent = 1 },
	is_ground_content = false,
	sounds = default.node_sound.default,
})

minetest.register_node(":default:sign_wall", {
	description = S("Sign"),
	drawtype = "signlike",
	tiles = { "sign_wall.png" },
	inventory_image = "sign_wall.png",
	wield_image = "sign_wall.png",
	paramtype = "light",
	paramtype2 = "wallmounted",
	legacy_wallmounted = true,
	sunlight_propagates = true,
	walkable = false,
	selection_box = {
		type = "wallmounted",
		wall_top = {-0.35, 0.42, -0.4, 0.35, 0.49, 0.4},
		wall_bottom = {-0.35, -0.49, -0.4, 0.35, -0.42, 0.4},
		wall_side = {-0.49, -0.35, -0.4, -0.42, 0.35, 0.4},
	},
	groups = { dig_hand = 1, air_equivalent = 1 },
	is_ground_content = false,
	sounds = default.node_sound.default,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", "field[text;;${text}]")
	end,
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		-- set default text in user's native language
		if placer and placer:is_player() then
			local pi = minetest.get_player_information(placer:get_player_name()) or {}
			local text = minetest.get_translated_string(pi.lang_code or "", S("Some sign"))
			local meta = minetest.get_meta(pos)
			meta:set_string("text", text)
			meta:set_string("infotext", S('"@1"', text))
		end
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		local player_name = sender:get_player_name()
		if minetest.is_protected(pos, player_name) then
			minetest.record_protection_violation(pos, player_name)
			return
		end
		local meta = minetest.get_meta(pos)
		local text = fields.text
		if not text then
			return
		end
		if #text > 512 then
			minetest.chat_send_player(player_name, S("Text too long"))
			return
		end
		text = text:gsub("[%z-\8\11-\31\127]", "") -- strip naughty control characters (keeps \t and \n)
		minetest.log("action", ("%s writes %q to sign at %s"):format(player_name, text, minetest.pos_to_string(pos)))
		meta:set_string("text", text)
		meta:set_string("infotext", S('"@1"', text))
	end,
})

local function can_dig_chest(pos, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if not inv:is_empty("main") then
		return false
	end
	local player_name = player:get_player_name()
	if minetest.is_protected(pos, player_name) then
		minetest.record_protection_violation(pos, player_name)
		return false
	end
	return true
end

minetest.register_node(":default:chest", {
	description = S("Chest"),
	tiles = { "chest_top.png", "chest_top.png", "chest_side.png", "chest_side.png", "chest_side.png", "chest_front.png" },
	paramtype2 = "facedir",
	legacy_facedir_simple = true,
	groups = { wood = 6 },
	is_ground_content = false,
	sounds = default.node_sound.wood,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", "size[8,9]"..
			"list[current_name;main;0,0;8,4;]"..
			"list[current_player;main;0,5;8,4;]"..
			"listring[current_name;main]"..
			"listring[current_player;main]")
		meta:set_string("infotext", S("Chest"))
		local inv = meta:get_inventory()
		inv:set_size("main", 8*4)
	end,
	can_dig = can_dig_chest,
})

local function can_use_locked_chest(pos, player)
	local meta = minetest.get_meta(pos)
	local player_name = player:get_player_name()
	if meta:get_string("owner") ~= player_name then
		-- 0.3 uses the 'server' priv for this
		if not minetest.check_player_privs(player, "protection_bypass") then
			return false
		end
	end
	if minetest.is_protected(pos, player_name) then
		minetest.record_protection_violation(pos, player_name)
		return false
	end
	return true
end

minetest.register_node(":default:chest_locked", {
	description = S("Locking Chest"),
	tiles = {
		"chest_top.png", "chest_top.png", "chest_side.png", "chest_side.png", "chest_side.png",
		default.modernize.fix_textures and "chest_lock.png" or "chest_lock_old.png"
	},
	paramtype2 = "facedir",
	legacy_facedir_simple = true,
	groups = { wood = 6 },
	is_ground_content = false,
	sounds = default.node_sound.wood,
	after_place_node = function(pos, player)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", "size[8,9]"..
			"list[current_name;main;0,0;8,4;]"..
			"list[current_player;main;0,5;8,4;]"..
			"listring[current_name;main]"..
			"listring[current_player;main]")
		meta:set_string("owner", player:get_player_name())
		meta:set_string("infotext", S("Locking Chest"))
		-- TODO option to show the player name here
		local inv = meta:get_inventory()
		inv:set_size("main", 8*4)
	end,
	-- note: can_dig_chest() does not check the owner, this is intentional.
	can_dig = can_dig_chest,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if not can_use_locked_chest(pos, player) then
			return 0
		end
		return count
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if not can_use_locked_chest(pos, player) then
			return 0
		end
		return stack:get_count()
	end,
	allow_metadata_inventory_take = function(pos, listname, index, stack, player)
		if not can_use_locked_chest(pos, player) then
			return 0
		end
		return stack:get_count()
	end,
})

minetest.register_node(":default:furnace", {
	description = S("Furnace"),
	tiles = { "furnace_side.png", "furnace_side.png", "furnace_side.png", "furnace_side.png", "furnace_side.png", "furnace_front.png" },
	paramtype2 = "facedir",
	legacy_facedir_simple = true,
	groups = { stone = 6 },
	is_ground_content = false,
	drop = "default:cobble 6",
	sounds = default.node_sound.stone,
	-- formspecs / nodetimer is located in furnace.lua
})

minetest.register_node(":default:cobble", {
	description = S("Cobblestone"),
	tiles = { "cobble.png" },
	groups = { stone = 3 },
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:mossycobble", {
	description = S("Mossy Cobblestone"),
	tiles = { "mossycobble.png" },
	groups = { stone = 2 },
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:steelblock", {
	description = S("Steel Block"),
	tiles = { "steel_block.png" },
	groups = { stone = 7 },
	sounds = default.node_sound.stone,
})

-- The original Nyan Cat texture cannot be included due to known trademark issues:
-- https://web.archive.org/web/20200911031901/https://github.com/minetest/minetest_game/issues/1647
minetest.register_node(":default:nyancat", {
	description = S("PB&J Pup"),
	tiles = { "nc_side.png", "nc_side.png", "nc_side.png", "nc_side.png", "nc_back.png", "nc_front.png" },
	paramtype2 = "facedir",
	legacy_facedir_simple = true,
	groups = { stone = 6 },
	is_ground_content = false,
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:nyancat_rainbow", {
	description = S("PB&J Pup Candies"),
	tiles = { "nc_rb.png" },
	groups = { stone = 6 },
	is_ground_content = false,
	sounds = default.node_sound.stone,
})

minetest.register_node(":default:sapling", {
	description = S("Sapling"),
	drawtype = "mesh",
	mesh = "plantlike1.obj",
	use_texture_alpha = "clip",
	tiles = {
		{ name = "sapling.png", backface_culling = true }
	},
	inventory_image = "sapling.png",
	wield_image = "sapling.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	groups = { dig_hand = 2, air_equivalent = 1 },
	is_ground_content = false,
	sounds = default.node_sound.default,
})

minetest.register_node(":default:apple", {
	description = S("Apple"),
	drawtype = "plantlike",
	tiles = { "apple.png" },
	inventory_image = "apple.png",
	wield_image = "apple.png",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	groups = { dig_hand = 2, air_equivalent = 1 },
	is_ground_content = false,
	on_use = minetest.item_eat(4),
	sounds = default.node_sound.default,
})

--
-- Tools
--

local function levels(tbl, m)
	local ret = {}
	for _, n in ipairs(tbl) do
		table.insert(ret, n * m)
	end
	return ret
end

minetest.override_item("", {
	tool_capabilities = {
		-- this is the object_hit_delay in 0.3, SAO code addtl. caps this to
		-- either do full damage or none at all
		full_punch_interval = 0.5,
		groupcaps = {
			dig_hand = { times = { 0.5, 0 }, uses = 0 },
			dirt = { times = levels(default.dirt_levels, 0.75), uses = 0 },
			stone = { times = levels(default.stone_levels, 15), uses = 0 },
			wood = { times = levels(default.wood_levels, 3), uses = 0 },
		},
		damage_groups = { brittle = 5, fleshy = 2 },
	}
})

minetest.register_tool(":default:pick_wood", {
	description = S("Wooden Pickaxe"),
	inventory_image = "tool_woodpick.png",
	tool_capabilities = {
		groupcaps = {
			stone = { times = levels(default.stone_levels, 1.3), uses = 30 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:pick_stone", {
	description = S("Stone Pickaxe"),
	inventory_image = "tool_stonepick.png",
	tool_capabilities = {
		groupcaps = {
			stone = { times = levels(default.stone_levels, 0.75), uses = 100 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:pick_steel", {
	description = S("Steel Pickaxe"),
	inventory_image = "tool_steelpick.png",
	tool_capabilities = {
		full_punch_interval = 0.5,
		groupcaps = {
			stone = { times = levels(default.stone_levels, 0.50), uses = 333 },
		},
		damage_groups = { brittle = 7, fleshy = 3 },
		punch_attack_uses = 100,
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:pick_mese", {
	description = S("Mese Pickaxe"),
	inventory_image = "tool_mesepick.png",
	tool_capabilities = {
		groupcaps = {
			-- digs everything instantly
			dirt = { times = levels(default.dirt_levels, 0), uses = 1337 },
			stone = { times = levels(default.stone_levels, 0), uses = 1337 },
			wood = { times = levels(default.wood_levels, 0), uses = 1337 },
			dig_hand = { times = { 0, 0 }, uses = 1337 },
			dig_mese = { times = { 0 }, uses = 1337 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:shovel_wood", {
	description = S("Wooden Shovel"),
	inventory_image = "tool_woodshovel.png",
	tool_capabilities = {
		groupcaps = {
			dirt = { times = levels(default.dirt_levels, 0.4), uses = 50 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:shovel_stone", {
	description = S("Stone Shovel"),
	inventory_image = "tool_stoneshovel.png",
	tool_capabilities = {
		groupcaps = {
			dirt = { times = levels(default.dirt_levels, 0.2), uses = 150 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:shovel_steel", {
	description = S("Steel Shovel"),
	inventory_image = "tool_steelshovel.png",
	tool_capabilities = {
		groupcaps = {
			dirt = { times = levels(default.dirt_levels, 0.15), uses = 400 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:axe_wood", {
	description = S("Wooden Axe"),
	inventory_image = "tool_woodaxe.png",
	tool_capabilities = {
		groupcaps = {
			wood = { times = levels(default.wood_levels, 1.5), uses = 30 },
		},
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:axe_stone", {
	description = S("Stone Axe"),
	inventory_image = "tool_stoneaxe.png",
	tool_capabilities = {
		full_punch_interval = 0.5,
		groupcaps = {
			wood = { times = levels(default.wood_levels, 0.75), uses = 100 },
		},
		damage_groups = { brittle = 7, fleshy = 3 },
		punch_attack_uses = 100,
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:axe_steel", {
	description = S("Steel Axe"),
	inventory_image = "tool_steelaxe.png",
	tool_capabilities = {
		full_punch_interval = 0.5,
		groupcaps = {
			wood = { times = levels(default.wood_levels, 0.5), uses = 333 },
		},
		damage_groups = { brittle = 9, fleshy = 4 },
		punch_attack_uses = 100,
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:sword_wood", {
	description = S("Wooden Sword"),
	inventory_image = "tool_woodsword.png",
	tool_capabilities = {
		full_punch_interval = 0.5,
		damage_groups = { brittle = 10, fleshy = 4 },
		punch_attack_uses = 100,
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:sword_stone", {
	description = S("Stone Sword"),
	inventory_image = "tool_stonesword.png",
	tool_capabilities = {
		full_punch_interval = 0.5,
		damage_groups = { brittle = 12, fleshy = 6 },
		punch_attack_uses = 100,
	},
	sound = default.tool_sound,
})

minetest.register_tool(":default:sword_steel", {
	description = S("Steel Sword"),
	inventory_image = "tool_steelsword.png",
	tool_capabilities = {
		full_punch_interval = 0.5,
		damage_groups = { brittle = 16, fleshy = 8 },
		punch_attack_uses = 100,
	},
	sound = default.tool_sound,
})

--
-- Items
--

if not default.modernize.wieldhand then
	minetest.override_item("", {
		wield_image = "blank.png",
	})
end

minetest.register_craftitem(":default:stick", {
	description = S("Stick"),
	inventory_image = "stick.png",
	groups = { },
})

minetest.register_craftitem(":default:paper", {
	description = S("Paper"),
	inventory_image = "paper.png",
	groups = { },
})

minetest.register_craftitem(":default:book", {
	description = S("Book"),
	inventory_image = "book.png",
	groups = { },
})

minetest.register_craftitem(":default:lump_of_coal", {
	description = S("Lump of Coal"),
	inventory_image = "lump_of_coal.png",
	groups = { },
})

minetest.register_craftitem(":default:lump_of_iron", {
	description = S("Lump of Iron"),
	inventory_image = "lump_of_iron.png",
	groups = { },
})

minetest.register_craftitem(":default:lump_of_clay", {
	description = S("Lump of Clay"),
	inventory_image = "lump_of_clay.png",
	groups = { },
})

minetest.register_craftitem(":default:steel_ingot", {
	description = S("Steel Ingot"),
	inventory_image = "steel_ingot.png",
	groups = { },
})

minetest.register_craftitem(":default:clay_brick", {
	description = S("Clay Brick"),
	inventory_image = "clay_brick.png",
	groups = { },
})

minetest.register_craftitem(":default:rat", {
	description = S("Rat"),
	inventory_image = "rat.png",
	groups = { },
})

minetest.register_craftitem(":default:cooked_rat", {
	description = S("Cooked Rat"),
	inventory_image = "cooked_rat.png",
	groups = { },
	on_use = minetest.item_eat(6),
})

minetest.register_craftitem(":default:scorched_stuff", {
	description = S("Scorched Stuff"),
	inventory_image = "scorched_stuff.png",
	groups = { },
})

minetest.register_craftitem(":default:firefly", {
	description = S("Firefly"),
	inventory_image = "firefly.png",
	groups = { },
})

minetest.register_craftitem(":default:apple_iron", {
	description = S("Iron Apple"),
	inventory_image = "apple_iron.png",
	groups = { },
	on_use = minetest.item_eat(8),
})

--
-- Crafting
--

minetest.register_craft({
	output = "default:wood 4",
	recipe = {
		{"default:tree"},
	}
})

minetest.register_craft({
	output = "default:stick 4",
	recipe = {
		{"default:wood"},
	}
})

minetest.register_craft({
	output = "default:fence_wood 2",
	recipe = {
		{"default:stick", "default:stick", "default:stick"},
		{"default:stick", "default:stick", "default:stick"},
	}
})

minetest.register_craft({
	output = "default:sign_wall",
	recipe = {
		{"default:wood", "default:wood", "default:wood"},
		{"default:wood", "default:wood", "default:wood"},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:torch 4",
	recipe = {
		{"default:lump_of_coal"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:pick_wood",
	recipe = {
		{"default:wood", "default:wood", "default:wood"},
		{"", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:pick_stone",
	recipe = {
		{"default:cobble", "default:cobble", "default:cobble"},
		{"", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:pick_steel",
	recipe = {
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		{"", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:pick_mese",
	recipe = {
		{"default:mese", "default:mese", "default:mese"},
		{"", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:shovel_wood",
	recipe = {
		{"default:wood"},
		{"default:stick"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:shovel_stone",
	recipe = {
		{"default:cobble"},
		{"default:stick"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:shovel_steel",
	recipe = {
		{"default:steel_ingot"},
		{"default:stick"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:axe_wood",
	recipe = {
		{"default:wood", "default:wood", ""},
		{"default:wood", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:axe_stone",
	recipe = {
		{"default:cobble", "default:cobble", ""},
		{"default:cobble", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:axe_steel",
	recipe = {
		{"default:steel_ingot", "default:steel_ingot", ""},
		{"default:steel_ingot", "default:stick", ""},
		{"", "default:stick", ""},
	}
})

minetest.register_craft({
	output = "default:sword_wood",
	recipe = {
		{"default:wood"},
		{"default:wood"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:sword_stone",
	recipe = {
		{"default:cobble"},
		{"default:cobble"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:sword_steel",
	recipe = {
		{"default:steel_ingot"},
		{"default:steel_ingot"},
		{"default:stick"},
	}
})

minetest.register_craft({
	output = "default:rail 15",
	recipe = {
		{"default:steel_ingot", "default:stick", "default:steel_ingot"},
		{"default:steel_ingot", "default:stick", "default:steel_ingot"},
		{"default:steel_ingot", "default:stick", "default:steel_ingot"},
	}
})

minetest.register_craft({
	output = "default:chest",
	recipe = {
		{"default:wood", "default:wood", "default:wood"},
		{"default:wood", "", "default:wood"},
		{"default:wood", "default:wood", "default:wood"},
	}
})

minetest.register_craft({
	output = "default:chest_locked",
	recipe = {
		{"default:wood", "default:wood", "default:wood"},
		{"default:wood", "default:steel_ingot", "default:wood"},
		{"default:wood", "default:wood", "default:wood"},
	}
})

minetest.register_craft({
	output = "default:furnace",
	recipe = {
		{"default:cobble", "default:cobble", "default:cobble"},
		{"default:cobble", "", "default:cobble"},
		{"default:cobble", "default:cobble", "default:cobble"},
	}
})

minetest.register_craft({
	output = "default:steelblock",
	recipe = {
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	}
})

minetest.register_craft({
	output = "default:sandstone",
	recipe = {
		{"default:sand", "default:sand"},
		{"default:sand", "default:sand"},
	}
})

minetest.register_craft({
	output = "default:clay",
	recipe = {
		{"default:lump_of_clay", "default:lump_of_clay"},
		{"default:lump_of_clay", "default:lump_of_clay"},
	}
})

minetest.register_craft({
	output = "default:brick",
	recipe = {
		{"default:clay_brick", "default:clay_brick"},
		{"default:clay_brick", "default:clay_brick"},
	}
})

minetest.register_craft({
	output = "default:paper",
	recipe = {
		{"default:papyrus", "default:papyrus", "default:papyrus"},
	}
})

minetest.register_craft({
	output = "default:book",
	recipe = {
		{"default:paper"},
		{"default:paper"},
		{"default:paper"},
	}
})

minetest.register_craft({
	output = "default:bookshelf",
	recipe = {
		{"default:wood", "default:wood", "default:wood"},
		{"default:book", "default:book", "default:book"},
		{"default:wood", "default:wood", "default:wood"},
	}
})

minetest.register_craft({
	output = "default:ladder",
	recipe = {
		{"default:stick", "", "default:stick"},
		{"default:stick", "default:stick", "default:stick"},
		{"default:stick", "", "default:stick"},
	}
})

minetest.register_craft({
	output = "default:apple_iron",
	recipe = {
		{"", "default:steel_ingot", ""},
		{"default:steel_ingot", "default:apple", "default:steel_ingot"},
		{"", "default:steel_ingot", ""},
	}
})

--
-- Fuels & Cooking
--

for item, time in pairs({
	["default:tree"]         = 30,
	["default:jungletree"]   = 30,
	["default:fence_wood"]   = 30/2,
	["default:wood"]         = 30/4,
	["default:bookshelf"]    = 30/4,
	["default:leaves"]       = 30/16,
	["default:papyrus"]      = 30/32,
	["default:junglegrass"]  = 30/32,
	["default:cactus"]       = 30/4,
	["default:stick"]        = 30/4/4,
	["default:lump_of_coal"] = 40,
}) do
	minetest.register_craft({
		type = "fuel",
		recipe = item,
		burntime = time,
	})
end

for item_in, item_out in pairs({
	["default:tree"]         = "default:lump_of_coal",
	["default:cobble"]       = "default:stone",
	["default:sand"]         = "default:glass",
	["default:lump_of_iron"] = "default:steel_ingot",
	["default:lump_of_clay"] = "default:clay_brick",
	["default:rat"]          = "default:cooked_rat",
	["default:cooked_rat"]   = "default:scorched_stuff",
}) do
	minetest.register_craft({
		type = "cooking",
		output = item_out,
		recipe = item_in,
	})
end

--
-- Includes
--

local modpath = minetest.get_modpath(minetest.get_current_modname())
dofile(modpath .. "/alias.lua")
dofile(modpath .. "/furnace.lua")
dofile(modpath .. "/sao.lua")
dofile(modpath .. "/mapgen_setup.lua")
dofile(modpath .. "/abm.lua")
if minetest.settings:get_bool("minetest_classic_internal_test") then
	dofile(modpath .. "/test.lua")
end
