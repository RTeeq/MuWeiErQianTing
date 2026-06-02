--- 联机合作系统
--- 房间管理、投票踢人、断线重连、观战模式、物品交易、救援机制
local Config = require("Config")

local CoopSystem = {}

-- ============================================================
-- 房间管理
-- ============================================================
CoopSystem.ROOM_STATE = {
    WAITING  = "waiting",    -- 等待玩家
    PLAYING  = "playing",    -- 游戏中
    PAUSED   = "paused",     -- 房主暂停
}

--- 创建房间管理状态
---@return table roomState
function CoopSystem.CreateRoom()
    return {
        -- 房间设置
        state = CoopSystem.ROOM_STATE.WAITING,
        password = nil,          -- nil=公开，string=密码房
        difficulty = 1,          -- 难度等级 1~3
        maxPlayers = 4,          -- 最大玩家数 2~4
        hostSlot = 1,            -- 房主槽位（固定为1）

        -- 投票系统
        votes = {},              -- 当前投票 {type, targetSlot, voters={}, startTime, duration}
        voteHistory = {},        -- 投票历史

        -- 断线重连
        disconnected = {},       -- [slot] = {role, state, timestamp, reconnectToken}
        reconnectTimeout = 180,  -- 重连超时（秒）

        -- 暂停
        pauseRequester = nil,
        pauseTimer = 0,
        maxPauseTime = 60,       -- 最大暂停时间（秒）
    }
end

--- 验证房间密码
---@param room table 房间状态
---@param password string|nil 输入的密码
---@return boolean valid
function CoopSystem.ValidatePassword(room, password)
    if room.password == nil then return true end
    return room.password == password
end

--- 设置房间密码
---@param room table 房间状态
---@param password string|nil 密码（nil=公开）
function CoopSystem.SetPassword(room, password)
    room.password = password
end

--- 设置难度
---@param room table 房间状态
---@param difficulty number 难度 1~3
function CoopSystem.SetDifficulty(room, difficulty)
    room.difficulty = math.max(1, math.min(3, difficulty))
end

--- 房主暂停游戏
---@param room table 房间状态
---@param slot number 请求暂停的槽位
---@return boolean success
---@return string|nil reason
function CoopSystem.PauseGame(room, slot)
    if slot ~= room.hostSlot then
        return false, "只有房主可以暂停"
    end
    if room.state ~= CoopSystem.ROOM_STATE.PLAYING then
        return false, "当前无法暂停"
    end
    room.state = CoopSystem.ROOM_STATE.PAUSED
    room.pauseRequester = slot
    room.pauseTimer = 0
    return true, nil
end

--- 房主恢复游戏
---@param room table 房间状态
---@param slot number 请求恢复的槽位
---@return boolean success
function CoopSystem.ResumeGame(room, slot)
    if slot ~= room.hostSlot then return false end
    if room.state ~= CoopSystem.ROOM_STATE.PAUSED then return false end
    room.state = CoopSystem.ROOM_STATE.PLAYING
    room.pauseRequester = nil
    room.pauseTimer = 0
    return true
end

--- 更新暂停计时（超时自动恢复）
---@param room table 房间状态
---@param dt number 时间步长
function CoopSystem.UpdatePause(room, dt)
    if room.state == CoopSystem.ROOM_STATE.PAUSED then
        room.pauseTimer = room.pauseTimer + dt
        if room.pauseTimer >= room.maxPauseTime then
            room.state = CoopSystem.ROOM_STATE.PLAYING
            room.pauseRequester = nil
            room.pauseTimer = 0
        end
    end
end

-- ============================================================
-- 投票系统
-- ============================================================
CoopSystem.VOTE_TYPE = {
    KICK = "kick",           -- 踢出玩家
    PAUSE = "vote_pause",    -- 投票暂停
    DIFFICULTY = "difficulty",-- 投票调难度
}

