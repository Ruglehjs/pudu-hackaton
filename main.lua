-- Pudú Fantasy: mapa, encuentros y combate por prompts (LÖVE 11.5).

local AssetLoader = require("asset_loader")
local Audio = require("audio")
local Encounters = require("encounters")
local StageRenderer = require("stage_renderer")
local Shaders = require("shaders")
local BeatSync = require("beat_sync")
local BattleHUD = require("battle_hud")
local BattleFX = require("battle_fx")
local VictoryAlbum = require("victory_album")
local SpellRitual = require("spell_ritual")
local Judge = require("battle_judge")

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

local function easeOutCubic(t)
    local x = clamp(t or 0.0, 0.0, 1.0)
    local inv = 1.0 - x
    return 1.0 - inv * inv * inv
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
        autoPrompts = {},
        testRitual = nil,
        demoCombo = nil,
        demoFinale = nil,
        forceReaction = nil,
        transitionPreview = nil,
        battleEnterPreview = false,
        openDirector = false,
        openAlbum = false,
        disableGi = false,
        disableBloom = false,
        disableShake = false,
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
            if v then cli.autoPrompts[#cli.autoPrompts + 1] = v end

            if a:match("^%-%-test%-ritual$") then cli.testRitual = "arrows" end
            if a:match("^%-%-test%-ritual=bonus$") then cli.testRitual = "bonus" end

            v = a:match("^%-%-demo%-combo=(.+)$")
            if v then cli.demoCombo = v end
            v = a:match("^%-%-demo%-finale=(.+)$")
            if v then cli.demoFinale = v end

            v = a:match("^%-%-force%-reaction=(.+)$")
            if v and v ~= "" then cli.forceReaction = v end

            v = a:match("^%-%-transition%-preview=(%d+%.?%d*)$")
            if v then cli.transitionPreview = clamp(tonumber(v) or 0.0, 0.0, 1.0) end

            if a:match("^%-%-battle%-enter%-preview$") then cli.battleEnterPreview = true end
            if a:match("^%-%-open%-director$") then cli.openDirector = true end
            if a:match("^%-%-open%-album$") then cli.openAlbum = true end
            if a:match("^%-%-disable%-gi$") then cli.disableGi = true end
            if a:match("^%-%-disable%-bloom$") then cli.disableBloom = true end
            if a:match("^%-%-disable%-shake$") then cli.disableShake = true end
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
    nextRequestId = 0,

    -- Hero Overworld State
    puduU = 3.8,
    puduV = 0.0,
    puduFacingRow = 3, -- 3 = NE (diagonal up-right)
    puduWalkT = 0.0,
    puduAnimCol = 1,
    puduBobY = 0.0,
    puduMoving = false,

    -- Battle Arena & Dash-in State
    battlePhase = "player_turn",
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
        title = mk(26),
        heading = mk(17),
        body = mk(14),
        small = mk(12),
        combo = mk(28),
        damage = mk(20),
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

-- Each command follows the normal turn path, including setup, counter and KO.
local comboDemos = {
    combo_electro = { "charco", "rayo" },
    combo_deep_freeze = { "charco", "hielo" },
    combo_steam_sauna = { "escarcha", "secador" },
    combo_slip_slide = { "jabón", "plátano" },
    combo_fire_boom = { "aceite", "fósforo" },
    combo_chaos = { "oscuridad", "bocina" },
}
local demoAliases = { electro = "combo_electro", freeze = "combo_deep_freeze",
    steam = "combo_steam_sauna", slip = "combo_slip_slide", fire = "combo_fire_boom", chaos = "combo_chaos" }

local SPEECH_STYLE = {
    angry = "shout", crying = "cry", laughing = "laugh", confused = "think",
}

local function setSpeech(b, text, duration)
    b.speech = text
    Game.battleFX:setSpeechBubble("enemy", text, duration or 4.0, SPEECH_STYLE[Game.enemyReaction])
end

local function enemyFrame(enc, animate)
    local pair = Game.assets.encounters[enc.id]
    if not pair or not pair.diff then return nil, nil, 68, 148 end
    local row = pair.isSheet and pair.quads and (pair.quads[enc.sheetRow or 1] or pair.quads[0])
    if row and #row > 0 then
        local time = Game.battle.actorTime or 0
        local quad = row[animate and (math.floor(time * 5) % #row + 1) or 1]
        local _, _, w, h = quad:getViewport()
        return pair, quad, w, h
    end
    local w, h = pair.diff:getDimensions()
    return pair, nil, w, h
end

local function syncBattleFX(enc, anchors, w, h)
    local _, _, fw, fh = enemyFrame(enc, false)
    local enemyH = anchors.enemyScaleH * (enc.scale or 2.55) / 2.55
    local ex, ey = anchors.enemyX + (enc.offsetX or 0), anchors.enemyY + (enc.offsetY or 0)
    Game.battleFX:setViewport(w, h)
    Game.battleFX:setBattleAnchors(anchors.puduX, anchors.puduY, ex, ey, enemyH * fw / fh, enemyH)
    return ex, ey
end

local function beginBattle()
    local enc = Encounters.getByIndex(Game.encounterIndex)
    Game.stageStates = {}
    Game.ritual:cancel()
    Game.hud:closePrompt(true)
    Game.battleFX:clear()
    Game.enemyReaction = Game.cli.forceReaction or "idle"
    Game.battle = {
        hp = 100, enemyHp = enc.maxHp, turn = 1, spriteRequests = {}, reaction = "idle",
        nonCritMissCount = 0, pendingSemiHint = false,
    }
    setSpeech(Game.battle, enc.introLine, 5.2)
end

local function submitPrompt(prompt, preview, automated)
    local b = Game.battle
    if not b or Game.battlePhase ~= "player_turn" or not BattleHUD.canSubmit(prompt) then return false end
    local enc = Encounters.getByIndex(Game.encounterIndex)
    Game.nextRequestId = Game.nextRequestId + 1
    b.uid, b.prompt, b.preview, b.autoRitual = Game.nextRequestId, prompt, preview, automated
    b.decision, b.pendingSummon, b.anticipationLine = nil, nil, nil
    b.previewSpriteAt = nil
    setSpeech(b, nil, 0)
    Game.battleFX:clearTurn()
    Game.hud:closePrompt(true)
    Game.battlePhase = "ritual"
    Game.enemyReaction = Game.cli.forceReaction or "idle"
    Game.ritual:start(prompt)
    b.nextAutoArrowAt = Game.demo and 0.12 or 0.26
    local props = {}
    for i, prop in ipairs(Game.battleFX:getPersistentProps()) do props[i] = prop.key end
    b.request = {
        id = enc.id, name = enc.name, category = enc.category, situation = enc.situation,
        weaknesses = enc.weaknesses, hp = b.enemyHp, pudu_hp = b.hp, max_hp = enc.maxHp, turn = b.turn,
        current_reaction = b.reaction, active_props = props, stage_states = Game.stageStates,
    }
    Game.battleIn:push({
        cmd = "prompt", id = b.uid, uid = b.uid, prompt = prompt,
        mock_mode = Game.cli.mock or preview ~= nil or Game.demo ~= nil, encounter = b.request,
    })
    return true
end

local function rememberState(value)
    if value == "none" then return end
    for i, state in ipairs(Game.stageStates) do
        if state == value then table.remove(Game.stageStates, i) break end
    end
    table.insert(Game.stageStates, value)
    if #Game.stageStates > 3 then table.remove(Game.stageStates, 1) end
end

local function logTurn(b, damage)
    local message = b.decision
    local res = message.result
    print(string.format("[BATALLA] turno=%d rival=%s juez=%s ms=%d aprobado=%s resultado=%s estado=%s combo=%s daño=%d",
        b.turn, b.request.id, message.source, message.latency_ms or 0, tostring(res.approved),
        res.outcome_type, res.adds_stage_state, res.combo_triggered, damage))
    io.stdout:flush()
end

local function enterPlayerTurn()
    local b = Game.battle
    if b.pendingSemiHint then
        local enc = Encounters.getByIndex(Game.encounterIndex)
        setSpeech(b, enc.semiHintLine, 5.2)
        b.pendingSemiHint = false
    end
    Game.battlePhase = "player_turn"
    Game.hud:openPrompt()
    if Game.album:isOpen() then love.keyboard.setTextInput(false) end
end

local function acceptDecision(message)
    local b, res = Game.battle, message.result
    if not b or Game.battlePhase ~= "ritual" or b.uid ~= message.uid or b.decision
        or Game.transitionState == "to_explore" then return end
    b.decision = message
    if not res.approved then
        Game.ritual:cancel()
        Game.enemyReaction = Game.cli.forceReaction or b.reaction
        setSpeech(b, res.reject_reason)
        logTurn(b, 0)
        enterPlayerTurn()
        return
    end

    if b.preview ~= "arrows" then
        local anticipation = res.anticipation_line
        if res.is_critical or res.combo_triggered ~= "none" or res.outcome_type == "super_funny_ko" then
            Game.enemyReaction = Game.cli.forceReaction or "scared"
            if anticipation == "" then anticipation = "¡Espera... eso se ve muy malo!" end
        elseif res.outcome_type == "backfire" then
            Game.enemyReaction = Game.cli.forceReaction or "laughing"
            if anticipation == "" then anticipation = "¿En serio vas a invocar eso?" end
        end
        b.anticipationLine = anticipation
    end
    local key = res.existing_sprite ~= "none" and res.existing_sprite or res.summon_name
    local art = Game.assets.gags[key] or Game.assets.props[key]
    local sprite = { diff = art and art.diff, norm = art and art.norm, isPlaceholder = art and art.isPlaceholder }
    b.pendingSummon = { key = key, sprite = sprite }
    local needsLive = res.sprite_mode == "generate_live" and message.source ~= "lua" and not Game.cli.mock
    if b.preview == "bonus" then
        needsLive = true
        b.previewSpriteAt = Game.ritual.elapsed + 3.2
    elseif needsLive then
        b.spriteRequests[b.uid] = sprite
        Game.spriteIn:push({ cmd = "generate", uid = b.uid, name = res.summon_name, original_prompt = b.prompt,
            sprite_prompt = res.sprite_prompt, keep_purple = res.keep_purple, target_dim = 80 })
    end
    Game.ritual:setAiReady(res, needsLive)
end

local function applySummonImpactEffects(enc, anchors, ex, ey)
    local b, res = Game.battle, Game.battle.decision.result
    b.result = res
    rememberState(res.adds_stage_state)
    b.reaction = res.enemy_reaction
    Game.enemyReaction = Game.cli.forceReaction or b.reaction
    b.damage = b.impact.damage_to_enemy
    b.enemyHp = math.max(0, b.enemyHp - b.damage)
    b.hp = clamp(b.hp + b.impact.heal_pudu - res.damage_to_pudu, 0, 100)
    b.mood = res.pudu_reaction == "shocked" and "shocked" or (res.pudu_reaction == "angry" and "angry" or "happy")

    if res.is_critical then
        b.nonCritMissCount, b.pendingSemiHint = 0, false
    elseif res.outcome_type ~= "heal_pudu" then
        b.nonCritMissCount = b.nonCritMissCount + 1
        if b.nonCritMissCount >= 2 then
            b.pendingSemiHint, b.nonCritMissCount = true, 0
        end
    end

    setSpeech(b, res.enemy_speech)
    local fx = Game.battleFX
    fx:triggerImpact(b.impact, ex, ey, anchors.puduX, anchors.puduY, Game.audio)
    if res.combo_triggered ~= "none" then
        fx:triggerComboSpectacle(res.combo_triggered, res.combo_name, ex, ey, Game.audio)
    end
    if enc.id == "nino_helado" and (res.adds_stage_state == "mojado" or res.adds_stage_state == "caliente"
        or b.reaction == "crying" or b.reaction == "wet" or res.particle_fx == "rain" or res.particle_fx == "fire") then
        fx:addPersistentProp({ key = "melted_icecream", sprite = Game.assets.gags.melted_icecream,
            x = ex - 58, y = ey + 12, anchor = "ground_enemy" })
    end
end

local function endBattleTurn(enc, ex, ey, w)
    local b = Game.battle
    logTurn(b, b.damage)
    if b.enemyHp == 0 then
        Game.battlePhase = "victory"
        Game.toastText, Game.toastTimer = nil, 0
        setSpeech(b, enc.defeatLine)
        Game.defeatedMap[enc.id] = true
        Game.battleFX:startDefeatFinale(Game.enemyReaction, ex, ey)
        Game.battleFX:spawnParticles("confetti", w * 0.5, 100, 85)
        local res = b.result
        local saved = Game.album:recordVictory(enc.id, {
            prompt = b.prompt, summonName = res.summon_name,
            comboName = res.combo_triggered ~= "none" and res.combo_name or "",
            isCritical = res.is_critical, narrator = res.narrator_text, reaction = Game.enemyReaction, turns = b.turn,
        })
        if not saved then showToast("No se pudo guardar el álbum.", 3) end
        Game.audio:playTrack("victory")
    elseif b.hp == 0 then
        Game.battlePhase = "defeat"
        b.mood = "shocked"
    else
        enterPlayerTurn()
    end
    b.turn = b.turn + 1
end

local function decodeSprite(data)
    local bytes = love.data.decode("string", "base64", data)
    local image = love.graphics.newImage(love.filesystem.newFileData(bytes, "invocacion.png"))
    image:setFilter("nearest", "nearest")
    return image
end

local function acceptSprite(msg)
    local b = Game.battle
    if not b or Game.transitionState == "to_explore" then return end
    if b.uid == msg.uid and Game.battlePhase == "ritual" then Game.ritual:setSpriteReady() end
    local target = b.spriteRequests[msg.uid]
    b.spriteRequests[msg.uid] = nil
    if not target or not msg.ok then return end
    local art = msg.existing_sprite and (Game.assets.gags[msg.existing_sprite] or Game.assets.props[msg.existing_sprite])
    if art then
        target.diff, target.norm, target.isPlaceholder = art.diff, art.norm, art.isPlaceholder
        return
    end
    if not msg.diff_b64 then return end
    local ok, diff = pcall(decodeSprite, msg.diff_b64)
    if ok then
        target.diff, target.isPlaceholder = diff, false
        if msg.norm_b64 then
            local valid, norm = pcall(decodeSprite, msg.norm_b64)
            if valid then target.norm = norm end
        end
    end
end

local function pollWorkers()
    local msg = Game.battleOut:pop()
    while msg do
        if msg.kind == "prompt_result" then acceptDecision(msg) end
        msg = Game.battleOut:pop()
    end
    msg = Game.spriteOut:pop()
    while msg do
        if msg.kind == "sprite_ready" then acceptSprite(msg) end
        msg = Game.spriteOut:pop()
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
    beginBattle()

    if skipEnterDash then
        enterPlayerTurn()
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
    Game.ritual:cancel()
    Game.hud:closePrompt(true)
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
            Game.battle = nil
            love.keyboard.setTextInput(false)
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

local function getPuduRenderHeight(anchors, h)
    return anchors.puduScaleH * math.min(1, h / 720)
end

local function getOrbLift(anchors, h)
    -- The diagonal arena uses a larger foreground Pudú and a taller hat silhouette.
    return math.max(134, getPuduRenderHeight(anchors, h) * 1.27)
end

local function updateBattle(dt, realDt)
    local b = Game.battle
    local phase = Game.battlePhase
    local fx = Game.battleFX
    local w, h = love.graphics.getDimensions()
    local enc = Encounters.getByIndex(Game.encounterIndex)
    local anchors = StageRenderer.getBattleAnchors(w, h)
    local ex, ey = syncBattleFX(enc, anchors, w, h)
    if not fx:isHitStopped() then b.actorTime = (b.actorTime or 0) + dt end
    fx:update(dt)
    if phase == "battle_enter" then
        Game.battleEnterT = math.min(1.0, Game.battleEnterT + dt / BATTLE_ENTER_DURATION)
        if Game.battleEnterT >= 1.0 then
            enterPlayerTurn()
            Game.puduAnimMode = "battle_idle"
        end
        return
    end
    if phase == "ritual" then
        local ritual = Game.ritual
        if b.previewSpriteAt and ritual.elapsed >= b.previewSpriteAt then
            ritual:setSpriteReady()
            b.previewSpriteAt = nil
        end
        if b.autoRitual and ritual.elapsed >= b.nextAutoArrowAt then
            local arrow = ritual.sequence[ritual.cursor]
            if arrow then ritual:onKeyPressed(arrow.direction, Game.audio) end
            b.nextAutoArrowAt = b.nextAutoArrowAt + (Game.demo and 0.055 or 0.17)
        end
        ritual:update(realDt, Game.beatSync, anchors.puduX, anchors.puduY, getOrbLift(anchors, h))
        if ritual.readyToUnleash and not b.decision then
            local fallback = Judge.standaloneLuaEvaluate(b.prompt, b.request)
            acceptDecision({ uid = b.uid, result = fallback, source = "lua", latency_ms = math.floor(ritual.elapsed * 1000) })
        end
        if ritual:isComplete() then
            local summon = b.pendingSummon
            local res = b.decision.result
            local power = ritual:getMultiplier()
            local impact = {}
            for key, value in pairs(res) do impact[key] = value end
            impact.damage_to_enemy = math.floor(res.damage_to_enemy * power + 0.5)
            impact.heal_pudu = math.floor(res.heal_pudu * power + 0.5)
            b.impact = impact
            b.anticipationLine = nil
            fx:launchSummon(impact, summon.sprite, anchors.puduX, anchors.puduY, ex, ey, Game.audio, summon.key)
            Game.battlePhase = "summon"
        end
    elseif phase == "summon" then
        if fx:hasSummonArrived() then
            applySummonImpactEffects(enc, anchors, ex, ey)
            b.phaseTimer = 0.22
            Game.battlePhase = "impact_hold"
        end
    elseif phase == "impact_hold" or phase == "enemy_counter" then
        b.phaseTimer = b.phaseTimer - dt
        if phase == "enemy_counter" and b.phaseTimer <= 0.60 and b.speech ~= b.result.enemy_counter_line then
            setSpeech(b, b.result.enemy_counter_line)
        end
        if b.phaseTimer > 0 then return end
        if phase == "impact_hold" then
            if b.hp > 0 and b.enemyHp > 0 then
                b.phaseTimer = Game.demo and 0.35 or 1.15
                Game.battlePhase = "enemy_counter"
            else
                endBattleTurn(enc, ex, ey, w)
            end
        else
            b.hp = math.max(0, b.hp - b.result.enemy_counter_damage)
            if b.result.enemy_counter_damage > 0 then
                b.mood = "shocked"
                fx:spawnParticles(b.result.enemy_counter_fx, anchors.puduX, anchors.puduY - 75, 18)
                fx:spawnFloatingText("-" .. b.result.enemy_counter_damage, anchors.puduX + 68,
                    anchors.puduY - 115, { 1, 0.47, 0.40 })
            end
            endBattleTurn(enc, ex, ey, w)
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

local function drawEnemySprite(enc, x, y, targetH, groove, litShader, defeat)
    if not enc or not Game.assets then return end
    local g = groove or {}
    local d = defeat or {}
    local alpha = d.alpha or 1
    if alpha <= 0 then return end

    local ex = x + (enc.offsetX or 0.0) + (g.offsetX or 0.0) + (d.dx or 0)
    local ey = y + (enc.offsetY or 0.0)
    local dy = (g.offsetY or 0) + (d.dy or 0)
    local tilt = (g.tilt or 0) + (d.rot or 0)
    local sxMul = (g.scaleX or 1) * (d.scaleX or 1)
    local syMul = (g.scaleY or 1) * (d.scaleY or 1)

    -- Soft contact shadow beneath rival feet
    local airFrac = clamp(-dy / 22.0, 0.0, 1.0)
    local shScale = 1.0 - airFrac * 0.25
    love.graphics.setShader()
    love.graphics.setColor(0.03, 0.04, 0.08, 0.36 * (1.0 - airFrac * 0.25) * alpha)
    love.graphics.ellipse("fill", ex, ey + 4, 46 * shScale, 15 * shScale)

    local encPair, quad, fw, fh = enemyFrame(enc, not defeat)
    if encPair then
        local scaleFactor = (enc.scale or 2.55) / 2.55
        local sc = (targetH * scaleFactor) / math.max(1, fh)
        love.graphics.setColor(1, 1, 1, alpha)
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
            d.flashWhite or 0,
            nil,
            litShader,
            true
        )
    else
        local c = enc.color or { 0.88, 0.36, 0.36 }
        love.graphics.push()
        love.graphics.translate(ex, ey + dy)
        love.graphics.rotate(tilt)
        love.graphics.scale(sxMul, syMul)
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.ellipse("fill", 0, -targetH * 0.45, 34, targetH * 0.45)
        love.graphics.pop()
    end
end


local function getHudState(battleEnc)
    local b = Game.battle
    local audio = Game.audio:getStats()
    local state = {
        mode = Game.mode, battlePhase = b and Game.battlePhase or nil,
        musicOff = audio.muted or not audio.musicEnabled,
        toast = Game.toastText, elapsed = Game.elapsed,
        albumCount = Game.album:countUnlocked(), encounterCount = Encounters.count(),
    }
    if b then
        state.context, state.contextColor = battleEnc.name, battleEnc.color
        state.hp, state.enemyHp, state.enemyMaxHp = b.hp, b.enemyHp, battleEnc.maxHp
        state.stageStates, state.portraits, state.mood = Game.stageStates, Game.assets.portraits, b.mood
        state.speech, state.lastPrompt = b.speech, b.prompt
        state.enemyStatusTag = b.result and b.result.status_tag
        state.arrowsDone = Game.battlePhase == "ritual" and Game.ritual.cursor > #Game.ritual.sequence
        local res = b.decision and b.decision.result
        if res and res.approved then
            state.summonName = res.summon_name
            state.narrator = res.narrator_text
        end
    else
        local biome = Encounters.getBiome(StageRenderer.getBiomeAt(Game.puduU))
        local defeated = 0
        for _ in pairs(Game.defeatedMap) do defeated = defeated + 1 end
        state.context = ("%s (%d/%d)"):format(biome.name, defeated, Encounters.count())
        state.contextColor = biome.accentColor
    end
    return state
end

--------------------------------------------------------------------------------
-- LOVE Callbacks
--------------------------------------------------------------------------------

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")

    Game.cli = parseCliArgs(args)
    Game.mode = (Game.cli.testRitual or Game.cli.demoFinale) and "battle" or Game.cli.mode
    if Game.cli.demoCombo then
        local id = demoAliases[Game.cli.demoCombo] or Game.cli.demoCombo
        Game.demo = assert(comboDemos[id], "Combo desconocido: " .. id)
        Game.demoId, Game.mode = id, "battle"
    end
    Game.encounterIndex = Game.cli.encounter
    Game.fonts = loadFonts()
    Game.hud = BattleHUD.new(Game.fonts)
    Game.ritual = SpellRitual.new()
    Game.battleFX = BattleFX.new()
    Game.battleFX:setTypography(Game.fonts)
    Game.battleFX:setShakeEnabled(not Game.cli.disableShake)
    Game.album = VictoryAlbum.new()
    if Game.cli.openAlbum then Game.album:toggle() end
    Game.autoPromptIndex = 1

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
            Game.mode = "explore"
            syncMusicForMode()
        end
    elseif Game.mode == "battle" or Game.cli.battleEnterPreview then
        -- If --battle-enter-preview is passed with short --quit-after, seed enterT cleanly near mid-slide
        local seedT = Game.cli.battleEnterPreview and 0.22 or 0.0
        enterBattleArenaImmediate(Game.encounterIndex, (Game.demo ~= nil or Game.cli.testRitual ~= nil)
            and not Game.cli.battleEnterPreview, seedT)
    else
        syncMusicForMode()
    end

    Game.battleIn, Game.battleOut = love.thread.getChannel("battle_in"), love.thread.getChannel("battle_out")
    Game.spriteIn, Game.spriteOut = love.thread.getChannel("sprite_in"), love.thread.getChannel("sprite_out")
    Game.battleWorker = love.thread.newThread("battle_worker.lua")
    Game.spriteWorker = love.thread.newThread("sprite_worker.lua")
    Game.battleWorker:start()
    Game.spriteWorker:start()
    if not Game.cli.mock and not Game.demo and not Game.cli.testRitual then
        Game.battleIn:push({ cmd = "health" })
    end
    Game.ritualPreview = Game.cli.testRitual
    love.keyboard.setKeyRepeat(true)
end

function love.resize(w, h)
    ensureWorldCanvas(w, h)
end

function love.update(dt)
    local safeDt = math.min(dt, 0.05)
    Game.elapsed = Game.elapsed + safeDt
    Game.cliElapsed = Game.cliElapsed + dt
    pollWorkers()
    local b = Game.battle
    if b and Game.battlePhase == "player_turn" and Game.transitionState == "none" and not Game.transitionPreview
        and not Game.album:isOpen() then
        if Game.ritualPreview then
            local preview = Game.ritualPreview
            Game.ritualPreview = nil
            local prompt = preview == "bonus" and "ornitorrinco dj" or "chispa mágica"
            submitPrompt(prompt, preview, preview == "bonus")
        elseif Game.demo then
            local prompt = Game.demo[b.turn]
            if prompt then submitPrompt(prompt, nil, true) end
        elseif Game.cli.demoFinale then
            local w, h = love.graphics.getDimensions()
            local enc = Encounters.getByIndex(Game.encounterIndex)
            local ex, ey = syncBattleFX(enc, StageRenderer.getBattleAnchors(w, h), w, h)
            Game.battlePhase, Game.enemyReaction = "victory", Game.cli.demoFinale
            b.enemyHp = 0
            setSpeech(b, enc.defeatLine)
            Game.hud:closePrompt(true)
            Game.battleFX:startDefeatFinale(Game.enemyReaction, ex, ey)
        else
            local prompt = Game.cli.autoPrompts[Game.autoPromptIndex]
            if prompt then
                Game.autoPromptIndex = Game.autoPromptIndex + 1
                submitPrompt(prompt, nil, true)
            end
        end
    end

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
            if not Game.album:isOpen() then updateExplore(safeDt) end
        elseif Game.mode == "battle" then
            if not Game.album:isOpen() then updateBattle(safeDt, dt) end
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
        if Game.demo and (not b or not b.result or b.result.combo_triggered ~= Game.demoId) then
            error("La secuencia no completó " .. Game.demoId)
        end
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

local function promptAvailable()
    return Game.mode == "battle" and Game.battlePhase == "player_turn"
        and Game.transitionState == "none" and Game.transitionPreview == nil and not Game.album:isOpen()
end

function love.textinput(text)
    if Game.ignoreAlbumText and text:lower() == "j" then return end
    if promptAvailable() then
        if Game.ignorePromptSlash and text == "/" then
            Game.ignorePromptSlash = false
            return
        end
        Game.hud:addText(text)
    end
end

function love.keyreleased(key)
    if key == "j" then Game.ignoreAlbumText = false end
end

local function toggleAlbum()
    local open = Game.album:toggle()
    love.keyboard.setTextInput(not open and Game.hud.promptOpen)
end

local function routeHudAction(action)
    if action == "music" then
        local enabled = Game.audio:toggleMusic()
        showToast(enabled and "Música activada" or "Música desactivada", 1.8)
    elseif action == "map" then
        if Game.mode == "battle" then triggerReturnToExplore()
        else triggerEncounterTransition(findNearestEncounterIndex(true)) end
    elseif action == "retry" and (Game.battlePhase == "victory" or Game.battlePhase == "defeat") then
        enterBattleArenaImmediate(Game.encounterIndex, false, 0)
    elseif action == "album" then
        toggleAlbum()
    elseif action == "prompt" and promptAvailable() then
        Game.hud:openPrompt()
    elseif action == "conjure" and promptAvailable() then
        submitPrompt(Game.hud.input)
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if Game.album:isOpen() then
        local w, h = love.graphics.getDimensions()
        local action, index = Game.album:hitTest(x, y, w, h)
        if action == "close" or not Game.album:containsPoint(x, y, w, h) then
            toggleAlbum()
        elseif action == "clear" then
            if not Game.album:clear() then showToast("No se pudo guardar el álbum.", 3) end
        elseif action == "card" then
            Game.album:close()
            Game.transitionState, Game.transitionTimer, Game.transitionPreview = "none", 0, nil
            enterBattleArenaImmediate(index, false)
        end
        return
    end
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then return end
    routeHudAction(Game.hud:hitTest(x, y))
end

function love.keypressed(key, scancode, isrepeat)
    if key == "escape" and isrepeat then return end
    Game.ignorePromptSlash = false
    if key == "f5" then
        reloadAssets(true)
        return
    elseif key == "f8" or (key == "m" and Game.mode == "explore") then
        if Game.audio then
            local muted = Game.audio:toggleMute()
            showToast(muted and "Audio silenciado" or "Audio activado", 1.8)
        end
        return
    elseif key == "f7" or (key == "l" and Game.mode == "explore") then
        local _, preset = Game.stage:cycleLightingPreset()
        showToast("Iluminación: " .. ((preset and preset.label) or "Día"), 1.8)
        return
    elseif key == "f12" then
        local out = string.format("screenshots/manual_%d.png", os.time())
        saveScreenshotTo(out)
        showToast("Captura guardada: " .. out, 2.2)
        return
    end

    if Game.album:isOpen() then
        if key == "escape" or key == "j" and not isrepeat then
            Game.ignoreAlbumText = key == "j"
            toggleAlbum()
        end
        return
    end
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then return end
    if key == "j" and (not Game.hud.promptOpen or Game.hud.input == ""
        or love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")) then
        Game.ignoreAlbumText = true
        if not isrepeat then toggleAlbum() end
        return
    end
    if Game.battlePhase == "ritual" and not isrepeat and Game.ritual:onKeyPressed(key, Game.audio) then return end

    local b = Game.battle
    local num = Game.mode == "battle" and tonumber(key)
    if not isrepeat and num and num >= 1 and num <= Encounters.count()
        and love.keyboard.isDown("lctrl", "rctrl") then
        enterBattleArenaImmediate(num, false, 0.0)
        return
    end
    if b and (key == "return" or key == "kpenter") and not isrepeat then
        if Game.battlePhase == "victory" or Game.battlePhase == "defeat" then
            triggerReturnToExplore()
        elseif promptAvailable() then
            if Game.hud.promptOpen then submitPrompt(Game.hud.input)
            else Game.hud:openPrompt() end
        end
    elseif promptAvailable() and key == "/" and not isrepeat and not Game.hud.promptOpen then
        Game.hud:openPrompt()
        Game.ignorePromptSlash = true
    elseif promptAvailable() and key == "backspace" then
        Game.hud:backspace()
    elseif promptAvailable() and key == "v" and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then
        Game.hud:addText(love.system.getClipboardText() or "")
    elseif key == "tab" and not isrepeat then
        routeHudAction("map")
    elseif key == "escape" then
        if Game.mode == "battle" then triggerReturnToExplore()
        else love.event.quit(0) end
    end
end

function love.draw()
    Game.framesDrawn = Game.framesDrawn + 1
    local w, h = love.graphics.getDimensions()
    local canvas = ensureWorldCanvas(w, h)

    local battleEnc = nil
    local battleTheme = nil
    local battleAnchors, defeatTransform
    local fx = Game.battleFX
    local puduEnterOffX, puduEnterOffY = 0.0, 0.0
    local enemyEnterOffX, enemyEnterOffY = 0.0, 0.0

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
        local lights = {}
        if Game.battlePhase == "ritual" then
            Game.ritual:collectLights(lights)
        end
        fx:collectLights(lights)
        for _, light in ipairs(Game.stage:collectBattleLights(battleEnc, w, h, Game.elapsed)) do
            lights[#lights + 1] = light
        end
        local litShader = Game.stage:configureLitShader(battleTheme, w, h, Game.elapsed, lights)
        local beatPulse = Game.beatSync and Game.beatSync:getBeatPulse() or 0.0

        -- Classic Pokémon diagonal entrance slide:
        -- Pudú + foreground pad enter from bottom-left; Rival + upper-right pad enter from right
        if Game.battlePhase == "battle_enter" then
            local rem = 1.0 - easeOutCubic(Game.battleEnterT)
            puduEnterOffX = -rem * 360.0
            puduEnterOffY = rem * 68.0
            enemyEnterOffX = rem * 380.0
            enemyEnterOffY = -rem * 26.0
        end

        local enterOffsets = {
            puduOffX = puduEnterOffX,
            puduOffY = puduEnterOffY,
            enemyOffX = enemyEnterOffX,
            enemyOffY = enemyEnterOffY,
            enterT = (Game.battlePhase == "battle_enter") and Game.battleEnterT or 1.0,
        }

        battleAnchors = Game.stage:drawBattleArena(
            battleEnc,
            Encounters.STAGE_THEMES,
            Game.assets,
            beatPulse,
            w,
            h,
            Game.elapsed,
            litShader,
            enterOffsets
        )

        -- Face 3/4 back-right (row 3 = NE) looking diagonally up-right toward the Rival!
        local b = Game.battle
        if not fx:isHitStopped() then
            b.puduPose = Game.beatSync:getPuduDancePose(Game.puduAnimMode, 3)
            b.enemyGroove = Game.beatSync:getEnemyGroove(Game.enemyReaction)
        end
        if Game.battlePhase == "victory" then defeatTransform = fx:getDefeatTransform() end

        fx:drawBackLayer()
        if Game.battlePhase == "ritual" then
            Game.ritual:drawCircle(battleAnchors.puduX, math.min(battleAnchors.puduY, h - 81))
        end

        -- Draw upper-right Rival first (background depth), then foreground bottom-left Pudú (cropped cleanly behind bottom strip)
        love.graphics.push()
        love.graphics.translate(fx:getShakeOffset())
        drawEnemySprite(
            battleEnc,
            battleAnchors.enemyX + enemyEnterOffX,
            battleAnchors.enemyY + enemyEnterOffY,
            battleAnchors.enemyScaleH or 148.0,
            not defeatTransform and b.enemyGroove or nil,
            litShader,
            defeatTransform
        )
        drawPuduSprite(
            battleAnchors.puduX + puduEnterOffX,
            battleAnchors.puduY + puduEnterOffY,
            getPuduRenderHeight(battleAnchors, h),
            b.puduPose,
            litShader
        )
        love.graphics.pop()

        Game.stage:drawBattleArenaForeground(battleEnc, Game.assets, w, h, Game.elapsed, litShader)
        fx:drawSummonsAndProps(litShader, function(pair, x, y, angle, sx, sy, ox, oy, shader)
            Game.stage:drawSpriteLit(pair, x, y, angle, sx, sy, ox, oy, nil, 0, nil, shader, true)
        end)
        if Game.battlePhase ~= "battle_enter" and Game.battlePhase ~= "ritual" then
            local ex = battleAnchors.enemyX + (battleEnc.offsetX or 0)
            local ey = battleAnchors.enemyY + (battleEnc.offsetY or 0)
            fx:drawReactionOverlay(Game.enemyReaction, ex, ey, Game.elapsed)
        end
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

    local hudState = getHudState(battleEnc)
    Game.hud:drawTopBar(hudState, w)
    if Game.mode == "explore" then
        Game.stage:drawOverworldMinimap(
            Game.puduU,
            Game.puduV,
            Encounters.LIST,
            Game.defeatedMap,
            w,
            h,
            Game.fonts.small
        )
        Game.hud:drawExploreBar(w, h)
    else
        local b, phase = Game.battle, Game.battlePhase
        local ex = battleAnchors.enemyX + (battleEnc.offsetX or 0) + enemyEnterOffX
        local ey = battleAnchors.enemyY + (battleEnc.offsetY or 0) + enemyEnterOffY
        local px, py = battleAnchors.puduX, battleAnchors.puduY
        if phase == "ritual" then
            Game.hud:drawAnticipation(b.anticipationLine, w, ex)
            Game.ritual:draw(w, h, px, py, Game.fonts, Game.beatSync, getOrbLift(battleAnchors, h))
        elseif phase ~= "battle_enter" and phase ~= "victory" and phase ~= "defeat" then
            fx:drawFrontParticles(Game.fonts, px, py, ex, ey)
            fx:drawSpeechBubbles(px, py, ex, ey, Game.fonts)
        else
            fx:drawFrontParticles(Game.fonts)
        end
        local enemyVisible = not defeatTransform or (defeatTransform.alpha >= 0.15 and defeatTransform.dx <= 180)
        if enemyVisible and (phase ~= "battle_enter" or Game.battleEnterT >= 0.88) then
            Game.hud:drawRivalStageBar(hudState, ex, ey, w)
        end
        Game.hud:drawBattleStrip(hudState, w, h)
        Game.hud:drawVictoryOrDefeat(hudState, w, h)
    end

    -- 4. JRPG Battle Transition Overlay (live or --transition-preview)
    if Game.transitionPreview ~= nil then
        Game.stage:drawBattleTransition(Game.transitionPreview, w, h)
    elseif Game.transitionState == "to_battle" then
        Game.stage:drawBattleTransition(Game.transitionTimer / TO_BATTLE_DURATION, w, h)
    elseif Game.transitionState == "to_explore" then
        Game.stage:drawBattleTransition(Game.transitionTimer / TO_EXPLORE_DURATION, w, h)
    end
    Game.album:draw(Encounters.LIST, Game.assets.encounters, Game.fonts, w, h)

    local statsNow = love.graphics.getStats()
    Game.lastDrawCalls = statsNow.drawcalls or 0
end

function love.quit()
    if Game.battleIn then Game.battleIn:clear(); Game.battleIn:push({cmd="quit"}) end
    if Game.spriteIn then Game.spriteIn:clear(); Game.spriteIn:push({cmd="quit"}) end
end
