-- stage_renderer.lua
-- Overworld isometric diagonal (NE / up-right) renderer, 3D irregular terrain,
-- calm room-snapped camera, biome landmarks/decor (Modo A & Modo B seamless),
-- diagonal minimap, JRPG battle transition, dedicated side-view HD-2D Battle Arena,
-- 4 lighting presets, dynamic point lights, atmospheric halos/sunbeams, and post-processing.
-- LÖVE2D 11.5 (LuaJIT) — Zero Unicode tofu (R2), safeSend/hasUniform (R4), zero per-frame GPU allocations.

local Encounters = require("encounters")

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
local unpack = table.unpack or unpack

--------------------------------------------------------------------------------
-- 0. Rule R4 Safe GLSL Uniform Dispatch (Cached hasUniform, ZERO raw :send)
--------------------------------------------------------------------------------

local _uniformCache = setmetatable({}, { __mode = "k" })

local function hasUniformCached(shader, name)
    if not shader or type(name) ~= "string" then
        return false
    end
    local cache = _uniformCache[shader]
    if not cache then
        cache = {}
        _uniformCache[shader] = cache
    end
    local known = cache[name]
    if known == nil then
        local ok, exists = pcall(shader.hasUniform, shader, name)
        known = (ok and exists == true)
        cache[name] = known
    end
    return known
end

local function safeSend(shader, name, ...)
    if select("#", ...) == 0 or select(1, ...) == nil then
        return false
    end
    if hasUniformCached(shader, name) then
        local ok = pcall(shader.send, shader, name, ...)
        return ok == true
    end
    return false
end

local function normalizeVec3(x, y, z)
    local len = sqrt(x * x + y * y + z * z)
    if len <= 1e-6 then
        return { 0.0, -0.707107, 0.707107 }
    end
    return { x / len, y / len, z / len }
end

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

local RIVER_START, RIVER_END = 79.0, 82.4
local BAY_START, BAY_END = 27.4, 42.6
local MARSH_START, MARSH_END = 42.8, 50.8
local LIGHTHOUSE_U, LIGHTHOUSE_V = 38.5, -8.8

local DESERT_ARRIVAL = {
    startU = 2.7, startV = 0.0, deckHeight = 32,
    finishU = 2.7, finishV = 0.7,
}
StageRenderer.DESERT_ARRIVAL = DESERT_ARRIVAL
local TRUCK_HALF_WIDTH, TRUCK_LENGTH = 0.76, 3.25
local ARICA_SIGN_U, ARICA_SIGN_V = 4.1, 5.15
local BODOQUE = {
    u = 7.15,
    v = 2.0,
    height = 102,
    enterRadius = 2.35,
    leaveRadius = 2.85,
    name = "Juan Carlos Bodoque",
    line = "¡La ruta de la caca!",
}

-- 6 explorable side alcoves distributed across all 4 biomes, each reachable from main path.
StageRenderer.SIDE_ALCOVES = {
    { id = "bosque_rewe",      name = "Claro del Rewe",       biome = "bosque",   u = 68.0,  v = 6.4,  r = 2.6, prop = "rewe_totem" },
    { id = "bosque_orbe",      name = "Santuario del Orbe",   biome = "bosque",   u = 76.0,  v = 3.5,  r = 2.5, prop = "orb_shrine" },
    { id = "atacama_mirador",  name = "Mirador del Sol",      biome = "desierto", u = 8.5,   v = 5.1,  r = 2.6, prop = "apacheta_sundial" },
    { id = "atacama_cristal",  name = "Gruta de Cristales",   biome = "desierto", u = 19.0,  v = -2.9, r = 2.6, prop = "mountain_crystal" },
    { id = "costa_mirador",    name = "Mirador de la Costa",  biome = "costa",    u = 45.8,  v = -4.3, r = 2.5, prop = "pincoya_shrine" },
    { id = "chiloe_mirador",   name = "Mirador de Chiloé",    biome = "chiloe",   u = 103.5, v = -1.4, r = 2.6, prop = "pincoya_shrine" },
}

-- Wizard hat head-anchor offsets (in 64x64 sprite pixels relative to bottom-center foot anchor)
-- Rows: 0=S, 1=SE, 2=E, 3=NE, 4=N, 5=NW, 6=W, 7=SW
StageRenderer.HAT_HEAD_OFFSETS = {
    [0] = { x = 0.0,  y = -40.0 },
    [1] = { x = 5.0,  y = -40.0 },
    [2] = { x = 8.5,  y = -41.0 },
    [3] = { x = 5.0,  y = -41.0 },
    [4] = { x = 0.0,  y = -41.0 },
    [5] = { x = -5.0, y = -41.0 },
    [6] = { x = -8.5, y = -41.0 },
    [7] = { x = -5.0, y = -40.0 },
}

-- Biome visual palette & tile mapping (used for 3D skirts, minimap, and Modo B fallback)
StageRenderer.BIOME_VISUALS = {
    bosque = {
        id = "bosque",
        name = "Bosque Valdiviano",
        floorTile = "grass_floor",
        pathTile = "stone_floor",
        cliffTile = "mountain_floor",
        backdrop = { 0.14, 0.27, 0.17 },
        groundTint = { 0.77, 0.93, 0.78 },
        pathTint = { 0.84, 0.91, 0.75 },
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
        groundTint = { 0.91, 0.78, 0.65 },
        plateauTint = { 0.78, 0.57, 0.48 },
        pathTint = { 1.00, 0.93, 0.79 },
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
        groundTint = { 0.91, 1.04, 1.09 },
        pathTint = { 0.89, 0.99, 1.08 },
        alcoveTint = { 0.84, 0.96, 0.96 },
        cliffTopTint = { 0.88, 0.88, 0.84 },
        cliffLeft = { 0.46, 0.49, 0.54 },
        cliffRight = { 0.30, 0.33, 0.40 },
        cliffLip = { 0.78, 0.76, 0.64 },
        cliffBand = { 0.66, 0.76, 0.82 },
        miniCol = { 0.20, 0.60, 0.78 },
        hazeCol = { 0.82, 0.94, 0.98 },
    },
    chiloe = {
        id = "chiloe",
        name = "Chiloé",
        floorTile = "grass_floor",
        pathTile = "stone_floor",
        cliffTile = "coast_floor",
        backdrop = { 0.18, 0.20, 0.29 },
        groundTint = { 0.68, 0.85, 0.76 },
        pathTint = { 0.84, 0.95, 1.08 },
        alcoveTint = { 0.94, 0.90, 1.00 },
        cliffTopTint = { 0.78, 0.80, 0.90 },
        cliffLeft = { 0.44, 0.47, 0.58 },
        cliffRight = { 0.27, 0.30, 0.40 },
        cliffLip = { 0.80, 0.84, 0.94 },
        cliffBand = { 0.64, 0.68, 0.80 },
        miniCol = { 0.42, 0.52, 0.80 },
        hazeCol = { 0.92, 0.80, 0.68 },
    },
}

--------------------------------------------------------------------------------
-- 1B. HD-2D Lighting Presets, Stage Tile Map & Battle Arena Decor
--------------------------------------------------------------------------------

StageRenderer.LIGHTING_ORDER = { "dia", "atardecer", "noche", "dramatico" }

StageRenderer.LIGHTING_PRESETS = {
    dia = {
        id = "dia",
        label = "Día Soleado",
        ambientMul = { 0.72, 0.76, 0.84 },
        ambientAdd = { 0.07, 0.07, 0.06 },
        sunEnergy = 1.15,
        sunColor = { 1.00, 0.96, 0.86 },
        sunDir = normalizeVec3(-0.46, -0.58, 0.67),
        skyTint = { 1.00, 1.00, 1.00 },
        skyDarken = 0.0,
        vignette = 0.14,
        bloomStrength = 0.14,
        beamStrength = 0.24,
        beamColor = { 1.00, 0.96, 0.82 },
        lanternBoost = 0.25,
        showStars = false,
        isMoon = false,
        dofEnabled = 0.0,
    },
    atardecer = {
        id = "atardecer",
        label = "Atardecer Dorado",
        ambientMul = { 0.74, 0.56, 0.52 },
        ambientAdd = { 0.08, 0.03, 0.01 },
        sunEnergy = 1.25,
        sunColor = { 1.00, 0.68, 0.34 },
        sunDir = normalizeVec3(-0.70, -0.36, 0.62),
        skyTint = { 1.04, 0.72, 0.56 },
        skyDarken = 0.14,
        vignette = 0.22,
        bloomStrength = 0.20,
        beamStrength = 0.56,
        beamColor = { 1.00, 0.76, 0.38 },
        lanternBoost = 0.72,
        showStars = false,
        isMoon = false,
        dofEnabled = 0.0,
    },
    noche = {
        id = "noche",
        label = "Noche Neón",
        ambientMul = { 0.44, 0.52, 0.76 },
        ambientAdd = { 0.05, 0.07, 0.12 },
        sunEnergy = 0.42,
        sunColor = { 0.58, 0.74, 1.00 },
        sunDir = normalizeVec3(0.36, -0.64, 0.68),
        skyTint = { 0.26, 0.34, 0.58 },
        skyDarken = 0.52,
        vignette = 0.30,
        bloomStrength = 0.22,
        beamStrength = 0.0,
        beamColor = { 0.58, 0.76, 1.00 },
        lanternBoost = 1.35,
        showStars = true,
        isMoon = true,
        dofEnabled = 0.0,
    },
    dramatico = {
        id = "dramatico",
        label = "Foco Teatral",
        ambientMul = { 0.36, 0.38, 0.52 },
        ambientAdd = { 0.03, 0.03, 0.05 },
        sunEnergy = 1.28,
        sunColor = { 1.00, 0.90, 0.68 },
        sunDir = normalizeVec3(-0.28, -0.82, 0.50),
        skyTint = { 0.52, 0.48, 0.66 },
        skyDarken = 0.38,
        vignette = 0.36,
        bloomStrength = 0.22,
        beamStrength = 0.62,
        beamColor = { 1.00, 0.92, 0.66 },
        lanternBoost = 1.10,
        showStars = false,
        isMoon = false,
        dofEnabled = 0.0,
    },
}

local LIGHTING_ALIASES = {
    dia = "dia",
    ["día"] = "dia",
    atardecer = "atardecer",
    noche = "noche",
    dramatico = "dramatico",
    ["dramático"] = "dramatico",
    teatral = "dramatico",
}

StageRenderer.THEME_TILES = {
    plaza   = { floor = "grass_floor",  path = "stone_floor" },
    bosque  = { floor = "grass_floor",  path = "stone_floor" },
    mirador = { floor = "desert_floor", path = "stone_floor" },
    vereda  = { floor = "desert_floor", path = "stone_floor" },
    muelle  = { floor = "coast_floor",  path = "stone_floor" },
    chiloe  = { floor = "coast_floor",  path = "stone_floor" },
    pantano = { floor = "coast_floor",  path = "stone_floor" },
    esquina = { floor = "stone_floor",  path = "mountain_floor" },
    oficina = { floor = "stone_floor",  path = "mountain_floor" },
}

-- Curated HD-2D side-view battle arena framing props for battle stages.
-- Composition rule: Pudú at (0.28w, 0.65h) and Rival at (0.72w, 0.65h) stay 100% unobstructed.
-- All non-fg props are placed along the far horizon (yFrac <= 0.50) or outer flanks (xFrac <= 0.16 or >= 0.84).
-- Foreground corner framing props (layer = "fg") sit strictly at xFrac = 0.03 and 0.97, yFrac = 0.84.
StageRenderer.BATTLE_STAGE_DECOR = {
    plaza = {
        { kind = "stone_pedestal",  xFrac = 0.48, yFrac = 0.39, scale = 0.68, biome = "bosque" },
        { kind = "araucaria_tree",  xFrac = 0.09, yFrac = 0.40, scale = 0.92, biome = "bosque" },
        { kind = "lantern_post",    xFrac = 0.17, yFrac = 0.41, scale = 0.78, biome = "bosque" },
        { kind = "lantern_post",    xFrac = 0.86, yFrac = 0.40, scale = 0.78, biome = "bosque" },
        { kind = "araucaria_tree",  xFrac = 0.93, yFrac = 0.41, scale = 0.94, biome = "bosque" },
        { kind = "lantern_post",    xFrac = 0.07, yFrac = 0.56, scale = 1.02, biome = "bosque" },
        { kind = "lantern_post",    xFrac = 0.93, yFrac = 0.58, scale = 1.04, biome = "bosque" },
        { kind = "copihue",         xFrac = 0.12, yFrac = 0.62, scale = 0.92, biome = "bosque" },
        { kind = "valdivian_shrub", xFrac = 0.89, yFrac = 0.64, scale = 0.96, biome = "bosque" },
        { kind = "copihue",         xFrac = 0.03, yFrac = 0.84, scale = 1.08, biome = "bosque", layer = "fg" },
        { kind = "valdivian_fern",  xFrac = 0.97, yFrac = 0.84, scale = 1.08, biome = "bosque", layer = "fg" },
    },
    bosque = {
        { kind = "rewe_totem",      xFrac = 0.44, yFrac = 0.39, scale = 0.74, biome = "bosque" },
        { kind = "orb_shrine",      xFrac = 0.54, yFrac = 0.40, scale = 0.70, biome = "bosque" },
        { kind = "ancient_tree",    xFrac = 0.12, yFrac = 0.40, scale = 0.98, biome = "bosque" },
        { kind = "araucaria_tree",  xFrac = 0.91, yFrac = 0.40, scale = 1.00, biome = "bosque" },
        { kind = "araucaria_tree",  xFrac = 0.06, yFrac = 0.56, scale = 1.12, biome = "bosque" },
        { kind = "ancient_tree",    xFrac = 0.94, yFrac = 0.58, scale = 1.10, biome = "bosque" },
        { kind = "mossy_boulder",   xFrac = 0.13, yFrac = 0.60, scale = 0.90, biome = "bosque" },
        { kind = "valdivian_fern",  xFrac = 0.88, yFrac = 0.64, scale = 1.00, biome = "bosque" },
        { kind = "valdivian_fern",  xFrac = 0.03, yFrac = 0.84, scale = 1.12, biome = "bosque", layer = "fg" },
        { kind = "copihue",         xFrac = 0.97, yFrac = 0.84, scale = 1.10, biome = "bosque", layer = "fg" },
    },
    mirador = {
        { kind = "apacheta_sundial", xFrac = 0.48, yFrac = 0.39, scale = 0.78, biome = "desierto" },
        { kind = "rock_monolith",    xFrac = 0.12, yFrac = 0.40, scale = 0.90, biome = "desierto" },
        { kind = "mountain_crystal", xFrac = 0.86, yFrac = 0.40, scale = 0.82, biome = "desierto" },
        { kind = "desert_cactus",    xFrac = 0.93, yFrac = 0.41, scale = 0.88, biome = "desierto" },
        { kind = "desert_cactus",    xFrac = 0.07, yFrac = 0.56, scale = 1.08, biome = "desierto" },
        { kind = "rock_monolith",    xFrac = 0.93, yFrac = 0.58, scale = 1.02, biome = "desierto" },
        { kind = "mountain_crystal", xFrac = 0.13, yFrac = 0.60, scale = 0.96, biome = "desierto" },
        { kind = "mountain_crystal", xFrac = 0.88, yFrac = 0.63, scale = 1.00, biome = "desierto" },
        { kind = "desert_cactus",    xFrac = 0.03, yFrac = 0.84, scale = 1.02, biome = "desierto", layer = "fg" },
        { kind = "mountain_crystal", xFrac = 0.97, yFrac = 0.84, scale = 1.06, biome = "desierto", layer = "fg" },
    },
    vereda = {
        { kind = "moai_relic",       xFrac = 0.49, yFrac = 0.39, scale = 0.78, biome = "desierto" },
        { kind = "desert_cactus",    xFrac = 0.10, yFrac = 0.40, scale = 0.90, biome = "desierto" },
        { kind = "lantern_post",     xFrac = 0.17, yFrac = 0.41, scale = 0.80, biome = "desierto" },
        { kind = "lantern_post",     xFrac = 0.86, yFrac = 0.40, scale = 0.80, biome = "desierto" },
        { kind = "desert_cactus",    xFrac = 0.93, yFrac = 0.41, scale = 0.90, biome = "desierto" },
        { kind = "lantern_post",     xFrac = 0.07, yFrac = 0.56, scale = 1.02, biome = "desierto" },
        { kind = "desert_cactus",    xFrac = 0.92, yFrac = 0.59, scale = 1.06, biome = "desierto" },
        { kind = "apacheta_sundial", xFrac = 0.13, yFrac = 0.61, scale = 0.90, biome = "desierto" },
        { kind = "rock_monolith",    xFrac = 0.88, yFrac = 0.63, scale = 0.88, biome = "desierto" },
        { kind = "apacheta_sundial", xFrac = 0.03, yFrac = 0.84, scale = 1.00, biome = "desierto", layer = "fg" },
        { kind = "desert_cactus",    xFrac = 0.97, yFrac = 0.84, scale = 1.00, biome = "desierto", layer = "fg" },
    },
    muelle = {
        { kind = "pincoya_shrine",   xFrac = 0.52, yFrac = 0.39, scale = 0.68, biome = "costa" },
        { kind = "lantern_post",     xFrac = 0.16, yFrac = 0.40, scale = 0.82, biome = "costa" },
        { kind = "lantern_post",     xFrac = 0.84, yFrac = 0.40, scale = 0.82, biome = "costa" },
        { kind = "coast_lighthouse", xFrac = 0.93, yFrac = 0.40, scale = 0.94, biome = "costa" },
        { kind = "lantern_post",     xFrac = 0.07, yFrac = 0.57, scale = 1.04, biome = "costa" },
        { kind = "lantern_post",     xFrac = 0.91, yFrac = 0.59, scale = 1.04, biome = "costa" },
        { kind = "mossy_boulder",    xFrac = 0.13, yFrac = 0.62, scale = 0.82, biome = "costa" },
        { kind = "valdivian_shrub",  xFrac = 0.94, yFrac = 0.64, scale = 0.84, biome = "costa" },
        { kind = "stanchion",        xFrac = 0.03, yFrac = 0.84, scale = 1.12, biome = "costa", layer = "fg" },
        { kind = "stanchion",        xFrac = 0.97, yFrac = 0.84, scale = 1.12, biome = "costa", layer = "fg" },
    },
    pantano = {
        { kind = "pincoya_shrine",   xFrac = 0.48, yFrac = 0.39, scale = 0.76, biome = "costa" },
        { kind = "ancient_tree",     xFrac = 0.09, yFrac = 0.40, scale = 0.94, biome = "costa" },
        { kind = "valdivian_fern",   xFrac = 0.58, yFrac = 0.40, scale = 0.82, biome = "costa" },
        { kind = "ancient_tree",     xFrac = 0.92, yFrac = 0.40, scale = 0.94, biome = "costa" },
        { kind = "valdivian_fern",   xFrac = 0.07, yFrac = 0.56, scale = 1.06, biome = "costa" },
        { kind = "mossy_boulder",    xFrac = 0.93, yFrac = 0.58, scale = 1.02, biome = "costa" },
        { kind = "lily_pad",         xFrac = 0.13, yFrac = 0.62, scale = 1.02, biome = "costa" },
        { kind = "lily_pad",         xFrac = 0.88, yFrac = 0.64, scale = 1.02, biome = "costa" },
        { kind = "valdivian_fern",   xFrac = 0.03, yFrac = 0.84, scale = 1.12, biome = "costa", layer = "fg" },
        { kind = "lily_pad",         xFrac = 0.97, yFrac = 0.84, scale = 1.08, biome = "costa", layer = "fg" },
    },
    esquina = {
        { kind = "stone_pedestal",   xFrac = 0.48, yFrac = 0.39, scale = 0.70, biome = "ciudad" },
        { kind = "biome_arch",       xFrac = 0.10, yFrac = 0.40, scale = 0.86, biome = "ciudad", extra = "harbor" },
        { kind = "lantern_post",     xFrac = 0.17, yFrac = 0.41, scale = 0.80, biome = "ciudad" },
        { kind = "lantern_post",     xFrac = 0.85, yFrac = 0.40, scale = 0.80, biome = "ciudad" },
        { kind = "biome_arch",       xFrac = 0.92, yFrac = 0.40, scale = 0.86, biome = "ciudad", extra = "harbor" },
        { kind = "lantern_post",     xFrac = 0.07, yFrac = 0.57, scale = 1.04, biome = "ciudad" },
        { kind = "lantern_post",     xFrac = 0.93, yFrac = 0.59, scale = 1.04, biome = "ciudad" },
        { kind = "stone_pedestal",   xFrac = 0.88, yFrac = 0.64, scale = 0.88, biome = "ciudad" },
        { kind = "debris_pile",      xFrac = 0.13, yFrac = 0.62, scale = 0.88, biome = "ciudad" },
        { kind = "debris_pile",      xFrac = 0.03, yFrac = 0.84, scale = 1.00, biome = "ciudad", layer = "fg" },
        { kind = "stanchion",        xFrac = 0.97, yFrac = 0.84, scale = 1.12, biome = "ciudad", layer = "fg" },
    },
    oficina = {
        { kind = "orb_shrine",       xFrac = 0.48, yFrac = 0.39, scale = 0.80, biome = "ciudad" },
        { kind = "office_column",    xFrac = 0.10, yFrac = 0.40, scale = 0.98, biome = "ciudad" },
        { kind = "lantern_post",     xFrac = 0.17, yFrac = 0.41, scale = 0.80, biome = "ciudad" },
        { kind = "lantern_post",     xFrac = 0.85, yFrac = 0.40, scale = 0.80, biome = "ciudad" },
        { kind = "office_column",    xFrac = 0.92, yFrac = 0.40, scale = 0.98, biome = "ciudad" },
        { kind = "office_column",    xFrac = 0.06, yFrac = 0.58, scale = 1.12, biome = "ciudad" },
        { kind = "office_column",    xFrac = 0.94, yFrac = 0.60, scale = 1.12, biome = "ciudad" },
        { kind = "stanchion",        xFrac = 0.13, yFrac = 0.62, scale = 1.00, biome = "ciudad" },
        { kind = "stanchion",        xFrac = 0.88, yFrac = 0.64, scale = 1.04, biome = "ciudad" },
        { kind = "stanchion",        xFrac = 0.03, yFrac = 0.84, scale = 1.14, biome = "ciudad", layer = "fg" },
        { kind = "stanchion",        xFrac = 0.97, yFrac = 0.84, scale = 1.14, biome = "ciudad", layer = "fg" },
    },
}

