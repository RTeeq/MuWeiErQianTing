--- 舱室内部渲染：地板、墙壁、门、设备
local Config = require("Config")

local Compartments = {}

--- 绘制所有舱室内部
---@param vg userdata
---@param subX number 潜艇内部左边界屏幕X
---@param subY number 潜艇内部顶部Y
---@param subH number 潜艇内部高度
---@param sub table 潜艇数据
---@param gameTime number
function Compartments.Draw(vg, subX, subY, subH, sub, gameTime)
    -- 设置全局时间供设备渲染使用
    nvgTime = gameTime
    for i, comp in ipairs(sub.compartments) do
        local cx = subX + comp.x
        local cw = comp.width

        -- 舱室地板
        local floorH = 8
        local fc = Config.Colors.floorColor
        nvgBeginPath(vg)
        nvgRect(vg, cx, subY + subH - floorH, cw, floorH)
        nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], fc[4]))
        nvgFill(vg)

        -- 地板金属格栅纹理
        nvgStrokeColor(vg, nvgRGBA(55, 58, 65, 150))
        nvgStrokeWidth(vg, 1)
        for gx = cx + 10, cx + cw - 10, 15 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, gx, subY + subH - floorH)
            nvgLineTo(vg, gx, subY + subH)
            nvgStroke(vg)
        end

        -- 天花板管道（可抓取区域）
        local pipeH = Config.Structure.pipeHeight or 20
        -- 主管道背景
        nvgBeginPath(vg)
        nvgRect(vg, cx, subY, cw, pipeH)
        nvgFillColor(vg, nvgRGBA(38, 42, 52, 255))
        nvgFill(vg)
        -- 管道细节线条
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, subY + pipeH)
        nvgLineTo(vg, cx + cw, subY + pipeH)
        nvgStrokeColor(vg, nvgRGBA(60, 65, 75, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        -- 管道横条（可攀抓标记）
        nvgStrokeColor(vg, nvgRGBA(75, 80, 90, 255))
        nvgStrokeWidth(vg, 3)
        for gx = cx + 30, cx + cw - 30, 50 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, gx, subY + pipeH - 5)
            nvgLineTo(vg, gx + 20, subY + pipeH - 5)
            nvgStroke(vg)
        end

        -- 扶手（每个舱室两侧墙壁）
        local handrailH = Config.Structure.handrailHeight or 60
        local floorTop = subY + subH - 8
        -- 左扶手
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + 8, floorTop - handrailH)
        nvgLineTo(vg, cx + 8, floorTop - 10)
        nvgStrokeColor(vg, nvgRGBA(90, 95, 105, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        -- 左扶手顶部横杆
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + 5, floorTop - handrailH)
        nvgLineTo(vg, cx + 35, floorTop - handrailH)
        nvgStroke(vg)
        -- 右扶手
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + cw - 8, floorTop - handrailH)
        nvgLineTo(vg, cx + cw - 8, floorTop - 10)
        nvgStroke(vg)
        -- 右扶手顶部横杆
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + cw - 35, floorTop - handrailH)
        nvgLineTo(vg, cx + cw - 5, floorTop - handrailH)
        nvgStroke(vg)

        -- 梯子（仅特定舱室有）
        local ladderSlots = Config.Structure.ladderSlots or {3, 5, 7}
        for _, slot in ipairs(ladderSlots) do
            if i == slot then
                Compartments.DrawLadder(vg, cx + cw * 0.5, subY, subH)
            end
        end

        -- 绘制设备
        Compartments.DrawEquipment(vg, cx, subY, cw, subH, comp, gameTime)

        -- 舱室间隔板和门（使用实际门状态数据）
        if i < #sub.compartments then
            local doorData = sub.doors and sub.doors[i] or nil
            Compartments.DrawDoor(vg, cx + cw, subY, subH, gameTime, doorData)
        end

        -- 舷窗（在舱壁上方绘制）
        if sub.portholes then
            for _, ph in ipairs(sub.portholes) do
                if ph.room == i then
                    local phX = cx + (ph.xOffset or 0.5) * cw
                    Compartments.DrawPorthole(vg, phX, subY, subH, ph, gameTime)
                end
            end
        end

        -- 水泵设备
        if sub.pumps then
            for _, pump in ipairs(sub.pumps) do
                if pump.room == i then
                    local pumpX = cx + cw * 0.85  -- 泵靠舱室右侧
                    local floorY = subY + subH - 8
                    Compartments.DrawWaterPump(vg, pumpX, floorY, pump, gameTime)
                end
            end
        end
    end
end

