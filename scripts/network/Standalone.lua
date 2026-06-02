--- 潜艇深海生存 - 单机模式（原 main.lua 逻辑封装）
--- 当 multiplayer.enabled = false 时运行此模块
--- 全触屏操作：虚拟摇杆 + 虚拟按钮 + 触摸点击

local Config = require("Config")
local Submarine = require("Submarine")
local Character = require("Character")
local CrisisManager = require("CrisisManager")
local Background = require("render.Background")
local SubHull = require("render.SubHull")
local Compartments = require("render.Compartments")
local Lighting = require("render.Lighting")
local Water = require("render.Water")
local CrewMember = require("render.CrewMember")
local HUD = require("HUD")
local Sonar = require("render.Sonar")
local ShakeEffect = require("render.ShakeEffect")
local SoundWave = require("render.SoundWave")
local ExternalView = require("render.ExternalView")
local PressureEffect = require("render.PressureEffect")
local CrisisEffects = require("render.CrisisEffects")
local AlertSystem = require("render.AlertSystem")
local AICrew = require("AICrew")
local CommandWheel = require("CommandWheel")
local MonsterManager = require("MonsterManager")
local TurretSystem = require("TurretSystem")
local Monsters = require("render.Monsters")
local TurretView = require("render.TurretView")
local PowerSystem = require("PowerSystem")
local PowerPanel = require("render.PowerPanel")
local Inventory = require("Inventory")
local Crafting = require("Crafting")
local InventoryPanel = require("render.InventoryPanel")
local GameState = require("GameState")
local PortScene = require("PortScene")
local MissionSystem = require("MissionSystem")
local PortView = require("render.PortView")
local EVASystem = require("EVASystem")
local RuinsGenerator = require("RuinsGenerator")
local EVAView = require("render.EVAView")
local TouchControls = require("TouchControls")

require "urhox-libs.UI.VirtualControls"

local Standalone = {}

-- ============================================================
-- 局部状态（原全局变量）
-- ============================================================
local vg = nil
local fontSans = -1

local sub = nil
local char = nil
local crisis = nil
local joystick = nil
local cameraX = 0
local cameraTargetX = 0
local screenW = 1280
local screenH = 720
local dpr = 1.0
local gameTime = 0
local isExternalView = false
local currentDepth = 2400
local isRepairHeld = false
local currentCrisisInfo = nil
local aiCrew = nil
local commandWheel = nil
local monsterMgr = nil
local turret = nil
local isTurretView = false
local powerSys = nil
local inventory = nil
local selectedRecipe = 1
local gameState = nil
local portScene = nil
local evaState = nil
local evaWorld = nil
local isEVAMode = false
local sonarPulseTimer = 0

-- ============================================================
-- Start
-- ============================================================
function Standalone.Start()
    SampleInitMouseMode(MM_ABSOLUTE)

    local graphics = GetGraphics()
    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()

    vg = nvgCreate(1)
    if vg == nil then
        print("[ERROR] Failed to create NanoVG context!")
        return
    end

    fontSans = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontSans == -1 then
        fontSans = nvgCreateFont(vg, "sans", "Fonts/Anonymous Pro.ttf")
    end

    gameState = GameState.Create()
    portScene = PortScene.Create()
    PortView.RefreshMissions(gameState.reputation)

    sub = Submarine.Init()
    char = Character.Create(sub)
    crisis = CrisisManager.Create()
    aiCrew = AICrew.Create(sub)
    commandWheel = CommandWheel.Create()
    monsterMgr = MonsterManager.Create()
    turret = TurretSystem.Create()
    powerSys = PowerSystem.Create()
    inventory = Inventory.Create()
    evaState = EVASystem.Create()

    local logW = screenW / dpr
    local logH = screenH / dpr
    Background.Init(logW, logH)

    VirtualControls.Initialize()
    joystick = VirtualControls.CreateJoystick({
        position = Vector2(200, -200),
        alignment = {HA_LEFT, VA_BOTTOM},
        baseRadius = 120,
        knobRadius = 50,
        moveRadius = 80,
        deadZone = 0.15,
        keyBinding = "WASD",
        opacity = 0.6,
    })

    -- 初始化触屏按钮
    TouchControls.Init()
    TouchControls.ShowDeepSea()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")

    print("[SubmarineSurvival] Standalone mode initialized (touch controls)!")
end

