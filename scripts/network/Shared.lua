--- 潜艇深海生存 - 多人联机共享模块
--- 事件名、Controls位定义、职业定义、序列化工具

local cjson = require("cjson")

local Shared = {}

-- ============================================================
-- 网络事件名
-- ============================================================
Shared.EVENTS = {
    CLIENT_READY    = "ClientReady",
    SELECT_ROLE     = "SelectRole",
    FORCE_START     = "ForceStart",
    ASSIGN_ROLE     = "AssignRole",
    GAME_SNAPSHOT   = "GameSnapshot",
    PLAYER_JOINED   = "PlayerJoined",
    PLAYER_LEFT     = "PlayerLeft",
    PORT_ACTION     = "PortAction",
    EVA_START       = "EvaStart",
    EVA_PICKUP      = "EvaPickup",
    GAME_START      = "GameStart",
    CHAT_MSG        = "ChatMsg",
    ROLE_LOCKED     = "RoleLocked",
    -- 联机交互事件
    USE_ITEM        = "UseItem",
    CRAFT_ITEM      = "CraftItem",
    COMMAND_AI      = "CommandAI",
    PICKUP_SCRAP    = "PickupScrap",
    TOGGLE_INVENTORY= "ToggleInventory",
    -- 合作系统事件
    QUICK_COMMAND   = "QuickCommand",      -- 快捷指令消息
    TRADE_OFFER     = "TradeOffer",        -- 发起交易
    TRADE_RESPOND   = "TradeRespond",      -- 接受/拒绝交易
    TRADE_RESULT    = "TradeResult",       -- 交易结果通知
    RESCUE_ACTION   = "RescueAction",      -- 救援操作（拖拽/背起/复活）
    RESCUE_UPDATE   = "RescueUpdate",      -- 救援状态更新
    VOTE_START      = "VoteStart",         -- 发起投票
    VOTE_CAST       = "VoteCast",          -- 投票
    VOTE_RESULT     = "VoteResult",        -- 投票结果
    ROOM_SETTINGS   = "RoomSettings",      -- 房间设置变更
    RECONNECT       = "Reconnect",         -- 重连请求
    RECONNECT_RESULT= "ReconnectResult",   -- 重连结果
    SPECTATE_SWITCH = "SpectateSwitch",    -- 切换观战目标
    SPECTATE_HINT   = "SpectateHint",      -- 观战者发送提示
    PLAYER_DOWNED   = "PlayerDowned",      -- 玩家倒地通知
    PLAYER_DEAD     = "PlayerDead",        -- 玩家死亡通知
    PLAYER_REVIVED  = "PlayerRevived",     -- 玩家复活通知
    NET_PING        = "NetPing",           -- 延迟测量
    NET_PONG        = "NetPong",           -- 延迟回复
    PAUSE_GAME      = "PauseGame",         -- 暂停游戏
    RESUME_GAME     = "ResumeGame",        -- 恢复游戏
}

-- 服务端接收的事件
Shared.SERVER_EVENTS = {
    Shared.EVENTS.CLIENT_READY,
    Shared.EVENTS.SELECT_ROLE,
    Shared.EVENTS.FORCE_START,
    Shared.EVENTS.PORT_ACTION,
    Shared.EVENTS.EVA_START,
    Shared.EVENTS.EVA_PICKUP,
    Shared.EVENTS.CHAT_MSG,
    Shared.EVENTS.USE_ITEM,
    Shared.EVENTS.CRAFT_ITEM,
    Shared.EVENTS.COMMAND_AI,
    Shared.EVENTS.PICKUP_SCRAP,
    Shared.EVENTS.TOGGLE_INVENTORY,
    -- 合作系统
    Shared.EVENTS.QUICK_COMMAND,
    Shared.EVENTS.TRADE_OFFER,
    Shared.EVENTS.TRADE_RESPOND,
    Shared.EVENTS.RESCUE_ACTION,
    Shared.EVENTS.VOTE_START,
    Shared.EVENTS.VOTE_CAST,
    Shared.EVENTS.ROOM_SETTINGS,
    Shared.EVENTS.RECONNECT,
    Shared.EVENTS.SPECTATE_SWITCH,
    Shared.EVENTS.SPECTATE_HINT,
    Shared.EVENTS.NET_PING,
    Shared.EVENTS.PAUSE_GAME,
    Shared.EVENTS.RESUME_GAME,
}

