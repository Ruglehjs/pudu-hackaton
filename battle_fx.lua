local utf8 = require("utf8")

local BattleFX = {}
BattleFX.__index = BattleFX

local ok, Spectacles = pcall(require, "battle_fx_spectacles")
if not ok then Spectacles = nil end

local MAX_PARTICLES, MAX_PERSISTENT_PROPS = 420, 3
local MAX_PARTICLE_LIGHTS = 48
local TAU = math.pi * 2
local CLEAR = { dx = 0, dy = 0, rot = 0, scaleX = 1, scaleY = 1, alpha = 1, flashWhite = 0 }
local WEATHER_OFFSETS = { 0, -24, 24 }
local COLOR_GOLD = { 1, 0.83, 0.31 }
local COLOR_DAMAGE = { 1, 0.94, 0.86 }
local COLOR_PUDU_DAMAGE = { 1, 0.47, 0.40 }
local COLOR_HEAL = { 0.53, 1, 0.70 }
local OUTLINE_RING_4PX, CRIT_GLOW_OFFSETS = {}, {}
for i = 1, 16 do
    local a = i / 16 * TAU
    OUTLINE_RING_4PX[i] = { math.cos(a) * 4, math.sin(a) * 4 }
    CRIT_GLOW_OFFSETS[i] = { math.cos(a) * 6, math.sin(a) * 6 }
end

local function clamp(value, lower, upper)
    return math.max(lower, math.min(value, upper))
end

local function lerp(a, b, p)
    return a + (b - a) * p
end

local function easeOutBack(p)
    local q = p - 1
    return 1 + 2.70158 * q * q * q + 1.70158 * q * q
end

