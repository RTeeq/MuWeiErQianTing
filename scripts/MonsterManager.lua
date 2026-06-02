--- 外部怪物管理器 - 生成、移动AI、攻击行为、受击/死亡
local Config = require("Config")
local ShakeEffect = require("render.ShakeEffect")
local CrisisManager = require("CrisisManager")

local MonsterManager = {}

-- ============================================================
-- 怪物类型定义
-- ============================================================
local MONSTER_TYPES = {
    worm = {
        name = "巨型蠕虫",
        speed = 40,            -- 游动速度
        hp = 3,                -- 需要3次击中
        damage = 15,           -- 撞击伤害（船体%）
        size = 80,             -- 视觉大小
        attackCooldown = 8,    -- 攻击间隔
    },
    jellyfish = {
        name = "触须水母",
        speed = 25,
        hp = 2,
        damage = 10,
        size = 60,
        attackCooldown = 6,
    },
    fish = {
        name = "多眼鱼",
        speed = 55,
        hp = 1,
        damage = 8,
        size = 50,
        attackCooldown = 5,
    },
}

local MONSTER_TYPE_LIST = {"worm", "jellyfish", "fish"}

-- ============================================================
-- 创建怪物管理器
-- ============================================================
---@return table
function MonsterManager.Create()
    return {
        monsters = {},             -- 活跃怪物列表
        spawnTimer = 0,            -- 生成计时
        spawnInterval = {20, 40},  -- 生成间隔（秒）
        nextSpawnTime = 15,        -- 首次生成
        maxMonsters = 3,           -- 最大同时存在怪物数
        sonarWarningTime = 5,      -- 声呐预警时间（秒）
        totalKills = 0,            -- 击杀数
    }
end

-- ============================================================
-- 创建单个怪物
-- ============================================================
local function CreateMonster(monsterType)
    local def = MONSTER_TYPES[monsterType]
    -- 怪物从远处出现（用归一化距离，1.0=远处，0=潜艇位置）
    local side = (math.random() > 0.5) and 1 or -1  -- 左右侧

    return {
        type = monsterType,
        def = def,
        hp = def.hp,
        maxHp = def.hp,

        -- 位置状态（归一化，用于声呐和外部视角）
        distance = 1.0,           -- 距潜艇距离 0~1 (1=远处, 0=接触)
        angle = math.random() * 60 - 30,  -- 接近角度（度）
        side = side,              -- -1=左侧, 1=右侧

        -- 状态机
        state = "approaching",    -- approaching, attacking, fleeing, dead
        stateTimer = 0,

        -- 声呐预警
        detectedOnSonar = true,
        sonarBlinkPhase = math.random() * math.pi * 2,

        -- 动画
        animTime = math.random() * 10,
        bodyPhase = math.random() * math.pi * 2,
        glowPhase = math.random() * math.pi * 2,

        -- 受击反馈
        hitFlash = 0,             -- 受击闪白
        hitParticles = {},        -- 绿血粒子

        -- 攻击冷却
        attackTimer = 0,
        hasAttacked = false,      -- 这一轮是否已攻击

        -- 船体凹陷动画
        hullDent = 0,             -- 凹陷程度 0~1
        dentX = 0,                -- 凹陷位置
    }
end

-- ============================================================
-- 更新
-- ============================================================
---@param mgr table 怪物管理器
---@param sub table 潜艇数据
---@param crisis table 危机管理器
---@param dt number
---@param gameTime number
function MonsterManager.Update(mgr, sub, crisis, dt, gameTime)
    mgr.spawnTimer = mgr.spawnTimer + dt

    -- 定时生成怪物
    if mgr.spawnTimer >= mgr.nextSpawnTime then
        local activeCount = 0
        for _, m in ipairs(mgr.monsters) do
            if m.state ~= "dead" then activeCount = activeCount + 1 end
        end
        if activeCount < mgr.maxMonsters then
            MonsterManager.SpawnRandom(mgr)
        end
        mgr.nextSpawnTime = mgr.spawnTimer + math.random(mgr.spawnInterval[1], mgr.spawnInterval[2])
    end

    -- 更新每只怪物
    for i = #mgr.monsters, 1, -1 do
        local m = mgr.monsters[i]
        m.animTime = m.animTime + dt
        m.stateTimer = m.stateTimer + dt

        if m.state == "approaching" then
            MonsterManager.UpdateApproaching(m, sub, crisis, dt, gameTime)
        elseif m.state == "attacking" then
            MonsterManager.UpdateAttacking(m, sub, crisis, dt, gameTime)
        elseif m.state == "fleeing" then
            MonsterManager.UpdateFleeing(m, dt)
        elseif m.state == "dead" then
            -- 死亡后移除
            if m.stateTimer > 3.0 then
                table.remove(mgr.monsters, i)
            end
        end

        -- 更新受击闪白
        if m.hitFlash > 0 then
            m.hitFlash = m.hitFlash - dt * 4
        end

        -- 更新绿血粒子
        MonsterManager.UpdateHitParticles(m, dt)

        -- 更新凹陷动画
        if m.hullDent > 0 then
            m.hullDent = m.hullDent - dt * 2.5  -- 0.4秒恢复
            if m.hullDent < 0 then m.hullDent = 0 end
        end
    end
end

