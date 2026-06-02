--- 对接系统
--- 潜艇与前哨站/其他潜艇的对接流程管理
--- 包含：对接请求、对齐检测、对接动画、通道管理
local DockingSystem = {}

-- ============================================================
-- 对接阶段枚举
-- ============================================================
DockingSystem.PHASE = {
    IDLE       = "idle",        -- 无对接任务
    APPROACH   = "approach",    -- 接近中，等待请求
    REQUESTED  = "requested",   -- 已发送对接请求，等待对方确认
    ALIGNING   = "aligning",    -- 对方同意，正在对齐
    DOCKING    = "docking",     -- 对齐完成，对接动画播放中
    SEALED     = "sealed",      -- 密封检测中
    CONNECTED  = "connected",   -- 对接完成，通道开放
    UNDOCKING  = "undocking",   -- 断开中
}

-- ============================================================
-- 配置
-- ============================================================
DockingSystem.Config = {
    -- 对接距离
    approachRange = 100,       -- 可发起对接请求的距离（米）
    dockingRange = 30,         -- 必须在此距离内完成对接

    -- 对齐精度要求
    maxDepthDiff = 5.0,        -- 深度差允许范围（米）
    maxAngleDiff = 3.0,        -- 角度差允许范围（度）
    maxSpeed = 2.0,            -- 最大对接速度（米/秒，约1档）

    -- 时间参数
    requestTimeout = 15.0,     -- 对接请求超时（秒）
    dockingDuration = 3.0,     -- 对接动画时长（秒）
    sealCheckDuration = 2.0,   -- 密封检测时长（秒）
    undockDuration = 2.5,      -- 断开动画时长（秒）

    -- 碰撞伤害
    crashSpeedThreshold = 4.0, -- 超过此速度视为碰撞
    crashDamageBase = 20,      -- 碰撞基础伤害

    -- 硬靠（无对接舱时）
    hardDockDamage = 15,       -- 硬靠自身伤害
    hardDockTargetDamage = 10, -- 硬靠对方伤害
}

-- ============================================================
-- 对接状态创建
-- ============================================================

--- 创建对接系统状态
function DockingSystem.Create()
    return {
        -- 当前阶段
        phase = DockingSystem.PHASE.IDLE,

        -- 目标信息
        targetId = nil,          -- 对接目标ID（前哨站或潜艇）
        targetType = nil,        -- "outpost" / "submarine"
        targetName = nil,        -- 对接目标名称
        targetX = 0,             -- 目标X坐标
        targetY = 0,             -- 目标Y坐标（深度）
        targetAngle = 0,         -- 目标对接口角度

        -- 对齐状态
        alignment = {
            depthDiff = 0,       -- 当前深度差（米）
            angleDiff = 0,       -- 当前角度差（度）
            speed = 0,           -- 当前接近速度
            depthOk = false,     -- 深度对齐合格
            angleOk = false,     -- 角度对齐合格
            speedOk = false,     -- 速度合格
            allGreen = false,    -- 全部合格
        },

        -- 计时器
        timer = 0,               -- 当前阶段计时
        requestTimer = 0,        -- 请求超时计时

        -- 通道状态
        passage = {
            isOpen = false,      -- 通道是否开放
            crewInside = {},     -- 通道内的船员列表
        },

        -- 对接口动画
        animProgress = 0,        -- 动画进度 0~1
        lockingClaws = 0,        -- 锁定爪状态 0~1
        passageTube = 0,         -- 通道管伸出进度 0~1
        sealIntegrity = 0,       -- 密封完整度 0~1

        -- 紧急状态
        isEmergency = false,     -- 紧急断开
        forcedUndock = false,    -- 单方面强制断开（会损伤对接舱）

        -- 统计
        totalDockings = 0,       -- 累计对接次数
    }
end

-- ============================================================
-- 核心逻辑
-- ============================================================

--- 检查是否可以发起对接请求
---@param dock table 对接状态
---@param subPhysics table 潜艇物理状态
---@param target table 目标信息 {id, type, name, x, y, angle}
---@return boolean canDock
---@return string|nil reason
function DockingSystem.CanRequestDock(dock, subPhysics, target)
    if dock.phase ~= DockingSystem.PHASE.IDLE then
        return false, "已在对接流程中"
    end

    -- 计算距离
    local dx = target.x - subPhysics.posX
    local dy = target.y - subPhysics.depth
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > DockingSystem.Config.approachRange then
        return false, string.format("距离太远（%.0f米，需<%d米）", dist, DockingSystem.Config.approachRange)
    end

    return true, nil
end

--- 发起对接请求
---@param dock table 对接状态
---@param target table 目标信息 {id, type, name, x, y, angle}
function DockingSystem.RequestDock(dock, target)
    dock.phase = DockingSystem.PHASE.REQUESTED
    dock.targetId = target.id
    dock.targetType = target.type
    dock.targetName = target.name
    dock.targetX = target.x
    dock.targetY = target.y
    dock.targetAngle = target.angle or 0
    dock.requestTimer = 0
    dock.timer = 0
