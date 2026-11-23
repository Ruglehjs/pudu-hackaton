-- asset_loader.lua
-- Dual-mode (Real Art / Procedural Greybox) asset loader with live [F5] hot-reload
-- supporting both unfused source directories and fused LÖVE2D 11.5 executables.

local AssetLoader = {}

local floor = math.floor
local abs = math.abs
local max = math.max
local min = math.min
local sin = math.sin
local exp = math.exp
local pi = math.pi

--------------------------------------------------------------------------------
-- Path & Low-Level Image Loading (External Disk First -> love.filesystem)
--------------------------------------------------------------------------------

function AssetLoader.getExternalBaseDir()
  local dir
  if love.filesystem.isFused() then
    dir = love.filesystem.getSourceBaseDirectory()
  else
    local src = love.filesystem.getSource()
    if type(src) == "string" and src:lower():match("%.love$") then
      dir = love.filesystem.getSourceBaseDirectory()
    else
      dir = src
    end
  end
  if type(dir) ~= "string" or dir == "" then
    return "."
  end
  if #dir > 1 then
    dir = dir:gsub("[/\\]+$", "")
  end
  return dir
end

local function normalizeRelPath(path)
  local p = path:gsub("\\", "/"):gsub("^/+", "")
  return p
end

local function applyImageSettings(img, path, repeatWrap, filterMode)
  local useLinear = (filterMode == "linear") or (path:lower():match("light_radial%.png$") ~= nil)
  if useLinear then
    img:setFilter("linear", "linear")
  else
    img:setFilter("nearest", "nearest")
  end
  if repeatWrap then
    img:setWrap("repeat", "repeat")
  end
  return img
end

function AssetLoader.loadImageRaw(path, repeatWrap, filterMode)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local relPath = normalizeRelPath(path)
  local img = nil

  -- 1. Try external disk first so [F5] reloads live PNG edits in unfused & fused builds.
  local okBase, baseDir = pcall(AssetLoader.getExternalBaseDir)
  if okBase and type(baseDir) == "string" and baseDir ~= "" then
    local fullPath = baseDir .. "/" .. relPath
    local okOpen, f = pcall(io.open, fullPath, "rb")
    if okOpen and f then
      local okRead, bytes = pcall(f.read, f, "*a")
      pcall(f.close, f)
      if okRead and type(bytes) == "string" and #bytes > 0 then
        local okData, fileData = pcall(love.filesystem.newFileData, bytes, relPath)
        if okData and fileData then
          local okImg, loaded = pcall(love.graphics.newImage, fileData)
          if okImg and loaded then
            img = loaded
          end
        end
      end
    end
  end

  -- 2. Fallback to love.filesystem (embedded .love / fused archive / save dir).
  if not img then
    local okInfo, info = pcall(love.filesystem.getInfo, relPath)
    if okInfo and info then
      local okImg, loaded = pcall(love.graphics.newImage, relPath)
      if okImg and loaded then
        img = loaded
      end
    end
  end

  if not img then
    return nil
  end

  return applyImageSettings(img, relPath, repeatWrap, filterMode)
end

function AssetLoader.loadSpritePair(basePath, repeatWrap, filterMode)
  if type(basePath) ~= "string" or basePath == "" then
    return nil
  end
  local stem = normalizeRelPath(basePath):gsub("%.[pP][nN][gG]$", "")
  local diffPath = stem .. ".png"
  local diffImg = AssetLoader.loadImageRaw(diffPath, repeatWrap, filterMode)
  if not diffImg then
    return nil
  end
  local normImg = AssetLoader.loadImageRaw(stem .. "_n.png", repeatWrap, filterMode)
  return {
    diff = diffImg,
    norm = normImg,
    isPlaceholder = false,
    path = diffPath,
  }
end

function AssetLoader.buildQuads(img, cols, rows)
  local quads = {}
  if not img then
    return quads
  end
  cols = max(1, floor(cols or 1))
  rows = max(1, floor(rows or 1))
  local iw, ih = img:getDimensions()
  local fw = iw / cols
  local fh = ih / rows

  for r = 0, rows - 1 do
    local rowQuads = {}
    for c = 1, cols do
      rowQuads[c] = love.graphics.newQuad((c - 1) * fw, r * fh, fw, fh, iw, ih)
    end
    quads[r] = rowQuads
  end
  return quads
end

--------------------------------------------------------------------------------
-- Fast Procedural Pixel-Art Helpers (Zero Per-Pixel Table Allocations)
--------------------------------------------------------------------------------

local function setPx(data, w, h, x, y, r, g, b, a)
  x = floor(x + 0.5)
  y = floor(y + 0.5)
  if x >= 0 and x < w and y >= 0 and y < h then
    data:setPixel(x, y, r, g, b, a or 1)
  end
end

local function fillRect(data, w, h, x0, y0, rw, rh, r, g, b, a)
  local sx = max(0, floor(x0 + 0.5))
  local sy = max(0, floor(y0 + 0.5))
  local ex = min(w - 1, floor(x0 + rw - 0.5))
  local ey = min(h - 1, floor(y0 + rh - 0.5))
  a = a or 1
  for y = sy, ey do
    for x = sx, ex do
      data:setPixel(x, y, r, g, b, a)
    end
  end
end

local function fillEllipse(data, w, h, cx, cy, rx, ry, r, g, b, a)
  if rx <= 0 or ry <= 0 then return end
  local sx = max(0, floor(cx - rx))
  local ex = min(w - 1, floor(cx + rx + 0.5))
  local sy = max(0, floor(cy - ry))
  local ey = min(h - 1, floor(cy + ry + 0.5))
  local invRx2 = 1 / (rx * rx)
  local invRy2 = 1 / (ry * ry)
  a = a or 1
  for y = sy, ey do
    local dy = y - cy
    local dy2 = dy * dy * invRy2
    for x = sx, ex do
      local dx = x - cx
      if dx * dx * invRx2 + dy2 <= 1.0 then
        data:setPixel(x, y, r, g, b, a)
      end
    end
  end
end

local function fillShadowEllipse(data, w, h, cx, cy, rx, ry, a)
  local sx = max(0, floor(cx - rx))
  local ex = min(w - 1, floor(cx + rx + 0.5))
  local sy = max(0, floor(cy - ry))
  local ey = min(h - 1, floor(cy + ry + 0.5))
  local invRx2 = 1 / (rx * rx)
  local invRy2 = 1 / (ry * ry)
  for y = sy, ey do
    local dy = y - cy
    local dy2 = dy * dy * invRy2
    for x = sx, ex do
      local dx = x - cx
      local d2 = dx * dx * invRx2 + dy2
      if d2 <= 1.0 then
        local _, _, _, ea = data:getPixel(x, y)
        if ea < 0.05 then
          local fade = a * (1.0 - d2 * 0.45)
          data:setPixel(x, y, 0.05, 0.04, 0.08, fade)
        end
      end
    end
  end
end

local function fillTriangle(data, w, h, x1, y1, x2, y2, x3, y3, r, g, b, a)
  local sx = max(0, floor(min(x1, x2, x3)))
  local ex = min(w - 1, floor(max(x1, x2, x3) + 0.5))
  local sy = max(0, floor(min(y1, y2, y3)))
  local ey = min(h - 1, floor(max(y1, y2, y3) + 0.5))
  local denom = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
  if abs(denom) < 1e-6 then return end
  local invDenom = 1 / denom
  a = a or 1
  for y = sy, ey do
    for x = sx, ex do
      local w1 = ((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3)) * invDenom
      local w2 = ((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3)) * invDenom
      local w3 = 1 - w1 - w2
      if w1 >= -1e-4 and w2 >= -1e-4 and w3 >= -1e-4 then
        data:setPixel(x, y, r, g, b, a)
      end
    end
  end
end

