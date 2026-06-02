--- 反应堆交互面板渲染
--- 显示：温度仪表、输出滑块、冷却按钮、紧急关机、启动
--- 数据来源：snapshot_.reactor

local Config = require("Config")

local ReactorPanel = {}

-- ============================================================
-- 面板布局常量
-- ============================================================
local PANEL_W = 280
local PANEL_H = 320
local MARGIN = 12
local CORNER_R = 8

-- ============================================================
-- 颜色辅助
-- ============================================================
local function tempColor(temp)
    -- 温度 0~100 → 绿→黄→红
    if temp < 40 then
        return nvgRGBA(60, 220, 120, 255)
    elseif temp < 60 then
        local t = (temp - 40) / 20
        return nvgRGBA(math.floor(60 + 195 * t), math.floor(220 - 80 * t), math.floor(120 - 80 * t), 255)
    elseif temp < 80 then
        local t = (temp - 60) / 20
        return nvgRGBA(255, math.floor(140 - 100 * t), math.floor(40 - 40 * t), 255)
    else
        return nvgRGBA(255, 40, 20, 255)
    end
end

local function stateText(state)
    if state == "off" then return "已关闭", nvgRGBA(100, 100, 100, 255)
    elseif state == "starting" then return "启动中...", nvgRGBA(80, 200, 255, 255)
    elseif state == "running" then return "运行中", nvgRGBA(60, 255, 120, 255)
    elseif state == "shutdown" then return "关机中...", nvgRGBA(255, 180, 60, 255)
    elseif state == "meltdown" then return "!! 熔毁 !!", nvgRGBA(255, 30, 30, 255)
    else return "未知", nvgRGBA(150, 150, 150, 255)
    end
end

-- ============================================================
-- 主绘制
-- ============================================================