StageRenderer.BATTLE_STAGE_DECOR.chiloe = StageRenderer.BATTLE_STAGE_DECOR.muelle

-- Default sky palettes when theme is omitted or partial (supports both biome IDs and stage kinds)
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
    chiloe = "chiloe",
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

local _encounterAnchors = {}

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
    return Encounters.getBiomeAtU(u).id
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

StageRenderer.setEncounters(Encounters.LIST)

function StageRenderer.isBosqueBridge(u, v)
    if u < RIVER_START - 0.7 or u > RIVER_END + 0.7 then
        return false
    end
    local pc = StageRenderer.pathCenterV(u)
    return abs(v - pc) <= 2.45
end

function StageRenderer.isCostaPier(u, v)
    if u < BAY_START - 0.4 or u > BAY_END + 0.4 then
        return false
    end
    local pc = StageRenderer.pathCenterV(u)
    if abs(v - pc) <= 2.55 then
        return true
    end
    -- Widened wharf platform around Gaviota Mafiosa (u=34.0, v=-1.4) so it stands cleanly on pier deck.
    if u >= 30.6 and u <= 37.4 then
        local du = u - 34.0
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
    -- Atacama plateau with a ramp down to the coast.
    if u >= 0.0 and u <= 22.0 then
        local up = smoothstep(0.0, 2.5, u)
        local down = 1.0 - smoothstep(19.0, 22.0, u)
        return 1.05 * up * down
    end

    -- Costa marsh low wetland
    if u >= MARSH_START and u <= MARSH_END then
        local into = smoothstep(MARSH_START, MARSH_START + 0.8, u)
        local out = 1.0 - smoothstep(MARSH_END - 0.8, MARSH_END, u)
        return -0.08 * into * out
    end

    -- Chiloé terraces approaching the final dock:
    -- Terrace 1: u = 93.0..96.0 -> +0.55
    -- Terrace 2: u = 105.0..108.5 -> +1.15 through 118+
    if u >= 93.0 then
        local t1 = smoothstep(93.0, 96.0, u) * 0.55
        local t2 = smoothstep(105.0, 108.5, u) * 0.60
        return t1 + t2
    end

    return 0.0
end

local DESERT_PULLOUT_ELEV = evalBaseCorridorElev(DESERT_ARRIVAL.startU)

local function desertPulloutMask(u, v)
    local distance = abs(u - DESERT_ARRIVAL.startU)
    if distance >= 1.75 or v <= -4.5 or v >= DESERT_ARRIVAL.finishV then
        return 0.0
    end
    local width = 1.0 - smoothstep(TRUCK_HALF_WIDTH, 1.75, distance)
    local length = smoothstep(-4.5, -TRUCK_LENGTH, v)
        * (1.0 - smoothstep(DESERT_ARRIVAL.startV, DESERT_ARRIVAL.finishV, v))
    return width * length
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
    if u >= RIVER_START and u <= RIVER_END then
        return -0.35
    end
    -- 3. Costa wooden pier over ocean (including widened Gaviota Mafiosa dock)
    if StageRenderer.isCostaPier(u, v) then
        return 0.42
    end
    -- 4. Costa Pacific ocean bay (extends seamlessly across screen)
    if u >= BAY_START and u <= BAY_END then
        -- Small rocky outcrop for the Valparaíso lighthouse.
        local ldu = u - LIGHTHOUSE_U
        local ldv = v - LIGHTHOUSE_V
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
    local pullout = desertPulloutMask(u, v)
    local flatMask = max(encMask, alcMask, pullout)
    baseElev = lerp(baseElev, DESERT_PULLOUT_ELEV, pullout)

    -- Dry stone overlook alcove beside the marsh (only on the alcove's own side away from the marsh path!)
    if inAlcove and u >= MARSH_START and u <= MARSH_END and (v - pc) < -1.8 then
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
    if u >= RIVER_START and u <= RIVER_END then
        return "river"
    end

    -- 2. Pier & Ocean (Costa)
    if StageRenderer.isCostaPier(u, v) then
        return "pier"
    end
    if u >= BAY_START and u <= BAY_END then
        local ldu = u - LIGHTHOUSE_U
        local ldv = v - LIGHTHOUSE_V
        if (ldu * ldu + ldv * ldv) <= 5.8 then
            return "cliff"
        end
        return "water"
    end

    local pc = StageRenderer.pathCenterV(u)
    local encMask, inEncDisk, inEncLane = evalEncounterMask(u, v)
    local alcMask, inAlcove = evalAlcoveMask(u, v)
    local flatMask = max(encMask, alcMask, desertPulloutMask(u, v))

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

    -- 6. Marsh with a dry stepping trail along the main path
    if u >= MARSH_START and u <= MARSH_END then
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

    if abs(u - DESERT_ARRIVAL.startU) <= TRUCK_HALF_WIDTH and v >= -TRUCK_LENGTH and v <= 0.0 then
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

    if terrain == "bridge" or terrain == "pier" then
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
    -- Classic Pokémon-style diagonal battle perspective:
    -- Pudú foreground bottom-left (lower hooves tucked cleanly behind bottom strip)
    -- Rival upper-right with generous top/right padding
    return {
        puduX = sw * 0.27,
        puduY = sh * 0.915,
        enemyX = sw * 0.72,
        enemyY = sh * 0.50,
        puduScaleH = 212.0,
        enemyScaleH = 148.0,
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
    local lightPosBuf = {}
    local lightColBuf = {}
    local lightsPool = {}
    for i = 1, 10 do
        lightPosBuf[i] = { 0.0, 0.0, 1.0, 0.0 }
        lightColBuf[i] = { 0.0, 0.0, 0.0, 0.0 }
        lightsPool[i] = {
            x = 0.0, y = 0.0, radius = 120.0, height = 60.0,
            r = 1.0, g = 0.8, b = 0.4, energy = 0.0, haloScale = 0.75,
        }
    end
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
        _tileContact = {},
        _tileSlope = {},
        _floorBandMesh = nil,
        _unitWhite = nil,
        _elevCache = {},
        _drawList = {},
        _drawPool = {},
        _drawCount = 0,
        _bodoqueNearby = false,
        _bodoqueDialogue = 0.0,
        _bodoqueGesture = 0.0,
        -- Phase 2 HD-2D Lighting & Shader State
        lightingPreset = "dia",
        shaders = nil,
        useLitShader = true,
        disableBloom = false,
        _ambBuf = { 0.5, 0.5, 0.6 },
        _sunDirBuf = { -0.46, -0.58, 0.67 },
        _sunColBuf = { 1.0, 0.96, 0.86 },
        _screenSizeBuf = { 1280.0, 720.0 },
        _texelSizeBuf = { 1.0 / 1280.0, 1.0 / 720.0 },
        _emissiveColBuf = { 1.0, 1.0, 1.0 },
        _lightPosBuf = lightPosBuf,
        _lightColBuf = lightColBuf,
        _lightsList = {},
        _lightsPool = lightsPool,
        _lightsCount = 0,
    }, StageRenderer)
    return self
end

--------------------------------------------------------------------------------
-- 4B. HD-2D Lighting Presets, Shader Config & Lit Sprite Pipeline
--------------------------------------------------------------------------------

function StageRenderer:setShaders(shaderSet)
    self.shaders = shaderSet
end

function StageRenderer:setLightingPreset(presetId)
    local raw = (type(presetId) == "string") and presetId:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    local resolved = LIGHTING_ALIASES[raw]
    if resolved and StageRenderer.LIGHTING_PRESETS[resolved] then
        self.lightingPreset = resolved
    elseif raw == "" then
        self.lightingPreset = "dia"
    end
    return self.lightingPreset, StageRenderer.LIGHTING_PRESETS[self.lightingPreset]
end

