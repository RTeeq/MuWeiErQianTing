--- 警报渲染系统
--- - 屏幕边缘颜色编码闪光（红/黄/蓝）
--- - 警报文字横幅
--- - 舱室内危机图标指示
--- - 静音控制

local Config = require("Config")

local AlertSystem = {}

-- ============================================================
-- 屏幕边缘颜色警报
-- ============================================================

--- 绘制屏幕边缘颜色闪光
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param activeCrises table[] 活跃危机列表
---@param gameTime number
---@param muted boolean 是否静音
function AlertSystem.DrawEdgeAlert(vg, w, h, activeCrises, gameTime, muted)
    if #activeCrises == 0 then return end
    if muted then return end

    local alertCfg = Config.Crisis.alert

    -- 确定最高警报级别和对应颜色
    local highestLevel = "notice"
    local levelPriority = { notice = 1, warning = 2, critical = 3 }

    for _, c in ipairs(activeCrises) do
        local level = alertCfg.levelMap[c.type] or "notice"
        -- 严重度升级
        if c.severity == "critical" and alertCfg.severityOverride.critical then
            level = alertCfg.severityOverride.critical
        end
        if (levelPriority[level] or 0) > (levelPriority[highestLevel] or 0) then
            highestLevel = level
        end
    end

    local color = alertCfg.colors[highestLevel] or alertCfg.colors.notice
    local flashSpeed = alertCfg.flashSpeed[highestLevel] or 2.0

    -- 脉冲动画
    local pulse = 0.5 + math.sin(gameTime * flashSpeed) * 0.5
    local baseAlpha = color[4] or 180
    local alpha = math.floor(baseAlpha * 0.3 + baseAlpha * 0.7 * pulse)

    -- 屏幕边缘径向渐变
    local cx, cy = w * 0.5, h * 0.5
    local innerRadius = math.min(w, h) * 0.38
    local outerRadius = math.max(w, h) * 0.72

    local edgeGrad = nvgRadialGradient(vg, cx, cy,
        innerRadius, outerRadius,
        nvgRGBA(color[1], color[2], color[3], 0),
        nvgRGBA(color[1], color[2], color[3], alpha))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, edgeGrad)
    nvgFill(vg)

    -- 顶部/底部高亮线
    local lineAlpha = math.floor(pulse * 220)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, 2)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], lineAlpha))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, h - 2, w, 2)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], lineAlpha))
    nvgFill(vg)

    -- 多个活跃危机时加强左右边框
    if #activeCrises >= 2 then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, 2, h)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(lineAlpha * 0.7)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, w - 2, 0, 2, h)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(lineAlpha * 0.7)))
        nvgFill(vg)
    end
end

-- ============================================================
-- 警报文字横幅
-- ============================================================

--- 绘制警报横幅（屏幕顶部）
---@param vg userdata
---@param w number
---@param h number
---@param alerts table[] 警报列表 {type, level, text, time}
---@param gameTime number
---@param muted boolean
function AlertSystem.DrawAlertBanners(vg, w, h, alerts, gameTime, muted)
    if #alerts == 0 then return end

    local alertCfg = Config.Crisis.alert
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    local startY = 35
    local spacing = 26

    for i, alert in ipairs(alerts) do
        if i > 3 then break end -- 最多显示3条

        local elapsed = gameTime - alert.time
        local fadeIn = math.min(1.0, elapsed * 3.0)
        local fadeOut = math.max(0.0, 1.0 - (elapsed - alert.duration + 1.0))
        local visibility = math.min(fadeIn, fadeOut)
        if visibility <= 0 then goto continue end

        local color = alertCfg.colors[alert.level] or alertCfg.colors.notice
        local flashSpeed = alertCfg.flashSpeed[alert.level] or 2.0

        -- 闪烁
        local flash = 0.7 + math.sin(gameTime * flashSpeed + i * 0.8) * 0.3
        local alpha = math.floor(255 * visibility * flash)

        -- 背景横幅
        local textW = 200
        local bannerY = startY + (i - 1) * spacing
        nvgBeginPath(vg)
        nvgRoundedRect(vg, w * 0.5 - textW * 0.5 - 10, bannerY - 3, textW + 20, 22, 4)
        nvgFillColor(vg, nvgRGBA(10, 10, 20, math.floor(180 * visibility)))
        nvgFill(vg)

        -- 左侧色标
        nvgBeginPath(vg)
        nvgRoundedRect(vg, w * 0.5 - textW * 0.5 - 10, bannerY - 3, 4, 22, 2)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
        nvgFill(vg)

        -- 文字
        nvgFontSize(vg, 14)
        -- 阴影
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.7)))
        nvgText(vg, w * 0.5 + 1, bannerY + 1, "⚠ " .. alert.text, nil)
        -- 主体
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
        nvgText(vg, w * 0.5, bannerY, "⚠ " .. alert.text, nil)

        -- 静音指示
        if muted then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(150, 150, 150, math.floor(alpha * 0.6)))
            nvgText(vg, w * 0.5 + textW * 0.5 + 15, bannerY + 2, "[静音]", nil)
        end

        ::continue::
    end
end

-- ============================================================
-- 舱室内危机图标
-- ============================================================

-- 危机类型图标字符
local CRISIS_ICONS = {
    breach              = "💧",
    overheat            = "🔥",
    fire                = "🔥",
    power_failure       = "⚡",
    monster_invasion    = "👾",
    equipment_malfunction = "⚙",
    toxic_gas           = "☠",
    crew_madness        = "😱",
}

