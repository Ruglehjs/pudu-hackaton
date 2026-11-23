local http = require("worker_http")
local inbox = love.thread.getChannel("sprite_in")
local outbox = love.thread.getChannel("sprite_out")

while true do
    local message = inbox:demand()
    if message.cmd == "quit" then break end
    if message.cmd == "generate" then
        local start = http.now()
        local result = http.request("/sprite", {
            name = message.name, original_prompt = message.original_prompt, live_sprite = true,
        }, 28) or {}
        local images = type(result.diff_b64) == "string" and type(result.norm_b64) == "string"
        local ok = result.ok == true and images and result.sprite_mode == "generate_live"
        outbox:push({
            kind = "sprite_ready", uid = message.uid, name = message.name,
            ok = ok, cached = result.cached == true, width = result.width, height = result.height,
            diff_b64 = result.diff_b64, norm_b64 = result.norm_b64,
            latency_ms = math.floor((http.now() - start) * 1000 + 0.5),
            error = not ok and (result.error or "Sprite en vivo no disponible.") or nil,
        })
    end
end
