--- 外部视角：潜艇在深海中航行的侧面全景视图
local Config = require("Config")

local ExternalView = {}

-- 外部视角粒子状态
local particles = {}
local fishSchools = {}
local initialized = false

-- 碰撞闪烁计时
local collisionFlashTimer = 0

--- 初始化外部视角粒子
local function initParticles(w, h)
    if initialized then return end
    initialized = true

    -- 海中微粒（营造深海氛围）
    for i = 1, 60 do
        table.insert(particles, {
            x = math.random() * w * 2,
            y = math.random() * h,
            size = 1 + math.random() * 2,
            speed = 10 + math.random() * 20,
            alpha = 20 + math.random(0, 40),
        })
    end

    -- 鱼群
    for i = 1, 3 do
        table.insert(fishSchools, {
            x = math.random() * w * 2,
            y = h * 0.2 + math.random() * h * 0.6,
            count = 3 + math.random(0, 5),
            speed = 20 + math.random() * 30,
            dir = (math.random() > 0.5) and 1 or -1,
        })
    end
end

--- 绘制外部视角
---@param vg userdata
---@param w number 屏幕宽度
---@param h number 屏幕高度
---@param sub table 潜艇数据（含 driving/physics/ballast/sonar/navigation）
---@param gameTime number
function ExternalView.Draw(vg, w, h, sub, gameTime)
    initParticles(w, h)

    -- 提取驾驶/物理数据（兼容旧调用方式）
    local driving = sub.driving or {}
    local physics = sub.physics or {}
    local ballast = sub.ballast or {}
    local speed = physics.speed or 0
    local heading = physics.heading or 0
    local verticalSpeed = physics.verticalSpeed or 0
    local throttleGear = driving.throttleGear or 0
    local searchlightOn = driving.searchlightOn or false
    local searchlightAngle = driving.searchlightAngle or 0
    local helmAngle = driving.helmAngle or 0

    -- 碰撞闪烁更新
    if physics.collisionDamage and physics.collisionDamage > 0 then
        collisionFlashTimer = 0.3
    end
    if collisionFlashTimer > 0 then
        collisionFlashTimer = collisionFlashTimer - (1.0 / 60.0)
    end

    -- 1. 深海背景（深度越深越暗）
    local depthFactor = math.min(1.0, (sub.depth or 0) / 8000)
    local topR = math.floor(5 + (1 - depthFactor) * 15)
    local topG = math.floor(15 + (1 - depthFactor) * 20)
    local topB = math.floor(35 + (1 - depthFactor) * 30)
    local bgGrad = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(topR, topG, topB, 255),
        nvgRGBA(1, 3, 8, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 2. 远景光柱（从上方微弱透下）
    for i = 1, 3 do
        local beamX = w * (0.2 + i * 0.25) + math.sin(gameTime * 0.3 + i) * 30
        local beamW = 40 + math.sin(gameTime * 0.5 + i * 2) * 15
        local beamGrad = nvgLinearGradient(vg, beamX, 0, beamX, h * 0.6,
            nvgRGBA(20, 60, 120, 15),
            nvgRGBA(10, 30, 60, 0))
        nvgBeginPath(vg)
        nvgMoveTo(vg, beamX - beamW * 0.3, 0)
        nvgLineTo(vg, beamX + beamW * 0.3, 0)
        nvgLineTo(vg, beamX + beamW, h * 0.6)
        nvgLineTo(vg, beamX - beamW, h * 0.6)
        nvgClosePath(vg)
        nvgFillPaint(vg, beamGrad)
        nvgFill(vg)
    end

    -- 3. 海中微粒
    for _, p in ipairs(particles) do
        local px = (p.x - gameTime * p.speed) % (w * 2) - w * 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, px, p.y, p.size)
        nvgFillColor(vg, nvgRGBA(100, 150, 200, p.alpha))
        nvgFill(vg)
    end

    -- 4. 潜艇主体（居中，缩小比例）
    local subScale = 0.35
    local subW = 500
    local subH = 80
    local subX = w * 0.5 - subW * 0.5
    local subY = h * 0.5 - subH * 0.5 + math.sin(gameTime * 0.8) * 5

    nvgSave(vg)
    nvgTranslate(vg, subX + subW * 0.5, subY + subH * 0.5)
    -- 根据垂直速度微微倾斜（下潜时船头下倾，上浮时上仰）
    local tiltAngle = math.max(-0.12, math.min(0.12, verticalSpeed * 0.03))
    nvgRotate(vg, tiltAngle)
    nvgTranslate(vg, -subW * 0.5, -subH * 0.5)

    -- 潜艇外壳（流线型）
    local hullGrad = nvgLinearGradient(vg, 0, 0, 0, subH,
        nvgRGBA(80, 85, 95, 255),
        nvgRGBA(45, 50, 58, 255))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, subW, subH, 35)
    nvgFillPaint(vg, hullGrad)
    nvgFill(vg)

    -- 潜艇外壳边线
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 0, 0, subW, subH, 35)
    nvgStrokeColor(vg, nvgRGBA(100, 110, 120, 150))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 指挥塔（顶部凸起）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subW * 0.3, -25, 60, 30, 8)
    nvgFillColor(vg, nvgRGBA(65, 70, 78, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subW * 0.3, -25, 60, 30, 8)
    nvgStrokeColor(vg, nvgRGBA(90, 95, 105, 120))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 船头尖锥
    nvgBeginPath(vg)
    nvgMoveTo(vg, -40, subH * 0.5)
    nvgLineTo(vg, 5, 5)
    nvgLineTo(vg, 5, subH - 5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(70, 75, 82, 255))
    nvgFill(vg)

    -- 舷窗（小亮点）
    for i = 1, 6 do
        local wx = 60 + i * 65
        local wy = subH * 0.35
        nvgBeginPath(vg)
        nvgCircle(vg, wx, wy, 6)
        local windowGlow = nvgRadialGradient(vg, wx, wy, 0, 6,
            nvgRGBA(180, 220, 255, 180),
            nvgRGBA(80, 120, 180, 60))
        nvgFillPaint(vg, windowGlow)
        nvgFill(vg)
    end

    -- 螺旋桨（尾部，转速随油门变化）
    local propX = subW + 10
    local propY = subH * 0.5
    local propSpeed = 0
    if throttleGear > 0 then
        propSpeed = 5 + throttleGear * 4  -- 1挡=9，4挡=21
    elseif throttleGear < 0 then
        propSpeed = -6  -- 倒车
    end
    nvgSave(vg)
    nvgTranslate(vg, propX, propY)
    nvgRotate(vg, gameTime * propSpeed)
    for blade = 0, 3 do
        nvgSave(vg)
        nvgRotate(vg, blade * math.pi * 0.5)
        nvgBeginPath(vg)
        nvgEllipse(vg, 12, 0, 12, 4)
        nvgFillColor(vg, nvgRGBA(90, 95, 105, 200))
        nvgFill(vg)
        nvgRestore(vg)
    end
    nvgRestore(vg)

    -- 5. 探照灯效果（根据驾驶数据动态调整）
    local lightX = -40
    local lightY = subH * 0.5
    local lightOn = searchlightOn
    local lightAlpha = lightOn and 80 or 20  -- 关闭时微弱光
    local lightLen = lightOn and 300 or 150
    local lightSpread = lightOn and 90 or 40

    -- 探照灯角度（转换为弧度，向下为正）
    local lightAngleRad = math.rad(searchlightAngle)
    local lightEndX = lightX - lightLen * math.cos(lightAngleRad)
    local lightEndY = lightY + lightLen * math.sin(lightAngleRad)
    local perpX = -math.sin(lightAngleRad) * lightSpread
    local perpY = -math.cos(lightAngleRad) * lightSpread

    -- 探照灯锥形光束
    local lightGrad = nvgLinearGradient(vg, lightX, lightY,
        lightEndX, lightEndY,
        nvgRGBA(200, 230, 255, lightAlpha),
        nvgRGBA(100, 150, 200, 0))
    nvgBeginPath(vg)
    nvgMoveTo(vg, lightX, lightY)
    nvgLineTo(vg, lightEndX - perpX, lightEndY - perpY)
    nvgLineTo(vg, lightEndX + perpX, lightEndY + perpY)
    nvgClosePath(vg)
    nvgFillPaint(vg, lightGrad)
    nvgFill(vg)

    -- 探照灯光源点
    local srcAlpha = lightOn and 220 or 80
    local srcGlow = nvgRadialGradient(vg, lightX, lightY, 0, lightOn and 18 or 10,
        nvgRGBA(255, 255, 240, srcAlpha),
        nvgRGBA(200, 230, 255, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, lightX, lightY, lightOn and 18 or 10)
    nvgFillPaint(vg, srcGlow)
    nvgFill(vg)

    nvgRestore(vg)

    -- 6. 探照灯照亮的微粒（在光锥内闪烁）
    local coneStartX = subX - 40
    local coneY = subY + subH * 0.5
    for i = 1, 12 do
        local dist = 30 + math.random() * 200
        local spread = (dist / 250) * 80
        local pxOff = math.sin(gameTime * 2 + i * 1.3) * spread * 0.5
        local px = coneStartX - dist
        local py = coneY + pxOff
        local pAlpha = math.floor(60 * (1 - dist / 300))
        if pAlpha > 5 and px > 0 then
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, 1.5 + math.sin(gameTime * 3 + i) * 0.5)
            nvgFillColor(vg, nvgRGBA(180, 220, 255, pAlpha))
            nvgFill(vg)
        end
    end

    -- 7. 鱼群剪影
    for _, school in ipairs(fishSchools) do
        local baseX = (school.x + gameTime * school.speed * school.dir) % (w * 1.5) - w * 0.2
        for f = 1, school.count do
            local fx = baseX + f * 15 + math.sin(gameTime * 3 + f * 2) * 5
            local fy = school.y + math.sin(gameTime * 2 + f * 1.5) * 10
            -- 小鱼形状
            nvgBeginPath(vg)
            nvgEllipse(vg, fx, fy, 8, 4)
            nvgFillColor(vg, nvgRGBA(15, 30, 50, 150))
            nvgFill(vg)
            -- 尾巴
            nvgBeginPath(vg)
            nvgMoveTo(vg, fx + 8 * (-school.dir), fy)
            nvgLineTo(vg, fx + 14 * (-school.dir), fy - 4)
            nvgLineTo(vg, fx + 14 * (-school.dir), fy + 4)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(15, 30, 50, 120))
            nvgFill(vg)
        end
    end

    -- 8. 气泡尾流（密度随速度动态变化）
    local trailX = subX + subW * 0.5 + 280
    local trailY = subY + subH * 0.5
    local bubbleCount = math.floor(5 + math.abs(speed) * 3)  -- 速度越快气泡越多
    bubbleCount = math.min(30, bubbleCount)
    for i = 1, bubbleCount do
        local phase = gameTime * (2 + math.abs(speed) * 0.5) + i * 0.8
        local bx = trailX + (i * 10) + math.sin(phase) * 5
        local by = trailY + math.sin(phase * 1.3 + i) * (10 + math.abs(speed) * 3)
        local br = 1.5 + math.sin(phase * 2) * 1.5 + math.abs(speed) * 0.3
        local bAlpha = math.floor(60 * (1 - i / bubbleCount))
        nvgBeginPath(vg)
        nvgCircle(vg, bx, by, br)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, bAlpha))
        nvgFill(vg)
    end

    -- 8.5 压载水舱排水气泡（排水时在潜艇底部冒泡）
    local ballastDraining = (ballast.draining == true)
    if ballastDraining then
        local drainX = subX + subW * 0.3
        local drainY = subY + subH + 10
        for i = 1, 20 do
            local phase = gameTime * 4 + i * 1.2
            local bx = drainX + math.sin(phase * 0.7 + i) * 60
            local by = drainY + (math.fmod(phase, 3.0) / 3.0) * 80
            local br = 2 + math.sin(phase * 3) * 1
            local bAlpha = math.floor(80 * (1 - math.fmod(phase, 3.0) / 3.0))
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, br)
            nvgFillColor(vg, nvgRGBA(180, 220, 255, bAlpha))
            nvgFill(vg)
        end
    end

    -- 8.6 碰撞闪烁效果（红色边框闪烁）
    if collisionFlashTimer > 0 then
        local flashAlpha = math.floor(120 * (collisionFlashTimer / 0.3))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgStrokeColor(vg, nvgRGBA(255, 60, 30, flashAlpha))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)
    end

    -- 9. 深度标尺（左侧，使用真实深度数据）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(80, 140, 180, 120))
    local depth = math.floor(sub.depth or 0)
    for i = 0, 5 do
        local ly = h * 0.15 + i * (h * 0.7 / 5)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 10, ly)
        nvgLineTo(vg, 35, ly)
        nvgStrokeColor(vg, nvgRGBA(60, 120, 160, 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgText(vg, 38, ly, tostring(depth + i * 20) .. "m", nil)
    end

    -- 10. 右下角航行状态信息
    local infoX = w - 160
    local infoY = h - 80
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 速度
    nvgFillColor(vg, nvgRGBA(100, 200, 180, 200))
    nvgText(vg, infoX, infoY, string.format("SPD: %.1f kn", speed), nil)

    -- 航向
    nvgFillColor(vg, nvgRGBA(120, 180, 220, 200))
    nvgText(vg, infoX, infoY + 16, string.format("HDG: %03d°", math.floor(heading) % 360), nil)

    -- 垂直速度
    local vsColor = verticalSpeed > 0.5 and nvgRGBA(255, 160, 60, 200) or
                    verticalSpeed < -0.5 and nvgRGBA(80, 200, 255, 200) or
                    nvgRGBA(150, 150, 150, 150)
    nvgFillColor(vg, vsColor)
    local vsArrow = verticalSpeed > 0.5 and "↓" or verticalSpeed < -0.5 and "↑" or "—"
    nvgText(vg, infoX, infoY + 32, string.format("VS: %s%.1f m/s", vsArrow, math.abs(verticalSpeed)), nil)

    -- 油门档位
    local gearNames = { [-1] = "R", [0] = "0", [1] = "1", [2] = "2", [3] = "3", [4] = "4" }
    local gearName = gearNames[throttleGear] or "?"
    nvgFillColor(vg, nvgRGBA(200, 200, 100, 200))
    nvgText(vg, infoX, infoY + 48, string.format("THR: GEAR %s", gearName), nil)
end

return ExternalView
