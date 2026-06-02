--- HUD 渲染：科幻工业风状态条 + 危机交互提示
local Config = require("Config")

local HUD = {}

--- 绘制完整 HUD
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param sub table 潜艇数据
---@param gameTime number
---@param crisisInfo table|nil 当前危机交互信息
function HUD.Draw(vg, w, h, sub, gameTime, crisisInfo)
    -- 左上角状态面板
    HUD.DrawStatusPanel(vg, 15, 15, sub, gameTime)

    -- 右上角信息
    HUD.DrawInfoPanel(vg, w - 180, 15, sub, gameTime)

    -- 气压警告与低压屏幕变暗
    HUD.DrawPressureWarning(vg, w, h, sub, gameTime)

    -- 导航偏航警报（顶部居中偏右）
    HUD.DrawNavigationAlert(vg, w, h, sub, gameTime)

    -- 底部中央危机交互提示
    HUD.DrawInteractionHint(vg, w, h, crisisInfo, gameTime)
end

--- 绘制状态面板（氧气/船体/电力/深度）
function HUD.DrawStatusPanel(vg, px, py, sub, gameTime)
    local panelW = 200
    local panelH = 128
    local c = Config.Colors

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(c.hudBg[1], c.hudBg[2], c.hudBg[3], c.hudBg[4]))
    nvgFill(vg)

    -- 面板边框（科幻蓝光）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgStrokeColor(vg, nvgRGBA(c.hudBorder[1], c.hudBorder[2], c.hudBorder[3], 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 角落装饰线
    local cornerLen = 12
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 2, py + cornerLen)
    nvgLineTo(vg, px + 2, py + 2)
    nvgLineTo(vg, px + cornerLen, py + 2)
    nvgStrokeColor(vg, nvgRGBA(c.hudBorder[1], c.hudBorder[2], c.hudBorder[3], 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 四个状态条
    local barX = px + 12
    local barW = panelW - 24
    local barH = 14
    local gap = 26

    -- O2 氧气条（蓝色）
    HUD.DrawBar(vg, barX, py + 16, barW, barH,
        sub.oxygen / Config.Game.maxOxygen,
        c.hudOxygen, "O2", gameTime)

    -- HULL 船体完整度（绿色）
    HUD.DrawBar(vg, barX, py + 16 + gap, barW, barH,
        sub.hull / Config.Game.maxHull,
        c.hudHull, "HULL", gameTime)

    -- PWR 电力（黄色）
    HUD.DrawBar(vg, barX, py + 16 + gap * 2, barW, barH,
        sub.power / Config.Game.maxPower,
        c.hudPower, "PWR", gameTime)

    -- DEPTH 深度条（白色，显示当前深度占最大深度百分比）
    local depth = sub.depth or 0
    local maxDepth = Config.Game.maxDepth or 10000
    local depthColor = {200, 220, 255}
    HUD.DrawBar(vg, barX, py + 16 + gap * 3, barW, barH,
        depth / maxDepth,
        depthColor, "DEP", gameTime)

    -- 深度数值叠加显示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, 200))
    nvgText(vg, px + panelW * 0.5 + 10, py + 16 + gap * 3 + barH * 0.5,
        string.format("%dm", math.floor(depth)), nil)
end

--- 绘制单个状态条
function HUD.DrawBar(vg, x, y, w, h, percent, color, label, gameTime)
    local c = Config.Colors

    -- 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(c.hudText[1], c.hudText[2], c.hudText[3], 200))
    nvgText(vg, x, y + h * 0.5, label, nil)

    -- 条形背景
    local barX = x + 38
    local barW = w - 38
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, y, barW, h, 3)
    nvgFillColor(vg, nvgRGBA(20, 25, 35, 200))
    nvgFill(vg)

    -- 条形填充
    local fillW = barW * math.max(0, math.min(1, percent))
    if fillW > 1 then
        local grad = nvgLinearGradient(vg, barX, y, barX + fillW, y,
            nvgRGBA(color[1], color[2], color[3], 255),
            nvgRGBA(color[1], color[2], color[3], 180))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, y, fillW, h, 3)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- 低值警告闪烁
    if percent < 0.25 then
        local flash = math.sin(gameTime * 5) > 0
        if flash then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, y, fillW, h, 3)
            nvgFillColor(vg, nvgRGBA(255, 50, 50, 80))
            nvgFill(vg)
        end
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, y, barW, h, 3)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 百分比数值
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(c.hudText[1], c.hudText[2], c.hudText[3], 180))
    nvgText(vg, barX + barW - 4, y + h * 0.5, string.format("%d%%", math.floor(percent * 100)), nil)
end

