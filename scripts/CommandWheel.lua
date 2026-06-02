--- 指令轮盘 UI - 点击AI船员后弹出的环形菜单
--- 选项：跟随/维修/操作设备/待命

local CommandWheel = {}

--- 轮盘配置
local COMMANDS = {
    {id = "follow",  label = "跟随",   icon = "→", color = {80, 180, 255}},
    {id = "repair",  label = "维修",   icon = "⚙", color = {255, 180, 50}},
    {id = "operate", label = "操作",   icon = "⚡", color = {100, 220, 100}},
    {id = "standby", label = "待命",   icon = "■", color = {180, 180, 180}},
}

local WHEEL_RADIUS = 80        -- 轮盘半径
local ITEM_RADIUS = 28         -- 选项圆半径
local FADE_SPEED = 6.0         -- 淡入速度

--- 创建轮盘状态
function CommandWheel.Create()
    return {
        visible = false,
        centerX = 0,
        centerY = 0,
        targetAI = nil,         -- 目标AI索引
        alpha = 0,              -- 透明度动画
        hoverIndex = nil,       -- 鼠标悬停的选项
        aiName = "",            -- 目标AI名字
    }
end

--- 显示轮盘
---@param wheel table
---@param screenX number 屏幕坐标X
---@param screenY number 屏幕坐标Y
---@param aiIndex number AI索引
---@param aiName string AI名字
function CommandWheel.Show(wheel, screenX, screenY, aiIndex, aiName)
    wheel.visible = true
    wheel.centerX = screenX
    wheel.centerY = screenY
    wheel.targetAI = aiIndex
    wheel.alpha = 0
    wheel.hoverIndex = nil
    wheel.aiName = aiName or ""
end

--- 隐藏轮盘
function CommandWheel.Hide(wheel)
    wheel.visible = false
    wheel.targetAI = nil
    wheel.hoverIndex = nil
end

--- 更新轮盘（淡入动画）
function CommandWheel.Update(wheel, dt)
    if wheel.visible then
        wheel.alpha = math.min(1.0, wheel.alpha + FADE_SPEED * dt)
    end
end

--- 处理点击 - 返回选中的指令ID，或nil
---@param wheel table
---@param clickX number 屏幕坐标
---@param clickY number 屏幕坐标
---@return string|nil commandId
---@return number|nil aiIndex
function CommandWheel.HandleClick(wheel, clickX, clickY)
    if not wheel.visible then return nil, nil end

    -- 检查是否点击了某个选项
    for i, cmd in ipairs(COMMANDS) do
        local angle = (i - 1) * (2 * math.pi / #COMMANDS) - math.pi / 2
        local ix = wheel.centerX + math.cos(angle) * WHEEL_RADIUS
        local iy = wheel.centerY + math.sin(angle) * WHEEL_RADIUS

        local dx = clickX - ix
        local dy = clickY - iy
        if dx * dx + dy * dy < ITEM_RADIUS * ITEM_RADIUS then
            local aiIdx = wheel.targetAI
            CommandWheel.Hide(wheel)
            return cmd.id, aiIdx
        end
    end

    -- 点击轮盘外部 → 关闭
    local dx = clickX - wheel.centerX
    local dy = clickY - wheel.centerY
    if dx * dx + dy * dy > (WHEEL_RADIUS + ITEM_RADIUS + 20) ^ 2 then
        CommandWheel.Hide(wheel)
    end

    return nil, nil
end

--- 更新悬停状态（用于高亮显示）
function CommandWheel.UpdateHover(wheel, mouseX, mouseY)
    if not wheel.visible then return end

    wheel.hoverIndex = nil
    for i, _ in ipairs(COMMANDS) do
        local angle = (i - 1) * (2 * math.pi / #COMMANDS) - math.pi / 2
        local ix = wheel.centerX + math.cos(angle) * WHEEL_RADIUS
        local iy = wheel.centerY + math.sin(angle) * WHEEL_RADIUS

        local dx = mouseX - ix
        local dy = mouseY - iy
        if dx * dx + dy * dy < ITEM_RADIUS * ITEM_RADIUS then
            wheel.hoverIndex = i
            break
        end
    end
end

--- 绘制轮盘
---@param vg userdata
---@param wheel table
---@param gameTime number
function CommandWheel.Draw(vg, wheel, gameTime)
    if not wheel.visible or wheel.alpha < 0.01 then return end

    local a = wheel.alpha
    local cx, cy = wheel.centerX, wheel.centerY

    nvgSave(vg)

    -- 半透明背景遮罩圆
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, WHEEL_RADIUS + ITEM_RADIUS + 15)
    nvgFillColor(vg, nvgRGBA(10, 15, 25, math.floor(120 * a)))
    nvgFill(vg)

    -- 中心AI名字
    nvgFontSize(vg, 14)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 220, 255, math.floor(255 * a)))
    nvgText(vg, cx, cy, wheel.aiName)

    -- 绘制各选项
    for i, cmd in ipairs(COMMANDS) do
        local angle = (i - 1) * (2 * math.pi / #COMMANDS) - math.pi / 2
        local ix = cx + math.cos(angle) * WHEEL_RADIUS
        local iy = cy + math.sin(angle) * WHEEL_RADIUS

        local isHover = (wheel.hoverIndex == i)
        local r = isHover and (ITEM_RADIUS + 4) or ITEM_RADIUS
        local brightMul = isHover and 1.3 or 1.0

        -- 选项圆形背景
        nvgBeginPath(vg)
        nvgCircle(vg, ix, iy, r)
        local cr = math.min(255, math.floor(cmd.color[1] * brightMul))
        local cg = math.min(255, math.floor(cmd.color[2] * brightMul))
        local cb = math.min(255, math.floor(cmd.color[3] * brightMul))
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(200 * a)))
        nvgFill(vg)

        -- 边框
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(100 * a)))
        nvgStrokeWidth(vg, isHover and 2.5 or 1.5)
        nvgStroke(vg)

        -- 标签文字
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * a)))
        nvgText(vg, ix, iy, cmd.label)
    end

    -- 连接线
    nvgBeginPath(vg)
    for i, _ in ipairs(COMMANDS) do
        local angle = (i - 1) * (2 * math.pi / #COMMANDS) - math.pi / 2
        local ix = cx + math.cos(angle) * (WHEEL_RADIUS - ITEM_RADIUS)
        local iy = cy + math.sin(angle) * (WHEEL_RADIUS - ITEM_RADIUS)
        nvgMoveTo(vg, cx, cy)
        nvgLineTo(vg, ix, iy)
    end
    nvgStrokeColor(vg, nvgRGBA(100, 150, 200, math.floor(60 * a)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgRestore(vg)
end

return CommandWheel
