--- 潜艇深海生存 - 服务端
--- 运行全部游戏逻辑，通过 Remote Events 广播状态快照

local Shared = require("network.Shared")
local Config = require("Config")
local Submarine = require("Submarine")
local CrisisManager = require("CrisisManager")
local AICrew = require("AICrew")
local MonsterManager = require("MonsterManager")
local TurretSystem = require("TurretSystem")
local PowerSystem = require("PowerSystem")
local Inventory = require("Inventory")
local Crafting = require("Crafting")
local GameState = require("GameState")
local PortScene = require("PortScene")
local MissionSystem = require("MissionSystem")
local EVASystem = require("EVASystem")
local RuinsGenerator = require("RuinsGenerator")
local CoopSystem = require("CoopSystem")
local QuickCommands = require("QuickCommands")
local cjson = require("cjson")

require "LuaScripts/Utilities/Sample"

local Server = {}

-- ============================================================
-- 服务端状态
-- ============================================================
local scene_ = nil

-- 玩家管理
local MAX_PLAYERS = 4
local players_ = {}          -- [slot 1..4] = playerInfo | nil
local connections_ = {}      -- [connKey] = slot
local connObjects_ = {}      -- [connKey] = Connection object
local readyCount_ = 0
local gameStarted_ = false

-- 游戏数据（从原 main.lua 迁移）
local sub = nil
local crisis = nil
local aiCrew = nil
local monsterMgr = nil
local turret = nil
local powerSys = nil
local inventory = nil
local gameState = nil
local portScene = nil
local gameTime = 0
local currentDepth = 2400

-- EVA：每个玩家独立状态
local evaStates_ = {}        -- [slot] = {eva, world}

-- 合作系统状态
local coopRoom_ = nil            -- CoopSystem 房间管理
local coopTrade_ = nil           -- 当前交易
local coopHealth_ = {}           -- [slot] = 玩家生存状态
local coopSpectators_ = {}       -- [slot] = 观战状态
local reconnectTokens_ = {}      -- [connKey] = {slot, token} 重连令牌

-- 快照计时
local snapshotTimer_ = 0
local SNAPSHOT_INTERVAL = 1.0 / 20.0   -- 20Hz

-- 大厅计时
local lobbyTimer_ = 0
local LOBBY_TIMEOUT = 35.0   -- 35秒后AI补位开始

-- ============================================================
-- 入口
-- ============================================================
function Server.Start()
    SampleStart()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    Shared.RegisterEvents()

    -- 初始化游戏数据
    gameState = GameState.Create()
    portScene = PortScene.Create()
    sub = Submarine.Init()
    crisis = CrisisManager.Create()
    aiCrew = AICrew.Create(sub)
    monsterMgr = MonsterManager.Create()
    turret = TurretSystem.Create()
    powerSys = PowerSystem.Create()
    inventory = Inventory.Create()

    -- 初始化玩家槽位
    for i = 1, MAX_PLAYERS do
        players_[i] = nil
        evaStates_[i] = { eva = EVASystem.Create(), world = nil }
    end

    -- 初始化合作系统
    coopRoom_ = CoopSystem.CreateRoom()
    coopTrade_ = CoopSystem.CreateTrade()
    for i = 1, MAX_PLAYERS do
        coopHealth_[i] = CoopSystem.CreatePlayerHealth()
        coopSpectators_[i] = CoopSystem.CreateSpectateState()
    end

    -- 订阅网络事件
    SubscribeToEvent("ClientConnected",    "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleClientReady")
    SubscribeToEvent(Shared.EVENTS.SELECT_ROLE,  "HandleSelectRole")
    SubscribeToEvent(Shared.EVENTS.FORCE_START,  "HandleForceStart")
    SubscribeToEvent(Shared.EVENTS.PORT_ACTION,  "HandlePortAction")
    SubscribeToEvent(Shared.EVENTS.EVA_START,    "HandleEvaStart")
    SubscribeToEvent(Shared.EVENTS.EVA_PICKUP,   "HandleEvaPickup")
    SubscribeToEvent(Shared.EVENTS.USE_ITEM,     "HandleUseItem")
    SubscribeToEvent(Shared.EVENTS.CRAFT_ITEM,   "HandleCraftItem")
    SubscribeToEvent(Shared.EVENTS.COMMAND_AI,   "HandleCommandAI")
    SubscribeToEvent(Shared.EVENTS.PICKUP_SCRAP, "HandlePickupScrap")
    SubscribeToEvent(Shared.EVENTS.TOGGLE_INVENTORY, "HandleToggleInventory")
    -- 合作系统事件
    SubscribeToEvent(Shared.EVENTS.QUICK_COMMAND,  "HandleQuickCommand")
    SubscribeToEvent(Shared.EVENTS.TRADE_OFFER,    "HandleTradeOffer")
    SubscribeToEvent(Shared.EVENTS.TRADE_RESPOND,  "HandleTradeRespond")
    SubscribeToEvent(Shared.EVENTS.RESCUE_ACTION,  "HandleRescueAction")
    SubscribeToEvent(Shared.EVENTS.VOTE_START,     "HandleVoteStart")
    SubscribeToEvent(Shared.EVENTS.VOTE_CAST,      "HandleVoteCast")
    SubscribeToEvent(Shared.EVENTS.ROOM_SETTINGS,  "HandleRoomSettings")
    SubscribeToEvent(Shared.EVENTS.RECONNECT,      "HandleReconnect")
    SubscribeToEvent(Shared.EVENTS.SPECTATE_SWITCH,"HandleSpectateSwitch")
    SubscribeToEvent(Shared.EVENTS.SPECTATE_HINT,  "HandleSpectateHint")
    SubscribeToEvent(Shared.EVENTS.NET_PING,       "HandleNetPing")
    SubscribeToEvent(Shared.EVENTS.PAUSE_GAME,     "HandlePauseGame")
    SubscribeToEvent(Shared.EVENTS.RESUME_GAME,    "HandleResumeGame")

    -- 游戏循环
    SubscribeToEvent("Update", "HandleUpdate")

    print("[Server] Submarine Co-op Server started, waiting for players...")
end

function Server.Stop()
    print("[Server] Shutting down")
end

-- ============================================================
-- 连接管理
-- ============================================================

function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    print("[Server] Client connected: " .. (connKey or "unknown"))
    -- 不做任何操作，等 CLIENT_READY
end

function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    if not connKey then return end

    connection.scene = scene_

    -- 设置可靠按键掩码
    connection:SetPulseButtonMask(Shared.PULSE_MASK)

    local slot = nil

    if gameStarted_ then
        -- 游戏已开始：接管一个AI槽位
        slot = FindAISlot()
        if not slot then
            print("[Server] No AI slot available, rejecting: " .. connKey)
            connection:Disconnect()
            return
        end
        -- 接管AI槽位
        players_[slot].connKey = connKey
        players_[slot].isAI = false
        print(string.format("[Server] Player took over AI slot %d (role: %s)", slot, players_[slot].role or "?"))
    else
        -- 大厅阶段：分配空槽位
        slot = FindFreeSlot()
        if not slot then
            print("[Server] Server full, rejecting: " .. connKey)
            connection:Disconnect()
            return
        end
        players_[slot] = {
            connKey = connKey,
            role = nil,          -- 未选职业
            ready = false,
            inEVA = false,
            room = 1,            -- 当前舱室
            x = 100,             -- 舱内X位置
            y = 0,               -- 舱内Y偏移（0=地面）
            vx = 0,              -- X速度
            vy = 0,              -- Y速度（向上为负）
            facing = 1,          -- 朝向（1=右，-1=左）
            animState = "idle",  -- 动画状态
            onGround = true,     -- 是否在地面
            isStunned = false,   -- 是否摔倒
            stunTimer = 0,       -- 摔倒恢复计时
            isGrabbing = false,  -- 是否抓握扶手/梯子
            inWater = false,     -- 是否在水中
        }
    end

    connections_[connKey] = slot
    connObjects_[connKey] = connection
    readyCount_ = readyCount_ + 1

    print(string.format("[Server] Player assigned slot %d, total: %d", slot, readyCount_))

    -- 通知该玩家分配结果
    local data = VariantMap()
    data["Slot"] = Variant(slot)
    data["Roles"] = Variant(cjson.encode(GetRoleStatus()))
    connection:SendRemoteEvent(Shared.EVENTS.ASSIGN_ROLE, true, data)

    -- 如果游戏已开始，也发送GAME_START让客户端进入游戏
    if gameStarted_ then
        local startData = VariantMap()
        startData["Phase"] = Variant(gameState.currentScene == GameState.SCENE_PORT and Shared.PHASE.PORT or Shared.PHASE.DEEP_SEA)
        connection:SendRemoteEvent(Shared.EVENTS.GAME_START, true, startData)
    end

    -- 通知所有人有人加入
    BroadcastPlayerJoined(slot)
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    if not connKey then return end

    local slot = connections_[connKey]
    if slot then
        local player = players_[slot]
        local roleName = player and player.role or "unassigned"
        print(string.format("[Server] Player slot %d (%s) disconnected", slot, roleName))

        -- 生成重连令牌（3分钟有效）
        if gameStarted_ and player and player.role then
            local token = CoopSystem.RecordDisconnect(coopRoom_, slot, player, gameTime)
            reconnectTokens_[token] = { slot = slot, connKey = connKey }
            print(string.format("[Server] Reconnect token generated for slot %d, valid 180s", slot))
        end

        -- 转为AI控制（保留职业）
        if player and player.role then
            player.connKey = nil  -- 标记为AI控制
            player.isAI = true
        else
            players_[slot] = nil
        end

        connections_[connKey] = nil
        connObjects_[connKey] = nil
        readyCount_ = math.max(0, readyCount_ - 1)

        -- 广播离开
        local data = VariantMap()
        data["Slot"] = Variant(slot)
        network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_LEFT, true, data)
    end
end

-- ============================================================
-- 职业选择
-- ============================================================

function HandleSelectRole(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local roleId = eventData["RoleId"]:GetString()

    -- 检查职业是否已被其他人选
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].role == roleId and i ~= slot then
            -- 职业被占，通知该客户端
            local data = VariantMap()
            data["Success"] = Variant(false)
            data["Reason"] = Variant("already_taken")
            connection:SendRemoteEvent(Shared.EVENTS.ROLE_LOCKED, true, data)
            return
        end
    end

    -- 分配成功
    players_[slot].role = roleId
    players_[slot].ready = true
    print(string.format("[Server] Slot %d selected role: %s", slot, roleId))

    -- 广播职业状态更新
    local data = VariantMap()
    data["Roles"] = Variant(cjson.encode(GetRoleStatus()))
    network:BroadcastRemoteEvent(Shared.EVENTS.ROLE_LOCKED, true, data)

    -- 检查是否全部就绪
    CheckAllReady()
