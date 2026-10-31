--[[
    MARS PRIVATE V1
    Private vehicle control surface
    Version 1.0
    -----------------------------------------------------------
    Scope:
      * No speed-cap manipulation.
      * No persistent visual preferences.
      * No automatic physics activation.
      * Smooth 7.6-second loader.
      * Temporarily hides other ScreenGuis during loading.
      * Restores prior GUI and CoreGui states.
      * Small glass-purple control surface.
      * Vehicle-local gravity compensation and downforce.
      * Optional angular damping and upright recovery.
      * Values displayed live on sliders.
      * Single cleanup path for re-execution.
    -----------------------------------------------------------
    Physics notes:
      VectorForce acts on the assembly containing Attachment0.
      Gravity compensation uses mass * Workspace.Gravity.
      The server may override local physics.
      These controls are not guaranteed to replicate.
    -----------------------------------------------------------
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G

if type(env.MarsPrivateV1Cleanup) == "function" then
    pcall(env.MarsPrivateV1Cleanup)
end

local state = {
    alive = true,
    ready = false,
    visible = true,
    page = "Vehicle",
    enabled = false,
    gravityEnabled = false,
    downforceEnabled = false,
    spinEnabled = false,
    recoveryEnabled = false,
    gravityMultiplier = 1.00,
    downforceMultiplier = 0.00,
    spinDamping = 0.20,
    recoveryStrength = 0.35,
    car = nil,
    seat = nil,
    root = nil,
    attachment = nil,
    force = nil,
    status = "Waiting for vehicle",
    lastApplied = 0,
    lastVehicleSearch = 0,
    lastStatus = 0,
    updates = 0,
}

local links = {}
local temporary = {}
local guiSnapshot = {}
local coreSnapshot = {}
local animations = {}

local palette = {
    bg = Color3.fromRGB(17, 15, 27),
    bg2 = Color3.fromRGB(24, 21, 38),
    panel = Color3.fromRGB(34, 30, 49),
    panel2 = Color3.fromRGB(42, 36, 60),
    border = Color3.fromRGB(110, 93, 145),
    text = Color3.fromRGB(246, 241, 255),
    muted = Color3.fromRGB(155, 144, 177),
    purple = Color3.fromRGB(178, 126, 255),
    purple2 = Color3.fromRGB(124, 77, 223),
    white = Color3.fromRGB(255, 255, 255),
    green = Color3.fromRGB(122, 231, 189),
    red = Color3.fromRGB(246, 128, 155),
}

local function track(connection)
    table.insert(links, connection)
    return connection
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function destroyTemporary()
    for _, instance in ipairs(temporary) do
        safe(function()
            instance:Destroy()
        end)
    end
    table.clear(temporary)
end

local function make(className, properties, parent)
    local instance = Instance.new(className)
    for property, value in pairs(properties or {}) do
        instance[property] = value
    end
    instance.Parent = parent
    return instance
end

local function round(frame, radius)
    return make("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, frame)
end

local function border(frame, color, alpha, thickness)
    return make("UIStroke", {
        Color = color or palette.border,
        Transparency = alpha or 0.55,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, frame)
end

local function gradient(frame, upper, lower, rotation)
    return make("UIGradient", {
        Rotation = rotation or 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, upper),
            ColorSequenceKeypoint.new(1, lower),
        }),
    }, frame)
end

local function tween(instance, duration, properties, easing, direction)
    local animation = TweenService:Create(
        instance,
        TweenInfo.new(
            duration,
            easing or Enum.EasingStyle.Quint,
            direction or Enum.EasingDirection.Out
        ),
        properties
    )
    table.insert(animations, animation)
    animation:Play()
    return animation
end

local function text(parent, value, size, color, weight)
    return make("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = value,
        TextColor3 = color or palette.text,
        TextSize = size or 13,
        Font = weight or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local function button(parent, name)
    local instance = make("TextButton", {
        Name = name,
        BackgroundColor3 = palette.panel,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
    }, parent)
    round(instance, 12)
    border(instance, palette.border, 0.73)
    return instance
end

local function pulse(target)
    if not target or not target.Parent then
        return
    end
    local original = target.BackgroundColor3
    tween(target, 0.11, {
        BackgroundColor3 = palette.purple2,
    })
    task.delay(0.13, function()
        if state.alive and target.Parent then
            tween(target, 0.28, {
                BackgroundColor3 = original,
            })
        end
    end)
end

local function getCar()
    local storage = Workspace:FindFirstChild("VehicleStorage")
    if not storage then
        return nil
    end

    local named = storage:FindFirstChild(localPlayer.Name .. "sCar")
    if named and named:IsA("Model") then
        return named
    end

    local character = localPlayer.Character
    local humanoid = character
        and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.SeatPart

    if seat then
        local model = seat:FindFirstAncestorOfClass("Model")
        if model and model:IsDescendantOf(storage) then
            return model
        end
    end

    return nil
end

local function getCarParts(car)
    if not car then
        return nil, nil
    end

    local body = car:FindFirstChild("Body")
    local seat = body and body:FindFirstChild("VehicleSeat")
    if not (seat and seat:IsA("VehicleSeat")) then
        seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
    end

    local root = seat
    if not root then
        root = car.PrimaryPart
    end

    if root and not root:IsA("BasePart") then
        root = nil
    end

    return seat, root
end

local function destroyForce()
    if state.force then
        safe(function()
            state.force.Force = Vector3.zero
        end)
        safe(function()
            state.force:Destroy()
        end)
    end

    if state.attachment then
        safe(function()
            state.attachment:Destroy()
        end)
    end

    state.force = nil
    state.attachment = nil
end

local function releaseVehicle()
    destroyForce()
    state.car = nil
    state.seat = nil
    state.root = nil
    state.status = "Waiting for vehicle"
end

local function bindVehicle()
    local car = getCar()
    local seat, root = getCarParts(car)

    if car == state.car
        and seat == state.seat
        and root == state.root
        and root
        and root.Parent
    then
        return
    end

    destroyForce()

    state.car = car
    state.seat = seat
    state.root = root

    if not root then
        state.status = "Vehicle not found"
        return
    end

    state.status = "Vehicle connected"

    local attachment = make("Attachment", {
        Name = "MarsPrivateV1Attachment",
    }, root)

    local force = make("VectorForce", {
        Name = "MarsPrivateV1GravityForce",
        Attachment0 = attachment,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        ApplyAtCenterOfMass = true,
        Force = Vector3.zero,
        Enabled = false,
    }, root)

    state.attachment = attachment
    state.force = force
end

local function physicsActive()
    return state.enabled and state.root and state.root.Parent
end

local function applyForce()
    local force = state.force
    local root = state.root

    if not force or not root then
        return
    end

    if not physicsActive() then
        force.Enabled = false
        force.Force = Vector3.zero
        return
    end

    local mass = root.AssemblyMass
    local gravity = Workspace.Gravity
    local netMultiplier = 1

    if state.gravityEnabled then
        netMultiplier = state.gravityMultiplier
    end

    if state.downforceEnabled then
        netMultiplier += state.downforceMultiplier
    end

    local verticalForce = mass * gravity * (1 - netMultiplier)

    force.Force = Vector3.new(0, verticalForce, 0)
    force.Enabled = math.abs(verticalForce) > 0.01

    state.lastApplied = verticalForce
end

local function applyStabilization(dt)
    local root = state.root
    if not physicsActive() or not root then
        return
    end

    if not state.spinEnabled and not state.recoveryEnabled then
        return
    end

    local velocity = root.AssemblyAngularVelocity
    local nextVelocity = velocity

    if state.spinEnabled then
        local damping = math.clamp(state.spinDamping * dt * 5, 0, 0.30)
        nextVelocity = Vector3.new(
            velocity.X * (1 - damping),
            velocity.Y,
            velocity.Z * (1 - damping)
        )
    end

    if state.recoveryEnabled then
        local up = root.CFrame.UpVector
        local upright = up:Dot(Vector3.yAxis)
        if upright < 0.55 then
            local corrective = up:Cross(Vector3.yAxis)
            local magnitude = math.clamp(
                state.recoveryStrength * dt * 9,
                0,
                0.12
            )
            nextVelocity += corrective * magnitude
        end
    end

    if (nextVelocity - velocity).Magnitude > 0.0001 then
        safe(function()
            root.AssemblyAngularVelocity = nextVelocity
        end)
    end
end

local function setAllOff()
    state.enabled = false
    state.gravityEnabled = false
    state.downforceEnabled = false
    state.spinEnabled = false
    state.recoveryEnabled = false
    if state.force then
        state.force.Force = Vector3.zero
        state.force.Enabled = false
    end
end

local gui = make("ScreenGui", {
    Name = "MarsPrivateV1",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    DisplayOrder = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Enabled = true,
}, playerGui)

local blur = make("BlurEffect", {
    Name = "MarsPrivateV1LoadingBlur",
    Size = 0,
    Enabled = true,
}, Lighting)

local function snapshotAndHide()
    for _, child in ipairs(playerGui:GetChildren()) do
        if child:IsA("ScreenGui") and child ~= gui then
            guiSnapshot[child] = child.Enabled
            child.Enabled = false
        end
    end

    for _, kind in ipairs({
        Enum.CoreGuiType.PlayerList,
        Enum.CoreGuiType.Backpack,
        Enum.CoreGuiType.Chat,
        Enum.CoreGuiType.Health,
        Enum.CoreGuiType.EmotesMenu,
    }) do
        local old = safe(function()
            return StarterGui:GetCoreGuiEnabled(kind)
        end)
        if type(old) == "boolean" then
            coreSnapshot[kind] = old
            safe(function()
                StarterGui:SetCoreGuiEnabled(kind, false)
            end)
        end
    end
end

local function restoreGui()
    for child, enabled in pairs(guiSnapshot) do
        if child and child.Parent then
            safe(function()
                child.Enabled = enabled
            end)
        end
    end
    table.clear(guiSnapshot)

    for kind, enabled in pairs(coreSnapshot) do
        safe(function()
            StarterGui:SetCoreGuiEnabled(kind, enabled)
        end)
    end
    table.clear(coreSnapshot)
end

local screen = make("Frame", {
    Name = "Loader",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ZIndex = 100,
}, gui)

local veil = make("Frame", {
    Name = "Dim",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(10, 8, 18),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 101,
}, screen)

local loaderShadow = make("Frame", {
    Name = "LoaderGlow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(335, 170),
    BackgroundColor3 = palette.purple2,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 102,
}, screen)
round(loaderShadow, 25)

local loader = make("Frame", {
    Name = "LoaderCard",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.53),
    Size = UDim2.fromOffset(0, 0),
    BackgroundColor3 = palette.bg,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 103,
}, screen)
round(loader, 19)
border(loader, palette.purple, 0.56, 1)
gradient(loader, palette.panel, palette.bg)

local loaderMark = text(loader, "◇", 23, palette.white, Enum.Font.GothamBold)
loaderMark.Position = UDim2.fromOffset(24, 19)
loaderMark.Size = UDim2.fromOffset(34, 34)
loaderMark.ZIndex = 105

local markBackground = make("Frame", {
    Name = "Mark",
    Position = UDim2.fromOffset(17, 17),
    Size = UDim2.fromOffset(46, 46),
    BackgroundColor3 = palette.purple2,
    BackgroundTransparency = 0.28,
    BorderSizePixel = 0,
    ZIndex = 104,
}, loader)
round(markBackground, 13)

local loaderTitle = text(loader, "mars private v1", 17, palette.white, Enum.Font.GothamBold)
loaderTitle.Position = UDim2.fromOffset(77, 17)
loaderTitle.Size = UDim2.fromOffset(225, 27)
loaderTitle.ZIndex = 105

local loaderSubtitle = text(loader, "private vehicle experience", 10, palette.muted)
loaderSubtitle.Position = UDim2.fromOffset(78, 43)
loaderSubtitle.Size = UDim2.fromOffset(225, 16)
loaderSubtitle.ZIndex = 105

local loaderStatus = text(loader, "preparing your workspace", 11, palette.muted)
loaderStatus.Position = UDim2.fromOffset(20, 92)
loaderStatus.Size = UDim2.fromOffset(240, 20)
loaderStatus.ZIndex = 105

local loaderPercent = text(loader, "0%", 11, palette.purple, Enum.Font.GothamBold)
loaderPercent.Position = UDim2.fromOffset(267, 92)
loaderPercent.Size = UDim2.fromOffset(47, 20)
loaderPercent.TextXAlignment = Enum.TextXAlignment.Right
loaderPercent.ZIndex = 105

local trackBack = make("Frame", {
    Position = UDim2.fromOffset(20, 121),
    Size = UDim2.fromOffset(294, 6),
    BackgroundColor3 = palette.panel2,
    BorderSizePixel = 0,
    ZIndex = 105,
}, loader)
round(trackBack, 8)

local progress = make("Frame", {
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = palette.purple,
    BorderSizePixel = 0,
    ZIndex = 106,
}, trackBack)
round(progress, 8)
gradient(progress, palette.purple2, palette.purple, 0)

local main = make("Frame", {
    Name = "Window",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.53),
    Size = UDim2.fromOffset(0, 0),
    BackgroundColor3 = palette.bg,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
    ZIndex = 5,
}, gui)
round(main, 20)
border(main, palette.purple, 0.29, 1.4)
gradient(main, palette.bg2, palette.bg)

