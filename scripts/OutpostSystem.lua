--- 前哨站系统
--- 管理深海前哨站的类型、内部区域、NPC交互、商店
--- 前哨站在深海世界中作为可对接目标存在
local OutpostSystem = {}

-- ============================================================
-- 前哨站类型
-- ============================================================
OutpostSystem.TYPES = {
    trade = {
        id = "trade",
        name = "贸易站",
        desc = "商品丰富的贸易中心，价格偏高",
        color = {200, 180, 60},
        priceMultiplier = 1.3,     -- 商品价格×1.3
        buyMultiplier = 0.8,       -- 收购价格×0.8
        specialItems = {"rare_mineral", "alien_crystal"},
    },
    military = {
        id = "military",
        name = "军事站",
        desc = "装备精良的军事前哨，武器弹药便宜",
        color = {100, 140, 180},
        priceMultiplier = 1.0,
        buyMultiplier = 0.7,
        specialItems = {"torpedo_mk2", "armor_plate"},
        hasSecurityNPC = true,
    },
    research = {
        id = "research",
        name = "科研站",
        desc = "高端研究设施，任务报酬丰厚",
        color = {140, 200, 180},
        priceMultiplier = 1.2,
        buyMultiplier = 1.0,
        specialItems = {"scanner_upgrade", "data_core"},
        missionRewardMult = 1.5,
    },
    mining = {
        id = "mining",
        name = "矿站",
        desc = "深海矿业基地，高价收购矿石",
        color = {180, 130, 70},
        priceMultiplier = 1.1,
        buyMultiplier = 1.4,       -- 矿石收购价高
        specialItems = {"drill_bit", "ore_scanner"},
    },
    medical = {
        id = "medical",
        name = "医疗站",
        desc = "专业医疗设施，治疗费用低廉",
        color = {180, 220, 200},
        priceMultiplier = 0.7,     -- 医疗品便宜
        buyMultiplier = 0.6,
        specialItems = {"antidote", "stim_pack", "nano_repair"},
        healCostMult = 0.5,
    },
    blackmarket = {
        id = "blackmarket",
        name = "非法站",
        desc = "黑市交易所，违禁品流通，风险极高",
        color = {120, 50, 80},
        priceMultiplier = 0.6,     -- 黑市价便宜
        buyMultiplier = 1.2,       -- 收购不挑
        specialItems = {"emp_device", "stealth_coat", "illegal_cargo"},
        isIllegal = true,
    },
}

-- ============================================================
-- 前哨站内部区域
-- ============================================================
OutpostSystem.ZONES = {
    corridor  = { id = "corridor",  name = "走廊",   width = 180, desc = "连接各功能区的通道" },
    shop      = { id = "shop",      name = "商店区", width = 260, desc = "NPC商人，买卖物品" },
    mission   = { id = "mission",   name = "任务板", width = 200, desc = "接取深海任务" },
    repair    = { id = "repair",    name = "修理区", width = 220, desc = "花钱修复船体" },
    medical   = { id = "medical",   name = "医疗区", width = 220, desc = "治疗和购买药品" },
    recruit   = { id = "recruit",   name = "船员招募", width = 200, desc = "雇佣AI船员" },
    bar       = { id = "bar",       name = "酒吧",   width = 240, desc = "休息恢复士气" },
}

-- 各类型前哨站的区域布局
OutpostSystem.LAYOUTS = {
    trade     = {"corridor", "shop", "mission", "repair", "bar"},
    military  = {"corridor", "shop", "mission", "repair", "recruit"},
    research  = {"corridor", "shop", "mission", "medical", "bar"},
    mining    = {"corridor", "shop", "repair", "recruit", "bar"},
    medical   = {"corridor", "medical", "shop", "mission", "bar"},
    blackmarket = {"corridor", "shop", "mission", "bar"},
}

