local function wait_map(callback)
	local pos = vector.new(5, 30, 5)
	for y = 0, 4 do
		assert(minetest.forceload_block(
			vector.new(pos.x, y*16, pos.z), true, -1
		))
	end

	local function check()
		if minetest.get_node(pos).name ~= "ignore" then
			return callback(pos)
		end
		minetest.after(0, check)
	end
	check()
end

do
	local v = minetest.get_version()
	minetest.log("action", "Engine version: " .. (v.hash or v.string))
end

minetest.after(0, function()
	wait_map(function(pos)
		for x = -1, 1 do
		for z = -1, 1 do
			minetest.add_node(pos:offset(x, 0, z), {name="default:dirt"})
		end
		end

		pos = pos:offset(0, 1, 0)
		assert(minetest.add_entity(pos, "default:rat") ~= nil)
		assert(minetest.add_entity(pos, "default:oerkki1") ~= nil)
		assert(minetest.add_entity(pos, "default:firefly") ~= nil)
		assert(default.spawn_mobv2(pos, default.get_mob_dungeon_master()) ~= nil)

		minetest.after(2.5, function()
			minetest.log("action", "Exiting test run.")
			minetest.request_shutdown()
		end)
	end)
end)