local mainGlow = make("Frame", {
    Name = "GlowLine",
    Size = UDim2.new(1, -38, 0, 2),
    Position = UDim2.fromOffset(19, 0),
    BackgroundColor3 = palette.purple,
    BackgroundTransparency = 0.06,
    BorderSizePixel = 0,
    ZIndex = 6,
}, main)
round(mainGlow, 2)

local top = make("Frame", {
    Name = "Top",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 68),
    ZIndex = 7,
}, main)

local brandIcon = make("Frame", {
    Position = UDim2.fromOffset(17, 16),
    Size = UDim2.fromOffset(36, 36),
    BackgroundColor3 = palette.purple2,
    BackgroundTransparency = 0.30,
    BorderSizePixel = 0,
    ZIndex = 8,
}, top)
round(brandIcon, 12)
border(brandIcon, palette.purple, 0.45)

local brandLetter = text(brandIcon, "◇", 23, palette.white, Enum.Font.GothamBold)
brandLetter.Size = UDim2.fromScale(1, 1)
brandLetter.TextXAlignment = Enum.TextXAlignment.Center
brandLetter.ZIndex = 9

local brand = text(top, "mars private v1", 15, palette.text, Enum.Font.GothamBold)
brand.Position = UDim2.fromOffset(64, 16)
brand.Size = UDim2.fromOffset(250, 22)
brand.ZIndex = 8

