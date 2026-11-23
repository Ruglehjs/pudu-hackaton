-- audio.lua — Sample-accurate music clock, drop-in audio replacement, and safe SFX manager for Pudu Fantasy (LOVE2D 11.5)

local json = require("json")
local AssetLoader = require("asset_loader")

local Audio = {}
Audio.__index = Audio

Audio.SUPPORTED_EXTENSIONS = { ".ogg", ".wav", ".mp3", ".flac" }
Audio.CUSTOM_AUDIO_DIR = "assets/custom/audio"
Audio.TRACKS_OVERRIDE_PATHS = {
    "assets/custom/audio/tracks.json",
    "assets/audio/tracks.json",
}

Audio.TRACK_META = {
    -- 4 Biome Overworld Themes (8-bit / GBA Superstar Saga style)
    overworld_desierto = {
        path = "assets/audio/bgm_overworld_desierto.wav",
        bpm = 116.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    overworld_costa = {
        path = "assets/audio/bgm_overworld_costa.wav",
        bpm = 124.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    overworld_bosque = {
        path = "assets/audio/bgm_overworld_bosque.wav",
        bpm = 112.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    overworld_chiloe = {
        path = "assets/audio/bgm_overworld_chiloe.wav",
        bpm = 108.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },

    -- 4 Campaign Battle Themes (distinct 8-bit/GBA identity per rival)
    battle_pila_ropa = {
        path = "assets/audio/bgm_battle_pila_ropa.wav",
        bpm = 138.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    battle_gaviota = {
        path = "assets/audio/bgm_battle_gaviota.wav",
        bpm = 132.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    battle_puma = {
        path = "assets/audio/bgm_battle_puma.wav",
        bpm = 142.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    battle_caleuche = {
        path = "assets/audio/bgm_battle_caleuche.wav",
        bpm = 148.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },

    -- Victory & Defeat Jingles
    victory = {
        path = "assets/audio/bgm_victory.wav",
        bpm = 138.0,
        beats = 32,
        beatOffset = 0.0,
        loop = false,
    },
    defeat = {
        path = "assets/audio/bgm_defeat.wav",
        bpm = 104.0,
        beats = 20,
        beatOffset = 0.0,
        loop = false,
    },

    -- Backward-compatible track aliases (share cached Source by file path)
    overworld = {
        path = "assets/audio/bgm_overworld_desierto.wav",
        bpm = 116.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    user_battle = {
        path = "assets/audio/bgm_battle_pila_ropa.wav",
        bpm = 138.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    plaza = {
        path = "assets/audio/bgm_battle_pila_ropa.wav",
        bpm = 138.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    superstar = {
        path = "assets/audio/bgm_battle_gaviota.wav",
        bpm = 132.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
    boss = {
        path = "assets/audio/bgm_battle_caleuche.wav",
        bpm = 148.0,
        beats = 64,
        beatOffset = 0.0,
        loop = true,
    },
}

Audio.BIOME_TRACKS = {
    desierto = "overworld_desierto",
    costa = "overworld_costa",
    bosque = "overworld_bosque",
    chiloe = "overworld_chiloe",
    ciudad = "overworld_chiloe",
}

Audio.BIOME_STEP_SFX = {
    desierto = "sfx_step_sand",
    costa = "sfx_step_wood",
    bosque = "sfx_step_grass",
    chiloe = "sfx_step_wood",
    ciudad = "sfx_step_wood",
}

function Audio.getBiomeTrackId(a, b)
    local biomeId = (type(a) == "table") and b or a
    return Audio.BIOME_TRACKS[biomeId] or "overworld_desierto"
end

function Audio.getBiomeStepSfx(a, b)
    local biomeId = (type(a) == "table") and b or a
    return Audio.BIOME_STEP_SFX[biomeId] or "sfx_step_sand"
end

Audio.SFX_FILES = {
    -- Base 26 SFX
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
    chime_2             = "assets/audio/chime_2.wav",
    chime_3             = "assets/audio/chime_3.wav",
    parry_clash         = "assets/audio/parry_clash.wav",
    rock_fall           = "assets/audio/rock_fall.wav",
    orb_gain            = "assets/audio/orb_gain.wav",
    sfx_spell_miss      = "assets/audio/sfx_spell_miss.wav",
    sfx_spell_unleash   = "assets/audio/sfx_spell_unleash.wav",
    heal                = "assets/audio/heal.wav",
    puma_growl          = "assets/audio/puma_growl.wav",
    hurt                = "assets/audio/hurt.wav",

    -- 8 Elemental Stage State SFX
    sfx_elem_mojado     = "assets/audio/sfx_elem_mojado.wav",
    sfx_elem_congelado  = "assets/audio/sfx_elem_congelado.wav",
    sfx_elem_caliente   = "assets/audio/sfx_elem_caliente.wav",
    sfx_elem_enjabonado = "assets/audio/sfx_elem_enjabonado.wav",
    sfx_elem_aceitoso   = "assets/audio/sfx_elem_aceitoso.wav",
    sfx_elem_oscuro     = "assets/audio/sfx_elem_oscuro.wav",
    sfx_elem_ruidoso    = "assets/audio/sfx_elem_ruidoso.wav",
    sfx_elem_pegajoso   = "assets/audio/sfx_elem_pegajoso.wav",

    -- 6 Super-Combo Signature SFX
    sfx_combo_electro     = "assets/audio/sfx_combo_electro.wav",
    sfx_combo_deep_freeze = "assets/audio/sfx_combo_deep_freeze.wav",
    sfx_combo_steam_sauna = "assets/audio/sfx_combo_steam_sauna.wav",
    sfx_combo_slip_slide  = "assets/audio/sfx_combo_slip_slide.wav",
    sfx_combo_fire_boom   = "assets/audio/sfx_combo_fire_boom.wav",
    sfx_combo_chaos       = "assets/audio/sfx_combo_chaos.wav",

    -- 8 Enemy Counterattack FX
    sfx_counter_tears    = "assets/audio/sfx_counter_tears.wav",
    sfx_counter_flash    = "assets/audio/sfx_counter_flash.wav",
    sfx_counter_splash   = "assets/audio/sfx_counter_splash.wav",
    sfx_counter_wind     = "assets/audio/sfx_counter_wind.wav",
    sfx_counter_mud      = "assets/audio/sfx_counter_mud.wav",
    sfx_counter_stink    = "assets/audio/sfx_counter_stink.wav",
    sfx_counter_music    = "assets/audio/sfx_counter_music.wav",
    sfx_counter_sparkles = "assets/audio/sfx_counter_sparkles.wav",

    -- Combat polish, UI & Overworld exploration SFX
    sfx_crit_hit      = "assets/audio/sfx_crit_hit.wav",
    sfx_prompt_reject = "assets/audio/sfx_prompt_reject.wav",
    sfx_enemy_ko      = "assets/audio/sfx_enemy_ko.wav",
    sfx_battle_enter  = "assets/audio/sfx_battle_enter.wav",
    sfx_ui_click      = "assets/audio/sfx_ui_click.wav",
    sfx_prompt_open   = "assets/audio/sfx_prompt_open.wav",
    sfx_prompt_submit = "assets/audio/sfx_prompt_submit.wav",
    sfx_truck_jump    = "assets/audio/sfx_truck_jump.wav",
    sfx_truck_land    = "assets/audio/sfx_truck_land.wav",
    sfx_step_sand     = "assets/audio/sfx_step_sand.wav",
    sfx_step_wood     = "assets/audio/sfx_step_wood.wav",
    sfx_step_grass    = "assets/audio/sfx_step_grass.wav",
    sfx_camera_pan    = "assets/audio/sfx_camera_pan.wav",
}

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

local function readExternalBytes(relPath)
    if not (AssetLoader and AssetLoader.getExternalBaseDir) then
        return nil
    end
    local baseDir = AssetLoader.getExternalBaseDir()
    if not baseDir or baseDir == "" then
        return nil
    end
    local fullPath = baseDir .. "/" .. relPath
    local okOpen, f = pcall(io.open, fullPath, "rb")
    if not okOpen or not f then
        return nil
    end
    local okRead, bytes = pcall(f.read, f, "*a")
    pcall(f.close, f)
    if okRead and type(bytes) == "string" and #bytes > 0 then
        return bytes
    end
    return nil
end

local function loadStaticSourceExact(path)
    if not (love and love.filesystem and love.audio) or type(path) ~= "string" or path == "" then
        return nil
    end
    -- Prioritize external filesystem so drop-in replacement works even in fused .exe builds (R1)
    local extBytes = readExternalBytes(path)
    if extBytes then
        local fileName = path:match("([^/\\]+)$") or "audio.wav"
        local okData, fileData = pcall(love.filesystem.newFileData, extBytes, fileName)
        if okData and fileData then
            local okSrc, src = pcall(love.audio.newSource, fileData, "static")
            if okSrc and src then
                return src, path
            end
        end
    end
    local info = love.filesystem.getInfo(path)
    if not info or info.type == "directory" then
        return nil
    end
    local ok, src = pcall(love.audio.newSource, path, "static")
    if not ok or not src then
        return nil
    end
    return src, path
end

local function stripExtension(path)
    return (path:gsub("%.[^./\\]+$", ""))
end

local function basenameNoExt(path)
    local file = path:match("([^/\\]+)$") or path
    return stripExtension(file)
end

local function buildCandidatePaths(defaultPath, idHint)
    local candidates = {}
    local seen = {}
    local function add(p)
        if p and p ~= "" and not seen[p] then
            seen[p] = true
            candidates[#candidates + 1] = p
        end
    end

    local stem = basenameNoExt(defaultPath or "")
    -- 1. Drop-in overrides in assets/custom/audio/ by track/sfx ID or filename stem (.ogg, .wav, .mp3, .flac)
    if type(idHint) == "string" and idHint ~= "" then
        for _, ext in ipairs(Audio.SUPPORTED_EXTENSIONS) do
            add(Audio.CUSTOM_AUDIO_DIR .. "/" .. idHint .. ext)
        end
    end
    if stem ~= "" then
        for _, ext in ipairs(Audio.SUPPORTED_EXTENSIONS) do
            add(Audio.CUSTOM_AUDIO_DIR .. "/" .. stem .. ext)
        end
    end

    -- 2. Exact configured path, then alternate extensions in the same folder
    if type(defaultPath) == "string" and defaultPath ~= "" then
        add(defaultPath)
        local baseNoExt = stripExtension(defaultPath)
        for _, ext in ipairs(Audio.SUPPORTED_EXTENSIONS) do
            add(baseNoExt .. ext)
        end
    end

    return candidates
end

local function loadStaticSourceWithDropIn(defaultPath, idHint, cacheByPath)
    local candidates = buildCandidatePaths(defaultPath, idHint)
    for _, candidate in ipairs(candidates) do
        local isCustom = candidate:sub(1, #Audio.CUSTOM_AUDIO_DIR) == Audio.CUSTOM_AUDIO_DIR
        if cacheByPath and cacheByPath[candidate] ~= nil then
            if cacheByPath[candidate] ~= false then
                return cacheByPath[candidate], candidate, isCustom
            end
        else
            local src = loadStaticSourceExact(candidate)
            if cacheByPath then
                cacheByPath[candidate] = src or false
            end
            if src then
                return src, candidate, isCustom
            end
        end
    end
    return nil, defaultPath, false
end

local function readJsonFile(relPath)
    local raw = readExternalBytes(relPath)
    if not raw and love and love.filesystem and love.filesystem.getInfo then
        local okInfo, info = pcall(love.filesystem.getInfo, relPath)
        if okInfo and info and info.type ~= "directory" then
            local okRead, content = pcall(love.filesystem.read, relPath)
            if okRead and type(content) == "string" and #content > 0 then
                raw = content
            end
        end
    end
    if not raw then
        return nil
    end
    local okDec, decoded = pcall(json.decode, raw)
    if okDec and type(decoded) == "table" then
        return decoded
    end
    return nil
end

local function buildTrackMetaWithOverrides()
    local merged = {}
    for trackId, meta in pairs(Audio.TRACK_META) do
        merged[trackId] = {
            path = meta.path,
            bpm = meta.bpm,
            beats = meta.beats,
            beatOffset = meta.beatOffset,
            loop = meta.loop,
        }
    end

    for i = #Audio.TRACKS_OVERRIDE_PATHS, 1, -1 do
        local overrides = readJsonFile(Audio.TRACKS_OVERRIDE_PATHS[i])
        if overrides then
            for trackId, patch in pairs(overrides) do
                if type(trackId) == "string" and type(patch) == "table" then
                    local dst = merged[trackId] or { path = "", bpm = 120.0, beats = 64, beatOffset = 0.0, loop = true }
                    if type(patch.path) == "string" and patch.path ~= "" then dst.path = patch.path end
                    if tonumber(patch.bpm) and tonumber(patch.bpm) > 20 then dst.bpm = tonumber(patch.bpm) end
                    if tonumber(patch.beats) and tonumber(patch.beats) > 0 then dst.beats = tonumber(patch.beats) end
                    if tonumber(patch.beatOffset) ~= nil then dst.beatOffset = tonumber(patch.beatOffset) end
                    if type(patch.loop) == "boolean" then dst.loop = patch.loop end
                    merged[trackId] = dst
                end
            end
        end
    end

    return merged
end

function Audio:_loadAllAssets()
    self.trackMeta = buildTrackMetaWithOverrides()
    self.tracks = {}
    self.trackDurations = {}
    self.trackResolvedPaths = {}
    self.sfx = {}
    self.missing = {}
    self.loadedTrackCount = 0
    self.totalTrackCount = 0
    self.loadedSfxCount = 0
    self.totalSfxCount = 0
    self.customCount = 0

    local loadedTrackByPath = {}
    local durationByPath = {}
    for trackId, meta in pairs(self.trackMeta) do
        self.totalTrackCount = self.totalTrackCount + 1
        local src, resolvedPath, isCustom = loadStaticSourceWithDropIn(meta.path, trackId, loadedTrackByPath)
        if src then
            if durationByPath[resolvedPath] == nil then
                pcall(src.setLooping, src, meta.loop and true or false)
                pcall(src.setVolume, src, 0.0)
                local okDur, dur = pcall(src.getDuration, src, "seconds")
                durationByPath[resolvedPath] = (okDur and tonumber(dur)) or 0.0
            end
            self.tracks[trackId] = src
            self.trackDurations[trackId] = durationByPath[resolvedPath] or 0.0
            self.trackResolvedPaths[trackId] = resolvedPath
            self.loadedTrackCount = self.loadedTrackCount + 1
            if isCustom then
                self.customCount = self.customCount + 1
            end
        else
            self.missing[#self.missing + 1] = meta.path
        end
    end

    local loadedSfxByPath = {}
    for sfxId, path in pairs(Audio.SFX_FILES) do
        self.totalSfxCount = self.totalSfxCount + 1
        local src, _, isCustom = loadStaticSourceWithDropIn(path, sfxId, loadedSfxByPath)
        if src then
            self.sfx[sfxId] = src
            self.loadedSfxCount = self.loadedSfxCount + 1
            if isCustom then
                self.customCount = self.customCount + 1
            end
        else
            self.missing[#self.missing + 1] = path
        end
    end

    table.sort(self.missing)
end

function Audio.new(muted)
    local self = setmetatable({
        muted = muted and true or false,
        musicEnabled = true,
        musicVolume = 0.52,
        sfxVolume = 0.80,
        trackMeta = {},
        tracks = {},
        trackDurations = {},
        trackResolvedPaths = {},
        sfx = {},
        missing = {},
        currentTrackId = nil,
        currentTrack = nil,
        trackPaused = false,
        loadedTrackCount = 0,
        totalTrackCount = 0,
        loadedSfxCount = 0,
        totalSfxCount = 0,
        customCount = 0,
    }, Audio)

    self:_loadAllAssets()
    return self
end

function Audio:reload()
    local prevTrackId = self.currentTrackId
    local wasPaused = self.trackPaused
    if self.currentTrack then
        pcall(self.currentTrack.stop, self.currentTrack)
    end
    self.currentTrack = nil
    self.currentTrackId = nil

    self:_loadAllAssets()

    if prevTrackId then
        self:playTrack(prevTrackId, true)
        if wasPaused then
            self:setTrackPaused(true)
        end
    end
    return self:getStats()
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
    local meta = (self.trackMeta and self.trackMeta[trackId]) or Audio.TRACK_META[trackId]
    if not meta then
        return false
    end

    local src = self.tracks[trackId]

    if (self.currentTrackId == trackId or (src and self.currentTrack == src)) and not restartIfSame then
        self.currentTrackId = trackId
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
    local meta = trackId and ((self.trackMeta and self.trackMeta[trackId]) or Audio.TRACK_META[trackId]) or nil
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

function Audio:playArrowChime(index)
    local tier = math.min(index, 3)
    local rise = 2 ^ ((index - tier) / 12)
    if self.sfx["chime_" .. tier] then
        return self:play("chime_" .. tier, 0.65, 0, rise)
    end
    return self:play("chime_1", 0.65, 0, 2 ^ ((index - 1) / 12))
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
        customCount = self.customCount or 0,
        missingCount = #self.missing,
        muted = self.muted,
        musicEnabled = self.musicEnabled,
    }
end

return Audio
