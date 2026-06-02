--- 潜艇深海生存 - 客户端
--- 负责：发送输入、接收快照、渲染所有画面

local Shared = require("network.Shared")
local Config = require("Config")
local cjson = require("cjson")

-- 渲染模块
local Background = require("render.Background")
local SubHull = require("render.SubHull")
local Compartments = require("render.Compartments")
local Lighting = require("render.Lighting")
local Water = require("render.Water")
local CrewMember = require("render.CrewMember")
local HUD = require("HUD")
local Sonar = require("render.Sonar")
local ShakeEffect = require("render.ShakeEffect")
local SoundWave = require("render.SoundWave")
local ExternalView = require("render.ExternalView")
local PressureEffect = require("render.PressureEffect")
local CrisisEffects = require("render.CrisisEffects")
local AlertSystem = require("render.AlertSystem")
local Monsters = require("render.Monsters")
local TurretView = require("render.TurretView")
local PowerPanel = require("render.PowerPanel")
local ReactorPanel = require("render.ReactorPanel")
local InventoryPanel = require("render.InventoryPanel")
local PortView = require("render.PortView")
local EVAView = require("render.EVAView")
local EVASystem = require("EVASystem")
local Cockpit = require("render.Cockpit")
local NavMap = require("render.NavMap")
local GameState = require("GameState")
local PortScene = require("PortScene")
local Submarine = require("Submarine")
local Inventory = require("Inventory")
local Crafting = require("Crafting")
local CommandWheel = require("CommandWheel")
local AICrew = require("AICrew")
local QuickCommands = require("QuickCommands")
local CoopSystem = require("CoopSystem")
local AudioManager = require("AudioManager")

require "LuaScripts/Utilities/Sample"
require "urhox-libs.UI.VirtualControls"
local TouchControls = require("TouchControls")

local Client = {}

local MAX_PLAYERS = 4

-- ============================================================
-- 客户端状态
-- ============================================================
local scene_ = nil
local serverConnection_ = nil

-- NanoVG
local vg = nil
local fontSans = -1

-- 屏幕
local screenW = 1280
local screenH = 720
local dpr = 1.0

-- 游戏时间（本地渲染用）
local gameTime = 0

-- 本地玩家信息
local mySlot_ = 0
local myRole_ = nil

-- 当前快照（从服务端接收）
local snapshot_ = nil
local phase_ = Shared.PHASE.TITLE  -- 初始为标题画面
local titleDismissed_ = false       -- 标题画面是否已关闭

-- 连接状态
local matchConnected_ = false

-- 职业选择
local roleStatus_ = {}     -- 大厅中各槽位职业状态
local selectedRoleIdx_ = 1 -- 本地选中的职业索引

-- 物品栏/合成本地状态
local inventoryOpen_ = false
local selectedRecipe_ = 1

-- 摇杆
local joystick = nil

-- 视角切换（本地状态）
local isExternalView = false
local isTurretView = false
local cameraX = 0

-- AI指令轮盘
local cmdWheel_ = CommandWheel.Create()

-- ============================================================
-- 合作系统客户端状态
-- ============================================================
local qcWheel_ = QuickCommands.CreateWheel()
local qcMessages_ = QuickCommands.CreateMessageQueue()
local qcChat_ = QuickCommands.CreateChatInput()
local netQuality_ = CoopSystem.CreateNetQuality()

-- 观战状态
local spectateState_ = nil   -- nil=未观战, CoopSystem.CreateSpectateState()
local spectateTarget_ = 0    -- 当前观战目标槽位

-- 交易状态
local tradeOffer_ = nil      -- 收到的交易提议 {fromSlot, itemId, count, timeout}
local tradeResult_ = nil     -- 交易结果消息 {text, timer}

-- 投票状态
local voteActive_ = nil      -- 当前活跃投票 {type, initiator, target, yesCount, noCount, timeout, voted}
local voteResult_ = nil      -- 投票结果消息 {text, timer}

-- 救援/倒地状态
local myDowned_ = false       -- 本地是否倒地
local rescueInfo_ = nil       -- 正在被救援的信息 {rescuer, action, progress}
local downedPlayers_ = {}     -- {[slot] = true} 标记哪些玩家倒地

-- 暂停状态
local isPaused_ = false
local pauseSlot_ = 0         -- 谁暂停的

-- 网络延迟测量
local pingTimer_ = 0
local pingSentTime_ = 0
local PING_INTERVAL = 3.0    -- 每3秒测一次延迟

-- 驾驶本地状态（船长专属UI交互）
local drivingState = {
    helmDragging = false,     -- 是否正在拖动舵盘
    helmAngle = 0,            -- 本地舵盘角度（平滑显示用）
    throttleGear = 2,         -- 本地油门档位（显示用，0=R,1=Stop,2-5=Gear1-4）
    targetDepth = 2400,       -- 本地目标深度
    depthDragging = false,    -- 是否在拖动深度滑块
    searchlightAngle = 0,     -- 探照灯角度
    searchlightDragging = false,
    navMapOpen = false,       -- 导航地图是否展开
    cockpitVisible = false,   -- 驾驶舱面板是否可见（船长在驾驶室时）
}

-- 港口本地状态
local portScene = nil
local gameState = nil

-- 港口列表滚动拖动状态
local portScrollDrag = {
    active = false,     -- 是否正在拖动
    startY = 0,        -- 触摸起始Y
    lastY = 0,         -- 上一帧Y
    totalDY = 0,       -- 累计移动距离（判断是否为滚动而非点击）
    touchId = -1,      -- 跟踪的触摸ID
}
local SCROLL_THRESHOLD = 10  -- 超过此距离视为滚动（不触发点击）

-- ============================================================
-- 入口
-- ============================================================
function Client.Start()
    SampleStart()
    SampleInitMouseMode(MM_ABSOLUTE)

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    Shared.RegisterEvents()

    -- 匹配完成后脚本才加载，此时连接已建立
    serverConnection_ = network:GetServerConnection()
    if serverConnection_ then
        serverConnection_.scene = scene_
        serverConnection_:SendRemoteEvent(Shared.EVENTS.CLIENT_READY, true)
        matchConnected_ = true
    end
    phase_ = Shared.PHASE.TITLE  -- 标题画面是第一个看到的页面

    -- 获取屏幕
    local graphics = GetGraphics()
    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()

    -- NanoVG
    vg = nvgCreate(1)
    fontSans = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- 封面图纹理（标题画面用）
    titleCoverImg = nvgCreateImage(vg, "image/game_cover_20260528030232.png", 0)

    -- 初始化音频系统
    AudioManager.Init(scene_)
    AudioManager.UpdatePhaseMusic(phase_)

    -- 初始化背景和渲染模块
    local logW = screenW / dpr
    local logH = screenH / dpr
    Background.Init(logW, logH)

    -- 港口本地状态（用于渲染）
    portScene = PortScene.Create()
    gameState = GameState.Create()

    -- 初始化虚拟控件系统
    VirtualControls.Initialize()

    -- 先初始化触屏按钮（内部会 Clear 所有控件）
    TouchControls.Init()
    TouchControls.HideAll()  -- 标题画面不显示任何按钮

    -- 再创建摇杆（这样不会被 Init 清掉）
    joystick = VirtualControls.CreateJoystick({
        position = Vector2(200, -200),
        alignment = {HA_LEFT, VA_BOTTOM},
        baseRadius = 120,
        knobRadius = 50,
        moveRadius = 80,
        deadZone = 0.15,
        keyBinding = "WASD",
        opacity = 0.6,
    })

    -- 订阅事件
    SubscribeToEvent(Shared.EVENTS.ASSIGN_ROLE,  "HandleAssignRole")
    SubscribeToEvent(Shared.EVENTS.GAME_SNAPSHOT,"HandleGameSnapshot")
    SubscribeToEvent(Shared.EVENTS.GAME_START,   "HandleGameStart")
    SubscribeToEvent(Shared.EVENTS.ROLE_LOCKED,  "HandleRoleLocked")
    SubscribeToEvent(Shared.EVENTS.PLAYER_JOINED,"HandlePlayerJoined")
    SubscribeToEvent(Shared.EVENTS.PLAYER_LEFT,  "HandlePlayerLeft")

    -- 合作系统事件
    SubscribeToEvent(Shared.EVENTS.QUICK_COMMAND,   "HandleQuickCommandReceived")
    SubscribeToEvent(Shared.EVENTS.TRADE_OFFER,     "HandleTradeOfferReceived")
    SubscribeToEvent(Shared.EVENTS.TRADE_RESULT,    "HandleTradeResultReceived")
    SubscribeToEvent(Shared.EVENTS.RESCUE_UPDATE,   "HandleRescueUpdateReceived")
    SubscribeToEvent(Shared.EVENTS.VOTE_START,      "HandleVoteStartReceived")
    SubscribeToEvent(Shared.EVENTS.VOTE_RESULT,     "HandleVoteResultReceived")
    SubscribeToEvent(Shared.EVENTS.RECONNECT_RESULT,"HandleReconnectResult")
    SubscribeToEvent(Shared.EVENTS.SPECTATE_HINT,   "HandleSpectateHintReceived")
    SubscribeToEvent(Shared.EVENTS.PLAYER_DOWNED,   "HandlePlayerDownedReceived")
    SubscribeToEvent(Shared.EVENTS.PLAYER_DEAD,     "HandlePlayerDeadReceived")
    SubscribeToEvent(Shared.EVENTS.PLAYER_REVIVED,  "HandlePlayerRevivedReceived")
    SubscribeToEvent(Shared.EVENTS.NET_PONG,        "HandleNetPongReceived")
    SubscribeToEvent(Shared.EVENTS.PAUSE_GAME,      "HandlePauseReceived")
    SubscribeToEvent(Shared.EVENTS.RESUME_GAME,     "HandleResumeReceived")

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("ServerDisconnected", "HandleServerDisconnected")

    print("[Client] Submarine Co-op Client started")
end

function Client.Stop()
    if vg then nvgDelete(vg); vg = nil end
    TouchControls.Clear()
    VirtualControls.Shutdown()
end

-- ============================================================
-- 网络事件处理
-- ============================================================

function HandleAssignRole(eventType, eventData)
    mySlot_ = eventData["Slot"]:GetInt()
    local rolesJson = eventData["Roles"]:GetString()
    roleStatus_ = cjson.decode(rolesJson)
    print(string.format("[Client] Assigned slot %d", mySlot_))
end

function HandleGameSnapshot(eventType, eventData)
    local jsonStr = eventData["Data"]:GetString()
    snapshot_ = cjson.decode(jsonStr)
    local newPhase = snapshot_.phase or Shared.PHASE.LOBBY
    -- 标题画面是纯客户端状态，不被服务器快照覆盖
    if phase_ == Shared.PHASE.TITLE then
        -- 保存快照但不切换 phase
    else
        if newPhase ~= phase_ then
            phase_ = newPhase
            AudioManager.UpdatePhaseMusic(phase_)
        else
            phase_ = newPhase
        end
    end

    -- 同步金币到本地渲染用 gameState
    if snapshot_.gold then
        gameState.gold = snapshot_.gold
    end

    -- 同步任务到本地 gameState（服务端确认后即时反映）
    if snapshot_.mission then
        gameState.currentMission = snapshot_.mission
    else
        gameState.currentMission = nil
    end

    -- 同步补给品到本地 gameState（购买后即时反映）
    if snapshot_.supplies then
        gameState.supplies = snapshot_.supplies
    end

    -- 同步驾驶数据到本地状态（用于UI显示）
    if snapshot_.sub and snapshot_.sub.driving then
        local drv = snapshot_.sub.driving
        -- 平滑本地舵盘角度（非拖动时跟随服务器）
        if not drivingState.helmDragging then
            drivingState.helmAngle = drv.helmAngle or 0
        end
        drivingState.throttleGear = drv.throttleGear or 2
        drivingState.searchlightAngle = drv.searchlightAngle or 0
    end
    if snapshot_.sub and snapshot_.sub.physics then
        local phys = snapshot_.sub.physics
        -- 非拖动时跟随服务器深度
        if not drivingState.depthDragging then
            drivingState.targetDepth = phys.targetDepth or 2400
        end
    end

    -- 判断驾驶舱是否可见（船长在驾驶室/第1舱）
    if myRole_ == "captain" and snapshot_.players and snapshot_.players[mySlot_] then
        local myPlayer = snapshot_.players[mySlot_]
        local room = myPlayer.room or 1
        drivingState.cockpitVisible = (room == 1)  -- 舱室1=驾驶室
    else
        drivingState.cockpitVisible = false
    end
