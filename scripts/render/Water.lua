--- 水位效果渲染：进水、波纹、气泡
local Config = require("Config")

local Water = {}

--- 绘制舱室进水效果
---@param vg userdata
---@param subX number 潜艇内部左边界
---@param subY number 潜艇内部顶部
---@param subH number 潜艇内部高度
---@param sub table 潜艇数据
---@param gameTime number
function Water.Draw(vg, subX, subY, subH, sub, gameTime)
    for i, comp in ipairs(sub.compartments) do
        if comp.waterLevel > 0.01 then
            local cx = subX + comp.x
            local cw = comp.width
            local waterH = subH * comp.waterLevel
            local waterY = subY + subH - waterH

            -- 水体主色（半透明蓝色）
            local cSurf = Config.Colors.waterSurface
            local cDeep = Config.Colors.waterDeep
            local grad = nvgLinearGradient(vg, cx, waterY, cx, subY + subH,
                nvgRGBA(cSurf[1], cSurf[2], cSurf[3], cSurf[4]),
                nvgRGBA(cDeep[1], cDeep[2], cDeep[3], cDeep[4]))
            nvgBeginPath(vg)
            nvgRect(vg, cx, waterY, cw, waterH)
            nvgFillPaint(vg, grad)
            nvgFill(vg)

            -- 水面波纹（增强多层波浪）
            Water.DrawEnhancedSurface(vg, cx, waterY, cw, gameTime, i, comp.waterLevel)
            Water.DrawWavesSurface(vg, cx, waterY, cw, gameTime, i)

            -- 水中气泡
            if comp.hasBreach then
                Water.DrawFloodBubbles(vg, cx, waterY, cw, waterH, gameTime, i)
            end

            -- 破洞涌入水流效果
            if comp.hasBreach then
                Water.DrawBreachFlow(vg, cx, subY, cw, subH, waterY, gameTime, comp.breachSize)
            end
        end
    end
end

--- 绘制水面波纹
function Water.DrawWavesSurface(vg, x, waterY, w, gameTime, seed)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, waterY)

    local waveAmp = 3
    local waveFreq = 0.05
    local segments = math.floor(w / 5)

    for s = 0, segments do
        local sx = x + (s / segments) * w
        local sy = waterY + math.sin(gameTime * 2 + sx * waveFreq + seed * 3) * waveAmp
        nvgLineTo(vg, sx, sy)
    end

    nvgLineTo(vg, x + w, waterY + 5)
    nvgLineTo(vg, x, waterY + 5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(40, 130, 210, 100))
    nvgFill(vg)
end

--- 绘制水中气泡（进水时）
function Water.DrawFloodBubbles(vg, x, waterY, w, waterH, gameTime, seed)
    local bubbleCount = 8
    for i = 1, bubbleCount do
        local phase = gameTime * 1.5 + i * 1.7 + seed * 2.3
        local bx = x + (math.sin(phase * 0.7 + i) * 0.5 + 0.5) * w
        local progress = (phase % 3) / 3  -- 0~1 上升进度
        local by = waterY + waterH * (1 - progress)
        local br = 2 + math.sin(phase) * 1

        if by > waterY and by < waterY + waterH then
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, br)
            nvgFillColor(vg, nvgRGBA(150, 200, 255, math.floor(80 * (1 - progress))))
            nvgFill(vg)
        end
    end
end