local brandSub = text(top, "", 9, palette.muted)
brandSub.Position = UDim2.fromOffset(64, 38)
brandSub.Size = UDim2.fromOffset(240, 15)
brandSub.ZIndex = 8

local close = button(top, "Close")
close.Position = UDim2.new(1, -44, 0, 19)
close.Size = UDim2.fromOffset(26, 26)
close.ZIndex = 8
local closeText = text(close, "×", 20, palette.muted, Enum.Font.GothamMedium)
closeText.Size = UDim2.fromScale(1, 1)
closeText.TextXAlignment = Enum.TextXAlignment.Center
closeText.ZIndex = 9

make("Frame", {
    Position = UDim2.fromOffset(17, 68),
    Size = UDim2.new(1, -34, 0, 1),
    BackgroundColor3 = palette.border,
    BackgroundTransparency = 0.75,
    BorderSizePixel = 0,
    ZIndex = 7,
}, main)

local navigation = make("Frame", {
    Name = "Navigation",
    Position = UDim2.fromOffset(17, 81),
    Size = UDim2.new(1, -34, 0, 38),
    BackgroundTransparency = 1,
    ZIndex = 7,
}, main)

make("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, navigation)

local content = make("Frame", {
    Name = "Content",
    Position = UDim2.fromOffset(17, 131),
    Size = UDim2.new(1, -34, 1, -179),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    ZIndex = 7,
}, main)

local footer = make("Frame", {
    Name = "Footer",
    Position = UDim2.new(0, 17, 1, -36),
    Size = UDim2.new(1, -34, 0, 22),
    BackgroundTransparency = 1,
    ZIndex = 7,
}, main)

local footerStatus = text(footer, "idle  ·  no effects enabled", 10, palette.muted)
footerStatus.Size = UDim2.new(1, -85, 1, 0)
footerStatus.ZIndex = 8

local footerKey = text(footer, "RIGHT SHIFT", 9, palette.muted)
footerKey.TextXAlignment = Enum.TextXAlignment.Right
footerKey.Position = UDim2.new(1, -92, 0, 0)
footerKey.Size = UDim2.fromOffset(92, 22)
footerKey.ZIndex = 8

local cleanup

local pages = {}
local navButtons = {}
local refreshers = {}

local function addRefresh(fn)
    table.insert(refreshers, fn)
end

local function refresh()
    for _, fn in ipairs(refreshers) do
        safe(fn)
    end
end

local function page(name)
    local frame = make("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = palette.purple,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
        ZIndex = 8,
    }, content)

    make("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, frame)

    make("UIPadding", {
        PaddingBottom = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 4),
    }, frame)

    pages[name] = frame
    return frame
