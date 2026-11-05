--[[
	SCHWEIZER MAP GENERATOR - VERSION 40
	Flache Ebene, 2 grosse Huegel, Bergkranz, grosser See mit Viadukt,
	1 Fluss mit Wasserfall, 12 Strassen, 6 Doerfer, Wald.
	Alle Strassen bleiben ausserhalb der Berge.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local terrain = Workspace.Terrain
local E = Enum.Material

----------------------------------------------------------------
-- EINSTELLUNGEN
----------------------------------------------------------------
local SIZE_X, SIZE_Z = 6000, 4480
local HALF_X, HALF_Z = SIZE_X / 2, SIZE_Z / 2
local VOX = 4
local NX = math.floor(SIZE_X / VOX)
local NZ = math.floor(SIZE_Z / VOX)
local BASEY = -32
local NY = 220
local WL = 20
local PLAIN = 24
local LAKE_BED = 10
local PAINT_HALF = 12      -- Asphalt-Pinsel im Terrain (schmal!)
local ROAD_HALF = 16       -- Strassen-Part (deckt den Pinsel ab)
local ROAD_TOP = 0.9
local ROAD_EMBED = 1.1
local RIVER_HALF = 15
local RIVER_BED = 13
local VIADUCT_H = 13       -- Fahrbahn ueber Wasserspiegel
local TREE_COUNT = 1700
local SEED = 11.37
math.randomseed(2026)

----------------------------------------------------------------
-- HELFER
----------------------------------------------------------------
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function sstep(a, b, x)
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
local function nz(x, z, s)
	return math.noise(x + 0.37, z + 0.71, SEED + (s or 0)) * 2
end
local function IDX(i, k) return (i - 1) * NZ + k end
local T0 = os.clock()

print("[v40] Start...")
terrain:Clear()
local old = Workspace:FindFirstChild("SwissMap")
if old then old:Destroy() end
local map = Instance.new("Folder")
map.Name = "SwissMap"
map.Parent = Workspace

----------------------------------------------------------------
-- GRUNDHOEHEN
----------------------------------------------------------------
local LAKE = { x = 1250, z = 200, rx = 640, rz = 430 }

local function lakeMask(x, z)
	local dx = (x - LAKE.x) / LAKE.rx
	local dz = (z - LAKE.z) / LAKE.rz
	local d = math.sqrt(dx * dx + dz * dz) + nz(x / 170, z / 170, 10) * 0.09
	return 1 - sstep(0.30, 1.00, d)
end

local function mountainBlendAt(x, z)
	local edgeDistance = math.min(HALF_X - math.abs(x), HALF_Z - math.abs(z))
	local wobble = nz(x / 400, z / 400, 12) * 60
	return 1 - sstep(520, 760, edgeDistance + wobble)
end

local HILLS = {
	{ x = -950, z = -350, rx = 1500, rz = 1150, h = 28 },
	{ x = 700,  z = 1050, rx = 1300, rz = 1000, h = 20 },
}

local function heightRaw(x, z)
	local h = PLAIN + nz(x / 950, z / 950, 31) * 1.6 + nz(x / 420, z / 420, 32) * 0.5
	for i, hill in ipairs(HILLS) do
		local dx = (x - hill.x) / hill.rx
		local dz = (z - hill.z) / hill.rz
		local r = math.sqrt(dx * dx + dz * dz) + nz(x / 300, z / 300, 40 + i) * 0.08
		local t = clamp(1 - r, 0, 1)
		h = h + hill.h * (t * t * (3 - 2 * t))
	end
	local mb = mountainBlendAt(x, z)
	if mb > 0 then
		local ridge = nz(x / 300, z / 300, 23)
		local peak = 1 - math.abs(nz(x / 150, z / 150, 24))
		local sharp = peak * peak * peak
		h = lerp(h, 300 + ridge * 110 + sharp * 340 + nz(x / 55, z / 55, 25) * 16, mb)
	end
	h = lerp(h, LAKE_BED, lakeMask(x, z))
	if lakeMask(x, z) < 0.02 then h = math.max(h, WL + 2) end
	return clamp(h, 2, 850)
end

----------------------------------------------------------------
-- DOERFER (Boden vorher flach)
----------------------------------------------------------------
local V2 = function(x, z) return Vector2.new(x, z) end

local TOWNS = {
	{ name = "Oberried",  x = -900,  z = -600, church = true },
	{ name = "Talbach",   x = -950,  z = 450,  church = false },
	{ name = "Bergheim",  x = 650,   z = -550, church = false },
	{ name = "Seeburg",   x = 400,   z = 1050, church = true },
	{ name = "Ostegg",    x = 1700,  z = 1000, church = false },
	{ name = "Westhalde", x = -1750, z = 950,  church = false },
}
do
	local ok = {}
	for _, t in ipairs(TOWNS) do
		t.h = heightRaw(t.x, t.z)
		if t.h > WL + 6 and t.h < 200 and lakeMask(t.x, t.z) < 0.05 then
			ok[#ok + 1] = t
		else
			print("[v40] Dorf " .. t.name .. " uebersprungen")
		end
	end
	TOWNS = ok
end

local function heightPlain(x, z)
	local h = heightRaw(x, z)
	for _, t in ipairs(TOWNS) do
		local d = math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2)
		if d < 130 then h = lerp(h, t.h, 1 - sstep(70, 130, d)) end
	end
	return h
end

----------------------------------------------------------------
-- FLUSS (Ost -> West in den See) mit Wasserfall
----------------------------------------------------------------
local RIVER_PTS = {
	V2(2280, 700), V2(2160, 650), V2(2060, 590), V2(1950, 530),
	V2(1870, 470), V2(1790, 405),
}

local fRiver = {}
do
	local function splat(x, z, radius)
		local cx = math.floor((x + HALF_X) / VOX) + 1
		local cz = math.floor((z + HALF_Z) / VOX) + 1
		local r = math.ceil(radius / VOX)
		local r2 = radius * radius
		for di = -r, r do
			local i = cx + di
			if i >= 1 and i <= NX then
				local px = -HALF_X + (i - 0.5) * VOX
				local dx = px - x
				local base = (i - 1) * NZ
				for dk = -r, r do
					local k = cz + dk
					if k >= 1 and k <= NZ then
						local pz = -HALF_Z + (k - 0.5) * VOX
						local d2 = dx * dx + (pz - z) * (pz - z)
						if d2 <= r2 then
							local id = base + k
							local ov = fRiver[id]
							if ov == nil or d2 < ov then fRiver[id] = d2 end
						end
					end
				end
			end
		end
	end
	for i = 1, #RIVER_PTS - 1 do
		local a, b = RIVER_PTS[i], RIVER_PTS[i + 1]
		local steps = math.max(1, math.ceil((b - a).Magnitude / 6))
		for s = 0, steps - 1 do
			local p = a:Lerp(b, s / steps)
			splat(p.X, p.Y, 60)
		end
	end
end
print("[v40] Fluss gebacken")

local function heightWithRiver(x, z)
	local h = heightPlain(x, z)
	local i = clamp(math.floor((x + HALF_X) / VOX) + 1, 1, NX)
	local k = clamp(math.floor((z + HALF_Z) / VOX) + 1, 1, NZ)
	local d2 = fRiver[IDX(i, k)]
	if not d2 then return h end
	local d = math.sqrt(d2)
	local blend = 44
	if d < RIVER_HALF + blend then
		local target = RIVER_BED
		if h > WL + 30 then target = math.max(RIVER_BED, h - 3) end
		local t = 1 - sstep(RIVER_HALF * 0.55, RIVER_HALF + blend, d)
		h = lerp(h, math.min(h, target), t)
	end
	return h
end

----------------------------------------------------------------
-- STRASSEN-NETZ  (alles innerhalb |x|<=2100, |z|<=1350)
----------------------------------------------------------------
local N = {
	A1 = V2(-1950, -700), A2 = V2(-750, -780), A3 = V2(450, -700),
	A4 = V2(1550, -720),  A5 = V2(2100, -800),
	B1 = V2(-1950, 250),  B2 = V2(-750, 300),  B4 = V2(2100, 350),
	C1 = V2(-1950, 1150), C2 = V2(-750, 1100), C3 = V2(450, 1200),
	C4 = V2(1550, 1150),  C5 = V2(2100, 1200),
	D1 = V2(-1500, -1350), D2 = V2(1250, -1350), D3 = V2(2100, -1350),
	E1 = V2(-1500, 1350),  E2 = V2(1250, 1350),  E3 = V2(2100, 1350),
}

local ROADS = {
	{ name = "Nordstrasse", pts = {
		N.A1, V2(-1350, -820), N.A2, V2(-150, -840), N.A3,
		V2(950, -800), N.A4, V2(1900, -880), N.A5 } },
	{ name = "Suedstrasse", pts = {
		N.C1, V2(-1350, 1050), N.C2, V2(-150, 1120), N.C3,
		V2(950, 1080), N.C4, V2(1900, 1140), N.C5 } },
	{ name = "Westrand", pts = {
		N.D1, V2(-2050, -300), N.A1, N.B1, N.C1, V2(-2050, 800), N.E1 } },
	{ name = "Westmitte", pts = { N.A2, N.B2, N.C2 } },
	{ name = "Seestrasse", pts = {
		N.D2, V2(1250, -600), N.E2 } },
	{ name = "Ostrand", pts = {
		N.D3, N.A5, N.B4, N.C5, N.E3 } },
	{ name = "Diagonale NW", pts = {
		N.D1, V2(-1100, -1050), N.A2 } },
	{ name = "Diagonale SW", pts = {
		N.E1, V2(-1100, 1250), N.C2 } },
	{ name = "Diagonale NO", pts = {
		N.A4, V2(1850, -200), N.B4 } },
	{ name = "Diagonale SO", pts = {
		N.C4, V2(1850, 750), N.B4 } },
	{ name = "Nordquer", pts = { N.A4, N.D2 } },
	{ name = "Suedquer", pts = { N.C4, N.E2 } },
}

local function spline(pts, step)
	step = step or 6
	local out, n = {}, #pts
	for i = 1, n - 1 do
		local p0 = pts[math.max(i - 1, 1)]
		local p1, p2 = pts[i], pts[i + 1]
		local p3 = pts[math.min(i + 2, n)]
		local steps = math.max(2, math.ceil((p2 - p1).Magnitude / step))
		for s = 0, steps - 1 do
			local t = s / steps
			out[#out + 1] = 0.5 * ((2 * p1) + (p2 - p0) * t
				+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
				+ (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)
		end
	end
	out[#out + 1] = pts[n]
	return out
end

local BUILT = {}
for idx, def in ipairs(ROADS) do
	local P = spline(def.pts, 6)
	local hs = {}
	for i, p in ipairs(P) do hs[i] = heightPlain(p.X, p.Y) end
	for _ = 1, 16 do
		local n = {}
		for i = 1, #P do
			local s, c = 0, 0
			for j = math.max(1, i - 12), math.min(#P, i + 12) do s += hs[j]; c += 1 end
			n[i] = s / c
		end
		hs = n
	end

	-- Wasserstellen = Viadukt
	local wet = {}
	local anyWet = false
	for i, p in ipairs(P) do
		wet[i] = heightPlain(p.X, p.Y) < WL
		if wet[i] then anyWet = true end
	end
	if anyWet then
		for i = 1, #P do
			if wet[i] then hs[i] = WL + VIADUCT_H end
		end
		for _ = 1, 8 do
			local n = {}
			for i = 1, #P do
				if wet[i] then
					n[i] = hs[i]
				else
					local s, c = 0, 0
					for j = math.max(1, i - 5), math.min(#P, i + 5) do s += hs[j]; c += 1 end
					n[i] = s / c
				end
			end
			hs = n
		end
	end

	BUILT[idx] = { def = def, P = P, hs = hs, wet = wet }
	task.wait()
end

-- gemeinsame Knoten exakt gleich hoch
for ia = 1, #BUILT do
	for ib = ia + 1, #BUILT do
		local A, B = BUILT[ia], BUILT[ib]
		for i, p in ipairs(A.P) do
			for j, q in ipairs(B.P) do
				if math.abs(p.X - q.X) < 0.5 and math.abs(p.Y - q.Y) < 0.5 then
					local avg = (A.hs[i] + B.hs[j]) / 2
					A.hs[i] = avg
					B.hs[j] = avg
				end
			end
		end
	end
	task.wait()
end

-- Viadukt-Laeufe
local VIADUCTS = {}
for _, r in ipairs(BUILT) do
	local start = nil
	for i = 1, #r.P do
		local w = r.wet[i]
		if w and not start then start = i end
		if (not w or i == #r.P) and start then
			local iEnd = w and i or (i - 1)
			local a, b = r.P[start], r.P[iEnd]
			if (b - a).Magnitude > 4 then
				VIADUCTS[#VIADUCTS + 1] = {
					x = (a.X + b.X) / 2, z = (a.Y + b.Y) / 2,
					y = (r.hs[start] + r.hs[iEnd]) / 2,
					dirx = b.X - a.X, dirz = b.Y - a.Y,
					len = (b - a).Magnitude,
					ax = a.X, az = a.Y, bx = b.X, bz = b.Y,
				}
			end
			start = nil
		end
	end
end
print(("[v40] %d Viadukte"):format(#VIADUCTS))

----------------------------------------------------------------
-- STRASSENFELD
----------------------------------------------------------------
local fRoadD, fRoadY, bridgeZone = {}, {}, {}
do
	local R = ROAD_HALF + 26
	local function pt(x, z, y)
		local cx = math.floor((x + HALF_X) / VOX) + 1
		local cz = math.floor((z + HALF_Z) / VOX) + 1
		local r = math.ceil(R / VOX)
		local r2 = R * R
		for di = -r, r do
			local i = cx + di
			if i >= 1 and i <= NX then
				local px = -HALF_X + (i - 0.5) * VOX
				local dx = px - x
				local base = (i - 1) * NZ
				for dk = -r, r do
					local k = cz + dk
					if k >= 1 and k <= NZ then
						local pz = -HALF_Z + (k - 0.5) * VOX
						local d2 = dx * dx + (pz - z) * (pz - z)
						if d2 <= r2 then
							local id = base + k
							local ov = fRoadD[id]
							if ov == nil or d2 < ov then
								fRoadD[id] = d2
								fRoadY[id] = y
							end
						end
					end
				end
			end
		end
	end
	for _, r in ipairs(BUILT) do
		for i = 1, #r.P - 1 do
			local a, b = r.P[i], r.P[i + 1]
			local steps = math.max(1, math.ceil((b - a).Magnitude / 3))
			for s = 0, steps - 1 do
				local t = s / steps
				pt(lerp(a.X, b.X, t), lerp(a.Y, b.Y, t), lerp(r.hs[i], r.hs[i + 1], t))
			end
		end
	end
end
print("[v40] Strassenfeld gebacken")

-- Viadukt-Zonen
for _, c in ipairs(VIADUCTS) do
	local steps = math.max(1, math.ceil(c.len / 4))
	for s = 0, steps do
		local t = s / steps
		local x, z = lerp(c.ax, c.bx, t), lerp(c.az, c.bz, t)
		local ci = math.floor((x + HALF_X) / VOX) + 1
		local ck = math.floor((z + HALF_Z) / VOX) + 1
		local r = math.ceil((ROAD_HALF + 8) / VOX)
		for di = -r, r do
			local i = ci + di
			if i >= 1 and i <= NX then
				for dk = -r, r do
					local k = ck + dk
					if k >= 1 and k <= NZ then
						local px = -HALF_X + (i - 0.5) * VOX
						local pz = -HALF_Z + (k - 0.5) * VOX
						if (px - x) ^ 2 + (pz - z) ^ 2 < (ROAD_HALF + 8) ^ 2 then
							bridgeZone[IDX(i, k)] = true
						end
					end
				end
			end
		end
	end
end

-- Bruecken ueber den Fluss
local BRIDGES = {}
for _, r in ipairs(BUILT) do
	local start = nil
	for i = 1, #r.P do
		local p = r.P[i]
		local ci = clamp(math.floor((p.X + HALF_X) / VOX) + 1, 1, NX)
		local ck = clamp(math.floor((p.Y + HALF_Z) / VOX) + 1, 1, NZ)
		local d2 = fRiver[IDX(ci, ck)]
		local crossed = d2 and d2 < (RIVER_HALF + 16) ^ 2
		if crossed and not start then start = i end
		if (not crossed or i == #r.P) and start then
			local iEnd = crossed and i or (i - 1)
			local a, b = r.P[start], r.P[iEnd]
			if (b - a).Magnitude > 4 then
				BRIDGES[#BRIDGES + 1] = {
					x = (a.X + b.X) / 2, z = (a.Y + b.Y) / 2,
					y = (r.hs[start] + r.hs[iEnd]) / 2,
					dirx = b.X - a.X, dirz = b.Y - a.Y,
					len = (b - a).Magnitude,
					ax = a.X, az = a.Y, bx = b.X, bz = b.Y,
				}
			end
			start = nil
		end
	end
end
print(("[v40] %d Fluessbruecken"):format(#BRIDGES))

for _, c in ipairs(BRIDGES) do
	local steps = math.max(1, math.ceil(c.len / 4))
	for s = 0, steps do
		local t = s / steps
		local x, z = lerp(c.ax, c.bx, t), lerp(c.az, c.bz, t)
		local ci = math.floor((x + HALF_X) / VOX) + 1
		local ck = math.floor((z + HALF_Z) / VOX) + 1
		local r = math.ceil((RIVER_HALF + 8) / VOX)
		for di = -r, r do
			local i = ci + di
			if i >= 1 and i <= NX then
				for dk = -r, r do
					local k = ck + dk
					if k >= 1 and k <= NZ then
						local px = -HALF_X + (i - 0.5) * VOX
						local pz = -HALF_Z + (k - 0.5) * VOX
						if (px - x) ^ 2 + (pz - z) ^ 2 < (RIVER_HALF + 8) ^ 2 then
							bridgeZone[IDX(i, k)] = true
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------
-- ENDGUELTIGE HOEHE
----------------------------------------------------------------
local GROUND_DROP = ROAD_EMBED + 0.1

local function terrainH(x, z)
	local i = clamp(math.floor((x + HALF_X) / VOX) + 1, 1, NX)
	local k = clamp(math.floor((z + HALF_Z) / VOX) + 1, 1, NZ)
	local id = IDX(i, k)
	local h = heightWithRiver(x, z)
	local d2 = fRoadD[id]
	if d2 and not bridgeZone[id] then
		local d = math.sqrt(d2)
		if d < ROAD_HALF + 26 then
			local t = 1 - sstep(ROAD_HALF + 4, ROAD_HALF + 26, d)
			h = lerp(h, fRoadY[id] - GROUND_DROP, t)
		end
	end
	return h
end

----------------------------------------------------------------
-- GITTER
----------------------------------------------------------------
local H, MAT = {}, {}
for i = 1, NX do
	local Hi, Mi = {}, {}
	local x = -HALF_X + (i - 0.5) * VOX
	for k = 1, NZ do
		local z = -HALF_Z + (k - 0.5) * VOX
		local h = terrainH(x, z)
		Hi[k] = h
		local id = IDX(i, k)
		local d2 = fRoadD[id]
		local m
		if d2 and d2 < PAINT_HALF * PAINT_HALF and not bridgeZone[id] then
			m = E.Asphalt
		elseif h < WL - 1 then
			m = E.Sand
		elseif mountainBlendAt(x, z) > 0.3 or h > 200 then
			m = E.Rock
		else
			m = E.Grass
		end
		Mi[k] = m
	end
	H[i], MAT[i] = Hi, Mi
	if i % 25 == 0 then task.wait() end
end
print("[v40] Hoehen + Material fertig")

----------------------------------------------------------------
-- TERRAIN SCHREIBEN
----------------------------------------------------------------
local CH = 20
local AIR = E.Air
local wlv = math.floor((WL - BASEY) / VOX)

for ci = 0, NX / CH - 1 do
	for ck = 0, NZ / CH - 1 do
		local maxH = WL
		for a = 1, CH do
			local Hi = H[ci * CH + a]
			for zc = 1, CH do
				local v = Hi[ck * CH + zc]
				if v > maxH then maxH = v end
			end
		end
		local localNY = clamp(math.ceil((maxH - BASEY) / VOX) + 2, wlv + 1, NY)
		local x0 = -HALF_X + ci * CH * VOX
		local z0 = -HALF_Z + ck * CH * VOX
		local region = Region3.new(
			Vector3.new(x0, BASEY, z0),
			Vector3.new(x0 + CH * VOX, BASEY + localNY * VOX, z0 + CH * VOX))

		local mats, occs = {}, {}
		for a = 1, CH do
			local ma, oa = {}, {}
			for b = 1, localNY do
				ma[b] = table.create(CH, AIR)
				oa[b] = table.create(CH, 0)
			end
			mats[a], occs[a] = ma, oa
		end

		for a = 1, CH do
			local ma, oa = mats[a], occs[a]
			for zc = 1, CH do
				local i, k = ci * CH + a, ck * CH + zc
				local h, surf = H[i][k], MAT[i][k]
				local deep = (surf == E.Rock) and E.Rock or E.Grass
				local top = clamp((h - BASEY) / VOX, 0, localNY - 1)
				local full = math.floor(top)
				local frac = top - full
				for b = 1, full do
					ma[b][zc] = (top - b < 2) and surf or deep
					oa[b][zc] = 1
				end
				local nextFree = full + 1
				if frac > 0.02 and full + 1 <= localNY then
					ma[full + 1][zc] = surf
					oa[full + 1][zc] = frac
					nextFree = full + 2
				end
				if top < wlv then
					for b = nextFree, math.min(wlv, localNY) do
						ma[b][zc] = E.Water
						oa[b][zc] = 1
					end
				end
			end
		end
		terrain:WriteVoxels(region, VOX, mats, occs)
		task.wait()
	end
	print(("[v40] Terrain %d%%"):format(math.floor((ci + 1) / (NX / CH) * 100)))
end

----------------------------------------------------------------
-- STIL
----------------------------------------------------------------
pcall(function()
	terrain:SetMaterialColor(E.Grass, Color3.fromRGB(86, 136, 68))
	terrain:SetMaterialColor(E.Rock, Color3.fromRGB(112, 114, 120))
	terrain:SetMaterialColor(E.Ground, Color3.fromRGB(96, 118, 76))
	terrain:SetMaterialColor(E.Sand, Color3.fromRGB(200, 188, 148))
	terrain:SetMaterialColor(E.Snow, Color3.fromRGB(240, 245, 250))
	terrain:SetMaterialColor(E.Asphalt, Color3.fromRGB(66, 68, 74))
end)
terrain.WaterColor = Color3.fromRGB(46, 118, 158)
terrain.WaterTransparency = 0.45
terrain.WaterReflectance = 0.25
terrain.WaterWaveSize = 0.12
pcall(function() terrain.Decoration = true end)

----------------------------------------------------------------
-- PARTS
----------------------------------------------------------------
local partCount = 0
local function part(parent, size, cf, color, material, shape, collide)
	local p = Instance.new("Part")
	p.Anchored = true
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or E.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if collide == false then p.CanCollide = false end
	p.Parent = parent
	partCount += 1
	return p
end

local function heightAt(x, z)
	local i = clamp(math.floor((x + HALF_X) / VOX) + 1, 1, NX)
	local k = clamp(math.floor((z + HALF_Z) / VOX) + 1, 1, NZ)
	return H[i][k]
end

----------------------------------------------------------------
-- STRASSEN-PARTS
----------------------------------------------------------------
local roadFolder = Instance.new("Folder")
roadFolder.Name = "Strassen"
roadFolder.Parent = map
local asphalt = Color3.fromRGB(64, 65, 68)

for _, r in ipairs(BUILT) do
	local P, hs = r.P, r.hs
	for i = 1, #P - 1 do
		local a, b = P[i], P[i + 1]
		local len = (b - a).Magnitude
		if len > 0.05 then
			local ya, yb = hs[i], hs[i + 1]
			local mid = (a + b) / 2
			local dy = (ROAD_TOP - ROAD_EMBED) / 2
			local my = (ya + yb) / 2 + dy + (i % 2) * 0.01
			local look = CFrame.lookAt(
				Vector3.new(mid.X, my, mid.Y),
				Vector3.new(b.X, yb + dy, b.Y))
			local road = part(roadFolder,
				Vector3.new(ROAD_HALF * 2, ROAD_TOP + ROAD_EMBED, len + 2),
				look, asphalt, E.Asphalt)
			road.Name = r.def.name
		end
	end
	task.wait()
end
print(("[v40] %d Strassenteile"):format(partCount))

----------------------------------------------------------------
-- KREUZUNGEN
----------------------------------------------------------------
local junctions = {}
for ia = 1, #BUILT do
	local A = BUILT[ia]
	for i, p in ipairs(A.P) do
		for ib = ia + 1, #BUILT do
			local B = BUILT[ib]
			for j, q in ipairs(B.P) do
				if math.abs(p.X - q.X) < 6 and math.abs(p.Y - q.Y) < 6 then
					local dup = false
					for _, jj in ipairs(junctions) do
						if (jj.x - p.X) ^ 2 + (jj.z - p.Y) ^ 2 < 32 * 32 then dup = true; break end
					end
					if not dup then
						junctions[#junctions + 1] = {
							x = p.X, z = p.Y, y = (A.hs[i] + B.hs[j]) / 2,
						}
					end
					break
				end
			end
		end
	end
end

for _, j in ipairs(junctions) do
	part(roadFolder, Vector3.new(ROAD_TOP + ROAD_EMBED, ROAD_HALF * 2.4, ROAD_HALF * 2.4),
		CFrame.new(j.x, j.y + (ROAD_TOP - ROAD_EMBED) / 2, j.z) * CFrame.Angles(0, 0, math.pi / 2),
		asphalt, E.Asphalt, Enum.PartType.Cylinder, false)
end

local function nearJunction(x, z, rad)
	local r2 = rad * rad
	for _, j in ipairs(junctions) do
		if (j.x - x) ^ 2 + (j.z - z) ^ 2 < r2 then return true end
	end
	return false
end

for _, r in ipairs(BUILT) do
	local P, hs = r.P, r.hs
	local cum = { 0 }
	for i = 2, #P do cum[i] = cum[i - 1] + (P[i] - P[i - 1]).Magnitude end
	local total = cum[#cum]
	local d = 30
	while d < total - 12 do
		local i = 1
		while i < #cum and cum[i + 1] < d do i += 1 end
		local seg = math.max(0.001, cum[i + 1] - cum[i])
		local t = clamp((d - cum[i]) / seg, 0, 1)
		local p = P[i]:Lerp(P[i + 1], t)
		local y = lerp(hs[i], hs[i + 1], t)
		if not nearJunction(p.X, p.Y, 36) then
			local dir = P[i + 1] - P[i]
			part(roadFolder, Vector3.new(1.4, 0.18, 11),
				CFrame.lookAt(Vector3.new(p.X, y + ROAD_TOP + 0.12, p.Y),
					Vector3.new(p.X + dir.X, y + ROAD_TOP + 0.12, p.Y + dir.Y)),
				Color3.fromRGB(245, 235, 205), E.SmoothPlastic, nil, false).Name = "Markierung"
		end
		d += 56
	end
end

----------------------------------------------------------------
-- VIADUKTE (See + Fluss)
----------------------------------------------------------------
local function buildDeck(c, deckLen, extra)
	local br = Instance.new("Model")
	br.Name = "Viadukt"
	br.Parent = roadFolder
	local L = math.sqrt(c.dirx * c.dirx + c.dirz * c.dirz)
	local tx, tz = 0, 1
	if L > 0 then tx, tz = c.dirx / L, c.dirz / L end
	local y = c.y + (ROAD_TOP - ROAD_EMBED) / 2
	local cf = CFrame.lookAt(Vector3.new(c.x, y, c.z), Vector3.new(c.x + tx, y, c.z + tz))

	part(br, Vector3.new(ROAD_HALF * 2 + 6, 2.6, deckLen), cf, asphalt, E.Asphalt)
	for _, sgn in ipairs({ -1, 1 }) do
		part(br, Vector3.new(1.1, 4.4, deckLen),
			cf * CFrame.new((ROAD_HALF + 2) * sgn, 2.8, 0),
			Color3.fromRGB(196, 196, 202), E.Concrete).Name = "Gelaender"
	end
	-- Pfeiler bis ins Wasser/Bett
	local step = 40
	local n = math.floor(deckLen / step)
	for s = 0, n do
		local off = -deckLen / 2 + s * (deckLen / math.max(1, n))
		local gx = c.x + tx * off
		local gz = c.z + tz * off
		local gy = heightAt(gx, gz)
		local h = y - gy
		if h > 3 then
			part(br, Vector3.new(h, 5, 5),
				CFrame.new(gx, gy + h / 2, gz) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(150, 150, 152), E.Concrete, Enum.PartType.Cylinder)
		end
	end
end

for _, c in ipairs(VIADUCTS) do
	buildDeck(c, c.len + 40, 0)
end
for _, c in ipairs(BRIDGES) do
	buildDeck(c, c.len + 30, 0)
end
print(("[v40] %d Viadukte gebaut"):format(#VIADUCTS + #BRIDGES))

----------------------------------------------------------------
-- DOERFER BAUEN
----------------------------------------------------------------
local function gableRoof(parent, base, rb, w, d, roofC, fillC)
	local a = math.rad(28)
	local half = w / 2 + 1.5
	local L = half / math.cos(a)
	local rise = half * math.tan(a)
	part(parent, Vector3.new(L, 0.8, d + 3),
		base * CFrame.new(half / 2, rb + rise / 2, 0) * CFrame.Angles(0, 0, -a), roofC, E.Wood)
	part(parent, Vector3.new(L, 0.8, d + 3),
		base * CFrame.new(-half / 2, rb + rise / 2, 0) * CFrame.Angles(0, 0, a), roofC, E.Wood)
	local n, hr = 4, (w / 2) * math.tan(a)
	for s = 0, n - 1 do
		local sw = w * (1 - (s + 0.5) / n)
		local sh = hr / n
		part(parent, Vector3.new(sw, sh + 0.05, d), base * CFrame.new(0, rb + s * sh + sh / 2, 0), fillC, E.Wood)
	end
end

local function chalet(parent, x, z, yaw)
	local m = Instance.new("Model")
	m.Name = "Chalet"
	m.Parent = parent
	local w, d, wallH = 12 + math.random(0, 4), 16 + math.random(0, 6), 9
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.8, z) * CFrame.Angles(0, yaw, 0)
	local wallC = (math.random() < 0.5) and Color3.fromRGB(150, 100, 62) or Color3.fromRGB(236, 222, 190)
	local roofC = (math.random() < 0.5) and Color3.fromRGB(96, 62, 48) or Color3.fromRGB(150, 74, 60)
	part(m, Vector3.new(w + 1.5, 3, d + 1.5), base * CFrame.new(0, 1.5, 0), Color3.fromRGB(150, 150, 150), E.Concrete)
	part(m, Vector3.new(w, wallH, d), base * CFrame.new(0, 3 + wallH / 2, 0), wallC, E.Wood)
	local rise = gableRoof(m, base, 3 + wallH, w, d, roofC, wallC)
	part(m, Vector3.new(3, 5, 0.4), base * CFrame.new(0, 5.5, d / 2 + 0.1), Color3.fromRGB(80, 52, 36), E.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(2.6, 2.6, 0.4), base * CFrame.new(sx * w / 4 + sx * 1, 8.5, d / 2 + 0.1),
			Color3.fromRGB(160, 200, 230), E.Glass)
	end
	part(m, Vector3.new(2, 5, 2), base * CFrame.new(w / 4, 3 + wallH + rise * 0.6, -d / 4),
		Color3.fromRGB(120, 115, 110), E.Brick)
end

local function church(parent, x, z, yaw)
	local m = Instance.new("Model")
	m.Name = "Kirche"
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.8, z) * CFrame.Angles(0, yaw, 0)
	local white = Color3.fromRGB(240, 236, 226)
	part(m, Vector3.new(16, 3, 28), base, Color3.fromRGB(150, 150, 150), E.Concrete)
	part(m, Vector3.new(14, 11, 24), base * CFrame.new(0, 8, 2), white)
	gableRoof(m, base * CFrame.new(0, 2, 2), 13, 14, 24, Color3.fromRGB(120, 60, 52), white)
	part(m, Vector3.new(8, 30, 8), base * CFrame.new(0, 18, -14), white)
	for s = 0, 5 do
		local sw = 9 * (1 - s / 6) + 0.5
		part(m, Vector3.new(sw, 3, sw), base * CFrame.new(0, 34.5 + s * 3, -14), Color3.fromRGB(120, 60, 52))
	end
end

local townFolder = Instance.new("Folder")
townFolder.Name = "Doerfer"
townFolder.Parent = map

local function roadDistXZ(x, z)
	local ci = clamp(math.floor((x + HALF_X) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF_Z) / VOX) + 1, 1, NZ)
	local d2 = fRoadD[IDX(ci, ck)]
	if not d2 then return math.huge end
	return math.sqrt(d2)
end

for _, t in ipairs(TOWNS) do
	local tf = Instance.new("Folder")
	tf.Name = t.name
	tf.Parent = townFolder
	local placed = { { x = t.x, z = t.z } }

	local function tryPlace(rad)
		for _ = 1, 50 do
			local a = math.random() * 6.28
			local r = rad * (0.45 + math.random() * 0.55)
			local x, z = t.x + math.cos(a) * r, t.z + math.sin(a) * r
			local ok = true
			if roadDistXZ(x, z) < ROAD_HALF + 8 then ok = false end
			if ok then
				for _, p in ipairs(placed) do
					if (p.x - x) ^ 2 + (p.z - z) ^ 2 < 24 * 24 then ok = false; break end
				end
			end
			if ok then
				placed[#placed + 1] = { x = x, z = z }
				return x, z, math.atan2(t.x - x, t.z - z)
			end
		end
		return nil
	end

	if t.church then
		local x, z, yaw = tryPlace(60)
		if x then church(tf, x, z, yaw) end
	end
	for _ = 1, math.random(6, 10) do
		local x, z, yaw = tryPlace(75)
		if x then chalet(tf, x, z, yaw) end
	end
	task.wait()
end
print(("[v40] %d Doerfer gebaut"):format(#TOWNS))

----------------------------------------------------------------
-- WASSERFALL
----------------------------------------------------------------
do
	local wf = Instance.new("Folder")
	wf.Name = "Wasserfall"
	wf.Parent = map
	local src = RIVER_PTS[1]
	local topY = heightAt(src.X + 60, src.Y)
	if topY < WL + 18 then topY = WL + 18 end
	local fallH = topY - (WL + 1)
	local steps = math.max(3, math.floor(fallH / 12))
	for s = 0, steps do
		local t = s / steps
		local y = topY - fallH * t
		local x = src.X + 55 - 55 * t
		local p = part(wf, Vector3.new(28, fallH / steps + 2, 9),
			CFrame.new(x, y, src.Y) * CFrame.Angles(0, 0, math.rad(-6)),
			Color3.fromRGB(150, 205, 235), E.Glass, nil, false)
		p.Transparency = 0.35
	end
	for _ = 1, 10 do
		local a = math.random() * 6.28
		local r = 4 + math.random() * 20
		local p = part(wf, Vector3.new(5, 5, 5),
			CFrame.new(src.X + math.cos(a) * r, WL + 1, src.Y + math.sin(a) * r),
			Color3.fromRGB(230, 245, 255), E.Glass, Enum.PartType.Ball, false)
		p.Transparency = 0.5
	end
end

----------------------------------------------------------------
-- WALD
----------------------------------------------------------------
local function findTemplate()
	local pools = { ServerStorage, Workspace, ReplicatedStorage }
	for _, pool in ipairs(pools) do
		local t = pool:FindFirstChild("TreeTemplate")
		if t and (t:IsA("MeshPart") or t:IsA("Model")) then return t end
	end
	for _, pool in ipairs(pools) do
		for _, name in ipairs({ "Tree Tanne", "Tanne", "Tree", "Baum" }) do
			local t = pool:FindFirstChild(name, true)
			if t and (t:IsA("MeshPart") or t:IsA("Model")) then return t end
		end
	end
	return nil
end

local template = findTemplate()
print("[v40] Baum-Vorlage: " .. (template and template:GetFullName() or "FEHLT (Ersatzbaum)"))

local treeFolder = Instance.new("Folder")
treeFolder.Name = "Wald"
treeFolder.Parent = map

local function allParts(root)
	if root:IsA("BasePart") then return { root } end
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then out[#out + 1] = d end
	end
	return out
end

local function buildTree(x, z, y, s, rot)
	if not template then
		local m = Instance.new("Model")
		m.Name = "Tanne"
		m.Parent = treeFolder
		local up = CFrame.Angles(0, 0, math.pi / 2)
		part(m, Vector3.new(7 * s, 2 * s, 2 * s),
			CFrame.new(x, y + 3.5 * s, z) * up, Color3.fromRGB(92, 64, 48), E.Wood, Enum.PartType.Cylinder)
		part(m, Vector3.new(11 * s, 13 * s, 13 * s),
			CFrame.new(x, y + 6.5 * s, z) * up, Color3.fromRGB(44, 92, 56), E.Grass, Enum.PartType.Cylinder, false)
		part(m, Vector3.new(8 * s, 9 * s, 9 * s),
			CFrame.new(x, y + 13 * s, z) * up, Color3.fromRGB(52, 108, 62), E.Grass, Enum.PartType.Cylinder, false)
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "Tanne"
	local c = template:Clone()
	c.Parent = holder
	holder.Parent = treeFolder
	local parts = allParts(holder)
	if #parts == 0 then holder:Destroy() return end
	for _, p in ipairs(parts) do
		p.Anchored = true
		p.CanCollide = false
		p.Size = p.Size * s
	end
	local cf, size = holder:GetBoundingBox()
	local bottomY = cf.Position.Y - size.Y / 2
	holder:PivotTo(
		CFrame.new(x, y, z) * CFrame.Angles(0, rot, 0)
		* CFrame.new(-cf.Position.X, -bottomY, -cf.Position.Z))
end

local placedTrees, attempts = 0, 0
while placedTrees < TREE_COUNT and attempts < TREE_COUNT * 20 do
	attempts += 1
	local x = (math.random() * 2 - 1) * (HALF_X - 60)
	local z = (math.random() * 2 - 1) * (HALF_Z - 60)
	local ci = clamp(math.floor((x + HALF_X) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF_Z) / VOX) + 1, 1, NZ)
	local id = IDX(ci, ck)
	local h = H[ci][ck]

	local nearTown = false
	for _, t in ipairs(TOWNS) do
		if (t.x - x) ^ 2 + (t.z - z) ^ 2 < 140 * 140 then nearTown = true; break end
	end

	local forest = nz(x / 380, z / 380, 60) + nz(x / 120, z / 120, 61) * 0.5
	local dr = fRoadD[id]
	local rv = fRiver[id]
	local ok = (not nearTown) and forest > 0.12 and h > WL + 3 and h < 250 and MAT[ci][ck] == E.Grass
	if ok and dr and dr < (ROAD_HALF + 14) ^ 2 then ok = false end
	if ok and rv and rv < (RIVER_HALF + 12) ^ 2 then ok = false end
	if ok then
		buildTree(x, z, h - 0.4, 0.85 + math.random() * 0.8, math.random() * 6.28)
		placedTrees += 1
	end
	if attempts % 400 == 0 then task.wait() end
end
print(("[v40] %d Baeume"):format(placedTrees))

----------------------------------------------------------------
-- SPAWN
----------------------------------------------------------------
do
	local t = TOWNS[1] or { x = -900, z = -600 }
	local x, z = t.x + 40, t.z + 40
	local sp = Instance.new("SpawnLocation")
	sp.Anchored = true
	sp.Neutral = true
	sp.Size = Vector3.new(14, 1, 14)
	sp.Position = Vector3.new(x, heightAt(x, z) + 1.2, z)
	sp.Transparency = 1
	sp.Parent = map
	sp.Name = "Spawn"
end

----------------------------------------------------------------
-- ATMOSPHAERE
----------------------------------------------------------------
Lighting.ClockTime = 15
Lighting.Brightness = 2.3
Lighting.Ambient = Color3.fromRGB(96, 106, 124)
Lighting.OutdoorAmbient = Color3.fromRGB(146, 156, 176)

local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
clouds.Cover = 0.5
clouds.Density = 0.3
clouds.Color = Color3.fromRGB(246, 246, 250)
clouds.Parent = terrain

local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
atm.Density = 0.28
atm.Offset = 0.2
atm.Color = Color3.fromRGB(176, 202, 232)
atm.Decay = Color3.fromRGB(110, 145, 198)
atm.Glare = 0
atm.Haze = 1.1

print(("[v40] FERTIG in %.0f s | %d Teile | %d Baeume | %d Viadukte | %d Doerfer"):format(
	os.clock() - T0, partCount, placedTrees, #VIADUCTS + #BRIDGES, #TOWNS))
