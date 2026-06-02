--- 潜艇状态数据模型
local Config = require("Config")

local Submarine = {}

--- 初始化潜艇状态
function Submarine.Init()
    local sub = {
        -- 全局状态
        oxygen = Config.Game.maxOxygen,
        hull   = Config.Game.maxHull,
        power  = Config.Game.maxPower,
        isPowerOn = true,

        -- 舱室数据（运行时计算位置）
        compartments = {},

        -- 破洞列表
        breaches = {},

        -- 时间累计
        time = 0,
    }

    -- 初始化每个舱室
    local xOffset = 0
    for i, cfg in ipairs(Config.Sub.compartments) do
        sub.compartments[i] = {
            id         = cfg.id,
            name       = cfg.name,
            width      = cfg.width,
            x          = xOffset,   -- 左边界相对潜艇内部起点
            equipment  = cfg.equipment,
            waterLevel = 0,         -- 0~1 水位比例
            lightOn    = true,      -- 灯光开关
            hasBreach  = false,     -- 是否有破洞
            breachSize = 0,         -- 破洞大小 0~1
            pressure   = Config.Pressure.standard,  -- 气压 0~100%
        }
        xOffset = xOffset + cfg.width
    end

    -- 初始化门状态
    sub.doors = {}
    for i, doorCfg in ipairs(Config.Sub.doors) do
        sub.doors[i] = {
            id       = doorCfg.id,
            type     = doorCfg.type,         -- normal/safety/airlock
            state    = "closed",             -- closed/opening/open/closing
            locked   = false,                -- 是否锁死
            progress = 0,                    -- 开关动画进度 0~1
            balancing= false,                -- 是否正在气压平衡
            balanceProgress = 0,             -- 气压平衡进度 0~1
        }
    end

    -- 初始化维修舱口
    sub.hatches = {}
    for i, hatchCfg in ipairs(Config.Sub.hatches) do
        sub.hatches[i] = {
            id       = hatchCfg.id,
            room     = hatchCfg.room,
            position = hatchCfg.position,    -- ceiling/floor
            state    = "closed",             -- closed/opening/open
            progress = 0,
        }
    end

    -- 初始化舷窗
    sub.portholes = {}
    for i, phCfg in ipairs(Config.Sub.portholes) do
        sub.portholes[i] = {
            room     = phCfg.room,
            xOffset  = phCfg.xOffset,        -- 在舱室内的X比例位置
            state    = "normal",             -- normal/covered/broken
            coverClosed = false,             -- 舷窗盖是否关闭
        }
    end

    -- 初始化水泵
    sub.pumps = {}
    for i, roomIdx in ipairs(Config.WaterPump.rooms) do
        sub.pumps[i] = {
            room   = roomIdx,
            active = false,                  -- 是否运行中
        }
    end

    -- ========================================================
    -- 反应堆状态
    -- ========================================================
    sub.reactor = {
        state       = "running",    -- off/starting/running/shutdown/meltdown
        output      = Config.Reactor.defaultOutput,  -- 当前输出（0~150%）
        temperature = 20,           -- 当前温度（0~100%）
        cooldownTimer = 0,          -- 冷却按钮冷却倒计时
        startupTimer = 0,           -- 启动预热倒计时
        shutdownTimer = 0,          -- 关机倒计时
        shutdownHoldProgress = 0,   -- 长按关机进度（0~1）
        meltdownTimer = 0,          -- 熔毁倒计时（30秒）
        meltdownActive = false,     -- 是否进入熔毁倒计时
        panelOpen   = false,        -- 反应堆面板是否打开
    }

    -- ========================================================
    -- 接线系统状态
    -- ========================================================
    sub.wiring = {
        cables = {},                -- 线缆状态列表
        junctionBoxes = {},         -- 接线盒状态
        severedSystems = {},        -- 被切断供电的系统列表（key→true）
    }

    -- 初始化线缆
    for i, cableCfg in ipairs(Config.Wiring.defaultCables) do
        sub.wiring.cables[i] = {
            from     = cableCfg.from,
            to       = cableCfg.to,
            system   = cableCfg.system,
            intact   = true,            -- 是否完好
            repairing= false,           -- 是否正在修复
            repairProgress = 0,         -- 修复进度 0~1
        }
    end

    -- 初始化接线盒
    for i, jbCfg in ipairs(Config.Wiring.junctionBoxes) do
        sub.wiring.junctionBoxes[i] = {
            id       = jbCfg.id,
            room     = jbCfg.room,
            xOffset  = jbCfg.xOffset,
            sparking = false,           -- 是否在冒火花（有断线）
            sparkTimer = 0,
        }
    end

    -- ========================================================
    -- 驾驶系统状态
    -- ========================================================
    sub.driving = {
        helmAngle      = 0,         -- 当前舵角（-90~+90）
        helmTarget     = 0,         -- 目标舵角（玩家输入）
        throttleGear   = Config.Driving.throttle.defaultGear,  -- 当前档位索引
        gearSwitching  = false,     -- 是否正在换挡
        gearSwitchTimer= 0,         -- 换挡倒计时
        searchlightOn  = false,     -- 探照灯开关
        searchlightAngle = Config.Searchlight.defaultAngle,   -- 探照灯角度
        searchlightRange = Config.Searchlight.defaultRange,   -- 探照灯范围
    }

    -- ========================================================
    -- 潜艇物理状态
    -- ========================================================
    sub.physics = {
        posX       = 0,             -- 世界X坐标（米）
        posY       = 0,             -- 世界Y坐标（米，水平面第二轴）
        depth      = 2400,          -- 当前深度（米）
        targetDepth= 2400,          -- 目标深度（米）
        heading    = 0,             -- 航向角（度，0=北）
        headingVel = 0,             -- 航向角速度（度/秒）
        speed      = 0,             -- 当前速度（m/s）
        targetSpeed= 0,             -- 目标速度（根据油门档位）
        verticalSpeed = 0,          -- 垂直速度（正=下潜，负=上浮，m/s）
    }

    -- ========================================================
    -- 压载水舱状态
    -- ========================================================
    sub.ballast = {}
    for i, roomIdx in ipairs(Config.Ballast.rooms) do
        sub.ballast[i] = {
            room     = roomIdx,
            level    = 50,              -- 水位 0~100%（50=中性浮力）
            breached = false,           -- 是否破裂
            damaged  = false,           -- 系统是否损坏（紧急排水可能导致）
        }
    end

    -- ========================================================
    -- 声呐状态
    -- ========================================================
    sub.sonar = {
        scanAngle   = 0,            -- 扫描线当前角度（弧度）
        pulsing     = false,        -- 是否正在发射脉冲
        pulseCooldown = 0,          -- 脉冲冷却倒计时
        pulseTimer  = 0,            -- 脉冲结果显示倒计时
        blips       = {},           -- 探测到的回波点 { {x, y, age, type} }
    }

    -- ========================================================
    -- 导航系统状态
    -- ========================================================
    sub.navigation = {
        waypoints   = {},           -- 航点列表 { {x, y, label} }
        currentWP   = 0,            -- 当前目标航点索引（0=无）
        deviation   = 0,            -- 偏航距离（米）
        alarmTimer  = 0,            -- 偏航报警倒计时
        explored    = {},           -- 已探索区域 { {x, y, radius} }
        dangerZones = {},           -- 危险区域 { {x, y, radius, type} }
    }

    return sub
