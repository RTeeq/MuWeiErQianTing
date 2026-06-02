--- 物品栏与材料系统
--- 管理废料拾取、材料分解、物品存储

local Inventory = {}

-- ============================================================
-- 物品定义
-- ============================================================

--- 材料类型
Inventory.MATERIALS = {
    scrap_metal  = { name = "废金属",   icon = "M", color = {160, 170, 180} },
    wires        = { name = "电线",     icon = "W", color = {220, 180, 50} },
    chemicals    = { name = "化学品",   icon = "C", color = {80, 220, 140} },
    circuits     = { name = "电路板",   icon = "B", color = {50, 180, 220} },
    polymer      = { name = "聚合物",   icon = "P", color = {200, 130, 220} },
}

--- 废料类型（可拾取物）
Inventory.SCRAP_TYPES = {
    {
        id = "metal_debris",
        name = "金属碎片",
        icon = "◆",
        color = {150, 160, 170},
        yields = { scrap_metal = {2, 4} },  -- 分解产出：2~4个废金属
        weight = 40,  -- 生成权重
    },
    {
        id = "wire_bundle",
        name = "线缆束",
        icon = "≈",
        color = {200, 170, 50},
        yields = { wires = {2, 3}, scrap_metal = {0, 1} },
        weight = 30,
    },
    {
        id = "chem_canister",
        name = "化学罐",
        icon = "●",
        color = {60, 200, 120},
        yields = { chemicals = {1, 3} },
        weight = 20,
    },
    {
        id = "circuit_board",
        name = "旧电路板",
        icon = "□",
        color = {40, 160, 200},
        yields = { circuits = {1, 2}, wires = {0, 1} },
        weight = 15,
    },
    {
        id = "plastic_chunk",
        name = "塑料块",
        icon = "▪",
        color = {180, 120, 200},
        yields = { polymer = {2, 3} },
        weight = 20,
    },
}

--- 制成品类型
Inventory.PRODUCTS = {
    ammo_pack = {
        name = "弹药包",
        icon = "▶",
        color = {255, 80, 80},
        desc = "补充炮塔5发弹药",
        stackable = true,
        maxStack = 10,
    },
    medkit = {
        name = "医疗包",
        icon = "+",
        color = {80, 255, 130},
        desc = "修复20点船体",
        stackable = true,
        maxStack = 5,
    },
    repair_tool = {
        name = "修复工具",
        icon = "⚒",
        color = {220, 200, 80},
        desc = "修复速度翻倍(30秒)",
        stackable = true,
        maxStack = 3,
    },
    power_cell = {
        name = "电力芯",
        icon = "⚡",
        color = {100, 200, 255},
        desc = "临时增加20总电力(60秒)",
        stackable = true,
        maxStack = 3,
    },
    sonar_boost = {
        name = "声呐增幅器",
        icon = "◎",
        color = {80, 255, 200},
        desc = "声呐探测距离加倍(45秒)",
        stackable = true,
        maxStack = 3,
    },
}

-- ============================================================
-- 创建
-- ============================================================

--- 创建物品栏系统
---@return table
function Inventory.Create()
    return {
        -- 材料（键=材料ID，值=数量）
        materials = {
            scrap_metal = 0,
            wires = 0,
            chemicals = 0,
            circuits = 0,
            polymer = 0,
        },

        -- 制成品（键=产品ID，值=数量）
        products = {
            ammo_pack = 0,
            medkit = 0,
            repair_tool = 0,
            power_cell = 0,
            sonar_boost = 0,
        },

        -- 地上废料（等待拾取）
        scraps = {},         -- {id, type, x, roomIndex, bobTime}

        -- 拾取提示
        nearScrap = nil,     -- 当前靠近的废料

        -- buff效果
        buffs = {},          -- {id, remaining, ...}

        -- 生成计时
        spawnTimer = 0,
        spawnInterval = 12,  -- 每12秒尝试生成废料

        -- 统计
        totalCollected = 0,  -- 总收集废料数（用于任务追踪）

        -- UI
        isOpen = false,      -- 面板是否展开
        message = nil,       -- 提示消息
        messageTimer = 0,
    }
end

-- ============================================================
-- 废料生成
-- ============================================================

--- 按权重随机选一种废料
---@return table
local function randomScrapType()
    local totalWeight = 0
    for _, s in ipairs(Inventory.SCRAP_TYPES) do
        totalWeight = totalWeight + s.weight
    end
    local roll = math.random() * totalWeight
    local acc = 0
    for _, s in ipairs(Inventory.SCRAP_TYPES) do
        acc = acc + s.weight
        if roll <= acc then return s end
    end
    return Inventory.SCRAP_TYPES[1]
end

