local Skin = require("battle_ui_skin")
local Scores = require("battle_scores")
local BattleHUD = {}
BattleHUD.__index = BattleHUD
BattleHUD.VICTORY_ENTRANCE = 0.45

local g
local CHAR = "[^\128-\191][\128-\191]*"
local PROMPT_LIMIT = 12
local SCORE_ROWS = 6
local STATE_TAGS = {
    mojado = { "MOJADO", { 0.45, 0.80, 1.00 } },
    congelado = { "CONGELADO", { 0.62, 0.94, 1.00 } },
    enjabonado = { "ENJABONADO", { 0.67, 0.95, 0.91 } },
    aceitoso = { "ACEITOSO", { 1.00, 0.82, 0.49 } },
    caliente = { "CALIENTE", { 1.00, 0.64, 0.45 } },
    oscuro = { "OSCURO", { 0.83, 0.72, 1.00 } },
    ruidoso = { "RUIDOSO", { 1.00, 0.75, 0.94 } },
    pegajoso = { "PEGAJOSO", { 0.76, 0.94, 0.55 } },
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(v, hi))
end

-- Keep the original prompt for the judge and use the font's Spanish repertoire on screen.
function BattleHUD.displayText(text)
    text = (text or ""):gsub("[%c]+", " "):gsub("…", "..."):gsub("–", "-"):gsub("—", "-")
    return (text:gsub(CHAR, function(char)
        local first, second = char:byte(1, 2)
        if #char == 1 and first >= 32 and first <= 126 then return char end
        if #char == 2 and (first == 195 or (first == 194 and second >= 160)) then return char end
        return ""
    end))
end

local function fit(text, font, width)
    if font:getWidth(text) <= width then return text end
    while text ~= "" and font:getWidth(text .. "...") > width do
        text = text:gsub(CHAR .. "$", "")
    end
    return text .. "..."
end

local function label(font, text, x, y, width, align, color)
    g.setFont(font)
    g.setColor(color or Skin.cream)
    g.printf(text, x, math.floor(y), width, align or "left")
end

local function oneLine(font, text, x, y, width, align, color)
    label(font, fit(BattleHUD.displayText(text), font, width), x, y, width, align, color)
end

local function drawName(font, text, centerX, centerY, width)
    text = BattleHUD.displayText(text)
    local textWidth = font:getWidth(text)
    local scale = math.min(1, width / math.max(1, textWidth))
    g.setColor(Skin.cream)
    g.print(text, font, math.floor(centerX - textWidth * scale / 2),
        math.floor(centerY - font:getHeight() * scale / 2), 0, scale, scale)
end

local function drawBar(x, y, w, h, ratio, color)
    g.setColor(0.58, 0.37, 0.20)
    g.rectangle("fill", x, y, w, h, h / 2)
    g.setColor(0.16, 0.087, 0.048)
    g.rectangle("fill", x + 1, y + 1, w - 2, h - 2, (h - 2) / 2)
    local filled = (w - 6) * clamp(ratio, 0, 1)
    if filled > 0 then
        g.setColor(color)
        g.rectangle("fill", x + 3, y + 3, filled, h - 6, 2)
        g.setColor(1, 0.95, 0.72, 0.32)
        g.rectangle("fill", x + 3, y + 3, filled, 1, 1)
    end
end

local function drawMusicNoteIcon(x, y, muted)
    g.setColor(muted and Skin.muted or Skin.gold)
    g.ellipse("fill", x + 3, y + 12, 3.5, 2.5)
    g.ellipse("fill", x + 12, y + 10, 3.5, 2.5)
    g.setLineWidth(2)
    g.line(x + 6, y + 12, x + 6, y + 3, x + 15, y + 1, x + 15, y + 10)
    g.line(x + 6, y + 5, x + 15, y + 3)
    if muted then
        g.setColor(1, 0.44, 0.45)
        g.line(x, y + 1, x + 17, y + 14)
    end
    g.setLineWidth(1)
end

function BattleHUD.new(fonts)
    g = love.graphics
    return setmetatable({ fonts = fonts, input = "", promptOpen = false, hits = {} }, BattleHUD)
end

function BattleHUD:openPrompt()
    self.promptOpen = true
    love.keyboard.setTextInput(true)
end

function BattleHUD:closePrompt(clear)
    self.promptOpen = false
    if clear then self.input = "" end
    love.keyboard.setTextInput(false)
end

function BattleHUD.canSubmit(text)
    local trimmed = text:match("^%s*(.-)%s*$")
    local _, count = trimmed:gsub(CHAR, "")
    return count >= 2 and count <= PROMPT_LIMIT