end

--- 更新潜艇状态
---@param sub table
---@param dt number
---@param oxygenEff number|nil 氧气系统效率(0~1)，影响氧气消耗速度，nil=1.0
---@param currentDepth number|nil 当前深度（用于舷窗破裂判定）
function Submarine.Update(sub, dt, oxygenEff, currentDepth)
    sub.time = sub.time + dt
    currentDepth = currentDepth or 0

    -- 氧气消耗（效率越高，消耗越慢；效率为0时消耗加倍）
    local oxyEff = oxygenEff or 1.0
    local drainMult = 2.0 - oxyEff  -- 效率1.0→消耗×1，效率0→消耗×2
    sub.oxygen = math.max(0, sub.oxygen - Config.Game.oxygenDrain * drainMult * dt)

    -- 处理各舱室进水和气压
    for i, comp in ipairs(sub.compartments) do
        if comp.hasBreach then
            comp.waterLevel = math.min(
                Config.Game.maxWaterLevel,
                comp.waterLevel + Config.Game.floodRate * comp.breachSize * dt / 100
            )
            -- 破洞导致气压下降
            comp.pressure = math.max(0, comp.pressure - Config.Pressure.breachDrainRate * comp.breachSize * dt)

            -- 水位影响船体完整度
            if comp.waterLevel > 0.5 then
                sub.hull = math.max(0, sub.hull - 0.5 * dt)
            end
        end
    end

    -- 门状态更新（滑动动画）
    for i, door in ipairs(sub.doors) do
        if door.state == "opening" then
            door.progress = door.progress + dt / Config.Door.openTime
            if door.progress >= 1 then
                door.progress = 1
                door.state = "open"
            end
        elseif door.state == "closing" then
            door.progress = door.progress - dt / Config.Door.closeTime
            if door.progress <= 0 then
                door.progress = 0
                door.state = "closed"
            end
        end

        -- 气压平衡进度
        if door.balancing then
            door.balanceProgress = door.balanceProgress + dt / Config.Door.pressureBalanceTime
            if door.balanceProgress >= 1 then
                door.balanceProgress = 1
                door.balancing = false
                -- 两侧气压平衡
                local leftRoom = i
                local rightRoom = i + 1
                if leftRoom >= 1 and rightRoom <= #sub.compartments then
                    local avg = (sub.compartments[leftRoom].pressure + sub.compartments[rightRoom].pressure) / 2
                    sub.compartments[leftRoom].pressure = avg
                    sub.compartments[rightRoom].pressure = avg
                end
            end
        end

        -- 开门状态下气压和水自然流通
        if door.state == "open" then
            local leftRoom = i
            local rightRoom = i + 1
            if leftRoom >= 1 and rightRoom <= #sub.compartments then
                local compL = sub.compartments[leftRoom]
                local compR = sub.compartments[rightRoom]

                -- 气压自然流通（趋向平衡）
                local pDiff = compL.pressure - compR.pressure
                if math.abs(pDiff) > 1 then
                    local flow = Config.Pressure.doorFlowRate * dt * (pDiff > 0 and 1 or -1)
                    flow = math.min(math.abs(flow), math.abs(pDiff) / 2) * (pDiff > 0 and 1 or -1)
                    compL.pressure = compL.pressure - flow
                    compR.pressure = compR.pressure + flow
                end

                -- 水流通（从高水位流向低水位）
                local wDiff = compL.waterLevel - compR.waterLevel
                if math.abs(wDiff) > 0.01 then
                    local wFlow = Config.Game.floodRate * 0.5 * dt / 100 * (wDiff > 0 and 1 or -1)
                    wFlow = math.min(math.abs(wFlow), math.abs(wDiff) / 2) * (wDiff > 0 and 1 or -1)
                    compL.waterLevel = math.max(0, compL.waterLevel - wFlow)
                    compR.waterLevel = math.min(Config.Game.maxWaterLevel, compR.waterLevel + wFlow)
                end
            end
        end
    end

    -- 舱口动画更新
    for _, hatch in ipairs(sub.hatches) do
        if hatch.state == "opening" then
            hatch.progress = hatch.progress + dt / Config.Door.hatchOpenTime
            if hatch.progress >= 1 then
                hatch.progress = 1
                hatch.state = "open"
            end
        end
    end

    -- 舷窗破裂检测（深度越大，越容易破）
    if currentDepth > Config.Porthole.breakDepth then
        for _, ph in ipairs(sub.portholes) do
            if ph.state == "normal" and not ph.coverClosed then
                if math.random() < Config.Porthole.breakChance * dt then
                    ph.state = "broken"
                    -- 舷窗破裂等同于该舱室产生破洞
                    local comp = sub.compartments[ph.room]
                    if comp then
                        comp.hasBreach = true
                        comp.breachSize = math.min(1, comp.breachSize + 0.6)
                    end
                end
            end
        end
    end

    -- 破裂舷窗持续进水（比普通破洞更快）
    for _, ph in ipairs(sub.portholes) do
        if ph.state == "broken" then
            local comp = sub.compartments[ph.room]
            if comp then
                comp.waterLevel = math.min(
                    Config.Game.maxWaterLevel,
                    comp.waterLevel + Config.Porthole.floodRate * dt / 100
                )
                comp.pressure = math.max(0, comp.pressure - Config.Pressure.breachDrainRate * 0.8 * dt)
            end
        end
    end

    -- 水泵排水
    for _, pump in ipairs(sub.pumps) do
        if pump.active and sub.isPowerOn then
            local comp = sub.compartments[pump.room]
            if comp and comp.waterLevel > 0 then
                comp.waterLevel = math.max(0, comp.waterLevel - Config.WaterPump.pumpRate * dt)
                -- 耗电
                sub.power = math.max(0, sub.power - Config.WaterPump.powerCost * dt)
            end
        end
    end

    -- 电力状态
    if sub.power <= 0 then
        sub.isPowerOn = false
    end