-- 客户端接收的事件
Shared.CLIENT_EVENTS = {
    Shared.EVENTS.ASSIGN_ROLE,
    Shared.EVENTS.GAME_SNAPSHOT,
    Shared.EVENTS.PLAYER_JOINED,
    Shared.EVENTS.PLAYER_LEFT,
    Shared.EVENTS.GAME_START,
    Shared.EVENTS.CHAT_MSG,
    Shared.EVENTS.ROLE_LOCKED,
    -- 合作系统
    Shared.EVENTS.QUICK_COMMAND,
    Shared.EVENTS.TRADE_RESULT,
    Shared.EVENTS.RESCUE_UPDATE,
    Shared.EVENTS.VOTE_START,
    Shared.EVENTS.VOTE_RESULT,
    Shared.EVENTS.ROOM_SETTINGS,
    Shared.EVENTS.RECONNECT_RESULT,
    Shared.EVENTS.SPECTATE_HINT,
    Shared.EVENTS.PLAYER_DOWNED,
    Shared.EVENTS.PLAYER_DEAD,
    Shared.EVENTS.PLAYER_REVIVED,
    Shared.EVENTS.NET_PONG,
    Shared.EVENTS.PAUSE_GAME,
    Shared.EVENTS.RESUME_GAME,
    Shared.EVENTS.TRADE_OFFER,
}

-- ============================================================
-- Controls 按钮位掩码
-- ============================================================
Shared.CTRL = {
    -- 通用移动
    LEFT    = 1,      -- bit 0
    RIGHT   = 2,      -- bit 1
    UP      = 4,      -- bit 2
    DOWN    = 8,      -- bit 3
    -- 动作
    INTERACT= 16,     -- bit 4: F键交互/拾取
    REPAIR  = 32,     -- bit 5: R键修复
    SHOOT   = 64,     -- bit 6: 射击
    EVA_EXIT= 128,    -- bit 7: G键进出气闸
    ESCAPE  = 256,    -- bit 8: ESC键
    -- 系统
    POWER_TOGGLE = 512,    -- bit 9: P键电力面板
    POWER_UP     = 1024,   -- bit 10
    POWER_DOWN   = 2048,   -- bit 11
    POWER_INC    = 4096,   -- bit 12
    POWER_DEC    = 8192,   -- bit 13
    -- 新增：物品栏/合成
    INVENTORY    = 16384,  -- bit 14: 物品栏面板
    CRAFT_PREV   = 32768,  -- bit 15
    CRAFT_NEXT   = 65536,  -- bit 16
    CRAFT_CONFIRM= 131072, -- bit 17
    -- 新增：跳跃
    JUMP         = 262144, -- bit 18: 跳跃
    -- 新增：门/舷窗/水泵交互
    DOOR_OPEN    = 524288,  -- bit 19: 开门/关门
    DOOR_LOCK    = 1048576, -- bit 20: 锁门/解锁
    PRESSURE_BAL = 2097152, -- bit 21: 手动气压平衡（长按）
    PUMP_TOGGLE  = 4194304, -- bit 22: 水泵开关
    PORTHOLE_VIEW= 8388608, -- bit 23: 查看舷窗
    PORTHOLE_COVER=16777216,-- bit 24: 关闭/打开舷窗盖
    -- 驾驶系统
    THROTTLE_UP  = 33554432, -- bit 25: 油门升档
    THROTTLE_DOWN= 67108864, -- bit 26: 油门降档
    SONAR_PULSE  = 134217728,-- bit 27: 声呐脉冲
    SEARCHLIGHT  = 268435456,-- bit 28: 探照灯开关
    -- 压载水舱
    BALLAST_FILL = 536870912, -- bit 29: 压载注水
    BALLAST_DRAIN=1073741824, -- bit 30: 压载排水
    BALLAST_EMERG=2147483648, -- bit 31: 紧急排水（UInt32 最高位）
}

