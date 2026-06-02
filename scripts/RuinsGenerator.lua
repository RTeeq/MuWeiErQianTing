--- 深海遗迹生成器
--- 生成EVA舱外探索时的遗迹POI（兴趣点）
--- 包括沉船残骸、古代遗迹、矿脉、生物巢穴等
local RuinsGenerator = {}

-- ============================================================
-- 配置
-- ============================================================
RuinsGenerator.Config = {
    -- 生成区域（与EVASystem.Config同步）
    worldWidth = 2400,
    worldHeight = 800,

    -- 遗迹安全区（潜艇附近不生成）
    safeZoneX = 350,       -- 气闸右侧350px不生成遗迹

    -- 遗迹数量
    minRuins = 3,
    maxRuins = 6,

    -- 战利品数量
    minLootsPerRuin = 2,
    maxLootsPerRuin = 5,
}

-- ============================================================
-- 遗迹模板
-- ============================================================
local RUIN_TYPES = {
    {
        id = "shipwreck",
        name = "沉船残骸",
        desc = "一艘破碎的探索船，可能还有物资",
        width = 180,
        height = 120,
        color = {80, 90, 100, 255},
        lootTable = {"metal_scrap", "power_cell", "ammo_pack", "data_core"},
    },
    {
        id = "ancient_ruin",
        name = "远古遗迹",
        desc = "未知文明的建筑残片",
        width = 220,
        height = 150,
        color = {60, 100, 80, 255},
        lootTable = {"alien_crystal", "data_core", "rare_mineral", "alien_artifact"},
    },
    {
        id = "mineral_vein",
        name = "矿脉",
        desc = "裸露的深海矿脉，富含稀有矿物",
        width = 140,
        height = 90,
        color = {100, 80, 50, 255},
        lootTable = {"metal_scrap", "rare_mineral", "metal_scrap", "rare_mineral"},
    },
    {
        id = "bio_nest",
        name = "生物巢穴",
        desc = "某种深海生物的栖息地，危险但有珍贵标本",
        width = 160,
        height = 110,
        color = {50, 80, 60, 255},
        lootTable = {"bio_sample", "bio_sample", "rare_mineral", "alien_crystal"},
    },
    {
        id = "cargo_pod",
        name = "货物舱",
        desc = "散落的运输船货舱，物资丰富",
        width = 120,
        height = 80,
        color = {90, 85, 70, 255},
        lootTable = {"metal_scrap", "power_cell", "ammo_pack", "repair_tool"},
    },
}

-- ============================================================
-- 战利品定义
-- ============================================================
local LOOT_DEFS = {
    metal_scrap = {
        name = "金属碎片",
        value = 15,
        icon = "scrap",
        desc = "可用于制造和维修",
    },
    power_cell = {
        name = "能量电池",
        value = 40,
        icon = "power",
        desc = "高纯度能量单元",
    },
    ammo_pack = {
        name = "弹药箱",
        value = 30,
        icon = "ammo",
        desc = "鱼雷弹药补充",
    },
    data_core = {
        name = "数据核心",
        value = 60,
        icon = "data",
        desc = "包含珍贵航海数据",
    },
    alien_crystal = {
        name = "异星结晶",
        value = 80,
        icon = "crystal",
        desc = "散发微光的未知矿物",
    },
    rare_mineral = {
        name = "稀有矿石",
        value = 50,
        icon = "mineral",
        desc = "深海压力下形成的珍贵矿物",
    },
    bio_sample = {
        name = "生物样本",
        value = 45,
        icon = "bio",
        desc = "深海生物组织标本",
    },
    alien_artifact = {
        name = "远古遗物",
        value = 120,
        icon = "artifact",
        desc = "未知文明的神秘造物",
    },
    repair_tool = {
        name = "修复工具",
        value = 35,
        icon = "repair",
        desc = "高性能维修套件",
    },
}

-- ============================================================
-- 生成函数
-- ============================================================

