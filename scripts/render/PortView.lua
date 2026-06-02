--- 港口场景 NanoVG 渲染
--- 包含港口背景、标签页UI、任务/商店/升级面板
local PortScene = require("PortScene")
local MissionSystem = require("MissionSystem")

local PortView = {}

-- 缓存的任务列表
local cachedMissions = nil

-- 滚动状态
local scrollOffset = 0        -- 当前滚动偏移（像素）
local scrollTarget = 0        -- 滚动目标（用于惯性动画）
local scrollMaxOffset = 0     -- 当前列表最大滚动量
local lastScrollTab = 0       -- 上次滚动的标签页（切换标签时重置）
local ITEM_HEIGHT_FIXED = 70  -- 列表项固定高度（不再自适应压缩）

--- 初始化/刷新任务列表
function PortView.RefreshMissions(reputation)
    cachedMissions = MissionSystem.GenerateMissions(reputation)
end

--- 获取当前缓存的任务列表
function PortView.GetMissions()
    return cachedMissions
end

--- 从缓存列表中移除指定索引的任务（确认选择后调用）
function PortView.RemoveMission(index)
    if cachedMissions and index >= 1 and index <= #cachedMissions then
        table.remove(cachedMissions, index)
        -- 重置滚动偏移防止越界
        local contentH = #cachedMissions * ITEM_HEIGHT_FIXED
        local panelH = 400  -- 近似值，实际由 Draw 时更新
        scrollMaxOffset = math.max(0, contentH - panelH)
        if scrollOffset > scrollMaxOffset then
            scrollOffset = scrollMaxOffset
        end
    end
end

-- ============================================================
-- 主绘制入口
-- ============================================================

--- 绘制港口场景
function PortView.Draw(vg, w, h, port, gameState, gameTime)
    -- 1. 港口背景
    PortView.DrawBackground(vg, w, h, gameTime)

    -- 2. 标题区域
    PortView.DrawHeader(vg, w, h, gameState, gameTime)

    -- 3. 标签栏
    PortView.DrawTabBar(vg, w, h, port)

    -- 4. 内容面板（根据当前标签页）
    if port.currentTab == PortScene.TAB_MISSION then
        PortView.DrawMissionPanel(vg, w, h, port, gameState, gameTime)
    elseif port.currentTab == PortScene.TAB_SHOP then
        PortView.DrawShopPanel(vg, w, h, port, gameState, gameTime)
    elseif port.currentTab == PortScene.TAB_UPGRADE then
        PortView.DrawUpgradePanel(vg, w, h, port, gameState, gameTime)
    elseif port.currentTab == PortScene.TAB_DEPART then
        PortView.DrawDepartPanel(vg, w, h, port, gameState, gameTime)
    end

    -- 5. 提示消息
    if port.message then
        PortView.DrawMessage(vg, w, h, port)
    end

    -- 6. 操作提示
    PortView.DrawControls(vg, w, h, port)
end

-- ============================================================
-- 背景
-- ============================================================
function PortView.DrawBackground(vg, w, h, gameTime)
    -- 港口水下基地氛围 - 深蓝渐变 + 灯光
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(15, 35, 65, 255), nvgRGBA(5, 12, 28, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    -- 水面波光效果（顶部）
    for i = 1, 8 do
        local x = (i * w / 9) + math.sin(gameTime * 0.5 + i * 0.8) * 20
        local y = 10 + math.sin(gameTime * 0.3 + i) * 5
        local alpha = math.floor(30 + math.sin(gameTime + i * 1.2) * 20)
        nvgBeginPath(vg)
        nvgEllipse(vg, x, y, 40 + math.sin(gameTime * 0.7 + i) * 10, 3)
        nvgFillColor(vg, nvgRGBA(80, 160, 220, alpha))
        nvgFill(vg)
    end

    -- 底部港口灯光（暖色散射）
    local dockGlow = nvgRadialGradient(vg, w * 0.5, h * 0.85,
        50, 300, nvgRGBA(200, 150, 60, 40), nvgRGBA(200, 150, 60, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, h * 0.5, w, h * 0.5)
    nvgFillPaint(vg, dockGlow)
    nvgFill(vg)

    -- 两侧结构线条（暗示港口码头）
    nvgStrokeColor(vg, nvgRGBA(60, 80, 110, 80))
    nvgStrokeWidth(vg, 2)
    for i = 0, 3 do
        local lx = 30 + i * 15
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx, h * 0.3)
        nvgLineTo(vg, lx, h)
        nvgStroke(vg)

        local rx = w - 30 - i * 15
        nvgBeginPath(vg)
        nvgMoveTo(vg, rx, h * 0.3)
        nvgLineTo(vg, rx, h)
        nvgStroke(vg)
    end
end

-- ============================================================
-- 顶部标题栏
-- ============================================================
function PortView.DrawHeader(vg, w, h, gameState, gameTime)
    -- 标题背景条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 20, 15, w - 40, 50, 6)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 130, 180, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 210, 240, 255))
    nvgText(vg, 40, 40, "⚓ 木卫二 · 深海港", nil)

    -- 金币
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 200, 60, 255))
    nvgText(vg, w - 40, 33, "金币: " .. gameState.gold, nil)

    -- 声望
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 140, 240, 200))
    nvgText(vg, w - 40, 50, "声望: " .. gameState.reputation .. " | 任务完成: " .. gameState.totalMissions, nil)