end

function HandleGameStart(eventType, eventData)
    local startPhase = eventData["Phase"]:GetString()
    phase_ = startPhase
    print("[Client] Game started! Phase: " .. startPhase)
end

function HandleRoleLocked(eventType, eventData)
    -- 可能含 Success 字段（选择失败）或 Roles 字段（状态更新）
    local rolesStr = eventData["Roles"]:GetString()
    if rolesStr and rolesStr ~= "" then
        roleStatus_ = cjson.decode(rolesStr)
    end
end

function HandlePlayerJoined(eventType, eventData)
    local slot = eventData["Slot"]:GetInt()
    print("[Client] Player joined slot " .. slot)
end

function HandlePlayerLeft(eventType, eventData)
    local slot = eventData["Slot"]:GetInt()
    print("[Client] Player left slot " .. slot)
end

function HandleServerDisconnected(eventType, eventData)
    print("[Client] Disconnected from server!")
    serverConnection_ = nil
    matchConnected_ = false
    phase_ = Shared.PHASE.LOBBY
end



-- ============================================================
-- 每帧更新：发送输入
-- ============================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    gameTime = gameTime + dt

    -- 重置一次性触摸动作
    TouchControls.ResetActions()

    if not serverConnection_ then return end

    -- 构建输入（从触屏按钮和摇杆读取）
    local buttons = 0
    local yaw = 0.0

    -- 摇杆输入
    local jx = 0
    local jy = 0
    if joystick then
        jx = joystick.x or 0
        jy = joystick.y or 0
    end

    -- 摇杆 → 方向按钮位
    if jx < -0.3 then buttons = buttons | Shared.CTRL.LEFT end
    if jx > 0.3 then buttons = buttons | Shared.CTRL.RIGHT end
    if jy < -0.3 then buttons = buttons | Shared.CTRL.UP end
    if jy > 0.3 then buttons = buttons | Shared.CTRL.DOWN end

    -- 触屏按钮 → 动作按钮位
    if TouchControls.held.repair then buttons = buttons | Shared.CTRL.REPAIR end
    if TouchControls.actions.pickup then buttons = buttons | Shared.CTRL.INTERACT end
    if TouchControls.actions.eva or TouchControls.actions.evaReturn then buttons = buttons | Shared.CTRL.EVA_EXIT end
    if TouchControls.actions.escape then buttons = buttons | Shared.CTRL.ESCAPE end
    if TouchControls.actions.power then buttons = buttons | Shared.CTRL.POWER_TOGGLE end
    if TouchControls.actions.powerUp then buttons = buttons | Shared.CTRL.POWER_UP end
    if TouchControls.actions.powerDown then buttons = buttons | Shared.CTRL.POWER_DOWN end
    if TouchControls.held.powerInc then buttons = buttons | Shared.CTRL.POWER_INC end
    if TouchControls.held.powerDec then buttons = buttons | Shared.CTRL.POWER_DEC end

    -- 跳跃（触屏按钮 或 键盘空格）
    if TouchControls.actions.jump or input:GetKeyPress(KEY_SPACE) then
        buttons = buttons | Shared.CTRL.JUMP
    end

    -- 触摸射击（炮塔模式点击屏幕）
    if TouchControls.actions.fire or input:GetMouseButtonDown(MOUSEB_LEFT) then
        if isTurretView then
            buttons = buttons | Shared.CTRL.SHOOT
        end
    end

    -- 物品栏/合成操作
    if TouchControls.actions.inventory then
        buttons = buttons | Shared.CTRL.INVENTORY
        inventoryOpen_ = not inventoryOpen_
    end
    if TouchControls.actions.craftPrev then
        buttons = buttons | Shared.CTRL.CRAFT_PREV
        local recipeCount = Crafting.GetRecipeCount and Crafting.GetRecipeCount() or 5
        selectedRecipe_ = selectedRecipe_ - 1
        if selectedRecipe_ < 1 then selectedRecipe_ = recipeCount end
    end
    if TouchControls.actions.craftNext then
        buttons = buttons | Shared.CTRL.CRAFT_NEXT
        local recipeCount = Crafting.GetRecipeCount and Crafting.GetRecipeCount() or 5
        selectedRecipe_ = selectedRecipe_ + 1
        if selectedRecipe_ > recipeCount then selectedRecipe_ = 1 end
    end
    if TouchControls.actions.craftConfirm then
        buttons = buttons | Shared.CTRL.CRAFT_CONFIRM
        -- 发送合成远程事件（带配方索引）
        if serverConnection_ then
            local data = VariantMap()
            data["RecipeIdx"] = Variant(selectedRecipe_)
            serverConnection_:SendRemoteEvent(Shared.EVENTS.CRAFT_ITEM, true, data)
        end
    end

    -- 门/舷窗/水泵交互
    if TouchControls.actions.doorOpen then buttons = buttons | Shared.CTRL.DOOR_OPEN end
    if TouchControls.actions.doorLock then buttons = buttons | Shared.CTRL.DOOR_LOCK end
    if TouchControls.held.pressureBalance then buttons = buttons | Shared.CTRL.PRESSURE_BAL end
    if TouchControls.actions.pumpToggle then buttons = buttons | Shared.CTRL.PUMP_TOGGLE end
    if TouchControls.actions.portholeView then buttons = buttons | Shared.CTRL.PORTHOLE_VIEW end
    if TouchControls.actions.portholeCover then buttons = buttons | Shared.CTRL.PORTHOLE_COVER end

    -- 驾驶系统输入（船长 + 工程师/机械师压载水舱）
    if TouchControls.actions.throttleUp then buttons = buttons | Shared.CTRL.THROTTLE_UP end
    if TouchControls.actions.throttleDown then buttons = buttons | Shared.CTRL.THROTTLE_DOWN end
    if TouchControls.actions.sonarPulse then buttons = buttons | Shared.CTRL.SONAR_PULSE end
    if TouchControls.actions.searchlight then buttons = buttons | Shared.CTRL.SEARCHLIGHT end
    if TouchControls.held.ballastFill then buttons = buttons | Shared.CTRL.BALLAST_FILL end
    if TouchControls.held.ballastDrain then buttons = buttons | Shared.CTRL.BALLAST_DRAIN end
    if TouchControls.actions.ballastEmerg then buttons = buttons | Shared.CTRL.BALLAST_EMERG end
    -- 导航地图开关
    if TouchControls.actions.navMap then
        drivingState.navMapOpen = not drivingState.navMapOpen
    end

    -- yaw/pitch 用途取决于角色和驾驶状态
    -- 船长在驾驶室：yaw = 舵盘角度，pitch = 目标深度（归一化0~1）
    local pitch = 0
    if myRole_ == "captain" and drivingState.cockpitVisible then
        yaw = drivingState.helmAngle  -- -90 ~ +90 来自舵盘拖动
        -- 深度归一化：(depth - min) / (max - min)
        local depthMin = Config.Driving.depth.minDepth
        local depthMax = Config.Driving.depth.maxDepth
        pitch = (drivingState.targetDepth - depthMin) / (depthMax - depthMin)
        pitch = math.max(0, math.min(1, pitch))
    else
        -- 非驾驶模式：yaw 用于移动方向
        yaw = jx * 90.0  -- -90 ~ +90 映射
    end

    serverConnection_.controls.buttons = buttons
    serverConnection_.controls.yaw = yaw
    serverConnection_.controls.pitch = pitch

    -- 本地视角切换（触屏按钮）
    if TouchControls.actions.extView then
        isExternalView = not isExternalView
    end
    if TouchControls.actions.turret then
        isTurretView = not isTurretView
        if isTurretView then
            isExternalView = false
            TouchControls.ShowTurret()
        else
            TouchControls.ShowDeepSea()
        end
    end

    -- 场景按钮组切换（基于快照phase）
    if phase_ == Shared.PHASE.TITLE then
        -- 标题画面不显示任何控件
        if TouchControls.GetActiveGroup() ~= nil then
            TouchControls.HideAll()
        end
    elseif phase_ == Shared.PHASE.DEEP_SEA then
        if TouchControls.GetActiveGroup() ~= "deepsea" and TouchControls.GetActiveGroup() ~= "turret" then
            TouchControls.ShowDeepSea()
        end
    elseif phase_ == Shared.PHASE.EVA then
        if TouchControls.GetActiveGroup() ~= "eva" then
            TouchControls.ShowEVA()
        end
    elseif phase_ == Shared.PHASE.PORT then
        if TouchControls.GetActiveGroup() ~= "port" then
            TouchControls.ShowPort()
        end
        -- 更新港口提示消息倒计时
        PortScene.Update(portScene, dt)
    elseif phase_ == Shared.PHASE.LOBBY then
        if TouchControls.GetActiveGroup() ~= "lobby" then
            TouchControls.ShowLobby()
        end
    end

    -- 更新指令轮盘动画
    CommandWheel.Update(cmdWheel_, dt)

    -- 摄像机跟随玩家角色
    if snapshot_ and snapshot_.players and snapshot_.players[mySlot_] then
        local myPlayer = snapshot_.players[mySlot_]
        local targetX = (myPlayer.x or 0) - (screenW / dpr) * 0.5
        -- 限制摄像机范围（不超出潜艇边界）
        targetX = math.max(0, targetX)
        -- 平滑跟随
        cameraX = cameraX + (targetX - cameraX) * math.min(1, dt * 5)
    end

    -- 合作系统更新
    QuickCommands.UpdateWheel(qcWheel_, dt)
    QuickCommands.UpdateMessages(qcMessages_, gameTime)
    QuickCommands.UpdateChatInput(qcChat_, dt)

    -- 交易结果消息倒计时
    if tradeResult_ then
        tradeResult_.timer = tradeResult_.timer - dt
        if tradeResult_.timer <= 0 then tradeResult_ = nil end
    end
    -- 投票结果消息倒计时
    if voteResult_ then
        voteResult_.timer = voteResult_.timer - dt
        if voteResult_.timer <= 0 then voteResult_ = nil end
    end
    -- 交易提议超时
    if tradeOffer_ then
        tradeOffer_.timeout = tradeOffer_.timeout - dt
        if tradeOffer_.timeout <= 0 then tradeOffer_ = nil end
    end

    -- 网络延迟测量
    pingTimer_ = pingTimer_ + dt
    if pingTimer_ >= PING_INTERVAL and serverConnection_ then
        pingTimer_ = 0
        pingSentTime_ = os.clock()
        serverConnection_:SendRemoteEvent(Shared.EVENTS.NET_PING, true)
    end

    -- 从快照同步合作数据
    if snapshot_ and snapshot_.coop then
        local coop = snapshot_.coop
        -- 暂停状态
        isPaused_ = coop.isPaused or false
        pauseSlot_ = coop.pauseSlot or 0
        -- 投票状态（从快照刷新）
        if coop.vote and coop.vote.active then
            voteActive_ = coop.vote
        elseif not voteActive_ then
            -- 没有活跃投票
        end
        -- 倒地玩家列表
        if coop.health then
            for slot, hp in pairs(coop.health) do
                downedPlayers_[tonumber(slot)] = hp.isDowned or false
            end
        end
    end

    -- 更新渲染模块（动画/粒子等本地效果）
    local logW = screenW / dpr
    local logH = screenH / dpr
    Background.Update(dt, logW, logH, gameTime)
    Sonar.Update(dt, gameTime)
    ShakeEffect.Update(dt, gameTime)
    SoundWave.Update(dt, gameTime)
    PressureEffect.Update(dt, snapshot_ and snapshot_.depth or 2400)
    CrisisEffects.UpdateSparks(dt)
    CrewMember.UpdateRipples(dt)
