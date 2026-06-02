--- 角色渲染：简笔画风格船员（支持多色AI + 名字状态标签 + 脚步波纹）
local Config = require("Config")
local AICrew = require("AICrew")

local CrewMember = {}

-- 脚步波纹粒子池
local footstepRipples = {}
local MAX_RIPPLES = 20

--- 绘制玩家角色（使用默认服装色）
---@param vg userdata
---@param char table 角色数据
---@param subX number 潜艇内部左边界屏幕X
---@param subY number 潜艇内部顶部Y
---@param subH number 潜艇内部高度
---@param gameTime number
function CrewMember.Draw(vg, char, subX, subY, subH, gameTime)
    local suitColor = Config.Colors.crewSuit
    CrewMember.DrawCharacter(vg, char, subX, subY, subH, gameTime, suitColor, nil, nil)
end

--- 绘制AI船员（带颜色/名字/职业/状态）
---@param vg userdata
---@param ai table AI船员数据
---@param subX number
---@param subY number
---@param subH number
---@param gameTime number
function CrewMember.DrawAI(vg, ai, subX, subY, subH, gameTime)
    local suitColor = ai.color
    local name = ai.name
    local stateText = AICrew.GetStateText(ai)
    local profTitle = AICrew.GetProfTitle(ai)

    CrewMember.DrawCharacter(vg, ai, subX, subY, subH, gameTime, suitColor, name, stateText, profTitle)

    -- 脚步波纹
    if ai.isMoving then
        local interval = 0.35
        if ai.footstepTimer >= interval then
            ai.footstepTimer = ai.footstepTimer - interval
            local x = subX + ai.x
            local floorY = subY + subH - 8
            CrewMember.AddRipple(x, floorY)
        end
    end
end

--- 通用角色绘制
---@param vg userdata
---@param char table 角色/AI数据
---@param subX number
---@param subY number
---@param subH number
---@param gameTime number
---@param suitColor table {r, g, b}
---@param name string|nil 头顶名字
---@param stateText string|nil 状态文字
---@param profTitle string|nil 职业头衔
function CrewMember.DrawCharacter(vg, char, subX, subY, subH, gameTime, suitColor, name, stateText, profTitle)
    local x = subX + char.x
    local floorY = subY + subH - 8
    local h = Config.Crew.height

    nvgSave(vg)
    nvgTranslate(vg, x, floorY)

    -- 根据朝向翻转
    if char.facing == -1 then
        nvgScale(vg, -1, 1)
    end

    local animTime = char.animTime
    local sc = suitColor  -- {r, g, b}

    if char.animState == "walk" then
        CrewMember.DrawWalking(vg, h, animTime, sc)
    elseif char.animState == "operate" then
        CrewMember.DrawOperating(vg, h, animTime, sc)
    elseif char.animState == "repair" then
        CrewMember.DrawRepairing(vg, h, animTime, sc)
    else
        CrewMember.DrawIdle(vg, h, animTime, sc)
    end

    -- 绘制肩章标识（职业区分）
    if profTitle then
        CrewMember.DrawShoulder(vg, h, sc, char)
    end

    nvgRestore(vg)

    -- 名字和状态标签（不受翻转影响）
    if name then
        local labelY = floorY - h - 20
        CrewMember.DrawLabel(vg, x, labelY, name, stateText, suitColor, gameTime, profTitle)
    end
end

--- 绘制头顶名字和状态标签
function CrewMember.DrawLabel(vg, x, y, name, stateText, color, gameTime, profTitle)
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)

    -- 职业头衔（小字）
    if profTitle then
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 150))
        nvgText(vg, x, y - 11, "【" .. profTitle .. "】")
    end

    -- 名字
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 220))
    nvgText(vg, x, y, name)

    -- 状态文字
    if stateText then
        nvgFontSize(vg, 10)
        local pulse = math.sin(gameTime * 3) * 0.15 + 0.85
        nvgFillColor(vg, nvgRGBA(200, 220, 240, math.floor(180 * pulse)))
        nvgText(vg, x, y + 13, stateText)
    end

    nvgRestore(vg)
end

--- 绘制肩章（职业视觉区分）
function CrewMember.DrawShoulder(vg, h, sc, char)
    local bodyY = -h * 0.4
    -- 肩章亮条纹（白色高光）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -12, bodyY + 2, 4, 8, 1)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 120))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 8, bodyY + 2, 4, 8, 1)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 120))
    nvgFill(vg)
