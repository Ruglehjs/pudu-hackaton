-- main.lua — Fase 00: Bootstrap, Harness CLI, Asset Dual-Mode & Audio Diagnostic (LOVE2D 11.5)

local json = require("json")
local AssetLoader = require("asset_loader")
local Audio = require("audio")

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
-- Phase 00 Preview Catalog (replaced by encounters.lua in Phase 01)
--------------------------------------------------------------------------------

local PREVIEW_ENCOUNTERS = {
    { id = "nino_helado",      name = "Niño del Helado Triple",    biome = "bosque",   color = { 0.94, 0.52, 0.62 } },
    { id = "mimo_muro",        name = "Mimo del Muro Invisible",   biome = "bosque",   color = { 0.85, 0.86, 0.92 } },
    { id = "puma_dramatico",   name = "Puma Dramático",            biome = "bosque",   color = { 0.88, 0.56, 0.24 }, isSheet = true, sheetCols = 4, sheetRows = 2 },
    { id = "turista_selfie",   name = "Turista del Selfie",        biome = "desierto", color = { 0.36, 0.78, 0.90 } },
    { id = "gato_guaton",      name = "Gato Guatón Inamovible",    biome = "desierto", color = { 0.92, 0.68, 0.30 } },
    { id = "gaviota_mafiosa",  name = "Gaviota Mafiosa",           biome = "costa",    color = { 0.78, 0.86, 0.96 } },
    { id = "piscina_barro",    name = "Pantano Traicionero",       biome = "costa",    color = { 0.44, 0.62, 0.34 } },
    { id = "semaforo_rebelde", name = "Semáforo Rebelde",          biome = "ciudad",   color = { 0.92, 0.32, 0.28 } },
    { id = "fila_tramite",     name = "Tótem de la Fila #999",     biome = "ciudad",   color = { 0.66, 0.52, 0.88 } },
}

local DIR_LABELS = { [0] = "S", "SE", "E", "NE", "N", "NW", "W", "SW" }

local TILE_SHOWCASE = {
    { key = "grass_floor",    label = "Bosque",   biome = "bosque" },
    { key = "stone_floor",    label = "Plaza",    biome = "bosque" },
    { key = "desert_floor",   label = "Atacama",  biome = "desierto" },
    { key = "coast_floor",    label = "Costa",    biome = "costa" },
    { key = "mountain_floor", label = "Ciudad",   biome = "ciudad" },
}

--------------------------------------------------------------------------------
-- CLI Parser (every literal hyphen escaped as %-%-)
--------------------------------------------------------------------------------

