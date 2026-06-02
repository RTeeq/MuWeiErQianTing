--- 驾驶舱渲染：舵盘、油门档位、深度控制、声呐屏幕、探照灯控制
local Config = require("Config")

local Cockpit = {}

-- ============================================================
-- 舵盘（Helm Wheel）
-- ============================================================

--- 绘制舵盘
---@param vg userdata
---@param cx number 中心X
---@param cy number 中心Y
---@param radius number 半径
---@param angle number 当前舵角 (-90~+90)
---@param gameTime number
local function DrawHelmWheel(vg, cx, cy, radius, angle, gameTime)
    -- 外圈底盘
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius + 4)
    nvgFillColor(vg, nvgRGBA(15, 25, 40, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 100, 140, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 刻度环
    for i = -9, 9 do
        local deg = i * 10
        local rad = math.rad(deg - 90)  -- 0度在正上方
        local inner = radius - 8
        local outer = radius - 2
        if i % 3 == 0 then
            inner = radius - 12
            nvgStrokeWidth(vg, 2)
        else
            nvgStrokeWidth(vg, 1)
        end
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + math.cos(rad) * inner, cy + math.sin(rad) * inner)
        nvgLineTo(vg, cx + math.cos(rad) * outer, cy + math.sin(rad) * outer)
        nvgStrokeColor(vg, nvgRGBA(80, 140, 180, 150))
        nvgStroke(vg)
    end

    -- 旋转的舵盘本体
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, math.rad(angle))

    -- 中心圆
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, radius * 0.25)
    nvgFillColor(vg, nvgRGBA(40, 60, 90, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 160, 220, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 辐条（6根）
    for i = 0, 5 do
        local rad = i * math.pi / 3
        nvgBeginPath(vg)
        nvgMoveTo(vg, math.cos(rad) * radius * 0.25, math.sin(rad) * radius * 0.25)
        nvgLineTo(vg, math.cos(rad) * radius * 0.75, math.sin(rad) * radius * 0.75)
        nvgStrokeColor(vg, nvgRGBA(100, 180, 240, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        -- 辐条端部小圆
        nvgBeginPath(vg)
        nvgCircle(vg, math.cos(rad) * radius * 0.75, math.sin(rad) * radius * 0.75, 4)
        nvgFillColor(vg, nvgRGBA(60, 120, 180, 220))
        nvgFill(vg)
    end

    -- 外环
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, radius * 0.75)
    nvgStrokeColor(vg, nvgRGBA(80, 150, 200, 180))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    nvgRestore(vg)

    -- 当前角度指示器（固定在顶部）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy - radius - 8)
    nvgLineTo(vg, cx - 5, cy - radius - 15)
    nvgLineTo(vg, cx + 5, cy - radius - 15)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 100, 80, 220))
    nvgFill(vg)

    -- 角度数值
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 230, 255, 220))
    nvgText(vg, cx, cy + radius + 8, string.format("%.0f°", angle), nil)
end

-- ============================================================
-- 油门档位指示
-- ============================================================

--- 绘制油门档位
---@param vg userdata
---@param x number 左上角X
---@param y number 左上角Y
---@param gear number 当前档位 (0=R, 1=Stop, 2=G1, 3=G2, 4=G3, 5=G4)
---@param gameTime number
local function DrawThrottle(vg, x, y, gear, gameTime)
    local gearLabels = {"R", "0", "1", "2", "3", "4"}
    local gearColors = {
        {255, 80, 80},   -- Reverse
        {150, 150, 150}, -- Stop
        {80, 200, 120},  -- Gear1
        {100, 220, 150}, -- Gear2
        {150, 240, 100}, -- Gear3
        {200, 255, 80},  -- Gear4
    }
    local slotW = 36
    local slotH = 28
    local gap = 4
    local totalH = (#gearLabels) * (slotH + gap) - gap

    -- 背景面板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 8, y - 8, slotW + 16, totalH + 16, 6)
    nvgFillColor(vg, nvgRGBA(10, 20, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 90, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 180, 220, 180))
    nvgText(vg, x + slotW * 0.5, y - 12, "THROTTLE", nil)

    -- 每个档位槽
    for i, label in ipairs(gearLabels) do
        local sy = y + (i - 1) * (slotH + gap)
        local isActive = (gear == (i - 1))  -- gear 0-based index maps to label index 1-based

        -- 槽背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, sy, slotW, slotH, 4)
        if isActive then
            local c = gearColors[i]
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 180))
        else
            nvgFillColor(vg, nvgRGBA(25, 35, 50, 180))
        end
        nvgFill(vg)

        -- 槽边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, sy, slotW, slotH, 4)
        if isActive then
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 1.5)
        else
            nvgStrokeColor(vg, nvgRGBA(60, 80, 100, 120))
            nvgStrokeWidth(vg, 1)
        end
        nvgStroke(vg)

        -- 标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 240))
        else
            nvgFillColor(vg, nvgRGBA(120, 150, 180, 160))
        end
        nvgText(vg, x + slotW * 0.5, sy + slotH * 0.5, label, nil)
    end
