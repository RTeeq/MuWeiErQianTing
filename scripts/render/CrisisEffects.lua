--- 危机视觉效果渲染（扩展版）
--- 支持8种危机类型的视觉效果
--- - 修复进度条 + 诊断进度
--- - 焊接火花粒子（修补时）
--- - 操作设备动画
--- - 舱室叠加效果（过热/火/毒气）
--- - 怪物入侵视觉

local Config = require("Config")

local CrisisEffects = {}

-- 火花粒子池
local sparks = {}
local MAX_SPARKS = 40

-- 危机类型显示名和颜色
local CRISIS_DISPLAY = {
    breach              = { text = "!! 船体破裂 !!", color = {240, 80, 50} },
    overheat            = { text = "!! 反应堆过热 !!", color = {255, 120, 30} },
    power_failure       = { text = "!! 电力故障 !!", color = {180, 130, 255} },
    fire                = { text = "!! 火灾 !!", color = {255, 80, 20} },
    monster_invasion    = { text = "!! 怪物入侵 !!", color = {200, 50, 200} },
    equipment_malfunction = { text = "!! 设备故障 !!", color = {150, 200, 60} },
    toxic_gas           = { text = "!! 有毒气体 !!", color = {60, 200, 100} },
    crew_madness        = { text = "!! 船员恐慌 !!", color = {180, 100, 220} },
}

-- 严重度颜色修正
local SEVERITY_TINT = {
    minor    = 0.6,     -- 降低亮度
    moderate = 1.0,     -- 正常
    critical = 1.3,     -- 增强
}

-- ============================================================
-- 焊接火花粒子系统
-- ============================================================

--- 生成焊接火花
---@param x number 焊接位置X
---@param y number 焊接位置Y
function CrisisEffects.EmitSparks(x, y)
    for _ = 1, math.random(2, 3) do
        if #sparks < MAX_SPARKS then
            table.insert(sparks, {
                x = x + (math.random() - 0.5) * 6,
                y = y + (math.random() - 0.5) * 4,
                vx = (math.random() - 0.5) * 120,
                vy = -math.random() * 80 - 20,
                life = 0.4 + math.random() * 0.5,
                maxLife = 0.4 + math.random() * 0.5,
                size = 1.5 + math.random() * 2.0,
                r = 255,
                g = math.floor(180 + math.random() * 75),
                b = math.floor(30 + math.random() * 50),
            })
        end
    end
end

--- 更新火花粒子
---@param dt number
function CrisisEffects.UpdateSparks(dt)
    for i = #sparks, 1, -1 do
        local s = sparks[i]
        s.life = s.life - dt
        if s.life <= 0 then
            table.remove(sparks, i)
        else
            s.vy = s.vy + 200 * dt
            s.vx = s.vx * 0.96
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt
            local progress = 1.0 - (s.life / s.maxLife)
            s.size = s.size * (1.0 - progress * 0.5)
        end
    end
end

--- 绘制火花粒子
---@param vg userdata
function CrisisEffects.DrawSparks(vg)
    for _, s in ipairs(sparks) do
        local alpha = math.floor(255 * (s.life / s.maxLife))
        nvgBeginPath(vg)
        nvgCircle(vg, s.x, s.y, s.size)
        nvgFillColor(vg, nvgRGBA(s.r, s.g, s.b, alpha))
        nvgFill(vg)

        -- 拖尾光晕
        local glow = nvgRadialGradient(vg, s.x, s.y, 0, s.size * 3,
            nvgRGBA(s.r, s.g, s.b, math.floor(alpha * 0.3)),
            nvgRGBA(s.r, s.g, s.b, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, s.x, s.y, s.size * 3)
        nvgFillPaint(vg, glow)
        nvgFill(vg)
    end
end

-- ============================================================
-- 修复进度条
-- ============================================================

--- 绘制角色头顶修复/诊断进度条
---@param vg userdata
---@param x number 角色X位置（屏幕坐标）
---@param y number 角色头顶Y
---@param progress number 0~1
---@param crisisType string
---@param isDiagnosing boolean 是否在诊断阶段
function CrisisEffects.DrawProgressBar(vg, x, y, progress, crisisType, isDiagnosing)
    local barW = 50
    local barH = 8
    local bx = x - barW * 0.5
    local by = y - 20

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(10, 10, 15, 200))
    nvgFill(vg)

    -- 确定颜色
    local display = CRISIS_DISPLAY[crisisType]
    local color = display and display.color or {100, 200, 100}
    if isDiagnosing then
        color = {100, 200, 255} -- 诊断用蓝色
    end

    -- 填充条
    local fillW = barW * progress
    if fillW > 1 then
        local grad = nvgLinearGradient(vg, bx, by, bx + fillW, by,
            nvgRGBA(color[1], color[2], color[3], 255),
            nvgRGBA(math.min(255, color[1] + 40), color[2], color[3], 200))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, fillW, barH, 3)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, barW, barH, 3)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    local label = isDiagnosing and "诊断中" or string.format("%d%%", math.floor(progress * 100))
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 200))
    nvgText(vg, x, by - 2, label, nil)
