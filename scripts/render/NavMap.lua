--- 导航地图渲染：当前位置、航点、路线、偏航警告
local Config = require("Config")

local NavMap = {}

-- ============================================================
-- 辅助绘制函数（必须在 Draw 之前定义）
-- ============================================================

--- 绘制网格
local function DrawGrid(vg, x, y, w, h)
    local gridSize = 40
    nvgStrokeColor(vg, nvgRGBA(20, 40, 60, 100))
    nvgStrokeWidth(vg, 0.5)

    for gx = 0, w, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + gx, y)
        nvgLineTo(vg, x + gx, y + h)
        nvgStroke(vg)
    end
    for gy = 0, h, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, y + gy)
        nvgLineTo(vg, x + w, y + gy)
        nvgStroke(vg)
    end
end

--- 绘制已探索区域
local function DrawExploredAreas(vg, x, y, w, h, navData, gameTime)
    if not navData.explored then return end
    for _, area in ipairs(navData.explored) do
        local ax = x + (area.x or 0) / 10000 * w
        local ay = y + (area.y or 0) / 10000 * h
        local ar = (area.radius or 500) / 10000 * w
        nvgBeginPath(vg)
        nvgCircle(vg, ax, ay, ar)
        nvgFillColor(vg, nvgRGBA(20, 40, 60, 80))
        nvgFill(vg)
    end
end

--- 绘制危险区域
local function DrawDangerZones(vg, x, y, w, h, navData, gameTime)
    if not navData.dangerZones then return end
    for _, zone in ipairs(navData.dangerZones) do
        local zx = x + (zone.x or 0) / 10000 * w
        local zy = y + (zone.y or 0) / 10000 * h
        local zr = (zone.radius or 300) / 10000 * w
        local alpha = math.floor(60 + 30 * math.sin(gameTime * 2))
        nvgBeginPath(vg)
        nvgCircle(vg, zx, zy, zr)
        nvgFillColor(vg, nvgRGBA(200, 40, 40, alpha))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 80, alpha + 40))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
end

--- 绘制航路线
local function DrawRoute(vg, x, y, w, h, navData, physData)
    local waypoints = navData.waypoints
    if not waypoints or #waypoints < 1 then return end

    -- 从当前位置到第一个航点
    local posX = (physData and physData.posX or 0)
    local posY2 = (physData and physData.posY or 0)
    local curMX = x + posX / 10000 * w
    local curMY = y + posY2 / 10000 * h

    nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 120))
    nvgStrokeWidth(vg, 1.5)

    -- 当前位置 → 当前目标航点
    local currentWP = navData.currentWP or 1
    if currentWP >= 1 and currentWP <= #waypoints then
        local wp = waypoints[currentWP]
        local wpMX = x + (wp.x or 0) / 10000 * w
        local wpMY = y + (wp.y or 0) / 10000 * h
        nvgBeginPath(vg)
        nvgMoveTo(vg, curMX, curMY)
        nvgLineTo(vg, wpMX, wpMY)
        -- 虚线效果
        nvgStrokeColor(vg, nvgRGBA(80, 255, 160, 150))
        nvgStroke(vg)
    end

    -- 航点之间连线
    nvgStrokeColor(vg, nvgRGBA(60, 120, 180, 100))
    nvgStrokeWidth(vg, 1)
    for i = 1, #waypoints - 1 do
        local wp1 = waypoints[i]
        local wp2 = waypoints[i + 1]
        local x1 = x + (wp1.x or 0) / 10000 * w
        local y1 = y + (wp1.y or 0) / 10000 * h
        local x2 = x + (wp2.x or 0) / 10000 * w
        local y2 = y + (wp2.y or 0) / 10000 * h
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStroke(vg)
    end
end

--- 绘制航点标记
local function DrawWaypoints(vg, x, y, w, h, navData, gameTime)
    local waypoints = navData.waypoints
    if not waypoints then return end
    local currentWP = navData.currentWP or 1

    for i, wp in ipairs(waypoints) do
        local wpX = x + (wp.x or 0) / 10000 * w
        local wpY = y + (wp.y or 0) / 10000 * h
        local isCurrent = (i == currentWP)
        local isPast = (i < currentWP)

        -- 航点圆形
        nvgBeginPath(vg)
        nvgCircle(vg, wpX, wpY, isCurrent and 6 or 4)
        if isPast then
            nvgFillColor(vg, nvgRGBA(80, 80, 100, 120))
        elseif isCurrent then
            local pulse = math.floor(200 + 55 * math.sin(gameTime * 3))
            nvgFillColor(vg, nvgRGBA(80, 255, 160, pulse))
        else
            nvgFillColor(vg, nvgRGBA(100, 180, 255, 180))
        end
        nvgFill(vg)

        -- 边框
        if isCurrent then
            nvgBeginPath(vg)
            nvgCircle(vg, wpX, wpY, 9)
            nvgStrokeColor(vg, nvgRGBA(80, 255, 160, 150))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 序号
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 220, 240, 180))
        nvgText(vg, wpX, wpY - 8, tostring(i), nil)
    end
end

