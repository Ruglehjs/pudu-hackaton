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

local function drawFFWindow(x, y, w, h, top, bottom, alpha)
    top, bottom, alpha = top or BLUE_TOP, bottom or BLUE_BOTTOM, alpha or 1
    g.setColor(0.015, 0.025, 0.06, 0.55 * alpha)
    g.rectangle("fill", x + 2, y + 4, w, h, 8)
    g.setColor(0.025, 0.04, 0.09, alpha)
    g.rectangle("fill", x, y, w, h, 7)
    for i = 0, 4 do
        local mix = i / 4
        local bandH = (h - 8) / 5
        g.setColor(top[1] + (bottom[1] - top[1]) * mix, top[2] + (bottom[2] - top[2]) * mix,
            top[3] + (bottom[3] - top[3]) * mix, alpha)
        g.rectangle("fill", x + 4, y + 4 + i * bandH, w - 8, bandH)
    end
    g.setColor(0.82, 0.89, 1, 0.96 * alpha)
    g.setLineWidth(2)
    g.rectangle("line", x + 3, y + 3, w - 6, h - 6, 5)
    g.setLineWidth(1)
end

local function drawBar(x, y, w, h, ratio, color)
    g.setColor(0.025, 0.04, 0.09)
    g.rectangle("fill", x, y, w, h, 4)
    local filled = (w - 4) * clamp(ratio, 0, 1)
    if filled > 0 then
        g.setColor(color)
        g.rectangle("fill", x + 2, y + 2, filled, h - 4, 2)
        g.setColor(1, 1, 1, 0.27)
        g.rectangle("fill", x + 2, y + 2, filled, 1)
    end
    g.setColor(0.73, 0.82, 0.96, 0.55)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4)
end

local function drawMusicNoteIcon(x, y, muted)
    g.setColor(muted and MUTED or GOLD)
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

