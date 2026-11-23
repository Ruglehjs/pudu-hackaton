-- main.lua — Fase 02: Arena HD-2D Vista Lateral, Iluminación, Dash-in, Sombrero de Mago y Baile Idle al Compás (LÖVE2D 11.5)

local json = require("json")
local AssetLoader = require("asset_loader")
local Audio = require("audio")
local Encounters = require("encounters")
local StageRenderer = require("stage_renderer")
local Shaders = require("shaders")
local BeatSync = require("beat_sync")

--------------------------------------------------------------------------------
-- Custom Error Handler (prints traceback to stderr; exits 1 under --quit-after)
--------------------------------------------------------------------------------

local function hasQuitAfterArg()
    if type(arg) ~= "table" then
        return false
    end
    for _, a in ipairs(arg) do
        if type(a) == "string" and a:match("^%-%-quit%-after=") then
            return true
        end
    end
    return false
end

function love.errorhandler(msg)
    msg = tostring(msg)
    local trace = debug.traceback("Error: " .. msg, 2):gsub("\n[^\n]+$", "")
    local full = "[PUDU FANTASY ERROR]\n" .. trace .. "\n"
    io.stderr:write(full)
    io.stderr:flush()

    if hasQuitAfterArg() then
        os.exit(1)
    end

    if not love.window or not love.graphics or not love.event then
        return
    end
    if not love.graphics.isCreated() or not love.window.isOpen() then
        local ok = pcall(love.window.setMode, 960, 540)
        if not ok then
            return
        end
    end

    love.graphics.reset()
    local font = love.graphics.setNewFont(15)
    love.graphics.setColor(1, 1, 1, 1)

    return function()
        love.event.pump()
        for e, a in love.event.poll() do
            if e == "quit" or (e == "keypressed" and a == "escape") then
                return 1
            end
        end
        love.graphics.clear(0.11, 0.14, 0.24, 1)
        love.graphics.setFont(font)
        love.graphics.printf(full .. "\nPresiona ESC para cerrar.", 40, 40, love.graphics.getWidth() - 80)
        love.graphics.present()
        if love.timer then
            love.timer.sleep(0.05)
        end
    end
end

--------------------------------------------------------------------------------
-- Math & CLI Parser (every literal hyphen escaped as %-%- per Rule R5)
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function smoothstep01(t)
    local x = clamp(t or 0.0, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)
end

local function parseCliArgs(argList)
    local cli = {
        mode = "explore",
        biome = nil,
        encounter = 1,
        encounterExplicit = false,
        lighting = "dia",
        mock = false,
        screenshot = nil,
        quitAfter = nil,
        printPerf = false,
        autoPrompt = nil,
        testRitual = false,
        demoCombo = nil,
        forceReaction = nil,
        transitionPreview = nil,
        battleEnterPreview = false,
        openDirector = false,
        openAlbum = false,
        disableGi = false,
        disableBloom = false,
    }

    if type(argList) ~= "table" then
        return cli
    end

    for _, a in ipairs(argList) do
        if type(a) == "string" then
            local v
            v = a:match("^%-%-mode=(.+)$")
            if v == "explore" or v == "battle" then cli.mode = v end

            v = a:match("^%-%-biome=(.+)$")
            if v and v ~= "" then cli.biome = v end

            v = a:match("^%-%-encounter=(%d+)$")
            if v then
                local n = tonumber(v)
                if n then
                    cli.encounter = clamp(math.floor(n), 1, Encounters.count())
                    cli.encounterExplicit = true
                end
            end

            v = a:match("^%-%-lighting=(.+)$")
            if v and v ~= "" then cli.lighting = v end

            if a:match("^%-%-mock$") then cli.mock = true end

            v = a:match("^%-%-screenshot=(.+)$")
            if v and v ~= "" then cli.screenshot = v end

            v = a:match("^%-%-quit%-after=(%d+%.?%d*)$")
            if v then cli.quitAfter = tonumber(v) end

            if a:match("^%-%-print%-perf$") then cli.printPerf = true end

            v = a:match("^%-%-auto%-prompt=(.+)$")
            if v then cli.autoPrompt = v end

            if a:match("^%-%-test%-ritual$") then cli.testRitual = true end

            v = a:match("^%-%-demo%-combo=(.+)$")
            if v then cli.demoCombo = v end

            v = a:match("^%-%-force%-reaction=(.+)$")
            if v and v ~= "" then cli.forceReaction = v end

            v = a:match("^%-%-transition%-preview=(%d+%.?%d*)$")
            if v then cli.transitionPreview = clamp(tonumber(v) or 0.0, 0.0, 1.0) end

            if a:match("^%-%-battle%-enter%-preview$") then cli.battleEnterPreview = true end
            if a:match("^%-%-open%-director$") then cli.openDirector = true end
            if a:match("^%-%-open%-album$") then cli.openAlbum = true end
            if a:match("^%-%-disable%-gi$") then cli.disableGi = true end
            if a:match("^%-%-disable%-bloom$") then cli.disableBloom = true end
        end
    end

    return cli
end

--------------------------------------------------------------------------------
-- Constants & Game State
--------------------------------------------------------------------------------

local ALERT_DURATION = 0.40
local TO_BATTLE_DURATION = 1.05
local TO_EXPLORE_DURATION = 0.72
local BATTLE_ENTER_DURATION = 0.88
local BATTLE_ENTER_SLIDE_PX = 320.0
local ENCOUNTER_TRIGGER_DIST = 1.75
local WALK_SPEED = 6.2

-- Wizard hat head-anchor offsets per Pudú facing row (0..7) in 64px base units
-- Rows: 0=S, 1=SE, 2=E, 3=NE, 4=N, 5=NW, 6=W, 7=SW
local HAT_HEAD_OFFSETS = {
    [0] = { x = 0.0,  y = -40.0 },
    [1] = { x = 5.0,  y = -40.0 },
    [2] = { x = 8.5,  y = -41.0 },
    [3] = { x = 5.0,  y = -41.0 },
    [4] = { x = 0.0,  y = -41.0 },
    [5] = { x = -5.0, y = -41.0 },
    [6] = { x = -8.5, y = -41.0 },
    [7] = { x = -5.0, y = -40.0 },
}