end

-- ============================================================
-- 渲染
-- ============================================================

function HandleNanoVGRender(eventType, eventData)
    if vg == nil then return end

    local graphics = GetGraphics()
    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()

    local w = screenW / dpr
    local h = screenH / dpr

    nvgBeginFrame(vg, w, h, dpr)

    if phase_ == Shared.PHASE.TITLE then
        DrawTitle(w, h)
    elseif phase_ == Shared.PHASE.LOBBY then
        DrawLobby(w, h)
    elseif phase_ == Shared.PHASE.PORT then
        DrawPort(w, h)
    elseif phase_ == Shared.PHASE.DEEP_SEA or phase_ == Shared.PHASE.EVA then
        DrawDeepSea(w, h)
    else
        DrawLobby(w, h)
    end

    nvgEndFrame(vg)
end


-- ============================================================
-- 标题画面（开始界面）
-- ============================================================
local titleTime_ = 0

function DrawTitle(w, h)
    titleTime_ = titleTime_ + (1.0 / 60.0)

    -- 全屏封面图
    if titleCoverImg and titleCoverImg > 0 then
        local imgPaint = nvgImagePattern(vg, 0, 0, w, h, 0, titleCoverImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    else
        -- fallback 深海渐变背景
        local bg = nvgLinearGradient(vg, 0, 0, 0, h,
            nvgRGBA(5, 10, 30, 255), nvgRGBA(0, 30, 60, 255))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, bg)
        nvgFill(vg)
    end

    -- 半透明暗色叠加（让文字更清晰）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    -- 游戏标题
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题阴影
    nvgFontSize(vg, 36)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgText(vg, w * 0.5 + 2, h * 0.3 + 2, "深海潜航", nil)

    -- 标题主体（带发光感）
    nvgFillColor(vg, nvgRGBA(100, 220, 255, 255))
    nvgText(vg, w * 0.5, h * 0.3, "深海潜航", nil)

    -- 副标题
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 210, 240, 200))
    nvgText(vg, w * 0.5, h * 0.3 + 30, "ABYSSAL VOYAGE", nil)

    -- "点击开始" 闪烁提示
    local alpha = math.floor(150 + 105 * math.sin(titleTime_ * 2.5))
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(220, 240, 255, alpha))
    nvgText(vg, w * 0.5, h * 0.7, "— 点击屏幕开始 —", nil)

    -- 版本号
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 150, 180, 120))
    nvgText(vg, w - 10, h - 10, "v1.0", nil)
end

-- ============================================================
-- 大厅渲染（职业选择）
-- ============================================================

function DrawLobby(w, h)
    -- 深色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(8, 15, 30, 255))
    nvgFill(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
    nvgText(vg, w * 0.5, 30, "深海潜艇 - 选择职业", nil)

    -- 倒计时
    if snapshot_ and snapshot_.timer then
        local remaining = math.max(0, (snapshot_.timeout or 35) - snapshot_.timer)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 180))
        nvgText(vg, w * 0.5, 65, string.format("等待中... %.0f秒后自动开始", remaining), nil)
    end

    -- 在线玩家数
    local onlineCount = 0
    if snapshot_ and snapshot_.players then
        for _ in pairs(snapshot_.players) do onlineCount = onlineCount + 1 end
    end
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(150, 200, 230, 200))
    nvgText(vg, w * 0.5, 85, string.format("我的位置: 玩家 %d  |  房间人数: %d/%d", mySlot_, onlineCount, MAX_PLAYERS), nil)

    -- 职业卡片
    local cardW = 160
    local cardH = 200
    local startX = (w - cardW * 4 - 30 * 3) * 0.5
    local cardY = h * 0.3

    for i, role in ipairs(Shared.ROLES) do
        local cx = startX + (i - 1) * (cardW + 30)
        local isSelected = (i == selectedRoleIdx_)
        local isTaken = false
        local takenBySlot = 0

        -- 检查是否已被选
        for _, ps in pairs(roleStatus_) do
            if ps.role == role.id then
                isTaken = true
                takenBySlot = ps.slot
                break
            end
        end

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cardY, cardW, cardH, 8)
        if isTaken and takenBySlot ~= mySlot_ then
            nvgFillColor(vg, nvgRGBA(40, 40, 50, 200))
        elseif isSelected then
            nvgFillColor(vg, nvgRGBA(30, 60, 100, 240))
        else
            nvgFillColor(vg, nvgRGBA(20, 35, 60, 220))
        end
        nvgFill(vg)

        -- 选中边框
        if isSelected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cardY, cardW, cardH, 8)
            nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 255))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 职业名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
        nvgText(vg, cx + cardW * 0.5, cardY + 15, role.name, nil)

        -- 职业图标（简单几何）
        local iconY = cardY + 55
        DrawRoleIcon(cx + cardW * 0.5, iconY, role.id)

        -- 描述
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(160, 180, 200, 200))
        nvgText(vg, cx + cardW * 0.5, cardY + 110, role.desc, nil)

        -- 状态标签
        if isTaken then
            nvgFontSize(vg, 12)
            if takenBySlot == mySlot_ then
                nvgFillColor(vg, nvgRGBA(100, 220, 100, 255))
                nvgText(vg, cx + cardW * 0.5, cardY + cardH - 25, "已选择", nil)
            else
                nvgFillColor(vg, nvgRGBA(200, 100, 100, 200))
                nvgText(vg, cx + cardW * 0.5, cardY + cardH - 25, "玩家" .. takenBySlot .. "已选", nil)
            end
        end
    end

    -- 底部按钮区域
    local btnY = h - 70
    local btnH = 40

    -- 房主"开始游戏"按钮（slot 1 为房主）
    if mySlot_ == 1 then
        local btnW = 160
        local btnX = (w - btnW) * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
        nvgFillColor(vg, nvgRGBA(40, 160, 80, 240))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
        nvgStrokeColor(vg, nvgRGBA(80, 220, 120, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, btnX + btnW * 0.5, btnY + btnH * 0.5, "开始游戏", nil)
    end

    -- 提示文字
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(150, 180, 210, 140))
    if mySlot_ == 1 then
        nvgText(vg, w * 0.5, h - 15, "点击卡片选择职业 · 点击[开始游戏]立即开始(AI补位)", nil)
    else
        nvgText(vg, w * 0.5, h - 15, "点击卡片选择职业 · 等待房主开始...", nil)
    end
end



