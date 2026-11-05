--[[
	SCHWEIZER MAP GENERATOR - VERSION 42
	------------------------------------------------------------
	Karte 8000 x 8000.
	Tal (spielbar) -> innerer Bergkranz mit 2 Paessen -> Autobahnring
	-> aeusserer Bergkranz als Kulisse am Kartenrand.

	NUR EIN SEE, KEINE FLUESSE.
	See-Bruecke: Deck liegt ausschliesslich ueber Wasser, Pfeiler nur im Wasser.

	Strassennetz: Innenring + Aussenring + 6 Radien + 3 Querspangen
	+ 2 Passstrassen + Autobahnring.
	Alle Kurven: zentripetale Catmull-Rom-Splines (alpha = 0.5)
	-> weich, keine Schlaufen, keine Spitzen, keine harten Ecken.

	BENUTZUNG: Roblox Studio, Command Bar, NICHT im Play-Modus.
	Dauer: ca. 8-15 Minuten.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local terrain = Workspace.Terrain
local E = Enum.Material

local SIZE = 8000
local HALF = SIZE / 2
local VOX = 4
local NX = SIZE / VOX
local NZ = SIZE / VOX
local BASEY = -32
local NY = 220
local WL = 20
local PLAIN = 24
local PLATEAU = 70
local LAKE_BED = 12
local ROAD_HALF = 18
local PAINT_HALF = 16
local ROAD_TOP = 1.1
local ROAD_EMBED = 1.3
local BRIDGE_H = 9
local TREE_COUNT = 4200
local SEED = 11.37
local CH = 50
math.randomseed(2026)

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function sstep(a, b, x) local t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) end
local function nz(x, z, s) return math.noise(x + 0.37, z + 0.71, SEED + (s or 0)) * 2 end
local function IDX(i, k) return (i - 1) * NZ + k end
local function V2(x, z) return Vector2.new(x, z) end
local function pol(r, deg) local a = math.rad(deg); return V2(math.cos(a) * r, math.sin(a) * r) end
local function angDist(a, b)
	local d = math.abs((a - b) % 360)
	if d > 180 then d = 360 - d end
	return d
end
local T0 = os.clock()

print("[v42] Start...")
terrain:Clear()
local old = Workspace:FindFirstChild("SwissMap")
if old then old:Destroy() end
local map = Instance.new("Folder")
map.Name = "SwissMap"
map.Parent = Workspace

----------------------------------------------------------------
-- HOEHEN
----------------------------------------------------------------
local LAKE = { x = -1250, z = 0, rx = 340, rz = 240 }
local PASS_ANGLES = { 60, 240 }

local function lakeMask(x, z)
	local dx = (x - LAKE.x) / LAKE.rx
	local dz = (z - LAKE.z) / LAKE.rz
	local d = math.sqrt(dx * dx + dz * dz) + nz(x / 150, z / 150, 10) * 0.07
	return 1 - sstep(0.45, 1.0, d)
end

local function passMask(x, z, r, ang)
	local w = 0
	for _, pa in ipairs(PASS_ANGLES) do
		local m = 1 - sstep(3, 9, angDist(ang, pa))
		if m > w then w = m end
	end
	return w * sstep(1750, 1950, r) * (1 - sstep(3150, 3280, r))
end

local HILLS = {
	{ x = -800, z = -500, rx = 900, rz = 700, h = 16 },
	{ x = 600, z = 900, rx = 850, rz = 650, h = 12 },
	{ x = 1000, z = -900, rx = 700, rz = 600, h = 10 },
}

local function heightRaw(x, z)
	local r = math.sqrt(x * x + z * z)
	local h = PLAIN + nz(x / 900, z / 900, 31) * 1.8 + nz(x / 380, z / 380, 32) * 0.7
	for i, hill in ipairs(HILLS) do
		local dx = (x - hill.x) / hill.rx
		local dz = (z - hill.z) / hill.rz
		local d = math.sqrt(dx * dx + dz * dz) + nz(x / 300, z / 300, 40 + i) * 0.08
		local t = clamp(1 - d, 0, 1)
		h = h + hill.h * (t * t * (3 - 2 * t))
	end
	-- Boden steigt hinter dem Tal auf das Plateau (kein Loch hinter dem Bergkranz)
	h = lerp(h, PLATEAU + nz(x / 260, z / 260, 70) * 2.5, sstep(2650, 2950, r))
	-- innerer Bergkranz
	local rm = sstep(1850, 2200, r) * (1 - sstep(2750, 3000, r))
	if rm > 0 then
		local ridge = 1 - math.abs(nz(x / 280, z / 280, 23))
		local hh = 300 + ridge * 170 + nz(x / 85, z / 85, 25) * 22
		h = lerp(h, hh, rm)
	end
	-- 2 Paesse durch den Bergkranz
	local ang = math.deg(math.atan2(z, x))
	local pm = passMask(x, z, r, ang)
	if pm > 0 then
		local pf = lerp(PLAIN + 2, PLATEAU + 1, sstep(2000, 3150, r))
		h = lerp(h, pf, pm)
	end
	-- aeusserer Bergkranz (Kulisse hinter der Autobahn)
	local om = sstep(3500, 3850, r)
	if om > 0 then
		local ridge = 1 - math.abs(nz(x / 320, z / 320, 26))
		local hh = 340 + ridge * 190 + nz(x / 95, z / 95, 27) * 26
		h = lerp(h, hh, om)
	end
	-- See
	local lm = lakeMask(x, z)
	if lm > 0 then h = lerp(h, LAKE_BED, lm) end
	if lm < 0.02 then h = math.max(h, WL + 2) end
	return clamp(h, 2, 700)
end

----------------------------------------------------------------
-- KNOTEN + DOERFER
----------------------------------------------------------------
local IN, MID, OUT, PASS, AUTO = {}, {}, {}, {}, {}
local IN_R = { 820, 760, 840, 800, 860, 780 }
local OUT_R = { 1720, 1660, 1740, 1760, 1690, 1730 }
for i = 0, 5 do
	local a = i * 60
	IN[i] = pol(IN_R[i + 1], a)
	MID[i] = pol(1270, a)
	OUT[i] = pol(OUT_R[i + 1], a)
end
for i = 0, 11 do
	AUTO[i] = pol(3150 + 70 * math.sin(math.rad(i * 30) * 2 + 0.7), i * 30)
end
PASS[1] = pol(2400, 60)
PASS[4] = pol(2400, 240)

local TOWNS = {
	{ name = "Sonnenau",  x = IN[0].X,  z = IN[0].Y,  church = true },
	{ name = "Bergdorf",  x = OUT[1].X, z = OUT[1].Y, church = false },
	{ name = "Seeblick",  x = IN[2].X,  z = IN[2].Y,  church = true },
	{ name = "Waldau",    x = OUT[4].X, z = OUT[4].Y, church = false },
	{ name = "Nordegg",   x = OUT[2].X, z = OUT[2].Y, church = false },
	{ name = "Suedhalde", x = OUT[5].X, z = OUT[5].Y, church = false },
}
do
	local ok = {}
	for _, t in ipairs(TOWNS) do
		t.h = heightRaw(t.x, t.z)
		if t.h > WL + 1 and t.h < 160 and lakeMask(t.x, t.z) < 0.05 then
			ok[#ok + 1] = t
		else
			print("[v42] Dorf " .. t.name .. " uebersprungen")
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
-- STRASSEN-NETZ
----------------------------------------------------------------
local ROADS = {
	{ name = "Innenring", closed = true, pts = { IN[0], IN[1], IN[2], IN[3], IN[4], IN[5] } },
	{ name = "Aussenring", closed = true, pts = { OUT[0], OUT[1], OUT[2], OUT[3], OUT[4], OUT[5] } },
	{ name = "Autobahn", closed = true, auto = true,
		pts = { AUTO[0], AUTO[1], AUTO[2], AUTO[3], AUTO[4], AUTO[5], AUTO[6], AUTO[7], AUTO[8], AUTO[9], AUTO[10], AUTO[11] } },
}
for i = 0, 5 do
	ROADS[#ROADS + 1] = { name = "Radial " .. i, pts = { IN[i], MID[i], OUT[i] } }
end
ROADS[#ROADS + 1] = { name = "Querspange N",  pts = { MID[0], pol(1420, 30), MID[1] } }
ROADS[#ROADS + 1] = { name = "Querspange NO", pts = { MID[1], pol(1420, 90), MID[2] } }
ROADS[#ROADS + 1] = { name = "Querspange SW", pts = { MID[4], pol(1420, 270), MID[5] } }
ROADS[#ROADS + 1] = { name = "Pass Nord", pts = { OUT[1], PASS[1], AUTO[2] } }
ROADS[#ROADS + 1] = { name = "Pass Sued", pts = { OUT[4], PASS[4], AUTO[8] } }

-- zentripetale Catmull-Rom-Spline (alpha = 0.5): trifft jeden Knoten exakt,
-- keine Ueberschwinger, keine Schlaufen, keine Spitzen.
local function catmull(pts, closed, step)
	step = step or 6
	local out, n = {}, #pts
	local function get(i)
		if closed then return pts[((i - 1) % n) + 1] end
		return pts[clamp(i, 1, n)]
	end
	local segs = closed and n or (n - 1)
	for i = 1, segs do
		local p0, p1, p2, p3 = get(i - 1), get(i), get(i + 1), get(i + 2)
		local function tj(ti, a, b)
			local d = math.sqrt((b.X - a.X) ^ 2 + (b.Y - a.Y) ^ 2)
			return ti + math.max(d, 0.001) ^ 0.5
		end
		local t0 = 0
		local t1 = tj(t0, p0, p1)
		local t2 = tj(t1, p1, p2)
		local t3 = tj(t2, p2, p3)
		local steps = math.max(2, math.ceil((p2 - p1).Magnitude / step))
		for s = 0, steps - 1 do
			local t = lerp(t1, t2, s / steps)
			local A1 = p0:Lerp(p1, (t - t0) / (t1 - t0))
			local A2 = p1:Lerp(p2, (t - t1) / (t2 - t1))
			local A3 = p2:Lerp(p3, (t - t2) / (t3 - t2))
			local B1 = A1:Lerp(A2, (t - t0) / (t2 - t0))
			local B2 = A2:Lerp(A3, (t - t1) / (t3 - t1))
			out[#out + 1] = B1:Lerp(B2, (t - t1) / (t2 - t1))
		end
	end
	if not closed then out[#out] = pts[n] end
	return out
end

local BUILT = {}
for idx, def in ipairs(ROADS) do
	local P = catmull(def.pts, def.closed, 6)
	local hs = {}
	for i, p in ipairs(P) do hs[i] = heightPlain(p.X, p.Y) end
	for _ = 1, 14 do
		local n = {}
		for i = 1, #P do
			local s, c = 0, 0
			for j = math.max(1, i - 10), math.min(#P, i + 10) do s = s + hs[j]; c = c + 1 end
			n[i] = s / c
		end
		hs = n
	end

	-- Bruecke nur ueber Wasser
	local wet, anyWet = {}, false
	for i, p in ipairs(P) do
		wet[i] = heightPlain(p.X, p.Y) < WL - 0.5
		if wet[i] then anyWet = true end
	end
	if anyWet then
		for i = 1, #P do if wet[i] then hs[i] = WL + BRIDGE_H end end
		for _ = 1, 8 do
			local n = {}
			for i = 1, #P do
				if wet[i] then
					n[i] = hs[i]
				else
					local s, c = 0, 0
					for j = math.max(1, i - 5), math.min(#P, i + 5) do s = s + hs[j]; c = c + 1 end
					n[i] = s / c
				end
			end
			hs = n
		end
	end
	BUILT[idx] = { def = def, P = P, hs = hs, wet = wet }
	task.wait()
end

-- gemeinsame Knoten: Hoehen angleichen + Kreuzungspunkte sammeln
local buckets = {}
local function keyOf(x, z) return math.floor(x + 0.5) .. ":" .. math.floor(z + 0.5) end
for _, r in ipairs(BUILT) do
	for i, p in ipairs(r.P) do
		local k = keyOf(p.X, p.Y)
		local b = buckets[k]
		if not b then b = {}; buckets[k] = b end
		b[#b + 1] = { r = r, i = i }
	end
end
local junctions = {}
for _, b in pairs(buckets) do
	if #b >= 2 then
		local sx, sz, sy = 0, 0, 0
		for _, e in ipairs(b) do
			local p = e.r.P[e.i]
			sx = sx + p.X; sz = sz + p.Y; sy = sy + e.r.hs[e.i]
		end
		local c = #b
		local ay = sy / c
		for _, e in ipairs(b) do e.r.hs[e.i] = ay end
		junctions[#junctions + 1] = { x = sx / c, z = sz / c, y = ay }
	end
end
print(("[v42] %d Strassen, %d Knoten"):format(#BUILT, #junctions))

----------------------------------------------------------------
-- STRASSENFELD
----------------------------------------------------------------
local fRoadD, fRoadY, bridgeZone = {}, {}, {}
do
	local R = ROAD_HALF + 28
	local rCells = math.ceil(R / VOX)
	local r2 = R * R
	local function pt(x, z, y)
		local cx = math.floor((x + HALF) / VOX) + 1
		local cz = math.floor((z + HALF) / VOX) + 1
		for di = -rCells, rCells do
			local i = cx + di
			if i >= 1 and i <= NX then
				local px = -HALF + (i - 0.5) * VOX
				local dx = px - x
				local base = (i - 1) * NZ
				for dk = -rCells, rCells do
					local k = cz + dk
					if k >= 1 and k <= NZ then
						local pz = -HALF + (k - 0.5) * VOX
						local d2 = dx * dx + (pz - z) ^ 2
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
print("[v42] Strassenfeld gebacken")

for _, r in ipairs(BUILT) do
	for i = 1, #r.P do
		if r.wet[i] then
			local p = r.P[i]
			local ci = math.floor((p.X + HALF) / VOX) + 1
			local ck = math.floor((p.Y + HALF) / VOX) + 1
			local rr = math.ceil((ROAD_HALF + 10) / VOX)
			for di = -rr, rr do
				local ii = ci + di
				if ii >= 1 and ii <= NX then
					for dk = -rr, rr do
						local kk = ck + dk
						if kk >= 1 and kk <= NZ then
							local px = -HALF + (ii - 0.5) * VOX
							local pz = -HALF + (kk - 0.5) * VOX
							if (px - p.X) ^ 2 + (pz - p.Y) ^ 2 < (ROAD_HALF + 10) ^ 2 then
								bridgeZone[IDX(ii, kk)] = true
							end
						end
					end
				end
			end
		end
	end
end
print("[v42] Brueckenzone gebacken")

----------------------------------------------------------------
-- ENDGUELTIGE HOEHE
----------------------------------------------------------------
local GROUND_DROP = ROAD_EMBED - 0.15
local function terrainH(x, z)
	local i = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local k = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local id = IDX(i, k)
	local h = heightPlain(x, z)
	local d2 = fRoadD[id]
	if d2 and h >= WL - 1 then
		local d = math.sqrt(d2)
		if d < ROAD_HALF + 28 then
			local t = 1 - sstep(ROAD_HALF + 4, ROAD_HALF + 28, d)
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
	local x = -HALF + (i - 0.5) * VOX
	for k = 1, NZ do
		local z = -HALF + (k - 0.5) * VOX
		local h = terrainH(x, z)
		Hi[k] = h
		local id = IDX(i, k)
		local d2 = fRoadD[id]
		local m
		if h < WL - 1 then
			m = E.Sand
		elseif d2 and d2 < PAINT_HALF * PAINT_HALF and not bridgeZone[id] then
			m = E.Asphalt
		elseif h > 500 then
			m = E.Snow
		elseif h > 140 then
			m = E.Rock
		else
			m = E.Grass
		end
		Mi[k] = m
	end
	H[i], MAT[i] = Hi, Mi
	if i % 20 == 0 then task.wait() end
end
print("[v42] Hoehen + Material fertig")

----------------------------------------------------------------
-- TERRAIN SCHREIBEN
----------------------------------------------------------------
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
		local x0 = -HALF + ci * CH * VOX
		local z0 = -HALF + ck * CH * VOX
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
				local deep = (surf == E.Rock or surf == E.Snow) and E.Rock or E.Grass
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
	print(("[v42] Terrain %d%%"):format(math.floor((ci + 1) / (NX / CH) * 100)))
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
	partCount = partCount + 1
	return p
end

local function heightAt(x, z)
	local i = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local k = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	return H[i][k]
end

local asphalt = Color3.fromRGB(64, 65, 68)
local roadFolder = Instance.new("Folder")
roadFolder.Name = "Strassen"
roadFolder.Parent = map

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
print(("[v42] %d Strassenteile"):format(partCount))

----------------------------------------------------------------
-- KREUZUNGEN
----------------------------------------------------------------
for _, j in ipairs(junctions) do
	part(roadFolder, Vector3.new(ROAD_TOP + ROAD_EMBED, ROAD_HALF * 2.5, ROAD_HALF * 2.5),
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

-- Mittelstreifen (Autobahn bekommt eine echte Mittelleitplanke)
for _, r in ipairs(BUILT) do
	if not r.def.auto then
		local P, hs = r.P, r.hs
		local cum = { 0 }
		for i = 2, #P do cum[i] = cum[i - 1] + (P[i] - P[i - 1]).Magnitude end
		local total = cum[#cum]
		local d = 30
		while d < total - 12 do
			local i = 1
			while i < #cum and cum[i + 1] < d do i = i + 1 end
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
			d = d + 56
		end
	end
end

----------------------------------------------------------------
-- AUTOBAHN: Mittelleitplanke + Leitplanken
----------------------------------------------------------------
local function beam(folder, a, b, ya, yb, off, width, height, color)
	local dx, dz = b.X - a.X, b.Y - a.Y
	local L = math.sqrt(dx * dx + dz * dz)
	if L < 0.05 then return end
	local nx, nz2 = -dz / L, dx / L
	local mx = (a.X + b.X) / 2 + nx * off
	local mz = (a.Y + b.Y) / 2 + nz2 * off
	local y = (ya + yb) / 2 + ROAD_TOP
	local cf = CFrame.lookAt(Vector3.new(mx, y + height / 2, mz),
		Vector3.new(mx + dx, y + height / 2, mz + dz))
	part(folder, Vector3.new(width, height, L + 0.8), cf, color, E.Concrete, nil, false)
end

local autoFolder = Instance.new("Folder")
autoFolder.Name = "Autobahn"
autoFolder.Parent = map
for _, r in ipairs(BUILT) do
	if r.def.auto then
		local P, hs = r.P, r.hs
		for i = 1, #P - 2, 2 do
			local a, b = P[i], P[i + 2]
			local ya, yb = hs[i], hs[i + 2]
			if not nearJunction((a.X + b.X) / 2, (a.Y + b.Y) / 2, 30) then
				beam(autoFolder, a, b, ya, yb, 0, 1.6, 1.1, Color3.fromRGB(190, 192, 196))
			end
			beam(autoFolder, a, b, ya, yb, -(ROAD_HALF + 2.2), 0.9, 1.5, Color3.fromRGB(205, 208, 212))
			beam(autoFolder, a, b, ya, yb, (ROAD_HALF + 2.2), 0.9, 1.5, Color3.fromRGB(205, 208, 212))
		end
		task.wait()
	end
end

----------------------------------------------------------------
-- BRUECKE: Deck nur ueber Wasser, Pfeiler nur im Wasser
----------------------------------------------------------------
local bridgeFolder = Instance.new("Folder")
bridgeFolder.Name = "Bruecken"
bridgeFolder.Parent = map

local function buildBridge(r)
	local P, hs = r.P, r.hs
	for i = 1, #P - 1 do
		if r.wet[i] or r.wet[i + 1] then
			local a, b = P[i], P[i + 1]
			local len = (b - a).Magnitude
			local ya, yb = hs[i], hs[i + 1]
			local mid = (a + b) / 2
			local y = (ya + yb) / 2
			local look = CFrame.lookAt(
				Vector3.new(mid.X, y, mid.Y),
				Vector3.new(b.X, yb, b.Y))
			part(bridgeFolder, Vector3.new(ROAD_HALF * 2 + 8, 3.2, len + 1.2),
				look * CFrame.new(0, ROAD_TOP - 1.6 - 0.03, 0),
				Color3.fromRGB(120, 120, 126), E.Concrete).Name = "Deck"
			for _, sgn in ipairs({ -1, 1 }) do
				part(bridgeFolder, Vector3.new(1.6, 0.6, len + 1.2),
					look * CFrame.new((ROAD_HALF + 1.8) * sgn, ROAD_TOP + 0.25, 0),
					Color3.fromRGB(200, 200, 205), E.Concrete).Name = "Randstein"
				part(bridgeFolder, Vector3.new(1.0, 1.7, len + 1.2),
					look * CFrame.new((ROAD_HALF + 3.2) * sgn, ROAD_TOP + 0.9, 0),
					Color3.fromRGB(210, 212, 216), E.Concrete).Name = "Gelaender"
			end
		end
	end

	local d = 0
	for i = 1, #P - 1 do
		d = d + (P[i + 1] - P[i]).Magnitude
		if r.wet[i] and d > 44 then
			d = 0
			local p = P[i]
			local y = hs[i]
			local gy = heightAt(p.X, p.Y)
			if gy < WL - 1 then
				local h = (y + ROAD_TOP - 3.2) - gy
				if h > 4 then
					part(bridgeFolder, Vector3.new(h, 6, 6),
						CFrame.new(p.X, gy + h / 2, p.Y) * CFrame.Angles(0, 0, math.pi / 2),
						Color3.fromRGB(150, 150, 152), E.Concrete, Enum.PartType.Cylinder).Name = "Pfeiler"
				end
			end
		end
	end
end
for _, r in ipairs(BUILT) do buildBridge(r) end
print(("[v42] Bruecken gebaut (%d Teile)"):format(partCount))

----------------------------------------------------------------
-- DOERFER
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
	return rise
end

local function chalet(parent, x, z, yaw, w, d)
	local m = Instance.new("Model")
	m.Name = "Chalet"
	m.Parent = parent
	local wallH = 9
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
	local ci = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local d2 = fRoadD[IDX(ci, ck)]
	if not d2 then return math.huge end
	return math.sqrt(d2)
end

for _, t in ipairs(TOWNS) do
	local tf = Instance.new("Folder")
	tf.Name = t.name
	tf.Parent = townFolder
	local placed = { { x = t.x, z = t.z } }

	local function tryPlace(rad, clear)
		for _ = 1, 60 do
			local a = math.random() * 6.28
			local r = rad * (0.45 + math.random() * 0.55)
			local x, z = t.x + math.cos(a) * r, t.z + math.sin(a) * r
			local ok = true
			if roadDistXZ(x, z) < ROAD_HALF + clear then ok = false end
			if ok and math.abs(heightAt(x, z) - t.h) > 2.5 then ok = false end
			if ok then
				for _, p in ipairs(placed) do
					if (p.x - x) ^ 2 + (p.z - z) ^ 2 < 42 * 42 then ok = false; break end
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
		local x, z, yaw = tryPlace(75, 24)
		if x then church(tf, x, z, yaw) end
	end
	for _ = 1, math.random(6, 10) do
		local w, d = 12 + math.random(0, 4), 16 + math.random(0, 6)
		local clear = math.max(w, d) / 2 + 6
		local x, z, yaw = tryPlace(85, clear)
		if x then chalet(tf, x, z, yaw, w, d) end
	end
	task.wait()
end
print(("[v42] %d Doerfer gebaut"):format(#TOWNS))

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
print("[v42] Baum-Vorlage: " .. (template and template:GetFullName() or "FEHLT (Ersatzbaum)"))

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
	attempts = attempts + 1
	local x = (math.random() * 2 - 1) * (HALF - 60)
	local z = (math.random() * 2 - 1) * (HALF - 60)
	local ci = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local id = IDX(ci, ck)
	local h = H[ci][ck]

	local nearTown = false
	for _, t in ipairs(TOWNS) do
		if (t.x - x) ^ 2 + (t.z - z) ^ 2 < 150 * 150 then nearTown = true; break end
	end

	local forest = nz(x / 380, z / 380, 60) + nz(x / 120, z / 120, 61) * 0.5
	local dr = fRoadD[id]
	local ok = (not nearTown) and forest > 0.10 and h > WL + 3 and h < 250
		and MAT[ci][ck] == E.Grass and not bridgeZone[id]
	if ok and dr and dr < (ROAD_HALF + 14) ^ 2 then ok = false end
	if ok then
		buildTree(x, z, h - 0.4, 0.85 + math.random() * 0.8, math.random() * 6.28)
		placedTrees = placedTrees + 1
	end
	if attempts % 400 == 0 then task.wait() end
end
print(("[v42] %d Baeume"):format(placedTrees))

----------------------------------------------------------------
-- SPAWN
----------------------------------------------------------------
do
	local t = TOWNS[1] or { x = 820, z = 0 }
	local x, z = t.x, t.z
	for _ = 1, 60 do
		local a = math.random() * 6.28
		local r = 26 + math.random() * 20
		local px, pz = t.x + math.cos(a) * r, t.z + math.sin(a) * r
		local d = roadDistXZ(px, pz)
		if d < 34 and d > 18 then x, z = px, pz; break end
	end
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

print(("[v42] FERTIG in %.0f s | %d Teile | %d Baeume | %d Doerfer | %d Strassen | %d Knoten"):format(
	os.clock() - T0, partCount, placedTrees, #TOWNS, #BUILT, #junctions))
