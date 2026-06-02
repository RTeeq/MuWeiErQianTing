--- 角色移动逻辑（含危机交互状态）

local Config = require("Config")

local Character = {}

---@alias AnimState "idle"|"walk"|"repair"|"operate"

--- 创建角色
---@param sub table 潜艇状态
---@return table
function Character.Create(sub)
    local startRoom = Config.Crew.startRoom
    local startX = sub.compartments[startRoom].x + sub.compartments[startRoom].width * 0.5

    return {
        x = startX,             -- 在潜艇内部的X位置
        roomIndex = startRoom,  -- 当前所在舱室
        facing = 1,             -- 1=右, -1=左
        animState = "idle",     ---@type AnimState
        animTime = 0,           -- 动画计时器
        isOperating = false,    -- 是否在操作设备
        operateTarget = nil,    -- 操作的设备名

        -- 危机交互
        isRepairing = false,    -- 是否正在修复
        repairType = nil,       ---@type string|nil 正在修复的危机类型
        repairProgress = 0,     -- 修复进度 0~1
    }
end

--- 更新角色状态
---@param char table
---@param sub table
---@param joystickX number -1~1 摇杆X轴
---@param dt number
function Character.Update(char, sub, joystickX, dt)
    char.animTime = char.animTime + dt

    -- 如果正在修复，不处理移动
    if char.isRepairing then
        char.animState = "repair"
        return
    end

    -- 如果正在操作设备，不处理移动
    if char.isOperating then
        char.animState = "operate"
        return
    end

    -- 移动
    local deadZone = 0.15
    if math.abs(joystickX) > deadZone then
        local speed = Config.Crew.moveSpeed * joystickX
        char.x = char.x + speed * dt
        char.facing = joystickX > 0 and 1 or -1
        char.animState = "walk"
    else
        char.animState = "idle"
    end

    -- 限制在潜艇范围内
    local totalWidth = 0
    for _, comp in ipairs(sub.compartments) do
        totalWidth = totalWidth + comp.width
    end
    local margin = Config.Crew.width * 0.5
    char.x = math.max(margin, math.min(totalWidth - margin, char.x))

    -- 确定当前所在舱室
    for i, comp in ipairs(sub.compartments) do
        if char.x >= comp.x and char.x < comp.x + comp.width then
            char.roomIndex = i
            break
        end
    end
end

--- 开始修复动作
---@param char table
---@param crisisType string
function Character.StartRepair(char, crisisType)
    char.isRepairing = true
    char.repairType = crisisType
    char.animState = "repair"
    char.animTime = 0
end

--- 停止修复动作
---@param char table
function Character.StopRepair(char)
    char.isRepairing = false
    char.repairType = nil
    char.repairProgress = 0
    char.animState = "idle"
end

--- 开始操作设备
function Character.StartOperate(char, equipName)
    char.isOperating = true
    char.operateTarget = equipName
    char.animState = "operate"
    char.animTime = 0
end

--- 停止操作
function Character.StopOperate(char)
    char.isOperating = false
    char.operateTarget = nil
    char.animState = "idle"
end

--- 判断角色是否在指定舱室内且靠近设备位置
---@param char table
---@param sub table
---@param roomIndex number
---@param tolerance number 容差距离（像素）
---@return boolean
function Character.IsNearTarget(char, sub, roomIndex, tolerance)
    if char.roomIndex ~= roomIndex then return false end

    -- 判断是否在该舱室中心附近
    local comp = sub.compartments[roomIndex]
    if not comp then return false end
    local centerX = comp.x + comp.width * 0.5
    return math.abs(char.x - centerX) < (tolerance or comp.width * 0.4)
end

return Character
