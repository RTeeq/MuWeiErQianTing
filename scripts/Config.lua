---@meta
--- 潜艇深海生存游戏 - 全局配置
local Config = {}

-- ============================================================
-- 颜色定义（深海科幻工业风）
-- ============================================================
Config.Colors = {
    -- 深海背景
    deepSeaTop    = {8, 20, 40, 255},       -- 深蓝
    deepSeaBot    = {2, 5, 12, 255},        -- 近黑
    seawater      = {20, 80, 140, 120},     -- 半透明海水

    -- 潜艇外壳
    hullOuter     = {60, 65, 72, 255},      -- 深灰金属
    hullInner     = {45, 48, 55, 255},      -- 内壳暗灰
    hullHighlight = {90, 95, 105, 255},     -- 高光
    rivet         = {100, 105, 115, 255},   -- 铆钉

    -- 舱室
    floorColor    = {35, 38, 45, 255},      -- 地板深灰
    wallColor     = {50, 55, 62, 255},      -- 墙壁
    ceilingColor  = {40, 43, 52, 255},      -- 天花板
    doorColor     = {70, 75, 85, 255},      -- 门
    doorFrame     = {85, 90, 100, 255},     -- 门框
    doorSliding   = {80, 85, 95, 255},      -- 滑动门板

    -- 灯光
    lightNormal   = {255, 240, 200, 180},   -- 暖黄顶灯
    lightEmergency= {200, 30, 30, 150},     -- 红色应急灯
    darkness      = {5, 5, 10, 200},        -- 黑暗遮罩

    -- 水
    waterSurface  = {30, 120, 200, 160},    -- 水面
    waterDeep     = {15, 60, 120, 180},     -- 深水
    bubble        = {150, 200, 255, 100},   -- 气泡

    -- 角色
    crewBody      = {220, 200, 170, 255},   -- 肤色
    crewSuit      = {50, 80, 130, 255},     -- 工作服蓝
    crewHelmet    = {180, 185, 195, 255},   -- 头盔银

    -- HUD
    hudBg         = {10, 15, 25, 200},      -- HUD底色
    hudBorder     = {60, 130, 180, 255},    -- HUD边框（科幻蓝）
    hudOxygen     = {50, 160, 220, 255},    -- 氧气条蓝
    hudHull       = {60, 200, 100, 255},    -- 船体条绿
    hudPower      = {240, 200, 50, 255},    -- 电力条黄
    hudDepth      = {200, 210, 230, 255},   -- 深度条白
    hudText       = {200, 210, 230, 255},   -- 文字颜色

    -- 设备
    equipActive   = {50, 200, 100, 255},    -- 设备运行绿
    equipInactive = {120, 120, 130, 255},   -- 设备关闭灰
    equipWarning  = {240, 60, 60, 255},     -- 设备警告红

    -- 生物/怪物
    creatureGlow  = {80, 220, 180, 100},    -- 荧光绿
    creatureDark  = {20, 30, 50, 200},      -- 深色剪影
}