--- 绘制职业图标
function DrawRoleIcon(cx, cy, roleId)
    nvgBeginPath(vg)
    if roleId == "captain" then
        -- 船轮
        nvgCircle(vg, cx, cy, 20)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        for a = 0, 5 do
            local angle = a * math.pi / 3
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, cx + math.cos(angle) * 18, cy + math.sin(angle) * 18)
            nvgStroke(vg)
        end
    elseif roleId == "engineer" then
        -- 齿轮
        nvgCircle(vg, cx, cy, 15)
        nvgStrokeColor(vg, nvgRGBA(240, 200, 50, 200))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 8)
        nvgFillColor(vg, nvgRGBA(240, 200, 50, 150))
        nvgFill(vg)
    elseif roleId == "mechanic" then
        -- 扳手
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 12, cy + 12)
        nvgLineTo(vg, cx + 12, cy - 12)
        nvgStrokeColor(vg, nvgRGBA(150, 200, 150, 200))
        nvgStrokeWidth(vg, 4)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx + 12, cy - 12, 6)
        nvgStroke(vg)
    elseif roleId == "medic" then
        -- 十字
        nvgBeginPath(vg)
        nvgRect(vg, cx - 3, cy - 15, 6, 30)
        nvgFillColor(vg, nvgRGBA(220, 80, 80, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, cx - 15, cy - 3, 30, 6)
        nvgFillColor(vg, nvgRGBA(220, 80, 80, 200))
        nvgFill(vg)
    end
end

-- ============================================================
-- 港口渲染
-- ============================================================

function DrawPort(w, h)
    if snapshot_ and snapshot_.port then
        portScene.currentTab = snapshot_.port.tab or 1
        portScene.selectedItem = snapshot_.port.selected or 1
    end
    PortView.Draw(vg, w, h, portScene, gameState, gameTime)

    -- 叠加多人信息
    DrawMultiplayerHUD(w, h)
end

-- ============================================================
-- 深海渲染（使用快照数据）
-- ============================================================

function DrawDeepSea(w, h)
    if not snapshot_ or not snapshot_.sub then
        -- 等待第一个快照
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(5, 10, 20, 255))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 150, 200, 200))
        nvgText(vg, w * 0.5, h * 0.5, "正在同步...", nil)
        return
    end

    -- 检查自己是否在EVA
    local myPlayer = snapshot_.players and snapshot_.players[mySlot_]
    if myPlayer and myPlayer.inEVA and myPlayer.eva then
        DrawMyEVA(w, h, myPlayer.eva)
        return
    end

    -- 构建临时sub用于渲染模块
    local renderSub = BuildRenderSub()

    -- 外部视角模式（潜艇侧面全景 + 探照灯/怪物/地形）
    if isExternalView then
        ExternalView.Draw(vg, w, h, renderSub, gameTime)
        -- 外部视角HUD（简化版）
        HUD.Draw(vg, w, h, renderSub, gameTime, nil)
        -- 导航地图叠加
        if drivingState.navMapOpen and renderSub.navigation then
            NavMap.Draw(vg, w, h, renderSub.navigation, renderSub.physics, gameTime)
        end
        DrawMultiplayerHUD(w, h)
        return
    end

    -- 深海背景
    Background.Draw(vg, w, h, gameTime)

    -- 潜艇内部
    local shakeX, shakeY = ShakeEffect.GetOffset()
    nvgSave(vg)
    nvgTranslate(vg, -cameraX + shakeX, shakeY)

    local thick = Config.Sub.hullThickness
    local subTotalW = 1500 + thick * 2 + 60
    local subH = Config.Sub.hullHeight + thick * 2
    local subX = 30
    local subY = h * 0.5 - subH * 0.5

    SubHull.Draw(vg, subX, subY, subTotalW - 60, subH, gameTime, renderSub)

    local innerX = subX + thick
    local innerY = subY + thick
    local innerH = subH - thick * 2

    Compartments.Draw(vg, innerX, innerY, innerH, renderSub, gameTime)
    Water.Draw(vg, innerX, innerY, innerH, renderSub, gameTime)
    Lighting.Draw(vg, innerX, innerY, innerH, renderSub, gameTime)

    -- 绘制所有玩家角色
    if snapshot_.players then
        for _, p in pairs(snapshot_.players) do
            if not p.inEVA then
                DrawPlayerInSub(p, innerX, innerY, innerH)
            end
        end
    end

    -- AI船员已通过玩家槽位渲染（带职业颜色，无名字标签）

    -- 绘制危机效果（过热/修理中）
    if snapshot_.crises and renderSub then
        for _, c in ipairs(snapshot_.crises) do
            local comp = renderSub.compartments[c.room]
            if comp then
                local compX = innerX + comp.x
                local compY = innerY
                local compW = comp.width
                local compH = innerH
                -- 各类危机房间效果
                if c.type == "overheat" then
                    CrisisEffects.DrawOverheatRoom(vg, compX, compY, compW, compH, gameTime, c.temperature)
                elseif c.type == "fire" then
                    AlertSystem.DrawFireOverlay(vg, compX, compY, compW, compH, 0.5, gameTime)
                elseif c.type == "toxic_gas" then
                    AlertSystem.DrawGasOverlay(vg, compX, compY, compW, compH, 0.5, gameTime)
                elseif c.type == "power_failure" then
                    CrisisEffects.DrawPowerFailureRoom(vg, compX, compY, compW, compH, gameTime)
                elseif c.type == "monster_invasion" then
                    CrisisEffects.DrawMonsterInvasion(vg, compX, compY, compW, compH, gameTime, c.monsterHp or 1.0)
                end
                -- 修理中效果
                if c.repairing and c.type ~= "breach" then
                    CrisisEffects.DrawOperateEffect(vg, compX + compW * 0.5, compY + compH * 0.6, c.type, gameTime)
                end
            end
        end
        CrisisEffects.DrawSparks(vg)

        -- 疯狂效果（检查是否有 crew_madness 类型危机）
        for _, c in ipairs(snapshot_.crises) do
            if c.type == "crew_madness" then
                local sev = c.severity or "minor"
                AlertSystem.DrawMadnessEffect(vg, w, h, sev, gameTime)
                break
            end
        end
    end

    -- 修理进度条（本地玩家正在修理时）
    if snapshot_.myRepair and snapshot_.myRepair.repairing then
        local rep = snapshot_.myRepair
        local isDiagnosing = rep.crisisType == "equipment_malfunction" and not rep.diagnosed
        CrisisEffects.DrawProgressBar(vg, rep.screenX or (w * 0.5), rep.screenY or (h * 0.6), rep.progress or 0, rep.crisisType, isDiagnosing)
    end

    nvgRestore(vg)

    -- 边缘警报（使用 AlertSystem）
    if snapshot_.crises and #snapshot_.crises > 0 then
        local muted = snapshot_.crisisMuted or false
        AlertSystem.DrawEdgeAlert(vg, w, h, snapshot_.crises, gameTime, muted)
    end

    -- 后处理
    SoundWave.Draw(vg, w, h, gameTime)
    PressureEffect.Draw(vg, w, h, gameTime)
    ShakeEffect.DrawFlash(vg, w, h)

    -- 警报横幅（使用 crisisAlerts，包含 time/duration/level/text 字段）
    if snapshot_.crisisAlerts and #snapshot_.crisisAlerts > 0 then
        local muted = snapshot_.crisisMuted or false
        AlertSystem.DrawAlertBanners(vg, w, h, snapshot_.crisisAlerts, gameTime, muted)
    end

    -- HUD
    HUD.Draw(vg, w, h, renderSub, gameTime, nil)

    -- 门/舷窗/水泵交互UI覆盖层
    DrawDoorInteractionUI(w, h, renderSub)

    -- 舷窗查看模式
    DrawPortholeViewOverlay(w, h)

    -- 物品栏面板（从快照数据渲染）
    if snapshot_.inventory then
        local inv = snapshot_.inventory
        InventoryPanel.DrawQuickBar(vg, inv, w, h, gameTime)
        InventoryPanel.DrawPickupHint(vg, inv, w, h, gameTime)
        if inv.isOpen then
            InventoryPanel.DrawFull(vg, inv, w, h, gameTime, selectedRecipe_)
        end
        InventoryPanel.DrawMessage(vg, inv, w, h)
        InventoryPanel.DrawBuffs(vg, inv, w, h, gameTime)
    end

    -- 多人状态栏
    DrawMultiplayerHUD(w, h)

    -- 指令轮盘
    CommandWheel.Draw(vg, cmdWheel_, gameTime)

    -- 驾驶舱面板（船长在驾驶室时显示）
    if drivingState.cockpitVisible and myRole_ == "captain" then
        Cockpit.Draw(vg, w, h, renderSub, drivingState, gameTime)
    end

    -- 压载水舱面板（工程师/机械师显示）
    if myRole_ == "engineer" or myRole_ == "mechanic" then
        if renderSub.ballast then
            Cockpit.DrawBallastPanel(vg, w, h, renderSub.ballast, gameTime)
        end
    end

    -- 反应堆面板（工程师专属，面板打开时显示）
    if myRole_ == "engineer" and snapshot_.reactor and snapshot_.reactor.panelOpen then
        ReactorPanel.Draw(vg, w, h, snapshot_.reactor, gameTime)
    end

    -- 电力分配面板（工程师专属，面板打开时显示）
    if myRole_ == "engineer" and snapshot_.power and snapshot_.power.isOpen then
        PowerPanel.Draw(vg, w, h, snapshot_.power, snapshot_.reactor, gameTime)
    end

    -- 接线断裂警告（全员可见）
    if snapshot_.wiring then
        local sevCount = 0
        for _, cable in ipairs(snapshot_.wiring.cables) do
            if not cable.intact then sevCount = sevCount + 1 end
        end
        if sevCount > 0 then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local blink = math.sin(gameTime * 6) > 0
            if blink then
                nvgFillColor(vg, nvgRGBA(255, 80, 40, 220))
                nvgText(vg, 10, h - 30, string.format("!! %d根线缆断裂 !!", sevCount))
            end
        end
    end

    -- 导航地图叠加层
    if drivingState.navMapOpen and renderSub.navigation then
        NavMap.Draw(vg, w, h, renderSub.navigation, renderSub.physics, gameTime)
    end

    -- ============================================================
    -- 合作系统 UI 叠加层
    -- ============================================================

    -- 快捷指令轮盘
    QuickCommands.DrawWheel(vg, qcWheel_)

    -- 快捷消息队列（左上角消息流）
    QuickCommands.DrawMessages(vg, qcMessages_, w, h)

    -- 聊天输入框
    QuickCommands.DrawChatInput(vg, qcChat_, w, h)

    -- 倒地玩家标记（在各玩家位置显示倒地图标）
    DrawDownedIndicators(w, h)

    -- 交易提议弹窗
    if tradeOffer_ then
        DrawTradeOfferUI(w, h)
    end

    -- 交易结果提示
    if tradeResult_ then
        DrawCoopNotification(w, h, tradeResult_.text, 180, 220, 60)
    end

    -- 投票面板
    if voteActive_ and voteActive_.active then
        DrawVotePanel(w, h)
    end

    -- 投票结果提示
    if voteResult_ then
        DrawCoopNotification(w, h, voteResult_.text, 255, 200, 60)
    end

    -- 观战模式 UI
    if spectateState_ then
        DrawSpectateUI(w, h)
    end

    -- 暂停覆盖层
    if isPaused_ then
        DrawPauseOverlay(w, h)
    end

    -- 网络质量指示器
    DrawNetQualityIndicator(w, h)

    -- 自己倒地时的全屏效果
    if myDowned_ then
        DrawDownedOverlay(w, h)
    end

    -- 深度
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(80, 160, 200, 150))
    nvgText(vg, w - 20, 60, string.format("DEPTH: %dm", snapshot_.depth or 0), nil)
end

--- 绘制自己的EVA视角
function DrawMyEVA(w, h, evaData)
    -- 构建临时eva状态用于渲染
    local tempEva = {
        phase = evaData.phase,
        isActive = true,
        x = evaData.x,
        y = evaData.y,
        oxygen = evaData.oxygen,
        facing = evaData.facing,
        vx = 0, vy = 0,
        angle = 0,
        swimAnim = gameTime * 3,
        bubbles = {},
        headlightOn = true,
        nearLoot = nil,
        collectedLoot = {},
        oxygenWarning = evaData.oxygen < EVASystem.Config.criticalOxygen,
    }

    -- 构建临时世界
    local tempWorld = { ruins = {}, loots = {} }

    local dt = 1.0 / 60.0
    EVAView.Draw(vg, screenW / dpr, screenH / dpr, tempEva, tempWorld, gameTime, dt)

    -- 叠加其他EVA玩家标记
    if snapshot_ and snapshot_.players then
        for slot, p in pairs(snapshot_.players) do
            if slot ~= mySlot_ and p.inEVA and p.eva then
                DrawOtherEVAPlayer(p, evaData)
            end
        end
    end
end

--- 绘制其他EVA玩家标记
function DrawOtherEVAPlayer(otherPlayer, myEva)
    -- 相对位置（基于相机偏移）
    local w = screenW / dpr
    local h = screenH / dpr
    local relX = (otherPlayer.eva.x - myEva.x) + w * 0.5
    local relY = (otherPlayer.eva.y - myEva.y) + h * 0.5

    if relX > -50 and relX < w + 50 and relY > -50 and relY < h + 50 then
        -- 简单标记
        nvgBeginPath(vg)
        nvgCircle(vg, relX, relY, 8)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 150))
        nvgFill(vg)

        -- 职业标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
        local roleName = otherPlayer.role or "?"
        local roleInfo = Shared.GetRoleInfo(roleName)
        nvgText(vg, relX, relY - 12, roleInfo and roleInfo.name or roleName, nil)
    end
end

--- 绘制潜艇内的玩家角色（使用 CrewMember 完整渲染）
-- 角色颜色按职业区分
local roleColors = {
    captain  = {50, 100, 180},
    engineer = {180, 160, 50},
    mechanic = {50, 160, 80},
    medic    = {180, 60, 60},
}

function DrawPlayerInSub(playerData, innerX, innerY, innerH)
    -- Y轴偏移：server中 y=0是地面, y<0是空中(跳跃)
    -- NanoVG中y向下为正，所以直接加player.y即可让角色向上偏移
    local yOffset = playerData.y or 0

    -- 构建 CrewMember 兼容的 char 对象
    local char = {
        x = playerData.x or 100,
        facing = playerData.facing or 1,
        animState = playerData.animState or "idle",
        animTime = gameTime or 0,
    }

    local suitColor = roleColors[playerData.role] or {120, 120, 140}

    -- AI玩家不显示名字标签，只通过颜色区分
    local name = nil
    local stateText = nil
    if playerData.isAI then
        name = nil
        stateText = nil
    elseif playerData.slot == mySlot_ then
        name = "我"
    end

    -- 应用Y偏移渲染角色（yOffset<0时角色向上移）
    local adjustedInnerH = innerH + yOffset

    -- 使用 CrewMember 的完整角色绘制
    CrewMember.DrawCharacter(vg, char, innerX, innerY, adjustedInnerH, char.animTime, suitColor, name, stateText)

    -- 我的标记（蓝色小三角）
    if playerData.slot == mySlot_ then
        local x = innerX + char.x
        local floorY = innerY + adjustedInnerH - 8
        local charH = Config.Crew.height
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, floorY - charH - 35)
        nvgLineTo(vg, x - 5, floorY - charH - 42)
        nvgLineTo(vg, x + 5, floorY - charH - 42)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(80, 220, 255, 220))
        nvgFill(vg)
    end
end

-- ============================================================
-- 门/舷窗/水泵 交互UI
-- ============================================================

--- 绘制门交互浮层（靠近门时显示按钮和进度条）
function DrawDoorInteractionUI(w, h, renderSub)
    if not snapshot_ or not snapshot_.players then return end
    local myPlayer = snapshot_.players[mySlot_]
    if not myPlayer or myPlayer.inEVA then return end

    local centerX = w * 0.5
    local baseY = h - 120  -- 底部按钮区上方

    -- 门交互消息（气压差警告等）
    if myPlayer.doorMsg then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 120, 80, 240))
        nvgText(vg, centerX, baseY - 50, myPlayer.doorMsg, nil)
    end

    -- 气压减益警告
    if myPlayer.pressureDebuff then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 80, 80, math.floor(160 + 80 * math.sin(gameTime * 4))))
        nvgText(vg, centerX, 40, "⚠ 低气压区域 - 移动减速", nil)
    end

    -- 查找玩家附近的门/舷窗/水泵（基于renderSub中的位置）
    local playerX = myPlayer.x or 0
    local thick = Config.Sub.hullThickness

    -- 附近的门上下文按钮
    if renderSub and renderSub.doors then
        for i, door in ipairs(renderSub.doors) do
            local doorX = door.x or 0
            local dist = math.abs(playerX - doorX)
            if dist < Config.Door.interactRange then
                DrawDoorButtons(w, h, door, baseY)
                break  -- 只显示最近一扇门的操作
            end
        end
    end

    -- 附近的舷窗上下文按钮
    if renderSub and renderSub.portholes then
        for i, ph in ipairs(renderSub.portholes) do
            -- 计算舷窗绝对像素位置
            local comp = renderSub.compartments[ph.room]
            local phX = comp and (comp.x + (ph.xOffset or 0.5) * comp.width) or 0
            local dist = math.abs(playerX - phX)
            if dist < Config.Porthole.interactRange then
                DrawPortholeButtons(w, h, ph, baseY - 80)
                break
            end
        end
    end

    -- 附近的水泵上下文按钮
    if renderSub and renderSub.pumps then
        for i, pump in ipairs(renderSub.pumps) do
            local pumpRoom = pump.room
            -- 检查玩家是否在水泵所在舱室
            if renderSub.compartments[pumpRoom] then
                local comp = renderSub.compartments[pumpRoom]
                local compLeft = comp.x
                local compRight = comp.x + comp.width
                if playerX >= compLeft and playerX <= compRight then
                    DrawPumpButton(w, h, pump, baseY - 80)
                    break
                end
            end
        end
    end