local function box(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function intersects(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function vacant(area, reservations)
    for _, other in ipairs(reservations) do
        if intersects(area, other) then return false end
    end
    return true
end

local function play(audio, name, volume)
    if audio and type(audio.play) == "function" and name and name ~= "none" then
        audio:play(name, volume)
    end
end

local function textForFont(font, text)
    if font:hasGlyphs(text) then return text end
    return (text:gsub(utf8.charpattern, function(char)
        return font:hasGlyphs(char) and char or "?"
    end))
end

local function limited(text, font, maxWidth)
    while font:getWidth(text .. "...") > maxWidth and #text > 0 do
        text = text:sub(1, utf8.offset(text, -1) - 1)
    end
    return text .. "..."
end

function BattleFX.new()
    local self = setmetatable({ w = 1280, h = 720, shakeEnabled = true, lightPool = {} }, BattleFX)
    self:clear()
    return self
end

function BattleFX:clear()
    self.particles, self.backParticles = {}, {}
    self.props, self.texts, self.speech = {}, {}, {}
    self.summon, self.activeCombo, self.defeatFinale = nil, nil, nil
    self.age, self.shakeAge, self.shakeDuration, self.shakeMagnitude = 0, 0, 0, 0
    self.hitStopTimer, self.flashTimer = 0, 0
    self.anchors = nil
    self.rivalCard = nil
end

function BattleFX:setTypography(fonts)
    self.fonts = fonts
end

function BattleFX:setRivalCard(rivalCard)
    self.rivalCard = rivalCard
end

function BattleFX:clearTurn()
    self.summon, self.activeCombo = nil, nil
    self.texts, self.speech = {}, {}
    self.particles, self.backParticles = {}, {}
end

local function propAnchor(self, anchor, a)
    if anchor == "above_enemy" then return a.ex, math.max(96, a.ey - 178) end
    if anchor == "near_pudu" then return a.px, math.min(self.h - 122, a.py - 4) end
    if anchor == "center" then return (a.px + a.ex) * 0.5, a.ey end
    return a.ex, a.ey
end

function BattleFX:setBattleAnchors(px, py, ex, ey, enemyWidth, enemyHeight)
    local a = self.anchors or {}
    a.px, a.py, a.ex, a.ey = px, py, ex, ey
    a.ew, a.eh = enemyWidth or 120, enemyHeight or 148
    self.anchors = a
    for _, prop in ipairs(self.props) do
        local x, y = propAnchor(self, prop.anchor, a)
        if not prop.offsetX then prop.offsetX, prop.offsetY = prop.x - x, prop.y - y end
        prop.x, prop.y = x + prop.offsetX, y + prop.offsetY
    end
end

function BattleFX:setViewport(w, h)
    if self.w == w and self.h == h then return end
    local sx, sy = w / self.w, h / self.h
    for _, list in ipairs({ self.particles, self.backParticles, self.props, self.texts,
        { self.summon }, { self.activeCombo }, { self.defeatFinale } }) do
        for _, effect in ipairs(list) do
            effect.x, effect.y = effect.x * sx, effect.y * sy
        end
    end
    if self.summon then
        local s = self.summon
        s.x0, s.y0, s.x1, s.y1 = s.x0 * sx, s.y0 * sy, s.x1 * sx, s.y1 * sy
    end
    local a = self.anchors
    self.w, self.h = w, h
    if a then self:setBattleAnchors(a.px * sx, a.py * sy, a.ex * sx, a.ey * sy, a.ew, a.eh) end
end

function BattleFX:setShakeEnabled(enabled)
    self.shakeEnabled = not not enabled
    if not enabled then self.shakeDuration = 0 end
end

function BattleFX:triggerShake(magnitude, duration)
    if not self.shakeEnabled then return end
    self.shakeAge = 0
    self.shakeMagnitude = clamp(magnitude, 0, 11)
    self.shakeDuration = clamp(duration, 0, 0.36)
end

function BattleFX:getShakeOffset()
    if self.shakeAge >= self.shakeDuration then return 0, 0 end
    local strength = self.shakeMagnitude * (1 - self.shakeAge / self.shakeDuration) ^ 2
    return math.sin(self.shakeAge * 119) * strength, math.sin(self.shakeAge * 89) * strength * 0.55
end

function BattleFX:isHitStopped()
    return self.hitStopTimer > 0
end

-- Color, gravity, speed, size, lifetime and shape of each procedural effect.
local PARTICLES = {
    rain      = { {0.43, 0.78, 1.00}, 340,  65, 12, 0.38, "drop", 145 },
    snow      = { {0.76, 0.92, 1.00},  22,  42,  5, 0.93, "flake", 32 },
    fire      = { {1.00, 0.46, 0.15}, -69,  75,  8, 0.54, "ember", -37, true },
    splash    = { {0.37, 0.76, 1.00}, 380, 123,  7, 0.60, "drop", -54 },
    hearts    = { {1.00, 0.36, 0.61}, -12,  59,  7, 1.24, "heart", -48 },
    tears     = { {0.47, 0.77, 1.00}, 394,  62,  7, 0.45, "drop", -86 },
    steam     = { {1.00, 0.85, 0.88}, -31,  28, 19, 1.05, "cloud", -31 },
    flash     = { {0.76, 0.96, 1.00},   0, 177, 12, 0.34, "star",  0, true },
    confetti  = { {1.00, 0.87, 0.37}, 128, 214,  7, 1.70, "paper", -30 },
    stink     = { {0.61, 0.84, 0.28}, -20,  43, 16, 0.94, "cloud", -22 },
    mud       = { {0.66, 0.37, 0.20}, 420, 105,  9, 0.51, "blob", -97 },
    music     = { {0.86, 0.61, 1.00}, -26,  64,  8, 0.94, "note", -44 },
    explosion = { {1.00, 0.58, 0.20}, 150, 219, 11, 0.58, "ember", -35, true },
    wind      = { {0.59, 0.94, 0.92},   0, 130, 14, 0.56, "trail", -10 },
    bubbles   = { {0.64, 0.97, 1.00}, -12,  55,  9, 0.94, "ring", -34 },
    stars     = { {1.00, 0.83, 0.32},  36,  93,  8, 0.81, "star", -38, true },
    dust      = { {0.78, 0.65, 0.47}, -22,  62, 13, 0.72, "cloud", -10 },
    sweat     = { {0.50, 0.80, 1.00}, 240,  62,  8, 0.55, "drop", -18 },
    sparkles  = { {1.00, 0.91, 0.50}, -16, 100,  6, 0.70, "star", -21, true },
}
local CONFETTI = { {1, 0.42, 0.54}, {0.35, 0.91, 0.83}, {0.98, 0.80, 0.30}, {0.68, 0.55, 1} }

function BattleFX:spawnParticles(kind, x, y, count)
    if kind == "none" then return end
    local data = PARTICLES[kind] or PARTICLES.sparkles
    local available = MAX_PARTICLES - #self.particles - #self.backParticles
    local list = kind == "dust" and self.backParticles or self.particles
    for i = 1, math.min(available, count or 12) do
        local angle = math.random() * TAU
        local speed = data[3] * (0.40 + math.random() * 0.60)
        local startX = x
        local vx = math.cos(angle) * speed
        if kind == "tears" then
            local side = i % 2 == 0 and -1 or 1
            startX = x + side * 12
            vx = side * (28 + math.random() * 32)
        elseif kind == "confetti" then
            startX = x + (math.random() - 0.5) * 130
        end
        list[#list + 1] = {
            data = data, color = kind == "confetti" and CONFETTI[1 + i % #CONFETTI] or data[1],
            x = startX, y = y, vx = vx, vy = math.sin(angle) * speed + data[7],
            age = 0, life = data[5] * (0.66 + math.random() * 0.46),
            size = data[4] * (0.48 + math.random() * 0.70), spin = angle,
        }
    end
end

local function advanceParticles(list, dt)
    local count = 0
    for _, p in ipairs(list) do
        p.age = p.age + dt
        if p.age < p.life then
            p.vy = p.vy + p.data[2] * dt
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            count = count + 1
            list[count] = p
        end
    end
    for i = #list, count + 1, -1 do list[i] = nil end
end

local function drawStar(x, y, r)
    local lg = love.graphics
    lg.polygon("fill", x, y - r, x + r * 0.27, y, x, y + r, x - r * 0.27, y)
    lg.polygon("fill", x - r, y, x, y - r * 0.27, x + r, y, x, y + r * 0.27)
end

local function drawDrop(x, y, r)
    local lg = love.graphics
    lg.polygon("fill", x - r * 0.39, y, x, y - r, x + r * 0.39, y)
    lg.ellipse("fill", x, y + r * 0.13, r * 0.40, r * 0.49)
end

local function drawHeart(x, y, r)
    local lg = love.graphics
    lg.circle("fill", x - r * 0.41, y - r * 0.25, r * 0.49, 12)
    lg.circle("fill", x + r * 0.41, y - r * 0.25, r * 0.49, 12)
    lg.polygon("fill", x - r * 0.80, y, x + r * 0.80, y, x, y + r * 0.94)
end

local function drawFlake(x, y, r)
    local lg = love.graphics
    for i = 0, 2 do
        local a = i * math.pi / 3
        local dx, dy = math.cos(a) * r, math.sin(a) * r
        lg.line(x - dx, y - dy, x + dx, y + dy)
    end
end

local SHAPES = {
    star = drawStar,
    drop = drawDrop,
    flake = drawFlake,
    heart = drawHeart,
    ring = function(x, y, r)
        love.graphics.circle("line", x, y, r, 14)
        love.graphics.circle("fill", x - r * 0.32, y - r * 0.41, r * 0.16, 8)
    end,
    blob = function(x, y, r) love.graphics.ellipse("fill", x, y, r * 0.8, r * 0.55, 12) end,
    cloud = function(x, y, r) love.graphics.circle("fill", x, y, r, 12) end,
    ember = function(x, y, r) love.graphics.ellipse("fill", x, y, r * 0.55, r, 10) end,
    paper = function(x, y, r, age, spin)
        local shift = math.cos(age * 19 + spin) * r * 0.85
        love.graphics.polygon("fill", x - r + shift, y - r * 0.5, x + shift, y - r * 0.5,
            x + r - shift, y + r * 0.45, x - shift, y + r * 0.45)
    end,
    note = function(x, y, r)
        local lg = love.graphics
        lg.ellipse("fill", x - r * 0.25, y + r * 0.40, r * 0.49, r * 0.32, 10)
        lg.rectangle("fill", x + r * 0.10, y - r * 0.96, r * 0.16, r * 1.42)
        lg.polygon("fill", x + r * 0.18, y - r * 0.96, x + r * 0.78, y - r * 0.55,
            x + r * 0.72, y - r * 0.2, x + r * 0.18, y - r * 0.64)
    end,
    trail = function(x, y, r, _, _, vx)
        love.graphics.line(x - r * (vx < 0 and -1 or 1), y + r * 0.26, x, y, x + r * 0.2, y - r * 0.1)
    end,
}

local function drawParticles(list)
    local lg = love.graphics
    lg.setLineWidth(1.5)
    for _, p in ipairs(list) do
        local progress = p.age / p.life
        local shape = p.data[6]
        local size = p.size * (shape == "cloud" and (0.65 + progress) or (1 - progress * 0.46))
        local alpha = (1 - progress) * (shape == "cloud" and 0.43 or 0.95)
        lg.setColor(p.color[1], p.color[2], p.color[3], alpha)
        SHAPES[shape](p.x, p.y, size, p.age, p.spin, p.vx)
    end
end

local DELIVERY_TIME = {
    overhead_weather = 0.36, drop_from_sky = 0.38, throw_arc = 0.40,
    charge_across = 0.28, pop_underneath = 0.32, buff_pudu = 0.34,
}

function BattleFX:launchSummon(result, spriteObj, startX, startY, targetX, targetY, audio, key)
    local style = result.delivery_style
    local duration = DELIVERY_TIME[style] or DELIVERY_TIME.throw_arc
    if style == "overhead_weather" then
        targetY = math.max(96, targetY - 178)
        startX, startY = targetX - 30, targetY - 46
    elseif style == "drop_from_sky" then
        targetY = targetY - 46
        startX, startY = targetX - 16, math.max(70, targetY - 280)
    elseif style == "pop_underneath" then
        targetY = targetY - 18
        startX, startY = targetX, targetY + 42
    elseif style == "buff_pudu" then
        targetX, targetY = startX, startY - 78
        startX = targetX - 55
    else
        startY, targetY = startY - 94, targetY - 61
    end
    self.summon = {
        result = result, sprite = spriteObj,
        key = key or (result.existing_sprite ~= "none" and result.existing_sprite) or result.summon_name,
        style = style, x = startX, y = startY, x0 = startX, y0 = startY, x1 = targetX, y1 = targetY,
        age = 0, duration = duration, p = 0, hold = 0.23,
    }
    play(audio, "sfx_spell_unleash", 0.65)
    return duration
end

function BattleFX:hasSummonArrived()
    return self.summon == nil or self.summon.age >= self.summon.duration
end

function BattleFX:getPersistentProps()
    return self.props
end

function BattleFX:addPersistentProp(prop)
    for i, old in ipairs(self.props) do
        if old.key == prop.key then table.remove(self.props, i) break end
    end
    if self.anchors then
        local x, y = propAnchor(self, prop.anchor, self.anchors)
        prop.offsetX, prop.offsetY = prop.x - x, prop.y - y
    end
    prop.age = 0
    self.props[#self.props + 1] = prop
    if #self.props > MAX_PERSISTENT_PROPS then table.remove(self.props, 1) end
end

function BattleFX:spawnFloatingText(text, x, y, color, scale, isCrit)
    if color == "damage" then color = COLOR_PUDU_DAMAGE end
    self.texts[#self.texts + 1] = {
        text = text, x = x, y = y, color = type(color) == "table" and color or COLOR_DAMAGE,
        scale = scale or 1, crit = isCrit, age = 0,
    }
end

function BattleFX:triggerImpact(result, targetX, targetY, puduX, puduY, audio)
    local summon = self.summon
    if not summon or summon.result ~= result then summon = nil end
    local delta = result.damage_to_enemy or 0
    local critical = result.is_critical == true
    local buff = result.delivery_style == "buff_pudu"
    local sourceX, sourceY = targetX, targetY - 56
    if buff then sourceX, sourceY = puduX, puduY - 86 end
    local overhead = result.delivery_style == "overhead_weather" or result.prop_anchor == "above_enemy"
    if overhead then sourceY = math.max(96, targetY - 178) end
    local weather = overhead and (result.particle_fx == "rain" or result.particle_fx == "snow")
    if not weather then
        self:spawnParticles(result.particle_fx, sourceX, sourceY, critical and 34 or 16)
    end
    if delta > 0 then
        self:spawnFloatingText(critical and ("-%d ¡CRÍTICO!"):format(delta) or ("-%d"):format(delta),
            targetX + 86 + (critical and 52 or 12), targetY - 118, critical and COLOR_GOLD or COLOR_DAMAGE,
            critical and 1.10 or 1, critical)
    end
    local healing, selfDamage = result.heal_pudu or 0, result.damage_to_pudu or 0
    if healing > 0 then
        self:spawnFloatingText(("+%d PV"):format(healing), puduX + 93, puduY - 130, COLOR_HEAL)
    end
    if selfDamage > 0 then
        self:spawnFloatingText(("-%d AUTOGOL"):format(selfDamage), puduX + 93, puduY - 130, COLOR_PUDU_DAMAGE, 0.88)
    end
    if result.keep_prop_on_stage and not (summon and summon.persisted) then
        local x, y, anchor = targetX, targetY + 18, result.prop_anchor
        if overhead then
            y, anchor = math.max(96, targetY - 178), "above_enemy"
        elseif anchor == "near_pudu" then
            x, y = puduX - 85, math.min(self.h - 122, puduY - 4)
        elseif anchor == "center" then
            x, y = (targetX + puduX) * 0.5, targetY + 28
        else
            x = targetX - 24
        end
        self:addPersistentProp({ key = (summon and summon.key) or result.summon_name or result.existing_sprite,
            sprite = summon and summon.sprite, kind = result.particle_fx, anchor = anchor,
            x = x, y = y })
        if summon then summon.persisted = true end
    end
    if delta > 0 or selfDamage > 0 then
        self.hitStopTimer = math.max(self.hitStopTimer, 0.08)
        self.flashTimer = 0.13
        self:triggerShake(critical and 8 or 4, 0.21)
    end
    play(audio, result.sfx)
    play(audio, result.reaction_sfx)
end

function BattleFX:triggerComboSpectacle(comboType, comboName, targetX, targetY, audio)
    if not Spectacles or not comboType or comboType == "none" then return end
    local kind = Spectacles.normalizeComboType(comboType)
    local theme = Spectacles.COMBO_THEMES[kind]
    local name = comboName and comboName ~= "" and comboName or theme.defaultName
    self.activeCombo = { kind = kind, name = name, x = targetX, y = targetY - 20, age = 0, duration = 2.2 }
    Spectacles.spawnComboBurst(self, kind, targetX, targetY - 20)
    self.hitStopTimer, self.flashTimer = 0.10, 0.16
    self:triggerShake(theme.shakeMag, 0.32)
    play(audio, theme.sfx1)
    play(audio, theme.sfx2, 0.66)
end

function BattleFX:startDefeatFinale(reaction, enemyX, enemyY)
    self.defeatFinale = { reaction = reaction or "defeated", x = enemyX, y = enemyY, age = 0 }
    if Spectacles then Spectacles.spawnFinaleBurst(self, reaction or "defeated", enemyX, enemyY) end
end

function BattleFX:getDefeatTransform()
    if not self.defeatFinale or not Spectacles then return CLEAR end
    return Spectacles.computeDefeatTransform(self.defeatFinale)
end

function BattleFX:setSpeechBubble(who, text, duration, style)
    self.speech[who] = text and text ~= "" and { text = text, duration = duration or 2.4,
        style = style or "normal", age = 0 } or nil
end

function BattleFX:update(dt)
    self.age = self.age + dt
    self.shakeAge = self.shakeAge + dt
    self.flashTimer = math.max(0, self.flashTimer - dt)
    local paused = math.min(dt, self.hitStopTimer)
    self.hitStopTimer = self.hitStopTimer - paused
    dt = dt - paused
    if dt <= 0 then return end

    advanceParticles(self.particles, dt)
    advanceParticles(self.backParticles, dt)
    for _, prop in ipairs(self.props) do prop.age = prop.age + dt end
    for i = #self.texts, 1, -1 do
        local f = self.texts[i]
        f.age = f.age + dt
        if f.age >= 1.45 then table.remove(self.texts, i) end
    end
    for who, speech in pairs(self.speech) do
        speech.age = speech.age + dt
        if speech.age >= speech.duration then self.speech[who] = nil end
    end
    local summon = self.summon
    if summon then
        summon.age = summon.age + dt
        summon.p = clamp(summon.age / summon.duration, 0, 1)
        local p = summon.p
        local travel = summon.style == "drop_from_sky" and p * p or p
        local arc = summon.style == "throw_arc" and math.sin(p * math.pi) * 84 or 0
        summon.x = lerp(summon.x0, summon.x1, travel)
        summon.y = lerp(summon.y0, summon.y1, travel) - arc
        if summon.age > summon.duration + summon.hold then self.summon = nil end
    end
    local c = self.activeCombo
    if c then
        c.age = c.age + dt
        if c.age < c.duration then Spectacles.updateCombo(self, c, dt) else self.activeCombo = nil end
    end
    local f = self.defeatFinale
    if f and Spectacles then
        f.age = f.age + dt
        Spectacles.updateFinale(self, f, dt)
    end
end

local function shakeSafe(self, area)
    if not area or not self.shakeEnabled then return area end
    return box(area.x - 11, area.y - 7, area.w + 22, area.h + 14)
end

local function faceBounds(self)
    local a = self.anchors
    if not a then return box(self.w * 0.72 - 56, self.h * 0.50 - 148, 112, 109) end
    local width = clamp(a.ew, 72, self.w * 0.23)
    return box(a.ex - width / 2, a.ey - a.eh, width, math.max(36, a.eh * 0.72))
end

local function bannerMaxWidth(self)
    local face = shakeSafe(self, faceBounds(self))
    local right = self.w
    if face.y < 140 and face.y + face.h > 80 then
        right = face.x - 6
    end
    if self.rivalCard and self.rivalCard.x > self.w * 0.5 then
        right = math.min(right, self.rivalCard.x - 8)
    end
    return math.max(126, 2 * (right - self.w * 0.5))
end

local function bannerBounds(self, fonts)
    if not (self.activeCombo and Spectacles and fonts) then return nil end
    local x, y, w, h = Spectacles.getComboBannerBounds(self.activeCombo, fonts, self.w, bannerMaxWidth(self))
    return box(x, y, w, h)
end

local function weatherBounds(self, x, y, index, banner, face)
    local px = clamp(x + WEATHER_OFFSETS[index], 48, self.w - 48)
    local py = math.max(82, y)
    local cloud = box(px - 44, py - 21, 88, 43)
    local function toSide(obstacle)
        local right = obstacle.x + obstacle.w + 50
        local left = obstacle.x - 50
        local a = face.x + face.w / 2
        if right <= self.w - 48 then px = right + (index - 1) * 17
        elseif left >= a - 35 and left >= 48 then px = left - (index - 1) * 17
        else py = obstacle.y - 25 end
        px = clamp(px, 48, self.w - 48)
        cloud.x, cloud.y = px - 44, py - 21
    end
    if banner and intersects(cloud, banner) then toSide(banner) end
    if intersects(cloud, face) then toSide(face) end
    if banner and intersects(cloud, banner) then
        py = banner.y + banner.h + 26
        cloud.y = py - 21
        if intersects(cloud, face) then toSide(face) end
    end
    local rainHeight = 36
    if cloud.x + cloud.w > face.x and face.x + face.w > cloud.x then
        rainHeight = clamp(face.y - py - 22, 0, rainHeight)
    end
    return px, py, cloud, rainHeight
end

local function propReservations(self, face, banner)
    local reserved, index = {}, 0
    for _, prop in ipairs(self.props) do
        if prop.anchor == "above_enemy" then
            index = index + 1
            local _, _, area, rainH = weatherBounds(self, prop.x, prop.y, index, banner, face)
            area.h = area.h + rainH
            reserved[#reserved + 1] = area
        else
            reserved[#reserved + 1] = box(prop.x - 32, prop.y - 31, 64, 46)
        end
    end
    return reserved
end

local function drawCloud(x, y, scale, alpha)
    local lg = love.graphics
    lg.setColor(0.12, 0.20, 0.35, alpha)
    lg.ellipse("fill", x, y + 3 * scale, 39 * scale, 13 * scale)
    lg.circle("fill", x - 16 * scale, y - 3 * scale, 15 * scale, 14)
    lg.circle("fill", x + 7 * scale, y - 5 * scale, 18 * scale, 18)
    lg.setColor(0.63, 0.76, 0.95, alpha)
    lg.ellipse("fill", x, y + 2 * scale, 36 * scale, 10 * scale)
    lg.circle("fill", x - 16 * scale, y - 4 * scale, 12 * scale, 14)
    lg.circle("fill", x + 7 * scale, y - 6 * scale, 15 * scale, 18)
    lg.setColor(0.89, 0.95, 1, alpha * 0.8)
    lg.ellipse("fill", x - 3 * scale, y - 11 * scale, 13 * scale, 4 * scale)
end

local function drawProceduralFallbackSummon(kind, style, x, y, size, alpha, angle)
    local lg = love.graphics
    if style == "overhead_weather" or kind == "rain" or kind == "snow" then
        drawCloud(x, y, size / 82, alpha)
        return
    end
    local color = (PARTICLES[kind] or PARTICLES.sparkles)[1]
    lg.push()
    lg.translate(x, y)
    lg.rotate(angle)
    local r = size * 0.5
    lg.setColor(0.10, 0.07, 0.19, alpha * 0.94)
    drawStar(0, 3, r + 4)
    lg.setColor(color[1], color[2], color[3], alpha)
    drawStar(0, 0, r)
    lg.setColor(1, 0.99, 0.84, alpha)
    drawStar(0, 0, r * 0.48)
    lg.setColor(0.13, 0.08, 0.23, alpha)
    lg.circle("fill", -r * 0.13, -r * 0.13, r * 0.056, 10)
    lg.circle("fill", r * 0.13, -r * 0.13, r * 0.056, 10)
    lg.arc("line", "open", 0, -r * 0.06, r * 0.12, 0.1, math.pi - 0.1, 8)
    lg.pop()
end

local function drawSprite(pair, x, y, width, height, angle, alpha, litShader, drawLit)
    local image = pair and (pair.diff or pair.image)
    if not image then return false end
    local w, h = image:getDimensions()
    local s = math.min(width / w, height / h)
    love.graphics.setColor(1, 1, 1, alpha)
    if litShader and drawLit and pair.diff then
        drawLit(pair, x, y, angle, s, s, w / 2, h / 2, litShader)
    else
        love.graphics.draw(image, x, y, angle, s, s, w / 2, h / 2)
    end
    return true
end

local function drawWeather(prop, x, y, rainHeight, litShader, drawLit)
    local lg = love.graphics
    local alpha = clamp(prop.age * 9 + 0.22, 0, 1)
    local sprite = prop.sprite
    if not sprite or sprite.isPlaceholder or not drawSprite(sprite, x, y, 82, 42, 0, alpha, litShader, drawLit) then
        drawCloud(x, y, 1, alpha)
    end
    if rainHeight <= 0 then return end
    lg.setLineWidth(1.6)
    for i = 1, 8 do
        local p = (prop.age * (prop.kind == "snow" and 1.4 or 3.7) + i * 0.29) % 1
        local dx = (i - 4.5) * 8
        local dropY = y + 15 + p * rainHeight
        lg.setColor(0.58, 0.83, 1, (1 - p) * 0.82 * alpha)
        if prop.kind == "snow" then
            drawFlake(x + dx + math.sin(prop.age * 3 + i) * 4, dropY, 2.6)
        else
            lg.line(x + dx, dropY, x + dx - 2, math.min(dropY + 8, y + 21 + rainHeight))
        end
    end
end

function BattleFX:drawBackLayer()
    local lg = love.graphics
    lg.push("all")
    lg.setShader()
    drawParticles(self.backParticles)
    for _, prop in ipairs(self.props) do
        if prop.anchor ~= "above_enemy" then
            lg.setColor(0.04, 0.07, 0.13, 0.32)
            lg.ellipse("fill", prop.x, prop.y + 7, 28, 7, 20)
        end
    end
    if self.defeatFinale and Spectacles then Spectacles.drawDefeatBackLayer(self.defeatFinale, self.age) end
    lg.pop()
end

function BattleFX:drawSummonsAndProps(litShader, drawLit)
    local lg = love.graphics
    lg.push("all")
    lg.setShader()
    local banner, face = bannerBounds(self, self.fonts), faceBounds(self)
    local index = 0
    for _, prop in ipairs(self.props) do
        if prop.anchor == "above_enemy" then
            index = index + 1
            local x, y, _, rainHeight = weatherBounds(self, prop.x, prop.y, index, banner, face)
            drawWeather(prop, x, y, rainHeight, litShader, drawLit)
        elseif (prop.key == "melted_icecream" and prop.sprite and prop.sprite.isPlaceholder)
            or not drawSprite(prop.sprite, prop.x, prop.y - 8, 60, 44, 0, 1, litShader, drawLit) then
            if prop.key == "melted_icecream" then
                lg.setColor(0.92, 0.58, 0.70, 0.96)
                lg.ellipse("fill", prop.x, prop.y, 29, 8, 22)
                lg.setColor(1, 0.81, 0.76, 0.92)
                lg.ellipse("fill", prop.x - 10, prop.y - 3, 12, 4, 14)
                lg.setColor(0.88, 0.59, 0.28, 1)
                lg.polygon("fill", prop.x + 3, prop.y - 13, prop.x + 8, prop.y - 1, prop.x + 29, prop.y + 2)
            elseif prop.kind == "splash" or prop.kind == "rain" or prop.kind == "bubbles" then
                lg.setColor(0.23, 0.60, 0.85, 0.68)
                lg.ellipse("fill", prop.x, prop.y, 27, 8, 22)
                lg.setColor(0.65, 0.88, 0.99, 0.67)
                lg.arc("line", "open", prop.x, prop.y, 10 + math.sin(prop.age * 4) * 4, 0.1, math.pi - 0.1, 12)
            else
                drawProceduralFallbackSummon(prop.kind, nil, prop.x, prop.y - 12, 37, 0.92, 0)
            end
        end
    end
    local s = self.summon
    if s and not s.persisted then
        local x, y = s.x, s.y
        local alpha = 1 - clamp((s.age - s.duration) / s.hold, 0, 1)
        local size = 74 * (0.35 + 0.65 * easeOutBack(math.min(s.p * 2, 1)))
        local angle = s.style == "throw_arc" and (s.p - 0.5) * TAU or 0
        if s.style == "overhead_weather" then
            local weatherX, weatherY, _, rainHeight = weatherBounds(self, x, y, 1, banner, face)
            drawWeather({ kind = s.result.particle_fx, sprite = s.sprite, age = s.age }, weatherX, weatherY,
                rainHeight, litShader, drawLit)
        elseif not drawSprite(s.sprite, x, y, size, size, angle, alpha, litShader, drawLit) then
            drawProceduralFallbackSummon(s.result.particle_fx, s.style, x, y, size, alpha, angle)
        end
    end
    lg.pop()
end

local REACTION = {
    crying = { "drop", { 0.49, 0.79, 1 }, 3 },
    dizzy = { "star", COLOR_GOLD, 3 },
    angry = { "vein", { 1, 0.40, 0.34 }, 1 },
    scared = { "drop", { 0.52, 0.83, 1 }, 1 },
    shocked = { "alert", COLOR_GOLD, 1 },
    frozen = { "flake", { 0.65, 0.93, 1 }, 3 },
    wet = { "drop", { 0.50, 0.82, 1 }, 2 },
    laughing = { "note", COLOR_GOLD, 2 },
    happy_pacified = { "heart", { 1, 0.45, 0.68 }, 2 },
    embarrassed = { "drop", { 0.82, 0.71, 1 }, 1 },
    chased = { "alert", COLOR_GOLD, 1 },
    splatted = { "blob", { 0.82, 0.55, 0.37 }, 3 },
    confused = { "star", { 0.84, 0.69, 1 }, 2 },
    distracted = { "star", { 0.62, 0.85, 1 }, 1 },
}

function BattleFX:drawReactionOverlay(state, enemyX, enemyY, time)
    local lg = love.graphics
    lg.push("all")
    lg.setShader()
    local duplicateIce = self.defeatFinale and self.defeatFinale.reaction == "frozen"
        and self.activeCombo and self.activeCombo.kind == "combo_deep_freeze"
    if self.activeCombo and Spectacles and not duplicateIce then Spectacles.drawComboSpectacle(self.activeCombo, time) end
    if self.defeatFinale and Spectacles then
        Spectacles.drawDefeatFinaleOverlay(self.defeatFinale, time)
    else
        local reaction = REACTION[state]
        if reaction then
            local shape, color, count = reaction[1], reaction[2], reaction[3]
            local pose = faceBounds(self)
            local baseX = math.min(enemyX - 42, pose.x - 8)
            lg.setLineWidth(2.3)
            lg.setColor(color[1], color[2], color[3], 0.95)
            for i = 1, count do
                local x, y = baseX - (i - 1) * 13, enemyY - 102 + math.sin(time * 7 + i) * 4 + (i - 1) * 11
                if shape == "vein" then
                    lg.line(x - 13, y - 8, x - 4, y - 6, x - 5, y - 14)
                    lg.line(x + 6, y - 14, x + 4, y - 5, x + 14, y - 7)
                    lg.line(x - 13, y + 7, x - 5, y + 5, x - 7, y + 14)
                    lg.line(x + 14, y + 7, x + 5, y + 5, x + 8, y + 14)
                elseif shape == "alert" then
                    lg.polygon("fill", x - 4, y - 13, x + 4, y - 13, x + 2, y + 2, x - 2, y + 2)
                    lg.circle("fill", x, y + 8, 3, 10)
                else
                    SHAPES[shape](x, y, 8)
                end
            end
        end
    end
    lg.pop()
end

local BUBBLE_THEME = {
    normal = { {0.96, 0.85, 0.64}, {0.54, 0.35, 0.21}, 0 },
    shout  = { {1.00, 0.86, 0.56}, {0.68, 0.30, 0.19}, 2 },
    cry    = { {0.87, 0.90, 0.81}, {0.34, 0.52, 0.46}, 0 },
    laugh  = { {1.00, 0.90, 0.70}, {0.68, 0.43, 0.24}, 3 },
    think  = { {0.94, 0.84, 0.72}, {0.54, 0.39, 0.37}, 0 },
}

local function sceneReservations(self, fonts)
    local face, banner = faceBounds(self), bannerBounds(self, fonts)
    local reserved = propReservations(self, face, banner)
    reserved[#reserved + 1] = shakeSafe(self, face)
    local card = self.rivalCard
    if card then
        reserved[#reserved + 1] = box(card.x - 4, card.y - 4, card.w + 8, card.h + 8)
    end
    if banner then reserved[#reserved + 1] = banner end
    local a = self.anchors
    if a then
        reserved[#reserved + 1] = shakeSafe(self, box(a.px - 61, a.py - 217, 122, 110))
        reserved[#reserved + 1] = shakeSafe(self, box(face.x - 51, a.ey - 121, 52, 69))
        reserved[#reserved + 1] = box(a.ex - 111, a.ey + 36, 222, 74)
    end
    return reserved, banner, face
end

local function placeBubble(self, who, px, py, ex, ey, font, reserved, banner, face)
    local speech = self.speech[who]
    if not speech then return nil end
    local text = textForFont(font, speech.text)
    local padding, fontH = 26, font:getHeight()
    local desiredX, desiredY = px + 10, py - 148
    if who == "enemy" then desiredX, desiredY = ex - 55, clamp(ey - 210, 58, 148) end
    for _, maxWidth in ipairs({ 290, 248, 202, 158 }) do
        local bw = clamp(font:getWidth(text) + padding, 100, maxWidth)
        local _, lines = font:getWrap(text, bw - padding)
        if #lines > 3 then
            lines[3] = limited(lines[3], font, bw - padding)
            for i = #lines, 4, -1 do lines[i] = nil end
        end
        local bh = #lines * fontH + 16
        local x = clamp(desiredX, 16, self.w - bw - 16)
        local right = self.w - bw - 16
        local left = math.max(16, face.x - bw - 82)
        local candidates
        if who == "enemy" then
            candidates = {
                { x, desiredY },
                { banner and banner.x + banner.w + 10 or right, desiredY },
                { x, 150 }, { left, 150 }, { right, 150 }, { left, desiredY },
                { right, 58 }, { left, 58 }, { left, 98 },
            }
        else
            candidates = { { x, desiredY }, { px + 70, desiredY }, { px - bw - 65, desiredY },
                { px + 69, desiredY - 57 }, { px - bw, desiredY - 88 }, { 18, 150 } }
        end
        for _, candidate in ipairs(candidates) do
            local bx, by = candidate[1], candidate[2]
            local area = box(bx - 7, by - 4, bw + 14, bh + 21)
            if bx >= 12 and bx + bw + 12 <= self.w and by >= 58 and by + bh + 19 < self.h - 90
                and vacant(area, reserved) then
                reserved[#reserved + 1] = area
                return { x = bx, y = by, w = bw, h = bh, lines = lines, speech = speech, tip = who == "enemy" and ex or px }
            end
        end
    end
end

local function layoutSpeech(self, px, py, ex, ey, fonts, reserved, banner, face)
    local font = fonts.body or fonts.small or love.graphics.getFont()
    local enemy = placeBubble(self, "enemy", px, py, ex, ey, font, reserved, banner, face)
    local pudu = placeBubble(self, "pudu", px, py, ex, ey, font, reserved, banner, face)
    return enemy, pudu, font
end

local function drawBubble(item, font)
    if not item then return end
    local lg = love.graphics
    local style, age = item.speech.style, item.speech.age
    local theme = BUBBLE_THEME[style] or BUBBLE_THEME.normal
    local fill, edge = theme[1], theme[2]
    local x, y, w, h = item.x, item.y, item.w, item.h
    local alpha = clamp((item.speech.duration - age) * 5.6, 0, 1)
    if style == "shout" then x = x + math.sin(age * 57) * theme[3] end
    if style == "laugh" then y = y - math.abs(math.sin(age * 9)) * theme[3] end
    local tip = clamp(item.tip, x + 21, x + w - 21)
    lg.setColor(0.14, 0.08, 0.04, alpha * 0.66)
    lg.rectangle("fill", x + 2, y + 4, w, h, 9, 9)
    lg.setColor(edge[1], edge[2], edge[3], alpha)
    if style == "shout" then
        for i = 1, 5 do
            local k = x + 14 + (w - 28) * (i - 1) * 0.25
            lg.polygon("fill", k - 7, y + 3, k + 1, y - 4, k + 7, y + 3)
        end
    end
    lg.rectangle("fill", x, y, w, h, 9, 9)
    if style == "think" then
        lg.circle("fill", tip, y + h + 4, 4.6, 12)
        lg.circle("fill", tip + 8, y + h + 12, 2.7, 12)
    else
        lg.polygon("fill", tip - 9, y + h - 2, tip + 8, y + h - 2, tip + 3, y + h + 9)
    end
    lg.setColor(fill[1], fill[2], fill[3], alpha)
    lg.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 7, 7)
    if style ~= "think" then
        lg.polygon("fill", tip - 6, y + h - 4, tip + 5, y + h - 4, tip + 3, y + h + 5)
    end
    if style == "cry" then
        lg.setColor(0.31, 0.64, 0.89, alpha)
        for i = 1, 2 do
            drawDrop(x + w - 6 - i * 10, y + h + 3 + (age * (4 + i) % 1) * 9, 4)
        end
    end
    lg.setColor(0.24, 0.14, 0.08, alpha)
    lg.setFont(font)
    for i, line in ipairs(item.lines) do
        lg.print(line, math.floor(x + (w - font:getWidth(line)) * 0.5), math.floor(y + 7 + (i - 1) * font:getHeight()))
    end
end

function BattleFX:drawSpeechBubbles(px, py, ex, ey, fonts)
    local lg = love.graphics
    local reserved, banner, face = sceneReservations(self, fonts)
    local enemy, pudu, font = layoutSpeech(self, px, py, ex, ey, fonts, reserved, banner, face)
    lg.push("all")
    lg.setShader()
    drawBubble(enemy, font)
    drawBubble(pudu, font)
    lg.pop()
end

local function insideCandidate(self, x, y, width, fontH, reserved)
    if y - fontH / 2 - 24 < 54 or y > self.h - 130 then return false end
    local area = box(x - width / 2, y - fontH / 2 - 24, width, fontH + 25)
    for _, other in ipairs(reserved) do
        if other.textX and math.abs(x - other.textX) < 170 and math.abs(y - other.textY) < 42 then return false end
        if intersects(area, other) then return false end
    end
    return true
end

local function findTextPosition(self, x, y, minX, maxX, minY, width, height, reserved)
    if insideCandidate(self, x, y, width, height, reserved) then return x, y end
    -- Prefer the upper-right impact lane if weather occupies the center of the arena.
    local sideX = clamp(x + 176, minX, maxX)
    if sideX ~= x and insideCandidate(self, sideX, y, width, height, reserved) then return sideX, y end
    for pass = 1, 6 do
        local fy = y - pass * 44
        if fy >= minY and insideCandidate(self, x, fy, width, height, reserved) then
            return x, fy
        end
    end
    -- Reserve nearby columns when effects already occupy the original column.
    for _, dy in ipairs({0, -44, 44, -88, 88, -132, 132, -176, 176, -220, 220}) do
        local fy = y + dy
        for _, dx in ipairs({-176, 176, -352, 352}) do
            local fx = clamp(x + dx, minX, maxX)
            if insideCandidate(self, fx, fy, width, height, reserved) then return fx, fy end
        end
    end
end

local function drawText(self, text, font, reserved)
    local value = textForFont(font, text.text)
    local fw, fh = font:getWidth(value), font:getHeight()
    local scale = math.min(text.scale, 241 / math.max(fw, 1))
    local width, height = fw * scale * 1.10 + 16, fh * scale * 1.10 + 14
    local widthFactor = math.min(1, self.w / 1280)
    local minX = math.max(130 * widthFactor, width / 2 + 9)
    local maxX = self.w - math.max(135 * widthFactor, width / 2 + 9)
    local minY, maxY = math.max(76, 54 + height / 2 + 24), self.h - 130
    local x, y = findTextPosition(self, clamp(text.x, minX, maxX), clamp(text.y, minY, maxY),
        minX, maxX, minY, width, height, reserved)
    if not x then return end
    local area = box(x - width / 2, y - height / 2 - 24, width, height + 25)
    area.textX, area.textY = x, y
    reserved[#reserved + 1] = area
    local lg = love.graphics
    local p = text.age / 1.45
    local pop = 0.69 + easeOutBack(clamp(text.age / 0.19, 0, 1)) * 0.31
    local alpha = clamp((1 - p) * 4, 0, 1)
    local s = scale * pop
    x, y = x - fw * s * 0.5, y - fh * s * 0.5 - p * 23
    lg.setFont(font)
    if text.crit then
        lg.setBlendMode("add", "alphamultiply")
        lg.setColor(1, 0.48, 0.13, 0.16 * alpha)
        for _, offset in ipairs(CRIT_GLOW_OFFSETS) do
            lg.print(value, x + offset[1], y + offset[2], 0, s, s)
        end
        lg.setBlendMode("alpha", "alphamultiply")
    end
    lg.setColor(0.025, 0.017, 0.06, alpha * 0.86)
    lg.print(value, x + 2, y + 5, 0, s, s)
    lg.setColor(16 / 255, 8 / 255, 24 / 255, alpha)
    for _, offset in ipairs(OUTLINE_RING_4PX) do
        lg.print(value, x + offset[1], y + offset[2], 0, s, s)
    end
    lg.setColor(text.color[1], text.color[2], text.color[3], alpha)
    lg.print(value, x, y, 0, s, s)
end

function BattleFX:drawFrontParticles(fonts, px, py, ex, ey)
    local lg = love.graphics
    local reserved, banner, face = sceneReservations(self, fonts)
    if px and py and ex and ey then layoutSpeech(self, px, py, ex, ey, fonts, reserved, banner, face) end
    lg.push("all")
    lg.setShader()
    lg.intersectScissor(0, 54, self.w, self.h - 140)
    if self.flashTimer > 0 then
        lg.setColor(1, 0.95, 0.79, self.flashTimer * 0.27)
        lg.rectangle("fill", 0, 54, self.w, self.h - 140)
    end
    drawParticles(self.particles)
    if self.activeCombo and Spectacles then
        Spectacles.drawComboBanner(self.activeCombo, fonts, self.w, bannerMaxWidth(self))
    end
    local font = fonts.damage or fonts.title or fonts.heading or fonts.body or lg.getFont()
    for i = #self.texts, 1, -1 do drawText(self, self.texts[i], font, reserved) end
    lg.pop()
end

local function addLight(self, out, x, y, radius, color, energy, halo, height)
    local index = self.lightsUsed + 1
    self.lightsUsed = index
    local entry = self.lightPool[index] or {}
    self.lightPool[index] = entry
    entry.x, entry.y, entry.radius = x, y, radius
    entry.r, entry.g, entry.b = color[1], color[2], color[3]
    entry.energy, entry.haloScale, entry.height = energy, halo, height
    out[#out + 1] = entry
end

function BattleFX:collectLights(out)
    out = out or {}
    self.lightsUsed = 0
    if self.activeCombo and Spectacles then
        local c = self.activeCombo
        local theme = Spectacles.COMBO_THEMES[c.kind]
        local strength = 0.88 * (1 - c.age / c.duration) + 0.16
        addLight(self, out, c.x, c.y - 45, 177, theme.primary, strength, 0.57, 100)
    end
    local s = self.summon
    if s and not s.persisted then
        local data = PARTICLES[s.result.particle_fx] or PARTICLES.sparkles
        addLight(self, out, s.x, s.y, 108, data[1], 0.45 + s.p * 0.43, 0.50, 55)
    end
    local banner, face, index = bannerBounds(self, self.fonts), faceBounds(self), 0
    for _, prop in ipairs(self.props) do
        local data = PARTICLES[prop.kind] or PARTICLES.sparkles
        local x, y = prop.x, prop.y
        if prop.anchor == "above_enemy" then
            index = index + 1
            x, y = weatherBounds(self, x, y, index, banner, face)
        end
        addLight(self, out, x, y, 65, data[1], 0.10 + math.sin(prop.age * 4) * 0.025, 0.15, 31)
    end
    local micro = 0
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        if p.data[8] then
            addLight(self, out, p.x, p.y, 24 + p.size, p.color, 0.11 * (1 - p.age / p.life), 0.09, 20)
            micro = micro + 1
            if micro == MAX_PARTICLE_LIGHTS then break end
        end
    end
    return out
end

return BattleFX
