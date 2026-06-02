--- 怪物渲染模块 - 巨型蠕虫/触须水母/多眼鱼 + 荧光效果
local Config = require("Config")

local Monsters = {}

-- ============================================================
-- 绘制外部视角中的怪物
-- ============================================================

--- 在外部视角绘制所有可见怪物
---@param vg userdata
---@param visibleMonsters table[] 来自MonsterManager.GetVisibleMonsters
---@param w number 屏幕宽
---@param h number 屏幕高
---@param gameTime number
function Monsters.DrawExternal(vg, visibleMonsters, w, h, gameTime)
    for _, entry in ipairs(visibleMonsters) do
        local m = entry.monster
        -- 计算屏幕位置（根据 distance 和 angle）
        local screenX, screenY = Monsters.GetScreenPos(m, w, h)
        local scale = 1.0 - m.distance * 0.6  -- 远处更小

        nvgSave(vg)
        nvgTranslate(vg, screenX, screenY)
        nvgScale(vg, scale, scale)

        -- 受击闪白效果
        local flashAlpha = math.floor(m.hitFlash * 200)

        if m.type == "worm" then
            Monsters.DrawWorm(vg, m, gameTime, flashAlpha)
        elseif m.type == "jellyfish" then
            Monsters.DrawJellyfish(vg, m, gameTime, flashAlpha)
        elseif m.type == "fish" then
            Monsters.DrawMultiEyeFish(vg, m, gameTime, flashAlpha)
        end

        -- 绿血粒子
        Monsters.DrawHitParticles(vg, m, gameTime)

        nvgRestore(vg)
    end
end

--- 计算怪物在外部视角的屏幕位置
function Monsters.GetScreenPos(m, w, h)
    local subCenterX = w * 0.5
    local subCenterY = h * 0.5

    -- 基于 side 和 distance 计算位置
    local maxDist = w * 0.45  -- 最远在屏幕边缘
    local dx = m.side * m.distance * maxDist
    local dy = math.sin(math.rad(m.angle)) * m.distance * h * 0.3

    -- 加入游泳摆动
    local swimX = math.sin(m.animTime * 1.5 + m.bodyPhase) * 10 * m.distance
    local swimY = math.cos(m.animTime * 1.2 + m.bodyPhase) * 8

    return subCenterX + dx + swimX, subCenterY + dy + swimY
end

-- ============================================================
-- 巨型蠕虫
-- ============================================================
function Monsters.DrawWorm(vg, m, gameTime, flashAlpha)
    local t = m.animTime
    local segments = 8
    local segLen = 12

    -- 身体：多段连接的圆形
    for i = segments, 1, -1 do
        local phase = t * 3 + i * 0.8
        local sx = -i * segLen + math.sin(phase) * (i * 2)
        local sy = math.cos(phase * 0.7) * (i * 1.5)
        local radius = 8 + (segments - i) * 1.5 -- 头大尾小

        -- 身体主色（深红暗色）
        local bodyR = 80 + i * 5
        local bodyG = 20 + i * 3
        local bodyB = 30 + i * 2

        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, radius)
        nvgFillColor(vg, nvgRGBA(bodyR, bodyG, bodyB, 220))
        nvgFill(vg)

        -- 荧光点（每隔一段）
        if i % 2 == 0 then
            local glowPulse = 0.6 + math.sin(t * 4 + i) * 0.4
            local glowAlpha = math.floor(120 * glowPulse)
            local glowGrad = nvgRadialGradient(vg, sx, sy, 0, radius * 1.8,
                nvgRGBA(80, 255, 150, glowAlpha),
                nvgRGBA(80, 255, 150, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, radius * 1.8)
            nvgFillPaint(vg, glowGrad)
            nvgFill(vg)
        end
    end

    -- 头部
    local headX = math.sin(t * 3) * 3
    local headY = math.cos(t * 2.1) * 2
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, 14)
    nvgFillColor(vg, nvgRGBA(100, 30, 40, 240))
    nvgFill(vg)

    -- 口器（张合动画）
    local mouthOpen = 3 + math.abs(math.sin(t * 5)) * 6
    nvgBeginPath(vg)
    nvgCircle(vg, headX + 12, headY, mouthOpen)
    nvgFillColor(vg, nvgRGBA(150, 20, 30, 255))
    nvgFill(vg)

    -- 眼睛
    nvgBeginPath(vg)
    nvgCircle(vg, headX + 5, headY - 6, 4)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, headX + 5, headY - 6, 2)
    nvgFillColor(vg, nvgRGBA(20, 5, 5, 255))
    nvgFill(vg)

    -- 受击闪白
    if flashAlpha > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, 50)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
    end