end

--- 绘制门操作按钮
function DrawDoorButtons(w, h, door, baseY)
    local centerX = w * 0.5
    local btnW = 80
    local btnH = 28
    local gap = 10

    -- 门状态显示
    local stateText = ""
    local stateColor = nvgRGBA(150, 200, 220, 200)
    if door.state == "closed" then
        stateText = "已关闭"
    elseif door.state == "open" then
        stateText = "已开启"
    elseif door.state == "opening" then
        stateText = "开启中..."
    elseif door.state == "closing" then
        stateText = "关闭中..."
    end
    if door.locked then
        stateText = "已锁定"
        stateColor = nvgRGBA(255, 80, 80, 220)
    end

    -- 状态文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, stateColor)
    nvgText(vg, centerX, baseY - 30, "舱门: " .. stateText, nil)

    -- 开/关门按钮提示
    if door.state == "closed" and not door.locked then
        DrawActionHint(centerX - btnW - gap, baseY, btnW, btnH, "开门", {100, 220, 150})
    elseif door.state == "open" then
        DrawActionHint(centerX - btnW - gap, baseY, btnW, btnH, "关门", {220, 150, 80})
    end

    -- 锁定/解锁按钮提示（safety/airlock门）
    if door.locked then
        DrawActionHint(centerX + gap, baseY, btnW, btnH, "解锁", {80, 200, 255})
    else
        DrawActionHint(centerX + gap, baseY, btnW, btnH, "锁死", {255, 100, 100})
    end

    -- 气压平衡进度条（长按时显示）
    if door.balancing then
        local barW = 160
        local barH = 12
        local barX = centerX - barW * 0.5
        local barY = baseY - 65

        -- 底框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(20, 30, 50, 200))
        nvgFill(vg)

        -- 进度填充
        local prog = door.balanceProgress or 0
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX + 1, barY + 1, (barW - 2) * prog, barH - 2, 2)
        nvgFillColor(vg, nvgRGBA(80, 200, 255, 220))
        nvgFill(vg)

        -- 文字
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, centerX, barY + barH * 0.5, string.format("气压平衡中... %d%%", math.floor(prog * 100)), nil)
    end

    -- 开关门动画进度
    if door.state == "opening" or door.state == "closing" then
        local barW = 120
        local barH = 6
        local barX = centerX - barW * 0.5
        local barY = baseY - 18

        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 2)
        nvgFillColor(vg, nvgRGBA(30, 40, 60, 180))
        nvgFill(vg)

        local prog = door.progress or 0
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX + 1, barY + 1, (barW - 2) * prog, barH - 2, 1)
        nvgFillColor(vg, nvgRGBA(150, 220, 100, 200))
        nvgFill(vg)
    end
end

--- 绘制舷窗操作按钮
function DrawPortholeButtons(w, h, ph, baseY)
    local centerX = w * 0.5
    local btnW = 70
    local btnH = 26

    -- 舷窗状态
    local stateText = ""
    if ph.state == "broken" then
        stateText = "已破损!"
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, math.floor(180 + 60 * math.sin(gameTime * 5))))
        nvgText(vg, centerX, baseY - 15, "舷窗破损 - 正在进水!", nil)
    else
        -- 查看按钮
        DrawActionHint(centerX - btnW - 5, baseY, btnW, btnH, "查看", {100, 180, 255})
        -- 盖板按钮
        local coverText = ph.coverClosed and "打开盖板" or "关闭盖板"
        DrawActionHint(centerX + 5, baseY, btnW, btnH, coverText, {180, 150, 100})
    end
end

--- 绘制水泵操作按钮
function DrawPumpButton(w, h, pump, baseY)
    local centerX = w * 0.5
    local btnW = 80
    local btnH = 26

    local label = pump.active and "关闭水泵" or "启动水泵"
    local color = pump.active and {80, 220, 120} or {200, 200, 80}
    DrawActionHint(centerX, baseY, btnW, btnH, label, color)

    -- 状态指示灯
    nvgBeginPath(vg)
    nvgCircle(vg, centerX + btnW * 0.5 + 12, baseY + btnH * 0.5, 4)
    if pump.active then
        nvgFillColor(vg, nvgRGBA(80, 255, 120, math.floor(180 + 60 * math.sin(gameTime * 3))))
    else
        nvgFillColor(vg, nvgRGBA(100, 100, 100, 150))
    end
    nvgFill(vg)
end

--- 绘制操作提示按钮（通用）
function DrawActionHint(x, y, w, h, text, color)
    -- 按钮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x - w * 0.5, y, w, h, 4)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 40))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgText(vg, x, y + h * 0.5, text, nil)
end

--- 绘制舷窗查看模式覆盖层
function DrawPortholeViewOverlay(w, h)
    if not snapshot_ or not snapshot_.players then return end
    local myPlayer = snapshot_.players[mySlot_]
    if not myPlayer or not myPlayer.viewingPorthole then return end

    -- 暗色边框（望远镜效果）
    local cx = w * 0.5
    local cy = h * 0.5
    local viewRadius = math.min(w, h) * 0.35

    -- 四周遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgPathWinding(vg, NVG_SOLID)
    nvgCircle(vg, cx, cy, viewRadius)
    nvgPathWinding(vg, NVG_HOLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
    nvgFill(vg)

    -- 圆形边框
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, viewRadius)
    nvgStrokeColor(vg, nvgRGBA(60, 80, 100, 200))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 内圈（玻璃质感）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, viewRadius - 4)
    nvgStrokeColor(vg, nvgRGBA(100, 150, 200, 80))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 深海景观（简单渲染海底粒子和光线）
    local depth = snapshot_.depth or 2400
    local darkness = math.min(1.0, depth / 6000)
    local bgR = math.floor(5 * (1 - darkness))
    local bgG = math.floor(20 * (1 - darkness))
    local bgB = math.floor(60 * (1 - darkness * 0.5))

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, viewRadius - 5)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 200))
    nvgFill(vg)

    -- 浮游粒子
    for i = 1, 15 do
        local seed = i * 137.5
        local px = cx + math.sin(gameTime * 0.3 + seed) * viewRadius * 0.7
        local py = cy + math.cos(gameTime * 0.2 + seed * 0.7) * viewRadius * 0.6
        local sz = 1.5 + math.sin(seed) * 0.8
        local alpha = math.floor(40 + 30 * math.sin(gameTime + seed))

        nvgBeginPath(vg)
        nvgCircle(vg, px, py, sz)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, alpha))
        nvgFill(vg)
    end

    -- 光线效果（浅层）
    if depth < 3000 then
        local lightAlpha = math.floor(30 * (1 - depth / 3000))
        for i = 1, 3 do
            local lx = cx - viewRadius * 0.3 + i * viewRadius * 0.3
            nvgBeginPath(vg)
            nvgMoveTo(vg, lx, cy - viewRadius)
            nvgLineTo(vg, lx - 10, cy + viewRadius * 0.5)
            nvgLineTo(vg, lx + 10, cy + viewRadius * 0.5)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, lightAlpha))
            nvgFill(vg)
        end
    end

    -- 提示文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(150, 200, 230, 180))
    nvgText(vg, cx, h - 30, "点击任意处关闭舷窗视图", nil)

    -- 深度标注
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(80, 160, 200, 160))
    nvgText(vg, cx + viewRadius - 10, cy - viewRadius + 10, string.format("%dm", depth), nil)
end

--- 构建渲染用的潜艇数据
function BuildRenderSub()
    if not snapshot_ or not snapshot_.sub then
        return Submarine.Init()  -- fallback
    end

    local s = Submarine.Init()
    s.hull = snapshot_.sub.hull or 100
    s.oxygen = snapshot_.sub.oxygen or 100
    s.power = snapshot_.sub.power or 100
    s.depth = snapshot_.depth or 0

    if snapshot_.sub.waterLevels then
        for i, level in ipairs(snapshot_.sub.waterLevels) do
            if s.compartments[i] then
                s.compartments[i].waterLevel = level
            end
        end
    end

    -- 气压数据
    if snapshot_.sub.pressures then
        for i, pressure in ipairs(snapshot_.sub.pressures) do
            if s.compartments[i] then
                s.compartments[i].pressure = pressure
            end
        end
    end

    -- 门状态
    if snapshot_.sub.doors then
        for i, doorData in ipairs(snapshot_.sub.doors) do
            if s.doors[i] then
                s.doors[i].state = doorData.state
                s.doors[i].locked = doorData.locked
                s.doors[i].progress = doorData.progress
                s.doors[i].balancing = doorData.balancing
                s.doors[i].balanceProgress = doorData.balanceProgress
            end
        end
    end

    -- 舷窗状态
    if snapshot_.sub.portholes then
        for i, phData in ipairs(snapshot_.sub.portholes) do
            if s.portholes[i] then
                s.portholes[i].state = phData.state
                s.portholes[i].coverClosed = phData.coverClosed
            end
        end
    end

    -- 水泵状态
    if snapshot_.sub.pumps then
        for i, pumpData in ipairs(snapshot_.sub.pumps) do
            if s.pumps[i] then
                s.pumps[i].active = pumpData.active
            end
        end
    end

    -- 构建玩家位置点（供小地图使用）
    s.playerDots = {}
    if snapshot_.players then
        for slot, p in pairs(snapshot_.players) do
            table.insert(s.playerDots, {
                x = p.x or 0,
                isMe = (slot == mySlot_),
                isAI = p.isAI or false,
            })
        end
    end

    -- 驾驶系统数据
    if snapshot_.sub.driving then
        s.driving = snapshot_.sub.driving
    end

    -- 物理系统数据
    if snapshot_.sub.physics then
        s.physics = snapshot_.sub.physics
    end

    -- 压载水舱数据
    if snapshot_.sub.ballast then
        s.ballast = snapshot_.sub.ballast
    end

    -- 声呐数据
    if snapshot_.sub.sonar then
        s.sonar = snapshot_.sub.sonar
    end

    -- 导航数据
    if snapshot_.sub.navigation then
        s.navigation = snapshot_.sub.navigation
    end

    -- 反应堆数据（供渲染模块使用）
    if snapshot_.reactor then
        s.reactor = snapshot_.reactor
    end

    -- 接线数据
    if snapshot_.wiring then
        s.wiring = snapshot_.wiring
    end

    -- 照明效率（影响Lighting渲染）
    s.lightsEfficiency = snapshot_.lightsEfficiency or 1.0

    return s
end

-- ============================================================
-- 多人HUD叠加
-- ============================================================

function DrawMultiplayerHUD(w, h)
    if not snapshot_ or not snapshot_.players then return end

    -- 右上角玩家列表
    local hudX = w - 150
    local hudY = 10
    local lineH = 18

    nvgBeginPath(vg)
    nvgRoundedRect(vg, hudX - 5, hudY - 2, 148, 4 + lineH * 4, 4)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, 180))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    for i = 1, MAX_PLAYERS do
        local p = snapshot_.players[i]
        local y = hudY + (i - 1) * lineH

        if p then
            -- 在线/AI标记
            local prefix = p.isAI and "AI" or "P" .. i
            local roleInfo = Shared.GetRoleInfo(p.role)
            local roleName = roleInfo and roleInfo.name or "..."

            if i == mySlot_ then
                nvgFillColor(vg, nvgRGBA(80, 220, 255, 255))
            elseif p.isAI then
                nvgFillColor(vg, nvgRGBA(120, 120, 140, 180))
            else
                nvgFillColor(vg, nvgRGBA(180, 200, 220, 220))
            end

            local status = p.inEVA and " [EVA]" or ""
            nvgText(vg, hudX, y, string.format("%s %s%s", prefix, roleName, status), nil)
        else
            nvgFillColor(vg, nvgRGBA(60, 60, 80, 100))
            nvgText(vg, hudX, y, "-- 空位 --", nil)
        end
    end
