std = "lua51"
unused_args = false
allow_defined_top = true

globals = {
	"default"
}

read_globals = {
	"minetest",
	"dump",
	"vector",
	"VoxelManip", "VoxelArea",
	"PseudoRandom", "PcgRandom",
	"ItemStack",
	"Settings",
	-- Minetest specifics
	math = { fields = { "round" } },
	string = { fields = { "split" } },
	table = { fields = { "shuffle", "copy", "indexof" } },
}

-- reference: <https://luacheck.readthedocs.io/en/stable/warnings.html>
ignore = {
	"312", "411", "412", "421", "422", "631",
}

-- Overwrites fields in minetest
files["mods/default/init.lua"].globals = { "minetest" }
files["mods/creative/init.lua"].globals = { "minetest" }