function StageRenderer:cycleLightingPreset()
    local order = StageRenderer.LIGHTING_ORDER
    local cur = self.lightingPreset or "dia"
    local nextIdx = 1
    for i = 1, #order do
        if order[i] == cur then
            nextIdx = (i % #order) + 1
            break
        end
    end
    self.lightingPreset = order[nextIdx]
    return self.lightingPreset, StageRenderer.LIGHTING_PRESETS[self.lightingPreset]
end

function StageRenderer:getLightingPreset()
    local id = self.lightingPreset or "dia"
    local preset = StageRenderer.LIGHTING_PRESETS[id] or StageRenderer.LIGHTING_PRESETS.dia
    return preset, preset.id
end

function StageRenderer:setBloomEnabled(enabled)
    self.disableBloom = (enabled == false)
end

function StageRenderer:_getUnitWhite()
    if not self._unitWhite then
        local data = love.image.newImageData(2, 2)
        for y = 0, 1 do
            for x = 0, 1 do
                data:setPixel(x, y, 1, 1, 1, 1)
            end
        end
        local img = love.graphics.newImage(data)
        img:setFilter("nearest", "nearest")
        self._unitWhite = img
    end
    return self._unitWhite
end

function StageRenderer:_ensureFloorBandMesh()
    if not self._floorBandMesh then
        self._floorBandMesh = love.graphics.newMesh(4, "fan", "stream")
    end
    return self._floorBandMesh
end

function StageRenderer:configureLitShader(theme, screenW, screenH, time, extraLights, litShaderOpt, overworld)
    local litShader = litShaderOpt or (self.shaders and self.shaders.lit)
    if not litShader or not self.useLitShader then
        return nil
    end

    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia
    local sw = screenW or love.graphics.getWidth()
    local sh = screenH or love.graphics.getHeight()

    local themeTbl = nil
    if type(theme) == "table" then
        themeTbl = theme
    elseif type(theme) == "string" then
        local bId = STAGE_TO_BIOME[theme] or theme
        themeTbl = DEFAULT_SKY_THEMES[bId] or DEFAULT_SKY_THEMES.bosque
    end

    -- Harmonize biome ambient with active preset (high readability across dia/atardecer/noche/dramatico)
    local tAmb = (themeTbl and themeTbl.ambientColor) or { 0.48, 0.52, 0.60 }
    local baseR = lerp(1.0, tAmb[1] or 0.48, 0.52)
    local baseG = lerp(1.0, tAmb[2] or 0.52, 0.52)
    local baseB = lerp(1.0, tAmb[3] or 0.60, 0.52)

    local mul = preset.ambientMul
    local add = preset.ambientAdd or { 0.0, 0.0, 0.0 }
    local ambBuf = self._ambBuf
    ambBuf[1] = clamp(baseR * mul[1] + add[1], 0.08, 1.15)
    ambBuf[2] = clamp(baseG * mul[2] + add[2], 0.08, 1.15)
    ambBuf[3] = clamp(baseB * mul[3] + add[3], 0.10, 1.20)

    -- Normalized sun/moon direction (preset angle dominates in atardecer/noche/dramatico, blends with biome in dia)
    local pDir = preset.sunDir
    local tDir = themeTbl and themeTbl.sunDir
    local dx, dy, dz
    if self.lightingPreset == "dia" and tDir then
        dx = lerp(pDir[1], tDir[1] or pDir[1], 0.50)
        dy = lerp(pDir[2], tDir[2] or pDir[2], 0.50)
        dz = lerp(pDir[3], tDir[3] or pDir[3], 0.50)
    else
        dx, dy, dz = pDir[1], pDir[2], pDir[3]
    end
    local dLen = sqrt(dx * dx + dy * dy + dz * dz)
    if dLen <= 1e-6 then
        dx, dy, dz = 0.0, -0.707107, 0.707107
    else
        dx, dy, dz = dx / dLen, dy / dLen, dz / dLen
    end
    local sunDirBuf = self._sunDirBuf
    sunDirBuf[1], sunDirBuf[2], sunDirBuf[3] = dx, dy, dz

    -- Sun color & calibrated directional energy
    local tSun = (themeTbl and themeTbl.sunColor) or preset.sunColor
    local pSun = preset.sunColor
    local sunBlend = (self.lightingPreset == "dia") and 0.45 or 0.20
    local sunColBuf = self._sunColBuf
    sunColBuf[1] = lerp(pSun[1], tSun[1] or pSun[1], sunBlend)
    sunColBuf[2] = lerp(pSun[2], tSun[2] or pSun[2], sunBlend)
    sunColBuf[3] = lerp(pSun[3], tSun[3] or pSun[3], sunBlend)

    local themeSunFactor = clamp(((themeTbl and themeTbl.sunEnergy) or 1.30) / 1.30, 0.78, 1.14)
    local sunEnergy = preset.sunEnergy * themeSunFactor
    if overworld and self.lightingPreset == "dia" then
        local dusk = smoothstep(88.0, 98.0, self.camU)
        ambBuf[1] = lerp(ambBuf[1], 0.32, dusk)
        ambBuf[2] = lerp(ambBuf[2], 0.41, dusk)
        ambBuf[3] = lerp(ambBuf[3], 0.57, dusk)
        sunColBuf[1] = lerp(sunColBuf[1], 0.62, dusk)
        sunColBuf[2] = lerp(sunColBuf[2], 0.78, dusk)
        sunColBuf[3] = lerp(sunColBuf[3], 1.00, dusk)
        sunEnergy = lerp(sunEnergy, 0.66, dusk)
    end

    -- Pack up to 10 dynamic point lights into pre-allocated vec4 buffers
    local posBuf = self._lightPosBuf
    local colBuf = self._lightColBuf
    local count = 0
    if type(extraLights) == "table" then
        local total = min(10, #extraLights)
        for i = 1, total do
            local L = extraLights[i]
            if type(L) == "table" and (L.energy or 0.0) > 0.001 then
                count = count + 1
                local p = posBuf[count]
                p[1] = L.x or 0.0
                p[2] = L.y or 0.0
                p[3] = max(1.0, L.radius or 160.0)
                p[4] = L.height or 64.0

                local c = colBuf[count]
                c[1] = L.r or (L.color and L.color[1]) or 1.0
                c[2] = L.g or (L.color and L.color[2]) or 0.82
                c[3] = L.b or (L.color and L.color[3]) or 0.45
                c[4] = L.energy or 0.8
            end
        end
    end
    for i = count + 1, 10 do
        local p = posBuf[i]
        p[1], p[2], p[3], p[4] = 0.0, 0.0, 1.0, 0.0
        local c = colBuf[i]
        c[1], c[2], c[3], c[4] = 0.0, 0.0, 0.0, 0.0
    end

    local sizeBuf = self._screenSizeBuf
    sizeBuf[1], sizeBuf[2] = sw, sh

    safeSend(litShader, "ambientColor", ambBuf)
    safeSend(litShader, "sunDir", sunDirBuf)
    safeSend(litShader, "sunColor", sunColBuf)
    safeSend(litShader, "sunEnergy", sunEnergy)
    safeSend(litShader, "numLights", count)
    safeSend(litShader, "lightPosRadius", unpack(posBuf, 1, 10))
    safeSend(litShader, "lightColorEnergy", unpack(colBuf, 1, 10))
    safeSend(litShader, "screenSize", sizeBuf)
    safeSend(litShader, "time", time or 0.0)

    return litShader
end

function StageRenderer:drawSpriteLit(spritePair, x, y, angle, sx, sy, ox, oy, quadObj, emissiveBoost, emissiveCol, litShader, billboardFlag)
    if not spritePair then
        return
    end
    local diff, norm
    if type(spritePair) == "table" then
        diff = spritePair.diff
        norm = spritePair.norm
    else
        diff = spritePair
        norm = nil
    end
    if not diff then
        return
    end

    local rot = angle or 0.0
    local scaleX = sx or 1.0
    local scaleY = sy or scaleX
    local origX = ox or 0.0
    local origY = oy or 0.0

    local useLit = (litShader ~= nil and litShader ~= false and self.useLitShader)
    if useLit then
        love.graphics.setShader(litShader)
        if norm then
            safeSend(litShader, "hasNormalMap", 1.0)
            safeSend(litShader, "normalMap", norm)
            safeSend(litShader, "normalStrength", 0.88)
        else
            safeSend(litShader, "hasNormalMap", 0.0)
            safeSend(litShader, "normalStrength", 0.85)
        end
        safeSend(litShader, "spriteAngle", rot)
        safeSend(litShader, "spriteBillboard", (billboardFlag == false) and 0.0 or 1.0)
        safeSend(litShader, "surfaceBaseY", y or 0.0)
        safeSend(litShader, "emissiveBoost", emissiveBoost or 0.0)
        local emBuf = self._emissiveColBuf
        if type(emissiveCol) == "table" then
            emBuf[1] = emissiveCol[1] or 1.0
            emBuf[2] = emissiveCol[2] or 1.0
            emBuf[3] = emissiveCol[3] or 1.0
        else
            emBuf[1], emBuf[2], emBuf[3] = 1.0, 1.0, 1.0
        end
        safeSend(litShader, "emissiveColor", emBuf)
        safeSend(litShader, "specStrength", 0.20)
    end

    if quadObj then
        love.graphics.draw(diff, quadObj, x, y, rot, scaleX, scaleY, origX, origY)
    else
        love.graphics.draw(diff, x, y, rot, scaleX, scaleY, origX, origY)
    end

    if useLit then
        love.graphics.setShader()
    end
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

function StageRenderer:updateOverworldNPCs(puduU, puduV, dt)
    local du, dv = puduU - BODOQUE.u, puduV - BODOQUE.v
    local radius = self._bodoqueNearby and BODOQUE.leaveRadius or BODOQUE.enterRadius
    local nearby = du * du + dv * dv <= radius * radius
    self._bodoqueGesture = max(0.0, self._bodoqueGesture - dt)
    if nearby and not self._bodoqueNearby then
        self._bodoqueGesture = 0.48
    end
    self._bodoqueNearby = nearby
    local fade = nearby and dt / 0.18 or -dt / 0.22
    self._bodoqueDialogue = clamp(self._bodoqueDialogue + fade, 0.0, 1.0)
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

local function drawHorizonCaleuche(sx, sy, s, tNow, tr, tg, tb, isNightOrDramatic, assetsOpt)
    local bob = sin(tNow * 1.55) * 3.0 * s
    local syB = sy + bob

    -- Mode A optional sprite support for distant horizon Caleuche
    local pair = assetsOpt and assetsOpt.props and assetsOpt.props.caleuche_ship
    if pair and pair.diff and not pair.isPlaceholder then
        local img = pair.diff
        local iw, ih = img:getDimensions()
        local sc = (68.0 * s) / max(1, ih)
        love.graphics.setColor(clamp(tr * 1.05, 0.35, 1.0), clamp(tg * 1.08, 0.45, 1.0), clamp(tb * 1.12, 0.55, 1.0), 0.92)
        love.graphics.draw(img, sx, syB, sin(tNow * 1.1) * 0.03, sc, sc, iw * 0.5, ih * 0.85)
        return
    end

    -- Spectral coastal ripple ring under hull
    love.graphics.setColor(clamp(0.68 * tr + 0.16, 0, 1), clamp(0.94 * tg + 0.14, 0, 1), clamp(1.0 * tb + 0.18, 0, 1), 0.46)
    love.graphics.ellipse("line", sx, sy + 3 * s, 38 * s, 7 * s)

    -- Dark weathered wooden hull
    love.graphics.setColor(0.24 * tr, 0.16 * tg, 0.14 * tb, 0.96)
    love.graphics.polygon("fill", sx - 36 * s, syB - 6 * s, sx + 38 * s, syB - 8 * s, sx + 26 * s, syB + 6 * s, sx - 25 * s, syB + 6 * s)
    love.graphics.setColor(0.38 * tr, 0.26 * tg, 0.19 * tb, 0.96)
    love.graphics.rectangle("fill", sx - 30 * s, syB - 10 * s, 60 * s, 4.5 * s)

    -- Tall masts & rigging crossbars
    love.graphics.setColor(0.18 * tr, 0.13 * tg, 0.12 * tb, 0.96)
    love.graphics.rectangle("fill", sx - 10 * s, syB - 58 * s, 3.0 * s, 50 * s)
    love.graphics.rectangle("fill", sx + 12 * s, syB - 48 * s, 2.6 * s, 40 * s)
    love.graphics.rectangle("fill", sx - 22 * s, syB - 48 * s, 26 * s, 2.0 * s)
    love.graphics.rectangle("fill", sx + 2 * s, syB - 40 * s, 22 * s, 2.0 * s)

    -- Billowing sails with ghostly Caleuche teal-pearl sheen (pops in noche/dramatico!)
    local ghostBoost = isNightOrDramatic and 0.36 or 0.10
    love.graphics.setColor(
        clamp(0.82 * tr + ghostBoost * 0.55, 0, 1),
        clamp(0.94 * tg + ghostBoost * 0.95, 0, 1),
        clamp(0.94 * tb + ghostBoost * 0.95, 0, 1),
        0.90
    )
    love.graphics.polygon("fill", sx - 22 * s, syB - 48 * s, sx + 4 * s, syB - 45 * s, sx + 6 * s, syB - 18 * s, sx - 20 * s, syB - 20 * s)
    love.graphics.polygon("fill", sx + 3 * s, syB - 40 * s, sx + 24 * s, syB - 37 * s, sx + 24 * s, syB - 16 * s, sx + 5 * s, syB - 18 * s)

    -- Luminous spectral emerald-cyan stern lantern (always glowing!)
    local lanPulse = 0.80 + 0.20 * sin(tNow * 3.4)
    love.graphics.setColor(0.32, 0.98, 0.88, 0.28 * lanPulse)
    love.graphics.circle("fill", sx - 28 * s, syB - 12 * s, 12 * s)
    love.graphics.setColor(0.54, 1.00, 0.92, 0.95)
    love.graphics.circle("fill", sx - 28 * s, syB - 12 * s, 3.6 * s)
end

function StageRenderer:drawSkyAndHorizon(theme, w, h, time, horizonFrac, stageKind, assetsOpt)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = time or 0.0
    local hFrac = horizonFrac or 0.44
    local horizonY = floor(sh * hFrac)
    local pal, biomeId = resolveSkyPalette(theme, stageKind)

    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia
    local st = preset.skyTint or { 1.0, 1.0, 1.0 }
    local tr, tg, tb = st[1], st[2], st[3]
    local isSunset = (preset.id == "atardecer")
    local isNight = (preset.id == "noche")
    local isDramatic = (preset.id == "dramatico")

    local function tintRGB(r, g, b)
        return clamp(r * tr, 0.0, 1.0), clamp(g * tg, 0.0, 1.0), clamp(b * tb, 0.0, 1.0)
    end

    -- 1. 12-band crisp pixel-RPG gradient sky modulated by active lighting preset
    local bands = 12
    local bandH = ceil(horizonY / bands) + 1
    for i = 0, bands - 1 do
        local frac = i / (bands - 1)
        local r = lerp(pal.skyTop[1], pal.skyBot[1], frac) * tr
        local g = lerp(pal.skyTop[2], pal.skyBot[2], frac) * tg
        local b = lerp(pal.skyTop[3], pal.skyBot[3], frac) * tb

        if isNight then
            -- Deep vibrant twilight indigo zenith -> luminous midnight sapphire horizon
            r = lerp(r, lerp(0.05, 0.14, frac), 0.55)
            g = lerp(g, lerp(0.08, 0.21, frac), 0.55)
            b = lerp(b, lerp(0.20, 0.44, frac), 0.55)
        elseif isSunset then
            -- Golden-hour tangerine/rose glow building toward horizon
            local lowT = frac * frac
            r = lerp(r, 1.00, lowT * 0.42)
            g = lerp(g, 0.50, lowT * 0.34)
            b = lerp(b, 0.26, lowT * 0.36)
        elseif isDramatic then
            -- Theatrical deep velvet-violet zenith with warm stage horizon rim
            local lowT = frac * frac
            r = lerp(r, lerp(0.11, 0.34, lowT), 0.38)
            g = lerp(g, lerp(0.10, 0.24, lowT), 0.38)
            b = lerp(b, lerp(0.22, 0.38, lowT), 0.38)
        end

        love.graphics.setColor(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), 1.0)
        love.graphics.rectangle("fill", 0, floor(horizonY * i / bands), sw, bandH)
    end

    -- 1B. Crisp twinkling pixel stars in noche preset
    if preset.showStars then
        for i = 1, 38 do
            local sx = floor(hash2d(i * 1.73, 19.1) * (sw - 16) + 8)
            local sy = floor(hash2d(i * 3.11, 47.7) * (horizonY * 0.76) + 10)
            local speed = 1.8 + (i % 5) * 0.65
            local twinkle = 0.42 + 0.58 * (0.5 + 0.5 * sin(tNow * speed + i * 2.3))
            local sz = (i % 6 == 0) and 3 or 2
            if i % 5 == 0 then
                love.graphics.setColor(0.76, 0.92, 1.00, twinkle)
            elseif i % 7 == 0 then
                love.graphics.setColor(1.00, 0.93, 0.74, twinkle)
            else
                love.graphics.setColor(0.95, 0.97, 1.00, twinkle)
            end
            love.graphics.rectangle("fill", sx, sy, sz, sz)
            if sz == 3 and twinkle > 0.78 then
                love.graphics.setColor(0.86, 0.94, 1.00, twinkle * 0.45)
                love.graphics.rectangle("fill", sx - 2, sy + 1, 7, 1)
                love.graphics.rectangle("fill", sx + 1, sy - 2, 1, 7)
            end
        end
    end

    -- 2. Celestial disc: pale-silver full moon in noche, or golden sun disc in other presets
    local sunX = sw * ((biomeId == "ciudad") and 0.74 or 0.78)
    local sunY = horizonY * (isSunset and 0.56 or ((biomeId == "desierto") and 0.34 or 0.40))
    local sunR = min(sw, sh) * (preset.isMoon and 0.038 or 0.042)
    local hr, hg, hb = tintRGB(pal.horizonGlow[1], pal.horizonGlow[2], pal.horizonGlow[3])

    if preset.isMoon then
        -- Luminous pale-silver full moon + cool twilight halo + subtle pixel craters
        love.graphics.setColor(0.46, 0.66, 1.00, 0.14)
        love.graphics.circle("fill", sunX, sunY, sunR * 3.4)
        love.graphics.setColor(0.70, 0.84, 1.00, 0.24)
        love.graphics.circle("fill", sunX, sunY, sunR * 2.0)
        love.graphics.setColor(0.92, 0.95, 1.00, 0.98)
        love.graphics.circle("fill", sunX, sunY, sunR)
        love.graphics.setColor(0.76, 0.82, 0.92, 0.52)
        love.graphics.circle("fill", sunX + sunR * 0.24, sunY - sunR * 0.16, sunR * 0.22)
        love.graphics.circle("fill", sunX - sunR * 0.26, sunY + sunR * 0.22, sunR * 0.16)
        love.graphics.circle("fill", sunX + sunR * 0.08, sunY + sunR * 0.30, sunR * 0.12)
        love.graphics.setColor(1.0, 1.0, 1.0, 0.72)
        love.graphics.circle("fill", sunX - sunR * 0.20, sunY - sunR * 0.20, sunR * 0.42)
    else
        local pSun = preset.sunColor
        local scR = lerp(pal.sunColor[1], pSun[1], isSunset and 0.75 or 0.35)
        local scG = lerp(pal.sunColor[2], pSun[2], isSunset and 0.75 or 0.35)
        local scB = lerp(pal.sunColor[3], pSun[3], isSunset and 0.75 or 0.35)
        local sunAlpha = isDramatic and 0.72 or 1.0

        love.graphics.setColor(hr, hg, hb, 0.18 * sunAlpha)
        love.graphics.circle("fill", sunX, sunY, sunR * 3.1)
        love.graphics.setColor(scR, scG, scB, 0.30 * sunAlpha)
        love.graphics.circle("fill", sunX, sunY, sunR * 1.9)
        love.graphics.setColor(scR, scG, scB, 0.96 * sunAlpha)
        love.graphics.circle("fill", sunX, sunY, sunR)
        love.graphics.setColor(1.0, 0.98, 0.90, 0.82 * sunAlpha)
        love.graphics.circle("fill", sunX - sunR * 0.15, sunY - sunR * 0.15, sunR * 0.56)
    end

    -- 3. Drifting multi-block pixel clouds tinted by active preset
    local cloudAlpha = (biomeId == "desierto") and 0.45 or 0.72
    if isNight then
        cloudAlpha = cloudAlpha * 0.36
    elseif isDramatic then
        cloudAlpha = cloudAlpha * 0.56
    end
    local clR, clG, clB = tintRGB(0.98, 0.98, 1.0)
    if isSunset then
        clR, clG, clB = 1.00, 0.84, 0.66
    end
    for i = 1, 6 do
        local speed = 6.0 + (i % 3) * 4.5
        local cx = ((i * 238.0 + tNow * speed) % (sw + 220)) - 110
        local cy = horizonY * (0.14 + (i % 4) * 0.14)
        local cw = 64 + (i % 3) * 28
        local ch = 12 + (i % 2) * 6
        love.graphics.setColor(hr, hg, hb, cloudAlpha * 0.48)
        love.graphics.rectangle("fill", floor(cx - 8), floor(cy + ch * 0.45), cw + 16, ch * 0.65, 4, 4)
        love.graphics.setColor(clR, clG, clB, cloudAlpha)
        love.graphics.rectangle("fill", floor(cx), floor(cy), cw, ch, 4, 4)
        love.graphics.rectangle("fill", floor(cx + cw * 0.18), floor(cy - ch * 0.65), cw * 0.52, ch * 0.85, 4, 4)
    end

    -- 4. Horizon atmospheric glow band
    local glowR, glowG, glowB = hr, hg, hb
    if isSunset then
        glowR, glowG, glowB = 1.00, 0.62, 0.30
    elseif isNight then
        glowR, glowG, glowB = 0.24, 0.36, 0.64
    elseif isDramatic then
        glowR, glowG, glowB = 0.76, 0.58, 0.44
    end
    love.graphics.setColor(glowR, glowG, glowB, isNight and 0.28 or 0.36)
    love.graphics.rectangle("fill", 0, horizonY - 38, sw, 42)
    love.graphics.setColor(glowR, glowG, glowB, isNight and 0.14 or 0.20)
    love.graphics.rectangle("fill", 0, horizonY - 72, sw, 36)

    -- 5. Far & Near Parallax Silhouette Layers tailored to each Chilean biome
    if biomeId == "bosque" then
        -- Far layer: Andean cordillera peaks with subtle snow caps
        local fR, fG, fB = tintRGB(0.24, 0.40, 0.48)
        local sR, sG, sB = tintRGB(0.90, 0.95, 0.98)
        for i = 0, 7 do
            local px = i * (sw / 6.5) - 40
            local pw = sw / 4.2
            local ph = 72 + ((i * 37) % 54)
            love.graphics.setColor(fR, fG, fB, 0.90)
            love.graphics.polygon("fill", px, horizonY + 4, px + pw * 0.5, horizonY - ph, px + pw, horizonY + 4)
            love.graphics.setColor(sR, sG, sB, isNight and 0.36 or 0.56)
            love.graphics.polygon(
                "fill",
                px + pw * 0.5, horizonY - ph,
                px + pw * 0.38, horizonY - ph * 0.72,
                px + pw * 0.62, horizonY - ph * 0.72
            )
        end
        -- Near layer: Valdivian forest canopy & araucaria silhouettes
        local nR, nG, nB = tintRGB(0.11, 0.26, 0.18)
        love.graphics.setColor(nR, nG, nB, 0.97)
        love.graphics.rectangle("fill", 0, horizonY - 18, sw, 22)
        for i = 0, 26 do
            local tx = i * (sw / 25)
            local th = 26 + ((i * 29) % 30)
            if i % 4 == 0 then
                love.graphics.rectangle("fill", tx - 2, horizonY - th - 14, 4, th + 16)
                love.graphics.ellipse("fill", tx, horizonY - th - 14, 18, 6)
                love.graphics.ellipse("fill", tx, horizonY - th - 5, 13, 4)
            else
                love.graphics.circle("fill", tx, horizonY - th * 0.6, 18 + (i % 3) * 6)
            end
        end

    elseif biomeId == "desierto" then
        -- Far layer: Iconic Licancabur volcano cone + sweeping Atacama red mesas
        local vR, vG, vB = tintRGB(0.56, 0.34, 0.36)
        love.graphics.setColor(vR, vG, vB, 0.86)
        love.graphics.polygon("fill", sw * 0.08, horizonY + 4, sw * 0.28, horizonY - 112, sw * 0.48, horizonY + 4)
        local mR, mG, mB = tintRGB(0.68, 0.40, 0.34)
        love.graphics.setColor(mR, mG, mB, 0.88)
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
        -- Near layer: Warm terracotta canyon ridge
        local rR, rG, rB = tintRGB(0.48, 0.24, 0.16)
        love.graphics.setColor(rR, rG, rB, 0.96)
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

    elseif biomeId == "costa" or biomeId == "chiloe" then
        -- Far layer: Coastal headlands + layered Valparaiso hills
        local hR, hG, hB = tintRGB(0.24, 0.46, 0.64)
        love.graphics.setColor(hR, hG, hB, 0.88)
        for i = 0, 5 do
            local hx = i * (sw * 0.22) - 40
            local hw = sw * 0.28
            local hh = 42 + ((i * 31) % 38)
            love.graphics.ellipse("fill", hx + hw * 0.5, horizonY + 12, hw * 0.62, hh)
        end
        if biomeId == "costa" then
            -- Near layer: Colorful Valparaiso hillside houses + twinkling harbor lights at night
            for i = 0, 22 do
                local bx = i * (sw / 22)
                local bh = 14 + ((i * 17) % 24)
                local bw = 18 + (i % 3) * 8
                local hc = VALPARAISO_HOUSE_COLS[(i % #VALPARAISO_HOUSE_COLS) + 1]
                local cR, cG, cB = tintRGB(hc[1] * 0.72, hc[2] * 0.72, hc[3] * 0.78)
                love.graphics.setColor(cR, cG, cB, 0.92)
                love.graphics.rectangle("fill", bx, horizonY - bh - 4, bw, bh + 6)
                if isNight or isDramatic or isSunset then
                    love.graphics.setColor(1.0, 0.86, 0.46, isNight and 0.78 or 0.48)
                    love.graphics.rectangle("fill", bx + 4, horizonY - bh + 2, 3, 3)
                    if bw > 22 then
                        love.graphics.rectangle("fill", bx + 12, horizonY - bh + 5, 3, 3)
                    end
                end
            end
        end

        -- Shimmering distant Pacific sea band right along horizon
        local wR, wG, wB = tintRGB(0.14, 0.44, 0.64)
        love.graphics.setColor(wR, wG, wB, 0.97)
        love.graphics.rectangle("fill", 0, horizonY - 8, sw, 12)
        if isNight then
            love.graphics.setColor(0.68, 0.86, 1.0, 0.44)
        elseif isSunset then
            love.graphics.setColor(1.0, 0.82, 0.48, 0.54)
        else
            love.graphics.setColor(0.95, 0.98, 1.0, 0.45)
        end
        for i = 0, 9 do
            local gx = (i * 145 + tNow * 14) % sw
            love.graphics.rectangle("fill", gx, horizonY - 4, 28, 2)
        end

        -- Iconic Caleuche ship floating gracefully on the coastal bay horizon in muelle stage!
        if stageKind == "muelle" then
            local shipX = sw * 0.40 + sin(tNow * 0.28) * 20.0
            local shipY = horizonY - 10
            drawHorizonCaleuche(shipX, shipY, 0.78, tNow, tr, tg, tb, isNight or isDramatic, assetsOpt)
        end

    else
        -- Ciudad: Majestic Andes peaks behind Santiago skyline + glowing office windows
        local mR, mG, mB = tintRGB(0.26, 0.30, 0.48)
        love.graphics.setColor(mR, mG, mB, 0.84)
        for i = 0, 6 do
            local mx = i * (sw / 5.5) - 50
            local mw = sw / 3.6
            local mh = 86 + ((i * 41) % 52)
            love.graphics.polygon("fill", mx, horizonY + 4, mx + mw * 0.5, horizonY - mh, mx + mw, horizonY + 4)
        end
        -- Near skyline towers (including Costanera-style central spire)
        local t1R, t1G, t1B = tintRGB(0.16, 0.20, 0.34)
        local t2R, t2G, t2B = tintRGB(0.14, 0.17, 0.30)
        local winAlpha = isNight and 0.86 or ((isDramatic or isSunset) and 0.72 or 0.55)
        for i = 0, 19 do
            local tx = i * (sw / 19)
            local tw = 34 + (i % 3) * 14
            local th = 36 + ((i * 43) % 72)
            if i == 11 then
                th = 128
                tw = 42
                love.graphics.setColor(t1R, t1G, t1B, 0.98)
                love.graphics.polygon(
                    "fill",
                    tx, horizonY + 4,
                    tx + 6, horizonY - th,
                    tx + tw - 6, horizonY - th,
                    tx + tw, horizonY + 4
                )
            else
                love.graphics.setColor(t2R, t2G, t2B, 0.96)
                love.graphics.rectangle("fill", tx, horizonY - th, tw, th + 4)
            end
            -- Warm golden lit office windows (pop vividly at night!)
            love.graphics.setColor(0.99, 0.86, 0.48, winAlpha)
            for wy = horizonY - th + 8, horizonY - 10, 10 do
                for wx = tx + 6, tx + tw - 10, 9 do
                    if ((floor(wx) + floor(wy) + i) % 3) ~= 0 then
                        love.graphics.rectangle("fill", wx, wy, 4, 4)
                    end
                end
            end
        end
    end

    -- Soft seam haze across horizon line
    love.graphics.setColor(glowR, glowG, glowB, 0.18)
    love.graphics.rectangle("fill", 0, horizonY - 6, sw, 14)

    -- Solid lower ground backdrop below horizon tinted by preset so zero black voids appear
    local gbR, gbG, gbB = tintRGB(pal.groundB[1], pal.groundB[2], pal.groundB[3])
    love.graphics.setColor(gbR, gbG, gbB, 1.0)
    love.graphics.rectangle("fill", 0, horizonY, sw, sh - horizonY)
end

--------------------------------------------------------------------------------
-- 6. Overworld 3D Isometric Terrain Floor, Skirts, Water, Wayfinders & Beacons
--------------------------------------------------------------------------------

local TILE_VERTEX_FORMAT = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "byte", 4 },
    { "TerrainData", "float", 2 },
}

local function roadCoverage(u, v)
    local width = (u >= MARSH_START and u <= MARSH_END) and 1.1 or 1.7
    local distance = abs(v - StageRenderer.pathCenterV(u))
    local road = (1.0 - smoothstep(width - 0.35, width + 0.65, distance))
        * smoothstep(-0.9, 0.5, u) * (1.0 - smoothstep(115.7, 117.0, u))
    local encounter = evalEncounterMask(u, v)
    local alcove = evalAlcoveMask(u, v)
    return max(road, smoothstep(0.58, 0.98, encounter), smoothstep(0.54, 0.98, alcove))
end

local function shoreCoverage(u, v, mode)
    if mode == 2 then
        return 1.0 - smoothstep(0.0, 1.8, min(u - RIVER_START, RIVER_END - u))
    end
    local lu, lv = u - LIGHTHOUSE_U, v - LIGHTHOUSE_V
    local edge = min(u - BAY_START, BAY_END - u, sqrt(lu * lu + lv * lv) - 2.0)
    return 1.0 - smoothstep(0.0, 2.1, edge)
end

function StageRenderer:_ensureTileMesh()
    if not self._tileMesh then
        self._tileMesh = love.graphics.newMesh(TILE_VERTEX_FORMAT, 4, "fan", "stream")
    end
    return self._tileMesh
end

function StageRenderer:_drawTexturedDiamond(img, cx, cy, halfW, halfH, u, v, r, g, b,
    normImg, shader, mode, contact, slope)
    local h = StageRenderer.STEP * 0.5
    local padX = 0.95
    local padY = 0.72
    local tx, ty = cx, cy - halfH - padY
    local rx, ry = cx + halfW + padX, cy
    local bx, by = cx, cy + halfH + padY
    local lx, ly = cx - halfW - padX, cy
    if mode == 0 then
        ty, ry, by, ly = ty + slope[1], ry + slope[2], by + slope[3], ly + slope[4]
    end

    if shader and mode == nil then
        if img and normImg then
            safeSend(shader, "hasNormalMap", 1.0)
            safeSend(shader, "normalMap", normImg)
            safeSend(shader, "normalStrength", 0.92)
        else
            safeSend(shader, "hasNormalMap", 0.0)
        end
        safeSend(shader, "surfaceBaseY", cy)
    end

    if img then
        local mesh = self:_ensureTileMesh()
        local u0, u1, v0, v1 = u - h, u + h, v - h, v + h
        local top, right, bottom, left = 0, 0, 0, 0
        if mode == 0 then
            top, right = roadCoverage(u1, v0), roadCoverage(u1, v1)
            bottom, left = roadCoverage(u0, v1), roadCoverage(u0, v0)
        elseif mode == 1 or mode == 2 then
            top, right = shoreCoverage(u1, v0, mode), shoreCoverage(u1, v1, mode)
            bottom, left = shoreCoverage(u0, v1, mode), shoreCoverage(u0, v0, mode)
        elseif mode == nil then
            -- The standard shader samples the same repeating image with scaled UVs.
            u0, u1, v0, v1 = u0 * 0.36, u1 * 0.36, v0 * 0.36, v1 * 0.36
        end
        mesh:setTexture(img)
        mesh:setVertex(1, tx, ty, u1, v0, 1, 1, 1, 1, top, contact and contact[1] or 0)
        mesh:setVertex(2, rx, ry, u1, v1, 1, 1, 1, 1, right, contact and contact[2] or 0)
        mesh:setVertex(3, bx, by, u0, v1, 1, 1, 1, 1, bottom, contact and contact[3] or 0)
        mesh:setVertex(4, lx, ly, u0, v0, 1, 1, 1, 1, left, contact and contact[4] or 0)
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.draw(mesh)
    else
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.polygon("fill", tx, ty, rx, ry, bx, by, lx, ly)
    end
end

local function slopeCorner(elev, side, endHeight, diagonal, pixelScale)
    local range = max(elev, side, endHeight, diagonal) - min(elev, side, endHeight, diagonal)
    if range >= 0.38 then return 0 end
    return (elev - (elev + side + endHeight + diagonal) * 0.25) * pixelScale
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

    -- Solid terrain 3D cliff faces (Left-front = sunlit face, Right-front = deeper shadow face)
    local diffL = elev - eL
    local diffR = elev - eR
    local tuck = 0.75

    if diffL > 0.10 then
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
            elseif biomeVis.id == "chiloe" then
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
        if diffL > 0.40 then
            local lip = biomeVis.cliffLip
            love.graphics.setColor(lip[1], lip[2], lip[3], 0.40)
            love.graphics.line(lx, ly, bx, by)
        end
    end

    if diffR > 0.10 then
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
            elseif biomeVis.id == "chiloe" then
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

        if diffR > 0.40 then
            local lip = biomeVis.cliffLip
            love.graphics.setColor(lip[1] * 0.76, lip[2] * 0.76, lip[3] * 0.76, 0.36)
            love.graphics.line(bx, by, rx, ry)
        end
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
    local litShader = (ctx.litShader ~= nil and ctx.litShader ~= false and self.useLitShader) and ctx.litShader or nil
    local terrainShader = ctx.terrainShader
    local contact, slope = self._tileContact, self._tileSlope
    local roadPair = tiles and tiles.stone_floor
    local activeMode, activeGround, activeRoadTint = nil, false, nil
    if terrainShader then
        safeSend(terrainShader, "specStrength", 0.10)
        safeSend(terrainShader, "roadTexture", roadPair and roadPair.diff or self:_getUnitWhite())
        safeSend(terrainShader, "hasRoadNormal", roadPair and roadPair.norm and 1.0 or 0.0)
        if roadPair and roadPair.norm then safeSend(terrainShader, "roadNormal", roadPair.norm) end
    end

    local function drawSurface(mode, cx, cy, halfW, halfH, u, v, r, g, b, ground, roadTint)
        love.graphics.setShader(terrainShader)
        if activeMode ~= mode then
            safeSend(terrainShader, "terrainMode", mode)
            activeMode = mode
        end
        if mode == 0 and activeGround ~= ground then
            local norm = ground and ground.norm
            safeSend(terrainShader, "hasNormalMap", norm and 1.0 or 0.0)
            if norm then safeSend(terrainShader, "normalMap", norm) end
            activeGround = ground
        end
        if mode == 0 and activeRoadTint ~= roadTint then
            safeSend(terrainShader, "roadTint", roadTint)
            activeRoadTint = roadTint
        end
        local image = ground and ground.diff or self:_getUnitWhite()
        self:_drawTexturedDiamond(image, cx, cy, halfW, halfH, u, v, r, g, b,
            nil, terrainShader, mode, contact, slope)
    end

    -- 1. Seamless biome backdrop fill (guarantees zero black voids anywhere)
    local camBiome = StageRenderer.getBiomeAt(self.camU)
    local camVis = StageRenderer.BIOME_VISUALS[camBiome] or StageRenderer.BIOME_VISUALS.bosque
    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia
    local st = preset.skyTint or { 1.0, 1.0, 1.0 }
    if litShader then
        love.graphics.setColor(
            clamp(camVis.backdrop[1] * st[1], 0.02, 1.0),
            clamp(camVis.backdrop[2] * st[2], 0.02, 1.0),
            clamp(camVis.backdrop[3] * st[3], 0.04, 1.0),
            1.0
        )
    else
        love.graphics.setColor(camVis.backdrop[1], camVis.backdrop[2], camVis.backdrop[3], 1.0)
    end
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

    if litShader then
        love.graphics.setShader(litShader)
        safeSend(litShader, "spriteBillboard", 0.0)
        safeSend(litShader, "spriteAngle", 0.0)
        safeSend(litShader, "emissiveBoost", 0.0)
        safeSend(litShader, "specStrength", 0.14)
        safeSend(litShader, "hasNormalMap", 0.0)
    end

    for r = 0, rows - 2 do
        local iu = iuMax - r
        local u = iu * step
        local du = u - camU
        local rowOff = r * cols
        local prevRowOff = (r - 1) * cols
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
                local isWater = terrain == "water" or terrain == "river"
                local isDeck = terrain == "bridge" or terrain == "pier"
                -- Draw 3D cliff skirts / pier pilings first
                local hasSkirt = isDeck or elev - min(eL, eR) > 0.10
                if not isWater and hasSkirt then
                    love.graphics.setShader(litShader)
                    if litShader then
                        safeSend(litShader, "hasNormalMap", 0.0)
                        safeSend(litShader, "surfaceBaseY", cy)
                    end
                    self:_drawTileSkirts(cx, cy, halfW, halfH, elev, eL, eR, terrain, vis, time, z)
                end

                -- Draw top diamond surface
                if terrainShader then
                    local backL = c > 0 and elevCache[rowOff + c - 1] or elev
                    local backR = r > 0 and elevCache[prevRowOff + c] or elev
                    contact[1] = clamp((max(backL, backR) - elev) * 1.3, 0.0, 1.0)
                    contact[2] = clamp((max(backR, eR) - elev) * 1.3, 0.0, 1.0)
                    contact[3] = clamp((max(eL, eR) - elev) * 1.3, 0.0, 1.0)
                    contact[4] = clamp((max(backL, eL) - elev) * 1.3, 0.0, 1.0)
                    if isWater then
                        local mode = terrain == "river" and 2 or 1
                        drawSurface(mode, cx, cy, halfW, halfH, u, v, 1, 1, 1)
                    elseif isDeck then
                        drawSurface(3, cx, cy, halfW, halfH, u, v, 0.66, 0.46, 0.29)
                    else
                        -- Join gentle slopes at their shared corners while preserving tall cliff faces.
                        local nw = r > 0 and c > 0 and elevCache[prevRowOff + c - 1] or elev
                        local ne = r > 0 and elevCache[prevRowOff + c + 1] or elev
                        local southwest = c > 0 and elevCache[nextRowOff + c - 1] or elev
                        slope[1] = slopeCorner(elev, backL, backR, nw, elevPxZ)
                        slope[2] = slopeCorner(elev, backR, eR, ne, elevPxZ)
                        slope[3] = slopeCorner(elev, eL, eR, elevCache[nextRowOff + c + 1], elevPxZ)
                        slope[4] = slopeCorner(elev, backL, eL, southwest, elevPxZ)
                        local tileKey, tint = vis.floorTile, vis.groundTint
                        if terrain == "cliff" then
                            tileKey, tint = vis.cliffTile, vis.cliffTopTint
                        elseif terrain == "marsh" then
                            tileKey, tint = "grass_floor", { 0.55, 0.72, 0.56 }
                        elseif biomeId == "desierto" and elev > 0.55 then
                            tint = vis.plateauTint
                        end
                        local grade = clamp(0.96 + elev * 0.04, 0.90, 1.08)
                        drawSurface(0, cx, cy, halfW, halfH, u, v, tint[1] * grade, tint[2] * grade, tint[3] * grade,
                            tiles and tiles[tileKey], vis.pathTint)
                    end
                elseif isWater then
                    if litShader then
                        safeSend(litShader, "hasNormalMap", 0.0)
                        safeSend(litShader, "specStrength", 0.30)
                        safeSend(litShader, "surfaceBaseY", cy)
                    end
                    self:_drawWaterTile(cx, cy, halfW, halfH, u, v, terrain, time, z)
                    if litShader then
                        safeSend(litShader, "specStrength", 0.14)
                    end
                elseif isDeck then
                    if litShader then
                        safeSend(litShader, "hasNormalMap", 0.0)
                        safeSend(litShader, "surfaceBaseY", cy)
                    end
                    self:_drawWoodenDeckTile(cx, cy, halfW, halfH, terrain, z)
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
                    local tilePair = tiles and tiles[tileKey] or nil
                    local img = tilePair and tilePair.diff or nil
                    local norm = tilePair and tilePair.norm or nil
                    self:_drawTexturedDiamond(img, cx, cy, halfW, halfH, u, v,
                        tr * elevShade, tg * elevShade, tb * elevShade, norm, litShader)

                    -- Subtle glossy mud puddle sheen in marsh cells
                    if terrain == "marsh" and ((iu * 7 + iv * 13) % 3 == 0) then
                        if litShader then
                            safeSend(litShader, "hasNormalMap", 0.0)
                        end
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

    if litShader or terrainShader then
        love.graphics.setShader()
    end

    -- 4. Golden diagonal wayfinder chevrons along the winding main path (guiding NE travel)
    local encList = ctx.encounters or _encounterAnchors
    for u = 6.0, 102.0, 5.5 do
        if abs(u - camU) <= 18.0 then
            -- Skip directly underneath encounters
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

    -- Soft mist beneath the HUD without a visible horizontal edge.
    local hc = camVis.hazeCol
    local mr, mg, mb = hc[1], hc[2], hc[3]
    if litShader then
        mr, mg, mb = clamp(mr * st[1], 0, 1), clamp(mg * st[2], 0, 1), clamp(mb * st[3], 0, 1)
    end
    local mist = self:_ensureFloorBandMesh()
    local endY = sh * 0.31
    mist:setTexture()
    mist:setVertex(1, 0, 0, 0, 0, mr, mg, mb, 0.12)
    mist:setVertex(2, sw, 0, 1, 0, mr, mg, mb, 0.12)
    mist:setVertex(3, sw, endY, 1, 1, mr, mg, mb, 0)
    mist:setVertex(4, 0, endY, 0, 1, mr, mg, mb, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mist)
end

--------------------------------------------------------------------------------
-- 7. Overworld Landmarks & Procedural Decor Placement
--------------------------------------------------------------------------------

-- Heights are measured in world pixels. Small plants frame the foreground;
-- the mature trees reach across more than one 186 px terrain diamond.
local SCENERY_HEIGHT = {
    ancient_tree = 245, araucaria_tree = 226, calafate_bush = 29,
    apacheta_sundial = 62, biome_arch = 127, coast_lighthouse = 144,
    copihue = 37, debris_pile = 34, desert_cactus = 80, lantern_post = 71,
    lily_pad = 25, moai_relic = 67, mossy_boulder = 39, mossy_log = 42,
    mountain_crystal = 58, orb_shrine = 52, pincoya_shrine = 82,
    quena_monolith = 66, rewe_totem = 92, rock_monolith = 105,
    stone_pedestal = 34, valdivian_fern = 35, valdivian_shrub = 38,
    lettuce_truck = 248, arica_sign = 91,
}
local FOLIAGE_SWAY = {
    ancient_tree = 0.009, araucaria_tree = 0.012, calafate_bush = 0.023,
    copihue = 0.032, valdivian_fern = 0.050, valdivian_shrub = 0.032,
}

local function sceneryHeight(prop)
    return (SCENERY_HEIGHT[prop.kind] or 86) * (prop.scale or 1.0)
end

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

    local borderStyles = { "sandstone", "harbor", "stone" }
    for i, style in ipairs(borderStyles) do
        local biome = Encounters.getBiome(Encounters.BIOME_ORDER[i])
        local u = biome.uEnd - 1
        local pc = StageRenderer.pathCenterV(u)
        addProp("biome_arch", u, pc - 4.5, 1.05, biome.id, style)
        addProp("lantern_post", u, pc + 3.6, 0.95, biome.id)
    end

    for _, u in ipairs({ RIVER_START - 0.8, RIVER_END + 0.8 }) do
        local pc = StageRenderer.pathCenterV(u)
        addProp("lantern_post", u, pc - 2.65, 1.0, "bosque")
        addProp("lantern_post", u, pc + 2.65, 1.0, "bosque")
    end
    addProp("coast_lighthouse", LIGHTHOUSE_U, LIGHTHOUSE_V, 1.35, "costa")
    addProp("debris_pile", 43.8, StageRenderer.pathCenterV(43.8) + 3.2, 1.08, "costa")
    local pierU = BAY_START - 0.2
    local pierV = StageRenderer.pathCenterV(pierU)
    addProp("lantern_post", pierU, pierV - 2.75, 1.0, "costa")
    addProp("lantern_post", pierU, pierV + 2.75, 1.0, "costa")

    for _, u in ipairs({ 95.5, 102.0, 107.0, 110.5, 114.5 }) do
        local pc = StageRenderer.pathCenterV(u)
        addProp("lantern_post", u, pc - 3.7, 1.05, "chiloe")
        addProp("lantern_post", u, pc + 3.7, 1.05, "chiloe")
    end
    addProp("coast_lighthouse", 109.0, -6.7, 1.32, "chiloe")
    addProp("pincoya_shrine", 115.6, 4.5, 1.12, "chiloe")

    addProp("ancient_tree", 54.8, StageRenderer.pathCenterV(54.8) - 5.0, 1.10, "bosque")
    addProp("araucaria_tree", 58.5, StageRenderer.pathCenterV(58.5) - 5.7, 1.18, "bosque")
    addProp("ancient_tree", 63.0, StageRenderer.pathCenterV(63.0) - 5.3, 1.31, "bosque")
    addProp("araucaria_tree", 71.5, StageRenderer.pathCenterV(71.5) - 5.4, 1.23, "bosque")
    addProp("ancient_tree", 90.0, StageRenderer.pathCenterV(90.0) - 5.4, 1.22, "bosque")
    addProp("araucaria_tree", 58.0, StageRenderer.pathCenterV(58.0) + 7.8, 0.69, "bosque")
    addProp("calafate_bush", 97.0, StageRenderer.pathCenterV(97.0) + 3.8, 1.22, "chiloe")
    addProp("mossy_log", 61.0, StageRenderer.pathCenterV(61.0) + 4.2, 1.20, "bosque")
    addProp("valdivian_fern", 59.4, StageRenderer.pathCenterV(59.4) + 4.6, 1.22, "bosque")
    addProp("copihue", 62.0, StageRenderer.pathCenterV(62.0) + 5.1, 1.04, "bosque")
    addProp("rock_monolith", 1.5, StageRenderer.pathCenterV(1.5) - 6.0, 1.36, "desierto")
    addProp("rock_monolith", 10.0, StageRenderer.pathCenterV(10.0) - 7.2, 1.12, "desierto")
    addProp("quena_monolith", 21.0, StageRenderer.pathCenterV(21.0) - 4.5, 1.06, "desierto")
    addProp("stone_pedestal", 101.4, StageRenderer.pathCenterV(101.4) - 3.3, 1.07, "chiloe")
    addProp("lettuce_truck", DESERT_ARRIVAL.startU, DESERT_ARRIVAL.startV, 1.0, "desierto")
    addProp("arica_sign", ARICA_SIGN_U, ARICA_SIGN_V, 1.0, "desierto")
    addProp("desert_cactus", 7.0, StageRenderer.pathCenterV(7.0) + 5.2, 1.25, "desierto")
    addProp("desert_cactus", 11.5, StageRenderer.pathCenterV(11.5) - 5.1, 1.34, "desierto")
    addProp("desert_cactus", 17.0, StageRenderer.pathCenterV(17.0) + 5.1, 1.28, "desierto")

    -- E. Curated Shrine/Landmark at the outer rim of each of the 6 Side Alcoves
    for i = 1, #StageRenderer.SIDE_ALCOVES do
        local alc = StageRenderer.SIDE_ALCOVES[i]
        local pcA = StageRenderer.pathCenterV(alc.u)
        local side = (alc.v >= pcA) and 1.0 or -1.0
        addProp(alc.prop or "stone_pedestal", alc.u, alc.v + side * 1.55, 1.12, alc.biome)
    end

    -- F. Procedural Side Biome Decor with strict walkability & view clearance
    local bosqueFarProps = { "araucaria_tree", "ancient_tree", "araucaria_tree", "mossy_boulder", "copihue", "valdivian_fern" }
    local bosqueNearLow = { "valdivian_fern", "valdivian_shrub", "copihue", "mossy_boulder", "mossy_log" }
    local desiertoProps = { "desert_cactus", "mountain_crystal", "rock_monolith", "desert_cactus", "moai_relic", "apacheta_sundial" }
    local costaFarProps = { "valdivian_shrub", "mossy_boulder", "lantern_post", "pincoya_shrine" }
    local chiloeProps = { "lantern_post", "mossy_boulder", "calafate_bush", "valdivian_fern", "pincoya_shrine" }

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
                        and terrain ~= "pier" then

                        -- Keep foreground (+v) close band low so tall props never cover the Pudu!
                        local isForegroundNear = side > 0
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
                            if h1 < 0.54 then
                                kind = chiloeProps[(floor(h2 * #chiloeProps) % #chiloeProps) + 1]
                            end
                        end

                        if kind then
                            if not isTooCloseToList(pu, pv, decor, 1.55) then
                                addProp(kind, pu, pv, sc, biome)
                            end
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

local function paintFace(r, g, b, ...)
    love.graphics.setColor(r, g, b, 1)
    love.graphics.polygon("fill", ...)
end

local function drawLettuceCrate(x, y)
    paintFace(0.44, 0.28, 0.14, x, y, x + 27, y - 13.5, x + 27, y + 2, x, y + 15.5)
    paintFace(0.61, 0.38, 0.19, x - 13, y - 6.5, x, y, x, y + 15.5, x - 13, y + 9)
    paintFace(0.21, 0.30, 0.16, x - 13, y - 6.5, x + 14, y - 20, x + 27, y - 13.5, x, y)
    for i = 0, 2 do
        local leafX, leafY = x - 6 + i * 9, y - 9 - i * 4.5
        paintFace(0.31, 0.59, 0.22, leafX - 7, leafY - 2, leafX - 4, leafY - 11,
            leafX + 2, leafY - 14, leafX + 8, leafY - 9, leafX + 8, leafY - 2, leafX + 2, leafY + 3)
        paintFace(0.61, 0.76, 0.30, leafX - 5, leafY - 6, leafX - 3, leafY - 11,
            leafX + 2, leafY - 13, leafX + 5, leafY - 9, leafX + 1, leafY - 6)
    end
    paintFace(0.77, 0.51, 0.26, x, y, x + 27, y - 13.5, x + 27, y - 10, x, y + 3.5)
    paintFace(0.91, 0.62, 0.32, x - 13, y - 6.5, x, y, x, y + 3.5, x - 13, y - 3)
end

local TRUCK_WHEELS = { { 33, -31 }, { -67, 18 }, { -213, -55 } }

local function drawLettuceTruck(x, y, zoom, font)
    local lg = love.graphics
    local deck = DESERT_ARRIVAL.deckHeight
    lg.push()
    lg.translate(x, y)
    lg.scale(zoom)

    -- The cargo bay points along +v, with space behind the truck for the ramp.
    lg.push()
    lg.translate(-79, -26)
    lg.rotate(math.atan(0.5))
    lg.setColor(0.10, 0.08, 0.06, 0.20)
    lg.ellipse("fill", 7, 9, 150, 38)
    lg.setColor(0.13, 0.10, 0.08, 0.27)
    lg.ellipse("fill", 0, 0, 126, 28)
    lg.pop()

    paintFace(0.15, 0.17, 0.16, -237, -88, -189, -106, -38, -23, -38, 24, -235, -67)
    for _, wheel in ipairs(TRUCK_WHEELS) do
        local wx, wy = wheel[1], wheel[2]
        lg.setColor(0.10, 0.13, 0.13, 1)
        lg.ellipse("fill", wx, wy, 16, 20, 12)
        lg.setColor(0.26, 0.30, 0.27, 1)
        lg.ellipse("fill", wx - 1, wy - 1, 9, 12, 10)
        lg.setColor(0.58, 0.58, 0.47, 1)
        lg.ellipse("fill", wx - 1, wy - 1, 5, 6, 8)
    end

    -- Ochre cab and its windshield, door and step on the visible side.
    paintFace(0.47, 0.25, 0.13, -246, -107, -231, -100, -231, -63, -246, -70)
    paintFace(0.89, 0.56, 0.24, -246, -107, -224, -120, -209, -112, -231, -100)
    paintFace(0.69, 0.37, 0.16, -231, -100, -219, -141, -180, -121.5, -180, -57.5, -231, -83)
    paintFace(0.94, 0.66, 0.32, -219, -141, -142, -179.5, -103, -160, -180, -121.5)
    paintFace(0.24, 0.38, 0.37, -215, -131, -185, -116, -185, -91, -222, -109.5)
    paintFace(0.55, 0.69, 0.60, -215, -131, -185, -116, -185, -112, -216, -127.5)
    paintFace(0.94, 0.61, 0.27, -223, -105, -186, -86.5, -186, -65, -223, -83.5)
    paintFace(0.31, 0.24, 0.15, -198, -87, -188, -82, -188, -78, -198, -83)
    paintFace(0.95, 0.81, 0.52, -244, -95, -237, -91.5, -237, -83.5, -244, -87)
    paintFace(0.31, 0.35, 0.32, -246, -75, -232, -68, -232, -62, -246, -69)

    -- Insulated box. Every cargo face follows the same 2:1 floor projection.
    paintFace(0.62, 0.70, 0.56, -191, -197.5, -47, -125.5, 47, -172.5, -97, -244.5)
    paintFace(0.76, 0.78, 0.62, -188, -196, -47, -125.5, -42, -128, -183, -198.5)
    paintFace(0.29, 0.46, 0.36, -191, -197.5, -47, -125.5, -47, -8.5, -191, -80.5)
    paintFace(0.39, 0.56, 0.42, -186, -189, -52, -122, -52, -116, -186, -183)
    paintFace(0.22, 0.34, 0.28, -186, -90, -52, -23, -52, -15, -186, -82)

    lg.push()
    lg.translate(-173, -153)
    lg.shear(0, 0.5)
    lg.setColor(0.77, 0.78, 0.56, 1)
    lg.rectangle("fill", 0, 0, 104, 28)
    lg.setColor(0.16, 0.31, 0.20, 1)
    lg.setFont(font)
    lg.printf("LECHUGAS", 0, (28 - font:getHeight()) * 0.5, 104, "center")
    lg.pop()

    -- Dark opening, visible crates and the lower metal loading threshold.
    paintFace(0.39, 0.52, 0.40, -47, -125.5, 47, -172.5, 47, -55.5, -47, -8.5)
    paintFace(0.12, 0.17, 0.15, -39, -120, 39, -159, 39, -56, -39, -17)
    paintFace(0.20, 0.26, 0.21, 19, -149, 39, -159, 39, -56, 19, -46)
    paintFace(0.27, 0.29, 0.23, -39, -17, -59, -27, 19, -66, 39, -56)
    drawLettuceCrate(10, -54)
    drawLettuceCrate(-34, -29)

    local run = DESERT_ARRIVAL.finishV - DESERT_ARRIVAL.startV
    local rampX = run * StageRenderer.ISO_VX
    local rampY = run * StageRenderer.ISO_VY
    local rampHalfWidth = 34
    local rampHalfDepth = rampHalfWidth * 0.5
    local lx, ly = -rampHalfWidth, -deck + rampHalfDepth
    local rx, ry = rampHalfWidth, -deck - rampHalfDepth
    local bx, by = rampX - rampHalfWidth, rampY + rampHalfDepth
    local ex, ey = rampX + rampHalfWidth, rampY - rampHalfDepth
    paintFace(0.32, 0.30, 0.23, lx, ly, bx, by, bx, by + 5, lx, ly + 5)
    paintFace(0.49, 0.50, 0.39, lx, ly, rx, ry, ex, ey, bx, by)
    for i = 1, 5 do
        local t = i / 6
        local sx, sy = lerp(lx, bx, t), lerp(ly, by, t)
        local tx, ty = lerp(rx, ex, t), lerp(ry, ey, t)
        paintFace(0.61, 0.60, 0.45, sx, sy, tx, ty, tx + 1.8, ty + 2.2, sx + 1.8, sy + 2.2)
    end
    paintFace(0.60, 0.64, 0.49, -47, -16.5, 47, -63.5, 47, -55.5, -47, -8.5)
    paintFace(0.80, 0.32, 0.19, -46, -31, -39, -34.5, -39, -24, -46, -20.5)
    paintFace(0.80, 0.32, 0.19, 39, -73.5, 46, -77, 46, -66.5, 39, -63)

    lg.pop()
end

local function drawAricaSign(x, y, zoom, font)
    local lg = love.graphics
    lg.push()
    lg.translate(x, y)
    lg.scale(zoom)
    lg.setColor(0.12, 0.09, 0.07, 0.24)
    lg.ellipse("fill", 14, 2, 42, 10)
    lg.setColor(0.32, 0.37, 0.31, 1)
    lg.rectangle("fill", -32, -60, 7, 63)
    lg.rectangle("fill", 25, -60, 7, 63)
    lg.setColor(0.58, 0.61, 0.52, 1)
    lg.rectangle("fill", -32, -60, 2, 59)
    lg.rectangle("fill", 25, -60, 2, 59)
    lg.setColor(0.13, 0.24, 0.20, 1)
    lg.rectangle("fill", -58, -95, 116, 64, 5, 5)
    lg.setColor(0.75, 0.80, 0.63, 1)
    lg.rectangle("fill", -55, -92, 110, 58, 3, 3)
    lg.setColor(0.12, 0.33, 0.25, 1)
    lg.rectangle("fill", -52, -89, 104, 52, 2, 2)
    lg.pop()

    -- Keep the letters on whole screen pixels while the board follows the room zoom.
    local width = floor(104 * zoom + 0.5)
    local left = floor(x - width * 0.5 + 0.5)
    local halfLine = font:getHeight() * 0.5
    local kmY = floor(y - 76 * zoom - halfLine + 0.5)
    local aricaY = floor(y - 51 * zoom - halfLine + 0.5)
    lg.setFont(font)
    lg.setColor(0.06, 0.18, 0.13, 1)
    lg.printf("KM 23", left, kmY + 1, width, "center")
    lg.printf("ARICA", left, aricaY + 1, width, "center")
    lg.setColor(0.98, 0.97, 0.88, 1)
    lg.printf("KM 23", left, kmY, width, "center")
    lg.printf("ARICA", left, aricaY, width, "center")
end

local function drawStylizedProp(stage, prop, sx, sy, z, time, assetsOrProps, litShader, alphaOpt)
    local aMul = alphaOpt or 1.0
    local propsMap = (assetsOrProps and assetsOrProps.props) or assetsOrProps
    local lightRadial = assetsOrProps and assetsOrProps.lightRadial or nil
    local useLit = (litShader ~= nil and litShader ~= false and stage and stage.useLitShader)

    -- Mode A drop-in: if a real prop sprite exists in propsMap[kind].diff, draw it lit!
    local worldProp = prop.u ~= nil
    local scenery = worldProp and assetsOrProps and assetsOrProps.scenery
    local pair = scenery and scenery[prop.kind] or (type(propsMap) == "table" and propsMap[prop.kind])
    if type(pair) == "table" and pair.diff and not pair.isPlaceholder then
        local img = pair.diff
        local iw, ih = img:getDimensions()
        local targetH = worldProp and sceneryHeight(prop) * z or 86.0 * (prop.scale or 1.0) * z
        local sc = targetH / max(1, ih)
        local sway, lift = 0.0, 0.0
        local wind = worldProp and FOLIAGE_SWAY[prop.kind]
        if wind then
            sway = sin(time * 1.42 + prop.u * 0.69 + prop.v * 0.45) * wind
        end
        if prop.kind == "lily_pad" then
            lift = sin(time * 1.6 + (prop.u or 0)) * 1.25 * z
        else
            local contact = min(iw * sc * 0.36, targetH * 0.29, 33 * z)
            if worldProp then
                local preset = StageRenderer.LIGHTING_PRESETS[stage.lightingPreset]
                local dx, dy = -preset.sunDir[1], -preset.sunDir[2] * 0.58
                local length = targetH * 0.49
                love.graphics.push()
                love.graphics.translate(sx + dx * length * 0.68, sy + dy * length * 0.68)
                love.graphics.rotate(math.atan2(dy, dx))
                love.graphics.setColor(0.035, 0.063, 0.064, 0.14 + preset.sunEnergy * 0.075)
                love.graphics.ellipse("fill", 0, 0, max(contact, length * 0.64), contact * 0.57)
                love.graphics.pop()
            end
            love.graphics.setColor(0.04, 0.05, 0.07, 0.29 * aMul)
            love.graphics.ellipse("fill", sx, sy + z, contact, max(3 * z, contact * 0.35))
        end
        love.graphics.setColor(1, 1, 1, aMul)
        local emBoost = 0.0
        local emCol = nil
        if prop.kind == "lantern_post" then
            emBoost, emCol = 0.14, { 1.0, 0.78, 0.36 }
        elseif prop.kind == "mountain_crystal" or prop.kind == "pincoya_shrine" then
            emBoost, emCol = 0.22, { 0.38, 0.92, 1.0 }
        elseif prop.kind == "orb_shrine" or prop.kind == "quena_monolith" then
            emBoost, emCol = 0.18, { 1.0, 0.84, 0.38 }
        end
        if stage then
            stage:drawSpriteLit(pair, sx, sy + lift, sway, sc, sc, iw * 0.5, ih * 0.96,
                nil, emBoost, emCol, useLit and litShader or nil, true)
        else
            love.graphics.draw(img, sx, sy, 0, sc, sc, iw * 0.5, ih * 0.92)
        end
        return
    end

    -- Mode B high-craft stylized Chilean geometric landmarks
    local k = prop.kind
    local s = (prop.scale or 1.0) * z
    local seed = prop.u or (prop.xFrac and prop.xFrac * 25.0) or 1.0
    local sway = sin(time * 1.8 + seed * 0.7) * 1.8 * s

    -- Ground contact shadow (always unlit; omitted for flat lily pads and ship on water)
    if k ~= "lily_pad" and k ~= "caleuche_ship" then
        love.graphics.setColor(0.04, 0.05, 0.09, 0.28 * aMul)
        love.graphics.ellipse("fill", sx, sy + 1 * s, 20 * s, 8 * s)
    end

    local function beginBodyLit()
        if useLit then
            love.graphics.setShader(litShader)
            safeSend(litShader, "hasNormalMap", 0.0)
            safeSend(litShader, "spriteAngle", 0.0)
            safeSend(litShader, "spriteBillboard", 1.0)
            safeSend(litShader, "surfaceBaseY", sy)
            safeSend(litShader, "emissiveBoost", 0.0)
            safeSend(litShader, "specStrength", 0.16)
        end
    end

    local function endBodyLit()
        if useLit then
            love.graphics.setShader()
        end
    end

    beginBodyLit()

    if k == "araucaria_tree" then
        -- Iconic Chilean Araucaria: tall straight bark trunk + radiating tiered umbrella canopy
        love.graphics.setColor(0.34, 0.22, 0.14, aMul)
        love.graphics.rectangle("fill", sx - 5.5 * s, sy - 76 * s, 11 * s, 77 * s)
        love.graphics.setColor(0.48, 0.34, 0.21, aMul)
        love.graphics.rectangle("fill", sx - 4.0 * s, sy - 76 * s, 3.5 * s, 76 * s)
        for i = 1, #ARAUCARIA_TIERS do
            local tr = ARAUCARIA_TIERS[i]
            love.graphics.setColor(tr.col[1], tr.col[2], tr.col[3], aMul)
            love.graphics.ellipse("fill", sx + sway * 0.5, sy + tr.y * s, tr.rx * s, tr.ry * s)
            love.graphics.setColor(tr.col[1] + 0.10, tr.col[2] + 0.14, tr.col[3] + 0.08, 0.78 * aMul)
            love.graphics.ellipse("fill", sx - 5 * s + sway * 0.5, sy + (tr.y - 2) * s, tr.rx * 0.65 * s, tr.ry * 0.54 * s)
        end

    elseif k == "ancient_tree" then
        -- Lush Valdivian coigue tree
        love.graphics.setColor(0.36, 0.23, 0.14, aMul)
        love.graphics.rectangle("fill", sx - 7.5 * s, sy - 44 * s, 15 * s, 45 * s)
        love.graphics.setColor(0.14, 0.36, 0.19, aMul)
        love.graphics.circle("fill", sx - 15 * s + sway * 0.4, sy - 48 * s, 21 * s)
        love.graphics.circle("fill", sx + 15 * s + sway * 0.4, sy - 46 * s, 20 * s)
        love.graphics.setColor(0.20, 0.48, 0.24, aMul)
        love.graphics.circle("fill", sx + sway * 0.5, sy - 62 * s, 25 * s)
        love.graphics.setColor(0.34, 0.66, 0.32, 0.86 * aMul)
        love.graphics.circle("fill", sx - 7 * s + sway * 0.5, sy - 68 * s, 14 * s)

    elseif k == "valdivian_fern" or k == "valdivian_shrub" then
        love.graphics.setColor(0.16, 0.42, 0.20, aMul)
        love.graphics.ellipse("fill", sx - 9 * s, sy - 7 * s, 12 * s, 6 * s)
        love.graphics.ellipse("fill", sx + 9 * s, sy - 7 * s, 12 * s, 6 * s)
        love.graphics.setColor(0.26, 0.58, 0.26, aMul)
        love.graphics.ellipse("fill", sx, sy - 11 * s, 13 * s, 8 * s)
        love.graphics.setColor(0.42, 0.74, 0.34, 0.85 * aMul)
        love.graphics.ellipse("fill", sx - 3 * s, sy - 14 * s, 7 * s, 4 * s)

    elseif k == "copihue" then
        -- Green shrub studded with bright Chilean crimson copihue bell-flowers
        love.graphics.setColor(0.15, 0.40, 0.20, aMul)
        love.graphics.ellipse("fill", sx, sy - 10 * s, 15 * s, 9 * s)
        love.graphics.setColor(0.24, 0.54, 0.26, aMul)
        love.graphics.ellipse("fill", sx - 3 * s, sy - 14 * s, 10 * s, 6 * s)
        love.graphics.setColor(0.92, 0.16, 0.26, aMul)
        love.graphics.ellipse("fill", sx - 8 * s, sy - 12 * s, 3.2 * s, 5.2 * s)
        love.graphics.ellipse("fill", sx + 5 * s, sy - 15 * s, 3.2 * s, 5.2 * s)
        love.graphics.ellipse("fill", sx + 1 * s, sy - 8 * s, 3.0 * s, 4.6 * s)

    elseif k == "mossy_boulder" or k == "rock_monolith" or k == "debris_pile" then
        local isDesert = (prop.biome == "desierto")
        local isChiloe = (prop.biome == "chiloe")
        local baseR = isDesert and 0.70 or (isChiloe and 0.44 or 0.42)
        local baseG = isDesert and 0.39 or (isChiloe and 0.46 or 0.45)
        local baseB = isDesert and 0.24 or (isChiloe and 0.54 or 0.48)
        local hRock = (k == "rock_monolith") and 40 * s or 20 * s
        local wRock = (k == "rock_monolith") and 16 * s or 19 * s
        love.graphics.setColor(baseR * 0.72, baseG * 0.72, baseB * 0.76, aMul)
        love.graphics.polygon("fill", sx - wRock, sy, sx - wRock * 0.6, sy - hRock, sx + wRock * 0.55, sy - hRock * 0.88, sx + wRock, sy)
        love.graphics.setColor(baseR, baseG, baseB, aMul)
        love.graphics.polygon("fill", sx - wRock, sy, sx - wRock * 0.6, sy - hRock, sx + 2 * s, sy - hRock * 0.75, sx, sy + 2 * s)
        if not isDesert and not isChiloe then
            love.graphics.setColor(0.28, 0.56, 0.26, 0.90 * aMul)
            love.graphics.ellipse("fill", sx - 2 * s, sy - hRock * 0.82, wRock * 0.55, 4.5 * s)
        end

    elseif k == "desert_cactus" then
        -- Multi-armed Atacama cardon cactus
        love.graphics.setColor(0.18, 0.46, 0.27, aMul)
        love.graphics.rectangle("fill", sx - 7.5 * s, sy - 66 * s, 15 * s, 67 * s, 6 * s, 6 * s)
        love.graphics.rectangle("fill", sx - 25 * s, sy - 45 * s, 19 * s, 9.5 * s, 4 * s, 4 * s)
        love.graphics.rectangle("fill", sx - 25 * s, sy - 60 * s, 11 * s, 22 * s, 5 * s, 5 * s)
        love.graphics.rectangle("fill", sx + 5 * s, sy - 38 * s, 19 * s, 9.5 * s, 4 * s, 4 * s)
        love.graphics.rectangle("fill", sx + 13 * s, sy - 54 * s, 11 * s, 24 * s, 5 * s, 5 * s)
        love.graphics.setColor(0.36, 0.68, 0.40, 0.88 * aMul)
        love.graphics.rectangle("fill", sx - 3.5 * s, sy - 62 * s, 3.8 * s, 58 * s)
        love.graphics.setColor(0.98, 0.74, 0.24, aMul)
        love.graphics.circle("fill", sx, sy - 68 * s, 4.5 * s)

    elseif k == "mountain_crystal" then
        -- Glowing faceted Atacama crystal cluster (self-luminous facets pop at night!)
        endBodyLit()
        local glow = 0.75 + 0.25 * sin(time * 3.0 + seed)
        love.graphics.setColor(0.32, 0.86, 0.96, 0.24 * glow * aMul)
        love.graphics.circle("fill", sx, sy - 24 * s, 28 * s)
        love.graphics.setColor(0.22, 0.68, 0.86, 0.95 * aMul)
        love.graphics.polygon("fill", sx - 16 * s, sy, sx - 12 * s, sy - 30 * s, sx - 2 * s, sy)
        love.graphics.setColor(0.56, 0.34, 0.86, 0.95 * aMul)
        love.graphics.polygon("fill", sx + 2 * s, sy, sx + 14 * s, sy - 34 * s, sx + 18 * s, sy)
        love.graphics.setColor(0.42, 0.92, 0.98, 0.98 * aMul)
        love.graphics.polygon("fill", sx - 9 * s, sy + 1 * s, sx, sy - 48 * s, sx + 10 * s, sy + 1 * s)
        love.graphics.setColor(0.86, 0.99, 1.0, 0.88 * aMul)
        love.graphics.polygon("fill", sx - 5 * s, sy - 4 * s, sx, sy - 46 * s, sx + 2 * s, sy - 4 * s)

    elseif k == "apacheta_sundial" or k == "moai_relic" then
        -- Stacked Andean stone cairn / volcanic relic
        love.graphics.setColor(0.56, 0.36, 0.26, aMul)
        love.graphics.ellipse("fill", sx, sy - 6 * s, 16 * s, 7 * s)
        love.graphics.setColor(0.64, 0.43, 0.31, aMul)
        love.graphics.ellipse("fill", sx, sy - 17 * s, 12 * s, 6 * s)
        love.graphics.setColor(0.72, 0.50, 0.36, aMul)
        love.graphics.ellipse("fill", sx, sy - 27 * s, 8 * s, 5 * s)
        love.graphics.setColor(0.98, 0.82, 0.30, aMul)
        love.graphics.circle("fill", sx, sy - 38 * s, 6.5 * s)

    elseif k == "rewe_totem" then
        -- Carved wooden Mapuche ceremonial stepped totem
        love.graphics.setColor(0.46, 0.28, 0.16, aMul)
        love.graphics.rectangle("fill", sx - 6 * s, sy - 58 * s, 12 * s, 59 * s)
        love.graphics.setColor(0.62, 0.40, 0.23, aMul)
        for st = 1, 4 do
            love.graphics.rectangle("fill", sx - 8 * s, sy - st * 11 * s, 16 * s, 4 * s)
        end
        love.graphics.setColor(0.88, 0.68, 0.30, aMul)
        love.graphics.polygon("fill", sx, sy - 68 * s, sx - 9 * s, sy - 56 * s, sx + 9 * s, sy - 56 * s)

    elseif k == "orb_shrine" or k == "stone_pedestal" or k == "pincoya_shrine" or k == "quena_monolith" then
        -- Stepped stone pedestal with floating glowing magic orb
        local bob = sin(time * 2.8 + seed) * 4.0 * s
        love.graphics.setColor(0.48, 0.51, 0.58, aMul)
        love.graphics.rectangle("fill", sx - 16 * s, sy - 10 * s, 32 * s, 11 * s, 2, 2)
        love.graphics.setColor(0.62, 0.66, 0.74, aMul)
        love.graphics.rectangle("fill", sx - 10 * s, sy - 30 * s, 20 * s, 22 * s)
        love.graphics.setColor(0.78, 0.82, 0.90, aMul)
        love.graphics.rectangle("fill", sx - 13 * s, sy - 34 * s, 26 * s, 5 * s)
        -- Self-luminous floating orb stays crisp & bright in noche/dramatico
        endBodyLit()
        local orbCol = (k == "pincoya_shrine") and { 0.30, 0.92, 0.94 } or { 0.98, 0.82, 0.34 }
        love.graphics.setColor(orbCol[1], orbCol[2], orbCol[3], 0.30 * aMul)
        love.graphics.circle("fill", sx, sy - 46 * s + bob, 16 * s)
        love.graphics.setColor(orbCol[1], orbCol[2], orbCol[3], 0.98 * aMul)
        love.graphics.circle("fill", sx, sy - 46 * s + bob, 7.5 * s)
        love.graphics.setColor(1, 1, 1, 0.90 * aMul)
        love.graphics.circle("fill", sx - 2.2 * s, sy - 48.2 * s + bob, 2.4 * s)

    elseif k == "lantern_post" then
        -- Warm fantasy / urban streetlamp with glowing amber globe
        love.graphics.setColor(0.20, 0.22, 0.28, aMul)
        love.graphics.rectangle("fill", sx - 5 * s, sy - 5 * s, 10 * s, 6 * s)
        love.graphics.rectangle("fill", sx - 2.2 * s, sy - 54 * s, 4.4 * s, 51 * s)
        love.graphics.rectangle("fill", sx - 2 * s, sy - 54 * s, 14 * s, 3 * s)
        -- Self-luminous warm amber globe & halo
        endBodyLit()
        local lx, ly = sx + 10 * s, sy - 48 * s
        local pulse = 0.86 + 0.14 * sin(time * 4.0 + seed)
        if lightRadial then
            local lw, lh = lightRadial:getDimensions()
            local haloSc = (54 * s) / max(1, lw)
            love.graphics.setColor(1.0, 0.78, 0.32, 0.34 * pulse * aMul)
            love.graphics.draw(lightRadial, lx, ly, 0, haloSc, haloSc, lw * 0.5, lh * 0.5)
        else
            love.graphics.setColor(1.0, 0.78, 0.32, 0.24 * pulse * aMul)
            love.graphics.circle("fill", lx, ly, 22 * s)
        end
        love.graphics.setColor(1.0, 0.92, 0.50, 0.98 * aMul)
        love.graphics.rectangle("fill", lx - 4 * s, ly - 5 * s, 8 * s, 10 * s, 2, 2)
        love.graphics.setColor(1.0, 0.98, 0.82, 0.92 * aMul)
        love.graphics.rectangle("fill", lx - 2 * s, ly - 3 * s, 4 * s, 5 * s, 1, 1)
        beginBodyLit()
        love.graphics.setColor(0.20, 0.22, 0.28, aMul)
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
        love.graphics.setColor(pR * 0.72, pG * 0.72, pB * 0.76, aMul)
        love.graphics.rectangle("fill", sx - 13 * s, sy - 10 * s, 26 * s, 11 * s)
        love.graphics.setColor(pR, pG, pB, aMul)
        love.graphics.rectangle("fill", sx - 9 * s, sy - 66 * s, 18 * s, 58 * s)
        love.graphics.setColor(pR * 1.18, pG * 1.18, pB * 1.18, 0.95 * aMul)
        love.graphics.rectangle("fill", sx - 12 * s, sy - 70 * s, 24 * s, 7 * s)
        -- Self-luminous frontier crystal/brazier atop pillar
        endBodyLit()
        love.graphics.setColor(bR, bG, bB, 0.32 * aMul)
        love.graphics.circle("fill", sx, sy - 78 * s, 16 * s)
        love.graphics.setColor(bR, bG, bB, aMul)
        love.graphics.polygon("fill", sx, sy - 88 * s, sx - 7 * s, sy - 76 * s, sx, sy - 70 * s, sx + 7 * s, sy - 76 * s)

    elseif k == "coast_lighthouse" then
        -- Iconic tall red-and-white striped Valparaiso lighthouse with sweeping beacon
        love.graphics.setColor(0.38, 0.40, 0.46, aMul)
        love.graphics.ellipse("fill", sx, sy, 26 * s, 11 * s)
        local towerH = 104 * s
        local segs = 5
        for i = 0, segs - 1 do
            local yBot = sy - (i / segs) * towerH
            local yTop = sy - ((i + 1) / segs) * towerH
            local wBot = lerp(16 * s, 9 * s, i / segs)
            local wTop = lerp(16 * s, 9 * s, (i + 1) / segs)
            if i % 2 == 0 then
                love.graphics.setColor(0.95, 0.95, 0.97, aMul)
            else
                love.graphics.setColor(0.84, 0.22, 0.22, aMul)
            end
            love.graphics.polygon("fill", sx - wBot, yBot, sx + wBot, yBot, sx + wTop, yTop, sx - wTop, yTop)
        end
        local topY = sy - towerH
        love.graphics.setColor(0.20, 0.24, 0.32, aMul)
        love.graphics.rectangle("fill", sx - 12 * s, topY - 3 * s, 24 * s, 4 * s)
        -- Glowing beacon glass & sweeping volumetric beam (always bright!)
        endBodyLit()
        local beamAngle = sin(time * 1.4) * 0.55
        love.graphics.setColor(1.0, 0.92, 0.52, 0.24 * aMul)
        love.graphics.polygon(
            "fill",
            sx, topY - 10 * s,
            sx + cos(beamAngle - 0.16) * 95 * s, topY - 10 * s + sin(beamAngle - 0.16) * 42 * s,
            sx + cos(beamAngle + 0.16) * 95 * s, topY - 10 * s + sin(beamAngle + 0.16) * 42 * s
        )
        love.graphics.setColor(1.0, 0.95, 0.58, 0.98 * aMul)
        love.graphics.rectangle("fill", sx - 7 * s, topY - 16 * s, 14 * s, 13 * s)
        beginBodyLit()
        love.graphics.setColor(0.82, 0.20, 0.20, aMul)
        love.graphics.polygon("fill", sx - 10 * s, topY - 16 * s, sx + 10 * s, topY - 16 * s, sx, topY - 28 * s)

    elseif k == "caleuche_ship" then
        -- Iconic Chilean Caleuche ghostly wooden tall ship rocking gently in the bay
        local bob = sin(time * 1.6 + seed) * 4.5 * s
        local syB = sy + bob
        love.graphics.setColor(0.76, 0.96, 1.0, 0.42 * aMul)
        love.graphics.ellipse("line", sx, sy + 5 * s, 46 * s, 14 * s)
        love.graphics.setColor(0.32, 0.20, 0.14, aMul)
        love.graphics.polygon("fill", sx - 40 * s, syB - 8 * s, sx + 42 * s, syB - 10 * s, sx + 28 * s, syB + 8 * s, sx - 28 * s, syB + 8 * s)
        love.graphics.setColor(0.46, 0.30, 0.19, aMul)
        love.graphics.rectangle("fill", sx - 34 * s, syB - 12 * s, 68 * s, 5 * s)
        love.graphics.setColor(0.24, 0.16, 0.11, aMul)
        love.graphics.rectangle("fill", sx - 12 * s, syB - 70 * s, 3.5 * s, 60 * s)
        love.graphics.rectangle("fill", sx + 14 * s, syB - 58 * s, 3.2 * s, 48 * s)
        love.graphics.setColor(0.84, 0.96, 0.94, 0.90 * aMul)
        love.graphics.polygon("fill", sx - 26 * s, syB - 60 * s, sx + 4 * s, syB - 56 * s, sx + 6 * s, syB - 22 * s, sx - 24 * s, syB - 24 * s)
        love.graphics.polygon("fill", sx + 4 * s, syB - 50 * s, sx + 28 * s, syB - 46 * s, sx + 28 * s, syB - 20 * s, sx + 6 * s, syB - 22 * s)
        endBodyLit()
        love.graphics.setColor(0.45, 0.98, 0.86, 0.92 * aMul)
        love.graphics.circle("fill", sx - 32 * s, syB - 15 * s, 4.0 * s)

    elseif k == "office_column" then
        -- Grand neoclassical-office marble/granite column
        love.graphics.setColor(0.58, 0.62, 0.72, aMul)
        love.graphics.rectangle("fill", sx - 12 * s, sy - 8 * s, 24 * s, 9 * s)
        love.graphics.setColor(0.76, 0.80, 0.88, aMul)
        love.graphics.rectangle("fill", sx - 8 * s, sy - 66 * s, 16 * s, 59 * s)
        love.graphics.setColor(0.90, 0.92, 0.98, 0.85 * aMul)
        love.graphics.rectangle("fill", sx - 6 * s, sy - 65 * s, 4 * s, 57 * s)
        love.graphics.setColor(0.94, 0.78, 0.30, aMul)
        love.graphics.rectangle("fill", sx - 11 * s, sy - 71 * s, 22 * s, 6 * s)

    elseif k == "stanchion" then
        -- Brass velvet-queue post / harbor bollard
        love.graphics.setColor(0.78, 0.62, 0.22, aMul)
        love.graphics.ellipse("fill", sx, sy, 6.5 * s, 3.0 * s)
        love.graphics.rectangle("fill", sx - 1.8 * s, sy - 22 * s, 3.6 * s, 22 * s)
        love.graphics.setColor(0.98, 0.86, 0.36, aMul)
        love.graphics.circle("fill", sx, sy - 23 * s, 3.4 * s)

    elseif k == "lily_pad" then
        love.graphics.setColor(0.22, 0.56, 0.28, 0.92 * aMul)
        love.graphics.ellipse("fill", sx, sy, 12 * s, 6 * s)
        love.graphics.setColor(0.96, 0.68, 0.78, 0.95 * aMul)
        love.graphics.circle("fill", sx + 2 * s, sy - 1 * s, 3.0 * s)

    elseif k == "mossy_log" or k == "log_dam" then
        love.graphics.setColor(0.42, 0.27, 0.16, aMul)
        love.graphics.rectangle("fill", sx - 20 * s, sy - 11 * s, 40 * s, 11 * s, 4 * s, 4 * s)
        love.graphics.setColor(0.56, 0.39, 0.24, aMul)
        love.graphics.ellipse("fill", sx - 19 * s, sy - 5.5 * s, 4 * s, 5.5 * s)
        love.graphics.setColor(0.26, 0.56, 0.26, 0.92 * aMul)
        love.graphics.ellipse("fill", sx + 2 * s, sy - 11 * s, 13 * s, 4 * s)

    else
        -- Clean fallback milestone marker
        love.graphics.setColor(0.52, 0.56, 0.64, aMul)
        love.graphics.rectangle("fill", sx - 8 * s, sy - 24 * s, 16 * s, 25 * s, 3, 3)
    end

    endBodyLit()
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

local function drawRivalEntity(stage, enc, idx, sx, sy, sw, sh, z, time, assets, defeated, isAlerted, alertTimer, font, litShader)
    local encPair = assets and assets.encounters and assets.encounters[enc.id]
    local targetH = (enc.scale or 2.55) * 38.0 * (z / 0.72)
    if encPair and encPair.isPlaceholder and assets.scenery then
        if enc.id == "caleuche" then
            encPair = assets.scenery.caleuche_ship or encPair
            targetH = targetH * 1.12
        elseif enc.id == "pila_de_ropa" then
            encPair = assets.scenery.textile_bale or encPair
            targetH = targetH * 0.85
        end
    end
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
        if stage then
            stage:drawSpriteLit(encPair, sx, sy + bob, 0, sc, sc, fw * 0.5, fh * 0.92, quad, 0.0, nil, litShader, true)
        elseif quad then
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

    -- Clean name pill above rival head (unshaded crisp UI; ZERO Unicode tofu; y>=52)
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
        local py = floor(sy - targetH - ph - 6 + bob)
        local fitsAbove = py >= 52
        if not fitsAbove then py = floor(sy + 11) end

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
            drawAlertCallout(sx, fitsAbove and (py - 2) or max(52, sy - targetH - 8), alertTimer)
        end
    elseif isAlerted then
        drawAlertCallout(sx, max(52, sy - targetH - 8), alertTimer)
    end
end

-- Head motion measured relative to the first frame of each row in the stock 60px sheet.
local PUDU_HEAD_MOTION = {
    [0] = { [3] = { -1, -2 }, [4] = { 0, 0 }, [5] = { 1, -2 } },
    [1] = { [3] = { 4, -2 }, [4] = { 1, 0 }, [5] = { 5, -1 } },
    [2] = { [3] = { 2, -1 }, [4] = { 0, 0 }, [5] = { 4, -1 } },
    [3] = { [3] = { 4, -2 }, [4] = { 2, 0 }, [5] = { 4, -1 } },
    [4] = { [3] = { 0, -3 }, [4] = { 0, 0 }, [5] = { 0, -3 } },
    [5] = { [3] = { -3, -2 }, [4] = { -1, 0 }, [5] = { -3, -1 } },
    [6] = { [3] = { -2, -1 }, [4] = { 0, 0 }, [5] = { -4, -1 } },
    [7] = { [3] = { -5, -2 }, [4] = { -1, 0 }, [5] = { -6, -1 } },
}

function StageRenderer.getPuduFrameAnchor(pair, row, col, qw, qh)
    local defaultFootY = qh * 0.88
    if qw ~= 60 or qh ~= 60 or pair.isCustom or pair.isPlaceholder then
        return defaultFootY, 0, 0
    end

    local footY = 56
    local pivotShiftY = defaultFootY - footY
    local frames = PUDU_HEAD_MOTION[row]
    local motion = frames and frames[col]
    if motion then
        return footY, motion[1], pivotShiftY + motion[2]
    end
    return footY, 0, pivotShiftY - (col == 2 and 1 or 0)
end

local function drawPuduWithHat(stage, sx, sy, facingRow, animCol, targetH, bobY, assets, litShader, pose, lift)
    local row = clamp(floor(facingRow or 3), 0, 7)
    local col = clamp(floor(animCol or 1), 1, 6)
    local tilt = pose and pose.tilt or 0.0
    local scaleX = pose and pose.scaleX or 1.0
    local scaleY = pose and pose.scaleY or 1.0
    local frameY = sy + (pose and pose.jumpY or bobY or 0.0) - (lift or 0.0)

    -- Soft contact shadow beneath hooves
    local shadowAlpha = 0.34 - 0.22 * smoothstep(0.0, 25.0, sy - frameY)
    love.graphics.setColor(0.04, 0.04, 0.08, shadowAlpha)
    love.graphics.ellipse("fill", sx, sy + 2, targetH * 0.25, targetH * 0.09)

    local puduPair = assets and assets.pudu
    local quads = assets and assets.puduQuads
    local headX, headY = 0.0, 0.0
    if puduPair and puduPair.diff and quads and quads[row] and quads[row][col] then
        local quad = quads[row][col]
        local _, _, qw, qh = quad:getViewport()
        local sc = targetH / max(1, qh)
        local footY, shiftX, shiftY = StageRenderer.getPuduFrameAnchor(puduPair, row, col, qw, qh)
        headX, headY = shiftX * sc, shiftY * sc
        love.graphics.setColor(1, 1, 1, 1)
        if stage then
            stage:drawSpriteLit(puduPair, sx, frameY, tilt, sc * scaleX, sc * scaleY, qw * 0.5, footY,
                quad, 0.0, nil, litShader, true)
        else
            love.graphics.draw(puduPair.diff, quad, sx, frameY, tilt, sc * scaleX, sc * scaleY, qw * 0.5, footY)
        end
    else
        love.graphics.setColor(0.58, 0.35, 0.20, 1.0)
        love.graphics.circle("fill", sx, frameY - targetH * 0.4, targetH * 0.28)
    end

    -- Pointy brown wizard hat anchored cleanly to the Pudu's head for the current facing row
    local hatPair = assets and assets.wizardHat
    if hatPair and hatPair.diff then
        local hw, hh = hatPair.diff:getDimensions()
        local unit = targetH / 64.0
        local off = StageRenderer.HAT_HEAD_OFFSETS[row] or StageRenderer.HAT_HEAD_OFFSETS[3]
        local hatSc = (targetH * 0.58) / max(1, hh)
        local localX = (off.x * unit + headX) * scaleX
        local localY = (off.y * unit + headY) * scaleY
        local cosT, sinT = cos(tilt), sin(tilt)
        local hatX = sx + localX * cosT - localY * sinT
        local hatY = frameY + localX * sinT + localY * cosT + (pose and pose.hatOffsetY or 0.0)
        local hRot = pose and pose.hatTilt or tilt
        love.graphics.setColor(1, 1, 1, 1)
        if stage then
            stage:drawSpriteLit(hatPair, hatX, hatY, hRot, hatSc, hatSc, hw * 0.50, hh * 0.78, nil, 0.0, nil, litShader, true)
        else
            love.graphics.draw(hatPair.diff, hatX, hatY, hRot, hatSc, hatSc, hw * 0.50, hh * 0.78)
        end
    end
end

local function sortByDepth(a, b)
    if a.sortY ~= b.sortY then
        return a.sortY < b.sortY
    end
    return a.tie < b.tie
end

local function drawBodoque(stage, pair, x, y, zoom, time, litShader)
    local iw, ih = pair.diff:getDimensions()
    local h = BODOQUE.height * zoom / 0.72
    local scale = h / ih
    local gesture = sin(pi * stage._bodoqueGesture / 0.48) ^ 2
    local breath = sin(time * 2.8) * 0.012
    local sx = scale * (1.0 - breath * 0.40 - gesture * 0.018)
    local sy = scale * (1.0 + breath + gesture * 0.042)

    love.graphics.setColor(0.07, 0.05, 0.09, 0.18)
    love.graphics.ellipse("fill", x + 3 * zoom, y + 2 * zoom, 23 * zoom, 8 * zoom)
    love.graphics.setColor(0.04, 0.04, 0.07, 0.25)
    love.graphics.ellipse("fill", x, y, 15 * zoom, 4 * zoom)
    love.graphics.setColor(1, 1, 1, 1)
    stage:drawSpriteLit(pair, x, y, 0, sx, sy, iw * 0.5, ih, nil, 0, nil, litShader, true)
    stage._bodoqueScreenX, stage._bodoqueScreenTop = x, y - ih * sy
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
    local litShader = (ctx.litShader ~= nil and ctx.litShader ~= false and self.useLitShader) and ctx.litShader or nil

    if not self._decorBuilt then
        self:buildOverworldDecor(encList)
    end

    -- 1. Floor pass (unless caller already rendered it explicitly)
    if not ctx.skipFloor then
        self:drawOverworldFloor(ctx)
    end

    -- 2. Gather visible props and characters into the reusable Y-sort list.
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
            local extent = sceneryHeight(prop) * z
            if sx >= -extent and sx <= sw + extent and sy >= -32 and sy <= sh + extent then
                local baseY = baseScreenY + (prop.u - camU) * uyZ + (prop.v - camV) * vyZ
                -- Flat lily pads stay underneath characters
                local tie = (prop.kind == "lily_pad") and -1000 or i
                local sortY = (prop.kind == "lily_pad") and (baseY - 40.0) or baseY
                pushEntry("prop", sortY, tie, sx, sy, prop, i)
            end
        end
    end

    -- Encounters
    for i = 1, #encList do
        local enc = encList[i]
        if enc and abs(enc.u - camU) <= 18.0 then
            local elev = StageRenderer.getElevation(enc.u, enc.v)
            local sx, sy = self:isoToScreen(enc.u, enc.v, elev, sw, sh)
            if sx >= -120 and sx <= sw + 120 and sy >= -120 and sy <= sh + 150 then
                local baseY = baseScreenY + (enc.u - camU) * uyZ + (enc.v - camV) * vyZ
                pushEntry("rival", baseY, 10000 + i, sx, sy, enc, enc.index or i)
            end
        end
    end

    self._bodoqueScreenX = nil
    local bodoquePair = assets and assets.bodoque
    if bodoquePair and abs(BODOQUE.u - camU) <= 18.0 then
        local elev = StageRenderer.getElevation(BODOQUE.u, BODOQUE.v)
        local sx, sy = self:isoToScreen(BODOQUE.u, BODOQUE.v, elev, sw, sh)
        if sx >= -80 and sx <= sw + 80 and sy >= 0 and sy <= sh + 120 then
            local baseY = baseScreenY + (BODOQUE.u - camU) * uyZ + (BODOQUE.v - camV) * vyZ
            pushEntry("bodoque", baseY, 15000, sx, sy, bodoquePair, 0)
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
    local headingFont = (ctx.fonts and ctx.fonts.heading) or smallFont
    local puduTargetH = (ctx.puduTargetH or 84.0) * (z / 0.72)

    for i = 1, count do
        local item = list[i]
        if item.kind == "prop" then
            if item.data.kind == "lettuce_truck" then
                drawLettuceTruck(item.sx, item.sy, z, headingFont)
            elseif item.data.kind == "arica_sign" then
                drawAricaSign(item.sx, item.sy, z, headingFont)
            else
                drawStylizedProp(self, item.data, item.sx, item.sy, z, time, assets, litShader, 1.0)
            end
        elseif item.kind == "rival" then
            local enc = item.data
            local idx = item.idx
            local isDef = (defeatedMap[enc.id] == true) or (defeatedMap[idx] == true)
            local isAlerted = (ctx.alertEncounterIdx == idx)
            drawRivalEntity(self, enc, idx, item.sx, item.sy, sw, sh, z, time, assets, isDef, isAlerted, ctx.alertTimer, smallFont, litShader)
        elseif item.kind == "bodoque" then
            drawBodoque(self, item.data, item.sx, item.sy, z, time, litShader)
        else
            drawPuduWithHat(
                self,
                item.sx,
                item.sy,
                ctx.puduFacingRow or 3,
                (ctx.puduPose and ctx.puduPose.col) or ctx.puduAnimCol or 1,
                puduTargetH,
                ctx.puduBobY or 0.0,
                assets,
                litShader,
                ctx.puduPose,
                (ctx.puduArrivalLift or 0.0) * z
            )
        end
    end
end

-- Draw after the world post-processing so the letter edges stay sharp.
function StageRenderer:drawOverworldNPCDialogue(w, h, font)
    local x, headY = self._bodoqueScreenX, self._bodoqueScreenTop
    local progress = self._bodoqueDialogue
    if not x or progress == 0 or x < 12 or x > w - 12 then return end

    local f = font or makeFallbackFont()
    local alpha = smoothstep(0.0, 1.0, progress)
    local padding = 12
    local lineH = f:getHeight()
    local boxW = max(f:getWidth(BODOQUE.name), f:getWidth(BODOQUE.line)) + padding * 2
    local boxH = lineH * 2 + 18
    local left = floor(clamp(x - boxW * 0.5, 12, w - boxW - 12))
    local top = floor(headY - boxH - 14 + (1.0 - alpha) * 5)
    local bottom = top + boxH
    -- Keep the card above the sprite and away from the map and HUD.
    if top < 54 or bottom + 12 > h - 60 or (left < 231 and top < 185) then return end
    local tailX = floor(clamp(x, left + 14, left + boxW - 14))

    love.graphics.push("all")
    love.graphics.setFont(f)
    love.graphics.setColor(0.04, 0.03, 0.08, 0.48 * alpha)
    love.graphics.rectangle("fill", left + 2, top + 3, boxW, boxH, 8, 8)
    love.graphics.setColor(0.96, 0.66, 0.45, 0.88 * alpha)
    love.graphics.polygon("fill", tailX - 7, bottom - 2, tailX + 7, bottom - 2, tailX, bottom + 9)
    love.graphics.rectangle("fill", left, top, boxW, boxH, 8, 8)
    love.graphics.setColor(0.10, 0.07, 0.14, alpha)
    love.graphics.polygon("fill", tailX - 5, bottom - 2, tailX + 5, bottom - 2, tailX, bottom + 7)
    love.graphics.rectangle("fill", left + 1, top + 1, boxW - 2, boxH - 2, 7, 7)
    love.graphics.setColor(1.0, 0.72, 0.53, alpha)
    love.graphics.print(BODOQUE.name, left + padding, top + 7)
    love.graphics.setColor(1.0, 0.97, 0.93, alpha)
    love.graphics.print(BODOQUE.line, left + padding, top + 10 + lineH)
    love.graphics.pop()
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
    for _, id in ipairs(Encounters.BIOME_ORDER) do
        local biome = Encounters.getBiome(id)
        local col = StageRenderer.BIOME_VISUALS[id].miniCol
        local x0a, y0a = mapPt(biome.uStart, -8.5)
        local x0b, y0b = mapPt(biome.uStart, 8.5)
        local x1b, y1b = mapPt(biome.uEnd, 8.5)
        local x1a, y1a = mapPt(biome.uEnd, -8.5)
        love.graphics.setColor(col[1], col[2], col[3], 0.42)
        love.graphics.polygon("fill", x0a, y0a, x1a, y1a, x1b, y1b, x0b, y0b)
    end

    -- Subtle river accent band on the minimap
    local rx0, ry0 = mapPt(RIVER_START, -8.0)
    local rx1, ry1 = mapPt(RIVER_END, -8.0)
    local rx2, ry2 = mapPt(RIVER_END, 8.0)
    local rx3, ry3 = mapPt(RIVER_START, 8.0)
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

    -- Encounter dots (amber/red active, green defeated)
    local encList = encountersList or _encounterAnchors
    local defMap = defeatedMap or {}
    for i = 1, #encList do
        local enc = encList[i]
        if enc and enc.u and enc.v then
            local ex, ey = mapPt(enc.u, enc.v)
            local isDef = (defMap[enc.id] == true) or (defMap[enc.index or i] == true)
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
-- 11. Dedicated Side-View HD-2D Battle Arena (8 Stages + 12-Band Floor + Props)
--------------------------------------------------------------------------------

local ARENA_PROP_Z = 1.85
local ARENA_FG_Z = 1.75

local BATTLE_FLOOR_TINTS = {
    plaza   = { 0.96, 1.00, 0.92 },
    bosque  = { 0.80, 0.95, 0.80 },
    mirador = { 1.00, 0.90, 0.78 },
    vereda  = { 0.98, 0.92, 0.80 },
    muelle  = { 0.86, 0.90, 0.94 },
    pantano = { 0.56, 0.68, 0.48 },
    esquina = { 0.74, 0.76, 0.84 },
    oficina = { 0.84, 0.86, 0.96 },
    chiloe  = { 0.82, 0.91, 0.96 },
}

local function drawBattleStageCenterDetail(stageKind, pal, horizonY, floorH, sw, sh, tNow, activeLit)
    if activeLit then
        love.graphics.setShader(activeLit)
        safeSend(activeLit, "hasNormalMap", 0.0)
        safeSend(activeLit, "spriteAngle", 0.0)
        safeSend(activeLit, "spriteBillboard", 0.0)
        safeSend(activeLit, "emissiveBoost", 0.0)
        safeSend(activeLit, "specStrength", 0.14)
        safeSend(activeLit, "surfaceBaseY", sh * 0.65)
    end

    if stageKind == "oficina" then
        -- Perspective marble slab seams flanking the royal carpet
        love.graphics.setColor(0.24, 0.26, 0.36, 0.36)
        love.graphics.setLineWidth(1.5)
        for i = 1, 5 do
            local fy = horizonY + floorH * ((i / 6) ^ 1.32)
            love.graphics.line(0, fy, sw, fy)
        end
        love.graphics.setLineWidth(1)

        -- Grand royal crimson velvet carpet trapezoid converging toward horizon
        local topL, topR = sw * 0.25, sw * 0.75
        local botL, botR = sw * 0.10, sw * 0.90
        local topY = horizonY + 8
        love.graphics.setColor(0.68, 0.11, 0.16, 0.96)
        love.graphics.polygon("fill", topL, topY, topR, topY, botR, sh, botL, sh)

        -- Inner velvet sheen strip
        love.graphics.setColor(0.82, 0.18, 0.22, 0.56)
        love.graphics.polygon("fill", sw * 0.31, topY + 2, sw * 0.69, topY + 2, sw * 0.81, sh, sw * 0.19, sh)

        -- Ornate double golden border trim
        love.graphics.setColor(0.96, 0.80, 0.28, 0.94)
        love.graphics.setLineWidth(3.5)
        love.graphics.line(topL + 8, topY, botL + 16, sh)
        love.graphics.line(topR - 8, topY, botR - 16, sh)
        love.graphics.setLineWidth(1.6)
        love.graphics.line(topL + 18, topY, botL + 34, sh)
        love.graphics.line(topR - 18, topY, botR - 34, sh)
        love.graphics.line(topL + 8, topY + 2, topR - 8, topY + 2)

        -- Ceremonial golden bureau seal inlaid in center of carpet
        love.graphics.setColor(0.95, 0.78, 0.26, 0.30)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.65, sw * 0.13, sh * 0.045)
        love.graphics.setColor(0.98, 0.84, 0.34, 0.70)
        love.graphics.setLineWidth(2.0)
        love.graphics.ellipse("line", sw * 0.50, sh * 0.65, sw * 0.125, sh * 0.043)
        love.graphics.setLineWidth(1)

    elseif stageKind == "esquina" then
        -- Perspective urban asphalt avenue
        local roadTopY = horizonY + 14
        love.graphics.setColor(0.24, 0.26, 0.32, 0.94)
        love.graphics.rectangle("fill", 0, roadTopY, sw, sh - roadTopY)

        -- Far & near sidewalk curb bands with crisp yellow warning curb paint
        love.graphics.setColor(0.46, 0.48, 0.54, 0.95)
        love.graphics.rectangle("fill", 0, horizonY, sw, 14)
        love.graphics.setColor(0.94, 0.76, 0.20, 0.92)
        love.graphics.rectangle("fill", 0, roadTopY, sw, 6)
        love.graphics.setColor(0.94, 0.76, 0.20, 0.80)
        love.graphics.rectangle("fill", 0, sh - 22, sw, 8)

        -- Crisp perspective white zebra crosswalk stripes framing the duel lane
        love.graphics.setColor(0.92, 0.94, 0.98, 0.82)
        local stripeCount = 7
        for i = 0, stripeCount - 1 do
            local frac = (i + 0.5) / stripeCount
            local yTop = lerp(sh * 0.52, sh * 0.79, frac - 0.045)
            local yBot = lerp(sh * 0.52, sh * 0.79, frac + 0.045)
            local pT = (yTop - horizonY) / max(1, floorH)
            local pB = (yBot - horizonY) / max(1, floorH)
            local halfTop = lerp(sw * 0.14, sw * 0.24, pT)
            local halfBot = lerp(sw * 0.14, sw * 0.24, pB)
            love.graphics.polygon(
                "fill",
                sw * 0.50 - halfTop, yTop,
                sw * 0.50 + halfTop, yTop,
                sw * 0.50 + halfBot, yBot,
                sw * 0.50 - halfBot, yBot
            )
        end

    elseif stageKind == "muelle" or stageKind == "chiloe" then
        -- Perspective weathered wooden pier decking planks overlooking the Valparaiso bay
        local deckTopY = horizonY + 14
        local deckH = sh - deckTopY
        local plankCount = 11
        for i = 0, plankCount - 1 do
            local t0 = i / plankCount
            local t1 = (i + 1) / plankCount
            local y0 = deckTopY + floor(deckH * (t0 ^ 1.30))
            local y1 = deckTopY + floor(deckH * (t1 ^ 1.30)) + 1
            local shade = (i % 2 == 0) and 1.0 or 0.91
            local depth = lerp(0.84, 1.05, t0)
            if activeLit then
                safeSend(activeLit, "surfaceBaseY", (y0 + y1) * 0.5)
            end
            love.graphics.setColor(0.58 * shade * depth, 0.42 * shade * depth, 0.26 * shade * depth, 0.96)
            love.graphics.rectangle("fill", 0, y0, sw, max(2, y1 - y0))
            -- Plank seam + subtle iron nail dots
            love.graphics.setColor(0.24, 0.15, 0.08, 0.72)
            love.graphics.rectangle("fill", 0, y0, sw, 2)
            love.graphics.setColor(0.20, 0.14, 0.10, 0.48)
            local nailStep = floor(lerp(96, 172, t0))
            for nx = floor(nailStep * 0.5), sw - 20, nailStep do
                love.graphics.rectangle("fill", nx, y0 + 5, 3, 2)
            end
        end

        -- Sturdy wooden pier guardrail posts & sagging nautical rope right along horizon
        if activeLit then
            safeSend(activeLit, "spriteBillboard", 1.0)
            safeSend(activeLit, "surfaceBaseY", deckTopY)
        end
        local postTopY = deckTopY - 26
        -- Top wooden handrail beam
        love.graphics.setColor(0.46, 0.30, 0.17, 1.0)
        love.graphics.rectangle("fill", 0, postTopY + 3, sw, 5)
        love.graphics.setColor(0.68, 0.50, 0.31, 0.85)
        love.graphics.rectangle("fill", 0, postTopY + 2, sw, 2)

        -- Vertical timber posts + sagging rope spans
        local railPosts = 9
        local prevPx = nil
        for i = 0, railPosts do
            local px = floor(lerp(sw * 0.04, sw * 0.96, i / railPosts))
            if prevPx then
                love.graphics.setColor(0.76, 0.64, 0.44, 0.88)
                love.graphics.setLineWidth(2.4)
                local midX = (prevPx + px) * 0.5
                love.graphics.line(prevPx, postTopY + 14, midX, postTopY + 20, px, postTopY + 14)
                love.graphics.setLineWidth(1)
            end
            love.graphics.setColor(0.36, 0.22, 0.12, 1.0)
            love.graphics.rectangle("fill", px - 5, postTopY, 10, 29)
            love.graphics.setColor(0.56, 0.38, 0.22, 0.92)
            love.graphics.rectangle("fill", px - 4, postTopY, 4, 28)
            love.graphics.setColor(0.84, 0.70, 0.42, 1.0)
            love.graphics.rectangle("fill", px - 6, postTopY - 2, 12, 4)
            prevPx = px
        end
        if activeLit then
            safeSend(activeLit, "spriteBillboard", 0.0)
        end

    elseif stageKind == "plaza" then
        -- Decorative sunlit Valdivian cobblestone plaza courtyard oval
        love.graphics.setColor(0.74, 0.70, 0.61, 0.62)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.65, sw * 0.36, sh * 0.135)
        love.graphics.setColor(0.86, 0.82, 0.72, 0.58)
        love.graphics.setLineWidth(4)
        love.graphics.ellipse("line", sw * 0.50, sh * 0.65, sw * 0.355, sh * 0.132)
        love.graphics.setColor(0.62, 0.58, 0.50, 0.46)
        love.graphics.setLineWidth(2)
        love.graphics.ellipse("line", sw * 0.50, sh * 0.65, sw * 0.24, sh * 0.088)
        love.graphics.setLineWidth(1)

    elseif stageKind == "bosque" then
        -- Emerald Valdivian forest clearing with dappled sunlit moss ring
        love.graphics.setColor(0.28, 0.54, 0.26, 0.42)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.65, sw * 0.36, sh * 0.13)
        love.graphics.setColor(0.54, 0.74, 0.34, 0.26)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.64, sw * 0.24, sh * 0.08)

    elseif stageKind == "mirador" then
        -- Low stone lookout parapet along horizon + warm Atacama ochre terrace oval
        love.graphics.setColor(0.64, 0.42, 0.28, 0.86)
        love.graphics.rectangle("fill", 0, horizonY, sw, 10)
        love.graphics.setColor(0.88, 0.68, 0.44, 0.78)
        love.graphics.rectangle("fill", 0, horizonY, sw, 3)
        love.graphics.setColor(0.92, 0.74, 0.46, 0.32)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.65, sw * 0.35, sh * 0.125)
        love.graphics.setColor(0.98, 0.84, 0.52, 0.44)
        love.graphics.setLineWidth(2.2)
        love.graphics.ellipse("line", sw * 0.50, sh * 0.65, sw * 0.34, sh * 0.12)
        love.graphics.setLineWidth(1)

    elseif stageKind == "vereda" then
        -- Sun-baked Atacama cobblestone sidewalk lane with sandstone curb
        love.graphics.setColor(0.78, 0.68, 0.54, 0.54)
        love.graphics.rectangle("fill", 0, sh * 0.53, sw, sh * 0.24)
        love.graphics.setColor(0.92, 0.82, 0.64, 0.68)
        love.graphics.rectangle("fill", 0, sh * 0.53, sw, 5)
        love.graphics.setColor(0.56, 0.42, 0.28, 0.62)
        love.graphics.rectangle("fill", 0, sh * 0.77, sw, 6)

    elseif stageKind == "pantano" then
        -- Bubbling coastal marsh edge + flat stepping-stone causeway across the duel plane
        local bub = 0.5 + 0.5 * sin(tNow * 2.2)
        love.graphics.setColor(0.18, 0.30, 0.22, 0.58)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.66, sw * 0.40, sh * 0.145)
        -- Dry stepping stones across center duel corridor
        love.graphics.setColor(0.52, 0.54, 0.48, 0.78)
        for i = 0, 5 do
            local sx = lerp(sw * 0.22, sw * 0.78, i / 5)
            local sy = sh * 0.65 + sin(i * 1.4) * 6
            love.graphics.ellipse("fill", sx, sy, 46, 15)
        end
        love.graphics.setColor(0.52, 0.76, 0.38, 0.38 * bub)
        love.graphics.ellipse("line", sw * 0.17, sh * 0.58, 16 + bub * 6, 6 + bub * 2)
        love.graphics.ellipse("line", sw * 0.83, sh * 0.59, 14 + bub * 5, 5 + bub * 2)
    else
        love.graphics.setColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 0.18)
        love.graphics.ellipse("fill", sw * 0.50, sh * 0.65, sw * 0.34, sh * 0.125)
    end

    if activeLit then
        love.graphics.setShader()
    end