-- ============================================================
-- 潜艇尺寸（设计坐标，与屏幕逻辑像素对应）
-- ============================================================
Config.Sub = {
    -- 总体
    totalWidth   = 1900,        -- 潜艇总内部宽度（8舱室加宽）
    hullHeight   = 300,         -- 船体内部高度（对应3m）
    hullThickness = 12,         -- 外壳厚度
    hullRadius   = 30,          -- 外壳圆角
    hullY        = 0,           -- 船体中心Y（运行时根据屏幕计算）

    -- 舱室（8个）
    compartmentCount = 8,
    compartments = {
        {id = "bridge",      name = "驾驶舱",     width = 220, equipment = {"helm", "sonar"}},
        {id = "reactor",     name = "反应堆舱",   width = 260, equipment = {"reactor"}},
        {id = "engine",      name = "引擎舱",     width = 240, equipment = {"engine"}},
        {id = "cargo",       name = "货舱",       width = 230, equipment = {"crate", "crate2"}},
        {id = "medical",     name = "医疗舱",     width = 240, equipment = {"medbed", "cabinet"}},
        {id = "turret_upper",name = "炮塔舱(上)", width = 240, equipment = {"turret"}},
        {id = "turret_lower",name = "炮塔舱(下)", width = 230, equipment = {"turret_bottom"}},
        {id = "airlock",     name = "气闸舱",     width = 240, equipment = {"airlock_hatch", "suit_rack"}},
    },

    -- 门（滑动金属门）
    doorWidth    = 20,
    doorHeight   = 160,
    doorSlideSpeed = 120,       -- 门滑动速度（像素/秒）

    -- 门类型定义（每两个舱室之间的门）
    -- 索引对应：doors[1] = 舱室1和2之间, doors[2] = 舱室2和3之间, ...
    doors = {
        {type = "normal",   id = "door_1_2"},  -- 驾驶-反应堆
        {type = "normal",   id = "door_2_3"},  -- 反应堆-引擎
        {type = "normal",   id = "door_3_4"},  -- 引擎-货舱
        {type = "safety",   id = "door_4_5"},  -- 货舱-医疗（安全门）
        {type = "normal",   id = "door_5_6"},  -- 医疗-炮塔上
        {type = "normal",   id = "door_6_7"},  -- 炮塔上-炮塔下
        {type = "airlock",  id = "door_7_8"},  -- 炮塔下-气闸（气闸内门）
    },

    -- 维修舱口（天花板/地板小门）
    hatches = {
        {room = 3, position = "ceiling", id = "hatch_engine_top"},    -- 引擎舱天花板
        {room = 7, position = "floor",   id = "hatch_turret_bottom"}, -- 炮塔下地板
    },

    -- 舷窗配置（每个舱室的舷窗）
    portholes = {
        {room = 1, xOffset = 0.7},   -- 驾驶舱前窗
        {room = 2, xOffset = 0.5},   -- 反应堆舱
        {room = 4, xOffset = 0.3},   -- 货舱
        {room = 4, xOffset = 0.7},   -- 货舱（第二个）
        {room = 5, xOffset = 0.5},   -- 医疗舱
        {room = 6, xOffset = 0.8},   -- 炮塔上
        {room = 7, xOffset = 0.2},   -- 炮塔下
        {room = 8, xOffset = 0.5},   -- 气闸舱
    },
    portholeRadius = 18,
    portholeCount  = 6,             -- 舷窗数量

    -- 梯子/天花板管道（可攀爬）
    ladderWidth  = 16,
    pipeGrabHeight = 30,        -- 天花板管道可抓取高度范围
}

-- ============================================================
-- 门交互参数
-- ============================================================
Config.Door = {
    interactRange   = 40,           -- 交互范围（像素，约0.4m）
    openTime        = 2.0,          -- 开门动画时间（秒）
    closeTime       = 1.0,          -- 关门动画时间（秒）
    pressureBalanceTime = 5.0,      -- 手动气压平衡时间（秒）
    pressureTolerance = 10,         -- 气压差容忍度（%以内可开门）
    highlightColor  = {100, 200, 255, 180},  -- 高亮颜色

    -- 门类型特性
    types = {
        normal  = { canLock = false, color = {70, 75, 85, 255} },
        safety  = { canLock = true,  color = {180, 60, 60, 255} },     -- 红色安全门
        airlock = { canLock = true,  color = {60, 140, 180, 255} },    -- 蓝色气闸门
    },

    -- 维修舱口
    hatchOpenTime   = 1.5,          -- 舱口打开时间
    hatchSize       = 50,           -- 舱口尺寸（像素）
}

-- ============================================================
-- 气压系统参数
-- ============================================================
Config.Pressure = {
    standard        = 100,          -- 标准气压（100%）
    vacuum          = 0,            -- 真空

    -- 气压变化速率
    breachDrainRate = 8,            -- 破洞时气压下降速率（%/秒）
    balanceRate     = 20,           -- 手动平衡时气压变化速率（%/秒）
    doorFlowRate    = 15,           -- 开门时气压自然流通速率（%/秒）

    -- 效果阈值
    warningThreshold = 70,          -- 气压警告阈值（%）
    dangerThreshold  = 50,          -- 气压危险阈值（移动变慢+屏幕变暗）
    lethalThreshold  = 5,           -- 致命阈值（窒息）

    -- 移动惩罚
    lowPressureSpeedMult = 0.5,     -- 低气压时移动速度倍率
    suffocationDamage = 10,         -- 窒息时每秒氧气消耗

    -- 视觉效果
    darkenAlpha     = 160,          -- 低气压屏幕变暗透明度
    darkenColor     = {5, 0, 15, 160},  -- 变暗颜色（紫黑）
}