--- 在舱室内绘制危机类型指示图标
---@param vg userdata
---@param cx number 舱室中心X
---@param cy number 舱室中心Y
---@param crisisType string
---@param severity string
---@param gameTime number
function AlertSystem.DrawCrisisIcon(vg, cx, cy, crisisType, severity, gameTime)
    local alertCfg = Config.Crisis.alert
    local level = alertCfg.levelMap[crisisType] or "notice"
    if severity == "critical" then level = "critical" end
    local color = alertCfg.colors[level] or alertCfg.colors.notice
    local flashSpeed = alertCfg.flashSpeed[level] or 2.0

    local pulse = 0.6 + math.sin(gameTime * flashSpeed) * 0.4
    local alpha = math.floor(220 * pulse)

    -- 背景圆圈
    local radius = 12
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(alpha * 0.25)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 图标
    local icon = CRISIS_ICONS[crisisType] or "⚠"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha))
    nvgText(vg, cx, cy, icon, nil)

    -- 严重度标记（critical时外圈额外发光）
    if severity == "critical" then
        local outerPulse = math.sin(gameTime * 8) * 0.5 + 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius + 4 + outerPulse * 3)
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(60 * outerPulse)))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
end

-- ============================================================
-- 有毒气体舱室叠加
-- ============================================================

--- 绘制毒气覆盖效果
---@param vg userdata
---@param compX number 舱室X
---@param compY number 舱室Y
---@param compW number 舱室宽
---@param compH number 舱室高
---@param concentration number 0~1 浓度
---@param gameTime number
function AlertSystem.DrawGasOverlay(vg, compX, compY, compW, compH, concentration, gameTime)
    if concentration <= 0 then return end

    local alpha = math.floor(concentration * 80)
    local drift = math.sin(gameTime * 1.5) * 5

    -- 绿色毒雾覆盖
    nvgBeginPath(vg)
    nvgRect(vg, compX, compY, compW, compH)
    nvgFillColor(vg, nvgRGBA(40, 180, 60, alpha))
    nvgFill(vg)

    -- 漂浮的毒雾粒子
    for i = 1, math.floor(concentration * 6) do
        local px = compX + ((i * 37 + gameTime * 20) % compW)
        local py = compY + compH * 0.3 + math.sin(gameTime * 0.8 + i * 1.5) * compH * 0.2 + drift
        local size = 8 + math.sin(gameTime + i) * 4
        local pAlpha = math.floor(alpha * (0.4 + math.sin(gameTime * 2 + i) * 0.3))

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(60, 200, 80, pAlpha))
        nvgFill(vg)
    end
end

-- ============================================================
-- 火焰舱室叠加
-- ============================================================

--- 绘制火焰覆盖效果
---@param vg userdata
---@param compX number
---@param compY number
---@param compW number
---@param compH number
---@param intensity number 0~1
---@param gameTime number
function AlertSystem.DrawFireOverlay(vg, compX, compY, compW, compH, intensity, gameTime)
    if intensity <= 0 then return end

    local alpha = math.floor(intensity * 60)

    -- 橙红色闪烁底色
    local flash = 0.6 + math.sin(gameTime * 5) * 0.4
    nvgBeginPath(vg)
    nvgRect(vg, compX, compY, compW, compH)
    nvgFillColor(vg, nvgRGBA(255, 60, 20, math.floor(alpha * flash)))
    nvgFill(vg)

    -- 火焰粒子
    for i = 1, math.floor(intensity * 8) do
        local phase = gameTime * 3 + i * 1.7
        local px = compX + ((i * 43 + gameTime * 30) % compW)
        local py = compY + compH - ((phase % 1.0) * compH * 0.7)
        local size = 4 + math.sin(phase) * 3
        local fAlpha = math.floor((1.0 - (phase % 1.0)) * intensity * 180)

        -- 火焰颜色渐变（黄→橙→红）
        local t = (phase % 1.0)
        local r = 255
        local g = math.floor(200 * (1.0 - t))
        local b = math.floor(30 * (1.0 - t))

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(r, g, b, fAlpha))
        nvgFill(vg)
    end
end

-- ============================================================
-- 恐慌效果（屏幕抖动提示）
-- ============================================================

--- 获取恐慌引起的屏幕偏移（供外部使用）
---@param gameTime number
---@param severity string
---@return number offsetX, number offsetY
function AlertSystem.GetMadnessOffset(gameTime, severity)
    if severity == "minor" then
        return 0, 0
    elseif severity == "moderate" then
        return math.sin(gameTime * 12) * 2, math.cos(gameTime * 9) * 1.5
    else -- critical
        return math.sin(gameTime * 18) * 5, math.cos(gameTime * 14) * 4
    end
end

--- 绘制恐慌视觉效果（暗角 + 噪点）
---@param vg userdata
---@param w number
---@param h number
---@param severity string
---@param gameTime number
function AlertSystem.DrawMadnessEffect(vg, w, h, severity, gameTime)
    if severity == "minor" then return end

    local intensity = severity == "critical" and 1.0 or 0.5
    local pulse = 0.5 + math.sin(gameTime * 3) * 0.5

    -- 暗角加重
    local vignetteAlpha = math.floor(60 * intensity * pulse)
    local cx, cy = w * 0.5, h * 0.5
    local grad = nvgRadialGradient(vg, cx, cy,
        math.min(w, h) * 0.2,
        math.max(w, h) * 0.6,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(20, 0, 30, vignetteAlpha))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

return AlertSystem