local Game = {
    cli = nil,
    mode = "explore",
    encounterIndex = 1,
    assets = nil,
    audio = nil,
    stage = nil,
    shaders = nil,
    beatSync = nil,
    worldCanvas = nil,
    worldCanvasW = 0,
    worldCanvasH = 0,
    fonts = {},
    defeatedMap = {},

    -- Hero Overworld State
    puduU = 3.8,
    puduV = 0.0,
    puduFacingRow = 3, -- 3 = NE (diagonal up-right)
    puduWalkT = 0.0,
    puduAnimCol = 1,
    puduBobY = 0.0,
    puduMoving = false,

    -- Battle Arena & Dash-in State
    battlePhase = "player_turn", -- "battle_enter" | "player_turn"
    battleEnterT = 1.0,
    puduAnimMode = "battle_idle",
    enemyReaction = "idle",

    -- JRPG Encounter Transition State ("none" | "alert" | "to_battle" | "to_explore")
    transitionState = "none",
    transitionTimer = 0.0,
    transitionSwitched = false,
    transitionPreview = nil,
    alertEncounterIdx = nil,
    encounterCooldown = 0.0,

    -- Runtime & Telemetry
    elapsed = 0.0,
    cliElapsed = 0.0,
    cliScreenshotDone = false,
    framesDrawn = 0,
    lastDrawCalls = 0,
    reloadCount = 0,
    toastText = nil,
    toastTimer = 0.0,
}

--------------------------------------------------------------------------------
-- Canvas, Font, Screenshot & Asset Helpers
--------------------------------------------------------------------------------

local function ensureWorldCanvas(w, h)
    local cw = math.max(1, math.floor(w or love.graphics.getWidth()))
    local ch = math.max(1, math.floor(h or love.graphics.getHeight()))
    if Game.worldCanvas and Game.worldCanvasW == cw and Game.worldCanvasH == ch then
        return Game.worldCanvas
    end
    if Game.worldCanvas then
        pcall(Game.worldCanvas.release, Game.worldCanvas)
        Game.worldCanvas = nil
    end
    local ok, canvas = pcall(love.graphics.newCanvas, cw, ch)
    if ok and canvas then
        canvas:setFilter("linear", "linear")
        Game.worldCanvas = canvas
        Game.worldCanvasW = cw
        Game.worldCanvasH = ch
    end
    return Game.worldCanvas
end

local function loadFonts()
    local fontPath = "assets/fonts/PTSans.ttc"
    local hasFont = love.filesystem.getInfo(fontPath) ~= nil
    local function mk(size)
        if hasFont then
            local ok, f = pcall(love.graphics.newFont, fontPath, size)
            if ok and f then return f end
        end
        return love.graphics.newFont(size)
    end
    return {
        title = mk(20),
        heading = mk(16),
        body = mk(14),
        small = mk(12),
        hasPackagedFont = hasFont,
    }
end

local function showToast(msg, duration)
    Game.toastText = msg
    Game.toastTimer = duration or 2.2
end

local function ensureParentDir(fullPath)
    local parent = fullPath:match("^(.+)/[^/]+$")
    if not parent or parent == "" then
        return
    end
    local f = io.open(parent .. "/.pudu_dir_probe", "wb")
    if f then
        f:close()
        os.remove(parent .. "/.pudu_dir_probe")
        return
    end
    local escaped = parent:gsub("'", "'\\''")
    os.execute("mkdir -p '" .. escaped .. "'")
end

local function resolveOutputPath(path)
    if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then
        return path
    end
    local base = AssetLoader.getExternalBaseDir()
    if base and base ~= "" and base ~= "." then
        return base .. "/" .. path
    end
    return path
end

local function saveScreenshotTo(path)
    if type(path) ~= "string" or path == "" then
        return false
    end
    local fullPath = resolveOutputPath(path)
    ensureParentDir(fullPath)
    love.graphics.captureScreenshot(function(imageData)
        local okEnc, pngData = pcall(imageData.encode, imageData, "png")
        if not okEnc or not pngData then
            io.stderr:write("[PUDU FANTASY WARN] Fallo al codificar captura PNG\n")
            io.stderr:flush()
            return
        end
        local f, err = io.open(fullPath, "wb")
        if not f then
            io.stderr:write("[PUDU FANTASY WARN] No se pudo escribir captura: " .. tostring(err) .. "\n")
            io.stderr:flush()
            return
        end
        f:write(pngData:getString())
        f:close()
    end)
    return true
end

local function syncMusicForMode()
    if not Game.audio then return end
    if Game.mode == "battle" then
        Game.audio:playTrack("user_battle", false)
        if Game.beatSync then
            local ts = Game.audio:getTrackState()
            Game.beatSync:reset((ts and ts.bpm) or 139.20)
        end
    else
        Game.audio:playTrack("overworld", false)
        if Game.beatSync then
            local ts = Game.audio:getTrackState()
            Game.beatSync:reset((ts and ts.bpm) or 116.04)
        end
    end
end

local function reloadAssets(isHotReload)
    local overrides = Encounters.loadOverrides(AssetLoader.getExternalBaseDir())
    if overrides then
        Encounters.applyOverrides(overrides)
    end
    Game.assets = AssetLoader.loadAll(Encounters.LIST)
    if isHotReload then
        Game.reloadCount = Game.reloadCount + 1
        local s = Game.assets.stats
        showToast(string.format("Hot-Reload #%d listo (%d reales / %d greybox)", Game.reloadCount, s.realCount, s.placeholderCount), 2.4)
    end
end

--------------------------------------------------------------------------------
-- Overworld Navigation & Battle Entry Helpers
--------------------------------------------------------------------------------

-- Map screen-space input direction (dx, dy) to the 8 Pudu facing rows:
-- 0=S, 1=SE, 2=E, 3=NE, 4=N, 5=NW, 6=W, 7=SW
local function screenDirToFacingRow(dx, dy)
    if dx == 0 and dy > 0 then return 0 end
    if dx > 0 and dy > 0 then return 1 end
    if dx > 0 and dy == 0 then return 2 end
    if dx > 0 and dy < 0 then return 3 end
    if dx == 0 and dy < 0 then return 4 end
    if dx < 0 and dy < 0 then return 5 end
    if dx < 0 and dy == 0 then return 6 end
    if dx < 0 and dy > 0 then return 7 end
    return Game.puduFacingRow
end

local function findSafeSpotNearEncounter(enc, offsetU)
    local targetU = clamp(enc.u + (offsetU or -2.6), 1.5, StageRenderer.WORLD_U_MAX - 2.0)
    local candidates = {
        { targetU, enc.v },
        { targetU, StageRenderer.pathCenterV(targetU) },
        { enc.u - 2.4, StageRenderer.pathCenterV(enc.u - 2.4) },
        { enc.u + 2.6, StageRenderer.pathCenterV(enc.u + 2.6) },
        { enc.u, StageRenderer.pathCenterV(enc.u) },
    }
    for _, c in ipairs(candidates) do
        if StageRenderer.isWalkable(c[1], c[2]) then
            return c[1], c[2]
        end
    end
    return clamp(enc.u - 2.6, 2.0, 114.0), StageRenderer.pathCenterV(clamp(enc.u - 2.6, 2.0, 114.0))
end