--- 在舱室中生成废料
---@param inv table
---@param sub table
---@param gameTime number
function Inventory.SpawnScrap(inv, sub, gameTime)
    -- 最多同时存在6个废料
    if #inv.scraps >= 6 then return end

    -- 随机选一个舱室（不在驾驶舱生成）
    local roomIdx = math.random(2, #sub.compartments)
    local comp = sub.compartments[roomIdx]
    if not comp then return end

    local scrapType = randomScrapType()
    local scrap = {
        id = scrapType.id .. "_" .. math.floor(gameTime * 1000),
        typeData = scrapType,
        x = comp.x + 20 + math.random() * (comp.width - 40),
        roomIndex = roomIdx,
        bobTime = math.random() * math.pi * 2,  -- 随机起始浮动相位
        spawnTime = gameTime,
    }

    table.insert(inv.scraps, scrap)
end

-- ============================================================
-- 更新
-- ============================================================

--- 更新物品栏系统
---@param inv table
---@param sub table
---@param char table
---@param dt number
---@param gameTime number
function Inventory.Update(inv, sub, char, dt, gameTime)
    -- 废料自动生成
    inv.spawnTimer = inv.spawnTimer + dt
    if inv.spawnTimer >= inv.spawnInterval then
        inv.spawnTimer = 0
        Inventory.SpawnScrap(inv, sub, gameTime)
    end

    -- 检测角色是否靠近废料
    inv.nearScrap = nil
    for i, scrap in ipairs(inv.scraps) do
        if scrap.roomIndex == char.roomIndex then
            if math.abs(char.x - scrap.x) < 40 then
                inv.nearScrap = scrap
                break
            end
        end
    end

    -- 更新浮动动画
    for _, scrap in ipairs(inv.scraps) do
        scrap.bobTime = scrap.bobTime + dt
    end

    -- 更新buff倒计时
    for i = #inv.buffs, 1, -1 do
        local buff = inv.buffs[i]
        buff.remaining = buff.remaining - dt
        if buff.remaining <= 0 then
            table.remove(inv.buffs, i)
        end
    end

    -- 更新消息
    if inv.messageTimer > 0 then
        inv.messageTimer = inv.messageTimer - dt
        if inv.messageTimer <= 0 then
            inv.message = nil
        end
    end
end

-- ============================================================
-- 操作
-- ============================================================

--- 拾取靠近的废料
---@param inv table
---@return boolean 是否成功拾取
function Inventory.PickupNearScrap(inv)
    if not inv.nearScrap then return false end

    local scrap = inv.nearScrap
    local typeData = scrap.typeData

    -- 分解获得材料
    local gained = {}
    for matId, range in pairs(typeData.yields) do
        local amount = math.random(range[1], range[2])
        if amount > 0 then
            inv.materials[matId] = inv.materials[matId] + amount
            table.insert(gained, { id = matId, amount = amount })
        end
    end

    -- 从地图移除
    for i, s in ipairs(inv.scraps) do
        if s.id == scrap.id then
            table.remove(inv.scraps, i)
            break
        end
    end
    inv.nearScrap = nil
    inv.totalCollected = inv.totalCollected + 1

    -- 组装提示消息
    local msg = "拾取 " .. typeData.name .. " → "
    for j, g in ipairs(gained) do
        local matDef = Inventory.MATERIALS[g.id]
        msg = msg .. matDef.name .. "×" .. g.amount
        if j < #gained then msg = msg .. ", " end
    end
    inv.message = msg
    inv.messageTimer = 3.0

    return true
end

--- 使用制成品
---@param inv table
---@param productId string
---@param sub table
---@param turret table
---@param powerSys table
---@return boolean
function Inventory.UseProduct(inv, productId, sub, turret, powerSys)
    if inv.products[productId] <= 0 then return false end

    inv.products[productId] = inv.products[productId] - 1

    if productId == "ammo_pack" then
        -- 补充弹药（增加射击次数 - 减少冷却）
        inv.message = "使用弹药包：炮塔火力补充"
        inv.messageTimer = 2.5
        -- 添加buff：射速翻倍持续20秒
        table.insert(inv.buffs, { id = "ammo_boost", remaining = 20 })

    elseif productId == "medkit" then
        sub.hull = math.min(100, sub.hull + 20)
        inv.message = "使用医疗包：船体+20"
        inv.messageTimer = 2.5

    elseif productId == "repair_tool" then
        table.insert(inv.buffs, { id = "repair_boost", remaining = 30 })
        inv.message = "使用修复工具：修复速度×2 (30秒)"
        inv.messageTimer = 2.5

    elseif productId == "power_cell" then
        table.insert(inv.buffs, { id = "power_boost", remaining = 60 })
        inv.message = "使用电力芯：总电力+20 (60秒)"
        inv.messageTimer = 2.5

    elseif productId == "sonar_boost" then
        table.insert(inv.buffs, { id = "sonar_boost", remaining = 45 })
        inv.message = "使用声呐增幅：探测加强 (45秒)"
        inv.messageTimer = 2.5
    end

    return true
end

--- 检查是否有某个buff
---@param inv table
---@param buffId string
---@return boolean
function Inventory.HasBuff(inv, buffId)
    for _, b in ipairs(inv.buffs) do
        if b.id == buffId then return true end
    end
    return false
end

--- 获取buff剩余时间
---@param inv table
---@param buffId string
---@return number
function Inventory.GetBuffRemaining(inv, buffId)
    for _, b in ipairs(inv.buffs) do
        if b.id == buffId then return b.remaining end
    end
    return 0
end

--- 切换面板
function Inventory.TogglePanel(inv)
    inv.isOpen = not inv.isOpen
end

return Inventory
