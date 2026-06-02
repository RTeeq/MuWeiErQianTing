--- 声望系统
--- 每个前哨站独立声望，影响商品价格、任务等级、NPC态度
--- 声望范围：-100（敌对）到 +100（崇拜）
local ReputationSystem = {}

-- ============================================================
-- 声望等级
-- ============================================================
ReputationSystem.LEVELS = {
    { min = -100, max = -60, id = "hostile",   name = "敌对",   color = {200, 50, 50} },
    { min = -60,  max = -20, id = "unfriendly", name = "不友好", color = {200, 120, 50} },
    { min = -20,  max = 20,  id = "neutral",   name = "中立",   color = {180, 180, 100} },
    { min = 20,   max = 60,  id = "friendly",  name = "友好",   color = {100, 200, 100} },
    { min = 60,   max = 100, id = "respected", name = "尊敬",   color = {100, 180, 240} },
}

-- ============================================================
-- 声望变化事件
-- ============================================================
ReputationSystem.EVENTS = {
    complete_mission  = { change = 10,  desc = "完成任务" },
    trade_buy         = { change = 1,   desc = "交易（购买）" },
    trade_sell        = { change = 1,   desc = "交易（出售）" },
    help_defend       = { change = 15,  desc = "帮助防御" },
    repair_service    = { change = 2,   desc = "使用修理服务" },

    attack_outpost    = { change = -30, desc = "攻击前哨站" },
    steal_item        = { change = -20, desc = "偷窃" },
    refuse_pay        = { change = -10, desc = "拒绝付款" },
    smuggle_caught    = { change = -25, desc = "走私被抓" },
    abandon_mission   = { change = -5,  desc = "放弃任务" },
}

-- ============================================================
-- 状态创建
-- ============================================================

--- 创建声望系统状态
---@return table repState
function ReputationSystem.Create()
    return {
        -- 每个前哨站的声望值 {[outpostId] = number}
        stations = {},

        -- 全局声望（影响新发现的站点初始值）
        global = 0,

        -- 声望历史记录（最近10条）
        history = {},
    }
end

-- ============================================================
-- 核心接口
-- ============================================================

--- 获取指定前哨站的声望值
---@param repState table 声望状态
---@param outpostId string 前哨站ID
---@return number reputation 声望值 (-100 ~ 100)
function ReputationSystem.Get(repState, outpostId)
    return repState.stations[outpostId] or repState.global
end

--- 修改声望
---@param repState table 声望状态
---@param outpostId string 前哨站ID
---@param eventId string 事件ID
---@return number newValue 新声望值
---@return string message 变化描述
function ReputationSystem.Change(repState, outpostId, eventId)
    local event = ReputationSystem.EVENTS[eventId]
    if not event then return ReputationSystem.Get(repState, outpostId), "" end

    local current = repState.stations[outpostId] or repState.global
    local newValue = math.max(-100, math.min(100, current + event.change))
    repState.stations[outpostId] = newValue

    -- 同时小幅影响全局声望
    repState.global = math.max(-100, math.min(100, repState.global + event.change * 0.1))

    -- 记录历史
    local record = {
        outpostId = outpostId,
        event = eventId,
        change = event.change,
        desc = event.desc,
        newValue = newValue,
    }
    table.insert(repState.history, 1, record)
    if #repState.history > 10 then
        table.remove(repState.history)
    end

    local sign = event.change > 0 and "+" or ""
    local msg = string.format("声望%s%d（%s）", sign, event.change, event.desc)
    return newValue, msg
end

--- 直接设置声望（用于特殊事件）
---@param repState table 声望状态
---@param outpostId string 前哨站ID
---@param value number 新声望值
function ReputationSystem.Set(repState, outpostId, value)
    repState.stations[outpostId] = math.max(-100, math.min(100, value))
end

-- ============================================================
-- 查询接口
-- ============================================================

--- 获取声望等级信息
---@param reputation number 声望值
---@return table levelInfo {id, name, color}
function ReputationSystem.GetLevel(reputation)
    for _, level in ipairs(ReputationSystem.LEVELS) do
        if reputation >= level.min and reputation <= level.max then
            return level
        end
    end
    return ReputationSystem.LEVELS[3]  -- 默认中立
end

--- 检查是否允许停靠
---@param reputation number 声望值
---@return boolean canDock
---@return string|nil reason
function ReputationSystem.CanDock(reputation)
    if reputation <= -60 then
        return false, "声望过低，被拒绝停靠！"
    end
    return true, nil
end

--- 检查是否会被攻击
---@param reputation number 声望值
---@return boolean willAttack
function ReputationSystem.WillAttack(reputation)
    return reputation <= -80
end

--- 获取NPC态度文本
---@param reputation number 声望值
---@return string attitude
function ReputationSystem.GetAttitude(reputation)
    if reputation >= 60 then
        return "热情欢迎"
    elseif reputation >= 20 then
        return "友善对待"
    elseif reputation >= -20 then
        return "公事公办"
    elseif reputation >= -60 then
        return "态度冷淡"
    else
        return "充满敌意"
    end
end

--- 获取任务等级限制
---@param reputation number 声望值
---@return number maxTier 可接取的最高任务等级(1~3)
function ReputationSystem.GetMaxMissionTier(reputation)
    if reputation >= 60 then return 3 end
    if reputation >= 20 then return 2 end
    return 1
end

--- 获取价格倍率（购买）
---@param reputation number 声望值
---@return number multiplier
function ReputationSystem.GetBuyPriceMultiplier(reputation)
    -- -100 → 1.5x, 0 → 1.0x, 100 → 0.7x
    return math.max(0.5, math.min(1.5, 1.0 - (reputation / 100) * 0.3))
end

--- 获取价格倍率（出售）
---@param reputation number 声望值
---@return number multiplier
function ReputationSystem.GetSellPriceMultiplier(reputation)
    -- -100 → 0.5x, 0 → 1.0x, 100 → 1.3x
    return math.max(0.5, math.min(1.5, 1.0 + (reputation / 100) * 0.3))
end

return ReputationSystem