--- 发起投票
---@param room table 房间状态
---@param initiator number 发起者槽位
---@param voteType string 投票类型
---@param targetSlot number|nil 目标槽位（踢人用）
---@param playerCount number 当前玩家数
---@return boolean success
---@return string|nil reason
function CoopSystem.StartVote(room, initiator, voteType, targetSlot, playerCount)
    -- 已有投票进行中
    if room.votes and room.votes.active then
        return false, "已有投票进行中"
    end

    -- 不能踢房主
    if voteType == CoopSystem.VOTE_TYPE.KICK and targetSlot == room.hostSlot then
        return false, "不能踢出房主"
    end

    -- 2人房不需要投票直接踢
    if playerCount <= 2 and voteType == CoopSystem.VOTE_TYPE.KICK then
        -- 房主可以直接踢
        if initiator == room.hostSlot then
            return true, "direct_kick"
        end
    end

    room.votes = {
        active = true,
        type = voteType,
        targetSlot = targetSlot,
        initiator = initiator,
        voters = { [initiator] = true },  -- 发起者默认同意
        yesCount = 1,
        noCount = 0,
        startTime = 0,
        duration = 20.0,         -- 20秒投票时间
        threshold = math.max(2, math.ceil(playerCount * 0.6)),  -- 60%同意通过
    }

    return true, nil
end

--- 玩家投票
---@param room table 房间状态
---@param slot number 投票者槽位
---@param agree boolean 是否同意
---@return string|nil result "passed"/"rejected"/nil(继续中)
function CoopSystem.CastVote(room, slot, agree)
    local vote = room.votes
    if not vote or not vote.active then return nil end
    if vote.voters[slot] then return nil end  -- 已投过

    vote.voters[slot] = true
    if agree then
        vote.yesCount = vote.yesCount + 1
    else
        vote.noCount = vote.noCount + 1
    end

    -- 检查是否通过
    if vote.yesCount >= vote.threshold then
        vote.active = false
        table.insert(room.voteHistory, {type = vote.type, result = "passed", target = vote.targetSlot})
        return "passed"
    end

    return nil
end

--- 更新投票计时
---@param room table 房间状态
---@param dt number 时间步长
---@return string|nil result "timeout"/nil
function CoopSystem.UpdateVote(room, dt)
    local vote = room.votes
    if not vote or not vote.active then return nil end

    vote.startTime = vote.startTime + dt
    if vote.startTime >= vote.duration then
        -- 超时：如果已超过阈值则通过，否则失败
        vote.active = false
        if vote.yesCount >= vote.threshold then
            table.insert(room.voteHistory, {type = vote.type, result = "passed", target = vote.targetSlot})
            return "passed"
        else
            table.insert(room.voteHistory, {type = vote.type, result = "timeout", target = vote.targetSlot})
            return "timeout"
        end
    end
    return nil
end

-- ============================================================
-- 断线重连
-- ============================================================

--- 记录玩家断线信息（允许3分钟内重连）
---@param room table 房间状态
---@param slot number 断线槽位
---@param playerData table 玩家数据快照
---@param gameTime number 当前游戏时间
---@return string token 重连令牌
function CoopSystem.RecordDisconnect(room, slot, playerData, gameTime)
    local token = string.format("RC_%d_%d_%d", slot, math.floor(gameTime), math.random(10000, 99999))
    room.disconnected[slot] = {
        role = playerData.role,
        room = playerData.room,
        x = playerData.x,
        y = playerData.y,
        facing = playerData.facing,
        timestamp = gameTime,
        token = token,
        inventory = playerData.inventory,  -- 保存物品
    }
    return token
end

--- 尝试重连
---@param room table 房间状态
---@param slot number 槽位
---@param token string 重连令牌
---@param gameTime number 当前游戏时间
---@return boolean success
---@return table|nil savedData 保存的状态
function CoopSystem.TryReconnect(room, slot, token, gameTime)
    local data = room.disconnected[slot]
    if not data then return false, nil end

    -- 检查令牌
    if data.token ~= token then return false, nil end

    -- 检查超时
    if gameTime - data.timestamp > room.reconnectTimeout then
        room.disconnected[slot] = nil
        return false, nil
    end

    -- 重连成功，清除断线记录
    local savedData = {
        role = data.role,
        room = data.room,
        x = data.x,
        y = data.y,
        facing = data.facing,
        inventory = data.inventory,
    }
    room.disconnected[slot] = nil
    return true, savedData
end

--- 清理超时的断线记录
---@param room table 房间状态
---@param gameTime number 当前游戏时间
---@return table removed 被清除的槽位列表
function CoopSystem.CleanupDisconnected(room, gameTime)
    local removed = {}
    for slot, data in pairs(room.disconnected) do
        if gameTime - data.timestamp > room.reconnectTimeout then
            table.insert(removed, slot)
            room.disconnected[slot] = nil
        end
    end
    return removed
end

-- ============================================================
-- 观战系统
-- ============================================================
CoopSystem.SPECTATE_MODE = {
    FOLLOW = "follow",       -- 跟随某个玩家
    FREE   = "free",         -- 自由视角
}