end

function StageRenderer:drawBattleArena(encounter, stageThemes, propSpritesOrAssets, beatPulse, w, h, time, litShader, enterOffsets)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = time or 0.0
    local pulse = clamp(beatPulse or 0.0, 0.0, 1.5)

    local stageKind = "plaza"
    if type(encounter) == "table" and type(encounter.stage) == "string" then
        stageKind = encounter.stage
    elseif type(encounter) == "string" and encounter ~= "" then
        stageKind = encounter
    end

    local theme = nil
    if type(stageThemes) == "table" then
        if type(stageThemes[stageKind]) == "table" then
            theme = stageThemes[stageKind]
        elseif stageThemes.skyTop or stageThemes.groundA then
            theme = stageThemes
        end
    end

    local tiles = nil
    local propSprites = nil
    if type(propSpritesOrAssets) == "table" then
        if propSpritesOrAssets.tiles or propSpritesOrAssets.props then
            tiles = propSpritesOrAssets.tiles
            propSprites = propSpritesOrAssets.props
        else
            propSprites = propSpritesOrAssets
        end
    end

    local pal = resolveSkyPalette(theme, stageKind)
    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia
    local st = preset.skyTint or { 1.0, 1.0, 1.0 }
    local activeLit = (litShader ~= false) and (litShader or (self.useLitShader and self.shaders and self.shaders.lit)) or nil
    if not self.useLitShader then
        activeLit = nil
    end

    -- LAYER 1: Sky & Biome Parallax Horizon (horizonFrac = 0.36 for deep Pokémon diagonal battle plane)
    local horizonFrac = 0.36
    local horizonY = floor(sh * horizonFrac)
    local floorH = sh - horizonY
    self:drawSkyAndHorizon(theme, sw, sh, tNow, horizonFrac, stageKind, propSpritesOrAssets)

    -- LAYER 2: 12-Band Foreshortened Perspective Pixel-Art Floor (normal-mapped when tile.norm exists!)
    local tileSpec = StageRenderer.THEME_TILES[stageKind] or StageRenderer.THEME_TILES.plaza
    local tilePair = tiles and tiles[tileSpec.floor] or nil
    local floorImg = tilePair and tilePair.diff or nil
    local floorNorm = tilePair and tilePair.norm or nil
    local fTint = BATTLE_FLOOR_TINTS[stageKind] or BATTLE_FLOOR_TINTS.plaza
    local bands = 12

    if floorImg then
        local mesh = self:_ensureFloorBandMesh()
        mesh:setTexture(floorImg)
        if activeLit then
            love.graphics.setShader(activeLit)
            safeSend(activeLit, "spriteBillboard", 0.0)
            safeSend(activeLit, "spriteAngle", 0.0)
            safeSend(activeLit, "emissiveBoost", 0.0)
            safeSend(activeLit, "specStrength", 0.14)
            if floorNorm then
                safeSend(activeLit, "hasNormalMap", 1.0)
                safeSend(activeLit, "normalMap", floorNorm)
                safeSend(activeLit, "normalStrength", 0.95)
            else
                safeSend(activeLit, "hasNormalMap", 0.0)
            end
        end

        for i = 0, bands - 1 do
            local t0 = i / bands
            local t1 = (i + 1) / bands
            local tMid = (t0 + t1) * 0.5
            local y0 = horizonY + floor(floorH * (t0 ^ 1.32))
            local y1 = horizonY + floor(floorH * (t1 ^ 1.32)) + 1
            local pScale = lerp(0.46, 1.42, tMid)
            local uSpan = (sw / 128.0) / pScale
            local uL = 0.5 - uSpan * 0.5
            local uR = 0.5 + uSpan * 0.5
            local v0 = t0 * 4.2
            local v1 = t1 * 4.2

            if activeLit then
                safeSend(activeLit, "surfaceBaseY", (y0 + y1) * 0.5)
            end

            local depthShade = lerp(0.84, 1.04, tMid)
            local cr = fTint[1] * depthShade
            local cg = fTint[2] * depthShade
            local cb = fTint[3] * depthShade
            if not activeLit then
                cr = clamp(cr * st[1], 0, 1)
                cg = clamp(cg * st[2], 0, 1)
                cb = clamp(cb * st[3], 0, 1)
            end
            love.graphics.setColor(cr, cg, cb, 1.0)
            mesh:setVertex(1, 0,  y0, uL, v0, 1, 1, 1, 1)
            mesh:setVertex(2, sw, y0, uR, v0, 1, 1, 1, 1)
            mesh:setVertex(3, sw, y1, uR, v1, 1, 1, 1, 1)
            mesh:setVertex(4, 0,  y1, uL, v1, 1, 1, 1, 1)
            love.graphics.draw(mesh)
        end

        if activeLit then
            love.graphics.setShader()
        end
    else
        -- Defensive fallback if tiles table was omitted
        for i = 0, bands - 1 do
            local t0 = i / bands
            local t1 = (i + 1) / bands
            local y0 = horizonY + floor(floorH * (t0 ^ 1.32))
            local y1 = horizonY + floor(floorH * (t1 ^ 1.32)) + 1
            local r = lerp(pal.groundB[1], pal.groundA[1], t0) * st[1]
            local g = lerp(pal.groundB[2], pal.groundA[2], t0) * st[2]
            local b = lerp(pal.groundB[3], pal.groundA[3], t0) * st[3]
            love.graphics.setColor(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), 1.0)
            love.graphics.rectangle("fill", 0, y0, sw, max(2, y1 - y0))
        end
    end

    -- Gentle atmospheric perspective horizon haze blending distant floor bands into the horizon
    local hazeR = clamp(pal.horizonGlow[1] * st[1], 0.0, 1.0)
    local hazeG = clamp(pal.horizonGlow[2] * st[2], 0.0, 1.0)
    local hazeB = clamp(pal.horizonGlow[3] * st[3], 0.0, 1.0)
    if preset.id == "atardecer" then
        hazeR, hazeG, hazeB = 1.00, 0.62, 0.34
    elseif preset.id == "noche" then
        hazeR, hazeG, hazeB = 0.22, 0.32, 0.58
    end
    for i = 0, 5 do
        local t0 = i / bands
        local t1 = (i + 1) / bands
        local tMid = (t0 + t1) * 0.5
        local y0 = horizonY + floor(floorH * (t0 ^ 1.32))
        local y1 = horizonY + floor(floorH * (t1 ^ 1.32)) + 1
        local hazeA = ((1.0 - tMid) ^ 2.2) * 0.34
        love.graphics.setColor(hazeR, hazeG, hazeB, hazeA)
        love.graphics.rectangle("fill", 0, y0, sw, max(2, y1 - y0))
    end

    -- LAYER 3: Stage-Specific Center Arena Detail
    drawBattleStageCenterDetail(stageKind, pal, horizonY, floorH, sw, sh, tNow, activeLit)

    -- LAYER 4: Curated Background & Flank Props (sorted by yFrac, keeping center 100% clear)
    local decorList = StageRenderer.BATTLE_STAGE_DECOR[stageKind] or StageRenderer.BATTLE_STAGE_DECOR.plaza
    for i = 1, #decorList do
        local prop = decorList[i]
        if prop.layer ~= "fg" then
            local px = prop.xFrac * sw
            local py = prop.yFrac * sh
            drawStylizedProp(self, prop, px, py, ARENA_PROP_Z, tNow, propSpritesOrAssets or propSprites, activeLit, 1.0)
        end
    end

    -- LAYER 5: Pokémon-Style Sliding Diagonal Battle Pads & Beat-Pulsing Stance Rings
    local anchors = StageRenderer.getBattleAnchors(sw, sh)
    local ringPulse = pulse
    if beatPulse == nil then
        ringPulse = 0.5 + 0.5 * sin(tNow * 4.2)
    end

    local pOffX = (enterOffsets and enterOffsets.puduOffX) or 0.0
    local pOffY = (enterOffsets and enterOffsets.puduOffY) or 0.0
    local eOffX = (enterOffsets and enterOffsets.enemyOffX) or 0.0
    local eOffY = (enterOffsets and enterOffsets.enemyOffY) or 0.0
    local enterT = (enterOffsets and enterOffsets.enterT) or 1.0

    -- Subtle Pokémon-style dynamic diagonal speed streaks while platforms slide into place
    if enterT < 0.96 then
        local streakA = clamp((1.0 - enterT) * 0.38, 0.0, 0.34)
        love.graphics.setColor(1.0, 0.98, 0.90, streakA)
        for sIdx = 1, 7 do
            local sy = sh * (0.14 + sIdx * 0.105)
            local sx = ((sIdx * 210 + tNow * 1400) % (sw + 320)) - 160
            local len = 140 + (sIdx % 3) * 75
            love.graphics.rectangle("fill", sx, sy, len, 2.5)
        end
    end

    -- Biome-harmonized battle pad colors (lit softly by preset skyTint)
    local padFillR = clamp(lerp(pal.groundA[1], 0.90, 0.32) * lerp(1.0, st[1], 0.65), 0.10, 0.96)
    local padFillG = clamp(lerp(pal.groundA[2], 0.92, 0.32) * lerp(1.0, st[2], 0.65), 0.12, 0.96)
    local padFillB = clamp(lerp(pal.groundA[3], 0.84, 0.28) * lerp(1.0, st[3], 0.65), 0.12, 0.96)
    local padRimR = clamp(padFillR * 0.72, 0.06, 0.90)
    local padRimG = clamp(padFillG * 0.72, 0.06, 0.90)
    local padRimB = clamp(padFillB * 0.74, 0.08, 0.90)

    -- Upper-Right Rival Battle Platform (with generous top/right padding)
    local exPad = anchors.enemyX + eOffX
    local eyPad = anchors.enemyY + eOffY + 6
    love.graphics.setColor(0.03, 0.04, 0.09, 0.32)
    love.graphics.ellipse("fill", exPad, eyPad + 7, 124, 34)
    love.graphics.setColor(padRimR, padRimG, padRimB, 0.94)
    love.graphics.ellipse("fill", exPad, eyPad + 3, 120, 32)
    love.graphics.setColor(padFillR, padFillG, padFillB, 0.96)
    love.graphics.ellipse("fill", exPad, eyPad - 1, 114, 29)
    love.graphics.setColor(1.0, 0.98, 0.90, 0.24)
    love.graphics.setLineWidth(2.0)
    love.graphics.ellipse("line", exPad, eyPad - 1, 112, 28)

    -- Rival crimson-gold stance ring on upper-right pad
    love.graphics.setColor(0.98, 0.30, 0.26, 0.18 + 0.12 * ringPulse)
    love.graphics.ellipse("fill", exPad, eyPad - 1, 74 + ringPulse * 7, 21 + ringPulse * 2.2)
    love.graphics.setLineWidth(2.2)
    love.graphics.setColor(1.00, 0.38, 0.30, 0.76 + 0.18 * ringPulse)
    love.graphics.ellipse("line", exPad, eyPad - 1, 68 + ringPulse * 6, 19 + ringPulse * 2.0)
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(1.00, 0.82, 0.34, 0.72 + 0.20 * ringPulse)
    love.graphics.ellipse("line", exPad, eyPad - 1, 50 + ringPulse * 4.5, 14 + ringPulse * 1.6)

    -- Bottom-Left Foreground Pudú Battle Platform (partially tucked behind bottom strip!)
    local pxPad = anchors.puduX + pOffX
    local pyPad = anchors.puduY + pOffY - 14
    love.graphics.setColor(0.03, 0.04, 0.09, 0.34)
    love.graphics.ellipse("fill", pxPad, pyPad + 8, 174, 48)
    love.graphics.setColor(padRimR, padRimG, padRimB, 0.94)
    love.graphics.ellipse("fill", pxPad, pyPad + 3, 168, 45)
    love.graphics.setColor(padFillR, padFillG, padFillB, 0.96)
    love.graphics.ellipse("fill", pxPad, pyPad - 2, 160, 41)
    love.graphics.setColor(1.0, 0.98, 0.90, 0.26)
    love.graphics.setLineWidth(2.2)
    love.graphics.ellipse("line", pxPad, pyPad - 2, 158, 40)

    -- Pudú cyan-gold stance ring on foreground bottom-left pad
    love.graphics.setColor(0.20, 0.84, 0.98, 0.18 + 0.12 * ringPulse)
    love.graphics.ellipse("fill", pxPad, pyPad - 2, 108 + ringPulse * 10, 29 + ringPulse * 3.0)
    love.graphics.setLineWidth(2.4)
    love.graphics.setColor(0.36, 0.94, 1.00, 0.78 + 0.18 * ringPulse)
    love.graphics.ellipse("line", pxPad, pyPad - 2, 100 + ringPulse * 9, 27 + ringPulse * 2.8)
    love.graphics.setLineWidth(1.6)
    love.graphics.setColor(1.00, 0.88, 0.38, 0.72 + 0.20 * ringPulse)
    love.graphics.ellipse("line", pxPad, pyPad - 2, 74 + ringPulse * 6.5, 20 + ringPulse * 2.0)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
    return anchors
