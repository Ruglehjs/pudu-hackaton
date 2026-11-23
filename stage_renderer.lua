-- stage_renderer.lua
-- Overworld isometric diagonal (NE / up-right) renderer, 3D irregular terrain,
-- calm room-snapped camera, biome landmarks/decor (Modo A & Modo B seamless),
-- diagonal minimap, JRPG battle transition, and clean battle placeholder stage.
-- LÖVE2D 11.5 (LuaJIT) — Zero Unicode tofu (R2), zero per-frame GPU allocations.

local StageRenderer = {}
StageRenderer.__index = StageRenderer

local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local min = math.min
local max = math.max
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt
local pi = math.pi

--------------------------------------------------------------------------------
-- 1. Canonical Constants & World Geometry
--------------------------------------------------------------------------------

StageRenderer.ISO_UX = 62.0
StageRenderer.ISO_UY = -31.0
StageRenderer.ISO_VX = 62.0
StageRenderer.ISO_VY = 31.0
StageRenderer.ELEV_PX = 26.0

StageRenderer.ROOM_SPACING = 14.0
StageRenderer.WORLD_U_MIN = -2.0
StageRenderer.WORLD_U_MAX = 118.0
StageRenderer.STEP = 1.5

-- 6 explorable side alcoves distributed across all 4 biomes, each reachable from main path.
StageRenderer.SIDE_ALCOVES = {
    { id = "bosque_rewe",      name = "Claro del Rewe",       biome = "bosque",   u = 16.0,  v = 6.4,  r = 2.6, prop = "rewe_totem" },
    { id = "bosque_orbe",      name = "Santuario del Orbe",   biome = "bosque",   u = 24.0,  v = 3.5,  r = 2.5, prop = "orb_shrine" },
    { id = "atacama_mirador",  name = "Mirador del Sol",      biome = "desierto", u = 43.5,  v = 2.8,  r = 2.6, prop = "apacheta_sundial" },
    { id = "atacama_cristal",  name = "Gruta de Cristales",   biome = "desierto", u = 54.0,  v = -2.9, r = 2.6, prop = "mountain_crystal" },
    { id = "costa_mirador",    name = "Mirador de la Costa",  biome = "costa",    u = 85.8,  v = -4.3, r = 2.5, prop = "pincoya_shrine" },
    { id = "ciudad_plazoleta", name = "Plazoleta Civica",     biome = "ciudad",   u = 103.5, v = -1.4, r = 2.6, prop = "stone_pedestal" },
}

-- Wizard hat head-anchor offsets (in 64x64 sprite pixels relative to bottom-center foot anchor)
-- Rows: 0=S, 1=SE, 2=E, 3=NE, 4=N, 5=NW, 6=W, 7=SW
StageRenderer.HAT_HEAD_OFFSETS = {
    [0] = { x = 0.0,  y = -38.0 },
    [1] = { x = 5.0,  y = -38.0 },
    [2] = { x = 8.5,  y = -39.0 },
    [3] = { x = 5.0,  y = -39.0 },
    [4] = { x = 0.0,  y = -39.0 },
    [5] = { x = -5.0, y = -39.0 },
    [6] = { x = -8.5, y = -39.0 },
    [7] = { x = -5.0, y = -38.0 },
}

-- Biome visual palette & tile mapping (used for 3D skirts, minimap, and Modo B fallback)
StageRenderer.BIOME_VISUALS = {
    bosque = {
        id = "bosque",
        name = "Bosque y Plaza Valdiviana",
        floorTile = "grass_floor",
        pathTile = "stone_floor",
        cliffTile = "grass_floor",
        backdrop = { 0.14, 0.27, 0.17 },
        groundTint = { 0.96, 1.00, 0.94 },
        pathTint = { 0.98, 0.94, 0.82 },
        alcoveTint = { 0.84, 0.96, 0.82 },
        cliffTopTint = { 0.86, 0.96, 0.82 },
        cliffLeft = { 0.31, 0.36, 0.25 },
        cliffRight = { 0.19, 0.23, 0.18 },
        cliffLip = { 0.48, 0.72, 0.34 },
        cliffBand = { 0.28, 0.52, 0.23 },
        miniCol = { 0.24, 0.58, 0.31 },
        hazeCol = { 0.76, 0.92, 0.78 },
    },
    desierto = {
        id = "desierto",
        name = "Desierto de Atacama",
        floorTile = "desert_floor",
        pathTile = "stone_floor",
        cliffTile = "desert_floor",
        backdrop = { 0.56, 0.33, 0.18 },
        groundTint = { 1.00, 0.92, 0.82 },
        plateauTint = { 0.98, 0.72, 0.50 },
        pathTint = { 1.00, 0.89, 0.70 },
        alcoveTint = { 0.98, 0.86, 0.64 },
        cliffTopTint = { 0.94, 0.66, 0.44 },
        cliffLeft = { 0.74, 0.38, 0.22 },
        cliffRight = { 0.50, 0.23, 0.14 },
        cliffLip = { 0.98, 0.72, 0.44 },
        cliffBand = { 0.86, 0.50, 0.28 },
        miniCol = { 0.84, 0.54, 0.26 },
        hazeCol = { 1.00, 0.82, 0.52 },
    },
    costa = {
        id = "costa",
        name = "Costa y Muelle de Valparaíso",
        floorTile = "coast_floor",
        pathTile = "stone_floor",
        cliffTile = "coast_floor",
        backdrop = { 0.11, 0.36, 0.54 },
        groundTint = { 1.00, 0.98, 0.92 },
        pathTint = { 0.90, 0.92, 0.96 },
        alcoveTint = { 0.84, 0.96, 0.96 },
        cliffTopTint = { 0.88, 0.88, 0.84 },
        cliffLeft = { 0.46, 0.49, 0.54 },
        cliffRight = { 0.30, 0.33, 0.40 },
        cliffLip = { 0.78, 0.76, 0.64 },
        cliffBand = { 0.66, 0.76, 0.82 },
        miniCol = { 0.20, 0.60, 0.78 },
        hazeCol = { 0.82, 0.94, 0.98 },
    },
    ciudad = {
        id = "ciudad",
        name = "Ciudad y Gran Oficina",
        floorTile = "stone_floor",
        pathTile = "stone_floor",
        cliffTile = "mountain_floor",
        backdrop = { 0.18, 0.20, 0.29 },
        groundTint = { 0.86, 0.88, 0.96 },
        pathTint = { 0.98, 0.98, 1.00 },
        alcoveTint = { 0.94, 0.90, 1.00 },
        cliffTopTint = { 0.78, 0.80, 0.90 },
        cliffLeft = { 0.44, 0.47, 0.58 },
        cliffRight = { 0.27, 0.30, 0.40 },
        cliffLip = { 0.80, 0.84, 0.94 },
        cliffBand = { 0.64, 0.68, 0.80 },
        miniCol = { 0.56, 0.46, 0.78 },
        hazeCol = { 0.92, 0.80, 0.68 },
    },
}

-- Default sky palettes when theme is omitted or partial (supports both biome IDs and 8 stage kinds)
local DEFAULT_SKY_THEMES = {
    bosque = {
        skyTop = { 0.16, 0.44, 0.72 },
        skyBot = { 0.58, 0.84, 0.86 },
        horizonGlow = { 0.86, 0.95, 0.78 },
        sunColor = { 1.00, 0.95, 0.76 },
        groundA = { 0.26, 0.52, 0.27 },
        groundB = { 0.18, 0.40, 0.21 },
        accentColor = { 0.94, 0.76, 0.28 },
    },
    desierto = {
        skyTop = { 0.18, 0.42, 0.80 },
        skyBot = { 0.93, 0.73, 0.54 },
        horizonGlow = { 1.00, 0.82, 0.48 },
        sunColor = { 1.00, 0.92, 0.72 },
        groundA = { 0.82, 0.56, 0.32 },
        groundB = { 0.68, 0.44, 0.24 },
        accentColor = { 0.36, 0.84, 0.92 },
    },
    costa = {
        skyTop = { 0.16, 0.48, 0.82 },
        skyBot = { 0.62, 0.86, 0.96 },
        horizonGlow = { 0.84, 0.95, 0.98 },
        sunColor = { 1.00, 0.96, 0.86 },
        groundA = { 0.24, 0.54, 0.68 },
        groundB = { 0.16, 0.42, 0.56 },
        accentColor = { 0.28, 0.82, 0.92 },
    },
    ciudad = {
        skyTop = { 0.14, 0.20, 0.42 },
        skyBot = { 0.58, 0.50, 0.66 },
        horizonGlow = { 0.96, 0.76, 0.56 },
        sunColor = { 1.00, 0.88, 0.70 },
        groundA = { 0.36, 0.38, 0.46 },
        groundB = { 0.26, 0.28, 0.36 },
        accentColor = { 0.94, 0.78, 0.32 },
    },
}

local STAGE_TO_BIOME = {
    plaza = "bosque",
    bosque = "bosque",
    mirador = "desierto",
    vereda = "desierto",
    muelle = "costa",
    pantano = "costa",
    esquina = "ciudad",
    oficina = "ciudad",
    desierto = "desierto",
    costa = "costa",
    ciudad = "ciudad",
}

local VALPARAISO_HOUSE_COLS = {
    { 0.82, 0.36, 0.32 },
    { 0.90, 0.72, 0.28 },
    { 0.30, 0.64, 0.76 },
    { 0.68, 0.44, 0.72 },
}

local ARAUCARIA_TIERS = {
    { y = -46, rx = 28, ry = 8,  col = { 0.13, 0.34, 0.20 } },
    { y = -64, rx = 36, ry = 10, col = { 0.16, 0.42, 0.24 } },
    { y = -78, rx = 30, ry = 9,  col = { 0.22, 0.52, 0.28 } },
}

local MINIMAP_BIOME_BANDS = {
    { u0 = 0,  u1 = 40,  col = StageRenderer.BIOME_VISUALS.bosque.miniCol },
    { u0 = 40, u1 = 66,  col = StageRenderer.BIOME_VISUALS.desierto.miniCol },
    { u0 = 66, u1 = 92,  col = StageRenderer.BIOME_VISUALS.costa.miniCol },
    { u0 = 92, u1 = 118, col = StageRenderer.BIOME_VISUALS.ciudad.miniCol },
}

-- Seeded with canonical 9 encounters so walkability works even before setEncounters() is called.
local _encounterAnchors = {
    { id = "nino_helado",      u = 10.0,  v = 0.2 },
    { id = "mimo_muro",        u = 22.0,  v = -2.0 },
    { id = "puma_dramatico",   u = 34.0,  v = 1.6 },
    { id = "turista_selfie",   u = 48.0,  v = -1.2 },
    { id = "gato_guaton",      u = 60.0,  v = 1.8 },
    { id = "gaviota_mafiosa",  u = 74.0,  v = -1.4 },
    { id = "piscina_barro",    u = 86.0,  v = 1.2 },
    { id = "semaforo_rebelde", u = 99.0,  v = -0.8 },
    { id = "fila_tramite",     u = 112.0, v = 0.4 },
}

--------------------------------------------------------------------------------
-- 2. Math & Deterministic Helpers
--------------------------------------------------------------------------------

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

local function smoothstep(a, b, x)
    if b <= a then
        return x >= b and 1.0 or 0.0
    end
    local t = (x - a) / (b - a)
    if t <= 0.0 then return 0.0 end
    if t >= 1.0 then return 1.0 end
    return t * t * (3.0 - 2.0 * t)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function hash2d(x, y)
    local h = sin(x * 127.1 + y * 311.7) * 43758.5453123
    return h - floor(h)
end

local function makeFallbackFont()
    return love.graphics.getFont()
end

--------------------------------------------------------------------------------
-- 3. Static Terrain, Elevation, Walkability & Projection Functions
--------------------------------------------------------------------------------

function StageRenderer.pathCenterV(u)
    return sin(u * 0.14) * 2.4 + cos(u * 0.07) * 1.1
end

function StageRenderer.getBiomeAt(u)
    if u < 40.0 then
        return "bosque"
    elseif u < 66.0 then
        return "desierto"
    elseif u < 92.0 then
        return "costa"
    else
        return "ciudad"
    end
end

function StageRenderer.setEncounters(encountersList)
    if type(encountersList) ~= "table" or #encountersList == 0 then
        return
    end
    local anchors = {}
    for i = 1, #encountersList do
        local e = encountersList[i]
        if type(e) == "table" and type(e.u) == "number" and type(e.v) == "number" then
            anchors[#anchors + 1] = {
                id = e.id or ("enc_" .. tostring(i)),
                u = e.u,
                v = e.v,
                pc = StageRenderer.pathCenterV(e.u),
            }
        end
    end
    if #anchors > 0 then
        _encounterAnchors = anchors
    end
end

-- Ensure precomputed pc on initial seed anchors
for i = 1, #_encounterAnchors do
    _encounterAnchors[i].pc = StageRenderer.pathCenterV(_encounterAnchors[i].u)
end

function StageRenderer.isBosqueBridge(u, v)
    if u < 26.3 or u > 31.1 then
        return false
    end
    local pc = StageRenderer.pathCenterV(u)
    return abs(v - pc) <= 2.45
end

function StageRenderer.isCostaPier(u, v)
    if u < 67.0 or u > 83.0 then
        return false
    end
    local pc = StageRenderer.pathCenterV(u)
    if abs(v - pc) <= 2.55 then
        return true
    end
    -- Widened wharf platform around Gaviota Mafiosa (u=74.0, v=-1.4) so it stands cleanly on pier deck.
    if u >= 70.6 and u <= 77.4 then
        local du = u - 74.0
        local dv = v - (-1.4)
        if abs(dv) <= 3.35 and (du * du * 0.72 + dv * dv) <= 13.0 then
            return true
        end
    end
    return false
end

-- Returns:
--   flatMask  [0..1]: 1.0 inside encounter clearing or connecting lane (flattens cliffs)
--   inDisk    (bool): inside encounter circular clearing
--   inLane    (bool): inside connecting branch lane from pathCenterV(enc.u) to (enc.u, enc.v)
local function evalEncounterMask(u, v)
    local bestMask = 0.0
    local inDisk = false
    local inLane = false

    for i = 1, #_encounterAnchors do
        local enc = _encounterAnchors[i]
        local du = u - enc.u
        if abs(du) <= 4.8 then
            local ev = enc.v
            local pcE = enc.pc or StageRenderer.pathCenterV(enc.u)
            local dv = v - ev
            local dEnc = sqrt(du * du + dv * dv)

            if dEnc <= 2.9 then
                inDisk = true
                bestMask = 1.0
            elseif dEnc < 4.5 then
                local m = 1.0 - smoothstep(2.9, 4.5, dEnc)
                if m > bestMask then bestMask = m end
            end

            -- Connecting lane segment from (enc.u, pcE) to (enc.u, ev)
            local vLo = min(pcE, ev)
            local vHi = max(pcE, ev)
            local clampedV = clamp(v, vLo, vHi)
            local dLane = sqrt(du * du + (v - clampedV) * (v - clampedV))
            if dLane <= 2.0 then
                inLane = true
                bestMask = 1.0
            elseif dLane < 3.4 then
                local m = 1.0 - smoothstep(2.0, 3.4, dLane)
                if m > bestMask then bestMask = m end
            end
        end
    end

    return bestMask, inDisk, inLane
end

-- Returns:
--   alcMask   [0..1]: 1.0 inside side alcove or its connecting branch
--   inAlcove  (bool): strictly inside alcove walkable footprint
local function evalAlcoveMask(u, v)
    local bestMask = 0.0
    local inAlcove = false
    local alcoves = StageRenderer.SIDE_ALCOVES

    for i = 1, #alcoves do
        local alc = alcoves[i]
        local du = u - alc.u
        if abs(du) <= (alc.r + 2.2) then
            local dv = v - alc.v
            local dAlc = sqrt(du * du + dv * dv)
            local pcA = StageRenderer.pathCenterV(alc.u)
            local vLo = min(pcA, alc.v)
            local vHi = max(pcA, alc.v)
            local clampedV = clamp(v, vLo, vHi)
            local dLane = sqrt(du * du + (v - clampedV) * (v - clampedV))

            if dAlc <= alc.r or dLane <= 1.7 then
                inAlcove = true
                bestMask = 1.0
            else
                local m1 = 1.0 - smoothstep(alc.r, alc.r + 1.6, dAlc)
                local m2 = 1.0 - smoothstep(1.7, 3.0, dLane)
                local m = max(m1, m2)
                if m > bestMask then bestMask = m end
            end
        end
    end

    return bestMask, inAlcove