--- 创建观战状态
---@return table spectateState
function CoopSystem.CreateSpectateState()
    return {
        enabled = false,        -- 是否在观战
        mode = CoopSystem.SPECTATE_MODE.FOLLOW,
        followSlot = nil,       -- 跟随的目标槽位
        freeX = 0,              -- 自由视角位置
        freeRoom = 1,           -- 自由视角所在舱室

        -- 提示系统（观战者可发有限消息）
        hintCooldown = 0,       -- 提示冷却时间
        hintInterval = 15.0,    -- 每15秒最多发一条
        hintsRemaining = 5,     -- 每局最多5条提示
    }
end

--- 进入观战模式
---@param spectate table 观战状态
---@param followSlot number|nil 跟随目标
function CoopSystem.EnterSpectate(spectate, followSlot)
    spectate.enabled = true
    spectate.mode = CoopSystem.SPECTATE_MODE.FOLLOW
    spectate.followSlot = followSlot
end

--- 切换观战目标
---@param spectate table 观战状态
---@param targetSlot number 新目标
function CoopSystem.SwitchSpectateTarget(spectate, targetSlot)
    spectate.followSlot = targetSlot
    spectate.mode = CoopSystem.SPECTATE_MODE.FOLLOW
end

--- 切换自由视角
---@param spectate table 观战状态
function CoopSystem.ToggleFreeView(spectate)
    if spectate.mode == CoopSystem.SPECTATE_MODE.FREE then
        spectate.mode = CoopSystem.SPECTATE_MODE.FOLLOW
    else
        spectate.mode = CoopSystem.SPECTATE_MODE.FREE
    end
end

--- 观战者发送提示
---@param spectate table 观战状态
---@param gameTime number 当前时间
---@return boolean canSend
---@return string|nil reason
function CoopSystem.CanSendHint(spectate, gameTime)
    if not spectate.enabled then return false, "未在观战" end
    if spectate.hintsRemaining <= 0 then return false, "提示次数已用尽" end
    if spectate.hintCooldown > 0 then
        return false, string.format("冷却中（%.0f秒）", spectate.hintCooldown)
    end
    return true, nil
end

--- 消耗一次提示
---@param spectate table 观战状态
function CoopSystem.UseHint(spectate)
    spectate.hintsRemaining = spectate.hintsRemaining - 1
    spectate.hintCooldown = spectate.hintInterval
end

--- 更新观战冷却
---@param spectate table 观战状态
---@param dt number 时间步长
function CoopSystem.UpdateSpectate(spectate, dt)
    if spectate.hintCooldown > 0 then
        spectate.hintCooldown = math.max(0, spectate.hintCooldown - dt)
    end
end

-- ============================================================
-- 物品交易
-- ============================================================
CoopSystem.TRADE_STATE = {
    IDLE       = "idle",        -- 无交易
    OFFERED    = "offered",     -- 已提出交易
    PENDING    = "pending",     -- 等待对方确认
    CONFIRMED  = "confirmed",   -- 双方确认
}

--- 创建交易状态
---@return table tradeState
function CoopSystem.CreateTrade()
    return {
        state = CoopSystem.TRADE_STATE.IDLE,
        fromSlot = nil,         -- 发起者
        toSlot = nil,           -- 接收者
        itemId = nil,           -- 交易物品ID
        itemCount = 1,          -- 数量
        timer = 0,              -- 超时计时
        timeout = 15.0,         -- 15秒超时
    }
end

--- 发起物品交易（给予）
---@param trade table 交易状态
---@param fromSlot number 发起者槽位
---@param toSlot number 接收者槽位
---@param itemId string 物品ID
---@param count number 数量
---@return boolean success
---@return string|nil reason
function CoopSystem.OfferItem(trade, fromSlot, toSlot, itemId, count)
    if trade.state ~= CoopSystem.TRADE_STATE.IDLE then
        return false, "已有交易进行中"
    end
    if fromSlot == toSlot then
        return false, "不能和自己交易"
    end

    trade.state = CoopSystem.TRADE_STATE.OFFERED
    trade.fromSlot = fromSlot
    trade.toSlot = toSlot
    trade.itemId = itemId
    trade.itemCount = count or 1
    trade.timer = 0

    return true, nil
end

