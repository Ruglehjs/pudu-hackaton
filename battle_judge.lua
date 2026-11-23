-- Deterministic combat rules. This module also runs under plain LuaJIT.
local json = require("json")
local function loadRules()
    if love and love.filesystem then
        return json.decode(assert(love.filesystem.read("battle_rules.json")))
    end
    local file = assert(io.open("battle_rules.json", "rb"))
    local body = file:read("*a")
    file:close()
    return json.decode(body)
end
local rules = loadRules()
local Judge = {}

local accents = {
    ["á"]="a", ["é"]="e", ["í"]="i", ["ó"]="o", ["ú"]="u", ["ü"]="u", ["ñ"]="n",
    ["Á"]="a", ["É"]="e", ["Í"]="i", ["Ó"]="o", ["Ú"]="u", ["Ü"]="u", ["Ñ"]="n",
}
local uppercase = {["á"]="Á", ["é"]="É", ["í"]="Í", ["ó"]="Ó", ["ú"]="Ú", ["ü"]="Ü", ["ñ"]="Ñ"}
local charPattern = "[^\128-\191][\128-\191]*"
local function normalize(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("\204[\128-\191]", ""):gsub("\205[\128-\175]", "")
    return (s:gsub(charPattern, accents):lower():gsub("[^a-z0-9]+", " "):match("^%s*(.-)%s*$"))
end

-- The JSON decoder can receive opaque bytes from a broken local bridge. Give
-- LÖVE's font renderer valid UTF-8 even when clipping such a response.
local function validUtf8(text)
    local parts, since, i = {}, 1, 1
    while i <= #text do
        local a, b, c, d = text:byte(i, i + 3)
        local width = 0
        if a < 128 then width = 1
        elseif b and b >= 128 and b <= 191 then
            if a >= 194 and a <= 223 then width = 2
            elseif c and c >= 128 and c <= 191 then
                if a >= 224 and a <= 239 and not (a == 224 and b < 160 or a == 237 and b >= 160) then
                    width = 3
                elseif d and d >= 128 and d <= 191 and a >= 240 and a <= 244
                        and not (a == 240 and b < 144 or a == 244 and b > 143) then
                    width = 4
                end
            end
        end
        if width == 0 then
            parts[#parts + 1] = text:sub(since, i - 1) .. "?"
            i = i + 1
            since = i
        else
            i = i + width
        end
    end
    if #parts == 0 then return text end
    parts[#parts + 1] = text:sub(since)
    return table.concat(parts)
end
local function utf8Clip(s, limit)
    s = validUtf8(s):gsub("[%z\1-\31\127]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local n, shortEnd = 0, 1
    for pos in s:gmatch("()" .. charPattern) do
        n = n + 1
        if n == limit - 2 then shortEnd = pos end
        if n > limit then return s:sub(1, shortEnd - 1) .. "..." end
    end
    return s
end
local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end
local function hasWords(text, words)
    local padded = " " .. text .. " "
    for _, word in ipairs(words or {}) do
        if padded:find(" " .. word .. " ", 1, true) then return true end
    end
    return false
end
local function exactSprite(text)
    local first, rest = text:match("^(%S+)%s+(.+)$")
    while first and contains(rules.prefixes, first) do
        text = rest
        first, rest = text:match("^(%S+)%s+(.+)$")
    end
    for id, aliases in pairs(rules.sprites) do
        if text == normalize(id) or contains(aliases, text) then return id end
    end
    return "none"
end
local function invalidPrompt(text)
    if contains(rules.reject_exact, text) or hasWords(text, rules.reject_phrases) or hasWords(text, {"hack"}) then return true end
    if not text:find(" ") then
        return (#text >= 5 and text == text:sub(1, 1):rep(#text))
            or (#text >= 5 and not text:find("[aeiou0-9]"))
            or (text:match("^%d+$") ~= nil)
    end
    return false
end
local function activeStates(encounter)
    local active = {}
    for _, id in ipairs(encounter.stage_states or {}) do active[id] = true end
    for _, state in ipairs(rules.states) do
        if contains(state.reactions, encounter.current_reaction) then active[state.id] = true end
    end
    local function inspectProp(value)
        local name = normalize(value)
        for _, state in ipairs(rules.states) do
            if hasWords(name, state.words) or hasWords(name, state.props) then active[state.id] = true end
        end
        if hasWords(name, {"papel", "papeles", "formulario", "formularios", "paper"}) then active.papel = true end
    end
    for _, prop in ipairs(encounter.active_props or {}) do
        if type(prop) == "table" then
            inspectProp(prop.name)
            inspectProp(prop.id)
            inspectProp(prop.existing_sprite)
        else
            inspectProp(prop)
        end
    end
    if encounter.id == "fila_tramite" and (tonumber(encounter.turn) or 1) > 1 then active.papel = true end
    return active
end

local function comboFor(text, encounter)
    local active = activeStates(encounter)
    for _, combo in ipairs(rules.combos) do
        if hasWords(text, combo.words) then
            for _, prior in ipairs(combo.prior) do
                if active[prior] then return combo end
            end
        end
    end
end
local function applyCombo(r, combo)
    r.combo_triggered, r.combo_name = combo.id, combo.name
    r.comedy_score, r.comedy_badge = 10, "¡COMBO 10/10!"
    r.outcome_type, r.is_critical = "super_funny_ko", true
    r.damage_to_enemy = math.max(combo.min_damage, r.damage_to_enemy)
    r.heal_pudu, r.damage_to_pudu = 0, 0
    r.enemy_reaction, r.anticipation_line = combo.reaction, combo.anticipation
    r.narrator_text, r.particle_fx = combo.narrator, combo.fx
    if combo.sprite ~= "none" then r.sprite_mode, r.existing_sprite = "existing", combo.sprite end
end

function Judge.standaloneLuaEvaluate(rawPrompt, encounter)
    encounter = encounter or {}
    rawPrompt = utf8Clip(type(rawPrompt) == "string" and rawPrompt or "", 300)
    local text = normalize(rawPrompt)
    local rival = rules.rivals[encounter.id] or rules.rivals.nino_helado
    local sprite = exactSprite(text)
    local r = {
        approved = true, reject_reason = "", summon_name = utf8Clip(rawPrompt, 34),
        sprite_mode = sprite == "none" and "generate_live" or "existing", existing_sprite = sprite,
        sprite_prompt = "A curious enchanted stage prop with expressive eyes, pixel art facing right",
        keep_purple = hasWords(text, {"morado", "morada", "violeta", "uva", "berenjena", "pulpo"}),
        delivery_style = "throw_arc", particle_fx = "confetti", sfx = "sfx_boing", reaction_sfx = "sfx_rimshot",
        outcome_type = "creative_chaos", is_critical = false, damage_to_enemy = 30, damage_to_pudu = 0, heal_pudu = 0,
        enemy_reaction = "confused", pudu_reaction = "happy", enemy_speech = "¡Me distraje aplaudiendo y me caí de poto!",
        narrator_text = rival.gag, enemy_counter_name = rival.counter, enemy_counter_line = rival.line,
        enemy_counter_damage = 11, enemy_counter_fx = "wind", comedy_score = 6, comedy_badge = "¡BUENA TALLA!",
        keep_prop_on_stage = false, prop_anchor = "ground_enemy", status_tag = "DESPISTADO",
        ritual_theme_color = "#68CEA4", adds_stage_state = "none", combo_triggered = "none", combo_name = "",
        anticipation_line = "¿Quién pidió ese paquete?",
    }
    if invalidPrompt(text) then
        r.approved, r.damage_to_enemy, r.anticipation_line = false, 0, ""
        r.enemy_speech, r.narrator_text, r.status_tag, r.comedy_score = "", "", "", 1
        r.reject_reason = "¡El árbitro pide una invocación! Hasta una cuchara tiene más magia."
        return r
    end
    for _, state in ipairs(rules.states) do
        if hasWords(text, state.words) then
            r.adds_stage_state, r.status_tag = state.id, state.tag
            r.keep_prop_on_stage, r.narrator_text, r.particle_fx = true, state.narrator, state.fx
            break
        end
    end
    local combo = comboFor(text, encounter)
    if combo then
        applyCombo(r, combo)
        r.enemy_speech = "¡Paren el ensayo! ¡Ese golpe sí venía en serio!"
        r.status_tag = "EN COMBO"
    elseif hasWords(text, rules.heal) then
        r.outcome_type, r.damage_to_enemy, r.heal_pudu = "heal_pudu", 0, 24
        r.keep_prop_on_stage, r.adds_stage_state = false, "none"
        r.delivery_style, r.prop_anchor, r.status_tag = "buff_pudu", "near_pudu", "ALIVIO"
        r.particle_fx, r.sfx, r.pudu_reaction = "hearts", "heal", "dancing"
        r.narrator_text = "El Pudú recupera el color y ensaya una cueca en dos pezuñas."
    elseif hasWords(text, rival.backfire) then
        r.outcome_type, r.damage_to_enemy, r.damage_to_pudu = "backfire", 0, 14
        r.enemy_reaction, r.enemy_speech, r.pudu_reaction = "laughing", rival.backfire_line, "shocked"
        r.reaction_sfx, r.status_tag, r.comedy_score, r.comedy_badge = "sfx_laugh", "A CARCAJADAS", 4, "¡AUTOGOL!"
        r.narrator_text = "El rival da las gracias. Al Pudú le llega el rebote."
    elseif hasWords(text, rival.weak) or hasWords(text, encounter.weaknesses) then
        r.is_critical, r.damage_to_enemy, r.outcome_type = true, 88, "super_funny_ko"
        r.comedy_score, r.comedy_badge = 9, "¡QUÉ PUNTERÍA!"
        r.enemy_reaction, r.enemy_speech = rival.reaction, rival.speech
        if r.adds_stage_state == "none" then r.status_tag, r.narrator_text = "EN APUROS", rival.speech end
    elseif r.adds_stage_state ~= "none" then
        r.outcome_type, r.damage_to_enemy, r.comedy_score = "effective", 48, 7
        if r.adds_stage_state == "mojado" then r.enemy_reaction = "wet" end
        if r.adds_stage_state == "congelado" then r.enemy_reaction = "frozen" end
    else
        for _, gag in ipairs(rules.improv) do
            if hasWords(text, gag.words) then
                r.enemy_speech, r.narrator_text = gag.speech, gag.narrator
                break
            end
        end
    end
    if sprite == "rain_cloud" and not combo then
        r.delivery_style, r.prop_anchor, r.sfx = "overhead_weather", "above_enemy", "sfx_rain_pour"
        if r.enemy_reaction == "crying" then r.reaction_sfx = "sfx_cry_wah" end
    end
    return r
end

local function bounded(value, lo, hi)
    return math.min(hi, math.max(lo, math.floor(value)))
end
function Judge.ensureResultCoherence(raw, prompt, encounter)
    local r = Judge.standaloneLuaEvaluate(prompt, encounter)
    -- Invalid local input never spends a turn, even if a remote service approves.
    if type(raw) ~= "table" or type(raw.approved) ~= "boolean" or not r.approved then return r end
    local expectedCombo = comboFor(normalize(prompt), encounter or {})
    for key, base in pairs(r) do
        local value = raw[key]
        if type(value) == type(base) then
            if rules.limits[key] then
                local clean = utf8Clip(value, rules.limits[key])
                if clean ~= "" then r[key] = clean end
            elseif rules.enums[key] then
                if contains(rules.enums[key], value) then r[key] = value end
            elseif key == "adds_stage_state" then
                if value == "none" then r[key] = value end
                for _, state in ipairs(rules.states) do
                    if value == state.id then r[key] = value end
                end
            elseif key == "existing_sprite" then
                if rules.sprites[value] or value == "none" then r[key] = value end
            elseif key == "ritual_theme_color" then
                if value:match("^#%x%x%x%x%x%x$") then r[key] = value end
            elseif key ~= "combo_triggered" and key ~= "approved" then r[key] = value end
        end
    end
    r.enemy_counter_damage = bounded(r.enemy_counter_damage, 5, 22)
    r.comedy_score = bounded(r.comedy_score, 1, 10)
    r.damage_to_enemy = bounded(r.damage_to_enemy, 0, 100)
    r.status_tag = r.status_tag:gsub(charPattern, uppercase):upper()
    r.combo_triggered, r.combo_name = "none", ""
    r.reject_reason = ""
    local known = exactSprite(normalize(prompt))
    r.existing_sprite, r.sprite_mode = known, known == "none" and "generate_live" or "existing"
    local _, wordCount = r.sprite_prompt:gsub("%S+", "")
    if wordCount < 10 or wordCount > 16 or not r.sprite_prompt:lower():find("facing right", 1, true) then
        r.sprite_prompt = "A curious enchanted stage prop with expressive eyes, pixel art facing right"
    end
    local backfireDamage, heal = r.damage_to_pudu, r.heal_pudu
    r.is_critical, r.damage_to_pudu, r.heal_pudu = false, 0, 0
    if not expectedCombo and raw.combo_triggered ~= "none" then
        -- A cloud judge can recognize a new synonym, but it still needs the setup.
        local active = activeStates(encounter or {})
        for _, combo in ipairs(rules.combos) do
            if combo.id == raw.combo_triggered then
                for _, prior in ipairs(combo.prior) do
                    if active[prior] then expectedCombo = combo; break end
                end
            end
            if expectedCombo then break end
        end
    end
    if expectedCombo then
        applyCombo(r, expectedCombo)
    elseif r.outcome_type == "super_funny_ko" then
        r.is_critical, r.damage_to_enemy = true, bounded(r.damage_to_enemy, 85, 100)
    elseif r.outcome_type == "heal_pudu" then
        r.damage_to_enemy, r.heal_pudu = 0, bounded(heal, 18, 32)
        r.delivery_style, r.prop_anchor = "buff_pudu", "near_pudu"
    elseif r.outcome_type == "backfire" then
        r.damage_to_enemy, r.damage_to_pudu = bounded(r.damage_to_enemy, 0, 5), bounded(backfireDamage, 10, 18)
    elseif r.outcome_type == "effective" then
        r.damage_to_enemy = bounded(r.damage_to_enemy, 42, 56)
    else
        r.damage_to_enemy = bounded(r.damage_to_enemy, 20, 40)
    end
    return r
end
return Judge
