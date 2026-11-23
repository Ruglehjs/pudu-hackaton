local SpellRitual = {}
SpellRitual.__index = SpellRitual

local SAFETY_TIMEOUT = 12
local CLIMAX_DURATION = 0.28
local MAX_SEQUENCE_LEN = 10
local DIRECTIONS = { "up", "down", "left", "right" }
local KEYS = { w = "up", s = "down", a = "left", d = "right" }
local GLYPHS = {
    up    = { angle = -math.pi / 2, letter = "W", color = { 0.33, 0.90, 1.00 } },
    down  = { angle = math.pi / 2, letter = "S", color = { 1.00, 0.42, 0.82 } },
    left  = { angle = math.pi, letter = "A", color = { 1.00, 0.77, 0.34 } },
    right = { angle = 0, letter = "D", color = { 0.72, 0.97, 0.34 } },
}
local PATTERNS = {
    { "up", "left", "down", "right" },
    { "right", "up", "left", "down" },
    { "down", "right", "up", "left" },
    { "left", "down", "right", "up" },
    { "up", "right", "down", "left" },
    { "right", "down", "left", "up" },
}
local PRAISE = { "¡BRILLANTE!", "¡CHISPA!", "¡GENIAL!", "¡MAGIA!", "¡PODER!" }
local GOLD = { 1, 0.85, 0.42 }
local EMERALD = { 0.38, 0.93, 0.68 }

local function paint(g, color, alpha)
    g.setColor(color[1], color[2], color[3], alpha or 1)
end

local function colorFromHex(hex)
    local rgb = type(hex) == "string" and hex:match("^#(%x%x%x%x%x%x)$")
    if not rgb then return { 0.46, 0.77, 1 } end
    return { tonumber(rgb:sub(1, 2), 16) / 255, tonumber(rgb:sub(3, 4), 16) / 255,
        tonumber(rgb:sub(5, 6), 16) / 255 }
end

function SpellRitual.new()
    return setmetatable({ active = false }, SpellRitual)
end