--- 接受交易
---@param trade table 交易状态
---@param slot number 接受者槽位
---@return boolean success
function CoopSystem.AcceptTrade(trade, slot)
    if trade.state ~= CoopSystem.TRADE_STATE.OFFERED then return false end
    if trade.toSlot ~= slot then return false end

    trade.state = CoopSystem.TRADE_STATE.CONFIRMED
    return true
end

--- 拒绝交易
---@param trade table 交易状态
---@param slot number 拒绝者槽位
function CoopSystem.RejectTrade(trade, slot)
    if trade.toSlot == slot or trade.fromSlot == slot then
        trade.state = CoopSystem.TRADE_STATE.IDLE
        trade.fromSlot = nil
        trade.toSlot = nil
        trade.itemId = nil
    end
end

--- 更新交易超时
---@param trade table 交易状态
---@param dt number 时间步长
---@return boolean timedOut
function CoopSystem.UpdateTrade(trade, dt)
    if trade.state == CoopSystem.TRADE_STATE.OFFERED then
        trade.timer = trade.timer + dt
        if trade.timer >= trade.timeout then
            trade.state = CoopSystem.TRADE_STATE.IDLE
            trade.fromSlot = nil
            trade.toSlot = nil
            trade.itemId = nil
            return true
        end
    end
    return false
end

--- 执行交易（确认后调用）
---@param trade table 交易状态
---@return table|nil result {fromSlot, toSlot, itemId, count}
function CoopSystem.ExecuteTrade(trade)
    if trade.state ~= CoopSystem.TRADE_STATE.CONFIRMED then return nil end

    local result = {
        fromSlot = trade.fromSlot,
        toSlot = trade.toSlot,
        itemId = trade.itemId,
        count = trade.itemCount,
    }

    -- 重置交易
    trade.state = CoopSystem.TRADE_STATE.IDLE
    trade.fromSlot = nil
    trade.toSlot = nil
    trade.itemId = nil
    trade.itemCount = 1
    trade.timer = 0

    return result
end

-- ============================================================
-- 救援系统
-- ============================================================
CoopSystem.RESCUE_STATE = {
    NONE     = "none",       -- 正常
    DOWNED   = "downed",     -- 倒地
    DRAGGING = "dragging",   -- 被拖拽中
    CARRIED  = "carried",    -- 被背起
    DEAD     = "dead",       -- 死亡
}

--- 创建玩家生存状态
---@return table playerHealth
function CoopSystem.CreatePlayerHealth()
    return {
        hp = 100,                -- 血量 0~100
        maxHp = 100,
        state = CoopSystem.RESCUE_STATE.NONE,
        downedTimer = 0,         -- 倒地计时
        downedTimeout = 30.0,    -- 30秒内未救治→死亡
        rescuer = nil,           -- 正在救援的玩家槽位

        -- 被搬运状态
        carriedBy = nil,         -- 被谁背着
        dragggedBy = nil,        -- 被谁拖着

        -- 复活
        reviveProgress = 0,      -- 复活进度 0~1
        reviveDuration = 3.0,    -- 复活需要3秒

        -- 受伤效果
        bleedTimer = 0,          -- 流血计时（留血迹用）
        lastDamageTime = 0,      -- 上次受伤时间
    }
end

--- 对玩家造成伤害
---@param health table 生存状态
---@param damage number 伤害值
---@param gameTime number 当前时间
---@return string|nil event "downed"/"dead"/nil
function CoopSystem.DamagePlayer(health, damage, gameTime)
    if health.state == CoopSystem.RESCUE_STATE.DEAD then return nil end
    if health.state == CoopSystem.RESCUE_STATE.DOWNED then return nil end

    health.hp = math.max(0, health.hp - damage)
    health.lastDamageTime = gameTime
    health.bleedTimer = 5.0  -- 流血5秒

    if health.hp <= 0 then
        health.state = CoopSystem.RESCUE_STATE.DOWNED
        health.downedTimer = 0
        return "downed"
    end
    return nil
end

--- 治疗玩家
---@param health table 生存状态
---@param amount number 治疗量
function CoopSystem.HealPlayer(health, amount)
    if health.state == CoopSystem.RESCUE_STATE.DEAD then return end
    health.hp = math.min(health.maxHp, health.hp + amount)
    -- 如果从倒地恢复
    if health.state == CoopSystem.RESCUE_STATE.DOWNED and health.hp > 20 then
        health.state = CoopSystem.RESCUE_STATE.NONE
        health.downedTimer = 0
        health.rescuer = nil
    end
end

