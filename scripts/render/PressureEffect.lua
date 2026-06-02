--- 深海压力效果：屏幕边缘挤压变形 + 深度越深越强
local PressureEffect = {}

-- 压力状态
local pressureState = {
    depth = 2400,           -- 当前深度（米）
    maxDepth = 5000,        -- 最大深度
    intensity = 0,          -- 当前压力强度 0~1
    crackAlpha = 0,         -- 裂纹透明度（极深时出现）
}

--- 更新压力
---@param dt number
---@param depth number 当前深度
function PressureEffect.Update(dt, depth)
    pressureState.depth = depth or pressureState.depth
    -- 深度归一化（2000m以下开始有效果）
    local normalizedDepth = math.max(0, (pressureState.depth - 2000)) / (pressureState.maxDepth - 2000)
    pressureState.intensity = math.min(1, normalizedDepth)

    -- 裂纹效果（深度超过4000m）
    if pressureState.depth > 4000 then
        pressureState.crackAlpha = (pressureState.depth - 4000) / 1000 * 80
    else
        pressureState.crackAlpha = 0
    end
end

--- 设置深度
function PressureEffect.SetDepth(depth)
    pressureState.depth = depth
end

--- 绘制压力效果
---@param vg userdata
---@param w number 屏幕宽度
---@param h number 屏幕高度
---@param gameTime number
function PressureEffect.Draw(vg, w, h, gameTime)
    local intensity = pressureState.intensity
    if intensity < 0.01 then return end

    -- 1. 边缘暗角加深（模拟水压挤压视野）
    local vignetteSize = 0.3 + intensity * 0.25  -- 暗角范围随深度增大
    local vignetteAlpha = math.floor(60 + intensity * 120)
    local vigGrad = nvgRadialGradient(vg, w * 0.5, h * 0.5,
        w * (0.5 - vignetteSize), w * 0.7,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 5, 15, vignetteAlpha))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, vigGrad)
    nvgFill(vg)

    -- 2. 边缘扭曲线条（模拟压力）
    local waveAmp = 2 + intensity * 6
    local waveFreq = 0.03 + intensity * 0.02
    local lineAlpha = math.floor(20 + intensity * 50)

    -- 左边缘压力线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    for y = 0, h, 4 do
        local ox = waveAmp * math.sin(y * waveFreq + gameTime * 2)
        nvgLineTo(vg, ox + 3, y)
    end
    nvgLineTo(vg, 0, h)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(10, 30, 60, lineAlpha))
    nvgFill(vg)

    -- 右边缘压力线
    nvgBeginPath(vg)
    nvgMoveTo(vg, w, 0)
    for y = 0, h, 4 do
        local ox = waveAmp * math.sin(y * waveFreq + gameTime * 2 + 3.14)
        nvgLineTo(vg, w - ox - 3, y)
    end
    nvgLineTo(vg, w, h)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(10, 30, 60, lineAlpha))
    nvgFill(vg)

    -- 上边缘
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    for x = 0, w, 4 do
        local oy = waveAmp * 0.6 * math.sin(x * waveFreq + gameTime * 1.8 + 1.0)
        nvgLineTo(vg, x, oy + 2)
    end
    nvgLineTo(vg, w, 0)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(10, 30, 60, math.floor(lineAlpha * 0.7)))
    nvgFill(vg)

    -- 下边缘
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, h)
    for x = 0, w, 4 do
        local oy = waveAmp * 0.6 * math.sin(x * waveFreq + gameTime * 1.8 + 5.0)
        nvgLineTo(vg, x, h - oy - 2)
    end
    nvgLineTo(vg, w, h)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(10, 30, 60, math.floor(lineAlpha * 0.7)))
    nvgFill(vg)

    -- 3. 压力裂纹（极深时出现）
    if pressureState.crackAlpha > 2 then
        local ca = math.floor(pressureState.crackAlpha)
        -- 随机裂纹线（基于时间种子确保不每帧变化）
        local seed = math.floor(gameTime * 0.2)  -- 每5秒变化一次
        math.randomseed(seed)
        for i = 1, 3 do
            local startX = math.random(0, math.floor(w))
            local startY = math.random(0, math.floor(h * 0.3))
            nvgBeginPath(vg)
            nvgMoveTo(vg, startX, startY)
            local cx, cy = startX, startY
            for seg = 1, 4 do
                cx = cx + math.random(-20, 20)
                cy = cy + math.random(10, 30)
                nvgLineTo(vg, cx, cy)
            end
            nvgStrokeColor(vg, nvgRGBA(150, 200, 255, ca))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
        -- 恢复随机种子
        math.randomseed(os.clock() * 10000)
    end

    -- 4. 脉冲式挤压感（周期性加强）
    local squeezePulse = math.sin(gameTime * 1.5) * 0.5 + 0.5
    if intensity > 0.3 and squeezePulse > 0.8 then
        local pulseAlpha = math.floor((squeezePulse - 0.8) * 5 * 30 * intensity)
        -- 快速闪现一个更强的暗角
        local pulseGrad = nvgRadialGradient(vg, w * 0.5, h * 0.5,
            w * 0.25, w * 0.55,
            nvgRGBA(0, 0, 0, 0),
            nvgRGBA(5, 10, 25, pulseAlpha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, pulseGrad)
        nvgFill(vg)
    end
end

return PressureEffect
