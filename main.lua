-- Pudú Fantasy: mapa, encuentros y combate por prompts (LÖVE 11.5).

local utf8 = require("utf8")
local AssetLoader = require("asset_loader")
local Audio = require("audio")
local Encounters = require("encounters")
local StageRenderer = require("stage_renderer")

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
-- CLI Parser (every literal hyphen escaped as %-%-)
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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
-- Game State & Helpers
--------------------------------------------------------------------------------

local ALERT_DURATION = 0.40
local TO_BATTLE_DURATION = 1.05
local TO_EXPLORE_DURATION = 0.72
local ENCOUNTER_TRIGGER_DIST = 1.75
local WALK_SPEED = 6.2

local Game = {
    cli = nil,
    mode = "explore",
    encounterIndex = 1,
    assets = nil,
    audio = nil,
    stage = nil,
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
        local enc = Encounters.getByIndex(Game.encounterIndex)
        local trackId = (enc and enc.track) or "user_battle"
        Game.audio:playTrack(trackId, false)
    else
        Game.audio:playTrack("overworld", false)
    end
end

-- Each command follows the normal turn path, including setup, counter and KO.
local comboDemos = {
    combo_electro = { "balde de agua", "rayo" },
    combo_deep_freeze = { "balde de agua", "hielo" },
    combo_steam_sauna = { "hielo", "secador" },
    combo_slip_slide = { "jabón", "plátano" },
    combo_fire_boom = { "aceite", "fósforo" },
    combo_chaos = { "oscuridad", "bocina" },
}
local demoAliases = { electro = "combo_electro", freeze = "combo_deep_freeze",
    steam = "combo_steam_sauna", slip = "combo_slip_slide", fire = "combo_fire_boom", chaos = "combo_chaos" }

local function beginBattle()
    local enc = Encounters.getByIndex(Game.encounterIndex)
    Game.stageStates = {}
    Game.battle = {
        hp = 100, enemyHp = enc.maxHp, turn = 1, phase = "input", input = "",
        props = {}, reaction = "idle", misses = 0, speech = enc.introLine,
    }
    love.keyboard.setTextInput(true)
end

local function submitPrompt(prompt)
    local b = Game.battle
    if not b or b.phase ~= "input" or not prompt:find("%S") then return end
    local enc = Encounters.getByIndex(Game.encounterIndex)
    Game.nextRequestId = Game.nextRequestId + 1
    b.uid, b.prompt, b.phase, b.input = Game.nextRequestId, prompt, "waiting", ""
    local props = {}
    for i, prop in ipairs(b.props) do props[i] = prop.key end
    Game.battleIn:push({
        cmd = "prompt", id = b.uid, uid = b.uid, prompt = prompt, mock_mode = Game.cli.mock,
        encounter = { id = enc.id, name = enc.name, category = enc.category, situation = enc.situation,
            weaknesses = enc.weaknesses, hp = b.enemyHp, pudu_hp = b.hp, max_hp = enc.maxHp, turn = b.turn,
            current_reaction = b.reaction, active_props = props, stage_states = Game.stageStates },
    })
end

local function rememberState(value)
    if value == "none" then return end
    for i, state in ipairs(Game.stageStates) do
        if state == value then table.remove(Game.stageStates, i) break end
    end
    table.insert(Game.stageStates, value)
    if #Game.stageStates > 3 then table.remove(Game.stageStates, 1) end
end

local function finishTurn(message)
    local b, res = Game.battle, message.result
    if not b or b.phase ~= "waiting" or b.uid ~= message.uid or Game.transitionState == "to_explore" then return end
    local enc = Encounters.getByIndex(Game.encounterIndex)
    print(string.format("[BATALLA] turno=%d rival=%s juez=%s ms=%d aprobado=%s resultado=%s estado=%s combo=%s daño=%d",
        b.turn, enc.id, message.source, message.latency_ms or 0, tostring(res.approved),
        res.outcome_type, res.adds_stage_state, res.combo_triggered, res.damage_to_enemy))
    io.stdout:flush()
    b.result, b.phase = res, "input"
    if not res.approved then
        b.speech, b.summon, b.summary = res.reject_reason, nil, nil
        return
    end

    b.summon = { key = res.existing_sprite ~= "none" and res.existing_sprite or res.summon_name, uid = b.uid,
        name = res.summon_name, anchor = res.prop_anchor }
    if res.keep_prop_on_stage then
        for i, prop in ipairs(b.props) do
            if prop.key == b.summon.key then table.remove(b.props, i) break end
        end
        table.insert(b.props, b.summon)
        if #b.props > 3 then table.remove(b.props, 1) end
    end
    if res.sprite_mode == "generate_live" and not Game.cli.mock and message.source ~= "lua" then
        Game.spriteIn:push({ cmd = "generate", uid = b.uid, name = res.summon_name, original_prompt = b.prompt,
            sprite_prompt = res.sprite_prompt, keep_purple = res.keep_purple, target_dim = 80 })
    end

    rememberState(res.adds_stage_state)
    b.reaction = res.enemy_reaction
    b.enemyHp = math.max(0, b.enemyHp - res.damage_to_enemy)
    b.hp = clamp(b.hp + res.heal_pudu - res.damage_to_pudu, 0, 100)
    b.misses = res.is_critical and 0 or b.misses + 1
    b.speech = b.misses >= 2 and enc.semiHintLine or res.enemy_speech
    Game.audio:play(res.sfx)
    Game.audio:play(res.reaction_sfx)
    local recap = {}
    if res.damage_to_enemy > 0 then table.insert(recap, ("Rival -%d PV"):format(res.damage_to_enemy)) end
    if res.heal_pudu > 0 then table.insert(recap, ("Pudú +%d PV"):format(res.heal_pudu)) end
    if res.damage_to_pudu > 0 then table.insert(recap, ("Autogol -%d PV"):format(res.damage_to_pudu)) end
    if b.enemyHp > 0 and b.hp > 0 then
        b.hp = math.max(0, b.hp - res.enemy_counter_damage)
        table.insert(recap, ("%s  -%d PV al pudú"):format(res.enemy_counter_name, res.enemy_counter_damage))
    end
    b.summary = table.concat(recap, "   /   ")
    if b.enemyHp == 0 then
        b.phase, b.speech = "victory", enc.defeatLine
        Game.defeatedMap[enc.id] = true
        Game.audio:playTrack("victory")
    elseif b.hp == 0 then
        b.phase, b.speech = "defeat", res.enemy_counter_line
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
    if not b or not msg.ok then return end
    local target = b.summon
    if not target or target.uid ~= msg.uid then
        target = nil
        for _, prop in ipairs(b.props) do
            if prop.uid == msg.uid then target = prop break end
        end
    end
    if not target then return end
    if msg.existing_sprite and (Game.assets.gags[msg.existing_sprite] or Game.assets.props[msg.existing_sprite]) then
        target.key = msg.existing_sprite
        return
    end
    if not msg.diff_b64 then return end
    local ok, diff = pcall(decodeSprite, msg.diff_b64)
    if ok then
        target.images = { diff = diff }
        if msg.norm_b64 then
            local valid, norm = pcall(decodeSprite, msg.norm_b64)
            if valid then target.images.norm = norm end
        end
    end
end

local function pollWorkers()
    local msg = Game.battleOut:pop()
    while msg do
        if msg.kind == "prompt_result" then finishTurn(msg) end
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
            Game.mode = "battle"
            beginBattle()
            Game.alertEncounterIdx = nil
            Game.transitionSwitched = true
            syncMusicForMode()
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
-- Overworld Exploration Update (Slide Collisions + Room-Snapped Camera)
--------------------------------------------------------------------------------

local function updateExplore(dt)
    if Game.encounterCooldown > 0 then
        Game.encounterCooldown = math.max(0.0, Game.encounterCooldown - dt)
    end

    -- Pause walk input while calm room-snapped camera pans between rooms (R7)
    if Game.stage:isCameraPanning() then
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
        Game.puduFacingRow = screenDirToFacingRow(dx, dy)
        local du, dv = StageRenderer.screenVecToIso(dx, dy, WALK_SPEED)
        local candU = Game.puduU + du * dt
        local candV = Game.puduV + dv * dt

        -- Separate-axis sliding collision check (smoothly slides along riverbanks, cliffs, pier edges)
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

local function drawTopHud(w)
    local fBody = Game.fonts.body
    local fSmall = Game.fonts.small
    local audioStats = Game.audio and Game.audio:getStats() or { muted = false }

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
    local f5Text = "[F5] Recargar"
    local tabText = (Game.mode == "battle") and "[ESC/TAB] Mapa" or "[TAB] Combate"
    local muteKey = Game.mode == "battle" and "[F8]" or "[M]"
    local muteText = (audioStats.muted and "En silencio " or "Audio ") .. muteKey

    local f5W = fSmall:getWidth(f5Text) + 20
    local tabW = fSmall:getWidth(tabText) + 20
    local muteW = fSmall:getWidth(muteText) + 38

    local rx = w - 14
    -- [F5]
    rx = rx - f5W
    drawBevelBox(rx, 12, f5W, 32, { 0.08, 0.16, 0.36, 0.90 }, { 0.64, 0.78, 0.96, 0.86 })
    love.graphics.setColor(0.94, 0.96, 1.0, 1)
    love.graphics.print(f5Text, rx + 10, 21)

    -- [TAB]
    rx = rx - 8 - tabW
    local tabFill = (Game.mode == "battle") and { 0.42, 0.22, 0.22, 0.92 } or { 0.14, 0.34, 0.56, 0.92 }
    drawBevelBox(rx, 12, tabW, 32, tabFill, { 0.76, 0.86, 0.98, 0.90 })
    love.graphics.setColor(0.99, 0.97, 0.88, 1)
    love.graphics.print(tabText, rx + 10, 21)

    -- [M] Music Note + Mute
    rx = rx - 8 - muteW
    drawBevelBox(rx, 12, muteW, 32, { 0.08, 0.16, 0.36, 0.90 }, { 0.64, 0.78, 0.96, 0.86 })
    drawMusicNoteIcon(rx + 8, 20, audioStats.muted)
    love.graphics.setColor(0.94, 0.96, 1.0, 1)
    love.graphics.print(muteText, rx + 31, 21)

    -- Center Toast (y = 14..42, never overlaps left or right chips)
    if Game.toastText then
        local tw = fSmall:getWidth(Game.toastText) + 24
        local tx = math.floor((lw + 24 + rx - tw) * 0.5)
        if tx < lw + 24 or tx + tw > rx - 8 then return end
        drawBevelBox(tx, 14, tw, 28, { 0.14, 0.42, 0.26, 0.94 }, { 0.66, 0.96, 0.76, 0.92 })
        love.graphics.setColor(0.98, 1.0, 0.96, 1)
        love.graphics.print(Game.toastText, tx + 12, 21)
    end
end

local function drawExploreFooterHint(w, h)
    local fSmall = Game.fonts.small
    local text = "WASD / Flechas: Caminar   |   Choca con un rival o [TAB] para combatir"
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

local navy, edge = {0.06, 0.12, 0.25, 0.96}, {0.53, 0.70, 0.87}
local ivory, gold = {0.98, 0.97, 0.92}, {1.0, 0.84, 0.42}

-- The input stays intact for the judge even when the installed font lacks a glyph.
local function drawable(text, font)
    if font:hasGlyphs(text) then return text end
    return (text:gsub(utf8.charpattern, function(char)
        return font:hasGlyphs(char) and char or "?"
    end))
end

local function label(font, color, text, x, y, width, align)
    love.graphics.setFont(font)
    love.graphics.setColor(color)
    love.graphics.printf(drawable(text, font), x, y, width, align or "left")
end

local function hpBar(x, y, w, hp, maxHp, color)
    love.graphics.setColor(0.05, 0.07, 0.13)
    love.graphics.rectangle("fill", x, y, w, 8, 3)
    if hp > 0 then
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x + 2, y + 2, (w - 4) * hp / maxHp, 4, 2)
    end