-- ============================================================
-- Update
-- ============================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    gameTime = gameTime + dt

    -- 重置一次性触摸动作
    TouchControls.ResetActions()

    if gameState.transition.active then
        local completed = GameState.UpdateTransition(gameState, dt)
        if completed then
            if gameState.currentScene == GameState.SCENE_DEEP_SEA then
                sub = Submarine.Init()
                char = Character.Create(sub)
                crisis = CrisisManager.Create()
                aiCrew = AICrew.Create(sub)
                monsterMgr = MonsterManager.Create()
                turret = TurretSystem.Create()
                powerSys = PowerSystem.Create()
                inventory = Inventory.Create()
                local supplies = GameState.GetSuppliesForMission(gameState)
                for id, count in pairs(supplies) do
                    if inventory.products[id] then
                        inventory.products[id] = count
                    end
                end
                isTurretView = false
                isExternalView = false
                currentDepth = 2400
                cameraX = 0
                cameraTargetX = 0
                TouchControls.ShowDeepSea()
            else
                local result = GameState.SettleMission(gameState)
                if result then
                    if result.completed then
                        PortScene.ShowMessage(portScene, "任务完成！奖励: +" .. result.rewards.gold .. "金 +" .. result.rewards.reputation .. "声望")
                    else
                        PortScene.ShowMessage(portScene, "任务未完成，下次再来！")
                    end
                end
                PortView.RefreshMissions(gameState.reputation)
                TouchControls.ShowPort()
            end
        end
        return
    end

    if gameState.currentScene == GameState.SCENE_PORT then
        HandlePortUpdate(dt)
        return
    end

    if sub == nil then return end

    if isEVAMode then
        HandleEVAUpdate(dt)
        return
    end

    -- 深海场景主循环
    local jx = 0
    if joystick then jx = joystick.x or 0 end

    local pilotMult = AICrew.GetPilotBonus(aiCrew)
    jx = jx * pilotMult
    local engineEff = PowerSystem.GetEfficiency(powerSys, "engine")
    jx = jx * engineEff

    Character.Update(char, sub, jx, dt)

    local oxygenEff = PowerSystem.GetEfficiency(powerSys, "oxygen")
    Submarine.Update(sub, dt, oxygenEff)

    -- === 触屏按钮输入 ===
    if TouchControls.actions.escape then
        GameState.ReturnToPort(gameState)
        return
    end

    if TouchControls.actions.extView and not isTurretView then
        isExternalView = not isExternalView
    end

    if TouchControls.actions.turret then
        if isTurretView then
            TurretSystem.Deactivate(turret)
            isTurretView = false
            TouchControls.ShowDeepSea()
        elseif TurretSystem.IsInTurretRoom(char) then
            TurretSystem.Activate(turret)
            isTurretView = true
            isExternalView = false
            TouchControls.ShowTurret()
        end
    end

    if TouchControls.actions.power then
        PowerSystem.TogglePanel(powerSys)
        if powerSys.isOpen then
            TouchControls.ShowPowerOverlay()
        else
            TouchControls.HidePowerOverlay()
        end
    end

    -- 电力面板操作
    if powerSys.isOpen then
        if TouchControls.actions.powerUp then PowerSystem.SelectPrev(powerSys) end
        if TouchControls.actions.powerDown then PowerSystem.SelectNext(powerSys) end
        if TouchControls.held.powerInc then PowerSystem.IncreaseSelected(powerSys, 1) end
        if TouchControls.held.powerDec then PowerSystem.DecreaseSelected(powerSys, 1) end
    end

    -- EVA出舱
    if TouchControls.actions.eva then
        if char.roomIndex == 4 then
            if EVASystem.StartEVA(evaState) then
                evaWorld = RuinsGenerator.Generate()
                isEVAMode = true
                TouchControls.ShowEVA()
            end
        end
    end

    -- 物品栏
    if TouchControls.actions.inventory then
        Inventory.TogglePanel(inventory)
        if inventory.isOpen then
            TouchControls.ShowInventoryOverlay()
        else
            TouchControls.HideInventoryOverlay()
        end
    end
    if TouchControls.actions.pickup then Inventory.PickupNearScrap(inventory) end

    if inventory.isOpen then
        if TouchControls.actions.craftPrev and not powerSys.isOpen then
            selectedRecipe = selectedRecipe - 1
            if selectedRecipe < 1 then selectedRecipe = Crafting.GetRecipeCount() end
        end
        if TouchControls.actions.craftNext and not powerSys.isOpen then
            selectedRecipe = selectedRecipe + 1
            if selectedRecipe > Crafting.GetRecipeCount() then selectedRecipe = 1 end
        end
        if TouchControls.actions.craftConfirm then Crafting.Craft(inventory, selectedRecipe) end
        if TouchControls.actions.useItem1 then Inventory.UseProduct(inventory, "ammo_pack", sub, turret, powerSys) end
        if TouchControls.actions.useItem2 then Inventory.UseProduct(inventory, "medkit", sub, turret, powerSys) end
        if TouchControls.actions.useItem3 then Inventory.UseProduct(inventory, "repair_tool", sub, turret, powerSys) end
        if TouchControls.actions.useItem4 then Inventory.UseProduct(inventory, "power_cell", sub, turret, powerSys) end
        if TouchControls.actions.useItem5 then Inventory.UseProduct(inventory, "sonar_boost", sub, turret, powerSys) end
    end

    -- 噪音触发：高速航行
    if math.abs(jx) > 0.7 then
        CrisisManager.OnHighSpeed(crisis)
    end

    -- 危机修复
    CrisisManager.Update(crisis, sub, dt, gameTime)

    local roomCrisis = CrisisManager.GetCrisisInRoom(crisis, char.roomIndex)
    if roomCrisis and Character.IsNearTarget(char, sub, roomCrisis.roomIndex, nil) then
        currentCrisisInfo = {
            canInteract = true,
            crisisType = roomCrisis.type,
            severity = roomCrisis.severity,
            isRepairing = char.isRepairing,
            progress = roomCrisis.repairProgress,
            roomName = sub.compartments[roomCrisis.roomIndex].name,
            isDiagnosing = roomCrisis.type == "equipment_malfunction" and not roomCrisis.diagnosed,
        }
        isRepairHeld = TouchControls.held.repair
        if isRepairHeld then
            if not char.isRepairing then Character.StartRepair(char, roomCrisis.type) end
            local repairDt = dt
            if Inventory.HasBuff(inventory, "repair_boost") then repairDt = dt * 2 end
            local repairing, progress, completed = CrisisManager.DoRepair(crisis, sub, roomCrisis.roomIndex, repairDt, char.role)
            if repairing then
                char.repairProgress = progress
                currentCrisisInfo.isRepairing = true
                currentCrisisInfo.progress = progress
            end
            if completed then
                Character.StopRepair(char)
                isRepairHeld = false
                ShakeEffect.TriggerImpact(0.5)
                if gameState.currentMission then
                    gameState.missionProgress.crisisRepaired = gameState.missionProgress.crisisRepaired + 1
                end
            end
        else
            if char.isRepairing then
                Character.StopRepair(char)
                CrisisManager.StopRepair(crisis, char.roomIndex)
            end
        end
    else
        currentCrisisInfo = nil
        if char.isRepairing then Character.StopRepair(char) end
        isRepairHeld = false
    end

    -- 单机模式：假设反应堆满功率100%运行
    local reactorOutput = 100
    if Inventory.HasBuff(inventory, "power_boost") then
        reactorOutput = 120
    end
    PowerSystem.Update(powerSys, dt, reactorOutput, nil)
    Inventory.Update(inventory, sub, char, dt, gameTime)
    AICrew.Update(aiCrew, sub, crisis, char, dt, gameTime)
    AICrew.UpdateDoctorHeal(aiCrew, sub, dt)
    CommandWheel.Update(commandWheel, dt)
    CrewMember.UpdateRipples(dt)
    MonsterManager.Update(monsterMgr, sub, crisis, dt, gameTime)

    if isTurretView then
        local logW = screenW / dpr
        local logH = screenH / dpr
        local mx = input.mousePosition.x / dpr
        local my = input.mousePosition.y / dpr
        TurretSystem.UpdateAim(turret, mx / logW, my / logH)
        local turretEff = PowerSystem.GetEfficiency(powerSys, "turret")
        turret.fireCooldown = 0.8 / math.max(0.2, turretEff)
        TurretSystem.Update(turret, monsterMgr, dt, gameTime)
    end

    CrisisEffects.UpdateSparks(dt)
    if char.isRepairing and char.repairType == "breach" then
        local comp = sub.compartments[char.roomIndex]
        if comp then
            CrisisEffects.EmitSparks(char.x, Config.Sub.hullHeight * 0.5, gameTime)
        end
    end

    local logW = screenW / dpr
    cameraTargetX = char.x - logW * 0.4
    local totalW = Submarine.GetTotalWidth(sub)
    cameraTargetX = math.max(0, math.min(totalW - logW * 0.7, cameraTargetX))
    cameraX = cameraX + (cameraTargetX - cameraX) * math.min(1, dt * 4)

    local logH = screenH / dpr
    Background.Update(dt, logW, logH, gameTime)

    local sonarEff = PowerSystem.GetEfficiency(powerSys, "sonar")
    local sonarMult = sonarEff
    if Inventory.HasBuff(inventory, "sonar_boost") then sonarMult = sonarMult * 2.0 end
    Sonar.Update(dt * sonarMult, gameTime)

    -- 声呐脉冲检测（与 Sonar 内部 3s 间隔同步）
    sonarPulseTimer = sonarPulseTimer + dt * sonarMult
    if sonarPulseTimer >= 3.0 then
        sonarPulseTimer = sonarPulseTimer - 3.0
        CrisisManager.OnSonarPulse(crisis)
    end

    local moveSpeed = math.abs(jx)
    ShakeEffect.SetMoveShake(moveSpeed)
    ShakeEffect.Update(dt, gameTime)
    SoundWave.Update(dt, gameTime)

    currentDepth = 2400 + math.sin(gameTime * 0.05) * 300 + gameTime * 0.5
    PressureEffect.Update(dt, currentDepth)

    if gameState.currentMission then
        gameState.missionProgress.timeElapsed = gameState.missionProgress.timeElapsed + dt
        gameState.missionProgress.depthReached = math.max(gameState.missionProgress.depthReached, currentDepth)
        gameState.missionProgress.kills = monsterMgr.totalKills
        gameState.missionProgress.scrapsCollected = inventory.totalCollected or 0
    end