local function findNearestEncounterIndex(preferUndefeated)
    local bestIdx = 1
    local bestDist = math.huge
    for i = 1, Encounters.count() do
        local enc = Encounters.LIST[i]
        local isDef = Game.defeatedMap[enc.id] == true
        if (not preferUndefeated) or (not isDef) then
            local du = enc.u - Game.puduU
            local dv = enc.v - Game.puduV
            local d = math.sqrt(du * du + dv * dv)
            if d < bestDist then
                bestDist = d
                bestIdx = i
            end
        end
    end
    if preferUndefeated and bestDist == math.huge then
        return findNearestEncounterIndex(false)
    end
    return bestIdx
end

local function enterBattleArenaImmediate(idx, skipEnterDash, initialEnterT)
    local targetIdx = clamp(math.floor(tonumber(idx) or Game.encounterIndex or 1), 1, Encounters.count())
    Game.encounterIndex = targetIdx
    Game.mode = "battle"
    Game.alertEncounterIdx = nil

    if skipEnterDash then
        Game.battlePhase = "player_turn"
        Game.battleEnterT = 1.0
        Game.puduAnimMode = "battle_idle"
    else
        Game.battlePhase = "battle_enter"
        Game.battleEnterT = clamp(initialEnterT or 0.0, 0.0, 0.99)
        Game.puduAnimMode = "battle_enter"
    end

    Game.enemyReaction = (Game.cli and Game.cli.forceReaction) or "idle"

    if Game.audio then
        Game.audio:playTrack("user_battle", false)
    end
    if Game.beatSync then
        local ts = Game.audio and Game.audio:getTrackState()
        Game.beatSync:reset((ts and ts.bpm) or 139.20)
    end
end

--------------------------------------------------------------------------------
-- JRPG Encounter Transition State Machine
--------------------------------------------------------------------------------

local function triggerEncounterTransition(idx)
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then
        return
    end
    local enc = Encounters.getByIndex(idx)
    if not enc then return end

    Game.encounterIndex = idx
    Game.alertEncounterIdx = idx
    Game.transitionState = "alert"
    Game.transitionTimer = 0.0
    Game.transitionSwitched = false
    if Game.audio then
        Game.audio:play("sfx_encounter_start", 0.90)
    end
end

local function triggerReturnToExplore()
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then
        return
    end
    Game.transitionState = "to_explore"
    Game.transitionTimer = 0.0
    Game.transitionSwitched = false
end

local function updateTransition(dt)
    if Game.transitionState == "alert" then
        Game.transitionTimer = Game.transitionTimer + dt
        if Game.transitionTimer >= ALERT_DURATION then
            Game.transitionState = "to_battle"
            Game.transitionTimer = 0.0
            Game.transitionSwitched = false
        end
    elseif Game.transitionState == "to_battle" then
        Game.transitionTimer = Game.transitionTimer + dt
        local p = Game.transitionTimer / TO_BATTLE_DURATION
        if p >= 0.50 and not Game.transitionSwitched then
            Game.transitionSwitched = true
            enterBattleArenaImmediate(Game.encounterIndex, false, 0.0)
        end
        if p >= 1.0 then
            Game.transitionState = "none"
            Game.transitionTimer = 0.0
        end
    elseif Game.transitionState == "to_explore" then
        Game.transitionTimer = Game.transitionTimer + dt
        local p = Game.transitionTimer / TO_EXPLORE_DURATION
        if p >= 0.50 and not Game.transitionSwitched then
            Game.mode = "explore"
            Game.alertEncounterIdx = nil
            Game.transitionSwitched = true
            local enc = Encounters.getByIndex(Game.encounterIndex)
            if enc then
                local du = Game.puduU - enc.u
                local dv = Game.puduV - enc.v
                if math.sqrt(du * du + dv * dv) < 2.4 then
                    Game.puduU, Game.puduV = findSafeSpotNearEncounter(enc, -2.6)
                end
            end
            Game.stage:snapCameraToChunk(Game.puduU, Game.puduV)
            Game.encounterCooldown = 0.85
            syncMusicForMode()
        end
        if p >= 1.0 then
            Game.transitionState = "none"
            Game.transitionTimer = 0.0
        end
    end
end

--------------------------------------------------------------------------------
-- Overworld & Battle Update Loops
--------------------------------------------------------------------------------

local function updateExplore(dt)
    if Game.encounterCooldown > 0 then
        Game.encounterCooldown = math.max(0.0, Game.encounterCooldown - dt)
    end

    -- Pause walk input while calm room-snapped camera pans between rooms (R7)
    if Game.stage:isCameraPanning() then
        Game.puduMoving = false
        Game.puduAnimCol = 1
        Game.puduBobY = 0.0
        Game.stage:updateExploreCamera(Game.puduU, Game.puduV, dt)
        return
    end

    local dx, dy = 0, 0
    if love.keyboard.isDown("w", "up") then dy = dy - 1 end
    if love.keyboard.isDown("s", "down") then dy = dy + 1 end
    if love.keyboard.isDown("a", "left") then dx = dx - 1 end
    if love.keyboard.isDown("d", "right") then dx = dx + 1 end

    if dx ~= 0 or dy ~= 0 then
        Game.puduMoving = true
        Game.puduFacingRow = screenDirToFacingRow(dx, dy)
        local du, dv = StageRenderer.screenVecToIso(dx, dy, WALK_SPEED)
        local candU = Game.puduU + du * dt
        local candV = Game.puduV + dv * dt

        -- Separate-axis sliding collision check
        if StageRenderer.isWalkable(candU, candV) then
            Game.puduU, Game.puduV = candU, candV
        elseif StageRenderer.isWalkable(candU, Game.puduV) then
            Game.puduU = candU
        elseif StageRenderer.isWalkable(Game.puduU, candV) then
            Game.puduV = candV
        end

        Game.puduWalkT = Game.puduWalkT + dt * 9.5
        Game.puduAnimCol = (math.floor(Game.puduWalkT) % 6) + 1
        Game.puduBobY = -math.abs(math.sin(Game.puduWalkT * 1.15)) * 3.2
    else
        Game.puduMoving = false
        Game.puduAnimCol = 1
        Game.puduBobY = math.sin(Game.elapsed * 3.0) * 1.2
    end

    Game.stage:updateExploreCamera(Game.puduU, Game.puduV, dt)

    -- Check proximity collision with undefeated rivals
    if Game.encounterCooldown <= 0 then
        for i = 1, Encounters.count() do
            local enc = Encounters.LIST[i]
            if not Game.defeatedMap[enc.id] then
                local du = enc.u - Game.puduU
                local dv = enc.v - Game.puduV
                if (du * du + dv * dv) < (ENCOUNTER_TRIGGER_DIST * ENCOUNTER_TRIGGER_DIST) then
                    triggerEncounterTransition(i)
                    return
                end
            end
        end
    end
