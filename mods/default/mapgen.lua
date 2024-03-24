-- Original references:
-- https://github.com/minetest/minetest/blob/stable-0.3/src/mapgen.cpp#L1667

--
-- Setup
--

local MAPGEN_ENV = minetest.save_gen_notify ~= nil

if not minetest.global_exists("default") then
	assert(MAPGEN_ENV)
	default = {}
end

assert(minetest.MAP_BLOCKSIZE == 16) -- calculations would need to be redone

local water_level = tonumber(minetest.get_mapgen_setting("water_level"))

local chunksize = tonumber(minetest.get_mapgen_setting("chunksize"))
-- whole number multiplier used for mapgen processes to account for size difference
-- (0.3 generates one MapBlock at once, later versions use 1 MapChunk = 5*5*5 MapBlocks)
local chunksize_c = math.pow(chunksize, 3)

local FIVE_DIRS = {
	vector.new(-1, 0,  0),
	vector.new( 1, 0,  0),
	vector.new( 0, 0, -1),
	vector.new( 0, 0,  1),
	vector.new( 0, 1,  0),
}

local temple_workaround_needed = true

do
	local spflags = minetest.get_mapgen_setting("mgv6_spflags")
	if spflags:find("temples") then
		temple_workaround_needed = false
	end
end

minetest.log("info", "Desert temple workaround enabled: " .. dump(temple_workaround_needed))

--
-- Custom stuff
--

local np_crumblyness = {
	offset = 0,
	scale = 1, -- = noise_scale
	spread = vector.new(20, 20, 20), -- = pos_scale
	seed = 34413,
	octaves = 3,
	persistence = 1.3,
	lacunarity = 2, -- hardcoded in noise.cpp
}

local np_wetness = {
	offset = 0,
	scale = 1,
	spread = vector.new(40, 40, 40),
	seed = 32474,
	octaves = 4,
	persistence = 1.1,
	lacunarity = 2,
}

local np_clay = {
	offset = 0.5,
	scale = 1,
	spread = vector.new(500, 500, 500),
	seed = 4321,
	octaves = 6,
	persistence = 0.95,
	lacunarity = 2,
	eased = false,
}

local function rand_pos(self, a, b)
	return self.rand:next(a.x+1, b.x-1), self.rand:next(a.y+1, b.y-1), self.rand:next(a.z+1, b.z-1)
end

local function place_some(self, sparseness, x, y, z, content)
	for idx in self.va:iter(x-1, y-1, z-1, x+1, y+1, z+1) do
		if self.data[idx] == self.c_stone and self.rand:next() % sparseness == 0 then
			self.data[idx] = content
		end
	end
end

local function perlin_3d_buf(self, np, buffer)
	-- get map with same dimensions as vmanip area so indices can be reused
	local map = minetest.get_perlin_map(np, self.va:getExtent())
	return map:get_3d_map_flat(self.va.MinEdge, buffer)
end

local function fix_temple(self, cpos, wetness)
	-- Mapgenv6 has generated a desert temple room, great!
	-- Except we don't like that, desert temples weren't in 0.3.
	-- The best we can do here is make an attempt at changing them to at least
	-- resemble normal dungeons, which is what we'll do here.

	-- try to determine room dimensions, walls are stone:
	local d = {}
	for i, dir in ipairs(FIVE_DIRS) do
		local tmp = {}
		for off = -1, 1 do
			local start = vector.offset(cpos,
				i > 2 and off or 0, 0, i <= 2 and off or 0)
			table.insert(tmp, 1, 0)
			for j = 1, (i == 5 and 21 or 9) do
				local check = vector.add(start, vector.multiply(dir, j))
				if self.data[self.va:indexp(check)] == self.c_stone then
					break
				end
				tmp[1] = j
			end
		end
		table.sort(tmp)
		d[i] = tmp[2] -- median of three samples
	end

	-- (debug)
	minetest.log("info", "Fixing desert temple at " .. minetest.pos_to_string(cpos))
	--[[self.data[self.va:indexp(cpos)] = minetest.get_content_id("default:torch")
	for i, off in ipairs(d) do
		local tmp = vector.add(cpos, vector.multiply(FIVE_DIRS[i], off))
		self.data[self.va:indexp(tmp)] = minetest.get_content_id("default:sign_wall")
		minetest.get_meta(tmp):set_string("infotext", tostring(i))
	end--]]

	-- now turn all stone to cobble
	local rmin = vector.new(cpos.x - d[1] - 1, cpos.y        - 1, cpos.z - d[3] - 1)
	local rmax = vector.new(cpos.x + d[2] + 1, cpos.y + d[5] + 1, cpos.z + d[4] + 1)
	local c_cobble = minetest.get_content_id("default:cobble")
	local c_mossycobble = minetest.get_content_id("default:mossycobble")
	for idx in self.va:iterp(rmin, rmax) do
		if self.data[idx] == self.c_stone then
			local v = self.rand:next(0, 40) / 10 - 2
			self.data[idx] = (v < wetness[idx]/3) and c_mossycobble or c_cobble
		end
	end