end

-- ============================================================
-- 港口更新（触屏交互 - 通过 HandlePortInteraction 处理点击）
-- ============================================================
function HandlePortUpdate(dt)
    PortScene.Update(portScene, dt)
    -- 港口场景所有交互通过 HandlePortInteraction() 处理点击事件
    -- 不再需要键盘输入
end

-- ============================================================
-- EVA更新
-- ============================================================
function HandleEVAUpdate(dt)
    if evaState.phase == "suiting" or evaState.phase == "returning" then
        EVASystem.Update(evaState, 0, 0, dt)
        if evaState.phase == "idle" and not evaState.isActive then
            isEVAMode = false
            local loot = EVASystem.GetCollectedLoot(evaState)
            local totalValue = 0
            for _, item in ipairs(loot) do totalValue = totalValue + item.value end
            if totalValue > 0 then
                gameState.gold = gameState.gold + totalValue
            end
            TouchControls.ShowDeepSea()
        end
        return
    end

    if evaState.phase == "idle" and not evaState.isActive then
        isEVAMode = false
        local loot = EVASystem.GetCollectedLoot(evaState)
        local totalValue = 0
        for _, item in ipairs(loot) do totalValue = totalValue + item.value end
        if totalValue > 0 then gameState.gold = gameState.gold + totalValue end
        TouchControls.ShowDeepSea()
        return
    end

    -- 摇杆双轴输入（触屏自然支持2D摇杆）
    local jx, jy = 0, 0
    if joystick then
        jx = joystick.x or 0
        jy = joystick.y or 0
    end

    EVASystem.Update(evaState, jx, jy, dt)
    if evaWorld then EVASystem.CheckNearLoot(evaState, evaWorld.loots) end

    if TouchControls.actions.pickup then EVASystem.PickupLoot(evaState) end
    if TouchControls.actions.evaReturn then
        if EVASystem.IsNearDock(evaState) then EVASystem.EndEVA(evaState) end
    end
    if TouchControls.actions.escape then
        evaState.phase = "idle"
        evaState.isActive = false
        isEVAMode = false
        local loot = EVASystem.GetCollectedLoot(evaState)
        local totalValue = 0
        for _, item in ipairs(loot) do totalValue = totalValue + item.value end
        if totalValue > 0 then gameState.gold = gameState.gold + totalValue end
        TouchControls.ShowDeepSea()
    end
