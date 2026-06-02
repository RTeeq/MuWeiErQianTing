--- 深海背景渲染：渐变、气泡、深海生物剪影
local Config = require("Config")

local Background = {}

-- 气泡数据
local bubbles = {}
local creatures = {}
local nextCreatureTime = 5

--- 初始化气泡
function Background.Init(screenW, screenH)
    bubbles = {}
    for i = 1, Config.Background.bubbleCount do
        bubbles[i] = {
            x = math.random() * screenW,
            y = math.random() * screenH,
            r = Config.Background.bubbleMinR + math.random() * (Config.Background.bubbleMaxR - Config.Background.bubbleMinR),
            speed = Config.Background.bubbleSpeed * (0.5 + math.random() * 0.5),
            wobble = math.random() * math.pi * 2,
            wobbleSpeed = 1 + math.random() * 2,
        }
    end
    creatures = {}
    nextCreatureTime = 5 + math.random() * 5
end

--- 更新气泡和生物
function Background.Update(dt, screenW, screenH, gameTime)
    -- 更新气泡
    for _, b in ipairs(bubbles) do
        b.y = b.y - b.speed * dt
        b.wobble = b.wobble + b.wobbleSpeed * dt
        b.x = b.x + math.sin(b.wobble) * 0.5

        -- 超出顶部则回到底部
        if b.y < -10 then
            b.y = screenH + 10
            b.x = math.random() * screenW
        end
    end

    -- 生物出现逻辑
    nextCreatureTime = nextCreatureTime - dt
    if nextCreatureTime <= 0 then
        local dir = math.random() > 0.5 and 1 or -1
        local startX = dir == 1 and -200 or (screenW + 200)
        local yPos = screenH * (0.2 + math.random() * 0.6)
        local cType = math.random(1, 3) -- 1=鱼, 2=水母, 3=大型生物

        table.insert(creatures, {
            x = startX,
            y = yPos,
            dir = dir,
            speed = Config.Background.creatureSpeed * (0.5 + math.random()),
            cType = cType,
            size = 20 + math.random() * 40,
            alpha = 60 + math.random(0, 40),
        })

        local interval = Config.Background.creatureInterval
        nextCreatureTime = interval[1] + math.random() * (interval[2] - interval[1])
    end

    -- 更新生物位置
    for i = #creatures, 1, -1 do
        local c = creatures[i]
        c.x = c.x + c.dir * c.speed * dt
        -- 超出屏幕则移除
        if (c.dir == 1 and c.x > screenW + 300) or (c.dir == -1 and c.x < -300) then
            table.remove(creatures, i)
        end
    end
end

--- 绘制深海背景
---@param vg userdata NanoVG context
---@param w number 屏幕宽
---@param h number 屏幕高
---@param gameTime number 总游戏时间
function Background.Draw(vg, w, h, gameTime)
    -- 深海渐变背景
    local c1 = Config.Colors.deepSeaTop
    local c2 = Config.Colors.deepSeaBot
    local grad = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(c1[1], c1[2], c1[3], c1[4]),
        nvgRGBA(c2[1], c2[2], c2[3], c2[4]))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 绘制远景光柱（从上方微弱射入）
    for i = 1, 3 do
        local lx = w * (0.2 + 0.3 * (i - 1)) + math.sin(gameTime * 0.3 + i) * 30
        local lAlpha = 8 + math.sin(gameTime * 0.5 + i * 1.5) * 4
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx - 20, 0)
        nvgLineTo(vg, lx + 20, 0)
        nvgLineTo(vg, lx + 60, h * 0.6)
        nvgLineTo(vg, lx - 60, h * 0.6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(100, 150, 200, math.floor(lAlpha)))
        nvgFill(vg)
    end

    -- 绘制深海生物剪影
    for _, c in ipairs(creatures) do
        Background.DrawCreature(vg, c, gameTime)
    end

    -- 绘制气泡
    for _, b in ipairs(bubbles) do
        local alpha = math.floor(b.r / Config.Background.bubbleMaxR * 60 + 20)
        nvgBeginPath(vg)
        nvgCircle(vg, b.x, b.y, b.r)
        nvgStrokeColor(vg, nvgRGBA(150, 200, 255, alpha))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 小高光
        nvgBeginPath(vg)
        nvgCircle(vg, b.x - b.r * 0.3, b.y - b.r * 0.3, b.r * 0.3)
        nvgFillColor(vg, nvgRGBA(200, 230, 255, alpha))
        nvgFill(vg)
    end
end

--- 绘制深海生物
function Background.DrawCreature(vg, c, gameTime)
    nvgSave(vg)
    nvgTranslate(vg, c.x, c.y)

    local alpha = c.alpha
    local glow = Config.Colors.creatureGlow

    if c.cType == 1 then
        -- 鱼形剪影
        local s = c.size
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, s, s * 0.4)
        nvgFillColor(vg, nvgRGBA(15, 25, 45, alpha))
        nvgFill(vg)
        -- 尾巴
        nvgBeginPath(vg)
        local tailX = -c.dir * s * 0.8
        nvgMoveTo(vg, tailX, 0)
        nvgLineTo(vg, tailX - c.dir * s * 0.5, -s * 0.3)
        nvgLineTo(vg, tailX - c.dir * s * 0.5, s * 0.3)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(15, 25, 45, alpha))
        nvgFill(vg)
        -- 荧光眼
        local eyeX = c.dir * s * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, eyeX, -s * 0.1, 3)
        nvgFillColor(vg, nvgRGBA(glow[1], glow[2], glow[3], alpha + 60))
        nvgFill(vg)

    elseif c.cType == 2 then
        -- 水母
        local s = c.size * 0.7
        local wobY = math.sin(gameTime * 2 + c.x * 0.01) * 5
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, wobY, s, s * 0.6)
        nvgFillColor(vg, nvgRGBA(glow[1], glow[2], glow[3], math.floor(alpha * 0.5)))
        nvgFill(vg)
        -- 触须
        for t = -2, 2 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, t * s * 0.3, wobY + s * 0.5)
            local ty = wobY + s * 0.5 + s * 1.2 + math.sin(gameTime * 3 + t) * 5
            nvgLineTo(vg, t * s * 0.3 + math.sin(gameTime * 2 + t) * 8, ty)
            nvgStrokeColor(vg, nvgRGBA(glow[1], glow[2], glow[3], math.floor(alpha * 0.4)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

    elseif c.cType == 3 then
        -- 大型生物（模糊巨影）
        local s = c.size * 2
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, s, s * 0.5)
        nvgFillColor(vg, nvgRGBA(10, 15, 30, math.floor(alpha * 0.6)))
        nvgFill(vg)
        -- 荧光条纹
        for j = 1, 3 do
            nvgBeginPath(vg)
            local sy = -s * 0.2 + j * s * 0.15
            nvgMoveTo(vg, -s * 0.6, sy)
            nvgLineTo(vg, s * 0.6, sy)
            nvgStrokeColor(vg, nvgRGBA(glow[1], glow[2], glow[3], math.floor(alpha * 0.3)))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end
    end

    nvgRestore(vg)
end

return Background