end

function StageRenderer:drawBattleArenaForeground(encounter, propSpritesOrAssets, w, h, timeOrShader, litShaderOpt)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = 0.0
    local litShader = litShaderOpt
    if type(timeOrShader) == "number" then
        tNow = timeOrShader
    elseif timeOrShader ~= nil and litShader == nil then
        litShader = timeOrShader
    end

    local stageKind = "plaza"
    if type(encounter) == "table" and type(encounter.stage) == "string" then
        stageKind = encounter.stage
    elseif type(encounter) == "string" and encounter ~= "" then
        stageKind = encounter
    end

    local activeLit = (litShader ~= false) and (litShader or (self.useLitShader and self.shaders and self.shaders.lit)) or nil
    if not self.useLitShader then
        activeLit = nil
    end

    local decorList = StageRenderer.BATTLE_STAGE_DECOR[stageKind] or StageRenderer.BATTLE_STAGE_DECOR.plaza
    for i = 1, #decorList do
        local prop = decorList[i]
        if prop.layer == "fg" then
            local px = prop.xFrac * sw
            local py = prop.yFrac * sh
            drawStylizedProp(self, prop, px, py, ARENA_FG_Z, tNow, propSpritesOrAssets, activeLit, 0.92)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- 12. Dynamic Point Lights, Atmospheric Halos/Sunbeams & Post-Processing