end

-- ============================================================
-- 触须水母
-- ============================================================
function Monsters.DrawJellyfish(vg, m, gameTime, flashAlpha)
    local t = m.animTime

    -- 伞盖（半透明脉动）
    local pulseScale = 1.0 + math.sin(t * 2.5) * 0.1
    local bellW = 35 * pulseScale
    local bellH = 25 * pulseScale

    -- 伞盖发光渐变
    local bellGlow = nvgRadialGradient(vg, 0, -5, 0, bellW,
        nvgRGBA(60, 180, 220, 150),
        nvgRGBA(30, 80, 150, 60))
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, -5, bellW, bellH)
    nvgFillPaint(vg, bellGlow)
    nvgFill(vg)

    -- 伞盖边缘（荧光线条）
    nvgBeginPath(vg)
    nvgEllipse(vg, 0, -5, bellW, bellH)
    local edgePulse = 0.5 + math.sin(t * 3) * 0.5
    nvgStrokeColor(vg, nvgRGBA(100, 240, 255, math.floor(180 * edgePulse)))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内部纹理（同心圆）
    for ring = 1, 3 do
        local rr = bellW * ring / 4
        local rAlpha = math.floor(40 + math.sin(t * 2 + ring) * 20)
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, -5, rr, rr * 0.7)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, rAlpha))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- 触须（多条，波浪运动）
    local tentacleCount = 6
    for i = 1, tentacleCount do
        local baseX = (i - tentacleCount / 2 - 0.5) * 10
        nvgBeginPath(vg)
        nvgMoveTo(vg, baseX, bellH * 0.6)

        -- 二阶曲线模拟触须飘动
        local segments = 5
        for s = 1, segments do
            local progress = s / segments
            local waveX = baseX + math.sin(t * 2 + i * 0.8 + s * 1.2) * (8 + s * 3)
            local waveY = bellH * 0.6 + s * 12
            nvgLineTo(vg, waveX, waveY)
        end

        local tAlpha = math.floor(100 + math.sin(t * 3 + i) * 50)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 240, tAlpha))
        nvgStrokeWidth(vg, 2 - i * 0.15)
        nvgStroke(vg)

        -- 触须末端发光点
        local endX = baseX + math.sin(t * 2 + i * 0.8 + segments * 1.2) * (8 + segments * 3)
        local endY = bellH * 0.6 + segments * 12
        local tipGlow = nvgRadialGradient(vg, endX, endY, 0, 5,
            nvgRGBA(100, 255, 200, math.floor(80 + math.sin(t * 5 + i) * 40)),
            nvgRGBA(100, 255, 200, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, endX, endY, 5)
        nvgFillPaint(vg, tipGlow)
        nvgFill(vg)
    end

    -- 中心发光核心
    local coreGlow = nvgRadialGradient(vg, 0, 0, 0, 15,
        nvgRGBA(150, 255, 200, math.floor(100 + math.sin(t * 4) * 50)),
        nvgRGBA(80, 200, 180, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, 15)
    nvgFillPaint(vg, coreGlow)
    nvgFill(vg)

    -- 受击闪白
    if flashAlpha > 0 then
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, bellW * 1.2, bellH + 30)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
    end
end

-- ============================================================
-- 多眼鱼
-- ============================================================
function Monsters.DrawMultiEyeFish(vg, m, gameTime, flashAlpha)
    local t = m.animTime

    -- 鱼身（流线型）
    local bodyLen = 40
    local bodyH = 22
    local swimPhase = math.sin(t * 4) * 3

    -- 身体主轮廓
    nvgBeginPath(vg)
    nvgEllipse(vg, swimPhase, 0, bodyLen, bodyH)
    -- 深海鱼的深蓝/紫色
    local bodyGrad = nvgLinearGradient(vg, -bodyLen, 0, bodyLen, 0,
        nvgRGBA(30, 20, 60, 230),
        nvgRGBA(50, 30, 80, 230))
    nvgFillPaint(vg, bodyGrad)
    nvgFill(vg)

    -- 鳍（上鳍 + 胸鳍）
    -- 上鳍
    nvgBeginPath(vg)
    nvgMoveTo(vg, -10 + swimPhase, -bodyH + 3)
    nvgLineTo(vg, 5 + swimPhase, -bodyH - 12 + math.sin(t * 3) * 3)
    nvgLineTo(vg, 15 + swimPhase, -bodyH + 5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(40, 25, 70, 200))
    nvgFill(vg)

    -- 尾鳍（摆动）
    local tailAngle = math.sin(t * 5) * 0.4
    nvgSave(vg)
    nvgTranslate(vg, -bodyLen + swimPhase, 0)
    nvgRotate(vg, tailAngle)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgLineTo(vg, -18, -12)
    nvgLineTo(vg, -18, 12)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(40, 30, 70, 200))
    nvgFill(vg)
    nvgRestore(vg)

    -- 多只眼睛（5只，分布在头部区域）
    local eyePositions = {
        {x = 20, y = -8, size = 6},
        {x = 25, y = 0, size = 7},
        {x = 20, y = 8, size = 5},
        {x = 12, y = -12, size = 4},
        {x = 12, y = 12, size = 4},
    }

    for i, eye in ipairs(eyePositions) do
        local ex = eye.x + swimPhase
        local ey = eye.y

        -- 眼白（淡绿发光）
        local eyeGlow = nvgRadialGradient(vg, ex, ey, 0, eye.size * 1.5,
            nvgRGBA(150, 255, 180, 180),
            nvgRGBA(80, 200, 120, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, ex, ey, eye.size * 1.5)
        nvgFillPaint(vg, eyeGlow)
        nvgFill(vg)

        -- 眼球
        nvgBeginPath(vg)
        nvgCircle(vg, ex, ey, eye.size)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, 240))
        nvgFill(vg)

        -- 瞳孔（跟踪移动感）
        local pupilX = ex + math.sin(t * 1.5 + i * 0.5) * 2
        local pupilY = ey + math.cos(t * 1.2 + i * 0.7) * 1.5
        nvgBeginPath(vg)
        nvgCircle(vg, pupilX, pupilY, eye.size * 0.5)
        nvgFillColor(vg, nvgRGBA(10, 30, 10, 255))
        nvgFill(vg)

        -- 瞳孔高光
        nvgBeginPath(vg)
        nvgCircle(vg, pupilX + 1, pupilY - 1, eye.size * 0.2)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgFill(vg)
    end

    -- 全身荧光点（散布在身体上）
    for i = 1, 10 do
        local gx = (math.random() - 0.5) * bodyLen * 1.5 + swimPhase
        local gy = (math.random() - 0.5) * bodyH * 1.5
        local gPulse = 0.5 + math.sin(t * 3 + i * 1.1 + m.glowPhase) * 0.5
        local gAlpha = math.floor(60 * gPulse)

        nvgBeginPath(vg)
        nvgCircle(vg, gx, gy, 2)
        nvgFillColor(vg, nvgRGBA(100, 255, 180, gAlpha))
        nvgFill(vg)
    end

    -- 深海鱼特有的头灯（额头发光器官）
    local lanternX = 30 + swimPhase
    local lanternY = -5
    local lanternPulse = 0.6 + math.sin(t * 2) * 0.4
    local lanternGrad = nvgRadialGradient(vg, lanternX, lanternY, 0, 12,
        nvgRGBA(200, 255, 100, math.floor(150 * lanternPulse)),
        nvgRGBA(150, 255, 80, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, lanternX, lanternY, 12)
    nvgFillPaint(vg, lanternGrad)
    nvgFill(vg)
    -- 发光核心
    nvgBeginPath(vg)
    nvgCircle(vg, lanternX, lanternY, 4)
    nvgFillColor(vg, nvgRGBA(255, 255, 150, math.floor(200 * lanternPulse)))
    nvgFill(vg)

    -- 受击闪白
    if flashAlpha > 0 then
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, bodyLen * 1.2, bodyH * 1.5)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
    end