end

-- ============================================================
-- 渲染
-- ============================================================
function HandleNanoVGRender(eventType, eventData)
    if vg == nil then return end

    local graphics = GetGraphics()
    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()

    local w = screenW / dpr
    local h = screenH / dpr

    nvgBeginFrame(vg, w, h, dpr)

    if gameState.currentScene == GameState.SCENE_PORT then
        PortView.Draw(vg, w, h, portScene, gameState, gameTime)
        -- 绘制港口触摸提示（替代键盘提示）
        DrawPortTouchHints(w, h)
    elseif isEVAMode and evaState then
        if evaState.phase == "suiting" or evaState.phase == "returning" then
            EVAView.DrawSuitingPhase(vg, w, h, evaState, gameTime)
        else
            EVAView.Draw(vg, w, h, evaState, evaWorld, gameTime, 1.0 / 60.0)
        end
    elseif sub ~= nil then
        HandleDeepSeaRender(w, h)
    end

    local transAlpha = GameState.GetTransitionAlpha(gameState)
    PortView.DrawTransition(vg, w, h, transAlpha)

    nvgEndFrame(vg)
end

function HandleDeepSeaRender(w, h)
    if isTurretView then
        TurretView.Draw(vg, w, h, turret, monsterMgr, gameTime)
        -- 炮塔模式触摸提示
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, w * 0.5, h - 20, "点击屏幕射击 | 左上角[返回]退出炮塔", nil)
    elseif isExternalView then
        ExternalView.Draw(vg, w, h, sub, gameTime)
        local visibleMonsters = MonsterManager.GetVisibleMonsters(monsterMgr)
        if #visibleMonsters > 0 then Monsters.DrawExternal(vg, visibleMonsters, w, h, gameTime) end
        SoundWave.Draw(vg, w, h, gameTime)
        PressureEffect.Draw(vg, w, h, gameTime)
        DrawExternalHUD(w, h)
    else
        local shakeX, shakeY = ShakeEffect.GetOffset()
        Background.Draw(vg, w, h, gameTime)

        nvgSave(vg)
        nvgTranslate(vg, -cameraX + shakeX, shakeY)

        local thick = Config.Sub.hullThickness
        local subTotalW = Submarine.GetTotalWidth(sub) + thick * 2 + 60
        local subH = Config.Sub.hullHeight + thick * 2
        local subX = 30
        local subY = h * 0.5 - subH * 0.5

        SubHull.Draw(vg, subX, subY, subTotalW - 60, subH, gameTime, sub)

        local dentData = MonsterManager.GetHullDent(monsterMgr)
        if dentData then Monsters.DrawHullDent(vg, subX, subY, subTotalW - 60, subH, dentData, gameTime) end

        local innerX = subX + thick
        local innerY = subY + thick
        local innerH = subH - thick * 2

        Compartments.Draw(vg, innerX, innerY, innerH, sub, gameTime)
        DrawSonarOverlay(innerX, innerY, innerH)
        Water.Draw(vg, innerX, innerY, innerH, sub, gameTime)
        Lighting.Draw(vg, innerX, innerY, innerH, sub, gameTime)
        InventoryPanel.DrawScraps(vg, inventory, innerX, innerY, innerH, gameTime)

        CrewMember.Draw(vg, char, innerX, innerY, innerH, gameTime)
        for _, ai in ipairs(aiCrew.members) do
            CrewMember.DrawAI(vg, ai, innerX, innerY, innerH, gameTime)
        end
        CrewMember.DrawRipples(vg)

        local activeCrises = CrisisManager.GetActiveCrises(crisis)
        for _, c in ipairs(activeCrises) do
            local comp = sub.compartments[c.roomIndex]
            if comp then
                local compX = innerX + comp.x
                local compY = innerY
                local compW = comp.width
                local compH = innerH
                -- 各类危机房间效果
                if c.type == "overheat" then
                    CrisisEffects.DrawOverheatRoom(vg, compX, compY, compW, compH, gameTime, c.temperature)
                elseif c.type == "fire" then
                    AlertSystem.DrawFireOverlay(vg, compX, compY, compW, compH, c.intensity or 0.5, gameTime)
                elseif c.type == "toxic_gas" then
                    AlertSystem.DrawGasOverlay(vg, compX, compY, compW, compH, c.concentration or 0.5, gameTime)
                elseif c.type == "power_failure" then
                    CrisisEffects.DrawPowerFailureRoom(vg, compX, compY, compW, compH, gameTime)
                elseif c.type == "monster_invasion" then
                    CrisisEffects.DrawMonsterInvasion(vg, compX, compY, compW, compH, gameTime, c.monsterHp or 1.0)
                end
                -- 修理中效果
                if c.isBeingRepaired and c.type ~= "breach" then
                    CrisisEffects.DrawOperateEffect(vg, compX + compW * 0.5, compY + compH * 0.6, c.type, gameTime)
                end
            end
        end
        CrisisEffects.DrawSparks(vg)

        -- 疯狂效果
        local madness = CrisisManager.GetMadnessEffect(crisis)
        if madness and madness.severity then
            AlertSystem.DrawMadnessEffect(vg, w, h, madness.severity, gameTime)
        end

        if char.isRepairing and currentCrisisInfo then
            local charScreenX = char.x
            local charTopY = innerY + innerH - Config.Crew.height - 12
            local isDiagnosing = currentCrisisInfo.crisisType == "equipment_malfunction"
                and (currentCrisisInfo.progress or 0) < 0.3
            CrisisEffects.DrawProgressBar(vg, charScreenX, charTopY, currentCrisisInfo.progress, currentCrisisInfo.crisisType, isDiagnosing)
        end

        nvgRestore(vg)

        -- 边缘警报（使用 AlertSystem 替代旧版）
        AlertSystem.DrawEdgeAlert(vg, w, h, activeCrises, gameTime, false)
        SoundWave.Draw(vg, w, h, gameTime)
        PressureEffect.Draw(vg, w, h, gameTime)
        ShakeEffect.DrawFlash(vg, w, h)
        AlertSystem.DrawAlertBanners(vg, w, h, activeCrises, gameTime, false)
        HUD.Draw(vg, w, h, sub, gameTime, currentCrisisInfo)
        PowerPanel.DrawMini(vg, powerSys, w, h, gameTime)
        PowerPanel.DrawFull(vg, powerSys, w, h, gameTime)
        InventoryPanel.DrawQuickBar(vg, inventory, w, h, gameTime)
        InventoryPanel.DrawPickupHint(vg, inventory, w, h, gameTime)
        InventoryPanel.DrawFull(vg, inventory, w, h, gameTime, selectedRecipe)
        InventoryPanel.DrawMessage(vg, inventory, w, h)
        InventoryPanel.DrawBuffs(vg, inventory, w, h, gameTime)
        CommandWheel.Draw(vg, commandWheel, gameTime)
        DrawRoomIndicator(w, h)
        DrawDepthIndicator(w, h)
        if gameState.currentMission then DrawMissionHUD(w, h) end
    end
