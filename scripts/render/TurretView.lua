--- 炮塔视角渲染 - 准星/后坐力/弹道轨迹/怪物/绿血粒子
local Config = require("Config")
local MonsterManager = require("MonsterManager")
local Monsters = require("render.Monsters")

local TurretView = {}

-- ============================================================
-- 绘制完整的炮塔操作视角
-- ============================================================

--- 绘制炮塔视角（全屏替代内部/外部视角）
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param turret table 炮塔系统数据
---@param monsterMgr table 怪物管理器
---@param gameTime number
function TurretView.Draw(vg, w, h, turret, monsterMgr, gameTime)
    -- 1. 深海背景（炮塔视角 - 前方视野）
    TurretView.DrawBackground(vg, w, h, gameTime)

    -- 2. 怪物（外部视角）
    local visible = monsterMgr and MonsterManager.GetVisibleMonsters(monsterMgr) or {}
    if #visible > 0 then
        Monsters.DrawExternal(vg, visible, w, h, gameTime)
    end

    -- 3. 弹道轨迹
    TurretView.DrawProjectiles(vg, w, h, turret, gameTime)

    -- 4. 炮塔框架（底部）
    TurretView.DrawTurretFrame(vg, w, h, turret, gameTime)

    -- 5. 准星
    TurretView.DrawCrosshair(vg, w, h, turret, gameTime)

    -- 6. 炮塔HUD
    TurretView.DrawHUD(vg, w, h, turret, monsterMgr, gameTime)
end

-- ============================================================
-- 深海背景（炮塔前方视角）
-- ============================================================
function TurretView.DrawBackground(vg, w, h, gameTime)
    -- 深海渐变
    local bgGrad = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(3, 12, 30, 255),
        nvgRGBA(1, 4, 10, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 深海微粒
    for i = 1, 30 do
        local px = (math.sin(gameTime * 0.3 + i * 2.1) * 0.5 + 0.5) * w
        local py = (math.cos(gameTime * 0.2 + i * 1.7) * 0.5 + 0.5) * h
        local pAlpha = math.floor(20 + math.sin(gameTime + i) * 15)
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, 1.5)
        nvgFillColor(vg, nvgRGBA(80, 150, 200, pAlpha))
        nvgFill(vg)
    end

    -- 远方光晕（潜艇探照灯漫反射）
    local lightGrad = nvgRadialGradient(vg, w * 0.5, h * 0.4, 0, w * 0.4,
        nvgRGBA(15, 40, 80, 30),
        nvgRGBA(5, 15, 30, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, lightGrad)
    nvgFill(vg)
end

-- ============================================================
-- 弹道轨迹
-- ============================================================
function TurretView.DrawProjectiles(vg, w, h, turret, gameTime)
    for _, proj in ipairs(turret.projectiles) do
        local px = proj.x * w
        local py = proj.y * h

        -- 弹丸主体（亮点）
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, 4)
        nvgFillColor(vg, nvgRGBA(255, 240, 100, 255))
        nvgFill(vg)

        -- 弹丸发光
        local projGlow = nvgRadialGradient(vg, px, py, 0, 12,
            nvgRGBA(255, 200, 50, 150),
            nvgRGBA(255, 150, 30, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, 12)
        nvgFillPaint(vg, projGlow)
        nvgFill(vg)

        -- 弹道轨迹线
        if proj.trail and #proj.trail > 1 then
            for j = 2, #proj.trail do
                local t1 = proj.trail[j - 1]
                local t2 = proj.trail[j]
                local alpha = math.floor(t2.alpha * 0.5)
                if alpha > 5 then
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, t1.x * w, t1.y * h)
                    nvgLineTo(vg, t2.x * w, t2.y * h)
                    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, alpha))
                    nvgStrokeWidth(vg, 2)
                    nvgStroke(vg)
                end
            end
        end
    end
end

