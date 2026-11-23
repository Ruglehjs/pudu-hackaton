local g = love.graphics
local pi, tau = math.pi, 2 * math.pi
local sin, cos = math.sin, math.cos
local utf8 = require("utf8")

local Spectacles = {}

Spectacles.COMBO_THEMES = {
    combo_electro = {
        defaultName = "¡COMBO ELECTRO-CHARCO!", primary = {1, 0.86, 0.26}, accent = {0.20, 0.88, 1},
        shakeMag = 9.5, sfx1 = "sfx_combo_electro", sfx2 = "parry_clash",
        burst = {{"flash", 8, -44}, {"sparkles", 28, -40}}, trail = {"sparkles", 4, -30},
    },
    combo_deep_freeze = {
        defaultName = "¡COMBO HIELO TOTAL!", primary = {0.80, 0.98, 1}, accent = {0.27, 0.68, 1},
        shakeMag = 7.5, sfx1 = "sfx_combo_deep_freeze", sfx2 = "chime_3",
        burst = {{"snow", 24, -105}, {"sparkles", 14, -46}}, trail = {"snow", 4, -122},
    },
    combo_steam_sauna = {
        defaultName = "¡COMBO SAUNA EXTREMO!", primary = {1, 0.90, 0.72}, accent = {1, 0.48, 0.60},
        shakeMag = 7.0, sfx1 = "sfx_combo_steam_sauna", sfx2 = "water_rush",
        burst = {{"steam", 20, -20}, {"bubbles", 14, -25}}, trail = {"steam", 4, -12},
    },
    combo_slip_slide = {
        defaultName = "¡COMBO RESBALÓN TURBO!", primary = {1, 0.79, 0.24}, accent = {0.31, 0.94, 0.81},
        shakeMag = 7.2, sfx1 = "sfx_combo_slip_slide", sfx2 = "sfx_rimshot",
        burst = {{"wind", 20, -36}, {"stars", 10, -78}, {"bubbles", 12, -22}}, trail = {"wind", 4, -30},
    },
    combo_fire_boom = {
        defaultName = "¡COMBO SUPER-EXPLOSIÓN!", primary = {1, 0.66, 0.19}, accent = {1, 0.35, 0.22},
        shakeMag = 10.5, sfx1 = "sfx_combo_fire_boom", sfx2 = "rock_fall",
        burst = {{"explosion", 14, -38}, {"fire", 20, -28}, {"stars", 8, -72}}, trail = {"dust", 4, -30},
    },
    combo_chaos = {
        defaultName = "¡COMBO CAOS TOTAL!", primary = {0.87, 0.68, 1}, accent = {0.66, 0.41, 1},
        shakeMag = 9.0, sfx1 = "sfx_combo_chaos", sfx2 = "sfx_rimshot",
        burst = {{"confetti", 42, -100}, {"stars", 16, -65}, {"sparkles", 12, -44}}, trail = {"confetti", 5, -92},
    },
}

local comboAliases = {
    {"combo_electro", "electro", "rayo"},
    {"combo_deep_freeze", "freeze", "hielo"},
    {"combo_steam_sauna", "steam", "sauna", "vapor"},
    {"combo_slip_slide", "slip", "slide", "resbal"},
    {"combo_fire_boom", "fire", "boom", "explo"},
}

function Spectacles.normalizeComboType(comboType)
    local key = type(comboType) == "string" and comboType:lower() or ""
    if Spectacles.COMBO_THEMES[key] then return key end
    for _, aliases in ipairs(comboAliases) do
        for i = 2, #aliases do
            if key:find(aliases[i], 1, true) then return aliases[1] end
        end
    end
    return "combo_chaos"
end

local function themeFor(combo)
    return Spectacles.COMBO_THEMES[Spectacles.normalizeComboType(combo.kind)]
end

local function tint(color, alpha)
    g.setColor(color[1], color[2], color[3], alpha)
end

local function clamp01(value)
    return math.min(1, math.max(0, value))
end

local function smooth(value)
    local x = clamp01(value)
    return x * x * (3 - 2 * x)
end

local function easeOutBack(value)
    local x = clamp01(value) - 1
    return 1 + 2.70158 * x * x * x + 1.70158 * x * x
end

local function glint(x, y, width, height)
    g.polygon("fill", x - width, y, x, y - height, x + width, y, x, y + height)
