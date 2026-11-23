-- Victory records and the nine-card rematch gallery.
local AssetLoader = require("asset_loader")
local utf8 = require("utf8")

local VictoryAlbum = {}
VictoryAlbum.__index = VictoryAlbum

local FILENAME = "victory_album.json"
local MAX_INTEGER = 9007199254740991
local GOLD = { 1, 0.85, 0.53 }
local BIOMES = {
    bosque = { name = "Bosque", color = { 0.65, 0.92, 0.65 }, background = { 0.15, 0.40, 0.31 } },
    desierto = { name = "Desierto", color = { 1, 0.82, 0.59 }, background = { 0.47, 0.32, 0.21 } },
    costa = { name = "Costa", color = { 0.57, 0.92, 0.99 }, background = { 0.14, 0.37, 0.53 } },
    chiloe = { name = "Chiloé", color = { 0.52, 0.90, 0.84 }, background = { 0.18, 0.36, 0.40 } },
    ciudad = { name = "Ciudad", color = { 0.86, 0.77, 1 }, background = { 0.33, 0.29, 0.49 } },
}

local function stringValue(value)
    return type(value) == "string" and utf8.len(value) and value or ""
end

local function integer(value, minimum)
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) == math.huge then return minimum end
    return math.max(minimum, math.min(MAX_INTEGER, math.floor(number)))
end

local function normalizeEntry(entry)
    return {
        prompt = stringValue(entry.prompt),
        summonName = stringValue(entry.summonName),
        comboName = stringValue(entry.comboName),
        isCritical = entry.isCritical == true,
        narrator = stringValue(entry.narrator),
        reaction = stringValue(entry.reaction),
        turns = integer(entry.turns, 0),
        timestamp = integer(entry.timestamp, 0),
        count = integer(entry.count, 1),
    }
end

