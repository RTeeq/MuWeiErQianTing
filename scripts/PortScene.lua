--- 港口场景逻辑
--- 包含商店、升级数据和港口交互
local PortScene = {}

-- ============================================================
-- 港口标签页
-- ============================================================
PortScene.TAB_MISSION = 1    -- 任务板
PortScene.TAB_SHOP = 2      -- 补给商店
PortScene.TAB_UPGRADE = 3   -- 潜艇升级
PortScene.TAB_DEPART = 4    -- 出港

PortScene.TAB_NAMES = { "任务板", "补给站", "升级坞", "出港" }

-- ============================================================
-- 商店物品定义
-- ============================================================
PortScene.SHOP_ITEMS = {
    { id = "ammo_pack",    name = "弹药补给",   price = 80,  desc = "炮塔弹药×5发" },
    { id = "medkit",       name = "急救医疗包", price = 120, desc = "立即恢复25%船体" },
    { id = "repair_tool",  name = "焊接修复器", price = 100, desc = "修复速度翻倍(60s)" },
    { id = "power_cell",   name = "聚变电芯",   price = 150, desc = "总电力+20(60s)" },
    { id = "sonar_boost",  name = "声呐增幅器", price = 130, desc = "声呐效率翻倍(45s)" },
}

-- ============================================================
-- 升级定义
-- ============================================================
PortScene.UPGRADES = {
    { id = "hull",   name = "船体加固",   desc = "+20% 最大船体",     baseCost = 200 },
    { id = "engine", name = "引擎强化",   desc = "+15% 移动速度",     baseCost = 180 },
    { id = "oxygen", name = "氧气循环",   desc = "-20% 氧气消耗",     baseCost = 160 },
    { id = "turret", name = "炮塔改装",   desc = "+25% 炮塔伤害",     baseCost = 250 },
    { id = "sonar",  name = "声呐阵列",   desc = "+20% 探测范围",     baseCost = 220 },
    { id = "armor",  name = "纳米装甲",   desc = "-15% 受到伤害",     baseCost = 300 },
}

-- ============================================================
-- 港口状态
-- ============================================================

--- 创建港口场景状态
function PortScene.Create()
    local port = {
        currentTab = PortScene.TAB_MISSION,  -- 当前标签页
        selectedItem = 1,                     -- 当前选中的项目索引
        message = nil,                        -- 提示消息
        messageTimer = 0,                     -- 消息显示倒计时
        animTime = 0,                         -- 动画时间
    }
    return port
end

--- 更新港口场景
function PortScene.Update(port, dt)
    port.animTime = port.animTime + dt

    -- 消息倒计时
    if port.messageTimer > 0 then
        port.messageTimer = port.messageTimer - dt
        if port.messageTimer <= 0 then
            port.message = nil
        end
    end
end

--- 显示提示消息
function PortScene.ShowMessage(port, msg)
    port.message = msg
    port.messageTimer = 2.5
end

--- 切换标签页
function PortScene.SwitchTab(port, tabIndex)
    if tabIndex >= 1 and tabIndex <= 4 then
        port.currentTab = tabIndex
        port.selectedItem = 1
    end
end

--- 选择上一项
function PortScene.SelectPrev(port)
    port.selectedItem = port.selectedItem - 1
    local maxItems = PortScene.GetMaxItems(port)
    if port.selectedItem < 1 then
        port.selectedItem = maxItems
    end
end

--- 选择下一项
function PortScene.SelectNext(port)
    port.selectedItem = port.selectedItem + 1
    local maxItems = PortScene.GetMaxItems(port)
    if port.selectedItem > maxItems then
        port.selectedItem = 1
    end
end

--- 获取当前标签最大项目数
function PortScene.GetMaxItems(port)
    if port.currentTab == PortScene.TAB_MISSION then
        return 5  -- 任务数由MissionSystem决定，这里给个默认
    elseif port.currentTab == PortScene.TAB_SHOP then
        return #PortScene.SHOP_ITEMS
    elseif port.currentTab == PortScene.TAB_UPGRADE then
        return #PortScene.UPGRADES
    end
    return 1
end

--- 购买商店物品
function PortScene.BuyItem(port, gameState)
    if port.currentTab ~= PortScene.TAB_SHOP then return false end

    local itemDef = PortScene.SHOP_ITEMS[port.selectedItem]
    if not itemDef then return false end

    -- 检查金币
    if gameState.gold < itemDef.price then
        PortScene.ShowMessage(port, "金币不足！需要 " .. itemDef.price .. " 金币")
        return false
    end

    -- 购买
    gameState.gold = gameState.gold - itemDef.price
    gameState.supplies[itemDef.id] = (gameState.supplies[itemDef.id] or 0) + 1
    PortScene.ShowMessage(port, "购买成功：" .. itemDef.name)
    return true
end

--- 升级潜艇
function PortScene.UpgradeSub(port, gameState)
    if port.currentTab ~= PortScene.TAB_UPGRADE then return false end

    local upgDef = PortScene.UPGRADES[port.selectedItem]
    if not upgDef then return false end

    local currentLevel = gameState.upgrades[upgDef.id] or 1
    if currentLevel >= 5 then
        PortScene.ShowMessage(port, upgDef.name .. " 已达最高等级！")
        return false
    end

    -- 费用随等级递增
    local cost = upgDef.baseCost * currentLevel
    if gameState.gold < cost then
        PortScene.ShowMessage(port, "金币不足！需要 " .. cost .. " 金币")
        return false
    end

    -- 升级
    gameState.gold = gameState.gold - cost
    gameState.upgrades[upgDef.id] = currentLevel + 1
    PortScene.ShowMessage(port, upgDef.name .. " 升级到 Lv." .. (currentLevel + 1))
    return true
end

--- 获取升级费用
function PortScene.GetUpgradeCost(upgDef, currentLevel)
    return upgDef.baseCost * currentLevel
end

return PortScene