--- 怪物接近阶段
function MonsterManager.UpdateApproaching(m, sub, crisis, dt, gameTime)
    local speed = m.def.speed / 400  -- 归一化速度
    m.distance = m.distance - speed * dt

    -- 到达攻击距离
    if m.distance <= 0.05 then
        m.state = "attacking"
        m.stateTimer = 0
        m.distance = 0.05
    end
end

--- 怪物攻击阶段
function MonsterManager.UpdateAttacking(m, sub, crisis, dt, gameTime)
    m.attackTimer = m.attackTimer + dt

    if not m.hasAttacked and m.attackTimer > 0.5 then
        -- 执行攻击
        m.hasAttacked = true

        -- 1. 船体震动
        ShakeEffect.TriggerImpact(3.0 + m.def.damage * 0.1)

        -- 2. 触发船体破裂危机
        local roomIndex = math.random(2, #sub.compartments)
        CrisisManager.TriggerCrisis(crisis, sub, "breach", gameTime)

        -- 3. 船体损伤
        sub.hull = math.max(0, sub.hull - m.def.damage)

        -- 4. 船体凹陷动画
        m.hullDent = 1.0
        m.dentX = math.random() * 0.6 + 0.2  -- 凹陷在潜艇 20%~80% 位置

        print(string.format("[MONSTER] %s attacks! Hull damage: -%d%%", m.def.name, m.def.damage))
    end

    -- 攻击完后开始撤退
    if m.stateTimer > 2.0 then
        m.state = "fleeing"
        m.stateTimer = 0
    end
end

--- 怪物逃跑阶段
function MonsterManager.UpdateFleeing(m, dt)
    local speed = m.def.speed / 300  -- 逃跑略快
    m.distance = m.distance + speed * dt

    -- 逃出视野后移除
    if m.distance > 1.2 then
        m.state = "dead"
        m.stateTimer = 0
    end
end

--- 更新绿血粒子
function MonsterManager.UpdateHitParticles(m, dt)
    for i = #m.hitParticles, 1, -1 do
        local p = m.hitParticles[i]
        p.life = p.life - dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 30 * dt  -- 重力
        if p.life <= 0 then
            table.remove(m.hitParticles, i)
        end
    end
end

-- ============================================================
-- 操作接口
-- ============================================================

--- 随机生成怪物
function MonsterManager.SpawnRandom(mgr)
    local typeIdx = math.random(1, #MONSTER_TYPE_LIST)
    local monsterType = MONSTER_TYPE_LIST[typeIdx]
    local monster = CreateMonster(monsterType)
    table.insert(mgr.monsters, monster)
    print(string.format("[MONSTER] %s spawned! (distance=1.0)", MONSTER_TYPES[monsterType].name))
end

--- 怪物受击
---@param mgr table
---@param monsterIndex number
---@return boolean killed 是否击杀
function MonsterManager.HitMonster(mgr, monsterIndex)
    local m = mgr.monsters[monsterIndex]
    if not m or m.state == "dead" then return false end

    m.hp = m.hp - 1
    m.hitFlash = 1.0

    -- 生成绿血粒子
    for i = 1, 8 do
        table.insert(m.hitParticles, {
            x = 0, y = 0,
            vx = (math.random() - 0.5) * 120,
            vy = (math.random() - 0.5) * 80 - 30,
            life = 0.8 + math.random() * 0.5,
            maxLife = 1.3,
            size = 3 + math.random() * 4,
        })
    end

    if m.hp <= 0 then
        m.state = "fleeing"
        m.stateTimer = 0
        mgr.totalKills = mgr.totalKills + 1
        print(string.format("[MONSTER] %s killed! Total kills: %d", m.def.name, mgr.totalKills))
        return true
    else
        -- 被击中但未死，短暂后退
        m.distance = math.min(1.0, m.distance + 0.15)
        print(string.format("[MONSTER] %s hit! HP: %d/%d", m.def.name, m.hp, m.maxHp))
        return false
    end
end

--- 获取声呐上的怪物数据（供声呐模块调用）
---@param mgr table
---@return table[] 声呐显示数据
function MonsterManager.GetSonarData(mgr)
    local result = {}
    for i, m in ipairs(mgr.monsters) do
        if m.state ~= "dead" and m.detectedOnSonar then
            table.insert(result, {
                index = i,
                distance = m.distance,
                angle = m.angle,
                side = m.side,
                type = m.type,
                blinkPhase = m.sonarBlinkPhase,
                state = m.state,
            })
        end
    end
    return result
end

--- 获取在外部视角中可见的怪物（距离 < 0.8）
---@param mgr table
---@return table[]
function MonsterManager.GetVisibleMonsters(mgr)
    local result = {}
    for i, m in ipairs(mgr.monsters) do
        if m.state ~= "dead" and m.distance < 0.8 then
            table.insert(result, {
                index = i,
                monster = m,
            })
        end
    end
    return result
end

--- 获取船体凹陷数据（供SubHull渲染）
---@param mgr table
---@return table|nil
function MonsterManager.GetHullDent(mgr)
    for _, m in ipairs(mgr.monsters) do
        if m.hullDent > 0 then
            return { amount = m.hullDent, x = m.dentX }
        end
    end
    return nil
end

--- 获取正在攻击中的怪物数量
function MonsterManager.GetAttackingCount(mgr)
    local count = 0
    for _, m in ipairs(mgr.monsters) do
        if m.state == "attacking" then count = count + 1 end
    end
    return count
end

return MonsterManager
