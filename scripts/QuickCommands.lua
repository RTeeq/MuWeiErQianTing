--- 快捷通信系统
--- 预设消息轮盘（联机玩家间通信）、文字聊天、消息显示/淡出
local Config = require("Config")

local QuickCommands = {}

-- ============================================================
-- 预设快捷消息
-- ============================================================
QuickCommands.CATEGORIES = {
    { id = "danger",    label = "危险",   color = {255, 80, 80} },
    { id = "request",   label = "请求",   color = {80, 180, 255} },
    { id = "action",    label = "行动",   color = {100, 220, 100} },
    { id = "social",    label = "社交",   color = {220, 180, 80} },
}

QuickCommands.PRESETS = {
    -- 危险警告
    { id = "hull_breach",   category = "danger",  text = "船体破裂!",          icon = "!" },
    { id = "reactor_hot",   category = "danger",  text = "反应堆过热!",        icon = "☢" },
    { id = "monster_left",  category = "danger",  text = "怪物在左舷!",        icon = "◀" },
    { id = "monster_right", category = "danger",  text = "怪物在右舷!",        icon = "▶" },
    { id = "monster_front", category = "danger",  text = "怪物在前方!",        icon = "▲" },
    { id = "monster_rear",  category = "danger",  text = "怪物在后方!",        icon = "▼" },
    { id = "flooding",      category = "danger",  text = "进水了!",            icon = "~" },
    { id = "fire",          category = "danger",  text = "起火了!",            icon = "♨" },

    -- 请求协助
    { id = "need_engineer", category = "request", text = "需要工程师!",        icon = "⚡" },
    { id = "need_mechanic", category = "request", text = "需要技工!",          icon = "⚙" },
    { id = "need_medic",    category = "request", text = "需要医官!",          icon = "+" },
    { id = "need_help",     category = "request", text = "救命!",              icon = "!" },
    { id = "need_repair",   category = "request", text = "需要维修[位置]!",    icon = "⚙" },
    { id = "oxygen_low",    category = "request", text = "氧气不足!",          icon = "O" },

    -- 行动指令
    { id = "follow_me",     category = "action",  text = "跟我来",             icon = "→" },
    { id = "retreat",       category = "action",  text = "撤退!",              icon = "←" },
    { id = "hold_position", category = "action",  text = "原地待命",           icon = "■" },
    { id = "dive_now",      category = "action",  text = "紧急下潜!",          icon = "↓" },
    { id = "surface_now",   category = "action",  text = "紧急上浮!",          icon = "↑" },
    { id = "all_clear",     category = "action",  text = "安全了",             icon = "✓" },

    -- 社交
    { id = "thanks",        category = "social",  text = "谢谢!",              icon = "♥" },
    { id = "sorry",         category = "social",  text = "对不起",             icon = "…" },
    { id = "good_job",      category = "social",  text = "干得好!",            icon = "★" },
    { id = "ready",         category = "social",  text = "准备好了",           icon = "✓" },
    { id = "wait",          category = "social",  text = "等一下",             icon = "…" },
    { id = "roger",         category = "social",  text = "收到",               icon = "✓" },
}

-- ============================================================
-- 轮盘配置
-- ============================================================
local WHEEL_OUTER_RADIUS = 120   -- 外圈半径
local WHEEL_INNER_RADIUS = 40    -- 内圈半径（中心死区）
local CATEGORY_RADIUS = 80       -- 分类选择圆半径
local ITEM_RADIUS = 100          -- 子项圆半径
local FADE_SPEED = 8.0           -- 淡入速度

-- ============================================================
-- 消息显示配置
-- ============================================================
local MSG_MAX_VISIBLE = 6        -- 最多同时显示6条
local MSG_FADE_DURATION = 1.0    -- 淡出时间
local MSG_DISPLAY_TIME = 4.0     -- 显示持续时间
local MSG_QUICK_DISPLAY = 3.0    -- 快捷消息显示时间（短一些）