end

-- ============================================================
-- 绿血粒子绘制
-- ============================================================
function Monsters.DrawHitParticles(vg, m, gameTime)
    for _, p in ipairs(m.hitParticles) do
        local alpha = math.floor(200 * (p.life / p.maxLife))
        local size = p.size * (0.5 + p.life / p.maxLife * 0.5)

        -- 绿色血液粒子
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, size)
        nvgFillColor(vg, nvgRGBA(30, 200, 80, alpha))
        nvgFill(vg)

        -- 小拖尾发光
        local glowGrad = nvgRadialGradient(vg, p.x, p.y, 0, size * 2,
            nvgRGBA(50, 255, 100, math.floor(alpha * 0.3)),
            nvgRGBA(50, 255, 100, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, size * 2)
        nvgFillPaint(vg, glowGrad)
        nvgFill(vg)
    end
end

-- ============================================================
-- 声呐上的怪物红点绘制
-- ============================================================

--- 在声呐上绘制怪物红点（替代随机检测）
---@param vg userdata
---@param cx number 声呐中心X
---@param cy number 声呐中心Y
---@param radius number 声呐半径
---@param sonarData table[] 来自MonsterManager.GetSonarData
---@param gameTime number
function Monsters.DrawSonarDots(vg, cx, cy, radius, sonarData, gameTime)
    for _, data in ipairs(sonarData) do
        -- 计算在声呐上的位置
        local dist = data.distance * radius * 0.9
        local ang = math.rad(data.angle) + (data.side > 0 and 0 or math.pi)
        local dotX = cx + math.cos(ang) * dist
        local dotY = cy + math.sin(ang) * dist

        -- 闪烁效果
        local blink = 0.6 + math.sin(gameTime * 6 + data.blinkPhase) * 0.4
        local dotAlpha = math.floor(220 * blink)
        local dotSize = 3 + (1 - data.distance) * 2  -- 越近越大

        -- 红色威胁点
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotY, dotSize)
        nvgFillColor(vg, nvgRGBA(240, 40, 40, dotAlpha))
        nvgFill(vg)

        -- 红色光晕
        local redGlow = nvgRadialGradient(vg, dotX, dotY, 0, dotSize * 3,
            nvgRGBA(240, 40, 40, math.floor(dotAlpha * 0.3)),
            nvgRGBA(240, 40, 40, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotY, dotSize * 3)
        nvgFillPaint(vg, redGlow)
        nvgFill(vg)

        -- 接近时额外脉冲圈
        if data.distance < 0.4 then
            local pulseR = dotSize * 2 + math.sin(gameTime * 8) * 3
            nvgBeginPath(vg)
            nvgCircle(vg, dotX, dotY, pulseR)
            nvgStrokeColor(vg, nvgRGBA(240, 60, 60, math.floor(100 * blink)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end

-- ============================================================
-- 船体凹陷动画绘制
-- ============================================================

--- 在潜艇外壳上绘制撞击凹陷
---@param vg userdata
---@param subX number 潜艇左上X
---@param subY number 潜艇左上Y
---@param subW number 潜艇宽度
---@param subH number 潜艇高度
---@param dentData table|nil {amount, x}
---@param gameTime number
function Monsters.DrawHullDent(vg, subX, subY, subW, subH, dentData, gameTime)
    if not dentData or dentData.amount <= 0 then return end

    local dentCX = subX + subW * dentData.x
    local dentCY = subY + subH * 0.5
    local dentRadius = 30 + dentData.amount * 20
    local dentDepth = dentData.amount * 8

    -- 凹陷阴影（模拟变形）
    nvgSave(vg)

    -- 深色凹陷区域
    local dentGrad = nvgRadialGradient(vg, dentCX, dentCY, 0, dentRadius,
        nvgRGBA(20, 25, 35, math.floor(200 * dentData.amount)),
        nvgRGBA(60, 65, 72, 0))
    nvgBeginPath(vg)
    nvgEllipse(vg, dentCX, dentCY, dentRadius, dentRadius * 0.6)
    nvgFillPaint(vg, dentGrad)
    nvgFill(vg)

    -- 裂纹线条
    local crackAlpha = math.floor(180 * dentData.amount)
    nvgStrokeColor(vg, nvgRGBA(150, 100, 50, crackAlpha))
    nvgStrokeWidth(vg, 1.5)
    for i = 1, 4 do
        local ang = (i / 4) * math.pi * 2 + gameTime * 0.5
        local len = dentRadius * 0.6 + math.sin(ang * 3) * 5
        nvgBeginPath(vg)
        nvgMoveTo(vg, dentCX, dentCY)
        nvgLineTo(vg, dentCX + math.cos(ang) * len, dentCY + math.sin(ang) * len * 0.5)
        nvgStroke(vg)
    end

    -- 边缘金属高光（表示变形）
    nvgBeginPath(vg)
    nvgEllipse(vg, dentCX, dentCY, dentRadius, dentRadius * 0.6)
    nvgStrokeColor(vg, nvgRGBA(120, 130, 140, math.floor(100 * dentData.amount)))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgRestore(vg)
end

return Monsters