-- ============================================================
-- 商店物品定义
-- ============================================================
OutpostSystem.SHOP_ITEMS = {
    -- 基础补给
    { id = "coolant",      name = "冷却剂",     basePrice = 60,  category = "supply",  desc = "降低反应堆温度" },
    { id = "medkit",       name = "医疗包",     basePrice = 100, category = "medical", desc = "恢复25%船体" },
    { id = "ammo_box",     name = "弹药箱",     basePrice = 80,  category = "weapon",  desc = "炮塔弹药×5" },
    { id = "repair_kit",   name = "修复工具",   basePrice = 90,  category = "tool",    desc = "修复速度翻倍(60s)" },
    { id = "food_ration",  name = "食材包",     basePrice = 40,  category = "supply",  desc = "维持船员体力" },
    -- 高级物品
    { id = "torpedo_mk2",  name = "Mk2鱼雷",   basePrice = 250, category = "weapon",  desc = "高伤害鱼雷×2" },
    { id = "armor_plate",  name = "装甲板",     basePrice = 200, category = "tool",    desc = "+10%船体上限(永久)" },
    { id = "scanner_upgrade", name = "扫描升级", basePrice = 300, category = "tool",   desc = "声呐范围+30%" },
    { id = "antidote",     name = "解毒剂",     basePrice = 120, category = "medical", desc = "解除中毒状态" },
    { id = "stim_pack",    name = "兴奋剂",     basePrice = 150, category = "medical", desc = "移动速度+50%(30s)" },
    { id = "nano_repair",  name = "纳米修复",   basePrice = 400, category = "medical", desc = "自动修复船体(120s)" },
    { id = "drill_bit",    name = "钻头",       basePrice = 180, category = "tool",    desc = "矿石采集效率×2" },
    { id = "ore_scanner",  name = "矿石探测",   basePrice = 220, category = "tool",    desc = "显示附近矿脉" },
    -- 违禁品（仅黑市）
    { id = "emp_device",   name = "EMP装置",    basePrice = 500, category = "illegal", desc = "瘫痪附近电子设备" },
    { id = "stealth_coat", name = "隐身涂层",   basePrice = 600, category = "illegal", desc = "声呐隐身(60s)" },
    { id = "illegal_cargo", name = "违禁货物", basePrice = 50,  category = "illegal", desc = "高价转卖(有风险)" },
}

-- ============================================================
-- 前哨站创建
-- ============================================================

--- 生成一个前哨站实例
---@param typeId string 前哨站类型ID
---@param x number 世界X坐标
---@param depth number 深度（米）
---@param id string|nil 唯一ID
---@return table outpost
function OutpostSystem.Create(typeId, x, depth, id)
    local typeDef = OutpostSystem.TYPES[typeId]
    if not typeDef then
        typeDef = OutpostSystem.TYPES["trade"]
        typeId = "trade"
    end

    local layout = OutpostSystem.LAYOUTS[typeId] or {"corridor", "shop"}

    -- 构建区域列表
    local zones = {}
    local zoneX = 0
    for i, zoneId in ipairs(layout) do
        local zoneDef = OutpostSystem.ZONES[zoneId]
        zones[i] = {
            id = zoneDef.id,
            name = zoneDef.name,
            width = zoneDef.width,
            x = zoneX,
            desc = zoneDef.desc,
        }
        zoneX = zoneX + zoneDef.width
    end

    -- 生成商店库存
    local shopInventory = OutpostSystem.GenerateShopInventory(typeId)

    -- 生成可用任务
    local missions = OutpostSystem.GenerateMissions(typeId, 3)

    return {
        -- 标识
        id = id or ("outpost_" .. typeId .. "_" .. math.random(10000, 99999)),
        typeId = typeId,
        typeDef = typeDef,
        name = typeDef.name,

        -- 世界位置
        x = x,
        depth = depth,
        dockAngle = 0,           -- 对接口朝向角度

        -- 内部结构
        zones = zones,
        totalWidth = zoneX,

        -- 商店
        shopInventory = shopInventory,

        -- 任务
        missions = missions,

        -- 修理服务
        repairCostPerPercent = 5,  -- 每1%船体修复费用

        -- 船员招募
        availableCrew = OutpostSystem.GenerateCrewForHire(typeId),

        -- NPC状态
        npcs = OutpostSystem.GenerateNPCs(typeId),

        -- 玩家在站内的位置
        playerZoneIndex = 1,     -- 当前所在区域索引
        playerX = 0,             -- 在区域内的X位置

        -- 交互状态
        activeDialog = nil,      -- 当前对话
        activeMenu = nil,        -- 当前菜单（shop/mission/repair/recruit）

        -- 发现状态
        discovered = false,      -- 是否被发现
        visitCount = 0,          -- 访问次数
    }
