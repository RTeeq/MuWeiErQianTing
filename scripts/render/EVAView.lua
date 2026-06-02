--- 舱外活动(EVA)场景 NanoVG 渲染
--- 绘制：深海环境、遗迹、潜水员、头灯光锥、氧气HUD、战利品
local EVASystem = require("EVASystem")

local EVAView = {}

-- ============================================================
-- 颜色定义
-- ============================================================
local Colors = {
    -- 深海环境
    bgTop = {5, 12, 30},
    bgBot = {2, 4, 10},
    seabed = {20, 30, 40},
    seabedLine = {30, 40, 55},

    -- 潜水员
    suitBody = {60, 100, 140},
    suitHighlight = {80, 130, 180},
    helmet = {170, 190, 210},
    helmetVisor = {40, 180, 220, 200},
    oxygenTank = {90, 95, 100},

    -- 头灯
    headlightCenter = {255, 250, 230, 60},
    headlightEdge = {200, 230, 255, 0},

    -- 氧气HUD
    oxygenFull = {50, 180, 255},
    oxygenLow = {255, 80, 40},
    oxygenBg = {20, 30, 50, 180},

    -- 战利品
    lootGlow = {80, 220, 180, 120},
    lootCore = {200, 255, 220, 255},

    -- 潜艇（远处轮廓）
    subSilhouette = {40, 60, 80, 120},
    airlock = {100, 180, 220, 200},

    -- 气泡
    bubble = {140, 200, 255, 80},

    -- 遗迹名称
    ruinLabel = {150, 180, 200, 180},
}

-- ============================================================
-- 相机系统（跟随潜水员）
-- ============================================================
local camera = {
    x = 0,
    y = 0,
    targetX = 0,
    targetY = 0,
    smoothing = 3.0,
}

function EVAView.UpdateCamera(eva, w, h, dt)
    camera.targetX = eva.x - w * 0.4
    camera.targetY = eva.y - h * 0.5
    -- 限制边界
    camera.targetX = math.max(0, math.min(EVASystem.Config.worldWidth - w, camera.targetX))
    camera.targetY = math.max(0, math.min(EVASystem.Config.worldHeight - h, camera.targetY))
    -- 平滑跟随
    camera.x = camera.x + (camera.targetX - camera.x) * math.min(1, dt * camera.smoothing)
    camera.y = camera.y + (camera.targetY - camera.y) * math.min(1, dt * camera.smoothing)
end

-- ============================================================
-- 主绘制入口
-- ============================================================

--- 绘制EVA场景
function EVAView.Draw(vg, w, h, eva, world, gameTime, dt)
    -- 更新相机
    EVAView.UpdateCamera(eva, w, h, dt)

    -- 1. 深海背景
    EVAView.DrawBackground(vg, w, h, gameTime)

    -- 2. 世界坐标渲染（相机变换）
    nvgSave(vg)
    nvgTranslate(vg, -camera.x, -camera.y)

    -- 2.1 海底地形
    EVAView.DrawSeabed(vg, world, gameTime)

    -- 2.2 遗迹
    EVAView.DrawRuins(vg, world, eva, gameTime)

    -- 2.3 战利品
    EVAView.DrawLoots(vg, world, eva, gameTime)

    -- 2.4 潜艇轮廓（远处）
    EVAView.DrawSubSilhouette(vg, gameTime)

    -- 2.5 潜水员
    EVAView.DrawDiver(vg, eva, gameTime)

    -- 2.6 头灯光锥
    EVAView.DrawHeadlight(vg, eva, w, h)

    -- 2.7 气泡粒子
    EVAView.DrawBubbles(vg, eva, gameTime)

    nvgRestore(vg)

    -- 3. 深度暗角（环境压迫感）
    EVAView.DrawVignette(vg, w, h)

    -- 4. HUD（固定屏幕空间）
    EVAView.DrawHUD(vg, w, h, eva, world, gameTime)
end