end

-- Longitudinal base elevation profile along u (walkable corridor height)
local function evalBaseCorridorElev(u)
    -- Atacama elevated red plateau (+1.05 on u = 40.5..58.0, smooth ramps 38.5..41.0 & 57.5..60.0)
    if u >= 38.5 and u <= 60.0 then
        local up = smoothstep(38.5, 40.5, u)
        local down = 1.0 - smoothstep(58.0, 60.0, u)
        return 1.05 * up * down
    end

    -- Costa marsh low wetland (u = 82.8..90.8)
    if u >= 82.8 and u <= 90.8 then
        local into = smoothstep(82.8, 83.6, u)
        local out = 1.0 - smoothstep(90.0, 90.8, u)
        return -0.08 * into * out
    end

    -- Ciudad 2-terrace stone acropolis:
    -- Terrace 1: u = 93.0..96.0 -> +0.55
    -- Terrace 2: u = 105.0..108.5 -> +1.15 through 118+
    if u >= 93.0 then
        local t1 = smoothstep(93.0, 96.0, u) * 0.55
        local t2 = smoothstep(105.0, 108.5, u) * 0.60
        return t1 + t2
    end

    return 0.0
end

-- Computes irregular flanking 3D cliff height bump (0 inside walkable corridor, ~2.2..2.8 outside)
local function evalFlankCliffBump(u, v, pc, flatMask)
    local distFromPath = abs(v - pc)

    -- Soft world-end cliff enclosure beyond u < -1.5 or u > 117.5 (keeps screen edges full)
    local endCliff = 0.0
    if u < -0.8 then
        endCliff = smoothstep(-0.8, -3.5, u) * 2.25
    elseif u > 117.2 then
        endCliff = smoothstep(117.2, 120.5, u) * 2.15
    end

    -- Organic noise wobble on the cliff edge so flanking cliffs look natural, not straight walls
    local edgeWobble = sin(u * 0.37 + v * 0.21) * 0.55 + cos(u * 0.19 - v * 0.29) * 0.35
    local effectiveDist = distFromPath + edgeWobble * 0.45

    -- Walkable corridor stays clean out to ~4.45; cliffs rise dramatically beyond 4.65
    local cliffT = smoothstep(4.55, 6.45, effectiveDist)

    -- Stepped 3D terrace profile (gives crisp multi-tier mesa/ridge feel)
    local rawHeight = 0.0
    if cliffT > 0.0 then
        local ridgeNoise = 0.5 + 0.5 * sin(u * 0.24 + v * 0.31) * cos(u * 0.13 - v * 0.18)
        local targetH = 2.25 + ridgeNoise * 0.55
        -- Subtle intermediate shelf around half-climb
        local stepped = (cliffT < 0.42) and (cliffT * 1.15)
            or ((cliffT < 0.58) and 0.483 or (0.483 + ((cliffT - 0.58) / 0.42) * 0.517))
        rawHeight = stepped * targetH
    end

    -- Flanking cliffs are suppressed cleanly by encounter clearings, lanes, and side alcoves
    local carved = rawHeight * (1.0 - flatMask)
    return max(carved, endCliff * (1.0 - flatMask))
end