--- 绘制反应堆面板
---@param vg userdata NanoVG context
---@param w number 屏幕逻辑宽度
---@param h number 屏幕逻辑高度
---@param reactor table 反应堆快照数据
---@param gameTime number
function ReactorPanel.Draw(vg, w, h, reactor, gameTime)
    if not reactor then return end

    local px = w * 0.5 - PANEL_W * 0.5
    local py = h * 0.5 - PANEL_H * 0.5

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, PANEL_W, PANEL_H, CORNER_R)
    nvgFillColor(vg, nvgRGBA(15, 25, 45, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 120, 180, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
    nvgText(vg, px + PANEL_W * 0.5, py + 8, "反应堆控制", nil)

    -- 状态指示
    local statusStr, statusClr = stateText(reactor.state)
    nvgFontSize(vg, 12)
    nvgFillColor(vg, statusClr)
    nvgText(vg, px + PANEL_W * 0.5, py + 28, statusStr, nil)

    local contentY = py + 50

    -- ======== 温度仪表 ========
    local temp = reactor.temperature or 0
    local cfg = Config.Reactor

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 220))
    nvgText(vg, px + MARGIN, contentY, "温度", nil)

    -- 温度条背景
    local barX = px + MARGIN + 40
    local barW = PANEL_W - MARGIN * 2 - 80
    local barH = 16
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, contentY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(30, 40, 60, 200))
    nvgFill(vg)

    -- 温度条填充
    local tempRatio = math.min(1, temp / cfg.maxTemp)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, contentY, barW * tempRatio, barH, 3)
    nvgFillColor(vg, tempColor(temp))
    nvgFill(vg)

    -- 温度值
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, px + PANEL_W - MARGIN, contentY + 2, string.format("%.0f%%", temp), nil)

    -- 警告/临界标记线
    local warnX = barX + barW * (cfg.warningTemp / cfg.maxTemp)
    local critX = barX + barW * (cfg.criticalTemp / cfg.maxTemp)
    nvgBeginPath(vg)
    nvgMoveTo(vg, warnX, contentY)
    nvgLineTo(vg, warnX, contentY + barH)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 60, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, critX, contentY)
    nvgLineTo(vg, critX, contentY + barH)
    nvgStrokeColor(vg, nvgRGBA(255, 60, 40, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    contentY = contentY + barH + 12

    -- ======== 输出功率 ========
    local output = reactor.output or 0

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 220))
    nvgText(vg, px + MARGIN, contentY, "输出", nil)

    -- 输出条背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, contentY, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(30, 40, 60, 200))
    nvgFill(vg)

    -- 输出条填充（超过100%用红色表示超载）
    local outRatio = math.min(1, output / cfg.maxOutput)
    local outColor
    if output <= 100 then
        outColor = nvgRGBA(60, 180, 255, 255)
    else
        local t = (output - 100) / (cfg.maxOutput - 100)
        outColor = nvgRGBA(math.floor(60 + 195 * t), math.floor(180 - 130 * t), math.floor(255 - 200 * t), 255)
    end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, contentY, barW * outRatio, barH, 3)
    nvgFillColor(vg, outColor)
    nvgFill(vg)

    -- 100%标记线
    local safeX = barX + barW * (100 / cfg.maxOutput)
    nvgBeginPath(vg)
    nvgMoveTo(vg, safeX, contentY)
    nvgLineTo(vg, safeX, contentY + barH)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 输出数值
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, px + PANEL_W - MARGIN, contentY + 2, string.format("%.0f%%", output), nil)

    -- kW显示
    local kw = output * Config.Power.kWPerPercent
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 180, 200, 180))
    nvgText(vg, px + PANEL_W * 0.5, contentY + barH + 2, string.format("%d kW", kw), nil)

    contentY = contentY + barH + 20

    -- ======== 冷却管道状态 ========
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 200, 220, 220))
    nvgText(vg, px + MARGIN, contentY, "冷却管道", nil)

    local pipeY = contentY
    local pipeStartX = px + MARGIN + 70
    local pipeSpacing = 20
    for i = 1, cfg.coolingPipes do
        local cx = pipeStartX + (i - 1) * pipeSpacing
        nvgBeginPath(vg)
        nvgCircle(vg, cx, pipeY + 7, cfg.pipeRadius * 0.8)
        -- 管道状态可视化（简化：都是正常的蓝色）
        nvgFillColor(vg, nvgRGBA(40, 150, 220, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    contentY = contentY + 24

    -- ======== 操作按钮提示 ========
    local btnY = contentY + 8
    local btnH = 28
    local halfW = (PANEL_W - MARGIN * 3) / 2

    -- 冷却脉冲按钮
    local coolReady = (reactor.cooldownTimer or 0) <= 0 and reactor.state == "running"
    local coolBgColor = coolReady and nvgRGBA(30, 80, 140, 220) or nvgRGBA(40, 50, 60, 150)
    local coolTxtColor = coolReady and nvgRGBA(80, 200, 255, 255) or nvgRGBA(100, 100, 100, 180)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + MARGIN, btnY, halfW, btnH, 4)
    nvgFillColor(vg, coolBgColor)
    nvgFill(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, coolTxtColor)
    if coolReady then
        nvgText(vg, px + MARGIN + halfW * 0.5, btnY + btnH * 0.5, "[▲] 冷却", nil)
    else
        local cd = reactor.cooldownTimer or 0
        nvgText(vg, px + MARGIN + halfW * 0.5, btnY + btnH * 0.5, string.format("冷却 (%.0fs)", cd), nil)
    end

    -- 关机/启动按钮
    local rightX = px + MARGIN * 2 + halfW
    local isOff = reactor.state == "off"
    local shutBgColor, shutTxtColor, shutLabel

    if isOff then
        shutBgColor = nvgRGBA(30, 100, 60, 220)
        shutTxtColor = nvgRGBA(80, 255, 140, 255)
        shutLabel = "[▲] 启动"
    else
        shutBgColor = nvgRGBA(120, 30, 20, 220)
        shutTxtColor = nvgRGBA(255, 100, 80, 255)
        shutLabel = "[▼长按] 关机"
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, rightX, btnY, halfW, btnH, 4)
    nvgFillColor(vg, shutBgColor)
    nvgFill(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, shutTxtColor)
    nvgText(vg, rightX + halfW * 0.5, btnY + btnH * 0.5, shutLabel, nil)

    -- 关机进度条（长按时显示）
    local holdProg = reactor.shutdownHoldProgress or 0
    if holdProg > 0 then
        local progBarY = btnY + btnH + 4
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rightX, progBarY, halfW, 4, 2)
        nvgFillColor(vg, nvgRGBA(40, 40, 40, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rightX, progBarY, halfW * holdProg, 4, 2)
        nvgFillColor(vg, nvgRGBA(255, 80, 40, 255))
        nvgFill(vg)
    end

    btnY = btnY + btnH + 16

    -- ======== 输出调节提示 ========
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 150, 180, 180))
    nvgText(vg, px + PANEL_W * 0.5, btnY, "[◀▶] 调节输出    [P] 关闭面板", nil)

    -- ======== 熔毁倒计时警告 ========
    if reactor.meltdownActive then
        local meltT = reactor.meltdownTimer or 0
        local flash = math.sin(gameTime * 10) > 0

        -- 全面板红色闪烁边框
        if flash then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px - 2, py - 2, PANEL_W + 4, PANEL_H + 4, CORNER_R + 2)
            nvgStrokeColor(vg, nvgRGBA(255, 20, 0, 220))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end

        -- 倒计时文字
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(255, 40, 20, 255))
        nvgText(vg, px + PANEL_W * 0.5, py + PANEL_H - 10,
            string.format("熔毁倒计时: %.1f s", meltT), nil)
    end
end

return ReactorPanel