-- ============================================================
-- 水泵参数
-- ============================================================
Config.WaterPump = {
    -- 有水泵的舱室
    rooms = {3, 4},                 -- 引擎舱、货舱有水泵
    pumpRate        = 0.05,         -- 排水速率（水位/秒）
    powerCost       = 2,            -- 每秒耗电
    activateRange   = 50,           -- 操作范围（像素）
}

-- ============================================================
-- 舷窗参数
-- ============================================================
Config.Porthole = {
    radius          = 18,           -- 舷窗半径
    coverThickness  = 4,            -- 舷窗盖厚度
    breakDepth      = 5000,         -- 超过此深度舷窗可能破裂
    breakChance     = 0.001,        -- 每秒破裂概率（深度超标时）
    floodRate       = 12,           -- 舷窗破裂进水速率（比普通破洞快）
    viewZoomTime    = 0.5,          -- 查看外部的缩放动画时间
    interactRange   = 35,           -- 交互范围
}

-- ============================================================
-- 角色物理参数
-- ============================================================
Config.Crew = {
    -- 尺寸
    height      = 120,          -- 角色高度（对应1.8m，占舱室40%）
    width       = 36,           -- 角色宽度

    -- 移动速度
    walkSpeed   = 100,          -- 走路速度（摇杆轻推）
    runSpeed    = 200,          -- 跑步速度（摇杆推满）
    walkThreshold = 0.5,        -- 摇杆强度区分走/跑的阈值

    -- 物理
    gravity     = 600,          -- 重力加速度（像素/秒²）
    jumpSpeed   = 320,          -- 跳跃初速度（向上）
    jumpHeight  = 150,          -- 跳跃最大高度（约1.5m）
    maxFallSpeed= 500,          -- 最大下落速度

    -- 惯性
    accel       = 800,          -- 地面加速度（像素/秒²）
    decel       = 600,          -- 地面减速度（松手后减速）
    airAccel    = 300,          -- 空中加速度（较低，空中操控弱）
    airDecel    = 100,          -- 空中减速度

    -- 水中移动
    swimSpeed   = 60,           -- 水中移动速度
    floatSpeed  = 40,           -- 水中自然上浮速度
    waterDrag   = 0.85,         -- 水中阻力系数（每秒衰减）

    -- 摔倒/恢复
    fallThreshold = 350,        -- 下落速度超过此值着地会摔倒
    stunDuration  = 2.0,        -- 摔倒恢复时间（秒）
    shakeKnockdown = 0.7,       -- 剧烈晃动摔倒概率（0~1）

    -- 抓握
    grabRange   = 40,           -- 抓扶手/梯子的范围
    grabSlowdown= 0.3,          -- 抓握时速度衰减

    -- 初始位置
    startRoom   = 1,            -- 初始舱室索引
}

-- ============================================================
-- 舱室结构参数
-- ============================================================
Config.Structure = {
    floorHeight   = 10,         -- 地板厚度
    ceilingHeight = 8,          -- 天花板厚度
    wallThickness = 6,          -- 内墙厚度
    pipeHeight    = 20,         -- 天花板管道/可攀爬区域高度
    ladderSlots   = {3, 5, 7},  -- 有梯子的舱室索引（引擎、炮塔上、气闸）
    handrailHeight= 60,         -- 扶手高度（从地板算起）
}

-- ============================================================
-- 游戏状态参数
-- ============================================================
Config.Game = {
    maxOxygen    = 100,
    maxHull      = 100,
    maxPower     = 100,
    maxDepth     = 10000,       -- 最大深度（米，用于HUD深度条百分比）
    oxygenDrain  = 1.5,         -- 每秒消耗
    floodRate    = 8,           -- 每秒进水速度（破洞时）
    maxWaterLevel= 0.8,         -- 最大水位（占舱室高度比）

    -- 水中氧气消耗
    underwaterOxygenDrain = 5,  -- 水中氧气消耗倍率
}

-- ============================================================
-- 深海背景参数
-- ============================================================
Config.Background = {
    bubbleCount  = 30,          -- 气泡数量
    bubbleMinR   = 2,
    bubbleMaxR   = 6,
    bubbleSpeed  = 30,          -- 上升速度
    creatureInterval = {8, 15}, -- 生物出现间隔（秒）
    creatureSpeed = 60,         -- 生物移动速度
}

-- ============================================================
-- 灯光参数
-- ============================================================
Config.Lighting = {
    normalRadius   = 180,       -- 正常灯光照射半径
    emergencyRadius= 80,        -- 应急灯半径
    pulseSpeed     = 3.0,       -- 应急灯脉冲速度
    pulseMin       = 0.3,       -- 脉冲最小亮度
    ceilingLightSpacing = 100,  -- 天花板灯间距
}

