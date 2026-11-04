--[[
	SCHWEIZER MAP GENERATOR  (5000 x 5000 Studs) - VERSION 12
	Flaches Grundgelaende, felsige Berge rund um die Map und ein durchgehendes Strassennetz.

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
local SIZE = 5000            -- Mapgroesse in Studs
local HALF = SIZE / 2
local VOX = 4                -- Terrain-Aufloesung (4 = Roblox Standard)
local N = SIZE / VOX         -- 500 Zellen pro Seite
local BASEY = -32            -- unterste Terrain-Hoehe
local NY = 104               -- Anzahl Voxel in der Hoehe (oben = 384)
local WL = 4                 -- Wasserspiegel (See)
local ROAD_HALF = 28          -- halbe Strassenbreite
local BLEND = 40             -- Breite der Boeschung neben der Strasse
local TREE_COUNT = 0        -- keine Baeume in dieser Grundversion
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
	-- Flaches Grundgelaende; die Berge bleiben als Ring rund um die ganze Map.
	local flat = 34
	local r = (1 - math.abs(nz(x / 330, z / 330, 3))) ^ 2 * 0.75
		+ (1 - math.abs(nz(x / 150, z / 150, 4))) ^ 2 * 0.25
	local edge = sstep(1400, 2475, math.max(math.abs(x), math.abs(z)))
	-- Breiterer, massiverer Bergkranz, der weiter ins Karteninnere reicht.
	local mountains = 125 + r * 255 + nz(x / 58, z / 58, 5) * 18
	local h = lerp(flat, mountains, edge)
	if h > 280 then h = 280 + (h - 280) * 0.35 end
	return math.min(h, 376)
end

local function terrainH(x, z)
	return baseHeight(x, z)
end

----------------------------------------------------------------
-- STRASSEN
----------------------------------------------------------------
local MAP_SCALE = 2.5
local V2 = function(x, z) return Vector2.new(x * MAP_SCALE, z * MAP_SCALE) end
-- Organisches Strassennetz: mehrere verbundene Routen und Abzweigungen,
-- aber KEIN geschlossener Aussenring. Die festen Knoten sorgen dafuer,
-- dass jede Nebenstrasse an eine andere Strasse angeschlossen ist.
local ROADS = {
 {name="Westliche Hauptachse",pts={V2(-820,-260),V2(-650,-220),V2(-470,-285),V2(-300,-190),V2(-165,-75),V2(-78,0)}},
 {name="Oestliche Hauptachse",pts={V2(78,0),V2(220,105),V2(390,155),V2(570,95),V2(820,175)}},
 {name="Nordroute",pts={V2(-120,-820),V2(-90,-630),V2(-155,-440),V2(-80,-250),V2(0,-78)}},
 {name="Suedroute",pts={V2(78,0),V2(160,190),V2(120,370),V2(245,540),V2(300,820)}},
 {name="Nordwest-Verbindung",pts={V2(-650,-220),V2(-590,-410),V2(-430,-540),V2(-300,-690)}},
 {name="West-Sued-Verbindung",pts={V2(-470,-285),V2(-520,-80),V2(-470,120),V2(-560,330),V2(-690,520)}},
 {name="Mittlere Querstrasse",pts={V2(-470,120),V2(-260,190),V2(-70,270),V2(145,350),V2(390,420)}},
 {name="Ost-Abzweigung",pts={V2(390,155),V2(510,310),V2(680,390),V2(820,540)}},
 {name="Nordost-Verbindung",pts={V2(-155,-440),V2(50,-500),V2(260,-450),V2(450,-520),V2(650,-650)}},
 {name="Suedliche Verbindung",pts={V2(-560,330),V2(-360,470),V2(-160,540),V2(40,620),V2(300,820)}},
}
-- Runder Kreisel: viele Segmente statt eines sichtbaren Vielecks.
local circlePts={}
for i=0,144 do
 local angle=i/144*math.pi*2
 table.insert(circlePts,V2(math.cos(angle)*78,math.sin(angle)*78))
end
table.insert(ROADS,{name="Kreisel",pts=circlePts,noSpline=true,roundabout=true})

local function spline(pts)
 local out,n={},#pts
 for i=1,n-1 do
  local p0=pts[math.max(i-1,1)]
  local p1,p2=pts[i],pts[i+1]
  local p3=pts[math.min(i+2,n)]
  local steps=math.max(2,math.ceil((p2-p1).Magnitude/6))
  for j=0,steps-1 do
   local t=j/steps
   local pt=0.5*((2*p1)+(p2-p0)*t+(2*p0-5*p1+4*p2-p3)*t*t+(3*p1-p0-3*p2+p3)*t*t*t)
   table.insert(out,pt)
  end
 end
 table.insert(out,pts[n])
 return out
end
local CELL=128
local hash={}
local function addPoint(x,z,h)
 local cx=math.floor((x+3000)/CELL)
 local cz=math.floor((z+3000)/CELL)
 local k=cx*128+cz
 local t=hash[k]
 if not t then t={};hash[k]=t end
 t[#t+1]={x,z,h}
end
for _,def in ipairs(ROADS) do
 local P=def.noSpline and def.pts or spline(def.pts)
 local hs={}
 for i,p in ipairs(P) do hs[i]=terrainH(p.X,p.Y) end
 for _=1,10 do
  local new={}
  for i=1,#P do
   local sum,count=0,0
   for j=math.max(1,i-6),math.min(#P,i+6) do sum+=hs[j];count+=1 end
   new[i]=sum/count
  end
  hs=new
 end
 def.heights = hs
 for i,p in ipairs(P) do addPoint(p.X,p.Y,hs[i]) end
end

local function roadQuery(x, z)
	local cx = math.floor((x + 3000) / CELL)
	local cz = math.floor((z + 3000) / CELL)
	local best = math.huge
	for a = cx - 1, cx + 1 do
		for b = cz - 1, cz + 1 do
			local t = hash[a * 128 + b]
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
			local t = hash[a * 128 + b]
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
			-- Die sichtbare Fahrbahn wird als glattes Part ueber dem Terrain gebaut.
			-- Kein Asphalt-Terrain darunter: verhindert verwaschene Textur/Z-Fighting.
			m = E.Ground
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
				if h < 70 and f > 0.35 then m = E.Ground
				else m = E.Ground end
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
local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
clouds.Cover = 0.55; clouds.Density = 0.35; clouds.Color = Color3.fromRGB(245,245,250); clouds.Parent = terrain
local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
atm.Density = 0
atm.Offset = 0
atm.Color = Color3.fromRGB(255, 255, 255)
atm.Decay = Color3.fromRGB(255, 255, 255)
atm.Glare = 0
atm.Haze = 0
Lighting.FogStart = 0
Lighting.FogEnd = 100000


----------------------------------------------------------------
-- NUR STRASSEN UND KREUZUNG
-- Fahrbahn folgt der geglaetteten Gelaendehoehe und liegt nur minimal darueber.
----------------------------------------------------------------
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

local ROAD_LIFT=0.42
local function nearJunction(p)
 local nodes={
  V2(-650,-220),V2(-470,-285),V2(-470,120),V2(-560,330),
  V2(-155,-440),V2(390,155),V2(78,0),V2(-78,0),
  V2(390,420),V2(300,820),V2(0,-78)
 }
 for _,n in ipairs(nodes) do if (p-n).Magnitude<62 then return true end end
 return false
end
for _,def in ipairs(ROADS) do
 local P=def.noSpline and def.pts or spline(def.pts)
 local cumulative={0}
 for i=2,#P do cumulative[i]=cumulative[i-1]+(P[i]-P[i-1]).Magnitude end
 local total=cumulative[#cumulative]
 for i=1,#P-1 do
  local p1,p2=P[i],P[i+1]
  local mid=(p1+p2)/2
  local heights=def.heights or {}
  local y1=(heights[i] or terrainH(p1.X,p1.Y))+ROAD_LIFT
  local y2=(heights[i+1] or terrainH(p2.X,p2.Y))+ROAD_LIFT
  local midY=(y1+y2)/2
  local road=part(map,Vector3.new(ROAD_HALF*2,0.8,(p2-p1).Magnitude+1),
   CFrame.lookAt(Vector3.new(mid.X,midY,mid.Y),Vector3.new(p2.X,y2,p2.Y)),
   Color3.fromRGB(48,50,54),E.Asphalt)
  road.CanCollide=true
 end
 if not def.roundabout then
  local function pointAt(distance)
   local idx=1
   while idx<#cumulative and cumulative[idx+1]<distance do idx+=1 end
   local seg=math.max(0.001,cumulative[idx+1]-cumulative[idx])
   local t=math.clamp((distance-cumulative[idx])/seg,0,1)
   return P[idx]:Lerp(P[idx+1],t),(P[idx+1]-P[idx]).Unit
  end
  -- Einheitlicher Abstand entlang der tatsaechlichen Kurvenlaenge.
  for d=30,total-10,90 do
   local p,tangent=pointAt(d)
   if not nearJunction(p) then
    local y=(def.heights and def.heights[math.min(#def.heights, math.max(1, math.floor(d/6)+1))] or terrainH(p.X,p.Y))+ROAD_LIFT+0.51
    local cf=CFrame.lookAt(Vector3.new(p.X,y,p.Y),Vector3.new(p.X+tangent.X,y,p.Y+tangent.Y))
    local stripe=part(map,Vector3.new(1.8,0.16,20),cf,Color3.fromRGB(245,235,205),E.SmoothPlastic)
    stripe.CanCollide=false
   end
  end
 end
end
-- Kreiselinsel rund und glatt, passend zur kreisfoermigen Fahrbahn.
local islandBase=terrainH(0,0)+ROAD_LIFT+0.4
local island=part(map,Vector3.new(92,3,92),CFrame.new(0,islandBase+1.5,0)*CFrame.Angles(0,0,math.rad(90)),
 Color3.fromRGB(74,125,61),E.Grass,Enum.PartType.Cylinder)
island.CanCollide=true
local islandTop=part(map,Vector3.new(74,0.5,74),CFrame.new(0,islandBase+3.25,0)*CFrame.Angles(0,0,math.rad(90)),
 Color3.fromRGB(88,145,69),E.Grass,Enum.PartType.Cylinder)
islandTop.CanCollide=true

print("[Swiss Map] Fertig: 5000x5000 Map, angepasste Strassenhoehen, klare Fernsicht und runder Kreisel.")