-- ============================================================
-- 轮盘状态
-- ============================================================

--- 创建快捷指令轮盘状态
---@return table wheelState
function QuickCommands.CreateWheel()
    return {
        visible = false,
        alpha = 0,
        -- 两级选择：先选分类，再选具体指令
        level = 1,               -- 1=选分类, 2=选指令
        selectedCategory = nil,  -- 选中的分类ID
        hoverIndex = nil,        -- 悬停索引
        centerX = 0,
        centerY = 0,
    }
end

--- 显示轮盘
---@param wheel table 轮盘状态
---@param centerX number 屏幕中心X
---@param centerY number 屏幕中心Y
function QuickCommands.ShowWheel(wheel, centerX, centerY)
    wheel.visible = true
    wheel.alpha = 0
    wheel.level = 1
    wheel.selectedCategory = nil
    wheel.hoverIndex = nil
    wheel.centerX = centerX
    wheel.centerY = centerY
end

--- 隐藏轮盘
---@param wheel table 轮盘状态
function QuickCommands.HideWheel(wheel)
    wheel.visible = false
    wheel.level = 1
    wheel.selectedCategory = nil
    wheel.hoverIndex = nil
end

--- 更新轮盘动画
---@param wheel table 轮盘状态
---@param dt number 时间步长
function QuickCommands.UpdateWheel(wheel, dt)
    if wheel.visible then
        wheel.alpha = math.min(1.0, wheel.alpha + FADE_SPEED * dt)
    end
end

--- 获取当前分类下的预设消息列表
---@param categoryId string 分类ID
---@return table presets
function QuickCommands.GetPresetsForCategory(categoryId)
    local result = {}
    for _, preset in ipairs(QuickCommands.PRESETS) do
        if preset.category == categoryId then
            table.insert(result, preset)
        end
    end
    return result
end

--- 处理轮盘点击
---@param wheel table 轮盘状态
---@param clickX number 点击坐标X
---@param clickY number 点击坐标Y
---@return string|nil presetId 选中的指令ID
function QuickCommands.HandleWheelClick(wheel, clickX, clickY)
    if not wheel.visible then return nil end

    local dx = clickX - wheel.centerX
    local dy = clickY - wheel.centerY
    local dist = math.sqrt(dx * dx + dy * dy)

    -- 中心死区 → 关闭
    if dist < WHEEL_INNER_RADIUS then
        QuickCommands.HideWheel(wheel)
        return nil
    end

    -- 超出外圈 → 关闭
    if dist > WHEEL_OUTER_RADIUS + 40 then
        QuickCommands.HideWheel(wheel)
        return nil
    end

    -- 计算角度确定选中项
    local angle = math.atan(dy, dx)
    if angle < 0 then angle = angle + 2 * math.pi end

    if wheel.level == 1 then
        -- 第一级：选分类
        local catCount = #QuickCommands.CATEGORIES
        local sectorAngle = 2 * math.pi / catCount
        local index = math.floor(angle / sectorAngle) + 1
        index = math.max(1, math.min(catCount, index))

        wheel.selectedCategory = QuickCommands.CATEGORIES[index].id
        wheel.level = 2
        wheel.hoverIndex = nil
        return nil  -- 进入第二级，不返回结果
    else
        -- 第二级：选具体指令
        local presets = QuickCommands.GetPresetsForCategory(wheel.selectedCategory)
        local itemCount = #presets
        if itemCount == 0 then
            QuickCommands.HideWheel(wheel)
            return nil
        end

        local sectorAngle = 2 * math.pi / itemCount
        local index = math.floor(angle / sectorAngle) + 1
        index = math.max(1, math.min(itemCount, index))

        local selectedPreset = presets[index]
        QuickCommands.HideWheel(wheel)
        return selectedPreset.id
    end
end