-- ============================================================
-- 驾驶系统参数
-- ============================================================
Config.Driving = {
    -- 舵盘
    helm = {
        maxAngle     = 90,          -- 最大旋转角度（度，-90~+90）
        returnSpeed  = 60,          -- 回中速度（度/秒）
        turnRates    = {            -- 舵角→转向速度映射
            {angle = 0,  rate = 0},
            {angle = 45, rate = 8},     -- 45度舵角=8度/秒转向
            {angle = 90, rate = 15},    -- 90度满舵=15度/秒转向
        },
        inertiaDelay = 2.0,         -- 转向惯性延迟（秒）
        dragRadius   = 80,          -- UI拖拽半径（像素）
    },

    -- 油门
    throttle = {
        gears = {
            {id = "reverse", speed = -3,  noise = 0.4, label = "R"},
            {id = "stop",    speed = 0,   noise = 0.0, label = "0"},
            {id = "gear1",   speed = 2,   noise = 0.1, label = "1"},
            {id = "gear2",   speed = 4,   noise = 0.2, label = "2"},
            {id = "gear3",   speed = 7,   noise = 0.4, label = "3"},
            {id = "gear4",   speed = 12,  noise = 0.8, label = "4"},
        },
        defaultGear  = 2,           -- 默认档位索引（stop）
        gearSwitchTime = 0.5,       -- 换挡时间（秒）
    },

    -- 深度控制器
    depth = {
        minDepth     = 50,          -- 最小深度（米）
        maxDepth     = 8000,        -- 最大深度（米）
        diveRate     = 50,          -- 下潜速率（米/分钟 → 0.833米/秒）
        riseRate     = 30,          -- 上浮速率（米/分钟 → 0.5米/秒）
        tolerance    = 5,           -- 到达目标深度容差（米）
    },
}

-- ============================================================
-- 潜艇物理参数
-- ============================================================
Config.Physics = {
    -- 质量（吨）
    hullMass       = 800,           -- 空壳质量
    maxCargoMass   = 200,           -- 最大货物质量
    crewMass       = 0.08,          -- 每人质量（吨）
    waterDensity   = 1.025,         -- 海水密度（吨/立方米）

    -- 运动
    maxSpeed       = 12,            -- 最大速度（m/s，约23节）
    dragCoeff      = 0.15,          -- 阻力系数
    lateralDrag    = 0.6,           -- 侧向阻力（转弯时）
    angularDrag    = 0.3,           -- 角阻力（停止转向后减速）

    -- 惯性
    accelTime      = 8.0,           -- 从0到最大速度加速时间（秒）
    decelTime      = 15.0,          -- 从最大速度到0惯性滑行时间（秒）
    turnInertia    = 2.0,           -- 转向惯性（秒，舵角→实际转向延迟）

    -- 碰撞
    collision = {
        minDamageSpeed = 2.0,       -- 造成伤害的最低碰撞速度（m/s）
        damagePerSpeed = 5,         -- 每m/s碰撞速度造成的船体伤害
        frontalMult    = 0.6,       -- 正面碰撞伤害系数（船头加固）
        sideMult       = 1.0,       -- 侧面碰撞伤害系数
        shakeIntensity = 0.8,       -- 碰撞震动强度
        shakeDuration  = 2.0,       -- 碰撞震动持续时间（秒）
        crewFallChance = 0.6,       -- 碰撞时船员摔倒概率
    },
}

-- ============================================================
-- 压载水舱参数
-- ============================================================
Config.Ballast = {
    -- 有压载水舱的舱室
    rooms = {3, 4},                 -- 引擎舱(3)、货舱(4)
    tankCapacity   = 100,           -- 每个舱的水舱容量（%，0=空 100=满）

    -- 操作速率
    fillRate       = 8,             -- 进水速率（%/秒）
    drainRate      = 5,             -- 排水速率（%/秒）
    emergencyRate  = 20,            -- 紧急排水速率（%/秒）

    -- 效果
    buoyancyPerTank = 50,           -- 每个水舱满载时的下沉力（等效吨）
    emergencyDamageChance = 0.15,   -- 紧急排水时系统损坏概率

    -- 破裂
    breachFloodRate = 12,           -- 水舱破裂时进水速率（%/秒）

    -- 操作范围
    operateRange   = 50,            -- 操作距离（像素）
    operateRole    = {"engineer", "mechanic"},  -- 可操作角色
}