end

local function make_nc(self, ncrandom, minp, maxp)
	local c_nc = minetest.get_content_id("default:nyancat")
	local c_nc_rb = minetest.get_content_id("default:nyancat_rainbow")
	local dir, facedir_i = vector.zero(), 0
	local r = ncrandom:next(0, 3)
	if r == 0 then
		dir.x = 1
		facedir_i = 3
	elseif r == 1 then
		dir.x = -1
		facedir_i = 1
	elseif r == 2 then
		dir.z = 1
		facedir_i = 2
	else
		dir.z = -1
	end
	local ex = vector.subtract(maxp, minp)
	local p = vector.offset(minp, ncrandom:next(0, ex.x-1),
		ncrandom:next(0, ex.y-1), ncrandom:next(0, ex.z-1))

	minetest.log("info", "Placing nyancat at " .. minetest.pos_to_string(p))

	-- this sets param2 without needing to retrieve the entire buffer
	self.vm:set_node_at(p, { name = "air", param2 = facedir_i })
	self.data[self.va:indexp(p)] = c_nc
	local length = ncrandom:next(3, 15)
	for j = 1, length do
		p = vector.subtract(p, dir)
		self.data[self.va:indexp(p)] = c_nc_rb
	end
end

local cached_buf1 = {}
local cached_buf2 = {}
local cached_buf3 = {}
local cached_buf4 = {}