end

local function drawSummon(prop, x, y, size)
    local pair = prop.images or Game.assets.gags[prop.key] or Game.assets.props[prop.key] or Game.assets.mysterySummon
    local img = pair.diff
    local iw, ih = img:getDimensions()
    local scale = size / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x, y, 0, scale, scale, iw / 2, ih / 2)
end

local function drawBattleOverlay(w, h, enc)
    local b, f = Game.battle, Game.fonts
    local res, cx, ground = b.result, w * 0.72, h * 0.65
    local isOver = b.phase == "victory" or b.phase == "defeat"

    if res and res.approved then
        local topW = math.min(680, w - 64)
        local x = (w - topW) / 2
        drawBevelBox(x, 56, topW, 71, navy, edge)
        local name = res.combo_triggered ~= "none" and res.combo_name or res.summon_name
        label(f.title, gold, name, x + 12, 62, topW - 24, "center")
        label(f.body, ivory, res.narrator_text, x + 12, 89, topW - 24, "center")
        label(f.small, edge, b.summary or "", x + 12, 108, topW - 24, "center")
    end

    local speechW = math.min(w * 0.36, 400)
    local sx, sy = cx - speechW * 0.42, math.max(133, ground - 226)
    local speech = drawable(b.speech or "", f.body)
    local _, lines = f.body:getWrap(speech, speechW - 28)
    local speechH = 18 + #lines * f.body:getHeight()
    drawBevelBox(sx, sy, speechW, speechH, navy, edge)
    love.graphics.setColor(navy)
    love.graphics.polygon("fill", cx - 8, sy + speechH - 3, cx + 9, sy + speechH - 3, cx, sy + speechH + 8)
    label(f.body, ivory, speech, sx + 14, sy + 8, speechW - 28, "center")

    if b.summon then drawSummon(b.summon, w / 2, ground - 48, 112) end
    local propX = w * 0.47
    for _, prop in ipairs(b.props) do
        if prop ~= b.summon then
            drawSummon(prop, propX, ground + 18, 44)
            propX = propX + 40
        end
    end
    local ew, ey = 218, ground + 26
    drawBevelBox(cx - ew / 2, ey, ew, 37, navy, edge)
    label(f.small, ivory, ("Rival   %d / %d PV"):format(b.enemyHp, enc.maxHp), cx - ew / 2, ey + 4, ew, "center")
    hpBar(cx - 94, ey + 22, 188, b.enemyHp, enc.maxHp, {0.97, 0.49, 0.35})
    if #Game.stageStates > 0 then
        local states = table.concat(Game.stageStates, "  /  ")
        local sw = f.small:getWidth(states) + 24
        drawBevelBox(cx - sw / 2, ey + 42, sw, 22, navy, edge)
        label(f.small, ivory, states, cx - sw / 2, ey + 46, sw, "center")
    end

    local y, fieldX = h - 86, 196
    drawBevelBox(14, y, w - 28, 78, navy, edge)
    label(f.heading, ivory, "Pudú", 30, y + 10, 60)
    label(f.small, ivory, ("%d / 100 PV"):format(b.hp), 86, y + 13, 88, "right")
    hpBar(30, y + 37, 144, b.hp, 100, {0.40, 0.84, 0.63})
    label(f.small, edge, ("Turno %d"):format(isOver and b.turn - 1 or b.turn), 30, y + 52, 144)
    local fieldW = w - fieldX - 30
    local title = isOver and (b.phase == "victory" and "¡Camino despejado!" or "El pudú necesita un respiro") or "Tu invocación"
    label(f.heading, gold, title, fieldX, y + 8, fieldW)
    if isOver then
        label(f.body, ivory, "Pulsa Enter para volver al mapa.", fieldX, y + 42, fieldW)
    elseif b.phase == "waiting" then
        label(f.body, ivory, "El juez está leyendo tu conjuro...", fieldX, y + 43, fieldW)
    else
        label(f.small, edge, "Enter para invocar", fieldX, y + 11, fieldW, "right")
        love.graphics.setColor(0.035, 0.07, 0.15)
        love.graphics.rectangle("fill", fieldX, y + 32, fieldW, 34, 4)
        local prompt = b.input == "" and "Escribe lo que quieras invocar..." or drawable(b.input, f.body)
        local textW = f.body:getWidth(prompt)
        local textX = fieldX + 12 - math.max(0, textW - fieldW + 32)
        love.graphics.setScissor(fieldX + 8, y + 32, fieldW - 16, 34)
        love.graphics.setFont(f.body)
        love.graphics.setColor(b.input == "" and edge or ivory)
        love.graphics.print(prompt, textX, y + 41)
        if b.input ~= "" and Game.elapsed % 1 < 0.58 then
            love.graphics.rectangle("fill", textX + textW + 2, y + 40, 2, f.body:getHeight())
        end
        love.graphics.setScissor()
    end