end

local vehiclePage = page("Vehicle")
local handlingPage = page("Handling")
local appearancePage = page("Appearance")
local aboutPage = page("About")

local function switchPage(name)
    state.page = name

    for pageName, frame in pairs(pages) do
        frame.Visible = pageName == name
        if frame.Visible then
            frame.CanvasPosition = Vector2.zero
        end
    end

    for pageName, item in pairs(navButtons) do
        local selected = pageName == name
        tween(item.frame, 0.23, {
            BackgroundColor3 = selected and palette.purple2 or palette.panel,
            BackgroundTransparency = selected and 0.23 or 0.52,
        })
        tween(item.text, 0.23, {
            TextColor3 = selected and palette.white or palette.muted,
        })
    end
end

local function addNav(name, order, width)
    local b = button(navigation, name .. "Tab")
    b.LayoutOrder = order
    b.Size = UDim2.fromOffset(width, 34)
    b.BackgroundTransparency = 0.52
    b.ZIndex = 8

    local label = text(b, name, 11, palette.muted, Enum.Font.GothamMedium)
    label.Size = UDim2.fromScale(1, 1)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.ZIndex = 9

    navButtons[name] = {
        frame = b,
        text = label,
    }

    track(b.MouseButton1Click:Connect(function()
        pulse(b)
        switchPage(name)
    end))
end

addNav("Vehicle", 1, 88)
addNav("Handling", 2, 88)
addNav("Appearance", 3, 88)
addNav("About", 4, 88)

local function section(parent, title, description)
    local block = make("Frame", {
        Name = title,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        ZIndex = 9,
    }, parent)

    local heading = text(block, title, 14, palette.text, Enum.Font.GothamBold)
    heading.Position = UDim2.fromOffset(2, 2)
    heading.Size = UDim2.new(1, -4, 0, 22)
    heading.ZIndex = 10

    local sub = text(block, description, 10, palette.muted)
    sub.Position = UDim2.fromOffset(2, 24)
    sub.Size = UDim2.new(1, -4, 0, 19)
    sub.ZIndex = 10

    return block
end

local function panel(parent, height)
    local block = make("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = palette.panel,
        BackgroundTransparency = 0.47,
        BorderSizePixel = 0,
        ZIndex = 9,
    }, parent)
    round(block, 14)
    border(block, palette.border, 0.80)
    return block
end

