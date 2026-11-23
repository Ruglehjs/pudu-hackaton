-- From the project root: luajit tests/test_phase04_ui.lua
local SpellRitual = require("spell_ritual")
local BattleHUD = require("battle_hud")
local Judge = require("battle_judge")
local Encounters = require("encounters")

local CHAR = "[^\128-\191][\128-\191]*"
local function checkLatin1(text, description)
    for char in text:gmatch(CHAR) do
        local a, b = char:byte(1, 2)
        assert(#char == 1 and a < 128 or #char == 2 and (a == 195 or a == 194 and b >= 160), description)
    end
end

for _, name in ipairs({ "spell_ritual.lua", "battle_hud.lua", "encounters.lua", "main.lua" }) do
    local input = assert(io.open(name, "rb"))
    for line in input:lines() do
        local visible = line
        if name == "battle_hud.lua" and line:find(":gsub", 1, true) then
            -- These three input characters are mapped to punctuation before drawing.
            visible = visible:gsub("\226\128[\147\148\166]", "")
        end
        checkLatin1(visible, name .. ": " .. line)
    end
    input:close()
end

local nothing = function() end
local activeFont = {
    getWidth = function(_, value) return #value * 6 end,
    getHeight = function() return 14 end,
    getWrap = function(_, value) return #value * 6, { value } end,
}
local fonts = { small = activeFont, body = activeFont, heading = activeFont, title = activeFont }
local polygons, printed = {}, {}
local function recordPrint(text)
    checkLatin1(text, text)
    printed[#printed + 1] = text
end
love = {
    keyboard = { setTextInput = nothing, isDown = function() return true end },
    graphics = setmetatable({
        polygon = function(mode, ...)
            local args = { ... }
            assert(mode == "fill" and (#args == 6 or #args == 8), "polígono de flecha cóncavo")
            polygons[#polygons + 1] = args
        end,
        print = recordPrint,
        printf = recordPrint,
        getWidth = function() return 1280 end,
        getHeight = function() return 720 end,
        getDimensions = function() return 1280, 720 end,
    }, { __index = function() return nothing end }),
}
local audio = { play = nothing, playArrowChime = nothing, playTrack = nothing }
local function playBatch(ritual)
    local last = #ritual.sequence
    for i = ritual.cursor, last do
        ritual:onKeyPressed(ritual.sequence[i].direction, audio)
    end
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.0001, ("esperaba %.2f, recibí %.2f"):format(expected, actual))
end

local ritual = SpellRitual.new()
ritual:start("nube de lluvia")
assert(#ritual.sequence == 4)
local layout = ritual:_getTileLayout(1280, 720)
assert(layout.panelY >= 126 and layout.statusY >= 56)
assert(layout.panelY - layout.statusY - layout.statusH >= 42)
ritual:draw(1280, 720, 346, 658, fonts)
assert(#polygons >= 8 and printed[1] ~= nil)
local first = ritual.sequence[1].direction
ritual:onKeyPressed(first == "up" and "left" or "up", audio)
assert(ritual.cursor == 1 and ritual.sequence[1].shake == 1 and ritual.misses == 1)
local wasd = { up = "w", left = "a", down = "s", right = "d" }
ritual:onKeyPressed(wasd[first], audio)
assert(ritual.cursor == 2 and ritual:getLastDirection() == first)
near(ritual:getMultiplier(), 1.08)
playBatch(ritual)
assert(#ritual.sequence == 6 and ritual.sequence[5].bonus and ritual.sequence[6].bonus)
assert(ritual.overchargeBannerTimer > 0)
near(ritual:getMultiplier(), 1.32)
local words = 0
for _, item in ipairs(ritual.sparkles) do
    if item.kind == "word" then words = words + 1 end
end
assert(words == 1)
ritual:setAiReady({ ritual_theme_color = "#123456" }, true)
playBatch(ritual)
assert(#ritual.sequence == 8 and ritual.sequence[7].bonus and ritual.sequence[8].bonus)
playBatch(ritual)
assert(#ritual.sequence == 10 and ritual.sequence[9].bonus and ritual.sequence[10].bonus)
playBatch(ritual)
assert(ritual.cursor == 11 and not ritual.readyToUnleash)
near(ritual:getMultiplier(), 1 + 8 * 0.08 + 2 * 0.04)
for i = 3, #ritual.sequence do
    local direction = ritual.sequence[i].direction
    assert(direction ~= ritual.sequence[i - 1].direction or direction ~= ritual.sequence[i - 2].direction)
end
for _, size in ipairs({ { 1280, 720 }, { 960, 540 } }) do
    local extended = ritual:_getTileLayout(size[1], size[2])
    assert(extended.x >= 12 and extended.x + extended.w < size[1] * 0.58)
end
ritual:setSpriteReady()
ritual:update(0.01, nil, 346, 658)
assert(ritual.readyToUnleash and not ritual:isComplete())
local lights = {}
ritual:collectLights(lights)
assert(#lights == 1 and lights[1].y < 658)
ritual:update(0.30)
assert(ritual:isComplete())

ritual:start("prueba sin respuesta")
for _ = 1, 4 do playBatch(ritual) end
ritual:update(11.99)
assert(not ritual.readyToUnleash)
ritual:update(0.02)
assert(ritual.readyToUnleash)
ritual:start("prueba de ritmo libre")
ritual:setAiReady({}, false)
ritual:update(30)
assert(ritual.cursor == 1 and not ritual.readyToUnleash)
playBatch(ritual)
assert(#ritual.sequence == 4 and ritual.readyToUnleash)
ritual:cancel()
assert(not ritual:isComplete() and not ritual:onKeyPressed("w", audio))

local hud = BattleHUD.new(fonts)
hud:openPrompt()
hud:addText("áñ")
hud:backspace()
assert(hud.input == "á" and not BattleHUD.canSubmit(hud.input))
hud:addText("é")
assert(BattleHUD.canSubmit(hud.input) and not BattleHUD.canSubmit("a "))
hud:addText(string.rep("ü", 80))
assert(hud.input == "áé" .. string.rep("ü", 66))
assert(BattleHUD.displayText("Pudú \226\134\145 \240\159\148\165\226\128\166") == "Pudú  ...")
hud:closePrompt(true)
assert(hud.input == "" and not hud.promptOpen)
local kid = Encounters.getByIndex(1)
local state = {
    mode = "battle", battlePhase = "player_turn", context = kid.name, hp = 100,
    enemyHp = 80, enemyMaxHp = kid.maxHp, stageStates = { "mojado", "enjabonado" },
    toast = "Aviso", portraits = {}, elapsed = 0,
}
hud:drawTopBar(state, 1280)
hud:drawBattleStrip(state, 1280, 720)
hud:drawRivalStageBar(state, 921, 360, 1280)
assert(hud:hitTest(1240, 28) == "map")
assert(hud:hitTest(1220, 670) == nil)
state.battlePhase = "ritual"
printed = {}
hud:drawTopBar(state, 1280)
assert(not table.concat(printed, " "):find("Aviso", 1, true))

-- Drive the actual main.lua input and turn callbacks without starting a window or workers.
require("main")
local function upvalue(fn, key)
    for i = 1, 40 do
        local name, value = debug.getupvalue(fn, i)
        if name == key then return value end
    end
    error("No se encontró " .. key)
end
local game = upvalue(love.update, "Game")
local function channel()
    local messages = {}
    return {
        push = function(_, msg) messages[#messages + 1] = msg end,
        pop = function() return table.remove(messages, 1) end,
    }
end
game.mode = "battle"
game.cli = { mock = true, autoPrompts = {} }
game.autoPromptIndex = 1
game.audio, game.hud, game.ritual = audio, hud, ritual
game.assets = { encounters = {}, gags = {}, props = {} }
game.battleFX = require("battle_fx").new()
game.battleIn, game.battleOut = channel(), channel()
game.spriteIn, game.spriteOut = channel(), channel()

local function advance(seconds)
    for _ = 1, math.ceil(seconds / 0.05) do love.update(0.05) end
end
local function restart()
    love.keypressed("6", "6", false)
    advance(1)
    assert(game.battlePhase == "player_turn" and game.battle.speech == Encounters.getByIndex(6).introLine)
end
local function submit(text)
    love.textinput(text)
    love.keypressed("return", "return", false)
    assert(game.battlePhase == "ritual")
    return assert(game.battleIn:pop())
end
local function answer(request, source, result)
    game.battleOut:push({ kind = "prompt_result", uid = request.uid, result = result, source = source or "lua" })
    advance(0.05)
end
local function cast(text, expectedReaction)
    local request = submit(text)
    local result = Judge.standaloneLuaEvaluate(text, request.encounter)
    answer(request, "lua", result)
    assert(game.battlePhase == "ritual")
    if expectedReaction then assert(game.enemyReaction == expectedReaction) end
    assert(game.battle.enemyHp == request.encounter.hp)
    for _, item in ipairs(ritual.sequence) do love.keypressed(item.direction, item.direction, false) end
    advance(1.10)
    if game.battlePhase == "enemy_counter" then advance(1.15) end
end
local hint = Encounters.getByIndex(6).semiHintLine
restart()
cast("silla")
assert(game.battle.nonCritMissCount == 1 and game.battle.speech ~= hint)
cast("poción")
assert(game.battle.nonCritMissCount == 1 and game.battle.speech ~= hint)
cast("lápiz")
assert(game.battlePhase == "player_turn" and game.battle.nonCritMissCount == 0)
assert(not game.battle.pendingSemiHint and game.battle.speech == hint)
assert(game.battle.enemyHp == 30)
local hintBubble = game.battleFX.speech.enemy
assert(hintBubble.text == hint and hintBubble.duration == 5.2 and hintBubble.age < 0.4)
restart()
cast("silla")
cast("pintura", "scared")
assert(game.battle.nonCritMissCount == 0 and not game.battle.pendingSemiHint)
assert(game.battlePhase == "victory")
assert(game.defeatedMap.mimo_muro)
assert(game.battleFX.defeatFinale.reaction == game.battle.result.enemy_reaction)
state.battlePhase, state.lastPrompt = "victory", "pintura"
hud:drawTopBar(state, 1280)
hud:drawVictoryOrDefeat(state, 1280, 720)
for _, hit in ipairs(hud.hits) do
    if hit.action == "retry" then love.mousepressed(hit.x + hit.w / 2, hit.y + hit.h / 2, 1) end
end
assert(game.battlePhase == "versus" and not hud.promptOpen)
advance(1.25)
assert(game.battlePhase == "battle_enter" and not hud.promptOpen)
advance(1)
assert(game.battlePhase == "player_turn" and game.battle.turn == 1 and game.battle.hp == 100)

restart()
game.cli.mock = false
local online = submit("silla")
answer(online, "gemini", Judge.standaloneLuaEvaluate("silla", online.encounter))
assert(game.spriteIn:pop().uid == online.uid)
for _ = 1, 4 do playBatch(ritual) end
game.spriteOut:push({ kind = "sprite_ready", uid = online.uid - 1, ok = false })
advance(0.05)
assert(not ritual.readyToUnleash, "un sprite atrasado no puede liberar otro hechizo")
game.spriteOut:push({ kind = "sprite_ready", uid = online.uid, ok = false })
advance(0.05)
assert(ritual.readyToUnleash, "un fallo de sprite permite invocar con el fallback")

restart()
local lost = submit("lápiz")
for _ = 1, 4 do playBatch(ritual) end
advance(12.05)
assert(game.battle.decision and game.battle.decision.source == "lua")
answer(lost, "gemini", Judge.standaloneLuaEvaluate("pintura", lost.encounter))
assert(game.battle.decision.source == "lua", "un resultado atrasado no reemplaza el fallback")

love.keypressed("1", "1", false)
advance(1)
game.cli.mock = true
cast("calcetín", "laughing")
assert(game.battle.nonCritMissCount == 1 and game.battle.enemyHp == 90 and game.battle.hp < 100)

-- Osu! mouse targets (hit circle + slider) & extra arrow waves while waiting for live sprite
local osuRitual = SpellRitual.new()
osuRitual:start("ornitorrinco dj")
osuRitual:setAiReady({ ritual_theme_color = "#44DDAA" }, true)
osuRitual:update(0.40, nil, 346, 658, 134, audio)
assert(#osuRitual.osuTargets >= 1, "debe aparecer un objetivo Osu durante el ritual")
local firstTarget = osuRitual.osuTargets[1]
assert(osuRitual:onMousePressed(firstTarget.x, firstTarget.y, 1, audio))
assert(osuRitual.osuHits == 1 and osuRitual:getMultiplier() > 1.0)
osuRitual:onMouseMoved(500, 420)
assert(#osuRitual.cursorTrail == 1)
-- Finish all 10 arrows while sprite is still pending -> extra wave of 6 arrows spawns after pause
for _ = 1, 4 do playBatch(osuRitual) end
assert(osuRitual.cursor == 11 and not osuRitual.readyToUnleash)
osuRitual:update(0.65, nil, 346, 658, 134, audio)
assert(osuRitual.waveCount == 2 and #osuRitual.sequence == 6 and osuRitual.cursor == 1)
osuRitual:draw(1280, 720, 346, 658, fonts)

print("OK: ritual, Osu!, oleadas extra, sprites tardíos, timeout, carriles, UTF-8, anti-tofu y semi-pista de fase 04.")