end

--------------------------------------------------------------------------------
-- LOVE Callbacks
--------------------------------------------------------------------------------

function love.load(args)
    love.graphics.setDefaultFilter("nearest", "nearest")

    Game.cli = parseCliArgs(args)
    Game.mode = Game.cli.mode
    if Game.cli.demoCombo then
        local id = demoAliases[Game.cli.demoCombo] or Game.cli.demoCombo
        Game.demo = assert(comboDemos[id], "Combo desconocido: " .. id)
        Game.demoId, Game.mode = id, "battle"
    end
    Game.encounterIndex = Game.cli.encounter
    Game.fonts = loadFonts()

    reloadAssets(false)
    Game.audio = Audio.new(false)

    Game.stage = StageRenderer.new()
    Game.stage:buildOverworldDecor(Encounters.LIST)

    -- Initial Pudu position & camera snap
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
            Game.mode = "battle"
        end
    end

    Game.battleIn, Game.battleOut = love.thread.getChannel("battle_in"), love.thread.getChannel("battle_out")
    Game.spriteIn, Game.spriteOut = love.thread.getChannel("sprite_in"), love.thread.getChannel("sprite_out")
    Game.battleWorker = love.thread.newThread("battle_worker.lua")
    Game.spriteWorker = love.thread.newThread("sprite_worker.lua")
    Game.battleWorker:start()
    Game.spriteWorker:start()
    if not Game.cli.mock then Game.battleIn:push({ cmd = "health" }) end
    if Game.mode == "battle" then beginBattle() end
    love.keyboard.setKeyRepeat(true)
    syncMusicForMode()
