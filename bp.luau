--[[
    STEALTH AC BYPASS v4.0 - BULLETPROOF EDITION
    
    Fixes:
    - Race condition: Wait for Adonis to load before hooking
    - debug.info bug: Fixed closure reference
    - Late-loading AC: Continuous monitoring with getgc polling
    
    Bypasses BOTH:
    1. Labyrinth AC - __namecall hook
    2. Adonis AC - getgc + hookfunction
    
    Load this BEFORE your main script!
]]

local StealthBypass = {
    FlagFunction = nil,
    TerminateFunction = nil,
    IsVerbose = false,
    MonitorConnection = nil,
}

local Status = {
    LabyrinthBypassed = false,
    AdonisDetectionDisabled = false,
    AdonisKillBlocked = false,
    DebugInfoHooked = false,
}

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================
local function safeWrap(func)
    if newcclosure then
        local s, r = pcall(newcclosure, func)
        return s and r or func
    end
    return func
end

local function log(...)
    if StealthBypass.IsVerbose then
        print("[Bypass]", ...)
    end
end

-- ============================================
-- PART 1: ADONIS AC BYPASS
-- Scans for and hooks Adonis detection functions
-- ============================================
local function scanAndHookAdonis()
    if not getgc or not hookfunction then
        return false
    end
    
    local found = false
    local collected = getgc(true)
    
    for _, item in ipairs(collected) do
        if typeof(item) == 'table' then
            local detectionMethod = rawget(item, 'Detected')
            local killMethod = rawget(item, 'Kill')
            
            -- Hook Detected function
            if typeof(detectionMethod) == 'function' and not StealthBypass.FlagFunction then
                StealthBypass.FlagFunction = detectionMethod
                pcall(function()
                    hookfunction(detectionMethod, safeWrap(function(trigger, details, preventCrash)
                        log("Adonis Detected blocked:", trigger)
                        return true
                    end))
                end)
                Status.AdonisDetectionDisabled = true
                found = true
            end
            
            -- Hook Kill function
            if typeof(killMethod) == 'function' 
               and rawget(item, 'Variables') 
               and rawget(item, 'Process') 
               and not StealthBypass.TerminateFunction then
                StealthBypass.TerminateFunction = killMethod
                pcall(function()
                    hookfunction(killMethod, safeWrap(function(cause)
                        log("Adonis Kill blocked:", cause)
                        return nil
                    end))
                end)
                Status.AdonisKillBlocked = true
                found = true
            end
        end
    end
    
    return found
end

-- ============================================
-- PART 2: DEBUG.INFO HOOK (FIXED)
-- Hides our functions from stack traces
-- ============================================
local originalDebugInfo = nil

local function hookDebugInfo()
    if not getrenv or not hookfunction then return false end
    if not getrenv().debug or not getrenv().debug.info then return false end
    if originalDebugInfo then return true end -- Already hooked
    
    pcall(function()
        originalDebugInfo = hookfunction(getrenv().debug.info, safeWrap(function(...)
            local levelOrFunc = ...
            
            -- Hide our hooked function from stack traces
            if StealthBypass.FlagFunction and levelOrFunc == StealthBypass.FlagFunction then
                log("debug.info intercepted")
                return coroutine.yield(coroutine.running())
            end
            
            -- Call ORIGINAL (now properly referenced)
            return originalDebugInfo(...)
        end))
        
        Status.DebugInfoHooked = true
    end)
    
    return Status.DebugInfoHooked
end

-- ============================================
-- PART 3: CONTINUOUS MONITORING
-- Keeps scanning for late-loading Adonis
-- ============================================
local function startMonitoring()
    if StealthBypass.MonitorConnection then return end
    
    -- Scan every 2 seconds for first 30 seconds
    local scanCount = 0
    local maxScans = 15
    
    StealthBypass.MonitorConnection = task.spawn(function()
        while scanCount < maxScans do
            task.wait(2)
            scanCount = scanCount + 1
            
            -- Try to find Adonis if not found yet
            if not Status.AdonisDetectionDisabled then
                local found = scanAndHookAdonis()
                if found then
                    log("Late Adonis detection hooked!")
                    hookDebugInfo()
                end
            end
        end
        log("Monitoring stopped after", maxScans * 2, "seconds")
    end)
end

