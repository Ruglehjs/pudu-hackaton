-- json.lua
-- Minimal, rock-solid UTF-8 pure-Lua JSON encoder and decoder for LuaJIT / LÖVE2D 11.5.

local json = {
  _version = "1.0.0",
}

local floor = math.floor
local huge = math.huge
local byte = string.byte
local char = string.char
local sub = string.sub
local find = string.find
local format = string.format
local gsub = string.gsub
local concat = table.concat
local sort = table.sort

local MAX_DEPTH = 256
local MAX_SAFE_INT = 9007199254740992 -- 2^53

-- Optional metatable for callers who explicitly want an empty Lua table encoded as "{}"
local object_mt = { __json_type = "object" }
json.object_mt = object_mt

function json.object(tbl)
  return setmetatable(tbl or {}, object_mt)
end

--------------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------------

local ESCAPE_MAP = {
  ['"']  = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function escapeChar(c)
  return ESCAPE_MAP[c] or format("\\u%04x", byte(c))
end

local function encodeString(s)
  return '"' .. gsub(s, '[%z\1-\31\\"]', escapeChar) .. '"'
end

local encodeValue

local function encodeTable(t, stack, depth)
  if depth > MAX_DEPTH then
    error("json.encode: maximum nesting depth exceeded")
  end
  if stack[t] then
    error("json.encode: circular reference detected")
  end

  local count = 0
  local maxIdx = 0
  local hasInt = false
  local hasStr = false

  for k in pairs(t) do
    local kt = type(k)
    if kt == "number" then
      if k >= 1 and floor(k) == k and k ~= huge then
        hasInt = true
        if k > maxIdx then maxIdx = k end
      else
        error("json.encode: invalid numeric table key: " .. tostring(k))
      end
    elseif kt == "string" then
      hasStr = true
    else
      error("json.encode: unsupported table key type: " .. kt)
    end
    count = count + 1
  end

  if count == 0 then
    if getmetatable(t) == object_mt then
      return "{}"
    end
    return "[]"
  end

  if hasInt and hasStr then
    error("json.encode: cannot encode mixed array and object table")
  end

  stack[t] = true
  local out

  if hasInt then
    if maxIdx ~= count then
      stack[t] = nil
      error("json.encode: cannot encode sparse array (max index " .. maxIdx .. ", count " .. count .. ")")
    end
    local items = {}
    for i = 1, count do
      items[i] = encodeValue(t[i], stack, depth + 1)
    end
    out = "[" .. concat(items, ",") .. "]"
  else
    local keys = {}
    local n = 0
    for k in pairs(t) do
      n = n + 1
      keys[n] = k
    end
    sort(keys)
    local items = {}
    for i = 1, n do
      local k = keys[i]
      items[i] = encodeString(k) .. ":" .. encodeValue(t[k], stack, depth + 1)
    end
    out = "{" .. concat(items, ",") .. "}"
  end

  stack[t] = nil
  return out
end

encodeValue = function(val, stack, depth)
  local tv = type(val)
  if tv == "nil" then
    return "null"
  elseif tv == "boolean" then
    return val and "true" or "false"
  elseif tv == "number" then
    if val ~= val or val == huge or val == -huge then
      error("json.encode: cannot encode NaN or Infinity")
    end
    if val == 0 then
      return "0"
    end
    if val >= -MAX_SAFE_INT and val <= MAX_SAFE_INT and floor(val) == val then
      return format("%.0f", val)
    end
    return format("%.14g", val)
  elseif tv == "string" then
    return encodeString(val)
  elseif tv == "table" then
    return encodeTable(val, stack, depth)
  else
    error("json.encode: unsupported value type: " .. tv)
  end
end

function json.encode(val)
  return encodeValue(val, {}, 0)
end

--------------------------------------------------------------------------------
-- Decoder
--------------------------------------------------------------------------------

local function decodeError(str, pos, msg)
  local line = 1
  local col = 1
  local limit = pos - 1
  if limit > #str then limit = #str end
  for i = 1, limit do
    if byte(str, i) == 10 then
      line = line + 1
      col = 1
    else
      col = col + 1
    end
  end
  error(format("json.decode: %s at line %d, col %d", msg, line, col), 0)
end

local function skipWhitespace(str, pos)
  local len = #str
  while pos <= len do
    local b = byte(str, pos)
    if b == 32 or b == 9 or b == 10 or b == 13 then
      pos = pos + 1
    else
      break
    end
  end
  return pos
end

local function codepointToUtf8(cp)
  if cp <= 0x7F then
    return char(cp)
  elseif cp <= 0x7FF then
    return char(
      0xC0 + floor(cp / 0x40),
      0x80 + (cp % 0x40)
    )
  elseif cp <= 0xFFFF then
    return char(
      0xE0 + floor(cp / 0x1000),
      0x80 + (floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  elseif cp <= 0x10FFFF then
    return char(
      0xF0 + floor(cp / 0x40000),
      0x80 + (floor(cp / 0x1000) % 0x40),
      0x80 + (floor(cp / 0x40) % 0x40),
      0x80 + (cp % 0x40)
    )
  end
  return nil
end

local UNESCAPE_MAP = {
  [34]  = '"',  -- \"
  [92]  = '\\', -- \\
  [47]  = '/',  -- \/
  [98]  = '\b', -- \b
  [102] = '\f', -- \f
  [110] = '\n', -- \n
  [114] = '\r', -- \r
  [116] = '\t', -- \t
}

local function parseHex4(str, pos)
  local hex = sub(str, pos, pos + 3)
  if #hex ~= 4 or not find(hex, "^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
    decodeError(str, pos, "invalid \\uXXXX unicode escape")
  end
  return tonumber(hex, 16)
end

local function parseString(str, pos)
  -- pos points at opening '"'
  local startQuote = pos
  pos = pos + 1
  local len = #str
  local parts = {}
  local np = 0
  local chunkStart = pos

  while pos <= len do
    local nextSpecial = find(str, '["\\%z\1-\31]', pos)
    if not nextSpecial then
      decodeError(str, startQuote, "unterminated string")
    end

    local b = byte(str, nextSpecial)
    if b == 34 then -- closing '"'
      if np == 0 then
        return sub(str, chunkStart, nextSpecial - 1), nextSpecial + 1
      end
      if nextSpecial > chunkStart then
        np = np + 1
        parts[np] = sub(str, chunkStart, nextSpecial - 1)
      end
      return concat(parts), nextSpecial + 1
    elseif b == 92 then -- backslash '\'
      if nextSpecial > chunkStart then
        np = np + 1
        parts[np] = sub(str, chunkStart, nextSpecial - 1)
      end
      local escPos = nextSpecial + 1
      if escPos > len then
        decodeError(str, startQuote, "unterminated escape sequence in string")
      end
      local eb = byte(str, escPos)
      local mapped = UNESCAPE_MAP[eb]
      if mapped then
        np = np + 1
        parts[np] = mapped
        pos = escPos + 1
        chunkStart = pos
      elseif eb == 117 then -- 'u'
        local cp = parseHex4(str, escPos + 1)
        pos = escPos + 5
        if cp >= 0xD800 and cp <= 0xDBFF then
          -- UTF-16 high surrogate: must be followed by low surrogate \uDC00..\uDFFF
          if byte(str, pos) ~= 92 or byte(str, pos + 1) ~= 117 then
            decodeError(str, escPos - 1, "unpaired high UTF-16 surrogate")
          end
          local lo = parseHex4(str, pos + 2)
          if lo < 0xDC00 or lo > 0xDFFF then
            decodeError(str, pos, "invalid low UTF-16 surrogate")
          end
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          pos = pos + 6
        elseif cp >= 0xDC00 and cp <= 0xDFFF then
          decodeError(str, escPos - 1, "unpaired low UTF-16 surrogate")
        end
        np = np + 1
        parts[np] = codepointToUtf8(cp)
        chunkStart = pos
      else
        decodeError(str, escPos, "invalid escape character '\\" .. char(eb) .. "'")
      end
    else
      -- Unescaped control character (0x00..0x1F)
      decodeError(str, nextSpecial, format("unescaped control character 0x%02X in string", b))
    end
  end

  decodeError(str, startQuote, "unterminated string")
end

local function parseNumber(str, pos)
  local start = pos
  local len = #str

  -- Optional minus sign
  if byte(str, pos) == 45 then
    pos = pos + 1
    if pos > len then
      decodeError(str, start, "invalid number")
    end
  end

  -- Integer part
  local b = byte(str, pos)
  if b == 48 then -- '0'
    pos = pos + 1
    local nb = byte(str, pos)
    if nb and nb >= 48 and nb <= 57 then
      decodeError(str, start, "leading zeros are not allowed in JSON numbers")
    end
  elseif b and b >= 49 and b <= 57 then -- '1'..'9'
    pos = pos + 1
    while pos <= len do
      local db = byte(str, pos)
      if db >= 48 and db <= 57 then
        pos = pos + 1
      else
        break
      end
    end
  else
    decodeError(str, start, "invalid number")
  end

  -- Fractional part
  if byte(str, pos) == 46 then -- '.'
    pos = pos + 1
    local fracStart = pos
    while pos <= len do
      local db = byte(str, pos)
      if db >= 48 and db <= 57 then
        pos = pos + 1
      else
        break
      end
    end
    if pos == fracStart then
      decodeError(str, pos, "expected digit after decimal point")
    end
  end

  -- Exponent part
  local eb = byte(str, pos)
  if eb == 101 or eb == 69 then -- 'e' or 'E'
    pos = pos + 1
    local sb = byte(str, pos)
    if sb == 43 or sb == 45 then -- '+' or '-'
      pos = pos + 1
    end
    local expStart = pos
    while pos <= len do
      local db = byte(str, pos)
      if db >= 48 and db <= 57 then
        pos = pos + 1
      else
        break
      end
    end
    if pos == expStart then
      decodeError(str, pos, "expected digit in exponent")
    end
  end

  local numStr = sub(str, start, pos - 1)
  local num = tonumber(numStr)
  if not num then
    decodeError(str, start, "invalid number '" .. numStr .. "'")
  end
  return num, pos
end

local parseValue

local function parseArray(str, pos, depth)
  if depth > MAX_DEPTH then
    decodeError(str, pos, "maximum nesting depth exceeded")
  end
  local arr = {}
  pos = skipWhitespace(str, pos + 1)

  if byte(str, pos) == 93 then -- ']'
    return arr, pos + 1
  end

  local idx = 0
  while true do
    local val
    val, pos = parseValue(str, pos, depth + 1)
    idx = idx + 1
    arr[idx] = val

    pos = skipWhitespace(str, pos)
    local b = byte(str, pos)
    if b == 93 then -- ']'
      return arr, pos + 1
    elseif b == 44 then -- ','
      pos = skipWhitespace(str, pos + 1)
      if byte(str, pos) == 93 then
        decodeError(str, pos, "trailing comma in array")
      end
    else
      decodeError(str, pos, "expected ',' or ']' in array")
    end
  end
end

local function parseObject(str, pos, depth)
  if depth > MAX_DEPTH then
    decodeError(str, pos, "maximum nesting depth exceeded")
  end
  local obj = {}
  pos = skipWhitespace(str, pos + 1)

  if byte(str, pos) == 125 then -- '}'
    return obj, pos + 1
  end

  while true do
    if byte(str, pos) ~= 34 then -- '"'
      decodeError(str, pos, "expected string key in object")
    end
    local key
    key, pos = parseString(str, pos)

    pos = skipWhitespace(str, pos)
    if byte(str, pos) ~= 58 then -- ':'
      decodeError(str, pos, "expected ':' after object key")
    end

    pos = skipWhitespace(str, pos + 1)
    local val
    val, pos = parseValue(str, pos, depth + 1)
    obj[key] = val

    pos = skipWhitespace(str, pos)
    local b = byte(str, pos)
    if b == 125 then -- '}'
      return obj, pos + 1
    elseif b == 44 then -- ','
      pos = skipWhitespace(str, pos + 1)
      if byte(str, pos) == 125 then
        decodeError(str, pos, "trailing comma in object")
      end
    else
      decodeError(str, pos, "expected ',' or '}' in object")
    end
  end
end

parseValue = function(str, pos, depth)
  pos = skipWhitespace(str, pos)
  if pos > #str then
    decodeError(str, pos, "unexpected end of input")
  end

  local b = byte(str, pos)
  if b == 123 then -- '{'
    return parseObject(str, pos, depth)
  elseif b == 91 then -- '['
    return parseArray(str, pos, depth)
  elseif b == 34 then -- '"'
    return parseString(str, pos)
  elseif b == 45 or (b >= 48 and b <= 57) then -- '-' or '0'..'9'
    return parseNumber(str, pos)
  elseif b == 116 then -- 't'
    if sub(str, pos, pos + 3) == "true" then
      return true, pos + 4
    end
    decodeError(str, pos, "invalid literal (expected 'true')")
  elseif b == 102 then -- 'f'
    if sub(str, pos, pos + 4) == "false" then
      return false, pos + 5
    end
    decodeError(str, pos, "invalid literal (expected 'false')")
  elseif b == 110 then -- 'n'
    if sub(str, pos, pos + 3) == "null" then
      return nil, pos + 4
    end
    decodeError(str, pos, "invalid literal (expected 'null')")
  else
    decodeError(str, pos, format("unexpected character '%s'", sub(str, pos, pos)))
  end
end

function json.decode(str)
  if type(str) ~= "string" then
    error("json.decode: expected string, got " .. type(str), 2)
  end

  local pos = 1
  -- Ignore optional UTF-8 BOM
  if sub(str, 1, 3) == "\239\187\191" then
    pos = 4
  end

  local val, nextPos = parseValue(str, pos, 0)
  nextPos = skipWhitespace(str, nextPos)
  if nextPos <= #str then
    decodeError(str, nextPos, "trailing characters after JSON value")
  end
  return val
end

return json
