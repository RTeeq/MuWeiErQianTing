--- AI 船员系统 - 6名自动巡逻的AI队员（各有职业特长）
--- 行为：巡逻 → 检查设备 → 响应危机 → 执行指令
local Config = require("Config")

local AICrew = {}

---@alias AIState "patrol"|"check"|"respond"|"repair"|"follow"|"standby"
---@alias Profession "captain"|"engineer"|"mechanic"|"doctor"|"security"|"assistant"

--- 职业能力定义
local PROFESSIONS = {
    captain = {
        title = "舰长",
        repairSpeed = 0.10,     -- 修复速度（基准0.12）
        turretAccuracy = 1.0,   -- 炮塔精度倍率
        moveSpeedMult = 1.0,    -- 移动速度
        healPower = 0,          -- 治疗能力
        pilotBonus = 0.3,       -- 驾驶加成（提升30%航速）
        allBonus = 0,           -- 万能加成
    },
    engineer = {
        title = "工程师",
        repairSpeed = 0.15,     -- 接线/修电路更快
        turretAccuracy = 1.0,
        moveSpeedMult = 0.9,
        healPower = 0,
        pilotBonus = 0,
        allBonus = 0,
        -- 特殊：过热和氧气泄漏修复速度×1.8
        crisisBonus = { overheat = 1.8, oxygen_leak = 1.5 },
    },
    mechanic = {
        title = "机修工",
        repairSpeed = 0.24,     -- 修复速度翻倍！
        turretAccuracy = 1.0,
        moveSpeedMult = 0.95,
        healPower = 0,
        pilotBonus = 0,
        allBonus = 0,
        -- 特殊：漏水（breach）修复速度×2.0
        crisisBonus = { breach = 2.0 },
    },
    doctor = {
        title = "医生",
        repairSpeed = 0.08,     -- 修复不在行
        turretAccuracy = 0.8,
        moveSpeedMult = 0.9,
        healPower = 0.15,       -- 每秒恢复15%生命
        pilotBonus = 0,
        allBonus = 0,
    },
    security = {
        title = "安全官",
        repairSpeed = 0.10,
        turretAccuracy = 1.6,   -- 炮塔精度大幅提升！
        moveSpeedMult = 1.1,    -- 快速反应
        healPower = 0,
        pilotBonus = 0,
        allBonus = 0,
    },
    assistant = {
        title = "助手",
        repairSpeed = 0.13,     -- 略高于基准
        turretAccuracy = 1.15,  -- 略准一点
        moveSpeedMult = 1.0,
        healPower = 0.05,       -- 轻微治疗
        pilotBonus = 0.1,       -- 一点驾驶加成
        allBonus = 0.1,         -- 全面加成10%
    },
}

--- AI船员定义（6名各有职业）
local AI_DEFS = {
    {name = "李舰长", profession = "captain",   color = {220, 180, 50},  startRoom = 1},  -- 金色
    {name = "赵工程", profession = "engineer",  color = {50, 180, 220},  startRoom = 2},  -- 青色
    {name = "孙机修", profession = "mechanic",  color = {220, 130, 50},  startRoom = 3},  -- 橙色
    {name = "周医生", profession = "doctor",    color = {80, 220, 120},  startRoom = 5},  -- 绿色
    {name = "钱安官", profession = "security",  color = {180, 50, 50},   startRoom = 6},  -- 红色
    {name = "吴助手", profession = "assistant", color = {180, 130, 220}, startRoom = 4},  -- 紫色
}

--- 状态中文显示
local STATE_TEXT = {
    patrol  = "巡逻中",
    check   = "检查设备",
    respond = "前往维修",
    repair  = "修复中",
    follow  = "跟随中",
    standby = "待命中",
}

--- 创建AI船员系统
---@param sub table 潜艇状态
---@return table
function AICrew.Create(sub)
    local crew = {}
    for i, def in ipairs(AI_DEFS) do
        local comp = sub.compartments[def.startRoom]
        local startX = comp.x + comp.width * 0.5

        local prof = PROFESSIONS[def.profession]
        crew[i] = {
            -- 基础信息
            name = def.name,
            color = def.color,
            index = i,
            profession = def.profession,  -- 职业类型
            profData = prof,              -- 职业能力数据引用

            -- 位置
            x = startX,
            roomIndex = def.startRoom,
            facing = (i % 2 == 0) and -1 or 1,

            -- 状态
            state = "patrol",       ---@type AIState
            animState = "idle",     -- idle/walk/operate/repair
            animTime = 0,

            -- 巡逻参数
            patrolTarget = nil,     -- 目标X坐标
            patrolWait = 0,         -- 到达后等待时间
            patrolDir = (i % 2 == 0) and -1 or 1,  -- 巡逻方向

            -- 检查设备
            checkTimer = 0,         -- 检查设备倒计时
            checkDuration = 0,      -- 总检查时长

            -- 危机响应
            targetCrisis = nil,     -- 当前目标危机
            repairProgress = 0,

            -- 指令
            command = nil,          ---@type "follow"|"repair"|"operate"|"standby"|nil
            followTarget = nil,     -- 跟随目标（玩家char）

            -- 动画/效果
            footstepTimer = 0,      -- 脚步波纹计时
            isMoving = false,       -- 是否正在移动

            -- 职业特有状态
            healTarget = nil,       -- 医生：治疗目标
            isPiloting = false,     -- 舰长：是否在驾驶
        }
    end

    return {
        members = crew,
        selectedIndex = nil,        -- 当前选中的AI（用于指令轮盘）
    }
