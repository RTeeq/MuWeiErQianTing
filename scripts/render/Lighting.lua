--- 灯光系统渲染：顶灯、应急灯、黑暗遮罩
local Config = require("Config")

local Lighting = {}

--- 绘制灯光效果
---@param vg userdata
---@param subX number 潜艇内部左边界
---@param subY number 潜艇内部顶部
---@param subH number 潜艇内部高度
---@param sub table 潜艇数据
---@param gameTime number
function Lighting.Draw(vg, subX, subY, subH, sub, gameTime)
    for i, comp in ipairs(sub.compartments) do
        local cx = subX + comp.x
        local cw = comp.width
        local lightX = cx + cw * 0.5
        local lightY = subY + 10  -- 灯在天花板附近

        if comp.lightOn and sub.isPowerOn then
            -- 正常灯光：从顶部向下的暖黄色径向渐变
            Lighting.DrawNormalLight(vg, lightX, lightY, cw, subH, gameTime, i)
        else
            -- 停电：黑暗 + 应急红灯脉冲
            Lighting.DrawDarkness(vg, cx, subY, cw, subH)
            Lighting.DrawEmergencyLight(vg, lightX, lightY + subH * 0.3, gameTime, i)
        end
    end
end

--- 绘制正常灯光
function Lighting.DrawNormalLight(vg, x, y, roomW, roomH, gameTime, roomIdx)
    local radius = Config.Lighting.normalRadius
    local c = Config.Colors.lightNormal

    -- 灯具本体（小圆形）
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, 5)
    nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
    nvgFill(vg)

    -- 灯光照射范围（向下扩散的锥形渐变）
    local grad = nvgRadialGradient(vg, x, y + 20, 10, radius,
        nvgRGBA(c[1], c[2], c[3], 60),
        nvgRGBA(c[1], c[2], c[3], 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - radius, y, radius * 2, roomH)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 边缘阴暗处理（舱室两侧渐暗）
    local edgeDark = 60
    local leftGrad = nvgLinearGradient(vg, x - roomW * 0.5, y, x - roomW * 0.5 + 60, y,
        nvgRGBA(5, 5, 10, edgeDark),
        nvgRGBA(5, 5, 10, 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - roomW * 0.5, y, 60, roomH)
    nvgFillPaint(vg, leftGrad)
    nvgFill(vg)

    local rightGrad = nvgLinearGradient(vg, x + roomW * 0.5 - 60, y, x + roomW * 0.5, y,
        nvgRGBA(5, 5, 10, 0),
        nvgRGBA(5, 5, 10, edgeDark))
    nvgBeginPath(vg)
    nvgRect(vg, x + roomW * 0.5 - 60, y, 60, roomH)
    nvgFillPaint(vg, rightGrad)
    nvgFill(vg)
end

--- 绘制黑暗遮罩
function Lighting.DrawDarkness(vg, x, y, w, h)
    local dc = Config.Colors.darkness
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], dc[4]))
    nvgFill(vg)
end

--- 绘制应急红灯
function Lighting.DrawEmergencyLight(vg, x, y, gameTime, roomIdx)
    local pulse = Config.Lighting.pulseMin +
        (1 - Config.Lighting.pulseMin) * (0.5 + 0.5 * math.sin(gameTime * Config.Lighting.pulseSpeed + roomIdx))
    local radius = Config.Lighting.emergencyRadius
    local c = Config.Colors.lightEmergency

    -- 红灯光源
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, 4)
    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], math.floor(255 * pulse)))
    nvgFill(vg)

    -- 红色光晕
    local grad = nvgRadialGradient(vg, x, y, 5, radius * pulse,
        nvgRGBA(c[1], c[2], c[3], math.floor(80 * pulse)),
        nvgRGBA(c[1], c[2], c[3], 0))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, radius * pulse)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

return Lighting