local function drawLine(data, w, h, x0, y0, x1, y1, r, g, b, a)
  x0 = floor(x0 + 0.5)
  y0 = floor(y0 + 0.5)
  x1 = floor(x1 + 0.5)
  y1 = floor(y1 + 0.5)
  local dx = abs(x1 - x0)
  local dy = -abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  a = a or 1
  while true do
    if x0 >= 0 and x0 < w and y0 >= 0 and y0 < h then
      data:setPixel(x0, y0, r, g, b, a)
    end
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then
      err = err + dy
      x0 = x0 + sx
    end
    if e2 <= dx then
      err = err + dx
      y0 = y0 + sy
    end
  end
end

local outlineScratchX = {}
local outlineScratchY = {}

local function applyOutline(data, ox, oy, cw, ch, or_, og, ob)
  local n = 0
  local maxX = ox + cw - 1
  local maxY = oy + ch - 1
  for y = oy, maxY do
    for x = ox, maxX do
      local _, _, _, a = data:getPixel(x, y)
      if a < 0.5 then
        local solidNeighbor = false
        if x > ox then
          local _, _, _, na = data:getPixel(x - 1, y)
          if na >= 0.5 then solidNeighbor = true end
        end
        if not solidNeighbor and x < maxX then
          local _, _, _, na = data:getPixel(x + 1, y)
          if na >= 0.5 then solidNeighbor = true end
        end
        if not solidNeighbor and y > oy then
          local _, _, _, na = data:getPixel(x, y - 1)
          if na >= 0.5 then solidNeighbor = true end
        end
        if not solidNeighbor and y < maxY then
          local _, _, _, na = data:getPixel(x, y + 1)
          if na >= 0.5 then solidNeighbor = true end
        end
        if solidNeighbor then
          n = n + 1
          outlineScratchX[n] = x
          outlineScratchY[n] = y
        end
      end
    end
  end
  for i = 1, n do
    data:setPixel(outlineScratchX[i], outlineScratchY[i], or_, og, ob, 1)
  end
end

local function hash2(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 1442695041) % 2147483647
  n = ((n * 1103515245 + 12345) % 2147483647)
  return (n % 10000) / 10000
end

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function newPixelImage(data, repeatWrap, filterMode)
  local img = love.graphics.newImage(data)
  if filterMode == "linear" then
    img:setFilter("linear", "linear")
  else
    img:setFilter("nearest", "nearest")
  end
  if repeatWrap then
    img:setWrap("repeat", "repeat")
  end
  return img
end

--------------------------------------------------------------------------------
-- Procedural Placeholder 1: Chilean Pudú 8-Direction Walk Sheet (384x512, 6x8)
-- Rows: 0=S, 1=SE, 2=E, 3=NE, 4=N, 5=NW, 6=W, 7=SW
--------------------------------------------------------------------------------

local function drawPuduLeg(data, w, h, ox, oy, x, yTop, yBot, dark)
  local r, g, b
  if dark then
    r, g, b = 0.37, 0.21, 0.12
  else
    r, g, b = 0.54, 0.32, 0.19
  end
  local legH = max(3, floor(yBot - yTop))
  fillRect(data, w, h, ox + x - 1, oy + yTop, 4, legH, r, g, b, 1)
  -- Dark hoof tip
  fillRect(data, w, h, ox + x - 1, oy + yTop + legH - 2, 4, 2, 0.16, 0.10, 0.08, 1)
end

local function drawPuduEye(data, w, h, ox, oy, x, y)
  fillRect(data, w, h, ox + x - 1, oy + y - 1, 3, 3, 0.11, 0.07, 0.05, 1)
  setPx(data, w, h, ox + x - 1, oy + y - 1, 0.98, 0.97, 0.95, 1)
end

local function drawPuduAntler(data, w, h, ox, oy, x, yBase, dx)
  drawLine(data, w, h, ox + x, oy + yBase, ox + x + dx, oy + yBase - 5, 0.89, 0.81, 0.69, 1)
  setPx(data, w, h, ox + x + dx, oy + yBase - 5, 0.96, 0.91, 0.82, 1)
  setPx(data, w, h, ox + x, oy + yBase - 1, 0.80, 0.70, 0.56, 1)
end