-- ============================================================
-- 探照灯参数
-- ============================================================
Config.Searchlight = {
    defaultAngle   = 0,             -- 默认角度（正前方）
    minAngle       = -60,           -- 最小角度
    maxAngle       = 60,            -- 最大角度
    defaultRange   = 200,           -- 默认照射范围（像素）
    minRange       = 100,           -- 最小范围
    maxRange       = 400,           -- 最大范围
    beamWidth      = 25,            -- 光束宽度（度）
    powerCost      = 1,             -- 每秒耗电
    color          = {255, 250, 220, 200},  -- 光束颜色
}

-- ============================================================
-- 声呐参数
-- ============================================================
Config.Sonar = {
    radius         = 90,            -- 声呐屏幕半径（像素）
    scanSpeed      = 2.0,           -- 扫描线旋转速度（弧度/秒）
    pulseRange     = 3000,          -- 脉冲探测范围（米）
    pulseCooldown  = 5.0,           -- 脉冲冷却时间（秒）
    pulseDuration  = 3.0,           -- 脉冲结果显示持续时间（秒）
    pingSpeed      = 800,           -- 声波传播速度（米/秒，可视化用）
    blipFadeTime   = 4.0,           -- 回波点淡出时间（秒）
    color          = {50, 255, 100, 255},   -- 声呐绿色
    bgColor        = {5, 20, 10, 240},      -- 屏幕背景
}

-- ============================================================
-- 导航系统参数
-- ============================================================
Config.Navigation = {
    -- 地图显示
    mapWidth       = 400,           -- 地图面板宽度（像素）
    mapHeight      = 300,           -- 地图面板高度（像素）
    mapScale       = 0.02,          -- 世界坐标→地图坐标缩放

    -- 航点
    maxWaypoints   = 10,            -- 最大航点数
    waypointRadius = 50,            -- 到达航点判定半径（米）
    routeColor     = {100, 200, 255, 200},  -- 路线颜色
    waypointColor  = {255, 200, 50, 255},   -- 航点颜色
    currentPosColor= {50, 255, 100, 255},   -- 当前位置颜色

    -- 偏航警报
    deviationWarning = 200,         -- 偏航警告距离（米）
    deviationAlarm   = 500,         -- 偏航报警距离（米）
    alarmInterval    = 3.0,         -- 报警间隔（秒）

    -- 区域标记
    dangerColor    = {255, 60, 60, 150},    -- 危险区域颜色
    exploredColor  = {60, 150, 255, 80},    -- 已探索区域颜色
}

-- ============================================================
-- 反应堆参数
-- ============================================================
Config.Reactor = {
    -- 输出
    minOutput      = 0,             -- 最小输出（%）
    maxOutput      = 150,           -- 最大输出（%，超过100为超载）
    defaultOutput  = 80,            -- 默认输出
    outputStep     = 5,             -- 每次调节步长（%）

    -- 温度
    maxTemp        = 100,           -- 最高温度（%，100=熔毁阈值）
    warningTemp    = 60,            -- 温度警告阈值
    criticalTemp   = 80,            -- 温度危险阈值
    meltdownTemp   = 100,           -- 触发熔毁倒计时的温度

    -- 升温速率（%每10秒，根据输出档位）
    heatRates = {
        {output = 0,   rate = 0},       -- 停机：不升温
        {output = 80,  rate = 2},       -- 80%输出：2%/10秒
        {output = 100, rate = 5},       -- 100%输出：5%/10秒
        {output = 120, rate = 10},      -- 120%超载：10%/10秒
        {output = 150, rate = 20},      -- 150%极限：20%/10秒
    },

    -- 冷却
    cooldownRate     = 3,           -- 自然冷却速率（%/10秒，空闲时）
    coolPulseEffect  = 20,          -- 冷却按钮效果（-20%温度）
    coolPulseCooldown= 8,           -- 冷却按钮冷却时间（秒）
    coolingPipes     = 4,           -- 冷却管数量

    -- 熔毁
    meltdownCountdown = 30,         -- 熔毁倒计时（秒）
    meltdownDamage   = 9999,        -- 熔毁爆炸伤害（=游戏结束）

    -- 启动/关机
    startupTime    = 5,             -- 启动预热时间（秒）
    shutdownTime   = 3,             -- 紧急关机时间（秒，需长按）
    shutdownHoldTime = 3,           -- 长按关机所需时间（秒）

    -- 视觉
    cylinderWidth  = 80,            -- 反应堆圆柱宽度（像素）
    cylinderHeight = 140,           -- 反应堆圆柱高度（像素）
    pipeRadius     = 6,             -- 冷却管半径
}

