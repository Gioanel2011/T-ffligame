--[[
	SCHWEIZER MAP GENERATOR - VERSION 43
	------------------------------------------------------------
	Karte 8000 x 8000, Rand eckig.
	Rechteckiges, unregelmaessiges, langgestrecktes Tal (West-Ost)
	-> Bergmassive mit 2 Paessen -> Autobahn als abgerundetes Rechteck
	-> aeusserer Bergrahmen am Kartenrand.

	NUR EIN SEE, KEINE FLUESSE.
	See-Bruecke: Deck ausschliesslich ueber Wasser, Pfeiler nur im Wasser.

	KREUZUNGEN (Fix gegen Hoehenversatz):
	- jede Kreuzung ist ein exakt gemeinsamer Knoten,
	- alle Strassen werden an diesem Knoten auf EINE Hoehe gepinnt,
	- um jede Kreuzung liegt eine flache Zone + ein flaches Kreuzungspad,
	- das Terrain darunter wird auf dieselbe Hoehe gezogen.
	-> keine Strasse liegt an einer Kreuzung hoeher als die andere.

	Strassen: Talstrasse, Nord-/Suedstrasse, Querstrassen, Diagonalen,
	Seestrasse (Bruecke), 2 Passstrassen, Autobahn. Innerorts kleine
	unregelmaessige Gassennetze. Alle Kurven: zentripetale Catmull-Rom.

	BENUTZUNG: Roblox Studio, Command Bar, NICHT im Play-Modus.
	Dauer: ca. 10-18 Minuten.
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
local ROAD_TOP = 1.1
local ROAD_EMBED = 1.3
local BRIDGE_H = 9
local SEED = 11.37
local CH = 50
math.randomseed(2026)

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function sstep(a, b, x) local t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t) end
local function nz(x, z, s) return math.noise(x + 0.37, z + 0.71, SEED + (s or 0)) * 2 end
local function IDX(i, k) return (i - 1) * NZ + k end
local function V2(x, z) return Vector2.new(x, z) end
local function angDist(a, b)
	local d = math.abs((a - b) % 360)
	if d > 180 then d = 360 - d end
	return d
end
local T0 = os.clock()

print("[v43] Start...")
terrain:Clear()
local old = Workspace:FindFirstChild("SwissMap")
if old then old:Destroy() end
local map = Instance.new("Folder")
map.Name = "SwissMap"
map.Parent = Workspace

----------------------------------------------------------------
-- 1. TERRAIN-FORM (Tal, Berge, Paesse, See, Autobahn)
----------------------------------------------------------------
local VAX, VAZ = 2800, 1550
local AHX, AHZ, AHR = 3350, 2350, 650

-- unregelmaessiges, langgestrecktes Tal (normierter Radius, 1 = Talrand)
local function valleyN(x, z)
	local dx, dz = x / VAX, z / VAZ
	local r = math.sqrt(dx * dx + dz * dz)
	local a = math.atan2(dz, dx)
	local w = 1
		+ 0.050 * math.sin(2 * a + 0.6)
		+ 0.035 * math.sin(3 * a + 2.1)
		+ 0.020 * math.sin(5 * a + 4.0)
		+ 0.025 * math.sin(7 * a + 1.2)
	-- auswaerts gerichtete Bucht beim See (SW), damit der See im Tal liegt
	local da = math.atan2(math.sin(a - 2.64), math.cos(a - 2.64))
	w = w + 0.090 * math.exp(-(da * da) / 0.22)
	return r / w
end

local function rrectD(x, z)
	local qx = math.abs(x) - (AHX - AHR)
	local qz = math.abs(z) - (AHZ - AHR)
	local ax, az = math.max(qx, 0), math.max(qz, 0)
	return math.sqrt(ax * ax + az * az) + math.min(math.max(qx, qz), 0) - AHR
end

local LAKE = { x = -1850, z = 560, rx = 430, rz = 300 }
local function lakeD(x, z)
	local dx, dz = (x - LAKE.x) / LAKE.rx, (z - LAKE.z) / LAKE.rz
	local r = math.sqrt(dx * dx + dz * dz)
	local a = math.atan2(dz, dx)
	local w = 1
		+ 0.10 * math.sin(3 * a + 1.2)
		+ 0.055 * math.sin(5 * a + 3.4)
		+ 0.035 * math.sin(2 * a + 0.3)
	return r / w + nz(x / 140, z / 140, 10) * 0.03
end
local function lakeMask(x, z) return 1 - sstep(0.55, 1.0, lakeD(x, z)) end

local PASSES = {
	{ V2(-2450, 120), V2(-2900, 60), V2(-AHX, 0) },
	{ V2(2450, -60), V2(2900, -30), V2(AHX, 0) },
}
local function segDist(x, z, a, b)
	local dx, dz = b.X - a.X, b.Y - a.Y
	local L2 = dx * dx + dz * dz
	local t = clamp(((x - a.X) * dx + (z - a.Y) * dz) / math.max(L2, 0.001), 0, 1)
	local px, pz = a.X + dx * t, a.Y + dz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end
local function passDist(x, z)
	local best = 1e9
	for _, path in ipairs(PASSES) do
		for i = 1, #path - 1 do
			local d = segDist(x, z, path[i], path[i + 1])
			if d < best then best = d end
		end
	end
	return best
end

local HILLS = {
	{ x = -900, z = -500, rx = 820, rz = 540, h = 13 },
	{ x = 600, z = 720, rx = 760, rz = 480, h = 10 },
	{ x = 1900, z = -330, rx = 620, rz = 400, h = 9 },
	{ x = 1550, z = -620, rx = 155, rz = 155, h = 24 }, -- Burgberg
}

local function mountainH(x, z)
	local ridge = 1 - math.abs(nz(x / 300, z / 300, 23))
	local h = 330 + ridge * 200 + nz(x / 90, z / 90, 25) * 28
	h = h + 170 * math.exp(-(((x - 0) / 520) ^ 2 + ((z + 2050) / 480) ^ 2)) -- Hausberg
	h = h + 90 * math.exp(-(((x + 1500) / 450) ^ 2 + ((z + 1750) / 420) ^ 2))
	h = h + 80 * math.exp(-(((x - 1650) / 460) ^ 2 + ((z + 1700) / 430) ^ 2))
	h = h + 80 * math.exp(-(((x + 1650) / 480) ^ 2 + ((z - 1550) / 440) ^ 2))
	h = h + 75 * math.exp(-(((x - 1750) / 460) ^ 2 + ((z - 1500) / 430) ^ 2))
	return h
end

local function heightRaw(x, z)
	local t = valleyN(x, z)
	local dAuto = rrectD(x, z)
	local h = PLAIN + nz(x / 900, z / 900, 31) * 1.8 + nz(x / 380, z / 380, 32) * 0.7
	for i, hill in ipairs(HILLS) do
		local dx = (x - hill.x) / hill.rx
		local dz = (z - hill.z) / hill.rz
		local d = math.sqrt(dx * dx + dz * dz) + nz(x / 300, z / 300, 40 + i) * 0.08
		local s = clamp(1 - d, 0, 1)
		h = h + hill.h * (s * s * (3 - 2 * s))
	end
	-- Basis steigt ausserhalb des Tals auf das Plateau
	h = lerp(h, PLATEAU + nz(x / 260, z / 260, 70) * 2.0, sstep(1.0, 1.35, t))
	-- innerer Bergkranz (zwischen Talrand und Autobahn)
	local dVal = (t - 1) * 1550
	local dIn = -dAuto
	local m = sstep(90, 430, dVal) * sstep(60, 220, dIn)
	if m > 0 then h = lerp(h, mountainH(x, z), m) end
	-- 2 Passkorridore
	local pd = passDist(x, z)
	local pm = (1 - sstep(70, 180, pd))
		* sstep(2250, 2450, math.abs(x))
		* (1 - sstep(-60, 30, dAuto))
	if pm > 0 then
		local pf = lerp(PLAIN + 1, PLATEAU + 1, sstep(2450, 3250, math.abs(x)))
		h = lerp(h, pf, pm)
	end
	-- Autobahn-Plateau flach
	local am = 1 - sstep(50, 190, math.abs(dAuto))
	if am > 0 then h = lerp(h, PLATEAU, am) end
	-- aeusserer Bergrahmen
	local om = sstep(140, 700, dAuto)
	if om > 0 then
		local ridge = 1 - math.abs(nz(x / 340, z / 340, 26))
		local oh = 360 + ridge * 200 + nz(x / 95, z / 95, 27) * 30
		oh = oh + 170 * math.exp(-(((math.abs(x) - 3550) / 650) ^ 2 + ((math.abs(z) - 3550) / 650) ^ 2))
		h = lerp(h, oh, om)
	end
	-- See
	local lm = lakeMask(x, z)
	if lm > 0 then h = lerp(h, LAKE_BED, lm) end
	if lm < 0.02 then h = math.max(h, WL + 2) end
	return clamp(h, 2, 720)
end
----------------------------------------------------------------
-- 2. STRASSEN-KLASSEN, SPLINE, NETZ
----------------------------------------------------------------
local CLS = {
	main = { half = 16, paint = 15, mark = true, dash = 46, dashLen = 15 },
	sec = { half = 12, paint = 11, mark = true, dash = 54, dashLen = 10 },
	quart = { half = 8, paint = 7, mark = false, dash = 0, dashLen = 0 },
	auto = { half = 18, paint = 16, mark = false, dash = 0, dashLen = 0 },
}

-- zentripetale Catmull-Rom-Spline (alpha = 0.5)
local function catmull(pts, closed, step)
	step = step or 7
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

local NET = {}
local function addRoad(name, cls, pts, closed)
	local c = CLS[cls]
	NET[#NET + 1] = {
		name = name, cls = cls, half = c.half, paint = c.paint,
		mark = c.mark, dash = c.dash, dashLen = c.dashLen,
		P = catmull(pts, closed or false, 7), closed = closed or false,
		auto = (cls == "auto"),
	}
	return NET[#NET]
end
local function addRaw(name, cls, P, closed)
	local c = CLS[cls]
	NET[#NET + 1] = {
		name = name, cls = cls, half = c.half, paint = c.paint,
		mark = c.mark, dash = c.dash, dashLen = c.dashLen,
		P = P, closed = closed or false, auto = (cls == "auto"),
	}
	return NET[#NET]
end

local function nearestOn(P, x, z)
	local bi, bd = 1, math.huge
	for i, p in ipairs(P) do
		local d = (p.X - x) ^ 2 + (p.Y - z) ^ 2
		if d < bd then bd, bi = d, i end
	end
	return bi, P[bi]
end
local function nearX(P, x)
	local bi = 1
	for i, p in ipairs(P) do
		if math.abs(p.X - x) < math.abs(P[bi].X - x) then bi = i end
	end
	return bi, P[bi]
end
local function tangent(P, i)
	local a = P[math.max(1, i - 1)]
	local b = P[math.min(#P, i + 1)]
	local dx, dz = b.X - a.X, b.Y - a.Y
	local L = math.sqrt(dx * dx + dz * dz)
	if L < 0.001 then return 0, 1 end
	return dx / L, dz / L
end

-- Autobahn: abgerundetes Rechteck (lange Geraden + 4 weite Kurven)
local function autoPath()
	local pts = {}
	local function line(x0, z0, x1, z1, step)
		local n = math.max(2, math.ceil(math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) / step))
		for i = 0, n - 1 do pts[#pts + 1] = V2(lerp(x0, x1, i / n), lerp(z0, z1, i / n)) end
	end
	local function arc(cx, cz, a0, a1, stepDeg)
		local n = math.max(3, math.ceil(math.abs(a1 - a0) / stepDeg))
		for i = 0, n - 1 do
			local a = math.rad(lerp(a0, a1, i / n))
			pts[#pts + 1] = V2(cx + math.cos(a) * AHR, cz + math.sin(a) * AHR)
		end
	end
	line(AHX, -(AHZ - AHR), AHX, 0, 90)
	line(AHX, 0, AHX, AHZ - AHR, 90)
	arc(AHX - AHR, AHZ - AHR, 0, 90, 7.5)
	line(AHX - AHR, AHZ, -(AHX - AHR), AHZ, 90)
	arc(-(AHX - AHR), AHZ - AHR, 90, 180, 7.5)
	line(-AHX, AHZ - AHR, -AHX, 0, 90)
	line(-AHX, 0, -AHX, -(AHZ - AHR), 90)
	arc(-(AHX - AHR), -(AHZ - AHR), 180, 270, 7.5)
	line(-(AHX - AHR), -AHZ, (AHX - AHR), -AHZ, 90)
	arc(AHX - AHR, -(AHZ - AHR), 270, 360, 7.5)
	pts[#pts + 1] = pts[1]
	return pts
end

local TAL = addRoad("Talstrasse", "main", {
	V2(-2450, 120), V2(-1550, -120), V2(-550, 140), V2(450, -80), V2(1450, 120), V2(2450, -60),
})
local NOR = addRoad("Nordstrasse", "sec", {
	V2(-2000, -820), V2(-1250, -1050), V2(-250, -860), V2(850, -1010), V2(1950, -800),
})
local SUD = addRoad("Suedstrasse", "sec", {
	V2(-1750, 900), V2(-1300, 1160), V2(-350, 960), V2(700, 1210), V2(1700, 1010), V2(2050, 800),
})
local AUTO = addRaw("Autobahn", "auto", autoPath(), true)

-- 7 Orte: 2 gross, 3 mittel, 2 Weiler
local TOWNS = {
	{ name = "Mitteldorf", road = TAL, x = -550,  size = "large",  church = true,  flat = 310, L = 500, cross = { 0, 0.24, 0.56, 0.84 }, off = 200 },
	{ name = "Seeburg",    road = TAL, x = -1650, size = "large",  church = true,  flat = 300, L = 460, cross = { 0, 0.26, 0.58, 0.86 }, off = 190 },
	{ name = "Ostheim",    road = TAL, x = 1450,  size = "medium", church = false, flat = 210, L = 300, cross = { 0, 0.38, 0.74 },         off = 140 },
	{ name = "Nordegg",    road = NOR, x = 850,   size = "medium", church = false, flat = 200, L = 280, cross = { 0, 0.34, 0.72 },         off = 130 },
	{ name = "Suedhalde",  road = SUD, x = 700,   size = "medium", church = true,  flat = 200, L = 280, cross = { 0, 0.40, 0.76 },         off = 130 },
	{ name = "Westau",     road = TAL, x = -2350, size = "small",  church = false, flat = 120, L = 150, cross = { 0.22, 0.68 },           off = 95 },
	{ name = "Bergheim",   road = NOR, x = -1250, size = "small",  church = false, flat = 120, L = 150, cross = { 0.24, 0.70 },           off = 95 },
}
for _, t in ipairs(TOWNS) do
	local ci, p = nearX(t.road.P, t.x)
	t.ci = ci
	t.cx, t.cz = p.X, p.Y
	t.h = heightRaw(p.X, p.Y)
	t.roads = {}
end

local CASTLE = { x = 1550, z = -620, yaw = 0.35 }
CASTLE.h = heightRaw(CASTLE.x, CASTLE.z)

local function heightPlain(x, z)
	local h = heightRaw(x, z)
	for _, t in ipairs(TOWNS) do
		local dx, dz = x - t.cx, z - t.cz
		local d = math.sqrt(dx * dx + dz * dz)
		if d < t.flat + 80 and lakeMask(x, z) < 0.05 then
			h = lerp(h, t.h, 1 - sstep(t.flat, t.flat + 80, d))
		end
	end
	local dx, dz = x - CASTLE.x, z - CASTLE.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 100 then h = lerp(h, CASTLE.h, 1 - sstep(58, 100, d)) end
	return h
end

-- kleine unregelmaessige Gassennetze pro Ort
local function townGrid(t)
	local P, ci = t.road.P, t.ci
	local iA, iB = ci, ci
	local acc = 0
	while iA > 1 and acc < t.L / 2 do acc = acc + (P[iA] - P[iA - 1]).Magnitude; iA = iA - 1 end
	acc = 0
	while iB < #P and acc < t.L / 2 do acc = acc + (P[iB + 1] - P[iB]).Magnitude; iB = iB + 1 end
	local nodes = {}
	local jn = { 1.00, 0.94, 1.06, 0.97, 1.02 }
	local js = { 0.96, 1.05, 0.95, 1.02, 0.98 }
	for k, f in ipairs(t.cross) do
		local idx = clamp(math.floor(iA + (iB - iA) * f + 0.5), 1, #P)
		local M = P[idx]
		local tx, tz = tangent(P, idx)
		nodes[#nodes + 1] = {
			M = M, idx = idx, tx = tx, tz = tz, nx = -tz, nz = tx,
			oN = t.off * jn[((k - 1) % #jn) + 1],
			oS = t.off * js[((k - 1) % #js) + 1],
			shift = t.off * 0.14 * ((t.x > 0) and 1 or -1),
		}
	end
	local par = { {}, {} }
	for side = 1, 2 do
		for i, nd in ipairs(nodes) do
			local off = (side == 1) and nd.oN or -nd.oS
			par[side][i] = V2(nd.M.X + nd.nx * off + nd.tx * nd.shift,
				nd.M.Y + nd.nz * off + nd.tz * nd.shift)
		end
	end
	for i, nd in ipairs(nodes) do
		local r = addRoad(t.name .. " Gasse " .. i, "quart", { par[1][i], nd.M, par[2][i] })
		t.roads[#t.roads + 1] = r
	end
	-- Parallelstrassen mit Ueberstand -> keine geschlossenen Rechtecke
	for side = 1, 2 do
		local pts = {}
		local a, b = nodes[1], nodes[#nodes]
		pts[#pts + 1] = V2(par[side][1].X - a.tx * 58, par[side][1].Y - a.tz * 58)
		for i = 1, #nodes do pts[#pts + 1] = par[side][i] end
		pts[#pts + 1] = V2(par[side][#nodes].X + b.tx * 58, par[side][#nodes].Y + b.tz * 58)
		t.roads[#t.roads + 1] = addRoad(t.name .. " Rand " .. side, "quart", pts)
	end
	-- schraege Gasse quer durch den Ort
	if #nodes >= 3 then
		local a = par[1][2]
		local b = par[2][#nodes]
		local mx, mz = (a.X + b.X) / 2, (a.Y + b.Y) / 2
		t.roads[#t.roads + 1] = addRoad(t.name .. " Schlaufe", "quart",
			{ a, V2(mx + 18, mz - 14), b })
	end
	-- Stichgasse von der Hauptstrasse in den Block
	if #nodes >= 2 then
		local mid = clamp(math.floor((nodes[1].idx + nodes[2].idx) / 2), 1, #P)
		local M = P[mid]
		local tx, tz = tangent(P, mid)
		local sgn = (t.name == "Seeburg") and -1 or 1
		local off = t.off * 0.45
		t.roads[#t.roads + 1] = addRoad(t.name .. " Stich", "quart",
			{ M, V2(M.X - tz * off * sgn, M.Y + tx * off * sgn) })
	end
end
for _, t in ipairs(TOWNS) do townGrid(t) end

-- Querstrassen zwischen Nord, Tal und Sued (ungleichmaessig)
for _, x in ipairs({ -900, 250, 1100, 2050 }) do
	local _, pn = nearX(NOR.P, x)
	local _, pt = nearX(TAL.P, x)
	local _, ps = nearX(SUD.P, x)
	addRoad("Querstrasse " .. x, "sec", { pn, pt, ps })
end

-- 2 Diagonalen (kreuz und quer) mit leichten Schlenkern
do
	local _, pn = nearX(NOR.P, 300)
	local _, pt = nearX(TAL.P, 900)
	local _, ps = nearX(SUD.P, 1600)
	addRoad("Diagonale Ost 1", "sec", { pn, V2(430, -420), pt, V2(1250, 520), ps })
	local _, qn = nearX(NOR.P, 1500)
	local _, qt = nearX(TAL.P, 1200)
	local _, qs = nearX(SUD.P, 1900)
	addRoad("Diagonale Ost 2", "sec", { qn, V2(1420, -420), qt, V2(1550, 520), qs })
end

-- Diagonale im Westen (macht aus dem Nordende eine Schleife)
do
	local _, pn = nearX(NOR.P, -1800)
	local _, pt = nearX(TAL.P, -2100)
	addRoad("Diagonale West", "sec", { pn, V2(-1950, -450), pt })
end

-- Seestrasse mit Bruecke ueber den See
do
	local _, pt = nearX(TAL.P, -1750)
	local _, ps = nearX(SUD.P, -1700)
	addRoad("Seestrasse", "sec", { pt, V2(-1960, 300), V2(-2030, 600), V2(-1880, 900), ps })
end

-- Stichwege in Seitentaeler
do
	local _, p = nearX(SUD.P, -350)
	addRoad("Stichweg Farm", "quart", { p, V2(-300, 1280), V2(-260, 1400) })
	local _, q = nearX(NOR.P, -250)
	addRoad("Stichweg Aussicht", "quart", { q, V2(-250, -1180), V2(-220, -1340) })
end

-- Burgweg zum Aussichtspunkt
do
	local _, p = nearX(TAL.P, 1200)
	addRoad("Burgweg", "quart", { p, V2(1550, -300), V2(1550, -600) })
end

-- 2 Passstrassen zur Autobahn
do
	local _, p = nearX(TAL.P, -2450)
	addRoad("Pass West", "sec", { p, V2(-2900, 60), V2(-AHX, 0) })
	local _, q = nearX(TAL.P, 2450)
	addRoad("Pass Ost", "sec", { q, V2(2900, -30), V2(AHX, 0) })
end
print(("[v43] %d Strassen definiert"):format(#NET))
----------------------------------------------------------------
-- 3. KREUZUNGEN: Schnittpunkte, exakte Knoten, Hoehen-Pinning
----------------------------------------------------------------
local function segInt(a, b, c, d)
	local rx, rz = b.X - a.X, b.Y - a.Y
	local sx, sz = d.X - c.X, d.Y - c.Y
	local den = rx * sz - rz * sx
	if math.abs(den) < 1e-8 then return nil end
	local qx, qz = c.X - a.X, c.Y - a.Y
	local t = (qx * sz - qz * sx) / den
	local u = (qx * rz - qz * rx) / den
	if t < -1e-5 or t > 1 + 1e-5 or u < -1e-5 or u > 1 + 1e-5 then return nil end
	return t, u, a.X + rx * t, a.Y + rz * t
end

-- 3a. alle Segmente in ein grobes Raster legen
local CELL = 60
local cellT = {}
local function cellsOf(a, b, fn)
	local x0, x1 = math.min(a.X, b.X), math.max(a.X, b.X)
	local z0, z1 = math.min(a.Y, b.Y), math.max(a.Y, b.Y)
	local c0 = math.floor((x0 + HALF) / CELL)
	local c1 = math.floor((x1 + HALF) / CELL)
	local d0 = math.floor((z0 + HALF) / CELL)
	local d1 = math.floor((z1 + HALF) / CELL)
	for cx = c0, c1 do
		for cz = d0, d1 do
			fn(cx * 100000 + cz)
		end
	end
end
for ri, r in ipairs(NET) do
	local P = r.P
	for si = 1, #P - 1 do
		local a, b = P[si], P[si + 1]
		cellsOf(a, b, function(k)
			local t = cellT[k]
			if not t then t = {}; cellT[k] = t end
			t[#t + 1] = { ri = ri, si = si, a = a, b = b }
		end)
	end
end

local INS = {}
local function insAdd(ri, si, t, p)
	local a = INS[ri]
	if not a then a = {}; INS[ri] = a end
	local b = a[si]
	if not b then b = {}; a[si] = b end
	b[#b + 1] = { t = t, p = p }
end

local tested = {}
for _, list in pairs(cellT) do
	for i = 1, #list - 1 do
		local e1 = list[i]
		for j = i + 1, #list do
			local e2 = list[j]
			if e1.ri ~= e2.ri then
				local r1, r2 = e1.ri, e2.ri
				local s1, s2 = e1.si, e2.si
				if r1 > r2 then r1, r2, s1, s2 = r2, r1, s2, s1; e1, e2 = e2, e1 end
				local key = r1 .. "|" .. s1 .. "|" .. r2 .. "|" .. s2
				if not tested[key] then
					tested[key] = true
					local t, u, px, pz = segInt(e1.a, e1.b, e2.a, e2.b)
					if t then
						local atA = (t < 1e-4 or t > 1 - 1e-4)
						local atB = (u < 1e-4 or u > 1 - 1e-4)
						if not (atA and atB) then
							local p = V2(px, pz)
							if not atA then insAdd(e1.ri, e1.si, t, p) end
							if not atB then insAdd(e2.ri, e2.si, u, p) end
						end
					end
				end
			end
		end
	end
end

-- 3b. Schnittpunkte in die Polylinien einsetzen
for ri, r in ipairs(NET) do
	local a = INS[ri]
	if a then
		local P = r.P
		local NP = {}
		for si = 1, #P - 1 do
			NP[#NP + 1] = P[si]
			local b = a[si]
			if b then
				table.sort(b, function(x, y) return x.t < y.t end)
				local last = NP[#NP]
				for _, e in ipairs(b) do
					if (e.p - last).Magnitude > 0.30 then
						NP[#NP + 1] = e.p
						last = e.p
					end
				end
			end
		end
		NP[#NP + 1] = P[#P]
		r.P = NP
	end
end
print(("[v43] Kreuzungen eingesetzt, %d Strassen"):format(#NET))

-- 3c. gemeinsame Knoten + eine Hoehe pro Knoten
local buckets = {}
local function keyOf(x, z) return string.format("%.2f:%.2f", x, z) end
for ri, r in ipairs(NET) do
	for i, p in ipairs(r.P) do
		local k = keyOf(p.X, p.Y)
		local b = buckets[k]
		if not b then b = {}; buckets[k] = b end
		b[#b + 1] = { ri = ri, i = i }
	end
end
local JUN = {}
for _, b in pairs(buckets) do
	local seen, n = {}, 0
	for _, e in ipairs(b) do
		if not seen[e.ri] then seen[e.ri] = true; n = n + 1 end
	end
	if n >= 2 then
		local sx, sz, maxHalf = 0, 0, 0
		for _, e in ipairs(b) do
			local p = NET[e.ri].P[e.i]
			sx = sx + p.X; sz = sz + p.Y
			if NET[e.ri].half > maxHalf then maxHalf = NET[e.ri].half end
		end
		local x, z = sx / #b, sz / #b
		local padR = maxHalf * 1.7 + 4
		JUN[#JUN + 1] = { x = x, z = z, y = heightPlain(x, z), padR = padR, flatR = padR + 10 }
	end
end
print(("[v43] %d Kreuzungen"):format(#JUN))

-- 3d. Hoehenprofile: Strassen glatt, Kreuzungen flach und exakt gleich hoch
for _, r in ipairs(NET) do
	local P = r.P
	local hs = {}
	local pinY, pinW = {}, {}
	for i, p in ipairs(P) do
		hs[i] = heightPlain(p.X, p.Y)
		local bestD, bestY, bestF
		for _, j in ipairs(JUN) do
			local d2 = (p.X - j.x) ^ 2 + (p.Y - j.z) ^ 2
			if d2 < (j.flatR + 50) ^ 2 and (not bestD or d2 < bestD) then
				bestD, bestY, bestF = d2, j.y, j.flatR
			end
		end
		if bestD then
			local d = math.sqrt(bestD)
			local w = 1 - sstep(bestF, bestF + 50, d)
			if w > 0 then pinY[i] = bestY; pinW[i] = w end
		end
	end
	for _ = 1, 14 do
		local n = {}
		for i = 1, #P do
			local w = pinW[i]
			if w and w >= 0.999 then
				n[i] = pinY[i]
			else
				local s, c = 0, 0
				for k = math.max(1, i - 8), math.min(#P, i + 8) do
					s = s + hs[k]; c = c + 1
				end
				local avg = s / c
				if w and w > 0 then n[i] = lerp(avg, pinY[i], w) else n[i] = avg end
			end
		end
		hs = n
	end
	for i = 1, #P do
		if pinW[i] and pinW[i] >= 0.999 then hs[i] = pinY[i] end
	end
	r.hs, r.pinW, r.pinY = hs, pinW, pinY
end

-- 3e. Bruecke: nur ueber Wasser, Hoehe anheben, Land wieder glätten
for _, r in ipairs(NET) do
	local P = r.P
	local wet, anyWet = {}, false
	for i, p in ipairs(P) do
		wet[i] = heightPlain(p.X, p.Y) < WL - 0.5
		if wet[i] then anyWet = true end
	end
	r.wet = wet
	if anyWet then
		for i = 1, #P do if wet[i] then r.hs[i] = WL + BRIDGE_H end end
		for _ = 1, 8 do
			local n = {}
			for i = 1, #P do
				if wet[i] then
					n[i] = r.hs[i]
				else
					local s, c = 0, 0
					for k = math.max(1, i - 5), math.min(#P, i + 5) do
						s = s + r.hs[k]; c = c + 1
					end
					n[i] = s / c
				end
			end
			r.hs = n
		end
		for i = 1, #P do
			if r.pinW[i] and r.pinW[i] >= 0.999 then r.hs[i] = r.pinY[i] end
		end
	end
end

----------------------------------------------------------------
-- 4. STRASSEN- UND KREUZUNGSFELD
----------------------------------------------------------------
local fRoadD, fRoadY, fRoadH, fRoadP = {}, {}, {}, {}
local fJunD, fJunY, fJunPad = {}, {}, {}
do
	local function bake(x, z, y, half, paint)
		local cx = math.floor((x + HALF) / VOX) + 1
		local cz = math.floor((z + HALF) / VOX) + 1
		local R = half + 30
		local rc = math.ceil(R / VOX)
		local r2 = R * R
		for di = -rc, rc do
			local i = cx + di
			if i >= 1 and i <= NX then
				local px = -HALF + (i - 0.5) * VOX
				local dx = px - x
				local base = (i - 1) * NZ
				for dk = -rc, rc do
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
								fRoadH[id] = half
								fRoadP[id] = paint
							end
						end
					end
				end
			end
		end
	end
	for _, r in ipairs(NET) do
		for i = 1, #r.P - 1 do
			local a, b = r.P[i], r.P[i + 1]
			local steps = math.max(1, math.ceil((b - a).Magnitude / 3))
			for s = 0, steps - 1 do
				local t = s / steps
				bake(lerp(a.X, b.X, t), lerp(a.Y, b.Y, t), lerp(r.hs[i], r.hs[i + 1], t), r.half, r.paint)
			end
		end
		task.wait()
	end
	for _, j in ipairs(JUN) do
		local R = j.padR + 34
		local rc = math.ceil(R / VOX)
		local r2 = R * R
		local cx = math.floor((j.x + HALF) / VOX) + 1
		local cz = math.floor((j.z + HALF) / VOX) + 1
		for di = -rc, rc do
			local i = cx + di
			if i >= 1 and i <= NX then
				local px = -HALF + (i - 0.5) * VOX
				local dx = px - j.x
				local base = (i - 1) * NZ
				for dk = -rc, rc do
					local k = cz + dk
					if k >= 1 and k <= NZ then
						local pz = -HALF + (k - 0.5) * VOX
						local d2 = dx * dx + (pz - j.z) ^ 2
						if d2 <= r2 then
							local id = base + k
							local ov = fJunD[id]
							if ov == nil or d2 < ov then
								fJunD[id] = d2
								fJunY[id] = j.y
								fJunPad[id] = j.padR
							end
						end
					end
				end
			end
		end
	end
end
print("[v43] Strassenfeld gebacken")

-- Brueckenzone
local bridgeZone = {}
for _, r in ipairs(NET) do
	for i, p in ipairs(r.P) do
		if r.wet and r.wet[i] then
			local ci = math.floor((p.X + HALF) / VOX) + 1
			local ck = math.floor((p.Y + HALF) / VOX) + 1
			local rr = math.ceil((r.half + 10) / VOX)
			for di = -rr, rr do
				local ii = ci + di
				if ii >= 1 and ii <= NX then
					for dk = -rr, rr do
						local kk = ck + dk
						if kk >= 1 and kk <= NZ then
							local px = -HALF + (ii - 0.5) * VOX
							local pz = -HALF + (kk - 0.5) * VOX
							if (px - p.X) ^ 2 + (pz - p.Y) ^ 2 < (r.half + 10) ^ 2 then
								bridgeZone[IDX(ii, kk)] = true
							end
						end
					end
				end
			end
		end
	end
end

local GROUND_DROP = ROAD_EMBED - 0.15
local function terrainH(x, z)
	local i = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local k = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local id = IDX(i, k)
	local h = heightPlain(x, z)
	local d2 = fRoadD[id]
	if d2 and h >= WL - 1 then
		local d = math.sqrt(d2)
		local half = fRoadH[id] or 12
		if d < half + 22 then
			h = lerp(h, fRoadY[id] - GROUND_DROP, 1 - sstep(half + 3, half + 22, d))
		end
	end
	local jd = fJunD[id]
	if jd and h >= WL - 1 then
		local d = math.sqrt(jd)
		local pr = fJunPad[id] or 20
		if d < pr + 32 then
			h = lerp(h, fJunY[id] - GROUND_DROP, 1 - sstep(pr + 2, pr + 32, d))
		end
	end
	return h
end

----------------------------------------------------------------
-- 5. GITTER + MATERIAL + TERRAIN
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
		elseif d2 and d2 < (fRoadP[id] or 10) ^ 2 and not bridgeZone[id] then
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
print("[v43] Hoehen + Material fertig")

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
	print(("[v43] Terrain %d%%"):format(math.floor((ci + 1) / (NX / CH) * 100)))
end

----------------------------------------------------------------
-- 6. STIL
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
-- 7. PARTS: Fahrbahnen, Kreuzungspads, Markierungen, Autobahn, Bruecken
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
local function roadDistXZ(x, z)
	local ci = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local d2 = fRoadD[IDX(ci, ck)]
	if not d2 then return math.huge end
	return math.sqrt(d2)
end

local asphalt = Color3.fromRGB(64, 65, 68)
local roadFolder = Instance.new("Folder")
roadFolder.Name = "Strassen"
roadFolder.Parent = map

for _, r in ipairs(NET) do
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
				Vector3.new(r.half * 2, ROAD_TOP + ROAD_EMBED, len + 2),
				look, asphalt, E.Asphalt)
			road.Name = r.name
		end
	end
	task.wait()
end
print(("[v43] %d Fahrbahn-Teile"):format(partCount))

-- flache Kreuzungspads: decken die komplette Kreuzung ab
for _, j in ipairs(JUN) do
	part(roadFolder, Vector3.new(ROAD_TOP + ROAD_EMBED, j.padR * 2, j.padR * 2),
		CFrame.new(j.x, j.y + (ROAD_TOP - ROAD_EMBED) / 2 + 0.02, j.z) * CFrame.Angles(0, 0, math.pi / 2),
		asphalt, E.Asphalt, Enum.PartType.Cylinder, false).Name = "Kreuzung"
end

local function nearJunction(x, z, rad)
	local r2 = rad * rad
	for _, j in ipairs(JUN) do
		if (j.x - x) ^ 2 + (j.z - z) ^ 2 < r2 then return true end
	end
	return false
end

-- Mittelstreifen (nur Haupt-/Nebenstrassen, nicht innerorts)
for _, r in ipairs(NET) do
	if r.mark then
		local P, hs = r.P, r.hs
		local cum = { 0 }
		for i = 2, #P do cum[i] = cum[i - 1] + (P[i] - P[i - 1]).Magnitude end
		local total = cum[#cum]
		local d = 34
		while d < total - 14 do
			local i = 1
			while i < #cum and cum[i + 1] < d do i = i + 1 end
			local seg = math.max(0.001, cum[i + 1] - cum[i])
			local t = clamp((d - cum[i]) / seg, 0, 1)
			local p = P[i]:Lerp(P[i + 1], t)
			local y = lerp(hs[i], hs[i + 1], t)
			if not nearJunction(p.X, p.Y, 40) then
				local dir = P[i + 1] - P[i]
				part(roadFolder, Vector3.new(1.3, 0.18, r.dashLen),
					CFrame.lookAt(Vector3.new(p.X, y + ROAD_TOP + 0.12, p.Y),
						Vector3.new(p.X + dir.X, y + ROAD_TOP + 0.12, p.Y + dir.Y)),
					Color3.fromRGB(245, 235, 205), E.SmoothPlastic, nil, false).Name = "Markierung"
			end
			d = d + r.dash
		end
	end
end

-- Autobahn: Mittelleitplanke + Leitplanken
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
for _, r in ipairs(NET) do
	if r.auto then
		local P, hs = r.P, r.hs
		for i = 1, #P - 2, 2 do
			local a, b = P[i], P[i + 2]
			local ya, yb = hs[i], hs[i + 2]
			if not nearJunction((a.X + b.X) / 2, (a.Y + b.Y) / 2, 34) then
				beam(autoFolder, a, b, ya, yb, 0, 1.6, 1.1, Color3.fromRGB(190, 192, 196))
			end
			beam(autoFolder, a, b, ya, yb, -(r.half + 2.2), 0.9, 1.5, Color3.fromRGB(205, 208, 212))
			beam(autoFolder, a, b, ya, yb, (r.half + 2.2), 0.9, 1.5, Color3.fromRGB(205, 208, 212))
		end
		task.wait()
	end
end

-- Bruecken: Deck ausschliesslich ueber Wasser, Pfeiler nur im Wasser
local bridgeFolder = Instance.new("Folder")
bridgeFolder.Name = "Bruecken"
bridgeFolder.Parent = map
for _, r in ipairs(NET) do
	local P, hs = r.P, r.hs
	if r.wet then
		local any = false
		for i = 1, #P - 1 do
			if r.wet[i] or r.wet[i + 1] then
				any = true
				local a, b = P[i], P[i + 1]
				local len = (b - a).Magnitude
				local ya, yb = hs[i], hs[i + 1]
				local mid = (a + b) / 2
				local y = (ya + yb) / 2
				local look = CFrame.lookAt(Vector3.new(mid.X, y, mid.Y), Vector3.new(b.X, yb, b.Y))
				part(bridgeFolder, Vector3.new(r.half * 2 + 8, 3.2, len + 1.2),
					look * CFrame.new(0, ROAD_TOP - 1.6 - 0.03, 0),
					Color3.fromRGB(120, 120, 126), E.Concrete).Name = "Deck"
				for _, sgn in ipairs({ -1, 1 }) do
					part(bridgeFolder, Vector3.new(1.6, 0.6, len + 1.2),
						look * CFrame.new((r.half + 1.8) * sgn, ROAD_TOP + 0.25, 0),
						Color3.fromRGB(200, 200, 205), E.Concrete).Name = "Randstein"
					part(bridgeFolder, Vector3.new(1.0, 1.7, len + 1.2),
						look * CFrame.new((r.half + 3.2) * sgn, ROAD_TOP + 0.9, 0),
						Color3.fromRGB(210, 212, 216), E.Concrete).Name = "Gelaender"
				end
			end
		end
		if any then
			local d = 0
			for i = 1, #P - 1 do
				d = d + (P[i + 1] - P[i]).Magnitude
				if r.wet[i] and d > 48 then
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
	end
end
print(("[v43] Bruecken gebaut (%d Teile)"):format(partCount))
----------------------------------------------------------------
-- 8. DOERFER: Haeuser an Gassen, Kirche/Brunnen, Schilder
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

local function fountain(parent, x, z)
	local y = heightAt(x, z)
	part(parent, Vector3.new(1.2, 10, 10),
		CFrame.new(x, y + 0.6, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 150, 150), E.Concrete, Enum.PartType.Cylinder)
	part(parent, Vector3.new(0.25, 8.6, 8.6),
		CFrame.new(x, y + 1.15, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 140, 180), E.SmoothPlastic, Enum.PartType.Cylinder, false)
	part(parent, Vector3.new(4, 1.2, 1.2),
		CFrame.new(x, y + 2.8, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(145, 145, 145), E.Concrete, Enum.PartType.Cylinder)
end

local function signBoard(parent, x, z, fx, fz, w, h, text, bg, fg, postC)
	local y = heightAt(x, z)
	local cy = y + h / 2 + 2.6
	local cf = CFrame.lookAt(Vector3.new(x, cy, z), Vector3.new(fx, cy, fz))
	local board = part(parent, Vector3.new(w, h, 0.35), cf, bg, E.SmoothPlastic, nil, false)
	board.Name = "Schild"
	for _, s in ipairs({ -1, 1 }) do
		part(parent, Vector3.new(0.55, cy - y, 0.55),
			CFrame.new(x, y + (cy - y) / 2, z) * CFrame.new(cf:VectorToWorldSpace(Vector3.new((w / 2 - 1.2) * s, 0, 0))),
			postC or Color3.fromRGB(90, 90, 92), E.Metal, nil, false)
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 44
	sg.Parent = board
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = fg
	tl.TextScaled = true
	tl.TextWrapped = true
	tl.Font = Enum.Font.GothamBold
	tl.Parent = sg
	return board
end

local townFolder = Instance.new("Folder")
townFolder.Name = "Doerfer"
townFolder.Parent = map
local allPlaced = {}
local function farFrom(x, z, rad)
	for _, p in ipairs(allPlaced) do
		if (p.x - x) ^ 2 + (p.z - z) ^ 2 < rad * rad then return false end
	end
	return true
end

for _, t in ipairs(TOWNS) do
	local tf = Instance.new("Folder")
	tf.Name = t.name
	tf.Parent = townFolder
	local ci, M = nearestOn(t.road.P, t.cx, t.cz)
	local tx, tz = tangent(t.road.P, ci)
	local nx, nz = -tz, tx
	local sgn = (t.name == "Seeburg") and -1 or 1

	-- Kirche (grosse Orte) / Brunnen (alle)
	local cx, cz = M.X + nx * 88 * sgn, M.Y + nz * 88 * sgn
	if roadDistXZ(cx, cz) < 26 then
		sgn = -sgn
		cx, cz = M.X + nx * 88 * sgn, M.Y + nz * 88 * sgn
	end
	if t.size == "large" then
		local yaw = math.atan2(-nx * sgn, -nz * sgn)
		church(tf, cx, cz, yaw)
		allPlaced[#allPlaced + 1] = { x = cx, z = cz }
	else
		fountain(tf, cx, cz)
		allPlaced[#allPlaced + 1] = { x = cx, z = cz }
	end

	-- Haeuser an den Gassen
	local maxHouses = (t.size == "large") and 24 or ((t.size == "medium") and 14 or 6)
	local made = 0
	for _, r in ipairs(t.roads) do
		local P = r.P
		for i = 4, #P - 4, 7 do
			if made >= maxHouses then break end
			local p = P[i]
			local ux, uz = tangent(P, i)
			local px, pz = -uz, ux
			for _, side in ipairs({ -1, 1 }) do
				if made >= maxHouses then break end
				local hx = p.X + px * side * (r.half + 12)
				local hz = p.Y + pz * side * (r.half + 12)
				local ok = roadDistXZ(hx, hz) > r.half + 6
					and math.abs(heightAt(hx, hz) - t.h) < 3.5
					and lakeMask(hx, hz) < 0.05
					and farFrom(hx, hz, 38)
					and math.random() < 0.62
				if ok then
					local yaw = math.atan2(px * side, pz * side)
					chalet(tf, hx, hz, yaw, 12 + math.random(0, 4), 14 + math.random(0, 5))
					allPlaced[#allPlaced + 1] = { x = hx, z = hz }
					made = made + 1
				end
			end
		end
	end

	-- Ortsschilder an beiden Ortseingaengen
	local _, e1 = nearX(t.road.P, t.cx - t.L / 2)
	local _, e2 = nearX(t.road.P, t.cx + t.L / 2)
	for _, e in ipairs({ e1, e2 }) do
		local ei = nearestOn(t.road.P, e.X, e.Y)
		local etx, etz = tangent(t.road.P, ei)
		local enx, enz = -etz, etx
		local sx, sz = e.X + enx * 26, e.Y + enz * 26
		if roadDistXZ(sx, sz) < 17 then sx, sz = e.X - enx * 26, e.Y - enz * 26 end
		signBoard(tf, sx, sz, e.X, e.Y, 13, 3.6, t.name, Color3.fromRGB(20, 56, 112), Color3.fromRGB(255, 255, 255))
	end
	task.wait()
end
print(("[v43] %d Doerfer gebaut"):format(#TOWNS))

-- Wegweiser an den Hauptkreuzungen und Abzweigen
do
	local wp = Instance.new("Folder")
	wp.Name = "Wegweiser"
	wp.Parent = map
	local function postAtRoad(road, x, text)
		local ci, p = nearX(road.P, x)
		local tx, tz = tangent(road.P, ci)
		local nx, nz = -tz, tx
		local sx, sz = p.X + nx * 24, p.Y + nz * 24
		signBoard(wp, sx, sz, p.X, p.Y, 20, 3.0, text, Color3.fromRGB(250, 250, 246), Color3.fromRGB(20, 40, 80), Color3.fromRGB(70, 70, 72))
	end
	postAtRoad(TAL, -900, "◀ Westau · Seeburg      Mitteldorf ▶")
	postAtRoad(TAL, 250, "◀ Mitteldorf      Ostheim ▶")
	postAtRoad(TAL, -1750, "▼ See · Seeburg")
	postAtRoad(TAL, 1200, "▲ Burg")
	postAtRoad(TAL, -2380, "◀ Pass West · Autobahn")
	postAtRoad(TAL, 2380, "Pass Ost · Autobahn ▶")
	postAtRoad(NOR, -250, "▲ Hausberg")
end

----------------------------------------------------------------
-- 9. BURG, SEE-STEG, HAUSBERG-KREUZ
----------------------------------------------------------------
do
	local bf = Instance.new("Folder")
	bf.Name = "Burg"
	bf.Parent = map
	local y = heightAt(CASTLE.x, CASTLE.z)
	local base = CFrame.new(CASTLE.x, y, CASTLE.z) * CFrame.Angles(0, CASTLE.yaw, 0)
	local stone = Color3.fromRGB(126, 124, 120)
	local dark = Color3.fromRGB(92, 92, 96)
	local roof = Color3.fromRGB(110, 54, 48)
	part(bf, Vector3.new(36, 3.2, 36), base * CFrame.new(0, 1.6, 0), Color3.fromRGB(112, 110, 106), E.Concrete)
	part(bf, Vector3.new(16, 20, 16), base * CFrame.new(0, 3.2 + 10, 0), stone, E.Brick)
	part(bf, Vector3.new(4, 7, 0.8), base * CFrame.new(0, 3.2 + 3.5, 8.1), Color3.fromRGB(78, 52, 34), E.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(bf, Vector3.new(19, 7, 7), base * CFrame.new(sx * 12, 3.2 + 9.5, sz * 12),
				stone, E.Brick, Enum.PartType.Cylinder).CFrame = base * CFrame.new(sx * 12, 3.2 + 9.5, sz * 12) * CFrame.Angles(0, 0, math.pi / 2)
			part(bf, Vector3.new(3, 9, 9), base * CFrame.new(sx * 12, 3.2 + 20, sz * 12),
				roof, E.Slate, Enum.PartType.Cylinder).CFrame = base * CFrame.new(sx * 12, 3.2 + 20, sz * 12) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end
	part(bf, Vector3.new(25, 6, 1.6), base * CFrame.new(0, 3.2 + 3, 12), dark, E.Brick)
	part(bf, Vector3.new(25, 6, 1.6), base * CFrame.new(0, 3.2 + 3, -12), dark, E.Brick)
	part(bf, Vector3.new(1.6, 6, 25), base * CFrame.new(12, 3.2 + 3, 0), dark, E.Brick)
	part(bf, Vector3.new(1.6, 6, 25), base * CFrame.new(-12, 3.2 + 3, 0), dark, E.Brick)
	part(bf, Vector3.new(0.5, 16, 0.5), base * CFrame.new(0, 3.2 + 20 + 8, 0), Color3.fromRGB(60, 60, 62), E.Metal, nil, false)
	part(bf, Vector3.new(4.5, 2.6, 0.3), base * CFrame.new(2.3, 3.2 + 20 + 13, 0), Color3.fromRGB(170, 40, 40), E.Fabric, nil, false)
end

do
	local pf = Instance.new("Folder")
	pf.Name = "See-Steg"
	pf.Parent = map
	local y = WL + 2.0
	part(pf, Vector3.new(46, 0.7, 7), CFrame.new(-1450, y, 560), Color3.fromRGB(112, 82, 52), E.Wood)
	for i = 0, 2 do
		local x = -1432 - i * 16
		for _, sz in ipairs({ -1, 1 }) do
			local z = 560 + sz * 5.2
			local gy = heightAt(x, z)
			local h = y - gy
			if h > 1 then
				part(pf, Vector3.new(h, 1.0, 1.0),
					CFrame.new(x, gy + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(90, 64, 40), E.Wood, Enum.PartType.Cylinder, false)
			end
		end
	end
end

do
	local y = heightAt(0, -2050)
	local cf = CFrame.new(0, y, -2050)
	part(map, Vector3.new(0.9, 11, 0.9), cf * CFrame.new(0, 5.5, 0), Color3.fromRGB(60, 58, 54), E.Metal, nil, false)
	part(map, Vector3.new(5.5, 0.9, 0.9), cf * CFrame.new(0, 7.6, 0), Color3.fromRGB(60, 58, 54), E.Metal, nil, false)
end
----------------------------------------------------------------
-- 10. SPAWN + UEBERSICHTSTAFEL
----------------------------------------------------------------
do
	local t = TOWNS[1]
	local ci, M = nearestOn(t.road.P, t.cx, t.cz)
	local tx, tz = tangent(t.road.P, ci)
	local nx, nz = -tz, tx
	local bx, bz = M.X + nx * 80, M.Y + nz * 80
	local sx, sz = M.X + nx * 112, M.Y + nz * 112
	signBoard(map, bx, bz, sx, sz, 22, 13,
		"MITTELDORF\nDu bist hier\n\n◀ Westau · Seeburg\n▲ Nordegg · Bergheim\n▶ Ostheim\n▼ Suedhalde",
		Color3.fromRGB(18, 42, 78), Color3.fromRGB(255, 255, 255))
	local sp = Instance.new("SpawnLocation")
	sp.Anchored = true
	sp.Neutral = true
	sp.Size = Vector3.new(14, 1, 14)
	sp.Transparency = 1
	sp.CFrame = CFrame.lookAt(Vector3.new(sx, heightAt(sx, sz) + 1.6, sz), Vector3.new(bx, heightAt(sx, sz) + 1.6, bz))
	sp.Parent = map
	sp.Name = "Spawn"
end

----------------------------------------------------------------
-- 11. WALD
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
print("[v43] Baum-Vorlage: " .. (template and template:GetFullName() or "FEHLT (Ersatzbaum)"))

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
	local ps = allParts(holder)
	if #ps == 0 then holder:Destroy() return end
	for _, p in ipairs(ps) do
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

local TREE_COUNT = 4200
local placedTrees, attempts = 0, 0
while placedTrees < TREE_COUNT and attempts < TREE_COUNT * 22 do
	attempts = attempts + 1
	local x = (math.random() * 2 - 1) * (HALF - 80)
	local z = (math.random() * 2 - 1) * (HALF - 80)
	local ci = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local id = IDX(ci, ck)
	local h = H[ci][ck]
	local nearTown = false
	for _, t in ipairs(TOWNS) do
		if (t.cx - x) ^ 2 + (t.cz - z) ^ 2 < 190 * 190 then nearTown = true; break end
	end
	if (x - 1550) ^ 2 + (z + 620) ^ 2 < 95 * 95 then nearTown = true end
	local forest = nz(x / 380, z / 380, 60) + nz(x / 120, z / 120, 61) * 0.5
	local dr = fRoadD[id]
	local ok = (not nearTown) and forest > 0.10 and h > WL + 3 and h < 260
		and MAT[ci][ck] == E.Grass and not bridgeZone[id]
	if ok and dr and dr < (fRoadH[id] + 10) ^ 2 then ok = false end
	if ok then
		buildTree(x, z, h - 0.4, 0.85 + math.random() * 0.8, math.random() * 6.28)
		placedTrees = placedTrees + 1
	end
	if attempts % 400 == 0 then task.wait() end
end
print(("[v43] %d Baeume"):format(placedTrees))

----------------------------------------------------------------
-- 12. ATMOSPHAERE + ENDE
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

print(("[v43] FERTIG in %.0f s | %d Teile | %d Baeume | %d Doerfer | %d Strassen | %d Kreuzungen"):format(
	os.clock() - T0, partCount, placedTrees, #TOWNS, #NET, #JUN))