local function drawPuduCell(data, w, h, ox, oy, row, colIdx)
  -- Palette: warm Chilean Pudú
  local bR, bG, bB = 0.57, 0.34, 0.20 -- chestnut body
  local hR, hG, hB = 0.72, 0.46, 0.28 -- sunlit honey highlight
  local sR, sG, sB = 0.40, 0.22, 0.12 -- deep umber shadow
  local mR, mG, mB = 0.78, 0.58, 0.42 -- muzzle / inner ear tan
  local cR, cG, cB = 0.95, 0.91, 0.85 -- cream chest / fluffy tail
  local nR, nG, nB = 0.14, 0.09, 0.08 -- dark button nose

  local phase = (colIdx / 6) * pi * 2
  local stride = sin(phase)
  local bob = (colIdx % 3 == 1) and -2 or ((colIdx % 3 == 2) and -1 or 0)
  local earBob = (colIdx % 3 == 1) and -1 or 0

  if row == 0 then
    -- S (Front view: facing camera)
    local lLift = floor(max(0, stride) * 3)
    local rLift = floor(max(0, -stride) * 3)
    drawPuduLeg(data, w, h, ox, oy, 22, 46 + bob, 54 - rLift, true)
    drawPuduLeg(data, w, h, ox, oy, 41, 46 + bob, 54 - lLift, true)

    -- Body & cream chest
    fillEllipse(data, w, h, ox + 32, oy + 40 + bob, 12, 10, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 44 + bob, 11, 5, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 36 + bob, 9, 5, hR, hG, hB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 42 + bob, 6, 5, cR, cG, cB, 1)

    -- Front legs
    drawPuduLeg(data, w, h, ox, oy, 26, 46 + bob, 56 - lLift, false)
    drawPuduLeg(data, w, h, ox, oy, 37, 46 + bob, 56 - rLift, false)

    -- Ears & antlers
    fillEllipse(data, w, h, ox + 19, oy + 18 + bob + earBob, 5, 3, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 19, oy + 18 + bob + earBob, 3, 1.5, mR, mG, mB, 1)
    fillEllipse(data, w, h, ox + 45, oy + 18 + bob + earBob, 5, 3, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 45, oy + 18 + bob + earBob, 3, 1.5, mR, mG, mB, 1)
    drawPuduAntler(data, w, h, ox, oy, 26, 15 + bob, -1)
    drawPuduAntler(data, w, h, ox, oy, 38, 15 + bob, 1)

    -- Head, muzzle, eyes, nose
    fillEllipse(data, w, h, ox + 32, oy + 24 + bob, 11, 9, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 19 + bob, 7, 3.5, hR, hG, hB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 29 + bob, 5.5, 4, mR, mG, mB, 1)
    drawPuduEye(data, w, h, ox, oy, 26, 24 + bob)
    drawPuduEye(data, w, h, ox, oy, 38, 24 + bob)
    fillRect(data, w, h, ox + 30, oy + 28 + bob, 4, 2, nR, nG, nB, 1)
    fillRect(data, w, h, ox + 31, oy + 31 + bob, 2, 1, sR, sG, sB, 1)

  elseif row == 1 then
    -- SE (3/4 front-right)
    local sw = floor(stride * 3.2)
    -- Tail peeking on rear-left
    fillEllipse(data, w, h, ox + 16, oy + 37 + bob, 3.5, 3, cR, cG, cB, 1)
    -- Far legs
    drawPuduLeg(data, w, h, ox, oy, 22 - sw, 46 + bob, 55, true)
    drawPuduLeg(data, w, h, ox, oy, 36 + sw, 46 + bob, 55, true)

    -- Body & chest
    fillEllipse(data, w, h, ox + 30, oy + 40 + bob, 14, 9, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 29, oy + 44 + bob, 12, 4, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 28, oy + 36 + bob, 10, 4.5, hR, hG, hB, 1)
    fillEllipse(data, w, h, ox + 39, oy + 41 + bob, 5, 4.5, cR, cG, cB, 1)

    -- Near legs
    drawPuduLeg(data, w, h, ox, oy, 25 + sw, 46 + bob, 56, false)
    drawPuduLeg(data, w, h, ox, oy, 39 - sw, 46 + bob, 56, false)

    -- Back ear & antlers
    fillEllipse(data, w, h, ox + 27, oy + 16 + bob + earBob, 4.5, 3, sR, sG, sB, 1)
    drawPuduAntler(data, w, h, ox, oy, 34, 15 + bob, -1)
    drawPuduAntler(data, w, h, ox, oy, 41, 15 + bob, 1)

    -- Head turned front-right
    fillEllipse(data, w, h, ox + 37, oy + 24 + bob, 10, 8.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 36, oy + 19 + bob, 6, 3, hR, hG, hB, 1)
    -- Front ear
    fillEllipse(data, w, h, ox + 30, oy + 17 + bob + earBob, 4.5, 3, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 30, oy + 17 + bob + earBob, 2.5, 1.5, mR, mG, mB, 1)

    -- Snout pointing right-down + nose + both eyes
    fillEllipse(data, w, h, ox + 45, oy + 28 + bob, 5, 3.5, mR, mG, mB, 1)
    fillRect(data, w, h, ox + 47, oy + 27 + bob, 3, 2, nR, nG, nB, 1)
    drawPuduEye(data, w, h, ox, oy, 36, 24 + bob)
    drawPuduEye(data, w, h, ox, oy, 43, 24 + bob)

  elseif row == 2 then
    -- E (Full right profile)
    local sw = floor(stride * 4)
    -- Fluffy white tail on left rump
    fillEllipse(data, w, h, ox + 14, oy + 36 + bob, 3.5, 3, cR, cG, cB, 1)
    -- Far legs
    drawPuduLeg(data, w, h, ox, oy, 21 - sw, 45 + bob, 55, true)
    drawPuduLeg(data, w, h, ox, oy, 36 + sw, 45 + bob, 55, true)

    -- Horizontal deer body & neck
    fillEllipse(data, w, h, ox + 29, oy + 39 + bob, 14, 8.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 29, oy + 43 + bob, 12, 4, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 28, oy + 35 + bob, 10, 4, hR, hG, hB, 1)
    fillEllipse(data, w, h, ox + 42, oy + 40 + bob, 3.5, 4, cR, cG, cB, 1)
    fillEllipse(data, w, h, ox + 38, oy + 32 + bob, 5.5, 6.5, bR, bG, bB, 1)

    -- Near legs
    drawPuduLeg(data, w, h, ox, oy, 24 + sw, 45 + bob, 56, false)
    drawPuduLeg(data, w, h, ox, oy, 39 - sw, 45 + bob, 56, false)

    -- Ears & antlers
    fillEllipse(data, w, h, ox + 34, oy + 15 + bob + earBob, 4.5, 3, sR, sG, sB, 1)
    drawPuduAntler(data, w, h, ox, oy, 40, 15 + bob, 0)
    drawPuduAntler(data, w, h, ox, oy, 43, 16 + bob, 1)

    -- Head + extended right-pointing snout + side eye
    fillEllipse(data, w, h, ox + 41, oy + 23 + bob, 8.5, 7.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 39, oy + 19 + bob, 5, 2.5, hR, hG, hB, 1)
    fillEllipse(data, w, h, ox + 36, oy + 16 + bob + earBob, 4, 2.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 36, oy + 16 + bob + earBob, 2, 1.2, mR, mG, mB, 1)
    fillEllipse(data, w, h, ox + 49, oy + 25 + bob, 5, 3.5, mR, mG, mB, 1)
    fillRect(data, w, h, ox + 52, oy + 24 + bob, 3, 2, nR, nG, nB, 1)
    drawPuduEye(data, w, h, ox, oy, 44, 22 + bob)

  elseif row == 3 then
    -- NE (3/4 back-right — canonical diagonal travel & battle row!)
    local sw = floor(stride * 3.2)
    -- Far legs
    drawPuduLeg(data, w, h, ox, oy, 25 - sw, 45 + bob, 55, true)
    drawPuduLeg(data, w, h, ox, oy, 38 + sw, 45 + bob, 55, true)

    -- Body angled away-right
    fillEllipse(data, w, h, ox + 30, oy + 40 + bob, 14, 9, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 30, oy + 44 + bob, 12, 4, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 31, oy + 35 + bob, 10, 4.5, hR, hG, hB, 1)

    -- Near legs
    drawPuduLeg(data, w, h, ox, oy, 22 + sw, 46 + bob, 56, false)
    drawPuduLeg(data, w, h, ox, oy, 39 - sw, 46 + bob, 56, false)

    -- Prominent cute white tail puff on rear-left rump
    fillEllipse(data, w, h, ox + 19, oy + 41 + bob, 4.5, 4, cR, cG, cB, 1)

    -- Neck + head turned up-right
    fillEllipse(data, w, h, ox + 36, oy + 31 + bob, 6, 6, bR, bG, bB, 1)
    drawPuduAntler(data, w, h, ox, oy, 34, 15 + bob, -1)
    drawPuduAntler(data, w, h, ox, oy, 40, 15 + bob, 1)

    -- Snout clearly pointing right + dark nose tip
    fillEllipse(data, w, h, ox + 46, oy + 24 + bob, 5, 3, mR, mG, mB, 1)
    fillRect(data, w, h, ox + 49, oy + 23 + bob, 2, 2, nR, nG, nB, 1)

    -- Head + cheek eye peeking right
    fillEllipse(data, w, h, ox + 37, oy + 23 + bob, 9.5, 8, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 36, oy + 18 + bob, 6, 3, hR, hG, hB, 1)
    drawPuduEye(data, w, h, ox, oy, 43, 22 + bob)

    -- Ears seen from 3/4 rear
    fillEllipse(data, w, h, ox + 28, oy + 16 + bob + earBob, 4.5, 3, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 41, oy + 15 + bob + earBob, 4, 2.5, bR, bG, bB, 1)

  elseif row == 4 then
    -- N (Full back view: facing away)
    local lLift = floor(max(0, stride) * 3)
    local rLift = floor(max(0, -stride) * 3)
    drawPuduLeg(data, w, h, ox, oy, 22, 46 + bob, 54 - rLift, true)
    drawPuduLeg(data, w, h, ox, oy, 41, 46 + bob, 54 - lLift, true)

    -- Rounded chestnut back
    fillEllipse(data, w, h, ox + 32, oy + 39 + bob, 12, 10, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 44 + bob, 11, 5, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 34 + bob, 8.5, 4.5, hR, hG, hB, 1)

    -- Rear legs
    drawPuduLeg(data, w, h, ox, oy, 26, 46 + bob, 56 - lLift, false)
    drawPuduLeg(data, w, h, ox, oy, 37, 46 + bob, 56 - rLift, false)

    -- Centered fluffy white tail on rump
    fillEllipse(data, w, h, ox + 32, oy + 43 + bob, 4.5, 4, cR, cG, cB, 1)

    -- Ears (back of ear) & antlers
    fillEllipse(data, w, h, ox + 19, oy + 17 + bob + earBob, 5, 3, sR, sG, sB, 1)
    fillEllipse(data, w, h, ox + 45, oy + 17 + bob + earBob, 5, 3, sR, sG, sB, 1)
    drawPuduAntler(data, w, h, ox, oy, 26, 15 + bob, -1)
    drawPuduAntler(data, w, h, ox, oy, 38, 15 + bob, 1)

    -- Back of head (no eyes/snout)
    fillEllipse(data, w, h, ox + 32, oy + 23 + bob, 10.5, 8.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, ox + 32, oy + 18 + bob, 6.5, 3.5, hR, hG, hB, 1)
  end

  -- Crisp 1px dark espresso outline around opaque Pudú silhouette
  applyOutline(data, ox + 6, oy + 5, 52, 55, 0.15, 0.08, 0.05)

  -- Soft ground contact shadow drawn only onto transparent background beneath hooves
  fillShadowEllipse(data, w, h, ox + 32, oy + 56, 14, 3.5, 0.34)
