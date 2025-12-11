--[[
    LABYRINTH AC BYPASS v1.0
    
    Standalone bypass module for Labyrinth Anti-Cheat.
    Load this BEFORE your main script.
    
    Usage:
        loadstring(game:HttpGet("your-url/labyrinth_bypass.luau"))()
        -- or --
        require(path.to.labyrinth_bypass)
        
    What it does:
    1. Hooks __namecall to intercept all FireServer calls
    2. BLOCKS detection reports sent to __LABYRINTH__ remote
    3. ALLOWS heartbeat messages to __LABYRINTH__HANDSHAKE__ remote
    4. Protects against global bait function detection
    
    Based on full deobfuscation of Labyrinth AC.
]]

local LabyrinthBypass = {}

-- ============================================
-- CONFIGURATION
-- ============================================
local CONFIG = {
    -- Remote names (from deobfuscated AC)
    DETECTION_REMOTE = "__LABYRINTH__",
    HEARTBEAT_REMOTE = "__LABYRINTH__HANDSHAKE__",
    
    -- Report types to block
    REPORT_TYPES = {
        "mbait.metatable",
        "mbait_function"
    },
    
    -- Debug mode (print blocked calls)
    DEBUG = false,
    
    -- Silent mode (no console output at all)
    SILENT = false
}

-- ============================================
-- EXECUTOR FUNCTION DETECTION
-- ============================================
local function getExecutorFunctions()
    local funcs = {}
    
    -- Try to get executor-specific functions
    funcs.getrawmetatable = getrawmetatable or debug and debug.getmetatable
    funcs.setreadonly = setreadonly or function() end
    funcs.isreadonly = isreadonly or function() return false end
    funcs.newcclosure = newcclosure or function(f) return f end
    funcs.getnamecallmethod = getnamecallmethod
    funcs.hookfunction = hookfunction or replaceclosure or detour_function
    funcs.cloneref = cloneref or function(x) return x end
    
    return funcs
end

local exec = getExecutorFunctions()

-- ============================================
-- LOGGING
-- ============================================
local function log(...)
    if not CONFIG.SILENT then
        print("[Labyrinth Bypass]", ...)
    end
end

local function debug_log(...)
    if CONFIG.DEBUG and not CONFIG.SILENT then
        print("[Labyrinth Bypass DEBUG]", ...)
    end
end

-- ============================================
-- DETECTION CHECKER
-- ============================================
local function isDetectionReport(args)
    -- Detection reports have format: FireServer(nil, {r = "...", d = "..."})
    if type(args[1]) == "nil" and type(args[2]) == "table" then
        local payload = args[2]
        if payload.r then
            -- Check if it's a known report type
            for _, reportType in ipairs(CONFIG.REPORT_TYPES) do
                if payload.r == reportType then
                    return true, payload.r, payload.d
                end
            end
            -- Also block any table with 'r' field sent to labyrinth remote
            return true, payload.r, payload.d
        end
    end
    return false
end

-- ============================================
-- MAIN HOOK
-- ============================================
local function installHook()
    if not exec.getrawmetatable then
        log("ERROR: getrawmetatable not available. Bypass may not work.")
        return false
    end
    
    if not exec.getnamecallmethod then
        log("ERROR: getnamecallmethod not available. Bypass may not work.")
        return false
    end
    
    local game = exec.cloneref(game)
    local mt = exec.getrawmetatable(game)
    
    if not mt then
        log("ERROR: Could not get game metatable.")
        return false
    end
    
    -- Store original
    local oldNamecall = mt.__namecall
    
    -- Check if readonly
    local wasReadonly = exec.isreadonly(mt)
    if wasReadonly then
        exec.setreadonly(mt, false)
    end
    
    -- Install hook
    mt.__namecall = exec.newcclosure(function(self, ...)
        local method = exec.getnamecallmethod()
        local args = {...}
        
        -- Only intercept FireServer
        if method == "FireServer" then
            local remoteName = ""
            
            -- Safely get remote name
            pcall(function()
                remoteName = self.Name
            end)
            
            -- Check if this is the detection remote
            if remoteName == CONFIG.DETECTION_REMOTE then
                local isReport, reportType, details = isDetectionReport(args)
                
                if isReport then
                    debug_log("BLOCKED:", reportType, "-", tostring(details):sub(1, 50))
                    return -- DROP the call
                end
            end
            
            -- Allow heartbeat remote to pass through
            if remoteName == CONFIG.HEARTBEAT_REMOTE then
                debug_log("ALLOWED HEARTBEAT:", tostring(args[1]):sub(1, 30))
                return oldNamecall(self, ...)
            end
        end
        
        -- Pass through everything else
        return oldNamecall(self, ...)
    end)
    
    -- Restore readonly if needed
    if wasReadonly then
        exec.setreadonly(mt, true)
    end
    
    return true
end

-- ============================================
-- GLOBAL BAIT PROTECTION
-- ============================================
local function protectGlobalBait()
    -- Override the global bait functions to do nothing
    -- This prevents accidental triggering by other scripts
    
    local safeFunction = function()
        return "Nice try :)"
    end
    
    -- Wrap in pcall in case they're already defined with protection
    pcall(function()
        rawset(_G, "anticheat", safeFunction)
    end)
    
    pcall(function()
        rawset(_G, "detection", safeFunction)
    end)
    
    pcall(function()
        rawset(getfenv(), "anticheat", safeFunction)
    end)
    
    pcall(function()
        rawset(getfenv(), "detection", safeFunction)
    end)
end

-- ============================================
-- INITIALIZATION
-- ============================================
function LabyrinthBypass.init(config)
    -- Apply custom config
    if config then
        for k, v in pairs(config) do
            CONFIG[k] = v
        end
    end
    
    log("Initializing Labyrinth AC Bypass...")
    
    -- Install main hook
    local hookSuccess = installHook()
    if hookSuccess then
        log("✓ Namecall hook installed")
    else
        log("✗ Namecall hook failed")
    end
    
    -- Protect global bait
    protectGlobalBait()
    log("✓ Global bait protected")
    
    log("Bypass active! Detection reports will be blocked.")
    log("Heartbeat messages will pass through.")
    
    return hookSuccess
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

-- Enable/disable debug mode
function LabyrinthBypass.setDebug(enabled)
    CONFIG.DEBUG = enabled
    log("Debug mode:", enabled and "ON" or "OFF")
end

-- Enable/disable silent mode
function LabyrinthBypass.setSilent(enabled)
    CONFIG.SILENT = enabled
end

-- Get current status
function LabyrinthBypass.getStatus()
    return {
        debug = CONFIG.DEBUG,
        silent = CONFIG.SILENT,
        detectionRemote = CONFIG.DETECTION_REMOTE,
        heartbeatRemote = CONFIG.HEARTBEAT_REMOTE
    }
end

-- ============================================
-- AUTO-INIT
-- ============================================
-- Automatically initialize when loaded
LabyrinthBypass.init()

return LabyrinthBypass