--- 更新悬停状态
---@param wheel table 轮盘状态
---@param mouseX number 鼠标X
---@param mouseY number 鼠标Y
function QuickCommands.UpdateWheelHover(wheel, mouseX, mouseY)
    if not wheel.visible then return end

    local dx = mouseX - wheel.centerX
    local dy = mouseY - wheel.centerY
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < WHEEL_INNER_RADIUS or dist > WHEEL_OUTER_RADIUS + 40 then
        wheel.hoverIndex = nil
        return
    end

    local angle = math.atan(dy, dx)
    if angle < 0 then angle = angle + 2 * math.pi end

    local items
    if wheel.level == 1 then
        items = QuickCommands.CATEGORIES
    else
        items = QuickCommands.GetPresetsForCategory(wheel.selectedCategory)
    end

    local itemCount = #items
    if itemCount == 0 then
        wheel.hoverIndex = nil
        return
    end

    local sectorAngle = 2 * math.pi / itemCount
    local index = math.floor(angle / sectorAngle) + 1
    wheel.hoverIndex = math.max(1, math.min(itemCount, index))
end

--- 返回上一级（右键或ESC）
---@param wheel table 轮盘状态
function QuickCommands.WheelBack(wheel)
    if not wheel.visible then return end
    if wheel.level == 2 then
        wheel.level = 1
        wheel.selectedCategory = nil
        wheel.hoverIndex = nil
    else
        QuickCommands.HideWheel(wheel)
    end
end

-- ============================================================
-- 消息队列（显示在屏幕上的历史消息）
-- ============================================================

--- 创建消息队列
---@return table msgQueue
function QuickCommands.CreateMessageQueue()
    return {
        messages = {},           -- [{text, senderName, senderSlot, msgType, time, alpha}]
        maxMessages = 20,        -- 最大存储
    }
end

--- 推入新消息
---@param queue table 消息队列
---@param senderName string 发送者名字
---@param senderSlot number 发送者槽位
---@param text string 消息内容
---@param msgType string "quick"/"chat"/"system"/"hint"
---@param gameTime number 当前游戏时间
function QuickCommands.PushMessage(queue, senderName, senderSlot, text, msgType, gameTime)
    table.insert(queue.messages, {
        text = text,
        senderName = senderName,
        senderSlot = senderSlot,
        msgType = msgType,
        time = gameTime,
        alpha = 1.0,
    })

    -- 超出上限移除最早的
    while #queue.messages > queue.maxMessages do
        table.remove(queue.messages, 1)
    end
end

--- 更新消息淡出
---@param queue table 消息队列
---@param gameTime number 当前游戏时间
function QuickCommands.UpdateMessages(queue, gameTime)
    local toRemove = {}
    for i, msg in ipairs(queue.messages) do
        local displayTime = (msg.msgType == "quick") and MSG_QUICK_DISPLAY or MSG_DISPLAY_TIME
        local age = gameTime - msg.time

        if age > displayTime + MSG_FADE_DURATION then
            table.insert(toRemove, i)
        elseif age > displayTime then
            msg.alpha = 1.0 - (age - displayTime) / MSG_FADE_DURATION
        end
    end

    -- 从后往前删除
    for i = #toRemove, 1, -1 do
        table.remove(queue.messages, toRemove[i])
    end
end

--- 获取当前可见的消息列表
---@param queue table 消息队列
---@return table visibleMsgs
function QuickCommands.GetVisibleMessages(queue)
    local visible = {}
    local count = 0
    -- 从最新开始取
    for i = #queue.messages, 1, -1 do
        if queue.messages[i].alpha > 0.01 then
            table.insert(visible, 1, queue.messages[i])
            count = count + 1
            if count >= MSG_MAX_VISIBLE then break end
        end
    end
    return visible
end

-- ============================================================
-- 文字聊天输入
-- ============================================================