end

function BattleHUD.limitPrompt(text)
    text = text:gsub("[%c]+", " "):match("^%s*(.-)%s*$")
    local count = 0
    return (text:gsub(CHAR, function(char)
        count = count + 1
        return count <= PROMPT_LIMIT and char or ""
    end))
end

function BattleHUD:addText(text)
    if not self.promptOpen then return end
    local _, count = self.input:gsub(CHAR, "")
    for char in text:gsub("[%c]+", " "):gmatch(CHAR) do
        if count >= PROMPT_LIMIT then break end
        self.input = self.input .. char
        count = count + 1
    end
end

function BattleHUD:backspace()
    if self.promptOpen then self.input = self.input:gsub(CHAR .. "$", "") end
end

local function contains(mx, my, x, y, w, h)
    return mx ~= nil and mx >= x and mx <= x + w and my >= y and my <= y + h
end

function BattleHUD:hitTest(mx, my)
    for _, hit in ipairs(self.hits) do
        if contains(mx, my, hit.x, hit.y, hit.w, hit.h) then
            return hit.action
        end
    end
end

function BattleHUD:_buttonFace(action, x, y, w, h, enabled, spell)
    Skin.wood(g, x, y, w, h)
    local hovered = enabled and contains(self.pointerX, self.pointerY, x, y, w, h)
    if spell or hovered then
        g.setColor(hovered and Skin.gold or (enabled and { 0.54, 0.57, 0.28 } or { 0.43, 0.38, 0.24 }))
        g.rectangle("fill", x + 3, y + 3, w - 6, h - 7, 7)
        g.setColor(hovered and { 0.28, 0.37, 0.16 } or (enabled and { 0.22, 0.31, 0.14 } or { 0.25, 0.23, 0.15 }))
        g.rectangle("fill", x + 5, y + 5, w - 10, h - 11, 5)
    end
    if enabled then self.hits[#self.hits + 1] = { action = action, x = x, y = y, w = w, h = h } end
end

function BattleHUD:_button(action, text, x, y, w, h, enabled, spell)
    self:_buttonFace(action, x, y, w, h, enabled, spell)
    local font = spell and (self.fonts.story or self.fonts.heading) or self.fonts.body
    local inset = 5
    if action == "conjure" then
        Skin.spark(g, x + 17, y + h / 2 - 1, 5, enabled and Skin.gold or Skin.muted)
        inset = 26
    end
    oneLine(font, text, x + inset, y + (h - font:getHeight()) / 2 - 1, w - inset - 5, "center",
        enabled and Skin.cream or Skin.muted)
end

function BattleHUD:drawTopBar(state, w)
    self.hits = {}
    self.pointerX, self.pointerY = state.pointerX, state.pointerY
    local f = self.fonts
    local inBattle = state.mode == "battle"
    local contextFont = f.story or f.heading
    local context = BattleHUD.displayText(state.context)
    local chipW = math.min(contextFont:getWidth(context) + 55, w * (inBattle and 0.30 or 0.43))
    Skin.wood(g, 14, 11, chipW, 34)
    Skin.sprig(g, 24, 31, -0.2, 0.64)
    Skin.pin(g, 14 + chipW - 10, 28)
    oneLine(contextFont, context, 49, 27 - contextFont:getHeight() / 2, chipW - 52, "left", Skin.cream)

    local right = w - 14
    if state.canStartBattle or state.battlePhase == "player_turn" then
        local text = state.mode == "explore" and "Combate [Tab]" or "Mapa [Esc]"
        local width = f.body:getWidth(text) + 24
        right = right - width
        self:_button("map", text, right, 11, width, 34, true)
        right = right - 8
    end
    local music = "Música"
    local musicW = f.body:getWidth(music) + 43
    right = right - musicW
    self:_buttonFace("music", right, 11, musicW, 34, true)
    drawMusicNoteIcon(right + 12, 21, state.musicOff)
    oneLine(f.body, music, right + 35, 28 - f.body:getHeight() / 2, musicW - 39, "left", Skin.cream)

    if state.canOpenScores then
        local text = "Puntajes [F3]"
        local width = f.body:getWidth(text) + 24
        right = right - width - 8
        self:_button("scores", text, right, 11, width, 34, true)
    end
    if state.totalScore and state.battlePhase ~= "ritual" then
        local text = ("%d pts"):format(state.totalScore)
        local width = f.body:getWidth(text) + 22
        right = right - width - 8
        Skin.wood(g, right, 11, width, 34)
        label(f.body, text, right, 28 - f.body:getHeight() / 2, width, "center", Skin.gold)
    end

    if state.toast and state.battlePhase ~= "ritual" then
        local left = 14 + chipW + 12
        local room = right - left - 12
        if room < 80 then return end
        local toast = fit(BattleHUD.displayText(state.toast), f.body, room - 22)
        local tw = f.body:getWidth(toast) + 22
        local tx = clamp((w - tw) / 2, left, left + room - tw)
        Skin.paper(g, tx, 12, tw, 32)
        label(f.body, toast, tx + 11, 28 - f.body:getHeight() / 2, tw - 22, "center", Skin.ink)
    end
end

function BattleHUD:drawExploreBar(w, h)
    local f = self.fonts.small
    local walk = "Caminar"
    local keys = { "WASD", "Flechas" }
    local width = f:getWidth(walk) + f:getWidth(keys[1]) + f:getWidth(keys[2]) + 80
    local x, y = w - width - 14, h - 43
    Skin.wood(g, x, y, width, 33)
    Skin.sprig(g, x + 11, y + 22, -0.28, 0.50)
    local textY = y + (33 - f:getHeight()) / 2
    label(f, walk, x + 32, textY, f:getWidth(walk) + 2, "left", Skin.cream)
    local keyX = x + 41 + f:getWidth(walk)
    for _, key in ipairs(keys) do
        local keyW = f:getWidth(key) + 12
        Skin.paper(g, keyX, y + 6, keyW, 21)
        label(f, key, keyX, textY, keyW, "center", Skin.ink)
        keyX = keyX + keyW + 4
    end
end

function BattleHUD:drawCompletoPickup(w, h, image)
    local title, detail = "¡Completo recogido!", "El próximo rival empezará con la mitad de su vida."
    local heading, body = self.fonts.heading, self.fonts.body
    local width = math.max(heading:getWidth(title), body:getWidth(detail)) + 76
    local x, y = math.floor((w - width) / 2), h - 48
    Skin.wood(g, x, y, width, 42)
    Skin.paper(g, x + 5, y + 5, 47, 32)
    local iw, ih = image:getDimensions()
    local scale = math.min(35 / iw, 24 / ih)
    g.setColor(1, 1, 1, 1)
    g.draw(image, x + 29, y + 21, 0, scale, scale, iw / 2, ih / 2)
    label(heading, title, x + 61, y + 3, width - 67, "left", Skin.cream)
    label(body, detail, x + 61, y + 3 + heading:getHeight(), width - 67, "left", Skin.cream)
end

function BattleHUD:layoutPortrait(name, centerX, w, h)
    local font = self.fonts.story or self.fonts.heading
    local size = math.floor(clamp(52 + (h - 540) * 0.16, 52, 86))
    local width = clamp(font:getWidth(BattleHUD.displayText(name)) + 28, size + 12, w * 0.24)
    return { x = math.floor(clamp(centerX - width / 2, 16, w - width - 16)),
        y = math.floor(54 + clamp((h - 540) * 0.04, 0, 18)), w = width, h = size + 28, size = size }
end

local function drawFramedPortrait(image, faceX, y, size, accent)
    g.setColor(0.12, 0.07, 0.05, 0.75)
    g.rectangle("fill", faceX - 2, y + 2, size + 4, size + 4, 3)
    g.setColor(accent or Skin.gold)
    g.rectangle("fill", faceX - 2, y - 2, size + 4, size + 4, 3)
    g.setColor(0.16, 0.08, 0.06)
    g.rectangle("fill", faceX, y, size, size)
    if image then
        local iw, ih = image:getDimensions()
        local scale = size / math.max(iw, ih)
        g.setColor(1, 1, 1)
        g.draw(image, faceX + size / 2, y + size / 2, 0, scale, scale, iw / 2, ih / 2)
    end
end

function BattleHUD:drawPortrait(name, image, card, active)
    local x, y, w, size = card.x, card.y, card.w, card.size
    local faceX = math.floor(x + (w - size) / 2)
    local font = self.fonts.story or self.fonts.heading
    Skin.wood(g, x, y + size + 2, w, 26)
    drawName(font, name, x + w / 2, y + size + 14, w - 16)
    drawFramedPortrait(image, faceX, y, size, active and { 1, 0.67, 0.34 })
    if not image then
        local initial = BattleHUD.displayText(name):match(CHAR) or "?"
        oneLine(font, initial, faceX, y + (size - font:getHeight()) / 2, size, "center", Skin.cream)
    end
end

local function easeSlide(t)
    return 1 - (1 - clamp(t, 0, 1)) ^ 3
end

local function drawVersusHalf(image, left, color, top, bottom, w, h, arrival, shake)
    g.stencil(function()
        if left then
            g.polygon("fill", 0, 0, top, 0, bottom, h, 0, h)
        else
            g.polygon("fill", top, 0, w, 0, w, h, bottom, h)
        end
    end, "replace", 1)
    g.setStencilTest("equal", 1)
    local r, gc, b = color[1], color[2], color[3]
    g.setColor(r * 0.21, gc * 0.21, b * 0.21)
    g.rectangle("fill", 0, 0, w, h)
    if image then
        local iw, ih = image:getDimensions()
        local size = math.max(w * 0.70, h * 1.12)
        local centerX = w * (left and 0.265 or 0.735)
        local direction = left and -1 or 1
        local x = centerX + direction * (w * 0.37 * (1 - arrival) + shake)
        g.setColor(1, 1, 1)
        g.draw(image, x, h * 0.45, 0, size / iw, size / ih, iw / 2, ih / 2)
    end
    g.setStencilTest()
end

function BattleHUD:drawVersus(pudu, portraits, rivalName, rivalColor, w, h, progress, impactAt, shakeEnabled)
    self.hits = {}
    local arrival = easeSlide(progress / impactAt)
    local impact = clamp((progress - impactAt) / 0.19, 0, 1)
    local burst = progress >= impactAt and (1 - impact) ^ 2 or 0
    local shake = shakeEnabled and math.sin(impact * 27) * burst * 20 or 0
    local rival = portraits and ((progress >= impactAt and portraits.shout) or portraits.idle or portraits.shout)
    local top, bottom = w * 0.61, w * 0.39
    local cx, cy = w * 0.5, h * 0.49
    local heroColor = { 0.86, 0.65, 0.32 }
    local color = rivalColor or Skin.gold
    local title = self.fonts.versus or self.fonts.title
    local names = self.fonts.versusName or self.fonts.heading

    g.push("all")
    g.setShader()
    g.setBlendMode("alpha")
    drawVersusHalf(pudu, true, heroColor, top, bottom, w, h, arrival, shake)
    drawVersusHalf(rival, false, color, top, bottom, w, h, arrival, shake)
    if not self.versusShade then
        self.versusShade = g.newMesh({
            { 0, 0, 0, 0, 0.045, 0.026, 0.032, 0 }, { 1, 0, 0, 0, 0.045, 0.026, 0.032, 0 },
            { 0, 1, 0, 0, 0.045, 0.026, 0.032, 0.86 }, { 1, 1, 0, 0, 0.045, 0.026, 0.032, 0.86 },
        }, "strip", "static")
    end
    g.setColor(1, 1, 1)
    g.draw(self.versusShade, 0, h * 0.56, 0, w, h * 0.44)

    g.setColor(0.08, 0.035, 0.035)
    g.polygon("fill", top - 10, 0, top + 10, 0, bottom + 10, h, bottom - 10, h)
    g.setColor(0.98, 0.64 + burst * 0.22, 0.30 + burst * 0.33)
    local cut = 2 + burst * 5
    g.polygon("fill", top - cut, 0, top + cut, 0, bottom + cut, h, bottom - cut, h)

    if burst > 0 then
        g.setColor(1, 0.85, 0.54, burst * 0.78)
        for i = 1, 12 do
            local angle = i * math.pi / 6 + 0.1
            local dx, dy = math.cos(angle), math.sin(angle)
            local inner = 34 + impact * 230
            local outer = inner + (55 + i % 4 * 20) * burst
            g.polygon("fill", cx + dx * inner - dy * 3, cy + dy * inner + dx * 3,
                cx + dx * outer, cy + dy * outer, cx + dx * inner + dy * 3, cy + dy * inner - dx * 3)
        end
    end

    local badgeW, badgeH = 158 + burst * 20, 78 + burst * 10
    Skin.wood(g, cx - badgeW / 2, cy - badgeH / 2, badgeW, badgeH)
    Skin.pin(g, cx - badgeW / 2 + 14, cy)
    Skin.pin(g, cx + badgeW / 2 - 14, cy)
    label(title, "VS", cx - badgeW / 2, cy - title:getHeight() / 2, badgeW, "center", Skin.cream)

    local nameY, nameH = h * 0.80, names:getHeight() + 18
    for _, name in ipairs({ { "Pudú", w * 0.215, heroColor }, { rivalName, w * 0.785, color } }) do
        local nameW = clamp(names:getWidth(BattleHUD.displayText(name[1])) + 76, 160, w * 0.36)
        local x = math.floor(name[2] - nameW / 2)
        Skin.wood(g, x, nameY, nameW, nameH)
        Skin.sprig(g, x + 13, nameY + nameH * 0.63, -0.24, 0.65)
        Skin.pin(g, x + nameW - 14, nameY + nameH / 2)
        drawName(names, name[1], x + nameW / 2, nameY + 7 + names:getHeight() / 2, nameW - 62)
        g.setColor(name[3])
        g.rectangle("fill", name[2] - 15, nameY + nameH - 6, 30, 1)
    end
    g.setColor(1, 0.93, 0.75, burst * 0.23)
    g.rectangle("fill", 0, 0, w, h)
    g.setColor(0.05, 0.028, 0.028, clamp((progress - 0.86) / 0.14, 0, 1))
    g.rectangle("fill", 0, 0, w, h)
    g.pop()
end

function BattleHUD:drawRivalStageBar(state, ex, ey, w)
    local f = self.fonts.small
    local x, y = clamp(ex - 78, 12, w - 168), ey + 52
    Skin.wood(g, x - 5, y - 21, 166, 37)
    Skin.pin(g, x + 5, y - 7)
    Skin.pin(g, x + 151, y - 7)
    drawBar(x + 10, y, 136, 10, state.enemyHp / state.enemyMaxHp, { 0.82, 0.36, 0.25 })
    oneLine(f, ("%d / %d PV"):format(state.enemyHp, state.enemyMaxHp), x + 12, y - 17, 132, "center", Skin.cream)

    local tags, seen = {}, {}
    for _, key in ipairs(state.stageStates) do
        local item = STATE_TAGS[key]
        if item then
            tags[#tags + 1] = item
            seen[item[1]] = true
        end
    end
    local status = BattleHUD.displayText(state.enemyStatusTag)
    if status ~= "" and not seen[status] then tags[#tags + 1] = { status, Skin.gold } end

    local rows, row = {}, { width = 0 }
    local room = math.min(w * 0.43, 420)
    for _, tag in ipairs(tags) do
        local text = fit(tag[1], f, 110)
        local width = f:getWidth(text) + 16
        if row.width + 6 + width > room and #row > 0 then
            rows[#rows + 1], row = row, { width = 0 }
        end
        row.width = row.width + (#row > 0 and 6 or 0) + width
        row[#row + 1] = { text = text, color = tag[2], width = width }
    end
    rows[#rows + 1] = row
    for i, pills in ipairs(rows) do
        local px = clamp(ex - pills.width / 2, 12, w - pills.width - 12)
        local py = y + 20 + (i - 1) * 24
        for _, pill in ipairs(pills) do
            Skin.wood(g, px, py, pill.width, 20)
            label(f, pill.text, px, py + (20 - f:getHeight()) / 2, pill.width, "center", pill.color)
            px = px + pill.width + 6
        end
    end
end

function BattleHUD:drawAnticipation(text, w, ex, ey, card)
    text = BattleHUD.displayText(text)
    if text == "" then return end
    local f = self.fonts.body
    local minX = math.ceil(w * 0.58)
    if card then minX = math.max(minX, math.ceil(card.x + card.w + 12)) end
    local maxW = math.min(250, w - minX - 16)
    if maxW < 70 then return end
    local width = clamp(f:getWidth(text) + 28, math.min(110, maxW), maxW)
    local _, lines = f:getWrap(text, width - 26)
    local limit = 2
    if #lines > limit then
        lines[limit] = fit(lines[limit] .. "...", f, width - 26)
    end
    local height = math.min(#lines, limit) * f:getHeight() + 16
    local x = clamp(ex - width / 2, minX, w - width - 16)
    local y = math.max(58, ey - 216)
    local tipX = clamp(ex, x + 16, x + width - 16)
    g.setColor(0.64, 0.44, 0.25)
    g.polygon("fill", tipX - 8, y + height - 2, tipX + 8, y + height - 2, tipX, y + height + 8)
    Skin.paper(g, x, y, width, height)
    for i = 1, math.min(#lines, limit) do
        label(f, lines[i], x + 13, y + 7 + (i - 1) * f:getHeight(), width - 26, "center", Skin.ink)
    end
end

local BUSY_TEXT = {
    battle_enter = "Entrando a la arena...",
    ritual = "Completa la secuencia con flechas o WASD",
    summon = "El Pudú suelta el hechizo.",
    enemy_counter = "Turno del rival...",
}

local function battleStrip(w, h)
    local width = math.min(860, w - 28)
    return (w - width) / 2, h - 86, width
end

function BattleHUD:drawBattleStrip(state, w, h)
    local f = self.fonts
    local title = f.story or f.heading
    local leftW, gap = 196, 10
    local x, y, width = battleStrip(w, h)
    Skin.wood(g, x, y, leftW, 78)
    local portrait = state.puduPortrait or state.portraits[state.mood or "happy"]
    local portraitX, portraitY = x + 40, y + 38
    local portraitRadius = 24
    g.setColor(0.14, 0.09, 0.05)
    g.circle("fill", portraitX, portraitY + 1, 29)
    g.setColor(0.73, 0.52, 0.29)
    g.circle("fill", portraitX, portraitY, 27)
    g.setColor(0.19, 0.26, 0.13)
    g.circle("fill", portraitX, portraitY, portraitRadius)
    if portrait then
        local pw, ph = portrait:getDimensions()
        local scale = state.puduPortrait and (2 * portraitRadius) / math.min(pw, ph) or 43 / math.max(pw, ph)
        g.stencil(function()
            g.circle("fill", portraitX, portraitY, portraitRadius)
        end, "replace", 1)
        g.setStencilTest("equal", 1)
        g.setColor(1, 1, 1)
        g.draw(portrait, portraitX, portraitY, 0, scale, scale, pw / 2, ph / 2)
        g.setStencilTest()
    end
    Skin.sprig(g, x + 29, y + 65, math.pi + 0.62, 0.78)
    Skin.pin(g, x + 181, y + 17)
    label(title, "Pudú", x + 78, y + 11, 94, "left", Skin.cream)
    oneLine(f.small, ("%d / 100 PV"):format(state.hp), x + 78, y + 36, 104, "left", Skin.muted)
    drawBar(x + 78, y + 53, 104, 12, state.hp / 100, { 0.55, 0.70, 0.32 })

    if state.battlePhase == "victory" or state.battlePhase == "defeat" then return end
    local rightX, rightW = x + leftW + gap, width - leftW - gap
    Skin.wood(g, rightX, y, rightW, 78)
    if state.battlePhase ~= "player_turn" then
        Skin.sprig(g, rightX + 14, y + 48, -0.34, 0.8)
        Skin.sprig(g, rightX + rightW - 14, y + 30, math.pi - 0.34, 0.8)
        local text = BUSY_TEXT[state.battlePhase]
        if state.arrowsDone then text = "El orbe está cargado." end
        if state.battlePhase == "impact_hold" then
            oneLine(title, state.summonName, rightX + 48, y + 12, rightW - 96, "center", Skin.cream)
            oneLine(f.body, state.narrator, rightX + 48, y + 44, rightW - 96, "center", Skin.muted)
        else
            if state.battlePhase == "summon" and state.summonName then text = state.summonName end
            oneLine(title, text, rightX + 48, y + (78 - title:getHeight()) / 2, rightW - 96, "center", Skin.cream)
        end
        return
    end

    local fieldX, fieldY = rightX + 13, y + 14
    local fieldW, fieldH = rightW - 165, 49
    Skin.paper(g, fieldX, fieldY, fieldW, fieldH, self.promptOpen)
    Skin.sprig(g, fieldX + 17, fieldY + 32, -0.74, 0.64, { 0.40, 0.45, 0.22 })
    local paperInset = fieldX + 42
    local paperEnd = fieldX + fieldW - 68
    local prompt = self.input == "" and "Escribe qué quieres invocar..." or BattleHUD.displayText(self.input)
    local textW = f.body:getWidth(prompt)
    local textX = math.min(paperInset, paperEnd - textW - 5)
    local textY = fieldY + (fieldH - f.body:getHeight()) / 2
    g.push("all")
    g.intersectScissor(paperInset - 2, fieldY, paperEnd - paperInset + 2, fieldH)
    g.setFont(f.body)
    g.setColor(self.input == "" and { 0.38, 0.26, 0.15 } or Skin.ink)
    g.print(prompt, textX, math.floor(textY))
    if self.promptOpen and state.elapsed % 1 < 0.55 then
        local cursorX = self.input == "" and paperInset - 2 or textX + textW + 3
        g.setColor(Skin.ink)
        g.rectangle("fill", cursorX, textY, 1.5, f.body:getHeight())
    end
    g.pop()
    local _, count = self.input:gsub(CHAR, "")
    label(f.small, ("%d/%d"):format(count, PROMPT_LIMIT), paperEnd, fieldY + (fieldH - f.small:getHeight()) / 2,
        56, "right", Skin.ink)
    self.hits[#self.hits + 1] = { action = "prompt", x = fieldX, y = fieldY, w = fieldW, h = fieldH }
    self:_button("conjure", "Conjurar", rightX + rightW - 141, fieldY, 128, fieldH, BattleHUD.canSubmit(self.input), true)
end

function BattleHUD:drawVictory(state, w, h)
    self.hits = {}
    self.pointerX, self.pointerY = state.pointerX, state.pointerY
    local f = self.fonts
    local age = state.victoryElapsed
    local arrival = easeSlide(age / BattleHUD.VICTORY_ENTRANCE)

    g.setColor(0.09, 0.05, 0.04, 0.68 * arrival)
    g.rectangle("fill", 0, 0, w, h)

    local panelW, panelH = 760, 368
    local x = math.floor((w - panelW) / 2)
    local y = math.floor((h - panelH) / 2 + (1 - arrival) * 54)
    local sparkAge = clamp((age - 0.08) / 1.35, 0, 1)
    if sparkAge > 0 and sparkAge < 1 then
        local spread = easeSlide(sparkAge)
        local color = { 1, 0.80, 0.42, spread * (1 - sparkAge) }
        for i = 1, 18 do
            local angle = i * math.pi / 9
            local sx = w / 2 + math.cos(angle) * (panelW / 2 + 36 + spread * (28 + i % 3 * 12))
            local sy = y + panelH / 2 + math.sin(angle) * (panelH / 2 + 30 + spread * 40)
            Skin.spark(g, sx, sy, (4 + i % 4) * (1 - sparkAge), color)
        end
    end

    Skin.wood(g, x, y, panelW, panelH)
    Skin.pin(g, x + 14, y + 14)
    Skin.pin(g, x + panelW - 14, y + 14)
    Skin.pin(g, x + 14, y + panelH - 14)
    Skin.pin(g, x + panelW - 14, y + panelH - 14)

    local faceSize = math.floor(244 + 24 * arrival)
    local faceCenterX, faceCenterY = x + 162, y + panelH / 2
    drawFramedPortrait(state.puduPortrait or state.portraits.happy,
        faceCenterX - faceSize / 2, faceCenterY - faceSize / 2, faceSize)
    Skin.spark(g, faceCenterX + faceSize / 2 - 8, faceCenterY - faceSize / 2 + 12,
        6 + 2 * math.sin(age * 5))

    local textX, textW = x + 332, panelW - 362
    local title = state.campaignComplete and "¡Aventura completada!" or "¡Victoria!"
    drawName(f.victoryTitle or f.versus or f.title, title, textX + textW / 2, y + 64, textW)
    oneLine(f.story or f.heading, state.rivalName, textX, y + 102, textW, "center", Skin.gold)

    if state.lastPrompt then
        Skin.paper(g, textX, y + 142, textW, 61)
        label(f.small, "Último hechizo", textX + 12, y + 149, textW - 24, "center", Skin.ink)
        oneLine(f.body, state.lastPrompt, textX + 12, y + 174, textW - 24, "center", Skin.ink)
    end
    local _, lines = f.body:getWrap(BattleHUD.displayText(state.speech), textW - 24)
    for i = 1, math.min(2, #lines) do
        local line = i == 2 and #lines > 2 and fit(lines[i] .. "...", f.body, textW - 24) or lines[i]
        label(f.body, line, textX + 12, y + 219 + (i - 1) * f.body:getHeight(), textW - 24, "center", Skin.muted)
    end

    if state.score then
        label(f.heading, ("Puntaje final  %d pts"):format(state.totalScore), textX, y + 256, textW, "center", Skin.gold)
        local detail = ("Flechas %d  |  Prompts %d"):format(state.score.arrowPoints, state.score.promptPoints)
        oneLine(f.body, detail, textX, y + 280, textW, "center", Skin.cream)
    end

    local buttonW = state.campaignComplete and 200 or 148
    local buttonLabel = state.campaignComplete and "Cruzar el portal" or "Aceptar"
    self:_button("map", buttonLabel, textX + (textW - buttonW) / 2, y + 314, buttonW, 38, true, true)
end

function BattleHUD:drawDefeat(state, w, h)
    local f = self.fonts
    local x, y, width = battleStrip(w, h)
    local panelX, panelW = x + 206, width - 206
    local heading = f.story or f.heading
    Skin.wood(g, panelX, y, panelW, 78)
    local textX, textW = panelX + 16, panelW - 296
    oneLine(heading, "El Pudú necesita un respiro", textX, y + 6, textW, "left", Skin.cream)
    local summary = state.totalScore and ("Puntaje final  %d pts"):format(state.totalScore) or state.lastPrompt
    if summary then oneLine(f.body, summary, textX, y + 31, textW, "left", Skin.gold) end
    local _, lines = f.small:getWrap(BattleHUD.displayText(state.speech), textW)
    local speechY = y + (summary and 48 or 36)
    for i = 1, math.min(2, #lines) do
        local line = i == 2 and #lines > 2 and fit(lines[i] .. "...", f.small, textW) or lines[i]
        label(f.small, line, textX, speechY + (i - 1) * f.small:getHeight(), textW, "left", Skin.muted)
    end
    self:_button("map", "Volver al mapa", x + width - 271, y + 21, 133, 36, true)
    self:_button("retry", "Reintentar", x + width - 130, y + 21, 115, 36, true, true)
end

function BattleHUD.scorePageCount(entries)
    return math.max(1, math.ceil(entries / SCORE_ROWS))
end

function BattleHUD:drawScores(history, page, w, h, saveFailed)
    self.hits = {}
    local f = self.fonts
    g.setColor(0.12, 0.07, 0.04, 0.76)
    g.rectangle("fill", 0, 0, w, h)
    local panelW, panelH = math.min(820, w - 48), 420
    local x, y = math.floor((w - panelW) / 2), math.floor((h - panelH) / 2)
    Skin.wood(g, x, y, panelW, panelH)
    Skin.pin(g, x + 14, y + 14)
    label(f.story or f.title, "Puntajes de batalla", x + 27, y + 18, panelW - 170, "left", Skin.cream)
    self:_button("close_scores", "Cerrar [Esc]", x + panelW - 124, y + 14, 106, 34, true)

    local boardX, boardY, boardW = x + 20, y + 62, panelW - 40
    Skin.paper(g, boardX, boardY, boardW, 292)
    local function column(text, font, rowY, start, width, align, color)
        oneLine(font, text, boardX + boardW * start, rowY, boardW * width, align, color or Skin.ink)
    end
    local headerY = boardY + 13
    local rivalX, rivalW = 0.025, 0.36
    local arrowsX, arrowsW = 0.39, 0.22
    local promptX, promptW = 0.61, 0.18
    local totalX, totalW = 0.79, 0.185
    column("Rival y resultado", f.heading, headerY, rivalX, rivalW, "left")
    column("Flechas", f.heading, headerY, arrowsX, arrowsW, "center")
    column("Prompts", f.heading, headerY, promptX, promptW, "center")
    column("Total", f.heading, headerY, totalX, totalW, "center")

    if #history == 0 then
        label(f.body, "Tus batallas terminadas aparecerán aquí.", boardX, boardY + 130, boardW, "center", Skin.ink)
    end
    local last = #history - (page - 1) * SCORE_ROWS
    for row = 1, math.min(SCORE_ROWS, last) do
        local entry = history[last - row + 1]
        local rowY = boardY + 41 + (row - 1) * 40
        g.setColor(0.36, 0.22, 0.12, 0.24)
        g.line(boardX + 16, rowY, boardX + boardW - 16, rowY)
        column(entry.rival, f.body, rowY + 3, rivalX, rivalW, "left")
        column(entry.won and "Victoria" or "Derrota", f.small, rowY + 20, rivalX, rivalW, "left",
            entry.won and { 0.24, 0.36, 0.15 } or { 0.50, 0.24, 0.17 })
        column(("%d pts / %d ac."):format(entry.arrowPoints, entry.arrowHits), f.body, rowY + 11, arrowsX, arrowsW, "center")
        column(("%d pts"):format(entry.promptPoints), f.body, rowY + 11, promptX, promptW, "center")
        column(("%d pts"):format(Scores.total(entry)), f.heading, rowY + 10, totalX, totalW, "center")
    end

    local pages = BattleHUD.scorePageCount(#history)
    if pages > 1 then
        self:_button("score_newer", "Más recientes", x + 20, y + 371, 122, 31, page > 1)
        self:_button("score_older", "Más antiguos", x + panelW - 142, y + 371, 122, 31, page < pages)
        label(f.small, ("Página %d de %d"):format(page, pages), x + 146, y + 364, panelW - 292, "center", Skin.cream)
    end
    if saveFailed then
        label(f.small, "Hay puntajes pendientes de guardar.", x + 146, y + 384, panelW - 292, "center", Skin.gold)
    end
end

return BattleHUD