end

local function starburst(x, y, outer, inner, points, angle)
    for index = 0, points - 1 do
        local outerAngle = angle + index * tau / points
        local left = outerAngle - pi / points
        local right = outerAngle + pi / points
        g.polygon("fill", x, y, x + cos(left) * inner, y + sin(left) * inner,
            x + cos(outerAngle) * outer, y + sin(outerAngle) * outer)
        g.polygon("fill", x, y, x + cos(outerAngle) * outer, y + sin(outerAngle) * outer,
            x + cos(right) * inner, y + sin(right) * inner)
    end
end

local function snowflake(x, y, radius, angle)
    for arm = 0, 5 do
        local direction = angle + arm * tau / 6
        local dx, dy = cos(direction), sin(direction)
        local tipX, tipY = x + dx * radius, y + dy * radius
        local splitX, splitY = x + dx * radius * 0.58, y + dy * radius * 0.58
        local fork = radius * 0.31
        g.line(x, y, tipX, tipY)
        g.line(splitX + cos(direction - pi / 3) * fork, splitY + sin(direction - pi / 3) * fork,
            splitX, splitY, splitX + cos(direction + pi / 3) * fork, splitY + sin(direction + pi / 3) * fork)
    end
end

local function orbitStars(x, y, count, age, radius, height, alpha)
    for i = 1, count do
        local a = age * 3.8 + i * tau / count
        local size = 8 + 2 * sin(a)
        g.setColor(0.27, 0.12, 0.09, alpha * 0.85)
        starburst(x + cos(a) * radius + 1, y + sin(a) * height + 2, size + 2, size * 0.52, 5, a)
        g.setColor(1, 0.83, 0.27, alpha)
        starburst(x + cos(a) * radius, y + sin(a) * height, size, size * 0.48, 5, a)
    end
end

local iceCorners = {{-72, -68}, {31, -84}, {71, -59}, {49, 70}}

local function drawFacetedIceCube(x, y, scale, age, alpha)
    g.push()
    g.translate(x, y)
    g.scale(scale, scale)
    g.setColor(0.19, 0.54, 0.83, 0.23 * alpha)
    g.polygon("fill", -72, -68, 31, -84, 71, -59, 71, 50, 49, 70, -48, 74, -72, 49)
    g.setColor(0.65, 0.96, 1, 0.32 * alpha)
    g.polygon("fill", -72, -68, 31, -84, 71, -59, -47, -49)
    g.setColor(0.37, 0.76, 1, 0.31 * alpha)
    g.polygon("fill", -72, -68, -47, -49, -48, 74, -72, 49)
    g.setColor(0.76, 0.98, 1, 0.17 * alpha)
    g.polygon("fill", -47, -49, 71, -59, 71, 50, 49, 70, -48, 74)
    g.setColor(0.38, 0.85, 1, 0.52 * alpha)
    g.polygon("fill", -48, 60, 71, 46, 71, 50, 49, 70, -48, 74)
    g.setLineWidth(2.4)
    g.setColor(0.70, 0.95, 1, 0.9 * alpha)
    g.polygon("line", -72, -68, 31, -84, 71, -59, 71, 50, 49, 70, -48, 74, -72, 49)
    g.line(-72, -68, -47, -49, 71, -59)
    g.line(-47, -49, -48, 74)
    g.setColor(1, 1, 1, 0.46 * alpha)
    g.line(-34, 22, 4, -21)
    g.line(-21, 19, 17, -24)
    g.line(25, 51, 49, 23)
    for index, corner in ipairs(iceCorners) do
        local size = 4 + 4 * (0.5 + 0.5 * sin(age * 8 + index * 2))
        g.setColor(0.90, 0.98, 1, alpha)
        glint(corner[1], corner[2], size, size * 1.5)
    end
    g.pop()
end