end

-- ============================================================
-- 深度控制滑块
-- ============================================================

--- 绘制深度控制
---@param vg userdata
---@param x number
---@param y number
---@param height number 滑块高度
---@param currentDepth number 当前实际深度
---@param targetDepth number 目标深度
---@param gameTime number
local function DrawDepthControl(vg, x, y, height, currentDepth, targetDepth, gameTime)
    local depthMin = Config.Driving.depth.minDepth
    local depthMax = Config.Driving.depth.maxDepth
    local sliderW = 24
    local labelW = 60

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 10, y - 20, sliderW + labelW + 20, height + 40, 6)
    nvgFillColor(vg, nvgRGBA(10, 20, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 90, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 180, 220, 180))
    nvgText(vg, x + sliderW * 0.5, y - 6, "DEPTH", nil)

    -- 滑轨
    local trackX = x + sliderW * 0.5
    nvgBeginPath(vg)
    nvgMoveTo(vg, trackX, y)
    nvgLineTo(vg, trackX, y + height)
    nvgStrokeColor(vg, nvgRGBA(40, 70, 100, 200))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    -- 刻度标记
    local numMarks = 8
    for i = 0, numMarks do
        local t = i / numMarks
        local my = y + t * height
        local depthAtMark = depthMin + t * (depthMax - depthMin)
        nvgBeginPath(vg)
        nvgMoveTo(vg, trackX - 6, my)
        nvgLineTo(vg, trackX + 6, my)
        nvgStrokeColor(vg, nvgRGBA(60, 100, 140, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 深度标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 150, 180, 150))
        nvgText(vg, trackX + 14, my, string.format("%dm", math.floor(depthAtMark)), nil)
    end

    -- 当前深度指示（蓝色横线）
    local currentT = (currentDepth - depthMin) / (depthMax - depthMin)
    currentT = math.max(0, math.min(1, currentT))
    local currentY = y + currentT * height
    nvgBeginPath(vg)
    nvgCircle(vg, trackX, currentY, 5)
    nvgFillColor(vg, nvgRGBA(80, 180, 255, 220))
    nvgFill(vg)

    -- 目标深度指示（绿色三角）
    local targetT = (targetDepth - depthMin) / (depthMax - depthMin)
    targetT = math.max(0, math.min(1, targetT))
    local targetY = y + targetT * height
    nvgBeginPath(vg)
    nvgMoveTo(vg, trackX - 10, targetY)
    nvgLineTo(vg, trackX - 4, targetY - 5)
    nvgLineTo(vg, trackX - 4, targetY + 5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(80, 255, 120, 220))
    nvgFill(vg)

    -- 数值显示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(80, 200, 255, 220))
    nvgText(vg, x + sliderW * 0.5, y + height + 8, string.format("%dm", math.floor(currentDepth)), nil)
    nvgFontSize(vg, 8)
    nvgFillColor(vg, nvgRGBA(80, 255, 120, 180))
    nvgText(vg, x + sliderW * 0.5, y + height + 22, string.format("→%dm", math.floor(targetDepth)), nil)
end

-- ============================================================
-- 声呐屏幕
-- ============================================================

