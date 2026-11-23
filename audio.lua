-- audio.lua — Sample-accurate music clock and safe SFX manager for Pudu Fantasy (LOVE2D 11.5)

local Audio = {}
Audio.__index = Audio

Audio.TRACK_META = {
    user_battle = {
        path = "assets/audio/battle_user_main.wav",
        bpm = 139.20,
        beats = 37,
        beatOffset = 0.342,
        loop = true,
    },
    overworld = {
        path = "assets/audio/battle_overworld_lyria.ogg",
        bpm = 116.04,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    superstar = {
        path = "assets/audio/battle_superstar_lyria.ogg",
        bpm = 132.01,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    boss = {
        path = "assets/audio/battle_boss_lyria.ogg",
        bpm = 141.16,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    plaza = {
        path = "assets/audio/battle_plaza_lyria.ogg",
        bpm = 120.00,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    victory = {
        path = "assets/audio/battle_victory_lyria.ogg",
        bpm = 136.84,
        beats = 32,
        beatOffset = 0.0,
        loop = false,
    },
}

Audio.SFX_FILES = {
    sfx_encounter_start = "assets/audio/sfx_encounter_start.wav",
    sfx_rain_pour       = "assets/audio/sfx_rain_pour.wav",
    sfx_splat           = "assets/audio/sfx_splat.wav",
    sfx_boing           = "assets/audio/sfx_boing.wav",
    sfx_laugh           = "assets/audio/sfx_laugh.wav",
    sfx_camera_flash    = "assets/audio/sfx_camera_flash.wav",
    sfx_horn            = "assets/audio/sfx_horn.wav",
    sfx_rimshot         = "assets/audio/sfx_rimshot.wav",
    sfx_meow_scared     = "assets/audio/sfx_meow_scared.wav",
    sfx_seagull         = "assets/audio/sfx_seagull.wav",
    sfx_cry_wah         = "assets/audio/sfx_cry_wah.wav",
    water_rush          = "assets/audio/water_rush.wav",
    bash_impact         = "assets/audio/bash_impact.wav",
    stomp               = "assets/audio/stomp.wav",
    dog_bark            = "assets/audio/dog_bark.wav",
    chime_1             = "assets/audio/chime_1.wav",
    heal                = "assets/audio/heal.wav",
    puma_growl          = "assets/audio/puma_growl.wav",
    hurt                = "assets/audio/hurt.wav",
}

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

local function loadStaticSource(path)
    if not (love and love.filesystem and love.audio) then
        return nil
    end
    local info = love.filesystem.getInfo(path)
    if not info or info.type == "directory" then
        return nil
    end
    local ok, src = pcall(love.audio.newSource, path, "static")
    if not ok or not src then
        return nil
    end
    return src
end

function Audio.new(muted)
    local self = setmetatable({
        muted = muted and true or false,
        musicEnabled = true,
        musicVolume = 0.52,
        sfxVolume = 0.80,
        tracks = {},
        trackDurations = {},
        sfx = {},
        missing = {},
        currentTrackId = nil,
        currentTrack = nil,
        trackPaused = false,
        loadedTrackCount = 0,
        totalTrackCount = 0,
        loadedSfxCount = 0,
        totalSfxCount = 0,
    }, Audio)

    for trackId, meta in pairs(Audio.TRACK_META) do
        self.totalTrackCount = self.totalTrackCount + 1
        local src = loadStaticSource(meta.path)
        if src then
            pcall(src.setLooping, src, meta.loop and true or false)
            pcall(src.setVolume, src, 0.0)
            local okDur, dur = pcall(src.getDuration, src, "seconds")
            self.tracks[trackId] = src
            self.trackDurations[trackId] = (okDur and tonumber(dur)) or 0.0
            self.loadedTrackCount = self.loadedTrackCount + 1
        else
            self.missing[#self.missing + 1] = meta.path
        end
    end

    for sfxId, path in pairs(Audio.SFX_FILES) do
        self.totalSfxCount = self.totalSfxCount + 1
        local src = loadStaticSource(path)
        if src then
            self.sfx[sfxId] = src
            self.loadedSfxCount = self.loadedSfxCount + 1
        else
            self.missing[#self.missing + 1] = path
        end
    end

    table.sort(self.missing)
    return self
end

function Audio:_effectiveMusicVolume()
    if self.muted or not self.musicEnabled then
        return 0.0
    end
    return self.musicVolume
end

function Audio:_syncMusicVolume()
    if self.currentTrack then
        pcall(self.currentTrack.setVolume, self.currentTrack, self:_effectiveMusicVolume())
    end
end

function Audio:playTrack(trackId, restartIfSame)
    local meta = Audio.TRACK_META[trackId]
    if not meta then
        return false
    end

    local src = self.tracks[trackId]

    if self.currentTrackId == trackId and not restartIfSame then
        if src then
            self:_syncMusicVolume()
            if not self.trackPaused then
                local okPlay, isPlaying = pcall(src.isPlaying, src)
                if not (okPlay and isPlaying) and meta.loop then
                    pcall(src.play, src)
                end
            end
            return true
        end
        return false
    end

    if self.currentTrack then
        pcall(self.currentTrack.stop, self.currentTrack)
    end

    self.currentTrackId = trackId
    self.currentTrack = src
    self.trackPaused = false

    if src then
        pcall(src.stop, src)
        pcall(src.setLooping, src, meta.loop and true or false)
        pcall(src.setVolume, src, self:_effectiveMusicVolume())
        -- Always play even at volume 0.0 when muted so source:tell("seconds") stays locked to BPM.
        pcall(src.play, src)
        return true
    end

    return false
end

function Audio:getTrackState()
    local trackId = self.currentTrackId
    local meta = trackId and Audio.TRACK_META[trackId] or nil
    local src = self.currentTrack

    local pos = 0.0
    local duration = 0.0
    local playing = false
    local loaded = false

    if src then
        loaded = true
        local okPos, curPos = pcall(src.tell, src, "seconds")
        if okPos and tonumber(curPos) then
            pos = curPos
        end
        duration = self.trackDurations[trackId] or 0.0
        if duration <= 0.0 then
            local okDur, curDur = pcall(src.getDuration, src, "seconds")
            if okDur and tonumber(curDur) then
                duration = curDur
                self.trackDurations[trackId] = curDur
            end
        end
        local okPlay, isPlaying = pcall(src.isPlaying, src)
        playing = (okPlay and isPlaying) and true or false
    end

    return {
        id = trackId,
        trackId = trackId,
        bpm = meta and meta.bpm or 120.0,
        beats = meta and meta.beats or 64,
        beatOffset = meta and meta.beatOffset or 0.0,
        pos = pos,
        duration = duration,
        playing = playing,
        paused = self.trackPaused,
        loaded = loaded,
    }
end

function Audio:play(sfxId, vol, jitter, pitch)
    if self.muted or not sfxId then
        return false
    end

    local base = self.sfx[sfxId]
    if not base and type(sfxId) == "string" then
        if sfxId:sub(1, 4) == "sfx_" then
            base = self.sfx[sfxId:sub(5)]
        else
            base = self.sfx["sfx_" .. sfxId]
        end
    end
    if not base then
        return false
    end

    local okClone, src = pcall(base.clone, base)
    if not okClone or not src then
        return false
    end

    local effectiveVol = clamp((tonumber(vol) or 1.0) * self.sfxVolume, 0.0, 1.0)
    pcall(src.setVolume, src, effectiveVol)

    local p = tonumber(pitch) or 1.0
    local j = tonumber(jitter) or 0.0
    if j > 0.0 then
        local rnd = (love and love.math and love.math.random) or math.random
        p = p + (rnd() * 2.0 - 1.0) * j
    end
    pcall(src.setPitch, src, clamp(p, 0.25, 4.0))

    local okPlay = pcall(src.play, src)
    return okPlay and true or false
end

function Audio:setTrackPaused(paused)
    local wantPaused = paused and true or false
    self.trackPaused = wantPaused
    if not self.currentTrack then
        return
    end
    if wantPaused then
        pcall(self.currentTrack.pause, self.currentTrack)
    else
        self:_syncMusicVolume()
        pcall(self.currentTrack.play, self.currentTrack)
    end
end

function Audio:setMusicVolume(vol)
    local v = tonumber(vol)
    if not v then
        return
    end
    self.musicVolume = clamp(v, 0.0, 1.0)
    self:_syncMusicVolume()
end

function Audio:toggleMusic()
    self.musicEnabled = not self.musicEnabled
    -- Keep source running at volume 0.0 when disabled so beat_sync stays locked.
    self:_syncMusicVolume()
    return self.musicEnabled
end

function Audio:toggleMute()
    self.muted = not self.muted
    -- Keep music source running at volume 0.0 when muted so beat_sync stays locked.
    self:_syncMusicVolume()
    return self.muted
end

function Audio:stopAll()
    if love and love.audio then
        pcall(love.audio.stop)
    end
    for _, src in pairs(self.tracks) do
        pcall(src.stop, src)
    end
    self.currentTrack = nil
    self.currentTrackId = nil
    self.trackPaused = false
end

function Audio:getStats()
    return {
        loadedTracks = self.loadedTrackCount,
        totalTracks = self.totalTrackCount,
        loadedSfx = self.loadedSfxCount,
        totalSfx = self.totalSfxCount,
        missingCount = #self.missing,
        muted = self.muted,
        musicEnabled = self.musicEnabled,
    }
end

return Audio