--- 绘制穿衣/脱衣阶段
function EVAView.DrawSuitingPhase(vg, w, h, eva, gameTime)
    -- 暗色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(5, 10, 20, 230))
    nvgFill(vg)

    -- 动画进度
    local progress = eva.suitTimer / eva.suitDuration
    local text = "正在穿戴潜水服..."
    if eva.phase == "returning" then
        text = "正在卸下潜水服..."
        progress = eva.suitTimer / (eva.suitDuration * 0.5)
    end

    -- 进度条
    local barW = 200
    local barH = 12
    local barX = (w - barW) * 0.5
    local barY = h * 0.55

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(30, 40, 60, 200))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX + 2, barY + 2, (barW - 4) * math.min(1, progress), barH - 4, 4)
    nvgFillColor(vg, nvgRGBA(50, 180, 255, 220))
    nvgFill(vg)

    -- 文本
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(180, 210, 240, 220))
    nvgText(vg, w * 0.5, barY - 10, text, nil)

    -- 潜水员图标
    local iconY = h * 0.35
    local scale = 0.5 + progress * 0.5
    nvgSave(vg)
    nvgTranslate(vg, w * 0.5, iconY)
    nvgScale(vg, scale, scale)
    EVAView.DrawDiverIcon(vg, 0, 0, gameTime)
    nvgRestore(vg)
end

-- ============================================================
-- 背景和环境
-- ============================================================

function EVAView.DrawBackground(vg, w, h, gameTime)
    -- 深海渐变
    local bgGrad = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(Colors.bgTop[1], Colors.bgTop[2], Colors.bgTop[3], 255),
        nvgRGBA(Colors.bgBot[1], Colors.bgBot[2], Colors.bgBot[3], 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 悬浮颗粒（浮游生物）
    nvgFillColor(vg, nvgRGBA(80, 150, 200, 30))
    for i = 1, 40 do
        local px = ((i * 137 + gameTime * (5 + i % 3)) % (w + 100)) - 50
        local py = ((i * 97 + gameTime * (2 + i % 2)) % (h + 50)) - 25
        local size = 1 + (i % 3)
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFill(vg)
    end
end

function EVAView.DrawSeabed(vg, world, gameTime)
    local cfg = EVASystem.Config
    local groundY = cfg.worldHeight - 20

    -- 海底基线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, groundY)
    -- 起伏的海底
    for x = 0, cfg.worldWidth, 20 do
        local yOff = math.sin(x * 0.01 + gameTime * 0.2) * 5 + math.sin(x * 0.03) * 3
        nvgLineTo(vg, x, groundY + yOff)
    end
    nvgLineTo(vg, cfg.worldWidth, cfg.worldHeight + 50)
    nvgLineTo(vg, 0, cfg.worldHeight + 50)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(Colors.seabed[1], Colors.seabed[2], Colors.seabed[3], 255))
    nvgFill(vg)

    -- 装饰物
    if world and world.seabed then
        for _, deco in ipairs(world.seabed) do
            if deco.type == 1 then
                -- 小石头
                nvgBeginPath(vg)
                nvgEllipse(vg, deco.x, deco.y, deco.size, deco.size * 0.6)
                nvgFillColor(vg, nvgRGBA(35, 45, 55, 200))
                nvgFill(vg)
            elseif deco.type == 2 then
                -- 大石头
                nvgBeginPath(vg)
                nvgRoundedRect(vg, deco.x - deco.size, deco.y - deco.size * 0.7,
                    deco.size * 2, deco.size * 1.4, deco.size * 0.3)
                nvgFillColor(vg, nvgRGBA(40, 50, 65, 220))
                nvgFill(vg)
            elseif deco.type == 3 then
                -- 海草（摇摆）
                local swayX = math.sin(gameTime * 1.5 + deco.phase) * 5
                nvgBeginPath(vg)
                nvgMoveTo(vg, deco.x, deco.y)
                nvgQuadTo(vg, deco.x + swayX, deco.y - deco.size * 0.6,
                    deco.x + swayX * 1.5, deco.y - deco.size)
                nvgStrokeColor(vg, nvgRGBA(30, 80, 50, 180))
                nvgStrokeWidth(vg, 2)
                nvgStroke(vg)
            elseif deco.type == 4 then
                -- 珊瑚
                local glow = math.sin(gameTime * 2 + deco.phase) * 20 + 40
                nvgBeginPath(vg)
                nvgCircle(vg, deco.x, deco.y - deco.size * 0.5, deco.size * 0.5)
                nvgFillColor(vg, nvgRGBA(60, 120 + math.floor(glow), 100, 180))
                nvgFill(vg)
            end
        end
    end
end

-- ============================================================
-- 遗迹绘制
-- ============================================================

