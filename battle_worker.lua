if not love.filesystem then require("love.filesystem") end
local Judge = require("battle_judge")
local http = require("worker_http")
local inbox = love.thread.getChannel("battle_in")
local outbox = love.thread.getChannel("battle_out")
local retryAfter = 0

local function contact(path, payload, timeout)
    if http.now() < retryAfter then return nil end
    local response = http.request(path, payload, timeout)
    if not response then retryAfter = http.now() + 20 end
    return response
end

while true do
    local message = inbox:demand()
    local cmd = message.cmd
    if cmd == "quit" then break end
    local uid = message.uid or message.id
    if cmd == "health" then
        local info = not message.mock_mode and contact("/health", nil, 1) or nil
        local online = info and info.ok == true or false
        outbox:push({kind = "health", uid = uid, id = uid, ok = online, info = info or {}, source = online and info.provider or "lua"})
    elseif cmd == "prompt" then
        local start = http.now()
        local prompt, encounter = message.prompt, message.encounter or {}
        local response
        if not message.mock_mode then
            response = contact("/battle_prompt", {prompt = prompt, encounter = encounter, mock_mode = false}, 15)
        end
        local result = response and response.ok ~= false and (response.result or response)
        local online = type(result) == "table" and type(result.approved) == "boolean"
        local resolved = online and Judge.ensureResultCoherence(result, prompt, encounter)
            or Judge.standaloneLuaEvaluate(prompt, encounter)
        outbox:push({
            kind = "prompt_result", uid = uid, id = uid, ok = true,
            result = resolved, source = online and (response.source or "python") or "lua",
            latency_ms = math.floor((http.now() - start) * 1000 + 0.5),
        })
    end
end
