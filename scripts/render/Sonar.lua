--- 声呐脉冲效果：周期性绿色扫描波 + 检测到物体显示黄/红点
local Config = require("Config")

local Sonar = {}

-- 声呐状态
local sonarState = {
    sweepAngle = 0,          -- 当前扫描角度
    pingTimer = 0,           -- 脉冲计时器
    pingInterval = 3.0,      -- 脉冲间隔（秒）
    pulseRings = {},         -- 正在扩散的脉冲环
    detectedObjects = {},    -- 检测到的物体
    lastDetectTime = 0,      -- 上次检测时间
}

--- 更新声呐状态
---@param dt number
---@param gameTime number
function Sonar.Update(dt, gameTime)
    -- 扫描线旋转
    sonarState.sweepAngle = sonarState.sweepAngle + dt * 2.5

    -- 脉冲计时
    sonarState.pingTimer = sonarState.pingTimer + dt
    if sonarState.pingTimer >= sonarState.pingInterval then
        sonarState.pingTimer = 0
        -- 添加新的扩散环
        table.insert(sonarState.pulseRings, {
            radius = 0,
            maxRadius = 25,
            alpha = 255,
            time = 0,
        })
        -- 随机生成检测到的物体
        Sonar.GenerateDetections(gameTime)
    end

    -- 更新脉冲环
    for i = #sonarState.pulseRings, 1, -1 do
        local ring = sonarState.pulseRings[i]
        ring.time = ring.time + dt
        ring.radius = ring.maxRadius * (ring.time / 1.5)
        ring.alpha = math.floor(255 * (1 - ring.time / 1.5))
        if ring.time > 1.5 then
            table.remove(sonarState.pulseRings, i)
        end
    end

    -- 更新检测到的物体（淡出）
    for i = #sonarState.detectedObjects, 1, -1 do
        local obj = sonarState.detectedObjects[i]
        obj.lifetime = obj.lifetime - dt
        if obj.lifetime <= 0 then
            table.remove(sonarState.detectedObjects, i)
        end
    end
end

--- 生成随机检测物体
function Sonar.GenerateDetections(gameTime)
    -- 清除旧的检测
    sonarState.detectedObjects = {}

    -- 随机生成 1~4 个检测点
    local count = math.random(1, 4)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local dist = 8 + math.random() * 15  -- 距离中心 8~23 像素
        local threat = math.random()           -- 0~1 威胁度

        local color = "green"
        if threat > 0.7 then
            color = "red"
        elseif threat > 0.4 then
            color = "yellow"
        end

        table.insert(sonarState.detectedObjects, {
            x = math.cos(angle) * dist,
            y = math.sin(angle) * dist,
            color = color,
            size = 2 + threat * 3,
            lifetime = 2.5 + math.random() * 1.0,
            maxLife = 2.5 + math.random() * 1.0,
            pulse = math.random() * math.pi * 2,
        })
    end
end

--- 绘制声呐增强效果（覆盖在声呐设备上方）
--- 此函数在舱室渲染之后调用，渲染增强的声呐脉冲
---@param vg userdata
---@param sonarScreenX number 声呐屏幕中心X（世界坐标）
---@param sonarScreenY number 声呐屏幕中心Y
---@param radius number 声呐屏幕半径
---@param gameTime number
function Sonar.DrawEnhanced(vg, sonarScreenX, sonarScreenY, radius, gameTime)
    local cx = sonarScreenX
    local cy = sonarScreenY

    -- 声呐背景增强（更暗的绿色）
    local bgGrad = nvgRadialGradient(vg, cx, cy, 0, radius,
        nvgRGBA(5, 30, 15, 200), nvgRGBA(0, 10, 5, 240))
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 网格线（同心圆）
    for ring = 1, 3 do
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius * ring / 3)
        nvgStrokeColor(vg, nvgRGBA(30, 100, 50, 60))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)
    end

    -- 十字准线
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - radius, cy)
    nvgLineTo(vg, cx + radius, cy)
    nvgMoveTo(vg, cx, cy - radius)
    nvgLineTo(vg, cx, cy + radius)
    nvgStrokeColor(vg, nvgRGBA(30, 100, 50, 40))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 扫描扇面（亮绿色渐变尾巴）
    local sweepAng = sonarState.sweepAngle
    local tailAngle = 0.8  -- 尾部角度范围

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgArc(vg, 0, 0, radius - 2, sweepAng - tailAngle, sweepAng, 1)
    nvgClosePath(vg)
    -- 扇面渐变
    local sweepGrad = nvgRadialGradient(vg, 0, 0, 0, radius,
        nvgRGBA(50, 255, 100, 0), nvgRGBA(50, 255, 100, 80))
    nvgFillPaint(vg, sweepGrad)
    nvgFill(vg)

    -- 扫描前端亮线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgLineTo(vg, math.cos(sweepAng) * (radius - 2), math.sin(sweepAng) * (radius - 2))
    nvgStrokeColor(vg, nvgRGBA(80, 255, 130, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgRestore(vg)

    -- 脉冲扩散环
    for _, ring in ipairs(sonarState.pulseRings) do
        if ring.alpha > 0 then
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, ring.radius)
            nvgStrokeColor(vg, nvgRGBA(80, 255, 130, ring.alpha))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    end

    -- 检测到的物体（黄色/红色点）
    for _, obj in ipairs(sonarState.detectedObjects) do
        local fadeAlpha = math.min(1, obj.lifetime / (obj.maxLife * 0.3))
        local pulseFactor = 0.8 + math.sin(gameTime * 8 + obj.pulse) * 0.2
        local objAlpha = math.floor(200 * fadeAlpha * pulseFactor)

        local r, g, b = 50, 200, 100
        if obj.color == "yellow" then
            r, g, b = 240, 220, 50
        elseif obj.color == "red" then
            r, g, b = 240, 60, 60
        end

        -- 物体点
        nvgBeginPath(vg)
        nvgCircle(vg, cx + obj.x, cy + obj.y, obj.size * pulseFactor)
        nvgFillColor(vg, nvgRGBA(r, g, b, objAlpha))
        nvgFill(vg)

        -- 物体光晕
        local glowGrad = nvgRadialGradient(vg, cx + obj.x, cy + obj.y,
            0, obj.size * 3,
            nvgRGBA(r, g, b, math.floor(objAlpha * 0.3)),
            nvgRGBA(r, g, b, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx + obj.x, cy + obj.y, obj.size * 3)
        nvgFillPaint(vg, glowGrad)
        nvgFill(vg)
    end

    -- 外框亮绿
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgStrokeColor(vg, nvgRGBA(50, 200, 80, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

return Sonar
