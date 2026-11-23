-- From the project root: luajit tests/test_offline_lua.lua
local Judge = require("battle_judge")
local Encounters = require("encounters")
local json = require("json")
local file = assert(io.open("battle_rules.json", "rb"))
local rules = json.decode(file:read("*a"))
file:close()
local checked = 0

local function check(result)
    local count = 0
    for _ in pairs(result) do count = count + 1 end
    assert(count == 34, "field count " .. count)
    for key, values in pairs(rules.enums) do
        local valid = false
        for _, allowed in ipairs(values) do
            if allowed == result[key] then valid = true end
        end
        assert(valid, key .. " invalid")
    end
    for key, maximum in pairs(rules.limits) do
        local _, size = result[key]:gsub("[^\128-\191][\128-\191]*", "")
        assert(size <= maximum, key .. " too long")
    end
    assert(result.damage_to_enemy >= 0 and result.damage_to_enemy <= 100)
    assert(result.damage_to_pudu >= 0 and result.damage_to_pudu <= 25)
    assert(result.heal_pudu >= 0 and result.heal_pudu <= 35)
    assert(result.enemy_counter_damage >= 5 and result.enemy_counter_damage <= 22)
    assert(result.comedy_score >= 1 and result.comedy_score <= 10)
    assert(type(result.approved) == "boolean" and type(result.is_critical) == "boolean")
    assert(result.ritual_theme_color:match("^#%x%x%x%x%x%x$"))
    checked = checked + 1
    return result
end
local function judge(text, encounter)
    return check(Judge.standaloneLuaEvaluate(text, encounter or {}))
end