end

--- 对方同意对接
---@param dock table 对接状态
function DockingSystem.AcceptDock(dock)
    if dock.phase ~= DockingSystem.PHASE.REQUESTED then return end
    dock.phase = DockingSystem.PHASE.ALIGNING
    dock.timer = 0
end

--- 对方拒绝对接
---@param dock table 对接状态
---@return string message
function DockingSystem.RejectDock(dock)
    local name = dock.targetName or "目标"
    dock.phase = DockingSystem.PHASE.IDLE
    dock.targetId = nil
    return name .. " 拒绝了对接请求"
end

--- 更新对齐状态
---@param dock table 对接状态
---@param subPhysics table 潜艇物理状态
function DockingSystem.UpdateAlignment(dock, subPhysics)
    if dock.phase ~= DockingSystem.PHASE.ALIGNING then return end

    local cfg = DockingSystem.Config
    local align = dock.alignment

    -- 计算各项差值
    align.depthDiff = math.abs(subPhysics.depth - dock.targetY)
    align.angleDiff = math.abs(subPhysics.heading - dock.targetAngle)
    -- 角度差取最短路径
    if align.angleDiff > 180 then
        align.angleDiff = 360 - align.angleDiff
    end
    align.speed = math.abs(subPhysics.speed)

    -- 检查合格
    align.depthOk = (align.depthDiff <= cfg.maxDepthDiff)
    align.angleOk = (align.angleDiff <= cfg.maxAngleDiff)
    align.speedOk = (align.speed <= cfg.maxSpeed)
    align.allGreen = (align.depthOk and align.angleOk and align.speedOk)
end

--- 开始对接（对齐完成后调用）
---@param dock table 对接状态
---@return boolean success
---@return string|nil message
function DockingSystem.StartDocking(dock)
    if dock.phase ~= DockingSystem.PHASE.ALIGNING then
        return false, "当前阶段无法对接"
    end
    if not dock.alignment.allGreen then
        return false, "对齐精度不足"
    end

    dock.phase = DockingSystem.PHASE.DOCKING
    dock.timer = 0
    dock.animProgress = 0
    dock.lockingClaws = 0
    dock.passageTube = 0
    return true, nil
end

--- 更新对接系统（每帧调用）
---@param dock table 对接状态
---@param subPhysics table 潜艇物理状态
---@param dt number 时间步长
function DockingSystem.Update(dock, subPhysics, dt)
    local cfg = DockingSystem.Config

    -- 请求超时
    if dock.phase == DockingSystem.PHASE.REQUESTED then
        dock.requestTimer = dock.requestTimer + dt
        if dock.requestTimer >= cfg.requestTimeout then
            dock.phase = DockingSystem.PHASE.IDLE
            dock.targetId = nil
            return "timeout"
        end
    end

    -- 对齐阶段
    if dock.phase == DockingSystem.PHASE.ALIGNING then
        DockingSystem.UpdateAlignment(dock, subPhysics)

        -- 检测碰撞（速度过快）
        if subPhysics.speed > cfg.crashSpeedThreshold then
            dock.phase = DockingSystem.PHASE.IDLE
            dock.targetId = nil
            return "crash"
        end
    end

    -- 对接动画
    if dock.phase == DockingSystem.PHASE.DOCKING then
        dock.timer = dock.timer + dt
        dock.animProgress = math.min(1, dock.timer / cfg.dockingDuration)

        -- 动画分段：0~0.4通道管伸出, 0.4~0.8锁定爪, 0.8~1.0确认
        if dock.animProgress <= 0.4 then
            dock.passageTube = dock.animProgress / 0.4
        elseif dock.animProgress <= 0.8 then
            dock.passageTube = 1.0
            dock.lockingClaws = (dock.animProgress - 0.4) / 0.4
        else
            dock.passageTube = 1.0
            dock.lockingClaws = 1.0
        end

        -- 动画完成 → 密封检测
        if dock.animProgress >= 1.0 then
            dock.phase = DockingSystem.PHASE.SEALED
            dock.timer = 0
            dock.sealIntegrity = 0
        end
    end

    -- 密封检测阶段
    if dock.phase == DockingSystem.PHASE.SEALED then
        dock.timer = dock.timer + dt
        dock.sealIntegrity = math.min(1, dock.timer / cfg.sealCheckDuration)

        if dock.sealIntegrity >= 1.0 then
            -- 密封合格 → 连接完成
            dock.phase = DockingSystem.PHASE.CONNECTED
            dock.passage.isOpen = true
            dock.totalDockings = dock.totalDockings + 1
            return "connected"
        end
    end

    -- 断开动画
    if dock.phase == DockingSystem.PHASE.UNDOCKING then
        dock.timer = dock.timer + dt
        dock.animProgress = math.min(1, dock.timer / cfg.undockDuration)

        -- 反向动画
        dock.lockingClaws = math.max(0, 1 - dock.animProgress * 2)
        dock.passageTube = math.max(0, 1 - (dock.animProgress - 0.3) / 0.7)

        if dock.animProgress >= 1.0 then
            dock.phase = DockingSystem.PHASE.IDLE
            dock.targetId = nil
            dock.passage.isOpen = false
            dock.passage.crewInside = {}
            dock.forcedUndock = false
            return "undocked"
        end
    end

    return nil
