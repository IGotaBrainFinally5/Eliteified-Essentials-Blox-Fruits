--[[
    Eliteified Essentials (BLOX FRUITS) - NEW REMAKE v1
    Same features/UI as EE v1.4, rebuilt movement controller.

    Movement changes:
      - tweenTo(..., gen, opts) with opts.stayAnchored for waypoint pins
      - On successful waypoint arrive: keep Anchored=true and re-pin CFrame
      - cancelFarmTween / mode change still fully releases the character
      - Hold-above combat path unchanged in behavior
]]

print("[EE] Script started - Eliteified Essentials NEW REMAKE v1")

----------------------------------------------------------------
-- 1. CONFIG
----------------------------------------------------------------
local Config = {
    Title          = "Eliteified Essentials",
    GameTag        = "(BLOX FRUITS)",
    BrandMain      = "E.E.",
    BrandSub       = "Elites Essentials",

    WindowSize     = Vector2.new(560, 340),
    SidebarWidth   = 58,
    TitleBarHeight = 40,
    ToggleKey      = Enum.KeyCode.RightControl, -- hide/show (PC only)

    -- Diagnostics
    Diagnostics         = true,
    DiagnosticsAutoHide = 0, -- seconds after a successful load (0 = never hide)

    -- Game check. Matches by PlaceId OR GameId (universe).
    -- StrictGameCheck = false  -> only warns on a mismatch and still loads.
    -- StrictGameCheck = true   -> refuses to load outside Blox Fruits.
    StrictGameCheck    = false,
    BloxFruitsPlaceIds = { 2753915549, 4442272183, 7449423635 }, -- Sea 1 / 2 / 3
    BloxFruitsGameId   = 994732206,

    -- GUI parent. Tried in order; the first one that verifiably works is used.
    -- To force one, set ForceParent = "PlayerGui" (or "CoreGui" / "gethui").
    ParentOrder = { "gethui", "CoreGui", "PlayerGui" },
    ForceParent = nil,

    Theme = {
        Black        = Color3.fromRGB(8, 9, 13),
        Background   = Color3.fromRGB(13, 15, 23),
        Panel        = Color3.fromRGB(19, 22, 33),
        Surface      = Color3.fromRGB(26, 30, 44),
        SurfaceHover = Color3.fromRGB(34, 39, 58),
        Stroke       = Color3.fromRGB(44, 51, 74),
        Text         = Color3.fromRGB(255, 255, 255),
        TextDim      = Color3.fromRGB(150, 158, 184),
        Blue         = Color3.fromRGB(62, 132, 255),
        BlueSoft     = Color3.fromRGB(120, 176, 255),
        Purple       = Color3.fromRGB(146, 92, 255),
        PurpleSoft   = Color3.fromRGB(186, 146, 255),
        ToggleOff    = Color3.fromRGB(52, 58, 80),
        Danger       = Color3.fromRGB(235, 80, 96),
    },
}
local T = Config.Theme

local GUI_NAME  = "EliteifiedEssentials_BloxFruits"
local DIAG_NAME = "EliteifiedEssentials_Diagnostics"

----------------------------------------------------------------
-- 2. SERVICES + SHARED STATE
----------------------------------------------------------------
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local LocalPlayer, Gui, ParentUsed
-- BasicFarm is the ONE shared state for the Basic Farms toggles.
-- It is "Bones", "Cake", "Nearest", "Levels", or nil (nothing selected).
local State = {
    -- EE v1.4: UI portal/glow FX only (NOT Blox Fruits combat animations). Default OFF for phones.
    Effects            = false,
    BasicFarm          = nil,
    AutoRandomSurprise = false,
    AutoTryLuck        = false,
    AutoPray           = false,
    CombatMode         = "Melee",
    AttackDelayMs      = 0.05,
    TweenSpeed         = 250,
    FarmDistance       = 8,    -- studs above NPC while farming (0-30); lower = easier melee hits
    FastAttack         = true, -- rapid M1 clicks while farming
    BringEnabled       = false,
    BringRange         = 100,
    BringMaxTargets    = 5,
    FarmPaused         = false,
    Status = {
        ActiveMode      = "none",
        CurrentTarget   = "-",
        CurrentAction   = "idle",
        LastError       = "-",
        BringStatus     = "disabled",
        EnemiesSelected = 0,
        EquippedItem    = "-",
        DetectedCategory = "Unknown",
        ModeMatch       = "Unknown",
        HakiStatus      = "Unknown",
    },
}
local Connections = {}
local Animators   = {}
local Window      = { Tabs = {}, Selected = nil, Minimized = false }
local Notify      = function() end
-- generation: incremented on every mode change / Stop All so stale tween waits abort
local FarmRuntime = {
    running = false,
    task = nil,
    activeTween = nil,
    generation = 0,
    -- move: { tween, hrp, wasAnchored, tripId } — owned by the active tweenTo; cleared on finish/cancel
    move = nil,
    tripId = 0, -- diagnostic: increments once per tweenTo attempt
    cfWatchConn = nil, -- diagnostic: temporary CFrame watcher
    cfWatchGen = 0,    -- disconnect token so delayed stops don't kill a newer watch
}
local FarmUI = {
    modeToggles = {},
    bonesOptionRows = {},
    statusLabels = {},
    setFarmMode = nil, -- filled in stageFarming; sole writer of BasicFarm from UI
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Connections, c)
    return c
end

----------------------------------------------------------------
-- 3. DIAGNOSTICS (console + on-screen panel)
----------------------------------------------------------------
local Diag = { Lines = {}, Gui = nil, Label = nil, Failed = false }
local DIAG_COLORS = {
    OK = "120,220,160", WARN = "255,200,90", FAIL = "255,100,115", INFO = "170,185,220",
}

local function esc(s)
    s = tostring(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    return s
end

local function refreshDiag()
    if not Diag.Label then return end
    local parts = {}
    local first = math.max(1, #Diag.Lines - 11)
    for i = first, #Diag.Lines do
        local l = Diag.Lines[i]
        parts[#parts + 1] = string.format('<font color="rgb(%s)">[%s]</font> %s',
            DIAG_COLORS[l.kind] or DIAG_COLORS.INFO, l.kind, esc(l.msg))
    end
    pcall(function() Diag.Label.Text = table.concat(parts, "\n") end)
end

local function log(kind, msg)
    local line = "[EE] [" .. kind .. "] " .. tostring(msg)
    if kind == "FAIL" or kind == "WARN" then warn(line) else print(line) end
    table.insert(Diag.Lines, { kind = kind, msg = tostring(msg) })
    if kind == "FAIL" then Diag.Failed = true end
    refreshDiag()
end

----------------------------------------------------------------
-- 4. UTILITIES
----------------------------------------------------------------
local warnedOnce = {}
local function warnOnce(key, msg)
    if warnedOnce[key] then return end
    warnedOnce[key] = true
    log("WARN", msg)
end

-- Builds an instance. A property that fails to set is reported but does NOT abort the UI.
local function new(class, props, children)
    local inst = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            local ok, err = pcall(function() inst[k] = v end)
            if not ok then
                warnOnce(class .. "." .. tostring(k), "Could not set " .. class .. "." .. tostring(k) .. " (" .. tostring(err) .. ")")
            end
        end
    end
    for _, child in ipairs(children or {}) do child.Parent = inst end
    if parent then inst.Parent = parent end
    return inst
end

local function tween(obj, time, goal, style, dir)
    local ok, tw = pcall(function()
        local t = TweenService:Create(obj,
            TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
        t:Play()
        return t
    end)
    if not ok then
        warnOnce("tween", "Tween failed: " .. tostring(tw))
        return nil
    end
    return tw
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function round()   return new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) end

local function stroke(color, thickness, transparency)
    return new("UIStroke", {
        Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function getEnv()
    local ok, env = pcall(function()
        if typeof(getgenv) == "function" then return getgenv() end
        return nil
    end)
    if ok and type(env) == "table" then return env end
    return _G
end

-- Returns the container Instance for a parent mode, or nil + reason.
local function getContainer(mode)
    if mode == "gethui" then
        local okType, t = pcall(function() return typeof(gethui) end)
        if not okType or t ~= "function" then return nil, "gethui is not available" end
        local ok, res = pcall(gethui)
        if ok and typeof(res) == "Instance" then return res end
        return nil, "gethui() failed: " .. tostring(res)

    elseif mode == "CoreGui" then
        local ok, core = pcall(function() return game:GetService("CoreGui") end)
        if not ok or not core then return nil, "CoreGui service unavailable" end
        local probe = Instance.new("Folder")
        local okSet, err = pcall(function() probe.Parent = core end)
        pcall(function() probe:Destroy() end)
        if not okSet then return nil, "CoreGui not writable: " .. tostring(err) end
        return core

    elseif mode == "PlayerGui" then
        if not LocalPlayer then return nil, "LocalPlayer missing" end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
        if pg then return pg end
        return nil, "PlayerGui not found"
    end
    return nil, "unknown parent mode '" .. tostring(mode) .. "'"
end

local function protect(gui)
    pcall(function() if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then syn.protect_gui(gui) end end)
    pcall(function() if typeof(protect_gui) == "function" then protect_gui(gui) end end)
    pcall(function() if typeof(protectgui) == "function" then protectgui(gui) end end)
end

-- Forward declarations so close-button + toggle share one hide/show path
local createDiagGui
local setLogsVisible

createDiagGui = function()
    if not Config.Diagnostics or Diag.Gui then return end
    local ok, err = pcall(function()
        local container = getContainer("PlayerGui") or getContainer("gethui") or getContainer("CoreGui")
        if not container then error("no GUI container available") end
        pcall(function()
            local old = container:FindFirstChild(DIAG_NAME)
            if old then old:Destroy() end
        end)
        local g = new("ScreenGui", {
            Name = DIAG_NAME, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        })
        g.Parent = container
        local panel = new("Frame", {
            BackgroundColor3 = T.Black, BackgroundTransparency = 0.08, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10),
            Size = UDim2.fromOffset(400, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = g,
        }, {
            corner(8), stroke(T.Blue, 1, 0.3),
            new("UIPadding", {
                PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 26),
            }),
        })
        Diag.Label = new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            Font = Enum.Font.Code, TextSize = 12, TextColor3 = T.Text, RichText = true, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Text = "", Parent = panel,
        })
        local close = new("TextButton", {
            BackgroundTransparency = 1, Text = "×", Font = Enum.Font.GothamBold, TextSize = 16,
            TextColor3 = T.TextDim, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4),
            Size = UDim2.fromOffset(20, 20), Parent = panel,
        })
        -- Hide panel (do not destroy): preserves Diag.Lines and avoids duplicate ScreenGuis
        close.MouseButton1Click:Connect(function()
            setLogsVisible(false)
        end)
        Diag.Gui = g
        Diag.Visible = true
        refreshDiag()
    end)
    if not ok then warn("[EE] [WARN] Diagnostics panel unavailable: " .. tostring(err)) end
end

-- Show/hide diagnostics panel without clearing Diag.Lines history
setLogsVisible = function(visible)
    visible = visible and true or false
    if visible then
        if not Diag.Gui then
            createDiagGui()
        end
        if Diag.Gui then
            pcall(function() Diag.Gui.Enabled = true end)
            refreshDiag()
        end
    else
        if Diag.Gui then
            pcall(function() Diag.Gui.Enabled = false end)
        end
    end
    Diag.Visible = visible
    if FarmUI and FarmUI.logsToggleBtn then
        pcall(function()
            FarmUI.logsToggleBtn.Text = visible and "Hide Logs" or "Show Logs"
        end)
    end
end

local function finishDiag(success)
    if not Diag.Gui or not success then return end
    local delaySec = Config.DiagnosticsAutoHide
    if delaySec and delaySec > 0 then
        task.delay(delaySec, function()
            if not Diag.Failed and Diag.Gui then
                -- Hide only; keep Gui so Show Logs can reopen without recreating
                setLogsVisible(false)
            end
        end)
    end
end