function EVAView.DrawRuins(vg, world, eva, gameTime)
    if not world or not world.ruins then return end

    for _, ruin in ipairs(world.ruins) do
        local c = ruin.color

        -- 遗迹底色（暗色建筑轮廓）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ruin.x, ruin.y, ruin.width, ruin.height, 5)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 180))
        nvgFill(vg)

        -- 边框
        nvgStrokeColor(vg, nvgRGBA(c[1] + 30, c[2] + 30, c[3] + 30, 120))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 内部结构线条（窗户/裂缝效果）
        nvgStrokeColor(vg, nvgRGBA(c[1] - 10, c[2] - 10, c[3] - 10, 100))
        nvgStrokeWidth(vg, 1)
        for i = 1, 3 do
            nvgBeginPath(vg)
            local lx = ruin.x + ruin.width * (i * 0.25)
            nvgMoveTo(vg, lx, ruin.y + 5)
            nvgLineTo(vg, lx + math.sin(i * 2.1) * 5, ruin.y + ruin.height - 5)
            nvgStroke(vg)
        end

        -- 发光装饰点（散布在遗迹上）
        local glow = math.sin(gameTime * 1.5 + ruin.x * 0.01) * 30 + 50
        nvgBeginPath(vg)
        nvgCircle(vg, ruin.x + ruin.width * 0.3, ruin.y + ruin.height * 0.4, 3)
        nvgFillColor(vg, nvgRGBA(80, 200, 150, math.floor(glow)))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgCircle(vg, ruin.x + ruin.width * 0.7, ruin.y + ruin.height * 0.6, 2)
        nvgFillColor(vg, nvgRGBA(100, 180, 220, math.floor(glow * 0.8)))
        nvgFill(vg)

        -- 遗迹名称标签（潜水员靠近时显示）
        local dx = eva.x - (ruin.x + ruin.width * 0.5)
        local dy = eva.y - (ruin.y + ruin.height * 0.5)
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 200 then
            local alpha = math.max(0, 1 - dist / 200) * 180
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(Colors.ruinLabel[1], Colors.ruinLabel[2], Colors.ruinLabel[3], math.floor(alpha)))
            nvgText(vg, ruin.x + ruin.width * 0.5, ruin.y - 8, ruin.name, nil)
        end
    end
end

-- ============================================================
-- 战利品绘制
-- ============================================================

function EVAView.DrawLoots(vg, world, eva, gameTime)
    if not world or not world.loots then return end

    for _, loot in ipairs(world.loots) do
        if not loot.collected then
            -- 发光光环
            local glow = math.sin(gameTime * 3 + loot.glowPhase) * 0.3 + 0.7
            local radius = 8 * glow

            -- 外圈光晕
            local grad = nvgRadialGradient(vg, loot.x, loot.y, 2, radius + 8,
                nvgRGBA(Colors.lootGlow[1], Colors.lootGlow[2], Colors.lootGlow[3], math.floor(80 * glow)),
                nvgRGBA(Colors.lootGlow[1], Colors.lootGlow[2], Colors.lootGlow[3], 0))
            nvgBeginPath(vg)
            nvgCircle(vg, loot.x, loot.y, radius + 8)
            nvgFillPaint(vg, grad)
            nvgFill(vg)

            -- 核心光点
            nvgBeginPath(vg)
            nvgCircle(vg, loot.x, loot.y, 4)
            nvgFillColor(vg, nvgRGBA(Colors.lootCore[1], Colors.lootCore[2], Colors.lootCore[3], math.floor(200 * glow)))
            nvgFill(vg)

            -- 靠近时显示名称
            local dx = eva.x - loot.x
            local dy = eva.y - loot.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < EVASystem.Config.pickupRadius * 2 then
                local alpha = math.max(0, 1 - dist / (EVASystem.Config.pickupRadius * 2)) * 220
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(200, 255, 220, math.floor(alpha)))
                nvgText(vg, loot.x, loot.y - 12, loot.name, nil)

                -- 拾取提示
                if dist < EVASystem.Config.pickupRadius then
                    nvgFontSize(vg, 8)
                    nvgFillColor(vg, nvgRGBA(255, 255, 100, math.floor(150 + math.sin(gameTime * 5) * 60)))
                    nvgText(vg, loot.x, loot.y - 22, "[F] 拾取", nil)
                end
            end
        end
    end
end

-- ============================================================
-- 潜艇轮廓
-- ============================================================