local function toggle(parent, labelText, description, getter, setter)
    local row = panel(parent, 62)

    local title = text(row, labelText, 12, palette.text, Enum.Font.GothamMedium)
    title.Position = UDim2.fromOffset(14, 10)
    title.Size = UDim2.new(1, -88, 0, 21)
    title.ZIndex = 10

    local detail = text(row, description, 10, palette.muted)
    detail.Position = UDim2.fromOffset(14, 32)
    detail.Size = UDim2.new(1, -88, 0, 17)
    detail.ZIndex = 10

    local switch = button(row, "Switch")
    switch.AnchorPoint = Vector2.new(1, 0.5)
    switch.Position = UDim2.new(1, -14, 0.5, 0)
    switch.Size = UDim2.fromOffset(45, 25)
    switch.ZIndex = 11
    round(switch, 15)

    local dot = make("Frame", {
        Size = UDim2.fromOffset(17, 17),
        Position = UDim2.fromOffset(4, 4),
        BackgroundColor3 = palette.muted,
        BorderSizePixel = 0,
        ZIndex = 12,
    }, switch)
    round(dot, 12)

    local function repaint()
        local on = getter()
        tween(switch, 0.22, {
            BackgroundColor3 = on and palette.purple2 or palette.bg2,
            BackgroundTransparency = on and 0.06 or 0.25,
        })
        tween(dot, 0.22, {
            Position = on
                and UDim2.fromOffset(24, 4)
                or UDim2.fromOffset(4, 4),
            BackgroundColor3 = on and palette.white or palette.muted,
        })
    end

    track(switch.MouseButton1Click:Connect(function()
        setter(not getter())
        repaint()
        refresh()
    end))

    addRefresh(repaint)
    repaint()

    return row
end

local function slider(parent, titleText, description, key, low, high, step, unit)
    local card = panel(parent, 100)

    local heading = text(card, titleText, 12, palette.text, Enum.Font.GothamMedium)
    heading.Position = UDim2.fromOffset(14, 10)
    heading.Size = UDim2.new(1, -95, 0, 20)
    heading.ZIndex = 10

    local value = text(card, "", 12, palette.purple, Enum.Font.GothamBold)
    value.Position = UDim2.new(1, -98, 0, 10)
    value.Size = UDim2.fromOffset(83, 20)
    value.TextXAlignment = Enum.TextXAlignment.Right
    value.ZIndex = 10

    local detail = text(card, description, 10, palette.muted)
    detail.Position = UDim2.fromOffset(14, 33)
    detail.Size = UDim2.new(1, -28, 0, 17)
    detail.ZIndex = 10

    local rail = make("Frame", {
        Position = UDim2.fromOffset(16, 72),
        Size = UDim2.new(1, -32, 0, 5),
        BackgroundColor3 = palette.bg,
        BorderSizePixel = 0,
        ZIndex = 10,
    }, card)
    round(rail, 6)

    local fill = make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = palette.purple,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, rail)
    round(fill, 6)
    gradient(fill, palette.purple2, palette.purple, 0)

    local thumb = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = palette.white,
        BorderSizePixel = 0,
        ZIndex = 12,
    }, rail)
    round(thumb, 8)
    border(thumb, palette.purple, 0.1, 2)

    local hit = make("TextButton", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        Position = UDim2.fromOffset(10, 60),
        Size = UDim2.new(1, -20, 0, 31),
        ZIndex = 13,
    }, card)

    local dragging = false

    local function repaint()
        local current = math.clamp(state[key], low, high)
        local alpha = (current - low) / (high - low)
        value.Text = string.format(
            step < 1 and "%.2f%s" or "%.0f%s",
            current,
            unit or ""
        )
        fill.Size = UDim2.fromScale(alpha, 1)
        thumb.Position = UDim2.fromScale(alpha, 0.5)
    end

    local function change(x)
        if rail.AbsoluteSize.X < 1 then
            return
        end
        local alpha = math.clamp(
            (x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X,
            0,
            1
        )
        local raw = low + (high - low) * alpha
        local steps = math.floor((raw - low) / step + 0.5)
        local nextValue = math.clamp(low + steps * step, low, high)
        state[key] = math.floor(nextValue * 1000 + 0.5) / 1000
        repaint()
        applyForce()
    end

    track(hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = true
            change(input.Position.X)
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if dragging
            and (
                input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch
            )
        then
            change(input.Position.X)
        end
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            dragging = false
        end
    end))

    addRefresh(repaint)
    repaint()
    return card
end

section(
    vehiclePage,
    "Vehicle controls",
    "Local physics adjustments · all disabled by default"
)

toggle(
    vehiclePage,
    "Enable vehicle controller",
    "Master switch for all vehicle effects",
    function()
        return state.enabled
    end,
    function(value)
        state.enabled = value
        if not value then
            applyForce()
        end
    end
)

toggle(
    vehiclePage,
    "Custom gravity",
    "Compensate or increase effective vehicle gravity",
    function()
        return state.gravityEnabled
    end,
    function(value)
        state.gravityEnabled = value
        applyForce()
    end
)

slider(
    vehiclePage,
    "Gravity multiplier",
    "1.00× normal · below 1 is lighter",
    "gravityMultiplier",
    0.35,
    1.80,
    0.05,
    "×"
)

toggle(
    vehiclePage,
    "Extra downforce",
    "Additional downward force at center of mass",
    function()
        return state.downforceEnabled
    end,
    function(value)
        state.downforceEnabled = value
        applyForce()
    end
)