local function Cleanup()
    pcall(function()
        FarmRuntime.running = false
        FarmRuntime.generation = FarmRuntime.generation + 1
        -- Inline move cleanup (cancelFarmTween is defined later in the file; do not depend on it here)
        local tw = FarmRuntime.activeTween
        local m = FarmRuntime.move
        local cTrip = (m and m.tripId) or FarmRuntime.tripId or 0
        FarmRuntime.activeTween = nil
        FarmRuntime.move = nil
        if tw then
            pcall(function() log("INFO", "HRP_WRITE Cleanup Cancel tween trip=" .. tostring(cTrip)) end)
            pcall(function() tw:Cancel() end)
        end
        if m and m.tween and m.tween ~= tw then
            pcall(function() log("INFO", "HRP_WRITE Cleanup Cancel move.tween trip=" .. tostring(cTrip)) end)
            pcall(function() m.tween:Cancel() end)
        end
        if m and m.hrp and m.hrp.Parent then
            pcall(function()
                log("INFO", "HRP_WRITE Cleanup Anchored=" .. tostring(m.wasAnchored)
                    .. " trip=" .. tostring(cTrip))
            end)
            pcall(function() m.hrp.Anchored = m.wasAnchored end)
        end
        if FarmRuntime.task then
            pcall(function() task.cancel(FarmRuntime.task) end)
            FarmRuntime.task = nil
        end
        -- Diagnostic: drop CFrame watcher (stopCfWatch defined later; disconnect raw conn here)
        FarmRuntime.cfWatchGen = (FarmRuntime.cfWatchGen or 0) + 1
        if FarmRuntime.cfWatchConn then
            pcall(function() FarmRuntime.cfWatchConn:Disconnect() end)
            FarmRuntime.cfWatchConn = nil
        end
    end)
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    for i = #Animators, 1, -1 do Animators[i] = nil end
    if Gui then pcall(function() Gui:Destroy() end) end
    if Diag.Gui then pcall(function() Diag.Gui:Destroy() end) end
end

----------------------------------------------------------------
-- 5. ICONS (UI primitives only, no asset IDs)
----------------------------------------------------------------
local Icons = {}

function Icons.Home(parent)
    local holder = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18),
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 7), Parent = parent,
    })
    local roof = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(9, 6),
        Size = UDim2.fromOffset(9, 9), Rotation = 45, BorderSizePixel = 0, Parent = holder,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 1) }) })
    local body = new("Frame", {
        Position = UDim2.fromOffset(4, 7), Size = UDim2.fromOffset(10, 10),
        BorderSizePixel = 0, Parent = holder,
    }, { new("UICorner", { CornerRadius = UDim.new(0, 2) }) })
    return {
        SetColor = function(c)
            roof.BackgroundColor3 = c
            body.BackgroundColor3 = c
        end,
    }
end

-- Farming tab icon: a simple target (ring + centre dot), built from UI primitives.
function Icons.Farming(parent)
    local holder = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18),
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 7), Parent = parent,
    })
    local ring = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = holder,
    }, { round() })
    local ringStroke = stroke(T.TextDim, 2, 0)
    ringStroke.Parent = ring
    local dot = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(6, 6), BackgroundColor3 = T.TextDim, BorderSizePixel = 0, Parent = holder,
    }, { round() })
    return {
        SetColor = function(c)
            ringStroke.Color = c
            dot.BackgroundColor3 = c
        end,
    }
end

----------------------------------------------------------------
-- 6. COMPONENTS
----------------------------------------------------------------

-- 6a. Reusable purple toggle switch
local function CreateToggle(parent, opts)
    opts = opts or {}
    local state = opts.Default == true
    local hasDesc = opts.Description ~= nil

    local row = new("TextButton", {
        Name = opts.Name or "Toggle", Text = "", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, hasDesc and 52 or 44),
        LayoutOrder = opts.LayoutOrder or 0, Parent = parent,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })

    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, hasDesc and 8 or 0),
        Size = UDim2.new(1, -130, 0, hasDesc and 18 or 44), Font = Enum.Font.GothamMedium,
        TextSize = 14, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Text = opts.Name or "Toggle", Parent = row,
    })
    if hasDesc then
        new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 27),
            Size = UDim2.new(1, -130, 0, 16), Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Text = opts.Description, Parent = row,
        })
    end

    local stateLabel = new("TextLabel", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -68, 0.5, 0), Size = UDim2.fromOffset(34, 16),
        Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
        Text = "OFF", TextColor3 = T.TextDim, Parent = row,
    })
    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(42, 22), BackgroundColor3 = T.ToggleOff, BorderSizePixel = 0, Parent = row,
    }, { round() })
    local trackStroke = stroke(T.Purple, 1.5, 1)
    trackStroke.Parent = track
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(16, 16), BackgroundColor3 = T.TextDim, BorderSizePixel = 0, Parent = track,
    }, { round() })

    local object = { Instance = row }

    local function render(instant)
        local d = instant and 0 or 0.22
        tween(track, d, { BackgroundColor3 = state and T.Purple or T.ToggleOff })
        tween(trackStroke, d, { Transparency = state and 0.35 or 1 })
        tween(knob, d, {
            Position = state and UDim2.new(0, 23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = state and T.Text or T.TextDim,
        }, Enum.EasingStyle.Back)
        stateLabel.Text = state and "ON" or "OFF"
        tween(stateLabel, d, { TextColor3 = state and T.PurpleSoft or T.TextDim })
    end

    function object:Set(value, silent)
        state = value and true or false
        render(false)
        -- EE v1.4 stability: SyncCallback runs inline (needed for farm mode; avoids task.spawn races)
        if not silent and opts.Callback then
            if opts.SyncCallback then
                opts.Callback(state)
            else
                task.spawn(opts.Callback, state)
            end
        end
    end
    function object:Get() return state end

    connect(row.MouseButton1Click, function() object:Set(not state) end)
    connect(row.MouseEnter, function() tween(row, 0.15, { BackgroundColor3 = T.SurfaceHover }) end)
    connect(row.MouseLeave, function() tween(row, 0.15, { BackgroundColor3 = T.Surface }) end)

    render(true)
    return object
end

-- EE v1.4 ADDITION: simple value slider (drag on track)
local function clampNum(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function CreateSlider(parent, opts)
    opts = opts or {}
    local minV = opts.Min or 0
    local maxV = opts.Max or 1
    local step = opts.Step or 0.01
    local value = opts.Default
    if value == nil then value = minV end
    value = clampNum(value, minV, maxV)

    local row = new("Frame", {
        Name = opts.Name or "Slider", BackgroundColor3 = T.Surface,
        Size = UDim2.new(1, 0, 0, 56), LayoutOrder = opts.LayoutOrder or 0, Parent = parent,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })

    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6),
        Size = UDim2.new(1, -100, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 13,
        TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = opts.Name or "Slider", Parent = row,
    })
    local valueLabel = new("TextLabel", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 6), Size = UDim2.fromOffset(80, 18),
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.PurpleSoft,
        TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = row,
    })
    if opts.Description then
        new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 24),
            Size = UDim2.new(1, -28, 0, 12), Font = Enum.Font.Gotham, TextSize = 10,
            TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
            Text = opts.Description, Parent = row,
        })
    end

    local track = new("Frame", {
        BackgroundColor3 = T.ToggleOff, BorderSizePixel = 0,
        Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -28, 0, 6), Parent = row,
    }, { round() })
    local fill = new("Frame", {
        BackgroundColor3 = T.Purple, BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0), Parent = track,
    }, { round() })
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = T.Text, BorderSizePixel = 0, Parent = track,
    }, { round() })

    local object = { Instance = row }

    local function formatValue(v)
        if opts.Format then return opts.Format(v) end
        if step >= 1 then return tostring(math.floor(v + 0.5)) end
        return string.format("%.2f", v)
    end

    local function apply(v, silent)
        v = clampNum(v, minV, maxV)
        if step >= 1 then
            v = math.floor(v / step + 0.5) * step
        else
            v = math.floor(v / step + 0.5) * step
        end
        v = clampNum(v, minV, maxV)
        value = v
        local alpha = (maxV > minV) and ((v - minV) / (maxV - minV)) or 0
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = formatValue(v)
        if not silent and opts.Callback then task.spawn(opts.Callback, v) end
    end

    function object:Set(v, silent) apply(v, silent) end
    function object:Get() return value end

    local dragging = false
    local function valueFromX(x)
        local abs = track.AbsolutePosition.X
        local w = track.AbsoluteSize.X
        if w <= 0 then return value end
        local a = clampNum((x - abs) / w, 0, 1)
        return minV + a * (maxV - minV)
    end

    connect(track.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            apply(valueFromX(input.Position.X), false)
        end
    end)
    connect(knob.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            apply(valueFromX(input.Position.X), false)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    apply(value, true)
    return object
end

-- EE v1.4 ADDITION: cycle button through a list of options
local function CreateCycle(parent, opts)
    opts = opts or {}
    local options = opts.Options or { "A", "B" }
    local index = 1
    for i, o in ipairs(options) do
        if o == opts.Default then index = i break end
    end

    local row = new("TextButton", {
        Name = opts.Name or "Cycle", Text = "", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, opts.Description and 52 or 44),
        LayoutOrder = opts.LayoutOrder or 0, Parent = parent,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })

    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, opts.Description and 8 or 0),
        Size = UDim2.new(1, -120, 0, opts.Description and 18 or 44), Font = Enum.Font.GothamMedium,
        TextSize = 14, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = opts.Name or "Option", Parent = row,
    })
    if opts.Description then
        new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 27),
            Size = UDim2.new(1, -120, 0, 16), Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
            Text = opts.Description, Parent = row,
        })
    end
    local valLabel = new("TextLabel", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(100, 20),
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.BlueSoft,
        TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(options[index]), Parent = row,
    })

    local object = { Instance = row }
    function object:Get() return options[index] end
    function object:Set(v, silent)
        for i, o in ipairs(options) do
            if tostring(o) == tostring(v) then
                index = i
                valLabel.Text = tostring(options[index])
                if not silent and opts.Callback then task.spawn(opts.Callback, options[index]) end
                return
            end
        end
    end

    connect(row.MouseButton1Click, function()
        index = (index % #options) + 1
        valLabel.Text = tostring(options[index])
        if opts.Callback then task.spawn(opts.Callback, options[index]) end
    end)
    connect(row.MouseEnter, function() tween(row, 0.15, { BackgroundColor3 = T.SurfaceHover }) end)
    connect(row.MouseLeave, function() tween(row, 0.15, { BackgroundColor3 = T.Surface }) end)
    return object
end

-- 6b. E.E. brand button, Portal-Fruit-style swirling energy
local function CreateBrandButton(parent, opts)
    opts = opts or {}
    local hovered = false

    local btn = new("TextButton", {
        Name = "BrandButton", Text = "", AutoButtonColor = false, ClipsDescendants = true,
        BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, opts.Height or 104),
        LayoutOrder = opts.LayoutOrder or 0, Parent = parent,
    }, {
        corner(14),
        new("UIGradient", {
            Rotation = 35,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 10, 28)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(26, 12, 56)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 20, 50)),
            }),
        }),
    })

    local border = new("UIStroke", {
        Thickness = 1.5, Color = Color3.new(1, 1, 1), Transparency = 0.25,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = btn,
    })
    local borderGradient = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, T.Blue),
            ColorSequenceKeypoint.new(0.5, T.Purple),
            ColorSequenceKeypoint.new(1, T.Blue),
        }),
        Parent = border,
    })

    -- Soft portal core glow (stacked translucent circles)
    local core = {}
    for i, spec in ipairs({ { 180, 0.92, T.Blue }, { 120, 0.84, T.Purple }, { 72, 0.7, T.BlueSoft } }) do
        local f = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(spec[1], spec[1]), BackgroundColor3 = spec[3],
            BackgroundTransparency = spec[2], BorderSizePixel = 0, Parent = btn,
        }, { round() })
        core[i] = { frame = f, base = spec[2] }
    end

    -- Swirling energy rings (rotating gradient strokes)
    local rings = {}
    local ringSpecs = {
        -- size, thickness, speed(deg/s), colorA, colorB
        { 300, 2,    -22, T.Blue,       T.Purple },
        { 236, 3,     38, T.Purple,     T.BlueSoft },
        { 184, 2.5,  -62, T.BlueSoft,   T.Purple },
        { 138, 3,     96, T.Blue,       T.PurpleSoft },
        { 96,  2,   -140, T.PurpleSoft, T.Blue },
    }
    for _, s in ipairs(ringSpecs) do
        local frame = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(s[1], s[1]), BackgroundTransparency = 1, BorderSizePixel = 0,
            Rotation = math.random(0, 359), Parent = btn,
        }, {
            round(),
            new("UIStroke", {
                Thickness = s[2], Color = Color3.new(1, 1, 1),
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            }, {
                new("UIGradient", {
                    Color = ColorSequence.new(s[4], s[5]),
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(0.3, 0.05),
                        NumberSequenceKeypoint.new(0.6, 0.7),
                        NumberSequenceKeypoint.new(1, 1),
                    }),
                }),
            }),
        })
        table.insert(rings, { frame = frame, speed = s[3] })
    end

    -- Centre shade so the lettering stays readable
    new("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), Parent = btn,
    }, {
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0.55),
                NumberSequenceKeypoint.new(1, 1),
            }),
        }),
    })

    -- Lettering
    new("TextLabel", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.43, 0), Size = UDim2.new(1, 0, 0, 48),
        Font = Enum.Font.GothamBlack, TextSize = 40, TextColor3 = Color3.new(1, 1, 1),
        Text = opts.Main or Config.BrandMain, Parent = btn,
    }, {
        new("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 200, 255)),
        }),
        new("UIStroke", { Color = T.Blue, Thickness = 1.5, Transparency = 0.5 }),
    })
    new("TextLabel", {
        BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.8, 0), Size = UDim2.new(1, 0, 0, 16),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Color3.fromRGB(205, 218, 255),
        Text = opts.Sub or Config.BrandSub, Parent = btn,
    })

    local flash = new("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = btn,
    })

    connect(btn.MouseEnter, function()
        hovered = true
        tween(border, 0.2, { Transparency = 0 })
    end)
    connect(btn.MouseLeave, function()
        hovered = false
        tween(border, 0.25, { Transparency = 0.25, Thickness = 1.5 })
    end)
    connect(btn.MouseButton1Down, function() tween(border, 0.1, { Thickness = 2.5 }) end)
    connect(btn.MouseButton1Up,   function() tween(border, 0.15, { Thickness = 1.5 }) end)
    connect(btn.MouseButton1Click, function()
        flash.BackgroundTransparency = 0.7
        tween(flash, 0.5, { BackgroundTransparency = 1 })
        if opts.Callback then task.spawn(opts.Callback) end
    end)

    local boost = 1
    table.insert(Animators, function(dt, t)
        if not State.Effects or not btn.Visible then return end
        boost = boost + ((hovered and 2.4 or 1) - boost) * math.min(1, dt * 6)
        for _, r in ipairs(rings) do
            r.frame.Rotation = (r.frame.Rotation + r.speed * boost * dt) % 360
        end
        borderGradient.Rotation = (borderGradient.Rotation + 30 * boost * dt) % 360
        for i, c in ipairs(core) do
            c.frame.BackgroundTransparency = c.base + 0.06 * math.sin(t * 2 + i)
        end
    end)

    return btn