end

function love.update(dt)
    local safeDt = math.min(dt, 0.05)
    Game.elapsed = Game.elapsed + safeDt
    Game.cliElapsed = Game.cliElapsed + dt
    pollWorkers()
    local b = Game.battle
    if b and b.phase == "input" and Game.transitionState == "none" and not Game.transitionPreview then
        local auto = Game.demo and Game.demo[b.turn] or Game.cli.autoPrompt
        if auto then
            Game.cli.autoPrompt = nil
            submitPrompt(auto)
        end
    end

    if Game.toastTimer > 0 then
        Game.toastTimer = math.max(0.0, Game.toastTimer - safeDt)
        if Game.toastTimer == 0 then
            Game.toastText = nil
        end
    end

    if Game.transitionPreview == nil then
        if Game.transitionState ~= "none" then
            updateTransition(safeDt)
        elseif Game.mode == "explore" then
            updateExplore(safeDt)
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

local function appendInput(text)
    local b = Game.battle
    if not b or b.phase ~= "input" or Game.transitionState ~= "none" then return end
    local input = b.input .. text:gsub("[%c]+", " ")
    if not utf8.len(input) then return end
    local limit = utf8.offset(input, 281)
    b.input = limit and input:sub(1, limit - 1) or input
end

function love.textinput(text)
    appendInput(text)