--- 绘制声呐屏幕
---@param vg userdata
---@param cx number
---@param cy number
---@param radius number
---@param sonarData table
---@param gameTime number
local function DrawSonarScreen(vg, cx, cy, radius, sonarData, gameTime)
    if not sonarData then return end

    -- 外壳
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius + 3)
    nvgFillColor(vg, nvgRGBA(20, 30, 20, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(40, 80, 40, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 背景暗绿
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillColor(vg, nvgRGBA(5, 20, 5, 240))
    nvgFill(vg)

    -- 同心圈
    for i = 1, 3 do
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius * i / 4)
        nvgStrokeColor(vg, nvgRGBA(20, 60, 20, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- 十字线
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - radius, cy)
    nvgLineTo(vg, cx + radius, cy)
    nvgMoveTo(vg, cx, cy - radius)
    nvgLineTo(vg, cx, cy + radius)
    nvgStrokeColor(vg, nvgRGBA(20, 60, 20, 100))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 扫描线（旋转的绿色扇形）
    local scanAngle = sonarData.scanAngle or (gameTime * Config.Sonar.scanSpeed * math.pi * 2)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, scanAngle)
    -- 扇形渐变
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgArc(vg, 0, 0, radius, -0.3, 0, 1)
    nvgClosePath(vg)
    local sweepGrad = nvgLinearGradient(vg, 0, 0, radius * 0.7, 0,
        nvgRGBA(0, 200, 0, 100), nvgRGBA(0, 80, 0, 0))
    nvgFillPaint(vg, sweepGrad)
    nvgFill(vg)
    -- 扫描线本身
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgLineTo(vg, radius, 0)
    nvgStrokeColor(vg, nvgRGBA(0, 255, 0, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgRestore(vg)

    -- 脉冲动画（发出脉冲时的扩散圈）
    if sonarData.pulsing then
        local pulseT = sonarData.pulseTimer or 0
        local maxDur = Config.Sonar.pulseDuration
        local progress = math.min(1, pulseT / maxDur)
        local pulseR = radius * progress
        local alpha = math.floor(180 * (1 - progress))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, pulseR)
        nvgStrokeColor(vg, nvgRGBA(0, 255, 100, alpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 光标（blips）
    if sonarData.blips then
        for _, blip in ipairs(sonarData.blips) do
            local age = blip.age or 0
            local fadeTime = Config.Sonar.blipFadeTime
            local alpha = math.max(0, 1 - age / fadeTime)
            local bx = cx + (blip.x or 0) / Config.Sonar.pulseRange * radius
            local by = cy + (blip.y or 0) / Config.Sonar.pulseRange * radius
            -- 确保在圆内
            local dist = math.sqrt((bx - cx)^2 + (by - cy)^2)
            if dist < radius then
                nvgBeginPath(vg)
                nvgCircle(vg, bx, by, 3 + alpha * 2)
                nvgFillColor(vg, nvgRGBA(0, 255, 80, math.floor(alpha * 220)))
                nvgFill(vg)
            end
        end
    end

    -- 脉冲冷却指示
    local cooldown = sonarData.pulseCooldown or 0
    if cooldown > 0 then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 80, 180))
        nvgText(vg, cx, cy + radius + 6, string.format("CD: %.1fs", cooldown), nil)
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(0, 200, 100, 180))
        nvgText(vg, cx, cy + radius + 6, "READY", nil)
    end
end

-- ============================================================
-- 探照灯控制
-- ============================================================

--- 绘制探照灯控制面板
---@param vg userdata
---@param x number
---@param y number
---@param driving table 驾驶数据
---@param gameTime number
local function DrawSearchlightPanel(vg, x, y, driving, gameTime)
    local panelW = 100
    local panelH = 60

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, panelW, panelH, 5)
    nvgFillColor(vg, nvgRGBA(10, 20, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 90, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 180, 220, 180))
    nvgText(vg, x + panelW * 0.5, y + 4, "SEARCHLIGHT", nil)

    -- 开关状态灯
    local isOn = driving and driving.searchlightOn or false
    nvgBeginPath(vg)
    nvgCircle(vg, x + 20, y + 35, 8)
    if isOn then
        nvgFillColor(vg, nvgRGBA(255, 240, 100, math.floor(200 + 40 * math.sin(gameTime * 3))))
    else
        nvgFillColor(vg, nvgRGBA(50, 50, 50, 180))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 100, 80, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 角度显示
    local angle = driving and driving.searchlightAngle or 0
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 220, 240, 200))
    nvgText(vg, x + 35, y + 35, string.format("%.0f°", angle), nil)

    -- 范围条
    local range = driving and driving.searchlightRange or 200
    local rangeNorm = (range - Config.Searchlight.minRange) / (Config.Searchlight.maxRange - Config.Searchlight.minRange)
    rangeNorm = math.max(0, math.min(1, rangeNorm))
    local barX = x + 35
    local barY = y + 46
    local barW = panelW - 45
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, 6, 2)
    nvgFillColor(vg, nvgRGBA(30, 40, 50, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * rangeNorm, 6, 2)
    nvgFillColor(vg, nvgRGBA(255, 230, 100, 180))
    nvgFill(vg)
end

-- ============================================================
-- 压载水舱面板（工程师/机械师）
-- ============================================================

--- 绘制压载水舱状态面板
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param ballastData table
---@param gameTime number
function Cockpit.DrawBallastPanel(vg, w, h, ballastData, gameTime)
    if not ballastData then return end

    local panelW = 160
    local panelH = 120
    local px = 15
    local py = h - panelH - 80  -- 左下角靠上

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 140, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 180, 220, 220))
    nvgText(vg, px + panelW * 0.5, py + 6, "BALLAST TANKS", nil)

    -- 每个水舱
    local tanks = ballastData.tanks or ballastData
    local tankCount = 0
    if type(tanks) == "table" then
        for _ in pairs(tanks) do tankCount = tankCount + 1 end
    end
    if tankCount == 0 then return end

    local tankW = (panelW - 30) / math.max(1, tankCount)
    local tankH = 60
    local startX = px + 15
    local startY = py + 28

    local idx = 0
    for i, tank in pairs(tanks) do
        local tx = startX + idx * (tankW + 5)
        idx = idx + 1

        local level = 50
        local breached = false
        if type(tank) == "table" then
            level = tank.level or 50
            breached = tank.breached or false
        elseif type(tank) == "number" then
            level = tank
        end

        -- 水舱容器
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, startY, tankW, tankH, 3)
        nvgFillColor(vg, nvgRGBA(15, 25, 40, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, breached and nvgRGBA(255, 80, 80, 200) or nvgRGBA(50, 80, 120, 180))
        nvgStrokeWidth(vg, breached and 2 or 1)
        nvgStroke(vg)

        -- 水位填充
        local fillH = tankH * (level / 100)
        local fillY = startY + tankH - fillH
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx + 1, fillY, tankW - 2, fillH - 1, 2)
        if breached then
            nvgFillColor(vg, nvgRGBA(200, 60, 60, math.floor(150 + 50 * math.sin(gameTime * 4))))
        else
            nvgFillColor(vg, nvgRGBA(40, 120, 200, 180))
        end
        nvgFill(vg)

        -- 标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 210, 240, 200))
        nvgText(vg, tx + tankW * 0.5, startY + tankH + 4, string.format("%d%%", math.floor(level)), nil)
    end

    -- 浮力偏差显示
    local totalLevel = 0
    local count = 0
    if type(tanks) == "table" then
        for _, tank in pairs(tanks) do
            if type(tank) == "table" then
                totalLevel = totalLevel + (tank.level or 50)
            elseif type(tank) == "number" then
                totalLevel = totalLevel + tank
            end
            count = count + 1
        end
    end
    local avgLevel = count > 0 and (totalLevel / count) or 50
    local buoyancy = (50 - avgLevel) / 50  -- positive = rising, negative = sinking

    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    if buoyancy > 0.05 then
        nvgFillColor(vg, nvgRGBA(80, 255, 120, 200))
        nvgText(vg, px + panelW * 0.5, py + panelH - 4, string.format("BUOYANCY: +%.1f", buoyancy), nil)
    elseif buoyancy < -0.05 then
        nvgFillColor(vg, nvgRGBA(255, 120, 80, 200))
        nvgText(vg, px + panelW * 0.5, py + panelH - 4, string.format("BUOYANCY: %.1f", buoyancy), nil)
    else
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 160))
        nvgText(vg, px + panelW * 0.5, py + panelH - 4, "NEUTRAL", nil)
    end