local function drawSurrenderFlag(x, y, age, alpha)
    g.setLineWidth(5)
    g.setColor(0.16, 0.09, 0.18, alpha)
    g.line(x - 2, y, x + 8, y - 77)
    g.setLineWidth(2)
    g.setColor(0.83, 0.70, 0.55, alpha)
    g.line(x - 2, y - 1, x + 8, y - 77)
    local top = {}
    for segment = 0, 5 do
        local u = segment / 5
        top[segment] = y - 75 + 3 * u + sin(u * 6 - age * 9) * 6 * u
    end
    for segment = 0, 4 do
        local left = x + 8 + segment * 9
        local a, b = top[segment], top[segment + 1]
        local shade = 0.91 + 0.08 * cos(segment - age * 9)
        g.setColor(shade, shade, 1, alpha)
        g.polygon("fill", left, a, left + 9, b, left + 7, b + 23, left - 2, a + 23)
        g.setColor(0.36, 0.29, 0.41, alpha * 0.78)
        g.line(left, a, left + 9, b)
        g.line(left - 2, a + 23, left + 7, b + 23)
    end
    g.line(x + 53, top[5], x + 51, top[5] + 23)
end

function Spectacles.spawnComboBurst(fx, kind, x, y)
    local theme = Spectacles.COMBO_THEMES[Spectacles.normalizeComboType(kind)]
    for _, burst in ipairs(theme.burst) do
        fx:spawnParticles(burst[1], x, y + burst[3], burst[2])
    end
end

function Spectacles.updateCombo(fx, combo, dt)
    if combo.age >= 1.55 then return end
    combo.trailClock = (combo.trailClock or 0) + dt
    if combo.trailClock >= 0.13 then
        combo.trailClock = combo.trailClock % 0.13
        local trail = themeFor(combo).trail
        fx:spawnParticles(trail[1], combo.x, combo.y + trail[3], trail[2])
    end
end

local function drawElectro(x, y, age, alpha)
    local pulse = 0.65 + 0.35 * (0.5 + 0.5 * cos(age * 30))
    local zig = cos(age * 32) * 9
    local main = {x - 172, -12, x - 124 + zig, y * 0.30, x - 143, y * 0.50,
        x - 48 - zig, y * 0.68, x - 65, y - 44, x - 9, y - 24, x, y + 12}
    local leftBranch = {main[5], main[6], x - 178, y * 0.59, x - 153, y - 71}
    local rightBranch = {main[7], main[8], x - 20, y * 0.75, x - 38, y - 55}
    local body = {x - 45, y - 53, x - 66, y - 84, x - 45 + zig, y - 132,
        x - 10, y - 122, x + 31, y - 131, x + 55, y - 89, x + 36 - zig, y - 50}
    g.setBlendMode("add")
    g.setColor(0.14, 0.74, 1, alpha * pulse * 0.59)
    g.setLineWidth(14)
    g.line(main)
    g.setLineWidth(8)
    g.line(leftBranch)
    g.line(rightBranch)
    g.setLineWidth(4)
    g.line(body)
    g.ellipse("line", x, y + 11, 50 + sin(age * 13) * 15, 12)
    g.setBlendMode("alpha")
    g.setColor(1, 0.84, 0.20, alpha * pulse)
    g.setLineWidth(6.5)
    g.line(main)
    g.setLineWidth(3.5)
    g.line(leftBranch)
    g.line(rightBranch)
    g.setColor(1, 1, 0.88, alpha * pulse)
    g.setLineWidth(2.4)
    g.line(main)
    g.setLineWidth(1.2)
    g.line(leftBranch)
    g.line(rightBranch)
end

local function drawFreeze(x, y, age, alpha)
    drawFacetedIceCube(x, y - 55, 0.61 + 0.39 * easeOutBack(age / 0.36), age, alpha)
    g.setColor(0.83, 0.98, 1, 0.88 * alpha)
    g.setLineWidth(1.6)
    for i = 1, 6 do
        local a = age * 1.7 + i * tau / 6
        snowflake(x + cos(a) * 81, y - 56 + sin(a) * 65, 7 + 2 * sin(a), a)
    end
end

local function drawSauna(x, y, age, alpha)
    for i = 1, 9 do
        local rise = (age * 1.2 + i / 9) % 1
        local opacity = alpha * (0.52 * sin(pi * rise))
        local px = x + sin(i * 2.36 + age * 2.2) * (28 + rise * 26)
        local py = y - 112 * rise
        local size = 15 + 16 * rise
        g.setColor(0.92, 0.48, 0.57, opacity * 0.73)
        g.ellipse("fill", px, py + 7, size * 1.31, size * 0.73)
        g.setColor(1, 0.83, 0.77, opacity)
        g.ellipse("fill", px, py, size * 1.22, size * 0.66)
        g.setColor(1, 0.96, 0.87, opacity * 0.84)
        g.ellipse("fill", px - size * 0.34, py - 5, size * 0.79, size * 0.52)
    end
    g.setBlendMode("add")
    g.setLineWidth(2)
    for i = 1, 4 do
        local rise = (age * 1.43 + i / 4) % 1
        g.setColor(1, 0.60, 0.32, 0.57 * sin(pi * rise) * alpha)
        g.ellipse("line", x, y - rise * 99, 27 + rise * 57, 9 + 7 * rise)
    end
