--[[
	SCHWEIZER MAP GENERATOR  (6000 x 4480 Studs) - VERSION 26
	Flaches Grundgelaende, felsige Berge rund um die Map und ein geordnetes Talnetz mit einer Hauptachse und zwei Kreiseln.

	BENUTZUNG (in Roblox Studio, NICHT im Play-Modus):
	1. Neues leeres Baseplate-Place oeffnen (Baseplate kannst du loeschen)
	2. View -> Command Bar  (oder Script als "Local Plugin" speichern)
	3. Ganzen Code einfuegen + Enter. Je nach PC kann die Erzeugung mehrere Minuten dauern; Output zeigt den Fortschritt.
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
local SIZE_X = 6000          -- Kartenlaenge in X-Richtung
local SIZE_Z = 4480          -- Kartenbreite in Z-Richtung
local HALF_X = SIZE_X / 2
local HALF_Z = SIZE_Z / 2
local SIZE = SIZE_X
local HALF = HALF_X
local VOX = 4                -- Terrain-Aufloesung (4 = Roblox Standard)
local NX = SIZE_X / VOX
local NZ = SIZE_Z / VOX
local N = NX                 -- X-Zellen; Z wird separat mit NZ verarbeitet
local BASEY = -32            -- unterste Terrain-Hoehe
local NY = 180               -- vertikaler Bereich fuer die natuerlichen Bergketten
local WL = 4                 -- Wasserspiegel (See)
local ROAD_HALF = 12        -- halbe Strassenbreite: 21 Studs insgesamt
local BLEND = 8             -- schmale, sanfte Boeschung neben der Strasse
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
	-- Flaches Mittelland: keine zufaelligen Huegel unter den Strassen.
	local interior = 18

	-- Berge bleiben in einem schmalen Streifen am Kartenrand.
	-- Die hoechsten Bereiche liegen nahe am Rand; nach innen fallen sie rasch ab.
	local edgeDistance = math.min(HALF_X - math.abs(x), HALF_Z - math.abs(z))
	local ridgeWobble = nz(x / 330, z / 330, 12) * 65
	local d = edgeDistance + ridgeWobble
	local mountainBlend = 1 - sstep(430, 760, d)

	-- Unregelmaessige Gipfel und Paesse, aber keine breite Bergwand.
	local ridgeNoise = nz(x / 260, z / 260, 23)
	local peakNoise = 1 - math.abs(nz(x / 135, z / 135, 24))
	local detail = nz(x / 48, z / 48, 25) * 14
	local passNoise = math.abs(nz(x / 510, z / 510, 26))
	local mountainHeight = 205 + ridgeNoise * 85 + peakNoise * 145 + detail - passNoise * 65

	local h = lerp(interior, mountainHeight, mountainBlend)
	return clamp(h, 18, 520)
end

local function terrainH(x, z)
	return baseHeight(x, z)
end

----------------------------------------------------------------
-- STRASSEN
----------------------------------------------------------------
local MAP_SCALE = 1.0
local V2 = function(x, z) return Vector2.new(x * MAP_SCALE, z * MAP_SCALE) end

-- STRASSENKONZEPT:
-- Alle Strassen bleiben im flachen inneren Tal und halten grossen Abstand
-- zum Bergguertel. Keine Strasse fuehrt in die Berge oder bis an den Kartenrand.
-- Eine West-Ost-Hauptachse mit zwei Kreiseln und vier Tal-Zubringern.
local ROADS = {}
local function addRoad(name, pts)
 table.insert(ROADS, {name=name, pts=pts})
end

-- Hauptachse: nur im inneren Tal, mit Anschluss an die beiden Kreisel.
addRoad("Hauptstrasse West", {
 V2(-1800,0), V2(-1500,-8), V2(-1200,8), V2(-728,0)
})
addRoad("Hauptstrasse Mitte", {
 V2(-572,0), V2(-350,8), V2(-120,0), V2(120,0), V2(350,-8), V2(572,0)
})
addRoad("Hauptstrasse Ost", {
 V2(728,0), V2(1200,-8), V2(1500,8), V2(1800,0)
})

-- Vier Zubringer verlaufen ebenfalls ausschliesslich im flachen Tal.
addRoad("Nordwest-Zubringer", {
 V2(-650,-900), V2(-665,-700), V2(-635,-430), V2(-650,-78)
})
addRoad("Suedwest-Zubringer", {
 V2(-650,900), V2(-635,700), V2(-665,430), V2(-650,78)
})
addRoad("Nordost-Zubringer", {
 V2(650,-900), V2(635,-700), V2(665,-430), V2(650,-78)
})
addRoad("Suedost-Zubringer", {
 V2(650,900), V2(665,700), V2(635,430), V2(650,78)
})

-- Zwei Kreisel innerhalb des Talbereichs.
local ROUNDABOUTS = {
 {center=V2(-650,0), radius=78},
 {center=V2(650,0), radius=78},
}
for index, rb in ipairs(ROUNDABOUTS) do
 local pts = {}
 for i=0,144 do
  local a = i/144 * math.pi*2
  table.insert(pts, rb.center + Vector2.new(math.cos(a)*rb.radius, math.sin(a)*rb.radius))
 end
 table.insert(ROADS, {name="Kreisel "..index, pts=pts, noSpline=true, roundabout=true, center=rb.center})
end

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
for i = 1, NX do
	local Hi, Ri = {}, {}
	local x = -HALF_X + (i - 0.5) * VOX
	for k = 1, NZ do
		local z = -HALF_Z + (k - 0.5) * VOX
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
for i = 1, NX do
	local Mi = {}
	local x = -HALF_X + (i - 0.5) * VOX
	for k = 1, NZ do
		local z = -HALF_Z + (k - 0.5) * VOX
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
				math.abs(H[math.min(i + 1, NX)][k] - H[math.max(i - 1, 1)][k]),
				math.abs(H[i][math.min(k + 1, NZ)] - H[i][math.max(k - 1, 1)])) / 8
			local edgeDistance = math.min(HALF_X - math.abs(x), HALF_Z - math.abs(z))
			local mountainEdge = 1 - sstep(120, 820, edgeDistance + nz(x / 230, z / 230, 12) * 85)
			local snow = 430 + nz(x / 90, z / 90, 7) * 35
			-- Ab dem Berguebergang kein Gras mehr: Fels, in hohen Lagen Schnee.
			if mountainEdge > 0.18 and h > snow then
				m = E.Snow
			elseif mountainEdge > 0.12 then
				m = E.Rock
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
-- TERRAIN SCHREIBEN (in kleinen 80x80-Stud-Bloecken)
----------------------------------------------------------------
local CH = 20                 -- 80x80 Studs; alle Region-Grenzen liegen exakt auf dem 4er-Voxelraster
local AIR = E.Air
local wlv = math.floor((WL - BASEY) / VOX)

for ci = 0, NX / CH - 1 do
	for ck = 0, NZ / CH - 1 do
		local maxH = WL
		for a = 1, CH do
			for zc = 1, CH do
				maxH = math.max(maxH, H[ci * CH + a][ck * CH + zc])
			end
		end
		-- Nur bis zur hoechsten Stelle dieses Abschnitts schreiben, nicht pauschal bis 688 Studs.
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
			for zc = 1, CH do
				local i, k = ci * CH + a, ck * CH + zc
				local h, surf = H[i][k], MAT[i][k]
				local deep = (h > 110) and E.Rock or E.Ground
				local top = clamp((h - BASEY) / VOX, 0, localNY - 1)
				local full = math.floor(top)
				local frac = top - full
				local ma, oa = mats[a], occs[a]
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
	print(("[Swiss Map] Terrain %d%%"):format(math.floor((ci + 1) / (NX / CH) * 100)))
end

----------------------------------------------------------------
-- STIL: Farben, Wasser, Nebel, Licht
----------------------------------------------------------------
pcall(function()
	terrain:SetMaterialColor(E.Grass, Color3.fromRGB(78, 130, 62))
	terrain:SetMaterialColor(E.LeafyGrass, Color3.fromRGB(98, 150, 70))
	terrain:SetMaterialColor(E.Rock, Color3.fromRGB(112, 114, 120))
	terrain:SetMaterialColor(E.Ground, Color3.fromRGB(92, 112, 72))
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
-- Fahrbahn folgt der geglaetteten Gelaendehoehe und liegt sichtbar leicht ueber dem Terrain.
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

local ROAD_LIFT=1.25
local function nearJunction(p)
 for _,rb in ipairs(ROUNDABOUTS) do
  if (p-rb.center).Magnitude < 125 then return true end
 end
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
  local road=part(map,Vector3.new(ROAD_HALF*2,1,(p2-p1).Magnitude+1),
   CFrame.lookAt(Vector3.new(mid.X,midY,mid.Y),Vector3.new(p2.X,y2,p2.Y)),
   Color3.fromRGB(65,66,68),E.Asphalt)
  road.CanCollide=true
 end
 if not def.roundabout then
  local function pointAt(distance)
   local idx=1
   while idx<#cumulative and cumulative[idx+1]<distance do idx+=1 end
   local seg=math.max(0.001,cumulative[idx+1]-cumulative[idx])
   local t=math.clamp((distance-cumulative[idx])/seg,0,1)
   return P[idx]:Lerp(P[idx+1],t),(P[idx+1]-P[idx]).Unit,((def.heights and def.heights[idx] or terrainH(P[idx].X,P[idx].Y))*(1-t)+(def.heights and def.heights[idx+1] or terrainH(P[idx+1].X,P[idx+1].Y))*t)
  end
  -- Einheitlicher Abstand entlang der tatsaechlichen Kurvenlaenge.
  for d=30,total-10,52 do
   local p,tangent,pathY=pointAt(d)
   if not nearJunction(p) then
    local y=pathY+ROAD_LIFT+0.58
    local cf=CFrame.lookAt(Vector3.new(p.X,y,p.Y),Vector3.new(p.X+tangent.X,y,p.Y+tangent.Y))
    local stripe=part(map,Vector3.new(1.2,0.14,12),cf,Color3.fromRGB(245,235,205),E.SmoothPlastic)
    stripe.CanCollide=false
   end
  end
 end
end
-- Eine passende Mittelinsel fuer jeden der beiden Kreisel.
for _,rb in ipairs(ROUNDABOUTS) do
 local cx, cz = rb.center.X, rb.center.Y
 local islandBase = terrainH(cx,cz) + ROAD_LIFT + 0.4
 local island = part(map, Vector3.new(54,3,54),
  CFrame.new(cx,islandBase+1.5,cz)*CFrame.Angles(0,0,math.rad(90)),
  Color3.fromRGB(74,125,61),E.Grass,Enum.PartType.Cylinder)
 island.CanCollide = true
 local islandTop = part(map, Vector3.new(42,0.5,42),
  CFrame.new(cx,islandBase+3.25,cz)*CFrame.Angles(0,0,math.rad(90)),
  Color3.fromRGB(88,145,69),E.Grass,Enum.PartType.Cylinder)
 islandTop.CanCollide = true
end

print("[Swiss Map] Fertig: 6000x4480 Map, flaches Innenland, schmaler Bergguertel und Strassen nur im inneren Tal.")