function EVAView.DrawSubSilhouette(vg, gameTime)
    local cfg = EVASystem.Config
    local subX = 50
    local subY = cfg.subDockY - 60
    local subW = 250
    local subH = 120

    -- 潜艇暗色轮廓
    nvgBeginPath(vg)
    nvgRoundedRect(vg, subX, subY, subW, subH, 30)
    nvgFillColor(vg, nvgRGBA(Colors.subSilhouette[1], Colors.subSilhouette[2], Colors.subSilhouette[3], Colors.subSilhouette[4]))
    nvgFill(vg)

    -- 气闸门（亮色标记）
    local airlockX = subX + subW - 30
    local airlockY = cfg.subDockY - 15
    local airlockW = 20
    local airlockH = 30
    local pulse = math.sin(gameTime * 2) * 30 + 180
    nvgBeginPath(vg)
    nvgRoundedRect(vg, airlockX, airlockY, airlockW, airlockH, 3)
    nvgFillColor(vg, nvgRGBA(Colors.airlock[1], Colors.airlock[2], Colors.airlock[3], math.floor(pulse)))
    nvgFill(vg)

    -- 气闸标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(140, 200, 240, 150))
    nvgText(vg, airlockX + airlockW * 0.5, airlockY + airlockH + 4, "气闸", nil)

    -- 潜艇灯光
    nvgBeginPath(vg)
    nvgCircle(vg, subX + 30, subY + subH * 0.5, 4)
    nvgFillColor(vg, nvgRGBA(255, 240, 180, math.floor(100 + math.sin(gameTime * 3) * 30)))
    nvgFill(vg)
end

-- ============================================================
-- 潜水员绘制
-- ============================================================

function EVAView.DrawDiver(vg, eva, gameTime)
    local x = eva.x
    local y = eva.y
    local facing = eva.facing
    local swimPhase = eva.swimAnim

    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgScale(vg, facing, 1)  -- 翻转朝向

    -- 身体倾斜（游泳时倾斜）
    local tilt = math.sin(swimPhase * 0.5) * 5
    local speed = math.sqrt(eva.vx * eva.vx + eva.vy * eva.vy)
    if speed > 10 then
        tilt = tilt + eva.angle * facing * 10
    end
    nvgRotate(vg, math.rad(tilt))

    -- 氧气瓶（背部）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -4, -12, 8, 20, 3)
    nvgFillColor(vg, nvgRGBA(Colors.oxygenTank[1], Colors.oxygenTank[2], Colors.oxygenTank[3], 255))
    nvgFill(vg)
    -- 氧气瓶状态指示
    local oxyPct = EVASystem.GetOxygenPercent(eva)
    local oxyR = math.floor(255 * (1 - oxyPct))
    local oxyG = math.floor(180 * oxyPct)
    nvgBeginPath(vg)
    nvgRect(vg, -2, -10 + 16 * (1 - oxyPct), 4, 16 * oxyPct)
    nvgFillColor(vg, nvgRGBA(oxyR, oxyG, 100, 200))
    nvgFill(vg)

    -- 身体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -8, -15, 16, 25, 4)
    nvgFillColor(vg, nvgRGBA(Colors.suitBody[1], Colors.suitBody[2], Colors.suitBody[3], 255))
    nvgFill(vg)
    -- 身体高光
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -6, -13, 6, 20, 3)
    nvgFillColor(vg, nvgRGBA(Colors.suitHighlight[1], Colors.suitHighlight[2], Colors.suitHighlight[3], 80))
    nvgFill(vg)

    -- 头盔
    nvgBeginPath(vg)
    nvgCircle(vg, 0, -20, 10)
    nvgFillColor(vg, nvgRGBA(Colors.helmet[1], Colors.helmet[2], Colors.helmet[3], 255))
    nvgFill(vg)
    -- 面罩玻璃
    nvgBeginPath(vg)
    nvgCircle(vg, 2, -20, 6)
    nvgFillColor(vg, nvgRGBA(Colors.helmetVisor[1], Colors.helmetVisor[2], Colors.helmetVisor[3], Colors.helmetVisor[4]))
    nvgFill(vg)

    -- 腿部（游泳摆动）
    local legSwing = math.sin(swimPhase * 2) * 12
    nvgBeginPath(vg)
    nvgMoveTo(vg, -3, 10)
    nvgLineTo(vg, -3 + legSwing * 0.5, 25)
    nvgStrokeColor(vg, nvgRGBA(Colors.suitBody[1] - 10, Colors.suitBody[2] - 10, Colors.suitBody[3] - 10, 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 3, 10)
    nvgLineTo(vg, 3 - legSwing * 0.5, 25)
    nvgStroke(vg)

    -- 脚蹼
    nvgBeginPath(vg)
    nvgEllipse(vg, -3 + legSwing * 0.5, 27, 6, 3)
    nvgFillColor(vg, nvgRGBA(40, 60, 80, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, 3 - legSwing * 0.5, 27, 6, 3)
    nvgFill(vg)

    -- 手臂（向前伸展游泳）
    local armSwing = math.sin(swimPhase * 2 + 1.5) * 8
    nvgBeginPath(vg)
    nvgMoveTo(vg, 8, -8)
    nvgLineTo(vg, 14 + armSwing, -5 + armSwing * 0.3)
    nvgStrokeColor(vg, nvgRGBA(Colors.suitBody[1], Colors.suitBody[2], Colors.suitBody[3], 255))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    nvgRestore(vg)
end

--- 绘制简化潜水员图标（用于穿衣动画）
function EVAView.DrawDiverIcon(vg, x, y, gameTime)
    -- 头盔
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 20, 14)
    nvgFillColor(vg, nvgRGBA(170, 190, 210, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x + 3, y - 20, 8)
    nvgFillColor(vg, nvgRGBA(40, 180, 220, 200))
    nvgFill(vg)

    -- 身体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 12, y - 8, 24, 35, 6)
    nvgFillColor(vg, nvgRGBA(60, 100, 140, 255))
    nvgFill(vg)

    -- 氧气瓶
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 5, y - 5, 10, 25, 4)
    nvgFillColor(vg, nvgRGBA(90, 95, 100, 255))
    nvgFill(vg)
