-- Pudú Fantasy: mapa, encuentros y combate por prompts (LÖVE 11.5).

local AssetLoader = require("asset_loader")
local Audio = require("audio")
local Encounters = require("encounters")
local StageRenderer = require("stage_renderer")
local DesertArrival = require("desert_arrival")
local Shaders = require("shaders")
local BeatSync = require("beat_sync")
local BattleHUD = require("battle_hud")
local BattleFX = require("battle_fx")
local BattleScores = require("battle_scores")
local SpellRitual = require("spell_ritual")
local Judge = require("battle_judge")
local AdventureScreen = require("adventure_screen")

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
            if v == "explore" or v == "battle" then
                cli.mode, cli.modeExplicit = v, true
            end

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

            v = a:match("^%-%-screenshot%-phase=([%a_]+)$")
            if v then cli.screenshotPhase = v end

            if a:match("^%-%-qa%-no%-save$") then cli.qaNoSave = true end

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
local VERSUS_DURATION = 1.22
local VERSUS_IMPACT_AT = 0.36
local BATTLE_ENTER_DURATION = 0.88
local VICTORY_FINALE_TIME = 1.0
local FINAL_VICTORY_HOLD = 4.0
local PORTAL_DURATION = 2.0
local COUNTER_ATTACK_TIME = 0.44
local BATTLE_ENTER_SLIDE_PX = 320.0
local ENCOUNTER_TRIGGER_DIST = 1.75
local ENCOUNTER_SHORTCUT_DIST = 4.0
local WALK_SPEED = 6.2
local WALK_ACCELERATION = 32.0
local WALK_BRAKING = 42.0
local WALK_FRAME_DISTANCE = 0.58
local COMPLETO = StageRenderer.COMPLETO

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
    puduWalkT = 1.0,
    puduVelocityU = 0.0,
    puduVelocityV = 0.0,
    puduWalkWeight = 0.0,

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
    local storyPath = "assets/fonts/CormorantGaramond-SemiBold.ttf"
    local hasFont = love.filesystem.getInfo(fontPath) ~= nil
    local function mk(size)
        if hasFont then
            local ok, f = pcall(love.graphics.newFont, fontPath, size)
            if ok and f then return f end
        end
        return love.graphics.newFont(size)
    end
    local story, victoryTitle
    if love.filesystem.getInfo(storyPath) then
        local ok, font = pcall(love.graphics.newFont, storyPath, 23)
        if ok then story = font end
        local titleOk, titleFont = pcall(love.graphics.newFont, storyPath, 62)
        if titleOk then victoryTitle = titleFont end
    end
    return {
        title = mk(26),
        heading = mk(17),
        body = mk(14),
        small = mk(12),
        combo = mk(28),
        damage = mk(20),
        story = story,
        victoryTitle = victoryTitle,
        versus = mk(56),
        versusName = mk(32),
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

local function syncExploreBiomeMusic(forceResetBeat)
    if not Game.audio then return end
    local biomeId = StageRenderer.getBiomeAt(Game.puduU or 0)
    local trackId = Audio.getBiomeTrackId(biomeId)
    local changed = (Game.audio.currentTrackId ~= trackId)
    if changed or forceResetBeat then
        Game.audio:playTrack(trackId, false)
        if Game.beatSync and (changed or forceResetBeat) then
            local ts = Game.audio.getTrackState and Game.audio:getTrackState()
            Game.beatSync:reset((ts and ts.bpm) or 116.0)
        end
    end
end

local function syncMusicForMode()
    if not Game.audio then return end
    if Game.mode == "battle" then
        local enc = Encounters.getByIndex(Game.encounterIndex)
        local trackId = (enc and enc.track) or "user_battle"
        if not Game.audio:playTrack(trackId, false) then
            Game.audio:playTrack("user_battle", false)
        end
        if Game.beatSync then
            local ts = Game.audio.getTrackState and Game.audio:getTrackState()
            Game.beatSync:reset((ts and ts.bpm) or 138.0)
        end
    else
        syncExploreBiomeMusic(true)
    end
end

local function createStage()
    local stage = StageRenderer.new()
    stage:setShaders(Game.shaders)
    stage:setLightingPreset(Game.cli.lighting)
    stage:setBloomEnabled(not Game.cli.disableBloom)
    stage:buildOverworldDecor(Game.overworldEncounters)
    return stage
end

-- Each command follows the normal turn path, including setup, counter and KO.
local comboDemos = {
    combo_electro = { "charco", "rayo" },
    combo_deep_freeze = { "charco", "hielo" },
    combo_steam_sauna = { "escarcha", "secador" },
    combo_slip_slide = { "espuma", "plátano" },
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

local function rivalIsAttacking(phase, battle)
    return phase == "enemy_counter" and battle.phaseTimer <= COUNTER_ATTACK_TIME
end

local function enemyFrame(enc, facingRow, animate)
    local pair = Game.assets.encounters[enc.id]
    if not pair or not pair.diff then return nil, nil, 68, 148 end
    if pair.frameW then
        local phase = Game.battlePhase
        local poseName = "idle"
        if phase == "enemy_counter" then
            poseName = rivalIsAttacking(phase, Game.battle) and "attack" or "charge"
        elseif phase == "ritual" or phase == "summon" then
            poseName = "charge"
        end
        local pose = pair.poses and pair.poses[poseName] or pair
        return pose, pose.quads[facingRow][1], pose.frameW, pose.frameH, pair.companion
    end
    local row = pair.isSheet and pair.quads and (pair.quads[enc.sheetRow or 1] or pair.quads[0])
    if row and #row > 0 then
        local time = Game.battle.actorTime or 0
        local quad = row[animate and (math.floor(time * 5) % #row + 1) or 1]
        local _, _, w, h = quad:getViewport()
        return pair, quad, w, h, pair.companion
    end
    local w, h = pair.diff:getDimensions()
    return pair, nil, w, h, pair.companion
end

local function syncBattleFX(enc, anchors, w, h)
    local _, _, fw, fh = enemyFrame(enc, anchors.enemyFacingRow, false)
    local enemyH = anchors.enemyScaleH * (enc.scale or 2.55) / 2.55
    local ex, ey = anchors.enemyX + (enc.offsetX or 0), anchors.enemyY + (enc.offsetY or 0)
    Game.battleFX:setViewport(w, h)
    Game.battleFX:setBattleAnchors(anchors.puduX, anchors.puduY, ex, ey, enemyH * fw / fh, enemyH)
    return ex, ey
end

local function beginBattle()
    local enc = Encounters.getByIndex(Game.encounterIndex)
    local enemyHp = enc.maxHp
    if Game.completoBonusPending then
        enemyHp = math.floor(enemyHp / 2)
        Game.completoBonusPending = false
    end
    Game.stageStates = {}
    Game.ritual:cancel()
    Game.hud:closePrompt(true)
    Game.battleFX:clear()
    Game.enemyReaction = Game.cli.forceReaction or "idle"
    Game.battle = {
        hp = 100, enemyHp = enemyHp, turn = 1, reaction = "idle",
        nonCritMissCount = 0, pendingSemiHint = false, score = BattleScores.new(),
    }
    setSpeech(Game.battle, enc.introLine, 5.2)
end

local function submitPrompt(prompt, preview, automated)
    local b = Game.battle
    prompt = BattleHUD.limitPrompt(prompt)
    if not b or Game.battlePhase ~= "player_turn" or not BattleHUD.canSubmit(prompt) then return false end
    local enc = Encounters.getByIndex(Game.encounterIndex)
    Game.nextRequestId = Game.nextRequestId + 1
    b.uid, b.prompt, b.preview, b.autoRitual = Game.nextRequestId, prompt, preview, automated
    b.decision, b.pendingSummon, b.anticipationLine = nil, nil, nil
    b.previewSpriteAt, b.spriteDeadline = nil, nil
    setSpeech(b, nil, 0)
    Game.battleFX:clearTurn()
    Game.hud:closePrompt(true)
    Game.battlePhase = "ritual"
    Game.enemyReaction = Game.cli.forceReaction or "idle"
    Game.ritual:start(prompt)
    if Game.audio then Game.audio:play("sfx_prompt_submit", 0.68) end
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
end

local function acceptDecision(message)
    local b, res = Game.battle, message.result
    if not b or Game.battlePhase ~= "ritual" or b.uid ~= message.uid or b.decision
        or Game.transitionState == "to_explore" then return end
    b.decision = message
    if not res.approved then
        Game.ritual:cancel()
        if Game.audio then Game.audio:play("sfx_prompt_reject", 0.75) end
        Game.enemyReaction = Game.cli.forceReaction or b.reaction
        setSpeech(b, res.reject_reason)
        logTurn(b, 0)
        enterPlayerTurn()
        return
    end

    if b.preview ~= "arrows" or res.is_critical then
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
    local needsLive = message.live_sprite == true
    local art = not needsLive and (Game.assets.gags[key] or Game.assets.props[key])
    local sprite = { diff = art and art.diff, norm = art and art.norm, isPlaceholder = art and art.isPlaceholder }
    b.pendingSummon = { key = key, sprite = sprite }
    if b.preview == "bonus" then
        needsLive = true
        b.previewSpriteAt = Game.ritual.elapsed + 3.2
    elseif needsLive then
        b.spriteDeadline = Game.ritual.elapsed + 29
        Game.spriteIn:push({ cmd = "generate", uid = b.uid, name = res.summon_name, original_prompt = b.prompt })
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
    BattleScores.addTurn(b.score, Game.ritual, b.promptPoints)
    local reward = ("+%d pts de ritual  |  +%d pts de prompt"):format(
        Game.ritual.arrowPoints, b.promptPoints)
    if b.precisionBonus > 0 then
        reward = reward .. ("  |  +%d%% de daño por precisión"):format(b.precisionBonus)
    end
    showToast(reward, 3.2)
    if b.damage > 0 then b.rivalHitTimer = 0.46 end
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

local function campaignWins()
    local wins = 0
    for _, enc in ipairs(Encounters.LIST) do
        if Game.defeatedMap[enc.id] then wins = wins + 1 end
    end
    return wins
end

local function startVictory(enc, ex, ey, w)
    local b = Game.battle
    Game.battlePhase, b.victoryAt = "victory", Game.elapsed
    b.campaignComplete = enc.finalBoss and campaignWins() == #Encounters.LIST
    Game.hud:closePrompt(true)
    setSpeech(b, enc.defeatLine)
    Game.battleFX:startDefeatFinale(Game.enemyReaction, ex, ey, Game.audio)
    Game.battleFX:spawnParticles("confetti", w * 0.5, 100, 85)
    if Game.audio then Game.audio:playTrack("victory", true) end
end

local function endBattleTurn(enc, ex, ey, w)
    local b = Game.battle
    logTurn(b, b.damage)
    if b.enemyHp == 0 then
        if enc.restorationLine and not Game.defeatedMap[enc.id] then
            Game.stage:queueRestoration(enc)
        end
        Game.defeatedMap[enc.id] = true
        startVictory(enc, ex, ey, w)
    elseif b.hp == 0 then
        Game.battlePhase = "defeat"
        b.mood = "shocked"
        if Game.audio then Game.audio:playTrack("defeat", true) end
    else
        enterPlayerTurn()
    end
    if (b.enemyHp == 0 or b.hp == 0) and Game.scoreHistory and not Game.demo and not Game.cli.demoFinale
        and not Game.cli.testRitual and #Game.cli.autoPrompts == 0 then
        local saved, err = BattleScores.record(love.filesystem, Game.scoreHistory, b.score, enc.name, b.enemyHp == 0)
        Game.scoreSaveFailed = not saved
        if not saved then io.stderr:write("[PUDU FANTASY WARN] Puntajes: " .. tostring(err) .. "\n") end
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
    if not b or b.uid ~= msg.uid or not b.spriteDeadline or Game.battlePhase ~= "ritual"
        or Game.transitionState == "to_explore" then return end
    b.spriteDeadline = nil
    local valid, diff, norm
    if msg.ok then
        valid, diff, norm = pcall(function()
            return decodeSprite(msg.diff_b64), decodeSprite(msg.norm_b64)
        end)
        valid = valid and diff:getWidth() == 80 and diff:getHeight() == 80
            and norm:getWidth() == 80 and norm:getHeight() == 80
    end
    if valid then
        local target = b.pendingSummon.sprite
        target.diff, target.norm, target.isPlaceholder, target.generated = diff, norm, false, true
        Game.ritual:setSpriteReady()
        print(("[SPRITE] listo prompt=%q tamaño=80x80 caché=%s ms=%d"):format(
            b.prompt, tostring(msg.cached), msg.latency_ms))
        io.stdout:flush()
    else
        io.stderr:write("[SPRITE] " .. (msg.error or "Textura inválida.") .. "\n")
        b.decision, b.pendingSummon, b.anticipationLine = nil, nil, nil
        Game.ritual:cancel()
        Game.enemyReaction = Game.cli.forceReaction or b.reaction
        enterPlayerTurn()
        Game.hud:addText(b.prompt)
        showToast("No se generó la invocación. Intenta de nuevo.", 3.6)
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
    local overrides = not Game.cli.qaNoSave and Encounters.loadOverrides(AssetLoader.getExternalBaseDir())
    if overrides then
        Encounters.applyOverrides(overrides)
    end
    Game.assets = AssetLoader.loadAll(Encounters.SELECTABLE)
    if isHotReload then
        Game.stage:buildOverworldDecor(Game.overworldEncounters)
        if Game.audio and Game.audio.reload then
            Game.audio:reload()
            if Game.beatSync and Game.audio.getTrackState then
                local ts = Game.audio:getTrackState()
                Game.beatSync:reset((ts and ts.bpm) or 120.0)
            end
        end
        Game.reloadCount = Game.reloadCount + 1
        local s = Game.assets.stats
        showToast(string.format("Hot-Reload #%d listo (%d reales / %d greybox)", Game.reloadCount, s.realCount, s.placeholderCount), 2.4)
    end
end

--------------------------------------------------------------------------------
-- Overworld Navigation & Battle Entry Helpers
--------------------------------------------------------------------------------

local function stopPuduMovement()
    Game.puduVelocityU, Game.puduVelocityV = 0.0, 0.0
    Game.puduWalkWeight = 0.0
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

local function distanceSquaredFromPudu(point)
    local du, dv = point.u - Game.puduU, point.v - Game.puduV
    return du * du + dv * dv
end

local function nextOverworldEncounter()
    local nearest, nearestDistance = nil, math.huge
    for _, enc in ipairs(Game.overworldEncounters or Encounters.LIST) do
        if not Game.defeatedMap[enc.id] then
            if not Game.qaExplore then return enc end
            local distance = distanceSquaredFromPudu(enc)
            if distance < nearestDistance then
                nearest, nearestDistance = enc, distance
            end
        end
    end
    return nearest
end

local function startVersus()
    Game.battlePhase = "versus"
    Game.battle.versusTime = 0
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
    elseif initialEnterT ~= nil then
        Game.battlePhase = "battle_enter"
        Game.battleEnterT = clamp(initialEnterT, 0.0, 0.99)
        Game.puduAnimMode = "battle_enter"
    else
        startVersus()
    end

    Game.enemyReaction = (Game.cli and Game.cli.forceReaction) or "idle"

    if Game.audio then
        local enc = Encounters.getByIndex(targetIdx)
        local trackId = (enc and enc.track) or "user_battle"
        if not Game.audio:playTrack(trackId, false) then
            Game.audio:playTrack("user_battle", false)
        end
        if not skipEnterDash then
            Game.audio:play("sfx_battle_enter", 0.75)
        end
    end
    if Game.beatSync then
        local ts = Game.audio and Game.audio.getTrackState and Game.audio:getTrackState()
        Game.beatSync:reset((ts and ts.bpm) or 138.0)
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

    stopPuduMovement()
    Game.encounterIndex = idx
    Game.alertEncounterIdx = idx
    Game.transitionState = "alert"
    Game.transitionTimer = 0.0
    Game.transitionSwitched = false
    if Game.audio then
        Game.audio:play("sfx_encounter_start", 0.90)
    end
end

local function startPortal()
    Game.battlePhase = "portal"
    Game.battle.portalElapsed = 0
    Game.audio:play("chime_3", 0.75)
end

local function triggerReturnToExplore()
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then
        return
    end
    if Game.battle and Game.battle.campaignComplete then
        if Game.battlePhase == "victory" and Game.elapsed - Game.battle.victoryAt >= VICTORY_FINALE_TIME then
            startPortal()
        end
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
            startVersus()
        end
    elseif Game.transitionState == "to_explore" then
        Game.transitionTimer = Game.transitionTimer + dt
        local p = Game.transitionTimer / TO_EXPLORE_DURATION
        if p >= 0.50 and not Game.transitionSwitched then
            local enc = Encounters.getByIndex(Game.encounterIndex)
            Game.mode = "explore"
            Game.battle = nil
            love.keyboard.setTextInput(false)
            Game.alertEncounterIdx = nil
            Game.transitionSwitched = true
            if distanceSquaredFromPudu(enc) < 2.4 ^ 2
                or (not Game.qaExplore and enc == nextOverworldEncounter() and Game.puduU >= enc.u) then
                Game.puduU, Game.puduV = findSafeSpotNearEncounter(enc, -2.6)
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

local function updateDesertArrival(dt)
    local arrival = Game.desertArrival
    local prevElapsed = arrival.elapsed
    local finished = arrival:update(dt)
    if Game.audio then
        if prevElapsed < 0.32 and arrival.elapsed >= 0.32 then
            Game.audio:play("sfx_truck_jump", 0.72)
        elseif prevElapsed < 0.88 and arrival.elapsed >= 0.88 then
            Game.audio:play("sfx_truck_land", 0.72)
        end
    end
    Game.puduU, Game.puduV = arrival.u, arrival.v
    Game.puduFacingRow = arrival.facingRow
    if finished then Game.desertArrival = nil end
end

local function resetCampaign()
    Game.mode, Game.battle, Game.battlePhase = "explore", nil, "player_turn"
    Game.encounterIndex, Game.enemyReaction, Game.autoPromptIndex = 1, "idle", 1
    Game.battleEnterT, Game.puduAnimMode = 1.0, "battle_idle"
    Game.defeatedMap, Game.stageStates = {}, {}
    Game.qaExplore, Game.overworldEncounters = false, Encounters.LIST
    Game.transitionState, Game.transitionTimer, Game.transitionSwitched = "none", 0, false
    Game.alertEncounterIdx, Game.encounterCooldown, Game.transitionPreview = nil, 0, nil
    Game.toastText, Game.toastTimer = nil, 0
    Game.completoPickedAt, Game.completoBonusPending = nil, nil
    Game.scorePage, Game.lastStepBucket, Game.wasCameraPanning = nil, nil, nil
    Game.ritual:cancel()
    Game.battleFX:clear()
    Game.hud:closePrompt(true)
    Game.hud.hits = {}
    stopPuduMovement()
    Game.stage = createStage()
    Game.puduU = Encounters.getBiome("desierto").spawnU
    Game.puduV = StageRenderer.pathCenterV(Game.puduU)
    Game.puduFacingRow, Game.puduWalkT = 3, 1.0
    Game.stage:snapCameraToChunk(Game.puduU, Game.puduV)
    Game.desertArrival = DesertArrival.new(StageRenderer.DESERT_ARRIVAL, Game.puduU, Game.puduV)
    updateDesertArrival(0)
end

local function finishCinematic()
    Game.adventureScreen:stop()
    if Game.screen == "intro" then
        Game.screen = nil
        syncMusicForMode()
    else
        Game.screen = "complete"
    end
end

local function playCinematic(kind)
    Game.audio:stopAll()
    Game.screen = kind
    if not Game.adventureScreen:play(kind, Game.audio:getStats().muted) then
        finishCinematic()
    end
end

local function activateAdventureScreen()
    if Game.screen == "title" or Game.screen == "complete" then
        if Game.screen == "complete" then resetCampaign() end
        playCinematic("intro")
    else
        finishCinematic()
    end
end

local function updateExplore(dt)
    if Game.desertArrival then
        updateDesertArrival(dt)
        return
    end

    if Game.encounterCooldown > 0 then
        Game.encounterCooldown = math.max(0.0, Game.encounterCooldown - dt)
    end

    -- Pause walk input while calm room-snapped camera pans between rooms (R7)
    local panning = Game.stage:isCameraPanning()
    if panning and not Game.wasCameraPanning and Game.audio then
        Game.audio:play("sfx_camera_pan", 0.32)
    end
    Game.wasCameraPanning = panning
    if panning then
        Game.lastStepBucket = nil
        Game.stage:updateExploreCamera(Game.puduU, Game.puduV, dt)
        return
    end

    local dx, dy = 0, 0
    if love.keyboard.isDown("w", "up") then dy = dy - 1 end
    if love.keyboard.isDown("s", "down") then dy = dy + 1 end
    if love.keyboard.isDown("a", "left") then dx = dx - 1 end
    if love.keyboard.isDown("d", "right") then dx = dx + 1 end

    local nextEncounter = nextOverworldEncounter()
    local gateU = nextEncounter and not Game.qaExplore and nextEncounter.u
    local targetU, targetV = StageRenderer.screenVecToIso(dx, dy, WALK_SPEED)
    local velocityU, velocityV = Game.puduVelocityU, Game.puduVelocityV
    local changeU, changeV = targetU - velocityU, targetV - velocityV
    local change = math.sqrt(changeU * changeU + changeV * changeV)
    local hasInput = dx ~= 0 or dy ~= 0
    local acceleration = hasInput and WALK_ACCELERATION or WALK_BRAKING
    local rampTime = math.min(dt, change / acceleration)
    local ramp = change > 0 and math.min(1.0, dt * acceleration / change) or 1.0
    Game.puduVelocityU = velocityU + changeU * ramp
    Game.puduVelocityV = velocityV + changeV * ramp

    -- Integrate the ramp and then any time spent at the target speed this frame.
    local moveU = Game.puduVelocityU * dt - changeU * ramp * rampTime * 0.5
    local moveV = Game.puduVelocityV * dt - changeV * ramp * rampTime * 0.5
    local startU, startV = Game.puduU, Game.puduV
    local candU, candV = startU + moveU, startV + moveV
    if gateU and moveU > 0 and candU >= gateU then
        candU = math.max(startU, gateU)
        Game.puduVelocityU = 0.0
    end

    -- Cancel momentum on blocked axes while allowing the other axis to slide.
    if (candU ~= startU or candV ~= startV) and not StageRenderer.isWalkable(candU, candV) then
        if candU ~= startU and StageRenderer.isWalkable(candU, startV) then
            candV, Game.puduVelocityV = startV, 0.0
        elseif candV ~= startV and StageRenderer.isWalkable(startU, candV) then
            candU, Game.puduVelocityU = startU, 0.0
        else
            candU, candV = startU, startV
            Game.puduVelocityU, Game.puduVelocityV = 0.0, 0.0
        end
    end

    Game.puduU, Game.puduV = candU, candV
    local movedU, movedV = candU - startU, candV - startV
    local distance = math.sqrt(movedU * movedU + movedV * movedV)
    Game.puduWalkWeight = dt > 0 and math.min(1.0, distance / (dt * WALK_SPEED)) or 0.0
    if distance > 1e-5 then
        local screenX = movedU * StageRenderer.ISO_UX + movedV * StageRenderer.ISO_VX
        local screenY = movedU * StageRenderer.ISO_UY + movedV * StageRenderer.ISO_VY
        Game.puduFacingRow = StageRenderer.screenDirToFacingRow(screenX, screenY)
        Game.puduWalkT = (Game.puduWalkT + distance / WALK_FRAME_DISTANCE) % 4
        local bucket = math.floor(Game.puduWalkT)
        if bucket ~= Game.lastStepBucket then
            Game.lastStepBucket = bucket
            if (bucket == 1 or bucket == 3) and Game.audio then
                local biomeId = StageRenderer.getBiomeAt(Game.puduU)
                Game.audio:play(Audio.getBiomeStepSfx(biomeId), 0.26, 0.08)
            end
        end
    else
        Game.lastStepBucket = nil
        if hasInput then
            Game.puduFacingRow = StageRenderer.screenDirToFacingRow(dx, dy)
        end
    end

    Game.stage:updateExploreCamera(Game.puduU, Game.puduV, dt)
    if Game.stage:isCameraPanning() then
        Game.lastStepBucket = nil
        stopPuduMovement()
    end
    syncExploreBiomeMusic(false)

    if not Game.completoPickedAt and distanceSquaredFromPudu(COMPLETO) <= COMPLETO.pickupRadius ^ 2 then
        Game.completoPickedAt = Game.elapsed
        Game.completoBonusPending = true
    end

    -- Crossing the next rival's position starts combat even if the player takes a side path.
    if nextEncounter and Game.encounterCooldown <= 0
        and (distanceSquaredFromPudu(nextEncounter) < ENCOUNTER_TRIGGER_DIST ^ 2
            or (gateU and Game.puduU >= gateU)) then
        triggerEncounterTransition(nextEncounter.index)
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
    if phase == "portal" then
        b.portalElapsed = b.portalElapsed + dt
        if b.portalElapsed >= PORTAL_DURATION then playCinematic("ending") end
        return
    end
    if phase == "victory" and b.campaignComplete and Game.elapsed - b.victoryAt >= FINAL_VICTORY_HOLD then
        startPortal()
        return
    end
    if phase == "versus" then
        local before = b.versusTime
        b.versusTime = before + dt
        local impactTime = VERSUS_DURATION * VERSUS_IMPACT_AT
        if before < impactTime and b.versusTime >= impactTime then
            Game.audio:play("parry_clash", 0.92)
        end
        if b.versusTime >= VERSUS_DURATION then
            Game.battlePhase, Game.battleEnterT = "battle_enter", 0
            Game.puduAnimMode = "battle_enter"
        end
        return
    end
    if b.rivalHitTimer then b.rivalHitTimer = math.max(0, b.rivalHitTimer - dt) end
    local anchors = StageRenderer.getBattleAnchors(w, h, enc)
    local ex, ey = syncBattleFX(enc, anchors, w, h)
    if not fx:isHitStopped() then b.actorTime = (b.actorTime or 0) + dt end
    fx:update(dt, Game.audio)
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
        if b.spriteDeadline and ritual.elapsed >= b.spriteDeadline then
            acceptSprite({ uid = b.uid, error = "Tiempo de generación agotado." })
            return
        end
        if b.previewSpriteAt and ritual.elapsed >= b.previewSpriteAt then
            ritual:setSpriteReady()
            b.previewSpriteAt = nil
        end
        if b.autoRitual and ritual.elapsed >= b.nextAutoArrowAt then
            local arrow = ritual.sequence[ritual.cursor]
            if arrow then ritual:onKeyPressed(arrow.direction, Game.audio) end
            b.nextAutoArrowAt = b.nextAutoArrowAt + (Game.demo and 0.055 or 0.17)
        end
        ritual:update(realDt, anchors.puduX, anchors.puduY, getOrbLift(anchors, h))
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
            impact.damage_to_enemy, b.promptPoints, b.precisionBonus = BattleScores.attack(res, power, b.enemyHp)
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
                if Game.audio then
                    local cfx = b.result.enemy_counter_fx
                    if cfx and cfx ~= "none" then
                        Game.audio:play("sfx_counter_" .. tostring(cfx), 0.78)
                    end
                    Game.audio:play("hurt", 0.75)
                end
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

local function drawBattleContactShadow(x, y, rx, ry, opacity)
    love.graphics.setShader()
    love.graphics.setColor(0.03, 0.04, 0.08, opacity)
    local radial = Game.assets.lightRadial
    if radial then
        local iw, ih = radial:getDimensions()
        love.graphics.draw(radial, x, y, 0, rx * 2.8 / iw, ry * 2.8 / ih, iw * 0.5, ih * 0.5)
    else
        love.graphics.ellipse("fill", x, y, rx, ry)
    end
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
    drawBattleContactShadow(px, py + 4, targetH * 0.31 * shScale, targetH * 0.105 * shScale,
        0.50 * (1.0 - airFrac * 0.28))

    -- Subtle comic motion dust during battle_enter trot (zero music notes!)
    if Game.battlePhase == "battle_enter" then
        drawBattleDashDust(px, py + 2, Game.battleEnterT, Game.elapsed)
    end

    local puduPair = assets.pudu
    local quads = assets.puduQuads
    local sc = targetH / 64.0
    local headShiftX, headShiftY = 0.0, 0.0

    if puduPair and puduPair.diff and quads and quads[row] and quads[row][col] then
        local quad = quads[row][col]
        local _, _, qw, qh = quad:getViewport()
        local footY
        footY, headShiftX, headShiftY = StageRenderer.getPuduFrameAnchor(puduPair, row, col, qw, qh)
        sc = targetH / math.max(1, qh)
        love.graphics.setColor(1, 1, 1, 1)
        Game.stage:drawSpriteLit(
            puduPair,
            px,
            py + jumpY,
            tilt,
            sc * sxMul,
            sc * syMul,
            qw * 0.50,
            footY,
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

        -- Transform local head offset by Pudú's squash/stretch and body tilt
        local localX = (off.x * unit + headShiftX * sc) * sxMul
        local localY = (off.y * unit + headShiftY * sc) * syMul
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

local function drawEnemySprite(enc, x, y, targetH, facingRow, groove, litShader, defeat)
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
    drawBattleContactShadow(ex, ey + 4, 46 * shScale, 15 * shScale, 0.50 * (1.0 - airFrac * 0.25) * alpha)

    local encPair, quad, fw, fh, companion = enemyFrame(enc, facingRow, not defeat)
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
            encPair.originX or fw * 0.50,
            encPair.originY or fh * 0.92,
            quad,
            d.flashWhite or 0,
            nil,
            litShader,
            true
        )
        if companion then
            local side = fw * 0.56 * sc * sxMul
            local sockScale = sc * 0.72
            Game.stage:drawSpriteLit(companion, ex + math.cos(tilt) * side, ey + dy + math.sin(tilt) * side,
                tilt, sockScale * sxMul, sockScale * syMul, companion.originX, companion.originY,
                companion.quads[facingRow][1], d.flashWhite or 0, nil, litShader, true)
        end
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


local function canOpenScores()
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then return false end
    local phase = Game.battlePhase
    return Game.mode == "explore" or phase == "player_turn" or phase == "defeat"
end

local function getHudState(battleEnc)
    local b = Game.battle
    local audio = Game.audio:getStats()
    local state = {
        mode = Game.mode, battlePhase = b and Game.battlePhase or nil,
        musicOff = audio.muted or not audio.musicEnabled,
        toast = Game.toastText, elapsed = Game.elapsed, canOpenScores = canOpenScores(),
    }
    if b then
        local biome = Encounters.getBiome(battleEnc.biome)
        state.context = battleEnc.biome == "ciudad" and "Ciudad" or biome.shortName
        state.rivalName = battleEnc.name
        state.rivalShouts = (b.rivalHitTimer or 0) > 0 or rivalIsAttacking(Game.battlePhase, b)
        local portraits = Game.assets.rivalPortraits[battleEnc.id]
        if portraits then
            state.rivalPortrait = (state.rivalShouts and portraits.shout) or portraits.idle or portraits.shout
        end
        state.hp, state.enemyHp, state.enemyMaxHp = b.hp, b.enemyHp, battleEnc.maxHp
        state.score, state.totalScore = b.score, BattleScores.total(b.score)
        state.campaignComplete = b.campaignComplete
        state.stageStates, state.portraits, state.mood = Game.stageStates, Game.assets.portraits, b.mood
        state.puduPortrait = Game.assets.puduVersusPortrait
        if b.victoryAt then state.victoryElapsed = Game.elapsed - b.victoryAt - VICTORY_FINALE_TIME end
        state.speech = b.speech
        if Game.battlePhase == "victory" or Game.battlePhase == "defeat" then
            state.lastPrompt = b.prompt
            if Judge.hasProfanity(state.lastPrompt) then state.lastPrompt = b.result and b.result.summon_name end
        end
        state.enemyStatusTag = b.result and b.result.status_tag
        state.arrowsDone = Game.battlePhase == "ritual" and Game.ritual.cursor > #Game.ritual.sequence
        local res = b.decision and b.decision.result
        if res and res.approved then
            state.summonName = res.summon_name
            state.narrator = res.narrator_text
        end
    else
        local biome = Encounters.getBiome(StageRenderer.getBiomeAt(Game.puduU))
        local target = not Game.desertArrival and nextOverworldEncounter()
        state.canStartBattle = target and (Game.qaExplore or distanceSquaredFromPudu(target) < ENCOUNTER_SHORTCUT_DIST ^ 2)
        state.context = ("%s (%d/%d)"):format(biome.name, campaignWins(), #Encounters.LIST)
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
    Game.qaExplore = Game.cli.biome ~= nil or Game.cli.encounterExplicit
    if Game.mode == "explore" and not (Game.cli.modeExplicit or Game.qaExplore or Game.cli.transitionPreview
        or Game.cli.battleEnterPreview or Game.cli.openDirector or Game.cli.forceReaction
        or #Game.cli.autoPrompts > 0) then
        Game.screen = "title"
    end
    Game.overworldEncounters = Encounters.LIST
    if Game.mode == "explore" and not Game.cli.biome and Game.encounterIndex > #Encounters.LIST then
        Game.overworldEncounters = { Encounters.getByIndex(Game.encounterIndex) }
    end
    Game.fonts = loadFonts()
    Game.adventureScreen = AdventureScreen.new(Game.fonts)
    Game.hud = BattleHUD.new(Game.fonts)
    Game.scoreHistory = BattleScores.load(love.filesystem)
    Game.ritual = SpellRitual.new()
    Game.battleFX = BattleFX.new()
    Game.battleFX:setTypography(Game.fonts)
    Game.battleFX:setShakeEnabled(not Game.cli.disableShake)
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

    Game.stage = createStage()

    local w, h = love.graphics.getDimensions()
    ensureWorldCanvas(w, h)

    -- Initial Pudu overworld position & camera snap
    if not Game.cli.biome and (Game.cli.transitionPreview ~= nil
        or (Game.cli.encounterExplicit and Game.mode == "explore")
        or (Game.mode == "battle" and Game.encounterIndex <= #Encounters.LIST)) then
        local enc = Encounters.getByIndex(Game.encounterIndex)
        if enc then
            Game.puduU, Game.puduV = findSafeSpotNearEncounter(enc, -2.0)
            Game.puduFacingRow = 3
        end
    else
        Game.puduU = Encounters.getBiome(Game.cli.biome).spawnU
        Game.puduV = StageRenderer.pathCenterV(Game.puduU)
        Game.puduFacingRow = 3
    end

    Game.stage:snapCameraToChunk(Game.puduU, Game.puduV)

    if Game.mode == "explore" and not Game.qaExplore
        and Game.cli.transitionPreview == nil and not Game.cli.battleEnterPreview then
        Game.desertArrival = DesertArrival.new(StageRenderer.DESERT_ARRIVAL, Game.puduU, Game.puduV)
        updateDesertArrival(0)
    end

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
        local seedT = Game.cli.battleEnterPreview and 0.22 or (Game.cli.demoFinale and 0 or nil)
        enterBattleArenaImmediate(Game.encounterIndex, (Game.demo ~= nil or Game.cli.testRitual ~= nil)
            and not Game.cli.battleEnterPreview, seedT)
    elseif not Game.screen then
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
    if not Game.screen and not Game.scorePage then Game.elapsed = Game.elapsed + safeDt end
    Game.cliElapsed = Game.cliElapsed + dt
    pollWorkers()
    local b = Game.battle
    if b and not Game.screen and not Game.scorePage and Game.battlePhase == "player_turn"
        and Game.transitionState == "none" and not Game.transitionPreview then
        if Game.ritualPreview then
            local preview = Game.ritualPreview
            Game.ritualPreview = nil
            local prompt = preview == "bonus" and "pulpo DJ"
                or Encounters.getByIndex(Game.encounterIndex).weaknesses[1]
            submitPrompt(prompt, preview, preview == "bonus")
        elseif Game.demo then
            local prompt = Game.demo[b.turn]
            if prompt then submitPrompt(prompt, nil, true) end
        elseif Game.cli.demoFinale then
            local w, h = love.graphics.getDimensions()
            local enc = Encounters.getByIndex(Game.encounterIndex)
            local ex, ey = syncBattleFX(enc, StageRenderer.getBattleAnchors(w, h, enc), w, h)
            Game.enemyReaction = Game.cli.demoFinale
            b.enemyHp = 0
            startVictory(enc, ex, ey, w)
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

    if Game.screen == "intro" or Game.screen == "ending" then
        if not Game.adventureScreen:isPlaying() then finishCinematic() end
    elseif not Game.screen and not Game.scorePage and Game.transitionPreview == nil then
        if Game.transitionState ~= "none" then
            updateTransition(safeDt)
        elseif Game.mode == "explore" then
            local restored = Game.stage:updateRestorations(safeDt)
            if restored then showToast(restored.restorationLine, 5.0) end
            updateExplore(safeDt)
        elseif Game.mode == "battle" then
            updateBattle(safeDt, dt)
        end
        if Game.mode == "explore" then
            Game.stage:updateOverworldNPCs(Game.puduU, Game.puduV, safeDt)
        end
    end

    if Game.cli.screenshot and not Game.cliScreenshotDone and Game.framesDrawn >= 2 then
        local phase = Game.cli.screenshotPhase
        local triggerAt = Game.cli.quitAfter and math.max(0.15, Game.cli.quitAfter - 0.35) or 0.25
        if phase then
            local matches = Game.screen == phase or (not Game.screen and b and Game.battlePhase == phase)
            if phase == "combo" then
                matches = Game.battlePhase == "impact_hold" and b.result.combo_triggered ~= "none"
            end
            if matches then
                Game.screenshotPhaseTime = (Game.screenshotPhaseTime or 0) + safeDt
            else
                Game.screenshotPhaseTime = nil
            end
        end
        local phaseDelay = phase == "versus" and 0.53 or 0.1
        if phase == "victory" then phaseDelay = VICTORY_FINALE_TIME + BattleHUD.VICTORY_ENTRANCE end
        if (phase and (Game.screenshotPhaseTime or 0) >= phaseDelay)
            or (not phase and Game.cliElapsed >= triggerAt) then
            Game.cliScreenshotDone = true
            saveScreenshotTo(Game.cli.screenshot)
        end
    end

    if Game.cli.quitAfter and Game.cliElapsed >= Game.cli.quitAfter then
        if Game.cli.screenshotPhase and not Game.cliScreenshotDone then
            error("No se capturó la fase " .. Game.cli.screenshotPhase)
        end
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
    return not Game.screen and not Game.scorePage and Game.mode == "battle" and Game.battlePhase == "player_turn"
        and Game.transitionState == "none" and Game.transitionPreview == nil
end

function love.textinput(text)
    if promptAvailable() then
        if Game.ignorePromptSlash and text == "/" then
            Game.ignorePromptSlash = false
            return
        end
        Game.hud:addText(text)
    end
end

local function routeHudAction(action)
    if action == "scores" and not Game.scorePage and canOpenScores() then
        Game.scorePage = 1
        Game.reopenPromptOnClose = Game.hud.promptOpen
        Game.hud:closePrompt(false)
    elseif Game.scorePage then
        if action == "close_scores" then
            Game.scorePage = nil
            if Game.reopenPromptOnClose and promptAvailable() then Game.hud:openPrompt() end
            Game.reopenPromptOnClose = nil
        elseif action == "score_older" or action == "score_newer" then
            local delta = action == "score_older" and 1 or -1
            local pages = BattleHUD.scorePageCount(#Game.scoreHistory.entries)
            Game.scorePage = clamp(Game.scorePage + delta, 1, pages)
        end
    elseif action == "music" then
        if Game.audio then Game.audio:play("sfx_ui_click", 0.55) end
        local enabled = Game.audio:toggleMusic()
        showToast(enabled and "Música activada" or "Música desactivada", 1.8)
    elseif action == "map" then
        if Game.audio then Game.audio:play("sfx_ui_click", 0.55) end
        if Game.mode == "battle" then
            triggerReturnToExplore()
        elseif not Game.desertArrival then
            local target = nextOverworldEncounter()
            if target and (Game.qaExplore or distanceSquaredFromPudu(target) < ENCOUNTER_SHORTCUT_DIST ^ 2) then
                triggerEncounterTransition(target.index)
            end
        end
    elseif action == "retry" and Game.battlePhase == "defeat" then
        if Game.audio then Game.audio:play("sfx_ui_click", 0.55) end
        enterBattleArenaImmediate(Game.encounterIndex, false)
    elseif action == "prompt" and promptAvailable() then
        if not Game.hud.promptOpen and Game.audio then Game.audio:play("sfx_prompt_open", 0.55) end
        Game.hud:openPrompt()
    elseif action == "conjure" and promptAvailable() then
        submitPrompt(Game.hud.input)
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if Game.screen then
        if Game.adventureScreen:hitTest(Game.screen, x, y, love.graphics.getDimensions()) then
            activateAdventureScreen()
        end
        return
    end
    if Game.battlePhase == "portal" then return end
    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil then return end
    if Game.battlePhase == "versus" then return end
    routeHudAction(Game.hud:hitTest(x, y))
end

function love.wheelmoved(_, y)
    if Game.screen then return end
    if Game.scorePage and y ~= 0 then
        routeHudAction(y < 0 and "score_older" or "score_newer")
    elseif Game.mode == "explore" and Game.transitionState == "none" and Game.transitionPreview == nil then
        Game.stage:adjustExploreZoom(y)
    end
end

function love.keypressed(key, scancode, isrepeat)
    if key == "escape" and isrepeat then return end
    Game.ignorePromptSlash = false
    if key == "f12" and not Game.scorePage then
        local out = string.format("screenshots/manual_%d.png", os.time())
        saveScreenshotTo(out)
        showToast("Captura guardada: " .. out, 2.2)
        return
    end
    if Game.screen then
        if isrepeat then return end
        if key == "return" or key == "kpenter" or key == "space" then
            activateAdventureScreen()
        elseif key == "escape" then
            if Game.screen == "title" then love.event.quit(0) end
            if Game.screen == "intro" or Game.screen == "ending" then finishCinematic() end
        elseif key == "f8" then
            Game.adventureScreen:setMuted(Game.audio:toggleMute())
        end
        return
    end
    if Game.battlePhase == "portal" then return end
    if Game.scorePage then
        if key == "escape" or (key == "f3" and not isrepeat) then routeHudAction("close_scores") end
        if key == "right" or key == "pagedown" then routeHudAction("score_older") end
        if key == "left" or key == "pageup" then routeHudAction("score_newer") end
        return
    end
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
    end

    if Game.transitionState ~= "none" or Game.transitionPreview ~= nil or Game.battlePhase == "versus" then return end
    if key == "f3" and not isrepeat then
        routeHudAction("scores")
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
            else
                if Game.audio then Game.audio:play("sfx_prompt_open", 0.55) end
                Game.hud:openPrompt()
            end
        end
    elseif promptAvailable() and key == "/" and not isrepeat and not Game.hud.promptOpen then
        if Game.audio then Game.audio:play("sfx_prompt_open", 0.55) end
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
    if Game.screen then
        Game.adventureScreen:draw(Game.screen, w, h, love.mouse.getPosition())
        Game.lastDrawCalls = love.graphics.getStats().drawcalls or 0
        return
    end
    if Game.mode == "battle" and Game.battlePhase == "versus" then
        local enc = Encounters.getByIndex(Game.encounterIndex)
        Game.hud:drawVersus(Game.assets.puduVersusPortrait or Game.assets.portraits.happy,
            Game.assets.rivalPortraits[enc.id], enc.name, enc.color, w, h,
            Game.battle.versusTime / VERSUS_DURATION, VERSUS_IMPACT_AT, not Game.cli.disableShake)
        Game.lastDrawCalls = love.graphics.getStats().drawcalls or 0
        return
    end
    local canvas = ensureWorldCanvas(w, h)

    local battleEnc = nil
    local battleTheme = nil
    local battleAnchors, defeatTransform, rivalCard
    local portalProgress
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
        local lights = Game.stage:collectZoneLights(w, h, Game.elapsed, Game.defeatedMap)
        local litShader = Game.stage:configureLitShader(theme, w, h, Game.elapsed, lights, nil, true)
        local terrainShader = Game.shaders.terrain
            and Game.stage:configureLitShader(theme, w, h, Game.elapsed, lights, Game.shaders.terrain, true)
        local arrival = Game.desertArrival
        local overPose = arrival or Game.beatSync:getOverworldPuduPose(
            Game.puduFacingRow, Game.puduWalkT, Game.puduWalkWeight
        )

        Game.stage:drawOverworld({
            w = w,
            h = h,
            time = Game.elapsed,
            assets = Game.assets,
            encounters = Game.overworldEncounters,
            defeatedMap = Game.defeatedMap,
            puduU = Game.puduU,
            puduV = Game.puduV,
            puduFacingRow = Game.puduFacingRow,
            puduPose = overPose,
            puduArrivalLift = arrival and arrival.lift,
            completoCollected = Game.completoPickedAt ~= nil,
            alertEncounterIdx = Game.alertEncounterIdx,
            alertTimer = (Game.transitionState == "alert") and Game.transitionTimer or 0.25,
            fonts = Game.fonts,
            litShader = litShader,
            terrainShader = terrainShader,
        })
        Game.stage:drawAtmosphericLighting(Game.assets and Game.assets.lightRadial, lights, w, h, Game.elapsed, biomeId)
    else
        battleEnc = Encounters.getByIndex(Game.encounterIndex) or Encounters.LIST[1]
        battleTheme = Encounters.getTheme(battleEnc.stage)
        local lights = {}
        if Game.battlePhase == "ritual" then
            Game.ritual:collectLights(lights)
        end
        fx:collectLights(lights)
        for _, light in ipairs(Game.stage:collectBattleLights(battleEnc, w, h, Game.elapsed, Game.assets)) do
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

        if Game.battlePhase == "victory" then defeatTransform = fx:getDefeatTransform() end

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

        local b = Game.battle
        if Game.battlePhase == "portal" then portalProgress = b.portalElapsed / PORTAL_DURATION end
        local enemyVisible = not portalProgress
            and (not defeatTransform or (defeatTransform.alpha >= 0.15 and defeatTransform.dx <= 180))
        if enemyVisible and (Game.battlePhase ~= "battle_enter" or Game.battleEnterT >= 0.88) then
            local ex = battleAnchors.enemyX + (battleEnc.offsetX or 0) + enemyEnterOffX
            rivalCard = Game.hud:layoutPortrait(battleEnc.name, ex, w, h)
        end
        fx:setRivalCard(rivalCard)

        if not fx:isHitStopped() then
            b.puduPose = Game.beatSync:getPuduDancePose(Game.puduAnimMode, battleAnchors.puduFacingRow)
            b.enemyGroove = Game.beatSync:getEnemyGroove(Game.enemyReaction)
        end

        if not portalProgress then fx:drawBackLayer() end
        if Game.battlePhase == "ritual" then
            Game.ritual:drawCircle(battleAnchors.puduX, math.min(battleAnchors.puduY, h - 81))
        end

        -- Draw upper-right Rival first (background depth), then foreground bottom-left Pudú (cropped cleanly behind bottom strip)
        love.graphics.push()
        local puduHeight = getPuduRenderHeight(battleAnchors, h)
        if portalProgress then
            local portalX, portalY = w * 0.56, battleAnchors.puduY - h * 0.047
            AdventureScreen.drawPortal(portalX, portalY, puduHeight * 1.35, portalProgress)
            if portalProgress < 0.90 then
                local walk = smoothstep01((portalProgress - 0.16) / 0.74)
                local enter = smoothstep01((portalProgress - 0.72) / 0.18)
                local x = battleAnchors.puduX + (portalX - battleAnchors.puduX) * walk
                local y = battleAnchors.puduY + (portalY - battleAnchors.puduY) * walk
                local pose = { row = 2, col = math.floor(portalProgress * 20) % 4 + 1 }
                drawPuduSprite(x, y, puduHeight * (1 - 0.84 * enter), pose, litShader)
            end
        else
            love.graphics.translate(fx:getShakeOffset())
            drawEnemySprite(
                battleEnc,
                battleAnchors.enemyX + enemyEnterOffX,
                battleAnchors.enemyY + enemyEnterOffY,
                battleAnchors.enemyScaleH or 148.0,
                battleAnchors.enemyFacingRow,
                not defeatTransform and b.enemyGroove or nil,
                litShader,
                defeatTransform
            )
            drawPuduSprite(
                battleAnchors.puduX + puduEnterOffX,
                battleAnchors.puduY + puduEnterOffY,
                puduHeight,
                b.puduPose,
                litShader
            )
        end
        love.graphics.pop()

        Game.stage:drawBattleArenaForeground(battleEnc, Game.assets, w, h, Game.elapsed, litShader)
        if not portalProgress then
            fx:drawSummonsAndProps(litShader, function(pair, x, y, angle, sx, sy, ox, oy, shader)
                Game.stage:drawSpriteLit(pair, x, y, angle, sx, sy, ox, oy, nil, 0, nil, shader, true)
            end)
            if Game.battlePhase ~= "battle_enter" and Game.battlePhase ~= "ritual" then
                local ex = battleAnchors.enemyX + (battleEnc.offsetX or 0)
                local ey = battleAnchors.enemyY + (battleEnc.offsetY or 0)
                fx:drawReactionOverlay(Game.enemyReaction, ex, ey, Game.elapsed)
            end
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

    if portalProgress then
        love.graphics.setColor(0.035, 0.075, 0.06, smoothstep01((portalProgress - 0.82) / 0.18))
        love.graphics.rectangle("fill", 0, 0, w, h)
        Game.lastDrawCalls = love.graphics.getStats().drawcalls or 0
        return
    end

    local hudState = getHudState(battleEnc)
    hudState.pointerX, hudState.pointerY = love.mouse.getPosition()
    local showVictory = hudState.victoryElapsed and hudState.victoryElapsed > 0
    if showVictory then
        Game.hud:drawVictory(hudState, w, h)
    else
        Game.hud:drawTopBar(hudState, w)
    end
    if Game.mode == "explore" then
        local timeSincePickup = Game.completoBonusPending and Game.elapsed - Game.completoPickedAt
        local puduDialogue, npcDialogue
        if Game.transitionState == "none" and Game.transitionPreview == nil then
            local spotsCompleto = not Game.desertArrival and not Game.completoPickedAt
                and distanceSquaredFromPudu(COMPLETO) <= COMPLETO.sightRadius ^ 2
            local puduLine = (spotsCompleto or (timeSincePickup and timeSincePickup < 1.5)) and COMPLETO.line
            puduDialogue, npcDialogue = Game.stage:drawOverworldDialogue(w, h, Game.fonts, puduLine)
        end
        Game.stage:drawOverworldRivalSigns(w, h, Game.fonts.small, puduDialogue, npcDialogue)
        Game.stage:drawOverworldMinimap(
            Game.puduU,
            Game.puduV,
            Game.overworldEncounters,
            Game.defeatedMap,
            w,
            h,
            Game.fonts.small,
            Game.fonts.story
        )
        if not Game.desertArrival then Game.hud:drawExploreBar(w, h) end
        if timeSincePickup and timeSincePickup < 5.0 then
            Game.hud:drawCompletoPickup(w, h, Game.assets.scenery.completo_italiano.diff)
        end
    elseif not showVictory then
        local b, phase = Game.battle, Game.battlePhase
        local ex = battleAnchors.enemyX + (battleEnc.offsetX or 0) + enemyEnterOffX
        local ey = battleAnchors.enemyY + (battleEnc.offsetY or 0) + enemyEnterOffY
        local px, py = battleAnchors.puduX, battleAnchors.puduY
        if phase == "ritual" then
            Game.hud:drawAnticipation(b.anticipationLine, w, ex, ey, rivalCard)
            Game.ritual:draw(w, h, px, py, Game.fonts, Game.beatSync, getOrbLift(battleAnchors, h))
        elseif phase ~= "battle_enter" and phase ~= "victory" and phase ~= "defeat" then
            fx:drawFrontParticles(Game.fonts, px, py, ex, ey)
            fx:drawSpeechBubbles(px, py, ex, ey, Game.fonts)
        else
            fx:drawFrontParticles(Game.fonts)
        end
        if rivalCard then
            Game.hud:drawPortrait(hudState.rivalName, hudState.rivalPortrait, rivalCard, hudState.rivalShouts)
            Game.hud:drawRivalStageBar(hudState, ex, ey, w)
        end
        Game.hud:drawBattleStrip(hudState, w, h)
        if phase == "defeat" then Game.hud:drawDefeat(hudState, w, h) end
    end

    -- 4. JRPG Battle Transition Overlay (live or --transition-preview)
    if Game.transitionPreview ~= nil then
        Game.stage:drawBattleTransition(Game.transitionPreview, w, h)
    elseif Game.transitionState == "to_battle" then
        Game.stage:drawBattleTransition(Game.transitionTimer / TO_BATTLE_DURATION, w, h)
    elseif Game.transitionState == "to_explore" then
        Game.stage:drawBattleTransition(Game.transitionTimer / TO_EXPLORE_DURATION, w, h)
    end

    if Game.scorePage then
        Game.hud:drawScores(Game.scoreHistory.entries, Game.scorePage, w, h, Game.scoreSaveFailed)
    end

    local statsNow = love.graphics.getStats()
    Game.lastDrawCalls = statsNow.drawcalls or 0
end

function love.quit()
    if Game.adventureScreen then Game.adventureScreen:stop() end
    if Game.battleIn then Game.battleIn:clear(); Game.battleIn:push({cmd="quit"}) end
    if Game.spriteIn then Game.spriteIn:clear(); Game.spriteIn:push({cmd="quit"}) end
end
