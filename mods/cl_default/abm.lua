-- Original reference:
-- https://github.com/minetest/minetest/blob/stable-0.3/src/environment.cpp#L929
-- treegen https://github.com/minetest/minetest/blob/stable-0.3/src/mapgen.cpp#L83

-- Convert grass into mud if under something else than air
minetest.register_abm({
	label = "Mud to Grass",
	nodenames = {"default:dirt"},
	neighbors = {"group:air_equivalent"},
	interval = 10,
	chance = 20,
	catch_up = false, -- Back in my day we had no such thing
	action = function(pos, node)
		local p1 = vector.offset(pos, 0, 1, 0)
		local above = minetest.get_node(p1)
		if minetest.get_item_group(above.name, "air_equivalent") > 0 and minetest.get_node_light(p1) >= 13 then
			node.name = "default:dirt_with_grass"
			minetest.swap_node(pos, node)
		end
	end,
})

-- Convert grass into mud if under something else than air
minetest.register_abm({
	label = "Grass to Mud",
	nodenames = {"default:dirt_with_grass"},
	interval = 10,
	catch_up = false,
	action = function(pos, node)
		local above = minetest.get_node(vector.offset(pos, 0, 1, 0))
		if minetest.get_item_group(above.name, "air_equivalent") == 0 then
			node.name = "default:dirt"
			minetest.swap_node(pos, node)
		end
	end,
})

-- Rats spawn around regular trees
minetest.register_abm({
	label = "Rat Spawning",
	nodenames = {"default:tree", "default:jungletree"},
	interval = 10,
	chance = 200,
	catch_up = false,
	action = function(pos, node, active_object_count, active_object_count_wider)
		-- FIXME: this becomes problematic if users use other mods that spawn entities
		if active_object_count_wider > 0 then
			return
		end
		pos.x = pos.x + math.random(-2, 2)
		pos.z = pos.z + math.random(-2, 2)
		node = minetest.get_node(pos)
		local below = minetest.get_node(vector.offset(pos, 0, -1, 0))
		if below.name == "default:dirt_with_grass" and node.name == "air" then
			minetest.add_entity(pos, "default:rat")
		end
	end,
})

-- Fun things spawn in caves and dungeons
minetest.register_abm({
	label = "Mob Spawning",
	nodenames = {"default:stone", "default:mossycobble"},
	interval = 10,
	chance = 200,
	catch_up = false,
	action = function(pos, node, active_object_count, active_object_count_wider)
		if active_object_count_wider > 0 then
			return
		end
		local p1 = vector.offset(pos, 0, 1, 0)
		if (minetest.get_node_light(p1) or 0) <= 3 then
			if minetest.get_node(p1).name == "air" and
				minetest.get_node(vector.offset(p1, 0, 1, 0)).name == "air" then
				local i = math.random(0, 5)
				if i == 0 or i == 1 then
					minetest.log("action", "A dungeon master spawns at " ..
						minetest.pos_to_string(p1))
					default.spawn_mobv2(p1, default.get_mob_dungeon_master())
				elseif i == 2 or i == 3 then
					minetest.log("action", "Rats spawn at " ..
						minetest.pos_to_string(p1))
					for j = 1, 3 do
						minetest.add_entity(p1, "default:rat")
					end
				else
					minetest.log("action", "An oerkki spawns at " ..
						minetest.pos_to_string(p1))
					minetest.add_entity(p1, "default:oerkki1")
				end
			end
		end
	end,
})

-- Make trees from saplings!
default.make_tree = function(vm, p0, is_apple_tree)
	local n_tree = {name = "default:tree"}
	local n_leaves = {name = "default:leaves"}
	local n_apple = {name = "default:apple"}

	local trunk_h = math.random(4, 5)
	local p1 = p0
	for ii = 1, trunk_h do
		vm:set_node_at(p1, n_tree)
		p1.y = p1.y + 1
	end

	-- p1 is now the last piece of the trunk
	p1.y = p1.y - 1

	local leaves_a = VoxelArea:new({MinEdge = vector.new(-2,-1,-2),
		MaxEdge = vector.new(2,1,2)})
	local leaves_d = {}

	-- Force leaves near the end of the trunk
	local d = 1
	for z = -d, d do
	for y = -d, d do
	for x = -d, d do
		leaves_d[leaves_a:index(x, y, z)] = true
	end
	end
	end

	-- Add leaves randomly
	for iii = 1, 7 do
		local p = vector.combine(leaves_a.MinEdge, vector.add(leaves_a.MaxEdge, -d), math.random)

		for z = 0, d do
		for y = 0, d do
		for x = 0, d do
			leaves_d[leaves_a:index(p.x + x, p.y + y, p.z + z)] = true
		end
		end
		end
	end

	-- Blit leaves to vmanip
	for z = leaves_a.MinEdge.z, leaves_a.MaxEdge.z do
	for y = leaves_a.MinEdge.y, leaves_a.MaxEdge.y do
	for x = leaves_a.MinEdge.x, leaves_a.MaxEdge.x do
		local p = vector.add(vector.new(x, y, z), p1)
		local node = vm:get_node_at(p)
		if node.name == "air" or node.name == "ignore" then
			if leaves_d[leaves_a:index(x, y, z)] then
				if is_apple_tree and math.random(0, 99) < 10 then
					vm:set_node_at(p, n_apple)
				else
					vm:set_node_at(p, n_leaves)
				end
			end
		end
	end
	end
	end
end

minetest.register_abm({
	label = "Saplings",
	nodenames = {"default:sapling"},
	interval = 10,
	chance = 50,
	catch_up = false,
	action = function(pos, node)
		minetest.log("action", "A sapling grows into a tree at " ..
			minetest.pos_to_string(pos))

		local vm = minetest.get_voxel_manip()
		-- 1 extra block on each side
		local bs = vector.new(minetest.MAP_BLOCKSIZE, minetest.MAP_BLOCKSIZE, minetest.MAP_BLOCKSIZE)
		vm:read_from_map(vector.subtract(pos, bs), vector.add(pos, bs))

		local is_apple_tree = math.random(0, 4) == 0
		default.make_tree(vm, pos, is_apple_tree)

		if default.modernize.sounds then
			-- a tree magically pops into existence so add a sound cue
			minetest.sound_play("leaves", {
				pos = pos
			}, true)
		end

		vm:write_to_map()
	end,
})