-- ============================================================
-- 炮塔框架（底部视觉）
-- ============================================================
function TurretView.DrawTurretFrame(vg, w, h, turret, gameTime)
    -- 后坐力偏移
    local recoilOffset = turret.recoil * 8

    -- 炮塔底座（屏幕底部金属框）
    local baseH = 60 + recoilOffset
    local baseY = h - baseH

    -- 金属底座
    local baseGrad = nvgLinearGradient(vg, 0, baseY, 0, h,
        nvgRGBA(50, 55, 65, 240),
        nvgRGBA(30, 35, 42, 250))
    nvgBeginPath(vg)
    nvgRect(vg, 0, baseY, w, baseH)
    nvgFillPaint(vg, baseGrad)
    nvgFill(vg)

    -- 顶部边线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, baseY)
    nvgLineTo(vg, w, baseY)
    nvgStrokeColor(vg, nvgRGBA(100, 110, 130, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 炮管（居中）
    local barrelW = 16
    local barrelH = 40 + recoilOffset * 2
    local barrelX = w * 0.5 - barrelW * 0.5
    local barrelY = baseY - barrelH + recoilOffset

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barrelX, barrelY, barrelW, barrelH, 4)
    nvgFillColor(vg, nvgRGBA(70, 75, 85, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barrelX, barrelY, barrelW, barrelH, 4)
    nvgStrokeColor(vg, nvgRGBA(100, 105, 115, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 炮口闪光（射击时）
    if turret.recoil > 0.5 then
        local flashAlpha = math.floor((turret.recoil - 0.5) * 2 * 255)
        local muzzleGrad = nvgRadialGradient(vg, w * 0.5, barrelY - 5, 0, 25,
            nvgRGBA(255, 200, 50, flashAlpha),
            nvgRGBA(255, 150, 30, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, w * 0.5, barrelY - 5, 25)
        nvgFillPaint(vg, muzzleGrad)
        nvgFill(vg)
    end

    -- 侧面铆钉装饰
    for i = 1, 6 do
        local rx = w * (0.1 + i * 0.13)
        nvgBeginPath(vg)
        nvgCircle(vg, rx, baseY + 15, 3)
        nvgFillColor(vg, nvgRGBA(90, 95, 105, 200))
        nvgFill(vg)
    end

    -- 弹药指示灯
    local ammoX = w * 0.5 + 50
    local ammoY = baseY + 30
    for i = 1, 5 do
        local onAlpha = turret.canFire and 200 or 60
        nvgBeginPath(vg)
        nvgCircle(vg, ammoX + i * 15, ammoY, 4)
        nvgFillColor(vg, nvgRGBA(50, 200, 100, onAlpha))
        nvgFill(vg)
    end
end

-- ============================================================
-- 准星
-- ============================================================
function TurretView.DrawCrosshair(vg, w, h, turret, gameTime)
    local cx = turret.aimX * w
    local cy = turret.aimY * h

    -- 准星微颤（加入后坐力影响）
    local jitterX = math.sin(gameTime * 15) * (1 + turret.recoil * 8)
    local jitterY = math.cos(gameTime * 12) * (1 + turret.recoil * 6)
    cx = cx + jitterX
    cy = cy + jitterY

    local crossSize = 18
    local gap = 6

    -- 准星主色（科幻绿）
    local crossAlpha = turret.canFire and 220 or 120
    local cr, cg, cb = 80, 255, 130

    -- 四个短线
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, crossAlpha))
    nvgStrokeWidth(vg, 2)

    -- 上
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy - gap)
    nvgLineTo(vg, cx, cy - crossSize)
    nvgStroke(vg)
    -- 下
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx, cy + gap)
    nvgLineTo(vg, cx, cy + crossSize)
    nvgStroke(vg)
    -- 左
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - gap, cy)
    nvgLineTo(vg, cx - crossSize, cy)
    nvgStroke(vg)
    -- 右
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + gap, cy)
    nvgLineTo(vg, cx + crossSize, cy)
    nvgStroke(vg)

    -- 中心点
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 2)
    nvgFillColor(vg, nvgRGBA(cr, cg, cb, crossAlpha))
    nvgFill(vg)

    -- 外圈（旋转动画）
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, gameTime * 1.5)

    nvgBeginPath(vg)
    nvgArc(vg, 0, 0, crossSize + 5, 0, math.pi * 0.5, 1)
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, math.floor(crossAlpha * 0.4)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgArc(vg, 0, 0, crossSize + 5, math.pi, math.pi * 1.5, 1)
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, math.floor(crossAlpha * 0.4)))
    nvgStroke(vg)

    nvgRestore(vg)

    -- 锁定目标时准星变红
    -- (简单距离检测)
    local isLocked = false
    if turret.canFire then
        -- 未实装具体锁定检测，保持绿色
    end