--- 创建聊天输入状态
---@return table chatInput
function QuickCommands.CreateChatInput()
    return {
        active = false,          -- 输入框是否激活
        text = "",               -- 当前输入内容
        maxLength = 50,          -- 最大字符数
        cursorBlink = 0,         -- 光标闪烁计时
    }
end

--- 激活聊天输入
---@param chatInput table 聊天输入状态
function QuickCommands.ActivateChat(chatInput)
    chatInput.active = true
    chatInput.text = ""
    chatInput.cursorBlink = 0
end

--- 取消聊天输入
---@param chatInput table 聊天输入状态
function QuickCommands.DeactivateChat(chatInput)
    chatInput.active = false
    chatInput.text = ""
end

--- 处理文字输入（追加字符）
---@param chatInput table 聊天输入状态
---@param char string 输入字符
function QuickCommands.AppendChar(chatInput, char)
    if not chatInput.active then return end
    if #chatInput.text < chatInput.maxLength then
        chatInput.text = chatInput.text .. char
    end
end

--- 删除最后一个字符
---@param chatInput table 聊天输入状态
function QuickCommands.Backspace(chatInput)
    if not chatInput.active then return end
    if #chatInput.text > 0 then
        -- UTF-8 安全删除（处理中文）
        local bytes = {string.byte(chatInput.text, 1, -1)}
        local i = #bytes
        -- 回退到 UTF-8 字符起始位置
        while i > 0 and bytes[i] >= 128 and bytes[i] < 192 do
            i = i - 1
        end
        if i > 0 then
            chatInput.text = string.sub(chatInput.text, 1, i - 1)
        end
    end
end

--- 提交聊天消息（回车）
---@param chatInput table 聊天输入状态
---@return string|nil text 发送的文本
function QuickCommands.SubmitChat(chatInput)
    if not chatInput.active then return nil end
    local text = chatInput.text
    chatInput.active = false
    chatInput.text = ""
    if text and #text > 0 then
        return text
    end
    return nil
end

--- 更新聊天光标闪烁
---@param chatInput table 聊天输入状态
---@param dt number 时间步长
function QuickCommands.UpdateChatInput(chatInput, dt)
    if chatInput.active then
        chatInput.cursorBlink = chatInput.cursorBlink + dt
        if chatInput.cursorBlink > 1.0 then
            chatInput.cursorBlink = 0
        end
    end
end

-- ============================================================
-- NanoVG 绘制：轮盘
-- ============================================================