end

--- 更新所有AI船员
---@param aiCrew table
---@param sub table
---@param crisis table
---@param playerChar table
---@param dt number
---@param gameTime number
function AICrew.Update(aiCrew, sub, crisis, playerChar, dt, gameTime)
    for _, ai in ipairs(aiCrew.members) do
        ai.animTime = ai.animTime + dt

        -- 指令优先级：玩家指令 > 危机响应 > 自动巡逻
        if ai.command == "follow" then
            AICrew.UpdateFollow(ai, sub, playerChar, dt)
        elseif ai.command == "standby" then
            AICrew.UpdateStandby(ai, dt)
        elseif ai.command == "repair" then
            AICrew.UpdateCommandRepair(ai, sub, crisis, dt)
        else
            -- 自动行为
            if ai.state == "repair" or ai.state == "respond" then
                AICrew.UpdateCrisisResponse(ai, sub, crisis, dt)
            elseif ai.state == "check" then
                AICrew.UpdateCheck(ai, dt)
            else
                -- 检查是否有未处理危机需要响应
                local foundCrisis = AICrew.FindUnhandledCrisis(ai, aiCrew, crisis, sub)
                if foundCrisis then
                    ai.state = "respond"
                    ai.targetCrisis = foundCrisis
                    ai.animState = "walk"
                else
                    AICrew.UpdatePatrol(ai, sub, dt, gameTime)
                end
            end
        end

        -- 更新舱室索引
        for idx, comp in ipairs(sub.compartments) do
            if ai.x >= comp.x and ai.x < comp.x + comp.width then
                ai.roomIndex = idx
                break
            end
        end

        -- 脚步计时
        if ai.isMoving then
            ai.footstepTimer = ai.footstepTimer + dt
        end
    end
end