end

local function mirrorRowHorizontally(data, srcRow, dstRow, cols, cellSize)
  local srcOy = srcRow * cellSize
  local dstOy = dstRow * cellSize
  for c = 0, cols - 1 do
    local ox = c * cellSize
    for y = 0, cellSize - 1 do
      local sy = srcOy + y
      local dy = dstOy + y
      for x = 0, cellSize - 1 do
        local r, g, b, a = data:getPixel(ox + x, sy)
        if a > 0 then
          data:setPixel(ox + (cellSize - 1 - x), dy, r, g, b, a)
        end
      end
    end
  end
end

local function makePuduPlaceholderSheet()
  local cols, rows, cell = 6, 8, 64
  local w, h = cols * cell, rows * cell -- 384x512
  local data = love.image.newImageData(w, h)

  for r = 0, 4 do
    for c = 0, cols - 1 do
      drawPuduCell(data, w, h, c * cell, r * cell, r, c)
    end
  end

  -- Mirror right-facing rows into exact left-facing counterparts:
  -- 5 (NW) <- 3 (NE), 6 (W) <- 2 (E), 7 (SW) <- 1 (SE)
  mirrorRowHorizontally(data, 3, 5, cols, cell)
  mirrorRowHorizontally(data, 2, 6, cols, cell)
  mirrorRowHorizontally(data, 1, 7, cols, cell)

  return {
    diff = newPixelImage(data, false, "nearest"),
    norm = nil,
    isPlaceholder = true,
    path = "procedural:pudu_8dir_sheet",
  }
end

--------------------------------------------------------------------------------
-- Procedural Placeholder 2: Pointy Brown Wizard Hat (64x64)
--------------------------------------------------------------------------------

local function makeWizardHatPlaceholder()
  local w, h = 64, 64
  local data = love.image.newImageData(w, h)

  -- Wide curved brim (dark underside + warm brown upper rim)
  fillEllipse(data, w, h, 32, 47, 23, 7.5, 0.34, 0.18, 0.09, 1)
  fillEllipse(data, w, h, 32, 45, 22, 6, 0.54, 0.31, 0.16, 1)
  fillEllipse(data, w, h, 30, 44, 16, 3.5, 0.66, 0.40, 0.21, 1)

  -- Tall slightly crooked wizard cone (base + bent pointy tip)
  fillTriangle(data, w, h, 17, 43, 47, 43, 33, 14, 0.48, 0.27, 0.14, 1)
  fillTriangle(data, w, h, 26, 26, 39, 25, 42, 10, 0.48, 0.27, 0.14, 1)
  -- Sunlit left highlight facet
  fillTriangle(data, w, h, 19, 42, 31, 42, 33, 15, 0.64, 0.39, 0.21, 1)
  fillTriangle(data, w, h, 27, 25, 34, 24, 41, 11, 0.64, 0.39, 0.21, 1)
  -- Right-side shade facet
  fillTriangle(data, w, h, 37, 42, 46, 42, 35, 22, 0.36, 0.19, 0.10, 1)

  -- Golden satin band wrapping cone base
  fillRect(data, w, h, 18, 38, 28, 5, 0.88, 0.69, 0.18, 1)
  fillRect(data, w, h, 19, 39, 24, 2, 0.98, 0.86, 0.38, 1)

  -- Crisp square gold buckle centered on band
  fillRect(data, w, h, 28, 36, 8, 8, 0.98, 0.88, 0.42, 1)
  fillRect(data, w, h, 29, 37, 6, 6, 0.84, 0.60, 0.14, 1)
  fillRect(data, w, h, 30, 38, 4, 4, 0.28, 0.15, 0.08, 1)
  setPx(data, w, h, 28, 36, 1.0, 0.98, 0.82, 1)

  applyOutline(data, 4, 5, 56, 54, 0.15, 0.08, 0.05)

  return {
    diff = newPixelImage(data, false, "nearest"),
    norm = nil,
    isPlaceholder = true,
    path = "procedural:pudu_wizard_hat",
  }
end

--------------------------------------------------------------------------------
-- Procedural Placeholder 3: 5 Seamlessly Tileable Biome Floor Tiles (64x64)
--------------------------------------------------------------------------------

local function setWrappedPx(data, s, x, y, r, g, b)
  data:setPixel(x % s, y % s, clamp01(r), clamp01(g), clamp01(b), 1)
end