end

-- ============================================================
-- 商店系统
-- ============================================================

--- 生成商店库存
---@param typeId string 前哨站类型
---@return table[] inventory
function OutpostSystem.GenerateShopInventory(typeId)
    local typeDef = OutpostSystem.TYPES[typeId]
    local inventory = {}

    for _, item in ipairs(OutpostSystem.SHOP_ITEMS) do
        -- 违禁品仅黑市有
        if item.category == "illegal" and typeId ~= "blackmarket" then
            goto continue
        end

        -- 非违禁品在黑市也有
        local inStock = true
        local stock = math.random(3, 8)

        -- 特殊物品只在对应站点出现
        if item.id == "torpedo_mk2" or item.id == "armor_plate" then
            inStock = (typeId == "military" or typeId == "trade")
        elseif item.id == "scanner_upgrade" or item.id == "drill_bit" or item.id == "ore_scanner" then
            inStock = (typeId == "research" or typeId == "mining")
        elseif item.id == "antidote" or item.id == "stim_pack" or item.id == "nano_repair" then
            inStock = (typeId == "medical" or typeId == "trade")
        end

        if inStock then
            -- 应用价格倍率
            local price = math.floor(item.basePrice * typeDef.priceMultiplier)
            table.insert(inventory, {
                id = item.id,
                name = item.name,
                price = price,
                stock = stock,
                category = item.category,
                desc = item.desc,
            })
        end

        ::continue::
    end

    return inventory
end

--- 购买物品
---@param outpost table 前哨站实例
---@param itemIndex number 物品索引
---@param gameState table 游戏状态
---@param reputation number 当前声望
---@return boolean success
---@return string message
function OutpostSystem.BuyItem(outpost, itemIndex, gameState, reputation)
    local item = outpost.shopInventory[itemIndex]
    if not item then return false, "物品不存在" end
    if item.stock <= 0 then return false, item.name .. " 库存不足" end

    -- 声望折扣/加价
    local repMod = OutpostSystem.GetReputationPriceModifier(reputation)
    local finalPrice = math.floor(item.price * repMod)

    if gameState.gold < finalPrice then
        return false, string.format("金币不足（需要%d，现有%d）", finalPrice, gameState.gold)
    end

    gameState.gold = gameState.gold - finalPrice
    item.stock = item.stock - 1
    gameState.supplies[item.id] = (gameState.supplies[item.id] or 0) + 1

    return true, string.format("购买 %s -%d金币", item.name, finalPrice)
end

--- 出售物品
---@param outpost table 前哨站实例
---@param itemId string 物品ID
---@param gameState table 游戏状态
---@param reputation number 当前声望
---@return boolean success
---@return string message
function OutpostSystem.SellItem(outpost, itemId, gameState, reputation)
    local count = gameState.supplies[itemId]
    if not count or count <= 0 then
        return false, "没有这个物品"
    end

    -- 查找物品基础价格
    local basePrice = 0
    local itemName = itemId
    for _, def in ipairs(OutpostSystem.SHOP_ITEMS) do
        if def.id == itemId then
            basePrice = def.basePrice
            itemName = def.name
            break
        end
    end

    if basePrice == 0 then
        basePrice = 20  -- 未知物品默认收购价
    end

    local typeDef = outpost.typeDef
    local sellPrice = math.floor(basePrice * typeDef.buyMultiplier * 0.5)

    -- 声望加成
    local repMod = OutpostSystem.GetReputationSellModifier(reputation)
    sellPrice = math.floor(sellPrice * repMod)
    sellPrice = math.max(1, sellPrice)

    gameState.gold = gameState.gold + sellPrice
    gameState.supplies[itemId] = count - 1
    if gameState.supplies[itemId] <= 0 then
        gameState.supplies[itemId] = nil
    end

    return true, string.format("出售 %s +%d金币", itemName, sellPrice)
end

-- ============================================================
-- 修理服务
-- ============================================================

