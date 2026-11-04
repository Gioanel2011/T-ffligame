--[[
	SCHWEIZER MAP GENERATOR  (2000 x 2000 Studs)
	Berge, Tal, See, Mittelland, Hauptstrassen, Passstrasse mit Kehren,
	Doerfer mit Chalets + Kirche, Tannen, Nebel-Atmosphaere.

	BENUTZUNG (in Roblox Studio, NICHT im Play-Modus):
	1. Neues leeres Baseplate-Place oeffnen (Baseplate kannst du loeschen)
	2. View -> Command Bar  (oder Script als "Local Plugin" speichern)
	3. Ganzen Code einfuegen + Enter. Dauer ca. 1-3 Minuten.
	   Output-Fenster oeffnen, dort siehst du den Fortschritt.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local terrain = Workspace.Terrain
local E = Enum.Material

----------------------------------------------------------------
-- EINSTELLUNGEN
----------------------------------------------------------------
local SIZE = 2000            -- Mapgroesse in Studs
local HALF = SIZE / 2
local VOX = 4                -- Terrain-Aufloesung (4 = Roblox Standard)
local N = SIZE / VOX         -- 500 Zellen pro Seite
local BASEY = -32            -- unterste Terrain-Hoehe
local NY = 104               -- Anzahl Voxel in der Hoehe (oben = 384)
local WL = 4                 -- Wasserspiegel (See)
local ROAD_HALF = 8          -- halbe Strassenbreite
local BLEND = 38             -- Breite der Boeschung neben der Strasse
local TREE_COUNT = 1500      -- Anzahl Baeume
local SEED = 11.37           -- anderen Wert = andere Map
math.randomseed(2026)

----------------------------------------------------------------
-- HILFSFUNKTIONEN
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

print("[Swiss Map] Start...")
terrain:Clear()
local old = Workspace:FindFirstChild("SwissMap")
if old then old:Destroy() end
local map = Instance.new("Folder")
map.Name = "SwissMap"
map.Parent = Workspace

----------------------------------------------------------------
-- HOEHENFORMEL
-- Norden: Mittelland (Huegel, Felder)  | Mitte: See im Westen
-- Sueden: Alpen mit Haupttal           | Rand: Bergkranz rundherum
----------------------------------------------------------------
local LAKE = { x = -430, z = -130, rx = 300, rz = 170 }

local function lakeMask(x, z)
	local dx = (x - LAKE.x) / LAKE.rx
	local dz = (z - LAKE.z) / LAKE.rz
	local d = math.sqrt(dx * dx + dz * dz) + nz(x / 120, z / 120, 10) * 0.12
	return 1 - sstep(0.55, 0.95, d)
end

local function baseHeight(x, z)
	-- Mittelland
	local mid = 34 + nz(x / 420, z / 420, 1) * 18 + nz(x / 140, z / 140, 2) * 4
	-- Alpen (nach Sueden)
	local alp = sstep(150, 450, z)
	local r = (1 - math.abs(nz(x / 330, z / 330, 3))) ^ 2 * 0.75
		+ (1 - math.abs(nz(x / 150, z / 150, 4))) ^ 2 * 0.25
	local mtn = 60 + r * 230 + nz(x / 70, z / 70, 5) * 10
	local h = lerp(mid, mtn, alp)

	-- Haupttal (schlaengelt sich von West nach Ost)
	local vz = 430 + 60 * math.sin(x / 260)
	local carve = 1 - sstep(60, 240, math.abs(z - vz))
	local floor = 24 + (x + 1000) * 0.012 + nz(x / 200, z / 200, 6) * 4
	h = lerp(h, floor, carve)

	-- Bergkranz am Kartenrand (damit niemand rausfaehrt)
	local e = sstep(760, 990, math.max(math.abs(x), math.abs(z)))
	h = h + e * (110 + 110 * r)

	-- See
	h = lerp(h, -16, lakeMask(x, z))

	if h > 280 then h = 280 + (h - 280) * 0.35 end
	return math.min(h, 376)
end

----------------------------------------------------------------
-- DOERFER (Boden wird flach gemacht)
----------------------------------------------------------------
local VILLAGES = {
	{ x = 0, z = -380 },    -- 1 Dorf Mitte (Hauptstrasse)
	{ x = -500, z = -460 }, -- 2 Dorf am See
	{ x = 520, z = -330 },  -- 3 Dorf Ost
	{ x = 0, z = 430 },     -- 4 Talort (Spawn)
	{ x = -500, z = 374 },  -- 5 Talort West
	{ x = 500, z = 486 },   -- 6 Passfuss
}
for _, v in ipairs(VILLAGES) do v.h = baseHeight(v.x, v.z) end

local function terrainH(x, z)
	local h = baseHeight(x, z)
	for _, v in ipairs(VILLAGES) do
		local d = math.sqrt((x - v.x) ^ 2 + (z - v.z) ^ 2)
		if d < 110 then h = lerp(h, v.h, 1 - sstep(60, 110, d)) end
	end
	return h
end

----------------------------------------------------------------
-- STRASSEN
----------------------------------------------------------------
local V2 = Vector2.new
local ROADS = {
	{ name = "Hauptstrasse", pts = {
		V2(-740, -450), V2(-500, -460), V2(-250, -420), V2(0, -380),
		V2(250, -400), V2(520, -330), V2(740, -300) } },
	{ name = "Talstrasse", pts = {
		V2(-740, 413), V2(-500, 374), V2(-250, 381), V2(0, 430),
		V2(250, 479), V2(500, 486), V2(740, 447) } },
	{ name = "Verbindung", pts = {
		V2(0, -380), V2(-40, -200), V2(20, 0), V2(60, 150), V2(30, 300), V2(0, 430) } },
	{ name = "Passstrasse", topH = 215, pts = { -- mit Kehren den Berg hoch
		V2(500, 486), V2(450, 540), V2(370, 590), V2(450, 650),
		V2(350, 700), V2(440, 760), V2(340, 810) } },
}

local function spline(pts)
	local out, n = {}, #pts
	for i = 1, n - 1 do
		local p0 = pts[math.max(i - 1, 1)]
		local p1, p2 = pts[i], pts[i + 1]
		local p3 = pts[math.min(i + 2, n)]
		local steps = math.max(2, math.ceil((p2 - p1).Magnitude / 6))
		for s = 0, steps - 1 do
			local t = s / steps
			local pt = 0.5 * ((2 * p1) + (p2 - p0) * t
				+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
				+ (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)
			table.insert(out, pt)
		end
	end
	table.insert(out, pts[n])
	return out
end

local CELL = 64
local hash = {}
local function addPoint(x, z, h)
	local cx = math.floor((x + 1100) / CELL)
	local cz = math.floor((z + 1100) / CELL)
	local k = cx * 64 + cz
	local t = hash[k]
	if not t then t = {}; hash[k] = t end
	t[#t + 1] = { x, z, h }
end

for _, def in ipairs(ROADS) do
	local P = spline(def.pts)
	local hs = {}
	for i, p in ipairs(P) do hs[i] = terrainH(p.X, p.Y) end
	if def.topH then
		-- Passstrasse: gleichmaessige Steigung
		local len = { 0 }
		for i = 2, #P do len[i] = len[i - 1] + (P[i] - P[i - 1]).Magnitude end
		local total, h0 = len[#P], hs[1]
		for i = 1, #P do hs[i] = lerp(h0, def.topH, len[i] / total) end
	else
		-- normale Strassen: Hoehe glaetten
		for _ = 1, 10 do
			local new = {}
			for i = 1, #P do
				local s, c = 0, 0
				for j = math.max(1, i - 6), math.min(#P, i + 6) do
					s += hs[j]; c += 1
				end
				new[i] = s / c
			end
			hs = new
		end
	end
	for i, p in ipairs(P) do addPoint(p.X, p.Y, hs[i]) end
end

-- liefert Abstand zur naechsten Strasse + Strassenhoehe
local function roadQuery(x, z)
	local cx = math.floor((x + 1100) / CELL)
	local cz = math.floor((z + 1100) / CELL)
	local best = math.huge
	for a = cx - 1, cx + 1 do
		for b = cz - 1, cz + 1 do
			local t = hash[a * 64 + b]
			if t then
				for _, p in ipairs(t) do
					local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
					if d < best then best = d end
				end
			end
		end
	end
	if best == math.huge then return nil end
	local dmin = math.sqrt(best)
	local sw, sh = 0, 0
	for a = cx - 1, cx + 1 do
		for b = cz - 1, cz + 1 do
			local t = hash[a * 64 + b]
			if t then
				for _, p in ipairs(t) do
					local d = math.sqrt((p[1] - x) ^ 2 + (p[2] - z) ^ 2)
					if d < dmin + 12 then
						local w = 1 - (d - dmin) / 12
						sw += w; sh += w * p[3]
					end
				end
			end
		end
	end
	return dmin, sh / sw
end

local function roadDist(x, z)
	local d = roadQuery(x, z)
	return d or math.huge
end

----------------------------------------------------------------
-- HOEHEN-GITTER BERECHNEN
----------------------------------------------------------------
local H, ROADF = {}, {}
for i = 1, N do
	local Hi, Ri = {}, {}
	local x = -HALF + (i - 0.5) * VOX
	for k = 1, N do
		local z = -HALF + (k - 0.5) * VOX
		local h = terrainH(x, z)
		local d, rh = roadQuery(x, z)
		if d and d < ROAD_HALF + BLEND then
			local w = 1 - sstep(ROAD_HALF, ROAD_HALF + BLEND, d)
			h = lerp(h, rh, w)
			if d <= ROAD_HALF then Ri[k] = true end
		end
		Hi[k] = h
	end
	H[i], ROADF[i] = Hi, Ri
	if i % 5 == 0 then task.wait() end
end
print("[Swiss Map] Hoehen fertig")

----------------------------------------------------------------
-- MATERIAL-GITTER (Gras, Fels, Schnee, Sand, Asphalt)
----------------------------------------------------------------
local MAT = {}
for i = 1, N do
	local Mi = {}
	local x = -HALF + (i - 0.5) * VOX
	for k = 1, N do
		local z = -HALF + (k - 0.5) * VOX
		local h = H[i][k]
		local m
		if ROADF[i][k] then
			m = E.Asphalt
		elseif h < WL + 2.5 then
			m = E.Sand
		else
			local sl = math.max(
				math.abs(H[math.min(i + 1, N)][k] - H[math.max(i - 1, 1)][k]),
				math.abs(H[i][math.min(k + 1, N)] - H[i][math.max(k - 1, 1)])) / 8
			local snow = 170 + nz(x / 90, z / 90, 7) * 25
			if h > snow and sl < 1.4 then
				m = E.Snow
			elseif h > 150 or (sl > 0.8 and h > 40) then
				m = E.Rock
			else
				local f = nz(x / 60, z / 60, 8)
				if h < 70 and f > 0.35 then m = E.LeafyGrass
				elseif h < 45 and f < -0.6 then m = E.Ground
				else m = E.Grass end
			end
		end
		Mi[k] = m
	end
	MAT[i] = Mi
	if i % 25 == 0 then task.wait() end
end
print("[Swiss Map] Materialien fertig")

----------------------------------------------------------------
-- TERRAIN SCHREIBEN (in Bloecken von 200x200 Studs)
----------------------------------------------------------------
local CH = 50
local AIR = E.Air
local wlv = (WL - BASEY) / VOX

for ci = 0, N / CH - 1 do
	for ck = 0, N / CH - 1 do
		local x0 = -HALF + ci * CH * VOX
		local z0 = -HALF + ck * CH * VOX
		local region = Region3.new(
			Vector3.new(x0, BASEY, z0),
			Vector3.new(x0 + CH * VOX, BASEY + NY * VOX, z0 + CH * VOX))
		local mats, occs = {}, {}
		for a = 1, CH do
			local ma, oa = {}, {}
			for b = 1, NY do
				ma[b] = table.create(CH, AIR)
				oa[b] = table.create(CH, 0)
			end
			mats[a], occs[a] = ma, oa
		end
		for a = 1, CH do
			for c = 1, CH do
				local i, k = ci * CH + a, ck * CH + c
				local h, surf = H[i][k], MAT[i][k]
				local deep = (h > 110) and E.Rock or E.Ground
				local top = clamp((h - BASEY) / VOX, 0, NY - 1)
				local full = math.floor(top)
				local frac = top - full
				local ma, oa = mats[a], occs[a]
				for b = 1, full do
					ma[b][c] = (top - b < 2) and surf or deep
					oa[b][c] = 1
				end
				local nextFree = full + 1
				if frac > 0.02 then
					ma[full + 1][c] = surf
					oa[full + 1][c] = frac
					nextFree = full + 2
				end
				if top < wlv then
					for b = nextFree, wlv do
						ma[b][c] = E.Water
						oa[b][c] = 1
					end
				end
			end
		end
		terrain:WriteVoxels(region, VOX, mats, occs)
		task.wait()
	end
	print(("[Swiss Map] Terrain %d%%"):format(math.floor((ci + 1) / (N / CH) * 100)))
end

----------------------------------------------------------------
-- STIL: Farben, Wasser, Nebel, Licht
----------------------------------------------------------------
pcall(function()
	terrain:SetMaterialColor(E.Grass, Color3.fromRGB(78, 130, 62))
	terrain:SetMaterialColor(E.LeafyGrass, Color3.fromRGB(98, 150, 70))
	terrain:SetMaterialColor(E.Rock, Color3.fromRGB(118, 120, 128))
	terrain:SetMaterialColor(E.Ground, Color3.fromRGB(112, 88, 66))
	terrain:SetMaterialColor(E.Sand, Color3.fromRGB(198, 184, 140))
	terrain:SetMaterialColor(E.Snow, Color3.fromRGB(240, 245, 250))
	terrain:SetMaterialColor(E.Asphalt, Color3.fromRGB(66, 68, 74))
end)
terrain.WaterColor = Color3.fromRGB(40, 125, 170)
terrain.WaterTransparency = 0.55
terrain.WaterReflectance = 0.25
terrain.WaterWaveSize = 0.15
pcall(function() terrain.Decoration = true end)

Lighting.ClockTime = 14
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(90, 100, 120)
local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
atm.Density = 0.33
atm.Offset = 0.25
atm.Color = Color3.fromRGB(168, 196, 228)
atm.Decay = Color3.fromRGB(105, 140, 195)
atm.Glare = 0
atm.Haze = 1.6

----------------------------------------------------------------
-- OBJEKTE: Chalets, Kirche, Baeume
----------------------------------------------------------------
local function heightAt(x, z)
	local i = clamp(math.floor((x + HALF) / VOX) + 1, 1, N)
	local k = clamp(math.floor((z + HALF) / VOX) + 1, 1, N)
	return H[i][k]
end

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
	return p
end

-- Satteldach + ausgefuellter Giebel
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

local function chalet(parent, pos, yaw)
	local m = Instance.new("Model")
	m.Name = "Chalet"
	m.Parent = parent
	local w, d, wallH = 12 + math.random(0, 4), 16 + math.random(0, 6), 9
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local wallC = (math.random() < 0.5) and Color3.fromRGB(150, 100, 62) or Color3.fromRGB(236, 222, 190)
	local roofC = (math.random() < 0.5) and Color3.fromRGB(96, 62, 48) or Color3.fromRGB(150, 74, 60)
	part(m, Vector3.new(w + 1, 2, d + 1), base, Color3.fromRGB(150, 150, 150), E.Concrete)
	part(m, Vector3.new(w, wallH, d), base * CFrame.new(0, 1 + wallH / 2, 0), wallC, E.Wood)
	local rise = gableRoof(m, base, 1 + wallH, w, d, roofC, wallC)
	part(m, Vector3.new(3, 5, 0.4), base * CFrame.new(0, 3.5, d / 2 + 0.1), Color3.fromRGB(80, 52, 36), E.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(2.6, 2.6, 0.4), base * CFrame.new(sx * w / 4 + sx * 1, 6.5, d / 2 + 0.1),
			Color3.fromRGB(160, 200, 230), E.Glass)
		part(m, Vector3.new(0.8, 3, 0.5), base * CFrame.new(sx * w / 4 + sx * 3, 6.5, d / 2 + 0.1),
			Color3.fromRGB(190, 60, 55), E.Wood)
	end
	part(m, Vector3.new(2, 5, 2), base * CFrame.new(w / 4, 1 + wallH + rise * 0.6, -d / 4),
		Color3.fromRGB(120, 115, 110), E.Brick)
end

local function church(parent, pos, yaw)
	local m = Instance.new("Model")
	m.Name = "Kirche"
	m.Parent = parent
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local white = Color3.fromRGB(240, 236, 226)
	part(m, Vector3.new(16, 2, 28), base, Color3.fromRGB(150, 150, 150), E.Concrete)
	part(m, Vector3.new(14, 11, 24), base * CFrame.new(0, 6.5, 2), white)
	gableRoof(m, base * CFrame.new(0, 0, 2), 12, 14, 24, Color3.fromRGB(120, 60, 52), white)
	part(m, Vector3.new(8, 30, 8), base * CFrame.new(0, 16, -14), white)
	for s = 0, 5 do
		local sw = 9 * (1 - s / 6) + 0.5
		part(m, Vector3.new(sw, 3, sw), base * CFrame.new(0, 32.5 + s * 3, -14), Color3.fromRGB(120, 60, 52))
	end
end

local function tryPlace(v, rmin, rmax, gap, placed)
	for _ = 1, 40 do
		local a = math.random() * math.pi * 2
		local r = rmin + math.random() * (rmax - rmin)
		local x, z = v.x + math.cos(a) * r, v.z + math.sin(a) * r
		if roadDist(x, z) > ROAD_HALF + 14 then
			local ok = true
			for _, p in ipairs(placed) do
				if (p.x - x) ^ 2 + (p.z - z) ^ 2 < gap * gap then ok = false; break end
			end
			if ok then
				placed[#placed + 1] = { x = x, z = z }
				local yaw = math.atan2(-math.cos(a), -math.sin(a))
				yaw = math.floor(yaw / (math.pi / 2) + 0.5) * (math.pi / 2)
				return x, z, yaw
			end
		end
	end
end

for vi, v in ipairs(VILLAGES) do
	local vf = Instance.new("Folder")
	vf.Name = "Dorf" .. vi
	vf.Parent = map
	local placed = {}
	local cx, cz, cyaw = tryPlace(v, 28, 50, 30, placed)
	if cx then church(vf, Vector3.new(cx, heightAt(cx, cz) + 0.2, cz), cyaw) end
	for _ = 1, math.random(9, 14) do
		local x, z, yaw = tryPlace(v, 22, 64, 24, placed)
		if x then chalet(vf, Vector3.new(x, heightAt(x, z) + 0.2, z), yaw) end
	end
	task.wait()
end
print("[Swiss Map] Doerfer fertig")

-- Baeume (eigenes Modell nutzen: Model "TreeTemplate" in ServerStorage legen)
local template = ServerStorage:FindFirstChild("TreeTemplate")
local function tree(parent, x, z, y)
	local s = 0.8 + math.random() * 1.0
	if template then
		local c = template:Clone()
		c.Parent = parent
		c:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, math.random() * 6.28, 0))
		return
	end
	local up = CFrame.Angles(0, 0, math.pi / 2)
	part(parent, Vector3.new(6 * s, 1.4 * s, 1.4 * s), CFrame.new(x, y + 3 * s, z) * up,
		Color3.fromRGB(90, 62, 48), E.Wood, Enum.PartType.Cylinder)
	local g = math.random() * 18
	for t = 0, 2 do
		local dia = (13 - 3.8 * t) * s
		part(parent, Vector3.new(5 * s, dia, dia), CFrame.new(x, y + (5 + t * 4.2) * s, z) * up,
			Color3.fromRGB(34 + g, 96 + g * 1.5, 52), E.SmoothPlastic, Enum.PartType.Cylinder, false)
	end
end

local trees = Instance.new("Folder")
trees.Name = "Baeume"
trees.Parent = map
local placedTrees, attempts = 0, 0
while placedTrees < TREE_COUNT and attempts < TREE_COUNT * 14 do
	attempts += 1
	local x = (math.random() * 2 - 1) * (HALF - 30)
	local z = (math.random() * 2 - 1) * (HALF - 30)
	local i = clamp(math.floor((x + HALF) / VOX) + 1, 1, N)
	local k = clamp(math.floor((z + HALF) / VOX) + 1, 1, N)
	local h, m = H[i][k], MAT[i][k]
	if (m == E.Grass or m == E.LeafyGrass) and h > WL + 4 and h < 150
		and nz(x / 180, z / 180, 9) > -0.15 and roadDist(x, z) > ROAD_HALF + 10 then
		local nearV = false
		for _, v in ipairs(VILLAGES) do
			if (v.x - x) ^ 2 + (v.z - z) ^ 2 < 85 * 85 then nearV = true; break end
		end
		if not nearV then
			tree(trees, x, z, h - 0.5)
			placedTrees += 1
		end
	end
	if attempts % 400 == 0 then task.wait() end
end

-- Spawn im Talort
do
	local v = VILLAGES[4]
	local x, z = v.x + 18, v.z + 18
	local sp = Instance.new("SpawnLocation")
	sp.Anchored = true
	sp.Neutral = true
	sp.Size = Vector3.new(12, 1, 12)
	sp.Position = Vector3.new(x, heightAt(x, z) + 1, z)
	sp.Transparency = 1
	sp.Parent = map
end

print(("[Swiss Map] FERTIG! %d Baeume. Viel Spass mit dem Toeffli-Spiel!"):format(placedTrees))# T-ffligame