function StageRenderer.getElevation(u, v)
    -- 1. Bosque wooden bridge over river
    if StageRenderer.isBosqueBridge(u, v) then
        return 0.22
    end
    -- 2. Bosque river channel (flows continuously across the valley)
    if u >= 27.0 and u <= 30.4 then
        return -0.35
    end
    -- 3. Costa wooden pier over ocean (including widened Gaviota Mafiosa dock)
    if StageRenderer.isCostaPier(u, v) then
        return 0.42
    end
    -- 4. Costa Pacific ocean bay (extends seamlessly across screen)
    if u >= 67.4 and u <= 82.6 then
        -- Small rocky outcrop for Valparaiso lighthouse at u=78.5, v=-8.8
        local ldu = u - 78.5
        local ldv = v - (-8.8)
        local ld = sqrt(ldu * ldu + ldv * ldv)
        if ld <= 2.9 then
            return 0.85 * (1.0 - smoothstep(1.8, 2.9, ld)) - 0.42 * smoothstep(1.8, 2.9, ld)
        end
        return -0.42
    end

    local pc = StageRenderer.pathCenterV(u)
    local baseElev = evalBaseCorridorElev(u)

    local encMask = evalEncounterMask(u, v)
    local alcMask, inAlcove = evalAlcoveMask(u, v)
    local flatMask = max(encMask, alcMask)

    -- Dry stone overlook alcove beside the marsh (only on the alcove's own side away from the marsh path!)
    if inAlcove and u >= 82.8 and u <= 90.8 and (v - pc) < -1.8 then
        return 0.14
    end

    local cliffBump = evalFlankCliffBump(u, v, pc, flatMask)
    return baseElev + cliffBump
end

function StageRenderer.getTerrainType(u, v)
    -- 1. Bridge & River (Bosque)
    if StageRenderer.isBosqueBridge(u, v) then
        return "bridge"
    end
    if u >= 27.0 and u <= 30.4 then
        return "river"
    end

    -- 2. Pier & Ocean (Costa)
    if StageRenderer.isCostaPier(u, v) then
        return "pier"
    end
    if u >= 67.4 and u <= 82.6 then
        local ldu = u - 78.5
        local ldv = v - (-8.8)
        if (ldu * ldu + ldv * ldv) <= 5.8 then
            return "cliff"
        end
        return "water"
    end

    -- 3. Royal Crimson Carpet (Ciudad Gran Oficina)
    if u >= 104.5 and u <= 114.5 and abs(v - 0.4) <= 1.35 then
        return "carpet"
    end

    local pc = StageRenderer.pathCenterV(u)
    local encMask, inEncDisk, inEncLane = evalEncounterMask(u, v)
    local alcMask, inAlcove = evalAlcoveMask(u, v)
    local flatMask = max(encMask, alcMask)

    -- 4. Side Alcoves (visually distinct flagstone/shrine ground outside central road)
    if inAlcove and abs(v - pc) > 1.75 then
        return "alcove"
    end

    -- 5. Cliffs (elevated flanking walls)
    local baseElev = evalBaseCorridorElev(u)
    local cliffBump = evalFlankCliffBump(u, v, pc, flatMask)
    if cliffBump >= 0.95 or (baseElev + cliffBump) >= 2.15 then
        return "cliff"
    end

    -- 6. Marsh (Costa wetland u = 82.8..90.8, keeping narrow central stepping trail readable)
    if u >= 82.8 and u <= 90.8 then
        if abs(v - pc) <= 1.05 then
            return "path"
        end
        return "marsh"
    end

    -- 7. Main winding path + branching trails leading directly to encounters (strictly inside playable u = 0..116)
    if u >= -0.2 and u <= 116.2 and (abs(v - pc) <= 1.65 or inEncLane or inEncDisk) then
        return "path"
    end

    return "ground"
end

function StageRenderer.isWalkable(u, v)
    -- World longitudinal travel limits (safe traversal u = 0..116)
    if u < 0.0 or u > 116.5 then
        return false
    end

    local terrain = StageRenderer.getTerrainType(u, v)
    if terrain == "river" or terrain == "water" or terrain == "cliff" then
        return false
    end

    local elev = StageRenderer.getElevation(u, v)
    if elev >= 2.15 then
        return false
    end

    if terrain == "bridge" or terrain == "pier" or terrain == "carpet" then
        return true
    end

    -- Guaranteed walkable encounter clearings & connecting lanes
    local _, inEncDisk, inEncLane = evalEncounterMask(u, v)
    if inEncDisk or inEncLane then
        return true
    end

    -- Guaranteed walkable side alcoves & connectors
    local _, inAlcove = evalAlcoveMask(u, v)
    if inAlcove then
        return true
    end

    local pc = StageRenderer.pathCenterV(u)
    return abs(v - pc) <= 4.45
end

function StageRenderer.screenVecToIso(dx, dy, speed)
    if (dx == 0 or dx == nil) and (dy == 0 or dy == nil) then
        return 0.0, 0.0
    end
    dx = dx or 0.0
    dy = dy or 0.0
    local du = (dx / StageRenderer.ISO_UX - dy / 31.0) * 0.5
    local dv = (dx / StageRenderer.ISO_VX + dy / 31.0) * 0.5
    local len = sqrt(du * du + dv * dv)
    if len <= 1e-6 then
        return 0.0, 0.0
    end
    local spd = speed or 1.0
    return (du / len) * spd, (dv / len) * spd
end

function StageRenderer.getBattleAnchors(w, h)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    return {
        puduX = sw * 0.28,
        puduY = sh * 0.65,
        enemyX = sw * 0.72,
        enemyY = sh * 0.65,
    }
end

function StageRenderer.roomCenter(u)
    local idx = floor((u or 0.0) / StageRenderer.ROOM_SPACING)
    if idx < 0 then
        idx = 0
    elseif idx > 8 then
        idx = 8
    end
    local cu = min(113.0, 6.0 + idx * StageRenderer.ROOM_SPACING)
    local cv = StageRenderer.pathCenterV(cu)
    return cu, cv, idx
end

--------------------------------------------------------------------------------
-- 4. Constructor & Calm Room-Snapped Camera
--------------------------------------------------------------------------------

function StageRenderer.new()
    local cu, cv, idx = StageRenderer.roomCenter(3.8)
    local self = setmetatable({
        camZoom = 0.72,
        camPanDuration = 0.65,
        camU = cu,
        camV = cv,
        camStartU = cu,
        camStartV = cv,
        camTargetU = cu,
        camTargetV = cv,
        camPanT = 1.0,
        currentRoomIdx = idx,
        overworldDecor = {},
        _decorBuilt = false,
        _tileMesh = nil,
        _elevCache = {},
        _drawList = {},
        _drawPool = {},
        _drawCount = 0,
    }, StageRenderer)
    return self
end

function StageRenderer:snapCameraToChunk(u, v)
    local cu, cv, idx = StageRenderer.roomCenter(u or 3.8)
    -- If explicitly snapped to an off-axis point far from room center (e.g. deep alcove), keep room U and gently shift V.
    if type(v) == "number" and abs(v - cv) > 5.4 then
        cv = lerp(cv, v, 0.55)
    end
    self.camU = cu
    self.camV = cv
    self.camStartU = cu
    self.camStartV = cv
    self.camTargetU = cu
    self.camTargetV = cv
    self.camPanT = 1.0
    self.currentRoomIdx = idx
end

function StageRenderer:updateExploreCamera(puduU, puduV, dt)
    local delta = dt
    if delta == nil then
        delta = (love and love.timer) and love.timer.getDelta() or (1 / 60)
    end

    if self.camPanT < 1.0 then
        local dur = max(0.05, self.camPanDuration or 0.65)
        self.camPanT = min(1.0, self.camPanT + delta / dur)
        local t = self.camPanT
        local s = t * t * (3.0 - 2.0 * t)
        self.camU = self.camStartU + (self.camTargetU - self.camStartU) * s
        self.camV = self.camStartV + (self.camTargetV - self.camStartV) * s
        return
    end

    -- 100% STILL inside active room until threshold is crossed!
    local du = abs(puduU - self.camTargetU)
    local dv = abs(puduV - self.camTargetV)
    if du > 7.4 or dv > 5.4 then
        local nextU, nextV, nextIdx
        if du > 7.4 then
            -- Select nearest discrete room center cleanly with hysteresis so crossing +/-7.4 advances room
            local nearestIdx = clamp(floor((puduU - 6.0) / StageRenderer.ROOM_SPACING + 0.5), 0, 8)
            nextIdx = nearestIdx
            nextU = min(113.0, 6.0 + nearestIdx * StageRenderer.ROOM_SPACING)
            nextV = StageRenderer.pathCenterV(nextU)
            if abs(puduV - nextV) > 5.4 then
                nextV = lerp(nextV, puduV, 0.55)
            end
        else
            -- Lateral wander (e.g. side alcove): shift camera V smoothly in a single calm pan
            nextIdx = self.currentRoomIdx
            nextU = self.camTargetU
            local baseV = StageRenderer.pathCenterV(nextU)
            nextV = lerp(baseV, puduV, 0.62)
        end

        if abs(nextU - self.camTargetU) > 0.2 or abs(nextV - self.camTargetV) > 0.2 then
            self.camStartU = self.camU
            self.camStartV = self.camV
            self.camTargetU = nextU
            self.camTargetV = nextV
            self.currentRoomIdx = nextIdx
            self.camPanT = 0.0
        end
    end
end

function StageRenderer:isCameraPanning()
    return self.camPanT < 1.0
end

function StageRenderer:isoToScreen(u, v, elev, w, h)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local z = self.camZoom or 0.72
    local du = u - self.camU
    local dv = v - self.camV
    local sx = sw * 0.5 + (du * StageRenderer.ISO_UX + dv * StageRenderer.ISO_VX) * z
    local sy = sh * 0.54 + (du * StageRenderer.ISO_UY + dv * StageRenderer.ISO_VY - (elev or 0.0) * StageRenderer.ELEV_PX) * z
    return sx, sy
end

--------------------------------------------------------------------------------
-- 5. Sky & Parallax Biome Horizon (12-Band Sky + Sun + Clouds + 2 Layers)
--------------------------------------------------------------------------------

local function resolveSkyPalette(theme, stageKind)
    local biomeId = STAGE_TO_BIOME[stageKind or "bosque"] or "bosque"
    local base = DEFAULT_SKY_THEMES[biomeId] or DEFAULT_SKY_THEMES.bosque
    if type(theme) ~= "table" then
        return base, biomeId
    end
    local bId = theme.biome or biomeId
    return {
        skyTop = theme.skyTop or base.skyTop,
        skyBot = theme.skyBot or base.skyBot,
        horizonGlow = theme.horizonGlow or base.horizonGlow,
        sunColor = theme.sunColor or base.sunColor,
        groundA = theme.groundA or base.groundA,
        groundB = theme.groundB or base.groundB,
        accentColor = theme.accentColor or base.accentColor,
    }, bId
end

function StageRenderer:drawSkyAndHorizon(theme, w, h, time, horizonFrac, stageKind)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = time or 0.0
    local hFrac = horizonFrac or 0.44
    local horizonY = floor(sh * hFrac)
    local pal, biomeId = resolveSkyPalette(theme, stageKind)

    -- 1. 12-band crisp pixel-RPG gradient sky
    local bands = 12
    local bandH = ceil(horizonY / bands) + 1
    for i = 0, bands - 1 do
        local frac = i / (bands - 1)
        local r = lerp(pal.skyTop[1], pal.skyBot[1], frac)
        local g = lerp(pal.skyTop[2], pal.skyBot[2], frac)
        local b = lerp(pal.skyTop[3], pal.skyBot[3], frac)
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.rectangle("fill", 0, floor(horizonY * i / bands), sw, bandH)
    end

    -- 2. Warm sun disc + layered atmospheric halo
    local sunX = sw * ((biomeId == "ciudad") and 0.74 or 0.78)
    local sunY = horizonY * ((biomeId == "desierto") and 0.34 or 0.40)
    local sunR = min(sw, sh) * 0.042
    local sc = pal.sunColor
    love.graphics.setColor(pal.horizonGlow[1], pal.horizonGlow[2], pal.horizonGlow[3], 0.16)
    love.graphics.circle("fill", sunX, sunY, sunR * 3.1)
    love.graphics.setColor(sc[1], sc[2], sc[3], 0.28)
    love.graphics.circle("fill", sunX, sunY, sunR * 1.9)
    love.graphics.setColor(sc[1], sc[2], sc[3], 0.96)
    love.graphics.circle("fill", sunX, sunY, sunR)
    love.graphics.setColor(1.0, 0.99, 0.92, 0.85)
    love.graphics.circle("fill", sunX - sunR * 0.15, sunY - sunR * 0.15, sunR * 0.58)

    -- 3. Drifting multi-block pixel clouds
    local cloudAlpha = (biomeId == "desierto") and 0.45 or 0.72
    for i = 1, 6 do
        local speed = 6.0 + (i % 3) * 4.5
        local cx = ((i * 238.0 + tNow * speed) % (sw + 220)) - 110
        local cy = horizonY * (0.14 + (i % 4) * 0.14)
        local cw = 64 + (i % 3) * 28
        local ch = 12 + (i % 2) * 6
        love.graphics.setColor(pal.horizonGlow[1], pal.horizonGlow[2], pal.horizonGlow[3], cloudAlpha * 0.48)
        love.graphics.rectangle("fill", floor(cx - 8), floor(cy + ch * 0.45), cw + 16, ch * 0.65, 4, 4)
        love.graphics.setColor(0.98, 0.98, 1.0, cloudAlpha)
        love.graphics.rectangle("fill", floor(cx), floor(cy), cw, ch, 4, 4)
        love.graphics.rectangle("fill", floor(cx + cw * 0.18), floor(cy - ch * 0.65), cw * 0.52, ch * 0.85, 4, 4)
    end

    -- 4. Horizon atmospheric glow band
    love.graphics.setColor(pal.horizonGlow[1], pal.horizonGlow[2], pal.horizonGlow[3], 0.34)
    love.graphics.rectangle("fill", 0, horizonY - 38, sw, 42)
    love.graphics.setColor(pal.horizonGlow[1], pal.horizonGlow[2], pal.horizonGlow[3], 0.20)
    love.graphics.rectangle("fill", 0, horizonY - 72, sw, 36)

    -- 5. Far & Near Parallax Silhouette Layers tailored to each Chilean biome
    if biomeId == "bosque" then
        -- Far layer: Andean cordillera peaks with subtle snow caps
        local farCol = { 0.24, 0.40, 0.48 }
        for i = 0, 7 do
            local px = i * (sw / 6.5) - 40
            local pw = sw / 4.2
            local ph = 72 + ((i * 37) % 54)
            love.graphics.setColor(farCol[1], farCol[2], farCol[3], 0.88)
            love.graphics.polygon("fill", px, horizonY + 4, px + pw * 0.5, horizonY - ph, px + pw, horizonY + 4)
            -- Snow peak highlight
            love.graphics.setColor(0.90, 0.95, 0.98, 0.55)
            love.graphics.polygon(
                "fill",
                px + pw * 0.5, horizonY - ph,
                px + pw * 0.38, horizonY - ph * 0.72,
                px + pw * 0.62, horizonY - ph * 0.72
            )
        end
        -- Near layer: Valdivian forest canopy & araucaria silhouettes
        love.graphics.setColor(0.11, 0.26, 0.18, 0.96)
        love.graphics.rectangle("fill", 0, horizonY - 18, sw, 22)
        for i = 0, 26 do
            local tx = i * (sw / 25)
            local th = 26 + ((i * 29) % 30)
            if i % 4 == 0 then
                -- Distinctive Araucaria umbrella silhouette
                love.graphics.rectangle("fill", tx - 2, horizonY - th - 14, 4, th + 16)
                love.graphics.ellipse("fill", tx, horizonY - th - 14, 18, 6)
                love.graphics.ellipse("fill", tx, horizonY - th - 5, 13, 4)
            else
                love.graphics.circle("fill", tx, horizonY - th * 0.6, 18 + (i % 3) * 6)
            end
        end

    elseif biomeId == "desierto" then
        -- Far layer: Iconic Licancabur volcano cone + sweeping Atacama red mesas
        love.graphics.setColor(0.56, 0.34, 0.36, 0.84)
        love.graphics.polygon("fill", sw * 0.08, horizonY + 4, sw * 0.28, horizonY - 112, sw * 0.48, horizonY + 4)
        love.graphics.setColor(0.68, 0.40, 0.34, 0.86)
        for i = 0, 4 do
            local mx = i * (sw * 0.26) - 30
            local mw = sw * 0.24
            local mh = 46 + ((i * 23) % 36)
            love.graphics.polygon(
                "fill",
                mx, horizonY + 4,
                mx + mw * 0.16, horizonY - mh,
                mx + mw * 0.82, horizonY - mh,
                mx + mw, horizonY + 4
            )
        end
        -- Near layer: Warm terracotta canyon ridge + tiny distant cactus silhouettes
        love.graphics.setColor(0.48, 0.24, 0.16, 0.95)
        for i = 0, 7 do
            local rx = i * (sw / 6.5) - 20
            local rw = sw / 5.0
            local rh = 20 + ((i * 19) % 24)
            love.graphics.polygon(
                "fill",
                rx, horizonY + 4,
                rx + rw * 0.22, horizonY - rh,
                rx + rw * 0.76, horizonY - rh * 0.88,
                rx + rw, horizonY + 4
            )
        end
        love.graphics.rectangle("fill", 0, horizonY - 10, sw, 14)

    elseif biomeId == "costa" then
        -- Far layer: Coastal headlands + layered Valparaiso hills
        love.graphics.setColor(0.24, 0.46, 0.64, 0.86)
        for i = 0, 5 do
            local hx = i * (sw * 0.22) - 40
            local hw = sw * 0.28
            local hh = 42 + ((i * 31) % 38)
            love.graphics.ellipse("fill", hx + hw * 0.5, horizonY + 12, hw * 0.62, hh)
        end
        -- Near layer: Colorful Valparaiso hillside houses + distant harbor cranes + sea glint
        for i = 0, 22 do
            local bx = i * (sw / 22)
            local bh = 14 + ((i * 17) % 24)
            local bw = 18 + (i % 3) * 8
            local hc = VALPARAISO_HOUSE_COLS[(i % #VALPARAISO_HOUSE_COLS) + 1]
            love.graphics.setColor(hc[1] * 0.72, hc[2] * 0.72, hc[3] * 0.78, 0.90)
            love.graphics.rectangle("fill", bx, horizonY - bh - 4, bw, bh + 6)
        end
        -- Shimmering distant Pacific sea band right along horizon
        love.graphics.setColor(0.14, 0.44, 0.64, 0.96)
        love.graphics.rectangle("fill", 0, horizonY - 8, sw, 12)
        love.graphics.setColor(0.95, 0.98, 1.0, 0.45)
        for i = 0, 9 do
            local gx = (i * 145 + tNow * 14) % sw
            love.graphics.rectangle("fill", gx, horizonY - 4, 28, 2)
        end

    else
        -- Ciudad: Majestic Andes peaks behind Santiago skyline + glowing office windows
        love.graphics.setColor(0.26, 0.30, 0.48, 0.80)
        for i = 0, 6 do
            local mx = i * (sw / 5.5) - 50
            local mw = sw / 3.6
            local mh = 86 + ((i * 41) % 52)
            love.graphics.polygon("fill", mx, horizonY + 4, mx + mw * 0.5, horizonY - mh, mx + mw, horizonY + 4)
        end
        -- Near skyline towers (including Costanera-style central spire)
        for i = 0, 19 do
            local tx = i * (sw / 19)
            local tw = 34 + (i % 3) * 14
            local th = 36 + ((i * 43) % 72)
            if i == 11 then
                -- Iconic tapered spire tower
                th = 128
                tw = 42
                love.graphics.setColor(0.16, 0.20, 0.34, 0.98)
                love.graphics.polygon(
                    "fill",
                    tx, horizonY + 4,
                    tx + 6, horizonY - th,
                    tx + tw - 6, horizonY - th,
                    tx + tw, horizonY + 4
                )
            else
                love.graphics.setColor(0.14, 0.17, 0.30, 0.96)
                love.graphics.rectangle("fill", tx, horizonY - th, tw, th + 4)
            end
            -- Warm golden lit office windows
            love.graphics.setColor(0.98, 0.86, 0.46, 0.55)
            for wy = horizonY - th + 8, horizonY - 10, 10 do
                for wx = tx + 6, tx + tw - 10, 9 do
                    if ((floor(wx) + floor(wy) + i) % 3) ~= 0 then
                        love.graphics.rectangle("fill", wx, wy, 4, 4)
                    end
                end
            end
        end
    end

    -- Soft warm seam haze across horizon line
    love.graphics.setColor(pal.horizonGlow[1], pal.horizonGlow[2], pal.horizonGlow[3], 0.18)
    love.graphics.rectangle("fill", 0, horizonY - 6, sw, 14)

    -- Solid lower ground backdrop below horizon so zero black voids can ever appear
    love.graphics.setColor(pal.groundB[1], pal.groundB[2], pal.groundB[3], 1.0)
    love.graphics.rectangle("fill", 0, horizonY, sw, sh - horizonY)
end

--------------------------------------------------------------------------------
-- 6. Overworld 3D Isometric Terrain Floor, Skirts, Water, Wayfinders & Beacons
--------------------------------------------------------------------------------

function StageRenderer:_ensureTileMesh()
    if not self._tileMesh then
        self._tileMesh = love.graphics.newMesh(4, "fan", "stream")
    end
    return self._tileMesh
end

function StageRenderer:_drawTexturedDiamond(img, cx, cy, halfW, halfH, u, v, r, g, b, a)
    local h = StageRenderer.STEP * 0.5
    local padX = 0.95
    local padY = 0.72
    local tx, ty = cx, cy - halfH - padY
    local rx, ry = cx + halfW + padX, cy
    local bx, by = cx, cy + halfH + padY
    local lx, ly = cx - halfW - padX, cy

    if img then
        local mesh = self:_ensureTileMesh()
        -- World-anchored UVs guarantee 100% seamless tiling across adjacent diamonds!
        local uvScale = 0.36
        local uTop, vTop = (u + h) * uvScale, (v - h) * uvScale
        local uRig, vRig = (u + h) * uvScale, (v + h) * uvScale
        local uBot, vBot = (u - h) * uvScale, (v + h) * uvScale
        local uLef, vLef = (u - h) * uvScale, (v - h) * uvScale

        mesh:setTexture(img)
        mesh:setVertex(1, tx, ty, uTop, vTop, 1, 1, 1, 1)
        mesh:setVertex(2, rx, ry, uRig, vRig, 1, 1, 1, 1)
        mesh:setVertex(3, bx, by, uBot, vBot, 1, 1, 1, 1)
        mesh:setVertex(4, lx, ly, uLef, vLef, 1, 1, 1, 1)
        love.graphics.setColor(r, g, b, a or 1.0)
        love.graphics.draw(mesh)
    else
        love.graphics.setColor(r, g, b, a or 1.0)
        love.graphics.polygon("fill", tx, ty, rx, ry, bx, by, lx, ly)
    end
end

function StageRenderer:_drawWaterTile(cx, cy, halfW, halfH, u, v, terrain, time, z)
    local padX = 1.05
    local padY = 0.78
    local tx, ty = cx, cy - halfH - padY
    local rx, ry = cx + halfW + padX, cy
    local bx, by = cx, cy + halfH + padY
    local lx, ly = cx - halfW - padX, cy

    local wave = sin(time * 2.4 + u * 0.65 + v * 0.45)
    local wave2 = cos(time * 1.7 - u * 0.42 + v * 0.85)

    if terrain == "river" then
        -- Shimmering Valdivian emerald-turquoise river
        love.graphics.setColor(0.12 + wave * 0.025, 0.48 + wave * 0.035, 0.62 + wave2 * 0.03, 1.0)
        love.graphics.polygon("fill", tx, ty, rx, ry, bx, by, lx, ly)
        -- Flowing current streaks along +v (down-right across valley)
        local flow = ((time * 1.6 + hash2d(u, v) * 2.0) % 1.0) - 0.5
        local sx1 = cx + flow * halfW * 0.55 - halfW * 0.22
        local sy1 = cy + flow * halfH * 0.55 - halfH * 0.22
        love.graphics.setColor(0.68, 0.94, 0.98, 0.42 + 0.16 * wave)
        love.graphics.setLineWidth(max(1.2, 2.0 * z))
        love.graphics.line(sx1, sy1, sx1 + halfW * 0.34, sy1 + halfH * 0.34)
        love.graphics.setLineWidth(1)
    else
        -- Deep sparkling Pacific ocean at Valparaiso
        local pc = StageRenderer.pathCenterV(u)
        local depthT = clamp(abs(v - pc) / 11.0, 0.0, 1.0)
        local r = lerp(0.13, 0.06, depthT) + wave * 0.02
        local g = lerp(0.50, 0.31, depthT) + wave * 0.03
        local b = lerp(0.70, 0.54, depthT) + wave2 * 0.03
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.polygon("fill", tx, ty, rx, ry, bx, by, lx, ly)

        -- Sunlit ocean wave crest & gentle whitecap glint
        if (floor(u + v) % 2 == 0) then
            local ox = sin(time * 1.5 + v * 0.6) * 5.0 * z
            love.graphics.setColor(0.76, 0.95, 1.0, 0.32 + 0.18 * (0.5 + 0.5 * wave))
            love.graphics.setLineWidth(max(1.2, 1.8 * z))
            love.graphics.line(cx - halfW * 0.32 + ox, cy - 2 * z, cx + halfW * 0.24 + ox, cy - 2 * z)
            love.graphics.setLineWidth(1)
        end
    end
end

function StageRenderer:_drawWoodenDeckTile(cx, cy, halfW, halfH, terrain, z)
    local padX = 0.95
    local padY = 0.72
    local tx, ty = cx, cy - halfH - padY
    local rx, ry = cx + halfW + padX, cy
    local bx, by = cx, cy + halfH + padY
    local lx, ly = cx - halfW - padX, cy

    -- Base warm timber plank diamond
    if terrain == "bridge" then
        love.graphics.setColor(0.56, 0.37, 0.20, 1.0)
    else
        love.graphics.setColor(0.62, 0.46, 0.29, 1.0)
    end
    love.graphics.polygon("fill", tx, ty, rx, ry, bx, by, lx, ly)

    -- Subtle lighter top plank strip for crisp pixel-wood feel
    love.graphics.setColor(0.72, 0.55, 0.35, 0.40)
    love.graphics.polygon(
        "fill",
        lerp(lx, tx, 0.28), lerp(ly, ty, 0.28),
        lerp(tx, rx, 0.72), lerp(ty, ry, 0.72),
        lerp(bx, rx, 0.72), lerp(by, ry, 0.72),
        lerp(lx, bx, 0.28), lerp(ly, by, 0.28)
    )

    -- Plank seam lines perpendicular to travel direction (u) -> running along v axis
    love.graphics.setColor(0.28, 0.17, 0.09, 0.62)
    love.graphics.setLineWidth(max(1.0, 1.5 * z))
    for k = 1, 3 do
        local f = k / 4.0
        local x1 = lerp(lx, tx, f)
        local y1 = lerp(ly, ty, f)
        local x2 = lerp(bx, rx, f)
        local y2 = lerp(by, ry, f)
        love.graphics.line(x1, y1, x2, y2)
    end
    love.graphics.setLineWidth(1)
end

function StageRenderer:_drawCarpetTile(cx, cy, halfW, halfH, u, v, z)
    local padX = 0.95
    local padY = 0.72
    local tx, ty = cx, cy - halfH - padY
    local rx, ry = cx + halfW + padX, cy
    local bx, by = cx, cy + halfH + padY
    local lx, ly = cx - halfW - padX, cy

    -- Royal crimson carpet base
    love.graphics.setColor(0.76, 0.12, 0.17, 1.0)
    love.graphics.polygon("fill", tx, ty, rx, ry, bx, by, lx, ly)

    -- Subtle rich velvet center sheen
    love.graphics.setColor(0.88, 0.20, 0.24, 0.45)
    love.graphics.polygon(
        "fill",
        cx, cy - halfH * 0.55,
        cx + halfW * 0.55, cy,
        cx, cy + halfH * 0.55,
        cx - halfW * 0.55, cy
    )

    -- Ornate gold border trim running along the outer carpet edges (along u)
    local dv = v - 0.4
    love.graphics.setColor(0.96, 0.80, 0.28, 0.94)
    love.graphics.setLineWidth(max(1.8, 2.8 * z))
    if dv <= -0.45 then
        love.graphics.line(lx + 4 * z, ly + 2 * z, tx + 4 * z, ty + 2 * z)
    end
    if dv >= 0.45 then
        love.graphics.line(bx - 4 * z, by - 2 * z, rx - 4 * z, ry - 2 * z)
    end
    -- Gold fringe ends at start & end of carpet
    if u <= 105.6 then
        love.graphics.line(lx + 3 * z, ly, bx, by - 2 * z)
    elseif u >= 113.4 then
        love.graphics.line(tx, ty + 2 * z, rx - 3 * z, ry)
    end
    love.graphics.setLineWidth(1)
end

function StageRenderer:_drawTileSkirts(cx, cy, halfW, halfH, elev, eL, eR, terrain, biomeVis, time, z)
    local rx, ry = cx + halfW, cy
    local bx, by = cx, cy + halfH
    local lx, ly = cx - halfW, cy

    -- Wooden bridge & pier: timber fascia beam + vertical support pilings into water!
    if terrain == "bridge" or terrain == "pier" then
        local beamH = 7.5 * z
        local dropL = max(0.0, (elev - eL) * StageRenderer.ELEV_PX * z)
        local dropR = max(0.0, (elev - eR) * StageRenderer.ELEV_PX * z)

        -- Left-front wooden beam + support piling
        if dropL > 2.0 then
            local bh = min(beamH, dropL + 1.5)
            love.graphics.setColor(0.38, 0.24, 0.12, 1.0)
            love.graphics.polygon("fill", lx - 0.6, ly, bx + 0.6, by, bx + 0.6, by + bh, lx - 0.6, ly + bh)
            if dropL > beamH * 1.1 then
                -- Soft water shadow cast underneath overhanging wooden deck
                love.graphics.setColor(0.03, 0.12, 0.22, 0.30)
                love.graphics.polygon("fill", lx, ly + dropL - 2, bx, by + dropL - 2, bx, by + dropL + 6 * z, lx, ly + dropL + 6 * z)
                local postW = 7.4 * z
                local px = lerp(lx, bx, 0.28)
                local py = lerp(ly, by, 0.28)
                love.graphics.setColor(0.24, 0.14, 0.08, 1.0)
                love.graphics.rectangle("fill", px - postW * 0.5, py + bh * 0.5, postW, dropL - bh * 0.3 + 2.5)
                love.graphics.setColor(0.38, 0.24, 0.14, 0.75)
                love.graphics.rectangle("fill", px - postW * 0.5, py + bh * 0.5, postW * 0.35, dropL - bh * 0.3 + 1.5)
                -- Animated water foam collar around piling base
                local foamW = (9.5 + sin(time * 3.0 + px * 0.05) * 1.8) * z
                love.graphics.setColor(0.86, 0.97, 1.0, 0.74)
                love.graphics.ellipse("fill", px, py + dropL + 1.5, foamW, 3.0 * z)
            end
        end

        -- Right-front wooden beam + support piling + pier rail post
        if dropR > 2.0 then
            local bh = min(beamH, dropR + 1.5)
            love.graphics.setColor(0.28, 0.17, 0.09, 1.0)
            love.graphics.polygon("fill", bx - 0.6, by, rx + 0.6, ry, rx + 0.6, ry + bh, bx - 0.6, by + bh)
            if dropR > beamH * 1.1 then
                love.graphics.setColor(0.03, 0.10, 0.20, 0.34)
                love.graphics.polygon("fill", bx, by + dropR - 2, rx, ry + dropR - 2, rx, ry + dropR + 6 * z, bx, by + dropR + 6 * z)
                local postW = 7.4 * z
                local px = lerp(bx, rx, 0.55)
                local py = lerp(by, ry, 0.55)
                love.graphics.setColor(0.19, 0.11, 0.06, 1.0)
                love.graphics.rectangle("fill", px - postW * 0.5, py + bh * 0.5, postW, dropR - bh * 0.3 + 2.5)
                local foamW = (9.5 + cos(time * 2.8 + px * 0.05) * 1.8) * z
                love.graphics.setColor(0.86, 0.97, 1.0, 0.74)
                love.graphics.ellipse("fill", px, py + dropR + 1.5, foamW, 3.0 * z)
            end
            -- Low handrail post along outer pier/bridge edge
            local bollX = lerp(bx, rx, 0.55)
            local bollY = lerp(by, ry, 0.55)
            love.graphics.setColor(0.48, 0.31, 0.16, 1.0)
            love.graphics.rectangle("fill", bollX - 3.0 * z, bollY - 12.5 * z, 6.0 * z, 13.0 * z)
            love.graphics.setColor(0.84, 0.70, 0.44, 1.0)
            love.graphics.rectangle("fill", bollX - 3.5 * z, bollY - 13.5 * z, 7.0 * z, 2.8 * z)
        end

        -- Crisp sunlit wood deck edge highlight
        if dropL > 2.0 or dropR > 2.0 then
            love.graphics.setColor(0.84, 0.68, 0.45, 0.85)
            love.graphics.setLineWidth(max(1.2, 1.8 * z))
            if dropL > 2.0 then love.graphics.line(lx, ly, bx, by) end
            if dropR > 2.0 then love.graphics.line(bx, by, rx, ry) end
            love.graphics.setLineWidth(1)
        end
        return
    end

    -- Royal Crimson Carpet flowing cleanly down acropolis stair risers with brass stair rods!
    if terrain == "carpet" then
        local diffL = elev - eL
        local diffR = elev - eR
        local tuck = 2.6
        if diffL > 0.04 then
            local dropL = diffL * StageRenderer.ELEV_PX * z + tuck
            love.graphics.setColor(0.52, 0.07, 0.11, 1.0)
            love.graphics.polygon("fill", lx - 0.8, ly, bx + 0.8, by, bx + 0.8, by + dropL, lx - 0.8, ly + dropL)
            love.graphics.setColor(0.95, 0.79, 0.28, 0.92)
            love.graphics.setLineWidth(max(1.3, 2.0 * z))
            love.graphics.line(lx, ly + dropL - tuck, bx, by + dropL - tuck)
            love.graphics.setLineWidth(1)
        end
        if diffR > 0.04 then
            local dropR = diffR * StageRenderer.ELEV_PX * z + tuck
            love.graphics.setColor(0.40, 0.05, 0.08, 1.0)
            love.graphics.polygon("fill", bx - 0.8, by, rx + 0.8, ry, rx + 0.8, ry + dropR, bx - 0.8, by + dropR)
        end
        return
    end

    -- Solid terrain 3D cliff faces (Left-front = sunlit face, Right-front = deeper shadow face)
    local diffL = elev - eL
    local diffR = elev - eR
    local tuck = 2.6

    if diffL > 0.04 then
        local dropL = diffL * StageRenderer.ELEV_PX * z + tuck
        local cl = biomeVis.cliffLeft
        love.graphics.setColor(cl[1], cl[2], cl[3], 1.0)
        love.graphics.polygon("fill", lx - 0.8, ly, bx + 0.8, by, bx + 0.8, by + dropL, lx - 0.8, ly + dropL)

        -- Biome-specific geological surface detail on cliff wall
        if dropL > 9.0 * z then
            local cb = biomeVis.cliffBand
            if biomeVis.id == "bosque" then
                local mossH = min(5.5 * z, dropL * 0.35)
                love.graphics.setColor(cb[1], cb[2], cb[3], 0.92)
                love.graphics.polygon("fill", lx - 0.5, ly, bx + 0.5, by, bx + 0.5, by + mossH, lx - 0.5, ly + mossH)
            elseif biomeVis.id == "desierto" then
                local y1 = dropL * 0.34
                local y2 = dropL * 0.52
                love.graphics.setColor(cb[1], cb[2], cb[3], 0.68)
                love.graphics.polygon("fill", lx, ly + y1, bx, by + y1, bx, by + y2, lx, ly + y2)
            elseif biomeVis.id == "ciudad" then
                local trimH = min(4.0 * z, dropL * 0.28)
                love.graphics.setColor(cb[1], cb[2], cb[3], 0.80)
                love.graphics.polygon("fill", lx, ly + 1, bx, by + 1, bx, by + trimH, lx, ly + trimH)
            elseif biomeVis.id == "costa" and eL <= -0.25 then
                -- Sea-foam splash line at coastal cliff base
                love.graphics.setColor(0.86, 0.96, 1.0, 0.60)
                love.graphics.setLineWidth(max(1.5, 2.2 * z))
                love.graphics.line(lx, ly + dropL - tuck, bx, by + dropL - tuck)
                love.graphics.setLineWidth(1)
            end
        end

        -- Crisp top lip highlight
        local lip = biomeVis.cliffLip
        love.graphics.setColor(lip[1], lip[2], lip[3], 0.92)
        love.graphics.setLineWidth(max(1.3, 2.1 * z))
        love.graphics.line(lx, ly, bx, by)
        love.graphics.setLineWidth(1)
    end

    if diffR > 0.04 then
        local dropR = diffR * StageRenderer.ELEV_PX * z + tuck
        local cr = biomeVis.cliffRight
        love.graphics.setColor(cr[1], cr[2], cr[3], 1.0)
        love.graphics.polygon("fill", bx - 0.8, by, rx + 0.8, ry, rx + 0.8, ry + dropR, bx - 0.8, by + dropR)

        if dropR > 9.0 * z then
            local cb = biomeVis.cliffBand
            if biomeVis.id == "bosque" then
                local mossH = min(5.0 * z, dropR * 0.32)
                love.graphics.setColor(cb[1] * 0.78, cb[2] * 0.78, cb[3] * 0.78, 0.90)
                love.graphics.polygon("fill", bx - 0.5, by, rx + 0.5, ry, rx + 0.5, ry + mossH, bx - 0.5, by + mossH)
            elseif biomeVis.id == "desierto" then
                local y1 = dropR * 0.34
                local y2 = dropR * 0.52
                love.graphics.setColor(cb[1] * 0.72, cb[2] * 0.72, cb[3] * 0.72, 0.62)
                love.graphics.polygon("fill", bx, by + y1, rx, ry + y1, rx, ry + y2, bx, by + y2)
            elseif biomeVis.id == "ciudad" then
                local trimH = min(3.8 * z, dropR * 0.26)
                love.graphics.setColor(cb[1] * 0.74, cb[2] * 0.74, cb[3] * 0.74, 0.78)
                love.graphics.polygon("fill", bx, by + 1, rx, ry + 1, rx, ry + trimH, bx, by + trimH)
            elseif biomeVis.id == "costa" and eR <= -0.25 then
                love.graphics.setColor(0.80, 0.94, 1.0, 0.55)
                love.graphics.setLineWidth(max(1.5, 2.0 * z))
                love.graphics.line(bx, by + dropR - tuck, rx, ry + dropR - tuck)
                love.graphics.setLineWidth(1)
            end
        end

        local lip = biomeVis.cliffLip
        love.graphics.setColor(lip[1] * 0.88, lip[2] * 0.88, lip[3] * 0.88, 0.68)
        love.graphics.setLineWidth(max(1.1, 1.7 * z))
        love.graphics.line(bx, by, rx, ry)
        love.graphics.setLineWidth(1)
    end
end

-- Convex 2-wing golden wayfinder chevron on the ground pointing along +u (diagonal NE)
local function drawWayfinderChevron(stage, u, time, w, h)
    local pc = StageRenderer.pathCenterV(u)
    local elev = StageRenderer.getElevation(u, pc)
    local sx, sy = stage:isoToScreen(u, pc, elev + 0.02, w, h)
    if sx < -40 or sx > w + 40 or sy < -40 or sy > h + 40 then
        return
    end

    -- Tangent vector in screen space pointing forward along the winding path (+u)
    local pcNext = StageRenderer.pathCenterV(u + 0.9)
    local nx, ny = stage:isoToScreen(u + 0.9, pcNext, elev + 0.02, w, h)
    local dirX, dirY = nx - sx, ny - sy
    local len = sqrt(dirX * dirX + dirY * dirY)
    if len < 1e-4 then return end
    dirX, dirY = dirX / len, dirY / len
    local perpX, perpY = -dirY, dirX

    local z = stage.camZoom or 0.72
    local pulse = 0.76 + 0.24 * sin(time * 3.2 - u * 0.36)
    local tipL = 16.5 * z
    local wingBack = 13.5 * z
    local wingSpan = 15.5 * z
    local thick = 5.8 * z

    local tipX, tipY = sx + dirX * tipL, sy + dirY * tipL
    local innX, innY = sx + dirX * (tipL - thick * 1.45), sy + dirY * (tipL - thick * 1.45)
    local lOutX, lOutY = sx - dirX * wingBack + perpX * wingSpan, sy - dirY * wingBack + perpY * wingSpan
    local lInX, lInY = lOutX - dirX * thick * 0.35 - perpX * thick, lOutY - dirY * thick * 0.35 - perpY * thick
    local rOutX, rOutY = sx - dirX * wingBack - perpX * wingSpan, sy - dirY * wingBack - perpY * wingSpan
    local rInX, rInY = rOutX - dirX * thick * 0.35 + perpX * thick, rOutY - dirY * thick * 0.35 + perpY * thick

    -- Ground shadow for high contrast on desert sand & pale stone
    love.graphics.setColor(0.08, 0.06, 0.04, 0.44 * pulse)
    love.graphics.polygon("fill", tipX, tipY + 2.5, lOutX, lOutY + 2.5, lInX, lInY + 2.5, innX, innY + 2.5)
    love.graphics.polygon("fill", tipX, tipY + 2.5, rOutX, rOutY + 2.5, rInX, rInY + 2.5, innX, innY + 2.5)

    -- Two convex wing quads forming a crisp golden chevron (ZERO concave polygons, ZERO Unicode!)
    love.graphics.setColor(0.99, 0.84, 0.28, 0.90 * pulse)
    love.graphics.polygon("fill", tipX, tipY, lOutX, lOutY, lInX, lInY, innX, innY)
    love.graphics.polygon("fill", tipX, tipY, rOutX, rOutY, rInX, rInY, innX, innY)

    -- Subtle inner warm white highlight
    love.graphics.setColor(1.0, 0.97, 0.78, 0.72 * pulse)
    love.graphics.setLineWidth(1.4)
    love.graphics.line(lOutX, lOutY, tipX, tipY, rOutX, rOutY)
    love.graphics.setLineWidth(1)
end

local function drawRivalBeacon(stage, enc, defeated, time, w, h)
    local elev = StageRenderer.getElevation(enc.u, enc.v)
    local sx, sy = stage:isoToScreen(enc.u, enc.v, elev + 0.02, w, h)
    if sx < -90 or sx > w + 90 or sy < -90 or sy > h + 90 then
        return
    end
    local z = stage.camZoom or 0.72
    local pulse = 0.5 + 0.5 * sin(time * 3.8 + (enc.index or 1) * 0.9)
    local rx = (34.0 + pulse * 6.5) * z
    local ry = rx * 0.5

    if defeated then
        love.graphics.setColor(0.18, 0.76, 0.48, 0.20)
        love.graphics.ellipse("fill", sx, sy, rx, ry)
        love.graphics.setColor(0.28, 0.90, 0.60, 0.72)
        love.graphics.setLineWidth(2.0)
        love.graphics.ellipse("line", sx, sy, rx * 0.88, ry * 0.88)
        love.graphics.setLineWidth(1)
    else
        -- Warm crimson-gold pulsing encounter beacon ring
        love.graphics.setColor(0.96, 0.28, 0.22, 0.22 + 0.14 * pulse)
        love.graphics.ellipse("fill", sx, sy, rx * 1.12, ry * 1.12)
        love.graphics.setLineWidth(2.4)
        love.graphics.setColor(0.98, 0.34, 0.24, 0.86)
        love.graphics.ellipse("line", sx, sy, rx, ry)
        love.graphics.setLineWidth(1.8)
        love.graphics.setColor(1.00, 0.86, 0.34, 0.88)
        love.graphics.ellipse("line", sx, sy, rx * 0.70, ry * 0.70)
        love.graphics.setLineWidth(1)
    end
end

function StageRenderer:drawOverworldFloor(ctx)
    ctx = ctx or {}
    local sw = ctx.w or love.graphics.getWidth()
    local sh = ctx.h or love.graphics.getHeight()
    local time = ctx.time or 0.0
    local assets = ctx.assets
    local tiles = assets and assets.tiles or nil
    local z = self.camZoom or 0.72
    local step = StageRenderer.STEP

    -- 1. Seamless biome backdrop fill (guarantees zero black voids anywhere)
    local camBiome = StageRenderer.getBiomeAt(self.camU)
    local camVis = StageRenderer.BIOME_VISUALS[camBiome] or StageRenderer.BIOME_VISUALS.bosque
    love.graphics.setColor(camVis.backdrop[1], camVis.backdrop[2], camVis.backdrop[3], 1.0)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- 2. Compute exact visible integer grid bounds covering the full screen
    local halfW = step * StageRenderer.ISO_UX * z
    local halfH = step * 31.0 * z
    local maxShiftUp = 3.2 * StageRenderer.ELEV_PX * z
    local maxShiftDown = 3.6 * StageRenderer.ELEV_PX * z

    local spanU = ceil(((sw * 0.5) / (StageRenderer.ISO_UX * z) + (sh * 0.62) / (31.0 * z)) * 0.5 / step) + 4
    local spanV = ceil(((sw * 0.5) / (StageRenderer.ISO_VX * z) + (sh * 0.62) / (31.0 * z)) * 0.5 / step) + 4
    local centerIu = floor(self.camU / step + 0.5)
    local centerIv = floor(self.camV / step + 0.5)

    local iuMin = centerIu - spanU
    local iuMax = centerIu + spanU
    local ivMin = centerIv - spanV
    local ivMax = centerIv + spanV

    -- Precompute elevations into reusable flat cache (1 extra step on front edges for skirt lookup)
    local cols = (ivMax - ivMin) + 2
    local rows = (iuMax - iuMin) + 2
    local elevCache = self._elevCache
    for r = 0, rows - 1 do
        local iu = iuMax - r -- descending u: r=0 is iuMax, r+1 is u - STEP!
        local u = iu * step
        local rowOff = r * cols
        for c = 0, cols - 1 do
            local iv = ivMin + c -- ascending v: c+1 is v + STEP!
            local v = iv * step
            elevCache[rowOff + c] = StageRenderer.getElevation(u, v)
        end
    end

    -- 3. Strict Back-to-Front isometric grid render (u descending, v ascending)
    local baseScreenX = sw * 0.5
    local baseScreenY = sh * 0.54
    local uxZ = StageRenderer.ISO_UX * z
    local uyZ = StageRenderer.ISO_UY * z
    local vxZ = StageRenderer.ISO_VX * z
    local vyZ = StageRenderer.ISO_VY * z
    local elevPxZ = StageRenderer.ELEV_PX * z
    local camU = self.camU
    local camV = self.camV

    for r = 0, rows - 2 do
        local iu = iuMax - r
        local u = iu * step
        local du = u - camU
        local rowOff = r * cols
        local nextRowOff = (r + 1) * cols -- neighbor (u - STEP, v)
        local biomeId = StageRenderer.getBiomeAt(u)
        local vis = StageRenderer.BIOME_VISUALS[biomeId] or StageRenderer.BIOME_VISUALS.bosque

        for c = 0, cols - 2 do
            local iv = ivMin + c
            local v = iv * step
            local dv = v - camV
            local cx = baseScreenX + du * uxZ + dv * vxZ
            local baseCy = baseScreenY + du * uyZ + dv * vyZ

            -- Frustum cull before drawing
            if cx + halfW >= -24 and cx - halfW <= sw + 24
                and baseCy + halfH + maxShiftDown >= -24
                and baseCy - halfH - maxShiftUp <= sh + 24 then

                local elev = elevCache[rowOff + c]
                local eL = elevCache[nextRowOff + c]     -- front-left neighbor (u - STEP, v)
                local eR = elevCache[rowOff + c + 1]     -- front-right neighbor (u, v + STEP)
                local cy = baseCy - elev * elevPxZ
                local terrain = StageRenderer.getTerrainType(u, v)

                -- Draw 3D cliff skirts / pier pilings first
                if terrain ~= "water" and terrain ~= "river" then
                    self:_drawTileSkirts(cx, cy, halfW, halfH, elev, eL, eR, terrain, vis, time, z)
                end

                -- Draw top diamond surface
                if terrain == "water" or terrain == "river" then
                    self:_drawWaterTile(cx, cy, halfW, halfH, u, v, terrain, time, z)
                elseif terrain == "bridge" or terrain == "pier" then
                    self:_drawWoodenDeckTile(cx, cy, halfW, halfH, terrain, z)
                elseif terrain == "carpet" then
                    self:_drawCarpetTile(cx, cy, halfW, halfH, u, v, z)
                else
                    local tileKey
                    local tint
                    if terrain == "path" then
                        tileKey = vis.pathTile
                        tint = vis.pathTint
                    elseif terrain == "alcove" then
                        tileKey = vis.pathTile
                        tint = vis.alcoveTint
                    elseif terrain == "cliff" then
                        tileKey = vis.cliffTile
                        tint = vis.cliffTopTint
                    elseif terrain == "marsh" then
                        tileKey = "grass_floor"
                        tint = nil
                    else
                        tileKey = vis.floorTile
                        tint = vis.groundTint
                    end

                    local tr, tg, tb
                    if terrain == "marsh" then
                        tr, tg, tb = 0.44, 0.56, 0.38
                    elseif biomeId == "desierto" and terrain == "ground" and elev > 0.55 then
                        local pt = vis.plateauTint
                        tr, tg, tb = pt[1], pt[2], pt[3]
                    else
                        tr, tg, tb = tint[1], tint[2], tint[3]
                    end

                    -- Subtle elevation brightening so raised terraces read with crisp 3D contrast
                    local elevShade = clamp(0.95 + elev * 0.045, 0.88, 1.08)
                    local img = tiles and tiles[tileKey] and tiles[tileKey].diff or nil
                    self:_drawTexturedDiamond(img, cx, cy, halfW, halfH, u, v, tr * elevShade, tg * elevShade, tb * elevShade, 1.0)

                    -- Subtle glossy mud puddle sheen in marsh cells
                    if terrain == "marsh" and ((iu * 7 + iv * 13) % 3 == 0) then
                        local bub = 0.5 + 0.5 * sin(time * 2.1 + u + v)
                        love.graphics.setColor(0.22, 0.34, 0.24, 0.52)
                        love.graphics.ellipse("fill", cx, cy, halfW * 0.42, halfH * 0.36)
                        love.graphics.setColor(0.56, 0.74, 0.42, 0.36 * bub)
                        love.graphics.ellipse("line", cx + 4 * z, cy - 1 * z, (6 + bub * 4) * z, (3 + bub * 2) * z)
                    end
                end
            end
        end
    end

    -- 4. Golden diagonal wayfinder chevrons along the winding main path (guiding NE travel)
    local encList = ctx.encounters or _encounterAnchors
    for u = 6.0, 102.0, 5.5 do
        if abs(u - camU) <= 18.0 then
            -- Skip directly underneath encounters or carpet
            local nearEnc = false
            local pc = StageRenderer.pathCenterV(u)
            for i = 1, #encList do
                local e = encList[i]
                if e and abs(u - e.u) < 2.2 and abs(pc - e.v) < 2.4 then
                    nearEnc = true
                    break
                end
            end
            if not nearEnc then
                drawWayfinderChevron(self, u, time, sw, sh)
            end
        end
    end

    -- 5. Pulsing rival beacon rings on the ground
    local defeatedMap = ctx.defeatedMap or {}
    for i = 1, #encList do
        local enc = encList[i]
        if enc and abs(enc.u - camU) <= 18.0 then
            local isDef = (defeatedMap[enc.id] == true) or (defeatedMap[i] == true)
            drawRivalBeacon(self, enc, isDef, time, sw, sh)
        end
    end

    -- 6. Subtle top atmospheric horizon mist tint (gives depth & frames top HUD bar cleanly)
    local hc = camVis.hazeCol
    love.graphics.setColor(hc[1], hc[2], hc[3], 0.14)
    love.graphics.rectangle("fill", 0, 0, sw, 46)
    love.graphics.setColor(hc[1], hc[2], hc[3], 0.06)
    love.graphics.rectangle("fill", 0, 46, sw, 30)
end

--------------------------------------------------------------------------------
-- 7. Overworld Landmarks & Procedural Decor Placement
--------------------------------------------------------------------------------

local function isTooCloseToList(u, v, list, minDist)
    local d2 = minDist * minDist
    for i = 1, #list do
        local e = list[i]
        if e and e.u and e.v then
            local du = u - e.u
            local dv = v - e.v
            if (du * du + dv * dv) < d2 then
                return true
            end
        end
    end
    return false
end

function StageRenderer:buildOverworldDecor(encountersList)
    if encountersList then
        StageRenderer.setEncounters(encountersList)
    end
    local encList = encountersList or _encounterAnchors
    local decor = {}

    local function addProp(kind, u, v, scale, biome, extra)
        decor[#decor + 1] = {
            kind = kind,
            u = u,
            v = v,
            scale = scale or 1.0,
            biome = biome or StageRenderer.getBiomeAt(u),
            extra = extra,
        }
    end

    -- A. Iconic Biome Border Arches / Frontier Pillars near u = 39, 65, 91
    local borders = {
        { u = 39.0, biome = "bosque",   style = "stone" },
        { u = 65.0, biome = "desierto", style = "sandstone" },
        { u = 91.0, biome = "costa",    style = "harbor" },
    }
    for i = 1, #borders do
        local b = borders[i]
        local pc = StageRenderer.pathCenterV(b.u)
        addProp("biome_arch", b.u, pc - 3.45, 1.18, b.biome, b.style)
        addProp("biome_arch", b.u, pc + 3.45, 1.18, b.biome, b.style)
    end

    -- B. Bosque Bridge Entrance Posts (u = 26.2 and u = 31.2)
    for _, bu in ipairs({ 26.2, 31.2 }) do
        local pc = StageRenderer.pathCenterV(bu)
        addProp("lantern_post", bu, pc - 2.65, 1.0, "bosque")
        addProp("lantern_post", bu, pc + 2.65, 1.0, "bosque")
    end

    -- C. Costa Iconic Landmarks: Valparaiso Lighthouse & Ghostly Caleuche Ship in the Ocean Bay!
    addProp("coast_lighthouse", 78.5, -8.8, 1.35, "costa")
    addProp("caleuche_ship", 73.2, -8.6, 1.25, "costa")
    -- Pier entrance & harbor wharf lanterns
    local pcPierStart = StageRenderer.pathCenterV(67.2)
    addProp("lantern_post", 67.2, pcPierStart - 2.75, 1.0, "costa")
    addProp("lantern_post", 67.2, pcPierStart + 2.75, 1.0, "costa")
    addProp("lantern_post", 82.8, StageRenderer.pathCenterV(82.8) - 2.75, 1.0, "costa")

    -- D. Ciudad Acropolis Columns & Velvet Carpet Stanchions
    for _, cu in ipairs({ 95.5, 102.0, 107.0, 110.5, 114.5 }) do
        local pc = (cu >= 105.0) and 0.4 or StageRenderer.pathCenterV(cu)
        addProp("office_column", cu, pc - 3.7, 1.15, "ciudad")
        addProp("office_column", cu, pc + 3.7, 1.15, "ciudad")
    end
    for su = 105.2, 114.0, 2.8 do
        addProp("stanchion", su, 0.4 - 1.55, 0.95, "ciudad")
        addProp("stanchion", su, 0.4 + 1.55, 0.95, "ciudad")
    end
    -- Flanking ceremonial bureau shrines cleanly framing the Boss without overlapping its head
    addProp("quena_monolith", 115.6, -2.0, 1.16, "ciudad")
    addProp("quena_monolith", 115.6, 2.8, 1.16, "ciudad")

    -- D2. Curated Iconic Bosque Araucarias & Atacama Cardon Cacti framing key sightlines
    addProp("araucaria_tree", 6.5, StageRenderer.pathCenterV(6.5) - 5.2, 1.32, "bosque")
    addProp("ancient_tree", 13.5, StageRenderer.pathCenterV(13.5) - 4.8, 1.28, "bosque")
    addProp("araucaria_tree", 19.5, StageRenderer.pathCenterV(19.5) - 5.4, 1.36, "bosque")
    addProp("araucaria_tree", 32.5, StageRenderer.pathCenterV(32.5) - 5.0, 1.32, "bosque")
    addProp("desert_cactus", 42.5, StageRenderer.pathCenterV(42.5) - 4.8, 1.30, "desierto")
    addProp("desert_cactus", 47.0, StageRenderer.pathCenterV(47.0) + 5.2, 1.25, "desierto")
    addProp("desert_cactus", 51.5, StageRenderer.pathCenterV(51.5) - 5.1, 1.34, "desierto")
    addProp("desert_cactus", 57.0, StageRenderer.pathCenterV(57.0) + 5.1, 1.28, "desierto")

    -- E. Curated Shrine/Landmark at the outer rim of each of the 6 Side Alcoves
    for i = 1, #StageRenderer.SIDE_ALCOVES do
        local alc = StageRenderer.SIDE_ALCOVES[i]
        local pcA = StageRenderer.pathCenterV(alc.u)
        local side = (alc.v >= pcA) and 1.0 or -1.0
        addProp(alc.prop or "stone_pedestal", alc.u, alc.v + side * 1.55, 1.12, alc.biome)
    end

    -- F. Procedural Side Biome Decor with strict walkability & view clearance
    local bosqueFarProps = { "araucaria_tree", "ancient_tree", "araucaria_tree", "mossy_boulder", "copihue", "valdivian_fern" }
    local bosqueNearLow = { "valdivian_fern", "valdivian_shrub", "copihue", "mossy_boulder" }
    local desiertoProps = { "desert_cactus", "mountain_crystal", "rock_monolith", "desert_cactus", "moai_relic", "apacheta_sundial" }
    local costaFarProps = { "valdivian_shrub", "mossy_boulder", "lantern_post", "pincoya_shrine" }
    local ciudadProps = { "lantern_post", "stone_pedestal", "office_column", "debris_pile" }

    for u = -2.0, 117.0, 2.6 do
        local pc = StageRenderer.pathCenterV(u)
        local biome = StageRenderer.getBiomeAt(u)
        for sideIdx = 1, 2 do
            local side = (sideIdx == 1) and -1.0 or 1.0
            for band = 1, 2 do
                local h1 = hash2d(u * 1.3 + sideIdx * 17.0, band * 31.0)
                local h2 = hash2d(u * 2.7 + band * 13.0, sideIdx * 23.0)
                local h3 = hash2d(u * 0.9 + band * 41.0, sideIdx * 7.0)

                local baseOffset = (band == 1) and 3.65 or 6.6
                local jitterU = (h1 - 0.5) * 2.0
                local jitterV = h2 * 2.4
                local pu = u + jitterU
                local pv = pc + side * (baseOffset + jitterV)

                -- Strict clearance: >= 3.4 from path center, >= 3.6 from all encounters, clear of alcoves
                if abs(pv - StageRenderer.pathCenterV(pu)) >= 3.45
                    and not isTooCloseToList(pu, pv, encList, 3.7)
                    and not isTooCloseToList(pu, pv, StageRenderer.SIDE_ALCOVES, 2.3) then

                    local terrain = StageRenderer.getTerrainType(pu, pv)
                    if terrain ~= "water" and terrain ~= "river" and terrain ~= "bridge"
                        and terrain ~= "pier" and terrain ~= "carpet" then

                        -- Keep foreground (+v) close band low so tall props never cover the Pudu!
                        local isForegroundNear = (side > 0 and abs(pv - StageRenderer.pathCenterV(pu)) < 5.0)
                        local kind = nil
                        local sc = 0.85 + h3 * 0.42

                        if biome == "bosque" then
                            if h1 < 0.76 then
                                local pool = isForegroundNear and bosqueNearLow or bosqueFarProps
                                kind = pool[(floor(h2 * #pool) % #pool) + 1]
                            end
                        elseif biome == "desierto" then
                            if h1 < 0.62 then
                                kind = desiertoProps[(floor(h2 * #desiertoProps) % #desiertoProps) + 1]
                                if isForegroundNear and kind == "rock_monolith" then
                                    kind = "mountain_crystal"
                                end
                            end
                        elseif biome == "costa" then
                            if terrain == "marsh" and h1 < 0.68 then
                                kind = (h2 < 0.72) and "lily_pad" or "valdivian_fern"
                                sc = 0.85 + h3 * 0.3
                            elseif h1 < 0.52 then
                                kind = costaFarProps[(floor(h2 * #costaFarProps) % #costaFarProps) + 1]
                            end
                        else
                            -- Ciudad
                            if h1 < 0.54 then
                                kind = ciudadProps[(floor(h2 * #ciudadProps) % #ciudadProps) + 1]
                                if isForegroundNear and kind == "office_column" then
                                    kind = "stone_pedestal"
                                end
                            end
                        end

                        if kind then
                            addProp(kind, pu, pv, sc, biome)
                        end
                    end
                end
            end
        end
    end

    self.overworldDecor = decor
    self._decorBuilt = true
    return decor
end

--------------------------------------------------------------------------------
-- 8. Stylized Prop & Entity Renderers (Modo A Sprites + Modo B Geometric Art)
--------------------------------------------------------------------------------

local function drawStylizedProp(prop, sx, sy, z, time, assets)
    -- Mode A drop-in: if a real prop sprite exists in assets.props[kind].diff, draw it cleanly!
    local propsMap = assets and assets.props
    local pair = propsMap and propsMap[prop.kind]
    if pair and pair.diff then
        local img = pair.diff
        local iw, ih = img:getDimensions()
        local targetH = 86.0 * (prop.scale or 1.0) * z
        local sc = targetH / max(1, ih)
        love.graphics.setColor(0.04, 0.04, 0.08, 0.30)
        love.graphics.ellipse("fill", sx, sy, 22 * (prop.scale or 1.0) * z, 9 * (prop.scale or 1.0) * z)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, sx, sy, 0, sc, sc, iw * 0.5, ih * 0.92)
        return
    end

    -- Mode B high-craft stylized Chilean geometric landmarks
    local k = prop.kind
    local s = (prop.scale or 1.0) * z
    local sway = sin(time * 1.8 + prop.u * 0.7) * 1.8 * s

    -- Ground contact shadow (except flat lily pads and ship on water)
    if k ~= "lily_pad" and k ~= "caleuche_ship" then
        love.graphics.setColor(0.04, 0.05, 0.09, 0.28)
        love.graphics.ellipse("fill", sx, sy + 1 * s, 20 * s, 8 * s)
    end

    if k == "araucaria_tree" then
        -- Iconic Chilean Araucaria: tall straight bark trunk + radiating tiered umbrella canopy
        love.graphics.setColor(0.34, 0.22, 0.14, 1.0)
        love.graphics.rectangle("fill", sx - 5.5 * s, sy - 76 * s, 11 * s, 77 * s)
        love.graphics.setColor(0.48, 0.34, 0.21, 1.0)
        love.graphics.rectangle("fill", sx - 4.0 * s, sy - 76 * s, 3.5 * s, 76 * s)
        for i = 1, #ARAUCARIA_TIERS do
            local tr = ARAUCARIA_TIERS[i]
            love.graphics.setColor(tr.col[1], tr.col[2], tr.col[3], 1.0)
            love.graphics.ellipse("fill", sx + sway * 0.5, sy + tr.y * s, tr.rx * s, tr.ry * s)
            love.graphics.setColor(tr.col[1] + 0.10, tr.col[2] + 0.14, tr.col[3] + 0.08, 0.78)
            love.graphics.ellipse("fill", sx - 5 * s + sway * 0.5, sy + (tr.y - 2) * s, tr.rx * 0.65 * s, tr.ry * 0.54 * s)
        end

    elseif k == "ancient_tree" then
        -- Lush Valdivian coigue tree
        love.graphics.setColor(0.36, 0.23, 0.14, 1.0)
        love.graphics.rectangle("fill", sx - 7.5 * s, sy - 44 * s, 15 * s, 45 * s)
        love.graphics.setColor(0.14, 0.36, 0.19, 1.0)
        love.graphics.circle("fill", sx - 15 * s + sway * 0.4, sy - 48 * s, 21 * s)
        love.graphics.circle("fill", sx + 15 * s + sway * 0.4, sy - 46 * s, 20 * s)
        love.graphics.setColor(0.20, 0.48, 0.24, 1.0)
        love.graphics.circle("fill", sx + sway * 0.5, sy - 62 * s, 25 * s)
        love.graphics.setColor(0.34, 0.66, 0.32, 0.86)
        love.graphics.circle("fill", sx - 7 * s + sway * 0.5, sy - 68 * s, 14 * s)

    elseif k == "valdivian_fern" or k == "valdivian_shrub" then
        love.graphics.setColor(0.16, 0.42, 0.20, 1.0)
        love.graphics.ellipse("fill", sx - 9 * s, sy - 7 * s, 12 * s, 6 * s)
        love.graphics.ellipse("fill", sx + 9 * s, sy - 7 * s, 12 * s, 6 * s)
        love.graphics.setColor(0.26, 0.58, 0.26, 1.0)
        love.graphics.ellipse("fill", sx, sy - 11 * s, 13 * s, 8 * s)
        love.graphics.setColor(0.42, 0.74, 0.34, 0.85)
        love.graphics.ellipse("fill", sx - 3 * s, sy - 14 * s, 7 * s, 4 * s)

    elseif k == "copihue" then
        -- Green shrub studded with bright Chilean crimson copihue bell-flowers
        love.graphics.setColor(0.15, 0.40, 0.20, 1.0)
        love.graphics.ellipse("fill", sx, sy - 10 * s, 15 * s, 9 * s)
        love.graphics.setColor(0.24, 0.54, 0.26, 1.0)
        love.graphics.ellipse("fill", sx - 3 * s, sy - 14 * s, 10 * s, 6 * s)
        love.graphics.setColor(0.92, 0.16, 0.26, 1.0)
        love.graphics.ellipse("fill", sx - 8 * s, sy - 12 * s, 3.2 * s, 5.2 * s)
        love.graphics.ellipse("fill", sx + 5 * s, sy - 15 * s, 3.2 * s, 5.2 * s)
        love.graphics.ellipse("fill", sx + 1 * s, sy - 8 * s, 3.0 * s, 4.6 * s)

    elseif k == "mossy_boulder" or k == "rock_monolith" or k == "debris_pile" then
        local isDesert = (prop.biome == "desierto")
        local isCity = (prop.biome == "ciudad")
        local baseR = isDesert and 0.70 or (isCity and 0.44 or 0.42)
        local baseG = isDesert and 0.39 or (isCity and 0.46 or 0.45)
        local baseB = isDesert and 0.24 or (isCity and 0.54 or 0.48)
        local hRock = (k == "rock_monolith") and 40 * s or 20 * s
        local wRock = (k == "rock_monolith") and 16 * s or 19 * s
        love.graphics.setColor(baseR * 0.72, baseG * 0.72, baseB * 0.76, 1.0)
        love.graphics.polygon("fill", sx - wRock, sy, sx - wRock * 0.6, sy - hRock, sx + wRock * 0.55, sy - hRock * 0.88, sx + wRock, sy)
        love.graphics.setColor(baseR, baseG, baseB, 1.0)
        love.graphics.polygon("fill", sx - wRock, sy, sx - wRock * 0.6, sy - hRock, sx + 2 * s, sy - hRock * 0.75, sx, sy + 2 * s)
        if not isDesert and not isCity then
            love.graphics.setColor(0.28, 0.56, 0.26, 0.90)
            love.graphics.ellipse("fill", sx - 2 * s, sy - hRock * 0.82, wRock * 0.55, 4.5 * s)
        end

    elseif k == "desert_cactus" then
        -- Multi-armed Atacama cardon cactus
        love.graphics.setColor(0.18, 0.46, 0.27, 1.0)
        love.graphics.rectangle("fill", sx - 7.5 * s, sy - 66 * s, 15 * s, 67 * s, 6 * s, 6 * s)
        -- Left & right arms
        love.graphics.rectangle("fill", sx - 25 * s, sy - 45 * s, 19 * s, 9.5 * s, 4 * s, 4 * s)
        love.graphics.rectangle("fill", sx - 25 * s, sy - 60 * s, 11 * s, 22 * s, 5 * s, 5 * s)
        love.graphics.rectangle("fill", sx + 5 * s, sy - 38 * s, 19 * s, 9.5 * s, 4 * s, 4 * s)
        love.graphics.rectangle("fill", sx + 13 * s, sy - 54 * s, 11 * s, 24 * s, 5 * s, 5 * s)
        -- Sunlit vertical rib highlight + golden desert bloom
        love.graphics.setColor(0.36, 0.68, 0.40, 0.88)
        love.graphics.rectangle("fill", sx - 3.5 * s, sy - 62 * s, 3.8 * s, 58 * s)
        love.graphics.setColor(0.98, 0.74, 0.24, 1.0)
        love.graphics.circle("fill", sx, sy - 68 * s, 4.5 * s)

    elseif k == "mountain_crystal" then
        -- Glowing faceted Atacama crystal cluster
        local glow = 0.75 + 0.25 * sin(time * 3.0 + prop.u)
        love.graphics.setColor(0.32, 0.86, 0.96, 0.22 * glow)
        love.graphics.circle("fill", sx, sy - 24 * s, 28 * s)
        love.graphics.setColor(0.22, 0.68, 0.86, 0.95)
        love.graphics.polygon("fill", sx - 16 * s, sy, sx - 12 * s, sy - 30 * s, sx - 2 * s, sy)
        love.graphics.setColor(0.56, 0.34, 0.86, 0.95)
        love.graphics.polygon("fill", sx + 2 * s, sy, sx + 14 * s, sy - 34 * s, sx + 18 * s, sy)
        love.graphics.setColor(0.42, 0.92, 0.98, 0.98)
        love.graphics.polygon("fill", sx - 9 * s, sy + 1 * s, sx, sy - 48 * s, sx + 10 * s, sy + 1 * s)
        love.graphics.setColor(0.86, 0.99, 1.0, 0.85)
        love.graphics.polygon("fill", sx - 5 * s, sy - 4 * s, sx, sy - 46 * s, sx + 2 * s, sy - 4 * s)

    elseif k == "apacheta_sundial" or k == "moai_relic" then
        -- Stacked Andean stone cairn / volcanic relic
        love.graphics.setColor(0.56, 0.36, 0.26, 1.0)
        love.graphics.ellipse("fill", sx, sy - 6 * s, 16 * s, 7 * s)
        love.graphics.setColor(0.64, 0.43, 0.31, 1.0)
        love.graphics.ellipse("fill", sx, sy - 17 * s, 12 * s, 6 * s)
        love.graphics.setColor(0.72, 0.50, 0.36, 1.0)
        love.graphics.ellipse("fill", sx, sy - 27 * s, 8 * s, 5 * s)
        love.graphics.setColor(0.98, 0.82, 0.30, 1.0)
        love.graphics.circle("fill", sx, sy - 38 * s, 6.5 * s)

    elseif k == "rewe_totem" then
        -- Carved wooden Mapuche ceremonial stepped totem
        love.graphics.setColor(0.46, 0.28, 0.16, 1.0)
        love.graphics.rectangle("fill", sx - 6 * s, sy - 58 * s, 12 * s, 59 * s)
        love.graphics.setColor(0.62, 0.40, 0.23, 1.0)
        for st = 1, 4 do
            love.graphics.rectangle("fill", sx - 8 * s, sy - st * 11 * s, 16 * s, 4 * s)
        end
        love.graphics.setColor(0.88, 0.68, 0.30, 1.0)
        love.graphics.polygon("fill", sx, sy - 68 * s, sx - 9 * s, sy - 56 * s, sx + 9 * s, sy - 56 * s)

    elseif k == "orb_shrine" or k == "stone_pedestal" or k == "pincoya_shrine" or k == "quena_monolith" then
        -- Stepped stone pedestal with floating glowing magic orb
        local bob = sin(time * 2.8 + prop.u) * 4.0 * s
        love.graphics.setColor(0.48, 0.51, 0.58, 1.0)
        love.graphics.rectangle("fill", sx - 16 * s, sy - 10 * s, 32 * s, 11 * s, 2, 2)
        love.graphics.setColor(0.62, 0.66, 0.74, 1.0)
        love.graphics.rectangle("fill", sx - 10 * s, sy - 30 * s, 20 * s, 22 * s)
        love.graphics.setColor(0.78, 0.82, 0.90, 1.0)
        love.graphics.rectangle("fill", sx - 13 * s, sy - 34 * s, 26 * s, 5 * s)
        local orbCol = (k == "pincoya_shrine") and { 0.30, 0.92, 0.94 } or { 0.98, 0.82, 0.34 }
        love.graphics.setColor(orbCol[1], orbCol[2], orbCol[3], 0.28)
        love.graphics.circle("fill", sx, sy - 46 * s + bob, 16 * s)
        love.graphics.setColor(orbCol[1], orbCol[2], orbCol[3], 0.98)
        love.graphics.circle("fill", sx, sy - 46 * s + bob, 7.5 * s)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", sx - 2.2 * s, sy - 48.2 * s + bob, 2.4 * s)

    elseif k == "lantern_post" then
        -- Warm fantasy / urban streetlamp with soft radial amber glow
        love.graphics.setColor(0.20, 0.22, 0.28, 1.0)
        love.graphics.rectangle("fill", sx - 5 * s, sy - 5 * s, 10 * s, 6 * s)
        love.graphics.rectangle("fill", sx - 2.2 * s, sy - 54 * s, 4.4 * s, 51 * s)
        love.graphics.rectangle("fill", sx - 2 * s, sy - 54 * s, 14 * s, 3 * s)
        -- Warm lantern globe
        local lx, ly = sx + 10 * s, sy - 48 * s
        local pulse = 0.86 + 0.14 * sin(time * 4.0 + prop.u)
        if assets and assets.lightRadial then
            local lw, lh = assets.lightRadial:getDimensions()
            local haloSc = (54 * s) / max(1, lw)
            love.graphics.setColor(1.0, 0.78, 0.32, 0.34 * pulse)
            love.graphics.draw(assets.lightRadial, lx, ly, 0, haloSc, haloSc, lw * 0.5, lh * 0.5)
        else
            love.graphics.setColor(1.0, 0.78, 0.32, 0.24 * pulse)
            love.graphics.circle("fill", lx, ly, 22 * s)
        end
        love.graphics.setColor(1.0, 0.90, 0.46, 0.98)
        love.graphics.rectangle("fill", lx - 4 * s, ly - 5 * s, 8 * s, 10 * s, 2, 2)
        love.graphics.setColor(0.20, 0.22, 0.28, 1.0)
        love.graphics.polygon("fill", lx - 6 * s, ly - 5 * s, lx + 6 * s, ly - 5 * s, lx, ly - 10 * s)

    elseif k == "biome_arch" then
        -- Sculpted frontier stone/terracotta/iron pillar with glowing banner brazier
        local st = prop.extra or "stone"
        local pR, pG, pB = 0.52, 0.55, 0.50
        local bR, bG, bB = 0.32, 0.78, 0.42
        if st == "sandstone" then
            pR, pG, pB = 0.80, 0.48, 0.28
            bR, bG, bB = 0.98, 0.72, 0.26
        elseif st == "harbor" then
            pR, pG, pB = 0.42, 0.48, 0.58
            bR, bG, bB = 0.28, 0.82, 0.94
        end
        love.graphics.setColor(pR * 0.72, pG * 0.72, pB * 0.76, 1.0)
        love.graphics.rectangle("fill", sx - 13 * s, sy - 10 * s, 26 * s, 11 * s)
        love.graphics.setColor(pR, pG, pB, 1.0)
        love.graphics.rectangle("fill", sx - 9 * s, sy - 66 * s, 18 * s, 58 * s)
        love.graphics.setColor(pR * 1.18, pG * 1.18, pB * 1.18, 0.95)
        love.graphics.rectangle("fill", sx - 12 * s, sy - 70 * s, 24 * s, 7 * s)
        -- Glowing frontier crystal/brazier atop pillar
        love.graphics.setColor(bR, bG, bB, 0.30)
        love.graphics.circle("fill", sx, sy - 78 * s, 16 * s)
        love.graphics.setColor(bR, bG, bB, 1.0)
        love.graphics.polygon("fill", sx, sy - 88 * s, sx - 7 * s, sy - 76 * s, sx, sy - 70 * s, sx + 7 * s, sy - 76 * s)

    elseif k == "coast_lighthouse" then
        -- Iconic tall red-and-white striped Valparaiso lighthouse with sweeping beacon
        love.graphics.setColor(0.38, 0.40, 0.46, 1.0)
        love.graphics.ellipse("fill", sx, sy, 26 * s, 11 * s)
        -- 5 alternating red/white horizontal bands tapering upward
        local towerH = 104 * s
        local segs = 5
        for i = 0, segs - 1 do
            local yBot = sy - (i / segs) * towerH
            local yTop = sy - ((i + 1) / segs) * towerH
            local wBot = lerp(16 * s, 9 * s, i / segs)
            local wTop = lerp(16 * s, 9 * s, (i + 1) / segs)
            if i % 2 == 0 then
                love.graphics.setColor(0.95, 0.95, 0.97, 1.0)
            else
                love.graphics.setColor(0.84, 0.22, 0.22, 1.0)
            end
            love.graphics.polygon("fill", sx - wBot, yBot, sx + wBot, yBot, sx + wTop, yTop, sx - wTop, yTop)
        end
        -- Lantern gallery + glowing golden beacon + dome roof
        local topY = sy - towerH
        love.graphics.setColor(0.20, 0.24, 0.32, 1.0)
        love.graphics.rectangle("fill", sx - 12 * s, topY - 3 * s, 24 * s, 4 * s)
        local beamAngle = sin(time * 1.4) * 0.55
        love.graphics.setColor(1.0, 0.92, 0.52, 0.20)
        love.graphics.polygon(
            "fill",
            sx, topY - 10 * s,
            sx + cos(beamAngle - 0.16) * 95 * s, topY - 10 * s + sin(beamAngle - 0.16) * 42 * s,
            sx + cos(beamAngle + 0.16) * 95 * s, topY - 10 * s + sin(beamAngle + 0.16) * 42 * s
        )
        love.graphics.setColor(1.0, 0.95, 0.58, 0.98)
        love.graphics.rectangle("fill", sx - 7 * s, topY - 16 * s, 14 * s, 13 * s)
        love.graphics.setColor(0.82, 0.20, 0.20, 1.0)
        love.graphics.polygon("fill", sx - 10 * s, topY - 16 * s, sx + 10 * s, topY - 16 * s, sx, topY - 28 * s)

    elseif k == "caleuche_ship" then
        -- Iconic Chilean Caleuche ghostly wooden tall ship rocking gently in the bay
        local bob = sin(time * 1.6 + prop.u) * 4.5 * s
        local syB = sy + bob
        -- Water ripple ring under hull
        love.graphics.setColor(0.76, 0.96, 1.0, 0.42)
        love.graphics.ellipse("line", sx, sy + 5 * s, 46 * s, 14 * s)
        -- Curved wooden hull
        love.graphics.setColor(0.32, 0.20, 0.14, 1.0)
        love.graphics.polygon("fill", sx - 40 * s, syB - 8 * s, sx + 42 * s, syB - 10 * s, sx + 28 * s, syB + 8 * s, sx - 28 * s, syB + 8 * s)
        love.graphics.setColor(0.46, 0.30, 0.19, 1.0)
        love.graphics.rectangle("fill", sx - 34 * s, syB - 12 * s, 68 * s, 5 * s)
        -- Masts
        love.graphics.setColor(0.24, 0.16, 0.11, 1.0)
        love.graphics.rectangle("fill", sx - 12 * s, syB - 70 * s, 3.5 * s, 60 * s)
        love.graphics.rectangle("fill", sx + 14 * s, syB - 58 * s, 3.2 * s, 48 * s)
        -- Billowing cream-teal sails (subtle spectral sheen)
        love.graphics.setColor(0.84, 0.96, 0.94, 0.90)
        love.graphics.polygon("fill", sx - 26 * s, syB - 60 * s, sx + 4 * s, syB - 56 * s, sx + 6 * s, syB - 22 * s, sx - 24 * s, syB - 24 * s)
        love.graphics.polygon("fill", sx + 4 * s, syB - 50 * s, sx + 28 * s, syB - 46 * s, sx + 28 * s, syB - 20 * s, sx + 6 * s, syB - 22 * s)
        -- Lantern glow on stern
        love.graphics.setColor(0.45, 0.98, 0.86, 0.85)
        love.graphics.circle("fill", sx - 32 * s, syB - 15 * s, 4.0 * s)

    elseif k == "office_column" then
        -- Grand neoclassical-office marble/granite column
        love.graphics.setColor(0.58, 0.62, 0.72, 1.0)
        love.graphics.rectangle("fill", sx - 12 * s, sy - 8 * s, 24 * s, 9 * s)
        love.graphics.setColor(0.76, 0.80, 0.88, 1.0)
        love.graphics.rectangle("fill", sx - 8 * s, sy - 66 * s, 16 * s, 59 * s)
        love.graphics.setColor(0.90, 0.92, 0.98, 0.85)
        love.graphics.rectangle("fill", sx - 6 * s, sy - 65 * s, 4 * s, 57 * s)
        love.graphics.setColor(0.94, 0.78, 0.30, 1.0)
        love.graphics.rectangle("fill", sx - 11 * s, sy - 71 * s, 22 * s, 6 * s)

    elseif k == "stanchion" then
        -- Brass velvet-queue post flanking the crimson office carpet
        love.graphics.setColor(0.78, 0.62, 0.22, 1.0)
        love.graphics.ellipse("fill", sx, sy, 6.5 * s, 3.0 * s)
        love.graphics.rectangle("fill", sx - 1.8 * s, sy - 22 * s, 3.6 * s, 22 * s)
        love.graphics.setColor(0.98, 0.86, 0.36, 1.0)
        love.graphics.circle("fill", sx, sy - 23 * s, 3.4 * s)

    elseif k == "lily_pad" then
        love.graphics.setColor(0.22, 0.56, 0.28, 0.92)
        love.graphics.ellipse("fill", sx, sy, 12 * s, 6 * s)
        love.graphics.setColor(0.96, 0.68, 0.78, 0.95)
        love.graphics.circle("fill", sx + 2 * s, sy - 1 * s, 3.0 * s)

    else
        -- Clean fallback milestone marker
        love.graphics.setColor(0.52, 0.56, 0.64, 1.0)
        love.graphics.rectangle("fill", sx - 8 * s, sy - 24 * s, 16 * s, 25 * s, 3, 3)
    end
end

-- Crisp JRPG white/red "!" alert box rendered strictly with geometric primitives (R2 compliant)
local function drawAlertCallout(x, y, timer)
    local t = timer or 0.12
    local pop = min(1.0, t / 0.10)
    local bounce = 1.0 + sin(pop * pi) * 0.22
    local bw = 34 * bounce
    local bh = 40 * bounce
    local bx = floor(x - bw * 0.5)
    local by = floor(y - bh - 10)

    -- Drop shadow
    love.graphics.setColor(0.04, 0.04, 0.08, 0.55)
    love.graphics.rectangle("fill", bx + 3, by + 4, bw, bh, 7, 7)

    -- Speech tail pointing down
    love.graphics.setColor(0.90, 0.14, 0.16, 1.0)
    love.graphics.polygon("fill", x - 6, by + bh - 2, x + 6, by + bh - 2, x, by + bh + 9)

    -- White card with thick crimson border
    love.graphics.setColor(1.0, 0.99, 0.96, 1.0)
    love.graphics.rectangle("fill", bx, by, bw, bh, 7, 7)
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.90, 0.14, 0.16, 1.0)
    love.graphics.rectangle("line", bx, by, bw, bh, 7, 7)
    love.graphics.setLineWidth(1)

    -- Bold vector "!" (convex bar + circle dot)
    love.graphics.setColor(0.90, 0.12, 0.16, 1.0)
    love.graphics.rectangle("fill", x - 3.5 * bounce, by + 7 * bounce, 7.0 * bounce, 17.5 * bounce, 2, 2)
    love.graphics.circle("fill", x, by + 30.5 * bounce, 3.8 * bounce)
end

local function drawRivalEntity(enc, idx, sx, sy, sw, sh, z, time, assets, defeated, isAlerted, alertTimer, font)
    local encPair = assets and assets.encounters and assets.encounters[enc.id]
    local targetH = (enc.scale or 2.55) * 38.0 * (z / 0.72)
    local bob = defeated and 0.0 or sin(time * 3.0 + idx * 1.1) * 2.5 * z
    local alpha = defeated and 0.52 or 1.0

    -- Soft ground contact shadow
    love.graphics.setColor(0.03, 0.04, 0.08, 0.34 * alpha)
    love.graphics.ellipse("fill", sx, sy + 2 * z, 24 * z, 9 * z)

    if encPair and encPair.diff then
        local img = encPair.diff
        local quad = nil
        local fw, fh
        if encPair.isSheet and encPair.quads then
            local rowIdx = enc.sheetRow or 1
            local rowTable = encPair.quads[rowIdx] or encPair.quads[0]
            if rowTable and #rowTable > 0 then
                local colIdx = (floor(time * 5.0) % #rowTable) + 1
                quad = rowTable[colIdx]
                local _, _, qw, qh = quad:getViewport()
                fw, fh = qw, qh
            end
        end
        if not fw then
            fw, fh = img:getDimensions()
        end
        local sc = targetH / max(1, fh)
        love.graphics.setColor(1, 1, 1, alpha)
        if quad then
            love.graphics.draw(img, quad, sx, sy + bob, 0, sc, sc, fw * 0.5, fh * 0.92)
        else
            love.graphics.draw(img, sx, sy + bob, 0, sc, sc, fw * 0.5, fh * 0.92)
        end
    else
        -- Defensive silhouette if assets table was omitted
        local c = enc.color or { 0.88, 0.36, 0.36 }
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.ellipse("fill", sx, sy - targetH * 0.45 + bob, 22 * z, targetH * 0.45)
    end

    -- Clean name pill above rival head (ZERO Unicode tofu; strictly below top HUD y>=52 and inside viewport)
    local f = font or makeFallbackFont()
    local onScreenForTag = (sx >= 24 and sx <= sw - 24 and sy >= 76 and sy <= sh - 16)
    if f and enc.name and onScreenForTag then
        love.graphics.setFont(f)
        local label = defeated and (enc.name .. " (OK)") or enc.name
        local tw = f:getWidth(label)
        local th = f:getHeight()
        local pw = tw + 14
        local ph = th + 6
        local px = floor(clamp(sx - pw * 0.5, 12, sw - pw - 12))
        local py = floor(max(52, sy - targetH - ph - 6 + bob))

        if defeated then
            love.graphics.setColor(0.06, 0.16, 0.12, 0.72)
            love.graphics.rectangle("fill", px, py, pw, ph, 5, 5)
            love.graphics.setColor(0.28, 0.82, 0.56, 0.75)
            love.graphics.rectangle("line", px, py, pw, ph, 5, 5)
            love.graphics.setColor(0.76, 0.96, 0.84, 0.92)
        else
            love.graphics.setColor(0.06, 0.08, 0.16, 0.84)
            love.graphics.rectangle("fill", px, py, pw, ph, 5, 5)
            love.graphics.setColor(0.98, 0.80, 0.32, 0.88)
            love.graphics.rectangle("line", px, py, pw, ph, 5, 5)
            love.graphics.setColor(1.0, 0.98, 0.92, 1.0)
        end
        love.graphics.print(label, px + 7, py + 3)

        if isAlerted then
            drawAlertCallout(sx, py - 2, alertTimer)
        end
    elseif isAlerted then
        drawAlertCallout(sx, max(52, sy - targetH - 8), alertTimer)
    end
end

local function drawPuduWithHat(sx, sy, facingRow, animCol, targetH, bobY, assets)
    local row = clamp(floor(facingRow or 3), 0, 7)
    local col = clamp(floor(animCol or 1), 1, 6)
    local dy = bobY or 0.0

    -- Soft contact shadow beneath hooves
    love.graphics.setColor(0.04, 0.04, 0.08, 0.34)
    love.graphics.ellipse("fill", sx, sy + 2, targetH * 0.25, targetH * 0.09)

    local puduPair = assets and assets.pudu
    local quads = assets and assets.puduQuads
    if puduPair and puduPair.diff and quads and quads[row] and quads[row][col] then
        local quad = quads[row][col]
        local _, _, qw, qh = quad:getViewport()
        local sc = targetH / max(1, qh)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(puduPair.diff, quad, sx, sy + dy, 0, sc, sc, qw * 0.5, qh * 0.88)
    else
        love.graphics.setColor(0.58, 0.35, 0.20, 1.0)
        love.graphics.circle("fill", sx, sy - targetH * 0.4 + dy, targetH * 0.28)
    end

    -- Pointy brown wizard hat anchored cleanly to the Pudu's head for the current facing row
    local hatPair = assets and assets.wizardHat
    if hatPair and hatPair.diff then
        local hw, hh = hatPair.diff:getDimensions()
        local unit = targetH / 64.0
        local off = StageRenderer.HAT_HEAD_OFFSETS[row] or StageRenderer.HAT_HEAD_OFFSETS[3]
        local hatSc = (targetH * 0.58) / max(1, hh)
        local hatX = sx + off.x * unit
        local hatY = sy + off.y * unit + dy * 1.12
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(hatPair.diff, hatX, hatY, 0, hatSc, hatSc, hw * 0.50, hh * 0.78)
    end
end

local function sortByDepth(a, b)
    if a.sortY ~= b.sortY then
        return a.sortY < b.sortY
    end
    return a.tie < b.tie
end

function StageRenderer:drawOverworld(ctx)
    ctx = ctx or {}
    local sw = ctx.w or love.graphics.getWidth()
    local sh = ctx.h or love.graphics.getHeight()
    local time = ctx.time or 0.0
    local assets = ctx.assets
    local encList = ctx.encounters or _encounterAnchors
    local defeatedMap = ctx.defeatedMap or {}
    local z = self.camZoom or 0.72

    if not self._decorBuilt then
        self:buildOverworldDecor(encList)
    end

    -- 1. Floor pass (unless caller already rendered it explicitly)
    if not ctx.skipFloor then
        self:drawOverworldFloor(ctx)
    end

    -- 2. Gather all visible props, rivals, and Pudu into reusable Y-sort list (ZERO per-frame tables)
    local list = self._drawList
    local pool = self._drawPool
    local count = 0

    local function pushEntry(kind, sortY, tie, sx, sy, data, idx)
        count = count + 1
        local entry = pool[count]
        if not entry then
            entry = {}
            pool[count] = entry
        end
        entry.kind = kind
        entry.sortY = sortY
        entry.tie = tie
        entry.sx = sx
        entry.sy = sy
        entry.data = data
        entry.idx = idx
        list[count] = entry
    end

    local baseScreenY = sh * 0.54
    local uyZ = StageRenderer.ISO_UY * z
    local vyZ = StageRenderer.ISO_VY * z
    local camU = self.camU
    local camV = self.camV

    -- Decor props
    local decor = self.overworldDecor
    for i = 1, #decor do
        local prop = decor[i]
        if abs(prop.u - camU) <= 18.5 and abs(prop.v - camV) <= 18.5 then
            local elev = StageRenderer.getElevation(prop.u, prop.v)
            local sx, sy = self:isoToScreen(prop.u, prop.v, elev, sw, sh)
            if sx >= -110 and sx <= sw + 110 and sy >= -110 and sy <= sh + 160 then
                local baseY = baseScreenY + (prop.u - camU) * uyZ + (prop.v - camV) * vyZ
                -- Flat lily pads stay underneath characters
                local tie = (prop.kind == "lily_pad") and -1000 or i
                local sortY = (prop.kind == "lily_pad") and (baseY - 40.0) or baseY
                pushEntry("prop", sortY, tie, sx, sy, prop, i)
            end
        end
    end

    -- Encounters (9 rivals)
    for i = 1, #encList do
        local enc = encList[i]
        if enc and abs(enc.u - camU) <= 18.0 then
            local elev = StageRenderer.getElevation(enc.u, enc.v)
            local sx, sy = self:isoToScreen(enc.u, enc.v, elev, sw, sh)
            if sx >= -120 and sx <= sw + 120 and sy >= -120 and sy <= sh + 150 then
                local baseY = baseScreenY + (enc.u - camU) * uyZ + (enc.v - camV) * vyZ
                pushEntry("rival", baseY, 10000 + i, sx, sy, enc, i)
            end
        end
    end

    -- Hero Pudu
    local puduU = ctx.puduU or 3.8
    local puduV = ctx.puduV or StageRenderer.pathCenterV(puduU)
    local puduElev = StageRenderer.getElevation(puduU, puduV)
    local puduSx, puduSy = self:isoToScreen(puduU, puduV, puduElev, sw, sh)
    local puduBaseY = baseScreenY + (puduU - camU) * uyZ + (puduV - camV) * vyZ
    pushEntry("pudu", puduBaseY, 20000, puduSx, puduSy, nil, 0)

    -- Clear trailing references from previous frame before sorting
    for i = count + 1, self._drawCount do
        list[i] = nil
    end
    self._drawCount = count

    table.sort(list, sortByDepth)

    -- 3. Draw strictly in Y-sorted depth order
    local smallFont = (ctx.fonts and ctx.fonts.small) or makeFallbackFont()
    local puduTargetH = (ctx.puduTargetH or 84.0) * (z / 0.72)

    for i = 1, count do
        local item = list[i]
        if item.kind == "prop" then
            drawStylizedProp(item.data, item.sx, item.sy, z, time, assets)
        elseif item.kind == "rival" then
            local enc = item.data
            local idx = item.idx
            local isDef = (defeatedMap[enc.id] == true) or (defeatedMap[idx] == true)
            local isAlerted = (ctx.alertEncounterIdx == idx)
            drawRivalEntity(enc, idx, item.sx, item.sy, sw, sh, z, time, assets, isDef, isAlerted, ctx.alertTimer, smallFont)
        else
            drawPuduWithHat(
                item.sx,
                item.sy,
                ctx.puduFacingRow or 3,
                ctx.puduAnimCol or 1,
                puduTargetH,
                ctx.puduBobY or 0.0,
                assets
            )
        end
    end
end

--------------------------------------------------------------------------------
-- 9. Diagonal Overworld Minimap (212x122 at x=14, y=58 — ZERO Unicode Tofu)
--------------------------------------------------------------------------------

-- Vector diagonal NE arrow drawn strictly with 2 convex primitives (shaft + head)
local function drawVectorNEArrow(cx, cy, size)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(-pi * 0.25)

    -- Dark outline backing (2 convex parts)
    love.graphics.setColor(0.03, 0.05, 0.12, 0.92)
    love.graphics.rectangle("fill", -size * 0.65 - 1.5, -size * 0.20 - 1.5, size * 0.80 + 3.0, size * 0.40 + 3.0)
    love.graphics.polygon("fill", size * 0.05 - 1.5, -size * 0.58, size * 0.85, 0, size * 0.05 - 1.5, size * 0.58)

    -- Bright gold foreground (2 convex parts)
    love.graphics.setColor(0.99, 0.85, 0.30, 1.0)
    love.graphics.rectangle("fill", -size * 0.65, -size * 0.16, size * 0.80, size * 0.32)
    love.graphics.polygon("fill", size * 0.08, -size * 0.46, size * 0.72, 0, size * 0.08, size * 0.46)

    love.graphics.pop()
end

function StageRenderer:drawOverworldMinimap(puduU, puduV, encountersList, defeatedMap, w, h, font)
    local x, y = 14, 58
    local mw, mh = 212, 122
    local innerX, innerY = x + 8, y + 8
    local innerW, innerH = mw - 16, mh - 16

    -- Outer frame shadow & dark translucent RPG card
    love.graphics.setColor(0.02, 0.03, 0.08, 0.62)
    love.graphics.rectangle("fill", x + 3, y + 4, mw, mh, 8, 8)
    love.graphics.setColor(0.05, 0.09, 0.19, 0.90)
    love.graphics.rectangle("fill", x, y, mw, mh, 7, 7)

    -- Map world (u, v) -> minimap pixel (ascending diagonally bottom-left -> top-right!)
    local function mapPt(u, v)
        local t = clamp(u / 118.0, 0.0, 1.0)
        local bx = innerX + 12 + t * (innerW - 24)
        local by = innerY + innerH - 13 - t * (innerH - 26)
        local perp = clamp((v or 0.0) / 10.0, -1.0, 1.0)
        local px = clamp(bx + perp * 11.0, innerX + 4, innerX + innerW - 4)
        local py = clamp(by + perp * 15.0, innerY + 4, innerY + innerH - 4)
        return px, py
    end

    -- 4 biome colored bands ascending diagonally
    for i = 1, #MINIMAP_BIOME_BANDS do
        local b = MINIMAP_BIOME_BANDS[i]
        local x0a, y0a = mapPt(b.u0, -8.5)
        local x0b, y0b = mapPt(b.u0, 8.5)
        local x1b, y1b = mapPt(b.u1, 8.5)
        local x1a, y1a = mapPt(b.u1, -8.5)
        love.graphics.setColor(b.col[1], b.col[2], b.col[3], 0.42)
        love.graphics.polygon("fill", x0a, y0a, x1a, y1a, x1b, y1b, x0b, y0b)
    end

    -- Subtle river & ocean accent bands on minimap
    local rx0, ry0 = mapPt(27.0, -8.0)
    local rx1, ry1 = mapPt(30.4, -8.0)
    local rx2, ry2 = mapPt(30.4, 8.0)
    local rx3, ry3 = mapPt(27.0, 8.0)
    love.graphics.setColor(0.20, 0.72, 0.88, 0.55)
    love.graphics.polygon("fill", rx0, ry0, rx1, ry1, rx2, ry2, rx3, ry3)

    -- Winding S-path line
    love.graphics.setLineWidth(2.2)
    love.graphics.setColor(0.98, 0.92, 0.74, 0.88)
    local prevX, prevY = mapPt(0.0, StageRenderer.pathCenterV(0.0))
    for u = 3.0, 117.0, 3.0 do
        local nx, ny = mapPt(u, StageRenderer.pathCenterV(u))
        love.graphics.line(prevX, prevY, nx, ny)
        prevX, prevY = nx, ny
    end
    love.graphics.setLineWidth(1)

    -- 9 Encounter dots (amber/red active, green defeated)
    local encList = encountersList or _encounterAnchors
    local defMap = defeatedMap or {}
    for i = 1, #encList do
        local enc = encList[i]
        if enc and enc.u and enc.v then
            local ex, ey = mapPt(enc.u, enc.v)
            local isDef = (defMap[enc.id] == true) or (defMap[i] == true)
            if isDef then
                love.graphics.setColor(0.20, 0.86, 0.52, 0.96)
                love.graphics.circle("fill", ex, ey, 3.2)
            else
                love.graphics.setColor(1.0, 0.84, 0.30, 0.95)
                love.graphics.circle("fill", ex, ey, 4.4)
                love.graphics.setColor(0.96, 0.28, 0.22, 1.0)
                love.graphics.circle("fill", ex, ey, 2.8)
            end
        end
    end

    -- Hero Pudu bright cyan dot with subtle beacon ring
    local px, py = mapPt(puduU or 3.8, puduV or StageRenderer.pathCenterV(puduU or 3.8))
    love.graphics.setColor(0.20, 0.94, 1.0, 0.36)
    love.graphics.circle("fill", px, py, 7.5)
    love.graphics.setColor(0.18, 0.92, 1.0, 1.0)
    love.graphics.circle("fill", px, py, 4.2)
    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    love.graphics.circle("fill", px, py, 2.0)

    -- Corner label "MAPA" (pure ASCII) + vector diagonal NE arrow (ZERO Unicode tofu!)
    local f = font or makeFallbackFont()
    if f then
        love.graphics.setFont(f)
        love.graphics.setColor(0.86, 0.92, 1.0, 0.90)
        love.graphics.print("MAPA", x + 10, y + 6)
    end
    drawVectorNEArrow(x + mw - 19, y + mh - 18, 12)

    -- Clean RPG border
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.70, 0.80, 0.96, 0.88)
    love.graphics.rectangle("line", x, y, mw, mh, 7, 7)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 0.14)
    love.graphics.rectangle("line", x + 3, y + 3, mw - 6, mh - 6, 5, 5)
end

--------------------------------------------------------------------------------
-- 10. Classic JRPG Battle Transition (Double Flash + 10 Diagonal Shutters + Diamond)
--------------------------------------------------------------------------------

function StageRenderer:drawBattleTransition(progress, w, h)
    local p = clamp(progress or 0.0, 0.0, 1.0)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()

    -- 1. Double white flash (0.00..0.16)
    if p < 0.16 then
        local flashA = 0.0
        if p < 0.08 then
            flashA = sin((p / 0.08) * pi) * 0.82
        else
            flashA = sin(((p - 0.08) / 0.08) * pi) * 0.90
        end
        love.graphics.setColor(1.0, 0.99, 0.92, flashA)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
    end

    -- 2. 10 Diagonal shutters sweeping closed (0.12..0.50) and open (0.50..1.00)
    if p >= 0.12 then
        local shutT
        local closing = (p <= 0.50)
        if closing then
            shutT = smoothstep(0.12, 0.48, p)
        else
            shutT = 1.0 - smoothstep(0.52, 0.98, p)
        end

        local numShutters = 10
        local diag = sqrt(sw * sw + sh * sh) + 120
        local stripW = diag / numShutters
        local angle = -0.44

        love.graphics.push()
        love.graphics.translate(sw * 0.5, sh * 0.5)
        love.graphics.rotate(angle)

        for i = 0, numShutters - 1 do
            local stagger = closing and (i / numShutters) * 0.22 or ((numShutters - 1 - i) / numShutters) * 0.22
            local localT = clamp((shutT * 1.24) - stagger, 0.0, 1.0)
            if localT > 0.005 then
                local sx0 = -diag * 0.5 + i * stripW
                local coverW = stripW * localT + 1.5
                -- Deep JRPG midnight navy shutter blade
                love.graphics.setColor(0.04, 0.06, 0.15, 0.98)
                love.graphics.rectangle("fill", sx0, -diag * 0.5, coverW, diag)
                -- Crisp gold-amber leading edge streak while sweeping
                if localT < 0.98 then
                    love.graphics.setColor(0.99, 0.84, 0.30, 0.94)
                    love.graphics.rectangle("fill", sx0 + coverW - 4.0, -diag * 0.5, 4.5, diag)
                end
            end
        end

        love.graphics.pop()

        -- 3. Spinning golden diamond centerpiece (peaks around 0.35..0.60)
        local emblemVis = 0.0
        if p >= 0.14 and p <= 0.86 then
            if p <= 0.50 then
                emblemVis = smoothstep(0.14, 0.34, p)
            else
                emblemVis = 1.0 - smoothstep(0.56, 0.86, p)
            end
        end

        if emblemVis > 0.02 then
            local cx, cy = sw * 0.5, sh * 0.5
            local baseR = min(sw, sh) * 0.16 * (0.45 + 0.65 * emblemVis)
            local rot = p * pi * 2.8

            love.graphics.push()
            love.graphics.translate(cx, cy)
            love.graphics.rotate(rot)

            -- 4-point golden star burst (4 strictly convex triangles)
            love.graphics.setColor(1.0, 0.86, 0.32, 0.42 * emblemVis)
            local rayLen = baseR * 1.75
            local rayBase = baseR * 0.24
            love.graphics.polygon("fill", 0, -rayLen, rayBase, 0, -rayBase, 0)
            love.graphics.polygon("fill", 0, rayLen, -rayBase, 0, rayBase, 0)
            love.graphics.polygon("fill", rayLen, 0, 0, rayBase, 0, -rayBase)
            love.graphics.polygon("fill", -rayLen, 0, 0, -rayBase, 0, rayBase)

            -- Outer golden diamond frame
            love.graphics.setColor(0.99, 0.82, 0.26, 0.96 * emblemVis)
            love.graphics.polygon("fill", 0, -baseR, baseR, 0, 0, baseR, -baseR, 0)

            -- Inner midnight navy diamond
            local midR = baseR * 0.78
            love.graphics.setColor(0.08, 0.13, 0.28, 0.98 * emblemVis)
            love.graphics.polygon("fill", 0, -midR, midR, 0, 0, midR, -midR, 0)

            -- Radiant gold-white core diamond
            local coreR = baseR * 0.42
            love.graphics.setColor(1.0, 0.94, 0.62, 0.98 * emblemVis)
            love.graphics.polygon("fill", 0, -coreR, coreR, 0, 0, coreR, -coreR, 0)

            love.graphics.pop()
        end
    end
end

--------------------------------------------------------------------------------
-- 11. Clean Fase 01 Battle Placeholder Stage (Replaced by HD-2D Arena in Fase 02)
--------------------------------------------------------------------------------

function StageRenderer:drawBattlePlaceholderStage(ctx)
    ctx = ctx or {}
    local sw = ctx.w or love.graphics.getWidth()
    local sh = ctx.h or love.graphics.getHeight()
    local time = ctx.time or 0.0
    local enc = ctx.encounter
    local stageKind = (enc and enc.stage) or ctx.stageKind or "plaza"
    local biomeId = (enc and enc.biome) or STAGE_TO_BIOME[stageKind] or "bosque"
    local theme = ctx.theme
    local assets = ctx.assets
    local pal = resolveSkyPalette(theme, stageKind)

    -- 1. Sky + Sun + Clouds + 2 Parallax Biome Horizon Layers
    local horizonFrac = 0.46
    local horizonY = floor(sh * horizonFrac)
    self:drawSkyAndHorizon(theme, sw, sh, time, horizonFrac, stageKind)

    -- 2. Clean stylized battle ground floor (no Fase 02 shaders yet)
    local floorH = sh - horizonY
    local bands = 8
    for i = 0, bands - 1 do
        local t0 = i / bands
        local t1 = (i + 1) / bands
        local y0 = horizonY + floor(floorH * (t0 ^ 1.25))
        local y1 = horizonY + floor(floorH * (t1 ^ 1.25)) + 1
        local mix = t0
        local r = lerp(pal.groundB[1], pal.groundA[1], mix)
        local g = lerp(pal.groundB[2], pal.groundA[2], mix)
        local b = lerp(pal.groundB[3], pal.groundA[3], mix)
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.rectangle("fill", 0, y0, sw, max(2, y1 - y0))
    end

    -- Stage-specific center arena detail
    if stageKind == "oficina" then
        love.graphics.setColor(0.74, 0.14, 0.18, 0.92)
        love.graphics.polygon("fill", sw * 0.24, horizonY + 12, sw * 0.76, horizonY + 12, sw * 0.88, sh, sw * 0.12, sh)
        love.graphics.setColor(0.96, 0.80, 0.28, 0.85)
        love.graphics.setLineWidth(3)
        love.graphics.line(sw * 0.24, horizonY + 12, sw * 0.12, sh)
        love.graphics.line(sw * 0.76, horizonY + 12, sw * 0.88, sh)
        love.graphics.setLineWidth(1)
    elseif stageKind == "muelle" then
        love.graphics.setColor(0.58, 0.42, 0.26, 0.94)
        love.graphics.rectangle("fill", 0, horizonY + 18, sw, floorH)
        love.graphics.setColor(0.32, 0.20, 0.10, 0.65)
        for py = horizonY + 34, sh, 28 do
            love.graphics.line(0, py, sw, py)
        end
    else
        love.graphics.setColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 0.16)
        love.graphics.ellipse("fill", sw * 0.5, sh * 0.66, sw * 0.34, sh * 0.13)
    end

    -- 3. Pulsing stance rings at canonical battle anchors (0.28w, 0.65h) and (0.72w, 0.65h)
    local anchors = StageRenderer.getBattleAnchors(sw, sh)
    local pulse = 0.5 + 0.5 * sin(time * 4.2)

    love.graphics.setColor(0.24, 0.86, 0.98, 0.22 + 0.10 * pulse)
    love.graphics.ellipse("fill", anchors.puduX, anchors.puduY + 8, 66 + pulse * 6, 22 + pulse * 2)
    love.graphics.setColor(0.38, 0.94, 1.0, 0.78)
    love.graphics.setLineWidth(2)
    love.graphics.ellipse("line", anchors.puduX, anchors.puduY + 8, 62 + pulse * 5, 20 + pulse * 2)

    love.graphics.setColor(0.98, 0.34, 0.28, 0.22 + 0.10 * pulse)
    love.graphics.ellipse("fill", anchors.enemyX, anchors.enemyY + 8, 72 + pulse * 6, 24 + pulse * 2)
    love.graphics.setColor(1.0, 0.78, 0.32, 0.80)
    love.graphics.ellipse("line", anchors.enemyX, anchors.enemyY + 8, 68 + pulse * 5, 22 + pulse * 2)
    love.graphics.setLineWidth(1)

    -- 4. Optional actor preview draw (defaults to true so main.lua can use out of the box)
    if ctx.drawActors ~= false and assets then
        local animCol = (floor(time * 6.0) % 6) + 1
        local puduBob = sin(time * 5.2) * 3.5
        drawPuduWithHat(anchors.puduX, anchors.puduY, 2, animCol, 124.0, puduBob, assets)

        if enc then
            local encPair = assets.encounters and assets.encounters[enc.id]
            local enemyBob = -sin(time * 4.4) * 3.0
            local targetH = 152.0
            love.graphics.setColor(0.03, 0.04, 0.08, 0.34)
            love.graphics.ellipse("fill", anchors.enemyX, anchors.enemyY + 4, 42, 14)
            if encPair and encPair.diff then
                local img = encPair.diff
                local quad = nil
                local fw, fh
                if encPair.isSheet and encPair.quads then
                    local rowTable = encPair.quads[enc.sheetRow or 1] or encPair.quads[0]
                    if rowTable and #rowTable > 0 then
                        quad = rowTable[(floor(time * 5.0) % #rowTable) + 1]
                        local _, _, qw, qh = quad:getViewport()
                        fw, fh = qw, qh
                    end
                end
                if not fw then fw, fh = img:getDimensions() end
                local sc = targetH / max(1, fh)
                love.graphics.setColor(1, 1, 1, 1)
                if quad then
                    love.graphics.draw(img, quad, anchors.enemyX, anchors.enemyY + enemyBob, 0, sc, sc, fw * 0.5, fh * 0.92)
                else
                    love.graphics.draw(img, anchors.enemyX, anchors.enemyY + enemyBob, 0, sc, sc, fw * 0.5, fh * 0.92)
                end
            end
        end
    end

    return anchors, biomeId
end

return StageRenderer