--- 绘制破洞涌水效果（增强：高压水柱 + 飞溅粒子 + 雾气）
function Water.DrawBreachFlow(vg, cx, subY, cw, subH, waterY, gameTime, breachSize)
    -- 破洞位置（舱室侧面偏下）
    local bx = cx + cw * 0.8
    local by = subY + subH * 0.6

    -- 水流弧线从破洞涌入
    local flowWidth = 10 + breachSize * 16
    local flowAlpha = math.floor(120 + breachSize * 100)
    local pressure = 0.7 + math.sin(gameTime * 4) * 0.3  -- 压力脉冲

    -- 高压水柱主体（更粗更亮）
    nvgBeginPath(vg)
    nvgMoveTo(vg, bx, by - flowWidth * 0.5 * pressure)
    nvgQuadTo(vg, bx - 35 * pressure, by + 25, bx - 60 * pressure, waterY)
    nvgLineTo(vg, bx - 60 * pressure + flowWidth, waterY)
    nvgQuadTo(vg, bx - 35 * pressure + flowWidth, by + 25, bx, by + flowWidth * 0.5 * pressure)
    nvgClosePath(vg)
    -- 水柱渐变（近破洞处更亮）
    local jetGrad = nvgLinearGradient(vg, bx, by, bx - 60, waterY,
        nvgRGBA(80, 180, 255, flowAlpha),
        nvgRGBA(30, 100, 180, math.floor(flowAlpha * 0.6)))
    nvgFillPaint(vg, jetGrad)
    nvgFill(vg)

    -- 水柱核心（高亮白线）
    nvgBeginPath(vg)
    nvgMoveTo(vg, bx, by)
    nvgQuadTo(vg, bx - 30 * pressure, by + 20, bx - 50 * pressure, waterY + 5)
    nvgStrokeColor(vg, nvgRGBA(180, 220, 255, math.floor(150 * pressure)))
    nvgStrokeWidth(vg, 2 + breachSize * 2)
    nvgStroke(vg)

    -- 飞溅水滴粒子（从水柱四散）
    for i = 1, 8 do
        local phase = gameTime * 5 + i * 1.3
        local progress = (phase % 1.5) / 1.5
        local spreadX = math.sin(phase * 3 + i * 2.7) * (20 + progress * 30)
        local spreadY = -15 * (1 - progress) + progress * progress * 40  -- 抛物线
        local dropX = bx - 30 + spreadX
        local dropY = by + 10 + spreadY
        local dropSize = (2 + breachSize * 2) * (1 - progress)
        local dropAlpha = math.floor(180 * (1 - progress))

        if dropAlpha > 5 then
            nvgBeginPath(vg)
            nvgCircle(vg, dropX, dropY, dropSize)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, dropAlpha))
            nvgFill(vg)
        end
    end

    -- 破洞处水雾扩散
    local mistGrad = nvgRadialGradient(vg, bx, by, 5, 30 + breachSize * 20,
        nvgRGBA(100, 180, 240, math.floor(50 * pressure)),
        nvgRGBA(60, 140, 200, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, bx, by, 30 + breachSize * 20)
    nvgFillPaint(vg, mistGrad)
    nvgFill(vg)

    -- 破洞标记（红色警告 + 脉冲环）
    local flashAlpha = math.floor(150 + math.sin(gameTime * 6) * 100)
    nvgBeginPath(vg)
    nvgCircle(vg, bx, by, 6 + breachSize * 4)
    nvgStrokeColor(vg, nvgRGBA(240, 60, 60, flashAlpha))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 警告脉冲扩散环
    local ringProgress = (gameTime * 2) % 1.0
    local ringAlpha = math.floor(180 * (1 - ringProgress))
    nvgBeginPath(vg)
    nvgCircle(vg, bx, by, (8 + breachSize * 4) + ringProgress * 15)
    nvgStrokeColor(vg, nvgRGBA(240, 60, 60, ringAlpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

--- 绘制增强波动水面（更真实的水面模拟）
function Water.DrawEnhancedSurface(vg, x, waterY, w, gameTime, seed, waterLevel)
    if waterLevel < 0.02 then return end

    -- 多层波浪叠加
    local layers = {
        {amp = 4, freq = 0.06, speed = 2.5, alpha = 120},
        {amp = 2, freq = 0.12, speed = 3.8, alpha = 80},
        {amp = 1, freq = 0.25, speed = 5.0, alpha = 50},
    }

    for _, layer in ipairs(layers) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, waterY)
        local segments = math.floor(w / 4)
        for s = 0, segments do
            local sx = x + (s / segments) * w
            local sy = waterY + layer.amp * math.sin(gameTime * layer.speed + sx * layer.freq + seed * 3)
                     + layer.amp * 0.5 * math.sin(gameTime * layer.speed * 1.5 + sx * layer.freq * 2.3 + seed)
            nvgLineTo(vg, sx, sy)
        end
        nvgLineTo(vg, x + w, waterY + 8)
        nvgLineTo(vg, x, waterY + 8)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(60, 150, 230, layer.alpha))
        nvgFill(vg)
    end

    -- 水面高光反射
    for i = 1, 5 do
        local hx = x + (i / 6) * w
        local hy = waterY + math.sin(gameTime * 2 + i * 2.5 + seed) * 3
        local hw = 8 + math.sin(gameTime * 3 + i) * 4
        nvgBeginPath(vg)
        nvgEllipse(vg, hx, hy, hw, 1.5)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 40 + math.floor(math.sin(gameTime * 4 + i) * 20)))
        nvgFill(vg)
    end
end

return Water
