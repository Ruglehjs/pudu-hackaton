-- beat_sync.lua — Jitter-free PLL musical clock, Superstar Saga idle choreography,
-- wizard hat spring physics, and enemy counterpoint groove for Pudu Fantasy (LOVE2D 11.5).
--
-- Strict design rules (AGENTS.md R8):
--   * ZERO floating music notes (noteSparkle is ALWAYS false in every pose and mode).
--   * ZERO rhythm-game timing windows, scoring, or "Dance" buttons.
--   * Identical smooth behavior in Modo A (live WAV/OGG via audio:getTrackState())
--     and Modo B (autonomous metronome fallback at 139.20 BPM).

local BeatSync = {}
BeatSync.__index = BeatSync

local DEFAULT_BPM = 139.20
local PI = math.pi
local TWO_PI = math.pi * 2.0
local sin = math.sin
local cos = math.cos
local abs = math.abs
local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

local WALK_COLS = { 3, 4, 5, 4 }
local PUDU_POSE_FIELDS = { "scaleX", "scaleY", "jumpY", "tilt", "stepX", "stepY", "hatOffsetY", "hatTilt" }
local ENEMY_POSE_FIELDS = { "offsetX", "offsetY", "scaleX", "scaleY", "tilt", "squash" }

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

local function normalizeRow(dirOverride, fallbackRow)
    if dirOverride == nil then
        return fallbackRow
    end
    local n = tonumber(dirOverride)
    if not n then
        return fallbackRow
    end
    return floor(n) % 8
end

local function resolveValidBpm(val)
    local n = tonumber(val)
    if n and n > 20.0 then
        return n
    end
    return nil
end

local function blendPose(state, kind, pose, fields, time, duration)
    if state.kind ~= kind then
        state.from = state.pose
        state.started = time
        state.kind = kind
    end
    if state.from then
        local progress = clamp((time - state.started) / duration, 0.0, 1.0)
        if progress >= 1.0 then
            state.from = nil
        else
            local weight = progress * progress * (3.0 - 2.0 * progress)
            for _, field in ipairs(fields) do
                local start = state.from[field]
                pose[field] = start + (pose[field] - start) * weight
            end
        end
    end
    state.pose = pose
    return pose
end

--------------------------------------------------------------------------------
-- Constructor & Reset
--------------------------------------------------------------------------------

function BeatSync.new(defaultBpm)
    local self = setmetatable({
        bpm = resolveValidBpm(defaultBpm) or DEFAULT_BPM,
        beatFloat = 0.0,
        beatIndex = 0,
        beatPhase = 0.0,
        barBeat = 0,
        beatPulse = 0.0,
        time = 0.0,
        _lastTrackPos = nil,
        _lastTrackId = nil,
        _loopBeatBase = 0.0,
        _puduPose = {},
        _enemyPose = {},
        trackSynced = false,
    }, BeatSync)
    return self
end

function BeatSync:reset(bpm)
    local validBpm = resolveValidBpm(bpm)
    if validBpm then
        self.bpm = validBpm
    elseif not resolveValidBpm(self.bpm) then
        self.bpm = DEFAULT_BPM
    end

    self.beatFloat = 0.0
    self.beatIndex = 0
    self.beatPhase = 0.0
    self.barBeat = 0
    self.beatPulse = 0.0
    self.time = 0.0
    self._lastTrackPos = nil
    self._lastTrackId = nil
    self._loopBeatBase = 0.0
    self._puduPose = {}
    self._enemyPose = {}
    self.trackSynced = false
end

--------------------------------------------------------------------------------
-- Jitter-Free PLL Update (Modo A track lock + Modo B autonomous metronome)
--------------------------------------------------------------------------------