end

-- ============================================================
-- HUD辅助绘制
-- ============================================================
function DrawMissionHUD(w, h)
    local mission = gameState.currentMission
    if not mission then return end
    local hudX, hudY, hudW = 15, 85, 180
    nvgBeginPath(vg)
    nvgRoundedRect(vg, hudX, hudY, hudW, 16 + #mission.objectives * 16, 4)
    nvgFillColor(vg, nvgRGBA(10, 20, 40, 180))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgText(vg, hudX + 5, hudY + 3, "任务: " .. mission.title, nil)
    for i, obj in ipairs(mission.objectives) do
        local prog = MissionSystem.GetObjectiveProgress(obj, gameState.missionProgress)
        local oy = hudY + 3 + i * 14
        nvgFontSize(vg, 9)
        if prog >= 1.0 then
            nvgFillColor(vg, nvgRGBA(100, 220, 100, 220))
            nvgText(vg, hudX + 8, oy, "✓ " .. MissionSystem.GetObjectiveText(obj), nil)
        else
            nvgFillColor(vg, nvgRGBA(160, 180, 200, 180))
            nvgText(vg, hudX + 8, oy, "· " .. MissionSystem.GetObjectiveText(obj) .. string.format(" (%.0f%%)", prog * 100), nil)
        end
    end
end

function DrawSonarOverlay(innerX, innerY, innerH)
    local bridgeComp = sub.compartments[1]
    if not bridgeComp then return end
    local equipCount = #bridgeComp.equipment
    local sonarIdx = 2
    if sonarIdx > equipCount then return end
    local cx = innerX + bridgeComp.x
    local cw = bridgeComp.width
    local floorY = innerY + innerH - 8
    local ex = cx + cw * (sonarIdx / (equipCount + 1))
    local ey = floorY - 45
    Sonar.DrawEnhanced(vg, ex, ey, 25, gameTime)
    local sonarData = MonsterManager.GetSonarData(monsterMgr)
    if #sonarData > 0 then Monsters.DrawSonarDots(vg, ex, ey, 25, sonarData, gameTime) end
end

function DrawRoomIndicator(w, h)
    if char == nil or sub == nil then return end
    local comp = sub.compartments[char.roomIndex]
    if comp then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(180, 200, 220, 160))
        nvgText(vg, w * 0.5, h - 95, "[ " .. comp.name .. " ]", nil)
        if char.roomIndex == 4 then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(100, 200, 255, math.floor(130 + math.sin(gameTime * 2) * 40)))
            nvgText(vg, w * 0.5, h - 78, "按[出舱]按钮穿潜水服探索", nil)
        end
    end
