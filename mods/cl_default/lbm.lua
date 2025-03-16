-- Original reference:
-- https://github.com/minetest/minetest/blob/stable-0.3/src/environment.cpp#L622

local GRASS_GROWTH_DTIME = 300

local function maybe_replace_dirt(pos, p1)
	-- This originally operated on blocks so the above node for the topmost node
	-- would not be available, meaning the conversion could never happen for it.
	if pos.y % 16 == 15 then
		return
	end
	local above = core.get_node(p1)
	if core.get_item_group(above.name, "air_equivalent") > 0 and core.get_node_light(p1, 0.5) >= 13 then
		core.swap_node(pos, {name="default:dirt_with_grass"})
	end
end

local encpos, decpos = core.hash_node_position, core.get_position_from_hash
local lbm_def = {
	label = "Convert to grass",
	name = ":default:convert_to_grass",
	nodenames = {"default:dirt"},
	run_at_every_load = true,
	bulk_action = function(pos_list, dtime_s)
		if dtime_s <= GRASS_GROWTH_DTIME then
			return
		end
		local map = {}
		for _, pos in ipairs(pos_list) do
			map[encpos(pos)] = true
		end
		for h, _ in pairs(map) do
			-- We want to work on dirt nodes that are below air, so if we can tell
			-- that the above space is dirt we can immediately skip.
			local pos = decpos(h)
			local p1 = vector.offset(pos, 0, 1, 0)
			if not map[encpos(p1)] then
				maybe_replace_dirt(pos, p1)
			end
		end
	end,
	action = function(pos, node, dtime_s)
		if dtime_s == nil then
			return -- (since 5.7.0)
		end
		if dtime_s > GRASS_GROWTH_DTIME then
			local p1 = vector.offset(pos, 0, 1, 0)
			maybe_replace_dirt(pos, p1)
		end
	end
}

if core.features.bulk_lbms then
	lbm_def.action = nil
else
	lbm_def.bulk_action = nil
end
core.register_lbm(lbm_def)