end

--- 房主强制开始游戏
function HandleForceStart(eventType, eventData)
    if gameStarted_ then return end

    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]

    -- 只有房主（slot 1）可以强制开始
    if slot ~= 1 then
        print("[Server] Non-host tried to force start, ignored")
        return
    end

    print("[Server] Host forced game start!")
    AutoAssignRoles()
    StartGame()
end

--- 获取职业选择状态
function GetRoleStatus()
    local status = {}
    for i = 1, MAX_PLAYERS do
        if players_[i] then
            status[i] = { slot = i, role = players_[i].role, ready = players_[i].ready }
        end
    end
    return status
end

--- 检查是否可以开始游戏
function CheckAllReady()
    if gameStarted_ then return end

    local allReady = true
    local playerCount = 0
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].connKey then
            playerCount = playerCount + 1
            if not players_[i].ready or not players_[i].role then
                allReady = false
            end
        end
    end

    if playerCount >= 2 and allReady then
        StartGame()
    end
end

-- ============================================================
-- 游戏开始
-- ============================================================

function StartGame()
    gameStarted_ = true
    gameState.currentScene = GameState.SCENE_PORT

    -- AI补位空缺职业
    FillAISlots()

    -- 广播游戏开始
    local data = VariantMap()
    data["Phase"] = Variant(Shared.PHASE.PORT)
    network:BroadcastRemoteEvent(Shared.EVENTS.GAME_START, true, data)

    print("[Server] Game started! Players: " .. GetActivePlayerCount())
end

function FillAISlots()
    local usedRoles = {}
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].role then
            usedRoles[players_[i].role] = true
        end
    end

    -- 为空槽位分配AI
    for _, roleDef in ipairs(Shared.ROLES) do
        if not usedRoles[roleDef.id] then
            -- 找一个空槽
            local freeSlot = FindFreeSlot()
            if freeSlot then
                players_[freeSlot] = {
                    connKey = nil,
                    role = roleDef.id,
                    ready = true,
                    isAI = true,
                    inEVA = false,
                    room = 1,
                    x = 100 + freeSlot * 60,
                    y = 0,
                    vx = 0,
                    vy = 0,
                    facing = 1,
                    animState = "idle",
                    onGround = true,
                    isStunned = false,
                    stunTimer = 0,
                    isGrabbing = false,
                    inWater = false,
                }
            end
        end
    end
end

-- ============================================================
-- 游戏主循环
-- ============================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    gameTime = gameTime + dt

    -- 大厅阶段：等待玩家 + 超时
    if not gameStarted_ then
        lobbyTimer_ = lobbyTimer_ + dt
        if readyCount_ >= 1 and lobbyTimer_ >= LOBBY_TIMEOUT then
            -- 超时，给未选职业的玩家随机分配
            AutoAssignRoles()
            StartGame()
        end
        -- 大厅阶段也定期发快照（职业状态）
        snapshotTimer_ = snapshotTimer_ + dt
        if snapshotTimer_ >= 0.5 then
            snapshotTimer_ = 0
            BroadcastLobbyState()
        end
        return
    end

    -- 场景切换中
    if gameState.transition.active then
        local completed = GameState.UpdateTransition(gameState, dt)
        if completed then
            if gameState.currentScene == GameState.SCENE_DEEP_SEA then
                InitDeepSea()
            else
                SettleReturn()
            end
        end
        BroadcastSnapshot(dt)
        return
    end

    -- 合作系统更新
    if coopRoom_ then
        CoopSystem.UpdatePause(coopRoom_, dt)
        CoopSystem.UpdateVote(coopRoom_, dt)
        CoopSystem.CleanupDisconnected(coopRoom_, gameTime)
    end
    if coopTrade_ then
        local expired = CoopSystem.UpdateTrade(coopTrade_, dt)
        if expired then
            -- 交易超时，通知双方
            BroadcastTradeResult(coopTrade_.from, coopTrade_.to, "timeout")
            coopTrade_ = CoopSystem.CreateTrade()
        end
    end
    for i = 1, MAX_PLAYERS do
        if coopHealth_[i] then
            local died = CoopSystem.UpdateDowned(coopHealth_[i], dt)
            if died then
                -- 玩家死亡，进入观战
                coopSpectators_[i] = CoopSystem.CreateSpectateState()
                CoopSystem.EnterSpectate(coopSpectators_[i], i)
                -- 广播死亡事件
                local data = VariantMap()
                data["Slot"] = Variant(i)
                network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_DEAD, true, data)
                print(string.format("[Server] Player slot %d died, entering spectate", i))
            end
        end
    end

    -- 暂停检测
    if coopRoom_ and coopRoom_.isPaused then
        -- 暂停时不更新游戏逻辑，只广播快照
        snapshotTimer_ = snapshotTimer_ + dt
        if snapshotTimer_ >= SNAPSHOT_INTERVAL then
            snapshotTimer_ = 0
            BroadcastSnapshot(dt)
        end
        return
    end

    -- 根据场景分发
    if gameState.currentScene == GameState.SCENE_PORT then
        UpdatePort(dt)
    else
        UpdateDeepSea(dt)
    end

    -- 快照广播
    snapshotTimer_ = snapshotTimer_ + dt
    if snapshotTimer_ >= SNAPSHOT_INTERVAL then
        snapshotTimer_ = 0
        BroadcastSnapshot(dt)
    end
end

-- ============================================================
-- 港口更新
-- ============================================================

function UpdatePort(dt)
    PortScene.Update(portScene, dt)

    -- 港口中玩家角色移动（摇杆输入，含惯性）
    for i = 1, MAX_PLAYERS do
        local player = players_[i]
        if not player then goto continue_port_player end

        local buttons, yaw, pitch = GetPlayerInput(i)
        -- 港口使用简化物理（无跳跃/水）
        UpdatePlayerPhysics(i, buttons, yaw, dt)

        ::continue_port_player::
    end
end

