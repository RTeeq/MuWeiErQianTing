--- 炮塔系统 - 瞄准/射击/弹道/命中检测
local Config = require("Config")
local MonsterManager = require("MonsterManager")

local TurretSystem = {}

-- ============================================================
-- 创建炮塔系统
-- ============================================================
---@return table
function TurretSystem.Create()
    return {
        -- 状态
        active = false,           -- 是否在炮塔操作模式
        aimX = 0.5,              -- 瞄准位置 (归一化 0~1)
        aimY = 0.5,

        -- 射击
        projectiles = {},         -- 活跃弹丸列表
        fireTimer = 0,           -- 射击冷却
        fireCooldown = 0.8,      -- 射击间隔（秒）
        canFire = true,

        -- 后坐力
        recoil = 0,              -- 后坐力偏移 0~1
        recoilDecay = 5.0,       -- 后坐力恢复速度

        -- 统计
        shotsFired = 0,
        shotsHit = 0,
    }
end

-- ============================================================
-- 进入/退出炮塔模式
-- ============================================================

--- 进入炮塔操作模式
function TurretSystem.Activate(turret)
    turret.active = true
    turret.aimX = 0.5
    turret.aimY = 0.5
    turret.recoil = 0
    print("[TURRET] Activated! Aim and fire!")
end

--- 退出炮塔模式
function TurretSystem.Deactivate(turret)
    turret.active = false
    turret.projectiles = {}
    print("[TURRET] Deactivated.")
end

-- ============================================================
-- 更新
-- ============================================================

--- 更新炮塔系统
---@param turret table
---@param monsterMgr table
---@param dt number
---@param gameTime number
function TurretSystem.Update(turret, monsterMgr, dt, gameTime)
    if not turret.active then return end

    -- 射击冷却
    if not turret.canFire then
        turret.fireTimer = turret.fireTimer + dt
        if turret.fireTimer >= turret.fireCooldown then
            turret.canFire = true
            turret.fireTimer = 0
        end
    end

    -- 后坐力恢复
    if turret.recoil > 0 then
        turret.recoil = turret.recoil - turret.recoilDecay * dt
        if turret.recoil < 0 then turret.recoil = 0 end
    end

    -- 更新弹丸
    for i = #turret.projectiles, 1, -1 do
        local proj = turret.projectiles[i]
        proj.life = proj.life - dt
        proj.x = proj.x + proj.vx * dt
        proj.y = proj.y + proj.vy * dt
        proj.trail = proj.trail or {}

        -- 添加弹道轨迹点
        table.insert(proj.trail, {x = proj.x, y = proj.y, alpha = 255})

        -- 淡化轨迹
        for j = #proj.trail, 1, -1 do
            proj.trail[j].alpha = proj.trail[j].alpha - dt * 500
            if proj.trail[j].alpha <= 0 then
                table.remove(proj.trail, j)
            end
        end

        -- 检测命中怪物
        local hit = TurretSystem.CheckHit(proj, monsterMgr)
        if hit then
            -- 命中！
            turret.shotsHit = turret.shotsHit + 1
            table.remove(turret.projectiles, i)
        elseif proj.life <= 0 then
            -- 超出范围
            table.remove(turret.projectiles, i)
        end
    end
end

--- 更新瞄准位置（跟随手指/鼠标）
---@param turret table
---@param normX number 归一化X (0~1)
---@param normY number 归一化Y (0~1)
function TurretSystem.UpdateAim(turret, normX, normY)
    if not turret.active then return end
    -- 平滑跟随
    turret.aimX = turret.aimX + (normX - turret.aimX) * 0.3
    turret.aimY = turret.aimY + (normY - turret.aimY) * 0.3
end

-- ============================================================
-- 射击
-- ============================================================

--- 射击（accuracyMult 越高散布越小，1.0=基准，1.6=安全官精度）
---@param turret table
---@param accuracyMult number|nil 精度倍率（默认1.0）
---@return boolean 是否成功射击
function TurretSystem.Fire(turret, accuracyMult)
    if not turret.active or not turret.canFire then return false end

    turret.canFire = false
    turret.fireTimer = 0
    turret.shotsFired = turret.shotsFired + 1

    -- 后坐力
    turret.recoil = 1.0

    -- 创建弹丸（从屏幕中心向瞄准方向飞行）
    local startX = 0.5
    local startY = 0.8  -- 炮塔位于屏幕下方

    local dx = turret.aimX - startX
    local dy = turret.aimY - startY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then dist = 0.01 end

    -- 精度散布：基准散布0.04，精度越高散布越小
    local acc = accuracyMult or 1.0
    local spread = 0.04 / acc
    local spreadX = (math.random() - 0.5) * spread
    local spreadY = (math.random() - 0.5) * spread

    local speed = 2.0  -- 归一化速度
    local vx = (dx / dist + spreadX) * speed
    local vy = (dy / dist + spreadY) * speed

    table.insert(turret.projectiles, {
        x = startX,
        y = startY,
        vx = vx,
        vy = vy,
        life = 1.5,  -- 弹丸存活时间
        trail = {},
    })

    print(string.format("[TURRET] Fire! Aim: (%.2f, %.2f) Acc: %.1fx", turret.aimX, turret.aimY, acc))
    return true
end

-- ============================================================
-- 命中检测
-- ============================================================

--- 检测弹丸是否命中怪物
---@param proj table 弹丸
---@param monsterMgr table
---@return boolean
function TurretSystem.CheckHit(proj, monsterMgr)
    -- 弹丸位置转为怪物可比较的范围
    for i, m in ipairs(monsterMgr.monsters) do
        if m.state ~= "dead" and m.state ~= "fleeing" then
            -- 怪物在外部视角中的大致归一化位置
            local mx = 0.5 + m.side * m.distance * 0.45
            local my = 0.5 + math.sin(math.rad(m.angle)) * m.distance * 0.3

            -- 命中半径（根据怪物大小和距离）
            local hitRadius = 0.06 * (1 - m.distance * 0.5)

            local dx = proj.x - mx
            local dy = proj.y - my
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < hitRadius then
                MonsterManager.HitMonster(monsterMgr, i)
                return true
            end
        end
    end
    return false
end

--- 检查角色是否在炮塔舱（weapons room = index 6）
---@param char table
---@return boolean
function TurretSystem.IsInTurretRoom(char)
    return char.roomIndex == 6
end

return TurretSystem