end

----------------------------------------------------------------
-- 7. STARTUP STAGES (each runs protected; failures are reported)
----------------------------------------------------------------
local function getViewport()
    for _ = 1, 30 do
        local cam = workspace.CurrentCamera
        local s = cam and cam.ViewportSize
        if s and s.X >= 200 and s.Y >= 150 then return s end
        task.wait(0.1)
    end
    log("WARN", "Camera viewport not ready; using 1280x720 fallback")
    return Vector2.new(1280, 720)
end

-- Stage 1 ------------------------------------------------------
local function stageEnvironment()
    local t0 = os.clock()
    while not game:IsLoaded() and os.clock() - t0 < 15 do task.wait(0.1) end
    if not game:IsLoaded() then log("WARN", "game:IsLoaded() still false after 15s; continuing anyway") end

    LocalPlayer = Players.LocalPlayer
    t0 = os.clock()
    while not LocalPlayer and os.clock() - t0 < 10 do
        task.wait(0.1)
        LocalPlayer = Players.LocalPlayer
    end
    if not LocalPlayer then error("Players.LocalPlayer is nil (not running as a client script?)", 0) end

    createDiagGui() -- shows earlier log lines too

    pcall(function()
        local exec = "unknown"
        if typeof(identifyexecutor) == "function" then
            local a, b = identifyexecutor()
            exec = tostring(a) .. (b and (" " .. tostring(b)) or "")
        end
        log("INFO", "Executor: " .. exec)
        log("INFO", "gethui=" .. typeof(gethui) .. " getgenv=" .. typeof(getgenv))
    end)

    -- Remove a previous run, if any
    pcall(function()
        local prev = getEnv().EliteifiedEssentials
        if prev and type(prev.Cleanup) == "function" then prev.Cleanup() end
    end)
end

-- Stage 2 ------------------------------------------------------
local function stageGameCheck()
    local matched = false
    for _, id in ipairs(Config.BloxFruitsPlaceIds) do
        if game.PlaceId == id then matched = true break end
    end
    if game.GameId == Config.BloxFruitsGameId then matched = true end

    log("INFO", "PlaceId=" .. tostring(game.PlaceId) .. "  GameId=" .. tostring(game.GameId))
    if matched then
        log("OK", "Blox Fruits detected")
        return
    end
    local msg = "This place does not match the Blox Fruits IDs in Config."
    if Config.StrictGameCheck then
        error(msg .. " (StrictGameCheck = true, so the UI will not load.)", 0)
    end
    log("WARN", msg .. " Loading anyway (StrictGameCheck = false).")
end

-- Stage 3 ------------------------------------------------------
local function stageParent()
    Gui = new("ScreenGui", {
        Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    })
    protect(Gui)

    local order = Config.ForceParent and { Config.ForceParent } or Config.ParentOrder

    -- Remove stale copies from every container
    for _, mode in ipairs({ "gethui", "CoreGui", "PlayerGui" }) do
        local c = getContainer(mode)
        if c then
            pcall(function()
                local old = c:FindFirstChild(GUI_NAME)
                if old then old:Destroy() end
            end)
        end
    end

    for _, mode in ipairs(order) do
        local container, reason = getContainer(mode)
        if not container then
            log("WARN", "Parent '" .. mode .. "' skipped: " .. tostring(reason))
        else
            local ok, err = pcall(function() Gui.Parent = container end)
            if ok and Gui.Parent == container then
                ParentUsed = mode
                log("OK", "GUI parent: " .. mode .. " (" .. container.ClassName .. ")")
                return
            end
            log("WARN", "Parent '" .. mode .. "' rejected the GUI: " .. tostring(err))
        end
    end
    error("No usable GUI parent (tried: " .. table.concat(order, ", ") .. ")", 0)
end

