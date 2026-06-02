--- 电力分配面板渲染（kW制，优先级排列）
--- 工程师专属面板，显示发电/用电/优先级/系统状态
local PowerPanel = {}

-- ============================================================
-- 主绘制入口
-- ============================================================

--- 绘制完整电力分配面板
---@param vg userdata
---@param w number 屏幕宽
---@param h number 屏幕高
---@param power table snapshot_.power {isOpen, selectedIdx, totalGeneration, totalConsumption, overloaded, systems=[...]}
---@param reactor table|nil snapshot_.reactor (用于显示反应堆输出联动)
---@param gameTime number
function PowerPanel.Draw(vg, w, h, power, reactor, gameTime)
    if not power or not power.isOpen then return end

    local systems = power.systems
    if not systems or #systems == 0 then return end

    local panelW = 300
    local systemCount = #systems
    local rowH = 32
    local headerH = 72
    local footerH = 28
    local panelH = headerH + systemCount * rowH + footerH
    local px = w - panelW - 16
    local py = math.floor((h - panelH) * 0.5)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 8)
    nvgFillColor(vg, nvgRGBA(6, 10, 18, 235))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(40, 80, 140, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- ================================================================
    -- 头部：发电量 vs 用电量 条形图
    -- ================================================================
    local hx = px + 12
    local hy = py + 10

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 240))
    nvgText(vg, hx, hy, "⚡ 电力分配")

    -- 发电/用电数值
    local genKW = power.totalGeneration or 0
    local conKW = power.totalConsumption or 0
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 255, 160, 220))
    nvgText(vg, px + panelW - 12, hy, string.format("发电 %dkW", genKW))

    -- 发电/用电对比条
    local barX = hx
    local barY = hy + 20
    local barW = panelW - 24
    local barH = 14

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 4)
    nvgFillColor(vg, nvgRGBA(20, 25, 35, 200))
    nvgFill(vg)

    -- 发电量条（绿色底）
    local maxKW = math.max(genKW, conKW, 1)
    local genFillW = barW * (genKW / maxKW)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, genFillW, barH, 4)
    nvgFillColor(vg, nvgRGBA(40, 180, 100, 80))
    nvgFill(vg)

    -- 用电量条（叠加在发电条上）
    local conFillW = barW * (conKW / maxKW)
    local conColor = power.overloaded and nvgRGBA(255, 60, 60, 180) or nvgRGBA(60, 160, 255, 160)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, conFillW, barH, 4)
    nvgFillColor(vg, conColor)
    nvgFill(vg)

    -- 发电量线标记
    nvgBeginPath(vg)
    nvgMoveTo(vg, barX + genFillW, barY - 2)
    nvgLineTo(vg, barX + genFillW, barY + barH + 2)
    nvgStrokeColor(vg, nvgRGBA(100, 255, 160, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 用电标签
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local conLabelColor = power.overloaded and nvgRGBA(255, 80, 80, 220) or nvgRGBA(160, 200, 240, 180)
    nvgFillColor(vg, conLabelColor)
    nvgText(vg, barX, barY + barH + 3, string.format("用电 %dkW", conKW))

    -- 过载警告
    if power.overloaded then
        local flash = math.sin(gameTime * 8) > 0 and 255 or 120
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, flash))
        nvgText(vg, barX + barW, barY + barH + 3, "⚠ 过载!")
    end

    -- 反应堆输出联动显示
    if reactor then
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 180, 100, 160))
        nvgText(vg, px + panelW - 12, barY - 2,
            string.format("反应堆 %d%%", math.floor((reactor.output or 0) * 100)))
    end

    -- ================================================================
    -- 系统列表（按优先级排列）
    -- ================================================================
    local listY = py + headerH

    -- 列标题
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(100, 130, 160, 150))
    nvgText(vg, hx + 18, listY - 2, "系统")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(vg, px + panelW * 0.6, listY - 2, "电力分配")
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgText(vg, px + panelW - 14, listY - 2, "效率")

    for i, sys in ipairs(systems) do
        local y = listY + (i - 1) * rowH
        local selected = (i == power.selectedIdx)
        local c = sys.color or {150, 150, 150}
        local isOnline = sys.online ~= false
        local isSevered = sys.severed == true

        -- 选中高亮背景
        if selected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px + 4, y + 1, panelW - 8, rowH - 2, 4)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 20))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 80))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 选中指示箭头
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 200))
            nvgText(vg, hx, y + rowH * 0.5, "▶")
        end

        -- 优先级序号
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 130, 160, 140))
        nvgText(vg, hx + 8, y + rowH * 0.5, tostring(i))

        -- 系统图标和名称
        local nameAlpha = isOnline and 220 or 100
        if isSevered then nameAlpha = 120 end
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], nameAlpha))
        local displayName = (sys.icon or "?") .. " " .. (sys.name or sys.key or "?")
        nvgText(vg, hx + 18, y + rowH * 0.5, displayName)

        -- 电力条
        local sBarX = px + 130
        local sBarW = 100
        local sBarH = 10
        local sBarY = y + math.floor((rowH - sBarH) * 0.5)

        -- 条背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sBarX, sBarY, sBarW, sBarH, 3)
        nvgFillColor(vg, nvgRGBA(20, 25, 35, 200))
        nvgFill(vg)

        -- 最大功耗范围（浅色底）
        local maxP = sys.maxPower or 1
        local allocated = sys.allocated or 0
        local efficiency = sys.efficiency or 0

        -- 已分配电力填充
        local allocFillW = sBarW * (allocated / math.max(maxP, 1))
        allocFillW = math.min(allocFillW, sBarW)

        if isSevered then
            -- 断线：红色斜线纹样
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sBarX, sBarY, sBarW, sBarH, 3)
            nvgFillColor(vg, nvgRGBA(80, 20, 20, 100))
            nvgFill(vg)
            -- 红色X标记
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 60, 60, 200))
            nvgText(vg, sBarX + sBarW * 0.5, sBarY + sBarH * 0.5, "断线")
        elseif not isOnline then
            -- 离线：暗灰
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sBarX, sBarY, sBarW, sBarH, 3)
            nvgFillColor(vg, nvgRGBA(40, 40, 50, 150))
            nvgFill(vg)
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 120, 130, 160))
            nvgText(vg, sBarX + sBarW * 0.5, sBarY + sBarH * 0.5, "离线")
        else
            -- 正常分配条
            local barAlpha = 180
            if efficiency < 0.3 then
                barAlpha = math.floor(100 + math.sin(gameTime * 6) * 80)
            end
            nvgBeginPath(vg)
            nvgRoundedRect(vg, sBarX, sBarY, allocFillW, sBarH, 3)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], barAlpha))
            nvgFill(vg)

            -- 最大功耗刻度线
            nvgBeginPath(vg)
            nvgMoveTo(vg, sBarX + sBarW, sBarY)
            nvgLineTo(vg, sBarX + sBarW, sBarY + sBarH)
            nvgStrokeColor(vg, nvgRGBA(c[1], c[2], c[3], 50))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- kW 数值
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 160))
        if not isSevered and isOnline then
            nvgText(vg, sBarX + sBarW + 4, y + rowH * 0.5,
                string.format("%d/%d", allocated, maxP))
        end

        -- 效率百分比
        local effPct = math.floor(efficiency * 100)
        local effColor
        if isSevered then
            effColor = nvgRGBA(255, 60, 60, 180)
        elseif effPct >= 80 then
            effColor = nvgRGBA(100, 255, 160, 200)
        elseif effPct >= 50 then
            effColor = nvgRGBA(255, 220, 60, 200)
        elseif effPct > 0 then
            local fa = math.floor(140 + math.sin(gameTime * 5) * 60)
            effColor = nvgRGBA(255, 120, 60, fa)
        else
            effColor = nvgRGBA(120, 120, 130, 140)
        end
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, effColor)
        if isSevered then
            nvgText(vg, px + panelW - 14, y + rowH * 0.5, "✕")
        else
            nvgText(vg, px + panelW - 14, y + rowH * 0.5, string.format("%d%%", effPct))
        end
    end

    -- ================================================================
    -- 底部操作提示
    -- ================================================================
    local fy = py + panelH - footerH + 4
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 140, 180, 150))
    nvgText(vg, px + panelW * 0.5, fy, "↑↓选择系统  ←→调整优先级  P关闭")
end

return PowerPanel
