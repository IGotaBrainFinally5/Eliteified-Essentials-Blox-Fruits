--[[
    Eliteified Essentials (BLOX FRUITS) - v1.4
    UI Framework + Gameplay Automation

    v1.3: Farming loops for Bones / Cake / Nearest / Levels + Bones Options
    v1.4: Combat Settings UI, Bring Enemies config UI (no forced pull),
          Bones expandable section, mode-sync guard, Farming diagnostics,
          Clear Log / Stop All, pause + simple settings save.

    Diagnostics: bottom-left panel + [EE] console lines.
    If nothing prints, the paste was truncated - re-copy the entire file.
]]

print("[EE] Script started - Eliteified Essentials v1.4")

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
    Effects            = true,
    BasicFarm          = nil,
    AutoRandomSurprise = false,
    AutoTryLuck        = false,
    AutoPray           = false,
    -- EE v1.4 ADDITION: combat / bring / status (UI + state)
    CombatMode         = "Melee",       -- Melee | Blox Fruits | Sword | Gun
    AttackDelayMs      = 0.12,          -- EE v1.4: UI range 0.0-5.0 (labeled ms); loops clamp safely
    TweenSpeed         = 250,           -- 50-300
    BringEnabled       = false,         -- UI config only; no forced NPC pull in v1.4
    BringRange         = 100,           -- 25-500 studs
    BringMaxTargets    = 5,             -- number 2-10, or math.huge for All
    FarmPaused         = false,
    Status = {
        ActiveMode      = "none",
        CurrentTarget   = "-",
        CurrentAction   = "idle",
        LastError       = "-",
        BringStatus     = "disabled",
        EnemiesSelected = 0,
    },
}
local Connections = {}
local Animators   = {}
local Window      = { Tabs = {}, Selected = nil, Minimized = false }
local Notify      = function() end -- replaced once the GUI exists
local FarmRuntime = { running = false, task = nil }
-- EE v1.4 ADDITION: handles for Stop All / mode sync (filled in stageFarming)
local FarmUI = {
    modeToggles = {},
    syncing     = false,
    bonesExpanded = false,
    bonesPanel  = nil,
    statusLabels = {},
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

local function createDiagGui()
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
        close.MouseButton1Click:Connect(function()
            pcall(function() g:Destroy() end)
            Diag.Gui, Diag.Label = nil, nil
        end)
        Diag.Gui = g
        refreshDiag()
    end)
    if not ok then warn("[EE] [WARN] Diagnostics panel unavailable: " .. tostring(err)) end
end

local function finishDiag(success)
    if not Diag.Gui or not success then return end
    local delaySec = Config.DiagnosticsAutoHide
    if delaySec and delaySec > 0 then
        task.delay(delaySec, function()
            if not Diag.Failed and Diag.Gui then
                pcall(function() Diag.Gui:Destroy() end)
                Diag.Gui, Diag.Label = nil, nil
            end
        end)
    end
end