-- Stage 4 ------------------------------------------------------
local function stageNotifications()
    local holder = new("Frame", {
        Name = "Notifications", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.fromOffset(280, 320), Parent = Gui,
    }, {
        new("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
        }),
    })

    Notify = function(title, text, duration, accent)
        task.spawn(function()
            duration = duration or 4
            accent   = accent or T.Purple

            local wrap = new("Frame", {
                BackgroundTransparency = 1, Size = UDim2.fromOffset(280, 64), Parent = holder,
            })
            local toast = new("Frame", {
                BackgroundColor3 = T.Panel, Position = UDim2.new(1.25, 0, 0, 0),
                Size = UDim2.fromScale(1, 1), Parent = wrap,
            }, {
                corner(10), stroke(accent, 1, 0.55),
                new("Frame", {
                    BackgroundColor3 = accent, BorderSizePixel = 0,
                    Position = UDim2.fromOffset(9, 10), Size = UDim2.new(0, 3, 1, -20),
                }, { round() }),
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 8),
                    Size = UDim2.new(1, -32, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14,
                    TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, Text = title,
                }),
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 27),
                    Size = UDim2.new(1, -32, 0, 30), Font = Enum.Font.Gotham, TextSize = 12,
                    TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = text,
                }),
            })

            tween(toast, 0.45, { Position = UDim2.new(0, 0, 0, 0) }, Enum.EasingStyle.Back)
            task.wait(duration)
            tween(toast, 0.35, { Position = UDim2.new(1.25, 0, 0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.wait(0.4)
            wrap:Destroy()
        end)
    end
end

-- Stage 5 ------------------------------------------------------
local function runAnimators(dt, t)
    for _, fn in ipairs(Animators) do fn(dt, t) end
end

local function stageWindow()
    local viewport = getViewport()
    local TH, SW = Config.TitleBarHeight, Config.SidebarWidth
    -- Clamped so the window can never end up zero or negative sized.
    local W = math.max(320, math.min(Config.WindowSize.X, viewport.X - 24))
    local H = math.max(230, math.min(Config.WindowSize.Y, viewport.Y - 24))
    log("INFO", string.format("Viewport %.0fx%.0f -> window %.0fx%.0f", viewport.X, viewport.Y, W, H))

    local Root = new("Frame", {
        Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H),
        Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2 + 30), Parent = Gui,
    })
    Window.Root = Root
    Window.Size = Vector2.new(W, H)

    -- Layered glow behind the window
    for _, g in ipairs({ { 26, 0.965, T.Blue }, { 12, 0.93, T.Purple } }) do
        new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, g[1], 1, g[1]), BackgroundColor3 = g[3],
            BackgroundTransparency = g[2], BorderSizePixel = 0, Parent = Root,
        }, { corner(22) })
    end

    local Main = new("Frame", {
        Name = "Main", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        ClipsDescendants = true, Size = UDim2.fromScale(1, 1), Parent = Root,
    }, {
        corner(14),
        new("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new(Color3.fromRGB(16, 19, 30), Color3.fromRGB(9, 10, 15)),
        }),
    })
    local mainStroke = new("UIStroke", {
        Thickness = 1.5, Color = Color3.new(1, 1, 1), Transparency = 0.35,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = Main,
    })
    local mainStrokeGradient = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, T.Blue),
            ColorSequenceKeypoint.new(0.5, T.Purple),
            ColorSequenceKeypoint.new(1, T.Blue),
        }),
        Parent = mainStroke,
    })
    table.insert(Animators, function(dt)
        if State.Effects then
            mainStrokeGradient.Rotation = (mainStrokeGradient.Rotation + 12 * dt) % 360
        end
    end)

    -- Title bar ------------------------------------------------
    local TitleBar = new("Frame", {
        Name = "TitleBar", BackgroundTransparency = 1, Active = true,
        Size = UDim2.new(1, 0, 0, TH), Parent = Main,
    })
    new("TextLabel", {
        Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -110, 1, 0), Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, RichText = true,
        Text = Config.Title .. ' <font color="rgb(94,150,255)">' .. Config.GameTag .. "</font>",
        Parent = TitleBar,
    })

    local function titleButton(text, offsetX, hoverColor)
        local b = new("TextButton", {
            AutoButtonColor = false, BackgroundColor3 = T.Surface, Text = text,
            Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = T.TextDim,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, offsetX, 0.5, 0),
            Size = UDim2.fromOffset(28, 28), Parent = TitleBar,
        }, { corner(8) })
        connect(b.MouseEnter, function()
            tween(b, 0.15, { BackgroundColor3 = hoverColor, TextColor3 = T.Text })
        end)
        connect(b.MouseLeave, function()
            tween(b, 0.15, { BackgroundColor3 = T.Surface, TextColor3 = T.TextDim })
        end)
        return b
    end
    local MinBtn   = titleButton("–", -46, T.Blue)
    local CloseBtn = titleButton("×", -12, T.Danger)

    -- Body: sidebar | white divider | content ---------------------
    local Body = new("Frame", {
        Name = "Body", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, TH), Size = UDim2.new(1, 0, 1, -TH), Parent = Main,
    })

    local Sidebar = new("Frame", {
        Name = "Sidebar", BackgroundTransparency = 1,
        Size = UDim2.new(0, SW, 1, -12), Parent = Body,
    }, {
        new("UIListLayout", {
            Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        new("UIPadding", { PaddingTop = UDim.new(0, 4) }),
    })

    new("Frame", { -- thin white vertical divider
        Name = "Divider", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2,
        BorderSizePixel = 0, Position = UDim2.fromOffset(SW, 4), Size = UDim2.new(0, 1, 1, -16),
        Parent = Body,
    })

    local Content = new("Frame", {
        Name = "Content", BackgroundColor3 = T.Panel, BorderSizePixel = 0,
        Position = UDim2.fromOffset(SW + 11, 0), Size = UDim2.new(1, -(SW + 11 + 12), 1, -12),
        ClipsDescendants = true, Parent = Body,
    }, { corner(12), stroke(T.Stroke, 1, 0.45) })

    -- Tabs -----------------------------------------------------
    function Window:SelectTab(tab)
        self.Selected = tab
        for _, t in ipairs(self.Tabs) do
            local on = (t == tab)
            t.Page.Visible = on
            tween(t.Button, 0.2, { BackgroundTransparency = on and 0.82 or 1 })
            tween(t.Accent, 0.2, { BackgroundTransparency = on and 0 or 1 })
            tween(t.Label, 0.2, { TextColor3 = on and T.Text or T.TextDim })
            t.Icon.SetColor(on and T.BlueSoft or T.TextDim)
        end
    end

    function Window:AddTab(opts)
        opts = opts or {}
        local tab = { Name = opts.Name or "Tab", _order = 0 }

        tab.Button = new("TextButton", {
            Name = tab.Name .. "Tab", AutoButtonColor = false, Text = "",
            BackgroundColor3 = T.Blue, BackgroundTransparency = 1,
            Size = UDim2.fromOffset(46, 50), LayoutOrder = #self.Tabs + 1, Parent = Sidebar,
        }, { corner(10) })
        tab.Accent = new("Frame", {
            BackgroundColor3 = T.Purple, BackgroundTransparency = 1, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -6, 0.5, 0),
            Size = UDim2.fromOffset(3, 26), Parent = tab.Button,
        }, { round() })
        tab.Icon = (opts.Icon or Icons.Home)(tab.Button)
        tab.Label = new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 14),
            Font = Enum.Font.GothamMedium, TextSize = 10, TextColor3 = T.TextDim,
            Text = tab.Name, Parent = tab.Button,
        })

        tab.Page = new("ScrollingFrame", {
            Name = tab.Name .. "Page", BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), Visible = false,
            ScrollBarThickness = 3, ScrollBarImageColor3 = T.Purple,
            AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
            ScrollingDirection = Enum.ScrollingDirection.Y, Parent = Content,
        }, {
            new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
            new("UIPadding", {
                PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
                PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
            }),
        })

        local function nextOrder()
            tab._order = tab._order + 1
            return tab._order
        end

        function tab:AddHeader(title, subtitle)
            local f = new("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44),
                LayoutOrder = nextOrder(), Parent = tab.Page,
            })
            new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Font = Enum.Font.GothamBold,
                TextSize = 20, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left,
                Text = title, Parent = f,
            })
            if subtitle then
                new("TextLabel", {
                    BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 16),
                    Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = T.TextDim,
                    TextXAlignment = Enum.TextXAlignment.Left, Text = subtitle, Parent = f,
                })
            end
            return f
        end

        function tab:AddSection(text)
            return new("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = nextOrder(),
                Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.TextDim,
                TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(text), Parent = tab.Page,
            })
        end

        function tab:AddToggle(o)
            o = o or {}
            o.LayoutOrder = nextOrder()
            return CreateToggle(tab.Page, o)
        end

        function tab:AddBrandButton(o)
            o = o or {}
            o.LayoutOrder = nextOrder()
            return CreateBrandButton(tab.Page, o)
        end

        -- EE v1.4 ADDITION
        function tab:AddSlider(o)
            o = o or {}
            o.LayoutOrder = nextOrder()
            return CreateSlider(tab.Page, o)
        end

        function tab:AddCycle(o)
            o = o or {}
            o.LayoutOrder = nextOrder()
            return CreateCycle(tab.Page, o)
        end

        connect(tab.Button.MouseButton1Click, function() Window:SelectTab(tab) end)
        connect(tab.Button.MouseEnter, function()
            if Window.Selected ~= tab then tween(tab.Button, 0.15, { BackgroundTransparency = 0.92 }) end
        end)
        connect(tab.Button.MouseLeave, function()
            if Window.Selected ~= tab then tween(tab.Button, 0.15, { BackgroundTransparency = 1 }) end
        end)

        table.insert(self.Tabs, tab)
        self:SelectTab(self.Selected or tab)
        return tab
    end

    -- Dragging (mouse + touch) ------------------------------------
    local dragging, dragStart, startPos
    connect(TitleBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, Root.Position
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    c:Disconnect()
                end
            end)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            Root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                      startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    -- Minimize / close / hotkey -------------------------------------
    function Window:SetMinimized(value)
        self.Minimized = value
        if value then
            tween(Root, 0.3, { Size = UDim2.fromOffset(W, TH) }, Enum.EasingStyle.Quint)
            task.delay(0.28, function() if self.Minimized then Body.Visible = false end end)
        else
            Body.Visible = true
            tween(Root, 0.35, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Quint)
        end
        MinBtn.Text = value and "+" or "–"
    end

    function Window:Destroy()
        -- Stop farm movement immediately; full Cleanup (task cancel, GUI destroy) stays delayed
        FarmRuntime.running = false
        FarmRuntime.generation = FarmRuntime.generation + 1
        pcall(function()
            if type(cancelFarmTween) == "function" then
                cancelFarmTween()
            end
        end)
        tween(Root, 0.25, { Size = UDim2.fromOffset(W, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        task.delay(0.28, function()
            Cleanup()
            pcall(function() getEnv().EliteifiedEssentials = nil end)
        end)
    end

    connect(MinBtn.MouseButton1Click, function() Window:SetMinimized(not Window.Minimized) end)
    connect(CloseBtn.MouseButton1Click, function() Window:Destroy() end)
    connect(UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Config.ToggleKey then
            Root.Visible = not Root.Visible
        end
    end)

    -- Single animation loop; an error here stops animations, never the UI.
    local animFailed = false
    connect(RunService.RenderStepped, function(dt)
        if animFailed then return end
        local ok, err = pcall(runAnimators, dt, os.clock())
        if not ok then
            animFailed = true
            log("WARN", "Animation loop stopped: " .. tostring(err))
        end
    end)

    -- Opening animation
    tween(Root, 0.55, { Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2) }, Enum.EasingStyle.Back)
end

-- Stage 6 ------------------------------------------------------
local function stageHome()
    local Home = Window:AddTab({ Name = "Home", Icon = Icons.Home })

    Home:AddHeader("Home", "Welcome to " .. Config.Title)

    Home:AddBrandButton({
        Callback = function()
            Notify("Welcome to " .. Config.Title,
                "Hello, " .. LocalPlayer.DisplayName .. "! The UI is ready for Blox Fruits.", 4, T.Purple)
        end,
    })

    Home:AddSection("Interface")
    Home:AddToggle({
        Name = "Animated Effects",
        Description = "UI portal swirl/glow only (not game combat animations)",
        Default = false, -- EE v1.4: OFF by default for mobile performance
        Callback = function(on) State.Effects = on end,
    })

    pcall(function()
        getEnv().EliteifiedEssentials = {
            Window = Window, Notify = Notify, Icons = Icons, Theme = T, Config = Config,
            CreateToggle = CreateToggle, CreateBrandButton = CreateBrandButton, Cleanup = Cleanup,
            State = State, FarmRuntime = FarmRuntime,
        }
    end)
end

-- Stage 6b: Farming tab (EE v1.4 layout) --------------------------------
local function stageFarming()
    local Farming = Window:AddTab({ Name = "Farming", Icon = Icons.Farming })

    ----------------------------------------------------------------
    -- EE v1.4 ADDITION: Combat Settings (top of tab)
    ----------------------------------------------------------------
    Farming:AddSection("Combat Settings")

    Farming:AddCycle({
        Name = "Selected Mode",
        Description = "Equips a matching tool from backpack when possible",
        Options = { "Melee", "Blox Fruits", "Sword", "Gun" },
        Default = State.CombatMode,
        Callback = function(v)
            State.CombatMode = v
            log("INFO", "Combat mode: " .. tostring(v))
            -- Try to equip immediately when the user changes mode
            pcall(function()
                if type(equipBestTool) == "function" then
                    equipBestTool()
                end
            end)
            if FarmUI.refreshStatusUI then pcall(FarmUI.refreshStatusUI) end
        end,
    })

    Farming:AddSlider({
        Name = "Attack Delay",
        Description = "UI scale 0.0-5.0 (ms label). Loops clamp to a safe wait.",
        Min = 0, Max = 5, Step = 0.01, Default = State.AttackDelayMs,
        Format = function(v) return string.format("%.2f ms", v) end,
        Callback = function(v)
            State.AttackDelayMs = v
            log("INFO", "Attack delay UI value: " .. string.format("%.2f", v))
        end,
    })

    Farming:AddSlider({
        Name = "Tween Speed",
        Description = "Movement speed used by farm tweens (50-300)",
        Min = 50, Max = 300, Step = 1, Default = State.TweenSpeed,
        Format = function(v) return tostring(math.floor(v + 0.5)) end,
        Callback = function(v)
            State.TweenSpeed = v
            log("INFO", "Tween speed: " .. tostring(math.floor(v + 0.5)))
        end,
    })

    Farming:AddSlider({
        Name = "Farm Distance",
        Description = "Height above NPC while farming (studs)",
        Min = 0, Max = 30, Step = 1, Default = State.FarmDistance,
        Format = function(v) return tostring(math.floor(v + 0.5)) .. " studs" end,
        Callback = function(v)
            State.FarmDistance = v
            log("INFO", "Farm distance: " .. tostring(math.floor(v + 0.5)))
        end,
    })

    Farming:AddToggle({
        Name = "Fast Attack",
        Description = "Rapid M1 clicks while farming",
        Default = State.FastAttack == true,
        Callback = function(on)
            State.FastAttack = on
            log("INFO", "Fast Attack: " .. tostring(on))
        end,
    })

    ----------------------------------------------------------------
    -- EE v1.4 ADDITION: Bring Enemies (config UI only)
    ----------------------------------------------------------------
    Farming:AddSection("Bring Enemies")

    local bringStatusLabel
    local function refreshBringStatus()
        if State.BringEnabled then
            local maxTxt = (State.BringMaxTargets == math.huge) and "All" or tostring(State.BringMaxTargets)
            State.Status.BringStatus = string.format("configured %dstud max=%s (UI only)", State.BringRange, maxTxt)
        else
            State.Status.BringStatus = "disabled"
        end
        State.Status.EnemiesSelected = 0 -- no live pull; counter stays 0 unless updated elsewhere
        if bringStatusLabel then
            bringStatusLabel.Text = "Status: " .. State.Status.BringStatus
                .. "  |  Selected: " .. tostring(State.Status.EnemiesSelected)
        end
    end

    Farming:AddToggle({
        Name = "Enable Bring Enemies",
        Description = "Config only in v1.4 — does not force NPC movement",
        Default = false,
        Callback = function(on)
            State.BringEnabled = on
            refreshBringStatus()
            log("INFO", "Bring Enemies config: " .. tostring(on))
        end,
    })

    Farming:AddSlider({
        Name = "Bring Range",
        Description = "Configured range in studs (25-500)",
        Min = 25, Max = 500, Step = 1, Default = State.BringRange,
        Format = function(v) return tostring(math.floor(v + 0.5)) .. " studs" end,
        Callback = function(v)
            State.BringRange = v
            refreshBringStatus()
        end,
    })

    Farming:AddCycle({
        Name = "Max Targets",
        Description = "Configured max target count",
        Options = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "All" },
        Default = "5",
        Callback = function(v)
            if v == "All" then
                State.BringMaxTargets = math.huge
            else
                State.BringMaxTargets = tonumber(v) or 5
            end
            refreshBringStatus()
        end,
    })

    bringStatusLabel = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28),
        LayoutOrder = 0, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = T.TextDim, TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true, Text = "Status: disabled  |  Selected: 0", Parent = Farming.Page,
    })
    -- fix layout order via page's next order: re-parent after section items by setting LayoutOrder high enough
    pcall(function()
        local n = 0
        for _, ch in ipairs(Farming.Page:GetChildren()) do
            if ch:IsA("GuiObject") and typeof(ch.LayoutOrder) == "number" then
                n = math.max(n, ch.LayoutOrder)
            end
        end
        bringStatusLabel.LayoutOrder = n + 1
    end)
    refreshBringStatus()

    ----------------------------------------------------------------
    -- Basic Farms — single synchronous writer for State.BasicFarm
    ----------------------------------------------------------------
    Farming:AddSection("Basic Farms")

    local FARM_OPTIONS = { "Bones", "Cake", "Nearest", "Levels" }
    local farmToggles = FarmUI.modeToggles
    local bonesOptionRows = FarmUI.bonesOptionRows

    -- EE v1.4 recovery: sole UI writer for BasicFarm (sync, logged, cancels movement)
    local function setFarmMode(newMode, reason)
        local prev = State.BasicFarm
        if newMode ~= nil and newMode ~= "Bones" and newMode ~= "Cake"
            and newMode ~= "Nearest" and newMode ~= "Levels" then
            log("WARN", "setFarmMode rejected invalid mode: " .. tostring(newMode))
            return
        end
        if prev ~= newMode then
            State.BasicFarm = newMode
            FarmRuntime.generation = FarmRuntime.generation + 1
            pcall(function()
                if type(cancelFarmTween) == "function" then cancelFarmTween() end
            end)
            log("INFO", string.format(
                "Mode change: %s -> %s (reason: %s, gen=%d)",
                tostring(prev or "none"), tostring(newMode or "none"),
                tostring(reason or "?"), FarmRuntime.generation
            ))
        end
        State.Status.ActiveMode = State.BasicFarm or "none"
        State.Status.CurrentAction = State.BasicFarm and "idle" or "stopped"
        if not State.BasicFarm then
            State.Status.CurrentTarget = "-"
        end

        -- Sync mode toggle visuals only (silent = no callbacks)
        for _, name in ipairs(FARM_OPTIONS) do
            local toggle = farmToggles[name]
            if toggle then
                local should = (State.BasicFarm == name)
                if toggle:Get() ~= should then
                    toggle:Set(should, true)
                end
            end
        end

        -- Bones options: visible only when Bones is active (visibility only — no callbacks)
        local showBonesOpts = (State.BasicFarm == "Bones")
        for _, row in pairs(bonesOptionRows) do
            if row and row.Instance then
                row.Instance.Visible = showBonesOpts
            end
        end

        if FarmUI.refreshStatusUI then pcall(FarmUI.refreshStatusUI) end
        if prev ~= newMode then
            if newMode then
                Notify("Farming", "Mode: " .. newMode, 3, T.Blue)
            else
                Notify("Farming", "All farms stopped", 3, T.TextDim)
            end
        end
    end
    FarmUI.setFarmMode = setFarmMode

    local function makeModeToggle(name)
        farmToggles[name] = Farming:AddToggle({
            Name = name,
            Default = false,
            SyncCallback = true,
            Callback = function(on)
                if on then
                    setFarmMode(name, "user toggle ON " .. name)
                elseif State.BasicFarm == name then
                    setFarmMode(nil, "user toggle OFF " .. name)
                else
                    if farmToggles[name] then farmToggles[name]:Set(false, true) end
                end
            end,
        })
        return farmToggles[name]
    end

    -- Layout: Bones -> three Bones options -> Cake -> Nearest -> Levels
    makeModeToggle("Bones")

    -- Restored Bones submenu (regression fix): always created, shown only when Bones is ON
    local function makeBonesOption(name, desc, stateKey)
        local tog = Farming:AddToggle({
            Name = name,
            Description = desc,
            Default = false,
            Callback = function(on)
                State[stateKey] = on
                log("INFO", name .. ": " .. tostring(on))
            end,
        })
        if tog and tog.Instance then
            tog.Instance.Visible = false -- hidden until Bones is enabled
        end
        return tog
    end
    bonesOptionRows.Random = makeBonesOption(
        "Auto Random Surprise", "Death King - 50 Bones per roll", "AutoRandomSurprise")
    bonesOptionRows.TryLuck = makeBonesOption(
        "Auto Try Luck", "Gravestone - Try Your Luck (night)", "AutoTryLuck")
    bonesOptionRows.Pray = makeBonesOption(
        "Auto Pray", "Gravestone - Pray (night)", "AutoPray")

    makeModeToggle("Cake")
    makeModeToggle("Nearest")
    makeModeToggle("Levels")

    ----------------------------------------------------------------
    -- EE v1.4 ADDITION: Diagnostics + controls
    ----------------------------------------------------------------
    Farming:AddSection("Diagnostics")

    local function addStatusLine(key, initial)
        local lbl = new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
            Font = Enum.Font.Code, TextSize = 11, TextColor3 = T.TextDim,
            TextXAlignment = Enum.TextXAlignment.Left, Text = initial, Parent = Farming.Page,
        })
        pcall(function()
            local n = 0
            for _, ch in ipairs(Farming.Page:GetChildren()) do
                if ch:IsA("GuiObject") and typeof(ch.LayoutOrder) == "number" then
                    n = math.max(n, ch.LayoutOrder)
                end
            end
            lbl.LayoutOrder = n + 1
        end)
        FarmUI.statusLabels[key] = lbl
        return lbl
    end

    addStatusLine("ActiveMode", "Active Mode: none")
    addStatusLine("CurrentTarget", "Current Target: -")
    addStatusLine("CurrentAction", "Current Action: idle")
    addStatusLine("LastError", "Last Error: -")
    addStatusLine("EquippedItem", "Equipped Item: -")
    addStatusLine("ModeMatch", "Mode Match: Unknown")
    addStatusLine("HakiStatus", "Haki: Unknown")
    addStatusLine("BringStatus", "Bring Enemies: disabled")
    addStatusLine("EnemiesSelected", "Enemies Selected: 0")

    local function refreshStatusUI()
        local S = State.Status
        local map = {
            ActiveMode = "Active Mode: " .. tostring(S.ActiveMode),
            CurrentTarget = "Current Target: " .. tostring(S.CurrentTarget),
            CurrentAction = "Current Action: " .. tostring(S.CurrentAction),
            LastError = "Last Error: " .. tostring(S.LastError),
            EquippedItem = "Equipped Item: " .. tostring(S.EquippedItem),
            ModeMatch = "Mode Match: " .. tostring(S.ModeMatch)
                .. " (selected " .. tostring(State.CombatMode)
                .. " / detected " .. tostring(S.DetectedCategory) .. ")",
            HakiStatus = "Haki: " .. tostring(S.HakiStatus),
            BringStatus = "Bring Enemies: " .. tostring(S.BringStatus),
            EnemiesSelected = "Enemies Selected: " .. tostring(S.EnemiesSelected),
        }
        for key, text in pairs(map) do
            if FarmUI.statusLabels[key] then
                FarmUI.statusLabels[key].Text = text
            end
        end
    end
    FarmUI.refreshStatusUI = refreshStatusUI

    -- Pause toggle
    Farming:AddToggle({
        Name = "Pause Farming",
        Description = "Pauses farm controller ticks without clearing mode",
        Default = false,
        Callback = function(on)
            State.FarmPaused = on
            State.Status.CurrentAction = on and "paused" or "idle"
            if FarmUI.refreshStatusUI then FarmUI.refreshStatusUI() end
            log("INFO", "Farm paused: " .. tostring(on))
        end,
    })

    -- Clear Log button
    local clearBtn = new("TextButton", {
        Name = "ClearLog", Text = "Clear Log", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.Text, Parent = Farming.Page,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })
    pcall(function()
        local n = 0
        for _, ch in ipairs(Farming.Page:GetChildren()) do
            if ch:IsA("GuiObject") and typeof(ch.LayoutOrder) == "number" then
                n = math.max(n, ch.LayoutOrder)
            end
        end
        clearBtn.LayoutOrder = n + 1
    end)
    connect(clearBtn.MouseButton1Click, function()
        Diag.Lines = {}
        Diag.Failed = false
        refreshDiag()
        State.Status.LastError = "-"
        if FarmUI.refreshStatusUI then FarmUI.refreshStatusUI() end
        log("INFO", "Diagnostics log cleared")
    end)

    -- Show / Hide Logs (panel only; Diag.Lines history is never cleared by this)
    local logsToggleBtn = new("TextButton", {
        Name = "ToggleLogs", Text = "Hide Logs", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.Text, Parent = Farming.Page,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })
    pcall(function()
        logsToggleBtn.LayoutOrder = clearBtn.LayoutOrder + 1
    end)
    FarmUI.logsToggleBtn = logsToggleBtn
    connect(logsToggleBtn.MouseButton1Click, function()
        local open = Diag.Gui and Diag.Gui.Enabled ~= false and Diag.Visible ~= false
        setLogsVisible(not open)
        log("INFO", "Logs panel " .. ((Diag.Visible and "shown") or "hidden"))
    end)
    -- Sync label with actual panel state after load
    pcall(function()
        local open = Diag.Gui ~= nil and Diag.Gui.Enabled ~= false
        logsToggleBtn.Text = open and "Hide Logs" or "Show Logs"
        Diag.Visible = open
    end)

    -- Copy full Diag.Lines history to clipboard (not only the last ~12 visible lines)
    local copyBtn = new("TextButton", {
        Name = "CopyLogs", Text = "Copy Logs to Clipboard", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.Text, Parent = Farming.Page,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })
    pcall(function()
        copyBtn.LayoutOrder = logsToggleBtn.LayoutOrder + 1
    end)
    connect(copyBtn.MouseButton1Click, function()
        local parts = {}
        for i = 1, #Diag.Lines do
            local l = Diag.Lines[i]
            parts[#parts + 1] = string.format("[EE] [%s] %s", tostring(l.kind), tostring(l.msg))
        end
        local text = table.concat(parts, "\n")
        if text == "" then
            text = "[EE] [INFO] (log buffer is empty)"
        end

        local ok, err = false, "no clipboard API"
        -- Common executor clipboard helpers (try in order)
        if type(setclipboard) == "function" then
            ok, err = pcall(setclipboard, text)
        elseif type(toclipboard) == "function" then
            ok, err = pcall(toclipboard, text)
        elseif type(Clipboard) == "table" and type(Clipboard.set) == "function" then
            ok, err = pcall(Clipboard.set, text)
        else
            ok = false
            err = "setclipboard/toclipboard not available in this executor"
        end

        if ok then
            log("OK", "Copied " .. tostring(#Diag.Lines) .. " log line(s) to clipboard")
            Notify("Logs", "Copied " .. tostring(#Diag.Lines) .. " lines to clipboard", 3, T.Blue)
        else
            -- Fallback: keep full text in getgenv + print so the user can still recover it
            pcall(function()
                getEnv().EliteifiedEssentials_LastLogs = text
            end)
            print("[EE] --- BEGIN COPIED LOGS (clipboard unavailable) ---")
            print(text)
            print("[EE] --- END COPIED LOGS ---")
            log("WARN", "Clipboard copy failed: " .. tostring(err)
                .. " — full log printed to console and saved to getgenv().EliteifiedEssentials_LastLogs")
            Notify("Logs", "Clipboard unavailable — see console / getgenv", 4, T.Danger)
        end
    end)

    -- Stop All button
    local stopBtn = new("TextButton", {
        Name = "StopAll", Text = "Stop All", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = T.Danger, Parent = Farming.Page,
    }, { corner(10), stroke(T.Danger, 1, 0.5) })
    pcall(function()
        stopBtn.LayoutOrder = copyBtn.LayoutOrder + 1
    end)
    connect(stopBtn.MouseButton1Click, function()
        State.AutoRandomSurprise = false
        State.AutoTryLuck = false
        State.AutoPray = false
        State.FarmPaused = false
        State.Status.EnemiesSelected = 0
        if FarmUI.setFarmMode then
            FarmUI.setFarmMode(nil, "Stop All")
        else
            State.BasicFarm = nil
            FarmRuntime.generation = FarmRuntime.generation + 1
        end
        -- F2: every Stop All branch cancels movement + restores saved anchored state
        pcall(function()
            if type(cancelFarmTween) == "function" then
                cancelFarmTween()
            end
        end)
        log("OK", "Stop All: modes cleared, UI synced, gen=" .. tostring(FarmRuntime.generation))
        Notify("Farming", "All modes stopped", 3, T.Danger)
    end)

    -- Save settings (UI prefs only)
    local saveBtn = new("TextButton", {
        Name = "SaveSettings", Text = "Save Settings", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.BlueSoft, Parent = Farming.Page,
    }, { corner(10), stroke(T.Blue, 1, 0.5) })
    pcall(function()
        saveBtn.LayoutOrder = stopBtn.LayoutOrder + 1
    end)
    connect(saveBtn.MouseButton1Click, function()
        local ok, err = pcall(function()
            local env = getEnv()
            env.EliteifiedEssentials_Settings = {
                CombatMode = State.CombatMode,
                AttackDelayMs = State.AttackDelayMs,
                TweenSpeed = State.TweenSpeed,
                BringEnabled = State.BringEnabled,
                BringRange = State.BringRange,
                BringMaxTargets = State.BringMaxTargets,
            }
        end)
        if ok then
            log("OK", "Settings saved to getgenv().EliteifiedEssentials_Settings")
            Notify("Settings", "UI preferences saved", 3, T.Blue)
        else
            log("WARN", "Save settings failed: " .. tostring(err))
        end
    end)

    -- Load saved settings if present
    pcall(function()
        local s = getEnv().EliteifiedEssentials_Settings
        if type(s) == "table" then
            if s.CombatMode then State.CombatMode = s.CombatMode end
            if s.AttackDelayMs then State.AttackDelayMs = s.AttackDelayMs end
            if s.TweenSpeed then State.TweenSpeed = s.TweenSpeed end
            if s.BringEnabled ~= nil then State.BringEnabled = s.BringEnabled end
            if s.BringRange then State.BringRange = s.BringRange end
            if s.BringMaxTargets then State.BringMaxTargets = s.BringMaxTargets end
            refreshBringStatus()
            log("INFO", "Loaded saved UI settings")
        end
    end)
end

----------------------------------------------------------------
-- 7. GAMEPLAY MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")

local function getCharacter()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then
        return char, hrp, hum
    end
    return nil
end

local function getCommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return nil end
    return remotes:FindFirstChild("CommF_")
end

-- EE diagnostic: compact position string (not every frame)
local function fmtPos(v3)
    if not v3 then return "?" end
    return string.format("(%.1f, %.1f, %.1f)", v3.X, v3.Y, v3.Z)
end

-- EE diagnostic only: stop temporary HRP CFrame watcher (no movement side effects)
local function stopCfWatch()
    FarmRuntime.cfWatchGen = (FarmRuntime.cfWatchGen or 0) + 1
    local c = FarmRuntime.cfWatchConn
    FarmRuntime.cfWatchConn = nil
    if c then
        pcall(function() c:Disconnect() end)
    end
end

-- EE diagnostic only: observe CFrame changes (throttled). Does not claim cause.
-- phase "during" = tween in progress; "after" = post-COMPLETE snap window
local function startCfWatch(hrp, char, tripId, phase, durationSec)
    stopCfWatch()
    if not hrp or not hrp.Parent then return end
    local watchGen = FarmRuntime.cfWatchGen
    local t0 = os.clock()
    local lastPos = hrp.Position
    local lastLogAt = 0
    local minInterval = (phase == "after") and 0.04 or 0.12
    local minDist = (phase == "after") and 0.25 or 8 -- skip tiny tween steps while flying

    local conn
    conn = hrp:GetPropertyChangedSignal("CFrame"):Connect(function()
        if watchGen ~= FarmRuntime.cfWatchGen then return end
        if not hrp.Parent then return end
        local now = os.clock()
        if (now - lastLogAt) < minInterval then return end
        local newPos = hrp.Position
        local moved = (newPos - lastPos).Magnitude
        if moved < minDist then return end
        lastLogAt = now
        local curChar = LocalPlayer.Character
        local sameChar = (curChar ~= nil and char ~= nil and curChar == char)
        local hrpIsCurrent = curChar and hrp:IsDescendantOf(curChar)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local humState = "?"
        local humHp = "?"
        if hum then
            pcall(function()
                humState = tostring(hum:GetState())
                humHp = string.format("%.0f", hum.Health)
            end)
        end
        log("INFO", string.format(
            "CF_CHANGE phase=%s trip=%s dt=%.3fs moved=%.1f old=%s new=%s anchored=%s sameChar=%s hrpIsCurrent=%s hp=%s state=%s gen=%s",
            tostring(phase),
            tostring(tripId),
            now - t0,
            moved,
            fmtPos(lastPos),
            fmtPos(newPos),
            tostring(hrp.Anchored),
            tostring(sameChar),
            tostring(hrpIsCurrent == true),
            humHp,
            humState,
            tostring(FarmRuntime.generation)
        ))
        lastPos = newPos
    end)
    FarmRuntime.cfWatchConn = conn

    task.delay(durationSec or 0.5, function()
        if watchGen == FarmRuntime.cfWatchGen and FarmRuntime.cfWatchConn == conn then
            stopCfWatch()
            log("INFO", "CF_WATCH end phase=" .. tostring(phase) .. " trip=" .. tostring(tripId))
        end
    end)
end

-- EE diagnostic: log character / HRP replacements once each time they happen
pcall(function()
    LocalPlayer.CharacterAdded:Connect(function(char)
        stopCfWatch()
        log("INFO", "Character respawned/replaced gen=" .. tostring(FarmRuntime.generation)
            .. " trip=" .. tostring(FarmRuntime.tripId))
        pcall(function()
            local hrp = char:WaitForChild("HumanoidRootPart", 5)
            if hrp then
                log("INFO", "New HumanoidRootPart at " .. fmtPos(hrp.Position))
            end
        end)
    end)
end)

-- EE v1.4: cancel in-flight farm tween and always restore that move's anchored state
local function cancelFarmTween()
    local m = FarmRuntime.move
    local tw = FarmRuntime.activeTween
    local had = (m ~= nil) or (tw ~= nil)
    local cancelTrip = (m and m.tripId) or FarmRuntime.tripId or 0
    FarmRuntime.move = nil
    FarmRuntime.activeTween = nil
    if tw then
        log("INFO", "HRP_WRITE cancelFarmTween Cancel tween trip=" .. tostring(cancelTrip))
        pcall(function() tw:Cancel() end)
    elseif m and m.tween then
        log("INFO", "HRP_WRITE cancelFarmTween Cancel move.tween trip=" .. tostring(cancelTrip))
        pcall(function() m.tween:Cancel() end)
    end
    -- Restore only the HRP this move anchored; ignore if part is gone (respawn)
    if m and m.hrp and m.hrp.Parent then
        log("INFO", "HRP_WRITE cancelFarmTween Anchored=" .. tostring(m.wasAnchored)
            .. " trip=" .. tostring(cancelTrip))
        pcall(function() m.hrp.Anchored = m.wasAnchored end)
    end
    -- Also clear any farm-hold anchor (stay-above-NPC) so mode changes never leave you frozen
    pcall(function()
        local char = LocalPlayer and LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            log("INFO", "HRP_WRITE cancelFarmTween force Anchored=false trip=" .. tostring(cancelTrip))
            hrp.Anchored = false
        end
    end)
    -- Diagnostic only: log when there was something to cancel
    if had then
        local pos = "?"
        pcall(function()
            local _, hrp = getCharacter()
            if hrp then pos = fmtPos(hrp.Position) end
        end)
        log("INFO", "cancelFarmTween trip=" .. tostring(cancelTrip)
            .. " gen=" .. tostring(FarmRuntime.generation) .. " pos=" .. pos)
    end
end

-- opts.stayAnchored = true keeps HRP anchored at destination after a successful tween
-- (used for Bones/Cake search waypoints so we do not immediately float free at the destination)
local function tweenTo(cf, speed, gen, opts)
    opts = opts or {}
    local stayAnchored = opts.stayAnchored == true

    local char, hrp = getCharacter()
    if not char or not hrp then return false end

    -- Speed: optional explicit argument, else State.TweenSpeed (clamped to UI range 50-300)
    speed = tonumber(speed) or tonumber(State.TweenSpeed) or 250
    if speed < 50 then speed = 50 end
    if speed > 300 then speed = 300 end

    cancelFarmTween() -- finishes previous move (cancels + unanchors its HRP)
    if gen and gen ~= FarmRuntime.generation then return false end

    -- Diagnostic: unique trip id for this tweenTo attempt (captured by delayed samples)
    FarmRuntime.tripId = (FarmRuntime.tripId or 0) + 1
    local tripId = FarmRuntime.tripId

    local dist = (hrp.Position - cf.Position).Magnitude
    -- Duration follows configured speed: t = dist / speed (no max cap that defeats the slider)
    local t = dist / speed
    if t < 0.05 then t = 0.05 end

    local wasAnchored = hrp.Anchored
    local move = {
        tween = nil,
        hrp = hrp,
        wasAnchored = wasAnchored,
        tripId = tripId,
        stayAnchored = stayAnchored,
    }

    -- Own the move slot before any state change; every exit path must release or hand off via cancel.
    FarmRuntime.move = move
    FarmRuntime.activeTween = nil

    -- Diagnostic: tween start (once per tween)
    log("INFO", string.format(
        "tweenTo START trip=%d gen=%s dist=%.1f stayAnchored=%s from=%s to=%s",
        tripId,
        tostring(gen or FarmRuntime.generation),
        dist,
        tostring(stayAnchored),
        fmtPos(hrp.Position),
        fmtPos(cf.Position)
    ))

    local function releaseIfOwner()
        if FarmRuntime.move ~= move then
            log("INFO", "releaseIfOwner SKIP (not owner) trip=" .. tostring(tripId)
                .. " gen=" .. tostring(FarmRuntime.generation))
            return -- cancelFarmTween / newer move already cleaned up
        end
        local ownedTw = move.tween
        if FarmRuntime.activeTween == ownedTw then
            FarmRuntime.activeTween = nil
        end

        if stayAnchored and hrp.Parent then
            -- Keep ownership slot so cancelFarmTween still knows which HRP we pinned
            -- Re-pin CFrame and stay anchored (search waypoint)
            log("INFO", "HRP_WRITE releaseIfOwner PIN stayAnchored trip=" .. tostring(tripId))
            pcall(function()
                hrp.Anchored = true
                hrp.CFrame = cf
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end)
            move.tween = nil
            log("INFO", "releaseIfOwner DONE (pinned) trip=" .. tostring(tripId)
                .. " gen=" .. tostring(FarmRuntime.generation)
                .. " pos=" .. fmtPos(hrp.Position)
                .. " anchored=true")
            return
        end

        FarmRuntime.move = nil
        if hrp.Parent then
            log("INFO", "HRP_WRITE releaseIfOwner Anchored=" .. tostring(wasAnchored)
                .. " trip=" .. tostring(tripId))
            pcall(function() hrp.Anchored = wasAnchored end)
        end
        log("INFO", "releaseIfOwner DONE trip=" .. tostring(tripId)
            .. " gen=" .. tostring(FarmRuntime.generation)
            .. " pos=" .. fmtPos(hrp.Parent and hrp.Position or nil)
            .. " anchored->" .. tostring(wasAnchored))
    end

    -- F1: Create, Play, and Wait are all inside pcall so failures cannot skip restore
    local ok = pcall(function()
        log("INFO", "HRP_WRITE tweenTo Anchored=true trip=" .. tostring(tripId))
        hrp.Anchored = true

        log("INFO", "HRP_WRITE tweenTo CFrame tween trip=" .. tostring(tripId)
            .. " to=" .. fmtPos(cf.Position))
        local tw = TweenService:Create(
            hrp,
            TweenInfo.new(t, Enum.EasingStyle.Linear),
            { CFrame = cf }
        )
        move.tween = tw
        FarmRuntime.activeTween = tw
        -- Diagnostic: throttled CFrame observer during flight (not ownership claims)
        startCfWatch(hrp, char, tripId, "during", math.min(math.max(t + 0.5, 1), 45))
        tw:Play()
        tw.Completed:Wait()
    end)

    -- Always release if we still own the slot (does not rely solely on Completed resuming)
    releaseIfOwner()

    local endPos = hrp.Parent and fmtPos(hrp.Position) or "?"
    if not ok then
        stopCfWatch()
        log("WARN", "tweenTo FAIL/CANCEL trip=" .. tostring(tripId)
            .. " gen=" .. tostring(gen or FarmRuntime.generation) .. " pos=" .. endPos)
        return false
    end
    if gen and gen ~= FarmRuntime.generation then
        stopCfWatch()
        log("INFO", "tweenTo STALE trip=" .. tostring(tripId)
            .. " gen arg=" .. tostring(gen) .. " now=" .. tostring(FarmRuntime.generation) .. " pos=" .. endPos)
        return false
    end
    log("INFO", "tweenTo COMPLETE trip=" .. tostring(tripId)
        .. " gen=" .. tostring(gen or FarmRuntime.generation) .. " pos=" .. endPos
        .. " anchored=" .. tostring(hrp.Anchored)
        .. " stayAnchored=" .. tostring(stayAnchored)
        .. " sameChar=" .. tostring(LocalPlayer.Character == char))

    -- Diagnostic: post-COMPLETE window; replaces "during" watcher
    startCfWatch(hrp, char, tripId, "after", 0.55)

    -- Diagnostic only: sample after cleanup. Closures capture THIS tripId (not a later trip).
    local sampleHrp = hrp
    local sampleChar = char
    local sampleGen = tostring(gen or FarmRuntime.generation)
    local sampleTrip = tripId
    local function postSample(label)
        local curChar = LocalPlayer.Character
        local sameChar = (curChar ~= nil and sampleChar ~= nil and curChar == sampleChar)
        local hrpOk = sampleHrp and sampleHrp.Parent ~= nil
        local hrpIsCurrent = hrpOk and curChar and sampleHrp:IsDescendantOf(curChar)
        if hrpOk then
            log("INFO", string.format(
                "%s trip=%d gen=%s pos=%s anchored=%s sameChar=%s hrpIsCurrent=%s curTrip=%s",
                label, sampleTrip, sampleGen, fmtPos(sampleHrp.Position),
                tostring(sampleHrp.Anchored), tostring(sameChar), tostring(hrpIsCurrent == true),
                tostring(FarmRuntime.tripId)
            ))
        else
            log("INFO", string.format(
                "%s trip=%d gen=%s pos=(hrp gone) sameChar=%s hrpIsCurrent=false curTrip=%s",
                label, sampleTrip, sampleGen, tostring(sameChar), tostring(FarmRuntime.tripId)
            ))
        end
    end
    task.defer(function() postSample("tweenTo POST-defer") end)
    task.delay(0.2, function() postSample("tweenTo POST-0.2s") end)
    task.delay(0.6, function() postSample("tweenTo POST-0.6s") end)

    return true
end

local function getFarmHeight()
    local h = tonumber(State.FarmDistance)
    if h == nil then h = 15 end
    if h < 0 then h = 0 end
    if h > 30 then h = 30 end
    return h
end

-- Keep character above a target root while farming (must be re-applied every tick)
local function holdAboveTarget(targetRoot)
    local char, hrp, hum = getCharacter()
    if not char or not hrp or not targetRoot or not targetRoot.Parent then return false end
    local height = getFarmHeight()
    -- Diagnostic: only log the first hold in a streak (not every attack tick)
    if not FarmRuntime._holdLogged then
        FarmRuntime._holdLogged = true
        log("INFO", "holdAboveTarget BEGIN height=" .. tostring(height)
            .. " trip=" .. tostring(FarmRuntime.tripId)
            .. " gen=" .. tostring(FarmRuntime.generation)
            .. " at=" .. fmtPos(hrp.Position)
            .. " target=" .. fmtPos(targetRoot.Position))
    end
    local ok = pcall(function()
        -- Kill velocity so physics does not pull you out of the hold
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        if hum then
            hum.PlatformStand = true
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
        end
        -- HRP_WRITE logs only on first hold of streak to avoid spam each attack tick
        if not FarmRuntime._holdWriteLogged then
            FarmRuntime._holdWriteLogged = true
            log("INFO", "HRP_WRITE holdAboveTarget Anchored=true CFrame trip="
                .. tostring(FarmRuntime.tripId) .. " height=" .. tostring(height))
        end
        hrp.Anchored = true
        hrp.CFrame = targetRoot.CFrame * CFrame.new(0, height, 0)
    end)
    return ok
end

local function releaseFarmHold()
    FarmRuntime._holdLogged = false -- allow next holdAboveTarget to log once
    FarmRuntime._holdWriteLogged = false
    local char, hrp, hum = getCharacter()
    if hrp and hrp.Parent then
        log("INFO", "HRP_WRITE releaseFarmHold Anchored=false trip=" .. tostring(FarmRuntime.tripId))
        pcall(function()
            hrp.Anchored = false
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end)
    end
    if hum then
        pcall(function()
            hum.PlatformStand = false
        end)
    end
end

local function setNoCollide(model, state)
    if not model then return end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = not state
        end
    end
end

-- Expand NPC parts so M1 / touch range can register from farm height
local function expandMobHitbox(mob)
    if not mob then return end
    pcall(function()
        for _, part in ipairs(mob:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Size = Vector3.new(70, 70, 70)
                part.Transparency = 1
                part.CanCollide = false
                part.Massless = true
            end
        end
        local hum = mob:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            pcall(function() hum.JumpHeight = 0 end)
        end
    end)
end

-- EE v1.4: attack wait from UI delay (lower floor when Fast Attack is on)
local function attackWait()
    local sec = tonumber(State.AttackDelayMs) or 0.05
    if sec > 5 then sec = sec / 1000 end
    local minWait = State.FastAttack and 0.02 or 0.04
    sec = math.max(minWait, math.min(5, sec))
    task.wait(sec)
end

-- Classify a tool name into Melee / Sword / Gun / Blox Fruits / Unknown
local function categorizeToolName(name)
    local n = string.lower(tostring(name or ""))
    if n == "" then return "Unknown" end

    -- Guns first (specific)
    if string.find(n, "gun", 1, true) or string.find(n, "rifle", 1, true)
        or string.find(n, "pistol", 1, true) or string.find(n, "cannon", 1, true)
        or string.find(n, "musket", 1, true) or string.find(n, "flintlock", 1, true)
        or string.find(n, "shotgun", 1, true) or string.find(n, "acidum", 1, true)
        or string.find(n, "kabucha", 1, true) or string.find(n, "serpent bow", 1, true)
        or string.find(n, "bazooka", 1, true) then
        return "Gun"
    end

    -- Swords
    if string.find(n, "sword", 1, true) or string.find(n, "blade", 1, true)
        or string.find(n, "katana", 1, true) or string.find(n, "cutlass", 1, true)
        or string.find(n, "saber", 1, true) or string.find(n, "rapier", 1, true)
        or string.find(n, "scythe", 1, true) or string.find(n, "trident", 1, true)
        or string.find(n, "twin hooks", 1, true) or string.find(n, "shark anchor", 1, true)
        or string.find(n, "dark dagger", 1, true) or string.find(n, "midnight blade", 1, true)
        or string.find(n, "canvander", 1, true) or string.find(n, "buddy sword", 1, true)
        or string.find(n, "tushita", 1, true) or string.find(n, "yama", 1, true)
        or string.find(n, "shisui", 1, true) or string.find(n, "saddi", 1, true)
        or string.find(n, "wando", 1, true) or string.find(n, "rengoku", 1, true)
        or string.find(n, "koko", 1, true) or string.find(n, "spikey trident", 1, true)
        or string.find(n, "hallow scythe", 1, true) or string.find(n, "fox lamp", 1, true)
        or string.find(n, "pipe", 1, true) or string.find(n, "iron mace", 1, true)
        or string.find(n, "triple katana", 1, true) or string.find(n, "dual katana", 1, true)
        or string.find(n, "bisento", 1, true) or string.find(n, "soul cane", 1, true) then
        return "Sword"
    end

    -- Fighting styles (Melee)
    if string.find(n, "combat", 1, true) or string.find(n, "melee", 1, true)
        or string.find(n, "black leg", 1, true) or string.find(n, "electro", 1, true)
        or string.find(n, "fishman", 1, true) or string.find(n, "dragon claw", 1, true)
        or string.find(n, "superhuman", 1, true) or string.find(n, "death step", 1, true)
        or string.find(n, "sharkman", 1, true) or string.find(n, "godhuman", 1, true)
        or string.find(n, "sanguine", 1, true) or string.find(n, "electric claw", 1, true)
        or string.find(n, "dragon talon", 1, true) or string.find(n, "godhuman", 1, true)
        or string.find(n, "fighting style", 1, true) then
        return "Melee"
    end

    -- Blox Fruits (common fruit tool names / "Fruit")
    if string.find(n, "fruit", 1, true) or string.find(n, "-fruit", 1, true)
        or string.find(n, "dough", 1, true) or string.find(n, "dragon", 1, true)
        or string.find(n, "venom", 1, true) or string.find(n, "control", 1, true)
        or string.find(n, "shadow", 1, true) or string.find(n, "spirit", 1, true)
        or string.find(n, "mammoth", 1, true) or string.find(n, "t-rex", 1, true)
        or string.find(n, "leopard", 1, true) or string.find(n, "kitsune", 1, true)
        or string.find(n, "gas", 1, true) or string.find(n, "yeti", 1, true)
        or string.find(n, "gravity", 1, true) or string.find(n, "buddha", 1, true)
        or string.find(n, "magma", 1, true) or string.find(n, "light", 1, true)
        or string.find(n, "dark", 1, true) or string.find(n, "ice", 1, true)
        or string.find(n, "flame", 1, true) or string.find(n, "quake", 1, true)
        or string.find(n, "rumble", 1, true) or string.find(n, "portal", 1, true)
        or string.find(n, "phoenix", 1, true) or string.find(n, "sound", 1, true)
        or string.find(n, "spider", 1, true) or string.find(n, "love", 1, true)
        or string.find(n, "rubber", 1, true) or string.find(n, "barrier", 1, true)
        or string.find(n, "sand", 1, true) or string.find(n, "blizzard", 1, true) then
        return "Blox Fruits"
    end

    return "Unknown"
end

-- Equip a tool that matches State.CombatMode (unequips mismatch first)
local function equipBestTool()
    local char = LocalPlayer.Character
    if not char then return nil end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local want = State.CombatMode or "Melee"

    local function allTools()
        local list = {}
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then list[#list + 1] = t end
        end
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                if t:IsA("Tool") then list[#list + 1] = t end
            end
        end
        return list
    end

    -- Prefer already-correct equipped tool
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and categorizeToolName(equipped.Name) == want then
        return equipped
    end

    -- Unequip wrong tool so we can equip the right category
    if equipped and backpack then
        pcall(function() equipped.Parent = backpack end)
    end

    -- Find best match for selected combat mode
    local match, fallback = nil, nil
    for _, tool in ipairs(allTools()) do
        local cat = categorizeToolName(tool.Name)
        if cat == want then
            match = tool
            break
        end
        if not fallback then
            fallback = tool
        end
    end

    local chosen = match or fallback
    if not chosen then
        log("WARN", "No tool found for Combat Mode: " .. tostring(want))
        return nil
    end

    pcall(function() chosen.Parent = char end)
    local now = char:FindFirstChildOfClass("Tool") or chosen
    local cat = categorizeToolName(now.Name)
    if cat == want then
        log("INFO", "Equipped " .. now.Name .. " [" .. cat .. "] for mode " .. want)
    else
        log("WARN", "Equipped fallback " .. now.Name .. " [" .. cat .. "]; wanted " .. want)
    end
    return now
end

-- Status probe uses the same categorizer as equip
local function updateEquipmentStatus()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then
        State.Status.EquippedItem = "(none)"
        State.Status.DetectedCategory = "Unknown"
        State.Status.ModeMatch = "Unknown"
    else
        State.Status.EquippedItem = tool.Name
        local cat = categorizeToolName(tool.Name)
        State.Status.DetectedCategory = cat
        if cat == "Unknown" then
            State.Status.ModeMatch = "Unknown"
        elseif cat == State.CombatMode then
            State.Status.ModeMatch = "Match"
        else
            State.Status.ModeMatch = "Mismatch"
        end
    end
    State.Status.HakiStatus = "Unknown"
end

local function attackOnce(tool)
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(Vector2.new())
    end)
    -- Also activate the equipped tool (some weapons need this for M1)
    if tool then
        pcall(function() tool:Activate() end)
    end
end

-- Touch-interest helper: helps register hits when hitbox is expanded (if executor supports it)
local function tryTouchHit(mob)
    local char, hrp = getCharacter()
    if not char or not hrp or not mob then return end
    local root = mob:FindFirstChild("HumanoidRootPart")
    if not root then return end
    pcall(function()
        if typeof(firetouchinterest) == "function" then
            firetouchinterest(hrp, root, 0)
            firetouchinterest(hrp, root, 1)
        end
    end)
end

-- Fast M1: burst of clicks + tool activate + touch interest
local function doFarmAttack(tool, mob)
    local n = State.FastAttack and 5 or 1
    for _ = 1, n do
        tryTouchHit(mob)
        attackOnce(tool)
        task.wait(State.FastAttack and 0.02 or 0.04)
    end
end

-- Shared: tween above target, hold height, extended hitbox, attack while tracking mob
local function farmCombatOnTarget(mob, gen, modeName)
    local root = mob:FindFirstChild("HumanoidRootPart")
    local hum  = mob:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    local tool = equipBestTool()
    setNoCollide(mob, true)
    expandMobHitbox(mob)

    local height = getFarmHeight()
    State.Status.CurrentTarget = mob.Name
    State.Status.CurrentAction = "moving"

    if not tweenTo(root.CFrame * CFrame.new(0, height, 0), nil, gen) then
        releaseFarmHold()
        return
    end
    if gen ~= FarmRuntime.generation or State.BasicFarm ~= modeName then
        releaseFarmHold()
        return
    end

    -- Re-apply hold immediately after tween (tweenTo unanchors on purpose)
    holdAboveTarget(root)
    State.Status.CurrentAction = "attacking"

    local clicks = State.FastAttack and 30 or 12
    for _ = 1, clicks do
        if gen ~= FarmRuntime.generation or State.BasicFarm ~= modeName then break end
        if State.FarmPaused then break end
        if not mob.Parent or not root.Parent or hum.Health <= 0 then break end

        -- Stay locked above the NPC every tick
        if not holdAboveTarget(root) then break end
        expandMobHitbox(mob)
        tool = tool or equipBestTool()
        doFarmAttack(tool, mob)
        attackWait()
    end
    releaseFarmHold()
    State.Status.CurrentAction = "idle"
end

local BONE_MOBS = {
    "Reborn Skeleton",
    "Living Zombie",
    "Demonic Soul",
    "Posessed Mummy",
}

local function isBoneMob(name)
    for _, n in ipairs(BONE_MOBS) do
        if name == n or string.find(name, n, 1, true) then
            return true
        end
    end
    return false
end

local function findNearestEnemy(filterFn)
    local char, hrp = getCharacter()
    if not hrp then return nil end
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local best, bestDist = nil, math.huge
    for _, mob in ipairs(enemies:GetChildren()) do
        local hum = mob:FindFirstChildOfClass("Humanoid")
        local root = mob:FindFirstChild("HumanoidRootPart")
        if hum and root and hum.Health > 0 then
            if (not filterFn) or filterFn(mob.Name) then
                local d = (root.Position - hrp.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = mob
                end
            end
        end
    end
    return best, bestDist
end

local function findCakePrince()
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        local cp = enemies:FindFirstChild("Cake Prince") or enemies:FindFirstChild("Dough King")
        if cp then return cp end
    end
    return ReplicatedStorage:FindFirstChild("Cake Prince") or ReplicatedStorage:FindFirstChild("Dough King")
end

local lastSurprise = 0
local function doRandomSurprise()
    if not State.AutoRandomSurprise then return end
    if tick() - lastSurprise < 1.2 then return end
    local comm = getCommF()
    if not comm then
        log("WARN", "CommF_ not found - Random Surprise skipped")
        return
    end
    local ok, err = pcall(function()
        comm:InvokeServer("Bones", "Buy", 1, 1)
    end)
    lastSurprise = tick()
    if ok then
        log("OK", "Random Surprise fired")
    else
        log("WARN", "Random Surprise failed: " .. tostring(err))
    end
end

local GRAVESTONE_CF = CFrame.new(-8654.27, 143.45, 6169.98)
local lastGravestone = 0

local function doGravestone(action)
    if tick() - lastGravestone < 8 then return end
    local char, hrp = getCharacter()
    if not hrp then return end
    log("INFO", "Moving to Gravestone for " .. action)
    tweenTo(GRAVESTONE_CF * CFrame.new(0, 3, 4), nil, FarmRuntime.generation)
    task.wait(0.4)
    local comm = getCommF()
    local ok, err = pcall(function()
        if action == "TryLuck" then
            if comm then comm:InvokeServer("gravestoneEvent", 1) end
        else
            if comm then comm:InvokeServer("gravestoneEvent", 2) end
        end
    end)
    if not ok then
        pcall(function()
            if typeof(fireproximityprompt) == "function" then
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") then
                        local parent = obj.Parent
                        if parent and parent:IsA("BasePart") then
                            if (parent.Position - hrp.Position).Magnitude < 25 then
                                fireproximityprompt(obj)
                                break
                            end
                        end
                    end
                end
            end
        end)
        log("WARN", "Gravestone " .. action .. " failed: " .. tostring(err))
    else
        log("OK", "Gravestone " .. action .. " fired")
    end
    lastGravestone = tick()
end

local function farmBones()
    local gen = FarmRuntime.generation
    if State.AutoRandomSurprise then doRandomSurprise() end
    if State.AutoTryLuck then doGravestone("TryLuck") end
    if State.AutoPray then doGravestone("Pray") end
    if gen ~= FarmRuntime.generation or State.BasicFarm ~= "Bones" then return end

    local mob = findNearestEnemy(isBoneMob)
    if not mob then
        State.Status.CurrentAction = "searching"
        State.Status.CurrentTarget = "-"
        local char, hrp = getCharacter()
        if hrp and (hrp.Position - Vector3.new(-9500, 150, 5800)).Magnitude > 400 then
            log("INFO", "Bones: no NPC found — pathing to fixed dest gen=" .. tostring(gen)
                .. " from=" .. fmtPos(hrp.Position))
            -- Pin at destination until next move/cancel (search waypoint)
            tweenTo(CFrame.new(-9508, 142, 5737), nil, gen, { stayAnchored = true })
        else
            log("INFO", "Bones: no NPC found — already near fixed area gen=" .. tostring(gen))
        end
        return
    end

    log("INFO", "Bones: NPC found name=" .. tostring(mob.Name) .. " gen=" .. tostring(gen))
    farmCombatOnTarget(mob, gen, "Bones")
end

local function farmNearest()
    local gen = FarmRuntime.generation
    local modeName = State.BasicFarm
    if modeName ~= "Nearest" and modeName ~= "Levels" then return end
    local mob = findNearestEnemy(nil)
    if not mob then
        State.Status.CurrentTarget = "-"
        State.Status.CurrentAction = "searching"
        return
    end
    farmCombatOnTarget(mob, gen, modeName)
end

local function farmCake()
    local gen = FarmRuntime.generation
    local comm = getCommF()
    if comm then
        pcall(function()
            comm:InvokeServer("CakePrinceSpawner")
        end)
    end
    if gen ~= FarmRuntime.generation or State.BasicFarm ~= "Cake" then return end

    local prince = findCakePrince()
    if not prince then
        State.Status.CurrentAction = "searching"
        local char, hrp = getCharacter()
        if hrp and (hrp.Position - Vector3.new(-2100, 70, -12000)).Magnitude > 500 then
            tweenTo(CFrame.new(-2092, 70, -12160), nil, gen, { stayAnchored = true })
        end
        return
    end

    farmCombatOnTarget(prince, gen, "Cake")
end

local function farmLevels()
    local comm = getCommF()
    if comm then
        pcall(function()
            comm:InvokeServer("SetSpawnPoint")
        end)
    end
    farmNearest()
end

local function startFarmController()
    if FarmRuntime.running then return end
    FarmRuntime.running = true
    log("OK", "Farm controller started")

    FarmRuntime.task = task.spawn(function()
        while FarmRuntime.running do
            local mode = State.BasicFarm
            State.Status.ActiveMode = mode or "none"

            pcall(updateEquipmentStatus)

            if State.FarmPaused then
                State.Status.CurrentAction = "paused"
                if FarmUI.refreshStatusUI then pcall(FarmUI.refreshStatusUI) end
                task.wait(0.4)
            else
                local ok, err = pcall(function()
                    if mode == "Bones" then
                        farmBones()
                    elseif mode == "Cake" then
                        farmCake()
                    elseif mode == "Nearest" then
                        farmNearest()
                    elseif mode == "Levels" then
                        farmLevels()
                    else
                        State.Status.CurrentAction = "idle"
                        State.Status.CurrentTarget = "-"
                        if State.AutoRandomSurprise then doRandomSurprise() end
                        if State.AutoTryLuck then doGravestone("TryLuck") end
                        if State.AutoPray then doGravestone("Pray") end
                    end
                end)
                if not ok then
                    State.Status.LastError = tostring(err):match("^[^\n]*") or tostring(err)
                    log("WARN", "Farm tick error: " .. tostring(err))
                end
                if FarmUI.refreshStatusUI then pcall(FarmUI.refreshStatusUI) end
                if mode then
                    task.wait(0.25)
                else
                    task.wait(1.0)
                end
            end
        end
        log("INFO", "Farm controller stopped")
    end)
end

-- Stage 7 ------------------------------------------------------
local function stageVerify()
    task.wait(0.2)
    local root = Window.Root
    if not root then error("Window root was never created", 0) end
    log("INFO", "Parent=" .. tostring(ParentUsed) .. "  inDataModel=" .. tostring(Gui:IsDescendantOf(game)))
    local size, pos = root.AbsoluteSize, root.AbsolutePosition
    log("INFO", string.format("Window AbsoluteSize %.0fx%.0f at %.0f,%.0f", size.X, size.Y, pos.X, pos.Y))
    if size.X <= 0 or size.Y <= 0 then error("Window has zero size", 0) end
    if not Gui.Enabled then error("ScreenGui is disabled", 0) end
end

local function stageFarmController()
    startFarmController()
    log("OK", "Gameplay module loaded")
end

----------------------------------------------------------------
-- 8. MAIN
----------------------------------------------------------------
local stages = {
    { "Environment",     stageEnvironment },
    { "Game check",      stageGameCheck },
    { "GUI parent",      stageParent },
    { "Notifications",   stageNotifications },
    { "Main window",     stageWindow },
    { "Home page",       stageHome },
    { "Farming page",    stageFarming },
    { "Verify",          stageVerify },
    { "Farm controller", stageFarmController },
}

local function tracebackHandler(e)
    local tb = debug and debug.traceback
    if tb then return tb(tostring(e), 2) end
    return tostring(e)
end

local function runStage(name, fn)
    log("INFO", "Stage: " .. name)
    local ok, err = xpcall(fn, tracebackHandler)
    if ok then
        log("OK", name)
        return true
    end
    local text = tostring(err)
    log("FAIL", name .. " -> " .. (text:match("^[^\n]*") or text))
    warn("[EE] Full error in stage '" .. name .. "':\n" .. text)
    return false
end

for _, s in ipairs(stages) do
    if not runStage(s[1], s[2]) then
        log("FAIL", "Startup stopped at stage: " .. s[1])
        return
    end
end

log("OK", "Eliteified Essentials NEW REMAKE v1 loaded (UI + gameplay)")
finishDiag(true)
