--- 音频管理器 - 统一管理背景音乐和音效
local AudioManager = {}

-- 音乐资源路径
AudioManager.BGM = {
    MENU     = "audio/bgm_menu.ogg",
    DEEPSEA  = "audio/bgm_deepsea.ogg",
}

-- 音效资源路径
AudioManager.SFX = {
    BUTTON_CLICK   = "audio/sfx/sfx_button_click.ogg",
    DEPART         = "audio/sfx/sfx_depart.ogg",
    ALERT          = "audio/sfx/sfx_alert.ogg",
    MISSION_ACCEPT = "audio/sfx/sfx_mission_accept.ogg",
    SONAR_PING     = "audio/sfx/sfx_sonar_ping.ogg",
    COLLISION      = "audio/sfx/sfx_collision.ogg",
}

-- 内部状态
local currentBGM_ = nil       -- 当前播放的音乐路径
local musicNode_ = nil        -- 音乐节点
local musicSource_ = nil      -- 音乐 SoundSource
local sfxNode_ = nil          -- 音效节点
local scene_ = nil            -- 场景引用
local musicVolume_ = 0.6
local sfxVolume_ = 0.8

--- 初始化（传入 scene）
function AudioManager.Init(scene)
    scene_ = scene

    -- 音乐节点
    musicNode_ = scene_:CreateChild("BGM")
    musicSource_ = musicNode_:CreateComponent("SoundSource")
    musicSource_.soundType = SOUND_MUSIC
    musicSource_.gain = musicVolume_

    -- 音效节点
    sfxNode_ = scene_:CreateChild("SFX")
end

--- 播放背景音乐（自动循环，重复调用同路径不会重复播放）
function AudioManager.PlayMusic(path)
    if not musicSource_ then return end
    if currentBGM_ == path then return end  -- 已在播放

    currentBGM_ = path
    if path == nil then
        musicSource_:Stop()
        return
    end

    local sound = cache:GetResource("Sound", path)
    if sound then
        sound.looped = true
        musicSource_:Play(sound)
        musicSource_.gain = musicVolume_
    end
end

--- 停止音乐
function AudioManager.StopMusic()
    if musicSource_ then
        musicSource_:Stop()
    end
    currentBGM_ = nil
end

--- 播放音效（一次性）
function AudioManager.PlaySFX(path)
    if not sfxNode_ then return end
    local sound = cache:GetResource("Sound", path)
    if sound then
        sound.looped = false
        local source = sfxNode_:CreateComponent("SoundSource")
        source.soundType = SOUND_EFFECT
        source.gain = sfxVolume_
        source.autoRemoveMode = REMOVE_COMPONENT
        source:Play(sound)
    end
end

--- 根据阶段自动切换背景音乐
function AudioManager.UpdatePhaseMusic(phase)
    local Shared = require("network.Shared")
    if phase == Shared.PHASE.TITLE or phase == Shared.PHASE.LOBBY or phase == Shared.PHASE.PORT then
        AudioManager.PlayMusic(AudioManager.BGM.MENU)
    elseif phase == Shared.PHASE.DEEP_SEA or phase == Shared.PHASE.EVA then
        AudioManager.PlayMusic(AudioManager.BGM.DEEPSEA)
    end
end

--- 设置音乐音量 (0~1)
function AudioManager.SetMusicVolume(vol)
    musicVolume_ = vol
    if musicSource_ then
        musicSource_.gain = vol
    end
end

--- 设置音效音量 (0~1)
function AudioManager.SetSFXVolume(vol)
    sfxVolume_ = vol
end

return AudioManager