end

-- ============================================================
-- 本地输入（职业选择 - 点击卡片）
-- ============================================================

function SelectCurrentRole()
    if not serverConnection_ then return end
    if selectedRoleIdx_ < 1 or selectedRoleIdx_ > #Shared.ROLES then return end

    local role = Shared.ROLES[selectedRoleIdx_]
    local data = VariantMap()
    data["RoleId"] = Variant(role.id)
    serverConnection_:SendRemoteEvent(Shared.EVENTS.SELECT_ROLE, true, data)

    myRole_ = role.id
    print("[Client] Selected role: " .. role.id)
end

--- 发送使用物品远程事件
function SendUseItem(itemId)
    if not serverConnection_ then return end
    local data = VariantMap()
    data["ItemId"] = Variant(itemId)
    serverConnection_:SendRemoteEvent(Shared.EVENTS.USE_ITEM, true, data)
end

--- 发送指挥AI远程事件
function SendCommandAI(aiIdx, cmdId)
    if not serverConnection_ then return end
    local data = VariantMap()
    data["AIIdx"] = Variant(aiIdx)
    data["CmdId"] = Variant(cmdId)
    serverConnection_:SendRemoteEvent(Shared.EVENTS.COMMAND_AI, true, data)
end



--- 大厅点击处理：检测点击了哪张职业卡片
function HandleLobbyTap(screenX, screenY)
    if phase_ ~= Shared.PHASE.LOBBY then return end

    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    -- 将屏幕坐标转为逻辑坐标
    local tx = screenX / dpr
    local ty = screenY / dpr

    -- 卡片布局参数（与 DrawLobby 一致）
    local cardW = 160
    local cardH = 200
    local gap = 30
    local totalW = cardW * #Shared.ROLES + gap * (#Shared.ROLES - 1)
    local startX = (w - totalW) * 0.5
    local cardY = h * 0.3

    -- 房主"开始游戏"按钮点击检测
    if mySlot_ == 1 then
        local btnW = 160
        local btnH = 40
        local btnX = (w - btnW) * 0.5
        local btnY = h - 70
        if tx >= btnX and tx <= btnX + btnW and ty >= btnY and ty <= btnY + btnH then
            -- 发送强制开始事件
            if serverConnection_ then
                local data = VariantMap()
                serverConnection_:SendRemoteEvent(Shared.EVENTS.FORCE_START, true, data)
                print("[Client] Host requested force start")
            end
            return
        end
    end

    -- 检测点击了哪张卡片
    for i, role in ipairs(Shared.ROLES) do
        local cx = startX + (i - 1) * (cardW + gap)
        if tx >= cx and tx <= cx + cardW and ty >= cardY and ty <= cardY + cardH then
            -- 检查该职业是否已被其他玩家选择
            local takenByOther = false
            for _, ps in pairs(roleStatus_) do
                if ps.role == role.id and ps.slot ~= mySlot_ then
                    takenByOther = true
                    break
                end
            end
            if not takenByOther then
                selectedRoleIdx_ = i
                -- 直接确认选择
                SelectCurrentRole()
            end
            return
        end
    end
end

-- ============================================================
-- 港口场景触摸交互
-- ============================================================

--- 发送港口动作到服务器
local function SendPortAction(action, extraFields)
    if not serverConnection_ then return end
    local data = VariantMap()
    data["Action"] = Variant(action)
    if extraFields then
        for k, v in pairs(extraFields) do
            data[k] = v
        end
    end
    serverConnection_:SendRemoteEvent(Shared.EVENTS.PORT_ACTION, true, data)
end

--- 港口点击处理
function HandlePortTap(screenX, screenY)
    if phase_ ~= Shared.PHASE.PORT then return end

    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    local tx = screenX / dpr
    local ty = screenY / dpr

    -- 1. 标签栏点击
    local tabW = (w - 80) / 4
    local tabY = 75
    local tabH = 32
    if ty >= tabY and ty <= tabY + tabH then
        for i = 1, 4 do
            local tabX = 30 + (i - 1) * (tabW + 8)
            if tx >= tabX and tx <= tabX + tabW then
                SendPortAction("tab", { Tab = Variant(i) })
                return
            end
        end
    end

    -- 2. 出港面板的出港按钮
    if portScene.currentTab == PortScene.TAB_DEPART then
        local panelY = 120
        local panelH = h - panelY - 60
        local cx = w * 0.5
        local cy = panelY + panelH * 0.5
        local btnY = cy + 70
        local btnW = 160
        local btnH = 40
        if tx >= cx - btnW / 2 and tx <= cx + btnW / 2 and ty >= btnY and ty <= btnY + btnH then
            SendPortAction("depart")
            AudioManager.PlaySFX(AudioManager.SFX.DEPART)
            return
        end
    end

    -- 3. 列表项点击（任务板/补给站/升级坞）
    if portScene.currentTab ~= PortScene.TAB_DEPART then
        local panelY = 120
        local panelH = h - panelY - 60
        if tx >= 30 and tx <= w - 30 and ty >= panelY and ty <= panelY + panelH then
            local itemCount = 0
            if portScene.currentTab == PortScene.TAB_MISSION then
                local missions = PortView.GetMissions()
                itemCount = missions and #missions or 3
            elseif portScene.currentTab == PortScene.TAB_SHOP then
                itemCount = #PortScene.SHOP_ITEMS
            elseif portScene.currentTab == PortScene.TAB_UPGRADE then
                itemCount = #PortScene.UPGRADES
            end

            if itemCount > 0 then
                -- 使用固定 itemH 和 scrollOffset 计算点击索引
                local hasMission = (gameState and gameState.currentMission)
                local headerH
                if portScene.currentTab == PortScene.TAB_MISSION then
                    headerH = hasMission and 30 or 12
                elseif portScene.currentTab == PortScene.TAB_SHOP then
                    headerH = 30
                else
                    headerH = 15
                end
                local startY = panelY + headerH
                local itemH = 70  -- ITEM_HEIGHT_FIXED
                local currentScroll = PortView.GetScrollOffset()
                -- 点击位置相对于列表起始 + 滚动偏移 → 实际索引
                local clickedIdx = math.floor((ty - startY + currentScroll) / itemH) + 1
                if clickedIdx >= 1 and clickedIdx <= itemCount then
                    if portScene.selectedItem == clickedIdx then
                        -- 再次点击已选中项 → 确认操作
                        SendPortAction("confirm")
                        -- 任务面板确认后，显示提示并从列表移除
                        if portScene.currentTab == PortScene.TAB_MISSION then
                            local missions = PortView.GetMissions()
                            local mission = missions and missions[clickedIdx]
                            local missionTitle = mission and mission.title or "未知"
                            -- 立即设置本地任务（不等 snapshot），让出港按钮马上显示
                            if mission and gameState then
                                gameState.currentMission = mission
                            end
                            PortScene.ShowMessage(portScene, "已接取「" .. missionTitle .. "」任务")
                            AudioManager.PlaySFX(AudioManager.SFX.MISSION_ACCEPT)
                            PortView.RemoveMission(clickedIdx)
                            portScene.selectedItem = 0
                        elseif portScene.currentTab == PortScene.TAB_SHOP then
                            PortScene.ShowMessage(portScene, "购买成功")
                            AudioManager.PlaySFX(AudioManager.SFX.BUTTON_CLICK)
                        elseif portScene.currentTab == PortScene.TAB_UPGRADE then
                            PortScene.ShowMessage(portScene, "升级成功")
                        end
                    else
                        -- 首次点击 → 选中（立即本地更新，不等快照同步）
                        portScene.selectedItem = clickedIdx
                        SendPortAction("select_item", { Index = Variant(clickedIdx) })
                    end
                    return
                end
            end
        end
    end
end

-- ============================================================
-- 鼠标/触摸事件
-- ============================================================

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    if phase_ == Shared.PHASE.TITLE then
        -- 点击任意位置进入角色选择
        titleDismissed_ = true
        phase_ = Shared.PHASE.LOBBY
        AudioManager.PlaySFX(AudioManager.SFX.BUTTON_CLICK)
        AudioManager.UpdatePhaseMusic(phase_)
    elseif phase_ == Shared.PHASE.LOBBY then
        HandleLobbyTap(x, y)
    elseif phase_ == Shared.PHASE.PORT then
        HandlePortTap(x, y)
    elseif phase_ == Shared.PHASE.DEEP_SEA then
        HandleDeepSeaTap(x, y)
    end
end

--- 深海阶段点击处理：合作UI + 指令轮盘 + AI玩家点击
function HandleDeepSeaTap(screenX, screenY)
    if not snapshot_ or not snapshot_.players then return end

    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    local tx = screenX / dpr
    local ty = screenY / dpr

    -- 合作系统 UI 优先处理（最高优先级）
    if HandlePauseTap(tx, ty) then return end
    if HandleQuickWheelTap(tx, ty) then return end
    if HandleTradeOfferTap(tx, ty) then return end
    if HandleVotePanelTap(tx, ty) then return end
    if HandleSpectateTap(tx, ty) then return end

    if isTurretView or isExternalView then return end

    -- 如果轮盘已显示，先处理轮盘点击
    if cmdWheel_.visible then
        local cmdId, aiIdx = CommandWheel.HandleClick(cmdWheel_, tx, ty)
        if cmdId and aiIdx then
            SendCommandAI(aiIdx, cmdId)
        end
        return
    end

    -- 点击AI玩家显示指令轮盘
    local thick = Config.Sub.hullThickness
    local subH = Config.Sub.hullHeight + thick * 2
    local subY = h * 0.5 - subH * 0.5
    local innerX = 30 + thick
    local innerY = subY + thick
    local innerH = subH - thick * 2
    local floorY = innerY + innerH - 8
    local hitRadius = 30

    -- 将屏幕坐标转为潜艇内部世界坐标
    local worldX = tx + cameraX

    -- 遍历AI玩家检测点击
    local aiIdx = 0
    for i = 1, MAX_PLAYERS do
        local p = snapshot_.players[i]
        if p and p.isAI then
            aiIdx = aiIdx + 1
            local aiX = innerX + (p.x or 100)
            local aiScreenX = aiX - cameraX
            local aiScreenY = floorY - Config.Crew.height * 0.5

            local dx = tx - aiScreenX
            local dy = ty - aiScreenY
            if dx * dx + dy * dy < hitRadius * hitRadius then
                -- 显示指令轮盘（传入aiCrew索引）
                CommandWheel.Show(cmdWheel_, aiScreenX, aiScreenY - 40, aiIdx, "")
                return
            end
        end
    end
end

function HandleTouchBegin(eventType, eventData)
    if phase_ ~= Shared.PHASE.PORT then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local touchId = eventData["TouchID"]:GetInt()

    -- 检查触摸是否在列表面板区域内
    local w = graphics:GetWidth() / dpr
    local h = graphics:GetHeight() / dpr
    local tx = x / dpr
    local ty = y / dpr

    local panelY = 120
    local panelH = h - panelY - 60

    if portScene.currentTab ~= PortScene.TAB_DEPART and
       tx >= 30 and tx <= w - 30 and ty >= panelY and ty <= panelY + panelH then
        portScrollDrag.active = true
        portScrollDrag.startY = y
        portScrollDrag.lastY = y
        portScrollDrag.totalDY = 0
        portScrollDrag.touchId = touchId
    end
end