local function Cleanup()
    pcall(function()
        FarmRuntime.running = false
        if FarmRuntime.task then
            pcall(function() task.cancel(FarmRuntime.task) end)
            FarmRuntime.task = nil
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
        if not silent and opts.Callback then task.spawn(opts.Callback, state) end
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
        Description = "Portal swirl and glow animations",
        Default = true,
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
        Description = "Preferred loadout label (UI preference)",
        Options = { "Melee", "Blox Fruits", "Sword", "Gun" },
        Default = State.CombatMode,
        Callback = function(v)
            State.CombatMode = v
            log("INFO", "Combat mode: " .. tostring(v))
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
    -- Basic Farms (mutually exclusive) + mode sync guard
    ----------------------------------------------------------------
    Farming:AddSection("Basic Farms")

    local FARM_OPTIONS = { "Bones", "Cake", "Nearest", "Levels" }
    local farmToggles = FarmUI.modeToggles

    local function syncFarmToggles()
        FarmUI.syncing = true
        for name, toggle in pairs(farmToggles) do
            local shouldBeOn = (State.BasicFarm == name)
            if toggle:Get() ~= shouldBeOn then
                toggle:Set(shouldBeOn, true) -- silent
            end
        end
        FarmUI.syncing = false
        State.Status.ActiveMode = State.BasicFarm or "none"
        if FarmUI.statusLabels.ActiveMode then
            FarmUI.statusLabels.ActiveMode.Text = "Active Mode: " .. State.Status.ActiveMode
        end
    end

    for _, name in ipairs(FARM_OPTIONS) do
        farmToggles[name] = Farming:AddToggle({
            Name = name,
            Default = false,
            Callback = function(on)
                if FarmUI.syncing then return end -- EE v1.4: re-entrancy guard
                if on then
                    State.BasicFarm = name
                elseif State.BasicFarm == name then
                    State.BasicFarm = nil
                end
                -- never leave BasicFarm pointing at a different mode than the click target
                if on and State.BasicFarm ~= name then
                    State.BasicFarm = name
                end
                syncFarmToggles()
                log("INFO", "Basic Farm: " .. tostring(State.BasicFarm or "none"))
                if State.BasicFarm then
                    Notify("Farming", "Mode: " .. State.BasicFarm, 3, T.Blue)
                else
                    Notify("Farming", "All farms stopped", 3, T.TextDim)
                end
            end,
        })
    end

    ----------------------------------------------------------------
    -- EE v1.4 ADDITION: Bones expandable section under Bones
    ----------------------------------------------------------------
    Farming:AddSection("Bones Settings")

    local bonesExpandBtn = new("TextButton", {
        Name = "BonesExpand", Text = "", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Parent = Farming.Page,
    }, { corner(10), stroke(T.Stroke, 1, 0.45) })
    pcall(function()
        local n = 0
        for _, ch in ipairs(Farming.Page:GetChildren()) do
            if ch:IsA("GuiObject") and typeof(ch.LayoutOrder) == "number" then
                n = math.max(n, ch.LayoutOrder)
            end
        end
        bonesExpandBtn.LayoutOrder = n + 1
    end)

    local bonesExpandLabel = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.Text,
        Text = "Bones Settings  [+]", Parent = bonesExpandBtn,
    })

    local bonesPanel = new("Frame", {
        Name = "BonesPanel", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), Visible = false, ClipsDescendants = true,
        Parent = Farming.Page,
    }, {
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    pcall(function()
        bonesPanel.LayoutOrder = bonesExpandBtn.LayoutOrder + 1
    end)
    FarmUI.bonesPanel = bonesPanel

    local function setBonesExpanded(open)
        FarmUI.bonesExpanded = open
        bonesPanel.Visible = open
        if open then
            bonesPanel.Size = UDim2.new(1, 0, 0, 180)
            bonesExpandLabel.Text = "Bones Settings  [-]"
        else
            bonesPanel.Size = UDim2.new(1, 0, 0, 0)
            bonesExpandLabel.Text = "Bones Settings  [+]"
        end
    end
    setBonesExpanded(false)

    connect(bonesExpandBtn.MouseButton1Click, function()
        setBonesExpanded(not FarmUI.bonesExpanded)
        -- expand/collapse only — does not change BasicFarm
    end)
    connect(bonesExpandBtn.MouseEnter, function()
        tween(bonesExpandBtn, 0.15, { BackgroundColor3 = T.SurfaceHover })
    end)
    connect(bonesExpandBtn.MouseLeave, function()
        tween(bonesExpandBtn, 0.15, { BackgroundColor3 = T.Surface })
    end)

    CreateToggle(bonesPanel, {
        Name = "Auto Random Surprise",
        Description = "Death King - 50 Bones per roll",
        Default = false,
        LayoutOrder = 1,
        Callback = function(on)
            State.AutoRandomSurprise = on
            log("INFO", "Auto Random Surprise: " .. tostring(on))
        end,
    })
    CreateToggle(bonesPanel, {
        Name = "Auto Try Luck",
        Description = "Gravestone - Try Your Luck (night)",
        Default = false,
        LayoutOrder = 2,
        Callback = function(on)
            State.AutoTryLuck = on
            log("INFO", "Auto Try Luck: " .. tostring(on))
        end,
    })
    CreateToggle(bonesPanel, {
        Name = "Auto Pray",
        Description = "Gravestone - Pray (night)",
        Default = false,
        LayoutOrder = 3,
        Callback = function(on)
            State.AutoPray = on
            log("INFO", "Auto Pray: " .. tostring(on))
        end,
    })
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 4,
        Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "Bones Status: options keep state when collapsed",
        Parent = bonesPanel,
    })

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
    addStatusLine("BringStatus", "Bring Enemies: disabled")
    addStatusLine("EnemiesSelected", "Enemies Selected: 0")

    local function refreshStatusUI()
        local S = State.Status
        if FarmUI.statusLabels.ActiveMode then
            FarmUI.statusLabels.ActiveMode.Text = "Active Mode: " .. tostring(S.ActiveMode)
        end
        if FarmUI.statusLabels.CurrentTarget then
            FarmUI.statusLabels.CurrentTarget.Text = "Current Target: " .. tostring(S.CurrentTarget)
        end
        if FarmUI.statusLabels.CurrentAction then
            FarmUI.statusLabels.CurrentAction.Text = "Current Action: " .. tostring(S.CurrentAction)
        end
        if FarmUI.statusLabels.LastError then
            FarmUI.statusLabels.LastError.Text = "Last Error: " .. tostring(S.LastError)
        end
        if FarmUI.statusLabels.BringStatus then
            FarmUI.statusLabels.BringStatus.Text = "Bring Enemies: " .. tostring(S.BringStatus)
        end
        if FarmUI.statusLabels.EnemiesSelected then
            FarmUI.statusLabels.EnemiesSelected.Text = "Enemies Selected: " .. tostring(S.EnemiesSelected)
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

    -- Stop All button
    local stopBtn = new("TextButton", {
        Name = "StopAll", Text = "Stop All", AutoButtonColor = false,
        BackgroundColor3 = T.Surface, Size = UDim2.new(1, 0, 0, 36),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = T.Danger, Parent = Farming.Page,
    }, { corner(10), stroke(T.Danger, 1, 0.5) })
    pcall(function()
        stopBtn.LayoutOrder = clearBtn.LayoutOrder + 1
    end)
    connect(stopBtn.MouseButton1Click, function()
        State.BasicFarm = nil
        State.AutoRandomSurprise = false
        State.AutoTryLuck = false
        State.AutoPray = false
        State.FarmPaused = false
        State.Status.ActiveMode = "none"
        State.Status.CurrentTarget = "-"
        State.Status.CurrentAction = "stopped"
        State.Status.EnemiesSelected = 0
        syncFarmToggles()
        if FarmUI.refreshStatusUI then FarmUI.refreshStatusUI() end
        log("OK", "Stop All: modes cleared, UI synced")
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

local function tweenTo(cf, speed)
    local char, hrp = getCharacter()
    if not char or not hrp then return false end
    -- EE v1.4: prefer State.TweenSpeed when caller omits speed
    speed = speed or State.TweenSpeed or 250
    local dist = (hrp.Position - cf.Position).Magnitude
    local t = math.max(0.15, math.min(4, dist / speed))
    local tw = TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play()
    tw.Completed:Wait()
    return true
end

-- EE v1.4 ADDITION: safe attack wait from UI delay value
local function attackWait()
    -- UI stores 0-5 labeled ms; clamp to a practical minimum so the client does not spin
    local sec = tonumber(State.AttackDelayMs) or 0.12
    if sec > 5 then sec = sec / 1000 end -- allow accidental whole-ms entry
    sec = math.max(0.05, math.min(5, sec))
    task.wait(sec)
end

local function equipBestTool()
    local char = LocalPlayer.Character
    if not char then return end
    if char:FindFirstChildOfClass("Tool") then return end
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            pcall(function() tool.Parent = char end)
            return
        end
    end
end

local function attackOnce()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(Vector2.new())
    end)