end

-- ============================================================
-- 头灯光锥
-- ============================================================

function EVAView.DrawHeadlight(vg, eva, w, h)
    if not eva.headlightOn then return end

    local x = eva.x
    local y = eva.y - 18  -- 头盔位置
    local radius = EVASystem.Config.headlightRadius
    local angleRad = math.rad(EVASystem.Config.headlightAngle)

    -- 光锥方向（朝面向方向）
    local dirX = eva.facing
    local coneX = x + dirX * radius

    -- 渐变光锥
    local grad = nvgRadialGradient(vg, x + dirX * 20, y, 10, radius,
        nvgRGBA(255, 250, 230, 40),
        nvgRGBA(200, 230, 255, 0))

    nvgBeginPath(vg)
    nvgMoveTo(vg, x + dirX * 8, y)
    nvgLineTo(vg, coneX, y - radius * math.sin(angleRad))
    nvgLineTo(vg, coneX, y + radius * math.sin(angleRad))
    nvgClosePath(vg)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

-- ============================================================
-- 气泡
-- ============================================================

function EVAView.DrawBubbles(vg, eva, gameTime)
    for _, b in ipairs(eva.bubbles) do
        local alpha = math.floor(b.life / 2.0 * 80)
        nvgBeginPath(vg)
        nvgCircle(vg, b.x, b.y, b.size)
        nvgFillColor(vg, nvgRGBA(Colors.bubble[1], Colors.bubble[2], Colors.bubble[3], alpha))
        nvgFill(vg)
        -- 气泡高光
        nvgBeginPath(vg)
        nvgCircle(vg, b.x - b.size * 0.3, b.y - b.size * 0.3, b.size * 0.3)
        nvgFillColor(vg, nvgRGBA(200, 240, 255, math.floor(alpha * 0.5)))
        nvgFill(vg)
    end
end

-- ============================================================
-- 暗角效果
-- ============================================================

function EVAView.DrawVignette(vg, w, h)
    -- 四角暗色渐变，增加深海压迫感
    local size = math.max(w, h) * 0.6
    local grad = nvgRadialGradient(vg, w * 0.5, h * 0.5, size * 0.5, size,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, 100))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

-- ============================================================
-- HUD
-- ============================================================

function EVAView.DrawHUD(vg, w, h, eva, world, gameTime)
    -- 氧气条（顶部中央）
    EVAView.DrawOxygenBar(vg, w, h, eva, gameTime)

    -- 状态信息（左上）
    EVAView.DrawStatusInfo(vg, w, h, eva, world, gameTime)

    -- 返回提示（靠近气闸时）
    if EVASystem.IsNearDock(eva) then
        EVAView.DrawDockPrompt(vg, w, h, gameTime)
    end

    -- 紧急警告（氧气低）
    if eva.oxygenWarning then
        EVAView.DrawOxygenWarning(vg, w, h, gameTime)
    end

    -- 收集物显示（右侧）
    EVAView.DrawCollectedLoot(vg, w, h, eva)