function BattleHUD:_button(action, text, x, y, w, h, enabled, accent)
    local f = self.fonts.body
    drawFFWindow(x, y, w, h, accent and { 0.34, 0.28, 0.18 }, accent and { 0.13, 0.10, 0.12 },
        enabled and 1 or 0.62)
    oneLine(f, text, x + 5, y + (h - f:getHeight()) / 2, w - 10, "center", enabled and (accent and GOLD or INK) or MUTED)
    if enabled then self.hits[#self.hits + 1] = { action = action, x = x, y = y, w = w, h = h } end
end

function BattleHUD:drawTopBar(state, w)
    self.hits = {}
    local f = self.fonts
    local context = BattleHUD.displayText(state.context)
    local chipW = math.min(f.body:getWidth(context) + 42, w * 0.30)
    drawFFWindow(14, 11, chipW, 34)
    g.setColor(state.contextColor or GOLD)
    g.circle("fill", 30, 28, 4)
    oneLine(f.body, context, 42, 28 - f.body:getHeight() / 2, chipW - 36)

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
    drawFFWindow(right, 11, musicW, 34)
    drawMusicNoteIcon(right + 12, 21, state.musicOff)
    oneLine(f.body, music, right + 35, 28 - f.body:getHeight() / 2, musicW - 39)
    self.hits[#self.hits + 1] = { action = "music", x = right, y = 11, w = musicW, h = 34 }
    local album = ("Álbum [J] (%d/%d)"):format(state.albumCount or 0, state.encounterCount or 9)
    local albumW = f.body:getWidth(album) + 24
    right = right - albumW - 8
    self:_button("album", album, right, 11, albumW, 34, true, true)

    if state.toast and state.battlePhase ~= "ritual" then
        local left = 14 + chipW + 12
        local room = right - left - 12
        if room < 80 then return end
        local toast = fit(BattleHUD.displayText(state.toast), f.body, room - 22)
        local tw = f.body:getWidth(toast) + 22
        local tx = clamp((w - tw) / 2, left, left + room - tw)
        drawFFWindow(tx, 12, tw, 32)
        label(f.body, toast, tx + 11, 28 - f.body:getHeight() / 2, tw - 22, "center", GOLD)
    end
end

function BattleHUD:drawExploreBar(w, h)
    local text = "WASD / Flechas para caminar"
    local f = self.fonts.small
    local width = f:getWidth(text) + 26
    drawFFWindow(w - width - 14, h - 40, width, 30)
    label(f, text, w - width - 14, h - 25 - f:getHeight() / 2, width, "center")
end

function BattleHUD:drawRivalStageBar(state, ex, ey, w)
    local f = self.fonts.small
    local x, y = clamp(ex - 78, 12, w - 168), ey + 52
    drawBar(x, y, 156, 14, state.enemyHp / state.enemyMaxHp, { 0.92, 0.41, 0.36 })
    oneLine(f, ("%d / %d PV"):format(state.enemyHp, state.enemyMaxHp), x, y - 15, 156, "center")

    local tags, seen = {}, {}
    for _, key in ipairs(state.stageStates) do
        local item = STATE_TAGS[key]
        if item then
            tags[#tags + 1] = item
            seen[item[1]] = true
        end
    end
    local status = BattleHUD.displayText(state.enemyStatusTag)
    if status ~= "" and not seen[status] then tags[#tags + 1] = { status, GOLD } end

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
            g.setColor(0.034, 0.066, 0.14, 0.97)
            g.rectangle("fill", px, py, pill.width, 20, 7)
            g.setColor(pill.color)
            g.rectangle("line", px + 0.5, py + 0.5, pill.width - 1, 19, 7)
            label(f, pill.text, px, py + (20 - f:getHeight()) / 2, pill.width, "center", pill.color)
            px = px + pill.width + 6
        end
    end
end

function BattleHUD:drawAnticipation(text, w, ex, ey)
    text = BattleHUD.displayText(text)
    if text == "" then return end
    local f = self.fonts.body
    local minX = math.ceil(w * 0.58)
    local maxW = math.min(250, w - minX - 16)
    local width = clamp(f:getWidth(text) + 28, 110, maxW)
    local _, lines = f:getWrap(text, width - 26)
    local limit = 2
    if #lines > limit then
        lines[limit] = fit(lines[limit] .. "...", f, width - 26)
    end
    local height = math.min(#lines, limit) * f:getHeight() + 16
    local x = clamp(ex - width / 2, minX, w - width - 16)
    local y = math.max(58, ey - 216)
    drawFFWindow(x, y, width, height)
    local tipX = clamp(ex, x + 16, x + width - 16)
    g.setColor(0.025, 0.04, 0.09)
    g.polygon("fill", tipX - 8, y + height - 1, tipX + 8, y + height - 1, tipX, y + height + 9)
    for i = 1, math.min(#lines, limit) do
        label(f, lines[i], x + 13, y + 8 + (i - 1) * f:getHeight(), width - 26, "center", GOLD)
    end
end

local BUSY_TEXT = {
    battle_enter = "Entrando a la arena...",
    ritual = "Aprieta las flechas o WASD para completar el hechizo.",
    summon = "El Pudú suelta el hechizo.",
    enemy_counter = "Turno del rival...",
}

local function battleStrip(w, h)
    local width = math.min(860, w - 28)
    return (w - width) / 2, h - 86, width
end

function BattleHUD:drawBattleStrip(state, w, h)
    local f = self.fonts
    local leftW, gap = 196, 8
    local x, y, width = battleStrip(w, h)
    drawFFWindow(x, y, leftW, 78)
    local portrait = state.portraits[state.mood or "happy"]
    g.setColor(0.045, 0.083, 0.18)
    g.rectangle("fill", x + 12, y + 12, 54, 54, 6)
    if portrait then
        local pw, ph = portrait:getDimensions()
        local scale = 48 / math.max(pw, ph)
        g.setColor(1, 1, 1)
        g.draw(portrait, x + 39, y + 39, 0, scale, scale, pw / 2, ph / 2)
    end
    label(f.heading, "PUDÚ", x + 76, y + 12, 108)
    oneLine(f.small, ("%d / 100 PV"):format(state.hp), x + 76, y + 33, 108, "left", MUTED)
    drawBar(x + 76, y + 51, 108, 11, state.hp / 100, { 0.36, 0.85, 0.59 })

    if state.battlePhase == "victory" or state.battlePhase == "defeat" then return end
    local rightX, rightW = x + leftW + gap, width - leftW - gap
    drawFFWindow(rightX, y, rightW, 78)
    if state.battlePhase ~= "player_turn" then
        local text = BUSY_TEXT[state.battlePhase]
        if state.arrowsDone then text = "El orbe está cargado." end
        if state.battlePhase == "impact_hold" then
            oneLine(f.heading, state.summonName, rightX + 24, y + 17, rightW - 48, "center", GOLD)
            oneLine(f.body, state.narrator, rightX + 24, y + 42, rightW - 48, "center")
        else
            if state.battlePhase == "summon" and state.summonName then text = state.summonName end
            oneLine(f.heading, text, rightX + 24, y + (78 - f.heading:getHeight()) / 2, rightW - 48, "center", GOLD)
        end
        return
    end

    local fieldX, fieldY = rightX + 13, y + 19
    local fieldW, fieldH = rightW - 160, 40
    g.setColor(0.024, 0.048, 0.13)
    g.rectangle("fill", fieldX, fieldY, fieldW, fieldH, 5)
    g.setColor(self.promptOpen and { 0.58, 0.74, 0.97 } or MUTED)
    g.rectangle("line", fieldX + 0.5, fieldY + 0.5, fieldW - 1, fieldH - 1, 5)
    local prompt = self.input == "" and "Escribe qué generar para vencer al rival..." or BattleHUD.displayText(self.input)
    local textW = f.body:getWidth(prompt)
    local textX = fieldX + 15 - math.max(0, textW - fieldW + 30)
    local textY = fieldY + (fieldH - f.body:getHeight()) / 2
    g.setScissor(fieldX + 8, fieldY, fieldW - 16, fieldH)
    g.setFont(f.body)
    g.setColor(self.input == "" and MUTED or INK)
    g.print(prompt, textX, math.floor(textY))
    if self.promptOpen and state.elapsed % 1 < 0.55 then
        local cursorX = self.input == "" and fieldX + 10 or textX + textW + 3
        g.setColor(GOLD)
        g.rectangle("fill", cursorX, textY, 1.5, f.body:getHeight())
    end
    g.setScissor()
    self.hits[#self.hits + 1] = { action = "prompt", x = fieldX, y = fieldY, w = fieldW, h = fieldH }
    self:_button("conjure", "CONJURAR", rightX + rightW - 137, fieldY, 124, 40, BattleHUD.canSubmit(self.input), true)
end

function BattleHUD:drawVictoryOrDefeat(state, w, h)
    local won = state.battlePhase == "victory"
    if not won and state.battlePhase ~= "defeat" then return end
    local f = self.fonts
    local x, y, width = battleStrip(w, h)
    local panelX, panelW = x + 204, width - 204
    drawFFWindow(panelX, y, panelW, 78)
    local title = won and "¡Victoria!" or "El Pudú necesita un respiro"
    if state.campaignComplete then title = "¡Aventura completada!" end
    oneLine(f.heading, title, panelX + 16, y + 12, panelW - 296, "left", GOLD)
    if state.lastPrompt then
        oneLine(f.body, state.lastPrompt, panelX + 16, y + 33, panelW - 296)
    end
    oneLine(f.small, state.speech, panelX + 16, y + (state.lastPrompt and 54 or 42), panelW - 296, "left", MUTED)
    self:_button("map", "VOLVER AL MAPA", x + width - 271, y + 21, 133, 36, true)
    self:_button("retry", won and "REVANCHA" or "REINTENTAR", x + width - 130, y + 21, 115, 36, true, true)
end

return BattleHUD
