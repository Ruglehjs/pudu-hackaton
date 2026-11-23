-- Local transport shared by the two independent thread VMs.
local json = require("json")
local hasHttp, http = pcall(require, "socket.http")
local hasFilters, ltn12 = pcall(require, "ltn12")
local hasSocket, socket = pcall(require, "socket")
local port = tonumber(os.getenv("PUDU_BATTLE_PORT")) or 18425
local base = "http://127.0.0.1:" .. port
local Transport = {}
Transport.now = hasSocket and socket.gettime or os.clock

-- LuaSocket normally uses its HTTP read timeout for connect too. On Windows
-- even a refused localhost connection can otherwise hold the turn for ~2 s.
local function localConnection(readTimeout)
    local tcp, err = socket.tcp()
    if not tcp then return nil, err end
    local connection = {}
    function connection:connect(host, targetPort)
        tcp:settimeout(0.15)
        local ok, reason = tcp:connect(host, targetPort)
        tcp:settimeout(readTimeout)
        return ok, reason
    end
    -- Bind the remaining socket methods to their native userdata receiver.
    return setmetatable(connection, {__index = function(_, key)
        local method = tcp[key]
        if method then return function(_, ...) return method(tcp, ...) end end
    end})
end

function Transport.request(path, payload, timeout)
    if not hasHttp or not hasFilters or not hasSocket then return nil end
    local chunks = {}
    local request = {
        method = payload and "POST" or "GET",
        url = base .. path,
        headers = {connection = "close"},
        redirect = false,
        create = function() return localConnection(timeout) end,
        sink = ltn12.sink.table(chunks),
    }
    if payload then
        local data = json.encode(payload)
        request.source = ltn12.source.string(data)
        request.headers["content-type"] = "application/json"
        request.headers["content-length"] = #data
    end
    http.TIMEOUT = timeout
    local ok, sent, status = pcall(http.request, request)
    if not ok or not sent or tonumber(status) ~= 200 then return nil end
    local decoded, body = pcall(json.decode, table.concat(chunks))
    if decoded and type(body) == "table" then return body end
end
return Transport