end

-- ============================================================
-- 标签栏
-- ============================================================
function PortView.DrawTabBar(vg, w, h, port)
    local tabW = (w - 80) / 4
    local tabY = 75
    local tabH = 32

    for i = 1, 4 do
        local tx = 30 + (i - 1) * (tabW + 8)
        local isActive = (port.currentTab == i)

        -- 标签背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW, tabH, 4)
        if isActive then
            nvgFillColor(vg, nvgRGBA(40, 90, 140, 230))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 180, 240, 255))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        else
            nvgFillColor(vg, nvgRGBA(20, 40, 60, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(50, 80, 120, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 标签文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(220, 240, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(140, 160, 180, 200))
        end
        nvgText(vg, tx + tabW * 0.5, tabY + tabH * 0.5, PortScene.TAB_NAMES[i], nil)
    end
end

-- ============================================================
-- 任务板面板
-- ============================================================
function PortView.DrawMissionPanel(vg, w, h, port, gameState, gameTime)
    local panelY = 120
    local panelH = h - panelY - 60

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 30, panelY, w - 60, panelH, 8)
    nvgFillColor(vg, nvgRGBA(10, 18, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 150, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 当前已接任务提示
    if gameState.currentMission then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(240, 180, 60, 200))
        nvgText(vg, 50, panelY + 10, "当前任务: " .. gameState.currentMission.title .. " (已接取)", nil)
    end

    -- 任务列表
    if not cachedMissions then
        PortView.RefreshMissions(gameState.reputation)
    end

    local headerH = gameState.currentMission and 30 or 12
    local startY = panelY + headerH
    local itemH = ITEM_HEIGHT_FIXED
    local contentH = #cachedMissions * itemH
    local visibleH = panelH - headerH - 10

    -- 计算最大滚动
    scrollMaxOffset = math.max(0, contentH - visibleH)

    -- 切换标签时重置滚动
    if lastScrollTab ~= PortScene.TAB_MISSION then
        lastScrollTab = PortScene.TAB_MISSION
        scrollOffset = 0
    end

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, 30, startY, w - 60, visibleH)

    for i, mission in ipairs(cachedMissions) do
        local iy = startY + (i - 1) * itemH - scrollOffset
        -- 跳过不可见的项
        if iy + itemH >= startY and iy < startY + visibleH then
            local isSelected = (port.selectedItem == i)

            -- 选中高亮
            if isSelected then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, 40, iy, w - 80, itemH - 4, 4)
                nvgFillColor(vg, nvgRGBA(40, 80, 130, 150))
                nvgFill(vg)
            end

            -- 等级标识
            local tr, tg, tb = MissionSystem.GetTierColor(mission.tier)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(tr, tg, tb, 220))
            nvgText(vg, 50, iy + 6, MissionSystem.GetTierName(mission.tier), nil)

            -- 标题
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(220, 230, 240, 255))
            nvgText(vg, 120, iy + 4, mission.title, nil)

            -- 描述
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(150, 170, 190, 200))
            nvgText(vg, 50, iy + 24, mission.desc, nil)

            -- 奖励
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(240, 200, 60, 220))
            nvgText(vg, w - 50, iy + 6, "+" .. mission.reward.gold .. " 金", nil)
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(180, 140, 240, 180))
            nvgText(vg, w - 50, iy + 22, "+" .. mission.reward.reputation .. " 声望", nil)

            -- 选中指示箭头
            if isSelected then
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBA(80, 200, 255, 255))
                nvgText(vg, 38, iy + 10, ">", nil)
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条
    PortView.DrawScrollbar(vg, 30, startY, w - 60, visibleH, contentH)
