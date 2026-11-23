local Skin = require("battle_ui_skin")
local BattleHUD = {}
BattleHUD.__index = BattleHUD

local g
local CHAR = "[^\128-\191][\128-\191]*"
local PROMPT_LIMIT = 68
local INK = { 0.98, 0.98, 1 }
local MUTED = { 0.68, 0.78, 0.91 }
local GOLD = { 1, 0.85, 0.48 }
local BLUE_TOP = { 0.13, 0.26, 0.50 }
local BLUE_BOTTOM = { 0.035, 0.075, 0.19 }
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
    g.setColor(color or INK)
    g.printf(text, x, math.floor(y), width, align or "left")
end

local function oneLine(font, text, x, y, width, align, color)
    label(font, fit(BattleHUD.displayText(text), font, width), x, y, width, align, color)
end

local function drawExploreWindow(x, y, w, h)
    g.setColor(0.015, 0.025, 0.06, 0.55)
    g.rectangle("fill", x + 2, y + 4, w, h, 8)
    g.setColor(0.025, 0.04, 0.09)
    g.rectangle("fill", x, y, w, h, 7)
    for i = 0, 4 do
        local mix = i / 4
        local bandH = (h - 8) / 5
        g.setColor(BLUE_TOP[1] + (BLUE_BOTTOM[1] - BLUE_TOP[1]) * mix,
            BLUE_TOP[2] + (BLUE_BOTTOM[2] - BLUE_TOP[2]) * mix,
            BLUE_TOP[3] + (BLUE_BOTTOM[3] - BLUE_TOP[3]) * mix)
        g.rectangle("fill", x + 4, y + 4 + i * bandH, w - 8, bandH)
    end
    g.setColor(0.82, 0.89, 1, 0.96)
    g.setLineWidth(2)
    g.rectangle("line", x + 3, y + 3, w - 6, h - 6, 5)
    g.setLineWidth(1)
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

local function drawMusicNoteIcon(x, y, muted, inBattle)
    g.setColor(muted and (inBattle and Skin.muted or MUTED) or (inBattle and Skin.gold or GOLD))
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
    return count >= 2
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

function BattleHUD:hitTest(mx, my)
    for _, hit in ipairs(self.hits) do
        if mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h then
            return hit.action
        end
    end
end