end

--- 在指定舱室制造破洞
---@param sub table
---@param roomIndex number 舱室索引（1开始）
---@param size number 破洞大小 0~1
function Submarine.CreateBreach(sub, roomIndex, size)
    if roomIndex >= 1 and roomIndex <= #sub.compartments then
        local comp = sub.compartments[roomIndex]
        comp.hasBreach = true
        comp.breachSize = math.min(1, comp.breachSize + (size or 0.5))
    end
end

--- 修补破洞
---@param sub table
---@param roomIndex number
function Submarine.RepairBreach(sub, roomIndex)
    if roomIndex >= 1 and roomIndex <= #sub.compartments then
        local comp = sub.compartments[roomIndex]
        comp.hasBreach = false
        comp.breachSize = 0
    end
end

--- 切换电力
function Submarine.TogglePower(sub)
    if sub.power > 0 then
        sub.isPowerOn = not sub.isPowerOn
        if sub.isPowerOn then
            for _, comp in ipairs(sub.compartments) do
                comp.lightOn = true
            end
        else
            for _, comp in ipairs(sub.compartments) do
                comp.lightOn = false
            end
        end
    end
end

--- 获取舱室中心X坐标（相对潜艇内部）
---@param sub table
---@param roomIndex number
---@return number
function Submarine.GetRoomCenterX(sub, roomIndex)
    local comp = sub.compartments[roomIndex]
    if comp then
        return comp.x + comp.width * 0.5
    end
    return 0
end