--- 更新倒地计时
---@param health table 生存状态
---@param dt number 时间步长
---@return string|nil event "dead"/nil
function CoopSystem.UpdateDowned(health, dt)
    if health.state ~= CoopSystem.RESCUE_STATE.DOWNED then return nil end

    health.downedTimer = health.downedTimer + dt

    -- 有人在救援时暂停死亡计时
    if health.rescuer then
        health.downedTimer = math.max(0, health.downedTimer - dt * 0.5)
    end

    -- 超时死亡
    if health.downedTimer >= health.downedTimeout then
        health.state = CoopSystem.RESCUE_STATE.DEAD
        return "dead"
    end

    -- 流血减血
    if health.bleedTimer > 0 then
        health.bleedTimer = health.bleedTimer - dt
    end

    return nil
end

--- 开始救援（打强心针/拖拽/背起）
---@param health table 被救者状态
---@param rescuerSlot number 救援者槽位
---@param action string "revive"/"drag"/"carry"
---@return boolean success
---@return string|nil reason
function CoopSystem.StartRescue(health, rescuerSlot, action)
    if health.state ~= CoopSystem.RESCUE_STATE.DOWNED then
        return false, "目标未倒地"
    end

    if action == "revive" then
        health.rescuer = rescuerSlot
        health.reviveProgress = 0
        return true, nil
    elseif action == "drag" then
        health.state = CoopSystem.RESCUE_STATE.DRAGGING
        health.dragggedBy = rescuerSlot
        return true, nil
    elseif action == "carry" then
        health.state = CoopSystem.RESCUE_STATE.CARRIED
        health.carriedBy = rescuerSlot
        return true, nil
    end

    return false, "未知救援动作"
end

--- 更新复活进度
---@param health table 被救者状态
---@param dt number 时间步长
---@param isMedic boolean 救援者是否医官
---@return boolean revived
function CoopSystem.UpdateRevive(health, dt, isMedic)
    if health.state ~= CoopSystem.RESCUE_STATE.DOWNED then return false end
    if not health.rescuer then return false end

    local speed = 1.0
    if isMedic then speed = 2.0 end  -- 医官复活速度翻倍

    health.reviveProgress = health.reviveProgress + (dt / health.reviveDuration) * speed

    if health.reviveProgress >= 1.0 then
        health.state = CoopSystem.RESCUE_STATE.NONE
        health.hp = 30  -- 复活后30%血量
        health.downedTimer = 0
        health.rescuer = nil
        health.reviveProgress = 0
        return true
    end

    return false
end

--- 放下被背/拖的队友
---@param health table 被救者状态
function CoopSystem.DropCarried(health)
    if health.state == CoopSystem.RESCUE_STATE.CARRIED or
       health.state == CoopSystem.RESCUE_STATE.DRAGGING then
        health.state = CoopSystem.RESCUE_STATE.DOWNED
        health.carriedBy = nil
        health.dragggedBy = nil
    end
end

-- ============================================================
-- 分工配合（职业视野限制）
-- ============================================================
CoopSystem.ROLE_VISIBILITY = {
    captain = {
        -- 舰长只能看驾驶舱视野，需要听队友报告
        canSeeExternal = false,  -- 不能直接看外部（通过声呐）
        hasSonarFull = true,     -- 拥有完整声呐
        canSeeCrew = false,      -- 看不到其他舱室船员（除非监控）
    },
    engineer = {
        -- 工程师专注电力和反应堆
        canSeeExternal = false,
        hasSonarFull = false,
        canSeeCrew = true,       -- 可看简要状态
    },
    mechanic = {
        -- 机修工到处跑
        canSeeExternal = true,   -- 通过舷窗偶尔可见
        hasSonarFull = false,
        canSeeCrew = true,
    },
    medic = {
        -- 医生通过监控面板看
        canSeeExternal = false,
        hasSonarFull = false,
        canSeeCrew = true,       -- 医生有监控面板
        hasMonitor = true,       -- 摄像头画面
    },
}

--- 获取职业视野配置
---@param roleId string 职业ID
---@return table|nil visibility
function CoopSystem.GetVisibility(roleId)
    return CoopSystem.ROLE_VISIBILITY[roleId]
end

-- ============================================================
-- 延迟与同步质量
-- ============================================================