end

local function updateBattle(dt)
    if Game.battlePhase == "battle_enter" then
        Game.battleEnterT = math.min(1.0, Game.battleEnterT + dt / BATTLE_ENTER_DURATION)
        Game.puduAnimMode = "battle_enter"
        if Game.battleEnterT >= 1.0 then
            Game.battlePhase = "player_turn"
            Game.puduAnimMode = "battle_idle"
        end
    end
end

--------------------------------------------------------------------------------
-- Battle Actor Renderers (Lit HD-2D Pudú + Spring Wizard Hat + Rival Groove)
--------------------------------------------------------------------------------

local function drawBattleDashDust(x, y, enterT, time)
    if enterT >= 0.94 then
        return
    end
    local fade = clamp(1.0 - enterT * 0.9, 0.15, 0.85)
    love.graphics.setShader()
    for i = 1, 4 do
        local lag = i * 24.0 + ((time * 90.0 + i * 17.0) % 18.0)
        local r = (11.5 - i * 1.8) * (0.8 + 0.2 * math.sin(time * 16.0 + i))
        local dy = -i * 2.5 - math.abs(math.sin(time * 12.0 + i * 1.3)) * 5.0
        love.graphics.setColor(0.94, 0.90, 0.80, fade * (0.48 - i * 0.08))
        love.graphics.circle("fill", x - lag, y + dy, math.max(2.5, r))
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawPuduSprite(x, y, targetH, pose, litShader)
    local assets = Game.assets
    if not assets then return end

    local p = pose or {
        row = 1, col = 1, scaleX = 1, scaleY = 1,
        jumpY = 0, tilt = 0, stepX = 0, stepY = 0,
        hatOffsetY = 0, hatTilt = 0, noteSparkle = false,
    }
    local row = clamp(math.floor(p.row or 1), 0, 7)
    local col = clamp(math.floor(p.col or 1), 1, 6)
    local px = x + (p.stepX or 0.0)
    local py = y + (p.stepY or 0.0)
    local jumpY = p.jumpY or 0.0
    local tilt = p.tilt or 0.0
    local sxMul = p.scaleX or 1.0
    local syMul = p.scaleY or 1.0

    -- Contact shadow on ground shrinks gently as Pudú hops into the air
    local airFrac = clamp(-jumpY / 24.0, 0.0, 1.0)
    local shScale = 1.0 - airFrac * 0.30
    love.graphics.setShader()
    love.graphics.setColor(0.03, 0.04, 0.08, 0.36 * (1.0 - airFrac * 0.28))
    love.graphics.ellipse("fill", px, py + 4, targetH * 0.31 * shScale, targetH * 0.105 * shScale)

    -- Subtle comic motion dust during battle_enter trot (zero music notes!)
    if Game.battlePhase == "battle_enter" then
        drawBattleDashDust(px, py + 2, Game.battleEnterT, Game.elapsed)
    end

    local puduPair = assets.pudu
    local quads = assets.puduQuads
    local sc = targetH / 64.0
    local isPlaceholderSheet = true

    if puduPair and puduPair.diff and quads and quads[row] and quads[row][col] then
        local quad = quads[row][col]
        local _, _, qw, qh = quad:getViewport()
        sc = targetH / math.max(1, qh)
        isPlaceholderSheet = puduPair.isPlaceholder and true or false
        love.graphics.setColor(1, 1, 1, 1)
        Game.stage:drawSpriteLit(
            puduPair,
            px,
            py + jumpY,
            tilt,
            sc * sxMul,
            sc * syMul,
            qw * 0.50,
            qh * 0.88,
            quad,
            0.0,
            nil,
            litShader,
            true
        )
    else
        love.graphics.setColor(0.58, 0.35, 0.20, 1.0)
        love.graphics.circle("fill", px, py - targetH * 0.4 + jumpY, targetH * 0.28)
    end

    -- Pointy brown wizard hat with head-offset anchoring + spring follow-through
    local hatPair = assets.wizardHat
    if hatPair and hatPair.diff then
        local hw, hh = hatPair.diff:getDimensions()
        local unit = targetH / 64.0
        local off = HAT_HEAD_OFFSETS[row] or HAT_HEAD_OFFSETS[1]

        -- Air-tuck / dash head shift when col == 5 (full on real sheet, subtle on procedural placeholder)
        local dashShiftX, dashShiftY = 0.0, 0.0
        if col == 5 then
            local flip = (row == 5 or row == 6 or row == 7) and -1.0 or 1.0
            local shiftFactor = isPlaceholderSheet and 0.25 or 1.0
            dashShiftX = flip * 7.0 * unit * shiftFactor
            dashShiftY = 6.5 * unit * shiftFactor
        end

        -- Transform local head offset by Pudú's squash/stretch and body tilt
        local localX = (off.x * unit + dashShiftX) * sxMul
        local localY = (off.y * unit + dashShiftY) * syMul
        local cosT = math.cos(tilt)
        local sinT = math.sin(tilt)
        local rotX = localX * cosT - localY * sinT
        local rotY = localX * sinT + localY * cosT

        local hatX = px + rotX
        local hatY = py + jumpY + rotY + (p.hatOffsetY or 0.0)
        local hatRot = p.hatTilt or tilt

        -- Exact visual proportion in both Modo A (tight 34x24 PNG -> sc * 0.92) & Modo B (64x64 procedural)
        local hatSc
        if hatPair.isPlaceholder then
            hatSc = (targetH * 0.58) / math.max(1, hh)
        else
            hatSc = sc * 0.92
        end

        -- Slight elastic squash/stretch echo on hat
        local hatSx = hatSc * (1.0 + (sxMul - 1.0) * 0.45)
        local hatSy = hatSc * (1.0 + (syMul - 1.0) * 0.45)

        love.graphics.setColor(1, 1, 1, 1)
        Game.stage:drawSpriteLit(
            hatPair,
            hatX,
            hatY,
            hatRot,
            hatSx,
            hatSy,
            hw * 0.50,
            hh * 0.82,
            nil,
            0.0,
            nil,
            litShader,
            true
        )
    end
end