function SpellRitual:start(promptText, themeColorHex)
    self.promptText = promptText
    self.theme = colorFromHex(themeColorHex)
    self.active, self.readyToUnleash, self.complete = true, false, false
    self.aiDecisionReady, self.needsLiveSprite, self.spriteReady = false, false, false
    self.elapsed, self.climax, self.overchargeBannerTimer = 0, 0, 0
    self.cursor, self.powerBonus, self.orbEnergy, self.misses = 1, 1, 0, 0
    self.lastDirection = nil
    self.sequence, self.sparkles = {}, {}
    for _, direction in ipairs(PATTERNS[math.random(#PATTERNS)]) do
        self.sequence[#self.sequence + 1] = { direction = direction, shake = 0 }
    end
end

function SpellRitual:cancel()
    self.active, self.readyToUnleash, self.complete = false, false, false
    self.sparkles = {}
end

function SpellRitual:setAiReady(decisionResult, needsLiveSprite)
    self.aiDecisionReady = true
    self.needsLiveSprite = needsLiveSprite == true
    self.theme = colorFromHex(decisionResult and decisionResult.ritual_theme_color)
end

function SpellRitual:setSpriteReady()
    self.spriteReady = true
end

function SpellRitual:getMultiplier()
    return self.powerBonus or 1
end

function SpellRitual:getLastDirection()
    return self.lastDirection
end

function SpellRitual:isComplete()
    return self.complete == true
end

function SpellRitual:_canUnleashNow()
    return self.elapsed >= SAFETY_TIMEOUT
        or (self.aiDecisionReady and (not self.needsLiveSprite or self.spriteReady))
end

function SpellRitual:_triggerUnleash()
    self.readyToUnleash = true
    self.climax = CLIMAX_DURATION
end

function SpellRitual:_extend()
    for _ = 1, 2 do
        local n = #self.sequence
        local direction = DIRECTIONS[math.random(#DIRECTIONS)]
        if self.sequence[n].direction == direction and self.sequence[n - 1].direction == direction then
            local nextIndex = math.random(#DIRECTIONS - 1)
            if DIRECTIONS[nextIndex] == direction then nextIndex = #DIRECTIONS end
            direction = DIRECTIONS[nextIndex]
        end
        self.sequence[n + 1] = { direction = direction, bonus = true, shake = 0 }
    end
    self.overchargeBannerTimer = 3.2
end

function SpellRitual:_spawnWord(text)
    for i = #self.sparkles, 1, -1 do
        if self.sparkles[i].kind == "word" then table.remove(self.sparkles, i) end
    end
    self.sparkles[#self.sparkles + 1] = { kind = "word", text = text, age = 0, life = 0.62 }
end

function SpellRitual:_burst(index, count, color)
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = 40 + math.random() * 100
        self.sparkles[#self.sparkles + 1] = {
            kind = "star", index = index, age = 0, life = 0.28 + math.random() * 0.24,
            vx = math.cos(angle) * speed, vy = math.sin(angle) * speed, color = color,
        }
    end
end

function SpellRitual:onKeyPressed(key, audio)
    local direction = KEYS[key] or key
    if not self.active or self.readyToUnleash or not GLYPHS[direction] then return false end
    local item = self.sequence[self.cursor]
    if not item then return true end

    if item.direction ~= direction then
        self.misses = self.misses + 1
        item.shake = 1
        self:_burst(self.cursor, 6, { 1, 0.41, 0.48 })
        if audio then audio:play("sfx_spell_miss", 0.45) end
        return true
    end

    local index = self.cursor
    local color = item.bonus and GOLD or GLYPHS[direction].color
    self.cursor = index + 1
    self.lastDirection = direction
    self.orbEnergy = math.min(index / 8, 1)
    self.powerBonus = 1 + math.min(index, 8) * 0.08
    self:_burst(index, 18, color)
    self.sparkles[#self.sparkles + 1] = { kind = "ring", index = index, color = color, age = 0, life = 0.38 }
    self.sparkles[#self.sparkles + 1] = { kind = "ray", index = index, color = color, age = 0, life = 0.46 }
    local word = item.bonus and (index <= 8 and "¡BONUS +8%!" or "¡BONUS!") or PRAISE[(index - 1) % #PRAISE + 1]
    self:_spawnWord(word)
    if audio then
        audio:playArrowChime(index)
        audio:play("orb_gain", 0.35)
    end
    if self.cursor > #self.sequence then
        if self:_canUnleashNow() then
            self:_triggerUnleash()
        elseif #self.sequence < MAX_SEQUENCE_LEN then
            self:_extend()
        end
    end
    return true
end

function SpellRitual:_orbAt(puduX, puduY, orbLift)
    return puduX + 12, puduY - (orbLift or 134) + math.sin(self.elapsed * 4.2) * 5
end

function SpellRitual:update(dt, _, puduX, puduY, orbLift)
    if not self.active then return end
    self.elapsed = self.elapsed + dt
    if puduX and puduY then self.orbX, self.orbY = self:_orbAt(puduX, puduY, orbLift) end
    self.overchargeBannerTimer = math.max(0, self.overchargeBannerTimer - dt)
    for _, item in ipairs(self.sequence) do
        item.shake = math.max(0, item.shake - dt * 5)
    end
    for i = #self.sparkles, 1, -1 do
        local fx = self.sparkles[i]
        fx.age = fx.age + dt
        if fx.age >= fx.life then table.remove(self.sparkles, i) end
    end
    if self.readyToUnleash then
        self.climax = math.max(0, self.climax - dt)
        if self.climax == 0 then self.complete, self.active = true, false end
    elseif self.cursor > #self.sequence and self:_canUnleashNow() then
        self:_triggerUnleash()
    end
end

function SpellRitual:collectLights(out)
    if self.active and self.orbX and self.orbY then
        local c = self.theme
        out[#out + 1] = {
            x = self.orbX, y = self.orbY, r = c[1], g = c[2], b = c[3],
            radius = 70 + self.orbEnergy * 55, height = 60, haloScale = 0.72,
            energy = 0.24 + self.orbEnergy * 0.27 + (self.readyToUnleash and 0.20 or 0),
        }
    end
end

function SpellRitual:_getTileLayout(w, h)
    local panelH, statusH = 86, 26
    local available = w * 0.58 - 32
    local tile = math.min(48, 28 + w * 0.016, (available - 24) / ((#self.sequence - 1) * 1.20 + 1.28))
    local step = tile * 1.20
    local panelW = (#self.sequence - 1) * step + tile * 1.28 + 24
    local centerX = math.min(w / 2, w * 0.58 - 16 - panelW / 2)
    local panelY = math.max(126, math.floor(h * 0.235) - panelH / 2)
    return {
        x = centerX - panelW / 2, w = panelW, h = panelH, panelY = panelY,
        statusY = math.max(56, panelY - statusH - 42), statusH = statusH,
        firstX = centerX - (#self.sequence - 1) * step / 2,
        centerX = centerX, cy = panelY + panelH / 2, tile = tile, step = step,
    }
end

local function drawArrowGlyph(g, x, y, size, glyph, color, alpha)
    g.push()
    g.translate(x, y)
    g.rotate(glyph.angle)
    g.setColor(0.02, 0.04, 0.10, alpha)
    g.rectangle("fill", -size * 0.94 - 2, -size * 0.27 - 2, size + 4, size * 0.54 + 4, 2)
    g.polygon("fill", -size * 0.04 - 2, -size * 0.86 - 2, size * 1.04 + 3, 0,
        -size * 0.04 - 2, size * 0.86 + 2)
    paint(g, color, alpha)
    g.rectangle("fill", -size * 0.94, -size * 0.27, size, size * 0.54, 2)
    g.polygon("fill", -size * 0.04, -size * 0.86, size * 1.04, 0, -size * 0.04, size * 0.86)
    g.setColor(1, 1, 1, alpha * 0.44)
    g.line(-size * 0.76, -size * 0.11, size * 0.54, -size * 0.11)
    g.pop()
end

local function drawStar(g, x, y, r)
    local n = r * 0.22
    g.polygon("fill", x - n, y, x, y - r, x + n, y, x, y + r)
    g.polygon("fill", x - r, y, x, y - n, x + r, y, x, y + n)
end

local function quad(a, b, c, t)
    local u = 1 - t
    return u * u * a + 2 * u * t * b + t * t * c
end

local function drawTrails(g, sparkles, layout, ox, oy)
    for _, fx in ipairs(sparkles) do
        if fx.kind == "ray" and fx.age > 0 then
            local x, y = layout.firstX + (fx.index - 1) * layout.step, layout.cy
            local t = fx.age / fx.life
            local from = math.max(0, t - 0.25)
            local midX, midY = (x + ox) / 2 - 42, (y + oy) / 2 - 26
            local points = {}
            for i = 0, 8 do
                local u = from + (t - from) * i / 8
                points[#points + 1] = quad(x, midX, ox, u)
                points[#points + 1] = quad(y, midY, oy, u)
            end
            paint(g, fx.color, 1 - t)
            g.setLineWidth(2.5)
            g.line(points)
        end
    end
    g.setLineWidth(1)
end

local function drawTileEffects(g, sparkles, layout)
    g.setScissor(layout.x, layout.panelY, layout.w, layout.h)
    for _, fx in ipairs(sparkles) do
        local x, y = layout.firstX + ((fx.index or 1) - 1) * layout.step, layout.cy
        local t = fx.age / fx.life
        paint(g, fx.color or GOLD, 1 - t)
        if fx.kind == "star" then
            drawStar(g, x + fx.vx * fx.age, y + fx.vy * fx.age + 70 * fx.age ^ 2, 1.2 + 2 * (1 - t))
        elseif fx.kind == "ring" then
            g.circle("line", x, y, 17 + t * 35)
        end
    end
    g.setScissor()
end

local function centered(g, font, text, x, y)
    g.setFont(font)
    g.print(text, math.floor(x - font:getWidth(text) / 2), math.floor(y))
end

function SpellRitual:drawCircle(puduX, puduY)
    if not self.active then return end
    local g = love.graphics
    local spin = self.elapsed * 0.9
    paint(g, self.theme, 0.48 + self.orbEnergy * 0.18)
    g.setLineWidth(1.5)
    g.ellipse("line", puduX, puduY - 6, 70, 22)
    g.ellipse("line", puduX, puduY - 6, 58, 18)
    for i = 1, 8 do
        local a = spin + i * math.pi / 4
        drawStar(g, puduX + math.cos(a) * 63, puduY - 6 + math.sin(a) * 20, 3)
    end
    g.setLineWidth(1)
end

function SpellRitual:draw(w, h, puduX, puduY, fonts, beatSync, orbLift)
    if not self.active then return end
    local g = love.graphics
    local L = self:_getTileLayout(w, h)
    local ox, oy = self:_orbAt(puduX, puduY, orbLift)
    local pulse = beatSync and beatSync:getBeatPulse() or 0
    local theme = self.theme
    g.push("all")
    drawTrails(g, self.sparkles, L, ox, oy)
    g.setColor(0.025, 0.047, 0.12, 0.95)
    g.rectangle("fill", L.x, L.panelY, L.w, L.h, 14)
    paint(g, theme, 0.68)
    g.rectangle("line", L.x + 0.5, L.panelY + 0.5, L.w - 1, L.h - 1, 14)
    drawTileEffects(g, self.sparkles, L)

    for i, item in ipairs(self.sequence) do
        local done, active = i < self.cursor, i == self.cursor
        local glyph = GLYPHS[item.direction]
        local color = done and EMERALD or glyph.color
        local x = L.firstX + (i - 1) * L.step
        local cy = L.cy
        local size = L.tile * (active and 1.28 or (done and 0.86 or 0.80))
        x = x + math.sin(self.elapsed * 50) * item.shake * 4
        local left, top = x - size / 2, cy - size / 2
        if active then
            paint(g, color, 0.14 + 0.13 * (0.5 + 0.5 * math.sin(self.elapsed * 6)))
            g.rectangle("fill", left - 4, top - 4, size + 8, size + 8, 12)
        end
        g.setColor(0.09, 0.16, 0.30, active and 1 or 0.75)
        g.rectangle("fill", left, top, size, size, 8)
        paint(g, item.bonus and GOLD or color, active and 1 or (done and 0.64 or 0.45))
        g.setLineWidth(active and 2 or 1)
        g.rectangle("line", left + 0.5, top + 0.5, size - 1, size - 1, 8)
        g.setLineWidth(1)
        drawArrowGlyph(g, x, cy, size * 0.30, glyph, color, active and 1 or (done and 0.83 or 0.68))

        if active then
            paint(g, color)
            g.setFont(fonts.small)
            g.print(glyph.letter, left + size - fonts.small:getWidth(glyph.letter) - 5, top + size - 16)
            local py = L.panelY - 19 + math.sin(self.elapsed * 7) * 3
            g.setColor(0.02, 0.03, 0.08)
            g.polygon("fill", x - 10, py, x + 10, py, x, py + 14)
            paint(g, GOLD)
            g.polygon("fill", x - 7, py + 1, x + 7, py + 1, x, py + 11)
            g.setColor(0.02, 0.03, 0.08)
            centered(g, fonts.small, "APRIETA", x + 1, py - 17)
            centered(g, fonts.small, "APRIETA", x - 1, py - 17)
            paint(g, GOLD)
            centered(g, fonts.small, "APRIETA", x, py - 18)
        end
    end

    local status = self.readyToUnleash and "¡¡INVOCANDO!!"
        or (self.cursor > #self.sequence and "La magia está lista" or "Ritual de invocación")
    local statusW = fonts.body:getWidth(status) + 32
    g.setColor(0.035, 0.065, 0.16, 0.96)
    g.rectangle("fill", L.centerX - statusW / 2, L.statusY, statusW, L.statusH, 13)
    paint(g, self.readyToUnleash and GOLD or theme)
    g.rectangle("line", L.centerX - statusW / 2, L.statusY, statusW, L.statusH, 13)
    centered(g, fonts.body, status, L.centerX, L.statusY + (L.statusH - fonts.body:getHeight()) / 2)

    local barW, barY = 156, L.panelY + L.h + 8
    local barX = L.centerX - barW / 2 - 20
    g.setColor(0.025, 0.045, 0.09, 0.96)
    g.rectangle("fill", barX, barY, barW, 12, 5)
    paint(g, theme, 0.80)
    g.rectangle("line", barX, barY, barW, 12, 5)
    if self.orbEnergy > 0 then
        g.rectangle("fill", barX + 2, barY + 2, (barW - 4) * self.orbEnergy, 8, 3)
    end
    g.setColor(0.97, 0.98, 1)
    g.setFont(fonts.small)
    g.print(("+%d%%"):format(math.floor((self.powerBonus - 1) * 100 + 0.5)), barX + barW + 8, barY - 2)
    if self.overchargeBannerTimer > 0 and not self.readyToUnleash then
        local bonus = "¡BONUS! +2 flechas"
        local bw = fonts.small:getWidth(bonus) + 22
        local bx = h < 630 and L.x + L.w - bw or L.centerX - bw / 2
        g.setColor(0.16, 0.10, 0.06, 0.94)
        g.rectangle("fill", bx, barY + 20, bw, 23, 7)
        paint(g, GOLD)
        centered(g, fonts.small, bonus, bx + bw / 2, barY + 24)
    end

    local radius = math.min(28, 13 + self.orbEnergy * 12 + pulse * 2)
    if self.readyToUnleash then radius = radius + 21 * math.sin(math.pi * (1 - self.climax / CLIMAX_DURATION)) end
    paint(g, theme, 0.19)
    g.circle("fill", ox, oy, radius)
    paint(g, theme, 0.74)
    g.circle("line", ox, oy, radius * 0.80)
    g.circle("fill", ox, oy, radius * 0.52)
    g.setColor(0.91, 0.98, 1, 0.90)
    drawStar(g, ox, oy, radius * 0.45)

    for _, fx in ipairs(self.sparkles) do
        if fx.kind == "word" then
            local t = fx.age / fx.life
            local wy = oy - 38 - t * 12
            g.setColor(0.025, 0.04, 0.10, 1 - t)
            centered(g, fonts.body, fx.text, ox + 1, wy + 1)
            paint(g, GOLD, 1 - t)
            centered(g, fonts.body, fx.text, ox, wy)
        end
    end
    g.pop()
end

return SpellRitual
