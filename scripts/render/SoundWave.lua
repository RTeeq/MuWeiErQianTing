--- 水下音效可视化：屏幕边缘低频声波涟漪效果
local SoundWave = {}

-- 涟漪状态
local waveState = {
    ripples = {},           -- 活跃涟漪列表
    timer = 0,             -- 下一次涟漪计时
    interval = 2.5,        -- 涟漪间隔（秒）
    ambientPhase = 0,      -- 持续性环境涟漪相位
}

--- 更新涟漪
---@param dt number
---@param gameTime number
function SoundWave.Update(dt, gameTime)
    waveState.ambientPhase = gameTime
    waveState.timer = waveState.timer + dt

    -- 周期性产生涟漪
    if waveState.timer >= waveState.interval then
        waveState.timer = 0
        waveState.interval = 1.8 + math.random() * 2.0  -- 随机间隔

        -- 从随机边缘产生
        local side = math.random(1, 4)  -- 1=左,2=右,3=上,4=下
        table.insert(waveState.ripples, {
            side = side,
            progress = 0,       -- 0~1 扩展进度
            speed = 0.4 + math.random() * 0.3,
            amplitude = 3 + math.random() * 4,
            wavelength = 20 + math.random() * 30,
            alpha = 80 + math.random(0, 60),
        })
    end

    -- 更新涟漪
    for i = #waveState.ripples, 1, -1 do
        local rip = waveState.ripples[i]
        rip.progress = rip.progress + rip.speed * dt
        if rip.progress > 1 then
            table.remove(waveState.ripples, i)
        end
    end
end

--- 绘制边缘声波涟漪
---@param vg userdata
---@param w number 屏幕宽度
---@param h number 屏幕高度
---@param gameTime number
function SoundWave.Draw(vg, w, h, gameTime)
    -- 持续性环境低频振动（四边微弱波纹）
    SoundWave.DrawAmbient(vg, w, h, gameTime)

    -- 动态涟漪
    for _, rip in ipairs(waveState.ripples) do
        SoundWave.DrawRipple(vg, w, h, rip, gameTime)
    end
end

--- 绘制持续性边缘环境波纹
function SoundWave.DrawAmbient(vg, w, h, gameTime)
    local amp = 2.0   -- 极微弱振幅
    local freq = 0.08 -- 波长倒数
    local phase = gameTime * 1.2
    local alpha = 25

    -- 左边缘
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    for y = 0, h, 8 do
        local ox = amp * math.sin(y * freq + phase)
        nvgLineTo(vg, ox, y)
    end
    nvgLineTo(vg, -5, h)
    nvgLineTo(vg, -5, 0)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(30, 100, 180, alpha))
    nvgFill(vg)

    -- 右边缘
    nvgBeginPath(vg)
    nvgMoveTo(vg, w, 0)
    for y = 0, h, 8 do
        local ox = amp * math.sin(y * freq + phase + 2.0)
        nvgLineTo(vg, w + ox, y)
    end
    nvgLineTo(vg, w + 5, h)
    nvgLineTo(vg, w + 5, 0)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(30, 100, 180, alpha))
    nvgFill(vg)

    -- 下边缘
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, h)
    for x = 0, w, 8 do
        local oy = amp * math.sin(x * freq * 0.7 + phase + 4.0)
        nvgLineTo(vg, x, h + oy)
    end
    nvgLineTo(vg, w, h + 5)
    nvgLineTo(vg, 0, h + 5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(20, 80, 160, alpha))
    nvgFill(vg)
end

--- 绘制单个声波涟漪
function SoundWave.DrawRipple(vg, w, h, rip, gameTime)
    local prog = rip.progress
    local fadeAlpha = math.floor(rip.alpha * (1 - prog) * (1 - prog))
    if fadeAlpha < 2 then return end

    local depth = 40 * prog  -- 涟漪向内扩展深度
    local amp = rip.amplitude * (1 - prog * 0.5)
    local wl = rip.wavelength

    nvgBeginPath(vg)

    if rip.side == 1 then
        -- 左侧涟漪
        local x0 = depth
        nvgMoveTo(vg, 0, 0)
        for y = 0, h, 6 do
            local ox = x0 + amp * math.sin(y / wl * math.pi * 2 + gameTime * 3)
            nvgLineTo(vg, ox, y)
        end
        nvgLineTo(vg, 0, h)
        nvgClosePath(vg)
    elseif rip.side == 2 then
        -- 右侧涟漪
        local x0 = w - depth
        nvgMoveTo(vg, w, 0)
        for y = 0, h, 6 do
            local ox = x0 - amp * math.sin(y / wl * math.pi * 2 + gameTime * 3 + 1.5)
            nvgLineTo(vg, ox, y)
        end
        nvgLineTo(vg, w, h)
        nvgClosePath(vg)
    elseif rip.side == 3 then
        -- 顶部涟漪
        local y0 = depth
        nvgMoveTo(vg, 0, 0)
        for x = 0, w, 6 do
            local oy = y0 + amp * math.sin(x / wl * math.pi * 2 + gameTime * 3 + 3.0)
            nvgLineTo(vg, x, oy)
        end
        nvgLineTo(vg, w, 0)
        nvgClosePath(vg)
    else
        -- 底部涟漪
        local y0 = h - depth
        nvgMoveTo(vg, 0, h)
        for x = 0, w, 6 do
            local oy = y0 - amp * math.sin(x / wl * math.pi * 2 + gameTime * 3 + 4.5)
            nvgLineTo(vg, x, oy)
        end
        nvgLineTo(vg, w, h)
        nvgClosePath(vg)
    end

    nvgFillColor(vg, nvgRGBA(20, 80, 160, fadeAlpha))
    nvgFill(vg)
end

return SoundWave
