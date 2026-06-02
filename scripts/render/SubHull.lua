--- 潜艇外壳渲染：金属质感、铆钉、管道、舷窗
local Config = require("Config")

local SubHull = {}

--- 绘制潜艇外壳
---@param vg userdata
---@param subX number 潜艇左边界屏幕X
---@param subY number 潜艇顶部屏幕Y
---@param subW number 潜艇总宽度
---@param subH number 潜艇总高度（含外壳）
---@param gameTime number
---@param sub table 潜艇数据（用于舷窗显示状态）
function SubHull.Draw(vg, subX, subY, subW, subH, gameTime, sub)
    local thick = Config.Sub.hullThickness
    local radius = Config.Sub.hullRadius
    local c = Config.Colors

    -- 外壳主体（深灰金属）
    local grad = nvgLinearGradient(vg, subX, subY, subX, subY + subH,
        nvgRGBA(c.hullHighlight[1], c.hullHighlight[2], c.hullHighlight[3], 255),
        nvgRGBA(c.hullOuter[1], c.hullOuter[2], c.hullOuter[3], 255))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX, subY, subW, subH, radius)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 内部空间（挖空）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX + thick, subY + thick, subW - thick * 2, subH - thick * 2, radius * 0.6)
    nvgFillColor(vg, nvgRGBA(20, 22, 28, 255))
    nvgFill(vg)

    -- 外壳边框线
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX, subY, subW, subH, radius)
    nvgStrokeColor(vg, nvgRGBA(c.hullHighlight[1], c.hullHighlight[2], c.hullHighlight[3], 120))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 铆钉（顶部和底部一排）
    local rivetSpacing = 40
    local rivetR = 3
    for x = subX + 30, subX + subW - 30, rivetSpacing do
        -- 顶部铆钉
        nvgBeginPath(vg)
        nvgCircle(vg, x, subY + thick * 0.5, rivetR)
        nvgFillColor(vg, nvgRGBA(c.rivet[1], c.rivet[2], c.rivet[3], 200))
        nvgFill(vg)
        -- 底部铆钉
        nvgBeginPath(vg)
        nvgCircle(vg, x, subY + subH - thick * 0.5, rivetR)
        nvgFillColor(vg, nvgRGBA(c.rivet[1], c.rivet[2], c.rivet[3], 200))
        nvgFill(vg)
    end

    -- 管道（外壳底部横贯一条）
    local pipeY = subY + subH - thick * 0.5
    nvgBeginPath(vg)
    nvgMoveTo(vg, subX + radius, pipeY + 4)
    nvgLineTo(vg, subX + subW - radius, pipeY + 4)
    nvgStrokeColor(vg, nvgRGBA(50, 55, 60, 180))
    nvgStrokeWidth(vg, 5)
    nvgStroke(vg)
    -- 管道高光
    nvgBeginPath(vg)
    nvgMoveTo(vg, subX + radius, pipeY + 2)
    nvgLineTo(vg, subX + subW - radius, pipeY + 2)
    nvgStrokeColor(vg, nvgRGBA(80, 85, 95, 100))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 舷窗
    SubHull.DrawPortholes(vg, subX, subY, subW, subH, gameTime)

    -- 潜艇头部装饰（左侧尖端）
    nvgBeginPath(vg)
    nvgMoveTo(vg, subX - 30, subY + subH * 0.5)
    nvgLineTo(vg, subX + 5, subY + 8)
    nvgLineTo(vg, subX + 5, subY + subH - 8)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(c.hullOuter[1], c.hullOuter[2], c.hullOuter[3], 255))
    nvgFill(vg)

    -- 潜艇尾部装饰（右侧螺旋桨）
    SubHull.DrawPropeller(vg, subX + subW, subY + subH * 0.5, gameTime)
end

--- 绘制舷窗
function SubHull.DrawPortholes(vg, subX, subY, subW, subH, gameTime)
    local r = Config.Sub.portholeRadius
    local count = Config.Sub.portholeCount
    local spacing = subW / (count + 1)

    for i = 1, count do
        local px = subX + spacing * i
        local py = subY + Config.Sub.hullThickness * 0.5

        -- 舷窗金属框
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, r + 3)
        nvgFillColor(vg, nvgRGBA(70, 75, 82, 255))
        nvgFill(vg)

        -- 舷窗玻璃（深蓝，偶尔有怪物影子闪过）
        local glassAlpha = 180
        -- 随机让某个舷窗闪过阴影
        local shadowPhase = math.sin(gameTime * 0.5 + i * 2.0)
        local hasShadow = (shadowPhase > 0.9)

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, r)
        if hasShadow then
            nvgFillColor(vg, nvgRGBA(5, 10, 20, 240))
        else
            local grad = nvgRadialGradient(vg, px, py, r * 0.3, r,
                nvgRGBA(30, 60, 100, glassAlpha),
                nvgRGBA(10, 25, 50, glassAlpha))
            nvgFillPaint(vg, grad)
        end
        nvgFill(vg)

        -- 玻璃高光
        nvgBeginPath(vg)
        nvgCircle(vg, px - r * 0.3, py - r * 0.3, r * 0.25)
        nvgFillColor(vg, nvgRGBA(120, 160, 200, 40))
        nvgFill(vg)

        -- 框边
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, r + 3)
        nvgStrokeColor(vg, nvgRGBA(90, 95, 105, 150))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 绘制螺旋桨
function SubHull.DrawPropeller(vg, cx, cy, gameTime)
    local bladeLen = 35
    local angle = gameTime * 8  -- 旋转速度

    nvgSave(vg)
    nvgTranslate(vg, cx + 15, cy)

    -- 桨轴
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, 8)
    nvgFillColor(vg, nvgRGBA(60, 65, 72, 255))
    nvgFill(vg)

    -- 桨叶（4片）
    for i = 0, 3 do
        nvgSave(vg)
        nvgRotate(vg, angle + i * math.pi * 0.5)
        nvgBeginPath(vg)
        nvgEllipse(vg, bladeLen * 0.5, 0, bladeLen * 0.5, 6)
        nvgFillColor(vg, nvgRGBA(80, 85, 92, 200))
        nvgFill(vg)
        nvgRestore(vg)
    end

    nvgRestore(vg)
end

return SubHull