-- 需要可靠传输的一次性按钮
Shared.PULSE_MASK = Shared.CTRL.INTERACT
    | Shared.CTRL.EVA_EXIT
    | Shared.CTRL.ESCAPE
    | Shared.CTRL.SHOOT
    | Shared.CTRL.POWER_TOGGLE
    | Shared.CTRL.INVENTORY
    | Shared.CTRL.CRAFT_PREV
    | Shared.CTRL.CRAFT_NEXT
    | Shared.CTRL.CRAFT_CONFIRM
    | Shared.CTRL.JUMP
    | Shared.CTRL.DOOR_OPEN
    | Shared.CTRL.DOOR_LOCK
    | Shared.CTRL.PUMP_TOGGLE
    | Shared.CTRL.PORTHOLE_VIEW
    | Shared.CTRL.PORTHOLE_COVER
    | Shared.CTRL.THROTTLE_UP
    | Shared.CTRL.THROTTLE_DOWN
    | Shared.CTRL.SONAR_PULSE
    | Shared.CTRL.SEARCHLIGHT
    | Shared.CTRL.BALLAST_EMERG

-- ============================================================
-- 职业定义
-- ============================================================
Shared.ROLES = {
    { id = "captain",  name = "船长",  desc = "操控方向·声呐+50%·标记目标" },
    { id = "engineer", name = "工程师", desc = "电力分配·引擎+30%·超载加速" },
    { id = "mechanic", name = "技工",  desc = "修复x2·高级配方·采集+50%" },
    { id = "medic",    name = "医官",  desc = "治疗·氧耗-30%·EVA+20s" },
}

-- 职业加成常量
Shared.ROLE_BONUS = {
    captain = {
        sonarRange = 1.5,       -- 声呐范围 +50%
        pilotSpeed = 1.0,       -- 只有船长能驾驶
    },
    engineer = {
        engineEff = 1.3,        -- 引擎效率 +30%
        canOverload = true,     -- 可以超载加速
        powerControl = true,    -- 可以操作电力分配
    },
    mechanic = {
        repairSpeed = 2.0,      -- 修复速度 x2
        craftBonus = true,      -- 高级配方解锁
        evaCollect = 1.5,       -- EVA采集效率 +50%
    },
    medic = {
        healRate = 2.0,         -- 治疗速率
        oxygenMult = 0.7,       -- 氧气消耗 -30%
        evaOxygenBonus = 20,    -- EVA额外氧气 +20s
    },
}

-- ============================================================
-- Controls.yaw / Controls.pitch 用途复用
-- yaw: 船长模式下表示舵盘角度（-90~+90），非船长为移动方向
-- pitch: 船长模式下表示目标深度（归一化 0~1），非船长为探照灯角度
-- ============================================================
Shared.CONTROLS_EXTRA = {
    -- yaw 复用：舵盘角度（仅captain在驾驶舱时）
    HELM_ANGLE = "yaw",
    -- pitch 复用：目标深度归一化（仅captain在驾驶舱时）
    DEPTH_TARGET = "pitch",
}

-- ============================================================
-- 游戏阶段
-- ============================================================
Shared.PHASE = {
    TITLE    = "title",     -- 标题画面（开始界面）
    MATCHING = "matching",  -- 等待匹配（background_match模式）
    LOBBY    = "lobby",
    PORT     = "port",
    DEEP_SEA = "deepsea",
    EVA      = "eva",
}

-- ============================================================
-- 工具函数
-- ============================================================

--- 注册所有远程事件
function Shared.RegisterEvents()
    for _, eventName in pairs(Shared.EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

--- 序列化游戏状态为JSON字符串
---@param state table
---@return string
function Shared.Encode(state)
    return cjson.encode(state)
end

--- 反序列化JSON字符串为table
---@param jsonStr string
---@return table
function Shared.Decode(jsonStr)
    return cjson.decode(jsonStr)
end

--- 获取连接唯一标识
---@param connection userdata
---@return string|nil
function Shared.GetConnectionKey(connection)
    if connection then
        return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
    end
    return nil
end

--- 获取职业信息
---@param roleId string
---@return table|nil
function Shared.GetRoleInfo(roleId)
    for _, role in ipairs(Shared.ROLES) do
        if role.id == roleId then return role end
    end
    return nil
end

return Shared