end

local function setNoCollide(model, state)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = not state
        end
    end
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
    tweenTo(GRAVESTONE_CF * CFrame.new(0, 3, 4), 300)
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
    if State.AutoRandomSurprise then doRandomSurprise() end
    if State.AutoTryLuck then doGravestone("TryLuck") end
    if State.AutoPray then doGravestone("Pray") end

    local mob = findNearestEnemy(isBoneMob)
    if not mob then
        local char, hrp = getCharacter()
        if hrp and (hrp.Position - Vector3.new(-9500, 150, 5800)).Magnitude > 400 then
            tweenTo(CFrame.new(-9508, 142, 5737), 280)
        end
        return
    end

    local root = mob:FindFirstChild("HumanoidRootPart")
    local hum  = mob:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    equipBestTool()
    setNoCollide(mob, true)
    pcall(function()
        root.Size = Vector3.new(40, 40, 40)
        root.Transparency = 1
        root.CanCollide = false
        hum.WalkSpeed = 0
        hum.JumpPower = 0
    end)

    State.Status.CurrentTarget = mob.Name
    State.Status.CurrentAction = "attacking"
    tweenTo(root.CFrame * CFrame.new(0, 25, 0))
    for _ = 1, 8 do
        if not State.BasicFarm or State.BasicFarm ~= "Bones" then break end
        if State.FarmPaused then break end
        if not mob.Parent or hum.Health <= 0 then break end
        attackOnce()
        attackWait()
    end