--- 创建网络质量监控状态
---@return table netQuality
function CoopSystem.CreateNetQuality()
    return {
        latency = 0,             -- 当前延迟（ms）
        jitter = 0,              -- 抖动（ms）
        packetLoss = 0,          -- 丢包率 (0~1)
        lastPingTime = 0,        -- 上次ping时间
        pingInterval = 1.0,      -- ping间隔（秒）
        samples = {},            -- 最近10次延迟样本
        maxSamples = 10,
        
        -- 状态显示
        qualityLevel = "good",   -- "good"/"fair"/"poor"/"disconnecting"
    }
end

--- 更新网络质量
---@param netQ table 网络质量状态
---@param latencyMs number 最新延迟（毫秒）
function CoopSystem.UpdateNetQuality(netQ, latencyMs)
    -- 添加样本
    table.insert(netQ.samples, latencyMs)
    if #netQ.samples > netQ.maxSamples then
        table.remove(netQ.samples, 1)
    end

    -- 计算平均延迟
    local sum = 0
    for _, s in ipairs(netQ.samples) do sum = sum + s end
    netQ.latency = sum / #netQ.samples

    -- 计算抖动
    if #netQ.samples >= 2 then
        local diffSum = 0
        for i = 2, #netQ.samples do
            diffSum = diffSum + math.abs(netQ.samples[i] - netQ.samples[i-1])
        end
        netQ.jitter = diffSum / (#netQ.samples - 1)
    end

    -- 判定质量等级
    if netQ.latency < 80 and netQ.jitter < 30 then
        netQ.qualityLevel = "good"
    elseif netQ.latency < 150 and netQ.jitter < 60 then
        netQ.qualityLevel = "fair"
    elseif netQ.latency < 300 then
        netQ.qualityLevel = "poor"
    else
        netQ.qualityLevel = "disconnecting"
    end
end

--- 获取质量显示文本
---@param netQ table 网络质量状态
---@return string text
---@return table color {r, g, b}
function CoopSystem.GetQualityDisplay(netQ)
    if netQ.qualityLevel == "good" then
        return "良好", {80, 220, 80}
    elseif netQ.qualityLevel == "fair" then
        return "一般", {220, 200, 50}
    elseif netQ.qualityLevel == "poor" then
        return "连接不稳定", {220, 120, 50}
    else
        return "连接中断", {220, 50, 50}
    end
end

-- ============================================================
-- 位置同步插值
-- ============================================================

--- 创建同步插值缓冲区（客户端用）
---@return table interpBuffer
function CoopSystem.CreateInterpBuffer()
    return {
        positions = {},          -- [{time, x, y, room, facing, animState}]
        maxSize = 10,            -- 最多缓存10帧
        interpDelay = 0.1,       -- 100ms 延迟插值
        lastTime = 0,
    }
end

--- 推入新的同步数据
---@param buf table 插值缓冲区
---@param time number 服务器时间戳
---@param data table {x, y, room, facing, animState}
function CoopSystem.PushInterpData(buf, time, data)
    table.insert(buf.positions, {
        time = time,
        x = data.x,
        y = data.y or 0,
        room = data.room,
        facing = data.facing,
        animState = data.animState,
    })

    -- 移除过旧数据
    while #buf.positions > buf.maxSize do
        table.remove(buf.positions, 1)
    end
    buf.lastTime = time
end

--- 获取插值后的位置
---@param buf table 插值缓冲区
---@param renderTime number 当前渲染时间（服务器时间 - interpDelay）
---@return table|nil interpolated {x, y, room, facing, animState}
function CoopSystem.GetInterpolated(buf, renderTime)
    local positions = buf.positions
    if #positions < 2 then
        return positions[#positions]
    end

    -- 找到合适的两个数据点进行插值
    local targetTime = renderTime - buf.interpDelay
    local p0, p1 = nil, nil

    for i = 2, #positions do
        if positions[i].time >= targetTime then
            p0 = positions[i - 1]
            p1 = positions[i]
            break
        end
    end

    -- 如果没找到合适区间，用最新数据
    if not p0 or not p1 then
        return positions[#positions]
    end

    -- 线性插值
    local dt = p1.time - p0.time
    if dt <= 0 then return p1 end
    local t = math.max(0, math.min(1, (targetTime - p0.time) / dt))

    return {
        x = p0.x + (p1.x - p0.x) * t,
        y = p0.y + (p1.y - p0.y) * t,
        room = p1.room,           -- 房间不插值，取最新
        facing = p1.facing,       -- 朝向取最新
        animState = p1.animState, -- 动画状态取最新
    }
end

return CoopSystem
