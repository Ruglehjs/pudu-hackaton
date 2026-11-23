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

local STRIDE_COLS = { 2, 3, 4, 5 }
local WALK_COLS = { 2, 3, 4, 3 }

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

    -- Buoyant airborne hop window [0.22, 0.94]
    if p >= 0.22 and p <= 0.94 then
        local hT = (p - 0.22) / 0.72
        local arc = sin(hT * PI)
        local buoyant = arc * (1.14 - 0.14 * arc)
        jumpY = -hop * buoyant
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

function BeatSync:getPuduDancePose(mode, facingDirOverride)
    local p = self.beatPhase
    local bar = self.barBeat
    local bf = self.beatFloat
    local t = self.time
    local animMode = mode or "battle_idle"

    if animMode == "battle_enter" then
        local row = normalizeRow(facingDirOverride, 2)
        local col = STRIDE_COLS[(floor(t * 12.0) % 4) + 1]
        local trotSin = sin(t * 13.5)
        local trotWave = abs(trotSin)
        local jumpY = -trotWave * 11.5
        local tilt = 0.09 + trotSin * 0.03
        local scaleX = 1.05 - 0.08 * trotWave
        local scaleY = 0.95 + 0.09 * trotWave
        local hatOffsetY = -1.5 - abs(sin(t * 13.5 - 0.5)) * 3.8
        local hatTilt = -0.14 - sin(t * 13.5 - 0.4) * 0.07

        return {
            row = row,
            col = col,
            scaleX = scaleX,
            scaleY = scaleY,
            jumpY = jumpY,
            tilt = tilt,
            stepX = 0.0,
            stepY = 0.0,
            hatOffsetY = hatOffsetY,
            hatTilt = hatTilt,
            noteSparkle = false,
        }
    end

    if animMode == "walk" then
        local row = normalizeRow(facingDirOverride, 3)
        local walkCycle = t * 8.5
        local col = WALK_COLS[(floor(walkCycle) % 4) + 1]
        local stepSin = sin(walkCycle * PI * 0.5)
        local stepArc = abs(stepSin)
        local jumpY = -stepArc * 3.8
        local scaleX = 1.0 + (1.0 - stepArc) * 0.03 - stepArc * 0.02
        local scaleY = 1.0 - (1.0 - stepArc) * 0.03 + stepArc * 0.025
        local tilt = stepSin * 0.035
        local hatOffsetY = -0.6 - abs(sin(walkCycle * PI * 0.5 - 0.45)) * 1.8
        local hatTilt = tilt * 1.15 - 0.03

        return {
            row = row,
            col = col,
            scaleX = scaleX,
            scaleY = scaleY,
            jumpY = jumpY,
            tilt = tilt,
            stepX = 0.0,
            stepY = 0.0,
            hatOffsetY = hatOffsetY,
            hatTilt = hatTilt,
            noteSparkle = false,
        }
    end

    if animMode == "overworld_idle" then
        local row = normalizeRow(facingDirOverride, 0)
        local breathe = sin(t * 2.6)
        local sway = sin(t * 1.3)
        local tilt = sway * 0.012
        local hatOffsetY = -0.4 - breathe * 0.85
        local hatTilt = tilt * 1.2 + sin(t * 1.3 - 0.3) * 0.015

        return {
            row = row,
            col = 1,
            scaleX = 1.0 - breathe * 0.018,
            scaleY = 1.0 + breathe * 0.024,
            jumpY = 0.0,
            tilt = tilt,
            stepX = 0.0,
            stepY = 0.0,
            hatOffsetY = hatOffsetY,
            hatTilt = hatTilt,
            noteSparkle = false,
        }
    end

    if animMode == "victory" then
        local defaultRow = (bar % 2 == 0) and 0 or 1
        local row = normalizeRow(facingDirOverride, defaultRow)
        local scaleX, scaleY, jumpY, hopWeight
        local col
        local tilt

        if bar == 0 or bar == 2 then
            local subP = (p * 2.0) % 1.0
            scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(subP, 0.11, 0.12, 14.0)
            col = (hopWeight > 0.35) and 5 or 1
            tilt = ((bar == 0) and 0.09 or -0.09) * sin(p * PI)
        else
            scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(p, 0.12, 0.13, 21.0)
            col = (hopWeight > 0.25) and 5 or 1
            tilt = 0.11 * sin(p * TWO_PI)
        end

        local lagSin = sin((p - 0.40) * TWO_PI)
        local hatOffsetY = -1.8 * hopWeight - (3.2 + 1.4 * hopWeight) * lagSin
        local hatTilt = tilt * 1.45 + sin((bf - 0.16) * PI) * 0.09

        return {
            row = row,
            col = col,
            scaleX = scaleX,
            scaleY = scaleY,
            jumpY = jumpY,
            tilt = tilt,
            stepX = sin(bf * PI) * 4.0,
            stepY = 0.0,
            hatOffsetY = hatOffsetY,
            hatTilt = hatTilt,
            noteSparkle = false,
        }
    end

    if animMode == "hurt" then
        local row = normalizeRow(facingDirOverride, 1)
        local shake = sin(t * 42.0)

        return {
            row = row,
            col = 1,
            scaleX = 1.14 + shake * 0.03,
            scaleY = 0.86 - shake * 0.03,
            jumpY = -3.0 * abs(sin(t * 18.0)),
            tilt = -0.16 + shake * 0.04,
            stepX = -6.0 + shake * 3.5,
            stepY = 0.0,
            hatOffsetY = -5.5 - abs(shake) * 2.5,
            hatTilt = -0.26 + shake * 0.08,
            noteSparkle = false,
        }
    end

    if animMode == "cast" or animMode == "ritual" then
        local row = normalizeRow(facingDirOverride, 2)
        local pulse = self.beatPulse
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
    local baseRow = normalizeRow(facingDirOverride, 1)
    local inten = 1.0
    local row = baseRow
    local col = 1
    local scaleX, scaleY, jumpY, hopWeight
    local tilt = 0.0
    local stepX = 0.0
    local stepY = 0.0

    if bar == 0 then
        scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(p, 0.10, 0.11, 11.0)
        tilt = 0.065 * sin(p * PI)
        stepX = 4.5 * sin(p * PI)
        col = (p < 0.52) and 2 or 3
        row = baseRow
    elseif bar == 1 then
        scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(p, 0.085, 0.095, 10.5)
        tilt = -0.075 * sin(p * PI)
        stepX = -4.0 * sin(p * PI)
        row = (p >= 0.24 and p <= 0.78) and 2 or baseRow
        col = 4
    elseif bar == 2 then
        scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(p, 0.105, 0.115, 13.0)
        tilt = 0.060 * sin(p * PI)
        stepX = 5.0 * sin(p * PI)
        col = (p < 0.48) and 2 or 3
        row = baseRow
    else -- bar == 3: flourish hop with air tuck
        scaleX, scaleY, jumpY, hopWeight = evalBeatBounceCore(p, 0.115, 0.125, 18.0)
        tilt = 0.085 * sin(p * TWO_PI)
        stepX = 0.0
        col = (p < 0.24) and 1 or ((p < 0.76) and 5 or 1)
        row = baseRow
    end

    -- Wizard hat elastic follow-through physics
    local lagSin = sin((p - 0.42) * TWO_PI)
    local hatOffsetY = (-0.85 * hopWeight - (2.55 + 0.95 * hopWeight) * lagSin) * inten
    local hatTilt = tilt * 1.35 + sin((bf - 0.18) * PI) * 0.065 * inten

    return {
        row = row,
        col = col,
        scaleX = scaleX,
        scaleY = scaleY,
        jumpY = jumpY,
        tilt = tilt,
        stepX = stepX,
        stepY = stepY,
        hatOffsetY = hatOffsetY,
        hatTilt = hatTilt,
        noteSparkle = false,
    }