-- ============================================
-- PART 4: LABYRINTH AC BYPASS
-- __namecall hook for remote blocking
-- ============================================
local function bypassLabyrinth()
    if not getrawmetatable then
        log("getrawmetatable not available")
        return false
    end
    
    local game_ref = cloneref and cloneref(game) or game
    local mt = getrawmetatable(game_ref)
    if not mt then return false end
    
    local oldNamecall = mt.__namecall
    
    if setreadonly then
        pcall(setreadonly, mt, false)
    end
    
    mt.__namecall = safeWrap(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod()
        local args = {...}
        
        -- RemoteSpy: Log all remote calls when verbose
        if StealthBypass.IsVerbose and (method == "FireServer" or method == "InvokeServer") then
            local remoteName = ""
            local remoteClass = ""
            local callerScript = "Unknown"
            
            pcall(function() remoteName = self.Name end)
            pcall(function() remoteClass = self.ClassName end)
            
            -- Try to get caller script info
            pcall(function()
                local info = debug.info(4, "s") -- 4 levels up in call stack
                if info then
                    callerScript = tostring(info)
                end
            end)
            
            -- Format arguments for display
            local argsPreview = ""
            pcall(function()
                local parts = {}
                for i, arg in ipairs(args) do
                    if i > 3 then 
                        table.insert(parts, "...") 
                        break 
                    end
                    local t = typeof(arg)
                    if t == "string" then
                        table.insert(parts, '"' .. string.sub(arg, 1, 20) .. '"')
                    elseif t == "table" then
                        -- Show table keys
                        local keys = {}
                        for k, _ in pairs(arg) do
                            table.insert(keys, tostring(k))
                            if #keys >= 3 then break end
                        end
                        table.insert(parts, "{" .. table.concat(keys, ",") .. "}")
                    elseif t == "nil" then
                        table.insert(parts, "nil")
                    else
                        table.insert(parts, t .. ":" .. tostring(arg):sub(1, 15))
                    end
                end
                argsPreview = table.concat(parts, ", ")
            end)
            
            -- Check if this will be blocked
            local isBlocked = (remoteName == "__LABYRINTH__" or remoteName == "__LABYRINTH__HANDSHAKE__")
            local status = isBlocked and "🚫 BLOCKED" or "✅ ALLOWED"
            
            print(string.format(
                "[RemoteSpy] %s | %s:%s | Args(%s) | From: %s",
                status,
                method,
                remoteName,
                argsPreview,
                callerScript
            ))
        end
        
        -- Block both FireServer AND InvokeServer to Labyrinth
        if method == "FireServer" or method == "InvokeServer" then
            local remoteName = ""
            pcall(function() remoteName = self.Name end)
            
            -- Block ALL Labyrinth remotes
            if remoteName == "__LABYRINTH__" or remoteName == "__LABYRINTH__HANDSHAKE__" then
                return -- DROP silently
            end
            
            -- Block any remote containing LABYRINTH in name
            if string.find(remoteName, "LABYRINTH") then
                log("Blocked suspicious remote:", remoteName)
                return
            end
        end
        
        return oldNamecall(self, ...)
    end)
    
    if setreadonly then
        pcall(setreadonly, mt, true)
    end
    
    Status.LabyrinthBypassed = true
    return true
end

-- ============================================
-- PART 5: GLOBAL BAIT PROTECTION
-- ============================================
local function protectGlobalBait()
    local safeFunc = function() return "Protected" end
    pcall(function() rawset(_G, "anticheat", safeFunc) end)
    pcall(function() rawset(_G, "detection", safeFunc) end)
    pcall(function() rawset(getfenv(), "anticheat", safeFunc) end)
    pcall(function() rawset(getfenv(), "detection", safeFunc) end)
end

-- ============================================
-- INITIALIZATION (ORDER IS CRITICAL!)
-- ============================================
local function init()
    print("[Bypass] v4.0 Bulletproof - Starting...")
    
    -- Set thread identity for maximum access
    if setthreadidentity then
        pcall(setthreadidentity, 2)
    end
    
    -- STEP 1: Try to hook Adonis immediately
    local adonisFound = scanAndHookAdonis()
    
    -- STEP 2: Hook debug.info BEFORE __namecall
    hookDebugInfo()
    
    -- STEP 3: Start background monitoring for late-loading Adonis
    startMonitoring()
    
    -- STEP 4: Small delay to let Adonis hooks settle
    task.wait(0.1)
    
    -- STEP 5: Now safe to install __namecall hook
    local labSuccess = bypassLabyrinth()
    
    -- STEP 6: Protect global bait
    protectGlobalBait()
    
    -- Reset thread identity
    if setthreadidentity then
        pcall(setthreadidentity, 7)
    end
    
    -- Status report
    print(string.format(
        "[Bypass] Adonis=%s,%s | Lab=%s | Debug=%s",
        tostring(Status.AdonisDetectionDisabled),
        tostring(Status.AdonisKillBlocked),
        tostring(Status.LabyrinthBypassed),
        tostring(Status.DebugInfoHooked)
    ))
    
    if not adonisFound then
        print("[Bypass] Adonis not found yet, monitoring...")
    end
    
    return Status
end

-- ============================================
-- API
-- ============================================
function StealthBypass.setVerbose(enabled)
    StealthBypass.IsVerbose = enabled
end

function StealthBypass.getStatus()
    return Status
end

function StealthBypass.rescan()
    return scanAndHookAdonis()
end

-- Auto-init
init()

return StealthBypass