end

-- ============================================================
-- 商店面板
-- ============================================================
function PortView.DrawShopPanel(vg, w, h, port, gameState, gameTime)
    local panelY = 120
    local panelH = h - panelY - 60

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 30, panelY, w - 60, panelH, 8)
    nvgFillColor(vg, nvgRGBA(10, 18, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 150, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 库存标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(160, 180, 200, 180))
    nvgText(vg, w - 50, panelY + 10, "当前金币: " .. gameState.gold, nil)

    -- 商品列表（带滚动）
    local headerH = 30
    local startY = panelY + headerH
    local itemH = ITEM_HEIGHT_FIXED
    local contentH = #PortScene.SHOP_ITEMS * itemH
    local visibleH = panelH - headerH - 10

    -- 计算最大滚动
    scrollMaxOffset = math.max(0, contentH - visibleH)

    -- 切换标签时重置滚动
    if lastScrollTab ~= PortScene.TAB_SHOP then
        lastScrollTab = PortScene.TAB_SHOP
        scrollOffset = 0
    end

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, 30, startY, w - 60, visibleH)

    for i, item in ipairs(PortScene.SHOP_ITEMS) do
        local iy = startY + (i - 1) * itemH - scrollOffset
        if iy + itemH >= startY and iy < startY + visibleH then
            local isSelected = (port.selectedItem == i)
            local owned = gameState.supplies[item.id] or 0

            -- 选中高亮
            if isSelected then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, 40, iy, w - 80, itemH - 4, 4)
                nvgFillColor(vg, nvgRGBA(40, 80, 130, 150))
                nvgFill(vg)
            end

            -- 物品名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 230, 240, 255))
            nvgText(vg, 55, iy + 5, item.name, nil)

            -- 描述
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(150, 170, 190, 180))
            nvgText(vg, 55, iy + 24, item.desc, nil)

            -- 价格
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFontSize(vg, 13)
            local canAfford = gameState.gold >= item.price
            if canAfford then
                nvgFillColor(vg, nvgRGBA(240, 200, 60, 255))
            else
                nvgFillColor(vg, nvgRGBA(180, 80, 80, 200))
            end
            nvgText(vg, w - 100, iy + 6, item.price .. " 金", nil)

            -- 已拥有数量
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(120, 180, 120, 200))
            nvgText(vg, w - 50, iy + 6, "×" .. owned, nil)

            -- 选中指示
            if isSelected then
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBA(80, 200, 255, 255))
                nvgText(vg, 40, iy + 8, ">", nil)
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条
    PortView.DrawScrollbar(vg, 30, startY, w - 60, visibleH, contentH)
end

