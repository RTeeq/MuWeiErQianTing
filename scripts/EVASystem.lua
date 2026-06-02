--- 舱外活动(EVA)系统
--- 船员穿潜水服通过气闸出潜艇，在深海遗迹中探索
--- 有氧气瓶限制，需要在耗尽前返回
local EVASystem = {}

-- ============================================================
-- 配置
-- ============================================================
EVASystem.Config = {
    -- 氧气瓶
    maxOxygen = 60,           -- 满瓶60秒氧气
    oxygenDrainRate = 1.0,    -- 每秒消耗1单位
    criticalOxygen = 15,      -- 低于15秒进入紧急状态

    -- 移动
    moveSpeed = 80,           -- 像素/秒（深海中缓慢）
    swimAccel = 200,          -- 游泳加速度
    swimDrag = 3.0,           -- 水阻力

    -- 区域
    worldWidth = 2400,        -- 探索区域宽度
    worldHeight = 800,        -- 探索区域高度
    subDockX = 200,           -- 潜艇气闸出口X位置
    subDockY = 400,           -- 潜艇气闸Y位置
    dockRadius = 40,          -- 返回判定半径

    -- 头灯
    headlightRadius = 120,    -- 头灯照射半径
    headlightAngle = 50,      -- 头灯锥形角度(度)

    -- 拾取
    pickupRadius = 35,        -- 拾取判定半径
}

-- ============================================================
-- 状态创建
-- ============================================================

--- 创建EVA状态
function EVASystem.Create()
    return {
        -- 状态
        isActive = false,       -- 是否正在舱外活动
        phase = "idle",         -- idle/suiting/active/returning/emergency

        -- 氧气
        oxygen = EVASystem.Config.maxOxygen,
        oxygenWarning = false,  -- 氧气警告状态

        -- 位置和移动（世界坐标）
        x = EVASystem.Config.subDockX,
        y = EVASystem.Config.subDockY,
        vx = 0,
        vy = 0,
        facing = 1,            -- 1=右 -1=左
        angle = 0,             -- 朝向角度(弧度)

        -- 动画
        swimAnim = 0,          -- 游泳动画计时
        bubbleTimer = 0,       -- 气泡生成计时
        bubbles = {},          -- 气泡粒子列表

        -- 气闸动画
        suitTimer = 0,         -- 穿衣/脱衣计时
        suitDuration = 2.0,    -- 穿衣时长

        -- 探照灯
        headlightOn = true,

        -- 拾取
        nearLoot = nil,        -- 最近的可拾取物品
        collectedLoot = {},    -- 本次EVA收集的战利品

        -- 统计
        totalEVAs = 0,         -- 总出舱次数
        totalExploreTime = 0,  -- 总探索时间
    }
end

-- ============================================================
-- 核心逻辑
-- ============================================================

--- 开始EVA（从气闸出发）
function EVASystem.StartEVA(eva)
    if eva.isActive then return false end

    eva.phase = "suiting"
    eva.suitTimer = 0
    eva.oxygen = EVASystem.Config.maxOxygen
    eva.oxygenWarning = false
    eva.x = EVASystem.Config.subDockX
    eva.y = EVASystem.Config.subDockY
    eva.vx = 0
    eva.vy = 0
    eva.collectedLoot = {}
    eva.bubbles = {}
    return true
end

--- 结束EVA（返回气闸）
function EVASystem.EndEVA(eva)
    if not eva.isActive then return false end

    eva.phase = "returning"
    eva.suitTimer = 0
    return true
end