--- 生成一组遗迹和战利品
---@return table world 包含 ruins 和 loots 的世界数据
function RuinsGenerator.Generate()
    local cfg = RuinsGenerator.Config
    local world = {
        ruins = {},     -- 遗迹列表
        loots = {},     -- 战利品列表（独立坐标，方便拾取判定）
        seabed = {},    -- 海底地形装饰点
    }

    -- 确定遗迹数量
    local ruinCount = math.random(cfg.minRuins, cfg.maxRuins)

    -- 可用区域（排除安全区）
    local availWidth = cfg.worldWidth - cfg.safeZoneX - 100  -- 右侧也留边
    local segmentW = availWidth / ruinCount

    for i = 1, ruinCount do
        -- 随机选择遗迹类型
        local typeIdx = math.random(1, #RUIN_TYPES)
        local ruinType = RUIN_TYPES[typeIdx]

        -- 在段内随机放置（避免重叠）
        local baseX = cfg.safeZoneX + (i - 1) * segmentW
        local rx = baseX + math.random(20, math.floor(segmentW - ruinType.width - 20))
        local ry = cfg.worldHeight - ruinType.height - math.random(20, 80)

        local ruin = {
            id = ruinType.id .. "_" .. i,
            type = ruinType.id,
            name = ruinType.name,
            desc = ruinType.desc,
            x = rx,
            y = ry,
            width = ruinType.width,
            height = ruinType.height,
            color = ruinType.color,
            explored = false,   -- 是否已探索过
            lootIds = {},       -- 关联的战利品ID
        }

        -- 生成该遗迹的战利品
        local lootCount = math.random(cfg.minLootsPerRuin, cfg.maxLootsPerRuin)
        for j = 1, lootCount do
            local lootType = ruinType.lootTable[math.random(1, #ruinType.lootTable)]
            local def = LOOT_DEFS[lootType]
            if def then
                local loot = {
                    id = ruin.id .. "_loot_" .. j,
                    type = lootType,
                    name = def.name,
                    value = def.value,
                    icon = def.icon,
                    desc = def.desc,
                    -- 在遗迹范围内随机位置
                    x = rx + math.random(10, ruinType.width - 10),
                    y = ry + math.random(10, ruinType.height - 10),
                    collected = false,
                    glowPhase = math.random() * 6.28,  -- 随机发光相位
                    ruinId = ruin.id,
                }
                table.insert(world.loots, loot)
                table.insert(ruin.lootIds, loot.id)
            end
        end

        table.insert(world.ruins, ruin)
    end

    -- 生成海底地形装饰
    RuinsGenerator.GenerateSeabed(world)

    return world
end

--- 生成海底地形装饰点
function RuinsGenerator.GenerateSeabed(world)
    local cfg = RuinsGenerator.Config
    local groundY = cfg.worldHeight - 20

    -- 岩石/珊瑚装饰
    for i = 1, 30 do
        local x = math.random(0, cfg.worldWidth)
        local y = groundY + math.random(-15, 5)
        table.insert(world.seabed, {
            x = x,
            y = y,
            type = math.random(1, 4),  -- 1=小石, 2=大石, 3=海草, 4=珊瑚
            size = 5 + math.random() * 15,
            phase = math.random() * 6.28,
        })
    end
end

--- 获取某个坐标附近的遗迹
function RuinsGenerator.GetNearbyRuin(world, px, py, radius)
    radius = radius or 100
    for _, ruin in ipairs(world.ruins) do
        local cx = ruin.x + ruin.width * 0.5
        local cy = ruin.y + ruin.height * 0.5
        local dx = px - cx
        local dy = py - cy
        if math.abs(dx) < ruin.width * 0.5 + radius and math.abs(dy) < ruin.height * 0.5 + radius then
            return ruin
        end
    end
    return nil
end

--- 获取未收集的战利品数量
function RuinsGenerator.GetRemainingLootCount(world)
    local count = 0
    for _, loot in ipairs(world.loots) do
        if not loot.collected then
            count = count + 1
        end
    end
    return count
end

--- 获取已收集战利品的总价值
function RuinsGenerator.GetCollectedValue(world)
    local total = 0
    for _, loot in ipairs(world.loots) do
        if loot.collected then
            total = total + loot.value
        end
    end
    return total
end

return RuinsGenerator