end

local function farmNearest()
    local mob = findNearestEnemy(nil)
    if not mob then
        State.Status.CurrentTarget = "-"
        State.Status.CurrentAction = "searching"
        return
    end
    local root = mob:FindFirstChild("HumanoidRootPart")
    local hum  = mob:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    equipBestTool()
    setNoCollide(mob, true)
    pcall(function()
        root.Size = Vector3.new(35, 35, 35)
        root.Transparency = 1
        root.CanCollide = false
    end)

    State.Status.CurrentTarget = mob.Name
    State.Status.CurrentAction = "attacking"
    tweenTo(root.CFrame * CFrame.new(0, 20, 0))
    for _ = 1, 6 do
        if not State.BasicFarm or State.BasicFarm ~= "Nearest" then break end
        if State.FarmPaused then break end
        if not mob.Parent or hum.Health <= 0 then break end
        attackOnce()
        attackWait()
    end
end

local function farmCake()
    local comm = getCommF()
    if comm then
        pcall(function()
            comm:InvokeServer("CakePrinceSpawner")
        end)
    end

    local prince = findCakePrince()
    if not prince then
        local char, hrp = getCharacter()
        if hrp and (hrp.Position - Vector3.new(-2100, 70, -12000)).Magnitude > 500 then
            tweenTo(CFrame.new(-2092, 70, -12160), 280)
        end
        return
    end

    local root = prince:FindFirstChild("HumanoidRootPart")
    local hum  = prince:FindFirstChildOfClass("Humanoid")
    if not root then return end
    if hum and hum.Health <= 0 then return end

    equipBestTool()
    setNoCollide(prince, true)
    pcall(function()
        root.Size = Vector3.new(50, 50, 50)
        root.Transparency = 1
        root.CanCollide = false
        if hum then hum.WalkSpeed = 0 end
    end)

    State.Status.CurrentTarget = prince.Name
    State.Status.CurrentAction = "attacking"
    tweenTo(root.CFrame * CFrame.new(0, 30, 0))
    for _ = 1, 10 do
        if not State.BasicFarm or State.BasicFarm ~= "Cake" then break end
        if State.FarmPaused then break end
        if not prince.Parent then break end
        if hum and hum.Health <= 0 then break end
        attackOnce()
        attackWait()
    end
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

log("OK", "Eliteified Essentials v1.4 loaded (UI + gameplay)")
finishDiag(true)