--- 绘制右上角小地图（舱室布局 + 玩家位置）
function HUD.DrawInfoPanel(vg, px, py, sub, gameTime)
    local panelW = 200
    local panelH = 70
    local c = Config.Colors

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(c.hudBg[1], c.hudBg[2], c.hudBg[3], c.hudBg[4]))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgStrokeColor(vg, nvgRGBA(c.hudBorder[1], c.hudBorder[2], c.hudBorder[3], 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.hudText[1], c.hudText[2], c.hudText[3], 150))
    nvgText(vg, px + 6, py + 3, "MAP", nil)

    -- 小地图区域
    local mapX = px + 8
    local mapY = py + 16
    local mapW = panelW - 16
    local mapH = panelH - 22

    -- 绘制舱室格子（动态计算x位置）
    local compartments = Config.Sub.compartments
    local totalSubW = Config.Sub.totalWidth or 1900
    local scaleX = mapW / totalSubW

    local compXAccum = 0  -- 累加x位置
    for i, comp in ipairs(compartments) do
        local cx = mapX + compXAccum * scaleX
        local cw = comp.width * scaleX
        local cy = mapY + 4
        local ch = mapH - 8
        compXAccum = compXAccum + comp.width + (Config.Sub.doorWidth or 20)

        -- 舱室背景
        nvgBeginPath(vg)
        nvgRect(vg, cx, cy, cw, ch)

        -- 根据水位/气压变色
        local waterLevel = 0
        local pressure = 100
        if sub.compartments and sub.compartments[i] then
            waterLevel = sub.compartments[i].waterLevel or 0
            pressure = sub.compartments[i].pressure or 100
        end
        if waterLevel > 0.5 then
            nvgFillColor(vg, nvgRGBA(30, 60, 120, 180))
        elseif pressure < Config.Pressure.dangerThreshold then
            -- 低气压：紫红警告
            local flash = math.floor(140 + 40 * math.sin(gameTime * 5))
            nvgFillColor(vg, nvgRGBA(80, 20, 40, flash))
        elseif pressure < Config.Pressure.warningThreshold then
            -- 气压偏低：深橙色
            nvgFillColor(vg, nvgRGBA(60, 45, 20, 180))
        else
            nvgFillColor(vg, nvgRGBA(30, 40, 55, 180))
        end
        nvgFill(vg)

        -- 舱室边框
        nvgBeginPath(vg)
        nvgRect(vg, cx, cy, cw, ch)
        nvgStrokeColor(vg, nvgRGBA(60, 100, 140, 150))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 舱室简称（首字）
        nvgFontSize(vg, 7)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(120, 160, 200, 150))
        local shortName = string.sub(comp.name or "", 1, 3)  -- UTF-8 取前3字节（约1个中文字）
        if #(comp.name or "") > 3 then
            shortName = string.sub(comp.name, 1, 3)  -- 1个汉字=3字节
        end
        nvgText(vg, cx + cw * 0.5, cy + ch * 0.5, shortName, nil)
    end

    -- 绘制玩家点（从 sub.playerDots 或外部传入）
    if sub.playerDots then
        for _, dot in ipairs(sub.playerDots) do
            local dotX = mapX + (dot.x or 0) * scaleX
            local dotY = mapY + mapH * 0.5
            nvgBeginPath(vg)
            nvgCircle(vg, dotX, dotY, dot.isMe and 3 or 2)
            if dot.isMe then
                nvgFillColor(vg, nvgRGBA(80, 220, 255, 255))
            elseif dot.isAI then
                nvgFillColor(vg, nvgRGBA(120, 120, 140, 200))
            else
                nvgFillColor(vg, nvgRGBA(100, 200, 100, 220))
            end
            nvgFill(vg)
        end
    end
end