--- 绘制当前位置和航向箭头
local function DrawCurrentPosition(vg, x, y, w, h, physData, gameTime)
    if not physData then return end

    local posX = physData.posX or 0
    local posY2 = physData.posY or 0
    local heading = physData.heading or 0

    local curX = x + posX / 10000 * w
    local curY = y + posY2 / 10000 * h

    -- 确保在地图范围内
    curX = math.max(x, math.min(x + w, curX))
    curY = math.max(y, math.min(y + h, curY))

    -- 航向箭头
    nvgSave(vg)
    nvgTranslate(vg, curX, curY)
    nvgRotate(vg, math.rad(heading - 90))  -- heading 0 = 北方（上）

    -- 三角形箭头
    nvgBeginPath(vg)
    nvgMoveTo(vg, 10, 0)
    nvgLineTo(vg, -5, -6)
    nvgLineTo(vg, -5, 6)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
    nvgFill(vg)

    nvgRestore(vg)

    -- 位置脉冲圈
    local pulse = math.sin(gameTime * 2) * 0.5 + 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, curX, curY, 4 + pulse * 3)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(150 - pulse * 100)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

--- 绘制偏航警告
local function DrawDeviationWarning(vg, mapX, mapY, mapW, mapH, navData, gameTime)
    local deviation = navData.deviation or 0
    local warnThreshold = Config.Navigation.deviationWarning
    local alarmThreshold = Config.Navigation.deviationAlarm

    if deviation < warnThreshold then return end

    local isAlarm = deviation >= alarmThreshold
    local alpha = math.floor(150 + 100 * math.sin(gameTime * (isAlarm and 6 or 3)))

    -- 警告边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mapX + 2, mapY + 2, mapW - 4, mapH - 4, 6)
    if isAlarm then
        nvgStrokeColor(vg, nvgRGBA(255, 40, 40, alpha))
    else
        nvgStrokeColor(vg, nvgRGBA(255, 180, 40, alpha))
    end
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 警告文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if isAlarm then
        nvgFillColor(vg, nvgRGBA(255, 60, 60, alpha))
        nvgText(vg, mapX + mapW * 0.5, mapY + mapH - 55,
            string.format("!! DEVIATION ALARM: %dm !!", math.floor(deviation)), nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 200, 60, alpha))
        nvgText(vg, mapX + mapW * 0.5, mapY + mapH - 55,
            string.format("WARNING: Off course %dm", math.floor(deviation)), nil)
    end
end

--- 绘制底部导航信息
local function DrawNavInfo(vg, x, y, w, navData, physData)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local midY = y + 12

    -- 当前航点 / 总航点
    local currentWP = navData.currentWP or 0
    local totalWP = navData.waypoints and #navData.waypoints or 0
    nvgFillColor(vg, nvgRGBA(150, 200, 230, 200))
    nvgText(vg, x + 15, midY, string.format("WP: %d/%d", currentWP, totalWP), nil)

    -- 偏差距离
    local deviation = navData.deviation or 0
    nvgText(vg, x + 90, midY, string.format("DEV: %dm", math.floor(deviation)), nil)

    -- 坐标
    local posX = physData and physData.posX or 0
    local posY2 = physData and physData.posY or 0
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 160, 190, 160))
    nvgText(vg, x + w - 15, midY, string.format("X:%.0f Y:%.0f", posX, posY2), nil)
end

-- ============================================================
-- 主绘制入口
-- ============================================================

--- 绘制导航地图叠加层
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param navData table 导航数据
---@param physData table 物理数据（位置/航向）
---@param gameTime number
function NavMap.Draw(vg, w, h, navData, physData, gameTime)
    if not navData then return end

    local mapW = Config.Navigation.mapWidth
    local mapH = Config.Navigation.mapHeight
    local mapX = (w - mapW) * 0.5
    local mapY = (h - mapH) * 0.5

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 地图面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mapX, mapY, mapW, mapH, 8)
    nvgFillColor(vg, nvgRGBA(8, 15, 30, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 160, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 240))
    nvgText(vg, mapX + mapW * 0.5, mapY + 8, "NAVIGATION MAP", nil)

    -- 地图内容区域
    local contentX = mapX + 15
    local contentY = mapY + 30
    local contentW = mapW - 30
    local contentH = mapH - 60

    -- 网格线
    DrawGrid(vg, contentX, contentY, contentW, contentH)

    -- 已探索区域（暗色填充）
    DrawExploredAreas(vg, contentX, contentY, contentW, contentH, navData, gameTime)

    -- 危险区域
    DrawDangerZones(vg, contentX, contentY, contentW, contentH, navData, gameTime)

    -- 航路线（连接航点）
    DrawRoute(vg, contentX, contentY, contentW, contentH, navData, physData)

    -- 航点标记
    DrawWaypoints(vg, contentX, contentY, contentW, contentH, navData, gameTime)

    -- 当前位置和航向
    DrawCurrentPosition(vg, contentX, contentY, contentW, contentH, physData, gameTime)

    -- 偏航警告
    DrawDeviationWarning(vg, mapX, mapY, mapW, mapH, navData, gameTime)

    -- 底部信息栏
    DrawNavInfo(vg, mapX, mapY + mapH - 24, mapW, navData, physData)

    -- 关闭提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(150, 180, 210, 140))
    nvgText(vg, w * 0.5, h - 15, "按 M 关闭导航地图", nil)
end

return NavMap
