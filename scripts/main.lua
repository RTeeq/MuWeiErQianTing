--- 潜艇深海生存游戏 - 网络路由入口
--- 根据运行模式（服务端/客户端/单机）分发到对应模块
---
--- 模式判断：
---   IsServerMode()  → 服务端（Headless，运行逻辑，广播状态）
---   IsNetworkMode() → 客户端（发送输入，接收快照，渲染）
---   其他            → 单机模式（原始完整逻辑）

require "LuaScripts/Utilities/Sample"

---@type table|nil
local Module = nil

function Start()
    if IsServerMode() then
        -- 服务端：无渲染，纯逻辑
        print("[Main] Server mode detected → loading network/Server")
        Module = require("network.Server")
    elseif IsNetworkMode() then
        -- 客户端：连接服务器，发送输入，渲染快照
        print("[Main] Client mode detected → loading network/Client")
        Module = require("network.Client")
    else
        -- 单机模式：完整本地逻辑
        print("[Main] Standalone mode → loading network/Standalone")
        Module = require("network.Standalone")
    end

    if Module and Module.Start then
        Module.Start()
    end
end

function Stop()
    if Module and Module.Stop then
        Module.Stop()
    end
    Module = nil
end
