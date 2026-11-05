--[[
	SCHWEIZER MAP GENERATOR - VERSION 44
	------------------------------------------------------------
	Karte 8000 x 8000. Dichtere, unregelmaessigere Welt.

	NEU IN v44:
	- Graphbasiertes Strassennetz: keine Sackgassen, keine Stichwege.
	- 5 Laengsachsen, Ringe, Querverbindungen, Hoefe-/Industrie-Loops.
	- 2 beleuchtete Tunnel durch den Bergring zur Autobahn (West/Ost).
	- Keine Burg mehr. Der Burgberg wird Aussichtshuegel mit Restaurant.
	- Keine Zylinder-Pads an Kreuzungen mehr, nur eckige Asphaltflaechen.
	- Kettenhaeuser an den Gitterstrassen, exakt auf Parzellen zentriert.
	- Groessere Low-Poly-Haeuser mit Fassaden, Balkonen, Laeden, Daechern.
	- Tankstellen, Raststaette, Bauernhoefe, Saegewerk, See-Resort, POIs.
	- Low-Poly-Tannen (keine beliebigen Baum-Templates mehr).
	- Autobahn mit unregelmaessigen Kurven, Galerie, Raststaette, Schildern.

	NUR EIN SEE, KEINE FLUESSE.
	See-Bruecke: Deck ausschliesslich ueber Wasser, Pfeiler nur im Wasser.

	KREUZUNGEN:
	- jede Kreuzung ist ein exakt gemeinsamer Knoten,
	- alle Strassen werden an diesem Knoten auf EINE Hoehe gepinnt,
	- das Terrain darunter wird flachgezogen,
	- kein Zylinder-Pad mehr, nur eckige Asphaltflaechen.

	BENUTZUNG: Roblox Studio, Command Bar, NICHT im Play-Modus.
	Dauer: ca. 15-25 Minuten.
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

print("[v44] Start...")
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

-- v44: keine offenen Passkorridore mehr. Die Tunnel werden spaeter
-- als Luftkoerper aus dem Berg geschnitten.
local PASSES = {}
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
	{ x = 1550, z = -620, rx = 190, rz = 190, h = 14 }, -- Aussichtshuegel (keine Burg)
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
		-- v44: Bergring beginnt frueher, damit die Tunnel echten Bergueberstand haben.
	local m = sstep(20, 260, dVal) * sstep(60, 220, dIn)
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

-- Autobahn: unregelmaessiger Ring mit unterschiedlichen Kurvenradien.
-- Bleibt innerhalb des Plateaus, damit das Terrain nicht neu gebaut werden muss.
local function autoPath()
	local ctrl = {
		V2(AHX, -1750), V2(AHX + 40, -1100), V2(AHX - 60, -500), V2(AHX, 0),
		V2(AHX - 70, 650), V2(AHX + 30, 1250), V2(AHX - 90, 1750),
		V2(3150, 2150), V2(2700, 2350), V2(2100, 2390), V2(1400, 2330),
		V2(700, 2390), V2(0, 2340), V2(-700, 2400), V2(-1400, 2330),
		V2(-2100, 2390), V2(-2650, 2300), V2(-3050, 2050), V2(-3300, 1650),
		V2(-AHX, 1100), V2(-AHX + 50, 500), V2(-AHX, 0), V2(-AHX - 30, -700),
		V2(-AHX + 40, -1300), V2(-3200, -1850), V2(-2800, -2200), V2(-2300, -2330),
		V2(-1700, -2390), V2(-1000, -2330), V2(-300, -2390), V2(400, -2330),
		V2(1100, -2390), V2(1800, -2330), V2(2500, -2380), V2(3000, -2150),
		V2(3250, -1900),
	}
	local P = catmull(ctrl, true, 9)
	P[#P + 1] = P[1]
	return P
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
local NMIT = addRoad("Nordmittelstrasse", "sec", {
	V2(-2250, -430), V2(-1500, -540), V2(-650, -430), V2(250, -520),
	V2(1150, -400), V2(2050, -500), V2(2250, -420),
})
local SMIT = addRoad("Suedmittelstrasse", "sec", {
	V2(-2450, 260), V2(-2100, 150), V2(-1750, 170), V2(-1400, 230),
	V2(-950, 360), V2(-550, 500), V2(450, 600), V2(1450, 520), V2(2250, 500),
})
local AUTO = addRaw("Autobahn", "auto", autoPath(), true)

-- 7 Orte: 2 gross, 3 mittel, 2 Weiler. Die Gitter sind jetzt geschlossene
-- Leitersysteme mit Ring, nicht mehr mit Stichwegen/Ueberstaenden.
local TOWNS = {
	{ name = "Mitteldorf", road = TAL, x = -550,  size = "large",  church = true,  flat = 340, L = 560, cross = { 0, 0.18, 0.38, 0.58, 0.78, 1.0 }, off = 215 },
	{ name = "Seeburg",    road = TAL, x = -1650, size = "large",  church = true,  flat = 330, L = 520, cross = { 0, 0.19, 0.40, 0.60, 0.81, 1.0 }, off = 205 },
	{ name = "Ostheim",    road = TAL, x = 1450,  size = "medium", church = false, flat = 245, L = 360, cross = { 0, 0.24, 0.50, 0.76, 1.0 },         off = 165 },
	{ name = "Nordegg",    road = NOR, x = 850,   size = "medium", church = false, flat = 240, L = 340, cross = { 0, 0.25, 0.52, 0.78, 1.0 },         off = 160 },
	{ name = "Suedhalde",  road = SUD, x = 700,   size = "medium", church = true,  flat = 240, L = 340, cross = { 0, 0.24, 0.51, 0.77, 1.0 },         off = 160 },
	{ name = "Westau",     road = TAL, x = -2350, size = "small",  church = false, flat = 155, L = 190, cross = { 0, 0.34, 0.67, 1.0 },           off = 105 },
	{ name = "Bergheim",   road = NOR, x = -1250, size = "small",  church = false, flat = 155, L = 190, cross = { 0, 0.34, 0.67, 1.0 },           off = 105 },
}
for _, t in ipairs(TOWNS) do
	local ci, p = nearX(t.road.P, t.x)
	t.ci = ci
	t.cx, t.cz = p.X, p.Y
	t.h = heightRaw(p.X, p.Y)
	t.roads = {}
end

local function heightPlain(x, z)
	local h = heightRaw(x, z)
	for _, t in ipairs(TOWNS) do
		local dx, dz = x - t.cx, z - t.cz
		local d = math.sqrt(dx * dx + dz * dz)
		if d < t.flat + 80 and lakeMask(x, z) < 0.05 then
			h = lerp(h, t.h, 1 - sstep(t.flat, t.flat + 80, d))
		end
	end
	return h
end

-- Geschlossenes Leitersystem pro Ort: zwei bis vier Parallelstrassen,
-- Querstrassen an beiden Enden verbunden. Keine Stichwege, keine Ueberstaende.
local function townGrid(t)
	local P = t.road.P
	local iA, iB = t.ci, t.ci
	local acc = 0
	while iA > 1 and acc < t.L / 2 do acc = acc + (P[iA] - P[iA - 1]).Magnitude; iA = iA - 1 end
	acc = 0
	while iB < #P and acc < t.L / 2 do acc = acc + (P[iB + 1] - P[iB]).Magnitude; iB = iB + 1 end
	local frames = {}
	for _, f in ipairs(t.cross) do
		local idx = clamp(math.floor(iA + (iB - iA) * f + 0.5), 1, #P)
		local M = P[idx]
		local tx, tz = tangent(P, idx)
		frames[#frames + 1] = { M = M, tx = tx, tz = tz, nx = -tz, nz = tx }
	end
	-- Bei kleinen Orten nur der Aussenring, bei mittleren/grossen zusaetzlich
	-- eine innere Parallelstrasse. So bleibt jeder Ort anders.
	local offsets = (t.size == "small") and { 1.0 } or { 0.55, 1.0 }
	for _, side in ipairs({ -1, 1 }) do
		for oi, fo in ipairs(offsets) do
			local pts = {}
			for _, fr in ipairs(frames) do
				local off = side * t.off * fo
				pts[#pts + 1] = V2(fr.M.X + fr.nx * off, fr.M.Y + fr.nz * off)
			end
			local nm = t.name .. " " .. (side < 0 and "Nord" or "Sued") .. " " .. oi
			t.roads[#t.roads + 1] = addRoad(nm, "quart", pts)
		end
	end
	-- Querstrassen verbinden alle Parallelstrassen und die Hauptstrasse.
	for i, fr in ipairs(frames) do
		local a = V2(fr.M.X + fr.nx * t.off, fr.M.Y + fr.nz * t.off)
		local b = V2(fr.M.X - fr.nx * t.off, fr.M.Y - fr.nz * t.off)
		t.roads[#t.roads + 1] = addRoad(t.name .. " Quer " .. i, "quart", { a, fr.M, b })
	end
	-- Eine schraege Gasse fuer groessere Orte. Sie endet an zwei Eckknoten.
	if t.size ~= "small" and #frames >= 4 then
		local a = V2(frames[1].M.X + frames[1].nx * t.off, frames[1].M.Y + frames[1].nz * t.off)
		local b = V2(frames[#frames].M.X - frames[#frames].nx * t.off, frames[#frames].M.Y - frames[#frames].nz * t.off)
		local mx, mz = (a.X + b.X) / 2, (a.Y + b.Y) / 2
		t.roads[#t.roads + 1] = addRoad(t.name .. " Diagonale", "quart",
			{ a, V2(mx + 24, mz - 18), b })
	end
end

-- Talring West/Ost: verbindet die Enden aller fuenf Laengsachsen.
do
	local pn, pnm, pt = NOR.P[1], NMIT.P[1], TAL.P[1]
	local psm, ps = SMIT.P[1], SUD.P[1]
	addRoad("Westring", "sec", {
		pn, V2(-2350, -830), pnm, V2(-2520, -150), pt,
		psm, V2(-2280, 700), ps,
	})
	local qn, qnm, qt = NOR.P[#NOR.P], NMIT.P[#NMIT.P], TAL.P[#TAL.P]
	local qsm, qs = SMIT.P[#SMIT.P], SUD.P[#SUD.P]
	addRoad("Ostring", "sec", {
		qn, V2(2260, -850), qnm, V2(2560, -430), qt,
		V2(2660, 230), qsm, V2(2410, 680), qs,
	})
end

-- 6 Querverbindungen, absichtlich ungleichmaessig und teilweise nur
-- zwischen zwei Achsen. Jede endet exakt auf einer bestehenden Strasse.
do
	local _, pn = nearX(NOR.P, -2050)
	local _, pt = nearX(TAL.P, -2050)
	addRoad("Quer West", "sec", { pn, V2(-2120, -560), pt })
end
do
	local _, pn = nearX(NOR.P, -950)
	local _, pnm = nearX(NMIT.P, -950)
	local _, pt = nearX(TAL.P, -950)
	local _, psm = nearX(SMIT.P, -950)
	local _, ps = nearX(SUD.P, -950)
	addRoad("Quer Seeburg", "sec", { pn, V2(-1010, -610), pnm, V2(-880, -240), pt, V2(-1010, 260), psm, V2(-900, 700), ps })
end
do
	local _, pn = nearX(NOR.P, -100)
	local _, pnm = nearX(NMIT.P, -100)
	local _, pt = nearX(TAL.P, -100)
	local _, psm = nearX(SMIT.P, -100)
	local _, ps = nearX(SUD.P, -100)
	addRoad("Quer Mitte", "sec", { pn, V2(-160, -600), pnm, V2(-40, -250), pt, V2(-150, 260), psm, V2(-40, 720), ps })
end
do
	local _, pn = nearX(NOR.P, 1050)
	local _, pnm = nearX(NMIT.P, 1050)
	local _, pt = nearX(TAL.P, 1050)
	local _, psm = nearX(SMIT.P, 1050)
	local _, ps = nearX(SUD.P, 1050)
	addRoad("Quer Ost", "sec", { pn, V2(1110, -610), pnm, V2(990, -250), pt, V2(1110, 260), psm, V2(990, 700), ps })
end
do
	local _, pn = nearX(NOR.P, 1900)
	local _, pnm = nearX(NMIT.P, 1900)
	local _, pt = nearX(TAL.P, 1900)
	local _, psm = nearX(SMIT.P, 1900)
	local _, ps = nearX(SUD.P, 1900)
	addRoad("Quer Ost 2", "sec", { pn, V2(1960, -610), pnm, V2(1840, -240), pt, V2(1960, 260), psm, V2(1840, 700), ps })
end
do
	local _, pt = nearX(TAL.P, 2250)
	local _, psm = nearX(SMIT.P, 2250)
	local _, ps = nearX(SUD.P, 2250)
	addRoad("Quer Suedost", "sec", { pt, V2(2320, 260), psm, V2(2250, 700), ps })
end

-- Diagonalen mit Endpunkten auf bestehenden Strassen.
do
	local _, pn = nearX(NOR.P, -1800)
	local _, pt = nearX(TAL.P, -1000)
	local _, ps = nearX(SUD.P, -300)
	addRoad("Diagonale West", "sec", { pn, V2(-1350, -550), pt, V2(-650, 450), ps })
end
do
	local _, pn = nearX(NMIT.P, 300)
	local _, pt = nearX(TAL.P, 900)
	local _, ps = nearX(SMIT.P, 1500)
	addRoad("Diagonale Ost", "sec", { pn, V2(620, -300), pt, V2(1160, 320), ps })
end

-- Seestrasse mit Bruecke ueber den See.
do
	local _, pt = nearX(TAL.P, -1750)
	local _, ps = nearX(SUD.P, -1700)
	addRoad("Seestrasse", "sec", { pt, V2(-1960, 300), V2(-2030, 600), V2(-1880, 900), ps })
end

-- Seeuferloop oestlich des Sees: kein Weg mehr in eine Sackgasse.
do
	local _, pt = nearX(TAL.P, -1750)
	local _, ps = nearX(SUD.P, -1500)
	addRoad("Seeuferloop", "sec", { pt, V2(-1450, 220), V2(-1400, 720), V2(-1420, 980), ps })
end

-- Hof- und Industrie-Loops: beide Enden haengen am Strassennetz.
do
	local _, pa = nearX(SUD.P, -900)
	local _, pb = nearX(SUD.P, -350)
	addRoad("Hofloop Sued", "quart", { pa, V2(-1080, 1330), V2(-650, 1420), V2(-280, 1190), pb })
end
do
	local _, pa = nearX(NOR.P, -350)
	local _, pb = nearX(NOR.P, 250)
	addRoad("Hofloop Nord", "quart", { pa, V2(-470, -1320), V2(-50, -1440), V2(260, -1180), pb })
end
do
	local _, pa = nearX(TAL.P, 1800)
	local _, pb = nearX(TAL.P, 2200)
	addRoad("Industrieloop", "sec", { pa, V2(2040, 340), V2(2290, 220), V2(2330, -170), pb })
end
do
	local _, pa = nearX(TAL.P, 1200)
	local _, pb = nearX(TAL.P, 1800)
	addRoad("Aussichtsloop", "sec", { pa, V2(1320, -250), V2(1550, -620), V2(1750, -350), pb })
end

-- Raststaetten-Loop an der Autobahn (zwei Anschluesse, keine Sackgasse).
do
	local _, a1 = nearestOn(AUTO.P, AHX, 1500)
	local _, a2 = nearestOn(AUTO.P, AHX, 1900)
	addRoad("Raststaettenzufahrt", "sec", { a1, V2(3150, 1500), V2(3080, 1600), V2(3080, 1800), V2(3150, 1900), a2 })
end

-- 2 Tunnel zur Autobahn. Die alten Passstrassen entfallen komplett.
local _, twValley = nearX(TAL.P, -2450)
local _, twAuto = nearestOn(AUTO.P, -AHX, 600)
local TUNW = addRoad("Tunnel West", "sec", {
	twValley, V2(-2650, 280), V2(-2900, 480), V2(-3150, 600), twAuto,
})
TUNW.tunnel = true
local _, teValley = nearX(TAL.P, 2450)
local _, teAuto = nearestOn(AUTO.P, AHX, -600)
local TUNE = addRoad("Tunnel Ost", "sec", {
	teValley, V2(2650, -360), V2(2900, -560), V2(3150, -620), teAuto,
})
TUNE.tunnel = true

for _, t in ipairs(TOWNS) do townGrid(t) end
print(("[v44] %d Strassen definiert"):format(#NET))
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
print(("[v44] Kreuzungen eingesetzt, %d Strassen"):format(#NET))

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
print(("[v44] %d Kreuzungen"):format(#JUN))

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

-- v44: Tunnel steigen gleichmaessig vom Tal auf das Autobahnplateau.
-- Sie werden nicht vom Terrain geformt; der Berg bleibt oben geschlossen.
for _, r in ipairs(NET) do
	if r.tunnel then
		local total = 0
		for i = 1, #r.P - 1 do total = total + (r.P[i + 1] - r.P[i]).Magnitude end
		local d = 0
		for i, p in ipairs(r.P) do
			if i > 1 then d = d + (p - r.P[i - 1]).Magnitude end
			local f = clamp(d / math.max(total, 0.001), 0, 1)
			r.hs[i] = lerp(PLAIN + 1, PLATEAU, sstep(0, 1, f))
		end
		-- An den beiden Anschluessen exakt auf das Strassennetz einrasten.
		r.hs[1] = heightPlain(r.P[1].X, r.P[1].Y)
		r.hs[#r.P] = heightPlain(r.P[#r.P].X, r.P[#r.P].Y)
	end
end

-- 3f. Graphpruefung: Knoten, Kanten, Zusammenhang, Sackgassen.
-- Das ist die Grundlage fuer die spaetere Verkehrs-KI.
do
	local adj, edgeCount = {}, 0
	local function nk(p) return string.format("%.1f:%.1f", p.X, p.Y) end
	local function node(k) if not adj[k] then adj[k] = {} end end
	for _, r in ipairs(NET) do
		for i = 1, #r.P do node(nk(r.P[i])) end
		for i = 1, #r.P - 1 do
			local ka, kb = nk(r.P[i]), nk(r.P[i + 1])
			if ka ~= kb then
				adj[ka][#adj[ka] + 1] = kb
				adj[kb][#adj[kb] + 1] = ka
				edgeCount = edgeCount + 1
			end
		end
	end
	local dead, nodes = {}, 0
	for k, t in pairs(adj) do
		nodes = nodes + 1
		if #t == 1 then dead[#dead + 1] = k end
	end
	local seen, comps = {}, 0
	for k in pairs(adj) do
		if not seen[k] then
			comps = comps + 1
			local q = { k }; seen[k] = true
			local qi = 1
			while qi <= #q do
				local a = q[qi]; qi = qi + 1
				for _, b in ipairs(adj[a]) do
					if not seen[b] then seen[b] = true; q[#q + 1] = b end
				end
			end
		end
	end
	print(("[v44] Graph: %d Knoten, %d Kanten, %d Komponenten, %d Sackgassen"):format(nodes, edgeCount, comps, #dead))
	if #dead > 0 then
		local list = {}
		for i = 1, math.min(#dead, 12) do list[#list + 1] = dead[i] end
		print("[v44] Sackgassen: " .. table.concat(list, " | "))
	end
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
		local P = r.P
		for i = 1, #P - 1 do
			local a, b = P[i], P[i + 1]
			local ya, yb = r.hs[i], r.hs[i + 1]
			local midX, midZ = (a.X + b.X) / 2, (a.Y + b.Y) / 2
			-- Tunnel: nur den offenen Zulauf ins Terrain backen. Im Berg
			-- bleibt der Berg stehen; dort wird der Luftkoerper ausgespart.
			local bakeHere = (not r.tunnel) or (heightPlain(midX, midZ) <= (ya + yb) / 2 + 5)
			if bakeHere then
				local steps = math.max(1, math.ceil((b - a).Magnitude / 3))
				for s = 0, steps - 1 do
					local t = s / steps
					bake(lerp(a.X, b.X, t), lerp(a.Y, b.Y, t), lerp(ya, yb, t), r.half, r.paint)
				end
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
print("[v44] Strassenfeld gebacken")

-- v44: Tunnel-Luftkoerper. Wird beim Terrain-Schreiben ausgespart.
local fTunD, fTunY, fTunH = {}, {}, {}
for _, r in ipairs(NET) do
	if r.tunnel then
		for i = 1, #r.P - 1 do
			local a, b = r.P[i], r.P[i + 1]
			local steps = math.max(1, math.ceil((b - a).Magnitude / 3))
			for s = 0, steps - 1 do
				local t = s / steps
				local x, z = lerp(a.X, b.X, t), lerp(a.Y, b.Y, t)
				local y = lerp(r.hs[i], r.hs[i + 1], t)
				local carveHere = heightPlain(x, z) > y + 5
				local R = r.half + 12
				local rc = math.ceil(R / VOX)
				local cx = math.floor((x + HALF) / VOX) + 1
				local cz = math.floor((z + HALF) / VOX) + 1
				local r2 = R * R
				for di = -rc, rc do
					local ii = cx + di
					if ii >= 1 and ii <= NX then
						local px = -HALF + (ii - 0.5) * VOX
						local dx = px - x
						local base = (ii - 1) * NZ
						for dk = -rc, rc do
							local kk = cz + dk
							if kk >= 1 and kk <= NZ then
								local pz = -HALF + (kk - 0.5) * VOX
								local d2 = dx * dx + (pz - z) ^ 2
								if carveHere and d2 <= r2 then
									local id = base + kk
									local ov = fTunD[id]
									if ov == nil or d2 < ov then
										fTunD[id] = d2
										fTunY[id] = y
										fTunH[id] = r.half
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

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
print("[v44] Hoehen + Material fertig")

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
				local id = IDX(i, k)
				local td = fTunD[id]
				local tcarve = td and math.sqrt(td) < (fTunH[id] or 12) + 9
				local ty = fTunY[id] or 0
				for b = 1, full do
					local wy = BASEY + (b - 0.5) * VOX
					if tcarve and wy > ty - 2 and wy < ty + 16 then
						ma[b][zc] = AIR
						oa[b][zc] = 0
					else
						ma[b][zc] = (top - b < 2) and surf or deep
						oa[b][zc] = 1
					end
				end
				local nextFree = full + 1
				local topY = BASEY + (full + 0.5) * VOX
				if frac > 0.02 and full + 1 <= localNY and not (tcarve and topY > ty - 2 and topY < ty + 16) then
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
	print(("[v44] Terrain %d%%"):format(math.floor((ci + 1) / (NX / CH) * 100)))
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
print(("[v44] %d Fahrbahn-Teile"):format(partCount))

-- v44: keine Zylinder mehr an Kreuzungen. Eine flache, eckige Asphaltflaeche
-- liegt knapp unter der Fahrbahn und deckt nur die Nahtstellen ab.
for _, j in ipairs(JUN) do
	part(roadFolder, Vector3.new(j.padR * 2.05, 0.22, j.padR * 2.05),
		CFrame.new(j.x, j.y + ROAD_TOP - 0.13, j.z),
		asphalt, E.Asphalt, nil, false).Name = "Kreuzung"
end

-- v44: Tunnel-Auskleidung, Portale und Beleuchtung.
-- Der Berg bleibt oben stehen; nur der Luftkoerper wurde ausgespart.
local tunnelFolder = Instance.new("Folder")
tunnelFolder.Name = "Tunnel"
tunnelFolder.Parent = map
local lightC = Color3.fromRGB(255, 242, 214)
for _, r in ipairs(NET) do
	if r.tunnel then
		local P, hs = r.P, r.hs
		local inside = {}
		for i, p in ipairs(P) do
			inside[i] = heightAt(p.X, p.Y) > hs[i] + 5
		end
		local i0, i1 = nil, nil
		for i = 1, #P do
			if inside[i] then if not i0 then i0 = i end; i1 = i end
		end
		if i0 and i1 and i1 > i0 + 1 then
			local lightDist = 0
			for i = i0, i1 - 1 do
				if inside[i] and inside[i + 1] then
					local a, b = P[i], P[i + 1]
					local ya, yb = hs[i], hs[i + 1]
					local len = (b - a).Magnitude
					if len > 0.05 then
						local mid = (a + b) / 2
						local look = CFrame.lookAt(
							Vector3.new(mid.X, (ya + yb) / 2, mid.Y),
							Vector3.new(b.X, yb, b.Y))
						local half = r.half
						local wallX = half + 3.2
						local wallH = 14.5
						local ceilY = 14.7
						for _, sgn in ipairs({ -1, 1 }) do
							part(tunnelFolder, Vector3.new(0.8, wallH, len + 0.5),
								look * CFrame.new(wallX * sgn, wallH / 2, 0),
								Color3.fromRGB(168, 168, 164), E.Concrete).Name = "Tunnelwand"
							part(tunnelFolder, Vector3.new(3.0, 0.55, len + 0.5),
								look * CFrame.new((half + 1.5) * sgn, 0.55, 0),
								Color3.fromRGB(190, 188, 180), E.Concrete, nil, false).Name = "Tunnelbord"
						end
						part(tunnelFolder, Vector3.new((wallX + 0.4) * 2, 0.7, len + 0.5),
							look * CFrame.new(0, ceilY, 0),
							Color3.fromRGB(158, 158, 154), E.Concrete).Name = "Tunneldecke"
						part(tunnelFolder, Vector3.new(1.5, 0.22, len + 0.5),
							look * CFrame.new(0, ceilY - 0.55, 0),
							lightC, E.Neon, nil, false).Name = "Tunnellicht"
						-- Reflektoren an den Waenden
						for _, sgn in ipairs({ -1, 1 }) do
							part(tunnelFolder, Vector3.new(0.22, 0.8, 0.5),
								look * CFrame.new((half + 2.75) * sgn, 2.3, 0),
								Color3.fromRGB(255, 210, 70), E.Neon, nil, false).Name = "Reflektor"
						end
						lightDist = lightDist + len
						if lightDist > 62 then
							lightDist = 0
							local lamp = part(tunnelFolder, Vector3.new(0.9, 0.2, 2.4),
								look * CFrame.new(0, ceilY - 0.65, 0),
								lightC, E.Neon, nil, false)
							lamp.Name = "TunnelLampe"
							local pl = Instance.new("PointLight")
							pl.Color = lightC
							pl.Range = 44
							pl.Brightness = 1.45
							pl.Shadows = false
							pl.Parent = lamp
						end
					end
				end
			end
			-- Portale an beiden Enden
			for _, ii in ipairs({ i0, i1 }) do
				local p = P[ii]
				local nb = P[math.min(#P, ii + 1)]
				if ii == i1 then nb = P[math.max(1, ii - 1)] end
				local y = hs[ii]
				local nbY = hs[(ii == i1) and math.max(1, ii - 1) or math.min(#P, ii + 1)] or y
				local cf = CFrame.lookAt(Vector3.new(p.X, y, p.Y), Vector3.new(nb.X, nbY, nb.Y))
				local half = r.half
				part(tunnelFolder, Vector3.new(2.4, 19, 2.4),
					cf * CFrame.new(-(half + 4.5), 9.5, 0),
					Color3.fromRGB(145, 145, 142), E.Concrete).Name = "Portalpfosten"
				part(tunnelFolder, Vector3.new(2.4, 19, 2.4),
					cf * CFrame.new((half + 4.5), 9.5, 0),
					Color3.fromRGB(145, 145, 142), E.Concrete).Name = "Portalpfosten"
				part(tunnelFolder, Vector3.new((half + 5.7) * 2, 2.5, 2.4),
					cf * CFrame.new(0, 18.2, 0),
					Color3.fromRGB(132, 132, 130), E.Concrete).Name = "Portalsturz"
				local board = part(tunnelFolder, Vector3.new(12, 2.2, 0.35),
					cf * CFrame.new(0, 16.1, 0.1), Color3.fromRGB(24, 40, 58), E.SmoothPlastic, nil, false)
				board.Name = "Tunnelschild"
				for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
					local sg = Instance.new("SurfaceGui")
					sg.Face = face
					sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
					sg.PixelsPerStud = 50
					sg.Parent = board
					local tl = Instance.new("TextLabel")
					tl.Size = UDim2.fromScale(1, 1)
					tl.BackgroundTransparency = 1
					tl.Text = (r.name == "Tunnel West") and "TUNNEL WEST" or "TUNNEL OST"
					tl.TextColor3 = Color3.fromRGB(255, 255, 255)
					tl.TextScaled = true
					tl.Font = Enum.Font.GothamBold
					tl.Parent = sg
				end
			end
		end
	end
end
print(("[v44] Tunnel gebaut (%d Teile)"):format(partCount))

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

-- v44: Autobahn-Variation: Notbuchten, Schilderbruecken, Laermschutz,
-- kurze Galerie. So ist der Ring kein gleichfoermiger Asphaltstreifen.
do
	local asphaltA = Color3.fromRGB(64, 65, 68)
	local function autoBoard(parent, cf, w, h, text, bg, fg)
		local board = part(parent, Vector3.new(w, h, 0.35), cf, bg, E.SmoothPlastic, nil, false)
		board.Name = "Autobahnschild"
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 38
			sg.Parent = board
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.Text = text
			tl.TextColor3 = fg
			tl.TextScaled = true
			tl.Font = Enum.Font.GothamBold
			tl.Parent = sg
		end
	end
	local nA = #AUTO.P
	local function autoSample(f)
		local i = clamp(math.floor(f * (nA - 1)) + 1, 2, nA - 1)
		local p = AUTO.P[i]
		local q, r = AUTO.P[i + 1], AUTO.P[i - 1]
		local tx, tz = q.X - r.X, q.Y - r.Y
		local L = math.sqrt(tx * tx + tz * tz)
		if L < 0.001 then tx, tz, L = 0, 1, 1 end
		return p, tx / L, tz / L, AUTO.hs[i]
	end
	-- Notbuchten, abwechselnd links/rechts.
	local bays = { { 0.12, 1 }, { 0.34, -1 }, { 0.70, 1 }, { 0.82, -1 } }
	for _, b in ipairs(bays) do
		local p, tx, tz, y = autoSample(b[1])
		local cf = CFrame.lookAt(Vector3.new(p.X, y + ROAD_TOP - 0.12, p.Y),
			Vector3.new(p.X + tx, y + ROAD_TOP - 0.12, p.Y + tz))
		local side = b[2]
		part(autoFolder, Vector3.new(11, 0.3, 30), cf * CFrame.new(side * (AUTO.half + 4.8), 0, 0),
			asphaltA, E.Asphalt, nil, false).Name = "Notbucht"
		part(autoFolder, Vector3.new(0.3, 0.32, 28), cf * CFrame.new(side * (AUTO.half + 10.1), 0, 0),
			Color3.fromRGB(235, 232, 210), E.SmoothPlastic, nil, false).Name = "Notbuchtmarkierung"
		part(autoFolder, Vector3.new(0.6, 5.0, 0.6), cf * CFrame.new(side * (AUTO.half + 12.0), 2.5, 0),
			Color3.fromRGB(210, 176, 60), E.Metal, nil, false).Name = "Notrufpfosten"
		local bcf = cf * CFrame.new(side * (AUTO.half + 12.0), 4.6, 0)
		autoBoard(autoFolder, bcf, 2.2, 1.4, "SOS", Color3.fromRGB(245, 238, 170), Color3.fromRGB(34, 62, 42))
	end
	-- Schilderbruecken ueber der Fahrbahn.
	local gantries = { { 0.21, "A1  NORD" }, { 0.49, "A1  MITTE" }, { 0.77, "A1  SUED" } }
	for _, g in ipairs(gantries) do
		local p, tx, tz, y = autoSample(g[1])
		local cf = CFrame.lookAt(Vector3.new(p.X, y + ROAD_TOP, p.Y),
			Vector3.new(p.X + tx, y + ROAD_TOP, p.Y + tz))
		for _, s in ipairs({ -1, 1 }) do
			part(autoFolder, Vector3.new(1.3, 9.2, 1.3),
				cf * CFrame.new(s * (AUTO.half + 5.0), 4.6, 0),
				Color3.fromRGB(120, 124, 128), E.Metal).Name = "Schilderbrueckenpfosten"
		end
		part(autoFolder, Vector3.new((AUTO.half + 5.5) * 2, 1.2, 1.4),
			cf * CFrame.new(0, 9.0, 0), Color3.fromRGB(132, 136, 140), E.Metal).Name = "Schilderbruecke"
		local bcf = cf * CFrame.new(0, 6.4, 0.3)
		autoBoard(autoFolder, bcf, 26, 3.6, g[2], Color3.fromRGB(20, 58, 96), Color3.fromRGB(255, 248, 220))
	end
	-- Laermschutzwand an einem laengeren Abschnitt.
	for i = math.floor(nA * 0.30), math.floor(nA * 0.38), 3 do
		if i + 3 <= nA then
			local a, b = AUTO.P[i], AUTO.P[i + 3]
			local ya, yb = AUTO.hs[i], AUTO.hs[i + 3]
			beam(autoFolder, a, b, ya, yb, AUTO.half + 4.4, 0.55, 5.2, Color3.fromRGB(194, 197, 200))
		end
	end
	-- Kurze Galerie: Dach auf Stuetzen, kein geschlossener Tunnel.
	for i = math.floor(nA * 0.84), math.floor(nA * 0.91), 2 do
		if i + 2 <= nA then
			local a, b = AUTO.P[i], AUTO.P[i + 2]
			local ya, yb = AUTO.hs[i], AUTO.hs[i + 2]
			local len = (b - a).Magnitude
			local mid = (a + b) / 2
			local yRoof = (ya + yb) / 2 + ROAD_TOP + 9.2
			local look = CFrame.lookAt(Vector3.new(mid.X, yRoof, mid.Y),
				Vector3.new(b.X, yb + ROAD_TOP + 9.2, b.Y))
			part(autoFolder, Vector3.new((AUTO.half + 7.0) * 2, 0.8, len + 1.0),
				look, Color3.fromRGB(120, 122, 126), E.Concrete).Name = "Galeriedach"
			for _, s in ipairs({ -1, 1 }) do
				part(autoFolder, Vector3.new(1.5, 9.0, 1.5),
					look * CFrame.new(s * (AUTO.half + 5.5), -4.6, 0),
					Color3.fromRGB(142, 144, 148), E.Concrete).Name = "Galeriestuetze"
			end
		end
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
print(("[v44] Bruecken gebaut (%d Teile)"):format(partCount))
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

local function faceSign(parent, cf, w, h, text, bg, fg)
	local board = part(parent, Vector3.new(w, h, 0.3), cf, bg, E.SmoothPlastic, nil, false)
	board.Name = "Fassadenschild"
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 46
	sg.Parent = board
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = fg or Color3.fromRGB(255, 255, 255)
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.Parent = sg
	return board
end

local function houseWindow(parent, base, lx, ly, lz, w, h, frameC, shutterC, flowers)
	part(parent, Vector3.new(w + 0.8, h + 0.8, 0.22),
		base * CFrame.new(lx, ly, lz), frameC, E.SmoothPlastic, nil, false).Name = "Fensterrahmen"
	part(parent, Vector3.new(w, h, 0.18),
		base * CFrame.new(lx, ly, lz + 0.14), Color3.fromRGB(135, 185, 210), E.Glass, nil, false).Name = "Fenster"
	part(parent, Vector3.new(0.15, h, 0.2),
		base * CFrame.new(lx, ly, lz + 0.24), frameC, E.SmoothPlastic, nil, false)
	part(parent, Vector3.new(w, 0.15, 0.2),
		base * CFrame.new(lx, ly, lz + 0.24), frameC, E.SmoothPlastic, nil, false)
	if shutterC then
		for _, s in ipairs({ -1, 1 }) do
			part(parent, Vector3.new(w * 0.36, h, 0.18),
				base * CFrame.new(lx + s * (w * 0.72), ly, lz + 0.05),
				shutterC, E.Wood, nil, false).Name = "Fensterladen"
		end
	end
	if flowers then
		part(parent, Vector3.new(w * 0.9, 0.55, 0.7),
			base * CFrame.new(lx, ly - h / 2 - 0.45, lz + 0.35),
			Color3.fromRGB(92, 62, 42), E.Wood, nil, false).Name = "Blumenkasten"
		for i = -2, 2 do
			part(parent, Vector3.new(0.35, 0.3, 0.35),
				base * CFrame.new(lx + i * w * 0.14, ly - h / 2 - 0.15, lz + 0.55),
				(i % 2 == 0) and Color3.fromRGB(210, 70, 70) or Color3.fromRGB(235, 150, 190),
				E.SmoothPlastic, nil, false).Name = "Blume"
		end
	end
end

local function houseDoor(parent, base, lx, ly, lz, doorC, awningC)
	part(parent, Vector3.new(4.2, 5.8, 0.24),
		base * CFrame.new(lx, ly + 2.9, lz), Color3.fromRGB(242, 238, 226), E.SmoothPlastic, nil, false).Name = "Tuerrahmen"
	part(parent, Vector3.new(3.2, 4.9, 0.28),
		base * CFrame.new(lx, ly + 2.45, lz + 0.16), doorC, E.Wood, nil, false).Name = "Tuer"
	part(parent, Vector3.new(0.32, 0.32, 0.35),
		base * CFrame.new(lx + 1.1, ly + 2.2, lz + 0.35), Color3.fromRGB(220, 190, 90), E.Metal, nil, false).Name = "Klinke"
	part(parent, Vector3.new(4.6, 0.32, 1.8),
		base * CFrame.new(lx, ly + 0.16, lz + 0.95), Color3.fromRGB(170, 168, 160), E.Concrete, nil, false).Name = "Tuerstufe"
	if awningC then
		part(parent, Vector3.new(5.2, 0.28, 2.1),
			base * CFrame.new(lx, ly + 5.35, lz + 1.0), awningC, E.Fabric, nil, false).Name = "Vordach"
	end
end

local function balcony(parent, base, lx, ly, lz, w, woodC)
	part(parent, Vector3.new(w, 0.36, 2.2),
		base * CFrame.new(lx, ly, lz + 1.0), Color3.fromRGB(120, 88, 58), E.Wood, nil, false).Name = "Balkon"
	for i = -3, 3 do
		part(parent, Vector3.new(0.18, 1.0, 0.18),
			base * CFrame.new(lx + i * w / 7, ly + 0.65, lz + 1.95), woodC, E.Wood, nil, false)
	end
	part(parent, Vector3.new(w, 0.18, 0.18),
		base * CFrame.new(lx, ly + 1.15, lz + 1.95), woodC, E.Wood, nil, false).Name = "Balkongelaender"
	for _, s in ipairs({ -1, 1 }) do
		part(parent, Vector3.new(0.18, 1.0, 2.0),
			base * CFrame.new(lx + s * w / 2, ly + 0.65, lz + 1.0), woodC, E.Wood, nil, false)
	end
end

local function chimney(parent, base, lx, ly, lz, c)
	part(parent, Vector3.new(1.8, 5.0, 1.8), base * CFrame.new(lx, ly + 2.5, lz), c, E.Brick).Name = "Kamin"
	part(parent, Vector3.new(2.4, 0.5, 2.4), base * CFrame.new(lx, ly + 5.1, lz), Color3.fromRGB(90, 86, 82), E.Concrete, nil, false).Name = "Kaminabdeckung"
end

local function roofDormer(parent, base, x, y, z, w, roofC, wallC)
	part(parent, Vector3.new(w, 3.2, 3.0), base * CFrame.new(x, y + 1.4, z), wallC, E.Wood).Name = "Dachgaube"
	part(parent, Vector3.new(w + 1.0, 0.5, 3.8), base * CFrame.new(x, y + 3.1, z), roofC, E.Wood).Name = "Gaubendach"
	part(parent, Vector3.new(w * 0.55, 1.3, 0.2), base * CFrame.new(x, y + 1.5, z + 1.55),
		Color3.fromRGB(135, 185, 210), E.Glass, nil, false).Name = "Gaubenfenster"
end

local STYLE = {
	Mitteldorf = { wall = { Color3.fromRGB(238, 224, 190), Color3.fromRGB(224, 206, 170), Color3.fromRGB(246, 238, 218) }, roof = { Color3.fromRGB(146, 68, 54), Color3.fromRGB(112, 64, 48) }, trim = Color3.fromRGB(250, 246, 232), shutter = Color3.fromRGB(72, 92, 74) },
	Seeburg = { wall = { Color3.fromRGB(224, 228, 210), Color3.fromRGB(226, 204, 172), Color3.fromRGB(204, 218, 228) }, roof = { Color3.fromRGB(130, 62, 54), Color3.fromRGB(98, 68, 58) }, trim = Color3.fromRGB(252, 250, 244), shutter = Color3.fromRGB(66, 104, 116) },
	Ostheim = { wall = { Color3.fromRGB(202, 186, 164), Color3.fromRGB(216, 202, 182), Color3.fromRGB(188, 174, 158) }, roof = { Color3.fromRGB(92, 74, 66), Color3.fromRGB(116, 76, 62) }, trim = Color3.fromRGB(232, 228, 218), shutter = Color3.fromRGB(86, 72, 62) },
	Nordegg = { wall = { Color3.fromRGB(142, 98, 62), Color3.fromRGB(166, 118, 76), Color3.fromRGB(230, 216, 190) }, roof = { Color3.fromRGB(78, 58, 48), Color3.fromRGB(104, 64, 50) }, trim = Color3.fromRGB(238, 230, 214), shutter = Color3.fromRGB(60, 72, 54) },
	Suedhalde = { wall = { Color3.fromRGB(240, 226, 198), Color3.fromRGB(222, 208, 184), Color3.fromRGB(244, 236, 220) }, roof = { Color3.fromRGB(154, 76, 58), Color3.fromRGB(120, 70, 54) }, trim = Color3.fromRGB(250, 246, 236), shutter = Color3.fromRGB(92, 82, 70) },
	Westau = { wall = { Color3.fromRGB(174, 136, 94), Color3.fromRGB(212, 196, 168), Color3.fromRGB(146, 108, 74) }, roof = { Color3.fromRGB(86, 64, 52), Color3.fromRGB(112, 72, 56) }, trim = Color3.fromRGB(236, 228, 212), shutter = Color3.fromRGB(70, 78, 58) },
	Bergheim = { wall = { Color3.fromRGB(150, 108, 72), Color3.fromRGB(184, 150, 112), Color3.fromRGB(226, 212, 188) }, roof = { Color3.fromRGB(76, 60, 52), Color3.fromRGB(100, 66, 54) }, trim = Color3.fromRGB(242, 236, 222), shutter = Color3.fromRGB(58, 70, 54) },
}
local function pick(t) return t[math.random(1, #t)] end

local function rowHouse(parent, x, z, yaw, w, d, style, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = "Kettenhaus"
	m.Parent = parent
	local floors = opts.floors or (2 + ((math.random() < 0.34) and 1 or 0))
	local wallH = floors * 3.2 + 0.5
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.35, z) * CFrame.Angles(0, yaw, 0)
	local wallC = pick(style.wall)
	local roofC = pick(style.roof)
	local trim = style.trim
	local shutterC = style.shutter
	part(m, Vector3.new(w + 0.8, 1.4, d + 0.8), base * CFrame.new(0, 0.7, 0),
		Color3.fromRGB(150, 148, 142), E.Concrete).Name = "Sockel"
	part(m, Vector3.new(w, wallH, d), base * CFrame.new(0, 1.4 + wallH / 2, 0),
		wallC, E.Wood).Name = "Fassade"
	local rise = gableRoof(m, base, 1.4 + wallH, w, d, roofC, wallC)
	-- Erdgeschoss
	if opts.shop then
		for i = -2, 2 do
			part(m, Vector3.new(2.0, 3.5, 0.18),
				base * CFrame.new(i * 2.3, 3.9, d / 2 + 0.14), Color3.fromRGB(125, 178, 202), E.Glass, nil, false).Name = "Schaufenster"
		end
		houseDoor(m, base, -w * 0.34, 0, d / 2 + 0.12, Color3.fromRGB(68, 48, 34), opts.awning or Color3.fromRGB(180, 70, 58))
		part(m, Vector3.new(w * 0.72, 0.35, 2.6),
			base * CFrame.new(0, 6.2, d / 2 + 1.1), opts.awning or Color3.fromRGB(180, 70, 58), E.Fabric, nil, false).Name = "Markise"
		faceSign(m, base * CFrame.new(0, 6.9, d / 2 + 0.3), w * 0.65, 1.5,
			opts.sign or "LADEN", Color3.fromRGB(36, 48, 62), Color3.fromRGB(255, 246, 220))
	else
		houseDoor(m, base, -w * 0.24, 0, d / 2 + 0.12, Color3.fromRGB(78, 52, 36), opts.awning)
		houseWindow(m, base, w * 0.22, 4.1, d / 2 + 0.15, 2.2, 2.4, trim, shutterC, true)
	end
	-- Obergeschosse
	for f = 2, floors do
		local y = 1.4 + (f - 0.5) * 3.2 + 0.1
		local n = (w >= 12) and 3 or 2
		for k = 1, n do
			local lx = (k - (n + 1) / 2) * (w / (n + 1))
			houseWindow(m, base, lx, y, d / 2 + 0.15, 2.1, 2.3, trim, shutterC, math.random() < 0.62)
		end
	end
	if opts.balcony or math.random() < 0.24 then
		balcony(m, base, 0, 1.4 + 3.2 + 0.25, d / 2 + 0.05, w * 0.62, Color3.fromRGB(104, 76, 50))
	end
	if math.random() < 0.55 then
		chimney(m, base, w * 0.26, 1.4 + wallH + rise * 0.55, -d * 0.2, Color3.fromRGB(126, 108, 96))
	end
	if math.random() < 0.22 and floors >= 2 then
		roofDormer(m, base, 0, 1.4 + wallH + rise * 0.48, d * 0.22, w * 0.28, roofC, wallC)
	end
	return m
end

local function detachedHouse(parent, x, z, yaw, w, d, style, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = "Haus"
	m.Parent = parent
	local floors = opts.floors or 2
	local wallH = floors * 3.3 + 0.7
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.4, z) * CFrame.Angles(0, yaw, 0)
	local wallC = pick(style.wall)
	local roofC = pick(style.roof)
	local trim = style.trim
	local shutterC = style.shutter
	part(m, Vector3.new(w + 1.2, 1.6, d + 1.2), base * CFrame.new(0, 0.8, 0),
		Color3.fromRGB(146, 144, 138), E.Concrete).Name = "Sockel"
	part(m, Vector3.new(w, wallH, d), base * CFrame.new(0, 1.6 + wallH / 2, 0),
		wallC, E.Wood).Name = "Fassade"
	local rise = gableRoof(m, base, 1.6 + wallH, w, d, roofC, wallC)
	houseDoor(m, base, 0, 0, d / 2 + 0.14, Color3.fromRGB(74, 50, 34), opts.awning)
	for f = 1, floors do
		local y = 1.6 + (f - 0.5) * 3.3 + 0.1
		if f > 1 then
			for k = -1, 1 do
				houseWindow(m, base, k * w * 0.29, y, d / 2 + 0.16, 2.3, 2.5, trim, shutterC, math.random() < 0.55)
			end
		else
			for _, k in ipairs({ -1, 1 }) do
				houseWindow(m, base, k * w * 0.33, y, d / 2 + 0.16, 2.2, 2.4, trim, shutterC, true)
			end
		end
		-- Seitenfenster
		for _, s in ipairs({ -1, 1 }) do
			houseWindow(m, base * CFrame.Angles(0, s * math.pi / 2, 0), 0, y, w / 2 + 0.16, 1.9, 2.2, trim, shutterC, false)
		end
	end
	balcony(m, base, 0, 1.6 + 3.3 + 0.3, d / 2 + 0.05, w * 0.58, Color3.fromRGB(102, 74, 50))
	chimney(m, base, w * 0.28, 1.6 + wallH + rise * 0.5, -d * 0.25, Color3.fromRGB(124, 106, 94))
	if opts.annex then
		local aw, ad = w * 0.42, d * 0.55
		part(m, Vector3.new(aw, 4.6, ad), base * CFrame.new(-w * 0.58, 2.3, -d * 0.12),
			pick(style.wall), E.Wood).Name = "Anbau"
		part(m, Vector3.new(aw + 1.0, 0.45, ad + 1.0), base * CFrame.new(-w * 0.58, 4.75, -d * 0.12),
			roofC, E.Wood).Name = "Anbaudach"
	end
	return m
end

local function publicBuilding(parent, x, z, yaw, w, d, floors, style, title, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = title
	m.Parent = parent
	local wallH = floors * 3.4 + 0.8
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.4, z) * CFrame.Angles(0, yaw, 0)
	local wallC = opts.wall or pick(style.wall)
	local roofC = opts.roof or pick(style.roof)
	local trim = style.trim
	part(m, Vector3.new(w + 1.4, 1.6, d + 1.4), base * CFrame.new(0, 0.8, 0),
		Color3.fromRGB(142, 140, 134), E.Concrete).Name = "Sockel"
	part(m, Vector3.new(w, wallH, d), base * CFrame.new(0, 1.6 + wallH / 2, 0),
		wallC, E.Brick).Name = "Fassade"
	local rise = gableRoof(m, base, 1.6 + wallH, w, d, roofC, wallC)
	for f = 1, floors do
		local y = 1.6 + (f - 0.5) * 3.4 + 0.1
		for k = -2, 2 do
			if not (f == 1 and k == 0) then
				houseWindow(m, base, k * w * 0.18, y, d / 2 + 0.16, 2.0, 2.3, trim, nil, f == 1)
			end
		end
	end
	houseDoor(m, base, 0, 0, d / 2 + 0.14, Color3.fromRGB(62, 48, 36), opts.awning)
	part(m, Vector3.new(w * 0.7, 0.35, 2.0), base * CFrame.new(0, 5.1, d / 2 + 0.9),
		Color3.fromRGB(180, 176, 166), E.Concrete, nil, false).Name = "Eingangsvordach"
	faceSign(m, base * CFrame.new(0, 1.6 + wallH * 0.72, d / 2 + 0.35), w * 0.56, 1.3, title,
		Color3.fromRGB(30, 54, 82), Color3.fromRGB(255, 250, 232))
	if opts.tower then
		local tx, tz = w * 0.32, -d * 0.22
		part(m, Vector3.new(5.0, 13, 5.0), base * CFrame.new(tx, 1.6 + wallH + 6.5, tz),
			wallC, E.Brick).Name = "Turm"
		part(m, Vector3.new(6.0, 0.6, 6.0), base * CFrame.new(tx, 1.6 + wallH + 13.2, tz),
			roofC, E.Wood).Name = "Turmhelm"
		part(m, Vector3.new(3.6, 3.6, 0.2), base * CFrame.new(tx, 1.6 + wallH + 9.2, tz + 2.55),
			Color3.fromRGB(245, 240, 220), E.SmoothPlastic, nil, false).Name = "Uhr"
	end
	return m
end

local function gasStation(parent, x, z, yaw, title)
	local m = Instance.new("Model")
	m.Name = "Tankstelle"
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.2, z) * CFrame.Angles(0, yaw, 0)
	part(m, Vector3.new(44, 0.35, 30), base * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(92, 92, 92), E.Asphalt, nil, false).Name = "Tankstellenplatz"
	-- Shop
	part(m, Vector3.new(18, 7, 12), base * CFrame.new(-10, 3.5, -8),
		Color3.fromRGB(236, 232, 220), E.SmoothPlastic).Name = "Shop"
	part(m, Vector3.new(19.5, 0.6, 13.5), base * CFrame.new(-10, 7.3, -8),
		Color3.fromRGB(48, 74, 92), E.SmoothPlastic).Name = "Shopdach"
	for i = -2, 2 do
		part(m, Vector3.new(2.2, 2.8, 0.2), base * CFrame.new(-10 + i * 3.2, 4.3, -1.85),
			Color3.fromRGB(130, 180, 205), E.Glass, nil, false).Name = "Shopfenster"
	end
	part(m, Vector3.new(3.2, 4.8, 0.2), base * CFrame.new(-17.4, 2.5, -1.85),
		Color3.fromRGB(64, 72, 80), E.Glass, nil, false).Name = "Shoptuer"
	faceSign(m, base * CFrame.new(-10, 6.0, -1.75), 10, 1.6, title,
		Color3.fromRGB(20, 72, 90), Color3.fromRGB(255, 246, 210))
	-- Canopy
	part(m, Vector3.new(34, 0.8, 18), base * CFrame.new(4, 8.0, 0),
		Color3.fromRGB(226, 228, 226), E.Metal).Name = "Canopy"
	part(m, Vector3.new(36, 0.35, 20), base * CFrame.new(4, 8.5, 0),
		Color3.fromRGB(198, 58, 54), E.SmoothPlastic, nil, false).Name = "Canopyband"
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(m, Vector3.new(1.1, 8.2, 1.1), base * CFrame.new(4 + sx * 14, 4.1, sz * 7),
				Color3.fromRGB(196, 198, 196), E.Metal).Name = "Canopy-Stuetze"
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local px = 4 + sx * 7
		part(m, Vector3.new(3.2, 0.5, 7.0), base * CFrame.new(px, 0.65, 2),
			Color3.fromRGB(120, 120, 120), E.Concrete).Name = "Zapfinsel"
		for _, sz in ipairs({ -2.0, 2.0 }) do
			part(m, Vector3.new(1.8, 3.4, 1.2), base * CFrame.new(px, 2.5, sz),
				Color3.fromRGB(238, 236, 226), E.SmoothPlastic).Name = "Zapfsaeule"
			part(m, Vector3.new(1.6, 1.0, 0.25), base * CFrame.new(px, 3.4, sz - 0.7),
				Color3.fromRGB(40, 92, 130), E.Neon, nil, false).Name = "Zapfdisplay"
		end
	end
	-- Preissaeule
	part(m, Vector3.new(4.5, 8, 0.6), base * CFrame.new(18, 4, -6),
		Color3.fromRGB(30, 58, 78), E.SmoothPlastic).Name = "Preissaeule"
	faceSign(m, base * CFrame.new(18, 7.2, -5.65), 4.0, 2.0, "TANK\n24h", Color3.fromRGB(30, 58, 78), Color3.fromRGB(255, 224, 120))
	-- Luft/Wasser und Parkplatz
	part(m, Vector3.new(3.2, 4.2, 3.2), base * CFrame.new(18, 2.1, 8),
		Color3.fromRGB(80, 130, 150), E.SmoothPlastic).Name = "Luftstation"
	for i = -1, 1 do
		part(m, Vector3.new(2.2, 0.2, 5.0), base * CFrame.new(-20 + i * 5, 0.25, 8),
			Color3.fromRGB(220, 220, 214), E.SmoothPlastic, nil, false).Name = "Parklinie"
	end
	return m
end

local function farmhouse(parent, x, z, yaw)
	local m = Instance.new("Model")
	m.Name = "Bauernhof"
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.4, z) * CFrame.Angles(0, yaw, 0)
	local wallC = Color3.fromRGB(226, 212, 184)
	local woodC = Color3.fromRGB(126, 88, 58)
	local roofC = Color3.fromRGB(100, 64, 50)
	part(m, Vector3.new(34, 1.4, 18), base * CFrame.new(-2, 0.7, 0), Color3.fromRGB(146, 142, 132), E.Concrete).Name = "Hofplatte"
	part(m, Vector3.new(24, 9, 15), base * CFrame.new(-4, 5.9, 0), wallC, E.Wood).Name = "Wohnhaus"
	gableRoof(m, base * CFrame.new(-4, 0, 0), 10.4, 24, 15, roofC, wallC)
	houseDoor(m, base * CFrame.new(-4, 0, 0), -7, 0, 7.65, Color3.fromRGB(74, 50, 34), woodC)
	for _, lx in ipairs({ -9, -4, 1 }) do
		houseWindow(m, base * CFrame.new(-4, 0, 0), lx, 5.0, 7.65, 2.1, 2.2, Color3.fromRGB(242, 236, 222), Color3.fromRGB(70, 84, 60), true)
	end
	part(m, Vector3.new(8, 2.2, 15.4), base * CFrame.new(-4, 10.8, 0), woodC, E.Wood).Name = "Holzbalkon"
	for i = -3, 3 do
		part(m, Vector3.new(0.16, 1.1, 0.16), base * CFrame.new(-4 + i * 1.1, 12.0, 7.4), woodC, E.Wood, nil, false)
	end
	-- Scheune
	part(m, Vector3.new(18, 9, 15), base * CFrame.new(15, 5.9, 0), Color3.fromRGB(126, 92, 62), E.Wood).Name = "Scheune"
	gableRoof(m, base * CFrame.new(15, 0, 0), 10.4, 18, 15, roofC, Color3.fromRGB(126, 92, 62))
	part(m, Vector3.new(7, 6.5, 0.3), base * CFrame.new(15, 4.2, 7.6), Color3.fromRGB(78, 54, 38), E.Wood).Name = "Scheunentor"
	part(m, Vector3.new(18, 0.3, 0.3), base * CFrame.new(15, 7.4, 7.65), Color3.fromRGB(210, 190, 150), E.Wood, nil, false)
	-- Silo
	part(m, Vector3.new(16, 9, 9), base * CFrame.new(27, 9, -4), Color3.fromRGB(190, 190, 184), E.Metal, Enum.PartType.Cylinder).CFrame =
		base * CFrame.new(27, 9, -4) * CFrame.Angles(0, 0, math.pi / 2)
	part(m, Vector3.new(1.5, 10.5, 10.5), base * CFrame.new(27, 17.4, -4), Color3.fromRGB(134, 134, 130), E.Metal, Enum.PartType.Cylinder).CFrame =
		base * CFrame.new(27, 17.4, -4) * CFrame.Angles(0, 0, math.pi / 2)
	-- Heuballen
	for i = 0, 3 do
		part(m, Vector3.new(3.0, 2.2, 3.0), base * CFrame.new(-20 + i * 4.0, 1.1, 7.0),
			Color3.fromRGB(210, 184, 96), E.Grass).Name = "Heuballen"
	end
	return m
end

local function industrialHall(parent, x, z, yaw, title)
	local m = Instance.new("Model")
	m.Name = title
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.3, z) * CFrame.Angles(0, yaw, 0)
	part(m, Vector3.new(36, 0.4, 26), base * CFrame.new(0, 0.2, 0), Color3.fromRGB(88, 88, 88), E.Asphalt).Name = "Vorplatz"
	part(m, Vector3.new(28, 9, 18), base * CFrame.new(0, 5.0, 0),
		Color3.fromRGB(160, 164, 166), E.Metal).Name = "Halle"
	part(m, Vector3.new(30, 0.8, 20), base * CFrame.new(0, 9.8, 0),
		Color3.fromRGB(92, 96, 100), E.Metal).Name = "Hallendach"
	for i = -1, 1 do
		part(m, Vector3.new(6, 6, 0.3), base * CFrame.new(i * 8, 3.5, 9.05),
			Color3.fromRGB(72, 76, 80), E.Metal, nil, false).Name = "Rolltor"
	end
	faceSign(m, base * CFrame.new(0, 8.0, 9.1), 14, 1.8, title,
		Color3.fromRGB(28, 48, 62), Color3.fromRGB(255, 235, 190))
	-- Holzstapel / Container
	for i = 0, 4 do
		part(m, Vector3.new(2.0, 2.0, 7.0), base * CFrame.new(-20, 1.2 + (i % 2) * 1.8, -6 + i * 3),
			Color3.fromRGB(122, 84, 54), E.Wood).Name = "Holzstapel"
	end
	part(m, Vector3.new(7, 3.2, 3.0), base * CFrame.new(20, 1.8, 8),
		Color3.fromRGB(60, 96, 110), E.Metal).Name = "Container"
	return m
end

local function restaurant(parent, x, z, yaw, title)
	local m = Instance.new("Model")
	m.Name = title
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.4, z) * CFrame.Angles(0, yaw, 0)
	part(m, Vector3.new(26, 0.5, 22), base * CFrame.new(0, 0.25, 0), Color3.fromRGB(112, 106, 96), E.Concrete).Name = "Terrasse"
	part(m, Vector3.new(20, 8, 14), base * CFrame.new(0, 4.4, -3), Color3.fromRGB(236, 226, 204), E.Wood).Name = "Restaurant"
	gableRoof(m, base * CFrame.new(0, 0, -3), 8.4, 20, 14, Color3.fromRGB(112, 68, 54), Color3.fromRGB(236, 226, 204))
	houseDoor(m, base * CFrame.new(0, 0, -3), 0, 0, 7.15, Color3.fromRGB(70, 50, 36), Color3.fromRGB(150, 64, 52))
	for _, lx in ipairs({ -6, 6 }) do
		houseWindow(m, base * CFrame.new(0, 0, -3), lx, 4.6, 7.15, 2.4, 2.4, Color3.fromRGB(248, 242, 226), Color3.fromRGB(70, 90, 70), true)
	end
	faceSign(m, base * CFrame.new(0, 7.0, 4.3), 12, 1.6, title,
		Color3.fromRGB(50, 62, 42), Color3.fromRGB(255, 240, 200))
	for i = -1, 1 do
		part(m, Vector3.new(3.0, 0.3, 3.0), base * CFrame.new(i * 5, 1.6, 5), Color3.fromRGB(180, 144, 94), E.Wood).Name = "Tisch"
		part(m, Vector3.new(0.3, 2.4, 0.3), base * CFrame.new(i * 5, 2.8, 5), Color3.fromRGB(90, 78, 62), E.Metal, nil, false)
		part(m, Vector3.new(4.5, 0.2, 4.5), base * CFrame.new(i * 5, 4.0, 5), Color3.fromRGB(150, 60, 52), E.Fabric, nil, false).Name = "Sonnenschirm"
	end
	return m
end

local function boathouse(parent, x, z, yaw)
	local m = Instance.new("Model")
	m.Name = "Bootshaus"
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.3, z) * CFrame.Angles(0, yaw, 0)
	part(m, Vector3.new(16, 7, 12), base * CFrame.new(0, 3.5, 0), Color3.fromRGB(126, 88, 58), E.Wood).Name = "Bootshaus"
	gableRoof(m, base, 7, 16, 12, Color3.fromRGB(82, 60, 48), Color3.fromRGB(126, 88, 58))
	part(m, Vector3.new(6, 5, 0.3), base * CFrame.new(0, 2.8, 6.1), Color3.fromRGB(72, 52, 36), E.Wood).Name = "Bootstor"
	part(m, Vector3.new(4, 0.6, 12), base * CFrame.new(10, 1.0, 0), Color3.fromRGB(120, 88, 56), E.Wood).Name = "Steg"
	for i = 0, 3 do
		part(m, Vector3.new(2.8, 1.0, 1.2), base * CFrame.new(-4 + i * 2.6, 0.6, 8),
			(i % 2 == 0) and Color3.fromRGB(200, 72, 60) or Color3.fromRGB(230, 220, 190), E.SmoothPlastic).Name = "Boot"
	end
	return m
end

local function campingCabin(parent, x, z, yaw)
	local m = Instance.new("Model")
	m.Name = "Camping-Huette"
	m.Parent = parent
	local gy = heightAt(x, z)
	local base = CFrame.new(x, gy - 0.3, z) * CFrame.Angles(0, yaw, 0)
	part(m, Vector3.new(8, 4.5, 7), base * CFrame.new(0, 2.4, 0), Color3.fromRGB(148, 104, 66), E.Wood)
	gableRoof(m, base, 4.7, 8, 7, Color3.fromRGB(88, 62, 48), Color3.fromRGB(148, 104, 66))
	part(m, Vector3.new(2.0, 3.5, 0.2), base * CFrame.new(-1.6, 1.9, 3.6), Color3.fromRGB(70, 50, 34), E.Wood)
	part(m, Vector3.new(1.6, 1.6, 0.2), base * CFrame.new(1.8, 2.5, 3.6), Color3.fromRGB(130, 180, 205), E.Glass, nil, false)
	return m
end

local function benchProp(parent, x, z, yaw)
	local y = heightAt(x, z)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	part(parent, Vector3.new(4.0, 0.25, 1.2), cf * CFrame.new(0, 1.1, 0), Color3.fromRGB(120, 84, 54), E.Wood)
	part(parent, Vector3.new(4.0, 1.0, 0.2), cf * CFrame.new(0, 1.75, -0.5), Color3.fromRGB(120, 84, 54), E.Wood)
	for _, sx in ipairs({ -1.5, 1.5 }) do
		part(parent, Vector3.new(0.2, 1.0, 0.2), cf * CFrame.new(sx, 0.6, 0), Color3.fromRGB(60, 60, 62), E.Metal)
	end
end

local function streetLight(parent, x, z)
	local y = heightAt(x, z)
	part(parent, Vector3.new(0.35, 12, 0.35), CFrame.new(x, y + 6, z), Color3.fromRGB(70, 72, 74), E.Metal)
	part(parent, Vector3.new(3.0, 0.25, 0.25), CFrame.new(x + 1.4, y + 11.8, z), Color3.fromRGB(70, 72, 74), E.Metal)
	part(parent, Vector3.new(1.1, 0.3, 0.6), CFrame.new(x + 2.8, y + 11.65, z),
		Color3.fromRGB(255, 240, 200), E.Neon, nil, false)
end

local function picnicTable(parent, x, z, yaw)
	local y = heightAt(x, z)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	part(parent, Vector3.new(4.5, 0.25, 2.2), cf * CFrame.new(0, 2.0, 0), Color3.fromRGB(150, 110, 72), E.Wood)
	for _, sx in ipairs({ -1.5, 1.5 }) do
		part(parent, Vector3.new(0.25, 2.0, 0.25), cf * CFrame.new(sx, 1.0, 0), Color3.fromRGB(90, 66, 44), E.Wood)
		part(parent, Vector3.new(0.7, 0.22, 0.7), cf * CFrame.new(sx, 0.55, 0), Color3.fromRGB(90, 66, 44), E.Wood)
	end
	for _, sz in ipairs({ -1.0, 1.0 }) do
		part(parent, Vector3.new(4.5, 0.22, 0.8), cf * CFrame.new(0, 1.1, sz * 1.4), Color3.fromRGB(150, 110, 72), E.Wood)
	end
end

local function umbrellaProp(parent, x, z)
	local y = heightAt(x, z)
	part(parent, Vector3.new(0.18, 5.0, 0.18), CFrame.new(x, y + 2.5, z), Color3.fromRGB(90, 78, 62), E.Metal, nil, false)
	part(parent, Vector3.new(5.0, 0.25, 5.0), CFrame.new(x, y + 5.0, z),
		Color3.fromRGB(196, 68, 56), E.Fabric, nil, false)
	part(parent, Vector3.new(4.0, 0.22, 4.0), CFrame.new(x, y + 5.1, z),
		Color3.fromRGB(236, 220, 184), E.Fabric, nil, false)
end

local function fenceLine(parent, a, b, step)
	step = step or 8
	local dx, dz = b.X - a.X, b.Y - a.Y
	local L = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.floor(L / step))
	for i = 0, n do
		local t = i / n
		local x, z = lerp(a.X, b.X, t), lerp(a.Y, b.Y, t)
		if lakeMask(x, z) < 0.05 then
			local y = heightAt(x, z)
			part(parent, Vector3.new(0.22, 1.8, 0.22), CFrame.new(x, y + 0.9, z),
				Color3.fromRGB(102, 74, 48), E.Wood, nil, false)
		end
	end
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local x0, z0 = lerp(a.X, b.X, t0), lerp(a.Y, b.Y, t0)
		local x1, z1 = lerp(a.X, b.X, t1), lerp(a.Y, b.Y, t1)
		if lakeMask(x0, z0) < 0.05 and lakeMask(x1, z1) < 0.05 then
			local y0, y1 = heightAt(x0, z0), heightAt(x1, z1)
			local cf = CFrame.lookAt(Vector3.new((x0 + x1) / 2, (y0 + y1) / 2 + 1.2, (z0 + z1) / 2),
				Vector3.new(x1, y1 + 1.2, z1))
			part(parent, Vector3.new(0.15, 0.18, (Vector2.new(x1, z1) - Vector2.new(x0, z0)).Magnitude),
				cf, Color3.fromRGB(112, 82, 54), E.Wood, nil, false)
		end
	end
end

local function hedgeLine(parent, a, b, step)
	step = step or 5
	local dx, dz = b.X - a.X, b.Y - a.Y
	local L = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.floor(L / step))
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local x0, z0 = lerp(a.X, b.X, t0), lerp(a.Y, b.Y, t0)
		local x1, z1 = lerp(a.X, b.X, t1), lerp(a.Y, b.Y, t1)
		if lakeMask(x0, z0) < 0.05 then
			local y = (heightAt(x0, z0) + heightAt(x1, z1)) / 2
			local cf = CFrame.lookAt(Vector3.new((x0 + x1) / 2, y + 1.2, (z0 + z1) / 2),
				Vector3.new(x1, y + 1.2, z1))
			part(parent, Vector3.new(2.2, 2.4, (Vector2.new(x1, z1) - Vector2.new(x0, z0)).Magnitude + 0.3),
				cf, Color3.fromRGB(58, 104, 58), E.Grass, nil, false)
		end
	end
end

local function fieldPlot(parent, x, z, w, d, yaw, cropC)
	local y = heightAt(x, z)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	local rows = math.max(3, math.floor(d / 4))
	for r = 1, rows do
		local zz = -d / 2 + (r - 0.5) * d / rows
		for c = 1, 3 do
			local xx = -w / 2 + (c - 0.5) * w / 3
			part(parent, Vector3.new(w / 3 - 1.0, 0.6, 1.6),
				cf * CFrame.new(xx, 0.35, zz), cropC, E.Grass, nil, false).Name = "Feldreihe"
		end
	end
	fenceLine(parent, Vector2.new(x - w / 2, z - d / 2), Vector2.new(x + w / 2, z - d / 2), 9)
	fenceLine(parent, Vector2.new(x - w / 2, z + d / 2), Vector2.new(x + w / 2, z + d / 2), 9)
end

local function orchard(parent, x, z, w, d, yaw)
	local y = heightAt(x, z)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	for ix = -2, 2 do
		for iz = -2, 2 do
			local px, pz = ix * w / 5, iz * d / 5
			part(parent, Vector3.new(0.5, 3.2, 0.5), cf * CFrame.new(px, 1.6, pz),
				Color3.fromRGB(90, 62, 42), E.Wood, nil, false)
			part(parent, Vector3.new(3.2, 2.8, 3.2), cf * CFrame.new(px, 4.2, pz),
				Color3.fromRGB(68, 116, 60), E.Grass, nil, false)
			part(parent, Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(px + 1.0, 4.6, pz),
				Color3.fromRGB(200, 60, 54), E.SmoothPlastic, nil, false)
		end
	end
end

local function parkingLot(parent, x, z, w, d, yaw)
	local y = heightAt(x, z)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	part(parent, Vector3.new(w, 0.25, d), cf * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(88, 88, 90), E.Asphalt, nil, false).Name = "Parkplatz"
	for i = -2, 2 do
		part(parent, Vector3.new(0.25, 0.1, d * 0.6), cf * CFrame.new(i * w / 6, 0.3, 0),
			Color3.fromRGB(230, 230, 220), E.SmoothPlastic, nil, false)
	end
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
	houseDoor(m, base, 0, 1.5, 14.15, Color3.fromRGB(78, 54, 38), Color3.fromRGB(120, 60, 52))
	for _, lx in ipairs({ -4.5, 4.5 }) do
		houseWindow(m, base, lx, 7.5, 14.15, 2.0, 4.0, white, nil, false)
	end
	part(m, Vector3.new(5, 5, 0.2), base * CFrame.new(0, 24, -9.85),
		Color3.fromRGB(150, 190, 210), E.Glass, nil, false).Name = "Kirchenfenster"
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
		local rr = rad + (p.r or 0)
		if (p.x - x) ^ 2 + (p.z - z) ^ 2 < rr * rr then return false end
	end
	return true
end
local function addPlaced(x, z, r)
	allPlaced[#allPlaced + 1] = { x = x, z = z, r = r or 0 }
end
local function roadLength(P)
	local n = 0
	for i = 1, #P - 1 do n = n + (P[i + 1] - P[i]).Magnitude end
	return n
end
local function pointAt(P, dist)
	local acc = 0
	for i = 1, #P - 1 do
		local a, b = P[i], P[i + 1]
		local L = (b - a).Magnitude
		if acc + L >= dist and L > 0.001 then
			local f = clamp((dist - acc) / L, 0, 1)
			local tx, tz = tangent(P, i)
			return a:Lerp(b, f), tx, tz
		end
		acc = acc + L
	end
	local tx, tz = tangent(P, #P)
	return P[#P], tx, tz
end
local function faceStreetYaw(nx, nz, side)
	-- Lokale +Z-Achse zeigt zur Strasse (Tuer nicht mehr von der Strasse weg).
	return math.atan2(-nx * side, -nz * side)
end

local function tryPublic(tf, t, style, kind, u, side, w, d, floors, title, opts)
	local ci, p = nearX(t.road.P, t.cx + u)
	local tx, tz = tangent(t.road.P, ci)
	local nx, nz = -tz, tx
	local off = t.road.half + 9 + d / 2
	local hx, hz = p.X + nx * side * off, p.Y + nz * side * off
	if roadDistXZ(hx, hz) < 17 then return false end
	if math.abs(heightAt(hx, hz) - t.h) > 4.5 then return false end
	if lakeMask(hx, hz) > 0.05 then return false end
	if nearJunction(hx, hz, 22) then return false end
	if not farFrom(hx, hz, 10) then return false end
	local yaw = faceStreetYaw(nx, nz, side)
	if kind == "church" then
		church(tf, hx, hz, yaw)
	elseif kind == "fountain" then
		fountain(tf, hx, hz)
	elseif kind == "gas" then
		gasStation(tf, hx, hz, yaw, title)
	elseif kind == "farm" then
		farmhouse(tf, hx, hz, yaw)
	else
		publicBuilding(tf, hx, hz, yaw, w, d, floors, style, title, opts)
	end
	addPlaced(hx, hz, (kind == "church" and 18) or (kind == "gas" and 25) or (kind == "farm" and 24) or (kind == "fountain" and 6) or math.max(w, d) * 0.5)
	return true
end

for _, t in ipairs(TOWNS) do
	local tf = Instance.new("Folder")
	tf.Name = t.name
	tf.Parent = townFolder
	local ci, M = nearestOn(t.road.P, t.cx, t.cz)
	local tx, tz = tangent(t.road.P, ci)
	local nx, nz = -tz, tx
	local sgn = (t.name == "Seeburg" or t.name == "Nordegg") and -1 or 1
	local style = STYLE[t.name]

	-- Oeffentliche Gebaeude entlang der Hauptstrasse, mittig auf ihren
	-- Parzellen und mit der Tuer zur Strasse.
	if t.size == "large" then
		tryPublic(tf, t, style, "church", 0, sgn, 18, 28, 1, "Kirche", {})
		tryPublic(tf, t, style, "public", -95, -sgn, 24, 17, 2, "Gemeindehaus", { tower = true })
		tryPublic(tf, t, style, "public", 110, sgn, 32, 17, 2, "Schule", {})
		tryPublic(tf, t, style, "public", 220, -sgn, 23, 18, 1, "Feuerwehr", {})
		-- Der grosse Brunnen liegt auf der Nordseite, weil die Diagonale
		-- suedlich der Hauptstrasse verlaeuft.
		tryPublic(tf, t, style, "fountain", 70, 1, 0, 0, 0, "Brunnen", {})
	elseif t.size == "medium" then
		-- Die mittleren Orte haben eine Querstrasse genau in der Mitte. Kirche
		-- und Brunnen deshalb leicht versetzen, sonst liegt ihr Grundriss auf
		-- der Strasse und wird korrekt verworfen.
		if t.church then
			tryPublic(tf, t, style, "church", 30, sgn, 16, 24, 1, "Kirche", {})
			tryPublic(tf, t, style, "fountain", 70, -sgn, 0, 0, 0, "Brunnen", {})
		else
			tryPublic(tf, t, style, "fountain", 30, sgn, 0, 0, 0, "Brunnen", {})
		end
		tryPublic(tf, t, style, "public", -85, -sgn, 20, 15, 2, "Gemeindehaus", {})
		tryPublic(tf, t, style, "public", 100, sgn, 26, 15, 2, "Schule", {})
		tryPublic(tf, t, style, "public", 185, -sgn, 18, 14, 1, "Werkhof", {})
	else
		tryPublic(tf, t, style, "fountain", 0, sgn, 0, 0, 0, "Brunnen", {})
		tryPublic(tf, t, style, "public", -65, -sgn, 15, 13, 1, "Backhaus", {})
		tryPublic(tf, t, style, "public", 70, sgn, 18, 14, 1, "Werkstatt", {})
	end

	-- Tankstellen: bewusst nicht in jedem Ort, damit sie besonders bleiben.
	if t.name == "Mitteldorf" then
		tryPublic(tf, t, style, "gas", 300, -sgn, 44, 30, 1, "TANKSTELLE", {})
	elseif t.name == "Ostheim" then
		tryPublic(tf, t, style, "gas", -150, sgn, 44, 30, 1, "TANKSTELLE", {})
	elseif t.name == "Suedhalde" then
		tryPublic(tf, t, style, "gas", 160, -sgn, 44, 30, 1, "TANKSTELLE", {})
	end

	-- Kettenhaeuser an den Gitterstrassen. Jedes Modul sitzt exakt
	-- in der Mitte seines Frontabschnitts; die Tuer zeigt zur Strasse.
	local maxRows = (t.size == "large") and 92 or ((t.size == "medium") and 54 or 16)
	local made = 0
	for _, r in ipairs(t.roads) do
		if made >= maxRows then break end
		local total = roadLength(r.P)
		for _, side in ipairs({ -1, 1 }) do
			local s = 18
			while s < total - 18 and made < maxRows do
				local w = 9 + math.random(0, 4)
				local d = 18 + math.random(0, 5)
				local p, rtx, rtz = pointAt(r.P, s + w / 2)
				local rnx, rnz = -rtz, rtx
				local off = r.half + 6 + d / 2
				local hx, hz = p.X + rnx * side * off, p.Y + rnz * side * off
				local ok = roadDistXZ(hx, hz) > r.half + 7
					and math.abs(heightAt(hx, hz) - t.h) < 4.2
					and lakeMask(hx, hz) < 0.05
					and not nearJunction(hx, hz, 18)
					and farFrom(hx, hz, 5)
				if ok then
					local yaw = faceStreetYaw(rnx, rnz, side)
					local shop = (t.size ~= "small") and (math.random() < 0.17)
					local opts = {
						floors = 2 + ((math.random() < 0.36) and 1 or 0),
						shop = shop,
						balcony = (math.random() < 0.20),
						awning = shop and Color3.fromRGB(170 + math.random(0, 40), 64 + math.random(0, 30), 54) or nil,
						sign = shop and (t.name == "Seeburg" and "CAFE" or (t.name == "Mitteldorf" and "LADEN" or "WERKSTATT")) or nil,
					}
					rowHouse(tf, hx, hz, yaw, w, d, style, opts)
					addPlaced(hx, hz, w * 0.5)
					made = made + 1
					s = s + w + 0.12
				else
					s = s + 5.5
				end
			end
		end
		task.wait()
	end

	-- Ein paar groessere Einzelhaeuser an der Hauptstrasse, aber nicht
	-- in der Ortsmitte. Sie haben ebenfalls die Tuer zur Strasse.
	local detached = 0
	for u = -t.L * 0.46, t.L * 0.46, 62 do
		if detached >= 7 then break end
		for _, side in ipairs({ -1, 1 }) do
			if detached >= 7 then break end
			local pi, p = nearX(t.road.P, t.cx + u)
			local dtx, dtz = tangent(t.road.P, pi)
			local dnx, dnz = -dtz, dtx
			local w = 20 + math.random(0, 6)
			local d = 22 + math.random(0, 6)
			local off = t.road.half + 9 + d / 2
			local hx, hz = p.X + dnx * side * off, p.Y + dnz * side * off
			local ok = roadDistXZ(hx, hz) > t.road.half + 9
				and math.abs(heightAt(hx, hz) - t.h) < 4.5
				and lakeMask(hx, hz) < 0.05
				and nearJunction(hx, hz, 30) == false
				and farFrom(hx, hz, 16)
			if ok then
				local yaw = faceStreetYaw(dnx, dnz, side)
				detachedHouse(tf, hx, hz, yaw, w, d, style, {
					floors = 2,
					annex = math.random() < 0.55,
					awning = (math.random() < 0.4) and Color3.fromRGB(150, 70, 56) or nil,
				})
				addPlaced(hx, hz, math.max(w, d) * 0.5)
				detached = detached + 1
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
		-- Das Ortsschild steht ausserhalb des Ortsendes, damit es nicht auf
		-- der Querstrasse des geschlossenen Gitters liegt.
		local eout = (e == e1) and -1 or 1
		local bx, bz = e.X + etx * eout * 24, e.Y + etz * eout * 24
		local sx, sz = bx + enx * 19.5, bz + enz * 19.5
		if roadDistXZ(sx, sz) < 17 or not farFrom(sx, sz, 4) then
			sx, sz = bx - enx * 19.5, bz - enz * 19.5
		end
		if roadDistXZ(sx, sz) > 17 and farFrom(sx, sz, 4) then
			local txx, tzz = e.X + etx * eout * 40, e.Y + etz * eout * 40
			signBoard(tf, sx, sz, txx, tzz, 13, 3.6, t.name, Color3.fromRGB(20, 56, 112), Color3.fromRGB(255, 255, 255))
			addPlaced(sx, sz, 4)
		end
	end
	task.wait()
end
print(("[v44] %d Doerfer gebaut"):format(#TOWNS))

---------------------------------------------------------------
-- 8b. POIs: Bauernhoefe, Saegewerk, See-Resort, Bergrestaurant,
--     Raststaette, Felder, Parkplaetze, Baenke.
---------------------------------------------------------------
local poiFolder = Instance.new("Folder")
poiFolder.Name = "POIs"
poiFolder.Parent = map
local function poiFree(x, z, r)
	return lakeMask(x, z) < 0.05
		and roadDistXZ(x, z) > (r or 14)
		and farFrom(x, z, 8)
end

-- Bergrestaurant auf dem ehemaligen Burgberg (keine Burg).
do
	local bx, bz = 1625, -700
	if poiFree(bx, bz, 18) then
		restaurant(poiFolder, bx, bz, math.rad(-32), "BERGRESTAURANT")
		addPlaced(bx, bz, 20)
		parkingLot(poiFolder, bx + 26, bz + 20, 34, 22, math.rad(-32))
		addPlaced(bx + 26, bz + 20, 20)
		picnicTable(poiFolder, bx - 24, bz + 8, math.rad(20))
		benchProp(poiFolder, bx - 22, bz - 6, math.rad(110))
		streetLight(poiFolder, bx + 8, bz + 26)
	end
end

-- Bauernhoefe an den neuen Loops.
do
	local farms = {
		{ -710, 1320, math.rad(18) },
		{ 35, -1360, math.rad(-24) },
		{ -2580, 380, math.rad(12) },
	}
	for _, f in ipairs(farms) do
		if poiFree(f[1], f[2], 22) then
			farmhouse(poiFolder, f[1], f[2], f[3])
			addPlaced(f[1], f[2], 26)
			fieldPlot(poiFolder, f[1] - 42, f[2] + 18, 42, 30, f[3] + 0.2, Color3.fromRGB(176, 156, 74))
			addPlaced(f[1] - 42, f[2] + 18, 23)
			fieldPlot(poiFolder, f[1] + 38, f[2] - 20, 34, 26, f[3] - 0.25, Color3.fromRGB(86, 136, 68))
			addPlaced(f[1] + 38, f[2] - 20, 19)
			orchard(poiFolder, f[1] + 4, f[2] + 48, 30, 24, f[3])
			addPlaced(f[1] + 4, f[2] + 48, 17)
		end
	end
end

-- Saegewerk / Industrie am Ostloop.
do
	local ix, iz = 2200, 120
	if poiFree(ix, iz, 22) then
		industrialHall(poiFolder, ix, iz, math.rad(78), "SAEGEWERK")
		addPlaced(ix, iz, 28)
		parkingLot(poiFolder, ix - 30, iz + 22, 34, 20, math.rad(78))
		addPlaced(ix - 30, iz + 22, 19)
		fenceLine(poiFolder, Vector2.new(ix - 36, iz - 20), Vector2.new(ix + 36, iz - 20), 9)
		for i = 0, 3 do
			part(poiFolder, Vector3.new(3, 3, 9), CFrame.new(ix - 40, heightAt(ix - 40, iz + 6 + i * 10) + 1.5, iz + 6 + i * 10),
				Color3.fromRGB(122, 84, 54), E.Wood).Name = "Baumstamm"
		end
		addPlaced(ix - 40, iz + 20, 14)
	end
end

-- See-Resort: Bootshaus, Camping, Strand, Restaurant.
do
	local bx, bz = -1385, 560
	if poiFree(bx, bz, 14) then
		boathouse(poiFolder, bx, bz, math.rad(90))
		addPlaced(bx, bz, 16)
	end
	local cabins = {
		{ -1310, 790, math.rad(28) },
		{ -1250, 910, math.rad(10) },
		{ -1370, 1010, math.rad(-18) },
		{ -1225, 1040, math.rad(38) },
	}
	for _, c in ipairs(cabins) do
		if poiFree(c[1], c[2], 10) then
			campingCabin(poiFolder, c[1], c[2], c[3])
			addPlaced(c[1], c[2], 8)
		end
	end
	for i = 0, 4 do
		local x = -1510 + i * 24
		local z = 690 + (i % 2) * 22
		if lakeMask(x, z) < 0.08 then
			umbrellaProp(poiFolder, x, z)
			addPlaced(x, z, 4)
			benchProp(poiFolder, x + 10, z + 6, math.rad(180))
			addPlaced(x + 10, z + 6, 3)
		end
	end
	local rx, rz = -1410, 300
	if poiFree(rx, rz, 16) then
		restaurant(poiFolder, rx, rz, math.rad(145), "SEEBECK")
		addPlaced(rx, rz, 18)
		parkingLot(poiFolder, rx + 28, rz + 8, 28, 18, math.rad(145))
		addPlaced(rx + 28, rz + 8, 17)
	end
end

-- Raststaette an der Autobahn.
do
	-- Die Raststaette liegt innerhalb der Zufahrtsschleife, damit Tankstelle,
	-- Parkplatz und WC nicht auf der Fahrbahn stehen.
	local rx, rz = 3150, 1700
	if lakeMask(rx, rz) < 0.05 then
		gasStation(poiFolder, rx, rz, math.rad(-90), "RASTSTAETTE")
		addPlaced(rx, rz, 25)
		parkingLot(poiFolder, rx + 60, rz + 22, 48, 24, math.rad(-90))
		addPlaced(rx + 60, rz + 22, 26)
		picnicTable(poiFolder, rx - 20, rz - 60, math.rad(20))
		addPlaced(rx - 20, rz - 60, 3)
		picnicTable(poiFolder, rx - 38, rz - 64, math.rad(-12))
		addPlaced(rx - 38, rz - 64, 3)
		streetLight(poiFolder, rx + 10, rz + 24)
		streetLight(poiFolder, rx - 30, rz + 24)
		part(poiFolder, Vector3.new(12, 4.5, 9), CFrame.new(rx - 28, heightAt(rx - 28, rz - 34) + 2.25, rz - 34),
			Color3.fromRGB(224, 220, 208), E.Concrete).Name = "WC"
		part(poiFolder, Vector3.new(13, 0.5, 10), CFrame.new(rx - 28, heightAt(rx - 28, rz - 34) + 4.7, rz - 34),
			Color3.fromRGB(70, 92, 108), E.SmoothPlastic).Name = "WC-Dach"
		addPlaced(rx - 28, rz - 34, 8)
		-- Zufahrt vom Rast-Loop zum Tankstellenvorplatz.
		part(poiFolder, Vector3.new(72, 0.35, 14), CFrame.new(rx - 44, heightAt(rx - 44, 1700) + 0.2, 1700),
			Color3.fromRGB(64, 65, 68), E.Asphalt, nil, false).Name = "Rastzufahrt"
		addPlaced(rx - 44, 1700, 20)
	end
end

-- Strassennahe Baenke, Bus-Haltestellen und Briefkaesten.
do
	local propFolder = Instance.new("Folder")
	propFolder.Name = "Strassenmobiliar"
	propFolder.Parent = map
	for _, x in ipairs({ -2150, -1250, -850, -200, 350, 800, 1250, 1850, 2250 }) do
		local _, p = nearX(TAL.P, x)
		local tx, tz = tangent(TAL.P, nearestOn(TAL.P, p.X, p.Y))
		local nx, nz = -tz, tx
		local sx, sz = p.X + nx * 19.5, p.Y + nz * 19.5
		if roadDistXZ(sx, sz) > 17 and farFrom(sx, sz, 4) then
			benchProp(propFolder, sx, sz, math.atan2(-nx, -nz))
			addPlaced(sx, sz, 3)
		end
	end
	for _, t in ipairs(TOWNS) do
		local _, p = nearX(t.road.P, t.cx - t.L * 0.42)
		local tx, tz = tangent(t.road.P, nearestOn(t.road.P, p.X, p.Y))
		local nx, nz = -tz, tx
		local sx, sz = p.X + nx * 19.5, p.Y + nz * 19.5
		if roadDistXZ(sx, sz) > 16 then
			local y = heightAt(sx, sz)
			part(propFolder, Vector3.new(0.28, 4.5, 0.28), CFrame.new(sx, y + 2.25, sz),
				Color3.fromRGB(76, 80, 84), E.Metal, nil, false)
			part(propFolder, Vector3.new(3.4, 0.9, 0.25), CFrame.new(sx, y + 4.4, sz),
				Color3.fromRGB(30, 64, 100), E.SmoothPlastic, nil, false).Name = "Bushaltestelle"
		end
	end
end

-- Wegweiser an den Hauptkreuzungen und Abzweigen
do
	local wp = Instance.new("Folder")
	wp.Name = "Wegweiser"
	wp.Parent = map
	local function postAtRoad(road, x, text)
		local ci, p = nearX(road.P, x)
		local tx, tz = tangent(road.P, ci)
		local nx, nz = -tz, tx
		local sx, sz = p.X + nx * 19.5, p.Y + nz * 19.5
		signBoard(wp, sx, sz, p.X, p.Y, 20, 3.0, text, Color3.fromRGB(250, 250, 246), Color3.fromRGB(20, 40, 80), Color3.fromRGB(70, 70, 72))
	end
	postAtRoad(TAL, -900, "◀ Westau · Seeburg      Mitteldorf ▶")
	postAtRoad(TAL, 250, "◀ Mitteldorf      Ostheim ▶")
	postAtRoad(TAL, -1750, "▼ See · Seeburg")
	postAtRoad(TAL, 1200, "▲ Bergrestaurant")
	postAtRoad(TAL, -2350, "◀ Tunnel West · Autobahn")
	postAtRoad(TAL, 2380, "Tunnel Ost · Autobahn ▶")
	postAtRoad(NOR, -250, "▲ Aussicht · Bergrestaurant")
end

----------------------------------------------------------------
-- 9. SEE-STEG
----------------------------------------------------------------
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
local treeFolder = Instance.new("Folder")
treeFolder.Name = "Wald"
treeFolder.Parent = map

-- v44: eigene Low-Poly-Tannen. Kein Template-Klonen, keine Zylinderkegel.
-- Stamm + vier versetzt gedrehte, nach oben kleiner werdende Nadel-Etagen.
local function buildFir(x, z, y, s, rot)
	local m = Instance.new("Model")
	m.Name = "Tanne"
	m.Parent = treeFolder
	local trunkH = 5.0 * s
	part(m, Vector3.new(1.15 * s, trunkH, 1.15 * s),
		CFrame.new(x, y + trunkH / 2, z),
		Color3.fromRGB(88, 60, 42), E.Wood, nil, false).Name = "Stamm"
	local baseY = y + 2.4 * s
	for i = 1, 4 do
		local w = (6.8 - i * 1.15) * s
		local hgt = 2.7 * s
		local yy = baseY + (i - 1) * 2.15 * s
		local shade = 0.82 + i * 0.045
		part(m, Vector3.new(w, hgt, w),
			CFrame.new(x, yy + hgt / 2, z) * CFrame.Angles(0, rot + i * math.pi / 4, 0),
			Color3.fromRGB(math.floor(36 * shade), math.floor(88 * shade), math.floor(52 * shade)),
			E.Grass, nil, false).Name = "Nadeletage"
	end
	part(m, Vector3.new(1.1 * s, 2.8 * s, 1.1 * s),
		CFrame.new(x, baseY + 3 * 2.15 * s + 1.3 * s, z),
		Color3.fromRGB(42, 100, 58), E.Grass, nil, false).Name = "Tannenspitze"
end

local TREE_COUNT = 3400
local placedTrees, attempts = 0, 0
while placedTrees < TREE_COUNT and attempts < TREE_COUNT * 26 do
	attempts = attempts + 1
	local x = (math.random() * 2 - 1) * (HALF - 80)
	local z = (math.random() * 2 - 1) * (HALF - 80)
	local ci = clamp(math.floor((x + HALF) / VOX) + 1, 1, NX)
	local ck = clamp(math.floor((z + HALF) / VOX) + 1, 1, NZ)
	local id = IDX(ci, ck)
	local h = H[ci][ck]
	local nearTown = false
	for _, t in ipairs(TOWNS) do
		if (t.cx - x) ^ 2 + (t.cz - z) ^ 2 < 205 * 205 then nearTown = true; break end
	end
	if (x - 1550) ^ 2 + (z + 620) ^ 2 < 110 * 110 then nearTown = true end
	local forest = nz(x / 380, z / 380, 60) + nz(x / 120, z / 120, 61) * 0.5
	local dr = fRoadD[id]
	local ok = (not nearTown) and forest > 0.08 and h > WL + 3 and h < 265
		and MAT[ci][ck] == E.Grass and not bridgeZone[id] and farFrom(x, z, 4)
	if ok and dr and dr < (fRoadH[id] + 11) ^ 2 then ok = false end
	if ok then
		buildFir(x, z, h - 0.5, 0.82 + math.random() * 0.75, math.random() * 6.28)
		placedTrees = placedTrees + 1
	end
	if attempts % 500 == 0 then task.wait() end
end
print(("[v44] %d Tannen"):format(placedTrees))

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

print(("[v44] FERTIG in %.0f s | %d Teile | %d Baeume | %d Doerfer | %d Strassen | %d Kreuzungen"):format(
	os.clock() - T0, partCount, placedTrees, #TOWNS, #NET, #JUN))
