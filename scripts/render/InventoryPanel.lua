--- 物品栏与制造UI渲染
--- 底部快捷栏 + I键展开完整面板（材料/制成品/合成配方）
--- 地面废料绘制 + 拾取提示

local Inventory = require("Inventory")
local Crafting = require("Crafting")

local InventoryPanel = {}

-- ============================================================
-- 地面废料渲染（世界坐标，在潜艇内部绘制）
-- ============================================================

--- 绘制舱室内的废料
---@param vg userdata
---@param inv table
---@param innerX number 潜艇内部起始X
---@param innerY number 潜艇内部起始Y
---@param innerH number 潜艇内部高度
---@param gameTime number
function InventoryPanel.DrawScraps(vg, inv, innerX, innerY, innerH, gameTime)
    local floorY = innerY + innerH - 12  -- 地面位置

    for _, scrap in ipairs(inv.scraps) do
        local sx = innerX + scrap.x
        local bob = math.sin(scrap.bobTime * 2.0) * 3  -- 上下浮动
        local sy = floorY - 10 + bob

        local td = scrap.typeData
        local c = td.color
        local alpha = 220

        -- 发光底光
        local glowGrad = nvgRadialGradient(vg, sx, sy + 4, 0, 14,
            nvgRGBA(c[1], c[2], c[3], 40), nvgRGBA(c[1], c[2], c[3], 0))
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy + 4, 14)
        nvgFillPaint(vg, glowGrad)
        nvgFill(vg)

        -- 废料主体（小方块/圆形）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx - 7, sy - 7, 14, 14, 3)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(c[1] + 40, c[2] + 40, c[3] + 40, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 图标
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, sx, sy, td.icon)
    end
end

--- 绘制拾取提示（屏幕空间，角色上方）
---@param vg userdata
---@param inv table
---@param w number
---@param h number
---@param gameTime number
function InventoryPanel.DrawPickupHint(vg, inv, w, h, gameTime)
    if not inv.nearScrap then return end

    local td = inv.nearScrap.typeData
    local pulse = 0.7 + math.sin(gameTime * 4) * 0.3

    -- 底部居中提示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(255, 240, 150, math.floor(220 * pulse)))
    nvgText(vg, w * 0.5, h - 105, "[F] 拾取 " .. td.name)
end

-- ============================================================
-- 底部快捷栏（始终可见）
-- ============================================================

--- 绘制底部材料快捷指示
---@param vg userdata
---@param inv table
---@param w number
---@param h number
---@param gameTime number
function InventoryPanel.DrawQuickBar(vg, inv, w, h, gameTime)
    local barW = 260
    local barH = 28
    local bx = w * 0.5 - barW * 0.5
    local by = h - 36

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(10, 15, 25, 180))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 100, 140, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 材料图标和数量
    local matKeys = {"scrap_metal", "wires", "chemicals", "circuits", "polymer"}
    local cellW = barW / #matKeys
    for i, matId in ipairs(matKeys) do
        local matDef = Inventory.MATERIALS[matId]
        local count = inv.materials[matId]
        local cx = bx + (i - 0.5) * cellW
        local cy = by + barH * 0.5
        local c = matDef.color

        -- 图标
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 200))
        nvgText(vg, cx - 8, cy, matDef.icon)

        -- 数量
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local cAlpha = count > 0 and 220 or 80
        nvgFillColor(vg, nvgRGBA(200, 220, 240, cAlpha))
        nvgText(vg, cx, cy, tostring(count))
    end

    -- "I" 键提示
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 170, 200, 150))
    nvgText(vg, bx + barW - 4, by + barH * 0.5, "[I]")
end

-- ============================================================
-- 完整面板（按I展开）
-- ============================================================

