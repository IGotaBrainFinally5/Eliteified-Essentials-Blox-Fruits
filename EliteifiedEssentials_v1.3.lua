--[[
    Eliteified Essentials (BLOX FRUITS) - v1.4 (stability)
    UI Framework + Gameplay Automation

    v1.3: Farming loops + Bones Options
    v1.4: Combat/Bring UI, diagnostics, Clear Log / Stop All
    v1.4 stability:
      - Single synchronous writer for State.BasicFarm (no async mode races)
      - Cancel in-flight farm tweens; generation token aborts stale ticks
      - TweenSpeed is the only movement speed source (no hardcoded 280/300)
      - Bones options shown under Bones when ON (no separate dropdown)
      - State.Effects defaults OFF (UI portal FX only — not engine combat anim)
      - Honest equipped-item / Haki / mode-match status (Unknown when unverified)

    Diagnostics: bottom-left panel + [EE] console lines.
]]

print("[EE] Script started - Eliteified Essentials v1.4 (stability)")

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
    -- move: { tween, hrp, wasAnchored } — owned by the active tweenTo; cleared on finish/cancel
    move = nil,
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
        FarmRuntime.generation = FarmRuntime.generation + 1
        -- Inline move cleanup (cancelFarmTween is defined later in the file; do not depend on it here)
        local tw = FarmRuntime.activeTween
        local m = FarmRuntime.move
        FarmRuntime.activeTween = nil
        FarmRuntime.move = nil
        if tw then pcall(function() tw:Cancel() end) end
        if m and m.tween and m.tween ~= tw then pcall(function() m.tween:Cancel() end) end
        if m and m.hrp and m.hrp.Parent then
            pcall(function() m.hrp.Anchored = m.wasAnchored end)
        end
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
