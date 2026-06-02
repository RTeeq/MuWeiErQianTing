--- 任务系统
--- 生成可接取任务、追踪进度
local MissionSystem = {}

-- ============================================================
-- 任务模板（难度分层）
-- ============================================================
MissionSystem.TEMPLATES = {
    -- === 初级任务 (声望 < 5) ===
    {
        tier = 1,
        title = "浅层巡航",
        desc = "在2500米深度存活3分钟",
        objectives = { { type = "survive", duration = 180 } },
        reward = { gold = 150, reputation = 1 },
    },
    {
        tier = 1,
        title = "清除威胁",
        desc = "消灭3只深海生物",
        objectives = { { type = "kill", count = 3 } },
        reward = { gold = 200, reputation = 1 },
    },
    {
        tier = 1,
        title = "废料回收",
        desc = "收集5份废料碎片",
        objectives = { { type = "collect", count = 5 } },
        reward = { gold = 120, reputation = 1, items = { { id = "repair_tool", count = 1 } } },
    },

    -- === 中级任务 (声望 3~10) ===
    {
        tier = 2,
        title = "深渊探测",
        desc = "到达3000米深度",
        objectives = { { type = "depth", value = 3000 } },
        reward = { gold = 350, reputation = 2 },
    },
    {
        tier = 2,
        title = "危机处理",
        desc = "修复4次突发危机",
        objectives = { { type = "repair", count = 4 } },
        reward = { gold = 300, reputation = 2, items = { { id = "medkit", count = 2 } } },
    },
    {
        tier = 2,
        title = "猎杀行动",
        desc = "消灭6只深海生物",
        objectives = { { type = "kill", count = 6 } },
        reward = { gold = 400, reputation = 2, items = { { id = "ammo_pack", count = 2 } } },
    },
    {
        tier = 2,
        title = "持久作战",
        desc = "在深海存活5分钟",
        objectives = { { type = "survive", duration = 300 } },
        reward = { gold = 280, reputation = 2 },
    },

    -- === 高级任务 (声望 >= 8) ===
    {
        tier = 3,
        title = "极限深潜",
        desc = "到达4000米深度并存活2分钟",
        objectives = {
            { type = "depth", value = 4000 },
            { type = "survive", duration = 120 },
        },
        reward = { gold = 600, reputation = 3, items = { { id = "power_cell", count = 2 } } },
    },
    {
        tier = 3,
        title = "歼灭作战",
        desc = "消灭10只深海生物",
        objectives = { { type = "kill", count = 10 } },
        reward = { gold = 700, reputation = 3, items = { { id = "ammo_pack", count = 3 } } },
    },
    {
        tier = 3,
        title = "全能指挥官",
        desc = "消灭5只生物并修复3次危机",
        objectives = {
            { type = "kill", count = 5 },
            { type = "repair", count = 3 },
        },
        reward = { gold = 800, reputation = 4, items = { { id = "sonar_boost", count = 2 } } },
    },
}

-- ============================================================
-- 任务生成
-- ============================================================

--- 生成可接任务列表（根据声望筛选）
function MissionSystem.GenerateMissions(reputation)
    local available = {}

    -- 根据声望确定可用等级
    local maxTier = 1
    if reputation >= 3 then maxTier = 2 end
    if reputation >= 8 then maxTier = 3 end

    -- 从模板中筛选
    for _, tmpl in ipairs(MissionSystem.TEMPLATES) do
        if tmpl.tier <= maxTier then
            table.insert(available, tmpl)
        end
    end

    -- 随机选取最多5个任务
    local missions = {}
    local pool = {}
    for i, m in ipairs(available) do
        pool[i] = m
    end

    -- Fisher-Yates洗牌取前5
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    for i = 1, math.min(5, #pool) do
        -- 深拷贝任务（避免修改模板）
        local m = pool[i]
        local mission = {
            title = m.title,
            desc = m.desc,
            tier = m.tier,
            objectives = {},
            reward = {
                gold = m.reward.gold,
                reputation = m.reward.reputation,
                items = m.reward.items,
            },
        }
        for _, obj in ipairs(m.objectives) do
            table.insert(mission.objectives, {
                type = obj.type,
                count = obj.count,
                value = obj.value,
                duration = obj.duration,
            })
        end
        table.insert(missions, mission)
    end

    return missions
end

--- 获取任务目标描述文字
function MissionSystem.GetObjectiveText(obj)
    if obj.type == "kill" then
        return "消灭 " .. obj.count .. " 只深海生物"
    elseif obj.type == "depth" then
        return "到达 " .. obj.value .. "m 深度"
    elseif obj.type == "survive" then
        local min = math.floor(obj.duration / 60)
        local sec = obj.duration % 60
        if sec > 0 then
            return "存活 " .. min .. "分" .. sec .. "秒"
        else
            return "存活 " .. min .. "分钟"
        end
    elseif obj.type == "collect" then
        return "收集 " .. obj.count .. " 份废料"
    elseif obj.type == "repair" then
        return "修复 " .. obj.count .. " 次危机"
    end
    return "???"
end

--- 获取任务等级颜色 (r,g,b)
function MissionSystem.GetTierColor(tier)
    if tier == 1 then return 120, 200, 120 end  -- 绿色
    if tier == 2 then return 220, 180, 60 end   -- 金色
    if tier == 3 then return 220, 80, 80 end    -- 红色
    return 180, 180, 180
end

--- 获取任务等级文字
function MissionSystem.GetTierName(tier)
    if tier == 1 then return "★ 初级" end
    if tier == 2 then return "★★ 中级" end
    if tier == 3 then return "★★★ 高级" end
    return "?"
end

--- 检查任务进度是否满足目标
function MissionSystem.CheckProgress(mission, progress)
    if not mission then return false end
    for _, obj in ipairs(mission.objectives) do
        if obj.type == "kill" and progress.kills < obj.count then
            return false
        elseif obj.type == "depth" and progress.depthReached < obj.value then
            return false
        elseif obj.type == "survive" and progress.timeElapsed < obj.duration then
            return false
        elseif obj.type == "collect" and progress.scrapsCollected < obj.count then
            return false
        elseif obj.type == "repair" and progress.crisisRepaired < obj.count then
            return false
        end
    end
    return true
end

--- 获取单个目标的进度比 (0~1)
function MissionSystem.GetObjectiveProgress(obj, progress)
    if obj.type == "kill" then
        return math.min(1, progress.kills / obj.count)
    elseif obj.type == "depth" then
        return math.min(1, progress.depthReached / obj.value)
    elseif obj.type == "survive" then
        return math.min(1, progress.timeElapsed / obj.duration)
    elseif obj.type == "collect" then
        return math.min(1, progress.scrapsCollected / obj.count)
    elseif obj.type == "repair" then
        return math.min(1, progress.crisisRepaired / obj.count)
    end
    return 0
end

return MissionSystem