--- 绘制滑动门（上下分离式科幻风格，支持门状态数据）
function Compartments.DrawDoor(vg, doorX, subY, subH, gameTime, doorData)
    local dw = Config.Sub.doorWidth
    local dh = Config.Sub.doorHeight
    local df = Config.Colors.doorFrame
    local ds = Config.Colors.doorSliding

    -- 解析门状态
    local state = "closed"
    local locked = false
    local progress = 0
    local doorType = "normal"
    local balancing = false

    if doorData then
        state = doorData.state or "closed"
        locked = doorData.locked or false
        progress = doorData.progress or 0
        doorType = doorData.doorType or "normal"
        balancing = doorData.balancing or false
    end

    -- 根据门类型设置颜色
    local typeColors = Config.Door.types[doorType]
    local doorColor = typeColors and typeColors.color or {ds[1], ds[2], ds[3], ds[4]}

    -- 隔板（全高）
    nvgBeginPath(vg)
    nvgRect(vg, doorX - dw * 0.5, subY, dw, subH)
    nvgFillColor(vg, nvgRGBA(40, 43, 50, 255))
    nvgFill(vg)

    -- 门洞区域
    local doorY = subY + (subH - dh) * 0.7
    local halfH = dh * 0.5

    -- 计算门开合量（基于状态和progress）
    local openAmount = 0  -- 0=完全关闭, 1=完全打开
    if state == "open" then
        openAmount = 1.0
    elseif state == "opening" then
        openAmount = progress
    elseif state == "closing" then
        openAmount = 1.0 - progress
    else
        -- closed 状态下的呼吸微动
        openAmount = math.sin(gameTime * 0.3) * 0.02
    end

    local slideOffset = openAmount * halfH * 0.95  -- 开门时门板上下滑走

    -- 门框背景（深色门洞）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, doorX - dw * 0.5 + 1, doorY, dw - 2, dh, 2)
    nvgFillColor(vg, nvgRGBA(15, 18, 25, 255))
    nvgFill(vg)

    -- 上半门板（向上滑）
    nvgBeginPath(vg)
    nvgRect(vg, doorX - dw * 0.5 + 2, doorY - slideOffset, dw - 4, halfH)
    nvgFillColor(vg, nvgRGBA(doorColor[1], doorColor[2], doorColor[3], doorColor[4] or 255))
    nvgFill(vg)
    -- 上门板中线
    nvgBeginPath(vg)
    nvgMoveTo(vg, doorX - dw * 0.5 + 4, doorY - slideOffset + halfH * 0.5)
    nvgLineTo(vg, doorX + dw * 0.5 - 4, doorY - slideOffset + halfH * 0.5)
    nvgStrokeColor(vg, nvgRGBA(50, 55, 65, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 下半门板（向下滑）
    nvgBeginPath(vg)
    nvgRect(vg, doorX - dw * 0.5 + 2, doorY + halfH + slideOffset, dw - 4, halfH)
    nvgFillColor(vg, nvgRGBA(doorColor[1], doorColor[2], doorColor[3], doorColor[4] or 255))
    nvgFill(vg)
    -- 下门板中线
    nvgBeginPath(vg)
    nvgMoveTo(vg, doorX - dw * 0.5 + 4, doorY + halfH + slideOffset + halfH * 0.5)
    nvgLineTo(vg, doorX + dw * 0.5 - 4, doorY + halfH + slideOffset + halfH * 0.5)
    nvgStrokeColor(vg, nvgRGBA(50, 55, 65, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 锁定标记（X形红色）
    if locked then
        nvgBeginPath(vg)
        nvgMoveTo(vg, doorX - 6, doorY + halfH - 6)
        nvgLineTo(vg, doorX + 6, doorY + halfH + 6)
        nvgMoveTo(vg, doorX + 6, doorY + halfH - 6)
        nvgLineTo(vg, doorX - 6, doorY + halfH + 6)
        nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 门框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, doorX - dw * 0.5 + 1, doorY, dw - 2, dh, 2)
    local frameColor = locked and nvgRGBA(200, 50, 50, 200) or nvgRGBA(df[1], df[2], df[3], df[4])
    nvgStrokeColor(vg, frameColor)
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 门类型标志（airlock=蓝环, safety=红三角）
    if doorType == "airlock" then
        nvgBeginPath(vg)
        nvgCircle(vg, doorX, doorY - 10, 5)
        nvgStrokeColor(vg, nvgRGBA(60, 180, 255, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    elseif doorType == "safety" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, doorX, doorY - 14)
        nvgLineTo(vg, doorX - 5, doorY - 6)
        nvgLineTo(vg, doorX + 5, doorY - 6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 80, 50, 180))
        nvgFill(vg)
    end

    -- 指示灯（根据状态变色）
    nvgBeginPath(vg)
    nvgCircle(vg, doorX, doorY - 6 + (doorType ~= "normal" and -8 or 0), 3)
    if locked then
        nvgFillColor(vg, nvgRGBA(255, 50, 50, 220))
    elseif state == "open" then
        nvgFillColor(vg, nvgRGBA(50, 255, 100, 220))
    elseif balancing then
        -- 气压平衡中：蓝色脉冲
        local bpulse = math.floor(150 + 100 * math.sin(gameTime * 4))
        nvgFillColor(vg, nvgRGBA(80, 180, 255, bpulse))
    else
        nvgFillColor(vg, nvgRGBA(180, 180, 60, 150))
    end
    nvgFill(vg)
end

--- 绘制设备
function Compartments.DrawEquipment(vg, cx, subY, cw, subH, comp, gameTime)
    local floorY = subY + subH - 8  -- 地板顶部

    for idx, equipId in ipairs(comp.equipment) do
        local ex = cx + cw * (idx / (#comp.equipment + 1))
        local ey = floorY

        if equipId == "helm" then
            Compartments.DrawHelm(vg, ex, ey, gameTime)
        elseif equipId == "sonar" then
            Compartments.DrawSonar(vg, ex, ey, gameTime)
        elseif equipId == "reactor" then
            Compartments.DrawReactor(vg, ex, ey, gameTime)
        elseif equipId == "engine" then
            Compartments.DrawEngine(vg, ex, ey, gameTime)
        elseif equipId == "turret" then
            Compartments.DrawTurret(vg, ex, ey, gameTime)
        elseif equipId == "turret_bottom" then
            Compartments.DrawTurretBottom(vg, ex, ey, gameTime)
        elseif equipId == "medbed" then
            Compartments.DrawMedBed(vg, ex, ey)
        elseif equipId == "cabinet" then
            Compartments.DrawCabinet(vg, ex, ey)
        elseif equipId == "crate" or equipId == "crate2" then
            Compartments.DrawCrate(vg, ex, ey, idx)
        elseif equipId == "airlock_hatch" then
            Compartments.DrawAirlockHatch(vg, ex, ey, gameTime)
        elseif equipId == "suit_rack" then
            Compartments.DrawSuitRack(vg, ex, ey)
        end
    end
end

--- 舵盘
function Compartments.DrawHelm(vg, x, y, t)
    -- 控制台
    nvgBeginPath(vg)
    nvgRect(vg, x - 25, y - 60, 50, 60)
    nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
    nvgFill(vg)
    -- 屏幕
    nvgBeginPath(vg)
    nvgRect(vg, x - 18, y - 55, 36, 25)
    nvgFillColor(vg, nvgRGBA(20, 60, 40, 255))
    nvgFill(vg)
    -- 扫描线动画
    local scanY = ((t * 20) % 25)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - 18, y - 55 + scanY)
    nvgLineTo(vg, x + 18, y - 55 + scanY)
    nvgStrokeColor(vg, nvgRGBA(50, 200, 100, 100))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    -- 舵轮
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 25, 12)
    nvgStrokeColor(vg, nvgRGBA(140, 130, 100, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
end

--- 声呐
function Compartments.DrawSonar(vg, x, y, t)
    -- 圆形显示屏
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 45, 25)
    nvgFillColor(vg, nvgRGBA(5, 20, 10, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 45, 25)
    nvgStrokeColor(vg, nvgRGBA(50, 180, 80, 150))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    -- 扫描线（旋转）
    local angle = t * 2
    local sx = x + math.cos(angle) * 22
    local sy = y - 45 + math.sin(angle) * 22
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - 45)
    nvgLineTo(vg, sx, sy)
    nvgStrokeColor(vg, nvgRGBA(50, 255, 100, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    -- 底座
    nvgBeginPath(vg)
    nvgRect(vg, x - 15, y - 18, 30, 18)
    nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
    nvgFill(vg)
end

--- 反应堆（增强：红色核心光芒 + 环境红光照射）
function Compartments.DrawReactor(vg, x, y, t)
    -- 环境红色光晕（大范围照射地面和墙壁）
    local envPulse = 0.6 + math.sin(t * 2.0) * 0.4
    local envGrad = nvgRadialGradient(vg, x, y - 65, 10, 120,
        nvgRGBA(200, 40, 20, math.floor(30 * envPulse)),
        nvgRGBA(200, 40, 20, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 65, 120)
    nvgFillPaint(vg, envGrad)
    nvgFill(vg)

    -- 大型圆柱体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 35, y - 120, 70, 120, 8)
    nvgFillColor(vg, nvgRGBA(50, 55, 65, 255))
    nvgFill(vg)

    -- 核心发光（改为红色/橙色光芒）
    local pulse = 0.7 + math.sin(t * 3) * 0.3
    local glowR = 25 * pulse

    -- 外层红色辉光
    local redGlow = nvgRadialGradient(vg, x, y - 65, glowR * 0.2, glowR * 1.5,
        nvgRGBA(255, 60, 20, math.floor(100 * pulse)),
        nvgRGBA(180, 30, 10, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 65, glowR * 1.5)
    nvgFillPaint(vg, redGlow)
    nvgFill(vg)

    -- 中层橙色辉光
    local orangeGlow = nvgRadialGradient(vg, x, y - 65, glowR * 0.1, glowR,
        nvgRGBA(255, 120, 30, math.floor(180 * pulse)),
        nvgRGBA(255, 60, 20, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 65, glowR)
    nvgFillPaint(vg, orangeGlow)
    nvgFill(vg)

    -- 核心白热点
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 65, 8 * pulse)
    nvgFillColor(vg, nvgRGBA(255, 220, 180, math.floor(240 * pulse)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 65, 4)
    nvgFillColor(vg, nvgRGBA(255, 255, 240, 255))
    nvgFill(vg)

    -- 放射状光线（从核心向外）
    nvgSave(vg)
    nvgTranslate(vg, x, y - 65)
    for i = 0, 5 do
        local angle = t * 0.5 + i * math.pi / 3
        local rayLen = 20 + math.sin(t * 4 + i * 1.2) * 8
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, 0)
        nvgLineTo(vg, math.cos(angle) * rayLen, math.sin(angle) * rayLen)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 30, math.floor(60 * pulse)))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
    nvgRestore(vg)

    -- 管道装饰（带红色反光）
    nvgBeginPath(vg)
    nvgRect(vg, x - 35, y - 90, 70, 4)
    nvgFillColor(vg, nvgRGBA(90, 55, 55, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, x - 35, y - 40, 70, 4)
    nvgFillColor(vg, nvgRGBA(90, 55, 55, 255))
    nvgFill(vg)
end

--- 引擎（增强：蒸汽粒子效果）
function Compartments.DrawEngine(vg, x, y, t)
    -- 引擎箱体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 40, y - 80, 80, 80, 5)
    nvgFillColor(vg, nvgRGBA(55, 58, 65, 255))
    nvgFill(vg)
    -- 排气管
    for i = 0, 2 do
        nvgBeginPath(vg)
        nvgRect(vg, x - 30 + i * 25, y - 90, 8, 15)
        nvgFillColor(vg, nvgRGBA(65, 68, 75, 255))
        nvgFill(vg)
    end
    -- 旋转部件
    nvgSave(vg)
    nvgTranslate(vg, x, y - 40)
    nvgRotate(vg, t * 5)
    nvgBeginPath(vg)
    nvgRect(vg, -20, -3, 40, 6)
    nvgFillColor(vg, nvgRGBA(120, 125, 135, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, -3, -20, 6, 40)
    nvgFillColor(vg, nvgRGBA(120, 125, 135, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- 蒸汽粒子（从排气管向上飘散）
    for i = 0, 2 do
        local pipeX = x - 30 + i * 25 + 4
        local pipeTopY = y - 90
        -- 每根管道生成 3~4 个蒸汽粒子
        for p = 1, 4 do
            local phase = t * 1.5 + i * 2.1 + p * 1.7
            local progress = (phase % 2.5) / 2.5  -- 0~1 上升进度
            local px = pipeX + math.sin(phase * 2 + p) * (4 + progress * 8)
            local py = pipeTopY - progress * 50
            local size = 3 + progress * 6
            local alpha = math.floor(80 * (1 - progress) * (1 - progress))

            if alpha > 2 then
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, size)
                nvgFillColor(vg, nvgRGBA(180, 190, 200, alpha))
                nvgFill(vg)
            end
        end
    end

    -- 引擎热量辉光（底部橙色）
    local heatPulse = 0.6 + math.sin(t * 4) * 0.4
    local heatGrad = nvgRadialGradient(vg, x, y - 20, 5, 40,
        nvgRGBA(255, 100, 20, math.floor(40 * heatPulse)),
        nvgRGBA(255, 60, 10, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 20, 40)
    nvgFillPaint(vg, heatGrad)
    nvgFill(vg)
end

--- 炮塔
function Compartments.DrawTurret(vg, x, y, t)
    -- 基座
    nvgBeginPath(vg)
    nvgRect(vg, x - 30, y - 50, 60, 50)
    nvgFillColor(vg, nvgRGBA(55, 60, 68, 255))
    nvgFill(vg)
    -- 炮管
    nvgBeginPath(vg)
    nvgRect(vg, x + 10, y - 65, 40, 10)
    nvgFillColor(vg, nvgRGBA(70, 75, 82, 255))
    nvgFill(vg)
    -- 弹药指示
    local ammoColor = (math.sin(t * 2) > 0) and {240, 60, 60} or {60, 200, 100}
    nvgBeginPath(vg)
    nvgCircle(vg, x - 15, y - 60, 4)
    nvgFillColor(vg, nvgRGBA(ammoColor[1], ammoColor[2], ammoColor[3], 200))
    nvgFill(vg)
end

--- 医疗床（增强：绿色急救灯 + 心跳监控线）
function Compartments.DrawMedBed(vg, x, y)
    -- 绿色环境急救灯光晕
    local t = nvgTime or 0
    local pulse = 0.6 + math.sin(t * 2.5) * 0.4

    -- 绿色急救灯（天花板）
    local greenGlow = nvgRadialGradient(vg, x, y - 100, 5, 80,
        nvgRGBA(30, 220, 80, math.floor(35 * pulse)),
        nvgRGBA(20, 180, 60, 0))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 100, 80)
    nvgFillPaint(vg, greenGlow)
    nvgFill(vg)

    -- 急救灯本体（天花板小灯）
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 100, 5)
    nvgFillColor(vg, nvgRGBA(50, 255, 100, math.floor(200 * pulse)))
    nvgFill(vg)
    -- 灯光外圈
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 100, 8)
    nvgStrokeColor(vg, nvgRGBA(50, 255, 100, math.floor(100 * pulse)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 医疗床
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 30, y - 25, 60, 25, 3)
    nvgFillColor(vg, nvgRGBA(200, 210, 220, 255))
    nvgFill(vg)
    -- 十字标志
    nvgBeginPath(vg)
    nvgRect(vg, x - 5, y - 22, 10, 18)
    nvgFillColor(vg, nvgRGBA(200, 50, 50, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, x - 9, y - 16, 18, 6)
    nvgFillColor(vg, nvgRGBA(200, 50, 50, 255))
    nvgFill(vg)

    -- 心跳监控屏（床头上方）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 28, y - 55, 35, 22, 3)
    nvgFillColor(vg, nvgRGBA(5, 15, 10, 240))
    nvgFill(vg)
    -- 心跳线
    nvgBeginPath(vg)
    local monitorX = x - 25
    local monitorY = y - 44
    nvgMoveTo(vg, monitorX, monitorY)
    for px = 0, 28, 2 do
        local beatPhase = ((nvgTime or 0) * 3 + px * 0.3) % 6.28
        local beatY = 0
        if beatPhase > 2.5 and beatPhase < 3.0 then
            beatY = -8
        elseif beatPhase > 3.0 and beatPhase < 3.3 then
            beatY = 5
        elseif beatPhase > 3.3 and beatPhase < 3.6 then
            beatY = -3
        end
        nvgLineTo(vg, monitorX + px, monitorY + beatY)
    end
    nvgStrokeColor(vg, nvgRGBA(50, 255, 100, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

--- 药品柜
function Compartments.DrawCabinet(vg, x, y)
    nvgBeginPath(vg)
    nvgRect(vg, x - 15, y - 70, 30, 70)
    nvgFillColor(vg, nvgRGBA(180, 185, 195, 255))
    nvgFill(vg)
    -- 柜门线
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - 70)
    nvgLineTo(vg, x, y)
    nvgStrokeColor(vg, nvgRGBA(140, 145, 155, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    -- 把手
    nvgBeginPath(vg)
    nvgCircle(vg, x - 5, y - 35, 2)
    nvgFillColor(vg, nvgRGBA(100, 105, 115, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x + 5, y - 35, 2)
    nvgFillColor(vg, nvgRGBA(100, 105, 115, 255))
    nvgFill(vg)
end

--- 货箱
function Compartments.DrawCrate(vg, x, y, variant)
    local w = 30 + (variant or 1) * 5
    local h = 25 + (variant or 1) * 8
    nvgBeginPath(vg)
    nvgRect(vg, x - w * 0.5, y - h, w, h)
    nvgFillColor(vg, nvgRGBA(90, 75, 50, 255))
    nvgFill(vg)
    -- 木条纹
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - w * 0.5, y - h * 0.5)
    nvgLineTo(vg, x + w * 0.5, y - h * 0.5)
    nvgStrokeColor(vg, nvgRGBA(70, 55, 35, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    -- 边框
    nvgBeginPath(vg)
    nvgRect(vg, x - w * 0.5, y - h, w, h)
    nvgStrokeColor(vg, nvgRGBA(60, 50, 35, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

--- 底部炮塔（向下射击，座舱式）
function Compartments.DrawTurretBottom(vg, x, y, t)
    -- 地板安装基座
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 35, y - 40, 70, 40, 4)
    nvgFillColor(vg, nvgRGBA(50, 55, 65, 255))
    nvgFill(vg)

    -- 座椅
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 15, y - 60, 30, 25, 5)
    nvgFillColor(vg, nvgRGBA(60, 65, 80, 255))
    nvgFill(vg)

    -- 操控杆（两侧）
    nvgStrokeColor(vg, nvgRGBA(100, 105, 115, 255))
    nvgStrokeWidth(vg, 3)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - 25, y - 50)
    nvgLineTo(vg, x - 30, y - 65)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 25, y - 50)
    nvgLineTo(vg, x + 30, y - 65)
    nvgStroke(vg)
    -- 操控杆球头
    nvgBeginPath(vg)
    nvgCircle(vg, x - 30, y - 67, 4)
    nvgFillColor(vg, nvgRGBA(120, 125, 135, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x + 30, y - 67, 4)
    nvgFillColor(vg, nvgRGBA(120, 125, 135, 255))
    nvgFill(vg)

    -- 下方炮管指示（向下的箭头标记）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - 5)
    nvgLineTo(vg, x - 8, y - 15)
    nvgLineTo(vg, x + 8, y - 15)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 80, 50, 200))
    nvgFill(vg)

    -- 状态灯（闪烁）
    local blink = math.sin(t * 3) > 0
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 75, 3)
    nvgFillColor(vg, blink and nvgRGBA(50, 200, 100, 220) or nvgRGBA(200, 60, 60, 220))
    nvgFill(vg)
end

--- 气闸舱口（圆形密封门 + 警示标记）
function Compartments.DrawAirlockHatch(vg, x, y, t)
    -- 地板上的圆形舱口底座
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 40, y - 10, 80, 10, 2)
    nvgFillColor(vg, nvgRGBA(55, 58, 68, 255))
    nvgFill(vg)

    -- 圆形密封门
    local radius = 32
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 50, radius)
    nvgFillColor(vg, nvgRGBA(65, 70, 80, 255))
    nvgFill(vg)
    -- 门框
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 50, radius)
    nvgStrokeColor(vg, nvgRGBA(100, 105, 115, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 转轮手柄（十字形）
    nvgSave(vg)
    nvgTranslate(vg, x, y - 50)
    local rot = math.sin(t * 0.5) * 0.3
    nvgRotate(vg, rot)
    nvgStrokeColor(vg, nvgRGBA(130, 135, 145, 255))
    nvgStrokeWidth(vg, 4)
    nvgBeginPath(vg)
    nvgMoveTo(vg, -18, 0)
    nvgLineTo(vg, 18, 0)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -18)
    nvgLineTo(vg, 0, 18)
    nvgStroke(vg)
    -- 中心螺栓
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, 5)
    nvgFillColor(vg, nvgRGBA(90, 95, 105, 255))
    nvgFill(vg)
    nvgRestore(vg)

    -- 黄黑警示条纹（底座两侧）
    for stripe = 0, 3 do
        local sx = x - 38 + stripe * 20
        nvgBeginPath(vg)
        nvgRect(vg, sx, y - 10, 8, 10)
        nvgFillColor(vg, (stripe % 2 == 0) and nvgRGBA(220, 180, 30, 200) or nvgRGBA(30, 30, 30, 200))
        nvgFill(vg)
    end

    -- 压力指示灯
    local pressOk = math.sin(t * 1.5) > -0.3
    nvgBeginPath(vg)
    nvgCircle(vg, x + 28, y - 85, 4)
    nvgFillColor(vg, pressOk and nvgRGBA(50, 200, 100, 220) or nvgRGBA(240, 60, 60, 220))
    nvgFill(vg)
end

--- 潜水服架（三套EVA服挂架）
function Compartments.DrawSuitRack(vg, x, y)
    -- 金属支架背板
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 45, y - 110, 90, 110, 3)
    nvgFillColor(vg, nvgRGBA(42, 46, 55, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - 45, y - 110, 90, 110, 3)
    nvgStrokeColor(vg, nvgRGBA(60, 65, 75, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 三套潜水服轮廓
    local suitColors = {
        {50, 80, 140},   -- 深蓝
        {50, 80, 140},   -- 深蓝
        {180, 100, 30},  -- 橙色（紧急用）
    }
    for i = 1, 3 do
        local sx = x - 30 + (i - 1) * 28
        local sc = suitColors[i]

        -- 头盔（圆形）
        nvgBeginPath(vg)
        nvgCircle(vg, sx, y - 92, 8)
        nvgFillColor(vg, nvgRGBA(180, 185, 195, 240))
        nvgFill(vg)
        -- 面罩
        nvgBeginPath(vg)
        nvgCircle(vg, sx, y - 92, 5)
        nvgFillColor(vg, nvgRGBA(40, 80, 100, 200))
        nvgFill(vg)

        -- 身体
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - 8, y - 80, 16, 45, 3)
        nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 240))
        nvgFill(vg)

        -- 手臂
        nvgBeginPath(vg)
        nvgRect(vg, sx - 12, y - 78, 4, 30)
        nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, sx + 8, y - 78, 4, 30)
        nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 220))
        nvgFill(vg)

        -- 挂钩
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, y - 108)
        nvgLineTo(vg, sx, y - 100)
        nvgStrokeColor(vg, nvgRGBA(100, 105, 115, 255))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 底部标签 "EVA"
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(150, 160, 170, 200))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, x, y - 15, "EVA")
end