-- ============================================================
-- 电力系统参数（基于反应堆输出的kW制）
-- ============================================================
Config.Power = {
    -- 基础：反应堆输出% × 100 = 总kW
    -- 例：80% → 8000kW，100% → 10000kW，150% → 15000kW
    kWPerPercent   = 100,           -- 每1%输出对应的kW

    -- 各系统最大消耗（kW）
    systems = {
        engine     = {name = "引擎",    icon = "E", maxPower = 5000, minPower = 0,   color = {60, 200, 255}},
        turret     = {name = "炮塔",    icon = "T", maxPower = 1000, minPower = 0,   color = {255, 80, 80}},
        sonar      = {name = "声呐",    icon = "S", maxPower = 500,  minPower = 0,   color = {80, 255, 140}},
        searchlight= {name = "探照灯",  icon = "L", maxPower = 1000, minPower = 200, color = {255, 220, 80}},
        oxygen     = {name = "制氧",    icon = "O", maxPower = 800,  minPower = 200, color = {180, 220, 255}},
        lights     = {name = "照明",    icon = "☀", maxPower = 200,  minPower = 0,   color = {255, 255, 200}},
        pump       = {name = "水泵",    icon = "P", maxPower = 600,  minPower = 0,   color = {100, 180, 255}},
        ballast    = {name = "压载",    icon = "B", maxPower = 400,  minPower = 0,   color = {60, 180, 160}},
        medical    = {name = "医疗",    icon = "M", maxPower = 300,  minPower = 0,   color = {255, 120, 180}},
    },

    -- 默认优先级（从高到低，电力不足时从最低优先级开始关闭）
    defaultPriority = {
        "oxygen", "lights", "engine", "pump", "sonar", "searchlight", "turret", "ballast", "medical"
    },

    -- 电力不足效果阈值
    shortageEffects = {
        lights = {
            dimThreshold   = 0.7,   -- 效率低于70%开始变暗
            flickerThreshold = 0.3, -- 效率低于30%开始闪烁
            offThreshold   = 0.0,   -- 效率0%完全熄灭
        },
        engine = {
            -- 电力不足时强制降档（效率<50%降一档，<25%降两档）
            forceDownGear1 = 0.5,
            forceDownGear2 = 0.25,
        },
    },
}

-- ============================================================
-- 接线系统参数
-- ============================================================
Config.Wiring = {
    -- 接线盒配置（每个舱室墙壁上的接线盒）
    junctionBoxes = {
        {room = 1, xOffset = 0.9, id = "jbox_bridge"},      -- 驾驶舱右墙
        {room = 2, xOffset = 0.2, id = "jbox_reactor_l"},   -- 反应堆舱左
        {room = 2, xOffset = 0.8, id = "jbox_reactor_r"},   -- 反应堆舱右
        {room = 3, xOffset = 0.5, id = "jbox_engine"},      -- 引擎舱
        {room = 4, xOffset = 0.5, id = "jbox_cargo"},       -- 货舱
        {room = 5, xOffset = 0.5, id = "jbox_medical"},     -- 医疗舱
        {room = 6, xOffset = 0.5, id = "jbox_turret_u"},    -- 炮塔上
        {room = 7, xOffset = 0.5, id = "jbox_turret_l"},    -- 炮塔下
        {room = 8, xOffset = 0.3, id = "jbox_airlock"},     -- 气闸舱
    },

    -- 线缆连接（默认拓扑：从反应堆向两侧供电）
    defaultCables = {
        {from = "jbox_reactor_l", to = "jbox_bridge",     system = "bridge"},
        {from = "jbox_reactor_r", to = "jbox_engine",     system = "engine"},
        {from = "jbox_engine",    to = "jbox_cargo",      system = "cargo"},
        {from = "jbox_cargo",     to = "jbox_medical",    system = "medical"},
        {from = "jbox_medical",   to = "jbox_turret_u",   system = "turret_u"},
        {from = "jbox_turret_u",  to = "jbox_turret_l",   system = "turret_l"},
        {from = "jbox_turret_l",  to = "jbox_airlock",    system = "airlock"},
    },

    -- 修复参数
    repairTime     = 4,             -- 修复被切断线缆所需时间（秒）
    interactRange  = 40,            -- 接线盒交互范围（像素）

    -- 怪物破坏
    monsterDamageChance = 0.3,      -- 怪物攻击时切断线缆概率
    maxSimultaneousCuts = 2,        -- 同时最多被切断的线缆数

    -- 紧急线路重定向
    rerouteTime    = 2,             -- 拉线重定向时间（秒）

    -- 视觉
    cableThickness = 3,             -- 线缆绘制粗细（像素）
    boxSize        = 24,            -- 接线盒尺寸（像素）
    sparkInterval  = 0.3,           -- 断线火花间隔（秒）
}