--- 获取潜艇总宽度
---@param sub table
---@return number
function Submarine.GetTotalWidth(sub)
    local last = sub.compartments[#sub.compartments]
    if last then
        return last.x + last.width
    end
    return Config.Sub.totalWidth
end

-- ============================================================
-- 门交互
-- ============================================================

--- 尝试打开门
---@param sub table
---@param doorIdx number 门索引
---@return boolean success
---@return string|nil reason 失败原因
function Submarine.TryOpenDoor(sub, doorIdx)
    local door = sub.doors[doorIdx]
    if not door then return false, "无效门" end
    if door.locked then return false, "门已锁死" end
    if door.state == "open" or door.state == "opening" then return false, "门已开启" end

    -- 检查气压差
    local leftRoom = doorIdx
    local rightRoom = doorIdx + 1
    local compL = sub.compartments[leftRoom]
    local compR = sub.compartments[rightRoom]
    if compL and compR then
        local pDiff = math.abs(compL.pressure - compR.pressure)
        if pDiff > Config.Door.pressureTolerance then
            return false, "气压差！无法开启"
        end
    end

    door.state = "opening"
    door.progress = 0
    return true, nil
end

--- 关闭门
---@param sub table
---@param doorIdx number
function Submarine.CloseDoor(sub, doorIdx)
    local door = sub.doors[doorIdx]
    if not door then return end
    if door.state == "open" then
        door.state = "closing"
    end
end

--- 锁定/解锁门
---@param sub table
---@param doorIdx number
---@return boolean newLockState
function Submarine.ToggleDoorLock(sub, doorIdx)
    local door = sub.doors[doorIdx]
    if not door then return false end
    -- 只有安全门和气闸门能锁
    local typeInfo = Config.Door.types[door.type]
    if not typeInfo or not typeInfo.canLock then return door.locked end
    door.locked = not door.locked
    -- 锁门时自动关门
    if door.locked and (door.state == "open" or door.state == "opening") then
        door.state = "closing"
    end
    return door.locked
end

--- 开始气压平衡
---@param sub table
---@param doorIdx number
function Submarine.StartPressureBalance(sub, doorIdx)
    local door = sub.doors[doorIdx]
    if not door then return end
    if door.locked then return end
    door.balancing = true
    door.balanceProgress = 0
end

--- 停止气压平衡（松手）
---@param sub table
---@param doorIdx number
function Submarine.StopPressureBalance(sub, doorIdx)
    local door = sub.doors[doorIdx]
    if not door then return end
    door.balancing = false
    -- 不重置进度，允许分多次完成
end

--- 切换水泵
---@param sub table
---@param roomIdx number
---@return boolean|nil newState
function Submarine.TogglePump(sub, roomIdx)
    for _, pump in ipairs(sub.pumps) do
        if pump.room == roomIdx then
            pump.active = not pump.active
            return pump.active
        end
    end
    return nil
end

--- 切换舷窗盖
---@param sub table
---@param portholeIdx number
function Submarine.TogglePortholeCover(sub, portholeIdx)
    local ph = sub.portholes[portholeIdx]
    if not ph then return end
    if ph.state == "broken" then return end  -- 破裂的无法操作
    ph.coverClosed = not ph.coverClosed
    if ph.coverClosed then
        ph.state = "covered"
    else
        ph.state = "normal"
    end
end

--- 获取玩家最近的门索引（基于X位置）
---@param sub table
---@param playerX number 玩家X坐标
---@param range number 交互范围
---@return number|nil doorIdx
function Submarine.GetNearbyDoor(sub, playerX, range)
    local accX = 0
    for i, cfg in ipairs(Config.Sub.compartments) do
        accX = accX + cfg.width
        -- 门在舱室右边界
        if i < #Config.Sub.compartments then
            local doorX = accX  -- 门的X位置
            if math.abs(playerX - doorX) <= range then
                return i
            end
        end
    end
    return nil
end

--- 获取玩家最近的舷窗索引
---@param sub table
---@param playerX number
---@param playerRoom number
---@param range number
---@return number|nil portholeIdx
function Submarine.GetNearbyPorthole(sub, playerX, playerRoom, range)
    for i, ph in ipairs(sub.portholes) do
        if ph.room == playerRoom then
            local comp = sub.compartments[ph.room]
            if comp then
                local phX = comp.x + comp.width * ph.xOffset
                if math.abs(playerX - phX) <= range then
                    return i
                end
            end
        end
    end
    return nil
end

--- 获取玩家最近的水泵（如果在水泵舱室内）
---@param sub table
---@param playerRoom number
---@return number|nil pumpIdx
function Submarine.GetNearbyPump(sub, playerRoom)
    for i, pump in ipairs(sub.pumps) do
        if pump.room == playerRoom then
            return i
        end
    end
    return nil
end

-- ============================================================
-- 驾驶系统更新
-- ============================================================

--- 更新驾驶系统（舵盘、油门、换挡）
---@param sub table
---@param dt number
---@param helmInput number 舵盘输入角度（-90~+90，0=回中）
function Submarine.UpdateDriving(sub, dt, helmInput)
    local drv = sub.driving
    local cfg = Config.Driving

    -- 舵盘：平滑跟随输入（如果有输入），否则自动回中
    if helmInput and helmInput ~= 0 then
        drv.helmTarget = math.max(-cfg.helm.maxAngle, math.min(cfg.helm.maxAngle, helmInput))
    else
        drv.helmTarget = 0
    end

    -- 舵角平滑移动到目标
    local angleDiff = drv.helmTarget - drv.helmAngle
    if math.abs(angleDiff) > 0.5 then
        local moveSpeed = cfg.helm.returnSpeed * dt
        if math.abs(angleDiff) < moveSpeed then
            drv.helmAngle = drv.helmTarget
        else
            drv.helmAngle = drv.helmAngle + moveSpeed * (angleDiff > 0 and 1 or -1)
        end
    end

    -- 换挡倒计时
    if drv.gearSwitching then
        drv.gearSwitchTimer = drv.gearSwitchTimer - dt
        if drv.gearSwitchTimer <= 0 then
            drv.gearSwitching = false
        end
    end

    -- 根据当前档位设置目标速度
    if not drv.gearSwitching then
        local gear = cfg.throttle.gears[drv.throttleGear]
        if gear then
            sub.physics.targetSpeed = gear.speed
        end
    end
end

--- 油门升档
---@param sub table
function Submarine.ThrottleUp(sub)
    local drv = sub.driving
    local cfg = Config.Driving.throttle
    if drv.gearSwitching then return end
    if drv.throttleGear < #cfg.gears then
        drv.throttleGear = drv.throttleGear + 1
        drv.gearSwitching = true
        drv.gearSwitchTimer = cfg.gearSwitchTime
    end
end

--- 油门降档
---@param sub table
function Submarine.ThrottleDown(sub)
    local drv = sub.driving
    local cfg = Config.Driving.throttle
    if drv.gearSwitching then return end
    if drv.throttleGear > 1 then
        drv.throttleGear = drv.throttleGear - 1
        drv.gearSwitching = true
        drv.gearSwitchTimer = cfg.gearSwitchTime
    end
end

--- 设置目标深度
---@param sub table
---@param depth number 目标深度（米）
function Submarine.SetTargetDepth(sub, depth)
    local cfg = Config.Driving.depth
    sub.physics.targetDepth = math.max(cfg.minDepth, math.min(cfg.maxDepth, depth))
end

--- 切换探照灯
---@param sub table
function Submarine.ToggleSearchlight(sub)
    sub.driving.searchlightOn = not sub.driving.searchlightOn
end

-- ============================================================
-- 潜艇物理模拟
-- ============================================================

--- 更新潜艇物理（位置、速度、航向、深度）
---@param sub table
---@param dt number
function Submarine.UpdatePhysics(sub, dt)
    local phys = sub.physics
    local cfg = Config.Physics
    local drvCfg = Config.Driving

    -- 1. 航向更新：舵角→角速度（有惯性延迟）
    local helmAngle = sub.driving.helmAngle
    -- 插值计算转向速率
    local turnRate = 0
    local rates = drvCfg.helm.turnRates
    local absHelm = math.abs(helmAngle)
    for i = 1, #rates - 1 do
        if absHelm >= rates[i].angle and absHelm <= rates[i + 1].angle then
            local t = (absHelm - rates[i].angle) / (rates[i + 1].angle - rates[i].angle)
            turnRate = rates[i].rate + t * (rates[i + 1].rate - rates[i].rate)
            break
        end
    end
    if absHelm >= rates[#rates].angle then
        turnRate = rates[#rates].rate
    end
    if helmAngle < 0 then turnRate = -turnRate end

    -- 惯性延迟：角速度平滑过渡到目标
    local targetHVel = turnRate
    local hvDiff = targetHVel - phys.headingVel
    local inertiaRate = 1.0 / cfg.turnInertia
    phys.headingVel = phys.headingVel + hvDiff * math.min(1, inertiaRate * dt)

    -- 角阻力
    phys.headingVel = phys.headingVel * (1 - cfg.angularDrag * dt)

    -- 更新航向
    phys.heading = phys.heading + phys.headingVel * dt
    -- 归一化到 0~360
    phys.heading = phys.heading % 360
    if phys.heading < 0 then phys.heading = phys.heading + 360 end

    -- 2. 速度更新：油门→加速/减速（有惯性）
    local speedDiff = phys.targetSpeed - phys.speed
    if math.abs(speedDiff) > 0.01 then
        local accelRate
        if math.abs(phys.targetSpeed) > math.abs(phys.speed) then
            -- 加速
            accelRate = cfg.maxSpeed / cfg.accelTime
        else
            -- 减速/惯性滑行
            accelRate = cfg.maxSpeed / cfg.decelTime
        end
        -- 阻力随速度增大
        local dragForce = cfg.dragCoeff * phys.speed * math.abs(phys.speed)
        local netAccel = accelRate * (speedDiff > 0 and 1 or -1) - dragForce
        phys.speed = phys.speed + netAccel * dt
        -- 限速
        phys.speed = math.max(-cfg.maxSpeed * 0.3, math.min(cfg.maxSpeed, phys.speed))
    else
        -- 自然阻力衰减
        phys.speed = phys.speed * (1 - cfg.dragCoeff * dt)
        if math.abs(phys.speed) < 0.01 then phys.speed = 0 end
    end

    -- 3. 位置更新
    local headingRad = math.rad(phys.heading)
    phys.posX = phys.posX + math.sin(headingRad) * phys.speed * dt
    phys.posY = phys.posY + math.cos(headingRad) * phys.speed * dt

    -- 4. 深度更新（基于压载水舱状态）
    local depthDiff = phys.targetDepth - phys.depth
    local dCfg = drvCfg.depth
    if math.abs(depthDiff) > dCfg.tolerance then
        local rate
        if depthDiff > 0 then
            -- 下潜
            rate = dCfg.diveRate / 60.0  -- 米/分 → 米/秒
        else
            -- 上浮
            rate = -dCfg.riseRate / 60.0
        end
        phys.verticalSpeed = rate
    else
        phys.verticalSpeed = 0
    end
    phys.depth = phys.depth + phys.verticalSpeed * dt
    phys.depth = math.max(dCfg.minDepth, math.min(dCfg.maxDepth, phys.depth))
end

-- ============================================================
-- 压载水舱系统
-- ============================================================

--- 更新压载水舱
---@param sub table
---@param dt number
function Submarine.UpdateBallast(sub, dt)
    for _, tank in ipairs(sub.ballast) do
        -- 破裂水舱自动进水
        if tank.breached then
            tank.level = math.min(100, tank.level + Config.Ballast.breachFloodRate * dt)
        end
    end

    -- 压载水总量影响目标深度的维持能力（简化模型）
    -- 总水量越多→越容易下潜；总水量越少→越容易上浮
    local totalBallast = 0
    for _, tank in ipairs(sub.ballast) do
        totalBallast = totalBallast + tank.level
    end
    local avgBallast = totalBallast / math.max(1, #sub.ballast)

    -- 压载偏移深度变化速率：50%=中性，>50%加速下潜，<50%加速上浮
    local ballastBias = (avgBallast - 50) / 50  -- -1 ~ +1
    local biasRate = ballastBias * 0.3  -- 额外 ±0.3 m/s
    sub.physics.depth = sub.physics.depth + biasRate * dt
    sub.physics.depth = math.max(Config.Driving.depth.minDepth, math.min(Config.Driving.depth.maxDepth, sub.physics.depth))
end

--- 压载水舱操作：注水
---@param sub table
---@param tankIdx number
function Submarine.BallastFill(sub, tankIdx, dt)
    local tank = sub.ballast[tankIdx]
    if not tank or tank.damaged then return end
    tank.level = math.min(100, tank.level + Config.Ballast.fillRate * dt)
end

--- 压载水舱操作：排水
---@param sub table
---@param tankIdx number
function Submarine.BallastDrain(sub, tankIdx, dt)
    local tank = sub.ballast[tankIdx]
    if not tank or tank.damaged then return end
    tank.level = math.max(0, tank.level - Config.Ballast.drainRate * dt)
end

--- 压载水舱操作：紧急排水
---@param sub table
---@param tankIdx number
function Submarine.BallastEmergency(sub, tankIdx)
    local tank = sub.ballast[tankIdx]
    if not tank or tank.damaged then return end
    -- 快速排空
    tank.level = 0
    -- 可能损坏系统
    if math.random() < Config.Ballast.emergencyDamageChance then
        tank.damaged = true
    end
end

--- 获取玩家最近的压载水舱
---@param sub table
---@param playerRoom number
---@return number|nil tankIdx
function Submarine.GetNearbyBallast(sub, playerRoom)
    for i, tank in ipairs(sub.ballast) do
        if tank.room == playerRoom then
            return i
        end
    end
    return nil
end

-- ============================================================
-- 声呐系统
-- ============================================================

--- 更新声呐
---@param sub table
---@param dt number
function Submarine.UpdateSonar(sub, dt)
    local sonar = sub.sonar

    -- 扫描线旋转
    sonar.scanAngle = sonar.scanAngle + Config.Sonar.scanSpeed * dt
    if sonar.scanAngle > math.pi * 2 then
        sonar.scanAngle = sonar.scanAngle - math.pi * 2
    end

    -- 脉冲冷却
    if sonar.pulseCooldown > 0 then
        sonar.pulseCooldown = sonar.pulseCooldown - dt
    end

    -- 脉冲结果显示倒计时
    if sonar.pulseTimer > 0 then
        sonar.pulseTimer = sonar.pulseTimer - dt
        if sonar.pulseTimer <= 0 then
            sonar.pulsing = false
        end
    end

    -- 回波点老化
    for i = #sonar.blips, 1, -1 do
        sonar.blips[i].age = sonar.blips[i].age + dt
        if sonar.blips[i].age > Config.Sonar.blipFadeTime then
            table.remove(sonar.blips, i)
        end
    end
end

--- 发射声呐脉冲
---@param sub table
---@param targets table|nil 周围目标列表 { {x, y, type} }
function Submarine.SonarPulse(sub, targets)
    local sonar = sub.sonar
    if sonar.pulseCooldown > 0 then return false end

    sonar.pulsing = true
    sonar.pulseCooldown = Config.Sonar.pulseCooldown
    sonar.pulseTimer = Config.Sonar.pulseDuration

    -- 生成回波（从服务端传入目标列表）
    if targets then
        for _, t in ipairs(targets) do
            local dx = t.x - sub.physics.posX
            local dy = t.y - sub.physics.posY
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= Config.Sonar.pulseRange then
                table.insert(sonar.blips, {
                    x = dx, y = dy, age = 0, type = t.type or "unknown"
                })
            end
        end
    end
    return true
end

-- ============================================================
-- 导航系统
-- ============================================================

--- 更新导航状态
---@param sub table
---@param dt number
function Submarine.UpdateNavigation(sub, dt)
    local nav = sub.navigation
    local phys = sub.physics

    -- 计算偏航距离（到当前航段的垂直距离）
    if nav.currentWP > 0 and nav.currentWP <= #nav.waypoints then
        local wp = nav.waypoints[nav.currentWP]
        local dx = wp.x - phys.posX
        local dy = wp.y - phys.posY
        local distToWP = math.sqrt(dx * dx + dy * dy)

        -- 简化偏航：与目标点连线的横向偏移
        local headingRad = math.rad(phys.heading)
        local toWPAngle = math.atan(dx, dy)  -- atan2(x,y) 因为heading以北为0
        local angleDiff = toWPAngle - headingRad
        nav.deviation = math.abs(math.sin(angleDiff) * distToWP)

        -- 到达航点
        if distToWP < Config.Navigation.waypointRadius then
            nav.currentWP = nav.currentWP + 1
            if nav.currentWP > #nav.waypoints then
                nav.currentWP = 0  -- 路线完成
            end
        end

        -- 偏航报警
        if nav.deviation > Config.Navigation.deviationAlarm then
            nav.alarmTimer = nav.alarmTimer - dt
        else
            nav.alarmTimer = Config.Navigation.alarmInterval
        end
    else
        nav.deviation = 0
        nav.alarmTimer = Config.Navigation.alarmInterval
    end

    -- 更新已探索区域（每隔一段距离记录）
    local lastExplored = nav.explored[#nav.explored]
    if not lastExplored or
        math.sqrt((lastExplored.x - phys.posX)^2 + (lastExplored.y - phys.posY)^2) > 100 then
        table.insert(nav.explored, {x = phys.posX, y = phys.posY, radius = 150})
        -- 限制数量
        if #nav.explored > 200 then
            table.remove(nav.explored, 1)
        end
    end
end

--- 添加航点
---@param sub table
---@param x number 世界X坐标
---@param y number 世界Y坐标
---@param label string|nil
function Submarine.AddWaypoint(sub, x, y, label)
    local nav = sub.navigation
    if #nav.waypoints >= Config.Navigation.maxWaypoints then return false end
    table.insert(nav.waypoints, {x = x, y = y, label = label or ""})
    if nav.currentWP == 0 then
        nav.currentWP = 1
    end
    return true
end

--- 清除航点
---@param sub table
function Submarine.ClearWaypoints(sub)
    sub.navigation.waypoints = {}
    sub.navigation.currentWP = 0
    sub.navigation.deviation = 0
end

-- ============================================================
-- 碰撞处理
-- ============================================================

--- 处理潜艇碰撞（由Server检测后调用）
---@param sub table
---@param impactSpeed number 碰撞速度（m/s）
---@param isFrontal boolean 是否正面碰撞
---@return number damage 造成的伤害
function Submarine.HandleCollision(sub, impactSpeed, isFrontal)
    local cfg = Config.Physics.collision
    if impactSpeed < cfg.minDamageSpeed then return 0 end

    local mult = isFrontal and cfg.frontalMult or cfg.sideMult
    local damage = (impactSpeed - cfg.minDamageSpeed) * cfg.damagePerSpeed * mult
    sub.hull = math.max(0, sub.hull - damage)

    -- 减速
    sub.physics.speed = sub.physics.speed * 0.3

    return damage
end

-- ============================================================
-- 反应堆系统
-- ============================================================

--- 更新反应堆（温度、状态转换、熔毁倒计时）
---@param sub table
---@param dt number
---@return string|nil event 事件（"meltdown"=爆炸）
function Submarine.UpdateReactor(sub, dt)
    local reactor = sub.reactor
    local cfg = Config.Reactor

    -- 冷却按钮冷却倒计时
    if reactor.cooldownTimer > 0 then
        reactor.cooldownTimer = reactor.cooldownTimer - dt
    end

    -- 状态机
    if reactor.state == "off" then
        -- 停机：温度自然冷却
        reactor.temperature = math.max(0, reactor.temperature - cfg.cooldownRate / 10 * dt)
        reactor.output = 0
        return nil

    elseif reactor.state == "starting" then
        -- 启动中：倒计时
        reactor.startupTimer = reactor.startupTimer - dt
        if reactor.startupTimer <= 0 then
            reactor.state = "running"
            reactor.startupTimer = 0
        end
        return nil

    elseif reactor.state == "shutdown" then
        -- 关机中：倒计时
        reactor.shutdownTimer = reactor.shutdownTimer - dt
        reactor.output = reactor.output * 0.9  -- 输出快速衰减
        reactor.temperature = math.max(0, reactor.temperature - cfg.cooldownRate / 10 * dt * 2)
        if reactor.shutdownTimer <= 0 then
            reactor.state = "off"
            reactor.output = 0
            reactor.meltdownActive = false
            reactor.meltdownTimer = 0
        end
        return nil

    elseif reactor.state == "running" then
        -- 运行中：根据输出计算升温
        local heatRate = 0
        local rates = cfg.heatRates
        local output = reactor.output
        -- 插值计算升温速率
        for i = 1, #rates - 1 do
            if output >= rates[i].output and output <= rates[i + 1].output then
                local t = (output - rates[i].output) / (rates[i + 1].output - rates[i].output)
                heatRate = rates[i].rate + t * (rates[i + 1].rate - rates[i].rate)
                break
            end
        end
        if output >= rates[#rates].output then
            heatRate = rates[#rates].rate
        end

        -- 自然冷却（始终有，但低于升温时温度还是上升）
        local netHeatRate = heatRate - cfg.cooldownRate
        -- 转换为每秒（配置是每10秒）
        reactor.temperature = reactor.temperature + (netHeatRate / 10.0) * dt
        reactor.temperature = math.max(0, math.min(cfg.maxTemp, reactor.temperature))

        -- 检查熔毁
        if reactor.temperature >= cfg.meltdownTemp then
            if not reactor.meltdownActive then
                reactor.meltdownActive = true
                reactor.meltdownTimer = cfg.meltdownCountdown
            end
        else
            -- 温度降回安全范围，取消熔毁倒计时
            if reactor.meltdownActive then
                reactor.meltdownActive = false
                reactor.meltdownTimer = 0
            end
        end

        -- 熔毁倒计时
        if reactor.meltdownActive then
            reactor.meltdownTimer = reactor.meltdownTimer - dt
            if reactor.meltdownTimer <= 0 then
                reactor.state = "meltdown"
                return "meltdown"  -- 游戏结束信号
            end
        end

        return nil

    elseif reactor.state == "meltdown" then
        -- 已熔毁，不再更新
        return "meltdown"
    end

    return nil
end

--- 调整反应堆输出
---@param sub table
---@param delta number 增量（正=提高输出，负=降低输出）
function Submarine.ReactorAdjustOutput(sub, delta)
    local reactor = sub.reactor
    if reactor.state ~= "running" then return end
    local cfg = Config.Reactor
    reactor.output = math.max(cfg.minOutput, math.min(cfg.maxOutput, reactor.output + delta))
end

--- 冷却脉冲（按下冷却按钮）
---@param sub table
---@return boolean success
function Submarine.ReactorCoolPulse(sub)
    local reactor = sub.reactor
    if reactor.state ~= "running" then return false end
    if reactor.cooldownTimer > 0 then return false end

    local cfg = Config.Reactor
    reactor.temperature = math.max(0, reactor.temperature - cfg.coolPulseEffect)
    reactor.cooldownTimer = cfg.coolPulseCooldown
    return true
end

--- 紧急关机（需要长按，调用此方法推进进度）
---@param sub table
---@param dt number
---@return boolean completed 是否完成关机
function Submarine.ReactorShutdownHold(sub, dt)
    local reactor = sub.reactor
    if reactor.state ~= "running" then return false end

    local cfg = Config.Reactor
    reactor.shutdownHoldProgress = reactor.shutdownHoldProgress + dt / cfg.shutdownHoldTime
    if reactor.shutdownHoldProgress >= 1 then
        reactor.shutdownHoldProgress = 0
        reactor.state = "shutdown"
        reactor.shutdownTimer = cfg.shutdownTime
        return true
    end
    return false
end

--- 取消长按关机（松手）
---@param sub table
function Submarine.ReactorShutdownRelease(sub)
    sub.reactor.shutdownHoldProgress = 0
end

--- 启动反应堆
---@param sub table
---@return boolean success
function Submarine.ReactorStartup(sub)
    local reactor = sub.reactor
    if reactor.state ~= "off" then return false end

    reactor.state = "starting"
    reactor.startupTimer = Config.Reactor.startupTime
    reactor.output = Config.Reactor.defaultOutput
    return true
end

--- 切换反应堆面板
---@param sub table
function Submarine.ToggleReactorPanel(sub)
    sub.reactor.panelOpen = not sub.reactor.panelOpen
end

-- ============================================================
-- 接线系统
-- ============================================================

--- 更新接线系统（火花动画、修复进度）
---@param sub table
---@param dt number
function Submarine.UpdateWiring(sub, dt)
    local wiring = sub.wiring

    -- 重新计算被切断的系统
    wiring.severedSystems = {}
    for _, cable in ipairs(wiring.cables) do
        if not cable.intact then
            -- 该线缆对应的系统供电被切断
            wiring.severedSystems[cable.system] = true
        end

        -- 修复进度
        if cable.repairing then
            cable.repairProgress = cable.repairProgress + dt / Config.Wiring.repairTime
            if cable.repairProgress >= 1 then
                cable.intact = true
                cable.repairing = false
                cable.repairProgress = 0
            end
        end
    end

    -- 接线盒火花动画
    for _, jbox in ipairs(wiring.junctionBoxes) do
        -- 检查是否有关联的断线
        local hasSevered = false
        for _, cable in ipairs(wiring.cables) do
            if not cable.intact and (cable.from == jbox.id or cable.to == jbox.id) then
                hasSevered = true
                break
            end
        end
        jbox.sparking = hasSevered
        if hasSevered then
            jbox.sparkTimer = jbox.sparkTimer + dt
        else
            jbox.sparkTimer = 0
        end
    end
end

--- 切断一条线缆（怪物攻击时调用）
---@param sub table
---@param cableIdx number|nil 指定索引，nil则随机
---@return boolean success
function Submarine.SeverCable(sub, cableIdx)
    local wiring = sub.wiring

    -- 检查同时被切断数是否超限
    local severedCount = 0
    for _, cable in ipairs(wiring.cables) do
        if not cable.intact then severedCount = severedCount + 1 end
    end
    if severedCount >= Config.Wiring.maxSimultaneousCuts then return false end

    if cableIdx then
        -- 指定索引
        local cable = wiring.cables[cableIdx]
        if cable and cable.intact then
            cable.intact = false
            cable.repairing = false
            cable.repairProgress = 0
            return true
        end
    else
        -- 随机选择一条完好的线缆
        local intact = {}
        for i, cable in ipairs(wiring.cables) do
            if cable.intact then table.insert(intact, i) end
        end
        if #intact > 0 then
            local idx = intact[math.random(#intact)]
            wiring.cables[idx].intact = false
            wiring.cables[idx].repairing = false
            wiring.cables[idx].repairProgress = 0
            return true
        end
    end
    return false
end

--- 开始修复线缆（玩家在接线盒旁操作）
---@param sub table
---@param cableIdx number
function Submarine.StartCableRepair(sub, cableIdx)
    local cable = sub.wiring.cables[cableIdx]
    if not cable then return end
    if cable.intact then return end  -- 已经完好
    cable.repairing = true
    cable.repairProgress = 0
end

--- 停止修复线缆（松手）
---@param sub table
---@param cableIdx number
function Submarine.StopCableRepair(sub, cableIdx)
    local cable = sub.wiring.cables[cableIdx]
    if not cable then return end
    cable.repairing = false
    -- 保留进度，允许分多次修
end

--- 获取玩家最近的接线盒
---@param sub table
---@param playerRoom number
---@param playerX number
---@param range number
---@return number|nil jboxIdx
function Submarine.GetNearbyJunctionBox(sub, playerRoom, playerX, range)
    for i, jbox in ipairs(sub.wiring.junctionBoxes) do
        if jbox.room == playerRoom then
            local comp = sub.compartments[jbox.room]
            if comp then
                local jbX = comp.x + comp.width * jbox.xOffset
                if math.abs(playerX - jbX) <= range then
                    return i
                end
            end
        end
    end
    return nil
end

--- 获取与接线盒关联的断线索引列表
---@param sub table
---@param jboxIdx number
---@return table severedCableIndices
function Submarine.GetSeveredCablesAtJBox(sub, jboxIdx)
    local jbox = sub.wiring.junctionBoxes[jboxIdx]
    if not jbox then return {} end

    local result = {}
    for i, cable in ipairs(sub.wiring.cables) do
        if not cable.intact and (cable.from == jbox.id or cable.to == jbox.id) then
            table.insert(result, i)
        end
    end
    return result
end

return Submarine