function HandleTouchMove(eventType, eventData)
    if not portScrollDrag.active then return end

    local touchId = eventData["TouchID"]:GetInt()
    if touchId ~= portScrollDrag.touchId then return end

    local y = eventData["Y"]:GetInt()
    local dy = y - portScrollDrag.lastY
    portScrollDrag.lastY = y
    portScrollDrag.totalDY = portScrollDrag.totalDY + math.abs(dy)

    -- 将触摸移动转为滚动（向上滑动 → dy<0 → 内容向下滚）
    local scaledDY = dy / dpr
    PortView.Scroll(scaledDY)
end

function HandleTouchEnd(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()

    -- 如果之前在拖动滚动
    if portScrollDrag.active then
        local wasScrolling = portScrollDrag.totalDY > SCROLL_THRESHOLD
        portScrollDrag.active = false
        portScrollDrag.touchId = -1

        -- 如果累计移动超过阈值，视为滚动操作，不触发点击
        if wasScrolling then
            return
        end
    end

    if phase_ == Shared.PHASE.TITLE then
        -- 点击任意位置进入角色选择
        titleDismissed_ = true
        phase_ = Shared.PHASE.LOBBY
        AudioManager.PlaySFX(AudioManager.SFX.BUTTON_CLICK)
        AudioManager.UpdatePhaseMusic(phase_)
    elseif phase_ == Shared.PHASE.LOBBY then
        HandleLobbyTap(x, y)
    elseif phase_ == Shared.PHASE.PORT then
        HandlePortTap(x, y)
    end
end

-- ============================================================
-- 合作系统事件处理
-- ============================================================

function HandleQuickCommandReceived(eventType, eventData)
    local senderSlot = eventData["Slot"]:GetInt()
    local presetId = eventData["PresetId"]:GetString()
    local msgType = eventData["MsgType"]:GetString()
    local text = eventData["Text"]:GetString()

    -- 获取发送者名称
    local senderName = "玩家" .. senderSlot
    if snapshot_ and snapshot_.players and snapshot_.players[senderSlot] then
        senderName = snapshot_.players[senderSlot].name or senderName
    end

    -- 如果是预设指令，取预设文本
    if presetId ~= "" then
        local presetText = QuickCommands.GetPresetText(presetId)
        if presetText then text = presetText end
    end

    -- 声音衰减（根据房间距离）
    local volume = 1.0
    if snapshot_ and snapshot_.players then
        local myPlayer = snapshot_.players[mySlot_]
        local sender = snapshot_.players[senderSlot]
        if myPlayer and sender then
            local myRoom = myPlayer.room or 1
            local senderRoom = sender.room or 1
            local dist = math.abs((sender.x or 0) - (myPlayer.x or 0))
            volume = QuickCommands.CalcVoiceVolume(senderRoom, myRoom, dist)
        end
    end

    -- 添加到消息队列（音量过低则不显示）
    if volume > 0.1 then
        QuickCommands.PushMessage(qcMessages_, senderName, senderSlot, text, msgType, gameTime)
    end
end

function HandleTradeOfferReceived(eventType, eventData)
    local fromSlot = eventData["FromSlot"]:GetInt()
    local itemId = eventData["ItemId"]:GetString()
    local count = eventData["Count"]:GetInt()

    -- 仅目标玩家收到此事件
    local fromName = "玩家" .. fromSlot
    if snapshot_ and snapshot_.players and snapshot_.players[fromSlot] then
        fromName = snapshot_.players[fromSlot].name or fromName
    end

    tradeOffer_ = {
        fromSlot = fromSlot,
        fromName = fromName,
        itemId = itemId,
        count = count,
        timeout = 15.0,  -- 15秒确认时间
    }
    print(string.format("[Client] Trade offer from %s: %s x%d", fromName, itemId, count))
end

function HandleTradeResultReceived(eventType, eventData)
    local result = eventData["Result"]:GetString()
    local textMap = {
        accepted = "交易完成！",
        rejected = "交易被拒绝",
        timeout  = "交易超时",
        cancelled= "交易取消",
    }
    tradeResult_ = {
        text = textMap[result] or ("交易: " .. result),
        timer = 3.0,
    }
    tradeOffer_ = nil  -- 清除挂起的提议
end

function HandleRescueUpdateReceived(eventType, eventData)
    local targetSlot = eventData["Slot"]:GetInt()
    local action = eventData["Action"]:GetString()
    local progress = eventData["Progress"]:GetFloat()
    local rescuerSlot = eventData["Rescuer"]:GetInt()

    if targetSlot == mySlot_ then
        if action == "reviving" then
            rescueInfo_ = { rescuer = rescuerSlot, action = action, progress = progress }
        elseif action == "carrying" then
            rescueInfo_ = { rescuer = rescuerSlot, action = "carry", progress = 0 }
        elseif action == "done" or action == "dropped" then
            rescueInfo_ = nil
        end
    end
end

function HandleVoteStartReceived(eventType, eventData)
    local voteType = eventData["Type"]:GetString()
    local initiator = eventData["Initiator"]:GetInt()
    local target = eventData["Target"]:GetInt()
    local timeout = eventData["Timeout"]:GetFloat()

    voteActive_ = {
        active = true,
        type = voteType,
        initiator = initiator,
        target = target,
        timeout = timeout,
        voted = false,
        yesCount = 0,
        noCount = 0,
    }
    print(string.format("[Client] Vote started: %s (by slot %d)", voteType, initiator))
end

function HandleVoteResultReceived(eventType, eventData)
    local result = eventData["Result"]:GetString()
    local voteType = eventData["Type"]:GetString()

    local textMap = {
        passed = "投票通过",
        failed = "投票未通过",
        timeout = "投票超时",
    }
    voteResult_ = {
        text = (textMap[result] or result) .. " (" .. voteType .. ")",
        timer = 4.0,
    }
    voteActive_ = nil
end

function HandleReconnectResult(eventType, eventData)
    local success = eventData["Success"]:GetBool()
    if success then
        mySlot_ = eventData["Slot"]:GetInt()
        myRole_ = eventData["Role"]:GetString()
        print(string.format("[Client] Reconnected! Slot=%d Role=%s", mySlot_, myRole_))
    else
        print("[Client] Reconnection failed")
    end
end

function HandleSpectateHintReceived(eventType, eventData)
    local fromSlot = eventData["FromSlot"]:GetInt()
    local hintText = eventData["Text"]:GetString()

    local fromName = "观战者"
    if snapshot_ and snapshot_.players and snapshot_.players[fromSlot] then
        fromName = snapshot_.players[fromSlot].name or fromName
    end

    -- 显示为系统消息
    QuickCommands.PushMessage(qcMessages_, fromName, fromSlot, "[提示] " .. hintText, "hint", gameTime)
end

function HandlePlayerDownedReceived(eventType, eventData)
    local slot = eventData["Slot"]:GetInt()
    downedPlayers_[slot] = true
    if slot == mySlot_ then
        myDowned_ = true
        print("[Client] You are downed! Wait for rescue...")
    end

    -- 系统消息
    local name = "玩家" .. slot
    if snapshot_ and snapshot_.players and snapshot_.players[slot] then
        name = snapshot_.players[slot].name or name
    end
    QuickCommands.PushMessage(qcMessages_, "系统", 0, name .. " 倒地了！", "system", gameTime)
end

function HandlePlayerDeadReceived(eventType, eventData)
    local slot = eventData["Slot"]:GetInt()
    downedPlayers_[slot] = false

    if slot == mySlot_ then
        myDowned_ = false
        -- 进入观战模式
        spectateState_ = CoopSystem.CreateSpectateState()
        -- 找一个活着的玩家作为初始目标
        local target = 0
        if snapshot_ and snapshot_.players then
            for i = 1, MAX_PLAYERS do
                if i ~= mySlot_ and snapshot_.players[i] and not downedPlayers_[i] then
                    target = i
                    break
                end
            end
        end
        CoopSystem.EnterSpectate(spectateState_, target)
        spectateTarget_ = target
        print("[Client] You died. Entering spectate mode.")
    end

    local name = "玩家" .. slot
    if snapshot_ and snapshot_.players and snapshot_.players[slot] then
        name = snapshot_.players[slot].name or name
    end
    QuickCommands.PushMessage(qcMessages_, "系统", 0, name .. " 死亡了", "system", gameTime)
end

function HandlePlayerRevivedReceived(eventType, eventData)
    local slot = eventData["Slot"]:GetInt()
    downedPlayers_[slot] = false

    if slot == mySlot_ then
        myDowned_ = false
        rescueInfo_ = nil
        print("[Client] You have been revived!")
    end

    local name = "玩家" .. slot
    if snapshot_ and snapshot_.players and snapshot_.players[slot] then
        name = snapshot_.players[slot].name or name
    end
    QuickCommands.PushMessage(qcMessages_, "系统", 0, name .. " 被救活了！", "system", gameTime)
end

function HandleNetPongReceived(eventType, eventData)
    local latencyMs = (os.clock() - pingSentTime_) * 1000
    CoopSystem.UpdateNetQuality(netQuality_, latencyMs)
end

function HandlePauseReceived(eventType, eventData)
    local slot = eventData["Slot"]:GetInt()
    isPaused_ = true
    pauseSlot_ = slot
    print(string.format("[Client] Game paused by slot %d", slot))
end

function HandleResumeReceived(eventType, eventData)
    isPaused_ = false
    pauseSlot_ = 0
    print("[Client] Game resumed")
end

-- ============================================================
-- 合作系统 UI 绘制函数
-- ============================================================

--- 倒地玩家标记
function DrawDownedIndicators(w, h)
    if not snapshot_ or not snapshot_.players then return end

    local thick = Config.Sub.hullThickness
    local subH = Config.Sub.hullHeight + thick * 2
    local subY = h * 0.5 - subH * 0.5
    local innerY = subY + thick
    local innerH = subH - thick * 2
    local floorY = innerY + innerH - 8
    local innerX = 30 + thick

    for slot, isDowned in pairs(downedPlayers_) do
        if isDowned and snapshot_.players[slot] then
            local p = snapshot_.players[slot]
            local px = innerX + (p.x or 100) - cameraX
            local py = floorY - 20

            -- 闪烁红色十字
            local alpha = math.floor(180 + 75 * math.sin(gameTime * 6))
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 60, 60, alpha))
            nvgText(vg, px, py - 20, "SOS", nil)

            -- 倒地动画（躺倒效果用横条表示）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px - 12, py, 24, 6, 2)
            nvgFillColor(vg, nvgRGBA(200, 50, 50, alpha))
            nvgFill(vg)
        end
    end
end

--- 交易提议弹窗
function DrawTradeOfferUI(w, h)
    local panelW = 260
    local panelH = 120
    local px = (w - panelW) * 0.5
    local py = h * 0.35

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 8)
    nvgFillColor(vg, nvgRGBA(20, 30, 50, 230))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, px + panelW * 0.5, py + 10, "收到交易请求", nil)

    -- 内容
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    local desc = string.format("%s 想给你: %s x%d",
        tradeOffer_.fromName or "?",
        tradeOffer_.itemId or "?",
        tradeOffer_.count or 0)
    nvgText(vg, px + panelW * 0.5, py + 35, desc, nil)

    -- 倒计时
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
    nvgText(vg, px + panelW * 0.5, py + 55, string.format("%.0f秒后超时", tradeOffer_.timeout), nil)

    -- 接受按钮
    local btnW = 80
    local btnH = 28
    local btnY = py + panelH - btnH - 12
    -- 接受
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + 30, btnY, btnW, btnH, 4)
    nvgFillColor(vg, nvgRGBA(40, 160, 80, 220))
    nvgFill(vg)
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, px + 30 + btnW * 0.5, btnY + btnH * 0.5, "接受", nil)

    -- 拒绝
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + panelW - 30 - btnW, btnY, btnW, btnH, 4)
    nvgFillColor(vg, nvgRGBA(160, 40, 40, 220))
    nvgFill(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, px + panelW - 30 - btnW * 0.5, btnY + btnH * 0.5, "拒绝", nil)
end