--- 绘制快捷指令轮盘
---@param vg userdata NanoVG 上下文
---@param wheel table 轮盘状态
function QuickCommands.DrawWheel(vg, wheel)
    if not wheel.visible or wheel.alpha < 0.01 then return end

    local a = wheel.alpha
    local cx, cy = wheel.centerX, wheel.centerY

    nvgSave(vg)

    -- 半透明遮罩背景
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, WHEEL_OUTER_RADIUS + 30)
    nvgFillColor(vg, nvgRGBA(5, 10, 20, math.floor(160 * a)))
    nvgFill(vg)

    -- 内圈边框
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, WHEEL_INNER_RADIUS)
    nvgStrokeColor(vg, nvgRGBA(100, 150, 200, math.floor(120 * a)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 中心提示文字
    nvgFontSize(vg, 11)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 180, 220, math.floor(180 * a)))
    if wheel.level == 1 then
        nvgText(vg, cx, cy, "选择分类")
    else
        nvgText(vg, cx, cy, "◀ 右键返回")
    end

    -- 获取当前显示项目
    local items
    if wheel.level == 1 then
        items = QuickCommands.CATEGORIES
    else
        items = QuickCommands.GetPresetsForCategory(wheel.selectedCategory)
    end

    local itemCount = #items
    if itemCount == 0 then
        nvgRestore(vg)
        return
    end

    local sectorAngle = 2 * math.pi / itemCount
    local radius = (wheel.level == 1) and CATEGORY_RADIUS or ITEM_RADIUS

    for i, item in ipairs(items) do
        local angle = (i - 1) * sectorAngle + sectorAngle / 2
        local ix = cx + math.cos(angle) * radius
        local iy = cy + math.sin(angle) * radius

        local isHover = (wheel.hoverIndex == i)

        -- 获取颜色
        local col
        if wheel.level == 1 then
            col = item.color
        else
            -- 从分类获取颜色
            for _, cat in ipairs(QuickCommands.CATEGORIES) do
                if cat.id == item.category then
                    col = cat.color
                    break
                end
            end
            col = col or {180, 180, 180}
        end

        -- 扇区高亮
        if isHover then
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgArc(vg, cx, cy, WHEEL_OUTER_RADIUS + 10,
                   (i - 1) * sectorAngle, i * sectorAngle, NVG_CW)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(40 * a)))
            nvgFill(vg)
        end

        -- 选项圆
        local r = isHover and 24 or 20
        nvgBeginPath(vg)
        nvgCircle(vg, ix, iy, r)
        local bgAlpha = isHover and 220 or 160
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(bgAlpha * a)))
        nvgFill(vg)

        -- 边框
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor((isHover and 200 or 80) * a)))
        nvgStrokeWidth(vg, isHover and 2.0 or 1.0)
        nvgStroke(vg)

        -- 标签
        nvgFontSize(vg, isHover and 13 or 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(255 * a)))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        if wheel.level == 1 then
            nvgText(vg, ix, iy, item.label)
        else
            -- 指令用图标 + 文字
            nvgText(vg, ix, iy - 6, item.icon or "")
            nvgFontSize(vg, 9)
            nvgText(vg, ix, iy + 8, item.text)
        end
    end

    -- 分隔线
    nvgBeginPath(vg)
    for i = 1, itemCount do
        local angle = (i - 1) * sectorAngle
        local lx = cx + math.cos(angle) * WHEEL_INNER_RADIUS
        local ly = cy + math.sin(angle) * WHEEL_INNER_RADIUS
        local ox = cx + math.cos(angle) * (WHEEL_OUTER_RADIUS + 10)
        local oy = cy + math.sin(angle) * (WHEEL_OUTER_RADIUS + 10)
        nvgMoveTo(vg, lx, ly)
        nvgLineTo(vg, ox, oy)
    end
    nvgStrokeColor(vg, nvgRGBA(60, 100, 140, math.floor(60 * a)))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    nvgRestore(vg)
end

-- ============================================================
-- NanoVG 绘制：消息列表
-- ============================================================

--- 获取消息类型对应颜色
---@param msgType string
---@return number r, number g, number b
local function GetMsgColor(msgType)
    if msgType == "quick" then return 80, 200, 255 end
    if msgType == "system" then return 255, 220, 80 end
    if msgType == "hint" then return 180, 100, 255 end
    return 200, 220, 240  -- chat
end

--- 绘制消息列表（左下角）
---@param vg userdata NanoVG 上下文
---@param queue table 消息队列
---@param screenW number 屏幕宽度
---@param screenH number 屏幕高度
function QuickCommands.DrawMessages(vg, queue, screenW, screenH)
    local visible = QuickCommands.GetVisibleMessages(queue)
    if #visible == 0 then return end

    nvgSave(vg)

    local x = 12
    local y = screenH - 60  -- 底部往上
    local lineHeight = 20

    -- 从下到上绘制消息
    for i = #visible, 1, -1 do
        local msg = visible[i]
        local ma = msg.alpha
        local r, g, b = GetMsgColor(msg.msgType)

        -- 背景条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 4, y - lineHeight + 4, 300, lineHeight, 3)
        nvgFillColor(vg, nvgRGBA(10, 15, 25, math.floor(140 * ma)))
        nvgFill(vg)

        -- 发送者名字
        nvgFontSize(vg, 12)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        if msg.msgType ~= "system" then
            nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(220 * ma)))
            nvgText(vg, x, y - lineHeight / 2 + 4, "[" .. msg.senderName .. "]")

            -- 消息内容（偏右）
            nvgFillColor(vg, nvgRGBA(230, 240, 255, math.floor(240 * ma)))
            local nameW = nvgTextBounds(vg, 0, 0, "[" .. msg.senderName .. "]")
            nvgText(vg, x + nameW + 6, y - lineHeight / 2 + 4, msg.text)
        else
            -- 系统消息居中显示
            nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(240 * ma)))
            nvgText(vg, x, y - lineHeight / 2 + 4, "● " .. msg.text)
        end

        y = y - lineHeight
    end

    nvgRestore(vg)
