local AssetLoader = require("asset_loader")
local Skin = require("battle_ui_skin")

local AdventureScreen = {}
AdventureScreen.__index = AdventureScreen

local g = love.graphics
local ROOT = "assets/ui/cinematics/"
local WIDTH, HEIGHT = 1280, 720
local BUTTONS = {
    title = { x = 244, y = 420, w = 230, h = 62, label = "Jugar" },
    intro = { x = 1076, y = 646, w = 176, h = 46, label = "Saltar  [Esc]" },
    ending = { x = 1076, y = 646, w = 176, h = 46, label = "Saltar  [Esc]" },
    complete = { x = 490, y = 642, w = 300, h = 56, label = "Volver a jugar" },
}

local function viewport(w, h)
    local scale = math.min(w / WIDTH, h / HEIGHT)
    return (w - WIDTH * scale) / 2, (h - HEIGHT * scale) / 2, scale
end

local function contains(button, x, y)
    return x >= button.x and x <= button.x + button.w
        and y >= button.y and y <= button.y + button.h
end

local function drawFit(image)
    local w, h = image:getDimensions()
    local scale = math.min(WIDTH / w, HEIGHT / h)
    g.setColor(1, 1, 1, 1)
    g.draw(image, (WIDTH - w * scale) / 2, (HEIGHT - h * scale) / 2, 0, scale, scale)
end

local function drawButton(button, font, hovered)
    local x, y, w, h = button.x, button.y, button.w, button.h
    Skin.wood(g, x, y, w, h)
    g.setColor(0.89, 0.69, 0.39, hovered and 0.95 or 0.48)
    g.rectangle("line", x + 3.5, y + 3.5, w - 7, h - 7, 6)
    Skin.pin(g, x + 15, y + h / 2)
    Skin.pin(g, x + w - 15, y + h / 2)
    g.setFont(font)
    g.setColor(Skin.cream)
    g.printf(button.label, x, math.floor(y + (h - font:getHeight()) / 2), w, "center")
end

function AdventureScreen.new(fonts)
    return setmetatable({
        fonts = fonts,
        titleArt = AssetLoader.loadImageRaw(ROOT .. "title.png"),
        endingArt = AssetLoader.loadImageRaw(ROOT .. "ending_still.jpg"),
    }, AdventureScreen)
end

function AdventureScreen:play(kind, muted)
    self:stop()
    local ok, video = pcall(function()
        -- Enable the decoder only when a cinematic begins.
        require("love.video")
        return g.newVideo(ROOT .. kind .. ".ogv", { audio = kind == "intro" })
    end)
    if not ok then
        io.stderr:write(("[PUDU FANTASY WARN] Cinemática %s: %s\n"):format(kind, video))
        return false
    end
    self.video = video
    self:setMuted(muted)
    video:play()
    return true
end

function AdventureScreen:setMuted(muted)
    local source = self.video and self.video:getSource()
    if source then source:setVolume(muted and 0 or 1) end
end

function AdventureScreen:isPlaying()
    return self.video and self.video:isPlaying()
end

function AdventureScreen:stop()
    if self.video then
        self.video:pause()
        self.video:release()
        self.video = nil
    end
end

function AdventureScreen:hitTest(screen, x, y, w, h)
    local left, top, scale = viewport(w, h)
    return contains(BUTTONS[screen], (x - left) / scale, (y - top) / scale)
end

function AdventureScreen:draw(screen, w, h, mx, my)
    local left, top, scale = viewport(w, h)
    g.clear(0.035, 0.046, 0.029, 1)
    g.push()
    g.translate(left, top)
    g.scale(scale)

    local image = self.video
    if screen == "title" then image = self.titleArt or self.endingArt end
    if screen == "complete" then image = self.endingArt end
    if image then drawFit(image) end
    local heading = self.fonts.victoryTitle or self.fonts.versus
    if screen == "title" and not self.titleArt then
        Skin.wood(g, 88, 152, 542, 104)
        g.setFont(heading)
        g.setColor(Skin.gold)
        g.printf("Puduprompter", 88, 163, 542, "center")
    elseif screen == "complete" then
        Skin.wood(g, 324, 43, 632, 102)
        g.setFont(heading)
        g.setColor(Skin.cream)
        g.printf("¡Aventura completada!", 324, 52, 632, "center")
    end

    local font = self.fonts.story or self.fonts.heading
    drawButton(BUTTONS[screen], font, self:hitTest(screen, mx, my, w, h))
    g.pop()
end

local function portalOctagon(radiusX, radiusY)
    g.polygon("fill",
        -radiusX * 0.45, -radiusY, radiusX * 0.45, -radiusY,
        radiusX, -radiusY * 0.48, radiusX, radiusY * 0.48,
        radiusX * 0.45, radiusY, -radiusX * 0.45, radiusY,
        -radiusX, radiusY * 0.48, -radiusX, -radiusY * 0.48)
end

function AdventureScreen.drawPortal(x, groundY, height, progress)
    local opening = math.min(1, progress / 0.23)
    if opening <= 0 then return end
    g.push()
    g.translate(x, groundY - height * 0.5 * opening)
    g.scale(height / 144 * opening)
    g.setColor(0.04, 0.17, 0.15, 0.52)
    g.ellipse("fill", 0, 69, 53, 13)
    g.setColor(0.17, 0.27, 0.29)
    portalOctagon(42, 72)
    g.setColor(0.24, 0.68, 0.59)
    portalOctagon(36, 67)
    g.setColor(0.75, 1, 0.80)
    portalOctagon(31, 61)
    g.setColor(0.28, 0.64, 0.60)
    portalOctagon(27, 57)
    g.setColor(0.07, 0.21, 0.28)
    portalOctagon(22, 51)

    for i = 1, 12 do
        local angle = i * 2.40 - progress * 10
        local orbit = i / 12
        local px = math.floor(math.cos(angle) * 19 * orbit / 3) * 3
        local py = math.floor(math.sin(angle) * 46 * orbit / 3) * 3
        local size = 2 + i % 3
        g.setColor(0.47, 0.90, 0.76, 0.38 + 0.46 * orbit)
        g.rectangle("fill", px, py, size, size)
    end
    for i = 1, 10 do
        local angle = i * 2.40 + progress * 6
        local px = math.floor(math.cos(angle) * (43 + i % 3 * 7) / 3) * 3
        local py = math.floor(math.sin(angle) * (68 + i % 3 * 6) / 3) * 3
        local size = 2 + i % 4
        g.setColor(0.82, 0.95, 0.64, 0.45 + 0.4 * math.sin(angle) ^ 2)
        g.rectangle("fill", px, py, size, size)
    end
    g.pop()
end

return AdventureScreen
