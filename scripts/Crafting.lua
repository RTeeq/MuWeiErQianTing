--- 制造系统
--- 配方定义、材料消耗、合成逻辑

local Inventory = require("Inventory")

local Crafting = {}

-- ============================================================
-- 配方定义
-- ============================================================

Crafting.RECIPES = {
    {
        id = "ammo_pack",
        name = "弹药包",
        icon = "▶",
        color = {255, 80, 80},
        cost = { scrap_metal = 3, chemicals = 2 },
        product = "ammo_pack",
        amount = 1,
    },
    {
        id = "medkit",
        name = "医疗包",
        icon = "+",
        color = {80, 255, 130},
        cost = { chemicals = 3, polymer = 2 },
        product = "medkit",
        amount = 1,
    },
    {
        id = "repair_tool",
        name = "修复工具",
        icon = "⚒",
        color = {220, 200, 80},
        cost = { scrap_metal = 4, wires = 2 },
        product = "repair_tool",
        amount = 1,
    },
    {
        id = "power_cell",
        name = "电力芯",
        icon = "⚡",
        color = {100, 200, 255},
        cost = { circuits = 3, wires = 2, polymer = 1 },
        product = "power_cell",
        amount = 1,
    },
    {
        id = "sonar_boost",
        name = "声呐增幅器",
        icon = "◎",
        color = {80, 255, 200},
        cost = { circuits = 2, wires = 3 },
        product = "sonar_boost",
        amount = 1,
    },
}

-- ============================================================
-- 逻辑
-- ============================================================

--- 检查是否能制造某个配方
---@param inv table 物品栏
---@param recipeIdx number 配方索引 (1-based)
---@return boolean canCraft
---@return table|nil 缺少的材料 {matId = needMore}
function Crafting.CanCraft(inv, recipeIdx)
    local recipe = Crafting.RECIPES[recipeIdx]
    if not recipe then return false, nil end

    -- 检查产品是否已满
    local productDef = Inventory.PRODUCTS[recipe.product]
    if productDef and productDef.maxStack then
        if inv.products[recipe.product] >= productDef.maxStack then
            return false, nil
        end
    end

    -- 检查材料
    local missing = {}
    local canDo = true
    for matId, needed in pairs(recipe.cost) do
        local have = inv.materials[matId] or 0
        if have < needed then
            missing[matId] = needed - have
            canDo = false
        end
    end

    return canDo, (not canDo) and missing or nil
end

--- 执行制造
---@param inv table
---@param recipeIdx number
---@return boolean success
function Crafting.Craft(inv, recipeIdx)
    local canCraft = Crafting.CanCraft(inv, recipeIdx)
    if not canCraft then return false end

    local recipe = Crafting.RECIPES[recipeIdx]

    -- 扣除材料
    for matId, needed in pairs(recipe.cost) do
        inv.materials[matId] = inv.materials[matId] - needed
    end

    -- 添加产品
    inv.products[recipe.product] = inv.products[recipe.product] + recipe.amount

    -- 设置消息
    inv.message = "合成 " .. recipe.name .. " ×" .. recipe.amount
    inv.messageTimer = 2.5

    return true
end

--- 获取配方数量
---@return number
function Crafting.GetRecipeCount()
    return #Crafting.RECIPES
end

return Crafting