end

-- ============================================================
-- NanoVG 绘制：聊天输入框
-- ============================================================

--- 绘制聊天输入框
---@param vg userdata NanoVG 上下文
---@param chatInput table 聊天输入状态
---@param screenW number 屏幕宽度
---@param screenH number 屏幕高度
function QuickCommands.DrawChatInput(vg, chatInput, screenW, screenH)
    if not chatInput.active then return end

    nvgSave(vg)

    local x = 10
    local y = screenH - 35
    local w = math.min(400, screenW - 20)
    local h = 28

    -- 输入框背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 4)
    nvgFillColor(vg, nvgRGBA(15, 20, 30, 220))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 150, 220, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 提示文字 / 输入内容
    nvgFontSize(vg, 13)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local displayText = chatInput.text
    if #displayText == 0 then
        nvgFillColor(vg, nvgRGBA(120, 140, 160, 180))
        nvgText(vg, x + 8, y + h / 2, "输入消息... (Enter发送, Esc取消)")
    else
        nvgFillColor(vg, nvgRGBA(230, 240, 255, 255))
        nvgText(vg, x + 8, y + h / 2, displayText)
    end

    -- 光标闪烁
    if chatInput.cursorBlink < 0.5 then
        local textW = 0
        if #displayText > 0 then
            textW = nvgTextBounds(vg, 0, 0, displayText)
        end
        nvgBeginPath(vg)
        nvgRect(vg, x + 8 + textW + 2, y + 5, 1.5, h - 10)
        nvgFillColor(vg, nvgRGBA(80, 180, 255, 220))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

-- ============================================================
-- 声音距离衰减（同舱室全音量，跨舱室按距离衰减）
-- ============================================================

--- 计算语音/通信音量衰减
---@param senderRoom number 发送者舱室
---@param receiverRoom number 接收者舱室
---@param distance number 距离（像素/逻辑单位）
---@return number volume 0~1
function QuickCommands.CalcVoiceVolume(senderRoom, receiverRoom, distance)
    if senderRoom == receiverRoom then
        return 1.0  -- 同舱室全音量
    end

    -- 跨舱室：基础衰减 + 距离衰减
    local baseAttenuation = 0.4   -- 隔一个舱室至少衰减到40%
    local roomDiff = math.abs(senderRoom - receiverRoom)
    local roomFactor = math.max(0.1, baseAttenuation / roomDiff)

    -- 距离进一步衰减
    local maxDist = 800  -- 最大可听距离
    local distFactor = math.max(0, 1.0 - distance / maxDist)

    return roomFactor * distFactor
end

-- ============================================================
-- 获取预设消息文本
-- ============================================================

--- 根据presetId获取预设消息完整信息
---@param presetId string 预设ID
---@return table|nil preset {id, category, text, icon}
function QuickCommands.GetPreset(presetId)
    for _, preset in ipairs(QuickCommands.PRESETS) do
        if preset.id == presetId then
            return preset
        end
    end
    return nil
end

--- 获取预设消息的显示文本
---@param presetId string 预设ID
---@return string text
function QuickCommands.GetPresetText(presetId)
    local preset = QuickCommands.GetPreset(presetId)
    if preset then return preset.text end
    return "[未知指令]"
end

return QuickCommands