-- ============================================================
-- 升级面板
-- ============================================================
function PortView.DrawUpgradePanel(vg, w, h, port, gameState, gameTime)
    local panelY = 120
    local panelH = h - panelY - 60

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 30, panelY, w - 60, panelH, 8)
    nvgFillColor(vg, nvgRGBA(10, 18, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 150, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 升级列表（带滚动）
    local headerH = 15
    local startY = panelY + headerH
    local itemH = ITEM_HEIGHT_FIXED
    local contentH = #PortScene.UPGRADES * itemH
    local visibleH = panelH - headerH - 10

    -- 计算最大滚动
    scrollMaxOffset = math.max(0, contentH - visibleH)

    -- 切换标签时重置滚动
    if lastScrollTab ~= PortScene.TAB_UPGRADE then
        lastScrollTab = PortScene.TAB_UPGRADE
        scrollOffset = 0
    end

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, 30, startY, w - 60, visibleH)

    for i, upg in ipairs(PortScene.UPGRADES) do
        local iy = startY + (i - 1) * itemH - scrollOffset
        -- 跳过不可见的项
        if iy + itemH >= startY and iy < startY + visibleH then
            local isSelected = (port.selectedItem == i)
            local currentLv = gameState.upgrades[upg.id] or 1
            local isMaxed = (currentLv >= 5)
            local cost = PortScene.GetUpgradeCost(upg, currentLv)

            -- 选中高亮
            if isSelected then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, 40, iy, w - 80, itemH - 4, 4)
                nvgFillColor(vg, nvgRGBA(40, 80, 130, 150))
                nvgFill(vg)
            end

            -- 名称
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(220, 230, 240, 255))
            nvgText(vg, 55, iy + 4, upg.name, nil)

            -- 等级条
            local barX = 55
            local barY = iy + 24
            local barW = 100
            local barH = 8
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, barW, barH, 3)
            nvgFillColor(vg, nvgRGBA(30, 40, 60, 200))
            nvgFill(vg)

            -- 填充等级
            local fillW = barW * (currentLv / 5)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, barX, barY, fillW, barH, 3)
            if isMaxed then
                nvgFillColor(vg, nvgRGBA(240, 200, 60, 255))
            else
                nvgFillColor(vg, nvgRGBA(60, 160, 220, 255))
            end
            nvgFill(vg)

            -- 等级文字
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(180, 200, 220, 200))
            nvgText(vg, barX + barW + 10, iy + 22, "Lv." .. currentLv .. "/5", nil)

            -- 描述
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(140, 160, 180, 160))
            nvgText(vg, 55, iy + 38, upg.desc, nil)

            -- 费用/已满
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFontSize(vg, 12)
            if isMaxed then
                nvgFillColor(vg, nvgRGBA(180, 180, 60, 200))
                nvgText(vg, w - 50, iy + 10, "MAX", nil)
            else
                local canAfford = gameState.gold >= cost
                if canAfford then
                    nvgFillColor(vg, nvgRGBA(240, 200, 60, 255))
                else
                    nvgFillColor(vg, nvgRGBA(180, 80, 80, 200))
                end
                nvgText(vg, w - 50, iy + 10, cost .. " 金", nil)
            end

            -- 选中指示
            if isSelected then
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFontSize(vg, 14)
                nvgFillColor(vg, nvgRGBA(80, 200, 255, 255))
                nvgText(vg, 40, iy + 8, ">", nil)
            end
        end
    end

    nvgRestore(vg)

    -- 滚动条
    PortView.DrawScrollbar(vg, 30, startY, w - 60, visibleH, contentH)
end

-- ============================================================
-- 出港面板
-- ============================================================
function PortView.DrawDepartPanel(vg, w, h, port, gameState, gameTime)
    local panelY = 120
    local panelH = h - panelY - 60
    local cx = w * 0.5
    local cy = panelY + panelH * 0.5

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 30, panelY, w - 60, panelH, 8)
    nvgFillColor(vg, nvgRGBA(10, 18, 35, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 100, 150, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 潜艇升级概览
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 210, 240, 220))
    nvgText(vg, cx, panelY + 20, "-- 出航准备 --", nil)

    -- 当前任务
    nvgFontSize(vg, 13)
    if gameState.currentMission then
        nvgFillColor(vg, nvgRGBA(120, 220, 160, 255))
        nvgText(vg, cx, panelY + 50, "任务: " .. gameState.currentMission.title, nil)

        -- 目标列表
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(160, 180, 200, 200))
        for j, obj in ipairs(gameState.currentMission.objectives) do
            nvgText(vg, cx, panelY + 50 + j * 18, "· " .. MissionSystem.GetObjectiveText(obj), nil)
        end
    else
        nvgFillColor(vg, nvgRGBA(220, 120, 80, 220))
        nvgText(vg, cx, panelY + 50, "尚未接受任务！请先到任务板接取", nil)
    end

    -- 补给概览
    local supY = cy + 10
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(160, 180, 200, 200))
    nvgText(vg, cx, supY, "-- 携带补给 --", nil)

    local supNames = { "弹药", "医疗", "修复", "电芯", "声呐" }
    local supKeys = { "ammo_pack", "medkit", "repair_tool", "power_cell", "sonar_boost" }
    local supStr = ""
    for i, key in ipairs(supKeys) do
        local count = gameState.supplies[key] or 0
        supStr = supStr .. supNames[i] .. "×" .. count .. "  "
    end
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(140, 200, 180, 200))
    nvgText(vg, cx, supY + 20, supStr, nil)

    -- 出港按钮（动画脉冲）
    local btnY = cy + 70
    local btnW = 160
    local btnH = 40
    local pulse = 0.8 + math.sin(gameTime * 2) * 0.2
    local hasMission = (gameState.currentMission ~= nil)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - btnW / 2, btnY, btnW, btnH, 8)
    if hasMission then
        nvgFillColor(vg, nvgRGBA(30, math.floor(120 * pulse), math.floor(180 * pulse), 230))
    else
        nvgFillColor(vg, nvgRGBA(60, 60, 70, 180))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 180, 240, hasMission and 200 or 60))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if hasMission then
        nvgFillColor(vg, nvgRGBA(220, 240, 255, 255))
        nvgText(vg, cx, btnY + btnH / 2, "[ Enter ] 出港!", nil)
    else
        nvgFillColor(vg, nvgRGBA(120, 120, 130, 180))
        nvgText(vg, cx, btnY + btnH / 2, "需要先接取任务", nil)
    end
