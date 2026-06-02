--- 触屏操作管理器（简化版）
--- 除移动摇杆外，只有3个按钮：互动、菜单、跳跃
--- 菜单按钮打开径向菜单，提供全部子功能

local TouchControls = {}

-- ============================================================
-- 按钮组定义
-- ============================================================

-- 主按钮（所有场景通用，只有3个）
local mainButtons = {}
-- 当前活跃按钮组
local activeGroup = nil

-- 径向菜单状态
TouchControls.menuOpen = false
TouchControls.menuSelection = nil  -- 选中的菜单项名称

-- 按钮状态（供外部读取）
TouchControls.actions = {
    -- 主要操作（3按钮直接触发）
    interact = false,     -- 互动（上下文感知：拾取/修复/开门/使用设备等）
    jump = false,         -- 跳跃
    menuToggle = false,   -- 打开/关闭菜单

    -- 以下 action 由径向菜单选择后触发
    repair = false,       -- 修复
    turret = false,       -- 切换炮塔
    eva = false,          -- 进出EVA
    power = false,        -- 电力面板
    inventory = false,    -- 物品栏
    pickup = false,       -- 拾取（等同于interact）
    extView = false,      -- 外部视角
    escape = false,       -- 返回
    fire = false,         -- 射击
    evaReturn = false,    -- 返回气闸
    -- 电力面板（在覆盖模式中自动出现）
    powerUp = false,
    powerDown = false,
    powerInc = false,
    powerDec = false,
    -- 物品栏
    craftPrev = false,
    craftNext = false,
    craftConfirm = false,
    useItem1 = false,
    useItem2 = false,
    useItem3 = false,
    useItem4 = false,
    useItem5 = false,
    -- 反应堆面板
    reactorInc = false,
    reactorDec = false,
    reactorCool = false,
    -- 门/舷窗/水泵交互（由 interact 自动判断）
    doorOpen = false,
    doorLock = false,
    pumpToggle = false,
    portholeView = false,
    portholeCover = false,
    -- 驾驶系统（由菜单选择触发）
    throttleUp = false,
    throttleDown = false,
    sonarPulse = false,
    searchlight = false,
    ballastEmerg = false,
    navMap = false,
}

-- 按压状态（held = 持续按住）
TouchControls.held = {
    repair = false,
    powerInc = false,
    powerDec = false,
    reactorShutdown = false,
    pressureBalance = false,
    ballastFill = false,
    ballastDrain = false,
}

-- ============================================================
-- 径向菜单配置（根据场景动态切换）
-- ============================================================

-- 深海场景菜单项
local deepSeaMenuItems = {
    { id = "turret",     label = "炮塔", color = {220, 80, 80} },
    { id = "eva",        label = "出舱", color = {80, 180, 255} },
    { id = "power",      label = "电力", color = {255, 255, 100} },
    { id = "inventory",  label = "背包", color = {180, 140, 100} },
    { id = "extView",    label = "外视", color = {150, 200, 230} },
    { id = "searchlight",label = "灯光", color = {255, 230, 100} },
    { id = "sonarPulse", label = "声呐", color = {80, 255, 180} },
    { id = "navMap",     label = "导航", color = {100, 180, 255} },
}

-- EVA 场景菜单项
local evaMenuItems = {
    { id = "evaReturn",  label = "返回", color = {255, 200, 80} },
}

-- 当前菜单项列表
local currentMenuItems = deepSeaMenuItems

-- ============================================================
-- 初始化
-- ============================================================

function TouchControls.Init()
    TouchControls.Clear()

    -- ==================== 三个主按钮 ====================

    -- 右下角：互动按钮（最大、最容易按到）
    -- 上下文感知：点按=拾取/开门/使用设备，长按=修复
    mainButtons.interact = VirtualControls.CreateButton({
        position = Vector2(-130, -140),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = 120,
        label = "互动",
        color = {100, 220, 150},
        keyBinding = KEY_E,
        opacity = 0.6,
        on_press = function()
            TouchControls.actions.interact = true
            TouchControls.actions.pickup = true
            TouchControls.held.repair = true
        end,
        on_release = function()
            TouchControls.held.repair = false
        end,
    })

    -- 右下角偏上：跳跃
    mainButtons.jump = VirtualControls.CreateButton({
        position = Vector2(-350, -140),
        alignment = {HA_RIGHT, VA_BOTTOM},
        radius = 102,
        label = "跳跃",
        color = {120, 200, 255},
        keyBinding = KEY_SPACE,
        opacity = 0.55,
        on_press = function() TouchControls.actions.jump = true end,
    })

    -- 左上角：菜单按钮（打开径向菜单）
    mainButtons.menu = VirtualControls.CreateButton({
        position = Vector2(100, 80),
        alignment = {HA_LEFT, VA_TOP},
        radius = 84,
        label = "菜单",
        color = {200, 180, 255},
        keyBinding = KEY_TAB,
        opacity = 0.5,
        on_press = function()
            TouchControls.actions.menuToggle = true
            TouchControls.menuOpen = not TouchControls.menuOpen
        end,
    })

    -- 初始全部隐藏
    TouchControls.HideAll()
end