--- 计算修理费用
---@param outpost table 前哨站实例
---@param currentHull number 当前船体值
---@param maxHull number 最大船体值
---@return number cost 修理费用
---@return number repairAmount 修理量
function OutpostSystem.GetRepairCost(outpost, currentHull, maxHull)
    local damage = maxHull - currentHull
    if damage <= 0 then return 0, 0 end
    local percent = damage / maxHull * 100
    local cost = math.floor(percent * outpost.repairCostPerPercent)
    return cost, damage
end

--- 执行修理
---@param outpost table 前哨站实例
---@param gameState table 游戏状态
---@param sub table 潜艇状态
---@return boolean success
---@return string message
function OutpostSystem.RepairSubmarine(outpost, gameState, sub)
    local maxHull = require("Config").Game.maxHull
    local cost, amount = OutpostSystem.GetRepairCost(outpost, sub.hull, maxHull)

    if amount <= 0 then return false, "船体完好，无需修理" end
    if gameState.gold < cost then
        return false, string.format("金币不足（修理费%d，现有%d）", cost, gameState.gold)
    end

    gameState.gold = gameState.gold - cost
    sub.hull = maxHull

    return true, string.format("修理完成！-%d金币，船体恢复至100%%", cost)
end

-- ============================================================
-- 船员招募
-- ============================================================

