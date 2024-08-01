-- Original references:
-- https://github.com/minetest/minetest/blob/stable-0.3/src/mapgen.cpp#L1667

--
-- General
--

if table.indexof({"v6", "singlenode"}, minetest.get_mapgen_setting("mg_name")) == -1 then
	error("Minetest Classic only works with the v6 map generator")
end

local water_level = tonumber(minetest.get_mapgen_setting("water_level"))

do
	local spflags = minetest.get_mapgen_setting("mgv6_spflags")
	spflags = string.split(spflags, ",", false)
	for i, v in ipairs(spflags) do
		-- force snow biomes off
		if v:find("snowbiomes") then
			spflags[i] = "nosnowbiomes"
		end
		-- disable temples too, if the engine supports it (5.9.0)
		if v:find("temples") then
			spflags[i] = "notemples"
		end
	end
	spflags = table.concat(spflags, ",")
	minetest.set_mapgen_setting("mgv6_spflags", spflags, true)
end

for k, v in pairs({
	mapgen_stone = "default:stone",
	mapgen_water_source = "default:water_source",
	mapgen_lava_source = "default:lava_source",
	mapgen_dirt = "default:dirt",
	mapgen_dirt_with_grass = "default:dirt_with_grass",
	mapgen_sand = "default:sand",
	mapgen_tree = "default:tree",
	mapgen_leaves = "default:leaves",
	mapgen_apple = "default:apple",
	mapgen_jungletree = "default:jungletree",
	mapgen_jungleleaves = "default:jungleleaves",
	mapgen_junglegrass = "default:junglegrass",
	mapgen_cobble = "default:cobble",
	mapgen_mossycobble = "default:mossycobble",
}) do
	minetest.register_alias(k, v)
end

--
-- Decorations
--

local np_tree_amount = {
	-- transformed from '0.04 * (x+0.39) / (1+0.39)'
	offset = 0.01122,
	scale = 0.02877,
	spread = vector.new(125, 125, 125),
	seed = 2,
	octaves = 4,
	persistence = 0.66,
	lacunarity = 2,
	-- Limitation: Can't model that jungles are supposed to have 5x as many trees
	-- (combination with another noise in original code)
}

minetest.register_decoration({
	deco_type = "simple",
	place_on = {"default:dirt"},

	-- Papyrus is part of the tree placing code in 0.3, which tries to place
	-- a certain random amount of trees in a mapblock. This maps to the current
	-- deco mechanism very well.
	sidelen = 16,
	noise_params = np_tree_amount,

	y_min = water_level - 1,
	y_max = water_level - 1,

	decoration = "default:papyrus",
	height = 2,
	height_max = 3,

	-- need this to replace water
	flags = "force_placement",
})

minetest.register_decoration({
	deco_type = "simple",
	place_on = {"default:sand"},

	-- same as above
	sidelen = 16,
	noise_params = np_tree_amount,

	y_min = water_level + 1,
	y_max = 4,

	decoration = "default:cactus",
	height = 3,
})

-- TODO junglegrass can sit on top of cacti, consider emulating that

--
-- on_generated
--

-- It's possible someone would want ores to be generated in
-- a singlenode map, but the chance is very slim. So leave it alone.
if minetest.get_mapgen_setting("mg_name") ~= "singlenode" then

	minetest.set_gen_notify({temple = true})

	local script = minetest.get_modpath(minetest.get_current_modname()) .. "/mapgen.lua"

	-- Mapgen Lua environment (5.9.0)
	if minetest.register_mapgen_script then
		minetest.log("info", "Using threaded mapgen")
		minetest.register_mapgen_script(script)
	else
		dofile(script)
		minetest.register_on_generated(function(minp, maxp, blockseed)
			local vm = minetest.get_mapgen_object("voxelmanip")
			default.on_generated(vm, minp, maxp, blockseed)
		end)
	end
end

-- for mapgen debugging
-- luacheck: ignore 511
if false then
	minetest.override_item("default:stone", { drawtype = "airlike" })
	local hl = {"coalstone", "ironstone", "mese", "clay", "gravel", "nyancat", "nyancat_rainbow"}
	for _, s in ipairs(hl) do
		minetest.override_item("default:" .. s, {
			paramtype = "light",
			light_source = 8,
		})
	end
	minetest.register_on_newplayer(function(player)
		player:get_inventory():add_item("main", "default:pick_mese")
	end)
end
