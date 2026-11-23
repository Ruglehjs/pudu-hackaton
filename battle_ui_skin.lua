local Skin = {
    cream = { 1.00, 0.93, 0.77 },
    gold = { 0.93, 0.76, 0.45 },
    muted = { 0.84, 0.73, 0.59 },
    ink = { 0.24, 0.14, 0.08 },
}

function Skin.wood(g, x, y, w, h, alpha)
    alpha = alpha or 1
    g.setColor(0.10, 0.06, 0.035, 0.53 * alpha)
    g.rectangle("fill", x, y + 3, w, h, 10)
    g.setColor(0.21, 0.12, 0.075, alpha)
    g.rectangle("fill", x, y, w, h, 10)
    g.setColor(0.43, 0.26, 0.15, alpha)
    g.rectangle("fill", x + 2, y + 2, w - 4, h - 5, 8)
    g.setColor(0.33, 0.19, 0.115, alpha)
    g.rectangle("fill", x + 5, y + 5, w - 10, h - 10, 5)

    g.setColor(0.72, 0.49, 0.29, 0.68 * alpha)
    g.line(x + 11, y + 3, x + w - 11, y + 3)
    g.setColor(0.88, 0.65, 0.39, 0.14 * alpha)
    local grainCount = math.max(2, math.floor(h / 22))
    for i = 1, grainCount do
        local gy = y + 6 + (h - 12) * i / (grainCount + 1)
        g.line(x + w * 0.09, gy, x + w * 0.25, gy - 2, x + w * 0.41, gy + 1,
            x + w * 0.64, gy - 1, x + w * 0.83, gy - 2, x + w * 0.91, gy)
    end
    g.setColor(0.13, 0.07, 0.04, 0.65 * alpha)
    g.line(x + 10, y + h - 3, x + w - 10, y + h - 3)
    if w >= 52 and h >= 30 then
        local knotX = x + w * 0.76
        local knotY = y + h * 0.63
        g.setColor(0.19, 0.10, 0.05, 0.48 * alpha)
        g.ellipse("line", knotX, knotY, 8, 2, 12)
        g.line(knotX - 3, knotY, knotX + 4, knotY - 0.5)
    end
end

function Skin.paper(g, x, y, w, h, focused, alpha)
    alpha = alpha or 1
    if focused then
        g.setColor(0.92, 0.71, 0.36, alpha)
    else
        g.setColor(0.64, 0.44, 0.25, alpha)
    end
    g.rectangle("fill", x, y, w, h, 7)
    g.setColor(0.85, 0.70, 0.47, alpha)
    g.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 5)
    g.setColor(0.96, 0.85, 0.64, alpha)
    g.rectangle("fill", x + 4, y + 4, w - 8, h - 8, 4)
    g.setColor(0.57, 0.38, 0.19, 0.30 * alpha)
    g.line(x + 9, y + h - 7, x + w - 9, y + h - 7)
end

function Skin.pin(g, x, y, alpha)
    alpha = alpha or 1
    g.setColor(0.20, 0.11, 0.06, alpha)
    g.circle("fill", x, y + 1, 3)
    g.setColor(0.76, 0.53, 0.29, alpha)
    g.circle("fill", x, y, 2.2)
    g.setColor(1, 0.82, 0.50, alpha)
    g.points(x, y - 1)
end

function Skin.sprig(g, x, y, angle, scale, tint)
    g.push()
    g.translate(x, y)
    g.rotate(angle)
    g.scale(scale, scale)
    g.setColor(0.23, 0.29, 0.12)
    g.line(-1, 4, 8, -1, 17, -4, 27, -5)
    g.setColor(tint or { 0.52, 0.64, 0.28 })
    g.polygon("fill", 6, 0, 1, -5, 0, -11, 7, -7)
    g.polygon("fill", 11, -1, 15, 4, 22, 6, 18, 0)
    g.polygon("fill", 15, -3, 12, -10, 16, -16, 20, -10)
    g.polygon("fill", 20, -4, 24, -10, 32, -11, 28, -6)
    g.setColor(1, 0.92, 0.61, 0.39)
    g.line(6, 0, 2, -8)
    g.line(15, -3, 16, -12)
    g.line(20, -4, 29, -9)
    g.pop()
end

function Skin.spark(g, x, y, size, color)
    g.setColor(color or Skin.gold)
    g.polygon("fill", x - size * 0.5, y, x, y - size, x + size * 0.5, y, x, y + size)
    g.rectangle("fill", x - size * 0.8, y - 0.5, size * 1.6, 1)
end

return Skin