--------------------------------------------------------------------------------

function StageRenderer:_resetLightCollection()
    self._lightsCount = 0
end

function StageRenderer:_pushLight(x, y, radius, r, g, b, energy, haloScale, height)
    if self._lightsCount >= 10 then
        return
    end
    self._lightsCount = self._lightsCount + 1
    local entry = self._lightsPool[self._lightsCount]
    entry.x = x
    entry.y = y
    entry.radius = radius
    entry.height = height or 68.0
    entry.r = r
    entry.g = g
    entry.b = b
    entry.energy = energy
    entry.haloScale = haloScale or 0.78
    self._lightsList[self._lightsCount] = entry
end

function StageRenderer:_finalizeLightCollection()
    local list = self._lightsList
    for i = self._lightsCount + 1, 10 do
        list[i] = nil
    end
    return list
end

function StageRenderer:collectBattleLights(encounter, w, h, time)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = time or 0.0
    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia
    local boost = preset.lanternBoost or 0.6

    local stageKind = "plaza"
    if type(encounter) == "table" and type(encounter.stage) == "string" then
        stageKind = encounter.stage
    elseif type(encounter) == "string" and encounter ~= "" then
        stageKind = encounter
    end

    self:_resetLightCollection()

    -- Priority 1: Character key/fill pools in noche & dramatico (Pokémon diagonal anchors; haloScale = 0)
    if self.lightingPreset == "noche" then
        self:_pushLight(sw * 0.27, sh * 0.76, 320, 1.00, 0.86, 0.64, 0.50, 0.0, 118)
        self:_pushLight(sw * 0.72, sh * 0.44, 285, 0.96, 0.84, 0.70, 0.48, 0.0, 104)
    elseif self.lightingPreset == "dramatico" then
        self:_pushLight(sw * 0.27, sh * 0.74, 315, 1.00, 0.90, 0.66, 0.52, 0.0, 144)
        self:_pushLight(sw * 0.72, sh * 0.44, 285, 1.00, 0.86, 0.66, 0.50, 0.0, 132)
    end

    -- Priority 2: Emissive props in the active stage arena (exact match to ARENA_PROP_Z anchor!)
    local decorList = StageRenderer.BATTLE_STAGE_DECOR[stageKind] or StageRenderer.BATTLE_STAGE_DECOR.plaza
    for i = 1, #decorList do
        local prop = decorList[i]
        if prop.layer ~= "fg" then
            local px = prop.xFrac * sw
            local py = prop.yFrac * sh
            local s = (prop.scale or 1.0) * ARENA_PROP_Z
            local k = prop.kind

            if k == "lantern_post" then
                local flicker = 0.90 + 0.10 * sin(tNow * 4.2 + i * 1.9)
                self:_pushLight(
                    px + 10 * s, py - 48 * s,
                    195 * (prop.scale or 1.0),
                    1.00, 0.74, 0.30,
                    0.92 * boost * flicker,
                    0.82 * (prop.scale or 1.0),
                    72
                )
            elseif k == "mountain_crystal" then
                local pulse = 0.88 + 0.12 * sin(tNow * 3.1 + i * 1.7)
                self:_pushLight(
                    px, py - 24 * s,
                    170 * (prop.scale or 1.0),
                    0.34, 0.88, 1.00,
                    0.78 * max(0.55, boost) * pulse,
                    0.72 * (prop.scale or 1.0),
                    56
                )
            elseif k == "orb_shrine" or k == "quena_monolith" or k == "stone_pedestal" then
                local pulse = 0.90 + 0.10 * sin(tNow * 2.8 + i * 1.4)
                self:_pushLight(
                    px, py - 46 * s,
                    180 * (prop.scale or 1.0),
                    1.00, 0.82, 0.36,
                    0.80 * max(0.45, boost) * pulse,
                    0.74 * (prop.scale or 1.0),
                    68
                )
            elseif k == "pincoya_shrine" then
                local pulse = 0.88 + 0.12 * sin(tNow * 2.9 + i * 1.3)
                self:_pushLight(
                    px, py - 46 * s,
                    175 * (prop.scale or 1.0),
                    0.30, 0.94, 0.92,
                    0.80 * max(0.50, boost) * pulse,
                    0.74 * (prop.scale or 1.0),
                    68
                )
            elseif k == "coast_lighthouse" then
                local pulse = 0.92 + 0.08 * sin(tNow * 1.8)
                self:_pushLight(
                    px, py - 114 * s,
                    245 * (prop.scale or 1.0),
                    1.00, 0.92, 0.56,
                    1.05 * max(0.55, boost) * pulse,
                    0.94 * (prop.scale or 1.0),
                    120
                )
            elseif k == "biome_arch" then
                local st = prop.extra or "stone"
                local lr, lg, lb = 0.34, 0.82, 0.46
                if st == "sandstone" then
                    lr, lg, lb = 0.98, 0.72, 0.28
                elseif st == "harbor" then
                    lr, lg, lb = 0.30, 0.84, 0.96
                end
                self:_pushLight(
                    px, py - 78 * s,
                    155 * (prop.scale or 1.0),
                    lr, lg, lb,
                    0.68 * max(0.45, boost),
                    0.66 * (prop.scale or 1.0),
                    82
                )
            end
        end
    end

    -- Priority 3: Coastal Caleuche spectral stern lantern on horizon in muelle stage
    if stageKind == "muelle" then
        local shipX = sw * 0.40 + sin(tNow * 0.28) * 20.0
        local shipY = floor(sh * 0.36) - 18
        self:_pushLight(shipX - 22, shipY, 135, 0.40, 0.96, 0.88, 0.52 * max(0.45, boost), 0.52, 48)
    end

    return self:_finalizeLightCollection()