function BeatSync:update(dt, trackState, manualBpmOverride)
    dt = clamp(tonumber(dt) or 0.0, 0.0, 0.1)
    self.time = self.time + dt

    local hasTrackTable = (type(trackState) == "table")
    local bpm = resolveValidBpm(manualBpmOverride)
        or (hasTrackTable and resolveValidBpm(trackState.bpm))
        or resolveValidBpm(self.bpm)
        or DEFAULT_BPM
    self.bpm = bpm

    local beatsPerSec = bpm / 60.0
    local prevBeatFloat = self.beatFloat
    local predicted = prevBeatFloat + dt * beatsPerSec

    local duration = hasTrackTable and (tonumber(trackState.duration) or 0.0) or 0.0
    local trackPlaying = hasTrackTable and (trackState.playing == true) and (duration > 0.1)

    if trackPlaying then
        local trackPos = tonumber(trackState.pos) or 0.0
        local trackOffset = tonumber(trackState.beatOffset) or 0.0
        local trackId = trackState.id or trackState.trackId
        local rawBeat = max(0.0, (trackPos - trackOffset) * beatsPerSec)
        local snappedInitial = false

        if trackId ~= self._lastTrackId or self._lastTrackPos == nil then
            self._lastTrackId = trackId
            self._lastTrackPos = trackPos
            if prevBeatFloat <= 0.001 then
                self._loopBeatBase = 0.0
                self.beatFloat = rawBeat
                snappedInitial = true
            else
                -- Preserve bar alignment and monotonic continuity without jumping backwards
                self._loopBeatBase = ceil((prevBeatFloat - rawBeat - 0.25) / 4.0) * 4.0
            end
        elseif trackPos < self._lastTrackPos - 0.25 then
            -- Loop wrap detected on the active track
            local metaBeats = tonumber(trackState.beats)
            local loopBeats = (metaBeats and metaBeats > 0.0) and metaBeats or (duration * beatsPerSec)
            self._loopBeatBase = self._loopBeatBase + loopBeats
        end

        self._lastTrackPos = trackPos

        if not snappedInitial then
            local targetBeat = self._loopBeatBase + rawBeat

            -- Guard against huge seeks or audio backend desyncs (> 6 beats away)
            if abs(targetBeat - predicted) > 6.0 then
                self._loopBeatBase = ceil(predicted - rawBeat - 0.25)
                targetBeat = self._loopBeatBase + rawBeat
            end

            local blend = clamp(dt * 12.0, 0.0, 1.0)
            local blended = predicted + (targetBeat - predicted) * blend
            self.beatFloat = max(prevBeatFloat, blended)
        end

        self.trackSynced = true
    else
        if hasTrackTable and trackState.paused then
            self.beatFloat = prevBeatFloat
        else
            self.beatFloat = predicted
        end
        self.trackSynced = false
    end

    self.beatIndex = floor(self.beatFloat)
    self.beatPhase = clamp(self.beatFloat - self.beatIndex, 0.0, 0.999999)
    self.barBeat = self.beatIndex % 4
    self.beatPulse = (1.0 - self.beatPhase) ^ 2.6
end

--------------------------------------------------------------------------------
-- Expressive Squash & Buoyant Bounce Curve
--------------------------------------------------------------------------------

local function evalBeatBounceCore(phase, squashX, squashY, hopHeight)
    local p = clamp(tonumber(phase) or 0.0, 0.0, 1.0)
    local sxAmp = tonumber(squashX) or 0.09
    local syAmp = tonumber(squashY) or 0.10
    local hop = tonumber(hopHeight) or 10.0

    local scaleX = 1.0
    local scaleY = 1.0
    local jumpY = 0.0
    local hopWeight = 0.0

    -- Raised-cosine C1 knee squash window on downbeat [0.0, 0.26)
    if p < 0.26 then
        local u = p / 0.26
        local sq = 0.5 * (1.0 - cos(u * TWO_PI))
        scaleX = 1.0 + sxAmp * sq
        scaleY = 1.0 - syAmp * sq
    end

    -- Keep the takeoff and landing tangent to the ground.
    if p >= 0.22 and p <= 0.92 then
        local hT = clamp((p - 0.22) / 0.70, 0.0, 1.0)
        local arc = sin(hT * PI) ^ 1.5
        jumpY = -hop * arc
        hopWeight = arc
        -- Subtle mid-air vertical stretch during ascent/apex
        scaleX = scaleX - sxAmp * 0.35 * arc
        scaleY = scaleY + syAmp * 0.40 * arc
    end

    return scaleX, scaleY, jumpY, hopWeight
