--- 船体震动效果：移动微颤 + 撞击剧烈抖动 + 红色闪烁
local ShakeEffect = {}

-- 震动状态
local shakeState = {
    -- 当前偏移
    offsetX = 0,
    offsetY = 0,

    -- 移动微颤
    moveShake = 0,          -- 移动震动强度
    moveFreq = 12,          -- 微颤频率

    -- 撞击震动
    impactIntensity = 0,    -- 撞击强度（自动衰减）
    impactDecay = 4.0,      -- 衰减速度
    impactFreq = 25,        -- 撞击频率（更高频）

    -- 红色闪烁
    flashAlpha = 0,         -- 红色闪烁透明度
    flashDecay = 5.0,       -- 闪烁衰减

    -- 时间
    time = 0,
}

--- 触发撞击震动
---@param intensity number 强度 0.5~5.0
function ShakeEffect.TriggerImpact(intensity)
    shakeState.impactIntensity = math.max(shakeState.impactIntensity, intensity or 2.0)
    shakeState.flashAlpha = math.min(255, math.floor(intensity * 80))
end

--- 设置移动震动（持续性，与速度成正比）
---@param speed number 0~1 移动速度归一化
function ShakeEffect.SetMoveShake(speed)
    shakeState.moveShake = speed
end

--- 更新震动状态
---@param dt number
---@param gameTime number
function ShakeEffect.Update(dt, gameTime)
    shakeState.time = gameTime

    -- 衰减撞击震动
    if shakeState.impactIntensity > 0 then
        shakeState.impactIntensity = shakeState.impactIntensity - shakeState.impactDecay * dt
        if shakeState.impactIntensity < 0.01 then
            shakeState.impactIntensity = 0
        end
    end

    -- 衰减红色闪烁
    if shakeState.flashAlpha > 0 then
        shakeState.flashAlpha = shakeState.flashAlpha - shakeState.flashDecay * dt * 60
        if shakeState.flashAlpha < 0 then
            shakeState.flashAlpha = 0
        end
    end

    -- 计算最终偏移
    local t = gameTime
    local ox, oy = 0, 0

    -- 移动微颤
    if shakeState.moveShake > 0.1 then
        local mIntensity = shakeState.moveShake * 1.5
        ox = ox + math.sin(t * shakeState.moveFreq) * mIntensity
        oy = oy + math.cos(t * shakeState.moveFreq * 1.3) * mIntensity * 0.6
    end

    -- 撞击震动（高频随机性更强）
    if shakeState.impactIntensity > 0 then
        local iIntensity = shakeState.impactIntensity * 5.0
        ox = ox + math.sin(t * shakeState.impactFreq + 1.7) * iIntensity
                * (0.5 + math.sin(t * 37) * 0.5)
        oy = oy + math.cos(t * shakeState.impactFreq * 1.1 + 0.3) * iIntensity
                * (0.5 + math.cos(t * 29) * 0.5)
    end

    shakeState.offsetX = ox
    shakeState.offsetY = oy
end

--- 获取当前震动偏移
---@return number, number
function ShakeEffect.GetOffset()
    return shakeState.offsetX, shakeState.offsetY
end

--- 获取红色闪烁透明度（用于屏幕红色叠加）
---@return number 0~255
function ShakeEffect.GetFlashAlpha()
    return math.floor(math.max(0, shakeState.flashAlpha))
end

--- 绘制红色闪烁效果（全屏叠加）
---@param vg userdata
---@param w number 屏幕宽度
---@param h number 屏幕高度
function ShakeEffect.DrawFlash(vg, w, h)
    local alpha = ShakeEffect.GetFlashAlpha()
    if alpha > 2 then
        -- 边缘红色（径向渐变，中心透明）
        local edgeGrad = nvgRadialGradient(vg, w * 0.5, h * 0.5,
            w * 0.3, w * 0.7,
            nvgRGBA(200, 20, 20, 0),
            nvgRGBA(200, 20, 20, alpha))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, edgeGrad)
        nvgFill(vg)
    end
end

return ShakeEffect
