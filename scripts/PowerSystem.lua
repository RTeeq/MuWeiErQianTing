--- 电力分配系统（kW制，基于反应堆输出）
--- 反应堆输出% × 100 = 总可用kW
--- 各系统按优先级分配，电力不足时从低优先级开始关闭

local Config = require("Config")

local PowerSystem = {}

-- ============================================================
-- 系统顺序（用于遍历和UI）
-- ============================================================
local SYSTEM_KEYS = {
    "engine", "turret", "sonar", "searchlight",
    "oxygen", "lights", "pump", "ballast", "medical"
}

-- ============================================================
-- 创建
-- ============================================================

--- 创建电力分配状态
---@return table
function PowerSystem.Create()
    local cfg = Config.Power

    local state = {
        -- 总发电量（由反应堆输出决定）
        totalGeneration = cfg.kWPerPercent * Config.Reactor.defaultOutput, -- 初始8000kW

        -- 各系统状态
        systems = {},

        -- 优先级顺序（索引=优先级，值=系统key，1=最高优先级）
        priority = {},

        -- 面板状态
        isOpen = false,
        selectedIdx = 1,        -- 当前选中的优先级行

        -- 汇总
        totalConsumption = 0,   -- 当前总消耗
        overloaded = false,     -- 是否过载（消耗>发电）
        warningTimer = 0,
    }

    -- 初始化各系统
    for _, key in ipairs(SYSTEM_KEYS) do
        local sysCfg = cfg.systems[key]
        state.systems[key] = {
            key        = key,
            name       = sysCfg.name,
            icon       = sysCfg.icon,
            color      = sysCfg.color,
            maxPower   = sysCfg.maxPower,   -- 最大消耗kW
            minPower   = sysCfg.minPower,   -- 最低供电kW（不能低于此值，否则系统报废）
            allocated  = sysCfg.maxPower,   -- 当前分配的kW（初始=最大，由优先级自动分配）
            efficiency = 1.0,               -- 运行效率 0~1（allocated / maxPower）
            online     = true,              -- 是否在线（有电力供应）
            severed    = false,             -- 线缆是否被切断（接线系统）
        }
    end

    -- 初始化默认优先级
    for i, key in ipairs(cfg.defaultPriority) do
        state.priority[i] = key
    end

    return state
end

-- ============================================================
-- 核心更新
-- ============================================================

--- 更新电力分配（每帧调用）
--- 基于优先级从高到低分配电力，不足时低优先级系统降效或离线
---@param ps table 电力状态
---@param dt number
---@param reactorOutput number 反应堆当前输出百分比（0~150）
---@param wiringState table|nil 接线状态（哪些线路被切断）
function PowerSystem.Update(ps, dt, reactorOutput, wiringState)
    local cfg = Config.Power

    -- 计算总发电量
    ps.totalGeneration = cfg.kWPerPercent * (reactorOutput or 0)

    -- 按优先级从高到低分配电力
    local remaining = ps.totalGeneration
    ps.totalConsumption = 0

    for _, key in ipairs(ps.priority) do
        local sys = ps.systems[key]
        if not sys then goto continue end

        -- 检查接线是否被切断
        if wiringState and wiringState[key] then
            sys.severed = true
            sys.allocated = 0
            sys.efficiency = 0
            sys.online = false
            goto continue
        else
            sys.severed = false
        end

        -- 分配电力（尽量满足最大需求）
        local demand = sys.maxPower
        local alloc = math.min(demand, remaining)
        alloc = math.max(0, alloc)

        sys.allocated = alloc
        remaining = remaining - alloc
        ps.totalConsumption = ps.totalConsumption + alloc

        -- 计算效率
        if sys.maxPower > 0 then
            sys.efficiency = alloc / sys.maxPower
        else
            sys.efficiency = 1.0
        end

        -- 在线状态（分配>=最低要求才算在线）
        sys.online = alloc >= sys.minPower

        ::continue::
    end

    -- 过载检测
    ps.overloaded = ps.totalConsumption > ps.totalGeneration
    if ps.overloaded then
        ps.warningTimer = ps.warningTimer + dt
    else
        ps.warningTimer = 0
    end
end

-- ============================================================
-- 查询接口
-- ============================================================

--- 获取某系统的运行效率（0~1）
---@param ps table
---@param systemKey string
---@return number
function PowerSystem.GetEfficiency(ps, systemKey)
    local sys = ps.systems[systemKey]
    if sys then return sys.efficiency end
    return 0
end

--- 获取某系统是否在线
---@param ps table
---@param systemKey string
---@return boolean
function PowerSystem.IsOnline(ps, systemKey)
    local sys = ps.systems[systemKey]
    if sys then return sys.online end
    return false
end

--- 获取剩余可用电力（kW）
---@param ps table
---@return number
function PowerSystem.GetRemaining(ps)
    return ps.totalGeneration - ps.totalConsumption
end

--- 获取系统顺序列表（用于渲染）
---@return table
function PowerSystem.GetOrder()
    return SYSTEM_KEYS
end

--- 获取优先级顺序（用于渲染）
---@param ps table
---@return table
function PowerSystem.GetPriority(ps)
    return ps.priority
end

-- ============================================================
-- 优先级操作（工程师专属）
-- ============================================================

--- 将选中项向上移动（提高优先级）
---@param ps table
function PowerSystem.MovePriorityUp(ps)
    local idx = ps.selectedIdx
    if idx <= 1 then return end
    -- 交换
    ps.priority[idx], ps.priority[idx - 1] = ps.priority[idx - 1], ps.priority[idx]
    ps.selectedIdx = idx - 1
end

--- 将选中项向下移动（降低优先级）
---@param ps table
function PowerSystem.MovePriorityDown(ps)
    local idx = ps.selectedIdx
    if idx >= #ps.priority then return end
    -- 交换
    ps.priority[idx], ps.priority[idx + 1] = ps.priority[idx + 1], ps.priority[idx]
    ps.selectedIdx = idx + 1
end

--- 选择上一项
---@param ps table
function PowerSystem.SelectPrev(ps)
    ps.selectedIdx = ps.selectedIdx - 1
    if ps.selectedIdx < 1 then ps.selectedIdx = #ps.priority end
end

--- 选择下一项
---@param ps table
function PowerSystem.SelectNext(ps)
    ps.selectedIdx = ps.selectedIdx + 1
    if ps.selectedIdx > #ps.priority then ps.selectedIdx = 1 end
end

--- 增加选中系统的最大分配（手动调高上限）
---@param ps table
---@param amount number
function PowerSystem.IncreaseSelected(ps, amount)
    local key = ps.priority[ps.selectedIdx]
    if not key then return end
    local sys = ps.systems[key]
    if not sys then return end
    local cfgSys = Config.Power.systems[key]
    if not cfgSys then return end
    sys.maxPower = math.min(cfgSys.maxPower, sys.maxPower + (amount or 100))
end

--- 减少选中系统的最大分配（手动调低上限节省电力）
---@param ps table
---@param amount number
function PowerSystem.DecreaseSelected(ps, amount)
    local key = ps.priority[ps.selectedIdx]
    if not key then return end
    local sys = ps.systems[key]
    if not sys then return end
    local cfgSys = Config.Power.systems[key]
    if not cfgSys then return end
    sys.maxPower = math.max(cfgSys.minPower, sys.maxPower - (amount or 100))
end

--- 切换面板显示
---@param ps table
function PowerSystem.TogglePanel(ps)
    ps.isOpen = not ps.isOpen
end

--- 获取系统配置（静态）
function PowerSystem.GetSystemConfig()
    return Config.Power.systems
end

return PowerSystem