slider(
    vehiclePage,
    "Downforce",
    "0.00× to 1.50× extra gravity",
    "downforceMultiplier",
    0,
    1.50,
    0.05,
    "×"
)

section(
    handlingPage,
    "Handling assists",
    "Optional local corrections for rotation"
)

toggle(
    handlingPage,
    "Anti-spin damping",
    "Reduces roll and pitch angular velocity",
    function()
        return state.spinEnabled
    end,
    function(value)
        state.spinEnabled = value
    end
)

slider(
    handlingPage,
    "Damping strength",
    "Higher values apply stronger correction",
    "spinDamping",
    0.05,
    1.00,
    0.05,
    "×"
)

toggle(
    handlingPage,
    "Upright recovery",
    "Attempts a gentle correction if tipped over",
    function()
        return state.recoveryEnabled
    end,
    function(value)
        state.recoveryEnabled = value
    end
)

slider(
    handlingPage,
    "Recovery strength",
    "Only applies when the car is heavily tilted",
    "recoveryStrength",
    0.05,
    1.00,
    0.05,
    "×"
)

-- Appearance: eight curated palettes, dropdown and accent swatches.
local themeDefinitions = {
    { name = "Amethyst", accent = {178,126,255}, secondary = {124,77,223}, bg = {17,15,27}, panel = {34,30,49}, border = {110,93,145} },
    { name = "Midnight", accent = {116,145,255}, secondary = {69,90,199}, bg = {13,17,30}, panel = {28,35,55}, border = {79,100,149} },
    { name = "Rose Quartz", accent = {255,135,189}, secondary = {205,78,137}, bg = {29,16,29}, panel = {52,30,49}, border = {145,89,126} },
    { name = "Glacier", accent = {114,225,255}, secondary = {54,145,204}, bg = {13,22,30}, panel = {28,45,58}, border = {83,130,153} },
    { name = "Emerald", accent = {110,242,185}, secondary = {39,155,120}, bg = {12,24,22}, panel = {27,49,43}, border = {69,129,112} },
    { name = "Solar", accent = {255,194,112}, secondary = {209,120,60}, bg = {29,22,18}, panel = {55,41,34}, border = {143,111,79} },
    { name = "Crimson", accent = {255,111,137}, secondary = {194,53,83}, bg = {29,15,23}, panel = {54,29,42}, border = {141,75,101} },
    { name = "Obsidian", accent = {215,217,233}, secondary = {127,132,163}, bg = {14,15,20}, panel = {33,35,45}, border = {103,108,129} },
}

local function rgb(values)
    return Color3.fromRGB(values[1], values[2], values[3])
end

local themeDropdownOpen = false
local themeRows = {}

local function themeColors(theme)
    return {
        bg = rgb(theme.bg),
        bg2 = rgb(theme.panel),
        panel = rgb(theme.panel),
        panel2 = rgb(theme.border),
        border = rgb(theme.border),
        purple = rgb(theme.accent),
        purple2 = rgb(theme.secondary),
    }
end

local function recolorSequence(sequence, oldColors, newColors)
    local keys = {}
    for _, point in ipairs(sequence.Keypoints) do
        local result = point.Value
        for name, old in pairs(oldColors) do
            if result == old and newColors[name] then
                result = newColors[name]
                break
            end
        end
        table.insert(keys, ColorSequenceKeypoint.new(point.Time, result))
    end
    return ColorSequence.new(keys)
end

local function applyTheme(theme)
    local previous = {}
    for name, color in pairs(palette) do
        previous[name] = color
    end

    local newColors = themeColors(theme)
    -- Each UI color is recolored from the previous palette, preserving
    -- element-specific transparency, sizing and animations.
    for _, item in ipairs(gui:GetDescendants()) do
        for _, property in ipairs({"BackgroundColor3", "TextColor3", "ImageColor3", "Color"}) do
            local existing = safe(function() return item[property] end)
            if typeof(existing) == "Color3" then
                for name, old in pairs(previous) do
                    if existing == old and newColors[name] then
                        safe(function() item[property] = newColors[name] end)
                        break
                    end
                end
            end
        end
        if item:IsA("UIGradient") then
            item.Color = recolorSequence(item.Color, previous, newColors)
        end
    end

    for name, color in pairs(newColors) do
        palette[name] = color
    end
    refresh()
end

section(appearancePage, "Appearance", "Select a curated colorway")

local themePicker = panel(appearancePage, 68)
local pickerLabel = text(themePicker, "COLOR THEME", 10, palette.muted, Enum.Font.GothamMedium)
pickerLabel.Position = UDim2.fromOffset(14, 7)
pickerLabel.Size = UDim2.fromOffset(180, 17)
pickerLabel.ZIndex = 11

local themeButton = button(themePicker, "ThemeDropdown")
themeButton.Position = UDim2.fromOffset(12, 27)
themeButton.Size = UDim2.new(1, -24, 0, 32)
themeButton.ZIndex = 11

local currentSwatch = make("Frame", {
    Position = UDim2.fromOffset(10, 8),
    Size = UDim2.fromOffset(16, 16),
    BackgroundColor3 = palette.purple,
    BorderSizePixel = 0,
    ZIndex = 12,
}, themeButton)
round(currentSwatch, 7)

