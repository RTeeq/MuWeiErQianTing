--- 危机事件管理器 - 完整8类危机系统
--- 支持概率触发、链式反应、严重度分级、条件触发
local Config = require("Config")

local CrisisManager = {}

-- 严重度级别索引
local SEVERITY_LEVELS = {"minor", "moderate", "critical"}
local SEVERITY_INDEX = { minor = 1, moderate = 2, critical = 3 }

-- ============================================================
-- 工具函数
-- ============================================================

--- 按权重随机选择严重度
---@param weights number[] 权重数组 {minor, moderate, critical}
---@return string severity
local function RollSeverity(weights)
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    local roll = math.random() * total
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if roll <= acc then
            return SEVERITY_LEVELS[i]
        end
    end
    return "minor"
end

--- 从数组中按严重度取值
---@param arr table 按 {minor, moderate, critical} 排列的值数组
---@param severity string
---@return any
local function GetBySeverity(arr, severity)
    if type(arr) ~= "table" then return arr end
    local idx = SEVERITY_INDEX[severity] or 1
    return arr[idx] or arr[1]
end

--- 随机选择舱室
---@param rooms number[]
---@return number
local function PickRoom(rooms)
    if #rooms == 0 then return 1 end
    return rooms[math.random(1, #rooms)]
end

-- ============================================================
-- 创建危机管理器
-- ============================================================

---@return table
function CrisisManager.Create()
    local cfg = Config.Crisis
    return {
        -- 计时
        gameTime = 0,
        lastCrisisTime = -cfg.minInterval, -- 允许首次触发

        -- 噪音增益追踪
        noiseBoostUntil = 0,        -- 噪音增益结束时间
        noiseBoostType = nil,       -- "sonar" | "speed"

        -- 当前活跃危机列表
        activeCrises = {},          ---@type table[]

        -- 链式反应队列（延迟触发）
        chainQueue = {},            ---@type table[]

        -- 警报状态
        alert = {
            muted = cfg.alert.muteDefault,
            activeAlerts = {},      -- 当前显示的警报 {type, level, text, time}
        },

        -- 统计
        crisisCount = 0,
        chainCount = 0,
    }
end

-- ============================================================
-- 创建单条危机记录
-- ============================================================

---@param crisisType string
---@param roomIndex number
---@param severity string
---@param params table|nil
---@return table
local function CreateCrisisEntry(crisisType, roomIndex, severity, params)
    local typeCfg = Config.Crisis.types[crisisType]
    local repairTime = GetBySeverity(typeCfg.repairTime, severity)

    return {
        type = crisisType,
        roomIndex = roomIndex,
        severity = severity,
        startTime = 0,              -- 已持续时间
        resolved = false,
        resolvedTime = nil,

        -- 修复
        repairProgress = 0,         -- 0~1
        repairSpeed = 1.0 / repairTime,
        isBeingRepaired = false,
        diagnosed = crisisType ~= "equipment_malfunction", -- 设备故障需先诊断
        diagnoseProgress = 0,

        -- 类型专属
        params = params or {},

        -- 火灾蔓延追踪
        spreadTimer = 0,

        -- 怪物入侵攻击计时
        attackTimer = 0,

        -- 有毒气体：受影响舱室列表及浓度
        gasRooms = crisisType == "toxic_gas" and { [roomIndex] = 1.0 } or nil,

        -- 链式反应已触发标记
        chainTriggered = false,
    }
end

-- ============================================================
-- 概率计算
-- ============================================================

--- 计算当前环境下的概率乘数
---@param mgr table 管理器
---@param sub table 潜艇
---@param crisisType string
---@return number multiplier
local function CalcProbabilityMultiplier(mgr, sub, crisisType)
    local cfg = Config.Crisis
    local mult = 1.0

    -- 深度因子
    local maxDepth = Config.Driving.depth.maxDepth
    local depthRatio = (sub.physics and sub.physics.depth or 0) / maxDepth
    if depthRatio > cfg.depthFactor.threshold then
        local excess = (depthRatio - cfg.depthFactor.threshold) / (1.0 - cfg.depthFactor.threshold)
        mult = mult + excess * (cfg.depthFactor.multiplier - 1.0)
    end

    -- 时间因子
    local minutesElapsed = mgr.gameTime / 60
    local timeMult = 1.0 + math.min(minutesElapsed * cfg.timeFactor.perMinute, cfg.timeFactor.cap - 1.0)
    mult = mult * timeMult

    -- 噪音因子
    if mgr.gameTime < mgr.noiseBoostUntil then
        if mgr.noiseBoostType == "sonar" then
            mult = mult * (1.0 + cfg.noiseFactor.sonarPulseBoost)
        elseif mgr.noiseBoostType == "speed" then
            mult = mult * (1.0 + cfg.noiseFactor.highSpeedBoost)
        end
    end

    -- 条件触发加成
    local typeCfg = Config.Crisis.types[crisisType]
    if typeCfg and typeCfg.conditionalBoost then
        local boost = typeCfg.conditionalBoost
        if boost.reactorOutput and sub.reactor then
            if sub.reactor.output > boost.reactorOutput then
                mult = mult * boost.multiplier
            end
        end
        if boost.depthRatio then
            if depthRatio > boost.depthRatio then
                mult = mult * boost.multiplier
            end
        end
    end

    return mult
end

-- ============================================================
-- 主更新
-- ============================================================

---@param mgr table 管理器
---@param sub table 潜艇
---@param dt number
---@param gameTime number
function CrisisManager.Update(mgr, sub, dt, gameTime)
    mgr.gameTime = gameTime

    -- 处理链式反应队列
    CrisisManager.ProcessChainQueue(mgr, sub, gameTime)

    -- 尝试触发新危机
    if gameTime >= Config.Crisis.firstCrisisDelay then
        CrisisManager.TryTriggerCrisis(mgr, sub, dt, gameTime)
    end

    -- 更新各活跃危机效果
    for i = #mgr.activeCrises, 1, -1 do
        local c = mgr.activeCrises[i]
        if not c.resolved then
            c.startTime = c.startTime + dt
            CrisisManager.UpdateCrisis(c, mgr, sub, dt, gameTime)
        end
    end

    -- 清理已解决超过4秒的危机
    for i = #mgr.activeCrises, 1, -1 do
        local c = mgr.activeCrises[i]
        if c.resolved and c.resolvedTime and (gameTime - c.resolvedTime > 4.0) then
            table.remove(mgr.activeCrises, i)
        end
    end

    -- 更新警报
    CrisisManager.UpdateAlerts(mgr, gameTime)
end

-- ============================================================
-- 触发逻辑
-- ============================================================

--- 每帧尝试触发新危机（概率检查）
function CrisisManager.TryTriggerCrisis(mgr, sub, dt, gameTime)
    local cfg = Config.Crisis

    -- 冷却检查
    if (gameTime - mgr.lastCrisisTime) < cfg.minInterval then return end

    -- 活跃数量限制
    local activeCount = 0
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved then activeCount = activeCount + 1 end
    end
    if activeCount >= cfg.maxSimultaneous then return end

    -- 已激活的类型集合（避免重复）
    local activeTypes = {}
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved then activeTypes[c.type] = true end
    end

    -- 遍历所有类型，独立概率检查
    for typeName, typeCfg in pairs(cfg.types) do
        if not activeTypes[typeName] then
            local chance = typeCfg.baseChance * dt
            local mult = CalcProbabilityMultiplier(mgr, sub, typeName)
            chance = chance * mult

            if math.random() < chance then
                CrisisManager.TriggerCrisis(mgr, sub, typeName, gameTime)
                return -- 每帧最多触发一个
            end
        end
    end
end

--- 触发指定类型危机
---@param mgr table
---@param sub table
---@param crisisType string
---@param gameTime number
---@param forceSeverity string|nil 强制严重度（链式反应用）
function CrisisManager.TriggerCrisis(mgr, sub, crisisType, gameTime, forceSeverity)
    local typeCfg = Config.Crisis.types[crisisType]
    if not typeCfg then
        print("[CRISIS] Unknown type: " .. tostring(crisisType))
        return
    end

    -- 确定严重度
    local severity = forceSeverity or RollSeverity(typeCfg.severityWeights)

    -- 选择舱室
    local roomIndex = PickRoom(typeCfg.rooms)

    -- 构建额外参数
    local params = {}

    if crisisType == "breach" then
        params.breachPos = math.random() * 0.6 + 0.2
        -- 实际造成破洞
        local Submarine = require("Submarine")
        local breachSize = GetBySeverity({0.3, 0.5, 0.8}, severity)
        Submarine.CreateBreach(sub, roomIndex, breachSize)

    elseif crisisType == "overheat" then
        params.temperature = sub.reactor and sub.reactor.temperature or 50
        params.blackout = false

    elseif crisisType == "power_failure" then
        params.effect = typeCfg.effects and typeCfg.effects[severity] or "single_system"
        params.affectedRooms = {}
        -- 根据严重度确定受影响范围
        if severity == "minor" then
            params.affectedRooms = { roomIndex }
        elseif severity == "moderate" then
            params.affectedRooms = { roomIndex, math.max(1, roomIndex - 1), math.min(#sub.compartments, roomIndex + 1) }
        else
            for i = 1, #sub.compartments do params.affectedRooms[i] = i end
        end

    elseif crisisType == "fire" then
        params.originRoom = roomIndex
        params.burningRooms = { [roomIndex] = 1.0 } -- room → intensity

    elseif crisisType == "monster_invasion" then
        params.monsterHp = GetBySeverity({30, 60, 100}, severity)
        params.monsterType = severity == "critical" and "worm" or "jellyfish"

    elseif crisisType == "equipment_malfunction" then
        local systems = typeCfg.affectedSystems
        params.affectedSystem = systems[math.random(1, #systems)]
        params.diagnosed = false

    elseif crisisType == "toxic_gas" then
        params.concentration = GetBySeverity({0.3, 0.6, 1.0}, severity)
        params.ventilating = false

    elseif crisisType == "crew_madness" then
        params.effectType = typeCfg.effects and typeCfg.effects[severity] or "slow"
        params.targetPlayerIdx = nil -- 后续由Server分配
    end

    local entry = CreateCrisisEntry(crisisType, roomIndex, severity, params)
    table.insert(mgr.activeCrises, entry)
    mgr.crisisCount = mgr.crisisCount + 1
    mgr.lastCrisisTime = gameTime

    -- 添加警报
    CrisisManager.AddAlert(mgr, crisisType, severity, gameTime)

    print(string.format("[CRISIS] %s (%s) triggered in room %d!", crisisType, severity, roomIndex))
end

-- ============================================================
-- 链式反应
-- ============================================================

--- 检查并排队链式反应
local function CheckChainReaction(mgr, crisis, gameTime)
    if crisis.chainTriggered then return end

    local typeCfg = Config.Crisis.types[crisis.type]
    if not typeCfg or not typeCfg.chainReaction then return end

    local chain = typeCfg.chainReaction
    -- 严重度门槛
    if chain.minSeverity then
        local minIdx = SEVERITY_INDEX[chain.minSeverity] or 1
        local curIdx = SEVERITY_INDEX[crisis.severity] or 1
        if curIdx < minIdx then return end
    end

    -- 概率检查
    if math.random() < chain.chance then
        crisis.chainTriggered = true
        table.insert(mgr.chainQueue, {
            type = chain.type,
            triggerTime = gameTime + 3.0 + math.random() * 5.0, -- 3-8秒延迟
            sourceCrisis = crisis.type,
        })
        mgr.chainCount = mgr.chainCount + 1
        print(string.format("[CRISIS] Chain reaction queued: %s → %s", crisis.type, chain.type))
    else
        crisis.chainTriggered = true -- 检查过了不再触发
    end
end

--- 处理链式反应队列
function CrisisManager.ProcessChainQueue(mgr, sub, gameTime)
    for i = #mgr.chainQueue, 1, -1 do
        local item = mgr.chainQueue[i]
        if gameTime >= item.triggerTime then
            table.remove(mgr.chainQueue, i)
            -- 检查是否已有该类型活跃
            local alreadyActive = false
            for _, c in ipairs(mgr.activeCrises) do
                if not c.resolved and c.type == item.type then
                    alreadyActive = true
                    break
                end
            end
            if not alreadyActive then
                CrisisManager.TriggerCrisis(mgr, sub, item.type, gameTime)
            end
        end
    end
end

-- ============================================================
-- 单个危机更新
-- ============================================================

---@param c table 危机条目
---@param mgr table 管理器
---@param sub table 潜艇
---@param dt number
---@param gameTime number
function CrisisManager.UpdateCrisis(c, mgr, sub, dt, gameTime)
    local sevMult = Config.Crisis.severity[c.severity] and Config.Crisis.severity[c.severity].damageMult or 1.0

    if c.type == "breach" then
        -- 持续进水 + 船体伤害
        local comp = sub.compartments[c.roomIndex]
        if comp then
            local rate = GetBySeverity(Config.Crisis.types.breach.floodRate, c.severity)
            comp.waterLevel = math.min(Config.Game.maxWaterLevel,
                comp.waterLevel + rate * dt / 100)
            sub.hull = math.max(0, sub.hull - GetBySeverity(Config.Crisis.types.breach.hullDamage, c.severity) * dt)
        end
        -- 持续5秒后检查链式反应
        if c.startTime > 5 then CheckChainReaction(mgr, c, gameTime) end

    elseif c.type == "overheat" then
        -- 温度持续上升
        local heatRate = Config.Crisis.types.overheat.heatRate * sevMult
        c.params.temperature = (c.params.temperature or 50) + heatRate * dt
        -- 同步到反应堆
        if sub.reactor then
            sub.reactor.temperature = math.max(sub.reactor.temperature, c.params.temperature)
        end
        -- 温度过高 → 全船停电
        if c.params.temperature >= Config.Crisis.types.overheat.meltdownTemp and not c.params.blackout then
            c.params.blackout = true
            sub.isPowerOn = false
            for _, comp in ipairs(sub.compartments) do comp.lightOn = false end
        end
        if c.startTime > 8 then CheckChainReaction(mgr, c, gameTime) end

    elseif c.type == "power_failure" then
        -- 受影响区域灯光关闭
        if c.params.affectedRooms then
            for _, ri in ipairs(c.params.affectedRooms) do
                local comp = sub.compartments[ri]
                if comp then comp.lightOn = false end
            end
        end
        if c.startTime > 4 then CheckChainReaction(mgr, c, gameTime) end

    elseif c.type == "fire" then
        -- 消耗氧气 + 船体伤害
        local oxyBurn = GetBySeverity(Config.Crisis.types.fire.oxygenBurn, c.severity)
        local hullDmg = GetBySeverity(Config.Crisis.types.fire.hullDamage, c.severity)
        -- 所有燃烧舱室
        local totalRooms = 0
        if c.params.burningRooms then
            for _, intensity in pairs(c.params.burningRooms) do
                totalRooms = totalRooms + intensity
            end
        end
        sub.oxygen = math.max(0, sub.oxygen - oxyBurn * totalRooms * dt)
        sub.hull = math.max(0, sub.hull - hullDmg * totalRooms * dt)

        -- 蔓延逻辑
        c.spreadTimer = c.spreadTimer + dt
        if c.spreadTimer >= Config.Crisis.types.fire.spreadInterval then
            c.spreadTimer = 0
            CrisisManager.SpreadFire(c, sub)
        end
        if c.startTime > 6 then CheckChainReaction(mgr, c, gameTime) end

    elseif c.type == "monster_invasion" then
        -- 定期攻击船员/线缆
        local interval = GetBySeverity(Config.Crisis.types.monster_invasion.attackInterval, c.severity)
        c.attackTimer = c.attackTimer + dt
        if c.attackTimer >= interval then
            c.attackTimer = 0
            CrisisManager.MonsterAttack(c, sub)
        end

    elseif c.type == "equipment_malfunction" then
        -- 设备持续失效（直到修复）
        if c.params.affectedSystem == "lights" then
            local comp = sub.compartments[c.roomIndex]
            if comp then comp.lightOn = false end
        end
        -- 不需要链式反应

    elseif c.type == "toxic_gas" then
        -- 气体蔓延到相邻舱室
        if c.gasRooms then
            local spreadSpeed = Config.Crisis.types.toxic_gas.spreadSpeed
            local newRooms = {}
            for ri, conc in pairs(c.gasRooms) do
                newRooms[ri] = math.min(1.0, conc + 0.01 * dt) -- 浓度缓慢增加
                -- 蔓延到相邻
                if conc > 0.5 then
                    local left = ri - 1
                    local right = ri + 1
                    if left >= 1 and not c.gasRooms[left] then
                        newRooms[left] = spreadSpeed * dt
                    end
                    if right <= #sub.compartments and not c.gasRooms[right] then
                        newRooms[right] = spreadSpeed * dt
                    end
                end
            end
            for ri, conc in pairs(newRooms) do
                c.gasRooms[ri] = math.min(1.0, (c.gasRooms[ri] or 0) + conc)
            end
        end
        if c.startTime > 10 then CheckChainReaction(mgr, c, gameTime) end

    elseif c.type == "crew_madness" then
        -- 效果由Server在玩家逻辑中处理（通过查询activeCrises）
        -- 此处不做额外模拟
    end
end

-- ============================================================
-- 火灾蔓延
-- ============================================================

function CrisisManager.SpreadFire(c, sub)
    if not c.params.burningRooms then return end
    local cfg = Config.Crisis.types.fire

    local newRooms = {}
    for ri, _ in pairs(c.params.burningRooms) do
        -- 检查左右相邻舱
        local neighbors = { ri - 1, ri + 1 }
        for _, nri in ipairs(neighbors) do
            if nri >= 1 and nri <= #sub.compartments and not c.params.burningRooms[nri] then
                if math.random() < cfg.spreadChance then
                    newRooms[nri] = 0.5 -- 新蔓延的火势从50%开始
                    print(string.format("[CRISIS] Fire spread to room %d!", nri))
                end
            end
        end
    end

    for ri, intensity in pairs(newRooms) do
        c.params.burningRooms[ri] = intensity
    end
end

-- ============================================================
-- 怪物入侵攻击
-- ============================================================

function CrisisManager.MonsterAttack(c, sub)
    local cfg = Config.Crisis.types.monster_invasion
    -- 线缆破坏
    if math.random() < cfg.cableDamageChance then
        local Submarine = require("Submarine")
        local intact = {}
        for ci, cable in ipairs(sub.wiring.cables) do
            if cable.intact then intact[#intact + 1] = ci end
        end
        if #intact > 0 then
            local cutIdx = intact[math.random(#intact)]
            Submarine.SeverCable(sub, cutIdx)
            print(string.format("[CRISIS] Monster invasion severed cable #%d", cutIdx))
        end
    end
end

-- ============================================================
-- 修复接口
-- ============================================================

--- 尝试修复危机（角色站在对应舱室时调用）
---@param mgr table
---@param sub table
---@param roomIndex number 玩家所在舱室
---@param dt number
---@param role string|nil 玩家职业
---@return boolean isRepairing
---@return number progress 0~1
---@return boolean justCompleted
function CrisisManager.DoRepair(mgr, sub, roomIndex, dt, role)
    -- 查找该舱室未解决的危机
    local c = nil
    for _, crisis in ipairs(mgr.activeCrises) do
        if not crisis.resolved and crisis.roomIndex == roomIndex then
            c = crisis
            break
        end
    end
    if not c then return false, 0, false end

    -- 设备故障需先诊断
    if c.type == "equipment_malfunction" and not c.diagnosed then
        c.diagnoseProgress = c.diagnoseProgress + (1.0 / Config.Crisis.types.equipment_malfunction.diagnoseTime) * dt
        if c.diagnoseProgress >= 1.0 then
            c.diagnosed = true
            c.diagnoseProgress = 1.0
            print("[CRISIS] Equipment malfunction diagnosed!")
        end
        return true, c.diagnoseProgress * 0.3, false -- 诊断占前30%进度显示
    end

    c.isBeingRepaired = true

    -- 技工加速修复
    local speedMult = 1.0
    if role == "mechanic" then
        speedMult = speedMult * 2.0
    end

    c.repairProgress = math.min(1.0, c.repairProgress + c.repairSpeed * speedMult * dt)

    -- 修复完成
    if c.repairProgress >= 1.0 then
        c.resolved = true
        c.resolvedTime = mgr.gameTime
        c.isBeingRepaired = false
        CrisisManager.OnCrisisResolved(c, sub)
        return true, 1.0, true
    end

    -- 设备故障进度显示偏移（诊断30% + 修复70%）
    local displayProgress = c.repairProgress
    if c.type == "equipment_malfunction" then
        displayProgress = 0.3 + c.repairProgress * 0.7
    end

    return true, displayProgress, false
end

--- 停止修复（松手）
function CrisisManager.StopRepair(mgr, roomIndex)
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved and c.roomIndex == roomIndex then
            c.isBeingRepaired = false
            -- 轻微进度衰减
            c.repairProgress = math.max(0, c.repairProgress - 0.03)
        end
    end
end

-- ============================================================
-- 危机解决处理
-- ============================================================

function CrisisManager.OnCrisisResolved(c, sub)
    local Submarine = require("Submarine")

    if c.type == "breach" then
        Submarine.RepairBreach(sub, c.roomIndex)
        print("[CRISIS] Breach repaired in room " .. c.roomIndex)

    elseif c.type == "overheat" then
        -- 降温：恢复电力
        if sub.reactor then
            sub.reactor.temperature = math.min(sub.reactor.temperature, 40)
        end
        if c.params.blackout then
            sub.isPowerOn = true
            for _, comp in ipairs(sub.compartments) do comp.lightOn = true end
        end
        print("[CRISIS] Reactor cooled down!")

    elseif c.type == "power_failure" then
        -- 恢复受影响区域电力
        if c.params.affectedRooms then
            for _, ri in ipairs(c.params.affectedRooms) do
                local comp = sub.compartments[ri]
                if comp then comp.lightOn = true end
            end
        end
        print("[CRISIS] Power restored!")

    elseif c.type == "fire" then
        -- 所有燃烧舱室灭火
        c.params.burningRooms = {}
        print("[CRISIS] Fire extinguished!")

    elseif c.type == "monster_invasion" then
        print("[CRISIS] Monster driven away!")

    elseif c.type == "equipment_malfunction" then
        -- 恢复设备
        if c.params.affectedSystem == "lights" then
            local comp = sub.compartments[c.roomIndex]
            if comp then comp.lightOn = true end
        end
        print("[CRISIS] Equipment fixed: " .. (c.params.affectedSystem or "unknown"))

    elseif c.type == "toxic_gas" then
        c.gasRooms = {}
        print("[CRISIS] Gas cleared!")

    elseif c.type == "crew_madness" then
        print("[CRISIS] Crew calmed down!")
    end
end

-- ============================================================
-- 警报系统
-- ============================================================

--- 添加警报
function CrisisManager.AddAlert(mgr, crisisType, severity, gameTime)
    local cfg = Config.Crisis.alert
    local level = cfg.levelMap[crisisType] or "notice"

    -- 严重度升级覆盖
    if severity == "critical" and cfg.severityOverride.critical then
        level = cfg.severityOverride.critical
    end

    local typeCfg = Config.Crisis.types[crisisType]
    local text = typeCfg and typeCfg.name or crisisType
    local sevLabel = Config.Crisis.severity[severity] and Config.Crisis.severity[severity].label or ""

    table.insert(mgr.alert.activeAlerts, {
        type = crisisType,
        level = level,
        text = text .. " - " .. sevLabel,
        time = gameTime,
        duration = 5.0, -- 警报显示5秒
    })
end

--- 更新警报（清除过期）
function CrisisManager.UpdateAlerts(mgr, gameTime)
    for i = #mgr.alert.activeAlerts, 1, -1 do
        local alert = mgr.alert.activeAlerts[i]
        if gameTime - alert.time > alert.duration then
            table.remove(mgr.alert.activeAlerts, i)
        end
    end
end

--- 切换静音
function CrisisManager.ToggleMute(mgr)
    mgr.alert.muted = not mgr.alert.muted
end

-- ============================================================
-- 噪音增益接口（由Server调用）
-- ============================================================

--- 声呐脉冲触发噪音增益
function CrisisManager.OnSonarPulse(mgr)
    mgr.noiseBoostUntil = mgr.gameTime + Config.Crisis.noiseFactor.boostDuration
    mgr.noiseBoostType = "sonar"
end

--- 高速航行触发噪音增益
function CrisisManager.OnHighSpeed(mgr)
    mgr.noiseBoostUntil = mgr.gameTime + Config.Crisis.noiseFactor.boostDuration
    mgr.noiseBoostType = "speed"
end

--- 怪物目击触发恐慌检查
function CrisisManager.OnMonsterSight(mgr, sub, gameTime)
    local cfg = Config.Crisis.types.crew_madness
    if cfg and cfg.triggerOnMonsterSight then
        -- 额外概率检查
        if math.random() < 0.15 then
            CrisisManager.TriggerCrisis(mgr, sub, "crew_madness", gameTime)
        end
    end
end

-- ============================================================
-- 查询接口
-- ============================================================

--- 获取活跃危机列表
---@param mgr table
---@return table[]
function CrisisManager.GetActiveCrises(mgr)
    local result = {}
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved then
            table.insert(result, c)
        end
    end
    return result
end

--- 获取指定舱室的危机
---@param mgr table
---@param roomIndex number
---@return table|nil
function CrisisManager.GetCrisisInRoom(mgr, roomIndex)
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved and c.roomIndex == roomIndex then
            return c
        end
    end
    return nil
end

--- 获取所有受毒气影响的舱室及浓度
---@param mgr table
---@return table<number, number> roomIndex → concentration
function CrisisManager.GetGasRooms(mgr)
    local result = {}
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved and c.type == "toxic_gas" and c.gasRooms then
            for ri, conc in pairs(c.gasRooms) do
                result[ri] = math.max(result[ri] or 0, conc)
            end
        end
    end
    return result
end

--- 获取所有燃烧中的舱室
---@param mgr table
---@return table<number, number> roomIndex → intensity
function CrisisManager.GetFireRooms(mgr)
    local result = {}
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved and c.type == "fire" and c.params.burningRooms then
            for ri, intensity in pairs(c.params.burningRooms) do
                result[ri] = math.max(result[ri] or 0, intensity)
            end
        end
    end
    return result
end

--- 获取受恐慌影响的信息（供Server施加效果）
---@param mgr table
---@return table|nil {effectType, severity}
function CrisisManager.GetMadnessEffect(mgr)
    for _, c in ipairs(mgr.activeCrises) do
        if not c.resolved and c.type == "crew_madness" then
            return {
                effectType = c.params.effectType,
                severity = c.severity,
                roomIndex = c.roomIndex,
            }
        end
    end
    return nil
end

--- 手动触发（用于测试）
function CrisisManager.TriggerTest(mgr, sub, crisisType, gameTime, severity)
    CrisisManager.TriggerCrisis(mgr, sub, crisisType, gameTime, severity)
end

--- 随机触发一个（兼容旧接口）
function CrisisManager.TriggerRandomCrisis(mgr, sub, gameTime)
    local typeNames = {}
    for name, _ in pairs(Config.Crisis.types) do
        typeNames[#typeNames + 1] = name
    end
    if #typeNames > 0 then
        local chosen = typeNames[math.random(1, #typeNames)]
        CrisisManager.TriggerCrisis(mgr, sub, chosen, gameTime)
    end
end

return CrisisManager