end

function StageRenderer:collectZoneLights(w, h, time)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = time or 0.0
    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia
    local boost = preset.lanternBoost
    if self.lightingPreset == "dia" then
        boost = lerp(boost, 1.0, smoothstep(88.0, 98.0, self.camU))
    end
    local z = self.camZoom or 0.72
    local camU = self.camU
    local camV = self.camV

    self:_resetLightCollection()

    -- Gentle readability lantern around Pudu/camera center in noche or dramatico overworld (litShader only)
    if self.lightingPreset == "noche" then
        self:_pushLight(sw * 0.50, sh * 0.52, 290, 1.00, 0.86, 0.64, 0.48, 0.0, 96)
    elseif self.lightingPreset == "dramatico" then
        self:_pushLight(sw * 0.50, sh * 0.50, 310, 1.00, 0.90, 0.68, 0.52, 0.0, 114)
    end

    local decor = self.overworldDecor or {}
    for i = 1, #decor do
        if self._lightsCount >= 10 then
            break
        end
        local prop = decor[i]
        local k = prop.kind
        if (k == "lantern_post" or k == "mountain_crystal" or k == "orb_shrine"
            or k == "pincoya_shrine" or k == "quena_monolith" or k == "coast_lighthouse"
            or k == "biome_arch" or k == "caleuche_ship")
            and abs(prop.u - camU) <= 17.0 and abs(prop.v - camV) <= 17.0 then

            local elev = StageRenderer.getElevation(prop.u, prop.v)
            local sx, sy = self:isoToScreen(prop.u, prop.v, elev, sw, sh)
            if sx >= -140 and sx <= sw + 140 and sy >= -140 and sy <= sh + 140 then
                local h = sceneryHeight(prop) * z
                if k == "lantern_post" then
                    local flicker = 0.94 + 0.06 * sin(tNow * 4.0 + prop.u)
                    self:_pushLight(sx + h * 0.21, sy - h * 0.58, 250 * z, 1.00, 0.73, 0.34,
                        0.96 * boost * flicker, 0.66, 62)
                elseif k == "mountain_crystal" then
                    local pulse = 0.86 + 0.14 * sin(tNow * 3.0 + prop.u)
                    self:_pushLight(sx, sy - h * 0.60, 180 * z, 0.34, 0.88, 1.00, 0.52 * max(0.50, boost) * pulse, 0.58, 48)
                elseif k == "pincoya_shrine" then
                    self:_pushLight(sx - h * 0.08, sy - h * 0.44, 200 * z, 1.00, 0.72, 0.39, 0.56 * max(0.50, boost), 0.68, 60)
                elseif k == "orb_shrine" or k == "quena_monolith" then
                    self:_pushLight(sx, sy - h * 0.79, 200 * z, 0.45, 0.94, 0.87, 0.80 * max(0.45, boost), 0.70, 60)
                elseif k == "coast_lighthouse" then
                    self:_pushLight(sx, sy - h * 0.77, 255 * z, 1.00, 0.84, 0.42, 1.00 * max(0.55, boost), 0.72, 110)
                elseif k == "caleuche_ship" then
                    self:_pushLight(sx - h * 0.31, sy - h * 0.18, 145 * z, 0.42, 0.98, 0.88, 0.65 * max(0.45, boost), 0.65, 52)
                elseif k == "biome_arch" then
                    local st = prop.extra or "stone"
                    local lr, lg, lb = 0.34, 0.80, 0.44
                    if st == "sandstone" then
                        lr, lg, lb = 0.98, 0.72, 0.28
                    elseif st == "harbor" then
                        lr, lg, lb = 0.30, 0.84, 0.96
                    end
                    self:_pushLight(sx, sy - h * 0.71, 155 * z, lr, lg, lb, 0.48 * max(0.45, boost), 0.66, 72)
                end
            end
        end
    end

    return self:_finalizeLightCollection()