end

-- Supports both BeatSync.evalBeatBounce(phase, sx, sy, hop) and beatSync:evalBeatBounce(...)
function BeatSync.evalBeatBounce(a, b, c, d, e)
    if type(a) == "table" then
        return evalBeatBounceCore(b ~= nil and b or a.beatPhase, c, d, e)
    end
    return evalBeatBounceCore(a, b, c, d)
end

--------------------------------------------------------------------------------
-- Pudu Choreography & Wizard Hat Spring Physics
--------------------------------------------------------------------------------

local function walkFrame(phase)
    return WALK_COLS[(floor(phase + 0.5) % #WALK_COLS) + 1]
end

local function evalStride(phase)
    local step = sin(phase * PI * 0.5)
    local previousStep = sin((phase - 0.32) * PI * 0.5)
    return step, step * step, previousStep * previousStep
end

local function evalHatLift(phase, hopHeight, jumpY)
    local _, _, delayedJumpY = evalBeatBounceCore((phase - 0.09) % 1.0, 0.0, 0.0, hopHeight)
    return clamp((delayedJumpY - jumpY) * 0.36, -2.3, 1.25) - 0.35
end

function BeatSync:getOverworldPuduPose(facingRow, walkPhase, walkWeight)
    local t = self.time
    local breathe = sin(t * 2.75)
    local sway = sin(t * 1.55)
    local earPhase = t % 5.2
    local earFlick = (earPhase > 3.62 and earPhase < 3.76)
        or (earPhase > 3.89 and earPhase < 4.04)
    local step, lift, delayedLift = evalStride(walkPhase + 1.0)
    local settle = walkWeight * walkWeight * (3.0 - 2.0 * walkWeight)
    local idleTilt, walkTilt = sway * 0.028, step * 0.035
    local function between(idle, walk)
        return idle + (walk - idle) * settle
    end

    local col = earFlick and 2 or 1
    if walkWeight >= 0.30 then
        col = walkFrame(walkPhase)
    end
    return {
        row = facingRow,
        col = col,
        scaleX = between(1.0 - breathe * 0.024, 1.024 - 0.038 * lift),
        scaleY = between(1.0 + breathe * 0.042, 0.974 + 0.048 * lift),
        jumpY = -2.4 * lift * settle,
        tilt = between(idleTilt, walkTilt),
        hatOffsetY = between(-0.4 - sin(t * 2.75 - 0.40) * 0.75, (lift - delayedLift) * 1.8 - 0.35),
        hatTilt = between(idleTilt * 1.3 + sin(t * 1.55 - 0.35) * 0.018,
            walkTilt + (lift - delayedLift) * 0.060),
    }
end

local function evaluatePuduPose(self, animMode, facingDirOverride)
    local p = self.beatPhase
    local bar = self.barBeat
    local bf = self.beatFloat
    local t = self.time

    if animMode == "battle_enter" then
        local row = normalizeRow(facingDirOverride, 2)
        local stridePhase = t * 12.0
        local trot, lift, delayedLift = evalStride(stridePhase)
        local tilt = 0.07 + trot * 0.025

        return {
            row = row,
            col = walkFrame(stridePhase),
            scaleX = 1.035 - 0.055 * lift,
            scaleY = 0.965 + 0.065 * lift,
            jumpY = -8.0 * lift,
            tilt = tilt,
            stepX = 0.0,
            stepY = 0.0,
            hatOffsetY = (lift - delayedLift) * 2.8 - 0.7,
            hatTilt = tilt - 0.12 + (lift - delayedLift) * 0.10,
            noteSparkle = false,
        }
    end

    if animMode == "victory" then
        local defaultRow = (bar % 2 == 0) and 0 or 1
        local row = normalizeRow(facingDirOverride, defaultRow)
        local scaleX, scaleY, jumpY, hopWeight
        local hopPhase, hopHeight, tilt

        if bar == 0 or bar == 2 then
            hopPhase, hopHeight = (p * 2.0) % 1.0, 14.0
            scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(hopPhase, 0.11, 0.12, hopHeight)
            tilt = ((bar == 0) and 0.09 or -0.09) * sin(p * PI)
        else
            hopPhase, hopHeight = p, 19.0
            scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(hopPhase, 0.12, 0.13, hopHeight)
            tilt = 0.11 * sin(p * TWO_PI)
        end

        local hatTilt = tilt * 1.25 + sin((bf - 0.16) * PI) * 0.065

        return {
            row = row,
            col = hopWeight > 0.35 and 3 or 1,
            scaleX = scaleX,
            scaleY = scaleY,
            jumpY = jumpY,
            tilt = tilt,
            stepX = sin(bf * PI) * 4.0,
            stepY = 0.0,
            hatOffsetY = evalHatLift(hopPhase, hopHeight, jumpY),
            hatTilt = hatTilt,
            noteSparkle = false,
        }
    end

    if animMode == "hurt" then
        local row = normalizeRow(facingDirOverride, 1)
        local shake = sin(t * 26.0)

        return {
            row = row,
            col = 1,
            scaleX = 1.14 + shake * 0.03,
            scaleY = 0.86 - shake * 0.03,
            jumpY = -3.0 * abs(sin(t * 18.0)),
            tilt = -0.16 + shake * 0.04,
            stepX = -6.0 + shake * 3.5,
            stepY = 0.0,
            hatOffsetY = -1.6 - abs(shake) * 1.4,
            hatTilt = -0.26 + shake * 0.08,
            noteSparkle = false,
        }
    end

    if animMode == "cast" or animMode == "ritual" then
        local row = normalizeRow(facingDirOverride, 2)
        local pulse = 0.5 + 0.5 * cos((p - 0.12) * TWO_PI)
        local sway = sin(bf * PI)
        local ritualLift = (animMode == "ritual") and (1.5 * abs(sway)) or 0.0
        local tilt = 0.07 + 0.03 * sway
        local hatOffsetY = -1.6 * pulse - 1.2 * sin((p - 0.35) * TWO_PI)
        local hatTilt = 0.10 + 0.04 * sway

        return {
            row = row,
            col = 3,
            scaleX = 1.0 - 0.03 * pulse + 0.02 * (1.0 - pulse),
            scaleY = 1.0 + 0.045 * pulse - 0.015 * (1.0 - pulse),
            jumpY = -3.5 * pulse - ritualLift,
            tilt = tilt,
            stepX = 3.0 + 1.5 * pulse,
            stepY = 0.0,
            hatOffsetY = hatOffsetY,
            hatTilt = hatTilt,
            noteSparkle = false,
        }
    end

    -- Default: "battle_idle" (4-beat Mario & Luigi: Superstar Saga idle groove)
    local row = normalizeRow(facingDirOverride, 1)
    local sway = sin(p * PI)
    local squashX, squashY, hopHeight, tilt, stepX
    if bar == 0 then
        squashX, squashY, hopHeight = 0.08, 0.09, 9.0
        tilt, stepX = 0.045 * sway, 3.5 * sway
    elseif bar == 1 then
        squashX, squashY, hopHeight = 0.07, 0.08, 8.0
        tilt, stepX = -0.055 * sway, -3.0 * sway
    elseif bar == 2 then
        squashX, squashY, hopHeight = 0.085, 0.095, 10.5
        tilt, stepX = 0.05 * sway, 4.0 * sway
    else -- bar == 3: flourish hop with air tuck
        squashX, squashY, hopHeight = 0.095, 0.105, 14.5
        tilt, stepX = 0.065 * sin(p * TWO_PI), 0.0
    end

    local scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(p, squashX, squashY, hopHeight)
    local col = hopWeight > 0.42 and 3 or 1
    local hatTilt = tilt * 1.15 + sin((bf - 0.18) * PI) * 0.035

    return {
        row = row,
        col = col,
        scaleX = scaleX,
        scaleY = scaleY,
        jumpY = jumpY,
        tilt = tilt,
        stepX = stepX,
        stepY = 0.0,
        hatOffsetY = evalHatLift(p, hopHeight, jumpY),
        hatTilt = hatTilt,
        noteSparkle = false,
    }
end

function BeatSync:getPuduDancePose(mode, facingDirOverride)
    local animMode = mode or "battle_idle"
    local pose = evaluatePuduPose(self, animMode, facingDirOverride)
    return blendPose(self._puduPose, animMode, pose, PUDU_POSE_FIELDS, self.time, 0.12)
end

--------------------------------------------------------------------------------
-- Enemy Counterpoint Groove & Stylized Reactions
--------------------------------------------------------------------------------

local function evaluateEnemyGroove(self, r)
    local bf = self.beatFloat
    local t = self.time

    if r == "crying" then
        local sob = abs(sin(t * 7.5))
        local sx = 1.04 + sob * 0.04
        local sy = 0.93 - sob * 0.05
        return {
            offsetX = sin(t * 18.0) * 1.5,
            offsetY = 3.0 + sob * 2.5,
            scaleX = sx,
            scaleY = sy,
            tilt = -0.06 + sin(t * 15.0) * 0.03,
            squash = sx - 1.0,
        }
    end

    if r == "laughing" then
        local ha = abs(sin(t * 14.0))
        local sx = 1.08 - ha * 0.06
        local sy = 0.92 + ha * 0.10
        return {
            offsetX = sin(t * 7.0) * 3.0,
            offsetY = -ha * 9.5,
            scaleX = sx,
            scaleY = sy,
            tilt = sin(t * 14.0) * 0.09,
            squash = sx - 1.0,
        }
    end

    if r == "angry" then
        local stomp = abs(sin(t * 10.0))
        local sx = 1.09 - stomp * 0.05
        local sy = 0.94 + stomp * 0.06
        return {
            offsetX = sin(t * 24.0) * 2.0,
            offsetY = -stomp * 5.0,
            scaleX = sx,
            scaleY = sy,
            tilt = -0.05 + sin(t * 22.0) * 0.045,
            squash = sx - 1.0,
        }
    end

    if r == "shocked" then
        local shake = sin(t * 22.0)
        local jolt = shake * shake
        local sx = 0.92 + shake * 0.025
        local sy = 1.12 - shake * 0.025
        return {
            offsetX = shake * 2.8,
            offsetY = -8.0 - jolt * 3.6,
            scaleX = sx,
            scaleY = sy,
            tilt = shake * 0.065,
            squash = sx - 1.0,
        }
    end

    if r == "dizzy" then
        local sway = sin(t * 3.6)
        local sx = 1.0 + sway * 0.04
        local sy = 1.0 - sway * 0.04
        return {
            offsetX = sway * 9.0,
            offsetY = -2.0 + sin(t * 7.2) * 3.0,
            scaleX = sx,
            scaleY = sy,
            tilt = sway * 0.16,
            squash = sx - 1.0,
        }
    end

    if r == "frozen" then
        local chatter = max(0.0, sin(t * 3.5)) ^ 2 * sin(t * 26.0)
        local sx = 0.98
        local sy = 1.02
        return {
            offsetX = chatter * 1.4,
            offsetY = 0.0,
            scaleX = sx,
            scaleY = sy,
            tilt = chatter * 0.02,
            squash = sx - 1.0,
        }
    end

    if r == "wet" then
        local shiver = sin(t * 21.0)
        local sx = 0.95 + abs(shiver) * 0.04
        local sy = 0.96
        return {
            offsetX = shiver * 2.4,
            offsetY = 2.5,
            scaleX = sx,
            scaleY = sy,
            tilt = shiver * 0.055,
            squash = sx - 1.0,
        }
    end

    if r == "scared" then
        local trem = sin(t * 23.0)
        local sx = 0.92 + trem * 0.03
        local sy = 1.05 - trem * 0.03
        return {
            offsetX = 7.0 + trem * 3.2,
            offsetY = -2.0 - abs(sin(t * 12.0)) * 3.5,
            scaleX = sx,
            scaleY = sy,
            tilt = 0.09 + trem * 0.05,
            squash = sx - 1.0,
        }
    end

    if r == "happy_pacified" or r == "happy" or r == "charmed" then
        local sx, sy, jy = evalBeatBounceCore(self.beatPhase, 0.07, 0.075, 9.0)
        return {
            offsetX = sin(bf * PI) * 5.0,
            offsetY = jy,
            scaleX = sx,
            scaleY = sy,
            tilt = sin(bf * PI) * 0.085,
            squash = sx - 1.0,
        }
    end

    if r == "embarrassed" then
        local fidget = sin(t * 9.0)
        local sx = 0.94
        local sy = 0.96
        return {
            offsetX = fidget * 3.5,
            offsetY = 2.0,
            scaleX = sx,
            scaleY = sy,
            tilt = 0.06 + fidget * 0.05,
            squash = sx - 1.0,
        }
    end

    if r == "splatted" then
        local wob = sin(t * 11.0)
        local sx = 1.24 + wob * 0.03
        local sy = 0.72 - wob * 0.02
        return {
            offsetX = wob * 2.0,
            offsetY = 10.0,
            scaleX = sx,
            scaleY = sy,
            tilt = wob * 0.04,
            squash = sx - 1.0,
        }
    end

    if r == "chased" then
        local run = abs(sin(t * 16.0))
        local sx = 1.04 - run * 0.06
        local sy = 0.96 + run * 0.08
        return {
            offsetX = sin(t * 8.0) * 14.0,
            offsetY = -run * 10.5,
            scaleX = sx,
            scaleY = sy,
            tilt = -0.11 + sin(t * 16.0) * 0.07,
            squash = sx - 1.0,
        }
    end

    if r == "confused" or r == "distracted" then
        local look = sin(t * 2.8)
        return {
            offsetX = look * 4.0,
            offsetY = -abs(look) * 2.0,
            scaleX = 1.0,
            scaleY = 1.0,
            tilt = look * 0.13,
            squash = 0.0,
        }
    end

    if r == "sleeping" then
        local snore = sin(t * 2.2)
        local sx = 1.03 - snore * 0.04
        local sy = 0.94 + snore * 0.05
        return {
            offsetX = 0.0,
            offsetY = 3.0 + snore * 1.5,
            scaleX = sx,
            scaleY = sy,
            tilt = 0.11 + snore * 0.03,
            squash = sx - 1.0,
        }
    end

    if r == "defeated" then
        local sx = 1.12
        local sy = 0.80
        return {
            offsetX = 6.0,
            offsetY = 12.0,
            scaleX = sx,
            scaleY = sy,
            tilt = 0.24 + sin(t * 2.5) * 0.02,
            squash = sx - 1.0,
        }
    end

    -- Default: "idle" — antiphase counterpoint against Pudu's beat
    local ep = (self.beatPhase + 0.5) % 1.0
    local sx, sy, jy = evalBeatBounceCore(ep, 0.055, 0.06, 6.8)
    return {
        offsetX = -sin(bf * PI) * 3.0,
        offsetY = jy,
        scaleX = sx,
        scaleY = sy,
        tilt = -sin(bf * PI) * 0.048,
        squash = sx - 1.0,
    }
end

function BeatSync:getEnemyGroove(reaction)
    local kind = reaction or "idle"
    return blendPose(self._enemyPose, kind, evaluateEnemyGroove(self, kind), ENEMY_POSE_FIELDS, self.time, 0.10)
end

--------------------------------------------------------------------------------
-- Convenience Getters
--------------------------------------------------------------------------------

function BeatSync:getBeatPulse()
    return self.beatPulse
end

function BeatSync:getBeatPhase()
    return self.beatPhase
end

function BeatSync:getBarBeat()
    return self.barBeat
end

function BeatSync:getBpm()
    return self.bpm
end

function BeatSync:isTrackSynced()
    return self.trackSynced
end

return BeatSync