end

local function drawSlide(x, y, age, alpha)
    for i = 1, 6 do
        local points = {}
        local radius = 37 + i * 7
        local phase = age * 13 + i * 0.63
        for step = 0, 16 do
            local u = step / 16
            local a = phase + u * pi * 1.55
            points[#points + 1] = x + cos(a) * radius * (0.79 + u * 0.21)
            points[#points + 1] = y - i * 15 + sin(a) * (12 + i) - u * 15
        end
        g.setLineWidth(5)
        g.setColor(0.11, 0.43, 0.44, 0.57 * alpha)
        g.line(points)
        g.setLineWidth(2)
        g.setColor(0.50 + i * 0.08, 0.97, 0.82 - i * 0.08, 0.77 * alpha)
        g.line(points)
    end
    orbitStars(x, y - 138, 5, age * 1.5, 49, 12, alpha)
end

local function drawFireBoom(x, y, age, alpha)
    local energy = 1 - smooth(age / 0.85)
    local radius = 28 + 94 * smooth(age / 0.47)
    local cy = y - 47
    if energy > 0 then
        g.setColor(0.93, 0.27, 0.08, energy * alpha)
        starburst(x, cy, radius, radius * 0.57, 14, age * 0.7)
        g.setColor(1, 0.78, 0.23, energy * alpha)
        starburst(x, cy, radius * 0.71, radius * 0.36, 14, age * 0.7)
        g.setBlendMode("add")
        g.setLineWidth(4)
        g.setColor(1, 0.66, 0.21, energy * alpha * 0.86)
        g.ellipse("line", x, cy, radius + 15, (radius + 15) * 0.67)
        g.setBlendMode("alpha")
    end
    g.setLineWidth(8)
    for i = 1, 4 do
        local rise = (age * 0.67 + i * 0.22) % 1
        g.setColor(0.23, 0.14, 0.19, 0.52 * alpha * sin(pi * rise))
        local px = x + cos(i * 2.38 + age * 2) * 26
        g.ellipse("line", px, y - 25 - 108 * rise, 18 + rise * 37, 6 + rise * 13)
    end
end

local rainbow = {
    {1, 0.26, 0.44}, {1, 0.57, 0.23}, {1, 0.84, 0.28},
    {0.32, 1, 0.53}, {0.30, 0.79, 1}, {0.74, 0.38, 1},
}

local function drawChaos(x, y, age, alpha)
    local cy = y - 56
    local pulse = 0.83 + 0.17 * sin(age * 12)
    g.setBlendMode("add")
    for i = 1, 12 do
        local a = i * tau / 12 + age * 3
        local inner, outer = 17, (66 + 31 * (i % 2)) * pulse
        tint(rainbow[(i - 1) % #rainbow + 1], alpha * 0.57)
        g.polygon("fill", x + cos(a) * inner, cy + sin(a) * inner,
            x + cos(a - 0.08) * outer, cy + sin(a - 0.08) * outer,
            x + cos(a + 0.08) * outer, cy + sin(a + 0.08) * outer)
    end
    g.setLineWidth(2.5)
    for i = 1, 2 do
        local points = {}
        local spin = age * (i == 1 and 2.5 or -2.5)
        for corner = 0, 7 do
            local a = spin + corner * tau / 8
            points[#points + 1] = x + cos(a) * (53 + i * 15)
            points[#points + 1] = cy + sin(a) * (43 + i * 12)
        end
        g.setColor(0.55 + 0.2 * i, 0.77, 1, alpha * 0.74)
        g.polygon("line", points)
    end
end

local comboDraw = {
    combo_electro = drawElectro,
    combo_deep_freeze = drawFreeze,
    combo_steam_sauna = drawSauna,
    combo_slip_slide = drawSlide,
    combo_fire_boom = drawFireBoom,
    combo_chaos = drawChaos,
}

function Spectacles.drawComboSpectacle(combo, time)
    if not combo then return end
    local age = combo.age or time or 0
    local alpha = 1 - smooth((age - 1.40) / ((combo.duration or 2.2) - 1.40))
    if alpha <= 0 then return end
    g.push("all")
    g.setBlendMode("alpha")
    comboDraw[Spectacles.normalizeComboType(combo.kind)](combo.x, combo.y, age, alpha)
    g.pop()
end

local function bannerLayout(combo, fonts, sw, maxWidth)
    local theme = themeFor(combo)
    local font = fonts and (fonts.combo or fonts.title or fonts.heading) or g.getFont()
    local text = combo.name
    if not text or text == "" or text == "none" then text = theme.defaultName end
    text = text:gsub("%s+", " ")
    if not font:hasGlyphs(text) then
        text = text:gsub(utf8.charpattern, function(char)
            return font:hasGlyphs(char) and char or "?"
        end)
    end
    local width = font:getWidth(text)
    local allowed = math.min(540, sw - 260, maxWidth or math.huge)
    local scale = math.min(1.42, math.max(1, allowed - 92) / math.max(width, 1), 30 / font:getHeight())
    local half = width * scale / 2 + 24
    return font, text, scale, half
end

function Spectacles.getComboBannerBounds(combo, fonts, sw, maxWidth)
    sw = sw or g.getWidth()
    local _, _, _, half = bannerLayout(combo, fonts, sw, maxWidth)
    return sw * 0.5 - half - 22, 80, half * 2 + 44, 60
end

local function ribbon(mode, cx, cy, half)
    g.polygon(mode, cx - half - 14, cy - 23, cx + half + 2, cy - 23,
        cx + half + 14, cy + 23, cx - half - 2, cy + 23)
end

function Spectacles.drawComboBanner(combo, fonts, outlineRing4px, critGlowOffsets, sw, maxWidth)
    if not combo then return end
    local age = combo.age or 0
    local alpha = 1 - smooth((age - 1.64) / ((combo.duration or 2.2) - 1.64))
    if alpha <= 0 then return end
    sw = sw or g.getWidth()
    local font, text, scale, half = bannerLayout(combo, fonts, sw, maxWidth)
    local theme = themeFor(combo)
    local cx, cy = sw * 0.5, 108
    local tx = cx - font:getWidth(text) * scale * 0.5
    local ty = cy - font:getHeight() * scale * 0.5

    g.push("all")
    g.setBlendMode("alpha")
    g.setFont(font)
    g.setColor(0.05, 0.025, 0.08, 0.66 * alpha)
    ribbon("fill", cx + 4, cy + 7, half)
    g.setColor(0.063, 0.031, 0.094, 0.96 * alpha)
    ribbon("fill", cx, cy, half)
    g.setLineWidth(6)
    ribbon("line", cx, cy, half)
    tint(theme.accent, alpha)
    g.setLineWidth(2)
    ribbon("line", cx, cy, half)
    tint(theme.accent, alpha * 0.24)
    g.line(cx - half - 3, cy - 17, cx + half - 4, cy - 17)
    g.line(cx - half + 4, cy + 17, cx + half + 3, cy + 17)

    if critGlowOffsets then
        g.setBlendMode("add")
        tint(theme.accent, alpha * 0.06)
        for _, offset in ipairs(critGlowOffsets) do
            g.print(text, tx + offset[1], ty + offset[2], 0, scale, scale)
        end
        g.setBlendMode("alpha")
    end
    g.setColor(0.063, 0.031, 0.094, alpha)
    for _, offset in ipairs(outlineRing4px or {}) do
        g.print(text, tx + offset[1], ty + offset[2], 0, scale, scale)
    end
    tint(theme.primary, alpha)
    g.print(text, tx, ty, 0, scale, scale)
    local glintSize = 7 + sin(age * 12) * 2
    glint(cx - half + 6, cy, glintSize, glintSize * 1.55)
    glint(cx + half - 6, cy, glintSize, glintSize * 1.55)
    g.pop()
end

local finaleKind = {
    crying = "crying", sad = "crying",
    scared = "scared", chased = "scared", panicked = "scared",
    frozen = "frozen",
    happy_pacified = "pacified", pacified = "pacified",
}

local finaleBursts = {
    crying = {{"tears", 12, -91}},
    scared = {{"dust", 24, -12}, {"sweat", 5, -86}},
    frozen = {{"snow", 18, -117}, {"sparkles", 10, -64}},
    pacified = {{"hearts", 12, -80}, {"sparkles", 12, -72}},
    knockout = {{"stars", 16, -118}},
}

local finaleTrails = {
    crying = {"tears", 4, -87, 0.16},
    frozen = {"snow", 3, -123, 0.29},
    pacified = {"hearts", 3, -70, 0.33},
}

function Spectacles.spawnFinaleBurst(fx, reaction, x, y)
    for _, burst in ipairs(finaleBursts[finaleKind[reaction] or "knockout"]) do
        fx:spawnParticles(burst[1], x, y + burst[3], burst[2])
    end
end

function Spectacles.updateFinale(fx, finale, dt)
    local trail = finaleTrails[finaleKind[finale.reaction]]
    if not trail then return end
    finale.trailClock = (finale.trailClock or 0) + dt
    if finale.trailClock >= trail[4] then
        finale.trailClock = finale.trailClock % trail[4]
        local transform = Spectacles.computeDefeatTransform(finale)
        fx:spawnParticles(trail[1], finale.x + transform.dx, finale.y + transform.dy + trail[3], trail[2])
    end
end

function Spectacles.computeDefeatTransform(finale)
    local transform = {dx = 0, dy = 0, rot = 0, scaleX = 1, scaleY = 1, alpha = 1, flashWhite = 0}
    if not finale then return transform end
    local age = finale.age
    local kind = finaleKind[finale.reaction]
    if kind == "crying" then
        local slump = smooth(age / 0.32)
        transform.dx = sin(age * 32) * 2.6 * slump
        transform.dy = 6 * slump
        transform.scaleX, transform.scaleY = 1 + 0.06 * slump, 1 - 0.12 * slump
    elseif kind == "scared" then
        if age < 0.14 then
            local recoil = sin(age / 0.14 * pi)
            transform.dy = -17 * recoil
            transform.scaleX, transform.scaleY = 1 - 0.20 * recoil, 1 + 0.18 * recoil
            transform.flashWhite = recoil * 0.62
        else
            local flight = clamp01((age - 0.14) / 0.73)
            transform.dx = 460 * flight ^ 1.33
            transform.dy = -math.abs(sin(flight * 3.5 * pi)) * 31 * (1 - 0.38 * flight)
            transform.rot = 0.25 * smooth(flight / 0.27)
            transform.alpha = 1 - smooth((flight - 0.55) / 0.45)
        end
    elseif kind == "frozen" then
        local shiver = 1 - smooth(age / 0.22)
        transform.dx = sin(age * 90) * 5 * shiver
        transform.flashWhite = shiver * 0.62
    elseif kind == "pacified" then
        transform.dy = -math.abs(sin(age * 7)) * 10
        transform.rot = sin(age * 7) * 0.065
    else
        local fall = easeOutBack(age / 0.48)
        transform.rot, transform.dx, transform.dy = 0.24 * fall, 10 * fall, 6 * fall
        transform.flashWhite = (1 - smooth(age / 0.09)) * 0.40
    end
    return transform
end

function Spectacles.drawDefeatBackLayer(finale)
    if not finale or finaleKind[finale.reaction] ~= "crying" then return end
    local x, y, age = finale.x, finale.y + 9, finale.age
    local puddle = smooth(age / 1.75)
    local rx, ry = 22 + 54 * puddle, 7 + 16 * puddle
    local wave = (age * 1.8) % 1
    g.push("all")
    g.setBlendMode("alpha")
    g.setColor(0.14, 0.38, 0.64, 0.86)
    g.ellipse("fill", x, y, rx, ry)
    g.setColor(0.33, 0.67, 0.87, 0.81)
    g.ellipse("fill", x, y - 3, rx * 0.94, ry * 0.86)
    g.setColor(0.79, 0.98, 1, 0.66)
    g.ellipse("fill", x - rx * 0.28, y + ry * 0.30, rx * 0.22, 2.1)
    g.setLineWidth(1.5)
    g.setColor(0.85, 0.97, 1, (1 - wave) * 0.66)
    g.ellipse("line", x, y, rx * (0.15 + 0.83 * wave), ry * (0.20 + 0.76 * wave))
    g.pop()
end

local function drawSpinningDustCloud(x, y, age)
    local alpha = smooth((age - 0.12) / 0.12) * (1 - smooth((age - 0.74) / 0.69))
    if alpha <= 0 then return end
    local swell = smooth((age - 0.12) / 0.33)
    for i = 1, 7 do
        local a = i * tau / 7 + age * 13
        local px, py = x + cos(a) * 37 * swell, y + sin(a) * 18 * swell
        local size = (18 + 7 * sin(a + 1)) * swell
        g.setColor(0.43, 0.30, 0.27, alpha * 0.59)
        g.ellipse("fill", px, py + 3, size * 1.32, size * 0.91)
        g.setColor(0.95, 0.84, 0.67, alpha * 0.85)
        g.ellipse("fill", px, py, size * 1.24, size * 0.83)
    end
    g.setLineWidth(2)
    g.setColor(0.62, 0.46, 0.36, alpha * 0.84)
    for i = 1, 2 do
        local points = {}
        for j = 0, 15 do
            local a = j * 0.41 + age * 13 + i * pi
            local radius = (j + 2) * 0.95 * swell
            points[#points + 1] = x + (i * 2 - 3) * 14 + cos(a) * radius
            points[#points + 1] = y + sin(a) * radius * 0.60
        end
        g.line(points)
    end
    g.setColor(1, 0.92, 0.77, alpha * 0.88)
    for i = 1, 5 do
        local xStart = x + 38 + (i * 13 + age * 129) % 52
        g.line(xStart, y - 26 + i * 7, xStart + 24 + i * 3, y - 26 + i * 7)
    end
end

local function drawHeart(x, y, size)
    g.circle("fill", x - 0.42 * size, y - 0.20 * size, size * 0.55)
    g.circle("fill", x + 0.42 * size, y - 0.20 * size, size * 0.55)
    g.polygon("fill", x - 0.91 * size, y + 0.01 * size, x + 0.91 * size, y + 0.01 * size, x, y + size)
end

function Spectacles.drawDefeatFinaleOverlay(finale)
    if not finale then return end
    local x, y, age = finale.x, finale.y, finale.age
    local kind = finaleKind[finale.reaction]
    g.push("all")
    g.setBlendMode("alpha")
    if kind == "crying" then
        drawSurrenderFlag(x + 64, y + 2, age, smooth(age / 0.34))
    elseif kind == "scared" then
        drawSpinningDustCloud(x, y - 24, age)
    elseif kind == "frozen" then
        local alpha = smooth(age / 0.25)
        drawFacetedIceCube(x, y - 74, 0.60 + 0.40 * easeOutBack(age / 0.31), age, alpha)
        g.setColor(0.85, 0.98, 1, 0.85 * alpha)
        g.setLineWidth(1.3)
        for i = 1, 4 do
            local a = i * tau / 4 + age * 1.05
            snowflake(x + cos(a) * 76, y - 68 + sin(a) * 67, 5 + 2 * sin(age * 4 + i), a)
        end
    elseif kind == "pacified" then
        local alpha = smooth(age / 0.22)
        local cy = y - 73 + Spectacles.computeDefeatTransform(finale).dy
        for i = 1, 4 do
            local a = age * 2.6 + i * pi * 0.5
            local px, py = x + cos(a) * 63, cy + sin(a) * 43
            local size = 8 + 2.5 * sin(a)
            g.setColor(0.47, 0.08, 0.25, alpha)
            drawHeart(px, py + 2, size + 1.5)
            g.setColor(1, 0.41, 0.65, alpha)
            drawHeart(px, py, size)
            g.setColor(1, 0.80, 0.91, alpha)
            g.circle("fill", px - size * 0.46, py - size * 0.38, size * 0.14)
        end
        g.setBlendMode("add")
        for i = 1, 3 do
            local a = i * tau / 3 - age * 1.66
            g.setColor(1, 0.70, 0.24, alpha * 0.85)
            glint(x + cos(a) * 78, cy + sin(a) * 54, 5, 8)
        end
    else
        local alpha = smooth(age / 0.33)
        orbitStars(x + 14, y - 168, 4, age, 47, 11, alpha)
        drawSurrenderFlag(x + 66, y + 2, age, alpha)
    end
    g.pop()
end

return Spectacles