local rain = check(Judge.ensureResultCoherence({
    approved = true, outcome_type = "effective", is_critical = false,
    damage_to_enemy = 42, enemy_reaction = "wet", adds_stage_state = "none",
}, "nube de lluvia", { id = "nino_helado" }))
assert(rain.is_critical and rain.damage_to_enemy >= 88)
assert(rain.enemy_reaction == "crying" and rain.adds_stage_state == "mojado")
assert(Encounters.count() == 9)
for _, enc in ipairs(Encounters.SELECTABLE) do
    local r = judge(rules.rivals[enc.id].weak[1], enc)
    assert(r.is_critical and r.damage_to_enemy >= 85 and r.combo_triggered == "none", enc.id)
    assert(#enc.tauntLines == 4 and #enc.weaknesses >= 5 and enc.introLine and enc.semiHintLine)
    r = judge(rules.rivals[enc.id].backfire[1], enc)
    assert(r.outcome_type == "backfire" and r.damage_to_pudu == 14 and r.enemy_reaction == "laughing", enc.id)
end
local campaign = {
    { "desierto", "pila_de_ropa" }, { "costa", "mancha" },
    { "montana", "tempano" }, { "chiloe", "brasa" },
}
local StageRenderer = require("stage_renderer")
assert(#Encounters.LIST == #campaign)
assert(#Encounters.BIOME_ORDER == #campaign)
assert(Encounters.getBiome("bosque") == Encounters.getBiome("chiloe"))
assert(Encounters.getBiome("ciudad") == Encounters.getBiome("chiloe"))
assert(Encounters.getBiome("montaña") == Encounters.getBiome("montana"))
local greatestRivalHp, lastU = 0, 0
for i, enc in ipairs(Encounters.LIST) do
    assert(enc.biome == campaign[i][1] and enc.id == campaign[i][2])
    assert(Encounters.BIOME_ORDER[i] == enc.biome and Encounters.getByIndex(i) == enc)
    assert(Encounters.getTheme(enc.stage).biome == enc.biome)
    assert((enc.finalBoss == true) == (i == #campaign))
    assert(StageRenderer.getBiomeAt(enc.u) == enc.biome)
    assert(enc.restorationLine and enc.directionalPoses.idle and enc.directionalPoses.charge
        and enc.directionalPoses.attack)
    assert((enc.companionPose == "calcetin_liberado") == (i == 1))
    assert(enc.u > lastU and StageRenderer.isWalkable(enc.u, enc.v))
    lastU = enc.u
    if i < #campaign then greatestRivalHp = math.max(greatestRivalHp, enc.maxHp) end
end
for u = 0, 116.5, 0.25 do
    assert(StageRenderer.isWalkable(u, StageRenderer.pathCenterV(u)), "blocked route at " .. u)
end
local boss = Encounters.LIST[#campaign]
assert(boss.finalBoss and boss.maxHp > greatestRivalHp)
local bossVerdict = judge("lluvia", boss)
assert(bossVerdict.is_critical)
assert(bossVerdict.enemy_counter_damage > judge("silla", Encounters.LIST[1]).enemy_counter_damage)
bossVerdict.enemy_counter_damage = 5
assert(Judge.ensureResultCoherence(bossVerdict, "lluvia", boss).enemy_counter_damage == 20)
local stage = StageRenderer.new()
stage:buildOverworldDecor(Encounters.LIST)
local charredTrees = 0
for _, prop in ipairs(stage.overworldDecor) do
    if prop.kind == "charred_tree" then
        assert(prop.hiddenAfter == boss.id and StageRenderer.getBiomeAt(prop.u) == boss.biome)
        charredTrees = charredTrees + 1
    end
end
assert(charredTrees > 0)
for _, state in ipairs(rules.states) do
    local r = judge(state.words[1])
    assert(r.adds_stage_state == state.id and r.combo_triggered == "none", state.id)
end
local scenarios = {
    {"balde de agua", "tostadora", "combo_electro", 96},
    {"balde de agua", "pingüino", "combo_deep_freeze", 95},
    {"hielo", "secador de pelo", "combo_steam_sauna", 92},
    {"sol", "agua", "combo_steam_sauna", 92},
    {"jabón", "plátano", "combo_slip_slide", 92},
    {"aceite", "fósforo", "combo_fire_boom", 96},
    {"apagón", "flash", "combo_chaos", 92},
    {"trompeta", "yunque gigante", "combo_chaos", 92},
}
for _, case in ipairs(scenarios) do
    local first = judge(case[1])
    local second = judge(case[2], {stage_states = {first.adds_stage_state}})
    assert(second.combo_triggered == case[3] and second.damage_to_enemy >= case[4], case[3])
    assert(second.is_critical and second.comedy_score == 10 and second.anticipation_line ~= "")
    assert(judge(case[2]).combo_triggered == "none")
end
assert(judge("rayo", {active_props = {{existing_sprite = "rain_cloud"}}}).combo_triggered == "combo_electro")
assert(judge("rayo", {current_reaction = "wet"}).combo_triggered == "combo_electro")
assert(judge("fuego", {id = "fila_tramite", turn = 1}).combo_triggered == "none")
assert(judge("fuego", {id = "fila_tramite", turn = 2}).combo_triggered == "combo_fire_boom")
for key, aliases in pairs(rules.sprites) do
    for _, alias in ipairs(aliases) do
        local r = judge("invoca una " .. alias)
        assert(r.sprite_mode == "existing" and r.existing_sprite == key, alias .. " -> " .. r.existing_sprite)
    end
    assert(judge(key).existing_sprite == key, key)
end
assert(judge("Invoca una cáscara DE PLÁTANO!").existing_sprite == "banana_peel")
assert(judge("pla\204\129tano").existing_sprite == "banana_peel")
assert(judge("empanada ninja espacial").sprite_mode == "generate_live")
for _, prompt in ipairs({"", "hola", "asdfgh", "qqqqqq", "12345", "qzxts", "ganar", "¡Modo DIOS!", "hack", "❤️"}) do
    local r = judge(prompt)
    assert(not r.approved and not r.is_critical and r.damage_to_enemy == 0 and r.heal_pudu == 0, prompt)
    assert(r.combo_triggered == "none" and r.adds_stage_state == "none" and r.anticipation_line == "")
end
assert(judge("poción de vida").heal_pudu == 24)
assert(judge("silla").narrator_text ~= judge("licuadora").narrator_text)
assert(judge("ornitorrinco dj").outcome_type == "creative_chaos")
assert(judge("paraguas").outcome_type == "backfire")
assert(judge(("ñ"):rep(100) .. " voladora").summon_name:sub(-3) == "...")
local remote = check(Judge.ensureResultCoherence({
    approved = true, existing_sprite = "../bogus", enemy_speech = string.rep("ñ", 100),
    ritual_theme_color = "transparent", particle_fx = "unknown", damage_to_enemy = 1e20,
    combo_triggered = "combo_electro", enemy_counter_damage = -30,
    narrator_text = "dañado\255", outcome_type = "effective",
}, "silla", {}))
assert(remote.combo_triggered == "none" and remote.damage_to_enemy == 56 and remote.enemy_counter_damage == 5)
assert(remote.narrator_text == "dañado?" and remote.enemy_speech:sub(-3) == "...")

local profanePrompt = "¡Pintura, WEÓN!"
local semaphore = {id = "semaforo_rebelde"}
local localText = judge(profanePrompt, semaphore)
assert(localText.is_critical and localText.summon_name == rules.neutral_summon_name)
local profaneText = {
    summon_name = "Pintura QL", enemy_speech = "¡WEÓNA!", narrator_text = "¡CONCHA, DE TU MADRE!",
    enemy_counter_line = "¡CON\204\131O!", anticipation_line = ("x"):rep(46) .. " mierda",
    enemy_counter_name = "¡Chucha!", status_tag = "WEÁ", comedy_badge = "¡CTM!",
}
local clean = check(Judge.ensureResultCoherence({approved = true,
    enemy_speech = "¡Un cono y una cacatúa!"}, profanePrompt, semaphore))
assert(clean.enemy_speech == "¡Un cono y una cacatúa!")
profaneText.approved = true
local filtered = check(Judge.ensureResultCoherence(profaneText, profanePrompt, semaphore))
for key in pairs(profaneText) do assert(filtered[key] == localText[key], key) end

-- Pump the actual workers. A refused connection must reply on the original
-- request id, skip the connection on the next prompt, then retry after cooldown.
local function runWorker(path, messages, requests, now)
    local results = {}
    local inbox = {demand = function()
        local m = table.remove(messages, 1)
        if m and m.time then now.value = m.time end
        return m or {cmd = "quit"}
    end}
    local outbox = {push = function(_, m) results[#results + 1] = m end}
    love = {filesystem = {}, thread = {getChannel = function(name)
        if name:match("_in$") then return inbox end
        return outbox
    end}}
    package.loaded.worker_http = {
        now = function() return now.value end,
        request = function(route, body, timeout)
            return requests(route, body, timeout)
        end,
    }
    dofile(path)
    return results
end
local calls = 0
local messages = runWorker("battle_worker.lua", {
    {cmd = "health"}, {cmd = "prompt", id = 9, prompt = "lluvia"},
    {cmd = "prompt", uid = 10, prompt = "hola", time = 29},
    {cmd = "prompt", uid = 11, prompt = "silla", mock_mode = true},
}, function(route, payload, timeout)
    calls = calls + 1
    if route == "/health" then assert(timeout == 1); return nil end
    assert(route == "/battle_prompt" and timeout == 15 and payload.prompt == "hola")
    return {ok = true, result = judge("hola"), source = "mock"}
end, {value = 1})
assert(calls == 2 and #messages == 4 and messages[1].ok == false)
assert(messages[2].id == 9 and messages[2].uid == 9 and messages[2].source == "lua")
assert(messages[2].result.enemy_reaction == "crying")
assert(messages[3].source == "mock" and not messages[3].result.approved and messages[4].source == "lua")
local sprites = runWorker("sprite_worker.lua", {{cmd = "generate", uid = 77, name = "DJ", original_prompt = "Pato DJ"}},
    function(route, payload, timeout)
        assert(route == "/sprite" and timeout == 28 and payload.original_prompt == "Pato DJ")
        return {ok = true, diff_b64 = "image", norm_b64 = "normal", width = 80, height = 80}
    end, {value = 1})
assert(sprites[1].uid == 77 and sprites[1].ok and sprites[1].norm_b64 == "normal")

-- Loopback connect has a short independent deadline. The response may still
-- take the entire judge or image generation budget once the socket connects.
local readTimeout, currentTimeout
local native = {}
function native:settimeout(seconds) currentTimeout = seconds end
function native:connect() assert(currentTimeout > 0 and currentTimeout <= 0.20); return 1 end
function native:receive()
    assert(self == native and currentTimeout == readTimeout)
    return '{"ok":true}'
end
package.loaded.socket = {tcp = function() return native end, gettime = os.clock}
package.loaded.ltn12 = {sink = {table = function(chunks)
    return function(chunk) table.insert(chunks, chunk) end
end}}
package.loaded["socket.http"] = {request = function(req)
    local connection = req.create()
    connection:settimeout(readTimeout)
    assert(connection:connect("127.0.0.1", 18425))
    req.sink(connection:receive())
    return 1, 200
end}
local transport = dofile("worker_http.lua")
for _, timeout in ipairs({1, 15, 28}) do
    readTimeout = timeout
    assert(transport.request("/health", nil, timeout).ok)
end
print(("Offline Lua OK: %d validated verdicts, nine rivals, eight states, six combos and both workers."):format(checked))