end

function DrawDepthIndicator(w, h)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(80, 160, 200, 150))
    nvgText(vg, w - 20, 60, string.format("DEPTH: %dm", math.floor(currentDepth)), nil)
    if currentDepth > 3500 then
        local warnAlpha = math.floor(120 + math.sin(gameTime * 4) * 80)
        nvgFillColor(vg, nvgRGBA(240, 100, 50, warnAlpha))
        nvgText(vg, w - 20, 75, "! HIGH PRESSURE !", nil)
    end
end

function DrawExternalHUD(w, h)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(150, 200, 230, 200))
    nvgText(vg, w * 0.5, 15, "[ 外部视角 ]", nil)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(100, 170, 210, 180))
    nvgText(vg, 15, h - 15, string.format("DEPTH: %dm  |  HULL: %.0f%%  |  O2: %.0f%%",
        math.floor(currentDepth), sub.hull, sub.oxygen), nil)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 150))
    nvgText(vg, w - 15, 35, "按[外视]按钮返回", nil)
end

-- ============================================================
-- 港口触摸提示（替代原来的键盘提示）
-- ============================================================
function DrawPortTouchHints(w, h)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(150, 180, 210, 160))
    nvgText(vg, w * 0.5, h - 10, "点击标签切换 · 点击列表项选中 · 点击出港按钮开始", nil)

    -- 判断当前按钮应显示什么
    local hasMission = (gameState.currentMission ~= nil)
    local isDepart = (portScene.currentTab == PortScene.TAB_DEPART)

    -- 右侧主按钮
    local btnW, btnH = 80, 36
    local btnX = w - 50 - btnW * 0.5
    local btnY = h - 55

    if isDepart then
        -- 出港标签页 → 显示出港按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX - btnW * 0.5, btnY - btnH * 0.5, btnW, btnH, 6)
        if hasMission then
            local pulse = 0.7 + math.sin(gameTime * 3) * 0.3
            nvgFillColor(vg, nvgRGBA(20, math.floor(140 * pulse), math.floor(200 * pulse), 240))
        else
            nvgFillColor(vg, nvgRGBA(60, 60, 70, 180))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 255, hasMission and 240 or 60))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if hasMission then
            nvgFillColor(vg, nvgRGBA(240, 255, 255, 255))
            nvgText(vg, btnX, btnY, "出港", nil)
        else
            nvgFillColor(vg, nvgRGBA(120, 120, 130, 180))
            nvgText(vg, btnX, btnY, "需接任务", nil)
        end
    elseif hasMission then
        -- 非出港标签页但已有任务 → 显示出港快捷按钮（高亮提醒）
        local pulse = 0.7 + math.sin(gameTime * 3) * 0.3
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX - btnW * 0.5, btnY - btnH * 0.5, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(20, math.floor(140 * pulse), math.floor(200 * pulse), 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 200, 255, 240))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 255, 255, 255))
        nvgText(vg, btnX, btnY, "出港", nil)
    else
        -- 没有任务，显示确认按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX - btnW * 0.5, btnY - btnH * 0.5, btnW, btnH, 6)
        nvgFillColor(vg, nvgRGBA(40, 120, 180, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 250, 255, 255))
        nvgText(vg, btnX, btnY, "确认", nil)
    end

    -- 放弃任务按钮（如果有当前任务）
    if hasMission then
        local abX = 80
        local abY = h - 55
        nvgBeginPath(vg)
        nvgRoundedRect(vg, abX - 35, abY - 16, 70, 32, 5)
        nvgFillColor(vg, nvgRGBA(140, 50, 50, 200))
        nvgFill(vg)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
        nvgText(vg, abX, abY, "放弃任务", nil)
    end