end

-- ============================================================
-- 主绘制入口
-- ============================================================

--- 绘制完整驾驶舱面板
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param renderSub table 潜艇渲染数据
---@param drivingState table 本地驾驶状态
---@param gameTime number
function Cockpit.Draw(vg, w, h, renderSub, drivingState, gameTime)
    local driving = renderSub and renderSub.driving or {}
    local physics = renderSub and renderSub.physics or {}
    local sonar = renderSub and renderSub.sonar or {}

    -- 布局：底部中央区域
    local panelY = h - 200

    -- 1. 舵盘（底部中央偏左）
    local helmRadius = Config.Driving.helm.dragRadius or 80
    local helmCX = w * 0.35
    local helmCY = panelY + 90
    DrawHelmWheel(vg, helmCX, helmCY, helmRadius, drivingState.helmAngle, gameTime)

    -- 2. 油门档位（舵盘右侧）
    DrawThrottle(vg, w * 0.5 + 20, panelY + 20, drivingState.throttleGear, gameTime)

    -- 3. 深度控制（右侧）
    local depthX = w * 0.5 + 80
    local currentDepth = physics.depth or 2400
    DrawDepthControl(vg, depthX, panelY - 10, 160, currentDepth, drivingState.targetDepth, gameTime)

    -- 4. 声呐屏幕（左下角）
    local sonarR = 55
    local sonarCX = 80
    local sonarCY = panelY + 40
    DrawSonarScreen(vg, sonarCX, sonarCY, sonarR, sonar, gameTime)

    -- 5. 探照灯控制（声呐下方）
    DrawSearchlightPanel(vg, 20, panelY + 110, driving, gameTime)

    -- 6. 速度/航向信息条（顶部横条）
    DrawDrivingInfoBar(vg, w, panelY - 30, physics, driving, gameTime)
