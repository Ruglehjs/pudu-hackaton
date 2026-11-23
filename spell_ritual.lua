local Skin = require("battle_ui_skin")
local SpellRitual = {}
SpellRitual.__index = SpellRitual

local SAFETY_TIMEOUT = 12
local CLIMAX_DURATION = 0.28
local MAX_SEQUENCE_LEN = 10
local WAVE_PAUSE = 0.55
local OSU_MAX_TARGETS = 3
local OSU_CIRCLE_RADIUS = 26
local OSU_CIRCLE_LIFE = 2.15
local OSU_SLIDER_WAIT = 2.10
local OSU_SLIDER_DURATION = 0.92
local OSU_FOLLOW_RADIUS = 50
local MAX_TOTAL_MULTIPLIER = 2.00

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
local OSU_COLORS = {
    { 0.33, 0.90, 1.00 },
    { 1.00, 0.46, 0.80 },
    { 1.00, 0.82, 0.36 },
    { 0.62, 0.96, 0.42 },
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

local function quad(a, b, c, t)
    local u = 1 - t
    return u * u * a + 2 * u * t * b + t * t * c
end

local function dist2(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy
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
    self.overchargeBannerText = "¡BONUS! +2 flechas"
    self.cursor, self.powerBonus, self.arrowBonus, self.osuBonus = 1, 1, 0, 0
    self.orbEnergy, self.misses = 0, 0
    self.arrowHits, self.waveCount = 0, 1
    self.nextWaveAt = nil
    self.lastDirection = nil
    self.sequence, self.sparkles = {}, {}

    -- Osu!-style interactive mouse targets (circles + sliders) & cursor trail
    self.osuTargets = {}
    self.osuNextSpawnAt = 0.32
    self.osuNextNumber = 1
    self.osuCombo = 0
    self.osuHits = 0
    self.activeSlider = nil
    self.mouseX, self.mouseY = nil, nil
    self.cursorTrail = {}
    self.lastViewportW, self.lastViewportH = 1280, 720

    for _, direction in ipairs(PATTERNS[math.random(#PATTERNS)]) do
        self.sequence[#self.sequence + 1] = { direction = direction, shake = 0 }
    end
end

function SpellRitual:cancel()
    self.active, self.readyToUnleash, self.complete = false, false, false
    self.sparkles = {}
    self.osuTargets = {}
    self.activeSlider = nil
    self.cursorTrail = {}
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

function SpellRitual:_recomputePower()
    self.powerBonus = math.min(MAX_TOTAL_MULTIPLIER, 1 + (self.arrowBonus or 0) + (self.osuBonus or 0))
    self.orbEnergy = math.min(1, ((self.arrowHits or 0) + (self.osuHits or 0) * 0.8) / 8)
end

function SpellRitual:_canUnleashNow()
    return self.elapsed >= SAFETY_TIMEOUT
        or (self.aiDecisionReady and (not self.needsLiveSprite or self.spriteReady))
end

function SpellRitual:_triggerUnleash()
    self.readyToUnleash = true
    self.activeSlider = nil
    self.climax = CLIMAX_DURATION
end

function SpellRitual:_pickDirection(list)
    local n = #list
    local direction = DIRECTIONS[math.random(#DIRECTIONS)]
    if n >= 2 and list[n].direction == direction and list[n - 1].direction == direction then
        local nextIndex = math.random(#DIRECTIONS - 1)
        if DIRECTIONS[nextIndex] == direction then nextIndex = #DIRECTIONS end
        direction = DIRECTIONS[nextIndex]
    end
    return direction
end

function SpellRitual:_extend()
    for _ = 1, 2 do
        local direction = self:_pickDirection(self.sequence)
        self.sequence[#self.sequence + 1] = { direction = direction, bonus = true, shake = 0 }
    end
    self.overchargeBannerText = "¡BONUS! +2 flechas"
    self.overchargeBannerTimer = 3.2
end

function SpellRitual:_startExtraWave()
    self.waveCount = (self.waveCount or 1) + 1
    self.sequence = {}
    for _ = 1, 6 do
        local direction = self:_pickDirection(self.sequence)
        self.sequence[#self.sequence + 1] = { direction = direction, bonus = true, shake = 0 }
    end
    self.cursor = 1
    self.nextWaveAt = nil
    self.overchargeBannerText = ("¡OLEADA %d! +6 flechas"):format(self.waveCount)
    self.overchargeBannerTimer = 3.2
end

function SpellRitual:_spawnWord(text)
    for i = #self.sparkles, 1, -1 do
        if self.sparkles[i].kind == "word" then table.remove(self.sparkles, i) end
    end
    self.sparkles[#self.sparkles + 1] = { kind = "word", text = text, age = 0, life = 0.62 }
end

function SpellRitual:_burst(index, count, color, wx, wy)
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = 40 + math.random() * 100
        self.sparkles[#self.sparkles + 1] = {
            kind = "star", index = index, wx = wx, wy = wy,
            age = 0, life = 0.28 + math.random() * 0.24,
            vx = math.cos(angle) * speed, vy = math.sin(angle) * speed, color = color,
        }
    end
end

function SpellRitual:_spawnOsuEffect(x, y, color, text)
    self:_burst(nil, 14, color, x, y)
    self.sparkles[#self.sparkles + 1] = { kind = "ring", wx = x, wy = y, color = color, age = 0, life = 0.36 }
    self.sparkles[#self.sparkles + 1] = { kind = "ray", wx = x, wy = y, color = color, age = 0, life = 0.44 }
    if text then self:_spawnWord(text) end
end

function SpellRitual:_getOsuBounds(w, h)
    local L = self:_getTileLayout(w, h)
    local minX = math.max(240, w * 0.34)
    local maxX = math.min(w - 220, w * 0.61)
    local minY = math.max(268, L.panelY + L.h + 62)
    local maxY = math.max(minY + 60, h - 148)
    return minX, maxX, minY, maxY
end

function SpellRitual:_spawnOsuTarget()
    if #self.osuTargets >= OSU_MAX_TARGETS then return end
    local w, h = self.lastViewportW or 1280, self.lastViewportH or 720
    local minX, maxX, minY, maxY = self:_getOsuBounds(w, h)
    if maxX <= minX + 40 or maxY <= minY + 40 then return end

    local num = self.osuNextNumber
    self.osuNextNumber = num + 1
    local color = OSU_COLORS[(num - 1) % #OSU_COLORS + 1]
    local wantSlider = (num % 3 == 0) and (self.activeSlider == nil)

    -- Pick a start point spaced away from existing targets
    local x1, y1
    for _ = 1, 10 do
        local cx = minX + math.random() * (maxX - minX)
        local cy = minY + math.random() * (maxY - minY)
        local clear = true
        for _, other in ipairs(self.osuTargets) do
            if dist2(cx, cy, other.x, other.y) < 76 * 76 then
                clear = false
                break
            end
        end
        if clear then
            x1, y1 = cx, cy
            break
        end
    end
    if not x1 then
        x1 = minX + math.random() * (maxX - minX)
        y1 = minY + math.random() * (maxY - minY)
    end

    if wantSlider then
        local spanX = (x1 > (minX + maxX) * 0.5) and -(95 + math.random() * 55) or (95 + math.random() * 55)
        local spanY = (y1 > (minY + maxY) * 0.5) and -(45 + math.random() * 45) or (45 + math.random() * 45)
        local x2 = math.max(minX, math.min(maxX, x1 + spanX))
        local y2 = math.max(minY, math.min(maxY, y1 + spanY))
        local midX = (x1 + x2) * 0.5 + (math.random() - 0.5) * 48
        local midY = (y1 + y2) * 0.5 + (y1 < y2 and -36 or 36)
        midX = math.max(minX, math.min(maxX, midX))
        midY = math.max(minY, math.min(maxY, midY))
        self.osuTargets[#self.osuTargets + 1] = {
            kind = "slider", number = num, color = color,
            x = x1, y = y1, cx = midX, cy = midY, x2 = x2, y2 = y2,
            radius = OSU_CIRCLE_RADIUS, age = 0, life = OSU_SLIDER_WAIT,
            holding = false, slideT = 0, trackGood = 0, trackTotal = 0,
            sparkTimer = 0,
        }
    else
        self.osuTargets[#self.osuTargets + 1] = {
            kind = "circle", number = num, color = color,
            x = x1, y = y1, radius = OSU_CIRCLE_RADIUS,
            age = 0, life = OSU_CIRCLE_LIFE,
        }
    end
end

function SpellRitual:_awardOsuHit(x, y, color, bonusAdd, label, audio, comboStep)
    self.osuHits = (self.osuHits or 0) + 1
    self.osuCombo = (self.osuCombo or 0) + (comboStep or 1)
    self.osuBonus = math.min(0.40, (self.osuBonus or 0) + bonusAdd)
    self:_recomputePower()
    self:_spawnOsuEffect(x, y, color, label)
    if audio then
        audio:playArrowChime(self.osuCombo)
        audio:play("orb_gain", 0.30)
    end
end

function SpellRitual:onMousePressed(x, y, button, audio)
    if button ~= 1 or not self.active or self.readyToUnleash then return false end
    self.mouseX, self.mouseY = x, y
    for i = 1, #self.osuTargets do
        local target = self.osuTargets[i]
        local hitR = target.radius + 10
        if target.kind == "circle" and dist2(x, y, target.x, target.y) <= hitR * hitR then
            local t = target.age / target.life
            local perfect = t >= 0.52 and t <= 0.95
            local bonus = perfect and 0.06 or 0.04
            local label = perfect and "¡PERFECTO! +6%" or "¡BIEN! +4%"
            local color = perfect and GOLD or target.color
            table.remove(self.osuTargets, i)
            self:_awardOsuHit(target.x, target.y, color, bonus, label, audio, 1)
            return true
        elseif target.kind == "slider" and not target.holding and dist2(x, y, target.x, target.y) <= hitR * hitR then
            target.holding = true
            target.slideT = 0
            target.trackGood = 0
            target.trackTotal = 0
            self.activeSlider = target
            self:_burst(nil, 8, target.color, target.x, target.y)
            if audio then audio:playArrowChime(self.osuCombo + 1) end
            return true
        end
    end
    return false
end

function SpellRitual:onMouseMoved(x, y)
    if not self.active then return end
    self.mouseX, self.mouseY = x, y
    self.cursorTrail[#self.cursorTrail + 1] = { x = x, y = y, age = 0, life = 0.22 }
    if #self.cursorTrail > 22 then table.remove(self.cursorTrail, 1) end
end

function SpellRitual:onMouseReleased(x, y, button, audio)
    if button ~= 1 or not self.active then return false end
    self.mouseX, self.mouseY = x, y
    local s = self.activeSlider
    if not s then return false end
    self.activeSlider = nil
    local bx = quad(s.x, s.cx, s.x2, s.slideT)
    local by = quad(s.y, s.cy, s.y2, s.slideT)
    for i = #self.osuTargets, 1, -1 do
        if self.osuTargets[i] == s then
            table.remove(self.osuTargets, i)
            break
        end
    end
    if s.slideT >= 0.55 then
        self:_awardOsuHit(bx, by, s.color, 0.04, "¡DESLIZ +4%!", audio, 1)
    end
    return true
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
    self.arrowHits = (self.arrowHits or 0) + 1
    self.arrowBonus = math.min(self.arrowHits, 8) * 0.08 + math.max(0, self.arrowHits - 8) * 0.04
    self:_recomputePower()
    self:_burst(index, 18, color)
    self.sparkles[#self.sparkles + 1] = { kind = "ring", index = index, color = color, age = 0, life = 0.38 }
    self.sparkles[#self.sparkles + 1] = { kind = "ray", index = index, color = color, age = 0, life = 0.46 }
    local word = item.bonus and (self.arrowHits <= 8 and "¡BONUS +8%!" or "¡BONUS +4%!")
        or PRAISE[(index - 1) % #PRAISE + 1]
    self:_spawnWord(word)
    if audio then
        audio:playArrowChime(self.arrowHits)
        audio:play("orb_gain", 0.35)
    end
    if self.cursor > #self.sequence then
        if self:_canUnleashNow() then
            self:_triggerUnleash()
        elseif #self.sequence < MAX_SEQUENCE_LEN then
            self:_extend()
        elseif self.needsLiveSprite and not self.spriteReady then
            self.nextWaveAt = self.elapsed + WAVE_PAUSE
        end
    end
    return true
end

function SpellRitual:_orbAt(puduX, puduY, orbLift)
    return puduX + 12, puduY - (orbLift or 134) + math.sin(self.elapsed * 4.2) * 5
end

function SpellRitual:update(dt, _, puduX, puduY, orbLift, audio)
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
    for i = #self.cursorTrail, 1, -1 do
        local pt = self.cursorTrail[i]
        pt.age = pt.age + dt
        if pt.age >= pt.life then table.remove(self.cursorTrail, i) end
    end

    if not self.readyToUnleash then
        -- Spawn Osu! targets continuously while ritual is active
        local waitingForLive = self.needsLiveSprite and not self.spriteReady
        if self.elapsed >= self.osuNextSpawnAt then
            self:_spawnOsuTarget()
            self.osuNextSpawnAt = self.elapsed + (waitingForLive and 0.62 or 0.85)
        end

        -- Update Osu! targets and active slider tracking
        for i = #self.osuTargets, 1, -1 do
            local target = self.osuTargets[i]
            if target.kind == "slider" and target.holding then
                target.slideT = math.min(1, target.slideT + dt / OSU_SLIDER_DURATION)
                local bx = quad(target.x, target.cx, target.x2, target.slideT)
                local by = quad(target.y, target.cy, target.y2, target.slideT)
                target.trackTotal = target.trackTotal + dt
                local inside = self.mouseX and self.mouseY
                    and dist2(self.mouseX, self.mouseY, bx, by) <= OSU_FOLLOW_RADIUS * OSU_FOLLOW_RADIUS
                target.insideBall = inside
                if inside then
                    target.trackGood = target.trackGood + dt
                    target.sparkTimer = target.sparkTimer + dt
                    if target.sparkTimer >= 0.08 then
                        target.sparkTimer = 0
                        self:_burst(nil, 3, GOLD, bx, by)
                    end
                end
                if target.slideT >= 1 then
                    self.activeSlider = nil
                    table.remove(self.osuTargets, i)
                    local ratio = target.trackTotal > 0 and (target.trackGood / target.trackTotal) or 1
                    if ratio >= 0.40 then
                        self:_awardOsuHit(target.x2, target.y2, GOLD, 0.10, "¡DESLIZ +10%!", audio, 2)
                    else
                        self:_awardOsuHit(target.x2, target.y2, target.color, 0.05, "¡DESLIZ +5%!", audio, 1)
                    end
                end
            else
                target.age = target.age + dt
                if target.age >= target.life then
                    table.remove(self.osuTargets, i)
                end
            end
        end

        -- Launch extra arrow wave if the player finished all 10 arrows while live sprite is still loading
        if self.nextWaveAt and self.elapsed >= self.nextWaveAt and not self:_canUnleashNow() then
            self:_startExtraWave()
        end
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

local function fxOrigin(fx, layout)
    if fx.wx and fx.wy then return fx.wx, fx.wy end
    return layout.firstX + ((fx.index or 1) - 1) * layout.step, layout.cy
end

local function drawTrails(g, sparkles, layout, ox, oy)
    for _, fx in ipairs(sparkles) do
        if fx.kind == "ray" and fx.age > 0 then
            local x, y = fxOrigin(fx, layout)
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

local function drawWorldEffects(g, sparkles, layout)
    for _, fx in ipairs(sparkles) do
        if fx.wx and fx.wy and fx.kind ~= "ray" and fx.kind ~= "word" then
            local t = fx.age / fx.life
            paint(g, fx.color or GOLD, 1 - t)
            if fx.kind == "star" then
                drawStar(g, fx.wx + fx.vx * fx.age, fx.wy + fx.vy * fx.age + 65 * fx.age ^ 2, 1.4 + 2.4 * (1 - t))
            elseif fx.kind == "ring" then
                g.setLineWidth(2.2)
                g.circle("line", fx.wx, fx.wy, 20 + t * 44)
                g.setLineWidth(1)
            end
        end
    end
end

local function drawTileEffects(g, sparkles, layout)
    g.setScissor(layout.x, layout.panelY, layout.w, layout.h)
    for _, fx in ipairs(sparkles) do
        if not fx.wx then
            local x, y = layout.firstX + ((fx.index or 1) - 1) * layout.step, layout.cy
            local t = fx.age / fx.life
            paint(g, fx.color or GOLD, 1 - t)
            if fx.kind == "star" then
                drawStar(g, x + fx.vx * fx.age, y + fx.vy * fx.age + 70 * fx.age ^ 2, 1.2 + 2 * (1 - t))
            elseif fx.kind == "ring" then
                g.circle("line", x, y, 17 + t * 35)
            end
        end
    end
    g.setScissor()
end

local function centered(g, font, text, x, y)
    g.setFont(font)
    g.print(text, math.floor(x - font:getWidth(text) / 2), math.floor(y))
end

local function drawOsuTargets(g, targets, fonts)
    for _, target in ipairs(targets) do
        local c = target.color
        if target.kind == "circle" then
            local t = math.min(1, target.age / target.life)
            local fade = t > 0.85 and (1 - (t - 0.85) / 0.15) or math.min(1, target.age / 0.14)
            local r = target.radius
            local approachR = r * (2.25 - 1.25 * t)

            -- Approach ring (classic Osu! shrinking ring)
            paint(g, c, 0.82 * fade)
            g.setLineWidth(2.6)
            g.circle("line", target.x, target.y, approachR)

            -- Target body
            g.setColor(0.03, 0.06, 0.15, 0.84 * fade)
            g.circle("fill", target.x, target.y, r)
            paint(g, c, 0.28 * fade)
            g.circle("fill", target.x, target.y, r - 4)
            g.setColor(1, 1, 1, 0.92 * fade)
            g.setLineWidth(2.4)
            g.circle("line", target.x, target.y, r)
            g.setLineWidth(1)

            g.setColor(1, 1, 1, fade)
            centered(g, fonts.body, tostring(target.number), target.x, target.y - fonts.body:getHeight() / 2)
        elseif target.kind == "slider" then
            local t = math.min(1, target.age / target.life)
            local fade = target.holding and 1 or (t > 0.85 and (1 - (t - 0.85) / 0.15) or math.min(1, target.age / 0.15))
            local r = target.radius
            local pts = {}
            for s = 0, 14 do
                local u = s / 14
                pts[#pts + 1] = quad(target.x, target.cx, target.x2, u)
                pts[#pts + 1] = quad(target.y, target.cy, target.y2, u)
            end

            -- Slider track (outer glow + dark inner rail + center guide)
            paint(g, c, 0.34 * fade)
            g.setLineWidth(r * 1.45)
            g.line(pts)
            g.setColor(0.03, 0.06, 0.15, 0.78 * fade)
            g.setLineWidth(r * 1.10)
            g.line(pts)
            paint(g, c, 0.70 * fade)
            g.setLineWidth(3)
            g.line(pts)
            g.setLineWidth(1)

            -- End cap
            g.setColor(0.04, 0.08, 0.18, 0.88 * fade)
            g.circle("fill", target.x2, target.y2, r * 0.78)
            paint(g, GOLD, 0.85 * fade)
            g.setLineWidth(2)
            g.circle("line", target.x2, target.y2, r * 0.78)

            if not target.holding then
                -- Start circle + approach ring
                local approachR = r * (2.2 - 1.2 * t)
                paint(g, c, 0.84 * fade)
                g.setLineWidth(2.6)
                g.circle("line", target.x, target.y, approachR)
                g.setColor(0.03, 0.06, 0.15, 0.88 * fade)
                g.circle("fill", target.x, target.y, r)
                paint(g, c, 0.34 * fade)
                g.circle("fill", target.x, target.y, r - 4)
                g.setColor(1, 1, 1, 0.95 * fade)
                g.setLineWidth(2.4)
                g.circle("line", target.x, target.y, r)
                g.setLineWidth(1)
                centered(g, fonts.small, "ARRASTRA", target.x, target.y - r - 17)
                centered(g, fonts.body, tostring(target.number), target.x, target.y - fonts.body:getHeight() / 2)
            else
                -- Moving slider ball + follow ring
                local bx = quad(target.x, target.cx, target.x2, target.slideT)
                local by = quad(target.y, target.cy, target.y2, target.slideT)
                local ringColor = target.insideBall and GOLD or c
                paint(g, ringColor, target.insideBall and 0.35 or 0.16)
                g.circle("fill", bx, by, OSU_FOLLOW_RADIUS)
                paint(g, ringColor, 0.92)
                g.setLineWidth(2.5)
                g.circle("line", bx, by, OSU_FOLLOW_RADIUS)
                g.setColor(1, 1, 1, 0.96)
                g.circle("fill", bx, by, r * 0.72)
                paint(g, ringColor, 0.95)
                g.circle("line", bx, by, r * 0.72)
                g.setLineWidth(1)
            end
        end
    end
end

local function drawCursorTrail(g, trail, mx, my, theme)
    if #trail >= 2 then
        for i = 2, #trail do
            local a, b = trail[i - 1], trail[i]
            local alpha = (1 - b.age / b.life) * 0.65
            paint(g, theme, alpha)
            g.setLineWidth(1.5 + (i / #trail) * 4.5)
            g.line(a.x, a.y, b.x, b.y)
        end
        g.setLineWidth(1)
    end
    if mx and my then
        paint(g, GOLD, 0.85)
        g.setLineWidth(2)
        g.circle("line", mx, my, 10)
        g.setColor(1, 1, 1, 0.95)
        g.circle("fill", mx, my, 3.5)
        g.setLineWidth(1)
    end
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
    self.lastViewportW, self.lastViewportH = w, h
    local g = love.graphics
    local L = self:_getTileLayout(w, h)
    local ox, oy = self:_orbAt(puduX, puduY, orbLift)
    local pulse = beatSync and beatSync:getBeatPulse() or 0
    local theme = self.theme
    g.push("all")
    drawTrails(g, self.sparkles, L, ox, oy)
    Skin.wood(g, L.x, L.panelY, L.w, L.h)
    Skin.pin(g, L.x + 10, L.panelY + 10)
    Skin.pin(g, L.x + L.w - 10, L.panelY + L.h - 10)
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
        g.setColor(0.19, 0.14, 0.085, active and 1 or 0.86)
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

    local status
    if self.readyToUnleash then
        status = "¡Invocando!"
    elseif self.needsLiveSprite and not self.spriteReady then
        status = "La invocación toma forma..."
    elseif self.cursor > #self.sequence then
        status = "La magia está lista"
    else
        status = "Ritual de invocación"
    end
    local statusW = fonts.body:getWidth(status) + 40
    local statusX = L.centerX - statusW / 2
    Skin.wood(g, statusX, L.statusY, statusW, L.statusH)
    Skin.spark(g, statusX + 13, L.statusY + L.statusH / 2, 4)
    g.setColor(Skin.cream)
    centered(g, fonts.body, status, L.centerX + 3, L.statusY + (L.statusH - fonts.body:getHeight()) / 2 - 1)

    local barW, barY = 156, L.panelY + L.h + 8
    local barX = L.centerX - barW / 2 - 20
    g.setColor(0.19, 0.11, 0.06, 0.96)
    g.rectangle("fill", barX, barY, barW, 12, 5)
    g.setColor(Skin.gold)
    g.rectangle("line", barX, barY, barW, 12, 5)
    if self.orbEnergy > 0 then
        paint(g, theme)
        g.rectangle("fill", barX + 2, barY + 2, (barW - 4) * self.orbEnergy, 8, 3)
    end
    g.setColor(Skin.cream)
    g.setFont(fonts.small)
    local powerText = ("+%d%%"):format(math.floor((self.powerBonus - 1) * 100 + 0.5))
    if (self.osuCombo or 0) >= 2 then
        powerText = powerText .. (" | COMBO x%d"):format(self.osuCombo)
    end
    g.print(powerText, barX + barW + 8, barY - 2)
    if self.overchargeBannerTimer > 0 and not self.readyToUnleash then
        local bonus = self.overchargeBannerText or "¡BONUS! +2 flechas"
        local bw = fonts.small:getWidth(bonus) + 22
        local bx = h < 630 and L.x + L.w - bw or L.centerX - bw / 2
        Skin.wood(g, bx, barY + 20, bw, 23)
        g.setColor(Skin.gold)
        centered(g, fonts.small, bonus, bx + bw / 2, barY + 24)
    elseif not self.readyToUnleash then
        local help = "Flechas/WASD + Clic y arrastra orbes"
        local helpW = fonts.small:getWidth(help) + 22
        Skin.paper(g, L.centerX - helpW / 2, barY + 18, helpW, 22)
        g.setColor(Skin.ink)
        centered(g, fonts.small, help, L.centerX, barY + 22)
    end

    -- Draw Osu! targets, world bursts, and cursor trail
    if not self.readyToUnleash then
        drawOsuTargets(g, self.osuTargets, fonts)
    end
    drawWorldEffects(g, self.sparkles, L)
    if not self.readyToUnleash then
        drawCursorTrail(g, self.cursorTrail, self.mouseX, self.mouseY, theme)
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