end

function EVAView.DrawOxygenBar(vg, w, h, eva, gameTime)
    local barW = 200
    local barH = 14
    local barX = (w - barW) * 0.5
    local barY = 15

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 2, barY - 2, barW + 4, barH + 4, 5)
    nvgFillColor(vg, nvgRGBA(Colors.oxygenBg[1], Colors.oxygenBg[2], Colors.oxygenBg[3], Colors.oxygenBg[4]))
    nvgFill(vg)

    -- 氧气量
    local pct = EVASystem.GetOxygenPercent(eva)
    local fillW = barW * pct

    -- 颜色插值（满→蓝，空→红）
    local r = math.floor(Colors.oxygenFull[1] + (Colors.oxygenLow[1] - Colors.oxygenFull[1]) * (1 - pct))
    local g = math.floor(Colors.oxygenFull[2] + (Colors.oxygenLow[2] - Colors.oxygenFull[2]) * (1 - pct))
    local b = math.floor(Colors.oxygenFull[3] + (Colors.oxygenLow[3] - Colors.oxygenFull[3]) * (1 - pct))

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, fillW, barH, 4)
    nvgFillColor(vg, nvgRGBA(r, g, b, 220))
    nvgFill(vg)

    -- 低氧气闪烁
    if pct < 0.25 then
        local flash = math.sin(gameTime * 6) * 0.5 + 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, fillW, barH, 4)
        nvgFillColor(vg, nvgRGBA(255, 50, 50, math.floor(flash * 80)))
        nvgFill(vg)
    end

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 240, 255, 220))
    nvgText(vg, w * 0.5, barY + barH * 0.5, string.format("O₂ %.0f%%  [%.0fs]", pct * 100, eva.oxygen), nil)

    -- 图标
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(r, g, b, 240))
    nvgText(vg, barX - 8, barY + barH * 0.5, "🫁", nil)
end

function EVAView.DrawStatusInfo(vg, w, h, eva, world, gameTime)
    local x = 15
    local y = 45

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 收集进度
    local remaining = 0
    if world then
        remaining = 0
        for _, loot in ipairs(world.loots) do
            if not loot.collected then remaining = remaining + 1 end
        end
    end
    nvgFillColor(vg, nvgRGBA(150, 200, 180, 180))
    nvgText(vg, x, y, string.format("剩余物品: %d", remaining), nil)

    -- 探索时间
    nvgFillColor(vg, nvgRGBA(130, 170, 200, 160))
    nvgText(vg, x, y + 14, string.format("探索: %.0fs", eva.totalExploreTime), nil)

    -- 操作提示
    nvgFillColor(vg, nvgRGBA(120, 140, 160, 140))
    nvgText(vg, x, y + 32, "[摇杆] 游泳  [F] 拾取", nil)
    nvgText(vg, x, y + 44, "[G] 返回气闸", nil)
end

function EVAView.DrawDockPrompt(vg, w, h, gameTime)
    local pulse = math.sin(gameTime * 3) * 30 + 200
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, math.floor(pulse)))
    nvgText(vg, w * 0.5, h - 40, "按 [G] 返回气闸", nil)
end

function EVAView.DrawOxygenWarning(vg, w, h, gameTime)
    -- 屏幕边缘红色闪烁
    local flash = math.sin(gameTime * 4) * 0.5 + 0.5
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(200, 30, 0, math.floor(flash * 40)))
    nvgFill(vg)

    -- 警告文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 60, 40, math.floor(150 + flash * 100)))
    nvgText(vg, w * 0.5, 38, "⚠ 氧气不足！立即返回！", nil)
end

function EVAView.DrawCollectedLoot(vg, w, h, eva)
    if #eva.collectedLoot == 0 then return end

    local x = w - 140
    local y = 45

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 200, 200))
    nvgText(vg, x, y, "已收集:", nil)

    for i, item in ipairs(eva.collectedLoot) do
        if i > 6 then
            nvgFillColor(vg, nvgRGBA(140, 160, 170, 150))
            nvgText(vg, x + 5, y + i * 13, string.format("... +%d", #eva.collectedLoot - 6), nil)
            break
        end
        nvgFillColor(vg, nvgRGBA(160, 240, 200, 180))
        nvgText(vg, x + 5, y + i * 13, string.format("· %s (%d)", item.name, item.value), nil)
    end
end

return EVAView