--- 通用通知气泡
function DrawCoopNotification(w, h, text, r, g, b)
    local textW = 200
    local px = (w - textW) * 0.5
    local py = h * 0.2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, textW, 30, 6)
    nvgFillColor(vg, nvgRGBA(r, g, b, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, px + textW * 0.5, py + 15, text, nil)
end

--- 投票面板
function DrawVotePanel(w, h)
    local panelW = 240
    local panelH = 110
    local px = w - panelW - 20
    local py = 80

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 6)
    nvgFillColor(vg, nvgRGBA(30, 20, 50, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 150, 255, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 150, 255, 255))
    local title = "投票: " .. (voteActive_.type or "?")
    nvgText(vg, px + panelW * 0.5, py + 8, title, nil)

    -- 目标
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    local targetName = "玩家" .. (voteActive_.target or 0)
    nvgText(vg, px + panelW * 0.5, py + 28, "目标: " .. targetName, nil)

    -- 倒计时
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 180))
    nvgText(vg, px + panelW * 0.5, py + 44,
        string.format("剩余 %.0f 秒", voteActive_.timeout or 0), nil)

    -- 按钮（未投票时显示）
    if not voteActive_.voted then
        local btnW = 70
        local btnH = 26
        local btnY = py + panelH - btnH - 10

        -- 赞成
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + 25, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(60, 180, 80, 220))
        nvgFill(vg)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, px + 25 + btnW * 0.5, btnY + btnH * 0.5, "赞成", nil)

        -- 反对
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + panelW - 25 - btnW, btnY, btnW, btnH, 4)
        nvgFillColor(vg, nvgRGBA(180, 60, 60, 220))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, px + panelW - 25 - btnW * 0.5, btnY + btnH * 0.5, "反对", nil)
    else
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
        nvgText(vg, px + panelW * 0.5, py + panelH - 22, "已投票，等待结果...", nil)
    end
end

--- 观战模式 UI
function DrawSpectateUI(w, h)
    -- 顶部观战栏
    local barH = 36
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, barH)
    nvgFillColor(vg, nvgRGBA(10, 10, 10, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 100, 100, 255))
    nvgText(vg, w * 0.5, barH * 0.5, "观战模式", nil)

    -- 当前观战目标
    local targetName = "无"
    if spectateTarget_ > 0 and snapshot_ and snapshot_.players and snapshot_.players[spectateTarget_] then
        targetName = snapshot_.players[spectateTarget_].name or ("玩家" .. spectateTarget_)
    end
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
    nvgText(vg, w * 0.5, barH * 0.5 + 16,
        "正在观看: " .. targetName .. "  [点击切换]", nil)

    -- 提示次数
    if spectateState_ then
        local hintsLeft = spectateState_.maxHints - spectateState_.hintsUsed
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
        nvgText(vg, w - 20, barH * 0.5, string.format("剩余提示: %d/5", hintsLeft), nil)
    end

    -- 底部半透明遮罩（营造观战氛围）
    nvgBeginPath(vg)
    nvgRect(vg, 0, h - 3, w, 3)
    nvgFillColor(vg, nvgRGBA(255, 60, 60, 100))
    nvgFill(vg)
end

--- 暂停覆盖层
function DrawPauseOverlay(w, h)
    -- 半透明全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgFill(vg)

    -- 暂停文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 28)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
    nvgText(vg, w * 0.5, h * 0.4, "游戏已暂停", nil)

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 200))
    local pauserName = "玩家" .. pauseSlot_
    if snapshot_ and snapshot_.players and snapshot_.players[pauseSlot_] then
        pauserName = snapshot_.players[pauseSlot_].name or pauserName
    end
    nvgText(vg, w * 0.5, h * 0.5, "由 " .. pauserName .. " (房主) 暂停", nil)

    -- 房主看到恢复按钮
    if mySlot_ == 1 then
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(100, 220, 100, 220))
        nvgText(vg, w * 0.5, h * 0.6, "[点击屏幕恢复游戏]", nil)
    end
end

--- 网络质量指示器
function DrawNetQualityIndicator(w, h)
    local display = CoopSystem.GetQualityDisplay(netQuality_)
    if not display then return end

    -- 右上角小图标
    local ix = w - 60
    local iy = 8
    local barW = 4
    local barGap = 2
    local maxBars = 4

    -- 颜色映射
    local colors = {
        good = {60, 200, 80},
        fair = {220, 200, 40},
        poor = {220, 120, 40},
        bad  = {220, 50, 50},
    }
    local c = colors[display.level] or colors.fair
    local activeBars = ({good = 4, fair = 3, poor = 2, bad = 1})[display.level] or 2

    for i = 1, maxBars do
        local bh = 4 + i * 3
        local bx = ix + (i - 1) * (barW + barGap)
        local by = iy + (maxBars * 3 + 4) - bh

        nvgBeginPath(vg)
        nvgRect(vg, bx, by, barW, bh)
        if i <= activeBars then
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 220))
        else
            nvgFillColor(vg, nvgRGBA(80, 80, 80, 100))
        end
        nvgFill(vg)
    end

    -- 延迟数字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 180))
    nvgText(vg, ix + maxBars * (barW + barGap) + 4, iy + 2,
        string.format("%dms", display.latency or 0), nil)
end

--- 倒地全屏效果
function DrawDownedOverlay(w, h)
    -- 红色边缘渐变
    local alpha = math.floor(80 + 40 * math.sin(gameTime * 3))

    -- 上下红色渐变条
    local gradH = h * 0.15
    local topGrad = nvgLinearGradient(vg, 0, 0, 0, gradH,
        nvgRGBA(180, 0, 0, alpha), nvgRGBA(180, 0, 0, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, gradH)
    nvgFillPaint(vg, topGrad)
    nvgFill(vg)

    local botGrad = nvgLinearGradient(vg, 0, h - gradH, 0, h,
        nvgRGBA(180, 0, 0, 0), nvgRGBA(180, 0, 0, alpha))
    nvgBeginPath(vg)
    nvgRect(vg, 0, h - gradH, w, gradH)
    nvgFillPaint(vg, botGrad)
    nvgFill(vg)

    -- 倒地提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 80, 80, math.floor(180 + 50 * math.sin(gameTime * 4))))
    nvgText(vg, w * 0.5, h * 0.75, "你已倒地！等待队友救援...", nil)

    -- 救援进度
    if rescueInfo_ and rescueInfo_.action == "reviving" then
        local prog = rescueInfo_.progress or 0
        local barW = 160
        local barH = 8
        local bx = (w - barW) * 0.5
        local by = h * 0.8

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(40, 40, 40, 180))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, barW * prog, barH, 3)
        nvgFillColor(vg, nvgRGBA(60, 220, 100, 230))
        nvgFill(vg)

        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        nvgText(vg, w * 0.5, by + barH + 12, "正在被救援...", nil)
    elseif rescueInfo_ and rescueInfo_.action == "carry" then
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(200, 200, 100, 220))
        nvgText(vg, w * 0.5, h * 0.82, "队友正在背你移动...", nil)
    end
end

-- ============================================================
-- 合作系统交互处理（点击事件）
-- ============================================================

--- 处理交易弹窗点击
function HandleTradeOfferTap(tx, ty)
    if not tradeOffer_ then return false end

    local w = screenW / dpr
    local h = screenH / dpr
    local panelW = 260
    local panelH = 120
    local px = (w - panelW) * 0.5
    local py = h * 0.35
    local btnW = 80
    local btnH = 28
    local btnY = py + panelH - btnH - 12

    -- 接受按钮区域
    if tx >= px + 30 and tx <= px + 30 + btnW and
       ty >= btnY and ty <= btnY + btnH then
        -- 发送接受
        if serverConnection_ then
            local data = VariantMap()
            data["Response"] = Variant("accept")
            serverConnection_:SendRemoteEvent(Shared.EVENTS.TRADE_RESPOND, true, data)
        end
        tradeOffer_ = nil
        return true
    end

    -- 拒绝按钮区域
    if tx >= px + panelW - 30 - btnW and tx <= px + panelW - 30 and
       ty >= btnY and ty <= btnY + btnH then
        if serverConnection_ then
            local data = VariantMap()
            data["Response"] = Variant("reject")
            serverConnection_:SendRemoteEvent(Shared.EVENTS.TRADE_RESPOND, true, data)
        end
        tradeOffer_ = nil
        return true
    end

    return false
end

--- 处理投票面板点击
function HandleVotePanelTap(tx, ty)
    if not voteActive_ or not voteActive_.active or voteActive_.voted then return false end

    local w = screenW / dpr
    local panelW = 240
    local panelH = 110
    local px = w - panelW - 20
    local py = 80
    local btnW = 70
    local btnH = 26
    local btnY = py + panelH - btnH - 10

    -- 赞成
    if tx >= px + 25 and tx <= px + 25 + btnW and
       ty >= btnY and ty <= btnY + btnH then
        if serverConnection_ then
            local data = VariantMap()
            data["Agree"] = Variant(true)
            serverConnection_:SendRemoteEvent(Shared.EVENTS.VOTE_CAST, true, data)
        end
        voteActive_.voted = true
        return true
    end

    -- 反对
    if tx >= px + panelW - 25 - btnW and tx <= px + panelW - 25 and
       ty >= btnY and ty <= btnY + btnH then
        if serverConnection_ then
            local data = VariantMap()
            data["Agree"] = Variant(false)
            serverConnection_:SendRemoteEvent(Shared.EVENTS.VOTE_CAST, true, data)
        end
        voteActive_.voted = true
        return true
    end

    return false
end

--- 处理观战切换点击
function HandleSpectateTap(tx, ty)
    if not spectateState_ then return false end

    local w = screenW / dpr
    local barH = 36

    -- 观战栏点击 → 切换目标
    if ty <= barH then
        -- 找下一个活着的玩家
        if snapshot_ and snapshot_.players then
            local nextTarget = spectateTarget_
            for i = 1, MAX_PLAYERS do
                nextTarget = (nextTarget % MAX_PLAYERS) + 1
                if nextTarget ~= mySlot_ and snapshot_.players[nextTarget] and not downedPlayers_[nextTarget] then
                    spectateTarget_ = nextTarget
                    CoopSystem.SwitchSpectateTarget(spectateState_, nextTarget)
                    -- 通知服务端
                    if serverConnection_ then
                        local data = VariantMap()
                        data["Target"] = Variant(nextTarget)
                        serverConnection_:SendRemoteEvent(Shared.EVENTS.SPECTATE_SWITCH, true, data)
                    end
                    break
                end
            end
        end
        return true
    end

    return false
end

--- 处理暂停恢复点击（房主）
function HandlePauseTap(tx, ty)
    if not isPaused_ then return false end
    if mySlot_ ~= 1 then return false end  -- 只有房主能恢复

    if serverConnection_ then
        serverConnection_:SendRemoteEvent(Shared.EVENTS.RESUME_GAME, true)
    end
    return true
end

--- 处理快捷指令轮盘点击
function HandleQuickWheelTap(tx, ty)
    if not qcWheel_.visible then return false end

    local selection = QuickCommands.HandleWheelClick(qcWheel_, tx, ty)
    if selection then
        -- 发送到服务端
        if serverConnection_ then
            local data = VariantMap()
            data["PresetId"] = Variant(selection.presetId or "")
            data["Text"] = Variant(selection.text or "")
            data["MsgType"] = Variant(selection.msgType or "preset")
            serverConnection_:SendRemoteEvent(Shared.EVENTS.QUICK_COMMAND, true, data)
        end
        return true
    end

    -- 点击轮盘外部区域关闭
    local dx = tx - qcWheel_.centerX
    local dy = ty - qcWheel_.centerY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > qcWheel_.outerRadius then
        QuickCommands.HideWheel(qcWheel_)
        return true
    end

    return false
end

--- 发送快捷指令轮盘打开（长按触发）
function OpenQuickCommandWheel(cx, cy)
    local w = screenW / dpr
    local h = screenH / dpr
    QuickCommands.ShowWheel(qcWheel_, cx, cy)
end

return Client