end

--- 绘制航行信息横条
---@param vg userdata
---@param w number
---@param y number
---@param physics table
---@param driving table
---@param gameTime number
function DrawDrivingInfoBar(vg, w, y, physics, driving, gameTime)
    local barH = 22
    local barW = w * 0.6
    local barX = (w - barW) * 0.5

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, y, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(10, 20, 35, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 90, 120, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 内容
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local midY = y + barH * 0.5

    -- 航速
    local speed = physics.speed or 0
    nvgFillColor(vg, nvgRGBA(80, 200, 255, 220))
    nvgText(vg, barX + 10, midY, string.format("SPD: %.1f kn", speed), nil)

    -- 航向
    local heading = physics.heading or 0
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgText(vg, barX + 110, midY, string.format("HDG: %.0f°", heading), nil)

    -- 垂直速度
    local vSpeed = physics.verticalSpeed or 0
    if math.abs(vSpeed) > 0.5 then
        if vSpeed > 0 then
            nvgFillColor(vg, nvgRGBA(255, 120, 80, 200))
            nvgText(vg, barX + 210, midY, string.format("DIVE: %.1f m/s", vSpeed), nil)
        else
            nvgFillColor(vg, nvgRGBA(80, 255, 120, 200))
            nvgText(vg, barX + 210, midY, string.format("RISE: %.1f m/s", math.abs(vSpeed)), nil)
        end
    else
        nvgFillColor(vg, nvgRGBA(150, 180, 200, 140))
        nvgText(vg, barX + 210, midY, "LEVEL", nil)
    end

    -- 惯性延迟指示
    local inertia = driving.helmAngle or 0
    if math.abs(inertia) > 5 then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 180))
        local turnDir = inertia > 0 and "→" or "←"
        nvgText(vg, barX + barW - 10, midY, string.format("TURN %s", turnDir), nil)
    end
end

return Cockpit