default.on_generated = function(vmanip, minp, maxp, blockseed)
	if minp.y >= 100 then
		-- high in the air there's nothing, skip
		return
	end

	local self = {
		rand = PseudoRandom(blockseed),

		--va = <VoxelArea>,
		vm = vmanip,
		data = cached_buf1,

		c_stone = minetest.get_content_id("default:stone")
	}
	do
		local emin, emax = self.vm:get_emerged_area()
		self.va = VoxelArea:new({MinEdge=emin, MaxEdge=emax})
		self.vm:get_data(self.data)
	end

	local x, y, z
	local amount
	local crumblyness = perlin_3d_buf(self, np_crumblyness, cached_buf2)
	local wetness = perlin_3d_buf(self, np_wetness, cached_buf3)
	local c_coal = minetest.get_content_id("default:coalstone")
	local c_iron = minetest.get_content_id("default:ironstone")

	-- Before we do anything else: fix desert temples
	if temple_workaround_needed then
		local gennotify = minetest.get_mapgen_object("gennotify")
		for _, pos in ipairs(gennotify.temple or {}) do
			fix_temple(self, pos, wetness)
		end
	end

	-- Mese
	local c_mese = minetest.get_content_id("default:mese")
	-- do this in slices to improve distribution accuracy
	for ii = 0, chunksize - 1 do
		local sminp = vector.offset(minp, 0, ii * 16, 0)
		local smaxp = vector.new(maxp.x, sminp.y + 15, maxp.z)
		-- assume ground level is at zero which simplifies this a lot
		local approx_ground_depth = -(sminp.y + smaxp.y) / 2
		amount = approx_ground_depth / 4
		amount = amount * (chunksize * chunksize)
		for n = 1, amount do
			if self.rand:next() % 50 == 0 then
				x, y, z = rand_pos(self, sminp, smaxp)
				place_some(self, 8, x, y, z, c_mese)
			end
		end
	end

	-- Minerals
	amount = self.rand:next(0, 15)
	amount = 20 * (amount*amount*amount) / 1000
	amount = amount * chunksize_c
	for n = 1, amount do
		x, y, z = rand_pos(self, minp, maxp)
		local mineral
		local idx = self.va:index(x, y+5, z)
		if crumblyness[idx] < -0.1 then
			mineral = c_coal
		elseif wetness[idx] > 0 then
			mineral = c_iron
		end
		if mineral ~= nil then
			place_some(self, 6, x, y, z, mineral)
		end
	end

	-- More coal
	local coal_amount = 30
	for ii = 1, chunksize_c do
		if self.rand:next() % math.floor(60 / coal_amount) == 0 then
			amount = self.rand:next(0, 15)
			amount = coal_amount * (amount*amount*amount) / 1000
			for n = 1, amount do
				x, y, z = rand_pos(self, minp, maxp)
				place_some(self, 8, x, y, z, c_coal)
			end
		end
	end

	-- More iron
	local iron_amount = 8
	for ii = 1, chunksize_c do
		if self.rand:next() % math.floor(60 / iron_amount) == 0 then
			amount = self.rand:next(0, 15)
			amount = iron_amount * (amount*amount*amount) / 1000
			for n = 1, amount do
				x, y, z = rand_pos(self, minp, maxp)
				place_some(self, 8, x, y, z, c_iron)
			end
		end
	end

	-- Gravel
	-- mgv6 takes care of sand and mud already and generates way
	-- less than 0.3 would have but we don't have a say in that.
	local c_gravel = minetest.get_content_id("default:gravel")
	for x = minp.x, maxp.x do
	for z = minp.z, maxp.z do
		for idx in self.va:iter(x, minp.y, z, x, maxp.y, z) do
			if self.data[idx] == self.c_stone then
				if crumblyness[idx] <= 1.3 and crumblyness[idx] > 0.7 and wetness[idx] < -0.6 then
					self.data[idx] = c_gravel
				end
			end
		end
	end
	end

	-- Generating dungeons is left up to the mapgen

	-- Nyancats
	local ncrandom = PseudoRandom(blockseed+9324342)
	-- same slice method here so they don't inadvertently appear above ground
	for ii = 0, chunksize - 1 do
		local sminp = vector.offset(minp, 0, ii * 16, 0)
		local smaxp = vector.new(maxp.x, sminp.y + 15, maxp.z)
		if sminp.y <= -3 then
			for ii = 1, (chunksize * chunksize) do
				if ncrandom:next(0, 1000) == 0 then
					make_nc(self, ncrandom, sminp, smaxp)
				end
			end
		end
	end

	-- Clay
	-- The condition for clay is as follows:
	-- (0, 1 or 2 nodes below water level) and (at the surface or one node deep)
	-- and (where sand is) and (noise comparison suceeds)
	local c_sand = minetest.get_content_id("default:sand")
	local c_clay = minetest.get_content_id("default:clay")
	local c_water = minetest.get_content_id("default:water_source")
	if minp.y <= water_level-2 and water_level+1 <= maxp.y then
		local claynoise = minetest.get_perlin_map(np_clay,
			{x=maxp.x - minp.x + 1, y=maxp.z - minp.z + 1}):get_2d_map_flat(
			{x=minp.x, y=minp.z}, cached_buf4)
		local stride = maxp.x - minp.x + 1
		--
		local idx
		local depth, val
		for x = minp.x, maxp.x do
		for z = minp.z, maxp.z do
			depth = 0
			-- y+1 to detect surface
			for y = water_level + 1, water_level - 2, -1 do
				idx = self.va:index(x, y, z)
				if y <= water_level and depth <= 1 and self.data[idx] == c_sand then
					val = claynoise[(z - minp.z) * stride + (x - minp.x) + 1]
					if val > 0 and val < (depth == 1 and 0.12 or 0.04) then
						self.data[idx] = c_clay
					end
				end
				if depth > 0 and self.data[idx] ~= core.CONTENT_AIR and self.data[idx] ~= c_water then
					depth = depth + 1
				end
			end
		end
		end
	end

	self.vm:set_data(self.data)
	if not MAPGEN_ENV then
		self.vm:write_to_map()
	end
end

if MAPGEN_ENV then
	minetest.register_on_generated(default.on_generated)
end