--- 绘制底部危机交互提示
---@param vg userdata
---@param w number
---@param h number
---@param crisisInfo table|nil {canInteract, crisisType, isRepairing, progress, roomName}
---@param gameTime number
function HUD.DrawInteractionHint(vg, w, h, crisisInfo, gameTime)
    if not crisisInfo then return end

    local baseY = h - 65

    if crisisInfo.canInteract then
        -- 显示交互提示
        local actionText = ""
        local actionColor = {80, 200, 120}

        if crisisInfo.crisisType == "breach" then
            actionText = crisisInfo.isRepairing and "焊接修补中..." or "长按 [修补] 修复船体"
            actionColor = {240, 160, 50}
        elseif crisisInfo.crisisType == "overheat" then
            actionText = crisisInfo.isRepairing and "降温处理中..." or "长按 [降温] 冷却反应堆"
            actionColor = {255, 120, 30}
        elseif crisisInfo.crisisType == "oxygen_leak" then
            actionText = crisisInfo.isRepairing and "重启设备中..." or "长按 [重启] 恢复氧气"
            actionColor = {80, 180, 255}
        end

        -- 提示背景
        local textW = 240
        nvgBeginPath(vg)
        nvgRoundedRect(vg, w * 0.5 - textW * 0.5, baseY - 2, textW, 26, 5)
        nvgFillColor(vg, nvgRGBA(10, 15, 25, 180))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, w * 0.5 - textW * 0.5, baseY - 2, textW, 26, 5)
        nvgStrokeColor(vg, nvgRGBA(actionColor[1], actionColor[2], actionColor[3], 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 提示文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 闪烁效果（未操作时）
        local alpha = 220
        if not crisisInfo.isRepairing then
            alpha = math.floor(150 + math.sin(gameTime * 4) * 70)
        end

        nvgFillColor(vg, nvgRGBA(actionColor[1], actionColor[2], actionColor[3], alpha))
        nvgText(vg, w * 0.5, baseY + 11, actionText, nil)
    end
end

--- 绘制气压警告和低气压屏幕变暗效果
function HUD.DrawPressureWarning(vg, w, h, sub, gameTime)
    if not sub or not sub.compartments then return end

    -- 找到玩家所在舱室的气压（取所有舱室最低气压作为警告依据）
    local minPressure = 100
    local dangerRooms = {}

    for i, comp in ipairs(sub.compartments) do
        local p = comp.pressure or 100
        if p < minPressure then
            minPressure = p
        end
        if p < Config.Pressure.warningThreshold then
            table.insert(dangerRooms, { idx = i, pressure = p })
        end
    end

    -- 低气压屏幕边缘变暗效果（气压越低越暗）
    if minPressure < Config.Pressure.dangerThreshold then
        local severity = 1.0 - (minPressure / Config.Pressure.dangerThreshold)  -- 0~1
        local maxAlpha = Config.Pressure.darkenAlpha or 160
        local alpha = math.floor(severity * maxAlpha)

        -- 四边暗角渐变（类似 vignette）
        local edgeW = w * 0.25 * severity  -- 暗角范围随严重度增大

        -- 左边
        local gradL = nvgLinearGradient(vg, 0, 0, edgeW, 0,
            nvgRGBA(5, 0, 15, alpha), nvgRGBA(5, 0, 15, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, edgeW, h)
        nvgFillPaint(vg, gradL)
        nvgFill(vg)

        -- 右边
        local gradR = nvgLinearGradient(vg, w, 0, w - edgeW, 0,
            nvgRGBA(5, 0, 15, alpha), nvgRGBA(5, 0, 15, 0))
        nvgBeginPath(vg)
        nvgRect(vg, w - edgeW, 0, edgeW, h)
        nvgFillPaint(vg, gradR)
        nvgFill(vg)

        -- 上边
        local gradT = nvgLinearGradient(vg, 0, 0, 0, edgeW * 0.6,
            nvgRGBA(5, 0, 15, alpha), nvgRGBA(5, 0, 15, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, edgeW * 0.6)
        nvgFillPaint(vg, gradT)
        nvgFill(vg)

        -- 下边
        local gradB = nvgLinearGradient(vg, 0, h, 0, h - edgeW * 0.6,
            nvgRGBA(5, 0, 15, alpha), nvgRGBA(5, 0, 15, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, h - edgeW * 0.6, w, edgeW * 0.6)
        nvgFillPaint(vg, gradB)
        nvgFill(vg)
    end

    -- 气压危险警告文字（严重时脉冲闪烁）
    if minPressure < Config.Pressure.warningThreshold then
        local isCritical = minPressure < Config.Pressure.dangerThreshold
        local pulse = math.sin(gameTime * (isCritical and 6 or 3))
        local textAlpha = math.floor(180 + 60 * pulse)

        -- 警告框
        local warnW = 180
        local warnH = 24
        local warnX = w * 0.5 - warnW * 0.5
        local warnY = 8

        nvgBeginPath(vg)
        nvgRoundedRect(vg, warnX, warnY, warnW, warnH, 4)
        if isCritical then
            nvgFillColor(vg, nvgRGBA(80, 0, 0, math.floor(120 + 40 * pulse)))
        else
            nvgFillColor(vg, nvgRGBA(60, 40, 0, 100))
        end
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, warnX, warnY, warnW, warnH, 4)
        local borderColor = isCritical and nvgRGBA(255, 60, 60, textAlpha) or nvgRGBA(255, 180, 50, 150)
        nvgStrokeColor(vg, borderColor)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 警告文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        local warnText = ""
        if minPressure < Config.Pressure.lethalThreshold then
            warnText = "致命低压! 立即撤离!"
            nvgFillColor(vg, nvgRGBA(255, 50, 50, textAlpha))
        elseif isCritical then
            warnText = string.format("气压危险: %d%%", math.floor(minPressure))
            nvgFillColor(vg, nvgRGBA(255, 80, 80, textAlpha))
        else
            warnText = string.format("气压偏低: %d%%", math.floor(minPressure))
            nvgFillColor(vg, nvgRGBA(255, 200, 80, textAlpha))
        end

        nvgText(vg, w * 0.5, warnY + warnH * 0.5, warnText, nil)
    end

    -- 小地图上标记低压舱室（红色高亮）
    -- （这部分在 DrawInfoPanel 中处理，通过 compartments[i].pressure 数据）
end

--- 绘制导航偏航警报
---@param vg userdata
---@param w number
---@param h number
---@param sub table 潜艇数据（含 navigation 字段）
---@param gameTime number
function HUD.DrawNavigationAlert(vg, w, h, sub, gameTime)
    local nav = sub.navigation
    if not nav then return end

    local deviation = nav.deviation or 0
    local deviationWarning = nav.deviationWarning or 200
    local deviationAlarm = nav.deviationAlarm or 500

    -- 无偏航不显示
    if deviation < deviationWarning * 0.5 then return end

    -- 判断严重程度
    local isAlarm = deviation >= deviationAlarm
    local isWarning = deviation >= deviationWarning

    if not isWarning then
        -- 轻微偏航：右下角小提示
        local hintAlpha = math.floor(100 + 50 * math.sin(gameTime * 2))
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, hintAlpha))
        nvgText(vg, w - 15, h - 15,
            string.format("偏航 %dm", math.floor(deviation)), nil)
        return
    end

    -- 警告/报警框
    local alertW = isAlarm and 220 or 200
    local alertH = isAlarm and 50 or 36
    local alertX = w * 0.5 + 100
    local alertY = 50

    -- 背景
    local pulse = math.sin(gameTime * (isAlarm and 7 or 4))
    local bgAlpha = math.floor(140 + 40 * pulse)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, alertX, alertY, alertW, alertH, 5)
    if isAlarm then
        nvgFillColor(vg, nvgRGBA(100, 10, 10, bgAlpha))
    else
        nvgFillColor(vg, nvgRGBA(80, 60, 0, bgAlpha))
    end
    nvgFill(vg)

    -- 边框
    local borderAlpha = math.floor(180 + 60 * pulse)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, alertX, alertY, alertW, alertH, 5)
    if isAlarm then
        nvgStrokeColor(vg, nvgRGBA(255, 50, 50, borderAlpha))
    else
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, borderAlpha))
    end
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 图标（三角警告）
    local iconX = alertX + 16
    local iconY = alertY + alertH * 0.5
    nvgBeginPath(vg)
    nvgMoveTo(vg, iconX, iconY - 8)
    nvgLineTo(vg, iconX + 8, iconY + 6)
    nvgLineTo(vg, iconX - 8, iconY + 6)
    nvgClosePath(vg)
    if isAlarm then
        nvgFillColor(vg, nvgRGBA(255, 80, 80, borderAlpha))
    else
        nvgFillColor(vg, nvgRGBA(255, 200, 80, borderAlpha))
    end
    nvgFill(vg)
    -- 感叹号
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(20, 20, 20, 255))
    nvgText(vg, iconX, iconY, "!", nil)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    if isAlarm then
        -- 严重偏航：两行文字
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, borderAlpha))
        nvgText(vg, alertX + 32, alertY + alertH * 0.33,
            "航线严重偏离!", nil)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 160, 160, 200))
        nvgText(vg, alertX + 32, alertY + alertH * 0.67,
            string.format("偏差: %dm  请立即修正", math.floor(deviation)), nil)
    else
        -- 普通警告：一行
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, borderAlpha))
        nvgText(vg, alertX + 32, alertY + alertH * 0.5,
            string.format("航线偏航 %dm  建议修正", math.floor(deviation)), nil)
    end

    -- 方向箭头提示（告诉玩家该往哪转）
    local targetHeading = nav.targetHeading or 0
    local currentHeading = (sub.physics and sub.physics.heading) or 0
    local headingDiff = targetHeading - currentHeading
    -- 归一化到 -180~180
    while headingDiff > 180 do headingDiff = headingDiff - 360 end
    while headingDiff < -180 do headingDiff = headingDiff + 360 end

    if math.abs(headingDiff) > 5 then
        local arrowX = alertX + alertW - 20
        local arrowY = alertY + alertH * 0.5
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if headingDiff > 0 then
            -- 需要右转
            nvgFillColor(vg, nvgRGBA(80, 255, 160, borderAlpha))
            nvgText(vg, arrowX, arrowY, "→", nil)
        else
            -- 需要左转
            nvgFillColor(vg, nvgRGBA(80, 255, 160, borderAlpha))
            nvgText(vg, arrowX, arrowY, "←", nil)
        end
    end
end

return HUD
