-- https://github.com/minetest/minetest/blob/stable-0.3/src/content_nodemeta.cpp#L186

local S = default.get_translator

local function get_cooked(item)
	if not item:is_empty() then
		local ret = minetest.get_craft_result({
			method = "cooking",
			items = {item}
		})
		if not ret.item:is_empty() then
			return ret
		end
	end
end

-- TODO should probably support replacements

-- Note that the engine only reports meta updates if values actually change
-- so this function has okayish efficiency despite updating the infotext every run.
local function furnace_step(meta, inv, dtime)
	local src_item = inv:get_stack("src", 1)
	local cooked = get_cooked(src_item)

	local room_available = cooked and inv:room_for_item("dst", cooked.item)

	-- Start only if there are free slots in dst, so that it can
	-- accomodate any result item
	local src_totaltime = 0
	if room_available then
		src_totaltime = cooked.time
	else
		meta:set_float("src_time", 0)
	end

	-- If fuel is burning, increment the burn counters.
	-- If item finishes cooking, move it to result.
	local m_fuel_time = meta:get_float("fuel_time")
	local m_fuel_totaltime = meta:get_float("fuel_totaltime")
	if m_fuel_time < m_fuel_totaltime then
		m_fuel_time = m_fuel_time + dtime
		local m_src_time = meta:get_float("src_time")
		m_src_time = m_src_time + dtime
		if m_src_time >= src_totaltime and src_totaltime > 0.001 and cooked then
			inv:add_item("dst", cooked.item)
			src_item:take_item(1)
			inv:set_stack("src", 1, src_item)
			m_src_time = 0
		end

		meta:set_float("fuel_time", m_fuel_time)
		meta:set_float("src_time", m_src_time)
		local s = S("Furnace is active")
		if m_fuel_totaltime > 3 then -- so it doesn't always show (0%) for weak fuel
			s = S("Furnace is active (@1%)", math.floor(m_fuel_time/m_fuel_totaltime*100))
		end
		meta:set_string("infotext", s)

		-- If the fuel was not used up this step, just keep burning it
		if m_fuel_time < m_fuel_totaltime then
			return
		end
	else
		local s = S("Furnace is inactive")
		if cooked then
			s = room_available and S("Furnace is out of fuel") or S("Furnace is overloaded")
		end
		meta:set_string("infotext", s)
	end

	-- Get the source again in case it has all burned
	if src_item:is_empty() then
		src_item = inv:get_stack("src", 1)
		cooked = get_cooked(src_item)
		room_available = cooked and inv:room_for_item("dst", cooked.item)
	end

	-- If there is no source item, or the source item is not cookable,
	-- or the furnace became overloaded, stop.
	if not room_available then
		return false
	end

	local fuel_item = inv:get_stack("fuel", 1)
	local fuel = minetest.get_craft_result({
		method = "fuel",
		items = {fuel_item}
	})
	if fuel.time > 0 then
		meta:set_float("fuel_totaltime", fuel.time)
		meta:set_float("fuel_time", 0)
		fuel_item:take_item(1)
		inv:set_stack("fuel", 1, fuel_item)
	else
		-- No fuel, stop loop.
		meta:set_string("infotext", S("Furnace is out of fuel"))
		return false
	end
end

local FURNACE_INTERVAL = 2
local FURNACE_FORMSPEC = (
	"size[8,9]"..
	"list[current_name;fuel;2,3;1,1;]"..
	"list[current_name;src;2,1;1,1;]"..
	"list[current_name;dst;5,1;2,2;]"..
	"list[current_player;main;0,5;8,4;]"..
	"listring[context;dst]"..
	"listring[current_player;main]"..
	"listring[context;src]"..
	"listring[current_player;main]"..
	"listring[context;fuel]"..
	"listring[current_player;main]"
)

minetest.override_item("default:furnace", {
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", FURNACE_FORMSPEC)
		meta:set_string("infotext", S("Furnace is inactive"))
		local inv = meta:get_inventory()
		inv:set_size("fuel", 1)
		inv:set_size("src", 1)
		inv:set_size("dst", 4)

		minetest.get_node_timer(pos):start(FURNACE_INTERVAL)
	end,

	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("fuel") and inv:is_empty("src") and inv:is_empty("dest")
	end,

	on_timer = function(pos, elapsed)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()

		if elapsed > 60 then
			minetest.log("info", "Furnace stepping a long time (" .. elapsed .. ")")
		end
		-- Update at a fixed frequency
		while elapsed >= FURNACE_INTERVAL do
			if furnace_step(meta, inv, FURNACE_INTERVAL) == false then
				break
			end
			elapsed = elapsed - FURNACE_INTERVAL
		end
		return true
	end,

	--on_punch = function(pos, node)
	--	local meta = minetest.get_meta(pos)
	--	print(dump(meta:to_table()))
	--end,
})
