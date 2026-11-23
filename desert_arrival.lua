local DesertArrival = {}
DesertArrival.__index = DesertArrival

local READY_TIME = 0.32
local TOUCHDOWN_TIME = READY_TIME + 0.56
local STRIDE_TIME = TOUCHDOWN_TIME + 0.10
local REST_TIME = STRIDE_TIME + 0.40
local END_TIME = REST_TIME + 0.15
local JUMP_HEIGHT = 13.0 -- Additional lift in world pixels at the midpoint.
local WALK_COLS = { 2, 3, 4, 3 }

function DesertArrival.new(layout, spawnU, spawnV)
    return setmetatable({
        layout = layout,
        spawnU = spawnU,
        spawnV = spawnV,
        elapsed = 0.0,
        done = false,
        u = layout.startU,
        v = layout.startV,
        lift = layout.deckHeight,
        facingRow = 1, -- SE, toward the open tailgate
        col = 1,
        jumpY = 0.0,
        hatOffsetY = 0.0,
        hatTilt = 0.0,
    }, DesertArrival)
end

function DesertArrival:update(dt)
    if self.done then return true end

    self.elapsed = self.elapsed + dt
    local elapsed = self.elapsed
    local layout = self.layout

    if elapsed < READY_TIME then
        local ready = elapsed / READY_TIME
        self.col = ready < 0.60 and 1 or 4
        self.hatTilt = -0.08 * ready * ready
    elseif elapsed < TOUCHDOWN_TIME then
        local air = (elapsed - READY_TIME) / (TOUCHDOWN_TIME - READY_TIME)
        self.u = layout.startU + (layout.finishU - layout.startU) * air
        self.v = layout.startV + (layout.finishV - layout.startV) * air
        self.lift = layout.deckHeight * (1.0 - air * air) + 4.0 * JUMP_HEIGHT * air * (1.0 - air)
        self.col = air < 0.55 and 5 or 6
        self.hatOffsetY = -3.0 * math.sin(math.pi * air)
        self.hatTilt = -0.08 + 0.20 * air
    elseif elapsed < STRIDE_TIME then
        local impact = 1.0 - (elapsed - TOUCHDOWN_TIME) / (STRIDE_TIME - TOUCHDOWN_TIME)
        self.u, self.v = layout.finishU, layout.finishV
        self.lift, self.col = 0.0, 4
        self.hatOffsetY, self.hatTilt = 2.0 * impact, 0.12 * impact
    elseif elapsed < REST_TIME then
        local stride = (elapsed - STRIDE_TIME) / (REST_TIME - STRIDE_TIME)
        local travel = stride * stride * (3.0 - 2.0 * stride)
        local step = math.sin(stride * 2.0 * math.pi)
        self.u = layout.finishU + (self.spawnU - layout.finishU) * travel
        self.v = layout.finishV + (self.spawnV - layout.finishV) * travel
        self.lift, self.facingRow = 0.0, 2 -- E, away from the truck
        self.col = WALK_COLS[math.min(4, math.floor(stride * 4.0) + 1)]
        self.jumpY = -2.4 * math.abs(step)
        self.hatOffsetY, self.hatTilt = self.jumpY * 0.45, 0.035 * step
    else
        self.u, self.v = self.spawnU, self.spawnV
        self.facingRow, self.col = 3, 1 -- NE, toward the trail
        self.lift, self.jumpY = 0.0, 0.0
        self.hatOffsetY, self.hatTilt = 0.0, 0.0
        self.done = elapsed >= END_TIME
    end
    return self.done
end

return DesertArrival