--- 梯子（连接天花板管道到地板）
function Compartments.DrawLadder(vg, x, subY, subH)
    local ladderW = Config.Sub.ladderWidth or 16
    local pipeH = Config.Structure.pipeHeight or 20
    local topY = subY + pipeH
    local botY = subY + subH - 8  -- 地板顶部

    -- 两根竖杆
    nvgStrokeColor(vg, nvgRGBA(100, 105, 115, 255))
    nvgStrokeWidth(vg, 3)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - ladderW * 0.5, topY)
    nvgLineTo(vg, x - ladderW * 0.5, botY)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + ladderW * 0.5, topY)
    nvgLineTo(vg, x + ladderW * 0.5, botY)
    nvgStroke(vg)

    -- 横档
    local rungSpacing = 25
    nvgStrokeColor(vg, nvgRGBA(85, 90, 100, 255))
    nvgStrokeWidth(vg, 2.5)
    for ry = topY + 15, botY - 10, rungSpacing do
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - ladderW * 0.5, ry)
        nvgLineTo(vg, x + ladderW * 0.5, ry)
        nvgStroke(vg)
    end
end

--- 绘制舷窗（正常/盖板关闭/破损三种状态）
function Compartments.DrawPorthole(vg, phX, subY, subH, phData, gameTime)
    local radius = Config.Porthole.radius
    local phY = subY + subH * 0.35  -- 舷窗在墙壁中上部

    local state = phData.state or "normal"
    local coverClosed = phData.coverClosed or false

    -- 外圈金属框
    nvgBeginPath(vg)
    nvgCircle(vg, phX, phY, radius + 4)
    nvgFillColor(vg, nvgRGBA(60, 65, 75, 255))
    nvgFill(vg)

    -- 舷窗玻璃（内部）
    nvgBeginPath(vg)
    nvgCircle(vg, phX, phY, radius)

    if state == "broken" then
        -- 破损状态：红色裂纹背景 + 水流进入感
        local flashAlpha = math.floor(100 + 80 * math.sin(gameTime * 6))
        nvgFillColor(vg, nvgRGBA(20, 50, 80, flashAlpha))
        nvgFill(vg)

        -- 裂纹线条
        nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 200))
        nvgStrokeWidth(vg, 1.5)
        for i = 1, 5 do
            local angle = i * 1.2 + 0.5
            local len = radius * (0.5 + math.sin(i * 2.7) * 0.4)
            nvgBeginPath(vg)
            nvgMoveTo(vg, phX, phY)
            nvgLineTo(vg, phX + math.cos(angle) * len, phY + math.sin(angle) * len)
            nvgStroke(vg)
        end

        -- 进水气泡
        for i = 1, 4 do
            local bx = phX + math.sin(gameTime * 2 + i * 1.5) * radius * 0.5
            local by = phY + ((gameTime * 30 + i * 20) % (radius * 2)) - radius
            nvgBeginPath(vg)
            nvgCircle(vg, bx, by, 2 + math.sin(i) * 1)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, 120))
            nvgFill(vg)
        end
    elseif coverClosed then
        -- 盖板关闭：金属覆盖
        nvgFillColor(vg, nvgRGBA(50, 55, 65, 255))
        nvgFill(vg)

        -- 盖板十字加强筋
        nvgBeginPath(vg)
        nvgMoveTo(vg, phX - radius + 4, phY)
        nvgLineTo(vg, phX + radius - 4, phY)
        nvgMoveTo(vg, phX, phY - radius + 4)
        nvgLineTo(vg, phX, phY + radius - 4)
        nvgStrokeColor(vg, nvgRGBA(80, 85, 95, 255))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        -- 螺栓点
        local boltR = radius - 5
        for i = 0, 3 do
            local angle = i * math.pi * 0.5 + math.pi * 0.25
            nvgBeginPath(vg)
            nvgCircle(vg, phX + math.cos(angle) * boltR, phY + math.sin(angle) * boltR, 2)
            nvgFillColor(vg, nvgRGBA(100, 105, 115, 255))
            nvgFill(vg)
        end
    else
        -- 正常状态：可透过玻璃看到外部深海（深蓝色）
        local deepBlue = nvgRadialGradient(vg, phX, phY, 0, radius,
            nvgRGBA(10, 30, 60, 200), nvgRGBA(5, 15, 35, 255))
        nvgFillPaint(vg, deepBlue)
        nvgFill(vg)

        -- 微弱光斑（模拟水中光线折射）
        local spotX = phX + math.sin(gameTime * 0.5) * radius * 0.3
        local spotY = phY + math.cos(gameTime * 0.7) * radius * 0.2
        nvgBeginPath(vg)
        nvgCircle(vg, spotX, spotY, 4)
        nvgFillColor(vg, nvgRGBA(100, 180, 255, 30))
        nvgFill(vg)
    end

    -- 外框金属环
    nvgBeginPath(vg)
    nvgCircle(vg, phX, phY, radius + 4)
    nvgStrokeColor(vg, nvgRGBA(90, 95, 105, 220))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 内框
    nvgBeginPath(vg)
    nvgCircle(vg, phX, phY, radius)
    nvgStrokeColor(vg, nvgRGBA(70, 75, 85, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 破损时红色警告环
    if state == "broken" then
        local warnAlpha = math.floor(120 + 100 * math.sin(gameTime * 5))
        nvgBeginPath(vg)
        nvgCircle(vg, phX, phY, radius + 6)
        nvgStrokeColor(vg, nvgRGBA(255, 60, 60, warnAlpha))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 绘制水泵设备
function Compartments.DrawWaterPump(vg, x, y, pumpData, gameTime)
    local active = pumpData.active or false
    local pumpW = 30
    local pumpH = 45

    -- 泵体外壳
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - pumpW * 0.5, y - pumpH, pumpW, pumpH, 4)
    nvgFillColor(vg, nvgRGBA(45, 55, 65, 255))
    nvgFill(vg)

    -- 泵体边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - pumpW * 0.5, y - pumpH, pumpW, pumpH, 4)
    nvgStrokeColor(vg, nvgRGBA(70, 80, 95, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 进水管（底部左侧）
    nvgBeginPath(vg)
    nvgRect(vg, x - pumpW * 0.5 - 8, y - 15, 10, 6)
    nvgFillColor(vg, nvgRGBA(55, 65, 75, 255))
    nvgFill(vg)

    -- 出水管（顶部右侧）
    nvgBeginPath(vg)
    nvgRect(vg, x + pumpW * 0.5 - 2, y - pumpH + 5, 10, 6)
    nvgFillColor(vg, nvgRGBA(55, 65, 75, 255))
    nvgFill(vg)

    -- 叶轮（中心圆形）
    local impellerY = y - pumpH * 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, x, impellerY, 8)
    nvgStrokeColor(vg, nvgRGBA(100, 110, 130, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    if active then
        -- 运转动画（旋转叶片）
        local angle = gameTime * 8
        for i = 0, 2 do
            local a = angle + i * math.pi * 2 / 3
            nvgBeginPath(vg)
            nvgMoveTo(vg, x, impellerY)
            nvgLineTo(vg, x + math.cos(a) * 6, impellerY + math.sin(a) * 6)
            nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 运行指示灯（绿色脉冲）
        local greenPulse = math.floor(180 + 60 * math.sin(gameTime * 3))
        nvgBeginPath(vg)
        nvgCircle(vg, x, y - pumpH - 5, 3)
        nvgFillColor(vg, nvgRGBA(50, 255, 100, greenPulse))
        nvgFill(vg)

        -- 排水动画粒子（出水管方向）
        for i = 1, 3 do
            local px = x + pumpW * 0.5 + 8 + ((gameTime * 40 + i * 10) % 20)
            local py = y - pumpH + 8 + math.sin(gameTime * 5 + i) * 2
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, 1.5)
            nvgFillColor(vg, nvgRGBA(80, 180, 255, 150))
            nvgFill(vg)
        end
    else
        -- 静止状态：灰色叶片
        for i = 0, 2 do
            local a = i * math.pi * 2 / 3
            nvgBeginPath(vg)
            nvgMoveTo(vg, x, impellerY)
            nvgLineTo(vg, x + math.cos(a) * 6, impellerY + math.sin(a) * 6)
            nvgStrokeColor(vg, nvgRGBA(80, 85, 95, 150))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 关闭指示灯（暗红）
        nvgBeginPath(vg)
        nvgCircle(vg, x, y - pumpH - 5, 3)
        nvgFillColor(vg, nvgRGBA(100, 40, 40, 120))
        nvgFill(vg)
    end

    -- 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 7)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 150, 180, 180))
    nvgText(vg, x, y + 2, "PUMP", nil)
end

return Compartments