end

function love.keypressed(key, scancode, isrepeat)
    -- Tool hotkeys always work even during transitions (Contract 3.1)
    if key == "f5" then
        reloadAssets(true)
        return
    elseif key == "f8" or (key == "m" and Game.mode == "explore") then
        if Game.audio then
            local muted = Game.audio:toggleMute()
            showToast(muted and "Audio silenciado (reloj BPM activo)" or "Audio activado", 1.8)
        end
        return
    elseif key == "f12" then
        local out = string.format("screenshots/manual_%d.png", os.time())
        saveScreenshotTo(out)
        showToast("Captura guardada: " .. out, 2.2)
        return
    end

    -- Lock gameplay input during transitions
    if Game.transitionState ~= "none" or Game.transitionPreview then
        return
    end

    local b = Game.battle
    if b and (key == "return" or key == "kpenter") and not isrepeat then
        if b.phase == "victory" or b.phase == "defeat" then triggerReturnToExplore()
        else submitPrompt(b.input) end
    elseif b and b.phase == "input" and key == "backspace" then
        local pos = utf8.offset(b.input, -1)
        if pos then b.input = b.input:sub(1, pos - 1) end
    elseif b and key == "v" and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then
        appendInput(love.system.getClipboardText() or "")
    elseif key == "tab" and not isrepeat then
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

    if Game.mode == "explore" then
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
            alertEncounterIdx = Game.alertEncounterIdx,
            alertTimer = (Game.transitionState == "alert") and Game.transitionTimer or 0.25,
            fonts = Game.fonts,
        })
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
        local enc = Encounters.getByIndex(Game.encounterIndex) or Encounters.LIST[1]
        local theme = Encounters.getTheme(enc.stage)
        Game.stage:drawBattlePlaceholderStage({
            w = w,
            h = h,
            time = Game.elapsed,
            encounter = enc,
            theme = theme,
            assets = Game.assets,
            drawActors = true,
        })
        drawTopHud(w)
        drawBattleOverlay(w, h, enc)
    end

    -- JRPG Battle Transition Overlay (live or --transition-preview)
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

function love.quit()
    if Game.battleIn then Game.battleIn:clear(); Game.battleIn:push({cmd="quit"}) end
    if Game.spriteIn then Game.spriteIn:clear(); Game.spriteIn:push({cmd="quit"}) end
end