function HandlePortAction(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local action = eventData["Action"]:GetString()
    local player = players_[slot]
    local role = player.role

    if action == "depart" then
        -- 任何玩家都可以发起出港
        local ok, err = GameState.Depart(gameState)
        if not ok then
            -- 通知出港失败
            local data = VariantMap()
            data["Error"] = Variant(err or "unknown")
            connection:SendRemoteEvent(Shared.EVENTS.PORT_ACTION, true, data)
        end
    elseif action == "buy" then
        -- 工程师购买设备
        if role == "engineer" or role == "captain" then
            PortScene.BuyItem(portScene, gameState)
        end
    elseif action == "upgrade" then
        -- 技工升级
        if role == "mechanic" or role == "captain" then
            PortScene.UpgradeSub(portScene, gameState)
        end
    elseif action == "mission" then
        -- 接取任务
        if role == "captain" then
            local idx = eventData["Index"]:GetInt()
            local missions = MissionSystem.GenerateMissions(gameState.reputation)
            if missions and idx >= 1 and idx <= #missions then
                if gameState.currentMission then
                    -- 已有任务
                else
                    gameState.currentMission = missions[idx]
                    print("[Server] Mission accepted: " .. missions[idx].title)
                end
            end
        end
    elseif action == "abandon_mission" then
        -- 放弃当前任务
        if role == "captain" and gameState.currentMission then
            print("[Server] Mission abandoned: " .. gameState.currentMission.title)
            gameState.currentMission = nil
        end
    elseif action == "select_item" then
        -- 直接选中列表项（点击）
        local idx = eventData["Index"]:GetInt()
        local maxItems = PortScene.GetMaxItems(portScene)
        if idx >= 1 and idx <= maxItems then
            portScene.selectedItem = idx
        end
    elseif action == "confirm" then
        -- 通用确认（点击已选中的列表项执行操作）
        if portScene.currentTab == PortScene.TAB_MISSION then
            -- 任何角色都可以接取任务
            local missions = MissionSystem.GenerateMissions(gameState.reputation)
            if missions and portScene.selectedItem >= 1 and portScene.selectedItem <= #missions then
                if gameState.currentMission then
                    -- 已有任务
                else
                    gameState.currentMission = missions[portScene.selectedItem]
                    print("[Server] Mission accepted: " .. gameState.currentMission.title)
                end
            end
        elseif portScene.currentTab == PortScene.TAB_SHOP then
            if role == "engineer" or role == "captain" then
                PortScene.BuyItem(portScene, gameState)
            end
        elseif portScene.currentTab == PortScene.TAB_UPGRADE then
            if role == "mechanic" or role == "captain" then
                PortScene.UpgradeSub(portScene, gameState)
            end
        end
    elseif action == "tab" then
        local tab = eventData["Tab"]:GetInt()
        PortScene.SwitchTab(portScene, tab)
    elseif action == "select" then
        local dir = eventData["Dir"]:GetInt()
        if dir > 0 then PortScene.SelectNext(portScene)
        else PortScene.SelectPrev(portScene) end
    end
end

-- ============================================================
-- 深海更新
-- ============================================================

function InitDeepSea()
    sub = Submarine.Init()
    crisis = CrisisManager.Create()
    aiCrew = AICrew.Create(sub)
    monsterMgr = MonsterManager.Create()
    turret = TurretSystem.Create()
    powerSys = PowerSystem.Create()
    inventory = Inventory.Create()
    currentDepth = 2400

    -- 重置所有EVA状态
    for i = 1, MAX_PLAYERS do
        evaStates_[i] = { eva = EVASystem.Create(), world = nil }
    end

    -- 将补给注入
    local supplies = GameState.GetSuppliesForMission(gameState)
    for id, count in pairs(supplies) do
        if inventory.products[id] then
            inventory.products[id] = count
        end
    end

    print("[Server] Deep sea mission started!")
end

function SettleReturn()
    local result = GameState.SettleMission(gameState)
    print("[Server] Returned to port. Mission: " .. (result and "settled" or "none"))
end

function UpdateDeepSea(dt)
    if sub == nil then return end

    -- ====== 读取各玩家输入 ======
    local captainJx = 0
    local engineerEff = 1.0

    for i = 1, MAX_PLAYERS do
        local player = players_[i]
        if not player then goto continue_player end

        if player.inEVA then
            -- EVA独立更新
            UpdatePlayerEVA(i, dt)
            goto continue_player
        end

        -- 获取该玩家输入
        local buttons, yaw, pitch = GetPlayerInput(i)

        -- 船长驾驶控制
        if player.role == "captain" then
            -- yaw 作为舵盘角度输入（-90~+90）
            local helmInput = math.max(-90, math.min(90, yaw))
            -- 也可用按钮做离散控制
            if buttons & Shared.CTRL.LEFT ~= 0 then helmInput = -45 end
            if buttons & Shared.CTRL.RIGHT ~= 0 then helmInput = 45 end
            captainJx = helmInput  -- 复用变量存舵角

            -- 油门升降档
            if buttons & Shared.CTRL.THROTTLE_UP ~= 0 then
                Submarine.ThrottleUp(sub)
            end
            if buttons & Shared.CTRL.THROTTLE_DOWN ~= 0 then
                Submarine.ThrottleDown(sub)
            end

            -- 深度控制：pitch 作为目标深度归一化值（0~1）
            if pitch and pitch > 0 then
                local depthCfg = Config.Driving.depth
                local targetD = depthCfg.minDepth + pitch * (depthCfg.maxDepth - depthCfg.minDepth)
                Submarine.SetTargetDepth(sub, targetD)
            end

            -- 声呐脉冲
            if buttons & Shared.CTRL.SONAR_PULSE ~= 0 then
                -- 生成周围目标（怪物+地形特征）
                local targets = MonsterManager.GetSonarTargets(monsterMgr, sub.physics.posX, sub.physics.posY, Config.Sonar.pulseRange)
                Submarine.SonarPulse(sub, targets)
                -- 声呐脉冲增加危机触发概率
                CrisisManager.OnSonarPulse(crisis)
            end

            -- 探照灯开关
            if buttons & Shared.CTRL.SEARCHLIGHT ~= 0 then
                Submarine.ToggleSearchlight(sub)
            end
        end

        -- 工程师影响引擎效率
        if player.role == "engineer" then
            engineerEff = Shared.ROLE_BONUS.engineer.engineEff

            -- 反应堆面板开关（POWER_TOGGLE 键双用途）
            if buttons & Shared.CTRL.POWER_TOGGLE ~= 0 then
                -- 如果反应堆面板开着，再按一次关闭反应堆面板
                if sub.reactor.panelOpen then
                    Submarine.ToggleReactorPanel(sub)
                else
                    -- 否则切换电力面板
                    PowerSystem.TogglePanel(powerSys)
                end
            end

            -- 上下左右按钮：根据面板状态路由
            if sub.reactor.panelOpen then
                -- 反应堆面板：INC/DEC 调节输出
                if buttons & Shared.CTRL.POWER_INC ~= 0 then
                    Submarine.ReactorAdjustOutput(sub, Config.Reactor.outputStep)
                end
                if buttons & Shared.CTRL.POWER_DEC ~= 0 then
                    Submarine.ReactorAdjustOutput(sub, -Config.Reactor.outputStep)
                end
                -- UP=冷却脉冲 / 启动（反应堆关闭时）
                if buttons & Shared.CTRL.POWER_UP ~= 0 then
                    if sub.reactor.state == "off" then
                        Submarine.ReactorStartup(sub)
                    else
                        Submarine.ReactorCoolPulse(sub)
                    end
                end
                -- DOWN=长按关机（持续按住传入dt）
                if buttons & Shared.CTRL.POWER_DOWN ~= 0 then
                    Submarine.ReactorShutdownHold(sub, dt)
                else
                    -- 松手时检查是否需要重置
                    if sub.reactor.shutdownHoldProgress > 0 then
                        Submarine.ReactorShutdownRelease(sub)
                    end
                end
            else
                -- 电力面板：选择系统 + 调节优先级
                if buttons & Shared.CTRL.POWER_UP ~= 0 then
                    PowerSystem.SelectPrev(powerSys)
                end
                if buttons & Shared.CTRL.POWER_DOWN ~= 0 then
                    PowerSystem.SelectNext(powerSys)
                end
                if buttons & Shared.CTRL.POWER_INC ~= 0 then
                    PowerSystem.MovePriorityUp(powerSys)
                end
                if buttons & Shared.CTRL.POWER_DEC ~= 0 then
                    PowerSystem.MovePriorityDown(powerSys)
                end
            end
        end

        -- 玩家位置（多处用到，提前计算）
        local playerX = player.x or 0
        local playerRoom = player.room or 1

        -- 所有人：修复（技工加成）
        if buttons & Shared.CTRL.REPAIR ~= 0 then
            local repairDt = dt
            if player.role == "mechanic" then
                repairDt = dt * Shared.ROLE_BONUS.mechanic.repairSpeed
            end

            -- 优先检查附近断线缆修复
            local nearJBox = Submarine.GetNearbyJunctionBox(sub, playerRoom, playerX, Config.Wiring.interactRange)
            local repairedCable = false
            if nearJBox then
                local severed = Submarine.GetSeveredCablesAtJBox(sub, nearJBox)
                if #severed > 0 then
                    Submarine.StartCableRepair(sub, severed[1])
                    repairedCable = true
                end
            end

            -- 没有断线缆则修复危机
            if not repairedCable then
                local roomCrisis = CrisisManager.GetCrisisInRoom(crisis, player.room)
                if roomCrisis then
                    CrisisManager.DoRepair(crisis, sub, player.room, repairDt, player.role)
                end
            end
        else
            -- 松手时停止线缆修复
            for ci, cable in ipairs(sub.wiring.cables) do
                if cable.repairing then
                    Submarine.StopCableRepair(sub, ci)
                end
            end
            -- 松手时停止危机修复
            CrisisManager.StopRepair(crisis, player.room)
        end

        -- 所有人：射击（各自炮塔）
        if buttons & Shared.CTRL.SHOOT ~= 0 then
            if player.room == 6 then  -- 在炮塔舱
                TurretSystem.Fire(turret or TurretSystem.Create(), 1.0)
            end
        end

        -- G键：进入EVA（货舱）
        if buttons & Shared.CTRL.EVA_EXIT ~= 0 then
            if player.room == 4 and not player.inEVA then
                StartPlayerEVA(i)
            end
        end

        -- ESC：返回港口（船长才能操作）
        if buttons & Shared.CTRL.ESCAPE ~= 0 then
            if player.role == "captain" then
                GameState.ReturnToPort(gameState)
            end
        end

        -- 物品栏/合成操作（通过按钮位触发）
        if buttons & Shared.CTRL.INVENTORY ~= 0 then
            if inventory then Inventory.TogglePanel(inventory) end
        end
        if buttons & Shared.CTRL.CRAFT_PREV ~= 0 then
            -- 客户端维护 selectedRecipe 的本地状态，服务端不需处理
        end
        if buttons & Shared.CTRL.CRAFT_NEXT ~= 0 then
            -- 客户端维护 selectedRecipe 的本地状态，服务端不需处理
        end
        if buttons & Shared.CTRL.CRAFT_CONFIRM ~= 0 then
            -- 合成在远程事件 CRAFT_ITEM 中处理（带 recipeIdx 参数）
        end

        -- F键交互（多功能：拾取/反应堆面板）
        if buttons & Shared.CTRL.INTERACT ~= 0 then
            if not player.inEVA then
                -- 工程师在反应堆舱（房间2-机舱）可打开反应堆面板
                if player.role == "engineer" and playerRoom == 2 then
                    Submarine.ToggleReactorPanel(sub)
                elseif inventory then
                    Inventory.PickupNearScrap(inventory)
                end
            end
        end

        -- ====== 门/舷窗/水泵交互 ======

        -- 开门/关门
        if buttons & Shared.CTRL.DOOR_OPEN ~= 0 then
            local doorIdx = Submarine.GetNearbyDoor(sub, playerX, Config.Door.interactRange)
            if doorIdx then
                local door = sub.doors[doorIdx]
                if door.state == "open" then
                    Submarine.CloseDoor(sub, doorIdx)
                elseif door.state == "closed" then
                    local ok, reason = Submarine.TryOpenDoor(sub, doorIdx)
                    if not ok then
                        player.doorMsg = reason  -- 存储失败消息供客户端显示
                        player.doorMsgTimer = 2.0
                    end
                end
            end
        end

        -- 锁门/解锁
        if buttons & Shared.CTRL.DOOR_LOCK ~= 0 then
            local doorIdx = Submarine.GetNearbyDoor(sub, playerX, Config.Door.interactRange)
            if doorIdx then
                Submarine.ToggleDoorLock(sub, doorIdx)
            end
        end

        -- 手动气压平衡（长按：PRESSURE_BAL 不在 PULSE_MASK 中，持续传输）
        if buttons & Shared.CTRL.PRESSURE_BAL ~= 0 then
            local doorIdx = Submarine.GetNearbyDoor(sub, playerX, Config.Door.interactRange)
            if doorIdx then
                local door = sub.doors[doorIdx]
                if not door.balancing then
                    Submarine.StartPressureBalance(sub, doorIdx)
                end
            end
        else
            -- 松手时停止平衡
            local doorIdx = Submarine.GetNearbyDoor(sub, playerX, Config.Door.interactRange)
            if doorIdx then
                local door = sub.doors[doorIdx]
                if door.balancing then
                    Submarine.StopPressureBalance(sub, doorIdx)
                end
            end
        end

        -- 水泵开关
        if buttons & Shared.CTRL.PUMP_TOGGLE ~= 0 then
            local pumpIdx = Submarine.GetNearbyPump(sub, playerRoom)
            if pumpIdx then
                Submarine.TogglePump(sub, sub.pumps[pumpIdx].room)
            end
        end

        -- ====== 压载水舱操作（工程师/技工专属） ======
        if player.role == "engineer" or player.role == "mechanic" then
            local tankIdx = Submarine.GetNearbyBallast(sub, playerRoom)
            if tankIdx then
                -- 注水（持续按住）
                if buttons & Shared.CTRL.BALLAST_FILL ~= 0 then
                    Submarine.BallastFill(sub, tankIdx, dt)
                end
                -- 排水（持续按住）
                if buttons & Shared.CTRL.BALLAST_DRAIN ~= 0 then
                    Submarine.BallastDrain(sub, tankIdx, dt)
                end
                -- 紧急排水（一次性）
                if buttons & Shared.CTRL.BALLAST_EMERG ~= 0 then
                    Submarine.BallastEmergency(sub, tankIdx)
                end
            end
        end

        -- 舷窗盖开关
        if buttons & Shared.CTRL.PORTHOLE_COVER ~= 0 then
            local phIdx = Submarine.GetNearbyPorthole(sub, playerX, playerRoom, Config.Porthole.interactRange)
            if phIdx then
                Submarine.TogglePortholeCover(sub, phIdx)
            end
        end

        -- 舷窗查看（客户端本地处理，服务端只记录状态）
        if buttons & Shared.CTRL.PORTHOLE_VIEW ~= 0 then
            local phIdx = Submarine.GetNearbyPorthole(sub, playerX, playerRoom, Config.Porthole.interactRange)
            if phIdx then
                player.viewingPorthole = phIdx
            else
                player.viewingPorthole = nil
            end
        else
            player.viewingPorthole = nil
        end

        -- 门消息计时器衰减
        if player.doorMsgTimer and player.doorMsgTimer > 0 then
            player.doorMsgTimer = player.doorMsgTimer - dt
            if player.doorMsgTimer <= 0 then
                player.doorMsg = nil
                player.doorMsgTimer = nil
            end
        end

        -- ====== 气压对移动的影响 ======
        local roomPressure = sub.compartments[playerRoom] and sub.compartments[playerRoom].pressure or 100
        if roomPressure < Config.Pressure.dangerThreshold then
            player.pressureDebuff = true
        else
            player.pressureDebuff = false
        end
        -- 致命低气压：加速氧气消耗
        if roomPressure <= Config.Pressure.lethalThreshold then
            sub.oxygen = math.max(0, sub.oxygen - Config.Pressure.suffocationDamage * dt)
        end

        -- ====== 角色物理模拟 ======
        UpdatePlayerPhysics(i, buttons, yaw, dt)

        ::continue_player::
    end

    -- ====== 潜艇驾驶系统更新 ======
    local helmInput = captainJx  -- captainJx 现在存储舵角（-90~+90）
    Submarine.UpdateDriving(sub, dt, helmInput)

    -- ====== 潜艇物理模拟 ======
    Submarine.UpdatePhysics(sub, dt)

    -- ====== 压载水舱更新 ======
    Submarine.UpdateBallast(sub, dt)

    -- ====== 声呐更新 ======
    Submarine.UpdateSonar(sub, dt)

    -- ====== 导航更新 ======
    Submarine.UpdateNavigation(sub, dt)

    -- ====== 反应堆模拟 ======
    Submarine.UpdateReactor(sub, dt)

    -- ====== 接线系统更新 ======
    Submarine.UpdateWiring(sub, dt)

    -- ====== 电力系统更新（基于反应堆输出 + 接线状态） ======
    PowerSystem.Update(powerSys, dt, sub.reactor.output, sub.wiring.severedSystems)

    -- ====== 反应堆熔毁检测 ======
    if sub.reactor.state == "meltdown" then
        -- 反应堆爆炸 → 潜艇严重损毁 → 游戏结束
        sub.hull = 0
        print("[Server] REACTOR MELTDOWN! Game over!")
    end

    -- ====== 电力效率影响游戏系统 ======
    local lightsEff = PowerSystem.GetEfficiency(powerSys, "lights")
    local engineEff = PowerSystem.GetEfficiency(powerSys, "engine")
    local pumpEff = PowerSystem.GetEfficiency(powerSys, "pump")

    -- 探照灯耗电（根据效率）
    local searchlightEff = PowerSystem.GetEfficiency(powerSys, "searchlight")
    if sub.driving.searchlightOn then
        sub.driving.searchlightRange = Config.Searchlight.range * searchlightEff
        if searchlightEff <= 0 then
            sub.driving.searchlightOn = false  -- 无电力则强制关闭
        end
    end

    -- 引擎效率影响最大速度（电力不足时降档）
    if engineEff < 0.25 and sub.driving.throttleGear > 1 then
        sub.driving.throttleGear = 1  -- 强制降到最低档
    elseif engineEff < 0.5 and sub.driving.throttleGear > 2 then
        sub.driving.throttleGear = 2  -- 强制降到第二档
    end

    -- 照明效率 → 存入sub供渲染使用
    sub.lightsEfficiency = lightsEff

    -- 同步深度到全局变量（兼容现有代码）
    currentDepth = sub.physics.depth

    -- 更新潜艇（含气压/水流/舷窗物理）
    local oxygenEff = PowerSystem.GetEfficiency(powerSys, "oxygen")
    Submarine.Update(sub, dt, oxygenEff, currentDepth)

    -- 高速航行增加危机概率
    if sub.physics and math.abs(sub.physics.speed) > Config.Physics.maxSpeed * 0.8 then
        CrisisManager.OnHighSpeed(crisis)
    end

    -- 更新危机
    CrisisManager.Update(crisis, sub, dt, gameTime)

    -- 更新AI船员行为（驱动AI玩家移动/修复/巡逻）
    AICrew.Update(aiCrew, sub, crisis, nil, dt, gameTime)
    AICrew.UpdateDoctorHeal(aiCrew, sub, dt)

    -- 将AICrew行为结果同步到对应AI玩家槽位
    SyncAICrewToPlayers()

    -- 更新怪物（攻击时可能切断线缆）
    MonsterManager.Update(monsterMgr, sub, crisis, dt, gameTime)

    -- 怪物攻击时随机切断线缆
    if monsterMgr and monsterMgr.lastAttackFrame then
        monsterMgr.lastAttackFrame = false
        if math.random() < Config.Wiring.monsterDamageChance then
            -- 找一条完好的线缆切断
            local intact = {}
            for ci, cable in ipairs(sub.wiring.cables) do
                if cable.intact then intact[#intact + 1] = ci end
            end
            if #intact > 0 then
                local cutIdx = intact[math.random(#intact)]
                Submarine.SeverCable(sub, cutIdx)
                print(string.format("[Server] Monster severed cable #%d (system: %s)", cutIdx, sub.wiring.cables[cutIdx].system))
            end
        end
    end

    -- 碰撞检测（简化：基于速度和随机地形）
    UpdateSubCollision(dt)

    -- 任务进度
    if gameState.currentMission then
        gameState.missionProgress.timeElapsed = gameState.missionProgress.timeElapsed + dt
        gameState.missionProgress.depthReached = math.max(gameState.missionProgress.depthReached, currentDepth)
        gameState.missionProgress.kills = monsterMgr.totalKills
    end
end

-- ============================================================
-- 潜艇碰撞检测（简化模型）
-- ============================================================
local collisionCooldown_ = 0

function UpdateSubCollision(dt)
    if not sub then return end
    collisionCooldown_ = math.max(0, collisionCooldown_ - dt)
    if collisionCooldown_ > 0 then return end

    local speed = math.abs(sub.physics.speed)
    if speed < Config.Physics.collision.minDamageSpeed then return end

    -- 简化碰撞：基于深度和速度的随机障碍
    -- 深度越深，碰撞概率越高（更多岩石/地形）
    local depthFactor = sub.physics.depth / Config.Driving.depth.maxDepth
    local collisionChance = 0.002 * depthFactor * (speed / Config.Physics.maxSpeed)

    if math.random() < collisionChance * dt then
        -- 判断碰撞方向
        local isFrontal = math.random() < 0.6  -- 60%正面
        local damage = Submarine.HandleCollision(sub, speed, isFrontal)

        if damage > 0 then
            -- 船员摔倒
            local cfg = Config.Physics.collision
            for i = 1, MAX_PLAYERS do
                local player = players_[i]
                if player and not player.inEVA then
                    if math.random() < cfg.crewFallChance then
                        player.vy = -200  -- 向上弹起
                        player.onGround = false
                        player.animState = "fall"
                    end
                end
            end

            -- 触发震动事件（客户端处理）
            collisionCooldown_ = cfg.shakeDuration
            -- 碰撞数据存入快照
            sub.lastCollision = {
                damage = damage,
                frontal = isFrontal,
                speed = speed,
                time = gameTime,
            }
            print(string.format("[Server] Collision! speed=%.1f frontal=%s damage=%.1f", speed, tostring(isFrontal), damage))
        end
    end
end

-- ============================================================
-- MonsterManager 声呐目标辅助
-- ============================================================
-- 如果 MonsterManager 没有此方法，提供一个安全的 fallback
if not MonsterManager.GetSonarTargets then
    function MonsterManager.GetSonarTargets(mgr, px, py, range)
        local targets = {}
        if mgr and mgr.monsters then
            for _, m in ipairs(mgr.monsters) do
                if m.state ~= "dead" then
                    -- 用距离和角度转换为世界坐标
                    local mAngle = math.rad(m.angle or 0)
                    local mDist = m.distance or 500
                    table.insert(targets, {
                        x = px + math.sin(mAngle) * mDist,
                        y = py + math.cos(mAngle) * mDist,
                        type = m.type or "creature",
                    })
                end
            end
        end
        return targets
    end
end

-- ============================================================
-- EVA 多人处理
-- ============================================================

function StartPlayerEVA(slot)
    local player = players_[slot]
    if not player then return end

    local evaData = evaStates_[slot]
    local eva = evaData.eva

    -- 医官加成：额外氧气
    if player.role == "medic" then
        eva.oxygen = EVASystem.Config.maxOxygen + Shared.ROLE_BONUS.medic.evaOxygenBonus
    end

    if EVASystem.StartEVA(eva) then
        evaData.world = RuinsGenerator.Generate()
        player.inEVA = true
        print(string.format("[Server] Player slot %d (%s) started EVA", slot, player.role))
    end
end

function UpdatePlayerEVA(slot, dt)
    local player = players_[slot]
    local evaData = evaStates_[slot]
    if not evaData then return end

    local eva = evaData.eva
    local buttons, yaw, pitch = GetPlayerInput(slot)

    -- 游泳输入
    local jx, jy = 0, 0
    if buttons & Shared.CTRL.LEFT ~= 0 then jx = -1 end
    if buttons & Shared.CTRL.RIGHT ~= 0 then jx = 1 end
    if buttons & Shared.CTRL.UP ~= 0 then jy = -1 end
    if buttons & Shared.CTRL.DOWN ~= 0 then jy = 1 end

    -- 氧气消耗倍率（医官减少）
    local origDrain = EVASystem.Config.oxygenDrainRate
    if player.role == "medic" then
        EVASystem.Config.oxygenDrainRate = origDrain * Shared.ROLE_BONUS.medic.oxygenMult
    end

    EVASystem.Update(eva, jx, jy, dt)

    EVASystem.Config.oxygenDrainRate = origDrain  -- 恢复

    -- 检查附近战利品
    if evaData.world then
        EVASystem.CheckNearLoot(eva, evaData.world.loots)
    end

    -- F键拾取（技工加成在客户端体现为拾取范围大）
    if buttons & Shared.CTRL.INTERACT ~= 0 then
        local picked = EVASystem.PickupLoot(eva)
        if picked then
            -- 技工采集价值加成
            if player.role == "mechanic" then
                picked.value = math.floor(picked.value * Shared.ROLE_BONUS.mechanic.evaCollect)
            end
            print(string.format("[Server] Slot %d picked: %s ($%d)", slot, picked.name, picked.value))
        end
    end

    -- G键返回
    if buttons & Shared.CTRL.EVA_EXIT ~= 0 then
        if EVASystem.IsNearDock(eva) then
            EVASystem.EndEVA(eva)
        end
    end

    -- ESC强制退出
    if buttons & Shared.CTRL.ESCAPE ~= 0 then
        eva.phase = "idle"
        eva.isActive = false
        player.inEVA = false
        SettleEVALoot(slot)
    end

    -- EVA结束检测
    if eva.phase == "idle" and not eva.isActive then
        player.inEVA = false
        SettleEVALoot(slot)
    end
end

function SettleEVALoot(slot)
    local evaData = evaStates_[slot]
    if not evaData then return end

    local loot = EVASystem.GetCollectedLoot(evaData.eva)
    local totalValue = 0
    for _, item in ipairs(loot) do
        totalValue = totalValue + item.value
    end
    if totalValue > 0 then
        gameState.gold = gameState.gold + totalValue
        print(string.format("[Server] Slot %d EVA loot: $%d", slot, totalValue))
    end
end

function HandleEvaStart(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if slot and players_[slot] then
        StartPlayerEVA(slot)
    end
end

function HandleEvaPickup(eventType, eventData)
    -- 拾取通过 Controls.buttons INTERACT 位处理，这里备用
end

-- ============================================================
-- 快照广播
-- ============================================================

function BroadcastSnapshot(dt)
    local snapshot = BuildSnapshot()
    local jsonStr = cjson.encode(snapshot)

    local data = VariantMap()
    data["Data"] = Variant(jsonStr)
    network:BroadcastRemoteEvent(Shared.EVENTS.GAME_SNAPSHOT, true, data)
end

function BuildSnapshot()
    local snap = {
        phase = gameState.currentScene == GameState.SCENE_PORT and Shared.PHASE.PORT or Shared.PHASE.DEEP_SEA,
        time = gameTime,
        gold = gameState.gold,
        depth = math.floor(currentDepth),
    }

    -- 潜艇状态
    if sub then
        snap.sub = {
            hull = sub.hull,
            oxygen = sub.oxygen,
            power = sub.power,
            waterLevels = {},
            pressures = {},
            doors = {},
            portholes = {},
            pumps = {},
        }
        for i, comp in ipairs(sub.compartments) do
            snap.sub.waterLevels[i] = comp.waterLevel or 0
            snap.sub.pressures[i] = comp.pressure or 100
        end
        -- 门状态
        for i, door in ipairs(sub.doors) do
            snap.sub.doors[i] = {
                state = door.state,
                locked = door.locked,
                progress = door.progress,
                balancing = door.balancing,
                balanceProgress = door.balanceProgress,
            }
        end
        -- 舷窗状态
        for i, ph in ipairs(sub.portholes) do
            snap.sub.portholes[i] = {
                state = ph.state,
                coverClosed = ph.coverClosed,
            }
        end
        -- 水泵状态
        for i, pump in ipairs(sub.pumps) do
            snap.sub.pumps[i] = {
                room = pump.room,
                active = pump.active,
            }
        end
        -- 驾驶系统状态
        snap.sub.driving = {
            helmAngle = sub.driving.helmAngle,
            throttleGear = sub.driving.throttleGear,
            gearSwitching = sub.driving.gearSwitching,
            searchlightOn = sub.driving.searchlightOn,
            searchlightAngle = sub.driving.searchlightAngle,
            searchlightRange = sub.driving.searchlightRange,
        }
        -- 物理状态
        snap.sub.physics = {
            posX = sub.physics.posX,
            posY = sub.physics.posY,
            depth = sub.physics.depth,
            targetDepth = sub.physics.targetDepth,
            heading = sub.physics.heading,
            speed = sub.physics.speed,
            verticalSpeed = sub.physics.verticalSpeed,
        }
        -- 压载水舱
        snap.sub.ballast = {}
        for i, tank in ipairs(sub.ballast) do
            snap.sub.ballast[i] = {
                room = tank.room,
                level = tank.level,
                breached = tank.breached,
                damaged = tank.damaged,
            }
        end
        -- 声呐
        snap.sub.sonar = {
            scanAngle = sub.sonar.scanAngle,
            pulsing = sub.sonar.pulsing,
            pulseCooldown = sub.sonar.pulseCooldown,
            blips = sub.sonar.blips,
        }
        -- 导航
        snap.sub.navigation = {
            waypoints = sub.navigation.waypoints,
            currentWP = sub.navigation.currentWP,
            deviation = sub.navigation.deviation,
            alarmActive = sub.navigation.alarmTimer <= 0 and sub.navigation.deviation > Config.Navigation.deviationAlarm,
        }
    end

    -- 玩家状态
    snap.players = {}
    for i = 1, MAX_PLAYERS do
        local player = players_[i]
        if player then
            local ps = {
                slot = i,
                role = player.role,
                isAI = player.isAI or false,
                inEVA = player.inEVA or false,
                room = player.room or 1,
                x = player.x or 0,
                y = player.y or 0,
                facing = player.facing or 1,
                animState = player.animState or "idle",
                onGround = player.onGround ~= false,
                inWater = player.inWater or false,
                isGrabbing = player.isGrabbing or false,
                aiState = player.aiState,       -- AI行为状态(patrol/repair/respond等)
                aiCommand = player.aiCommand,   -- AI当前指令(follow/standby等)
                -- 门/气压系统
                doorMsg = player.doorMsg,
                pressureDebuff = player.pressureDebuff or false,
                viewingPorthole = player.viewingPorthole,
            }
            -- EVA状态
            if player.inEVA then
                local evaData = evaStates_[i]
                if evaData and evaData.eva then
                    local eva = evaData.eva
                    ps.eva = {
                        x = eva.x,
                        y = eva.y,
                        oxygen = eva.oxygen,
                        phase = eva.phase,
                        facing = eva.facing,
                        collected = #eva.collectedLoot,
                    }
                end
            end
            snap.players[i] = ps
        end
    end

    -- 危机（扩展：含严重度、诊断、特殊参数）
    if crisis then
        snap.crises = {}
        local activeCrises = CrisisManager.GetActiveCrises(crisis)
        for _, c in ipairs(activeCrises) do
            local entry = {
                type = c.type,
                room = c.roomIndex,
                severity = c.severity,
                progress = c.repairProgress,
                diagnosed = c.diagnosed,
                repairing = c.isBeingRepaired,
            }
            -- 类型特有数据
            if c.type == "overheat" then
                entry.temperature = c.params.temperature
            elseif c.type == "fire" then
                entry.burningRooms = c.params.burningRooms
            elseif c.type == "monster_invasion" then
                entry.monsterHp = c.params.monsterHp
            elseif c.type == "power_failure" then
                entry.affectedRooms = c.params.affectedRooms
            elseif c.type == "toxic_gas" then
                entry.gasRooms = c.gasRooms
            elseif c.type == "crew_madness" then
                entry.effectType = c.params.effectType
            end
            table.insert(snap.crises, entry)
        end
        -- 警报数据
        snap.crisisAlerts = crisis.alert.activeAlerts
        snap.crisisMuted = crisis.alert.muted
    end

    -- 怪物
    if monsterMgr then
        snap.monsters = {}
        for _, m in ipairs(monsterMgr.monsters) do
            if m.state ~= "dead" then
                table.insert(snap.monsters, {
                    type = m.type,
                    side = m.side,
                    dist = m.distance,
                    angle = m.angle,
                    state = m.state,
                })
            end
        end
    end

    -- 电力系统（kW制）
    if powerSys then
        local sysList = {}
        for idx, key in ipairs(powerSys.priority) do
            local sys = powerSys.systems[key]
            sysList[idx] = {
                key = key,
                name = sys.name,
                icon = sys.icon,
                color = sys.color,
                maxPower = sys.maxPower,
                allocated = sys.allocated,
                efficiency = sys.efficiency,
                online = sys.online,
                severed = sys.severed,
            }
        end
        snap.power = {
            isOpen = powerSys.isOpen,
            selectedIdx = powerSys.selectedIdx,
            totalGeneration = powerSys.totalGeneration,
            totalConsumption = powerSys.totalConsumption,
            overloaded = powerSys.overloaded,
            systems = sysList,
        }
    end

    -- 反应堆
    if sub and sub.reactor then
        local r = sub.reactor
        snap.reactor = {
            state = r.state,
            output = r.output,
            temperature = r.temperature,
            cooldownTimer = r.cooldownTimer,
            startupTimer = r.startupTimer,
            shutdownTimer = r.shutdownTimer,
            shutdownHoldProgress = r.shutdownHoldProgress,
            meltdownTimer = r.meltdownTimer,
            meltdownActive = r.meltdownActive,
            panelOpen = r.panelOpen,
        }
    end

    -- 接线系统
    if sub and sub.wiring then
        local cables = {}
        for i, cable in ipairs(sub.wiring.cables) do
            cables[i] = {
                system = cable.system,
                intact = cable.intact,
                repairing = cable.repairing,
                repairProgress = cable.repairProgress,
            }
        end
        snap.wiring = {
            cables = cables,
            severedSystems = sub.wiring.severedSystems,
        }
    end

    -- 照明效率（客户端渲染用）
    snap.lightsEfficiency = sub and sub.lightsEfficiency or 1.0

    -- 港口
    if gameState.currentScene == GameState.SCENE_PORT then
        snap.port = {
            tab = portScene.currentTab,
            selected = portScene.selectedItem,
            mission = gameState.currentMission and gameState.currentMission.title or nil,
        }
    end

    -- AI行为信息已通过SyncAICrewToPlayers同步到玩家数据中
    -- 不再需要独立的aiCrew快照

    -- 炮塔状态
    if turret then
        snap.turret = {
            isActive = turret.isActive or false,
            angle = turret.angle or 0,
            cooldown = turret.cooldownTimer or 0,
            ammo = turret.ammo or 999,
        }
    end

    -- 物品栏
    if inventory then
        snap.inventory = {
            materials = inventory.materials or {},
            scraps = inventory.scraps or {},
            products = inventory.products or {},
            isOpen = inventory.isOpen or false,
            totalCollected = inventory.totalCollected or 0,
            buffs = inventory.buffs or {},
            messages = inventory.messages or {},
        }
    end

    -- 任务
    if gameState.currentMission then
        snap.mission = {
            title = gameState.currentMission.title,
            objectives = gameState.currentMission.objectives,
            progress = gameState.missionProgress,
        }
    end

    -- 补给品（购买后客户端同步显示）
    if gameState.supplies then
        snap.supplies = gameState.supplies
    end

    -- 合作系统状态
    snap.coop = {}
    -- 玩家生存状态
    snap.coop.health = {}
    for i = 1, MAX_PLAYERS do
        if coopHealth_[i] then
            snap.coop.health[i] = {
                hp = coopHealth_[i].hp,
                maxHp = coopHealth_[i].maxHp,
                isDowned = coopHealth_[i].isDowned,
                isDead = coopHealth_[i].isDead,
                downedTimer = coopHealth_[i].downedTimer,
                rescuer = coopHealth_[i].rescuer,
                reviveProgress = coopHealth_[i].reviveProgress,
            }
        end
    end
    -- 交易状态
    if coopTrade_ and coopTrade_.active then
        snap.coop.trade = {
            from = coopTrade_.from,
            to = coopTrade_.to,
            itemId = coopTrade_.itemId,
            timer = coopTrade_.timer,
        }
    end
    -- 投票状态
    if coopRoom_ and coopRoom_.vote and coopRoom_.vote.active then
        snap.coop.vote = {
            type = coopRoom_.vote.type,
            target = coopRoom_.vote.target,
            timer = coopRoom_.vote.timer,
            yes = coopRoom_.vote.yes,
            no = coopRoom_.vote.no,
            total = coopRoom_.vote.total,
        }
    end
    -- 观战状态
    snap.coop.spectators = {}
    for i = 1, MAX_PLAYERS do
        if coopSpectators_[i] and coopSpectators_[i].active then
            snap.coop.spectators[i] = {
                target = coopSpectators_[i].target,
                freeView = coopSpectators_[i].freeView,
                hintsLeft = coopSpectators_[i].hintsLeft,
            }
        end
    end
    -- 房间/暂停
    if coopRoom_ then
        snap.coop.room = {
            isPaused = coopRoom_.isPaused or false,
            difficulty = coopRoom_.difficulty or "normal",
        }
    end

    -- EVA世界数据（所有出舱玩家共享同一组遗迹信息）
    local anyEVA = false
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].inEVA then anyEVA = true; break end
    end
    if anyEVA then
        for i = 1, MAX_PLAYERS do
            local ed = evaStates_[i]
            if ed and ed.world then
                snap.evaWorld = {
                    ruinCount = #ed.world.ruins,
                    lootCount = RuinsGenerator.GetRemainingLootCount(ed.world),
                }
                break
            end
        end
    end

    return snap
end

function BroadcastLobbyState()
    local snap = {
        phase = Shared.PHASE.LOBBY,
        players = {},
        timer = lobbyTimer_,
        timeout = LOBBY_TIMEOUT,
    }
    for i = 1, MAX_PLAYERS do
        if players_[i] then
            snap.players[i] = {
                slot = i,
                role = players_[i].role,
                ready = players_[i].ready,
                isAI = players_[i].isAI or false,
            }
        end
    end

    local data = VariantMap()
    data["Data"] = Variant(cjson.encode(snap))
    network:BroadcastRemoteEvent(Shared.EVENTS.GAME_SNAPSHOT, true, data)
end

-- ============================================================
-- 工具函数
-- ============================================================

function FindFreeSlot()
    for i = 1, MAX_PLAYERS do
        if players_[i] == nil then return i end
    end
    return nil
end

--- 查找一个AI控制的槽位（供玩家接管）
function FindAISlot()
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].isAI then return i end
    end
    return nil
end

function GetActivePlayerCount()
    local count = 0
    for i = 1, MAX_PLAYERS do
        if players_[i] then count = count + 1 end
    end
    return count
end

function GetPlayerInput(slot)
    local player = players_[slot]
    if not player or not player.connKey then
        -- AI玩家：返回空输入（后续AI逻辑可扩展）
        return 0, 0, 0
    end

    local conn = connObjects_[player.connKey]
    if not conn then return 0, 0, 0 end

    local buttons = conn.controls.buttons
    local yaw = conn.controls.yaw
    local pitch = conn.controls.pitch
    return buttons, yaw, pitch
end

function CalcRoom(x)
    -- 根据X坐标计算在哪个舱室
    local accX = 0
    for i, comp in ipairs(Config.Sub.compartments) do
        accX = accX + comp.width
        if x < accX then return i end
    end
    return #Config.Sub.compartments
end

-- ============================================================
-- 角色物理模拟
-- ============================================================

--- 获取舱室水位高度（像素，从地面算起）
local function GetRoomWaterHeight(roomIdx)
    if not sub or not sub.compartments then return 0 end
    local comp = sub.compartments[roomIdx]
    if not comp then return 0 end
    local waterLevel = comp.waterLevel or 0
    -- waterLevel 是 0~1 比例，对应舱室内部高度
    local innerH = Config.Sub.hullHeight - Config.Structure.floorHeight - Config.Structure.ceilingHeight
    return waterLevel * innerH
end

--- 检查某舱室是否有梯子
local function RoomHasLadder(roomIdx)
    for _, slot in ipairs(Config.Structure.ladderSlots) do
        if slot == roomIdx then return true end
    end
    return false
end

--- 完整角色物理更新
---@param slot number 玩家槽位
---@param buttons number 按钮位掩码
---@param yaw number 摇杆X强度（-90~+90映射）
---@param dt number 帧时间
function UpdatePlayerPhysics(slot, buttons, yaw, dt)
    local player = players_[slot]
    if not player then return end

    local crew = Config.Crew
    local structure = Config.Structure

    -- ====== 摔倒状态 ======
    if player.isStunned then
        player.stunTimer = player.stunTimer - dt
        if player.stunTimer <= 0 then
            player.isStunned = false
            player.stunTimer = 0
        end
        player.animState = "stun"
        -- 摔倒时仍受重力（但不接受输入）
        if not player.onGround then
            player.vy = player.vy + crew.gravity * dt
            if player.vy > crew.maxFallSpeed then player.vy = crew.maxFallSpeed end
            player.y = player.y + player.vy * dt
            if player.y >= 0 then
                player.y = 0
                player.vy = 0
                player.onGround = true
            end
        end
        -- 地面摩擦减速
        if player.onGround then
            local friction = crew.decel * dt
            if player.vx > 0 then
                player.vx = math.max(0, player.vx - friction)
            elseif player.vx < 0 then
                player.vx = math.min(0, player.vx + friction)
            end
        end
        player.x = player.x + player.vx * dt
        player.x = math.max(20, math.min(player.x, Config.Sub.totalWidth - 20))
        player.room = CalcRoom(player.x)
        return
    end

    -- ====== 解析输入 ======
    local moveDir = 0
    if buttons & Shared.CTRL.LEFT ~= 0 then moveDir = moveDir - 1 end
    if buttons & Shared.CTRL.RIGHT ~= 0 then moveDir = moveDir + 1 end

    -- 摇杆强度（从yaw还原，yaw = jx * 90）
    local joyIntensity = math.abs(yaw / 90.0)
    joyIntensity = math.min(1.0, joyIntensity)

    -- 走/跑判断
    local targetSpeed = 0
    if moveDir ~= 0 then
        if joyIntensity > crew.walkThreshold then
            targetSpeed = crew.runSpeed * moveDir
        else
            targetSpeed = crew.walkSpeed * moveDir
        end
    end

    -- ====== 水中检测 ======
    local waterH = GetRoomWaterHeight(player.room or 1)
    -- 角色脚部在水中（y是向上的偏移，0=地面，负=向上）
    -- 水位从地面向上，角色y=0在地面，y<0表示在空中（我们用y>=0为地面以上）
    -- 改为：y=0是地面，y向上为正不合惯例，我们用 y<=0 表示地面以上
    -- 实际设计：y=0为地面位置，y<0为跳起，vy为正表示下落
    -- 水位：waterH是从地面向上的高度
    local charFeetY = -player.y  -- player.y 为负数表示在地面以上
    player.inWater = (charFeetY < waterH) and waterH > 10

    -- ====== 抓握检测 ======
    local wantGrab = (buttons & Shared.CTRL.UP ~= 0)
    local canGrab = false
    if wantGrab then
        -- 检查天花板管道（角色顶部接近天花板）
        local innerH = Config.Sub.hullHeight - structure.floorHeight - structure.ceilingHeight
        local charTopY = -player.y + crew.height
        if charTopY >= innerH - structure.pipeHeight then
            canGrab = true
        end
        -- 检查梯子
        if RoomHasLadder(player.room or 1) then
            canGrab = true
        end
        -- 检查扶手（在扶手高度范围）
        if -player.y <= structure.handrailHeight and player.onGround then
            canGrab = true
        end
    end
    player.isGrabbing = wantGrab and canGrab

    -- ====== 水中物理 ======
    if player.inWater then
        -- 水中移动
        local swimTarget = moveDir * crew.swimSpeed
        player.vx = player.vx + (swimTarget - player.vx) * (1 - crew.waterDrag) * 60 * dt

        -- 水中垂直：自然上浮 + 输入
        local floatVy = -crew.floatSpeed  -- 自然上浮（向上为负vy）
        if buttons & Shared.CTRL.DOWN ~= 0 then
            floatVy = crew.swimSpeed  -- 向下游
        elseif buttons & Shared.CTRL.UP ~= 0 then
            floatVy = -crew.swimSpeed  -- 向上游加速
        end
        player.vy = player.vy + (floatVy - player.vy) * (1 - crew.waterDrag) * 60 * dt

        player.animState = "swim"
    else
        -- ====== 地面/空中物理 ======
        if player.onGround then
            -- 抓握时减速
            local speedMult = player.isGrabbing and crew.grabSlowdown or 1.0

            -- 惯性加速/减速
            if targetSpeed ~= 0 then
                local accelRate = crew.accel * dt
                if player.vx < targetSpeed * speedMult then
                    player.vx = math.min(targetSpeed * speedMult, player.vx + accelRate)
                elseif player.vx > targetSpeed * speedMult then
                    player.vx = math.max(targetSpeed * speedMult, player.vx - accelRate)
                end
            else
                -- 松手减速（惯性滑行）
                local decelRate = crew.decel * dt
                if player.vx > 0 then
                    player.vx = math.max(0, player.vx - decelRate)
                elseif player.vx < 0 then
                    player.vx = math.min(0, player.vx + decelRate)
                end
            end

            -- 跳跃
            if buttons & Shared.CTRL.JUMP ~= 0 then
                player.vy = -crew.jumpSpeed  -- 向上为负
                player.onGround = false
            end
        else
            -- 空中控制（较弱）
            if targetSpeed ~= 0 then
                local airAccel = crew.airAccel * dt
                if player.vx < targetSpeed then
                    player.vx = math.min(targetSpeed, player.vx + airAccel)
                elseif player.vx > targetSpeed then
                    player.vx = math.max(targetSpeed, player.vx - airAccel)
                end
            else
                local airDecel = crew.airDecel * dt
                if player.vx > 0 then
                    player.vx = math.max(0, player.vx - airDecel)
                elseif player.vx < 0 then
                    player.vx = math.min(0, player.vx + airDecel)
                end
            end

            -- 重力
            if not player.isGrabbing then
                player.vy = player.vy + crew.gravity * dt
                if player.vy > crew.maxFallSpeed then
                    player.vy = crew.maxFallSpeed
                end
            else
                -- 抓握时悬挂（缓慢下滑）
                player.vy = math.min(player.vy, 20)
            end
        end

        -- 动画状态
        if not player.onGround then
            if player.isGrabbing then
                player.animState = "grab"
            elseif player.vy < 0 then
                player.animState = "jump"
            else
                player.animState = "fall"
            end
        elseif math.abs(player.vx) > crew.walkSpeed * 0.8 then
            player.animState = "run"
        elseif math.abs(player.vx) > 10 then
            player.animState = "walk"
        else
            player.animState = "idle"
        end
    end

    -- ====== 应用速度 ======
    player.x = player.x + player.vx * dt
    player.y = player.y + player.vy * dt

    -- ====== 地面碰撞 ======
    if player.y >= 0 then
        -- 着地检测：是否摔倒
        if not player.onGround and player.vy > crew.fallThreshold then
            player.isStunned = true
            player.stunTimer = crew.stunDuration
        end
        player.y = 0
        player.vy = 0
        player.onGround = true
    end

    -- ====== 天花板碰撞 ======
    local innerH = Config.Sub.hullHeight - structure.floorHeight - structure.ceilingHeight
    local maxJumpY = -(innerH - crew.height)  -- 最大向上偏移（负值）
    if player.y < maxJumpY then
        player.y = maxJumpY
        player.vy = 0
    end

    -- ====== X轴边界 ======
    player.x = math.max(20, math.min(player.x, Config.Sub.totalWidth - 20))

    -- ====== 更新舱室和朝向 ======
    player.room = CalcRoom(player.x)
    if moveDir ~= 0 then
        player.facing = moveDir
    end
end

--- 将AICrew行为结果同步到AI玩家槽位
--- 只同步真正由AI控制的槽位（isAI == true），玩家接管的槽位由玩家输入驱动
function SyncAICrewToPlayers()
    if not aiCrew or not aiCrew.members then return end

    -- 建立纯AI玩家槽位列表（排除被玩家接管的）
    local aiSlots = {}
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].isAI then
            table.insert(aiSlots, i)
        end
    end

    -- 按顺序将AICrew成员映射到纯AI玩家槽位
    for idx, slot in ipairs(aiSlots) do
        local ai = aiCrew.members[idx]
        if ai then
            local player = players_[slot]
            player.x = ai.x
            player.facing = ai.facing or 1
            player.room = ai.roomIndex or CalcRoom(ai.x)
            -- 映射动画状态
            if ai.animState == "walk" then
                player.animState = "walk"
            elseif ai.animState == "repair" then
                player.animState = "repair"
            elseif ai.animState == "operate" then
                player.animState = "operate"
            else
                player.animState = "idle"
            end
            -- 存储AI行为状态供快照使用
            player.aiState = ai.state      -- patrol/repair/respond/follow/standby
            player.aiCommand = ai.command  -- 当前指令
        end
    end
end

--- 获取AI玩家对应的AICrew索引
function GetAICrewIndex(playerSlot)
    local aiIdx = 0
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].isAI then
            aiIdx = aiIdx + 1
            if i == playerSlot then
                return aiIdx
            end
        end
    end
    return nil
end

function BroadcastPlayerJoined(slot)
    local data = VariantMap()
    data["Slot"] = Variant(slot)
    network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_JOINED, true, data)