--- 巡逻行为
function AICrew.UpdatePatrol(ai, sub, dt, gameTime)
    ai.state = "patrol"

    -- 等待阶段
    if ai.patrolWait > 0 then
        ai.patrolWait = ai.patrolWait - dt
        ai.animState = "idle"
        ai.isMoving = false

        -- 等待结束后小概率转为检查设备
        if ai.patrolWait <= 0 then
            if math.random() < 0.3 then
                ai.state = "check"
                ai.checkTimer = 0
                ai.checkDuration = 2.0 + math.random() * 2.0
                ai.animState = "operate"
                return
            end
        end
        return
    end

    -- 确定巡逻目标
    if ai.patrolTarget == nil then
        -- 选择随机目标舱室
        local targetRoom = math.random(1, #sub.compartments)
        local comp = sub.compartments[targetRoom]
        ai.patrolTarget = comp.x + comp.width * (0.2 + math.random() * 0.6)
    end

    -- 移动向目标
    local dx = ai.patrolTarget - ai.x
    if math.abs(dx) < 5 then
        -- 到达目标
        ai.patrolTarget = nil
        ai.patrolWait = 1.5 + math.random() * 3.0  -- 停留1.5~4.5秒
        ai.animState = "idle"
        ai.isMoving = false
    else
        local speed = Config.Crew.walkSpeed * 0.7 * ai.profData.moveSpeedMult
        local move = speed * dt * (dx > 0 and 1 or -1)
        ai.x = ai.x + move
        ai.facing = dx > 0 and 1 or -1
        ai.animState = "walk"
        ai.isMoving = true
    end

    -- 边界限制
    local totalWidth = 0
    for _, comp in ipairs(sub.compartments) do
        totalWidth = totalWidth + comp.width
    end
    ai.x = math.max(15, math.min(totalWidth - 15, ai.x))
end

--- 检查设备行为
function AICrew.UpdateCheck(ai, dt)
    ai.checkTimer = ai.checkTimer + dt
    ai.animState = "operate"
    ai.isMoving = false

    if ai.checkTimer >= ai.checkDuration then
        -- 检查完毕，恢复巡逻
        ai.state = "patrol"
        ai.patrolWait = 0.5
        ai.animState = "idle"
    end
end

--- 查找未被处理的危机
function AICrew.FindUnhandledCrisis(ai, aiCrew, crisis, sub)
    local CrisisManager = require("CrisisManager")
    local activeCrises = CrisisManager.GetActiveCrises(crisis)

    for _, c in ipairs(activeCrises) do
        -- 检查是否已有其他AI在处理
        local alreadyHandled = false
        for _, other in ipairs(aiCrew.members) do
            if other.index ~= ai.index and
               other.targetCrisis and
               other.targetCrisis.type == c.type and
               other.targetCrisis.roomIndex == c.roomIndex then
                alreadyHandled = true
                break
            end
        end

        if not alreadyHandled then
            return c
        end
    end
    return nil
end

--- 危机响应行为
function AICrew.UpdateCrisisResponse(ai, sub, crisis, dt)
    if ai.targetCrisis == nil or ai.targetCrisis.resolved then
        -- 危机已解决，回归巡逻
        ai.state = "patrol"
        ai.targetCrisis = nil
        ai.repairProgress = 0
        ai.animState = "idle"
        return
    end

    local targetRoom = ai.targetCrisis.roomIndex
    local comp = sub.compartments[targetRoom]
    if not comp then
        ai.state = "patrol"
        return
    end

    local targetX = comp.x + comp.width * 0.5
    local dx = targetX - ai.x

    if math.abs(dx) < 20 then
        -- 到达目标位置，开始修复
        ai.state = "repair"
        ai.animState = "repair"
        ai.isMoving = false

        -- 根据职业计算修复速度
        local baseSpeed = ai.profData.repairSpeed
        -- 检查是否有针对特定危机类型的加成
        if ai.profData.crisisBonus and ai.targetCrisis and ai.targetCrisis.type then
            local bonus = ai.profData.crisisBonus[ai.targetCrisis.type]
            if bonus then
                baseSpeed = baseSpeed * bonus
            end
        end
        -- 助手万能加成
        if ai.profData.allBonus > 0 then
            baseSpeed = baseSpeed * (1 + ai.profData.allBonus)
        end

        ai.targetCrisis.repairProgress = math.min(1.0,
            ai.targetCrisis.repairProgress + baseSpeed * dt)
        ai.repairProgress = ai.targetCrisis.repairProgress
        ai.targetCrisis.isBeingRepaired = true

        -- 修复完成
        if ai.targetCrisis.repairProgress >= 1.0 then
            ai.targetCrisis.resolved = true
            ai.targetCrisis.resolvedTime = crisis.timer
            local CrisisManager = require("CrisisManager")
            CrisisManager.OnCrisisResolved(ai.targetCrisis, sub)
            ai.state = "patrol"
            ai.targetCrisis = nil
            ai.repairProgress = 0
            ai.animState = "idle"
        end
    else
        -- 移动到目标
        ai.state = "respond"
        local speed = Config.Crew.walkSpeed * 0.9 * ai.profData.moveSpeedMult
        ai.x = ai.x + speed * dt * (dx > 0 and 1 or -1)
        ai.facing = dx > 0 and 1 or -1
        ai.animState = "walk"
        ai.isMoving = true
    end
end

--- 跟随玩家指令
function AICrew.UpdateFollow(ai, sub, playerChar, dt)
    ai.state = "follow"
    local dx = playerChar.x - ai.x
    local followDist = 40 + ai.index * 25  -- 各自保持不同距离

    if math.abs(dx) > followDist then
        local speed = Config.Crew.walkSpeed * 0.85
        ai.x = ai.x + speed * dt * (dx > 0 and 1 or -1)
        ai.facing = dx > 0 and 1 or -1
        ai.animState = "walk"
        ai.isMoving = true
    else
        ai.animState = "idle"
        ai.isMoving = false
        ai.facing = playerChar.facing
    end
end

--- 待命指令
function AICrew.UpdateStandby(ai, dt)
    ai.state = "standby"
    ai.animState = "idle"
    ai.isMoving = false
end

--- 修复指令（玩家下令修理最近危机）
function AICrew.UpdateCommandRepair(ai, sub, crisis, dt)
    local CrisisManager = require("CrisisManager")
    local activeCrises = CrisisManager.GetActiveCrises(crisis)

    -- 找最近的未解决危机
    if ai.targetCrisis == nil or ai.targetCrisis.resolved then
        local closest = nil
        local closestDist = math.huge
        for _, c in ipairs(activeCrises) do
            local comp = sub.compartments[c.roomIndex]
            if comp then
                local dist = math.abs(ai.x - (comp.x + comp.width * 0.5))
                if dist < closestDist then
                    closestDist = dist
                    closest = c
                end
            end
        end
        if closest then
            ai.targetCrisis = closest
        else
            -- 没有危机可修，回到巡逻
            ai.command = nil
            ai.state = "patrol"
            return
        end
    end

    -- 复用危机响应逻辑
    AICrew.UpdateCrisisResponse(ai, sub, crisis, dt)
end

--- 设置AI指令
---@param aiCrew table
---@param aiIndex number
---@param command string "follow"|"repair"|"operate"|"standby"
function AICrew.SetCommand(aiCrew, aiIndex, command)
    local ai = aiCrew.members[aiIndex]
    if not ai then return end

    ai.command = command
    ai.targetCrisis = nil
    ai.repairProgress = 0

    if command == "follow" then
        ai.state = "follow"
    elseif command == "standby" then
        ai.state = "standby"
    elseif command == "repair" then
        ai.state = "respond"
    end

    print(string.format("[AI] %s -> 指令: %s", ai.name, command))
end

--- 清除AI指令（恢复自动行为）
function AICrew.ClearCommand(aiCrew, aiIndex)
    local ai = aiCrew.members[aiIndex]
    if not ai then return end
    ai.command = nil
    ai.state = "patrol"
    ai.targetCrisis = nil
end

--- 获取AI的状态文本
---@param ai table
---@return string
function AICrew.GetStateText(ai)
    return STATE_TEXT[ai.state] or "未知"
end

--- 检测点击某个AI船员（屏幕坐标）
---@param aiCrew table
---@param worldX number 世界坐标X
---@param worldY number 世界坐标Y
---@param subY number 潜艇内部Y
---@param subH number 潜艇内部高度
---@return number|nil 被点击的AI索引
function AICrew.HitTest(aiCrew, worldX, worldY, subY, subH)
    local floorY = subY + subH - 8
    local hitRadius = 30  -- 点击判定半径

    for i, ai in ipairs(aiCrew.members) do
        local aiScreenY = floorY - Config.Crew.height * 0.5
        local dx = worldX - ai.x
        local dy = worldY - aiScreenY
        if dx * dx + dy * dy < hitRadius * hitRadius then
            return i
        end
    end
    return nil
end

-- ============================================================
-- 职业能力查询 API
-- ============================================================

--- 获取炮塔精度加成（安全官在武器舱时提供加成）
---@param aiCrew table
---@return number 精度倍率（1.0=无加成）
function AICrew.GetTurretAccuracyBonus(aiCrew)
    local bestBonus = 1.0
    for _, ai in ipairs(aiCrew.members) do
        -- 安全官在武器舱（room 6）时提供加成
        if ai.roomIndex == 6 and ai.profData.turretAccuracy > bestBonus then
            bestBonus = ai.profData.turretAccuracy
        end
    end
    return bestBonus
end

--- 获取驾驶加成（舰长在舰桥时提供加成）
---@param aiCrew table
---@return number 航速加成倍率
function AICrew.GetPilotBonus(aiCrew)
    local bonus = 0
    for _, ai in ipairs(aiCrew.members) do
        -- 舰长/助手在舰桥（room 1）时提供驾驶加成
        if ai.roomIndex == 1 and ai.profData.pilotBonus > 0 then
            bonus = math.max(bonus, ai.profData.pilotBonus)
            ai.isPiloting = true
        else
            if ai.profession == "captain" then
                ai.isPiloting = false
            end
        end
    end
    return 1.0 + bonus
end

--- 医生治疗受伤船员（周期性恢复船体完整度）
---@param aiCrew table
---@param sub table
---@param dt number
function AICrew.UpdateDoctorHeal(aiCrew, sub, dt)
    for _, ai in ipairs(aiCrew.members) do
        if ai.profData.healPower > 0 and ai.state ~= "respond" and ai.state ~= "repair" then
            -- 医生/助手在任何舱室时，缓慢恢复船体
            if sub.hullIntegrity and sub.hullIntegrity < 1.0 then
                sub.hullIntegrity = math.min(1.0, sub.hullIntegrity + ai.profData.healPower * dt * 0.1)
            end
        end
    end
end

--- 获取职业数据表（外部访问用）
function AICrew.GetProfessions()
    return PROFESSIONS
end

--- 获取AI的职业标题
---@param ai table
---@return string
function AICrew.GetProfTitle(ai)
    return ai.profData.title or "船员"
end

return AICrew