end

-- ============================================================
-- 提示消息
-- ============================================================
function PortView.DrawMessage(vg, w, h, port)
    if not port.message then return end

    local alpha = math.min(255, math.floor(port.messageTimer / 0.3 * 255))
    local cx = w * 0.5
    local cy = h * 0.5

    -- 消息背景
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    local tw = 300

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - tw / 2 - 15, cy - 20, tw + 30, 40, 6)
    nvgFillColor(vg, nvgRGBA(20, 60, 100, math.floor(alpha * 0.85)))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 180, 240, alpha))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 文字
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 240, 255, alpha))
    nvgText(vg, cx, cy, port.message, nil)
end

-- ============================================================
-- 操作提示
-- ============================================================
function PortView.DrawControls(vg, w, h, port)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 150, 180, 160))

    local hint = "点击标签切换 · 点击列表项选中 · 再次点击确认"
    if port.currentTab == PortScene.TAB_DEPART then
        hint = "点击标签切换 · 点击出港按钮开始"
    end
    nvgText(vg, w * 0.5, h - 15, hint, nil)
end

-- ============================================================
-- 场景切换遮罩
-- ============================================================
function PortView.DrawTransition(vg, w, h, alpha)
    if alpha <= 0 then return end
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 255)))
    nvgFill(vg)
end

-- ============================================================
-- 滚动控制接口
-- ============================================================

--- 滚动指定偏移（由触摸滑动调用）
function PortView.Scroll(dy)
    scrollOffset = scrollOffset - dy
    -- 限制范围
    if scrollOffset < 0 then scrollOffset = 0 end
    if scrollOffset > scrollMaxOffset then scrollOffset = scrollMaxOffset end
end

--- 设置滚动偏移（绝对值）
function PortView.SetScrollOffset(offset)
    scrollOffset = math.max(0, math.min(offset, scrollMaxOffset))
end

--- 获取当前滚动偏移
function PortView.GetScrollOffset()
    return scrollOffset
end

--- 获取最大滚动量
function PortView.GetMaxScroll()
    return scrollMaxOffset
end

--- 重置滚动（切换标签时调用）
function PortView.ResetScroll()
    scrollOffset = 0
    scrollMaxOffset = 0
end

--- 绘制滚动条（面板右侧）
function PortView.DrawScrollbar(vg, panelX, panelY, panelW, panelH, contentH)
    if contentH <= panelH then return end  -- 内容未溢出，不显示

    local trackX = panelX + panelW - 8
    local trackY = panelY + 4
    local trackH = panelH - 8

    -- 滚动条轨道
    nvgBeginPath(vg)
    nvgRoundedRect(vg, trackX, trackY, 4, trackH, 2)
    nvgFillColor(vg, nvgRGBA(40, 60, 90, 100))
    nvgFill(vg)

    -- 滚动条滑块
    local ratio = panelH / contentH
    local thumbH = math.max(20, trackH * ratio)
    local scrollRatio = scrollOffset / math.max(1, scrollMaxOffset)
    local thumbY = trackY + scrollRatio * (trackH - thumbH)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, trackX, thumbY, 4, thumbH, 2)
    nvgFillColor(vg, nvgRGBA(100, 180, 240, 180))
    nvgFill(vg)
end

return PortView