end

-- ============================================================
-- 炮塔HUD
-- ============================================================
function TurretView.DrawHUD(vg, w, h, turret, monsterMgr, gameTime)
    -- 顶部标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(80, 200, 150, 200))
    nvgText(vg, w * 0.5, 12, "[ TURRET CONTROL ]", nil)

    -- 冷却指示
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    if turret.canFire then
        nvgFillColor(vg, nvgRGBA(80, 255, 130, 180))
        nvgText(vg, 15, 15, "READY", nil)
    else
        local coolPct = math.floor(turret.fireTimer / turret.fireCooldown * 100)
        nvgFillColor(vg, nvgRGBA(240, 180, 50, 180))
        nvgText(vg, 15, 15, string.format("COOLING %d%%", coolPct), nil)
    end

    -- 击杀统计
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 160))
    nvgText(vg, w - 15, 15, string.format("KILLS: %d", monsterMgr and monsterMgr.totalKills or 0), nil)

    -- 命中率
    if turret.shotsFired > 0 then
        local accuracy = math.floor(turret.shotsHit / turret.shotsFired * 100)
        nvgText(vg, w - 15, 30, string.format("ACC: %d%%", accuracy), nil)
    end

    -- 退出提示
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(150, 150, 170, 140))
    nvgText(vg, w * 0.5, h - 70, "点击射击 | 按 [T] 退出炮塔", nil)

    -- 边框扫描线效果
    local scanY = (gameTime * 50) % h
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, scanY)
    nvgLineTo(vg, w, scanY)
    nvgStrokeColor(vg, nvgRGBA(80, 200, 150, 15))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 四角准星框
    local cornerLen = 30
    local margin = 25
    nvgStrokeColor(vg, nvgRGBA(80, 200, 150, 100))
    nvgStrokeWidth(vg, 2)

    -- 左上
    nvgBeginPath(vg)
    nvgMoveTo(vg, margin, margin + cornerLen)
    nvgLineTo(vg, margin, margin)
    nvgLineTo(vg, margin + cornerLen, margin)
    nvgStroke(vg)
    -- 右上
    nvgBeginPath(vg)
    nvgMoveTo(vg, w - margin - cornerLen, margin)
    nvgLineTo(vg, w - margin, margin)
    nvgLineTo(vg, w - margin, margin + cornerLen)
    nvgStroke(vg)
    -- 左下
    nvgBeginPath(vg)
    nvgMoveTo(vg, margin, h - margin - cornerLen - 60)
    nvgLineTo(vg, margin, h - margin - 60)
    nvgLineTo(vg, margin + cornerLen, h - margin - 60)
    nvgStroke(vg)
    -- 右下
    nvgBeginPath(vg)
    nvgMoveTo(vg, w - margin - cornerLen, h - margin - 60)
    nvgLineTo(vg, w - margin, h - margin - 60)
    nvgLineTo(vg, w - margin, h - margin - cornerLen - 60)
    nvgStroke(vg)
end

return TurretView
