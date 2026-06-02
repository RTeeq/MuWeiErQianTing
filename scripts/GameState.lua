--- 游戏场景状态管理
--- 管理港口/深海两个场景的切换和持久化数据
local GameState = {}

-- 场景枚举
GameState.SCENE_PORT = "port"
GameState.SCENE_DEEP_SEA = "deep_sea"

--- 创建游戏状态
function GameState.Create()
    local state = {
        -- 当前场景
        currentScene = GameState.SCENE_PORT,

        -- 持久化玩家数据（跨场景保持）
        gold = 500,                  -- 初始金币
        totalMissions = 0,           -- 已完成任务总数
        reputation = 0,              -- 声望值

        -- 潜艇升级等级（影响深海中的数值）
        upgrades = {
            hull = 1,       -- 船体等级 (1~5): 每级+20%最大船体
            engine = 1,     -- 引擎等级 (1~5): 每级+15%移速
            oxygen = 1,     -- 氧气等级 (1~5): 每级-20%氧耗
            turret = 1,     -- 炮塔等级 (1~5): 每级+25%伤害
            sonar = 1,      -- 声呐等级 (1~5): 每级+20%范围
            armor = 1,      -- 装甲等级 (1~5): 每级-15%受伤
        },

        -- 物品库存（港口中购买/任务奖励，带入深海）
        supplies = {
            ammo_pack = 2,     -- 弹药包
            medkit = 1,        -- 医疗包
            repair_tool = 1,   -- 修复工具
            power_cell = 0,    -- 电力芯
            sonar_boost = 0,   -- 声呐增强
        },

        -- 当前任务（nil表示没接任务）
        ---@type table|nil
        currentMission = nil,

        -- 深海任务进度（返回港口时结算）
        missionProgress = {
            kills = 0,
            depthReached = 0,
            timeElapsed = 0,
            scrapsCollected = 0,
            crisisRepaired = 0,
        },

        -- 场景切换动画
        transition = {
            active = false,
            timer = 0,
            duration = 1.5,   -- 切换动画时长
            targetScene = nil,
        },
    }
    return state
end

--- 获取升级后的潜艇属性
function GameState.GetSubStats(state)
    local u = state.upgrades
    return {
        maxHull = 100 * (1 + (u.hull - 1) * 0.2),       -- 100/120/140/160/180
        maxOxygen = 100 * (1 + (u.oxygen - 1) * 0.15),  -- 100/115/130/145/160
        engineMult = 1.0 + (u.engine - 1) * 0.15,       -- 1.0/1.15/1.3/1.45/1.6
        turretDmgMult = 1.0 + (u.turret - 1) * 0.25,    -- 1.0/1.25/1.5/1.75/2.0
        sonarRange = 1.0 + (u.sonar - 1) * 0.2,         -- 1.0/1.2/1.4/1.6/1.8
        armorMult = 1.0 - (u.armor - 1) * 0.15,         -- 1.0/0.85/0.7/0.55/0.4 (伤害减少)
    }
end

--- 开始场景切换
function GameState.StartTransition(state, targetScene)
    state.transition.active = true
    state.transition.timer = 0
    state.transition.targetScene = targetScene
end

--- 更新场景切换
--- 返回 true 表示切换完成
function GameState.UpdateTransition(state, dt)
    if not state.transition.active then return false end

    state.transition.timer = state.transition.timer + dt

    -- 到达中点时切换场景
    local halfDur = state.transition.duration * 0.5
    if state.transition.timer >= halfDur and state.currentScene ~= state.transition.targetScene then
        state.currentScene = state.transition.targetScene
    end

    -- 动画结束
    if state.transition.timer >= state.transition.duration then
        state.transition.active = false
        state.transition.timer = 0
        return true
    end
    return false
end

--- 获取切换动画进度 (0~1，0.5=最暗)
function GameState.GetTransitionAlpha(state)
    if not state.transition.active then return 0 end
    local t = state.transition.timer / state.transition.duration
    -- 先变暗后变亮：sin曲线
    return math.sin(t * math.pi)
end

--- 出港（港口→深海）
function GameState.Depart(state)
    if state.currentMission == nil then
        return false, "请先接受一个任务！"
    end
    -- 重置任务进度
    state.missionProgress = {
        kills = 0,
        depthReached = 0,
        timeElapsed = 0,
        scrapsCollected = 0,
        crisisRepaired = 0,
    }
    GameState.StartTransition(state, GameState.SCENE_DEEP_SEA)
    return true, nil
end

--- 返回港口（深海→港口，结算任务）
function GameState.ReturnToPort(state)
    GameState.StartTransition(state, GameState.SCENE_PORT)
end

--- 任务结算（返回港口后调用）
function GameState.SettleMission(state)
    if state.currentMission == nil then return nil end

    local mission = state.currentMission
    local prog = state.missionProgress
    local rewards = { gold = 0, reputation = 0, items = {} }

    -- 检查任务目标是否完成
    local completed = true
    for _, obj in ipairs(mission.objectives) do
        if obj.type == "kill" and prog.kills < obj.count then
            completed = false
        elseif obj.type == "depth" and prog.depthReached < obj.value then
            completed = false
        elseif obj.type == "survive" and prog.timeElapsed < obj.duration then
            completed = false
        elseif obj.type == "collect" and prog.scrapsCollected < obj.count then
            completed = false
        elseif obj.type == "repair" and prog.crisisRepaired < obj.count then
            completed = false
        end
    end

    if completed then
        -- 发放奖励
        rewards.gold = mission.reward.gold or 0
        rewards.reputation = mission.reward.reputation or 0
        state.gold = state.gold + rewards.gold
        state.reputation = state.reputation + rewards.reputation
        state.totalMissions = state.totalMissions + 1

        -- 物品奖励
        if mission.reward.items then
            for _, item in ipairs(mission.reward.items) do
                state.supplies[item.id] = (state.supplies[item.id] or 0) + item.count
                table.insert(rewards.items, item)
            end
        end
    end

    -- 清除当前任务
    state.currentMission = nil
    return { completed = completed, rewards = rewards, mission = mission }
end

--- 消耗补给品（出港时扣除）
function GameState.GetSuppliesForMission(state)
    -- 复制一份供深海使用
    local copy = {}
    for k, v in pairs(state.supplies) do
        copy[k] = v
    end
    return copy
end

return GameState