function BattleHUD:_button(action, text, x, y, w, h, enabled, style)
    local font = self.fonts.body
    local color = INK
    local inset = 5
    if style == "explore" then
        drawExploreWindow(x, y, w, h)
    else
        Skin.wood(g, x, y, w, h)
        color = Skin.cream
        if style == "spell" then
            font = self.fonts.story or self.fonts.heading
            color = enabled and Skin.cream or Skin.muted
            g.setColor(enabled and { 0.54, 0.57, 0.28 } or { 0.43, 0.38, 0.24 })
            g.rectangle("fill", x + 3, y + 3, w - 6, h - 7, 7)
            g.setColor(enabled and { 0.22, 0.31, 0.14 } or { 0.25, 0.23, 0.15 })
            g.rectangle("fill", x + 5, y + 5, w - 10, h - 11, 5)
            if action == "conjure" then
                Skin.spark(g, x + 17, y + h / 2 - 1, 5, enabled and Skin.gold or Skin.muted)
                inset = 26
            end
        end
    end
    oneLine(font, text, x + inset, y + (h - font:getHeight()) / 2 - 1, w - inset - 5, "center", color)
    if enabled then self.hits[#self.hits + 1] = { action = action, x = x, y = y, w = w, h = h } end
end

function BattleHUD:drawTopBar(state, w)
    self.hits = {}
    local f = self.fonts
    local inBattle = state.mode == "battle"
    local contextFont = inBattle and (f.story or f.heading) or f.body
    local context = BattleHUD.displayText(state.context)
    local chipW = math.min(contextFont:getWidth(context) + (inBattle and 55 or 42), w * 0.30)
    if inBattle then
        Skin.wood(g, 14, 11, chipW, 34)
        Skin.sprig(g, 24, 31, -0.2, 0.64)
        Skin.pin(g, 14 + chipW - 10, 28)
        oneLine(contextFont, context, 49, 27 - contextFont:getHeight() / 2, chipW - 52, "left", Skin.cream)
    else
        drawExploreWindow(14, 11, chipW, 34)
        g.setColor(state.contextColor or GOLD)
        g.circle("fill", 30, 28, 4)
        oneLine(contextFont, context, 42, 28 - contextFont:getHeight() / 2, chipW - 36)
    end

    local right = w - 14
    if state.canStartBattle or state.battlePhase == "player_turn" then
        local text = state.mode == "explore" and "Combate [Tab]" or "Mapa [Esc]"
        local width = f.body:getWidth(text) + 24
        right = right - width
        self:_button("map", text, right, 11, width, 34, true, inBattle and "wood" or "explore")
        right = right - 8
    end
    local music = "Música"
    local musicW = f.body:getWidth(music) + 43
    right = right - musicW
    if inBattle then Skin.wood(g, right, 11, musicW, 34) else drawExploreWindow(right, 11, musicW, 34) end
    drawMusicNoteIcon(right + 12, 21, state.musicOff, inBattle)
    oneLine(f.body, music, right + 35, 28 - f.body:getHeight() / 2, musicW - 39, "left", inBattle and Skin.cream or INK)
    self.hits[#self.hits + 1] = { action = "music", x = right, y = 11, w = musicW, h = 34 }

    if state.toast and state.battlePhase ~= "ritual" then
        local left = 14 + chipW + 12
        local room = right - left - 12
        if room < 80 then return end
        local toast = fit(BattleHUD.displayText(state.toast), f.body, room - 22)
        local tw = f.body:getWidth(toast) + 22
        local tx = clamp((w - tw) / 2, left, left + room - tw)
        if inBattle then Skin.paper(g, tx, 12, tw, 32) else drawExploreWindow(tx, 12, tw, 32) end
        label(f.body, toast, tx + 11, 28 - f.body:getHeight() / 2, tw - 22, "center", inBattle and Skin.ink or GOLD)
    end
end

function BattleHUD:drawExploreBar(w, h)
    local text = "WASD / Flechas para caminar"
    local f = self.fonts.small
    local width = f:getWidth(text) + 26
    drawExploreWindow(w - width - 14, h - 40, width, 30)
    label(f, text, w - width - 14, h - 25 - f:getHeight() / 2, width, "center")
end

function BattleHUD:layoutRivalPortrait(name, ex, w, h)
    local font = self.fonts.story or self.fonts.heading
    local size = math.floor(clamp(52 + (h - 540) * 0.16, 52, 86))
    local width = clamp(font:getWidth(BattleHUD.displayText(name)) + 28, size + 12, w * 0.24)
    return { x = math.floor(clamp(ex - width / 2, 16, w - width - 16)),
        y = math.floor(54 + clamp((h - 540) * 0.04, 0, 18)), w = width, h = size + 28, size = size }
end

function BattleHUD:drawRivalPortrait(state, card)
    local x, y, w, size = card.x, card.y, card.w, card.size
    local faceX = math.floor(x + (w - size) / 2)
    local font = self.fonts.story or self.fonts.heading
    Skin.wood(g, x, y + size + 2, w, 26)
    oneLine(font, state.rivalName, x + 8, y + size + 14 - font:getHeight() / 2, w - 16, "center", Skin.cream)

    g.setColor(0.12, 0.07, 0.05, 0.75)
    g.rectangle("fill", faceX - 2, y + 2, size + 4, size + 4, 3)
    g.setColor(state.rivalShouts and { 1, 0.67, 0.34 } or Skin.gold)
    g.rectangle("fill", faceX - 2, y - 2, size + 4, size + 4, 3)
    g.setColor(0.16, 0.08, 0.06)
    g.rectangle("fill", faceX, y, size, size)
    local image = state.rivalPortrait
    if image then
        local iw, ih = image:getDimensions()
        g.setColor(1, 1, 1)
        g.draw(image, faceX, y, 0, size / iw, size / ih)
    else
        local initial = BattleHUD.displayText(state.rivalName):match(CHAR) or "?"
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

    local badgeW, badgeH = 79 + burst * 10, 39 + burst * 5
    g.setColor(0.95, 0.69, 0.37)
    g.polygon("fill", cx - badgeW, cy, cx - 46, cy - badgeH, cx + 46, cy - badgeH,
        cx + badgeW, cy, cx + 46, cy + badgeH, cx - 46, cy + badgeH)
    g.setColor(0.13, 0.065, 0.065)
    g.polygon("fill", cx - badgeW + 6, cy, cx - 44, cy - badgeH + 4, cx + 44, cy - badgeH + 4,
        cx + badgeW - 6, cy, cx + 44, cy + badgeH - 4, cx - 44, cy + badgeH - 4)
    label(title, "VS", cx - badgeW, cy - title:getHeight() / 2, badgeW * 2, "center", Skin.cream)

    local nameY, nameW = h * 0.82, w * 0.36
    for _, name in ipairs({ { "Pudú", w * 0.215, heroColor }, { rivalName, w * 0.785, color } }) do
        local x = math.floor(name[2] - nameW / 2)
        oneLine(names, name[1], x, nameY, nameW, "center", Skin.cream)
        g.setColor(name[3])
        g.rectangle("fill", name[2] - 26, nameY + names:getHeight() + 5, 52, 2)
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
            g.setColor(0.19, 0.12, 0.075)
            g.rectangle("fill", px, py, pill.width, 20, 7)
            g.setColor(pill.color)
            g.rectangle("line", px + 0.5, py + 0.5, pill.width - 1, 19, 7)
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
    ritual = "Cargando el hechizo...",
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
    local portrait = state.portraits[state.mood or "happy"]
    local portraitX, portraitY = x + 40, y + 38
    g.setColor(0.14, 0.09, 0.05)
    g.circle("fill", portraitX, portraitY + 1, 29)
    g.setColor(0.73, 0.52, 0.29)
    g.circle("fill", portraitX, portraitY, 27)
    g.setColor(0.19, 0.26, 0.13)
    g.circle("fill", portraitX, portraitY, 24)
    if portrait then
        local pw, ph = portrait:getDimensions()
        local scale = 43 / math.max(pw, ph)
        g.setColor(1, 1, 1)
        g.draw(portrait, portraitX, portraitY, 0, scale, scale, pw / 2, ph / 2)
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
    local paperEnd = fieldX + fieldW - 12
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
    self.hits[#self.hits + 1] = { action = "prompt", x = fieldX, y = fieldY, w = fieldW, h = fieldH }
    self:_button("conjure", "Conjurar", rightX + rightW - 141, fieldY, 128, fieldH, BattleHUD.canSubmit(self.input), "spell")
end

function BattleHUD:drawVictoryOrDefeat(state, w, h)
    local won = state.battlePhase == "victory"
    if not won and state.battlePhase ~= "defeat" then return end
    local f = self.fonts
    local x, y, width = battleStrip(w, h)
    local panelX, panelW = x + 206, width - 206
    local heading = f.story or f.heading
    Skin.wood(g, panelX, y, panelW, 78)
    local title = won and "¡Victoria!" or "El Pudú necesita un respiro"
    if state.campaignComplete then title = "¡Aventura completada!" end
    local textX, textW = panelX + 16, panelW - 296
    oneLine(heading, title, textX, y + 6, textW, "left", Skin.cream)
    if state.lastPrompt then
        oneLine(f.body, state.lastPrompt, textX, y + 31, textW, "left", Skin.cream)
    end
    local _, lines = f.small:getWrap(BattleHUD.displayText(state.speech), textW)
    local speechY = y + (state.lastPrompt and 48 or 36)
    for i = 1, math.min(2, #lines) do
        local line = i == 2 and #lines > 2 and fit(lines[i] .. "...", f.small, textW) or lines[i]
        label(f.small, line, textX, speechY + (i - 1) * f.small:getHeight(), textW, "left", Skin.muted)
    end
    self:_button("map", "Volver al mapa", x + width - 271, y + 21, 133, 36, true, "wood")
    self:_button("retry", won and "Revancha" or "Reintentar", x + width - 130, y + 21, 115, 36, true, "spell")
end

return BattleHUD
