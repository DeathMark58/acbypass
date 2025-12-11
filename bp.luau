--[[
    COMBINED AC BYPASS v1.0
    
    Bypasses BOTH:
    1. Labyrinth AC (remote-based detection)
    2. Adonis AC (memory-based detection)
    
    Load this BEFORE your main script!
    
    Usage:
        loadstring(game:HttpGet("URL"))()
]]

local CombinedBypass = {
    Hooks = {},
    FlagFunction = nil,
    TerminateFunction = nil,
    IsVerbose = false,  -- Set to true for debug logs
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
    if CombinedBypass.IsVerbose then
        print("[AC Bypass]", ...)
    end
end

-- ============================================
-- PART 1: LABYRINTH AC BYPASS
-- Hooks __namecall to block detection remotes
-- ============================================
local function bypassLabyrinth()
    if not getrawmetatable then
        log("getrawmetatable not available")
        return false
    end
    
    local game = cloneref and cloneref(game) or game
    local mt = getrawmetatable(game)
    if not mt then return false end
    
    local oldNamecall = mt.__namecall
    
    -- Make writable
    if setreadonly then
        pcall(setreadonly, mt, false)
    end
    
    -- Install hook
    mt.__namecall = safeWrap(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod()
        local args = {...}
        
        if method == "FireServer" then
            local remoteName = ""
            pcall(function() remoteName = self.Name end)
            
            -- Block Labyrinth detection reports
            if remoteName == "__LABYRINTH__" then
                if type(args[1]) == "nil" and type(args[2]) == "table" then
                    if args[2].r then
                        log("Blocked Labyrinth detection:", args[2].r)
                        return -- DROP
                    end
                end
            end
            
            -- Allow heartbeat through
            if remoteName == "__LABYRINTH__HANDSHAKE__" then
                return oldNamecall(self, ...)
            end
        end
        
        return oldNamecall(self, ...)
    end)
    
    -- Restore readonly
    if setreadonly then
        pcall(setreadonly, mt, true)
    end
    
    Status.LabyrinthBypassed = true
    return true
end

-- ============================================
-- PART 2: ADONIS AC BYPASS
-- Hooks internal detection functions via getgc
-- ============================================
local function bypassAdonis()
    if not getgc or not hookfunction then
        log("getgc or hookfunction not available")
        return false
    end
    
    -- Set thread identity for access
    if setthreadidentity then
        pcall(setthreadidentity, 2)
    end
    
    -- Scan garbage collector for Adonis functions
    local collected = getgc(true)
    for _, item in ipairs(collected) do
        if typeof(item) == 'table' then
            local detectionMethod = rawget(item, 'Detected')
            local killMethod = rawget(item, 'Kill')
            
            -- Hook Detected function
            if typeof(detectionMethod) == 'function' and not CombinedBypass.FlagFunction then
                CombinedBypass.FlagFunction = detectionMethod
                
                local success = pcall(function()
                    hookfunction(detectionMethod, safeWrap(function(trigger, details, preventCrash)
                        if trigger ~= '_' then
                            log("Adonis Detected blocked:", trigger, details)
                        end
                        return true
                    end))
                end)
                
                if success then
                    table.insert(CombinedBypass.Hooks, detectionMethod)
                    Status.AdonisDetectionDisabled = true
                end
            end
            
            -- Hook Kill function
            if typeof(killMethod) == 'function' 
               and rawget(item, 'Variables') 
               and rawget(item, 'Process') 
               and not CombinedBypass.TerminateFunction then
                
                CombinedBypass.TerminateFunction = killMethod
                
                local success = pcall(function()
                    hookfunction(killMethod, safeWrap(function(cause)
                        log("Adonis Kill blocked:", cause)
                        return nil
                    end))
                end)
                
                if success then
                    table.insert(CombinedBypass.Hooks, killMethod)
                    Status.AdonisKillBlocked = true
                end
            end
        end
    end
    
    -- Hook debug.info to hide our functions from stack traces
    if getrenv and getrenv().debug and getrenv().debug.info then
        local originalDebugInfo
        
        pcall(function()
            originalDebugInfo = hookfunction(
                getrenv().debug.info,
                safeWrap(function(...)
                    local levelOrFunc, info = ...
                    
                    -- If checking our hooked function, yield to hide it
                    if CombinedBypass.FlagFunction and levelOrFunc == CombinedBypass.FlagFunction then
                        log("debug.info check intercepted")
                        return coroutine.yield(coroutine.running())
                    end
                    
                    return originalDebugInfo(...)
                end)
            )
        end)
        
        if originalDebugInfo then
            Status.DebugInfoHooked = true
        end
    end
    
    -- Reset thread identity
    if setthreadidentity then
        pcall(setthreadidentity, 7)
    end
    
    return Status.AdonisDetectionDisabled or Status.AdonisKillBlocked
end

-- ============================================
-- PART 3: GLOBAL BAIT PROTECTION
-- Prevents accidental triggering of bait functions
-- ============================================
local function protectGlobalBait()
    local safeFunc = function() return "Protected" end
    
    pcall(function() rawset(_G, "anticheat", safeFunc) end)
    pcall(function() rawset(_G, "detection", safeFunc) end)
    pcall(function() rawset(getfenv(), "anticheat", safeFunc) end)
    pcall(function() rawset(getfenv(), "detection", safeFunc) end)
end

-- ============================================
-- INITIALIZATION
-- ============================================
local function init()
    print("[AC Bypass] Initializing combined bypass...")
    
    -- Bypass Labyrinth AC
    local labSuccess = bypassLabyrinth()
    print("[AC Bypass] Labyrinth:", labSuccess and "✓" or "✗")
    
    -- Bypass Adonis AC  
    local adonisSuccess = bypassAdonis()
    print("[AC Bypass] Adonis:", adonisSuccess and "✓" or "✗")
    
    -- Protect global bait
    protectGlobalBait()
    print("[AC Bypass] Global bait: ✓")
    
    -- Print status
    print(string.format(
        "[AC Bypass] Status: Labyrinth=%s | Adonis Detection=%s | Adonis Kill=%s | Debug.info=%s",
        tostring(Status.LabyrinthBypassed),
        tostring(Status.AdonisDetectionDisabled),
        tostring(Status.AdonisKillBlocked),
        tostring(Status.DebugInfoHooked)
    ))
    
    return Status
end

-- ============================================
-- API
-- ============================================
function CombinedBypass.setVerbose(enabled)
    CombinedBypass.IsVerbose = enabled
end

function CombinedBypass.getStatus()
    return Status
end

-- Auto-init
init()

return CombinedBypass