end

--- 绘制待机状态
function CrewMember.DrawIdle(vg, h, t, sc)
    local breathe = math.sin(t * 2) * 1.5
    local cc = Config.Colors

    CrewMember.DrawLegs(vg, 0, 0, false, 0)

    local bodyY = -h * 0.4 + breathe
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -10, bodyY, 20, h * 0.35, 4)
    nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgFill(vg)

    -- 头盔
    local headY = bodyY - 18
    nvgBeginPath(vg)
    nvgCircle(vg, 0, headY, 11)
    nvgFillColor(vg, nvgRGBA(cc.crewHelmet[1], cc.crewHelmet[2], cc.crewHelmet[3], 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -7, headY - 4, 14, 10, 3)
    nvgFillColor(vg, nvgRGBA(30, 50, 80, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 3, headY - 1, 2)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
    nvgFill(vg)

    -- 手臂
    nvgBeginPath(vg)
    nvgMoveTo(vg, -10, bodyY + 5)
    nvgLineTo(vg, -14, bodyY + h * 0.2)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 10, bodyY + 5)
    nvgLineTo(vg, 14, bodyY + h * 0.2)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

--- 绘制行走状态
function CrewMember.DrawWalking(vg, h, t, sc)
    local cc = Config.Colors
    local walkCycle = math.sin(t * 8)

    CrewMember.DrawLegs(vg, walkCycle, 0, true, t)

    local bobY = math.abs(math.sin(t * 8)) * 2
    local bodyY = -h * 0.4 - bobY
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -10, bodyY, 20, h * 0.35, 4)
    nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgFill(vg)

    local headY = bodyY - 18
    nvgBeginPath(vg)
    nvgCircle(vg, 0, headY, 11)
    nvgFillColor(vg, nvgRGBA(cc.crewHelmet[1], cc.crewHelmet[2], cc.crewHelmet[3], 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -7, headY - 4, 14, 10, 3)
    nvgFillColor(vg, nvgRGBA(30, 50, 80, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 3, headY - 1, 2)
    nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
    nvgFill(vg)

    local armSwing = walkCycle * 15 * (math.pi / 180)
    nvgBeginPath(vg)
    nvgMoveTo(vg, -10, bodyY + 5)
    nvgLineTo(vg, -14 + math.sin(armSwing) * 8, bodyY + h * 0.2 + math.cos(armSwing) * 5)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 10, bodyY + 5)
    nvgLineTo(vg, 14 - math.sin(armSwing) * 8, bodyY + h * 0.2 - math.cos(armSwing) * 5)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

--- 绘制操作设备状态
function CrewMember.DrawOperating(vg, h, t, sc)
    local cc = Config.Colors
    local workBob = math.sin(t * 4) * 2

    CrewMember.DrawLegs(vg, 0, -5, false, 0)

    local bodyY = -h * 0.4 + 5
    nvgSave(vg)
    nvgTranslate(vg, 0, bodyY + h * 0.17)
    nvgRotate(vg, 0.15)
    nvgTranslate(vg, 0, -(bodyY + h * 0.17))

    nvgBeginPath(vg)
    nvgRoundedRect(vg, -10, bodyY, 20, h * 0.35, 4)
    nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgFill(vg)

    local headY = bodyY - 18
    nvgBeginPath(vg)
    nvgCircle(vg, 0, headY, 11)
    nvgFillColor(vg, nvgRGBA(cc.crewHelmet[1], cc.crewHelmet[2], cc.crewHelmet[3], 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -7, headY - 4, 14, 10, 3)
    nvgFillColor(vg, nvgRGBA(30, 50, 80, 200))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 10, bodyY + 5)
    nvgLineTo(vg, 22 + workBob, bodyY - 5)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, -10, bodyY + 5)
    nvgLineTo(vg, 18 - workBob, bodyY)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgRestore(vg)
end