local function makeBiomeTilePlaceholder(tileName)
  local s = 64
  local data = love.image.newImageData(s, s)

  if tileName == "grass_floor" then
    -- Lush Valdivian mossy meadow with subtle dappled patches + pixel tufts
    for y = 0, s - 1 do
      for x = 0, s - 1 do
        local wave = sin(x * pi * 2 / s) * 0.5 + sin((y * 2 + x) * pi * 2 / s) * 0.5
        local n = hash2(x, y, 11) - 0.5
        local d = wave * 0.035 + n * 0.055
        data:setPixel(x, y, clamp01(0.28 + d * 0.8), clamp01(0.49 + d), clamp01(0.24 + d * 0.7), 1)
      end
    end
    -- Subtle grass blades & tiny wildflower specks (seamlessly wrapped)
    local tufts = {
      { 6, 10 }, { 22, 14 }, { 42, 8 }, { 56, 20 },
      { 12, 30 }, { 30, 26 }, { 48, 34 }, { 18, 48 },
      { 36, 44 }, { 54, 52 }, { 8, 58 }, { 28, 60 },
    }
    for i = 1, #tufts do
      local tx, ty = tufts[i][1], tufts[i][2]
      setWrappedPx(data, s, tx, ty, 0.21, 0.38, 0.18)
      setWrappedPx(data, s, tx + 1, ty, 0.21, 0.38, 0.18)
      setWrappedPx(data, s, tx - 1, ty - 1, 0.40, 0.64, 0.31)
      setWrappedPx(data, s, tx, ty - 2, 0.44, 0.68, 0.34)
      setWrappedPx(data, s, tx + 2, ty - 1, 0.38, 0.61, 0.29)
    end
    -- 3 tiny pale meadow blossoms
    setWrappedPx(data, s, 15, 22, 0.96, 0.91, 0.62)
    setWrappedPx(data, s, 45, 41, 0.94, 0.96, 0.82)
    setWrappedPx(data, s, 26, 54, 0.96, 0.88, 0.56)

  elseif tileName == "stone_floor" then
    -- Staggered cobblestone / plaza flagstones (16px row height, 32px brick width)
    for y = 0, s - 1 do
      local row = floor(y / 16)
      local ly = y % 16
      local xOff = (row % 2 == 1) and 16 or 0
      for x = 0, s - 1 do
        local sx = (x + xOff) % s
        local col = floor(sx / 32)
        local lx = sx % 32
        local tileTint = (hash2(col, row, 23) - 0.5) * 0.06
        local grain = (hash2(x, y, 29) - 0.5) * 0.045
        local r = 0.44 + tileTint + grain
        local g = 0.46 + tileTint + grain
        local b = 0.51 + tileTint + grain

        if ly == 0 or lx == 0 then
          -- Crisp recessed mortar joint
          r, g, b = 0.30, 0.32, 0.37
        elseif ly == 1 or lx == 1 then
          -- Sunlit top-left stone bevel
          r, g, b = r + 0.09, g + 0.09, b + 0.10
        elseif ly == 15 or lx == 31 then
          -- Subtle bottom-right bevel shade
          r, g, b = r - 0.06, g - 0.06, b - 0.06
        end
        data:setPixel(x, y, clamp01(r), clamp01(g), clamp01(b), 1)
      end
    end

  elseif tileName == "desert_floor" then
    -- Warm Atacama ochre sand with diagonal wind-swept dune ripples
    for y = 0, s - 1 do
      for x = 0, s - 1 do
        local ripple = sin((x * 2 + y * 4) * pi * 2 / s + sin(x * pi * 2 / s) * 0.6)
        local n = (hash2(x, y, 41) - 0.5) * 0.045
        local crest = (ripple > 0.55) and 0.06 or ((ripple < -0.55) and -0.05 or ripple * 0.03)
        local r = 0.83 + crest + n
        local g = 0.63 + crest * 0.85 + n * 0.85
        local b = 0.36 + crest * 0.6 + n * 0.6
        data:setPixel(x, y, clamp01(r), clamp01(g), clamp01(b), 1)
      end
    end
    -- Sparse warm terracotta pebbles
    local pebbles = { { 10, 12 }, { 34, 8 }, { 52, 26 }, { 20, 40 }, { 46, 54 }, { 6, 50 } }
    for i = 1, #pebbles do
      local px, py = pebbles[i][1], pebbles[i][2]
      setWrappedPx(data, s, px, py, 0.60, 0.39, 0.21)
      setWrappedPx(data, s, px + 1, py, 0.64, 0.42, 0.23)
      setWrappedPx(data, s, px, py - 1, 0.90, 0.74, 0.48)
    end

  elseif tileName == "mountain_floor" then
    -- Rugged Andean slate/granite highland stone with angular strata cracks & frost flecks
    for y = 0, s - 1 do
      for x = 0, s - 1 do
        local strata = sin((x * 3 - y * 2) * pi * 2 / s) * 0.5 + sin((y * 3 + x) * pi * 2 / s) * 0.5
        local n = (hash2(x, y, 53) - 0.5) * 0.065
        local r = 0.38 + strata * 0.045 + n
        local g = 0.36 + strata * 0.045 + n
        local b = 0.39 + strata * 0.055 + n
        -- Crisp rock fissure lines (periodic)
        local crack = abs(sin((x * 2 + y * 2) * pi * 2 / s + sin(y * pi * 2 / s) * 0.8))
        if crack < 0.055 then
          r, g, b = r - 0.12, g - 0.12, b - 0.11
        elseif crack > 0.96 then
          r, g, b = r + 0.07, g + 0.07, b + 0.09
        end
        data:setPixel(x, y, clamp01(r), clamp01(g), clamp01(b), 1)
      end
    end
    -- Small alpine quartz / pale stone flecks
    local flecks = { { 9, 18 }, { 27, 9 }, { 48, 22 }, { 16, 44 }, { 38, 36 }, { 56, 54 } }
    for i = 1, #flecks do
      local fx, fy = flecks[i][1], flecks[i][2]
      setWrappedPx(data, s, fx, fy, 0.72, 0.76, 0.82)
      setWrappedPx(data, s, fx + 1, fy + 1, 0.25, 0.24, 0.27)
    end

  else
    -- coast_floor: Pale Valparaíso coastal beach sand + turquoise tide-wash bands
    for y = 0, s - 1 do
      for x = 0, s - 1 do
        local tide = sin((y * 2 + sin(x * pi * 2 / s) * 3.5) * pi * 2 / s)
        local n = (hash2(x, y, 71) - 0.5) * 0.04
        local r, g, b
        if tide > 0.55 then
          -- Gentle coastal seafoam / turquoise tide-wash ribbon
          local mix = (tide - 0.55) / 0.45
          r = 0.80 * (1 - mix * 0.35) + 0.48 * (mix * 0.35) + n
          g = 0.77 * (1 - mix * 0.20) + 0.74 * (mix * 0.20) + n
          b = 0.63 * (1 - mix * 0.45) + 0.75 * (mix * 0.45) + n
        else
          -- Bright sun-bleached coastal sand
          r = 0.83 + tide * 0.03 + n
          g = 0.78 + tide * 0.03 + n
          b = 0.62 + tide * 0.03 + n
        end
        data:setPixel(x, y, clamp01(r), clamp01(g), clamp01(b), 1)
      end
    end
    -- Tiny shells & smooth coastal pebbles
    local shells = { { 12, 16 }, { 40, 12 }, { 26, 36 }, { 54, 44 }, { 18, 56 } }
    for i = 1, #shells do
      local sx, sy = shells[i][1], shells[i][2]
      setWrappedPx(data, s, sx, sy, 0.95, 0.93, 0.86)
      setWrappedPx(data, s, sx + 1, sy, 0.75, 0.84, 0.82)
      setWrappedPx(data, s, sx, sy + 1, 0.62, 0.58, 0.49)
    end
  end

  return {
    diff = newPixelImage(data, true, "nearest"),
    norm = nil,
    isPlaceholder = true,
    path = "procedural:tile_" .. tileName,
  }
end

--------------------------------------------------------------------------------
-- Procedural Placeholder 4: Smooth Radial Gaussian Light Halo (128x128, linear)
--------------------------------------------------------------------------------

local function makeLightRadialPlaceholder()
  local s = 128
  local half = s * 0.5
  local data = love.image.newImageData(s, s)

  for y = 0, s - 1 do
    local dy = (y + 0.5 - half) / half
    local dy2 = dy * dy
    for x = 0, s - 1 do
      local dx = (x + 0.5 - half) / half
      local r2 = dx * dx + dy2
      if r2 >= 1.0 then
        data:setPixel(x, y, 1, 1, 1, 0)
      else
        local edge = 1.0 - r2
        local a = exp(-4.0 * r2) * edge * edge
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
  end

  return newPixelImage(data, false, "linear")
end

--------------------------------------------------------------------------------
-- Procedural Placeholder 5: Expressive Pudú Portraits (64x64: happy/shocked/angry)
--------------------------------------------------------------------------------