--- 绘制完整物品栏+制造面板
---@param vg userdata
---@param inv table
---@param w number
---@param h number
---@param gameTime number
---@param selectedRecipe number 当前选中配方索引
function InventoryPanel.DrawFull(vg, inv, w, h, gameTime, selectedRecipe)
    if not inv.isOpen then return end

    local panelW = 320
    local panelH = 300
    local px = w * 0.5 - panelW * 0.5
    local py = h * 0.5 - panelH * 0.5

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(8, 12, 22, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 160, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 240))
    nvgText(vg, px + panelW * 0.5, py + 10, "物品栏 & 制造台")

    -- ==================== 左侧：材料 ====================
    local matX = px + 12
    local matY = py + 35

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 180, 210, 200))
    nvgText(vg, matX, matY, "■ 材料")
    matY = matY + 18

    local matKeys = {"scrap_metal", "wires", "chemicals", "circuits", "polymer"}
    for _, matId in ipairs(matKeys) do
        local matDef = Inventory.MATERIALS[matId]
        local count = inv.materials[matId]
        local c = matDef.color

        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 200))
        nvgText(vg, matX, matY, matDef.icon .. " " .. matDef.name)

        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        local cAlpha = count > 0 and 220 or 80
        nvgFillColor(vg, nvgRGBA(200, 220, 240, cAlpha))
        nvgText(vg, matX + 110, matY, "×" .. count)

        matY = matY + 16
    end

    -- ==================== 左侧下方：制成品 ====================
    matY = matY + 10
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 180, 210, 200))
    nvgText(vg, matX, matY, "■ 制成品 (数字键使用)")
    matY = matY + 18

    local prodKeys = {"ammo_pack", "medkit", "repair_tool", "power_cell", "sonar_boost"}
    for idx, prodId in ipairs(prodKeys) do
        local prodDef = Inventory.PRODUCTS[prodId]
        local count = inv.products[prodId]
        local c = prodDef.color

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local pAlpha = count > 0 and 200 or 80
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], pAlpha))
        nvgText(vg, matX, matY, idx .. "." .. prodDef.icon .. " " .. prodDef.name)

        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 220, 240, pAlpha))
        nvgText(vg, matX + 110, matY, "×" .. count)

        matY = matY + 14
    end

    -- ==================== 右侧：配方列表 ====================
    local recX = px + 140
    local recY = py + 35

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 180, 210, 200))
    nvgText(vg, recX, recY, "■ 合成配方 (↑↓选择 Enter合成)")
    recY = recY + 18

    for i, recipe in ipairs(Crafting.RECIPES) do
        local selected = (i == selectedRecipe)
        local canCraft = Crafting.CanCraft(inv, i)
        local c = recipe.color
        local rowH = 42
        local ry = recY + (i - 1) * rowH

        -- 选中背景
        if selected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, recX - 2, ry - 2, panelW - 142, rowH - 4, 4)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 25))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], canCraft and 150 or 60))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 配方名
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local nameAlpha = canCraft and 240 or 100
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], nameAlpha))
        nvgText(vg, recX + 2, ry + 2, recipe.icon .. " " .. recipe.name)

        -- 材料消耗
        local costStr = ""
        for matId, needed in pairs(recipe.cost) do
            local matDef = Inventory.MATERIALS[matId]
            local have = inv.materials[matId]
            local ok = have >= needed
            if #costStr > 0 then costStr = costStr .. " " end
            costStr = costStr .. matDef.icon .. needed
            if not ok then costStr = costStr .. "!" end
        end
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(160, 180, 200, canCraft and 180 or 80))
        nvgText(vg, recX + 2, ry + 16, costStr)

        -- 可合成标记
        if canCraft and selected then
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            local flash = math.floor(180 + math.sin(gameTime * 4) * 60)
            nvgFillColor(vg, nvgRGBA(100, 255, 150, flash))
            nvgText(vg, px + panelW - 14, ry + 2, "可合成")
        end
    end

    -- 操作提示
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 150, 180, 160))
    nvgText(vg, px + panelW * 0.5, py + panelH - 6,
        "↑↓选配方  Enter合成  1~5使用制成品  I关闭")
end

-- ============================================================
-- 消息提示（屏幕中央偏上）
-- ============================================================

--- 绘制浮动消息
---@param vg userdata
---@param inv table
---@param w number
---@param h number
function InventoryPanel.DrawMessage(vg, inv, w, h)
    if not inv.message or inv.messageTimer <= 0 then return end

    local alpha = math.min(1, inv.messageTimer / 0.5) * 230

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 240, 150, math.floor(alpha)))
    nvgText(vg, w * 0.5, h * 0.3, inv.message)
end

-- ============================================================
-- Buff指示器
-- ============================================================

--- 绘制活跃buff图标
---@param vg userdata
---@param inv table
---@param w number
---@param h number
---@param gameTime number
function InventoryPanel.DrawBuffs(vg, inv, w, h, gameTime)
    if #inv.buffs == 0 then return end

    local startX = 15
    local startY = 85
    local gap = 22

    for i, buff in ipairs(inv.buffs) do
        local bx = startX
        local by = startY + (i - 1) * gap
        local c, icon, label

        if buff.id == "ammo_boost" then
            c = {255, 80, 80}; icon = "▶"; label = "弹药"
        elseif buff.id == "repair_boost" then
            c = {220, 200, 80}; icon = "⚒"; label = "修复×2"
        elseif buff.id == "power_boost" then
            c = {100, 200, 255}; icon = "⚡"; label = "电力+20"
        elseif buff.id == "sonar_boost" then
            c = {80, 255, 200}; icon = "◎"; label = "声呐+"
        else
            c = {200, 200, 200}; icon = "?"; label = buff.id
        end

        local remSec = math.floor(buff.remaining)
        local pulse = 1.0
        if buff.remaining < 5 then
            pulse = 0.5 + math.sin(gameTime * 6) * 0.5
        end
        local alpha = math.floor(200 * pulse)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgText(vg, bx, by, icon .. " " .. label .. " " .. remSec .. "s")
    end
end

return InventoryPanel