local currentLabel = text(themeButton, "Amethyst", 12, palette.text, Enum.Font.GothamMedium)
currentLabel.Position = UDim2.fromOffset(35, 0)
currentLabel.Size = UDim2.new(1, -70, 1, 0)
currentLabel.ZIndex = 12

local dropdownArrow = text(themeButton, "⌄", 18, palette.muted)
dropdownArrow.Position = UDim2.new(1, -27, 0, 0)
dropdownArrow.Size = UDim2.fromOffset(23, 32)
dropdownArrow.ZIndex = 12

local themeOptions = make("Frame", {
    Name = "ThemeOptions",
    Size = UDim2.new(1, 0, 0, 0),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Visible = false,
    ZIndex = 10,
}, appearancePage)

make("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, themeOptions)

local function setDropdownOpen(open)
    themeDropdownOpen = open
    themeOptions.Visible = true
    tween(themeOptions, 0.28, {
        Size = UDim2.new(1, 0, 0, open and 348 or 0),
    })
    dropdownArrow.Text = open and "⌃" or "⌄"
    if not open then
        task.delay(0.30, function()
            if state.alive and not themeDropdownOpen then
                themeOptions.Visible = false
            end
        end)
    end
end

track(themeButton.MouseButton1Click:Connect(function()
    pulse(themeButton)
    setDropdownOpen(not themeDropdownOpen)
end))

for index, theme in ipairs(themeDefinitions) do
    local option = button(themeOptions, "Theme" .. theme.name)
    option.LayoutOrder = index
    option.Size = UDim2.new(1, 0, 0, 39)
    option.ZIndex = 11
    option.BackgroundTransparency = 0.42

    local swatch = make("Frame", {
        Position = UDim2.fromOffset(11, 10),
        Size = UDim2.fromOffset(19, 19),
        BackgroundColor3 = rgb(theme.accent),
        BorderSizePixel = 0,
        ZIndex = 12,
    }, option)
    round(swatch, 8)
    border(swatch, rgb(theme.secondary), 0.20)

    local swatch2 = make("Frame", {
        Position = UDim2.fromOffset(23, 16),
        Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = rgb(theme.secondary),
        BorderSizePixel = 0,
        ZIndex = 13,
    }, option)
    round(swatch2, 5)

    local nameLabel = text(option, theme.name, 11, palette.text, Enum.Font.GothamMedium)
    nameLabel.Position = UDim2.fromOffset(43, 0)
    nameLabel.Size = UDim2.new(1, -84, 1, 0)
    nameLabel.ZIndex = 12

    local selectedLabel = text(option, "", 11, palette.purple, Enum.Font.GothamBold)
    selectedLabel.Position = UDim2.new(1, -35, 0, 0)
    selectedLabel.Size = UDim2.fromOffset(27, 39)
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Center
    selectedLabel.ZIndex = 12

    table.insert(themeRows, {theme = theme, selected = selectedLabel})

    track(option.MouseButton1Click:Connect(function()
        applyTheme(theme)
        currentLabel.Text = theme.name
        currentSwatch.BackgroundColor3 = rgb(theme.accent)
        for _, row in ipairs(themeRows) do
            row.selected.Text = row.theme.name == theme.name and "✓" or ""
        end
        setDropdownOpen(false)
    end))
end

themeRows[1].selected.Text = "✓"

section(aboutPage, "Made for Mars", "")

local aboutCard = panel(aboutPage, 112)
local aboutTitle = text(aboutCard, "Made for Mars", 18, palette.text, Enum.Font.GothamBold)
aboutTitle.Position = UDim2.fromOffset(16, 12)
aboutTitle.Size = UDim2.new(1, -32, 0, 30)
aboutTitle.ZIndex = 10

local unloadButton = button(aboutCard, "Unload")
unloadButton.Position = UDim2.fromOffset(14, 56)
unloadButton.Size = UDim2.new(1, -28, 0, 39)
unloadButton.ZIndex = 11
unloadButton.BackgroundColor3 = palette.panel2

local unloadText = text(unloadButton, "Unload script", 12, palette.text, Enum.Font.GothamMedium)
unloadText.Size = UDim2.fromScale(1, 1)
unloadText.TextXAlignment = Enum.TextXAlignment.Center
unloadText.ZIndex = 12

track(unloadButton.MouseButton1Click:Connect(function()
    pulse(unloadButton)
    task.delay(0.18, function()
        if cleanup then cleanup() end
    end)
end))

addRefresh(function()
    footerStatus.Text = state.enabled
        and ("active  ·  " .. state.status)
        or ("idle  ·  " .. state.status)
    footerStatus.TextColor3 = state.enabled and palette.green or palette.muted
end)

switchPage("Vehicle")

local draggingWindow = false
local dragOrigin = nil
local windowOrigin = nil

track(top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingWindow = true
        dragOrigin = input.Position
        windowOrigin = main.Position
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if draggingWindow
        and input.UserInputType == Enum.UserInputType.MouseMovement
    then
        local delta = input.Position - dragOrigin
        main.Position = UDim2.new(
            windowOrigin.X.Scale,
            windowOrigin.X.Offset + delta.X,
            windowOrigin.Y.Scale,
            windowOrigin.Y.Offset + delta.Y
        )
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingWindow = false
    end
end))