local function makePortraitPlaceholder(mood)
  local w, h = 64, 64
  local data = love.image.newImageData(w, h)

  local bR, bG, bB = 0.57, 0.34, 0.20
  local hR, hG, hB = 0.74, 0.48, 0.30
  local sR, sG, sB = 0.39, 0.21, 0.12
  local mR, mG, mB = 0.82, 0.63, 0.46
  local cR, cG, cB = 0.95, 0.91, 0.85

  -- Shoulders + fluffy cream chest
  fillEllipse(data, w, h, 32, 57, 19, 11, bR, bG, bB, 1)
  fillEllipse(data, w, h, 32, 58, 10, 7, cR, cG, cB, 1)

  -- Ears positioned by expression
  if mood == "shocked" then
    fillEllipse(data, w, h, 10, 28, 7, 4, bR, bG, bB, 1)
    fillEllipse(data, w, h, 10, 28, 4, 2, mR, mG, mB, 1)
    fillEllipse(data, w, h, 54, 28, 7, 4, bR, bG, bB, 1)
    fillEllipse(data, w, h, 54, 28, 4, 2, mR, mG, mB, 1)
  elseif mood == "angry" then
    fillEllipse(data, w, h, 12, 26, 7, 3.5, sR, sG, sB, 1)
    fillEllipse(data, w, h, 52, 26, 7, 3.5, sR, sG, sB, 1)
  else
    -- happy (perky upright ears)
    fillEllipse(data, w, h, 13, 21, 7, 4.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, 13, 21, 4, 2.5, mR, mG, mB, 1)
    fillEllipse(data, w, h, 51, 21, 7, 4.5, bR, bG, bB, 1)
    fillEllipse(data, w, h, 51, 21, 4, 2.5, mR, mG, mB, 1)
  end

  -- Tiny twin antlers
  drawPuduAntler(data, w, h, 0, 0, 23, 17, -2)
  drawPuduAntler(data, w, h, 0, 0, 41, 17, 2)

  -- Big expressive round Pudú head + snout
  fillEllipse(data, w, h, 32, 34, 18, 16, bR, bG, bB, 1)
  fillEllipse(data, w, h, 32, 24, 12, 6, hR, hG, hB, 1)
  fillEllipse(data, w, h, 32, 42, 9.5, 6.5, mR, mG, mB, 1)

  -- Nose
  fillEllipse(data, w, h, 32, 39, 3.5, 2.2, 0.14, 0.09, 0.08, 1)

  if mood == "happy" then
    -- Cheerful curved happy eyes (^ ^) + rosy cheeks + big smile with pink tongue
    drawLine(data, w, h, 20, 32, 23, 29, 0.12, 0.07, 0.05, 1)
    drawLine(data, w, h, 23, 29, 26, 32, 0.12, 0.07, 0.05, 1)
    drawLine(data, w, h, 20, 33, 23, 30, 0.12, 0.07, 0.05, 1)
    drawLine(data, w, h, 23, 30, 26, 33, 0.12, 0.07, 0.05, 1)

    drawLine(data, w, h, 38, 32, 41, 29, 0.12, 0.07, 0.05, 1)
    drawLine(data, w, h, 41, 29, 44, 32, 0.12, 0.07, 0.05, 1)
    drawLine(data, w, h, 38, 33, 41, 30, 0.12, 0.07, 0.05, 1)
    drawLine(data, w, h, 41, 30, 44, 33, 0.12, 0.07, 0.05, 1)

    -- Rosy cheeks
    fillEllipse(data, w, h, 18, 37, 3.5, 2, 0.92, 0.48, 0.48, 1)
    fillEllipse(data, w, h, 46, 37, 3.5, 2, 0.92, 0.48, 0.48, 1)

    -- Happy open smile
    fillEllipse(data, w, h, 32, 45, 5, 3, 0.25, 0.10, 0.08, 1)
    fillEllipse(data, w, h, 32, 46, 3, 1.5, 0.93, 0.48, 0.52, 1)

  elseif mood == "shocked" then
    -- Wide white startled eyes with tiny pinpoint pupils
    fillEllipse(data, w, h, 23, 31, 5, 5.5, 0.98, 0.98, 1.0, 1)
    fillEllipse(data, w, h, 41, 31, 5, 5.5, 0.98, 0.98, 1.0, 1)
    fillRect(data, w, h, 22, 30, 2, 2, 0.10, 0.07, 0.06, 1)
    fillRect(data, w, h, 40, 30, 2, 2, 0.10, 0.07, 0.06, 1)
    -- Open "O" shocked mouth
    fillEllipse(data, w, h, 32, 45, 3.8, 4.5, 0.16, 0.08, 0.08, 1)
    fillEllipse(data, w, h, 32, 46, 2, 2, 0.72, 0.28, 0.30, 1)
    -- Comic blue sweat drop on right temple
    fillTriangle(data, w, h, 49, 13, 46, 20, 52, 20, 0.45, 0.85, 1.0, 1)
    fillEllipse(data, w, h, 49, 21, 3, 2.5, 0.45, 0.85, 1.0, 1)
    setPx(data, w, h, 48, 20, 0.95, 0.99, 1.0, 1)

  else
    -- angry: furrowed V-brows, intense narrowed eyes, determined frown, red anger vein
    fillEllipse(data, w, h, 23, 32, 4.2, 3.2, 0.98, 0.96, 0.92, 1)
    fillEllipse(data, w, h, 41, 32, 4.2, 3.2, 0.98, 0.96, 0.92, 1)
    fillRect(data, w, h, 23, 31, 3, 3, 0.12, 0.07, 0.06, 1)
    fillRect(data, w, h, 39, 31, 3, 3, 0.12, 0.07, 0.06, 1)
    -- Thick steep V-shaped angry eyebrows
    drawLine(data, w, h, 17, 26, 28, 30, 0.16, 0.08, 0.05, 1)
    drawLine(data, w, h, 17, 27, 28, 31, 0.16, 0.08, 0.05, 1)
    drawLine(data, w, h, 47, 26, 36, 30, 0.16, 0.08, 0.05, 1)
    drawLine(data, w, h, 47, 27, 36, 31, 0.16, 0.08, 0.05, 1)
    -- Determined scowl mouth
    drawLine(data, w, h, 27, 45, 32, 43, 0.18, 0.09, 0.07, 1)
    drawLine(data, w, h, 32, 43, 37, 45, 0.18, 0.09, 0.07, 1)
    drawLine(data, w, h, 27, 46, 32, 44, 0.18, 0.09, 0.07, 1)
    drawLine(data, w, h, 32, 44, 37, 46, 0.18, 0.09, 0.07, 1)
    -- Comic anger mark on upper forehead
    drawLine(data, w, h, 43, 18, 45, 20, 0.95, 0.25, 0.20, 1)
    drawLine(data, w, h, 49, 18, 47, 20, 0.95, 0.25, 0.20, 1)
    drawLine(data, w, h, 43, 24, 45, 22, 0.95, 0.25, 0.20, 1)
    drawLine(data, w, h, 49, 24, 47, 22, 0.95, 0.25, 0.20, 1)
  end

  applyOutline(data, 2, 4, 60, 60, 0.14, 0.08, 0.06)
  return newPixelImage(data, false, "nearest")
end

--------------------------------------------------------------------------------
-- Procedural Placeholder 6: Encounter Rival Silhouette (72x88)
--------------------------------------------------------------------------------

local ENCOUNTER_PALETTE = {
  { 0.86, 0.34, 0.36 }, -- 1. Coral crimson
  { 0.30, 0.56, 0.88 }, -- 2. Cobalt blue
  { 0.88, 0.62, 0.24 }, -- 3. Golden amber
  { 0.68, 0.36, 0.82 }, -- 4. Violet magenta
  { 0.26, 0.72, 0.54 }, -- 5. Emerald teal
  { 0.90, 0.48, 0.24 }, -- 6. Sunset orange
  { 0.38, 0.44, 0.78 }, -- 7. Deep indigo
  { 0.84, 0.32, 0.56 }, -- 8. Crimson rose
  { 0.28, 0.68, 0.78 }, -- 9. Coastal cyan
}

local function hashString(s)
  local h = 17
  for i = 1, #s do
    h = (h * 31 + s:byte(i)) % 100003
  end
  return h
end