local function parseCliArgs(argList)
    local cli = {
        mode = "explore",
        biome = "bosque",
        encounter = 1,
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
            if v then cli.biome = v end

            v = a:match("^%-%-encounter=(%d+)$")
            if v then
                local n = tonumber(v)
                if n then
                    cli.encounter = math.max(1, math.min(#PREVIEW_ENCOUNTERS, math.floor(n)))
                end
            end

            v = a:match("^%-%-lighting=(.+)$")
            if v then cli.lighting = v end

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
            if v then cli.forceReaction = v end

            v = a:match("^%-%-transition%-preview=(%d+%.?%d*)$")
            if v then cli.transitionPreview = tonumber(v) end

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
-- Game State & Helpers
--------------------------------------------------------------------------------

local Game = {
    cli = nil,
    mode = "explore",
    biome = "bosque",
    encounterIndex = 1,
    assets = nil,
    tileQuads = {},
    audio = nil,
    fonts = {},
    elapsed = 0,
    cliElapsed = 0,
    cliScreenshotDone = false,
    framesDrawn = 0,
    lastDrawCalls = 0,
    reloadCount = 0,
    toastText = nil,
    toastTimer = 0,
    jsonSelfTestOk = false,
}

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
        title = mk(22),
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

local function runJsonSanityCheck()
    local ok, encoded = pcall(json.encode, {
        title = "Pudú Fantasy",
        phase = 0,
        ok = true,
        tags = { "bosque", "ñandú" },
    })
    if not ok or type(encoded) ~= "string" then
        return false
    end
    local okDec, decoded = pcall(json.decode, encoded)
    return okDec and type(decoded) == "table" and decoded.title == "Pudú Fantasy" and decoded.phase == 0 and decoded.ok == true
end

local function syncMusicForMode()
    if not Game.audio then return end
    local trackId = (Game.mode == "battle") and "user_battle" or "overworld"
    Game.audio:playTrack(trackId, false)
end

local function reloadAssets(isHotReload)
    Game.assets = AssetLoader.loadAll(PREVIEW_ENCOUNTERS)
    Game.tileQuads = {}
    for _, tinfo in ipairs(TILE_SHOWCASE) do
        local pair = Game.assets.tiles and Game.assets.tiles[tinfo.key]
        if pair and pair.diff then
            local iw, ih = pair.diff:getDimensions()
            Game.tileQuads[tinfo.key] = love.graphics.newQuad(0, 0, iw * 2.5, ih * 1.5, iw, ih)
        end
    end
    if isHotReload then
        Game.reloadCount = Game.reloadCount + 1
        local s = Game.assets.stats
        showToast(string.format("Hot-Reload #%d listo (%d reales / %d greybox)", Game.reloadCount, s.realCount, s.placeholderCount), 2.5)
    end
end

--------------------------------------------------------------------------------
-- Vector UI Drawing Helpers (Zero Unicode Tofu — strictly LÖVE primitives)
--------------------------------------------------------------------------------

local function drawBevelPanel(x, y, w, h, fillCol, borderCol)
    love.graphics.setColor(0.02, 0.04, 0.10, 0.65)
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

local function drawChip(x, y, text, bgCol, textCol, font)
    love.graphics.setFont(font)
    local tw = font:getWidth(text)
    local w = tw + 18
    local h = 24
    love.graphics.setColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 5, 5)
    love.graphics.setColor(textCol[1], textCol[2], textCol[3], 1)
    love.graphics.print(text, x + 9, y + math.floor((h - font:getHeight()) * 0.5))
    return w
end

-- Vector eighth-note icon drawn purely with ellipse + rectangle + polygon (R2 compliant)
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

local function drawAssetFit(img, quad, x, y, boxW, boxH, scaleOverride)
    if not img then return end
    local iw, ih
    if quad then
        local _, _, qw, qh = quad:getViewport()
        iw, ih = qw, qh
    else
        iw, ih = img:getDimensions()
    end
    local scale = scaleOverride or math.min(boxW / iw, boxH / ih)
    local dw, dh = iw * scale, ih * scale
    local dx = math.floor(x + (boxW - dw) * 0.5)
    local dy = math.floor(y + (boxH - dh) * 0.5)
    love.graphics.setColor(1, 1, 1, 1)
    if quad then
        love.graphics.draw(img, quad, dx, dy, 0, scale, scale)
    else
        love.graphics.draw(img, dx, dy, 0, scale, scale)
    end
end

--------------------------------------------------------------------------------
-- LOVE Callbacks
--------------------------------------------------------------------------------

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")

    Game.cli = parseCliArgs(args)
    Game.mode = Game.cli.mode
    Game.biome = Game.cli.biome
    Game.encounterIndex = Game.cli.encounter
    Game.fonts = loadFonts()
    Game.jsonSelfTestOk = runJsonSanityCheck()

    reloadAssets(false)
    Game.audio = Audio.new(false)
    syncMusicForMode()
end

function love.update(dt)
    Game.elapsed = Game.elapsed + dt
    Game.cliElapsed = Game.cliElapsed + dt

    if Game.toastTimer > 0 then
        Game.toastTimer = math.max(0, Game.toastTimer - dt)
        if Game.toastTimer == 0 then
            Game.toastText = nil
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
            io.stdout:write(string.format(
                "[PERF] fps=%d deferred=false gi=false bloom=false drawcalls=%d\n",
                love.timer.getFPS(),
                Game.lastDrawCalls
            ))
            io.stdout:flush()
        end
        love.event.quit(0)
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit(0)
    elseif key == "f5" then
        reloadAssets(true)
    elseif key == "m" then
        if Game.audio then
            local muted = Game.audio:toggleMute()
            showToast(muted and "Audio silenciado (reloj BPM activo)" or "Audio activado", 1.8)
        end
    elseif key == "f12" then
        local out = string.format("screenshots/manual_%d.png", os.time())
        saveScreenshotTo(out)
        showToast("Captura guardada: " .. out, 2.2)
    elseif key == "b" then
        Game.mode = (Game.mode == "battle") and "explore" or "battle"
        syncMusicForMode()
        showToast("Modo vista previa: " .. Game.mode, 1.5)
    else
        local num = tonumber(key)
        if num and num >= 1 and num <= #PREVIEW_ENCOUNTERS then
            Game.encounterIndex = num
            showToast(string.format("Encuentro #%d: %s", num, PREVIEW_ENCOUNTERS[num].name), 1.6)
        end
    end
end

function love.draw()
    Game.framesDrawn = Game.framesDrawn + 1
    local w, h = love.graphics.getDimensions()
    local fTitle = Game.fonts.title
    local fHead = Game.fonts.heading
    local fBody = Game.fonts.body
    local fSmall = Game.fonts.small

    -- Background gradient bands (deep JRPG midnight sky)
    local bands = 10
    for i = 0, bands - 1 do
        local t = i / (bands - 1)
        love.graphics.setColor(0.05 + t * 0.04, 0.08 + t * 0.06, 0.16 + t * 0.10, 1)
        love.graphics.rectangle("fill", 0, math.floor(h * i / bands), w, math.ceil(h / bands) + 1)
    end

    local stats = Game.assets and Game.assets.stats or { realCount = 0, placeholderCount = 0, customCount = 0, mode = "B" }
    local audioStats = Game.audio and Game.audio:getStats() or { loadedTracks = 0, totalTracks = 6, loadedSfx = 0, totalSfx = 19, muted = false }
    local trackState = Game.audio and Game.audio:getTrackState() or { trackId = "none", bpm = 120, beatOffset = 0, playing = false }
    local activeEnc = PREVIEW_ENCOUNTERS[Game.encounterIndex] or PREVIEW_ENCOUNTERS[1]

    -- =========================================================================
    -- TOP HUD BAR (Zero-Overlap Lane: y = 10..48)
    -- =========================================================================
    drawBevelPanel(16, 10, w - 32, 42, { 0.09, 0.17, 0.38, 0.96 }, { 0.72, 0.82, 0.98, 0.92 })

    love.graphics.setFont(fTitle)
    love.graphics.setColor(0.99, 0.95, 0.78, 1)
    love.graphics.print("PUDÚ FANTASY", 30, 18)

    local cx = 216
    cx = cx + drawChip(cx, 19, "FASE 00", { 0.20, 0.34, 0.66 }, { 0.95, 0.98, 1.0 }, fSmall) + 8
    local modeLabel = (Game.mode == "battle")
        and string.format("MODO: BATTLE #%d", Game.encounterIndex)
        or ("MODO: EXPLORE (" .. Game.biome .. ")")
    local modeBg = (Game.mode == "battle") and { 0.68, 0.24, 0.24 } or { 0.18, 0.50, 0.34 }
    drawChip(cx, 19, modeLabel, modeBg, { 1, 1, 1 }, fSmall)

    -- Right-side status chips in Top HUD Bar
    local assetModeText = (stats.mode == "A") and "ASSETS: MODO A (REAL)"
        or ((stats.mode == "A+B") and "ASSETS: MODO A+B (MIXTO)" or "ASSETS: MODO B (GREYBOX)")
    local assetBg = (stats.mode == "A") and { 0.18, 0.52, 0.32 } or { 0.56, 0.38, 0.14 }
    local aw = fSmall:getWidth(assetModeText) + 18
    drawChip(w - 28 - aw, 19, assetModeText, assetBg, { 1, 0.98, 0.90 }, fSmall)

    local muteLabel = audioStats.muted and "AUDIO: MUTE [M]" or "AUDIO: ON [M]"
    local mw = fSmall:getWidth(muteLabel) + 38
    local mx = w - 36 - aw - mw
    love.graphics.setColor(0.14, 0.24, 0.50, 0.95)
    love.graphics.rectangle("fill", mx, 19, mw, 24, 5, 5)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.rectangle("line", mx, 19, mw, 24, 5, 5)
    drawMusicNoteIcon(mx + 7, 23, audioStats.muted)
    love.graphics.setFont(fSmall)
    love.graphics.setColor(0.95, 0.97, 1, 1)
    love.graphics.print(muteLabel, mx + 30, 24)

    -- Center toast if active (never overlaps chips)
    if Game.toastText then
        love.graphics.setFont(fSmall)
        local tw = fSmall:getWidth(Game.toastText) + 22
        local tx = math.floor((w - tw) * 0.5)
        drawChip(tx, 58, Game.toastText, { 0.16, 0.44, 0.28 }, { 0.98, 1, 0.95 }, fSmall)
    end

    -- =========================================================================
    -- LEFT COLUMN: CLI Harness, Audio Harness & Controls (x = 16..446)
    -- =========================================================================
    local leftX, leftW = 16, 430

    -- Card 1: CLI & Runtime Diagnostics
    drawBevelPanel(leftX, 66, leftW, 250, { 0.08, 0.15, 0.34, 0.95 }, { 0.62, 0.76, 0.96, 0.88 })
    love.graphics.setFont(fHead)
    love.graphics.setColor(0.98, 0.86, 0.44, 1)
    love.graphics.print("1. Harness CLI y Entorno (LÖVE2D 11.5)", leftX + 16, 78)

    local major, minor, rev = love.getVersion()
    local diagRows = {
        { "Motor / Ventana", string.format("LOVE %d.%d.%d  |  %dx%d (nearest, MSAA 0)", major, minor, rev, w, h) },
        { "--mode / --biome", string.format("%s  |  %s", Game.mode, Game.biome) },
        { "--encounter", string.format("#%d  (%s)", Game.encounterIndex, activeEnc.id) },
        { "--lighting / --mock", string.format("%s  |  mock = %s", Game.cli.lighting, tostring(Game.cli.mock)) },
        { "--screenshot", Game.cli.screenshot or "(ninguno)" },
        { "--quit-after", Game.cli.quitAfter and string.format("%.2fs (elapsed %.2fs)", Game.cli.quitAfter, Game.cliElapsed) or "interactivo" },
        { "json.lua UTF-8", Game.jsonSelfTestOk and "OK (roundtrip verificado)" or "ERROR" },
        { "Fuente / FPS", string.format("%s  |  %d FPS", Game.fonts.hasPackagedFont and "PTSans.ttc" or "LOVE fallback", love.timer.getFPS()) },
    }
    local ry = 108
    for _, row in ipairs(diagRows) do
        love.graphics.setFont(fSmall)
        love.graphics.setColor(0.68, 0.80, 0.98, 1)
        love.graphics.print(row[1], leftX + 16, ry)
        love.graphics.setColor(0.96, 0.98, 1.0, 1)
        love.graphics.print(row[2], leftX + 148, ry)
        ry = ry + 24
    end

    -- Card 2: Audio Harness Status
    drawBevelPanel(leftX, 330, leftW, 186, { 0.08, 0.15, 0.34, 0.95 }, { 0.62, 0.76, 0.96, 0.88 })
    love.graphics.setFont(fHead)
    love.graphics.setColor(0.98, 0.86, 0.44, 1)
    love.graphics.print("2. Audio Harness y Reloj BPM", leftX + 16, 342)

    local audioRows = {
        { "Track activo", tostring(trackState.trackId or "none") },
        { "BPM / beatOffset", string.format("%.2f BPM  |  offset %.3fs", trackState.bpm or 0, trackState.beatOffset or 0) },
        { "Estado reloj", trackState.playing and string.format("PLAYING (%.2fs)", trackState.pos or 0) or "MODO B (metrónomo silencioso)" },
        { "Pistas / SFX", string.format("%d/%d tracks  |  %d/%d SFX", audioStats.loadedTracks, audioStats.totalTracks, audioStats.loadedSfx, audioStats.totalSfx) },
        { "Faltantes", string.format("%d archivos (0 crashes)", audioStats.missingCount or 0) },
    }
    ry = 372
    for _, row in ipairs(audioRows) do
        love.graphics.setFont(fSmall)
        love.graphics.setColor(0.68, 0.80, 0.98, 1)
        love.graphics.print(row[1], leftX + 16, ry)
        love.graphics.setColor(0.96, 0.98, 1.0, 1)
        love.graphics.print(row[2], leftX + 148, ry)
        ry = ry + 26
    end

    -- Card 3: Asset Stats & Controls
    drawBevelPanel(leftX, 530, leftW, 174, { 0.08, 0.15, 0.34, 0.95 }, { 0.62, 0.76, 0.96, 0.88 })
    love.graphics.setFont(fHead)
    love.graphics.setColor(0.98, 0.86, 0.44, 1)
    love.graphics.print("3. Conteo de Assets y Controles", leftX + 16, 542)

    love.graphics.setFont(fBody)
    love.graphics.setColor(0.95, 0.98, 1.0, 1)
    love.graphics.print(
        string.format("Reales: %d   |   Greybox: %d   |   Custom: %d", stats.realCount, stats.placeholderCount, stats.customCount or 0),
        leftX + 16, 572
    )
    love.graphics.setFont(fSmall)
    love.graphics.setColor(0.76, 0.86, 0.98, 1)
    love.graphics.print("[F5]  Hot-reload PNGs (assets/ y assets/custom/)", leftX + 16, 604)
    love.graphics.print("[M]   Mute (mantiene el Source corriendo a vol 0)", leftX + 16, 624)
    love.graphics.print("[B]   Alternar vista Explore / Battle  |  [1-9] Rival", leftX + 16, 644)
    love.graphics.print("[F12] Guardar captura PNG  |  [ESC] Salir limpio", leftX + 16, 664)

    -- =========================================================================
    -- RIGHT COLUMN: Asset Loader & Greybox Visual Showcase (x = 462..1264)
    -- =========================================================================
    local rightX = 462
    local rightW = w - rightX - 16

    -- Top-Right Panel: Pudu 8-Dir Sheet, Wizard Hat, Light Radial, Portraits
    drawBevelPanel(rightX, 66, rightW, 326, { 0.08, 0.14, 0.30, 0.95 }, { 0.62, 0.76, 0.96, 0.88 })
    love.graphics.setFont(fHead)
    love.graphics.setColor(0.98, 0.86, 0.44, 1)
    love.graphics.print("Muestra de Sprites (Filtro nearest + Fallback Modo B)", rightX + 16, 78)

    local animCol = (math.floor(Game.elapsed * 7) % 6) + 1

    -- 8 directions strip (rows 0..7 = S, SE, E, NE, N, NW, W, SW)
    local cellW = 86
    local cellH = 98
    local stripX = rightX + 18
    local stripY = 108
    for row = 0, 7 do
        local bx = stripX + row * (cellW + 10)
        love.graphics.setColor(0.05, 0.09, 0.20, 0.95)
        love.graphics.rectangle("fill", bx, stripY, cellW, cellH, 6, 6)
        local isHighlight = (row == 3) -- NE canonical direction
        love.graphics.setColor(isHighlight and 0.98 or 0.45, isHighlight and 0.82 or 0.58, isHighlight and 0.30 or 0.80, 0.85)
        love.graphics.rectangle("line", bx, stripY, cellW, cellH, 6, 6)

        if Game.assets.pudu and Game.assets.puduQuads then
            drawAssetFit(Game.assets.pudu.diff, Game.assets.puduQuads[row][animCol], bx + 4, stripY + 4, cellW - 8, cellH - 24, 1.15)
        end
        love.graphics.setFont(fSmall)
        love.graphics.setColor(isHighlight and 0.98 or 0.85, isHighlight and 0.88 or 0.92, isHighlight and 0.46 or 1.0, 1)
        love.graphics.printf(string.format("%d:%s", row, DIR_LABELS[row]), bx, stripY + cellH - 18, cellW, "center")
    end

    -- Secondary showcase row: Wizard Hat, Light Radial, 3 Portraits
    local subY = 222
    local cardH = 152

    -- Wizard Hat box
    local hatX = rightX + 18
    love.graphics.setColor(0.05, 0.09, 0.20, 0.95)
    love.graphics.rectangle("fill", hatX, subY, 150, cardH, 6, 6)
    love.graphics.setColor(0.45, 0.58, 0.80, 0.8)
    love.graphics.rectangle("line", hatX, subY, 150, cardH, 6, 6)
    if Game.assets.wizardHat then
        drawAssetFit(Game.assets.wizardHat.diff, nil, hatX + 10, subY + 10, 130, 110, 1.75)
    end
    love.graphics.setFont(fSmall)
    love.graphics.setColor(0.94, 0.96, 1, 1)
    love.graphics.printf("Sombrero Mago", hatX, subY + cardH - 22, 150, "center")

    -- Light Radial box (linear filter proof)
    local radX = hatX + 164
    love.graphics.setColor(0.03, 0.04, 0.08, 1.0)
    love.graphics.rectangle("fill", radX, subY, 150, cardH, 6, 6)
    love.graphics.setColor(0.45, 0.58, 0.80, 0.8)
    love.graphics.rectangle("line", radX, subY, 150, cardH, 6, 6)
    if Game.assets.lightRadial then
        love.graphics.setColor(1.0, 0.88, 0.55, 1.0)
        local lw, lh = Game.assets.lightRadial:getDimensions()
        local sc = 112 / lw
        love.graphics.draw(Game.assets.lightRadial, radX + 19, subY + 8, 0, sc, sc)
    end
    love.graphics.setFont(fSmall)
    love.graphics.setColor(0.94, 0.96, 1, 1)
    love.graphics.printf("light_radial (linear)", radX, subY + cardH - 22, 150, "center")

    -- 3 Portraits box (happy, shocked, angry)
    local portX = radX + 164
    local portW = rightX + rightW - portX - 18
    love.graphics.setColor(0.05, 0.09, 0.20, 0.95)
    love.graphics.rectangle("fill", portX, subY, portW, cardH, 6, 6)
    love.graphics.setColor(0.45, 0.58, 0.80, 0.8)
    love.graphics.rectangle("line", portX, subY, portW, cardH, 6, 6)

    local moods = {
        { key = "happy",   label = "Feliz" },
        { key = "shocked", label = "Impactado" },
        { key = "angry",   label = "Enojado" },
    }
    local slotW = math.floor((portW - 24) / 3)
    for i, m in ipairs(moods) do
        local sx = portX + 12 + (i - 1) * slotW
        local img = Game.assets.portraits and Game.assets.portraits[m.key]
        drawAssetFit(img, nil, sx + 8, subY + 14, slotW - 16, 102, 1.5)
        love.graphics.setFont(fSmall)
        love.graphics.setColor(0.94, 0.96, 1, 1)
        love.graphics.printf(m.label, sx, subY + cardH - 22, slotW, "center")
    end

    -- Bottom-Right Panel: 5 Biome Tiles (2x2 repeat) + Active CLI Mode Preview
    drawBevelPanel(rightX, 408, rightW, 296, { 0.08, 0.14, 0.30, 0.95 }, { 0.62, 0.76, 0.96, 0.88 })
    love.graphics.setFont(fHead)
    love.graphics.setColor(0.98, 0.86, 0.44, 1)
    love.graphics.print("Tiles de Bioma (wrap = repeat) y Vista Previa del Modo CLI", rightX + 16, 420)

    -- 5 Biome Tiles row (evenly distributed across full width with cached repeat quads)
    local tileGap = 14
    local tileW = math.floor((rightW - 36 - tileGap * (#TILE_SHOWCASE - 1)) / #TILE_SHOWCASE)
    local tileH = 86
    local tileY = 450
    for i, tinfo in ipairs(TILE_SHOWCASE) do
        local tx = rightX + 18 + (i - 1) * (tileW + tileGap)
        local pair = Game.assets.tiles and Game.assets.tiles[tinfo.key]
        local repQuad = Game.tileQuads[tinfo.key]
        if pair and pair.diff and repQuad then
            local _, _, qw, qh = repQuad:getViewport()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(pair.diff, repQuad, tx, tileY, 0, tileW / qw, tileH / qh)
        end
        local activeBiome = (Game.mode == "explore" and tinfo.biome == Game.biome)
        love.graphics.setLineWidth(activeBiome and 2 or 1)
        love.graphics.setColor(activeBiome and 0.98 or 0.55, activeBiome and 0.84 or 0.70, activeBiome and 0.34 or 0.90, 0.95)
        love.graphics.rectangle("line", tx, tileY, tileW, tileH, 4, 4)
        love.graphics.setLineWidth(1)

        love.graphics.setFont(fSmall)
        love.graphics.setColor(0.96, 0.98, 1, 1)
        love.graphics.printf(tinfo.label, tx, tileY + tileH + 6, tileW, "center")
        love.graphics.setColor(0.68, 0.78, 0.94, 1)
        love.graphics.printf(tinfo.key:gsub("_floor", ""), tx, tileY + tileH + 22, tileW, "center")
    end

    -- Active Mode Stage Preview Box
    local prevX = rightX + 18
    local prevY = 582
    local prevW = rightW - 36
    local prevH = 106
    love.graphics.setColor(0.05, 0.09, 0.19, 0.96)
    love.graphics.rectangle("fill", prevX, prevY, prevW, prevH, 6, 6)
    love.graphics.setColor(0.48, 0.64, 0.88, 0.85)
    love.graphics.rectangle("line", prevX, prevY, prevW, prevH, 6, 6)

    if Game.mode == "battle" then
        -- Miniature JRPG Battle Preview proving --mode=battle --encounter=N
        local puduX = prevX + 76
        local rivalX = prevX + prevW - 148
        local bob = math.sin(Game.elapsed * 6.5) * 3

        if Game.assets.pudu and Game.assets.puduQuads then
            drawAssetFit(Game.assets.pudu.diff, Game.assets.puduQuads[2][animCol], puduX, prevY + 18 + bob, 72, 72, 1.25)
        end
        if Game.assets.wizardHat then
            drawAssetFit(Game.assets.wizardHat.diff, nil, puduX + 18, prevY + 4 + bob * 1.2, 46, 36, 0.72)
        end

        local encPair = Game.assets.encounters and Game.assets.encounters[activeEnc.id]
        if encPair and encPair.diff then
            drawAssetFit(encPair.diff, nil, rivalX, prevY + 10 - bob * 0.5, 84, 86, nil)
        end

        love.graphics.setFont(fHead)
        love.graphics.setColor(0.99, 0.86, 0.44, 1)
        love.graphics.printf("VISTA PREVIA BATALLA - ENCUENTRO #" .. Game.encounterIndex, prevX + 160, prevY + 18, prevW - 320, "center")

        love.graphics.setFont(fBody)
        love.graphics.setColor(0.96, 0.98, 1.0, 1)
        love.graphics.printf(activeEnc.name, prevX + 160, prevY + 46, prevW - 320, "center")

        love.graphics.setFont(fSmall)
        love.graphics.setColor(0.72, 0.84, 0.98, 1)
        local tag = (encPair and encPair.isPlaceholder) and "placeholder greybox" or "sprite real"
        love.graphics.printf(string.format("id: %s  |  bioma: %s  |  %s", activeEnc.id, activeEnc.biome, tag), prevX + 160, prevY + 72, prevW - 320, "center")
    else
        -- Explore Boot Preview proving --mode=explore --biome=...
        local bob = math.sin(Game.elapsed * 5.0) * 2
        if Game.assets.pudu and Game.assets.puduQuads then
            drawAssetFit(Game.assets.pudu.diff, Game.assets.puduQuads[3][animCol], prevX + 26, prevY + 16 + bob, 76, 76, 1.3)
        end
        if Game.assets.wizardHat then
            drawAssetFit(Game.assets.wizardHat.diff, nil, prevX + 42, prevY + 4 + bob * 1.2, 46, 36, 0.72)
        end

        local textX = prevX + 122
        local textW = prevW - 138

        love.graphics.setFont(fHead)
        love.graphics.setColor(0.62, 0.94, 0.72, 1)
        love.graphics.printf("PISTA BASE FASE 00 OPERATIVA - MODO EXPLORE", textX, prevY + 16, textW, "left")

        love.graphics.setFont(fBody)
        love.graphics.setColor(0.94, 0.97, 1.0, 1)
        love.graphics.printf(
            string.format("Bioma CLI: %s  |  9 encuentros listos en AssetLoader  |  Listo para Fase 01", Game.biome),
            textX, prevY + 44, textW, "left"
        )

        love.graphics.setFont(fSmall)
        love.graphics.setColor(0.74, 0.84, 0.96, 1)
        love.graphics.printf(
            "Drop-in Modo A: suelta PNGs en assets/ o assets/custom/<id>.png y pulsa [F5] para recargar en vivo.",
            textX, prevY + 72, textW, "left"
        )
    end

    local statsNow = love.graphics.getStats()
    Game.lastDrawCalls = statsNow.drawcalls or 0
end