end

--------------------------------------------------------------------------------
-- Enemy Counterpoint Groove & Stylized Reactions
--------------------------------------------------------------------------------

function BeatSync:getEnemyGroove(reaction)
    local bf = self.beatFloat
    local t = self.time
    local r = reaction or "idle"

    if r == "crying" then
        local sob = abs(sin(t * 7.5))
        local sx = 1.04 + sob * 0.04
        local sy = 0.93 - sob * 0.05
        return {
            offsetX = sin(t * 28.0) * 1.8,
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
            offsetX = sin(t * 45.0) * 2.6,
            offsetY = -stomp * 5.0,
            scaleX = sx,
            scaleY = sy,
            tilt = -0.05 + sin(t * 22.0) * 0.045,
            squash = sx - 1.0,
        }
    end

    if r == "shocked" then
        local jolt = abs(sin(t * 18.0))
        local sx = 0.90 + sin(t * 40.0) * 0.04
        local sy = 1.14 - sin(t * 40.0) * 0.04
        return {
            offsetX = sin(t * 58.0) * 4.5,
            offsetY = -9.0 - jolt * 5.0,
            scaleX = sx,
            scaleY = sy,
            tilt = sin(t * 52.0) * 0.10,
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
        local chatter = (sin(t * 3.5) > 0.3) and sin(t * 60.0) or 0.0
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
        local shiver = sin(t * 34.0)
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
        local trem = sin(t * 48.0)
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