end

function StageRenderer:drawAtmosphericLighting(lightRadialImg, lights, w, h, time, worldBiome)
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local tNow = time or 0.0
    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia

    -- 1. Soft additive radial halos for lanterns, crystals & shrines (calibrated to avoid white blowout!)
    if type(lights) == "table" and #lights > 0 then
        love.graphics.setShader()
        love.graphics.setBlendMode("add")
        local haloGain = clamp(0.16 + (preset.lanternBoost or 0.5) * 0.20, 0.12, 0.44)
        local lw, lh = 1, 1
        if lightRadialImg then
            lw, lh = lightRadialImg:getDimensions()
        end

        for i = 1, #lights do
            local L = lights[i]
            local scaleF = (type(L) == "table" and L.haloScale ~= nil) and L.haloScale or 0.75
            if type(L) == "table" and (L.energy or 0.0) > 0.01 and scaleF > 0.01 then
                local alpha = clamp((L.energy or 0.8) * haloGain * 0.62, 0.04, 0.38)
                local rad = (L.radius or 160.0) * 0.76 * scaleF
                local lr = L.r or (L.color and L.color[1]) or 1.0
                local lg = L.g or (L.color and L.color[2]) or 0.80
                local lb = L.b or (L.color and L.color[3]) or 0.40

                if lightRadialImg then
                    local sc = (rad * 2.0) / max(1, lw)
                    love.graphics.setColor(lr, lg, lb, alpha)
                    love.graphics.draw(lightRadialImg, L.x, L.y, 0, sc, sc, lw * 0.5, lh * 0.5)
                else
                    love.graphics.setColor(lr, lg, lb, alpha * 0.46)
                    love.graphics.circle("fill", L.x, L.y, rad * 0.72)
                    love.graphics.setColor(lr, lg, lb, alpha * 0.32)
                    love.graphics.circle("fill", L.x, L.y, rad * 0.38)
                end
            end
        end
    end

    -- 2. Diagonal volumetric sunbeams via shaders.sunbeam (strictly OFF in noche where beamStrength == 0)
    local beamStrength = preset.beamStrength or 0.0
    if worldBiome == "bosque" then
        beamStrength = beamStrength * 1.44
    elseif worldBiome == "chiloe" then
        beamStrength = beamStrength * 0.47
    end
    local beamShader = self.shaders and self.shaders.sunbeam
    if beamShader and beamStrength > 0.001 then
        local white = self:_getUnitWhite()
        local sizeBuf = self._screenSizeBuf
        sizeBuf[1], sizeBuf[2] = sw, sh

        love.graphics.setBlendMode("add")
        love.graphics.setShader(beamShader)
        safeSend(beamShader, "time", tNow)
        safeSend(beamShader, "beamAngle", -0.44)
        safeSend(beamShader, "beamColor", preset.beamColor or { 1.0, 0.94, 0.78 })
        safeSend(beamShader, "beamStrength", beamStrength)
        safeSend(beamShader, "screenSize", sizeBuf)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(white, 0, 0, 0, sw * 0.5, sh * 0.5)
        love.graphics.setShader()
    end

    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

function StageRenderer:drawPostProcessed(worldCanvas, w, h)
    if not worldCanvas then
        return
    end
    local sw = w or love.graphics.getWidth()
    local sh = h or love.graphics.getHeight()
    local cw, ch = worldCanvas:getDimensions()
    local sx = sw / max(1, cw)
    local sy = sh / max(1, ch)

    local postShader = self.shaders and self.shaders.post
    local preset = StageRenderer.LIGHTING_PRESETS[self.lightingPreset] or StageRenderer.LIGHTING_PRESETS.dia

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)

    if postShader then
        local texelBuf = self._texelSizeBuf
        texelBuf[1] = 1.0 / max(1, cw)
        texelBuf[2] = 1.0 / max(1, ch)

        love.graphics.setShader(postShader)
        safeSend(postShader, "dofEnabled", preset.dofEnabled or 0.0)
        safeSend(postShader, "focusY", 0.62)
        safeSend(postShader, "texelSize", texelBuf)
        safeSend(postShader, "bloomStrength", self.disableBloom and 0.0 or (preset.bloomStrength or 0.16))
        safeSend(postShader, "vignetteStrength", preset.vignette or 0.18)
        love.graphics.draw(worldCanvas, 0, 0, 0, sx, sy)
        love.graphics.setShader()
    else
        love.graphics.draw(worldCanvas, 0, 0, 0, sx, sy)
    end
end

--------------------------------------------------------------------------------
-- 13. Preserved Fase 01 Battle Placeholder Stage (Backward Compatibility Alias)
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
    elseif stageKind == "muelle" or stageKind == "chiloe" then
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
        drawPuduWithHat(self, anchors.puduX, anchors.puduY, 2, animCol, 124.0, puduBob, assets)

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