end

function AutoAssignRoles()
    local usedRoles = {}
    for i = 1, MAX_PLAYERS do
        if players_[i] and players_[i].role then
            usedRoles[players_[i].role] = true
        end
    end

    local available = {}
    for _, r in ipairs(Shared.ROLES) do
        if not usedRoles[r.id] then
            table.insert(available, r.id)
        end
    end

    for i = 1, MAX_PLAYERS do
        if players_[i] and not players_[i].role then
            if #available > 0 then
                players_[i].role = table.remove(available, 1)
                players_[i].ready = true
            end
        end
    end
end

-- ============================================================
-- 联机交互事件处理
-- ============================================================

--- 使用物品（远程事件）
function HandleUseItem(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end
    if not inventory then return end

    local itemId = eventData["ItemId"]:GetString()
    if itemId and itemId ~= "" then
        Inventory.UseProduct(inventory, itemId, sub, turret, powerSys)
        print(string.format("[Server] Slot %d used item: %s", slot, itemId))
    end
end

--- 合成物品（远程事件）
function HandleCraftItem(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end
    if not inventory then return end

    local recipeIdx = eventData["RecipeIdx"]:GetInt()
    if recipeIdx >= 1 then
        local success = Crafting.Craft(inventory, recipeIdx)
        if success then
            print(string.format("[Server] Slot %d crafted recipe #%d", slot, recipeIdx))
        end
    end
end

--- 指挥AI船员（远程事件）
function HandleCommandAI(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end
    if not aiCrew then return end

    local aiIdx = eventData["AIIdx"]:GetInt()
    local cmdId = eventData["CmdId"]:GetString()

    if aiIdx >= 1 and cmdId and cmdId ~= "" then
        AICrew.SetCommand(aiCrew, aiIdx, cmdId)
        print(string.format("[Server] Slot %d commanded AI #%d: %s", slot, aiIdx, cmdId))
    end
end

--- 拾取地板碎片（远程事件）
function HandlePickupScrap(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end
    if not inventory then return end

    Inventory.PickupNearScrap(inventory)
    print(string.format("[Server] Slot %d picked up scrap", slot))
end

--- 打开/关闭物品栏（远程事件）
function HandleToggleInventory(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end
    if not inventory then return end

    Inventory.TogglePanel(inventory)
end

-- ============================================================
-- 合作系统事件处理
-- ============================================================

--- 辅助：广播交易结果
function BroadcastTradeResult(fromSlot, toSlot, result)
    local data = VariantMap()
    data["From"] = Variant(fromSlot or 0)
    data["To"] = Variant(toSlot or 0)
    data["Result"] = Variant(result or "failed")
    network:BroadcastRemoteEvent(Shared.EVENTS.TRADE_RESULT, true, data)
end

--- 辅助：获取槽位对应的连接
local function GetConnectionForSlot(slot)
    local player = players_[slot]
    if not player or not player.connKey then return nil end
    return connObjects_[player.connKey]
end

--- 辅助：检查是否为房主（slot 1 或第一个非AI玩家）
local function IsHost(slot)
    return slot == 1
end

--- 快捷指令：接收后广播给所有玩家
function HandleQuickCommand(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local cmdId = eventData["CmdId"]:GetString()
    local category = eventData["Category"]:GetString()

    -- 广播给所有玩家（含发送者名称和位置）
    local data = VariantMap()
    data["Slot"] = Variant(slot)
    data["CmdId"] = Variant(cmdId or "")
    data["Category"] = Variant(category or "")
    data["Role"] = Variant(players_[slot].role or "")
    data["Room"] = Variant(players_[slot].room or 1)
    network:BroadcastRemoteEvent(Shared.EVENTS.QUICK_COMMAND, true, data)

    print(string.format("[Server] Slot %d quick command: [%s] %s", slot, category, cmdId))
end

--- 交易请求：验证并转发
function HandleTradeOffer(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local targetSlot = eventData["Target"]:GetInt()
    local itemId = eventData["ItemId"]:GetString()

    -- 验证目标存在且在附近
    if not players_[targetSlot] then
        print(string.format("[Server] Trade offer from slot %d: target %d not found", slot, targetSlot))
        return
    end

    -- 检查距离（同一舱室）
    if players_[slot].room ~= players_[targetSlot].room then
        local data = VariantMap()
        data["Result"] = Variant("too_far")
        connection:SendRemoteEvent(Shared.EVENTS.TRADE_RESULT, true, data)
        return
    end

    -- 检查是否有进行中的交易
    if coopTrade_ and coopTrade_.active then
        local data = VariantMap()
        data["Result"] = Variant("busy")
        connection:SendRemoteEvent(Shared.EVENTS.TRADE_RESULT, true, data)
        return
    end

    -- 创建交易
    coopTrade_ = CoopSystem.CreateTrade()
    CoopSystem.OfferItem(coopTrade_, slot, targetSlot, itemId, 1)

    -- 通知目标玩家
    local targetConn = GetConnectionForSlot(targetSlot)
    if targetConn then
        local data = VariantMap()
        data["From"] = Variant(slot)
        data["ItemId"] = Variant(itemId or "")
        data["FromRole"] = Variant(players_[slot].role or "")
        targetConn:SendRemoteEvent(Shared.EVENTS.TRADE_OFFER, true, data)
    end

    print(string.format("[Server] Trade: slot %d offers '%s' to slot %d", slot, itemId, targetSlot))
end

--- 交易响应：处理接受/拒绝
function HandleTradeRespond(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local accept = eventData["Accept"]:GetBool()

    if not coopTrade_ or not coopTrade_.active then return end
    if coopTrade_.to ~= slot then return end  -- 只有目标方可响应

    if accept then
        -- 执行交易（转移物品）
        local success = CoopSystem.AcceptTrade(coopTrade_, slot)
        if success and inventory then
            -- 实际物品转移逻辑（简化：从全局物品栏扣除/增加）
            local itemId = coopTrade_.itemId
            if inventory.products and inventory.products[itemId] then
                -- 这里需要个人物品栏支持，暂时用全局
                print(string.format("[Server] Trade executed: '%s' from slot %d to slot %d", itemId, coopTrade_.from, coopTrade_.to))
            end
        end
        BroadcastTradeResult(coopTrade_.from, coopTrade_.to, "success")
    else
        CoopSystem.RejectTrade(coopTrade_, slot)
        BroadcastTradeResult(coopTrade_.from, coopTrade_.to, "rejected")
    end

    coopTrade_ = CoopSystem.CreateTrade()
end

--- 救援操作：拖拽/背起倒地队友
function HandleRescueAction(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local action = eventData["Action"]:GetString()
    local targetSlot = eventData["Target"]:GetInt()

    if not players_[targetSlot] or not coopHealth_[targetSlot] then return end

    if action == "revive" then
        -- 开始救援（验证距离同舱）
        if players_[slot].room == players_[targetSlot].room then
            CoopSystem.StartRescue(coopHealth_[targetSlot], slot, action)
            -- 医官加速救援
            if players_[slot].role == "medic" then
                coopHealth_[targetSlot].reviveSpeed = 2.0  -- 医官双倍速度
            end
            -- 通知所有人
            local data = VariantMap()
            data["Rescuer"] = Variant(slot)
            data["Target"] = Variant(targetSlot)
            network:BroadcastRemoteEvent(Shared.EVENTS.RESCUE_UPDATE, true, data)
            print(string.format("[Server] Slot %d rescuing slot %d", slot, targetSlot))
        end
    elseif action == "carry" then
        -- 背起倒地队友
        if players_[slot].room == players_[targetSlot].room and coopHealth_[targetSlot].isDowned then
            coopHealth_[targetSlot].carrier = slot
            players_[slot].carrying = targetSlot
            -- 背人时速度减半
            print(string.format("[Server] Slot %d carrying slot %d", slot, targetSlot))
        end
    elseif action == "drop" then
        -- 放下队友
        if players_[slot].carrying then
            local carried = players_[slot].carrying
            if coopHealth_[carried] then
                CoopSystem.DropCarried(coopHealth_[carried])
            end
            players_[slot].carrying = nil
            print(string.format("[Server] Slot %d dropped carried player", slot))
        end
    elseif action == "cancel" then
        -- 取消救援
        if coopHealth_[targetSlot].rescuer == slot then
            coopHealth_[targetSlot].rescuer = nil
            coopHealth_[targetSlot].reviveProgress = 0
        end
    end
end

--- 发起投票
function HandleVoteStart(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local voteType = eventData["VoteType"]:GetString()
    local target = eventData["Target"]:GetInt()

    if not coopRoom_ then return end

    -- 计算在线玩家数
    local onlineCount = 0
    for i = 1, MAX_PLAYERS do
        if players_[i] and not players_[i].isAI then
            onlineCount = onlineCount + 1
        end
    end

    local ok = CoopSystem.StartVote(coopRoom_, slot, voteType, target, onlineCount)
    if ok then
        -- 广播投票开始
        local data = VariantMap()
        data["VoteType"] = Variant(voteType)
        data["Initiator"] = Variant(slot)
        data["Target"] = Variant(target or 0)
        data["Duration"] = Variant(20)  -- 20秒投票
        network:BroadcastRemoteEvent(Shared.EVENTS.VOTE_START, true, data)
        print(string.format("[Server] Vote started by slot %d: %s (target: %d)", slot, voteType, target or 0))
    end
end

--- 投票
function HandleVoteCast(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    local vote = eventData["Vote"]:GetBool()

    if not coopRoom_ then return end

    local result = CoopSystem.CastVote(coopRoom_, slot, vote)
    if result then
        -- 投票有结果了
        local data = VariantMap()
        data["Passed"] = Variant(result == "passed")
        data["VoteType"] = Variant(coopRoom_.vote.type or "")
        data["Target"] = Variant(coopRoom_.vote.target or 0)
        network:BroadcastRemoteEvent(Shared.EVENTS.VOTE_RESULT, true, data)

        -- 如果踢人投票通过
        if result == "passed" and coopRoom_.vote.type == "kick" then
            local kickSlot = coopRoom_.vote.target
            if kickSlot and players_[kickSlot] then
                local kickConn = GetConnectionForSlot(kickSlot)
                if kickConn then
                    kickConn:Disconnect()
                end
                print(string.format("[Server] Slot %d kicked by vote", kickSlot))
            end
        end

        -- 重置投票
        coopRoom_.vote = { active = false }
    end
end

--- 房间设置（房主操作）
function HandleRoomSettings(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot or not players_[slot] then return end

    -- 只有房主可以修改设置
    if not IsHost(slot) then return end

    local setting = eventData["Setting"]:GetString()
    local value = eventData["Value"]:GetString()

    if not coopRoom_ then return end

    if setting == "difficulty" then
        CoopSystem.SetDifficulty(coopRoom_, value)
        print(string.format("[Server] Room difficulty set to: %s", value))
    elseif setting == "password" then
        coopRoom_.password = value
        print("[Server] Room password updated")
    elseif setting == "kick" then
        -- 房主直接踢人
        local kickSlot = tonumber(value)
        if kickSlot and players_[kickSlot] and kickSlot ~= slot then
            local kickConn = GetConnectionForSlot(kickSlot)
            if kickConn then
                kickConn:Disconnect()
            end
            print(string.format("[Server] Host kicked slot %d", kickSlot))
        end
    end

    -- 广播设置变更
    local data = VariantMap()
    data["Setting"] = Variant(setting)
    data["Value"] = Variant(value)
    network:BroadcastRemoteEvent(Shared.EVENTS.ROOM_SETTINGS, true, data)
end

--- 重连处理
function HandleReconnect(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local token = eventData["Token"]:GetString()

    -- 查找匹配的重连令牌
    local tokenData = reconnectTokens_[token]
    local reconnSlot = tokenData and tokenData.slot or nil
    local success, savedData = false, nil
    if reconnSlot and coopRoom_ then
        success, savedData = CoopSystem.TryReconnect(coopRoom_, reconnSlot, token, gameTime)
    end

    local data = VariantMap()
    if success and reconnSlot then
        local slot = reconnSlot
        -- 恢复玩家控制
        if players_[slot] then
            players_[slot].connKey = connKey
            players_[slot].isAI = false
            connections_[connKey] = slot
            connObjects_[connKey] = connection
            readyCount_ = readyCount_ + 1

            connection.scene = scene_
            connection:SetPulseButtonMask(Shared.PULSE_MASK)

            data["Success"] = Variant(true)
            data["Slot"] = Variant(slot)
            data["Role"] = Variant(players_[slot].role or "")
            connection:SendRemoteEvent(Shared.EVENTS.RECONNECT_RESULT, true, data)

            -- 发送GAME_START让客户端恢复
            local startData = VariantMap()
            startData["Phase"] = Variant(gameState.currentScene == GameState.SCENE_PORT and Shared.PHASE.PORT or Shared.PHASE.DEEP_SEA)
            connection:SendRemoteEvent(Shared.EVENTS.GAME_START, true, startData)

            -- 清除令牌
            reconnectTokens_[token] = nil
            print(string.format("[Server] Player reconnected to slot %d", slot))
        else
            data["Success"] = Variant(false)
            data["Reason"] = Variant("slot_invalid")
            connection:SendRemoteEvent(Shared.EVENTS.RECONNECT_RESULT, true, data)
        end
    else
        data["Success"] = Variant(false)
        data["Reason"] = Variant("token_expired")
        connection:SendRemoteEvent(Shared.EVENTS.RECONNECT_RESULT, true, data)
    end
end

--- 观战切换目标
function HandleSpectateSwitch(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot then return end

    if not coopSpectators_[slot] or not coopSpectators_[slot].active then return end

    local direction = eventData["Direction"]:GetInt()  -- 1=下一个, -1=上一个
    local freeView = eventData["FreeView"]:GetBool()

    if freeView then
        CoopSystem.ToggleFreeView(coopSpectators_[slot])
    else
        -- 切换到下一个/上一个存活玩家
        local current = coopSpectators_[slot].target or 1
        local found = false
        local dir = direction > 0 and 1 or -1
        for step = 1, MAX_PLAYERS do
            local next = ((current - 1 + dir * step) % MAX_PLAYERS) + 1
            if players_[next] and not (coopHealth_[next] and coopHealth_[next].isDead) and next ~= slot then
                CoopSystem.SwitchSpectateTarget(coopSpectators_[slot], next)
                found = true
                break
            end
        end
    end
end

--- 观战者提示（死后给存活者发信息）
function HandleSpectateHint(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot then return end

    if not coopSpectators_[slot] or not coopSpectators_[slot].active then return end

    local message = eventData["Message"]:GetString()
    local targetSlot = eventData["Target"]:GetInt()

    -- 验证提示冷却
    if not CoopSystem.CanSendHint(coopSpectators_[slot], gameTime) then return end
    CoopSystem.UseHint(coopSpectators_[slot])

    -- 发送给目标玩家
    local targetConn = GetConnectionForSlot(targetSlot)
    if targetConn then
        local data = VariantMap()
        data["From"] = Variant(slot)
        data["Message"] = Variant(message or "")
        targetConn:SendRemoteEvent(Shared.EVENTS.SPECTATE_HINT, true, data)
    end

    print(string.format("[Server] Spectator slot %d hint to slot %d: %s", slot, targetSlot, message))
end

--- 网络延迟测量（Ping）
function HandleNetPing(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    if not connKey then return end

    -- 立即回Pong
    local data = VariantMap()
    data["T"] = eventData["T"]  -- 原样返回时间戳
    connection:SendRemoteEvent(Shared.EVENTS.NET_PONG, true, data)
end

--- 暂停游戏（房主操作）
function HandlePauseGame(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot then return end

    if not IsHost(slot) then return end
    if not coopRoom_ then return end

    CoopSystem.PauseGame(coopRoom_, slot)

    local data = VariantMap()
    data["Paused"] = Variant(true)
    data["By"] = Variant(slot)
    network:BroadcastRemoteEvent(Shared.EVENTS.PAUSE_GAME, true, data)
    print("[Server] Game paused by host")
end

--- 恢复游戏（房主操作）
function HandleResumeGame(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local slot = connections_[connKey]
    if not slot then return end

    if not IsHost(slot) then return end
    if not coopRoom_ then return end

    CoopSystem.ResumeGame(coopRoom_, slot)

    local data = VariantMap()
    data["Paused"] = Variant(false)
    data["By"] = Variant(slot)
    network:BroadcastRemoteEvent(Shared.EVENTS.RESUME_GAME, true, data)
    print("[Server] Game resumed by host")
end

return Server
