--[[
    STEALTH AC BYPASS v2.0
    
    Bypasses BOTH:
    1. Labyrinth AC - WITHOUT using __namecall hook (uses hookfunction on RemoteEvent)
    2. Adonis AC - getgc + hookfunction approach
    
    This version avoids metatable hooks entirely to bypass namecall detection!
    
    Load this BEFORE your main script!
]]

local StealthBypass = {
    Hooks = {},
    FlagFunction = nil,
    TerminateFunction = nil,
    IsVerbose = false,
    OriginalFireServer = nil,
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
        print("[Stealth Bypass]", ...)
    end
end

-- ============================================
-- PART 1: ADONIS AC BYPASS (RUN FIRST!)
-- Must disable Adonis BEFORE any hooks
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
            if typeof(detectionMethod) == 'function' and not StealthBypass.FlagFunction then
                StealthBypass.FlagFunction = detectionMethod
                
                local success = pcall(function()
                    hookfunction(detectionMethod, safeWrap(function(trigger, details, preventCrash)
                        if trigger ~= '_' then
                            log("Adonis Detected blocked:", trigger, details)
                        end
                        return true
                    end))
                end)
                
                if success then
                    table.insert(StealthBypass.Hooks, detectionMethod)
                    Status.AdonisDetectionDisabled = true
                end
            end
            
            -- Hook Kill function
            if typeof(killMethod) == 'function' 
               and rawget(item, 'Variables') 
               and rawget(item, 'Process') 
               and not StealthBypass.TerminateFunction then
                
                StealthBypass.TerminateFunction = killMethod
                
                local success = pcall(function()
                    hookfunction(killMethod, safeWrap(function(cause)
                        log("Adonis Kill blocked:", cause)
                        return nil
                    end))
                end)
                
                if success then
                    table.insert(StealthBypass.Hooks, killMethod)
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
                    if StealthBypass.FlagFunction and levelOrFunc == StealthBypass.FlagFunction then
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
-- PART 2: LABYRINTH AC BYPASS (STEALTH VERSION)
-- Uses hookfunction instead of __namecall
-- NO METATABLE MODIFICATION!
-- ============================================
local function bypassLabyrinth()
    if not hookfunction then
        log("hookfunction not available, trying alternative...")
        return bypassLabyrinthAlternative()
    end
    
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    
    -- Method 1: Hook Instance.new to catch remote creation
    pcall(function()
        local originalInstanceNew
        originalInstanceNew = hookfunction(Instance.new, safeWrap(function(className, parent)
            local instance = originalInstanceNew(className, parent)
            
            -- If it's a RemoteEvent, hook its FireServer
            if className == "RemoteEvent" and instance then
                task.defer(function()
                    pcall(function()
                        local originalRemoteFire
                        originalRemoteFire = hookfunction(instance.FireServer, safeWrap(function(self, ...)
                            local name = ""
                            pcall(function() name = self.Name end)
                            
                            if name == "__LABYRINTH__" then
                                local args = {...}
                                if type(args[1]) == "nil" and type(args[2]) == "table" and args[2].r then
                                    log("Blocked Labyrinth (new remote):", args[2].r)
                                    return
                                end
                            end
                            return originalRemoteFire(self, ...)
                        end))
                    end)
                end)
            end
            
            return instance
        end))
    end)
    
    -- Method 2: Find existing Labyrinth remote and hook it
    local function hookExistingRemote()
        local labyrinthRemote = ReplicatedStorage:FindFirstChild("__LABYRINTH__")
        if labyrinthRemote and labyrinthRemote:IsA("RemoteEvent") then
            pcall(function()
                -- hookfunction returns the ORIGINAL function
                local originalFire
                originalFire = hookfunction(labyrinthRemote.FireServer, safeWrap(function(self, ...)
                    local args = {...}
                    
                    -- Block detection reports
                    if type(args[1]) == "nil" and type(args[2]) == "table" then
                        if args[2].r then
                            log("Blocked Labyrinth detection:", args[2].r)
                            return -- DROP
                        end
                    end
                    
                    -- Call the ORIGINAL function (returned by hookfunction)
                    return originalFire(self, ...)
                end))
                
                StealthBypass.OriginalFireServer = originalFire
            end)
            
            Status.LabyrinthBypassed = true
            log("Hooked existing __LABYRINTH__ remote")
            return true
        end
        return false
    end
    
    -- Try to hook existing remote
    if hookExistingRemote() then
        return true
    end
    
    -- If remote doesn't exist yet, wait for it
    task.spawn(function()
        local remote = ReplicatedStorage:WaitForChild("__LABYRINTH__", 30)
        if remote then
            hookExistingRemote()
        end
    end)
    
    -- Also use ChildAdded to catch it
    ReplicatedStorage.ChildAdded:Connect(function(child)
        if child.Name == "__LABYRINTH__" and child:IsA("RemoteEvent") then
            task.defer(hookExistingRemote)
        end
    end)
    
    Status.LabyrinthBypassed = true
    return true
end

-- Alternative method if hookfunction fails
local function bypassLabyrinthAlternative()
    -- Use __namecall but only AFTER Adonis is disabled
    if not getrawmetatable then
        return false
    end
    
    local game = cloneref and cloneref(game) or game
    local mt = getrawmetatable(game)
    if not mt then return false end
    
    local oldNamecall = mt.__namecall
    
    if setreadonly then
        pcall(setreadonly, mt, false)
    end
    
    mt.__namecall = safeWrap(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod()
        local args = {...}
        
        if method == "FireServer" then
            local remoteName = ""
            pcall(function() remoteName = self.Name end)
            
            if remoteName == "__LABYRINTH__" then
                if type(args[1]) == "nil" and type(args[2]) == "table" and args[2].r then
                    log("Blocked Labyrinth (namecall):", args[2].r)
                    return
                end
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
-- PART 3: GLOBAL BAIT PROTECTION
-- ============================================
local function protectGlobalBait()
    local safeFunc = function() return "Protected" end
    
    pcall(function() rawset(_G, "anticheat", safeFunc) end)
    pcall(function() rawset(_G, "detection", safeFunc) end)
    pcall(function() rawset(getfenv(), "anticheat", safeFunc) end)
    pcall(function() rawset(getfenv(), "detection", safeFunc) end)
end

-- ============================================
-- INITIALIZATION (ORDER MATTERS!)
-- ============================================
local function init()
    print("[Stealth Bypass] v2.0 - Initializing...")
    
    -- STEP 1: Bypass Adonis FIRST (disables namecall detection)
    local adonisSuccess = bypassAdonis()
    print("[Stealth Bypass] Adonis:", adonisSuccess and "✓" or "✗")
    
    -- STEP 2: Now safe to bypass Labyrinth
    local labSuccess = bypassLabyrinth()
    print("[Stealth Bypass] Labyrinth:", labSuccess and "✓" or "✗")
    
    -- STEP 3: Protect global bait
    protectGlobalBait()
    print("[Stealth Bypass] Global bait: ✓")
    
    -- Print final status
    print(string.format(
        "[Stealth Bypass] Final: Adonis=%s,%s | Labyrinth=%s | Debug=%s",
        tostring(Status.AdonisDetectionDisabled),
        tostring(Status.AdonisKillBlocked),
        tostring(Status.LabyrinthBypassed),
        tostring(Status.DebugInfoHooked)
    ))
    
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

-- Auto-init
init()

return StealthBypass