-- ============================================================
-- 危机事件系统
-- ============================================================
Config.Crisis = {
    -- 全局限制
    maxSimultaneous = 3,            -- 同时最多活跃危机数
    minInterval = 15,               -- 两次危机之间最小间隔（秒）
    firstCrisisDelay = 25,          -- 游戏开始后首次危机延迟（秒）

    -- 概率调节因子（乘以基础概率）
    depthFactor = {                 -- 深度影响：depth/maxDepth * factor
        threshold = 0.3,            -- 深度比例超过此值才开始增加概率
        multiplier = 2.0,           -- 满深度时概率翻倍
    },
    timeFactor = {                  -- 时间影响：每分钟增加概率
        perMinute = 0.05,           -- 每分钟增加5%触发率
        cap = 2.0,                  -- 最大倍率
    },
    noiseFactor = {                 -- 噪音影响（声呐/引擎）
        sonarPulseBoost = 0.3,      -- 声呐脉冲后短暂增加30%
        highSpeedBoost = 0.2,       -- 高速航行增加20%
        boostDuration = 10,         -- 增益持续秒数
    },

    -- 严重度定义
    severity = {
        minor    = { label = "轻微", repairMult = 1.0, damageMult = 0.5 },
        moderate = { label = "中等", repairMult = 1.5, damageMult = 1.0 },
        critical = { label = "严重", repairMult = 2.5, damageMult = 2.0 },
    },

    -- ========================================
    -- 8种危机类型配置
    -- ========================================
    types = {
        -- 1. 船体破裂（3级严重度）
        breach = {
            name = "船体破裂",
            baseChance = 0.015,         -- 每秒基础概率
            rooms = {2, 3, 4, 5, 6, 7, 8}, -- 可发生的舱室（不含驾驶舱1）
            repairTime = {5, 8, 12},    -- 轻/中/重 修复时间
            floodRate = {0.3, 0.6, 1.2},-- 进水速率 (%/s)
            hullDamage = {0.5, 1.2, 2.5},-- 船体伤害/秒
            severityWeights = {60, 30, 10}, -- 轻:中:重 概率权重
            chainReaction = {           -- 链式反应
                type = "power_failure", -- 严重破裂可能导致电力故障
                chance = 0.2,           -- 20%概率
                minSeverity = "critical",
            },
        },

        -- 2. 反应堆过热
        overheat = {
            name = "反应堆过热",
            baseChance = 0.008,
            rooms = {2},                -- 只在反应堆舱
            heatRate = 2.0,             -- 温度上升速度 (%/s)
            meltdownTemp = 100,         -- 熔毁温度
            meltdownTime = 30,          -- 达到100%后多久熔毁
            repairTime = {4, 6, 10},
            severityWeights = {50, 35, 15},
            chainReaction = {
                type = "fire",
                chance = 0.3,
                minSeverity = "moderate",
            },
            -- 条件触发：反应堆输出>120%时概率x3
            conditionalBoost = { reactorOutput = 120, multiplier = 3.0 },
        },

        -- 3. 电力故障（线缆咬断/发电机故障）
        power_failure = {
            name = "电力故障",
            baseChance = 0.006,
            rooms = {2, 3},             -- 反应堆舱/引擎舱
            repairTime = {3, 5, 8},
            severityWeights = {50, 35, 15},
            effects = {
                minor = "single_system", -- 单系统断电
                moderate = "half_ship",  -- 半船断电
                critical = "full_blackout", -- 全船停电
            },
            chainReaction = {
                type = "equipment_malfunction",
                chance = 0.15,
                minSeverity = "moderate",
            },
        },

        -- 4. 火灾（蔓延到相邻舱室，消耗氧气）
        fire = {
            name = "火灾",
            baseChance = 0.005,
            rooms = {2, 3, 4, 5, 6},    -- 引擎/工程/货舱/生活/武器
            repairTime = {4, 7, 11},
            severityWeights = {55, 30, 15},
            spreadInterval = 15,         -- 每15秒蔓延检查一次
            spreadChance = 0.4,          -- 蔓延到相邻舱室概率
            oxygenBurn = {1.5, 3.0, 5.0},-- 氧气消耗 (%/s)
            hullDamage = {0.2, 0.5, 1.0},-- 船体伤害/秒
            chainReaction = {
                type = "toxic_gas",
                chance = 0.25,
                minSeverity = "moderate",
            },
        },

        -- 5. 怪物入侵（进入舱室攻击船员/设备）
        monster_invasion = {
            name = "怪物入侵",
            baseChance = 0.003,
            rooms = {4, 5, 6, 7, 8},    -- 货舱之后的舱室
            repairTime = {6, 10, 15},    -- 实际是驱逐时间
            severityWeights = {50, 35, 15},
            crewDamage = {5, 10, 20},    -- 对船员伤害/次
            cableDamageChance = 0.3,     -- 攻击线缆概率
            attackInterval = {3, 2, 1},  -- 攻击间隔（秒）
            -- 条件触发：深度>70%时概率x2
            conditionalBoost = { depthRatio = 0.7, multiplier = 2.0 },
        },

        -- 6. 设备故障（需诊断再修复）
        equipment_malfunction = {
            name = "设备故障",
            baseChance = 0.007,
            rooms = {1, 2, 3, 4, 5, 6, 7, 8}, -- 任何舱室
            repairTime = {4, 6, 9},
            severityWeights = {55, 30, 15},
            diagnoseTime = 2,            -- 诊断时间（秒）
            affectedSystems = {"sonar", "navigation", "lights", "pumps", "comms"},
        },

        -- 7. 有毒气体泄漏（通过通风蔓延）
        toxic_gas = {
            name = "有毒气体",
            baseChance = 0.004,
            rooms = {2, 3, 4, 5},        -- 工程区域
            repairTime = {5, 8, 12},
            severityWeights = {50, 35, 15},
            spreadSpeed = 0.1,           -- 每秒蔓延到相邻舱比例
            crewDamage = {2, 4, 8},      -- 对在场船员伤害/秒
            ventClearTime = 10,          -- 通风清除所需时间
            chainReaction = {
                type = "crew_madness",
                chance = 0.1,
                minSeverity = "critical",
            },
        },

        -- 8. 船员疯狂（深海压力/目击怪物）
        crew_madness = {
            name = "船员恐慌",
            baseChance = 0.002,
            rooms = {},                  -- 不限舱室，作用于船员个体
            repairTime = {8, 12, 18},    -- 安抚时间
            severityWeights = {60, 30, 10},
            effects = {
                minor = "slow",          -- 移动减速50%
                moderate = "uncontrol",  -- 短暂失控（随机移动）
                critical = "sabotage",   -- 可能破坏设备
            },
            -- 条件触发：深度>80%或刚目睹怪物
            conditionalBoost = { depthRatio = 0.8, multiplier = 2.5 },
            triggerOnMonsterSight = true, -- 看到怪物时额外触发检查
        },
    },

    -- ========================================
    -- 警报系统配置
    -- ========================================
    alert = {
        -- 颜色编码（RGBA）
        colors = {
            critical = {255, 40, 30, 220},   -- 红色 = 紧急
            warning  = {255, 200, 30, 200},  -- 黄色 = 警告
            notice   = {60, 160, 255, 180},  -- 蓝色 = 通知
        },
        -- 危机类型→警报级别映射
        levelMap = {
            breach              = "critical",
            overheat            = "critical",
            fire                = "critical",
            power_failure       = "warning",
            monster_invasion    = "critical",
            equipment_malfunction = "notice",
            toxic_gas           = "warning",
            crew_madness        = "notice",
        },
        -- 严重度升级：严重时任何类型都变红色
        severityOverride = {
            critical = "critical",  -- 严重度=critical 时强制红色警报
        },
        -- 闪烁参数
        flashSpeed = {
            critical = 6.0,     -- 快速闪烁
            warning  = 3.5,     -- 中速闪烁
            notice   = 2.0,     -- 慢速闪烁
        },
        -- 静音（驾驶舱按钮可切换）
        muteDefault = false,
        muteFadeTime = 1.0,     -- 静音后警报淡出时间
    },
}

return Config