-- ============================================================
-- 径向菜单逻辑
-- ============================================================

--- 选择径向菜单中的某一项（由 UI 层或径向菜单触摸逻辑调用）
---@param itemId string
function TouchControls.SelectMenuItem(itemId)
    TouchControls.menuOpen = false
    TouchControls.menuSelection = itemId

    -- 将选择映射到 action
    if TouchControls.actions[itemId] ~= nil then
        TouchControls.actions[itemId] = true
    end
end

--- 获取当前菜单项列表
function TouchControls.GetMenuItems()
    return currentMenuItems
end

-- ============================================================
-- 场景切换
-- ============================================================

--- 切换到深海场景
function TouchControls.ShowDeepSea()
    TouchControls.HideAll()
    for _, btn in pairs(mainButtons) do
        btn._shouldShow = true
    end
    currentMenuItems = deepSeaMenuItems
    activeGroup = "deepsea"
end

--- 切换到EVA场景
function TouchControls.ShowEVA()
    TouchControls.HideAll()
    for _, btn in pairs(mainButtons) do
        btn._shouldShow = true
    end
    currentMenuItems = evaMenuItems
    activeGroup = "eva"
end

--- 切换到炮塔模式（只保留菜单按钮用于退出）
function TouchControls.ShowTurret()
    TouchControls.HideAll()
    mainButtons.menu._shouldShow = true
    activeGroup = "turret"
end

--- 切换到港口场景（隐藏所有虚拟按钮）
function TouchControls.ShowPort()
    TouchControls.HideAll()
    activeGroup = "port"
end

--- 切换到大厅
function TouchControls.ShowLobby()
    TouchControls.HideAll()
    activeGroup = "lobby"
end

--- 显示电力面板覆盖（互动按钮变为"+/-"操作）
function TouchControls.ShowPowerOverlay()
    -- 电力面板保持3按钮：互动=确认, 跳跃=切换项, 菜单=关闭
    activeGroup = "power_overlay"
end

--- 隐藏电力面板覆盖
function TouchControls.HidePowerOverlay()
    if activeGroup == "power_overlay" then
        activeGroup = "deepsea"
    end
end

--- 显示反应堆面板覆盖
function TouchControls.ShowReactorOverlay()
    activeGroup = "reactor_overlay"
end

--- 隐藏反应堆面板覆盖
function TouchControls.HideReactorOverlay()
    if activeGroup == "reactor_overlay" then
        activeGroup = "deepsea"
    end
end

--- 显示物品栏覆盖
function TouchControls.ShowInventoryOverlay()
    activeGroup = "inventory_overlay"
end

--- 隐藏物品栏覆盖
function TouchControls.HideInventoryOverlay()
    if activeGroup == "inventory_overlay" then
        activeGroup = "deepsea"
    end
end

--- 隐藏所有按钮
function TouchControls.HideAll()
    for _, btn in pairs(mainButtons) do
        btn._shouldShow = false
    end
    activeGroup = nil
    TouchControls.menuOpen = false
end

-- ============================================================
-- 每帧重置
-- ============================================================

--- 清除一次性动作标记（每帧更新开头调用）
function TouchControls.ResetActions()
    TouchControls.actions.interact = false
    TouchControls.actions.jump = false
    TouchControls.actions.menuToggle = false
    TouchControls.actions.repair = false
    TouchControls.actions.turret = false
    TouchControls.actions.eva = false
    TouchControls.actions.power = false
    TouchControls.actions.inventory = false
    TouchControls.actions.pickup = false
    TouchControls.actions.extView = false
    TouchControls.actions.escape = false
    TouchControls.actions.fire = false
    TouchControls.actions.evaReturn = false
    TouchControls.actions.powerUp = false
    TouchControls.actions.powerDown = false
    TouchControls.actions.powerInc = false
    TouchControls.actions.powerDec = false
    TouchControls.actions.craftPrev = false
    TouchControls.actions.craftNext = false
    TouchControls.actions.craftConfirm = false
    TouchControls.actions.useItem1 = false
    TouchControls.actions.useItem2 = false
    TouchControls.actions.useItem3 = false
    TouchControls.actions.useItem4 = false
    TouchControls.actions.useItem5 = false
    TouchControls.actions.reactorInc = false
    TouchControls.actions.reactorDec = false
    TouchControls.actions.reactorCool = false
    TouchControls.actions.doorOpen = false
    TouchControls.actions.doorLock = false
    TouchControls.actions.pumpToggle = false
    TouchControls.actions.portholeView = false
    TouchControls.actions.portholeCover = false
    TouchControls.actions.throttleUp = false
    TouchControls.actions.throttleDown = false
    TouchControls.actions.sonarPulse = false
    TouchControls.actions.searchlight = false
    TouchControls.actions.ballastEmerg = false
    TouchControls.actions.navMap = false
    TouchControls.menuSelection = nil
end

-- ============================================================
-- 工具
-- ============================================================

--- 获取当前活跃组名
function TouchControls.GetActiveGroup()
    return activeGroup
end

--- 完全清理
function TouchControls.Clear()
    VirtualControls.Clear()
    mainButtons = {}
    activeGroup = nil
    TouchControls.menuOpen = false
end

return TouchControls