local function showWindow()
    state.visible = true
    main.Visible = true
    main.Size = UDim2.fromOffset(410, 0)
    main.Position = UDim2.fromScale(0.5, 0.53)
    tween(main, 0.55, {
        Size = UDim2.fromOffset(410, 410),
        Position = UDim2.fromScale(0.5, 0.5),
    }, Enum.EasingStyle.Back)
end

local function hideWindow()
    state.visible = false
    tween(main, 0.22, {
        Size = UDim2.fromOffset(395, 392),
    })
    task.delay(0.23, function()
        if state.alive and not state.visible then
            main.Visible = false
        end
    end)
end

track(close.MouseButton1Click:Connect(function()
    hideWindow()
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not state.ready then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if state.visible then
            hideWindow()
        else
            showWindow()
        end
    end
end))

cleanup = function()
    if not state.alive then
        return
    end
    state.alive = false
    setAllOff()
    restoreGui()
    releaseVehicle()

    for _, connection in ipairs(links) do
        safe(function()
            connection:Disconnect()
        end)
    end

    for _, animation in ipairs(animations) do
        safe(function()
            animation:Cancel()
        end)
    end

    safe(function()
        blur:Destroy()
    end)

    safe(function()
        gui:Destroy()
    end)

    destroyTemporary()
end

env.MarsPrivateV1Cleanup = cleanup

track(RunService.Heartbeat:Connect(function(dt)
    if not state.ready or not state.alive then
        return
    end

    local now = os.clock()
    if now - state.lastVehicleSearch > 0.8 then
        state.lastVehicleSearch = now
        bindVehicle()
    end

    if state.enabled then
        applyForce()
        applyStabilization(math.min(dt, 0.1))
    end

    if now - state.lastStatus > 0.4 then
        state.lastStatus = now
        state.updates += 1
        refresh()
    end
end))

-- LOADER SEQUENCE
-- It is intentionally staged rather than a single tween.
-- Durations total approximately 3.12 seconds plus entrance/fade (~4 seconds).
local loaderStages = {
    { duration = 0.45, percent = 12, message = "opening mars private" },
    { duration = 0.48, percent = 26, message = "preparing your space" },
    { duration = 0.42, percent = 41, message = "shaping the glass" },
    { duration = 0.48, percent = 57, message = "connecting vehicle controls" },
    { duration = 0.40, percent = 72, message = "checking systems" },
    { duration = 0.44, percent = 88, message = "finishing touches" },
    { duration = 0.45, percent = 100, message = "welcome, mars" },
}

local function runLoader()
    snapshotAndHide()

    tween(blur, 1.05, {
        Size = 11,
    })
    tween(veil, 1.10, {
        BackgroundTransparency = 0.77,
    })
    tween(loaderShadow, 0.95, {
        BackgroundTransparency = 0.86,
    })
    tween(loader, 0.85, {
        Size = UDim2.fromOffset(334, 153),
        Position = UDim2.fromScale(0.5, 0.5),
    }, Enum.EasingStyle.Back)

    task.wait(0.32)

    for index, stage in ipairs(loaderStages) do
        if not state.alive then
            return
        end

        loaderStatus.TextTransparency = 1
        loaderStatus.Text = stage.message

        tween(loaderStatus, 0.22, {
            TextTransparency = 0,
        })

        local moveTime = stage.duration * 0.70
        tween(progress, moveTime, {
            Size = UDim2.fromScale(stage.percent / 100, 1),
        }, Enum.EasingStyle.Sine)

        local previous = index == 1 and 0 or loaderStages[index - 1].percent
        local steps = math.max(1, math.floor(stage.duration / 0.055))

        for j = 1, steps do
            if not state.alive then
                return
            end

            local ratio = j / steps
            local eased = 1 - math.pow(1 - ratio, 3)
            local number = math.floor(
                previous + (stage.percent - previous) * eased
            )
            loaderPercent.Text = tostring(number) .. "%"
            task.wait(stage.duration / steps)
        end

        loaderPercent.Text = tostring(stage.percent) .. "%"
    end

    -- Hold at 100% briefly so the final status is readable.
    task.wait(0.20)

    tween(loader, 0.48, {
        Size = UDim2.fromOffset(320, 142),
        BackgroundTransparency = 1,
    }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

    tween(loaderShadow, 0.45, {
        BackgroundTransparency = 1,
    })

    tween(veil, 0.60, {
        BackgroundTransparency = 1,
    })

    tween(blur, 0.75, {
        Size = 0,
    })

    task.wait(0.37)

    if not state.alive then
        return
    end

    restoreGui()

    screen.Visible = false
    state.ready = true
    bindVehicle()
    refresh()

    -- Separate 1.2s entrance from loader fade.
    showWindow()
    task.wait(0.60)

    safe(function()
        blur:Destroy()
    end)
end

task.spawn(runLoader)

print("enjoy mars private yooo")