local function drawEnemySprite(enc, x, y, targetH, groove, litShader)
    if not enc or not Game.assets then return end
    local g = groove or { offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1, tilt = 0 }

    local ex = x + (enc.offsetX or 0.0) + (g.offsetX or 0.0)
    local ey = y + (enc.offsetY or 0.0)
    local dy = g.offsetY or 0.0
    local tilt = g.tilt or 0.0
    local sxMul = g.scaleX or 1.0
    local syMul = g.scaleY or 1.0

    -- Soft contact shadow beneath rival feet
    local airFrac = clamp(-dy / 22.0, 0.0, 1.0)
    local shScale = 1.0 - airFrac * 0.25
    love.graphics.setShader()
    love.graphics.setColor(0.03, 0.04, 0.08, 0.36 * (1.0 - airFrac * 0.25))
    love.graphics.ellipse("fill", ex, ey + 4, 46 * shScale, 15 * shScale)

    local encPair = Game.assets.encounters and Game.assets.encounters[enc.id]
    if encPair and encPair.diff then
        local img = encPair.diff
        local quad = nil
        local fw, fh
        if encPair.isSheet and encPair.quads then
            local rowTable = encPair.quads[enc.sheetRow or 1] or encPair.quads[0]
            if rowTable and #rowTable > 0 then
                local colIdx = (math.floor(Game.elapsed * 5.0) % #rowTable) + 1
                quad = rowTable[colIdx]
                local _, _, qw, qh = quad:getViewport()
                fw, fh = qw, qh
            end
        end
        if not fw then
            fw, fh = img:getDimensions()
        end

        local scaleFactor = (enc.scale or 2.55) / 2.55
        local sc = (targetH * scaleFactor) / math.max(1, fh)
        love.graphics.setColor(1, 1, 1, 1)
        Game.stage:drawSpriteLit(
            encPair,
            ex,
            ey + dy,
            tilt,
            sc * sxMul,
            sc * syMul,
            fw * 0.50,
            fh * 0.92,
            quad,
            0.0,
            nil,
            litShader,
            true
        )
    else
        local c = enc.color or { 0.88, 0.36, 0.36 }
        love.graphics.setColor(c[1], c[2], c[3], 1.0)
        love.graphics.ellipse("fill", ex, ey - targetH * 0.45 + dy, 34, targetH * 0.45)
    end
end

--------------------------------------------------------------------------------
-- Minimalist Vector HUD Helpers (Rule R2: ZERO Unicode Tofu; Rule R6: Zero Overlap)
--------------------------------------------------------------------------------

local function drawBevelBox(x, y, w, h, fillCol, borderCol)
    love.graphics.setColor(0.02, 0.04, 0.10, 0.58)
    love.graphics.rectangle("fill", x + 3, y + 4, w, h, 8, 8)

    love.graphics.setColor(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 0.94)
    love.graphics.rectangle("fill", x, y, w, h, 7, 7)

    love.graphics.setLineWidth(2)
    love.graphics.setColor(borderCol[1], borderCol[2], borderCol[3], borderCol[4] or 0.92)
    love.graphics.rectangle("line", x, y, w, h, 7, 7)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 0.14)
    love.graphics.rectangle("line", x + 3, y + 3, w - 6, h - 6, 5, 5)
end