end

-- ============================================================
-- 触摸/点击输入
-- ============================================================
function HandleTouchEnd(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    HandleInteraction(x / dpr, y / dpr)
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        HandleInteraction(input.mousePosition.x / dpr, input.mousePosition.y / dpr)
    end
end

function HandleInteraction(screenX, screenY)
    -- 港口场景触摸交互
    if gameState.currentScene == GameState.SCENE_PORT then
        HandlePortInteraction(screenX, screenY)
        return
    end

    -- 炮塔模式：点击即射击
    if isTurretView then
        local accBonus = AICrew.GetTurretAccuracyBonus(aiCrew)
        TurretSystem.Fire(turret, accBonus)
        return
    end
    if isExternalView then return end

    -- 指令轮
    if commandWheel.visible then
        local cmdId, aiIdx = CommandWheel.HandleClick(commandWheel, screenX, screenY)
        if cmdId and aiIdx then AICrew.SetCommand(aiCrew, aiIdx, cmdId) end
        return
    end

    -- 点击AI船员显示指令轮
    local worldX = screenX + cameraX
    local thick = Config.Sub.hullThickness
    local innerX = 30 + thick
    local subH = Config.Sub.hullHeight + thick * 2
    local subY = (screenH / dpr) * 0.5 - subH * 0.5
    local innerY = subY + thick
    local innerH = subH - thick * 2
    local localX = worldX - innerX
    local hitIdx = AICrew.HitTest(aiCrew, localX, screenY, innerY, innerH)
    if hitIdx then
        local ai = aiCrew.members[hitIdx]
        local aiScreenX = innerX + ai.x - cameraX
        local aiScreenY = innerY + innerH - 8 - Config.Crew.height * 0.5
        CommandWheel.Show(commandWheel, aiScreenX, aiScreenY, hitIdx, ai.name)
        return
    end

    -- 点击舱室移动角色
    if screenY >= subY and screenY <= subY + subH then
        for _, comp in ipairs(sub.compartments) do
            local cx = innerX + comp.x
            if worldX >= cx and worldX < cx + comp.width then
                local targetX = comp.x + comp.width * 0.5
                if math.abs(char.x - targetX) > 30 then
                    char.facing = (targetX > char.x) and 1 or -1
                end
                break
            end
        end
    end
end

-- ============================================================
-- 港口场景触摸交互（取代键盘操作）
-- ============================================================
function HandlePortInteraction(screenX, screenY)
    local w = screenW / dpr
    local h = screenH / dpr

    -- 1. 检测标签栏点击
    local tabW = (w - 80) / 4
    local tabY = 75
    local tabH = 32
    if screenY >= tabY and screenY <= tabY + tabH then
        for i = 1, 4 do
            local tx = 30 + (i - 1) * (tabW + 8)
            if screenX >= tx and screenX <= tx + tabW then
                PortScene.SwitchTab(portScene, i)
                return
            end
        end
    end

    -- 2. 检测右侧主按钮点击（确认/出港按钮）
    local btnW, btnH = 80, 36
    local btnX = w - 50 - btnW * 0.5
    local btnY = h - 55
    if screenX >= btnX - btnW * 0.5 and screenX <= btnX + btnW * 0.5
       and screenY >= btnY - btnH * 0.5 and screenY <= btnY + btnH * 0.5 then
        -- 已有任务时，此按钮为"出港"，直接执行出港
        if gameState.currentMission then
            local ok, err = GameState.Depart(gameState)
            if not ok then PortScene.ShowMessage(portScene, err) end
        else
            -- 没任务时按确认逻辑
            HandlePortConfirm()
        end
        return
    end

    -- 3. 检测放弃任务按钮
    if gameState.currentMission then
        local abX = 80
        local abY = h - 55
        if screenX >= abX - 35 and screenX <= abX + 35 and screenY >= abY - 16 and screenY <= abY + 16 then
            PortScene.ShowMessage(portScene, "已放弃任务: " .. gameState.currentMission.title)
            gameState.currentMission = nil
            return
        end
    end

    -- 4. 检测出港标签页大按钮点击（位于面板中央）
    if portScene.currentTab == PortScene.TAB_DEPART then
        local panelY2 = 120
        local panelH2 = h - panelY2 - 60
        local cx = w * 0.5
        local cy = panelY2 + panelH2 * 0.5
        local departBtnW = 160
        local departBtnH = 40
        local departBtnY = cy + 70
        if screenX >= cx - departBtnW / 2 and screenX <= cx + departBtnW / 2
           and screenY >= departBtnY and screenY <= departBtnY + departBtnH then
            HandlePortConfirm()
            return
        end
    end

    -- 5. 检测列表项点击（双击确认：已选中再次点击 = 确认）
    if portScene.currentTab ~= PortScene.TAB_DEPART then
        local panelY = 120
        local panelH = h - panelY - 60
        if screenX >= 30 and screenX <= w - 30 and screenY >= panelY and screenY <= panelY + panelH then
            -- 计算点击了哪个列表项
            local itemCount = GetPortItemCount()
            if itemCount > 0 then
                local startY = panelY + (gameState.currentMission and 30 or 12)
                local itemH = 70  -- ITEM_HEIGHT_FIXED，与 PortView 一致
                local currentScroll = PortView.GetScrollOffset()
                local clickedIdx = math.floor((screenY - startY + currentScroll) / itemH) + 1
                if clickedIdx >= 1 and clickedIdx <= itemCount then
                    if portScene.selectedItem == clickedIdx then
                        -- 已选中的项被再次点击 → 执行确认操作
                        HandlePortConfirm()
                    else
                        portScene.selectedItem = clickedIdx
                    end
                end
            end
        end
    end
end

--- 港口确认操作
function HandlePortConfirm()
    if portScene.currentTab == PortScene.TAB_MISSION then
        local missions = PortView.GetMissions()
        if missions and missions[portScene.selectedItem] then
            if gameState.currentMission then
                PortScene.ShowMessage(portScene, "已有进行中的任务，先完成或放弃！")
            else
                gameState.currentMission = missions[portScene.selectedItem]
                PortScene.ShowMessage(portScene, "接取任务: " .. gameState.currentMission.title)
                -- 接取任务后自动切换到出港标签页
                PortScene.SwitchTab(portScene, PortScene.TAB_DEPART)
            end
        end
    elseif portScene.currentTab == PortScene.TAB_SHOP then
        PortScene.BuyItem(portScene, gameState)
    elseif portScene.currentTab == PortScene.TAB_UPGRADE then
        PortScene.UpgradeSub(portScene, gameState)
    elseif portScene.currentTab == PortScene.TAB_DEPART then
        local ok, err = GameState.Depart(gameState)
        if not ok then PortScene.ShowMessage(portScene, err) end
    end
end

--- 获取当前标签页列表项数量
function GetPortItemCount()
    if portScene.currentTab == PortScene.TAB_MISSION then
        local missions = PortView.GetMissions()
        return missions and #missions or 0
    elseif portScene.currentTab == PortScene.TAB_SHOP then
        return #PortScene.SHOP_ITEMS
    elseif portScene.currentTab == PortScene.TAB_UPGRADE then
        return #PortScene.UPGRADES
    else
        return 0
    end
end

-- ============================================================
-- Stop
-- ============================================================
function Standalone.Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
    TouchControls.Clear()
    VirtualControls.Shutdown()
    print("[SubmarineSurvival] Standalone stopped.")
end

return Standalone