--- 绘制修复状态（焊接动作）
function CrewMember.DrawRepairing(vg, h, t, sc)
    local cc = Config.Colors
    local weldPulse = math.sin(t * 6) * 3

    CrewMember.DrawLegs(vg, 0, -3, false, 0)

    local bodyY = -h * 0.4 + 3
    -- 身体微蹲
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -10, bodyY, 20, h * 0.35, 4)
    nvgFillColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgFill(vg)

    local headY = bodyY - 18
    nvgBeginPath(vg)
    nvgCircle(vg, 0, headY, 11)
    nvgFillColor(vg, nvgRGBA(cc.crewHelmet[1], cc.crewHelmet[2], cc.crewHelmet[3], 255))
    nvgFill(vg)
    -- 焊接面罩（深色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -8, headY - 5, 16, 12, 2)
    nvgFillColor(vg, nvgRGBA(15, 20, 30, 240))
    nvgFill(vg)

    -- 双手前伸焊接
    nvgBeginPath(vg)
    nvgMoveTo(vg, 10, bodyY + 5)
    nvgLineTo(vg, 24 + weldPulse, bodyY + 10)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, -10, bodyY + 5)
    nvgLineTo(vg, 20 - weldPulse, bodyY + 15)
    nvgStrokeColor(vg, nvgRGBA(sc[1], sc[2], sc[3], 255))
    nvgStrokeWidth(vg, 5)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 焊接光点
    local sparkAlpha = (math.sin(t * 12) + 1) * 0.5
    nvgBeginPath(vg)
    nvgCircle(vg, 25, bodyY + 12, 4 + weldPulse * 0.5)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, math.floor(200 * sparkAlpha)))
    nvgFill(vg)
end

--- 绘制腿部
function CrewMember.DrawLegs(vg, swing, yOffset, walking, t)
    local legLen = 22

    if walking then
        local legAngle1 = math.sin(t * 8) * 0.4
        local legAngle2 = math.sin(t * 8 + math.pi) * 0.4

        nvgBeginPath(vg)
        nvgMoveTo(vg, -5, yOffset)
        nvgLineTo(vg, -5 + math.sin(legAngle1) * legLen, yOffset - legLen)
        nvgStrokeColor(vg, nvgRGBA(40, 45, 55, 255))
        nvgStrokeWidth(vg, 6)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgMoveTo(vg, 5, yOffset)
        nvgLineTo(vg, 5 + math.sin(legAngle2) * legLen, yOffset - legLen)
        nvgStrokeColor(vg, nvgRGBA(40, 45, 55, 255))
        nvgStrokeWidth(vg, 6)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    else
        nvgBeginPath(vg)
        nvgMoveTo(vg, -5, yOffset)
        nvgLineTo(vg, -7, yOffset - legLen)
        nvgStrokeColor(vg, nvgRGBA(40, 45, 55, 255))
        nvgStrokeWidth(vg, 6)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgMoveTo(vg, 5, yOffset)
        nvgLineTo(vg, 7, yOffset - legLen)
        nvgStrokeColor(vg, nvgRGBA(40, 45, 55, 255))
        nvgStrokeWidth(vg, 6)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end

    -- 靴子
    nvgBeginPath(vg)
    nvgCircle(vg, -6, yOffset + 1, 4)
    nvgFillColor(vg, nvgRGBA(30, 32, 38, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, 6, yOffset + 1, 4)
    nvgFillColor(vg, nvgRGBA(30, 32, 38, 255))
    nvgFill(vg)
end

-- ============================================================
-- 脚步波纹系统
-- ============================================================

--- 添加脚步波纹
function CrewMember.AddRipple(x, y)
    if #footstepRipples >= MAX_RIPPLES then
        table.remove(footstepRipples, 1)
    end
    table.insert(footstepRipples, {
        x = x,
        y = y,
        radius = 3,
        maxRadius = 15,
        alpha = 180,
        life = 0,
        maxLife = 0.8,
    })
end

--- 更新波纹
function CrewMember.UpdateRipples(dt)
    for i = #footstepRipples, 1, -1 do
        local r = footstepRipples[i]
        r.life = r.life + dt
        local t = r.life / r.maxLife
        r.radius = 3 + t * (r.maxRadius - 3)
        r.alpha = math.floor(180 * (1 - t))

        if r.life >= r.maxLife then
            table.remove(footstepRipples, i)
        end
    end
end

--- 绘制所有波纹
function CrewMember.DrawRipples(vg)
    for _, r in ipairs(footstepRipples) do
        if r.alpha > 5 then
            nvgBeginPath(vg)
            nvgCircle(vg, r.x, r.y, r.radius)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, r.alpha))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end
end

return CrewMember