local function resolveEncounterColor(id, index, color)
  if type(color) == "table" and type(color[1]) == "number" and type(color[2]) == "number" and type(color[3]) == "number" then
    local r, g, b = color[1], color[2], color[3]
    if r > 1 or g > 1 or b > 1 then
      r, g, b = r / 255, g / 255, b / 255
    end
    return clamp01(r), clamp01(g), clamp01(b)
  end
  local idx = index
  if type(idx) ~= "number" or idx < 1 then
    idx = (type(id) == "string" and (hashString(id) % #ENCOUNTER_PALETTE) + 1) or 1
  end
  local pal = ENCOUNTER_PALETTE[((floor(idx) - 1) % #ENCOUNTER_PALETTE) + 1]
  return pal[1], pal[2], pal[3]
end

function AssetLoader.makeEncounterPlaceholder(id, index, color)
  local w, h = 72, 88
  local data = love.image.newImageData(w, h)

  local r, g, b = resolveEncounterColor(id, index, color)
  local hiR, hiG, hiB = clamp01(r + 0.18), clamp01(g + 0.18), clamp01(b + 0.16)
  local shR, shG, shB = clamp01(r * 0.62), clamp01(g * 0.62), clamp01(b * 0.66)
  local headR, headG, headB = clamp01(r * 0.45 + 0.52), clamp01(g * 0.45 + 0.50), clamp01(b * 0.45 + 0.48)

  local variant = ((type(index) == "number" and floor(index)) or (type(id) == "string" and hashString(id)) or 1) % 3

  -- Sturdy RPG boots anchored near bottom
  fillRect(data, w, h, 24, 73, 8, 9, 0.24, 0.20, 0.26, 1)
  fillRect(data, w, h, 40, 73, 8, 9, 0.24, 0.20, 0.26, 1)
  fillRect(data, w, h, 22, 78, 10, 4, 0.18, 0.15, 0.20, 1)
  fillRect(data, w, h, 38, 78, 10, 4, 0.18, 0.15, 0.20, 1)

  -- Cloaked / vested JRPG rival torso with shading
  fillEllipse(data, w, h, 36, 59, 18, 17, r, g, b, 1)
  fillEllipse(data, w, h, 42, 62, 12, 13, shR, shG, shB, 1)
  fillEllipse(data, w, h, 30, 53, 10, 8, hiR, hiG, hiB, 1)

  -- Belt + gold buckle
  fillRect(data, w, h, 20, 62, 32, 4, 0.20, 0.16, 0.22, 1)
  fillRect(data, w, h, 31, 61, 8, 6, 0.94, 0.78, 0.26, 1)
  fillRect(data, w, h, 33, 63, 4, 2, 0.24, 0.18, 0.12, 1)

  -- Chest crest accent
  fillTriangle(data, w, h, 34, 48, 29, 54, 34, 60, 0.96, 0.95, 0.92, 1)
  fillTriangle(data, w, h, 34, 48, 39, 54, 34, 60, 0.88, 0.86, 0.82, 1)

  -- Distinct silhouette crest/hat/ears per variant
  if variant == 0 then
    -- Pointy ears / twin crest
    fillTriangle(data, w, h, 21, 24, 29, 20, 23, 10, r, g, b, 1)
    fillTriangle(data, w, h, 43, 20, 51, 24, 49, 10, shR, shG, shB, 1)
  elseif variant == 1 then
    -- Jaunty cap / crown silhouette
    fillEllipse(data, w, h, 36, 18, 15, 6, r, g, b, 1)
    fillEllipse(data, w, h, 32, 16, 10, 3.5, hiR, hiG, hiB, 1)
    fillRect(data, w, h, 20, 19, 26, 3, 0.95, 0.82, 0.32, 1)
  else
    -- Mohawk / plush crest tuft
    fillEllipse(data, w, h, 36, 14, 7, 7, hiR, hiG, hiB, 1)
    fillEllipse(data, w, h, 42, 16, 5, 5, r, g, b, 1)
  end

  -- Expressive round head facing slightly left toward Pudú
  fillEllipse(data, w, h, 36, 32, 15, 14, headR, headG, headB, 1)
  fillEllipse(data, w, h, 31, 25, 8, 5, clamp01(headR + 0.10), clamp01(headG + 0.10), clamp01(headB + 0.10), 1)

  -- Expressive white eyes looking left + dark pupils + angled brows
  fillEllipse(data, w, h, 28, 32, 3.8, 4.2, 0.99, 0.99, 1.0, 1)
  fillEllipse(data, w, h, 39, 32, 3.8, 4.2, 0.99, 0.99, 1.0, 1)
  fillRect(data, w, h, 25, 31, 3, 3, 0.12, 0.10, 0.15, 1)
  fillRect(data, w, h, 36, 31, 3, 3, 0.12, 0.10, 0.15, 1)
  setPx(data, w, h, 26, 31, 1, 1, 1, 1)
  setPx(data, w, h, 37, 31, 1, 1, 1, 1)

  -- Cheeky eyebrows & smirk
  drawLine(data, w, h, 24, 26, 31, 28, 0.16, 0.12, 0.18, 1)
  drawLine(data, w, h, 43, 26, 36, 28, 0.16, 0.12, 0.18, 1)
  drawLine(data, w, h, 29, 39, 35, 39, 0.22, 0.14, 0.16, 1)
  drawLine(data, w, h, 35, 39, 37, 37, 0.22, 0.14, 0.16, 1)

  -- Crisp 1px dark outline + soft oval ground shadow beneath boots
  applyOutline(data, 8, 6, 56, 78, 0.12, 0.09, 0.14)
  fillShadowEllipse(data, w, h, 36, 82, 22, 4.5, 0.34)

  return {
    diff = newPixelImage(data, false, "nearest"),
    norm = nil,
    isPlaceholder = true,
    path = "procedural:encounter_" .. tostring(id or index or "generic"),
  }
end

--------------------------------------------------------------------------------
-- High-Level Asset Bundle Loader (Modo A / Modo A+B / Modo B)
--------------------------------------------------------------------------------

local TILE_NAMES = {
  "grass_floor",
  "stone_floor",
  "desert_floor",
  "mountain_floor",
  "coast_floor",
}

local PORTRAIT_MOODS = {
  "happy",
  "shocked",
  "angry",
}

-- Siluetas de los gags para el prototipo sin PNG. Cada celda ocupa 4 píxeles.
local gagTiles = {
  rain_cloud      = "....www/..wwwccc/.wwwwccc/wwccccccc/.ccccccc/.......... /..b..b..b/.b..b..b",
  banana_peel     = "....t/....y/....yy/...yyyy/..yy.yyy/.yy..y.yy/ty...y..yt/.....t",
  cucumber        = "......gg/.....glgg/....glgg/...gglg/..glgg/..ggg/.glg/.gg",
  melted_icecream = "...ppp/..pwppp/..ppppp/...ttt/...tyt/....t/..p.ppp/.ppppppp",
  lightning_bolt  = "....yyyy/...yyyy/...yy/..yyyyyy/....yyy/...yyy/..yy/.y",
  hair_dryer      = "..rrrrrr/.rpprrrrtt/.rrrrrrrtt/..rrrrrr/...tt/..tt/..tt",
  giant_fan       = "...bbb/...bcb..bb/.bbbbb.bcb/bcbbbybbb/.bbb.bbb/....tbcb/....t.bb/...ttt",
  paint_bucket    = "...ccc/..c...c/.c.....c/.bbbbbbbb/.pprpppc/..rcccc/..rcccc/..cccc",
  empanada        = "....y/....yy/...ytyy/..ytyyyt/.ytyyyytt/ytyyyyttt/tytytytt/..tttt",
  cardboard_box   = "....tt/..ttyytt/ttyyttyytt/tyytttttyt/.ttytyttt/.ttyyyttt/..ttyytt/...tttt",
  robot_vacuum    = ".......... /...ccccc/..cwbccc/.ccccccct/.ctttttt/..ttttt",
  giant_anvil     = "........./.cccccccc/..ccctttt/...tttt/....tt/....tt/...cccc/..tttttt",
  soap_bubbles    = "......bb/.....bwwb/......bb/..bbb/...wwbb..b/.bwwccb.bwb/.bccccb..b/..bbbb",
  vip_stamp       = "....tt/..tttttt/..tyyytt/...tttt/....tt/...tttt/..rrrrrr/.rppppppr",
}
local mysteryTile = "....b/...bwb/..bwcbb/.bwccbbb/.bbccbbb/..bbbbb/...bbb/....b"
local gagInk = {
  w={0.97,0.98,1}, c={0.53,0.65,0.74}, b={0.26,0.68,0.93}, y={1,0.86,0.36},
  r={0.85,0.25,0.28}, p={1,0.60,0.68}, g={0.24,0.61,0.32}, l={0.63,0.84,0.36}, t={0.58,0.36,0.23},
}

local function makeGagTile(pattern)
  local data = love.image.newImageData(64, 64)
  local y = 11
  for row in pattern:gmatch("[^/]+") do
    for x = 1, #row do
      local ink = gagInk[row:sub(x, x)]
      if ink then fillRect(data, 64, 64, 7+x*4, y, 4, 4, unpack(ink)) end
    end
    y = y + 4
  end
  applyOutline(data, 0, 0, 64, 64, 0.10, 0.13, 0.20)
  return {diff=newPixelImage(data, false), isPlaceholder=true}
end

local function makeBodoquePlaceholder()
  local w, h = 44, 64
  local data = love.image.newImageData(w, h)
  -- Match the drop-in sprite's centered feet and transparent margins.
  fillEllipse(data, w, h, 16, 57, 6, 5, 0.24, 0.12, 0.14)
  fillEllipse(data, w, h, 28, 57, 6, 5, 0.24, 0.12, 0.14)
  fillEllipse(data, w, h, 22, 48, 15, 10, 0.39, 0.33, 0.31)
  for y = 43, 54, 4 do
    fillRect(data, w, h, 9, y, 27, 2, 0.77, 0.70, 0.60)
  end
  fillEllipse(data, w, h, 15, 14, 5, 13, 0.63, 0.12, 0.16)
  fillEllipse(data, w, h, 28, 15, 5, 13, 0.72, 0.14, 0.18)
  fillEllipse(data, w, h, 22, 31, 15, 14, 0.75, 0.14, 0.20)
  fillEllipse(data, w, h, 18, 27, 10, 8, 0.85, 0.23, 0.24)
  for x = 15, 27, 12 do
    fillEllipse(data, w, h, x, 28, 3, 3, 0.99, 0.94, 0.84)
    fillEllipse(data, w, h, x - 1, 28, 1.5, 2, 0.12, 0.08, 0.09)
  end
  fillEllipse(data, w, h, 20, 38, 7, 3, 0.31, 0.06, 0.10)
  fillRect(data, w, h, 16, 37, 9, 2, 1.0, 0.73, 0.24)
  fillEllipse(data, w, h, 19, 34, 3, 2, 0.98, 0.57, 0.17)
  applyOutline(data, 0, 0, w, h, 0.19, 0.07, 0.10)
  return { diff = newPixelImage(data, false), isPlaceholder = true }
end

function AssetLoader.loadAll(encountersList)
  local realCount = 0
  local placeholderCount = 0
  local customCount = 0

  local function trackPair(pair)
    if pair.isPlaceholder then
      placeholderCount = placeholderCount + 1
    else
      realCount = realCount + 1
      if pair.isCustom then
        customCount = customCount + 1
      end
    end
    return pair
  end

  local function loadDropIn(name, basePath, repeatWrap)
    local pair = AssetLoader.loadSpritePair("assets/custom/" .. name, repeatWrap)
    if pair then
      pair.isCustom = true
      return pair
    end
    return AssetLoader.loadSpritePair(basePath, repeatWrap)
  end

  local assets = {
    tiles = {},
    portraits = {},
    encounters = {},
    gags = {},
    props = {},
  }

  -- 1. Hero Pudú 8-direction sheet (6 cols x 8 rows) + quads
  local pudu = loadDropIn("pudu_8dir_sheet", "assets/sprites/pudu_8dir_sheet", false)
  if not pudu then
    pudu = makePuduPlaceholderSheet()
  end
  assets.pudu = trackPair(pudu)
  assets.puduQuads = AssetLoader.buildQuads(assets.pudu.diff, 6, 8)

  -- 2. Wizard hat gag
  local wizardHat = loadDropIn("pudu_wizard_hat", "assets/sprites/gags/pudu_wizard_hat", false)
  if not wizardHat then
    wizardHat = makeWizardHatPlaceholder()
  end
  assets.wizardHat = trackPair(wizardHat)
  assets.gags.pudu_wizard_hat = assets.wizardHat
  assets.mysterySummon = makeGagTile(mysteryTile)
  local rules = require("json").decode(assert(love.filesystem.read("battle_rules.json")))
  for id in pairs(rules.sprites) do
    local pattern = gagTiles[id]
    local folder = pattern and "assets/sprites/gags/" or "assets/sprites/"
    local pair = loadDropIn(id, folder .. id, false)
    pair = pair or (pattern and makeGagTile(pattern)) or assets.mysterySummon
    local group = pattern and assets.gags or assets.props
    group[id] = trackPair(pair)
  end

  -- 3. 5 seamlessly tileable biome floor tiles
  for i = 1, #TILE_NAMES do
    local name = TILE_NAMES[i]
    local tile = loadDropIn(name, "assets/tiles/" .. name, true)
    if not tile then
      tile = makeBiomeTilePlaceholder(name)
    end
    assets.tiles[name] = trackPair(tile)
  end

  -- Scenery is independent of the battle summon catalog.
  local scenery = {
    "ancient_tree", "apacheta_sundial", "araucaria_tree", "biome_arch", "calafate_bush", "caleuche_ship",
    "coast_lighthouse", "copihue", "debris_pile", "desert_cactus", "lantern_post",
    "lily_pad", "moai_relic", "mossy_boulder", "mossy_log", "mountain_crystal",
    "orb_shrine", "pincoya_shrine", "quena_monolith", "rewe_totem", "rock_monolith",
    "stone_pedestal", "textile_bale", "valdivian_fern", "valdivian_shrub",
  }
  assets.scenery = {}
  for _, name in ipairs(scenery) do
    local pair = loadDropIn(name, "assets/sprites/props/" .. name, false)
    if pair then assets.scenery[name] = trackPair(pair) end
  end

  local bodoque = loadDropIn("bodoque", "assets/sprites/npcs/bodoque", false)
  assets.bodoque = trackPair(bodoque or makeBodoquePlaceholder())

  -- 4. Radial soft light halo (linear filter)
  local lightRadial = AssetLoader.loadImageRaw("assets/sprites/light_radial.png", false, "linear")
  if lightRadial then
    realCount = realCount + 1
  else
    lightRadial = makeLightRadialPlaceholder()
    placeholderCount = placeholderCount + 1
  end
  assets.lightRadial = lightRadial

  -- 5. HUD Pudú portraits (happy, shocked, angry)
  for i = 1, #PORTRAIT_MOODS do
    local mood = PORTRAIT_MOODS[i]
    local img = AssetLoader.loadImageRaw("assets/ui/portraits/pudu_" .. mood .. ".png", false, "nearest")
    if img then
      realCount = realCount + 1
    else
      img = makePortraitPlaceholder(mood)
      placeholderCount = placeholderCount + 1
    end
    assets.portraits[mood] = img
  end

  -- 6. Encounters (priority: assets/custom/<id> -> enc.spritePath/enc.sprite -> assets/sprites/encounters/<id> -> placeholder)
  if type(encountersList) == "table" then
    for i, enc in ipairs(encountersList) do
      local id = enc and enc.id
      if type(id) == "string" and id ~= "" then
        local pair = AssetLoader.loadSpritePair("assets/custom/" .. id, false, "nearest")
        if pair then
          pair.isCustom = true
        else
          local configuredPath = enc.spritePath or enc.sprite
          if type(configuredPath) == "string" and configuredPath ~= "" then
            pair = AssetLoader.loadSpritePair(configuredPath, false, "nearest")
          end
          if not pair then
            local canonicalPath = "assets/sprites/encounters/" .. id
            local cfgStem = type(configuredPath) == "string" and normalizeRelPath(configuredPath):gsub("%.[pP][nN][gG]$", "") or ""
            if cfgStem ~= canonicalPath then
              pair = AssetLoader.loadSpritePair(canonicalPath, false, "nearest")
            end
          end
        end

        if not pair then
          pair = AssetLoader.makeEncounterPlaceholder(id, i, enc.color)
        elseif enc.isSheet then
          local cols = enc.sheetCols or 4
          local rows = enc.sheetRows or 2
          local iw, ih = pair.diff:getDimensions()
          if not pair.isCustom or (ih > 0 and (iw / ih) >= 1.5) then
            pair.quads = AssetLoader.buildQuads(pair.diff, cols, rows)
            pair.isSheet = true
          end
        end

        assets.encounters[id] = trackPair(pair)
      end
    end
  end

  -- 7. Summary stats & asset mode ("A" = all real, "A+B" = mixed, "B" = all placeholder)
  local mode
  if realCount > 0 and placeholderCount == 0 then
    mode = "A"
  elseif realCount > 0 and placeholderCount > 0 then
    mode = "A+B"
  else
    mode = "B"
  end

  assets.stats = {
    realCount = realCount,
    placeholderCount = placeholderCount,
    customCount = customCount,
    mode = mode,
  }

  return assets
end

return AssetLoader