local function drawMusicNoteIcon(x, y, muted)
    local c = muted and { 0.62, 0.66, 0.74 } or { 0.98, 0.84, 0.34 }
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.ellipse("fill", x + 4, y + 13, 4, 3)
    love.graphics.ellipse("fill", x + 13, y + 11, 4, 3)
    love.graphics.rectangle("fill", x + 7, y + 2, 2, 11)
    love.graphics.rectangle("fill", x + 16, y + 0, 2, 11)
    love.graphics.polygon("fill", x + 7, y + 2, x + 18, y + 0, x + 18, y + 3, x + 7, y + 5)
    if muted then
        love.graphics.setColor(0.95, 0.34, 0.32, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(x + 1, y + 1, x + 19, y + 15)
        love.graphics.setLineWidth(1)
    end
end

local function drawSunLampIcon(x, y, presetId)
    if presetId == "noche" then
        love.graphics.setColor(0.76, 0.86, 1.0, 1)
        love.graphics.circle("fill", x + 7, y + 8, 5.5)
        love.graphics.setColor(0.08, 0.16, 0.36, 1)
        love.graphics.circle("fill", x + 9.5, y + 6.5, 4.5)
    elseif presetId == "atardecer" then
        love.graphics.setColor(1.0, 0.68, 0.28, 1)
        love.graphics.circle("fill", x + 7, y + 9, 5.0)
        love.graphics.setColor(1.0, 0.88, 0.44, 0.9)
        love.graphics.rectangle("fill", x + 1, y + 12, 12, 2)
    elseif presetId == "dramatico" then
        love.graphics.setColor(1.0, 0.90, 0.54, 1)
        love.graphics.polygon("fill", x + 7, y + 2, x + 1, y + 14, x + 13, y + 14)
    else
        love.graphics.setColor(1.0, 0.88, 0.34, 1)
        love.graphics.circle("fill", x + 7, y + 8, 4.2)
        love.graphics.setLineWidth(1.5)
        love.graphics.line(x + 7, y + 1, x + 7, y + 3)
        love.graphics.line(x + 7, y + 13, x + 7, y + 15)
        love.graphics.line(x + 0, y + 8, x + 2, y + 8)
        love.graphics.line(x + 12, y + 8, x + 14, y + 8)
        love.graphics.setLineWidth(1)
    end
end

local function drawTopHud(w)
    local fBody = Game.fonts.body
    local fSmall = Game.fonts.small
    local audioStats = Game.audio and Game.audio:getStats() or { muted = false }
    local preset, presetId = Game.stage:getLightingPreset()

    -- Left Context Chip (y = 12..44, strictly above minimap y = 58)
    local leftLabel
    local dotCol
    if Game.mode == "explore" then
        local biomeId = StageRenderer.getBiomeAt(Game.puduU)
        local biome = Encounters.getBiome(biomeId)
        leftLabel = biome.name
        dotCol = biome.accentColor or { 0.36, 0.80, 0.44 }
    else
        local enc = Encounters.getByIndex(Game.encounterIndex)
        leftLabel = string.format("Encuentro #%d: %s", Game.encounterIndex, enc and enc.name or "Rival")
        dotCol = (enc and enc.color) or { 0.96, 0.42, 0.36 }
    end

    love.graphics.setFont(fBody)
    local lw = fBody:getWidth(leftLabel) + 42
    drawBevelBox(14, 12, lw, 32, { 0.08, 0.16, 0.36, 0.92 }, { 0.72, 0.82, 0.98, 0.90 })
    love.graphics.setColor(dotCol[1], dotCol[2], dotCol[3], 1)
    love.graphics.circle("fill", 30, 28, 5.5)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.circle("line", 30, 28, 5.5)
    love.graphics.setColor(0.98, 0.98, 1.0, 1)
    love.graphics.print(leftLabel, 43, 19)

    -- Right Compact Control Chips (y = 12..44)
    love.graphics.setFont(fSmall)
    local f5Text = "[F5]"
    local tabText = (Game.mode == "battle") and "[ESC] Mapa" or "[TAB] Combate"
    local lightText = string.format("[L] %s", (preset and preset.label) or "Dia")
    local muteText = audioStats.muted and "Mute [M]" or "Audio [M]"

    local f5W = fSmall:getWidth(f5Text) + 18
    local tabW = fSmall:getWidth(tabText) + 20
    local lightW = fSmall:getWidth(lightText) + 34
    local muteW = fSmall:getWidth(muteText) + 36

    local rx = w - 14
    -- [F5]
    rx = rx - f5W
    drawBevelBox(rx, 12, f5W, 32, { 0.08, 0.16, 0.36, 0.90 }, { 0.64, 0.78, 0.96, 0.86 })
    love.graphics.setColor(0.94, 0.96, 1.0, 1)
    love.graphics.print(f5Text, rx + 9, 21)

    -- [TAB/ESC]
    rx = rx - 8 - tabW
    local tabFill = (Game.mode == "battle") and { 0.42, 0.22, 0.22, 0.92 } or { 0.14, 0.34, 0.56, 0.92 }
    drawBevelBox(rx, 12, tabW, 32, tabFill, { 0.76, 0.86, 0.98, 0.90 })
    love.graphics.setColor(0.99, 0.97, 0.88, 1)
    love.graphics.print(tabText, rx + 10, 21)

    -- [L] Lighting Preset
    rx = rx - 8 - lightW
    drawBevelBox(rx, 12, lightW, 32, { 0.10, 0.17, 0.36, 0.92 }, { 0.74, 0.84, 0.98, 0.88 })
    drawSunLampIcon(rx + 8, 20, presetId)
    love.graphics.setColor(0.98, 0.95, 0.86, 1)
    love.graphics.print(lightText, rx + 26, 21)

    -- [M] Music Note + Mute
    rx = rx - 8 - muteW
    drawBevelBox(rx, 12, muteW, 32, { 0.08, 0.16, 0.36, 0.90 }, { 0.64, 0.78, 0.96, 0.86 })
    drawMusicNoteIcon(rx + 8, 20, audioStats.muted)
    love.graphics.setColor(0.94, 0.96, 1.0, 1)
    love.graphics.print(muteText, rx + 30, 21)

    -- Center Toast (y = 14..42, auto-sized cleanly)
    if Game.toastText then
        local tw = fSmall:getWidth(Game.toastText) + 24
        local tx = math.floor((w - tw) * 0.5)
        drawBevelBox(tx, 14, tw, 28, { 0.14, 0.42, 0.26, 0.94 }, { 0.66, 0.96, 0.76, 0.92 })
        love.graphics.setColor(0.98, 1.0, 0.96, 1)
        love.graphics.print(Game.toastText, tx + 12, 21)
    end
end

local function drawExploreFooterHint(w, h)
    local fSmall = Game.fonts.small
    local text = "WASD / Flechas: Caminar   |   [L] Iluminación   |   Choca con un rival o [TAB] para combatir"
    love.graphics.setFont(fSmall)
    local bw = fSmall:getWidth(text) + 24
    local bx = w - bw - 14
    local by = h - 38
    love.graphics.setColor(0.04, 0.07, 0.16, 0.78)
    love.graphics.rectangle("fill", bx, by, bw, 26, 6, 6)
    love.graphics.setColor(0.64, 0.78, 0.96, 0.55)
    love.graphics.rectangle("line", bx, by, bw, 26, 6, 6)
    love.graphics.setColor(0.90, 0.95, 1.0, 0.94)
    love.graphics.print(text, bx + 12, by + 6)
end

-- Clean minimalist Final Fantasy bottom strip for Phase 2 (zero rhythm UI, zero Dance button, zero prompt spoilers)
local function drawBattlePhase2Footer(w, h, enc, theme)
    local fHead = Game.fonts.heading
    local fBody = Game.fonts.body
    local fSmall = Game.fonts.small
    local stripH = 74
    local stripY = h - stripH - 10
    local stripX = 16
    local stripW = w - 32

    drawBevelBox(stripX, stripY, stripW, stripH, { 0.07, 0.15, 0.36, 0.94 }, { 0.76, 0.86, 0.98, 0.94 })

    -- Left: Pudú Portrait + Hero Status
    local portBox = 56
    local portX = stripX + 12
    local portY = stripY + 9
    love.graphics.setColor(0.04, 0.09, 0.22, 0.95)
    love.graphics.rectangle("fill", portX, portY, portBox, portBox, 6, 6)
    local portImg = Game.assets and Game.assets.portraits and Game.assets.portraits.happy
    if portImg then
        local pw, ph = portImg:getDimensions()
        local psc = (portBox - 6) / math.max(1, math.max(pw, ph))
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(portImg, portX + portBox * 0.5, portY + portBox * 0.5, 0, psc, psc, pw * 0.5, ph * 0.5)
    end
    love.graphics.setColor(0.76, 0.88, 1.0, 0.85)
    love.graphics.rectangle("line", portX, portY, portBox, portBox, 6, 6)

    local heroX = portX + portBox + 14
    love.graphics.setFont(fHead)
    love.graphics.setColor(0.99, 0.92, 0.56, 1)
    love.graphics.print("Pudú Mago", heroX, stripY + 12)

    -- Clean HP bar for Pudú
    local barW = 148
    local barH = 12
    local barY = stripY + 38
    love.graphics.setColor(0.04, 0.08, 0.18, 0.95)
    love.graphics.rectangle("fill", heroX, barY, barW, barH, 4, 4)
    love.graphics.setColor(0.24, 0.86, 0.56, 1)
    love.graphics.rectangle("fill", heroX + 2, barY + 2, barW - 4, barH - 4, 3, 3)
    love.graphics.setColor(0.76, 0.88, 1.0, 0.72)
    love.graphics.rectangle("line", heroX, barY, barW, barH, 4, 4)
    love.graphics.setFont(fSmall)
    love.graphics.setColor(0.90, 0.96, 1.0, 0.94)
    love.graphics.print("HP 100 / 100", heroX, stripY + 53)

    -- Vertical divider
    local divX = heroX + barW + 24
    love.graphics.setColor(0.72, 0.84, 0.98, 0.35)
    love.graphics.line(divX, stripY + 12, divX, stripY + stripH - 12)

    -- Center-Right: Stage context & Phase 2 inspection hints (zero spoilers, zero rhythm UI)
    local infoX = divX + 20
    local infoW = (stripX + stripW - 18) - infoX
    local stageName = (theme and theme.name) or (enc and enc.stage) or "Plaza"
    local phaseLabel = (Game.battlePhase == "battle_enter") and "Entrando a la arena..." or (enc and enc.introLine or "Listo para el duelo")

    love.graphics.setFont(fBody)
    love.graphics.setColor(0.99, 0.97, 0.90, 1)
    love.graphics.printf("\"" .. phaseLabel .. "\"", infoX, stripY + 14, infoW, "left")

    love.graphics.setFont(fSmall)
    love.graphics.setColor(0.72, 0.86, 0.98, 0.92)
    love.graphics.printf(
        string.format("Escenario: %s   |   [L] Cambiar luz   |   [1-9] Saltar encuentro   |   [ESC/TAB] Volver al mapa", stageName),
        infoX, stripY + 44, infoW, "left"
    )
end

-- Diegetic rival nameplate & HP pill strictly underneath rival anchor (Rule R6)
local function drawDiegeticEnemyBar(enc, enemyX, enemyY)
    if not enc then return end
    local fSmall = Game.fonts.small
    local barW = 156
    local bx = math.floor(enemyX - barW * 0.5)
    local by = math.floor(enemyY + 26)

    love.graphics.setColor(0.04, 0.07, 0.16, 0.84)
    love.graphics.rectangle("fill", bx - 8, by - 4, barW + 16, 36, 6, 6)
    love.graphics.setColor(0.92, 0.72, 0.42, 0.80)
    love.graphics.rectangle("line", bx - 8, by - 4, barW + 16, 36, 6, 6)

    love.graphics.setFont(fSmall)
    love.graphics.setColor(1.0, 0.96, 0.86, 1)
    love.graphics.printf(enc.name, bx - 4, by - 1, barW + 8, "center")

    local hpY = by + 17
    love.graphics.setColor(0.12, 0.06, 0.10, 0.95)
    love.graphics.rectangle("fill", bx, hpY, barW, 10, 4, 4)
    love.graphics.setColor(0.94, 0.30, 0.28, 1)
    love.graphics.rectangle("fill", bx + 2, hpY + 2, barW - 4, 6, 3, 3)
    love.graphics.setColor(1.0, 0.82, 0.46, 0.78)
    love.graphics.rectangle("line", bx, hpY, barW, 10, 4, 4)
end

--------------------------------------------------------------------------------
-- LOVE Callbacks
--------------------------------------------------------------------------------

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")

    Game.cli = parseCliArgs(args)
    Game.mode = Game.cli.mode
    Game.encounterIndex = Game.cli.encounter
    Game.fonts = loadFonts()

    reloadAssets(false)
    Game.audio = Audio.new(false)
    Game.shaders = Shaders.load()
    Game.beatSync = BeatSync.new(139.20)

    local shaderWarnings = Shaders.getWarnings(Game.shaders)
    if shaderWarnings and #shaderWarnings > 0 then
        for _, warnMsg in ipairs(shaderWarnings) do
            io.stderr:write("[PUDU FANTASY SHADER WARN] " .. tostring(warnMsg) .. "\n")
        end
        io.stderr:flush()
    end

    Game.stage = StageRenderer.new()
    Game.stage:setShaders(Game.shaders)
    Game.stage:setLightingPreset(Game.cli.lighting)
    if Game.cli.disableBloom then
        Game.stage:setBloomEnabled(false)
    end
    Game.stage:buildOverworldDecor(Encounters.LIST)

    local w, h = love.graphics.getDimensions()
    ensureWorldCanvas(w, h)

    -- Initial Pudu overworld position & camera snap
    if Game.cli.biome then
        local biome = Encounters.getBiome(Game.cli.biome)
        Game.puduU = biome.spawnU or 3.8
        Game.puduV = StageRenderer.pathCenterV(Game.puduU)
        Game.puduFacingRow = 3
    elseif Game.cli.transitionPreview ~= nil or (Game.cli.encounterExplicit and Game.mode == "explore") then
        local enc = Encounters.getByIndex(Game.encounterIndex)
        if enc then
            Game.puduU, Game.puduV = findSafeSpotNearEncounter(enc, -2.0)
            Game.puduFacingRow = 3
        end
    else
        Game.puduU = 3.8
        Game.puduV = StageRenderer.pathCenterV(3.8)
        Game.puduFacingRow = 3
    end

    Game.stage:snapCameraToChunk(Game.puduU, Game.puduV)

    -- Optional frozen JRPG transition preview (--transition-preview=0.0..1.0)
    if Game.cli.transitionPreview ~= nil then
        Game.transitionPreview = Game.cli.transitionPreview
        Game.alertEncounterIdx = Game.encounterIndex
        if Game.transitionPreview >= 0.50 then
            enterBattleArenaImmediate(Game.encounterIndex, true, 1.0)
        else
            syncMusicForMode()
        end
    elseif Game.mode == "battle" or Game.cli.battleEnterPreview then
        -- If --battle-enter-preview is passed with short --quit-after, seed enterT cleanly near mid-dash
        local seedT = Game.cli.battleEnterPreview and 0.30 or 0.0
        enterBattleArenaImmediate(Game.encounterIndex, false, seedT)
    else
        syncMusicForMode()
    end
end

function love.resize(w, h)
    ensureWorldCanvas(w, h)
end

function love.update(dt)
    local safeDt = math.min(dt, 0.05)
    Game.elapsed = Game.elapsed + safeDt
    Game.cliElapsed = Game.cliElapsed + dt

    if Game.toastTimer > 0 then
        Game.toastTimer = math.max(0.0, Game.toastTimer - safeDt)
        if Game.toastTimer == 0 then
            Game.toastText = nil
        end
    end

    -- Always update BeatSync PLL against real audio clock (stays locked even when muted!)
    if Game.beatSync then
        local trackState = Game.audio and Game.audio:getTrackState() or nil
        Game.beatSync:update(safeDt, trackState)
    end

    if Game.transitionPreview == nil then
        if Game.transitionState ~= "none" then
            updateTransition(safeDt)
        elseif Game.mode == "explore" then
            updateExplore(safeDt)
        elseif Game.mode == "battle" then
            updateBattle(safeDt)
        end
    end

    if Game.cli.screenshot and not Game.cliScreenshotDone and Game.framesDrawn >= 2 then
        local triggerAt = Game.cli.quitAfter and math.max(0.15, Game.cli.quitAfter - 0.35) or 0.25
        if Game.cliElapsed >= triggerAt then
            Game.cliScreenshotDone = true
            saveScreenshotTo(Game.cli.screenshot)
        end
    end

    if Game.cli.quitAfter and Game.cliElapsed >= Game.cli.quitAfter then
        if Game.cli.printPerf then
            local bloomOn = (not Game.cli.disableBloom) and (Game.shaders and Game.shaders.post ~= nil)
            io.stdout:write(string.format(
                "[PERF] fps=%d deferred=false gi=false bloom=%s drawcalls=%d\n",
                love.timer.getFPS(),
                tostring(bloomOn),
                Game.lastDrawCalls
            ))
            io.stdout:flush()
        end
        love.event.quit(0)
    end
end

function love.keypressed(key)
    -- Tool hotkeys always work even during transitions (Contract 3.1)
    if key == "f5" then
        reloadAssets(true)
        return
    elseif key == "m" then
        if Game.audio then
            local muted = Game.audio:toggleMute()
            showToast(muted and "Audio silenciado (reloj BPM activo)" or "Audio activado", 1.8)
        end
        return
    elseif key == "l" then
        local _, preset = Game.stage:cycleLightingPreset()
        showToast("Iluminación: " .. ((preset and preset.label) or "Día"), 1.8)
        return
    elseif key == "f12" then
        local out = string.format("screenshots/manual_%d.png", os.time())
        saveScreenshotTo(out)
        showToast("Captura guardada: " .. out, 2.2)
        return
    end

    -- Lock gameplay input during transitions
    if Game.transitionState ~= "none" then
        return
    end

    -- Phase 2 QA shortcut: keys 1..9 jump directly between the 9 encounters / 8 battle arenas
    if Game.mode == "battle" then
        local num = tonumber(key)
        if num and num >= 1 and num <= Encounters.count() then
            enterBattleArenaImmediate(num, false, 0.0)
            local enc = Encounters.getByIndex(num)
            showToast(string.format("Encuentro #%d: %s (%s)", num, enc.name, enc.stage), 1.8)
            return
        end
    end

    if key == "tab" then
        if Game.mode == "explore" then
            local nearIdx = findNearestEncounterIndex(true)
            triggerEncounterTransition(nearIdx)
        elseif Game.mode == "battle" then
            triggerReturnToExplore()
        end
    elseif key == "escape" then
        if Game.mode == "battle" then
            triggerReturnToExplore()
        else
            love.event.quit(0)
        end
    end
end

function love.draw()
    Game.framesDrawn = Game.framesDrawn + 1
    local w, h = love.graphics.getDimensions()
    local canvas = ensureWorldCanvas(w, h)

    local battleEnc = nil
    local battleTheme = nil
    local battleAnchors = nil
    local battleSlideOff = 0.0

    -- 1. Render HD-2D World (Overworld or Battle Arena + Atmospheric Lighting) into worldCanvas
    if canvas then
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0.05, 0.07, 0.14, 1.0)
    end

    if Game.mode == "explore" then
        local biomeId = StageRenderer.getBiomeAt(Game.stage.camU)
        local biome = Encounters.getBiome(biomeId)
        local theme = Encounters.getTheme(biome.stageDefault)
        local lights = Game.stage:collectZoneLights(w, h, Game.elapsed)
        local litShader = Game.stage:configureLitShader(theme, w, h, Game.elapsed, lights)
        local overPose = Game.beatSync and Game.beatSync:getPuduDancePose(
            Game.puduMoving and "walk" or "overworld_idle",
            Game.puduFacingRow
        )

        Game.stage:drawOverworld({
            w = w,
            h = h,
            time = Game.elapsed,
            assets = Game.assets,
            encounters = Encounters.LIST,
            defeatedMap = Game.defeatedMap,
            puduU = Game.puduU,
            puduV = Game.puduV,
            puduFacingRow = Game.puduFacingRow,
            puduAnimCol = Game.puduAnimCol,
            puduBobY = Game.puduBobY,
            puduHatOffsetY = overPose and overPose.hatOffsetY or 0.0,
            puduHatTilt = overPose and overPose.hatTilt or 0.0,
            alertEncounterIdx = Game.alertEncounterIdx,
            alertTimer = (Game.transitionState == "alert") and Game.transitionTimer or 0.25,
            fonts = Game.fonts,
            litShader = litShader,
        })
        Game.stage:drawAtmosphericLighting(Game.assets and Game.assets.lightRadial, lights, w, h, Game.elapsed)
    else
        battleEnc = Encounters.getByIndex(Game.encounterIndex) or Encounters.LIST[1]
        battleTheme = Encounters.getTheme(battleEnc.stage)
        local lights = Game.stage:collectBattleLights(battleEnc, w, h, Game.elapsed)
        local litShader = Game.stage:configureLitShader(battleTheme, w, h, Game.elapsed, lights)
        local beatPulse = Game.beatSync and Game.beatSync:getBeatPulse() or 0.0

        battleAnchors = Game.stage:drawBattleArena(
            battleEnc,
            Encounters.STAGE_THEMES,
            Game.assets,
            beatPulse,
            w,
            h,
            Game.elapsed,
            litShader
        )

        if Game.battlePhase == "battle_enter" then
            battleSlideOff = (1.0 - smoothstep01(Game.battleEnterT)) * BATTLE_ENTER_SLIDE_PX
        end

        local puduPose = Game.beatSync and Game.beatSync:getPuduDancePose(Game.puduAnimMode) or nil
        local enemyGroove = Game.beatSync and Game.beatSync:getEnemyGroove(Game.enemyReaction) or nil

        drawPuduSprite(battleAnchors.puduX - battleSlideOff, battleAnchors.puduY, 126.0, puduPose, litShader)
        drawEnemySprite(battleEnc, battleAnchors.enemyX + battleSlideOff, battleAnchors.enemyY, 152.0, enemyGroove, litShader)

        Game.stage:drawBattleArenaForeground(battleEnc, Game.assets, w, h, Game.elapsed, litShader)
        Game.stage:drawAtmosphericLighting(Game.assets and Game.assets.lightRadial, lights, w, h, Game.elapsed)
    end

    if canvas then
        love.graphics.setCanvas()
        -- 2. Post-processed world output (safe bloom + vignette)
        Game.stage:drawPostProcessed(canvas, w, h)
    end

    -- 3. Razor-sharp UI Layer (drawn AFTER post-processing -> zero bloom on text!)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)

    if Game.mode == "explore" then
        drawTopHud(w)
        Game.stage:drawOverworldMinimap(
            Game.puduU,
            Game.puduV,
            Encounters.LIST,
            Game.defeatedMap,
            w,
            h,
            Game.fonts.small
        )
        drawExploreFooterHint(w, h)
    else
        drawTopHud(w)
        if battleAnchors and battleEnc then
            drawDiegeticEnemyBar(battleEnc, battleAnchors.enemyX + battleSlideOff, battleAnchors.enemyY)
        end
        drawBattlePhase2Footer(w, h, battleEnc, battleTheme)
    end

    -- 4. JRPG Battle Transition Overlay (live or --transition-preview)
    if Game.transitionPreview ~= nil then
        Game.stage:drawBattleTransition(Game.transitionPreview, w, h)
    elseif Game.transitionState == "to_battle" then
        Game.stage:drawBattleTransition(Game.transitionTimer / TO_BATTLE_DURATION, w, h)
    elseif Game.transitionState == "to_explore" then
        Game.stage:drawBattleTransition(Game.transitionTimer / TO_EXPLORE_DURATION, w, h)
    end

    local statsNow = love.graphics.getStats()
    Game.lastDrawCalls = statsNow.drawcalls or 0
end