local function readExternal(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local raw = file:read("*a")
    file:close()
    return raw
end

local function writeExternal(path, raw)
    local file = io.open(path, "wb")
    if not file then return false end
    local written = file:write(raw)
    local closed = file:close()
    return written and closed
end

local function decodeSave(json, reader, path)
    local read, raw = pcall(reader, path)
    if not read or type(raw) ~= "string" then return nil end
    local decoded, data = pcall(json.decode, raw)
    if decoded and type(data) == "table" and type(data.entries) == "table" then return data end
end

function VictoryAlbum.new(jsonMod, inMemory)
    if inMemory then
        return setmetatable({ entries = {}, open = false, inMemory = true }, VictoryAlbum)
    end
    local json = jsonMod or require("json")
    local path = AssetLoader.getExternalBaseDir() .. "/" .. FILENAME
    local data = decodeSave(json, readExternal, path)
    local saved = decodeSave(json, love.filesystem.read, FILENAME)
    -- Prefer the newest copy if only one location was writable on the previous run.
    if saved and (not data or integer(saved.revision, 0) > integer(data.revision, 0)) then
        data = saved
    end
    if path ~= "./" .. FILENAME then
        local relative = decodeSave(json, readExternal, FILENAME)
        if relative and (not data or integer(relative.revision, 0) > integer(data.revision, 0)) then
            data = relative
        end
    end

    local self = setmetatable({
        json = json, entries = {}, open = false, path = path,
        revision = data and integer(data.revision, 0) or 0,
    }, VictoryAlbum)
    if data then
        for id, entry in pairs(data.entries) do
            if type(id) == "string" and id ~= "" and type(entry) == "table" then
                self.entries[id] = normalizeEntry(entry)
            end
        end
    end
    return self
end

function VictoryAlbum:save()
    if self.inMemory then return true end
    self.revision = math.min(MAX_INTEGER, math.max(os.time(), self.revision + 1))
    local entries = self.json.object and self.json.object(self.entries) or self.entries
    local raw = self.json.encode({ version = 1, revision = self.revision, entries = entries }) .. "\n"
    local okSave, saved = pcall(love.filesystem.write, FILENAME, raw)
    local okExternal, external = pcall(writeExternal, self.path, raw)
    if (okSave and saved) or (okExternal and external) then return true end
    if self.path ~= "./" .. FILENAME then
        local okRelative, relative = pcall(writeExternal, FILENAME, raw)
        return okRelative and not not relative
    end
    return false
end

function VictoryAlbum:recordVictory(encId, entry)
    if type(encId) ~= "string" or encId == "" or type(entry) ~= "table" then return false end
    local record = normalizeEntry(entry)
    local previous = self.entries[encId]
    record.count = previous and math.min(MAX_INTEGER, previous.count + 1) or 1
    record.timestamp = record.timestamp > 0 and record.timestamp or os.time()
    self.entries[encId] = record
    return self:save()
end

function VictoryAlbum:getEntry(encId)
    return self.entries[encId]
end

function VictoryAlbum:countUnlocked(encountersList)
    local count = 0
    if encountersList then
        for _, encounter in ipairs(encountersList) do
            if self.entries[encounter.id] then count = count + 1 end
        end
    else
        for _ in pairs(self.entries) do count = count + 1 end
    end
    return count
end

function VictoryAlbum:clear()
    self.entries = {}
    return self:save()
end

function VictoryAlbum:toggle()
    self.open = not self.open
    return self.open
end

function VictoryAlbum:isOpen()
    return self.open
end

function VictoryAlbum:close()
    self.open = false
end

local function contains(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

local function layout(w, h)
    if not w or not h then w, h = love.graphics.getDimensions() end
    local mw = math.min(w - 12, math.max(860, math.min(w - 80, 1100)))
    local mh = math.min(h - 12, math.max(476, math.min(h - 68, 636)))
    local x, y = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
    local gap, pad = 12, 24
    local cardW, cardH = math.floor((mw - 2 * pad - 2 * gap) / 3), math.floor((mh - 118 - 2 * gap) / 3)
    local cards = {}
    for i = 1, 9 do
        cards[i] = {
            x = x + pad + ((i - 1) % 3) * (cardW + gap),
            y = y + 71 + math.floor((i - 1) / 3) * (cardH + gap),
            w = cardW, h = cardH,
        }
    end
    return {
        modal = { x = x, y = y, w = mw, h = mh }, cards = cards,
        close = { x = x + mw - 66, y = y + 21, w = 42, h = 29 },
        clear = { x = x + mw - 152, y = y + 21, w = 76, h = 29 },
    }
end

function VictoryAlbum:containsPoint(mx, my, w, h)
    return self.open and contains(layout(w, h).modal, mx, my)
end

function VictoryAlbum:hitTest(mx, my, w, h)
    if not self.open then return nil end
    local ui = layout(w, h)
    if contains(ui.close, mx, my) then return "close" end
    if contains(ui.clear, mx, my) then return "clear" end
    for i, card in ipairs(ui.cards) do
        if contains(card, mx, my) then return "card", i end
    end
end

local function displayText(font, text)
    text = text:gsub("[%z\1-\31\127]", " "):gsub("%s+", " ")
    if font:hasGlyphs(text) then return text end
    return (text:gsub(utf8.charpattern, function(char)
        return font:hasGlyphs(char) and char or "?"
    end))
end

local function truncateText(font, text, maxW, forceEllipsis)
    if not forceEllipsis and font:getWidth(text) <= maxW then return text end
    local cut = #text + 1
    while cut > 1 and font:getWidth(text:sub(1, cut - 1) .. "...") > maxW do
        cut = utf8.offset(text, -1, cut)
    end
    return font:getWidth("...") <= maxW and text:sub(1, cut - 1) .. "..." or ""
end

local function frame(mode, box, radius)
    love.graphics.rectangle(mode, box.x, box.y, box.w, box.h, radius, radius)
end

local function drawFFWindow(box)
    local g = love.graphics
    local x, y, w, h = box.x, box.y, box.w, box.h
    g.setColor(0, 0, 0, 0.64)
    g.rectangle("fill", x - 4, y + 6, w + 8, h + 4, 10, 10)
    g.setColor(0.025, 0.035, 0.10)
    frame("fill", box, 8)
    local bandH = (h - 12) / 6
    for i = 0, 5 do
        g.setColor(0.115 - i * 0.011, 0.26 - i * 0.034, 0.59 - i * 0.06)
        g.rectangle("fill", x + 6, y + 6 + i * bandH, w - 12, bandH)
    end
    g.setColor(0.85, 0.86, 0.96)
    g.rectangle("line", x + 2, y + 2, w - 4, h - 4, 7, 7)
    g.setColor(0.52, 0.47, 0.40)
    g.rectangle("line", x + 5, y + 5, w - 10, h - 10, 4, 4)
    g.setColor(GOLD)
    for _, xx in ipairs({ x + 10, x + w - 10 }) do
        for _, yy in ipairs({ y + 10, y + h - 10 }) do
            g.circle("fill", xx, yy, 2.4)
        end
    end
end

local function drawButton(box, label, hovered, font)
    local g = love.graphics
    g.setColor(0.08, 0.13, 0.32, 0.95)
    frame("fill", box, 4)
    if hovered then g.setColor(GOLD) else g.setColor(0.61, 0.69, 0.88) end
    frame("line", box, 4)
    g.setFont(font)
    g.printf(label, box.x, box.y + math.floor((box.h - font:getHeight()) / 2), box.w, "center")
end

local function drawPortrait(enc, sprite, x, y, size, locked, fonts, slot, biome)
    local g = love.graphics
    g.setColor(biome.background)
    g.rectangle("fill", x, y, size, size, 4, 4)
    g.setColor(0.045, 0.07, 0.15, 0.53)
    g.ellipse("fill", x + size * 0.5, y + size * 0.89, size * 0.34, size * 0.067)
    local img = sprite and (sprite.diff or sprite.image)
    if locked then g.setColor(0.05, 0.08, 0.18, 0.92) else g.setColor(1, 1, 1) end
    if img then
        local quad, fw, fh
        if sprite.isSheet and sprite.quads then
            local grid = sprite.quads.grid or sprite.quads
            local row = grid[enc.sheetRow or 1] or grid[0]
            quad = row and row[1]
        end
        if quad then
            local _, _, qw, qh = quad:getViewport()
            fw, fh = qw, qh
        else
            fw, fh = img:getDimensions()
        end
        local fit = (size - 13) / math.max(fw, fh, 1)
        local px = math.floor(x + (size - fw * fit) / 2)
        local py = math.floor(y + (size - fh * fit) / 2)
        local minFilter, magFilter, anisotropy = img:getFilter()
        img:setFilter("nearest", "nearest")
        if quad then g.draw(img, quad, px, py, 0, fit, fit) else g.draw(img, px, py, 0, fit, fit) end
        img:setFilter(minFilter, magFilter, anisotropy)
    else
        g.setColor(0.05, 0.08, 0.18, 0.92)
        g.ellipse("fill", x + size * 0.5, y + size * 0.7, size * 0.29, size * 0.17)
        g.circle("fill", x + size * 0.5, y + size * 0.43, size * 0.17)
    end
    if locked then
        g.setFont(fonts.title)
        g.setColor(0.89, 0.92, 1)
        g.printf("?", x, y + math.floor((size - fonts.title:getHeight()) / 2), size, "center")
    end
    g.setColor(0.04, 0.07, 0.17, 0.92)
    g.rectangle("fill", x + 3, y + 3, 24, 17, 3, 3)
    g.setColor(GOLD)
    g.setFont(fonts.small)
    g.printf("#" .. slot, x + 3, y + 4, 24, "center")
    g.setColor(0.71, 0.73, 0.83, 0.45)
    g.rectangle("line", x, y, size, size, 4, 4)
end

local function drawBadges(labels, font, x, y, limit)
    local g = love.graphics
    local gap, pad = 4, 5
    local total = -gap
    for _, badge in ipairs(labels) do total = total + font:getWidth(badge.text) + 2 * pad + gap end
    g.push()
    g.translate(x, y)
    g.scale(math.min(1, limit / total), 1)
    g.setFont(font)
    local dx = 0
    for _, badge in ipairs(labels) do
        local width = font:getWidth(badge.text) + 2 * pad
        local r, green, b = unpack(badge.color)
        g.setColor(r, green, b, 0.16)
        g.rectangle("fill", dx, 0, width, 17, 4, 4)
        g.setColor(badge.color)
        g.print(badge.text, dx + pad, 1)
        dx = dx + width + gap
    end
    g.pop()
end

local function drawCard(card, enc, img, entry, fonts, slot, hovered)
    local g = love.graphics
    local x, y, w, h = card.x, card.y, card.w, card.h
    g.setColor(0.025, 0.045, 0.13, 0.60)
    g.rectangle("fill", x, y + 3, w, h, 6, 6)
    if hovered then g.setColor(0.17, 0.27, 0.46)
    elseif entry then g.setColor(0.105, 0.17, 0.34)
    else g.setColor(0.061, 0.105, 0.235) end
    frame("fill", card, 6)
    if hovered then g.setColor(GOLD)
    elseif entry then g.setColor(0.63, 0.51, 0.32)
    else g.setColor(0.38, 0.48, 0.69) end
    frame("line", card, 6)

    local biome = BIOMES[enc.biome] or BIOMES.bosque
    local portraitSize = math.min(h - 20, math.floor(w * 0.29))
    drawPortrait(enc, img, x + 10, y + math.floor((h - portraitSize) / 2), portraitSize,
        not entry, fonts, slot, biome)

    local tx = x + portraitSize + 21
    local tw = x + w - tx - 10
    local ty = y + math.floor((h - 108) / 2)
    local heading, body, small = fonts.heading, fonts.body, fonts.small
    local title = entry and displayText(heading, enc.name or "") or "???"
    local titleScale = math.max(0.84, math.min(1, tw / math.max(1, heading:getWidth(title))))
    g.setFont(heading)
    if entry then g.setColor(GOLD) else g.setColor(0.88, 0.91, 0.99) end
    g.print(truncateText(heading, title, tw / titleScale), tx, ty + 9, 0, titleScale, 1)

    local labels = { { text = biome.name, color = biome.color } }
    if entry then
        if entry.comboName ~= "" then labels[#labels + 1] = { text = "COMBO", color = { 0.55, 0.91, 1 } } end
        if entry.isCritical then labels[#labels + 1] = { text = "CRÍTICO", color = GOLD } end
        if entry.count > 1 then labels[#labels + 1] = { text = "x" .. entry.count, color = { 0.86, 0.84, 1 } } end
    end
    drawBadges(labels, small, tx, ty + 33, tw)

    if entry then
        local quote = displayText(body, "Con: '" .. entry.prompt .. "'")
        local _, lines = body:getWrap(quote, tw)
        g.setFont(body)
        g.setColor(1, 0.88, 0.66)
        local lineHeight = body:getHeight()
        for i = 1, math.min(2, #lines) do
            local line = lines[i]:gsub("%s+$", "")
            g.print(truncateText(body, line, tw, i == 2 and #lines > 2), tx, ty + 55 + (i - 1) * lineHeight)
        end
        local memory = entry.narrator
        if memory == "" then memory = entry.turns .. (entry.turns == 1 and " turno" or " turnos") end
        g.setFont(small)
        g.setColor(0.76, 0.84, 0.98)
        g.print(truncateText(small, displayText(small, memory), tw), tx, ty + 58 + 2 * lineHeight)
    else
        g.setFont(small)
        g.setColor(0.76, 0.84, 0.98)
        g.print(truncateText(small, "Haz clic para desafiar", tw), tx, ty + 57)
    end
end

function VictoryAlbum:draw(encountersList, enemySprites, fonts, w, h)
    if not self.open then return end
    local g = love.graphics
    if not w or not h then w, h = g.getDimensions() end
    local ui = layout(w, h)
    local box = ui.modal
    local mx, my = love.mouse.getPosition()
    g.push("all")
    g.origin()
    g.setShader()
    g.setScissor()
    g.setBlendMode("alpha")
    g.setLineWidth(1)
    g.setColor(0.008, 0.012, 0.035, 0.76)
    g.rectangle("fill", 0, 0, w, h)
    drawFFWindow(box)

    g.setFont(fonts.title)
    g.setColor(GOLD)
    g.print("ÁLBUM DE LOCURAS", box.x + 24, box.y + 19)
    g.setFont(fonts.body)
    g.setColor(0.79, 0.85, 0.99)
    g.print(string.format("%d / %d rivales vencidos", self:countUnlocked(encountersList), #encountersList),
        box.x + 25, box.y + 48)
    drawButton(ui.clear, "Limpiar", contains(ui.clear, mx, my), fonts.body)
    drawButton(ui.close, "X", contains(ui.close, mx, my), fonts.body)

    for i, card in ipairs(ui.cards) do
        local enc = encountersList[i]
        if enc then
            local sprite = enemySprites and (enemySprites[enc.id] or enemySprites[i])
            drawCard(card, enc, sprite, self:getEntry(enc.id), fonts, i, contains(card, mx, my))
        end
    end

    g.setColor(0.37, 0.49, 0.73)
    g.line(box.x + 24, box.y + box.h - 37, box.x + box.w - 24, box.y + box.h - 37)
    g.setFont(fonts.body)
    g.setColor(0.86, 0.90, 1)
    g.printf("Haz clic en cualquier rival para ir directo a la revancha  ·  [J] o [ESC] para cerrar",
        box.x + 24, box.y + box.h - 28, box.w - 48, "center")
    g.pop()
end

return VictoryAlbum