end

-- ============================================================
-- 操作特效（修复时）
-- ============================================================

--- 绘制操作设备特效
---@param vg userdata
---@param x number 设备X位置
---@param y number 设备Y位置
---@param crisisType string
---@param gameTime number
function CrisisEffects.DrawOperateEffect(vg, x, y, crisisType, gameTime)
    if crisisType == "overheat" then
        -- 降温效果：蓝色冷气向上飘
        for i = 0, 5 do
            local phase = gameTime * 2 + i * 1.0
            local py = y - (phase % 1.0) * 60
            local px = x + math.sin(phase * 3 + i) * 15
            local alpha = math.floor(150 * (1.0 - (phase % 1.0)))
            local size = 3 + (phase % 1.0) * 4
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, size)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, alpha))
            nvgFill(vg)
        end

    elseif crisisType == "fire" then
        -- 灭火效果：白色泡沫粒子
        for i = 0, 7 do
            local phase = gameTime * 2.5 + i * 0.9
            local px = x + math.cos(phase * 2 + i) * 20
            local py = y + math.sin(phase * 1.5 + i) * 15 - 10
            local alpha = math.floor(180 * (0.5 + math.sin(phase) * 0.5))
            local size = 2 + math.sin(phase * 3) * 2
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, size)
            nvgFillColor(vg, nvgRGBA(230, 240, 255, alpha))
            nvgFill(vg)
        end

    elseif crisisType == "toxic_gas" then
        -- 通风效果：风线条
        for i = 0, 4 do
            local phase = (gameTime * 3 + i * 0.5) % 1.0
            local startX = x - 30
            local endX = x + 30
            local lx = startX + phase * (endX - startX)
            local ly = y - 20 + math.sin(gameTime * 4 + i) * 5
            local alpha = math.floor(120 * (1.0 - math.abs(phase - 0.5) * 2))
            nvgBeginPath(vg)
            nvgMoveTo(vg, lx, ly)
            nvgLineTo(vg, lx + 15, ly + math.sin(gameTime * 5 + i) * 3)
            nvgStrokeColor(vg, nvgRGBA(200, 255, 200, alpha))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

    elseif crisisType == "equipment_malfunction" then
        -- 维修效果：齿轮旋转 + 工具扳手
        local angle = gameTime * 4
        for i = 0, 5 do
            local a = angle + i * math.pi / 3
            local rx = x + math.cos(a) * 12
            local ry = (y - 25) + math.sin(a) * 12
            local alpha = math.floor(150 + math.sin(gameTime * 6 + i) * 80)
            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, 2)
            nvgFillColor(vg, nvgRGBA(200, 200, 100, alpha))
            nvgFill(vg)
        end

    elseif crisisType == "power_failure" then
        -- 电路修复：电火花
        local pulse = math.sin(gameTime * 10)
        if pulse > 0.5 then
            nvgBeginPath(vg)
            nvgMoveTo(vg, x - 8, y - 25)
            nvgLineTo(vg, x + 2, y - 30)
            nvgLineTo(vg, x - 2, y - 20)
            nvgLineTo(vg, x + 8, y - 28)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 220))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

    elseif crisisType == "monster_invasion" then
        -- 攻击效果：红色冲击波
        local pulse = (gameTime * 2) % 1.0
        local radius = 10 + pulse * 25
        local alpha = math.floor(180 * (1.0 - pulse))
        nvgBeginPath(vg)
        nvgCircle(vg, x, y - 15, radius)
        nvgStrokeColor(vg, nvgRGBA(255, 50, 80, alpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

    elseif crisisType == "crew_madness" then
        -- 安抚效果：柔和光环
        local pulse = 0.5 + math.sin(gameTime * 2) * 0.5
        local grad = nvgRadialGradient(vg, x, y - 20, 5, 25,
            nvgRGBA(100, 200, 255, math.floor(80 * pulse)),
            nvgRGBA(100, 200, 255, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, x, y - 20, 25)
        nvgFillPaint(vg, grad)
        nvgFill(vg)
    end
end

-- ============================================================
-- 反应堆过热舱室闪烁
-- ============================================================

--- 绘制反应堆过热效果
---@param vg userdata
---@param compX number
---@param compY number
---@param compW number
---@param compH number
---@param gameTime number
---@param temperature number|nil 当前温度 0~100
function CrisisEffects.DrawOverheatRoom(vg, compX, compY, compW, compH, gameTime, temperature)
    local temp = temperature or 70
    local intensity = math.min(1.0, temp / 100)

    -- 红色闪烁
    local flash = math.sin(gameTime * 6) * 0.5 + 0.5
    local alpha = math.floor((20 + flash * 50) * intensity)

    nvgBeginPath(vg)
    nvgRect(vg, compX, compY, compW, compH)
    nvgFillColor(vg, nvgRGBA(255, 40, 20, alpha))
    nvgFill(vg)

    -- 热浪纹
    nvgBeginPath(vg)
    for lx = 0, math.floor(compW), 8 do
        local ly = compY + compH * 0.3 + math.sin(gameTime * 3 + lx * 0.05) * 8 * intensity
        if lx == 0 then
            nvgMoveTo(vg, compX + lx, ly)
        else
            nvgLineTo(vg, compX + lx, ly)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(255, 100, 30, math.floor((40 + flash * 60) * intensity)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 温度超过80%时额外高温粒子
    if temp > 80 then
        for i = 1, 4 do
            local px = compX + math.random() * compW
            local py = compY + math.random() * compH * 0.5
            local pAlpha = math.floor(math.random() * 100 * intensity)
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, 2 + math.random() * 2)
            nvgFillColor(vg, nvgRGBA(255, 180, 50, pAlpha))
            nvgFill(vg)
        end
    end
end

-- ============================================================
-- 电力故障闪烁效果
-- ============================================================

--- 绘制断电舱室效果
---@param vg userdata
---@param compX number
---@param compY number
---@param compW number
---@param compH number
---@param gameTime number
function CrisisEffects.DrawPowerFailureRoom(vg, compX, compY, compW, compH, gameTime)
    -- 间歇性闪烁（模拟灯光挣扎）
    local flicker = math.sin(gameTime * 15) * math.sin(gameTime * 7.3)
    if flicker > 0.6 then
        -- 短暂亮起
        nvgBeginPath(vg)
        nvgRect(vg, compX, compY, compW, compH)
        nvgFillColor(vg, nvgRGBA(150, 130, 255, 15))
        nvgFill(vg)
    end

    -- 电火花偶尔出现
    if math.sin(gameTime * 3.7) > 0.9 then
        local sx = compX + math.random() * compW
        local sy = compY + math.random() * compH * 0.3
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgLineTo(vg, sx + (math.random() - 0.5) * 10, sy + math.random() * 8)
        nvgLineTo(vg, sx + (math.random() - 0.5) * 6, sy + math.random() * 12)
        nvgStrokeColor(vg, nvgRGBA(150, 180, 255, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
end

-- ============================================================
-- 怪物入侵视觉
-- ============================================================

--- 绘制舱室内怪物入侵效果
---@param vg userdata
---@param compX number
---@param compY number
---@param compW number
---@param compH number
---@param gameTime number
---@param monsterHp number 剩余血量
function CrisisEffects.DrawMonsterInvasion(vg, compX, compY, compW, compH, gameTime, monsterHp)
    -- 暗紫色威胁氛围
    local pulse = 0.5 + math.sin(gameTime * 4) * 0.5
    local alpha = math.floor(25 + pulse * 30)
    nvgBeginPath(vg)
    nvgRect(vg, compX, compY, compW, compH)
    nvgFillColor(vg, nvgRGBA(100, 20, 120, alpha))
    nvgFill(vg)

    -- 触手/阴影动画
    local centerX = compX + compW * 0.5
    local centerY = compY + compH * 0.6
    for i = 1, 4 do
        local angle = gameTime * 1.5 + i * math.pi * 0.5
        local length = 15 + math.sin(gameTime * 2 + i) * 8
        local ex = centerX + math.cos(angle) * length
        local ey = centerY + math.sin(angle) * length * 0.6

        nvgBeginPath(vg)
        nvgMoveTo(vg, centerX, centerY)
        local cx1 = centerX + math.cos(angle + 0.3) * length * 0.5
        local cy1 = centerY + math.sin(angle + 0.3) * length * 0.3
        nvgQuadTo(vg, cx1, cy1, ex, ey)
        nvgStrokeColor(vg, nvgRGBA(150, 40, 180, math.floor(120 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 怪物HP指示
    if monsterHp and monsterHp > 0 then
        local hpBarW = 30
        local hpBarH = 4
        local hpX = centerX - hpBarW * 0.5
        local hpY = compY + 8
        local hpRatio = math.min(1.0, monsterHp / 100)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, hpX, hpY, hpBarW, hpBarH, 2)
        nvgFillColor(vg, nvgRGBA(20, 10, 30, 180))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, hpX, hpY, hpBarW * hpRatio, hpBarH, 2)
        nvgFillColor(vg, nvgRGBA(200, 50, 180, 200))
        nvgFill(vg)
    end
end

-- ============================================================
-- 通用：获取危机显示信息
-- ============================================================

--- 获取危机显示文本
---@param crisisType string
---@return string text, table color
function CrisisEffects.GetDisplay(crisisType)
    local display = CRISIS_DISPLAY[crisisType]
    if display then
        return display.text, display.color
    end
    return "!! 危险 !!", {255, 60, 60}
end

--- 清空火花
function CrisisEffects.ClearSparks()
    sparks = {}
end

return CrisisEffects