--- 更新EVA系统
function EVASystem.Update(eva, jx, jy, dt)
    if eva.phase == "idle" then return end

    -- 穿衣阶段
    if eva.phase == "suiting" then
        eva.suitTimer = eva.suitTimer + dt
        if eva.suitTimer >= eva.suitDuration then
            eva.phase = "active"
            eva.isActive = true
            eva.totalEVAs = eva.totalEVAs + 1
        end
        return
    end

    -- 返回阶段（脱衣动画）
    if eva.phase == "returning" then
        eva.suitTimer = eva.suitTimer + dt
        if eva.suitTimer >= eva.suitDuration * 0.5 then
            eva.phase = "idle"
            eva.isActive = false
        end
        return
    end

    -- ====== 活跃状态 ======

    -- 氧气消耗
    eva.oxygen = eva.oxygen - EVASystem.Config.oxygenDrainRate * dt
    eva.oxygenWarning = (eva.oxygen <= EVASystem.Config.criticalOxygen)

    -- 氧气耗尽 → 紧急返回
    if eva.oxygen <= 0 then
        eva.oxygen = 0
        eva.phase = "emergency"
        -- 紧急状态下自动返回气闸
        EVASystem.ForceReturn(eva, dt)
        return
    end

    -- 紧急状态处理
    if eva.phase == "emergency" then
        EVASystem.ForceReturn(eva, dt)
        return
    end

    -- 总探索时间
    eva.totalExploreTime = eva.totalExploreTime + dt

    -- 游泳移动（带水阻力的加速度模型）
    local cfg = EVASystem.Config
    local accel = cfg.swimAccel

    -- 摇杆输入转为加速度
    eva.vx = eva.vx + jx * accel * dt
    eva.vy = eva.vy + jy * accel * dt

    -- 水阻力
    local drag = cfg.swimDrag
    eva.vx = eva.vx * (1 - drag * dt)
    eva.vy = eva.vy * (1 - drag * dt)

    -- 限速
    local speed = math.sqrt(eva.vx * eva.vx + eva.vy * eva.vy)
    if speed > cfg.moveSpeed then
        local scale = cfg.moveSpeed / speed
        eva.vx = eva.vx * scale
        eva.vy = eva.vy * scale
    end

    -- 更新位置
    eva.x = eva.x + eva.vx * dt
    eva.y = eva.y + eva.vy * dt

    -- 边界限制
    eva.x = math.max(0, math.min(cfg.worldWidth, eva.x))
    eva.y = math.max(50, math.min(cfg.worldHeight - 50, eva.y))

    -- 朝向
    if math.abs(eva.vx) > 5 then
        eva.facing = eva.vx > 0 and 1 or -1
    end
    if speed > 5 then
        eva.angle = math.atan(eva.vy, eva.vx)
    end

    -- 游泳动画
    eva.swimAnim = eva.swimAnim + dt * (2 + speed * 0.02)

    -- 气泡生成
    eva.bubbleTimer = eva.bubbleTimer + dt
    if eva.bubbleTimer > 0.3 then
        eva.bubbleTimer = 0
        table.insert(eva.bubbles, {
            x = eva.x - eva.facing * 8,
            y = eva.y - 5,
            vy = -30 - math.random() * 20,
            size = 2 + math.random() * 3,
            life = 2.0,
        })
    end

    -- 更新气泡
    for i = #eva.bubbles, 1, -1 do
        local b = eva.bubbles[i]
        b.y = b.y + b.vy * dt
        b.x = b.x + math.sin(b.life * 3) * 10 * dt
        b.life = b.life - dt
        if b.life <= 0 then
            table.remove(eva.bubbles, i)
        end
    end
end

--- 紧急返回（自动飞向气闸）
function EVASystem.ForceReturn(eva, dt)
    local cfg = EVASystem.Config
    local dx = cfg.subDockX - eva.x
    local dy = cfg.subDockY - eva.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < cfg.dockRadius then
        -- 到达气闸
        eva.phase = "idle"
        eva.isActive = false
        return
    end

    -- 朝气闸移动（加速）
    local speed = cfg.moveSpeed * 1.5
    eva.x = eva.x + (dx / dist) * speed * dt
    eva.y = eva.y + (dy / dist) * speed * dt
    eva.facing = dx > 0 and 1 or -1
    eva.swimAnim = eva.swimAnim + dt * 4
end

--- 检查是否靠近气闸可以返回
function EVASystem.IsNearDock(eva)
    local cfg = EVASystem.Config
    local dx = cfg.subDockX - eva.x
    local dy = cfg.subDockY - eva.y
    return (dx * dx + dy * dy) < (cfg.dockRadius * cfg.dockRadius)
end

--- 检查是否靠近某个拾取物
function EVASystem.CheckNearLoot(eva, loots)
    eva.nearLoot = nil
    local cfg = EVASystem.Config
    local bestDist = cfg.pickupRadius

    for _, loot in ipairs(loots) do
        if not loot.collected then
            local dx = loot.x - eva.x
            local dy = loot.y - eva.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < bestDist then
                bestDist = dist
                eva.nearLoot = loot
            end
        end
    end
end

--- 拾取最近的战利品
function EVASystem.PickupLoot(eva)
    if not eva.nearLoot then return nil end

    local loot = eva.nearLoot
    loot.collected = true
    table.insert(eva.collectedLoot, {
        type = loot.type,
        name = loot.name,
        value = loot.value,
    })
    eva.nearLoot = nil
    return loot
end

--- 获取EVA收集的战利品（返回后结算）
function EVASystem.GetCollectedLoot(eva)
    return eva.collectedLoot
end

--- 获取氧气百分比
function EVASystem.GetOxygenPercent(eva)
    return eva.oxygen / EVASystem.Config.maxOxygen
end

return EVASystem