--- 生成可招募船员
---@param typeId string 前哨站类型
---@return table[] crewList
function OutpostSystem.GenerateCrewForHire(typeId)
    local professions = {"engineer", "medic", "gunner", "navigator"}
    local names = {"张伟", "李明", "王强", "刘洋", "陈勇", "杨帆", "赵鑫", "周海"}

    local count = math.random(1, 3)
    local crew = {}

    for i = 1, count do
        local prof = professions[math.random(1, #professions)]
        local name = names[math.random(1, #names)]
        local cost = math.random(150, 400)

        -- 军事站船员更便宜更专业
        if typeId == "military" then
            cost = math.floor(cost * 0.7)
        end

        crew[i] = {
            id = "crew_" .. i .. "_" .. math.random(1000, 9999),
            name = name,
            profession = prof,
            cost = cost,
            skill = math.random(1, 5),   -- 技能等级 1~5
        }
    end

    return crew
end

--- 雇佣船员
---@param outpost table 前哨站实例
---@param crewIndex number 船员索引
---@param gameState table 游戏状态
---@return boolean success
---@return string message
---@return table|nil crewData 雇佣的船员数据
function OutpostSystem.HireCrew(outpost, crewIndex, gameState)
    local crew = outpost.availableCrew[crewIndex]
    if not crew then return false, "船员不存在", nil end

    if gameState.gold < crew.cost then
        return false, string.format("金币不足（需要%d）", crew.cost), nil
    end

    gameState.gold = gameState.gold - crew.cost
    table.remove(outpost.availableCrew, crewIndex)

    return true, string.format("雇佣 %s（%s）-%d金币", crew.name, crew.profession, crew.cost), crew
end

-- ============================================================
-- NPC系统
-- ============================================================

--- 生成前哨站NPC
---@param typeId string 前哨站类型
---@return table[] npcs
function OutpostSystem.GenerateNPCs(typeId)
    local npcs = {
        { id = "shopkeeper", name = "商人", zone = "shop", dialog = "欢迎光临！看看有什么需要的？" },
    }

    if typeId == "military" then
        table.insert(npcs, { id = "officer", name = "安全官", zone = "corridor",
            dialog = "保持警惕，深海中危险无处不在。" })
    elseif typeId == "research" then
        table.insert(npcs, { id = "scientist", name = "科学家", zone = "mission",
            dialog = "我们正在研究深海生态，有些任务需要帮助。" })
    elseif typeId == "blackmarket" then
        table.insert(npcs, { id = "dealer", name = "掮客", zone = "shop",
            dialog = "嘘...想要点特殊的东西吗？" })
    end

    -- 酒吧区NPC
    table.insert(npcs, { id = "bartender", name = "酒保", zone = "bar",
        dialog = "来一杯？在这深海里，放松一下也是生存技能。" })

    return npcs
end

-- ============================================================
-- 任务生成
-- ============================================================

--- 生成前哨站任务
---@param typeId string 前哨站类型
---@param count number 任务数量
---@return table[] missions
function OutpostSystem.GenerateMissions(typeId, count)
    local templates = {
        { type = "collect", title = "矿石采集", desc = "采集%d份稀有矿石", target = 3, reward = 200 },
        { type = "kill",    title = "生物清剿", desc = "消灭%d只深海生物", target = 5, reward = 300 },
        { type = "explore", title = "遗迹探索", desc = "探索%d处未知遗迹", target = 2, reward = 250 },
        { type = "deliver", title = "物资运送", desc = "将物资送达指定坐标", target = 1, reward = 180 },
        { type = "survive", title = "深海生存", desc = "在%dm以下存活%d分钟", target = 5, reward = 350 },
        { type = "rescue",  title = "救援任务", desc = "救援被困船员", target = 1, reward = 400 },
    }

    local typeDef = OutpostSystem.TYPES[typeId]
    local rewardMult = typeDef.missionRewardMult or 1.0

    local missions = {}
    local used = {}

    for i = 1, math.min(count, #templates) do
        local idx
        repeat
            idx = math.random(1, #templates)
        until not used[idx]
        used[idx] = true

        local tmpl = templates[idx]
        local reward = math.floor(tmpl.reward * rewardMult * (0.8 + math.random() * 0.4))

        missions[i] = {
            id = "outpost_mission_" .. i .. "_" .. math.random(1000, 9999),
            type = tmpl.type,
            title = tmpl.title,
            desc = string.format(tmpl.desc, tmpl.target, tmpl.target),
            target = tmpl.target,
            reward = reward,
            progress = 0,
            completed = false,
        }
    end

    return missions
end

-- ============================================================
-- 声望价格接口
-- ============================================================

--- 获取声望对购买价格的影响
---@param reputation number 声望值 (-100~100)
---@return number modifier 价格倍率
function OutpostSystem.GetReputationPriceModifier(reputation)
    -- 声望高 → 折扣；低 → 加价
    -- -100 → 1.5x; 0 → 1.0x; 100 → 0.7x
    local mod = 1.0 - (reputation / 100) * 0.3
    return math.max(0.5, math.min(1.5, mod))
end

--- 获取声望对出售价格的影响
---@param reputation number 声望值
---@return number modifier
function OutpostSystem.GetReputationSellModifier(reputation)
    -- 声望高 → 收购价高
    local mod = 1.0 + (reputation / 100) * 0.3
    return math.max(0.5, math.min(1.5, mod))
end

-- ============================================================
-- 世界生成辅助
-- ============================================================

--- 在世界中随机生成前哨站列表
---@param count number 生成数量
---@param worldWidth number 世界宽度（米）
---@param depthRange table {min, max} 深度范围
---@return table[] outposts
function OutpostSystem.GenerateWorldOutposts(count, worldWidth, depthRange)
    local typeIds = {"trade", "military", "research", "mining", "medical", "blackmarket"}
    local outposts = {}

    -- 均匀分布在世界中
    local spacing = worldWidth / (count + 1)

    for i = 1, count do
        local typeId = typeIds[math.random(1, #typeIds)]
        local x = spacing * i + math.random(-50, 50)
        local depth = math.random(depthRange.min, depthRange.max)

        local outpost = OutpostSystem.Create(typeId, x, depth, "outpost_" .. i)
        table.insert(outposts, outpost)
    end

    return outposts
end

--- 获取前哨站在对接后玩家可交互的菜单列表
---@param outpost table 前哨站实例
---@return table[] menus
function OutpostSystem.GetAvailableMenus(outpost)
    local menus = {}
    for _, zone in ipairs(outpost.zones) do
        if zone.id == "shop" then
            table.insert(menus, { id = "shop", name = "商店", icon = "🛒" })
        elseif zone.id == "mission" then
            table.insert(menus, { id = "mission", name = "任务板", icon = "📋" })
        elseif zone.id == "repair" then
            table.insert(menus, { id = "repair", name = "修理", icon = "🔧" })
        elseif zone.id == "medical" then
            table.insert(menus, { id = "medical", name = "医疗", icon = "💊" })
        elseif zone.id == "recruit" then
            table.insert(menus, { id = "recruit", name = "招募", icon = "👤" })
        elseif zone.id == "bar" then
            table.insert(menus, { id = "bar", name = "酒吧", icon = "🍺" })
        end
    end
    return menus
end

return OutpostSystem