end

--- 请求断开对接
---@param dock table 对接状态
---@param forced boolean 是否强制（单方面，会损伤）
---@return boolean success
---@return string|nil reason
function DockingSystem.RequestUndock(dock, forced)
    if dock.phase ~= DockingSystem.PHASE.CONNECTED then
        return false, "未处于对接状态"
    end

    -- 检查通道内是否有船员
    if #dock.passage.crewInside > 0 and not forced then
        return false, "通道内有船员，无法断开！（可强制断开）"
    end

    dock.phase = DockingSystem.PHASE.UNDOCKING
    dock.timer = 0
    dock.animProgress = 0
    dock.passage.isOpen = false
    dock.forcedUndock = forced or false

    return true, nil
end

--- 关闭通道（紧急隔离，不断开对接）
---@param dock table 对接状态
function DockingSystem.ClosePassage(dock)
    if dock.phase == DockingSystem.PHASE.CONNECTED then
        dock.passage.isOpen = false
    end
end

--- 重开通道
---@param dock table 对接状态
function DockingSystem.OpenPassage(dock)
    if dock.phase == DockingSystem.PHASE.CONNECTED then
        dock.passage.isOpen = true
    end
end

--- 硬靠（无对接舱时的紧急停靠）
---@param dock table 对接状态
---@param target table 目标信息
---@return number selfDamage 己方伤害
---@return number targetDamage 对方伤害
function DockingSystem.HardDock(dock, target)
    local cfg = DockingSystem.Config
    dock.phase = DockingSystem.PHASE.CONNECTED
    dock.targetId = target.id
    dock.targetType = target.type
    dock.targetName = target.name
    dock.targetX = target.x
    dock.targetY = target.y
    dock.passage.isOpen = false  -- 硬靠无通道，需EVA出舱

    return cfg.hardDockDamage, cfg.hardDockTargetDamage
end

--- 取消对接请求
---@param dock table 对接状态
function DockingSystem.CancelRequest(dock)
    if dock.phase == DockingSystem.PHASE.REQUESTED then
        dock.phase = DockingSystem.PHASE.IDLE
        dock.targetId = nil
    end
end

--- 获取对接进度文本
---@param dock table 对接状态
---@return string text
function DockingSystem.GetStatusText(dock)
    local phase = dock.phase
    if phase == DockingSystem.PHASE.IDLE then
        return "未对接"
    elseif phase == DockingSystem.PHASE.REQUESTED then
        return "等待 " .. (dock.targetName or "目标") .. " 确认..."
    elseif phase == DockingSystem.PHASE.ALIGNING then
        local a = dock.alignment
        return string.format("对齐中 深度差:%.1fm 角度差:%.1f° 速度:%.1fm/s",
            a.depthDiff, a.angleDiff, a.speed)
    elseif phase == DockingSystem.PHASE.DOCKING then
        return string.format("对接中... %d%%", math.floor(dock.animProgress * 100))
    elseif phase == DockingSystem.PHASE.SEALED then
        return string.format("密封检测... %d%%", math.floor(dock.sealIntegrity * 100))
    elseif phase == DockingSystem.PHASE.CONNECTED then
        local passageState = dock.passage.isOpen and "通道开放" or "通道关闭"
        return "已对接 [" .. (dock.targetName or "") .. "] " .. passageState
    elseif phase == DockingSystem.PHASE.UNDOCKING then
        return string.format("断开中... %d%%", math.floor(dock.animProgress * 100))
    end
    return ""
end

--- 检查指定位置附近是否有可对接目标
---@param subPhysics table 潜艇物理状态
---@param outposts table[] 前哨站列表
---@return table|nil nearestTarget
function DockingSystem.FindNearestDockable(subPhysics, outposts)
    local cfg = DockingSystem.Config
    local nearest = nil
    local nearestDist = cfg.approachRange + 1

    for _, op in ipairs(outposts) do
        local dx = op.x - subPhysics.posX
        local dy = op.depth - subPhysics.depth
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < nearestDist then
            nearest = {
                id = op.id,
                type = "outpost",
                name = op.name,
                x = op.x,
                y = op.depth,
                angle = op.dockAngle or 0,
                distance = dist,
            }
            nearestDist = dist
        end
    end

    return nearest
end

return DockingSystem
