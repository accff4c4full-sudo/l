--[=[
    Minhdz hub (beta) by dev Minh | Blox Fruits v5.15.1 - RedzLib V5
    Modular Farm Level based on the supplied KaitunBF source; UI powered by the RedzLib V5 community copy.

    Implemented features:
      * Farm Level with existing Kaitun-style two-target Bring Mob controller
      * Farm selector: Level / Bone / Cake Prince / Dough King with one Farm toggle
      * Independent Auto Click with adjustable 1-30 CPS
      * Auto Berry sweep for every available BerryBush in the current server
      * Auto Chest with a 1-50 chest target and pause-on-special-item guard
      * ESP for players, active berries and island locations
      * Draggable circular menu toggle
      * Selectable weapon category + weapon lock
      * Kaitun-style direct CFrame flight + persistent hover above the target
      * Auto Buso (Haki)
      * Single-target Auto Stats (Melee / Sword / Gun / Blox Fruit)
      * Live Status tab with current-server player roster
      * Shop navigator for current-server vendors
      * Auto Sea Travel (unlock requirements still apply)
      * Circular top-left menu toggle, Small/Medium/Big sizing and five muted palettes

    Notes:
      * The script waits for a Pirates/Marines team before creating any hub UI.
      * All farm modes remain OFF until the user selects a mode and enables the Farm toggle.
      * Auto Click is OFF by default and runs independently from Farm.
      * Auto Chest pauses while Fist of Darkness, God's Chalice, Sweet Chalice or Red Key is held; it resumes when the item is no longer held.
      * Auto Berry scans all tagged BerryBush instances in the current server and waits locally when none remain; it does not server-hop.
      * Auto Buso activates once per character spawn, only when Buso is not already active.
      * Auto Equip Selected Weapon starts automatically after UI setup.
      * NoClip is automatically applied during controlled flight/hover and restored afterwards.
      * Disabling Farm Level cancels movement and removes only MinhDZ-owned NPC pull constraints; it never teleports NPCs back to saved positions.
      * Bring Mob is part of Farm Level and is limited to two same-quest NPCs.
      * Both NPCs are pinned to one shared anchor using Kaitun-style BodyPosition; SimulationRadius is refreshed when the executor exposes the API.
      * No hard CFrame snaps, zeroed velocities, or original-position teleports are used.
      * Bone and Cake farms are Third Sea modes. Dough King mode handles Cake/Elite Hunter prerequisites that can be resolved from the current server; God's Chalice and Sweet Chalice requirements still apply.
      * Special farms do not use Farm Level's two-NPC Bring Mob controller.
      * Shop navigation uses visible NPCs; purchases stay in the game's official interaction flow.
]=]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

--// Environment / re-execution cleanup
local ENV = (type(getgenv) == "function" and getgenv()) or _G
local previousHub = ENV.MinhDZBloxFruitsHub
if previousHub and type(previousHub.Unload) == "function" then
    -- v5.9 restored NPCs by teleporting them to their saved spawn CFrames on
    -- unload. Suppress only that stale teleport during an upgrade; preserve its
    -- normal cleanup of movers, Humanoid settings and collision flags.
    if type(previousHub.BroughtMobs) == "table" then
        for _, oldRecord in pairs(previousHub.BroughtMobs) do
            if type(oldRecord) == "table" then
                oldRecord.OriginalPivot = nil
                oldRecord.OriginalLinearVelocity = nil
                oldRecord.OriginalAngularVelocity = nil
            end
        end
    end
    pcall(previousHub.Unload)
end

--// Startup faction gate
-- The RedzLib menu and floating button are not created until a real team is assigned.
-- Change ENV.MinhDZPreferredTeam to "Marines" before execution to prefer Marines.
local STARTUP_PREFERRED_TEAM = ENV.MinhDZPreferredTeam
if STARTUP_PREFERRED_TEAM ~= "Pirates" and STARTUP_PREFERRED_TEAM ~= "Marines" then
    STARTUP_PREFERRED_TEAM = "Pirates"
end
local STARTUP_AUTO_JOIN_TEAM = ENV.MinhDZAutoJoinTeam ~= false

local function getCurrentTeamName()
    local team = LocalPlayer.Team
    return team and team.Name or nil
end

local function hasSelectedTeam()
    local teamName = getCurrentTeamName()
    return teamName == "Pirates" or teamName == "Marines"
end

local function waitForInitialGameReady(timeout)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if game:IsLoaded() and LocalPlayer:FindFirstChild("DataLoaded") then
            return true
        end
        task.wait(0.2)
    end
    return false
end

print("[MinhDZ Hub] Waiting for Blox Fruits to load...")
if not waitForInitialGameReady(120) then
    warn("[MinhDZ Hub] Game data did not finish loading. Main menu was not opened.")
    return
end

local startupPlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
if startupPlayerGui then
    local loadingDeadline = os.clock() + 45
    while startupPlayerGui:FindFirstChild("LoadingScreen") and os.clock() < loadingDeadline do
        task.wait(0.2)
    end
end

if not hasSelectedTeam() then
    print("[MinhDZ Hub] Waiting for Pirates/Marines selection...")
    local startupCommF = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
    local teamDeadline = os.clock() + 90
    local nextTeamRequest = 0
    local requestPending = false

    while not hasSelectedTeam() and os.clock() < teamDeadline do
        if STARTUP_AUTO_JOIN_TEAM and not requestPending and os.clock() >= nextTeamRequest then
            requestPending = true
            nextTeamRequest = os.clock() + 1.5
            task.spawn(function()
                local ok, result = pcall(function()
                    return startupCommF:InvokeServer("SetTeam", STARTUP_PREFERRED_TEAM)
                end)
                if not ok then
                    warn("[MinhDZ Hub] SetTeam request failed: " .. tostring(result))
                end
                requestPending = false
            end)
        end
        task.wait(0.15)
    end
end

if not hasSelectedTeam() then
    warn("[MinhDZ Hub] No faction was selected. Choose Pirates or Marines in the game, then execute MinhDZ Hub again. Main menu remains closed.")
    return
end

-- Wait briefly for the selected faction's character to finish spawning.
local characterDeadline = os.clock() + 45
while os.clock() < characterDeadline do
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        break
    end
    task.wait(0.2)
end

--// RedzLib V5 UI
-- The original REDzHUB/RedzLibV5 URL from the sample is no longer reachable.
-- This public community copy keeps the RedzLib V5 API and its Icons.lua dependency.
local REDZLIB_SOURCE_URL = "https://raw.githubusercontent.com/XenTz-Z/RedzLibV5/refs/heads/main/Source.lua"
local REDZLIB_SAVE_FILE = "MinhdzHub_Beta_v5_15_1.json"

local redzlib
local redzLoadOk, redzLoadResult = pcall(function()
    local source = game:HttpGet(REDZLIB_SOURCE_URL)
    if type(source) ~= "string" or #source < 1000 then
        error("RedzLib source response was empty or incomplete")
    end
    local compiler = loadstring or load
    if type(compiler) ~= "function" then
        error("This executor does not expose loadstring/load")
    end
    local chunk, compileError = compiler(source)
    if type(chunk) ~= "function" then
        error("RedzLib compile failed: " .. tostring(compileError))
    end
    local library = chunk()
    if type(library) ~= "table" or type(library.MakeWindow) ~= "function" then
        error("RedzLib did not return a valid library table")
    end
    return library
end)

if not redzLoadOk then
    error("[MinhDZ Hub] RedzLib V5 could not be loaded: " .. tostring(redzLoadResult))
end
redzlib = redzLoadResult

-- Use the blue-accented Redz theme that most closely matches the reference UI.
pcall(function()
    redzlib:SetTheme("Dark")
end)

-- Compatibility facade: keep the existing MinhDZ feature code unchanged while
-- translating the hub control interface to RedzLib V5 controls.
local Fluent = {
    Options = {},
    Unloaded = false,
    Redz = redzlib
}

function Fluent:CreateWindow(config)
    local nativeWindow = redzlib:MakeWindow({
        Title = config.Title or "Minhdz hub (beta) by dev Minh",
        SubTitle = config.SubTitle or "Blox Fruits | v5.15.1",
        SaveFolder = config.SaveFolder or REDZLIB_SAVE_FILE
    })

    local window = {
        Native = nativeWindow,
        Root = { Visible = true },
        Minimized = false,
        Tabs = {}
    }

    local function setNativeValue(nativeControl, value, controlName)
        if type(nativeControl) ~= "table" then
            warn("[MinhDZ Hub UI] " .. tostring(controlName) .. " returned no control object")
            return false
        end
        local setter = nativeControl.Set or nativeControl.SetValue
        if type(setter) ~= "function" then
            warn("[MinhDZ Hub UI] RedzLib control has no Set method: " .. tostring(controlName))
            return false
        end
        local ok, err = pcall(setter, nativeControl, value)
        if not ok then
            warn("[MinhDZ Hub UI] Could not update " .. tostring(controlName) .. ": " .. tostring(err))
            return false
        end
        return true
    end

    function window:AddTab(tabConfig)
        local title = tostring(tabConfig.Title or ("Tab " .. tostring(#self.Tabs + 1)))
        local nativeTab = nativeWindow:MakeTab({ title, tabConfig.Icon or "" })
        local tab = { Native = nativeTab, Title = title }

        function tab:AddParagraph(rowConfig)
            rowConfig = rowConfig or {}
            local titleText = tostring(rowConfig.Title or "Information")
            local contentText = tostring(rowConfig.Content or "")
            local nativeParagraph = nativeTab:AddParagraph({ titleText, contentText })
            local paragraph = { Native = nativeParagraph }
            function paragraph:SetDesc(value)
                local target = self.Native
                if type(target) == "table" and type(target.SetDesc) == "function" then
                    local ok, err = pcall(target.SetDesc, target, tostring(value or ""))
                    if not ok then
                        warn("[MinhDZ Hub UI] Paragraph update failed: " .. tostring(err))
                    end
                elseif type(target) == "table" and type(target.Set) == "function" then
                    pcall(target.Set, target, tostring(value or ""))
                end
            end
            return paragraph
        end

        function tab:AddToggle(id, rowConfig)
            rowConfig = rowConfig or {}
            local nativeControl = nativeTab:AddToggle({
                Name = tostring(rowConfig.Title or id),
                Description = tostring(rowConfig.Description or ""),
                Default = rowConfig.Default == true,
                Flag = tostring(id),
                Callback = rowConfig.Callback
            })
            local control = {
                Native = nativeControl,
                Value = rowConfig.Default == true,
                Visible = true
            }
            function control:SetValue(value)
                self.Value = value == true
                return setNativeValue(self.Native, self.Value, id)
            end
            Fluent.Options[id] = control
            return control
        end

        function tab:AddButton(rowConfig)
            rowConfig = rowConfig or {}
            return nativeTab:AddButton({
                Name = tostring(rowConfig.Title or "Action"),
                Description = tostring(rowConfig.Description or ""),
                Callback = rowConfig.Callback
            })
        end

        function tab:AddDropdown(id, rowConfig)
            rowConfig = rowConfig or {}
            local options = rowConfig.Values or {}
            local nativeControl = nativeTab:AddDropdown({
                Name = tostring(rowConfig.Title or id),
                Description = tostring(rowConfig.Description or ""),
                Options = options,
                Default = rowConfig.Default,
                Flag = tostring(id),
                Callback = rowConfig.Callback
            })
            local control = {
                Native = nativeControl,
                Value = rowConfig.Default,
                Visible = true
            }
            function control:SetValue(value)
                self.Value = value
                return setNativeValue(self.Native, value, id)
            end
            Fluent.Options[id] = control
            return control
        end

        function tab:AddSlider(id, rowConfig)
            rowConfig = rowConfig or {}
            local rounding = math.clamp(tonumber(rowConfig.Rounding) or 0, 0, 4)
            local increase = 10 ^ (-rounding)
            local nativeControl = nativeTab:AddSlider({
                Name = tostring(rowConfig.Title or id),
                Description = tostring(rowConfig.Description or ""),
                Min = tonumber(rowConfig.Min) or 0,
                Max = tonumber(rowConfig.Max) or 100,
                Increase = increase,
                Default = tonumber(rowConfig.Default) or tonumber(rowConfig.Min) or 0,
                Flag = tostring(id),
                Callback = rowConfig.Callback
            })
            local control = {
                Native = nativeControl,
                Value = tonumber(rowConfig.Default) or tonumber(rowConfig.Min) or 0,
                Visible = true
            }
            function control:SetValue(value)
                self.Value = tonumber(value) or self.Value
                return setNativeValue(self.Native, self.Value, id)
            end
            Fluent.Options[id] = control
            return control
        end

        function tab:AddTextBox(id, rowConfig)
            rowConfig = rowConfig or {}
            local control = { Native = nil, Value = tostring(rowConfig.Default or ""), Visible = true }
            local nativeControl = nativeTab:AddTextBox({
                Name = tostring(rowConfig.Title or id),
                Description = tostring(rowConfig.Description or ""),
                Default = control.Value,
                ClearText = false,
                PlaceholderText = tostring(rowConfig.PlaceholderText or "Enter value"),
                Callback = function(value)
                    control.Value = tostring(value or "")
                    if type(rowConfig.Callback) == "function" then
                        rowConfig.Callback(control.Value)
                    end
                end
            })
            control.Native = nativeControl
            Fluent.Options[id] = control
            return control
        end

        table.insert(self.Tabs, tab)
        return tab
    end

    function window:Minimize()
        if type(self.Native.Minimize) == "function" then
            self.Native:Minimize()
            self.Root.Visible = not self.Root.Visible
            self.Minimized = not self.Root.Visible
        end
        if type(self.OnVisibilityChanged) == "function" then
            pcall(self.OnVisibilityChanged)
        end
    end

    function window:SelectTab(tabOrIndex)
        if type(tabOrIndex) == "number" then
            return self.Native:SelectTab(tabOrIndex)
        end
        return self.Native:SelectTab(tabOrIndex and (tabOrIndex.Native or tabOrIndex))
    end

    function Fluent:Notify(notification)
        if self.Unloaded then return end
        local starterGui = game:GetService("StarterGui")
        pcall(function()
            starterGui:SetCore("SendNotification", {
                Title = tostring(notification.Title or "MinhDZ Hub"),
                Text = tostring(notification.Content or ""),
                Duration = tonumber(notification.Duration) or 4
            })
        end)
    end

    function Fluent:Destroy()
        if self.Unloaded then return end
        self.Unloaded = true
        pcall(function()
            local coreGui = game:GetService("CoreGui")
            local gui = coreGui:FindFirstChild("redz Library V5")
            if gui then gui:Destroy() end
        end)
        pcall(function()
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            local gui = playerGui and playerGui:FindFirstChild("redz Library V5")
            if gui then gui:Destroy() end
        end)
    end

    return window
end

local Window = Fluent:CreateWindow({
    Title = "Minhdz hub (beta) by dev Minh",
    SubTitle = "Blox Fruits | v5.15.1",
    SaveFolder = REDZLIB_SAVE_FILE
})

-- Sidebar order follows the available Banana Hub reference layout. Stats and
-- utility controls share one Character tab instead of splitting the same topic.
local ShopTab = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" })
local StatusTab = Window:AddTab({ Title = "Server", Icon = "users" })
local CharacterTab = Window:AddTab({ Title = "Character", Icon = "user" })
local SettingsTab = Window:AddTab({ Title = "Settings", Icon = "settings" })
local SkillsTab = Window:AddTab({ Title = "Skills", Icon = "swords" })
local FarmingTab = Window:AddTab({ Title = "Farming", Icon = "swords" })
local CombinedFarmTab = Window:AddTab({ Title = "Farm Other", Icon = "layers" })
local OtherFarmTab = Window:AddTab({ Title = "Travel", Icon = "gem" })
local ESPTab = Window:AddTab({ Title = "ESP", Icon = "scan-eye" })

local Tabs = {
    Shop = ShopTab,
    Status = StatusTab,
    Stats = CharacterTab,
    Utility = CharacterTab,
    Settings = SettingsTab,
    Skills = SkillsTab,
    Farming = FarmingTab,
    FarmOther = CombinedFarmTab,
    Travel = OtherFarmTab,
    ESP = ESPTab
}

-- Circular MZ reopen button; the window and all controls are provided by RedzLib.
local FloatingGui = Instance.new("ScreenGui")
FloatingGui.Name = "MinhDZHubFloatingToggle"
FloatingGui.ResetOnSpawn = false
FloatingGui.IgnoreGuiInset = true
FloatingGui.DisplayOrder = 100000
FloatingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local floatingParent
pcall(function() floatingParent = game:GetService("CoreGui") end)
local parentedToCoreGui = false
if floatingParent then
    parentedToCoreGui = pcall(function() FloatingGui.Parent = floatingParent end)
end
if not parentedToCoreGui then
    FloatingGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "MenuToggle"
ToggleButton.AnchorPoint = Vector2.new(0, 0)
ToggleButton.Position = UDim2.new(0, 16, 0, 16)
ToggleButton.Size = UDim2.fromOffset(48, 48)
ToggleButton.BackgroundColor3 = Color3.fromRGB(31, 38, 51)
ToggleButton.BackgroundTransparency = 0.04
ToggleButton.BorderSizePixel = 0
ToggleButton.AutoButtonColor = true
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Text = "MZ"
ToggleButton.TextColor3 = Color3.fromRGB(220, 232, 248)
ToggleButton.TextSize = 13
ToggleButton.ZIndex = 100
ToggleButton.Parent = FloatingGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = ToggleButton

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(65, 150, 255)
ToggleStroke.Thickness = 1.2
ToggleStroke.Transparency = 0.18
ToggleStroke.Parent = ToggleButton

local MenuPalettes = {
    Dark = {
        Background = Color3.fromRGB(24, 28, 37),
        Panel = Color3.fromRGB(34, 40, 52),
        Button = Color3.fromRGB(48, 58, 75),
        Accent = Color3.fromRGB(105, 157, 220),
        AccentSoft = Color3.fromRGB(57, 78, 105),
        Text = Color3.fromRGB(225, 233, 245)
    },
    Blue = {
        Background = Color3.fromRGB(23, 29, 40),
        Panel = Color3.fromRGB(31, 43, 59),
        Button = Color3.fromRGB(43, 64, 88),
        Accent = Color3.fromRGB(86, 153, 226),
        AccentSoft = Color3.fromRGB(48, 82, 119),
        Text = Color3.fromRGB(226, 237, 249)
    },
    Purple = {
        Background = Color3.fromRGB(29, 26, 39),
        Panel = Color3.fromRGB(43, 37, 56),
        Button = Color3.fromRGB(63, 53, 81),
        Accent = Color3.fromRGB(153, 126, 205),
        AccentSoft = Color3.fromRGB(82, 66, 111),
        Text = Color3.fromRGB(235, 229, 247)
    },
    Red = {
        Background = Color3.fromRGB(34, 27, 31),
        Panel = Color3.fromRGB(49, 37, 42),
        Button = Color3.fromRGB(72, 51, 59),
        Accent = Color3.fromRGB(190, 112, 124),
        AccentSoft = Color3.fromRGB(104, 62, 72),
        Text = Color3.fromRGB(244, 231, 234)
    },
    Green = {
        Background = Color3.fromRGB(24, 32, 31),
        Panel = Color3.fromRGB(34, 47, 44),
        Button = Color3.fromRGB(48, 69, 63),
        Accent = Color3.fromRGB(103, 166, 144),
        AccentSoft = Color3.fromRGB(53, 91, 78),
        Text = Color3.fromRGB(226, 241, 235)
    }
}

local function findRedzScreenGui()
    local coreGui
    pcall(function() coreGui = game:GetService("CoreGui") end)
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if coreGui then
        local gui = coreGui:FindFirstChild("redz Library V5")
        if gui and gui:IsA("ScreenGui") then return gui end
    end
    if playerGui then
        local gui = playerGui:FindFirstChild("redz Library V5")
        if gui and gui:IsA("ScreenGui") then return gui end
    end
    return nil
end

local function findRedzRootFrame()
    local gui = findRedzScreenGui()
    if not gui then return nil end
    local best, bestArea = nil, 0
    for _, child in ipairs(gui:GetChildren()) do
        if child:IsA("GuiObject") then
            local size = child.AbsoluteSize
            local area = size.X * size.Y
            if area > bestArea then
                best, bestArea = child, area
            end
        end
    end
    if best then return best end
    return gui:FindFirstChildWhichIsA("Frame", true)
end

local MenuScaleObject
local function applyMenuScale(sizeName)
    local scaleByName = { Small = 0.86, Medium = 1, Big = 1.14 }
    local scale = scaleByName[sizeName] or 1
    local rootFrame = findRedzRootFrame()
    if not rootFrame then
        return false
    end
    if not MenuScaleObject or MenuScaleObject.Parent ~= rootFrame then
        MenuScaleObject = rootFrame:FindFirstChild("MinhDZMenuScale")
        if not MenuScaleObject then
            MenuScaleObject = Instance.new("UIScale")
            MenuScaleObject.Name = "MinhDZMenuScale"
            MenuScaleObject.Parent = rootFrame
        end
    end
    MenuScaleObject.Scale = scale
    return true
end

local ActiveMenuPaletteName = "Dark"
local function applyMenuPalette(colorName)
    local palette = MenuPalettes[colorName] or MenuPalettes.Dark
    ActiveMenuPaletteName = MenuPalettes[colorName] and colorName or "Dark"
    pcall(function()
        redzlib:SetTheme({
            Background = palette.Background,
            Accent = palette.Accent,
            PrimaryText = palette.Text,
            SecondaryText = palette.Text,
            Divider = palette.AccentSoft,
            Header = palette.Panel,
            Box = palette.Panel,
            Button = palette.Button,
            Hover = palette.AccentSoft,
            Toggle = palette.Accent,
            ToggleBackground = palette.Panel,
            Dropdown = palette.Button,
            DropdownBackground = palette.Panel,
            Scrollbar = palette.Accent,
            Outline = palette.AccentSoft,
            Shadow = palette.Background
        })
    end)
    local gui = findRedzScreenGui()
    if gui then
        for _, object in ipairs(gui:GetDescendants()) do
            if object:IsA("UIStroke") then
                object.Color = palette.Accent
            elseif object:IsA("TextButton") then
                local lowerName = object.Name:lower()
                if lowerName:find("tab", 1, true) or lowerName:find("toggle", 1, true) then
                    object.BackgroundColor3 = palette.AccentSoft
                else
                    object.BackgroundColor3 = palette.Button
                end
                object.TextColor3 = palette.Text
            elseif object:IsA("Frame") or object:IsA("ScrollingFrame") then
                local lowerName = object.Name:lower()
                if lowerName:find("sidebar", 1, true) or lowerName:find("header", 1, true) or lowerName:find("topbar", 1, true) then
                    object.BackgroundColor3 = palette.Panel
                elseif lowerName:find("window", 1, true) or lowerName:find("background", 1, true) then
                    object.BackgroundColor3 = palette.Background
                end
            end
        end
    end
    ToggleButton.BackgroundColor3 = palette.Button
    ToggleButton.TextColor3 = palette.Text
    ToggleStroke.Color = palette.Accent
end

local function syncMenuToggleLabel()
    local visible = Window.Root and Window.Root.Visible == true
    local palette = MenuPalettes[ActiveMenuPaletteName] or MenuPalettes.Dark
    ToggleButton.Text = "MZ"
    ToggleButton.TextColor3 = visible and palette.Text or palette.Accent
end

task.spawn(function()
    for _ = 1, 30 do
        if applyMenuScale("Medium") then
            applyMenuPalette("Dark")
            break
        end
        task.wait(0.5)
    end
end)

local function setMenuVisible(visible)
    if not Window.Root then return end
    visible = visible == true
    if Window.Root.Visible ~= visible then
        Window:Minimize()
    end
    syncMenuToggleLabel()
end

Window.OnVisibilityChanged = syncMenuToggleLabel

local toggleInputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
        Window:Minimize()
        task.defer(syncMenuToggleLabel)
    end
end)

-- Drag the floating control anywhere on screen. A short click still toggles the menu.
local toggleDragConnections = {}
local toggleDrag = {
    Dragging = false,
    DragInput = nil,
    StartPointer = nil,
    StartPosition = nil,
    Moved = false,
    SuppressActivation = false
}
ToggleButton.Active = true

ToggleButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        toggleDrag.Dragging = true
        toggleDrag.Moved = false
        toggleDrag.StartPointer = input.Position
        toggleDrag.StartPosition = ToggleButton.Position
        if input.UserInputType == Enum.UserInputType.Touch then
            toggleDrag.DragInput = input
        end
    end
end)

ToggleButton.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        toggleDrag.DragInput = input
    end
end)

table.insert(toggleDragConnections, UserInputService.InputChanged:Connect(function(input)
    if not toggleDrag.Dragging then return end
    local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
    local isTrackedTouch = input.UserInputType == Enum.UserInputType.Touch
        and input == toggleDrag.DragInput
    if not isMouseMove and not isTrackedTouch then return end

    local delta = input.Position - toggleDrag.StartPointer
    if delta.Magnitude > 5 then
        toggleDrag.Moved = true
    end
    if not toggleDrag.Moved then return end

    local screenSize = FloatingGui.AbsoluteSize
    local buttonSize = ToggleButton.AbsoluteSize
    local maxX = math.max(0, screenSize.X - buttonSize.X)
    local maxY = math.max(0, screenSize.Y - buttonSize.Y)
    local startX = toggleDrag.StartPosition.X.Offset
    local startY = toggleDrag.StartPosition.Y.Offset
    local newX = math.clamp(startX + delta.X, 0, maxX)
    local newY = math.clamp(startY + delta.Y, 0, maxY)
    ToggleButton.Position = UDim2.fromOffset(newX, newY)
end))

table.insert(toggleDragConnections, UserInputService.InputEnded:Connect(function(input)
    local endedMouse = input.UserInputType == Enum.UserInputType.MouseButton1
    local endedTouch = input.UserInputType == Enum.UserInputType.Touch
        and input == toggleDrag.DragInput
    if toggleDrag.Dragging and (endedMouse or endedTouch) then
        toggleDrag.Dragging = false
        if toggleDrag.Moved then
            toggleDrag.SuppressActivation = true
            task.delay(0.18, function()
                toggleDrag.SuppressActivation = false
            end)
        end
        toggleDrag.DragInput = nil
    end
end))

ToggleButton.Activated:Connect(function()
    if toggleDrag.SuppressActivation then return end
    setMenuVisible(not (Window.Root and Window.Root.Visible == true))
end)

--// Game remotes / modules used by the source script
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local CommF = RemotesFolder:WaitForChild("CommF_")
local NetFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
local RegisterAttack = NetFolder:WaitForChild("RE/RegisterAttack")
local RegisterHit = NetFolder:WaitForChild("RE/RegisterHit")

local GlobalModule
local function getGlobalModule()
    if not GlobalModule then
        pcall(function()
            GlobalModule = require(ReplicatedStorage:WaitForChild("Global", 10))
        end)
    end
    return GlobalModule
end

local QuestModule
local GuideModule
local function getQuestModule()
    if not QuestModule then
        local ok, result = pcall(require, ReplicatedStorage:WaitForChild("Quests"))
        if ok and type(result) == "table" then
            QuestModule = result
        end
    end
    return QuestModule
end

local function getGuideModule()
    if not GuideModule then
        local ok, result = pcall(require, ReplicatedStorage:WaitForChild("GuideModule"))
        if ok and type(result) == "table" then
            GuideModule = result
        end
    end
    return GuideModule
end

--// State
local Hub = {
    Unloading = false,
    Features = {
        FarmLevel = { Enabled = false, Token = 0 },
        SpecialFarm = { Enabled = false, Token = 0 },
        AutoClick = { Enabled = false, Token = 0 },
        AutoChest = { Enabled = false, Token = 0 },
        AutoBerry = { Enabled = false, Token = 0 },
        ESPPlayers = { Enabled = false, Token = 0 },
        ESPBerry = { Enabled = false, Token = 0 },
        ESPIslands = { Enabled = false, Token = 0 },
        AutoEquipMelee = { Enabled = false, Token = 0 },
        AutoBuso = { Enabled = false, Token = 0 },
        AutoStats = { Enabled = false, Token = 0 },
        AutoSeaTravel = { Enabled = false, Token = 0 },
        ShopTravel = { Enabled = false, Token = 0 }
    },
    Settings = {
        FlightSpeed = 250,
        NoClipEnabled = true,
        AttackHeight = 18,
        AttackInterval = 0.18,
        BringPairRadius = 300,
        WeaponCategory = "Melee",
        AutoStatCategory = "Melee",
        FruitSkill = "Z",
        PreferredTeam = STARTUP_PREFERRED_TEAM,
        AutoJoinTeam = STARTUP_AUTO_JOIN_TEAM,
        ShopVendor = "Blox Fruit Dealer",
        SelectedFarmMode = "Farm Level",
        ClicksPerSecond = 20,
        ChestTargetCount = 5,
        MenuSize = "Medium",
        MenuColor = "Dark"
    },
    Status = "Ready",
    LastFarmQuestStart = 0,
    LastSeaTravel = 0,
    LastSeaCheck = 0,
    BusoCharacter = nil,
    BusoCharacterReadyAt = 0,
    BusoAttemptedCharacter = nil,
    LastEquipCheck = 0,
    LastStatAllocation = 0,
    LastCakeSpawnerCall = 0,
    LastDoughNpcCall = 0,
    LastEliteHunterCall = 0,
    ChestCollectedCount = 0,
    ChestPending = nil,
    ChestPausedItem = nil,
    BerryWaitingNotified = false,
    AutoStatFailureCount = 0,
    MismatchCount = 0,
    MovementToken = 0,
    MovementObjects = {},
    SavedCollision = {},
    NoClipConnection = nil,
    NoClipStepConnection = nil,
    NoClipCharacter = nil,
    Hover = { Connection = nil, Position = nil, Gyro = nil, TargetRoot = nil, SecondTargetRoot = nil, Character = nil, Humanoid = nil, AutoRotate = nil },
    FarmTarget = nil,
    BroughtMobs = setmetatable({}, { __mode = "k" }),
    BringControlStatus = "not active",
    UnresponsiveFarmTargets = setmetatable({}, { __mode = "k" }),
    FarmTargetWatch = { Model = nil, LastHealth = nil, LastDamageAt = 0 },
    FarmTargetWatchers = setmetatable({}, { __mode = "k" }),
    ActiveFarmPair = nil
}

ENV.MinhDZBloxFruitsHub = Hub

local function notify(title, content, duration)
    pcall(function()
        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = duration or 4
        })
    end)
end

local function setStatus(message)
    message = tostring(message)
    if Hub.Status ~= message then
        Hub.Status = message
        print("[MinhDZ Hub] " .. Hub.Status)
        local lower = message:lower()
        if lower:find("error", 1, true)
            or lower:find("unavailable", 1, true)
            or lower:find("not found", 1, true)
            or lower:find("no level quest", 1, true)
            or lower:find("rejected", 1, true) then
            notify("MinhDZ Hub diagnostics", message, 6)
        end
    end
end

local function isFeatureActive(name, token)
    local feature = Hub.Features[name]
    return feature ~= nil
        and feature.Enabled
        and feature.Token == token
        and not Hub.Unloading
        and not Fluent.Unloaded
end

--// Character helpers
local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local SPECIAL_CHEST_ITEM_NAMES = {
    ["fist of darkness"] = "Fist of Darkness",
    ["god's chalice"] = "God's Chalice",
    ["sweet chalice"] = "Sweet Chalice",
    ["red key"] = "Red Key"
}

local function getHeldSpecialChestItem()
    local containers = {
        LocalPlayer:FindFirstChildOfClass("Backpack"),
        getCharacter()
    }
    for _, container in ipairs(containers) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                local displayName = SPECIAL_CHEST_ITEM_NAMES[string.lower(item.Name)]
                if displayName then
                    return displayName
                end
            end
        end
    end
    return nil
end

local function getPlayerLevel()
    local data = LocalPlayer:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    return level and tonumber(level.Value) or nil
end

local function getSeaIndex()
    local mapAttribute = workspace:GetAttribute("MAP")
    if mapAttribute == "Sea1" then
        return 1
    elseif mapAttribute == "Sea2" then
        return 2
    elseif mapAttribute == "Sea3" then
        return 3
    end

    -- Same PlaceId fallback table used by the supplied KaitunBF script.
    local placeMap = {
        [2753915549] = 1,
        [79091703265657] = 2,
        [4442272183] = 2,
        [100117331123089] = 3,
        [7449423635] = 3
    }
    return placeMap[game.PlaceId] or 1
end

local function stripLevelSuffix(name)
    local value = tostring(name or "")
    value = value:gsub("%s*%[Lv%.?%s*%d+%]%s*", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function normalizeMobName(name)
    local value = stripLevelSuffix(name)
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d+%s+", "")
    value = value:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "Military Soldiers" then
        value = "Military Soldier"
    end
    return value
end

local function mobNamesMatch(left, right)
    if not left or not right then
        return false
    end
    local a = normalizeMobName(left):lower()
    local b = normalizeMobName(right):lower()
    if a == b then
        return true
    end
    if #a > 1 and a:sub(-1) == "s" and a:sub(-2) ~= "ss" then
        a = a:sub(1, -2)
    end
    if #b > 1 and b:sub(-1) == "s" and b:sub(-2) ~= "ss" then
        b = b:sub(1, -2)
    end
    return a == b
end

--// Quest selection: follows the level/quest selection pattern in KaitunBF.
local BLACKLISTED_QUESTS = {
    BartiloQuest = true,
    CitizenQuest = true,
    Trainees = true,
    MarineQuest = true
}

local function selectQuestForLevel(level, sea)
    local quests = getQuestModule()
    if not quests then
        return nil, "ReplicatedStorage.Quests is unavailable"
    end

    local effectiveLevel = level
    if sea == 1 and effectiveLevel >= 700 then
        effectiveLevel = 699
    elseif sea == 2 and effectiveLevel >= 1500 then
        effectiveLevel = 1499
    end

    local best = nil
    local bestRequirement = -1

    for questId, stages in pairs(quests) do
        if not BLACKLISTED_QUESTS[questId] and type(stages) == "table" then
            for stageId, stage in pairs(stages) do
                local requiredLevel = tonumber(stage.LevelReq)
                local tasks = type(stage.Task) == "table" and stage.Task or nil

                if requiredLevel and tasks and requiredLevel <= effectiveLevel and requiredLevel >= bestRequirement then
                    for mobName, amount in pairs(tasks) do
                        local numericAmount = tonumber(amount) or 0
                        local normalizedName = normalizeMobName(mobName)
                        if numericAmount > 1
                            and normalizedName ~= "Gladiator"
                            and normalizedName ~= "Factory Staff" then
                            bestRequirement = requiredLevel
                            best = {
                                QuestId = questId,
                                StageId = stageId,
                                MobName = normalizedName,
                                LevelReq = requiredLevel,
                                QuestName = stage.Name
                            }
                        end
                    end
                end
            end
        end
    end

    if not best then
        return nil, "No level quest found for the current sea/level"
    end
    return best
end

--// Resolve quest-giver CFrame from GuideModule.Data.NPCList (same source data as KaitunBF).
local function getObjectCFrame(object)
    if typeof(object) == "CFrame" then
        return object
    elseif typeof(object) == "Vector3" then
        return CFrame.new(object)
    end
    if typeof(object) ~= "Instance" then
        return nil
    end
    if object:IsA("BasePart") then
        return object.CFrame
    elseif object:IsA("Attachment") then
        return object.WorldCFrame
    elseif object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        if ok then
            return pivot
        end
    end
    local ok, cframe = pcall(function()
        return object.CFrame
    end)
    return ok and typeof(cframe) == "CFrame" and cframe or nil
end

local function getQuestGiverCFrame(requiredLevel)
    local guide = getGuideModule()
    local npcList = guide and guide.Data and guide.Data.NPCList
    if type(npcList) ~= "table" then
        return nil
    end

    for npcObject, npcInfo in pairs(npcList) do
        if type(npcInfo) == "table" and type(npcInfo.Levels) == "table" then
            for _, levelValue in ipairs(npcInfo.Levels) do
                if tonumber(levelValue) == tonumber(requiredLevel) then
                    local npcCFrame = getObjectCFrame(npcObject)
                    if not npcCFrame then
                        npcCFrame = getObjectCFrame(npcInfo.CFrame or npcInfo.NPC or npcInfo.Position)
                    end
                    if npcCFrame then
                        return npcCFrame
                    end
                end
            end
        end
    end
    return nil
end

--// Current quest parser. Mirrors KaitunBF's TrackedQuestFrame/Main.Quest
-- paths and includes a visible-label fallback for minor GUI layout changes.
local function parseQuestMob(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local value = text
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s*%d*%s*", "")
    value = value:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    value = value:gsub("%s+%d+%s*/%s*%d+%s*$", "")
    value = value:gsub("^%s*%d+%s+", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("^[Mm]il%.?%s*[Ss]oldier.*", "Military Soldier")
    value = value:gsub("^[Mm]il%.?%s*[Ss]py.*", "Military Spy")

    if value == "" then
        return nil
    end
    return normalizeMobName(value)
end

local function readActiveQuest()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil, nil, 0, 0
    end

    local tracked = playerGui:FindFirstChild("TrackedQuestFrame")
    if tracked and tracked.Enabled then
        local frame = tracked:FindFirstChild("Frame")
        if frame then
            local header = frame:FindFirstChild("header")
            local headerLabel = header and header:FindFirstChild("textLabel")
            local description = frame:FindFirstChild("description")
            local progressLabel = frame:FindFirstChild("progress")
            local headerText = headerLabel and headerLabel.Text or ""
            local descriptionText = description and description.Text or ""
            local titleText = headerText:match("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d") and headerText or descriptionText
            local mob = parseQuestMob(titleText)
            local current, maximum = 0, 0
            if progressLabel and progressLabel.Text ~= "" then
                local cur, max = progressLabel.Text:match("(%d+)%s*/%s*(%d+)")
                current, maximum = tonumber(cur) or 0, tonumber(max) or 0
            end
            if mob then
                return mob, titleText, current, maximum
            end
        end
    end

    local main = playerGui:FindFirstChild("Main")
    local questFrame = main and main:FindFirstChild("Quest")
    if questFrame and questFrame.Visible then
        local container = questFrame:FindFirstChild("Container")
        local titleFolder = container and container:FindFirstChild("QuestTitle")
        local title = titleFolder and titleFolder:FindFirstChild("Title")
        local titleText = title and title.Text or ""
        local mob = parseQuestMob(titleText)
        local cur, max = titleText:match("%((%d+)%s*/%s*(%d+)%)")
        if mob then
            return mob, titleText, tonumber(cur) or 0, tonumber(max) or 0
        end
    end

    -- Deep fallback: KaitunBF also searches visible text labels when the
    -- tracked-quest GUI is temporarily rebuilt by the game.
    local function isVisible(element)
        local current = element
        while current and current:IsA("GuiObject") do
            if not current.Visible then
                return false
            end
            current = current.Parent
        end
        return true
    end

    local foundMob, foundTitle, foundCurrent, foundMaximum
    local function scan(node)
        if foundMob then
            return
        end
        if (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) and isVisible(node) then
            local text = node.Text
            if type(text) == "string" and text:match("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d") then
                local mob = parseQuestMob(text)
                if mob then
                    local cur, max = text:match("%((%d+)%s*/%s*(%d+)%)")
                    if not cur then
                        cur, max = text:match("(%d+)%s*/%s*(%d+)")
                    end
                    foundMob, foundTitle = mob, text
                    foundCurrent, foundMaximum = tonumber(cur) or 0, tonumber(max) or 0
                    return
                end
            end
        end
        for _, child in ipairs(node:GetChildren()) do
            if foundMob then
                return
            end
            scan(child)
        end
    end
    scan(playerGui)

    return foundMob, foundTitle, foundCurrent or 0, foundMaximum or 0
end

--// Movement: smooth BodyPosition flight with a speed-limited moving target.
-- FlightSpeed is applied by advancing the Position target in bounded Heartbeat steps.
local function restoreCollision()
    for part, originalValue in pairs(Hub.SavedCollision) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = originalValue
            end)
        end
    end
    table.clear(Hub.SavedCollision)
end

local function disableCollisionForPart(part)
    if not part or not part:IsA("BasePart") then
        return
    end
    if Hub.SavedCollision[part] == nil then
        Hub.SavedCollision[part] = part.CanCollide
    end
    part.CanCollide = false
end

local function disableCollisionForCharacter(character)
    if not character or not Hub.Settings.NoClipEnabled then
        return
    end

    if Hub.NoClipCharacter ~= character then
        if Hub.NoClipConnection then
            pcall(function() Hub.NoClipConnection:Disconnect() end)
            Hub.NoClipConnection = nil
        end
        restoreCollision()
        Hub.NoClipCharacter = character
    end

    -- Apply to current parts and any accessories/body parts created mid-flight.
    for _, descendant in ipairs(character:GetDescendants()) do
        disableCollisionForPart(descendant)
    end

    if not Hub.NoClipConnection then
        Hub.NoClipConnection = character.DescendantAdded:Connect(function(descendant)
            if Hub.NoClipCharacter == character and Hub.Settings.NoClipEnabled then
                disableCollisionForPart(descendant)
            end
        end)
    end

    -- Re-apply every physics step: character controllers/game scripts may reset CanCollide.
    if not Hub.NoClipStepConnection then
        Hub.NoClipStepConnection = RunService.Stepped:Connect(function()
            local liveCharacter = getCharacter()
            if Hub.Settings.NoClipEnabled and liveCharacter and Hub.NoClipCharacter == liveCharacter then
                for _, part in ipairs(liveCharacter:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if Hub.SavedCollision[part] == nil then
                            Hub.SavedCollision[part] = part.CanCollide
                        end
                        part.CanCollide = false
                    end
                end
            end
        end)
    end
end

local function stopNoClip()
    if Hub.NoClipConnection then
        pcall(function() Hub.NoClipConnection:Disconnect() end)
        Hub.NoClipConnection = nil
    end
    if Hub.NoClipStepConnection then
        pcall(function() Hub.NoClipStepConnection:Disconnect() end)
        Hub.NoClipStepConnection = nil
    end
    Hub.NoClipCharacter = nil
    restoreCollision()
end

local function destroyMovementObjects()
    for _, object in pairs(Hub.MovementObjects) do
        if object and object.Parent then
            pcall(function() object:Destroy() end)
        end
    end
    table.clear(Hub.MovementObjects)
end

local function stopHover()
    local hover = Hub.Hover
    if hover.Connection then
        pcall(function() hover.Connection:Disconnect() end)
        hover.Connection = nil
    end
    for _, object in pairs({ hover.Position, hover.Gyro }) do
        if object and object.Parent then
            pcall(function() object:Destroy() end)
        end
    end
    if hover.Humanoid and hover.Humanoid.Parent and hover.AutoRotate ~= nil then
        pcall(function() hover.Humanoid.AutoRotate = hover.AutoRotate end)
    end
    hover.Position = nil
    hover.Gyro = nil
    stopNoClip()
    hover.TargetRoot = nil
    hover.SecondTargetRoot = nil
    hover.Character = nil
    hover.Humanoid = nil
    hover.AutoRotate = nil
end

local function stopMovement()
    Hub.MovementToken = Hub.MovementToken + 1
    destroyMovementObjects()
    stopNoClip()
    local root = getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

local function moveTo(targetCFrame, farmToken, featureName)
    featureName = featureName or "FarmLevel"
    if typeof(targetCFrame) ~= "CFrame" then
        return false
    end

    stopHover()
    Hub.MovementToken = Hub.MovementToken + 1
    local movementToken = Hub.MovementToken
    local character = getCharacter()
    local humanoid = getHumanoid()
    local root = getRoot()
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        return false
    end

    destroyMovementObjects()
    disableCollisionForCharacter(character)

    -- Kaitun's supplied TweenController uses a direct CFrame step on Heartbeat,
    -- rather than a BodyPosition chasing a moving target. Its default is 275;
    -- Main uses 250 (about 9% slower) while retaining the same 50..325 range.
    local flightSpeed = math.clamp(tonumber(Hub.Settings.FlightSpeed) or 250, 50, 325)
    local targetPosition = targetCFrame.Position
    local initialDistance = (root.Position - targetPosition).Magnitude
    if initialDistance < 6 then
        stopNoClip()
        return true
    end

    -- Match Kaitun's zero-velocity float support, with a hub-owned name so cleanup
    -- never touches a float object created by another script.
    local floatForce = Instance.new("BodyVelocity")
    floatForce.Name = "MinhDZKaitunFloat"
    floatForce.MaxForce = Vector3.new(100000, 100000, 100000)
    floatForce.Velocity = Vector3.zero
    floatForce.P = 10000
    floatForce.Parent = root
    Hub.MovementObjects.Float = floatForce

    if humanoid.FloorMaterial ~= Enum.Material.Air then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
    end
    humanoid.PlatformStand = false

    local movementCharacter = character
    local movementHumanoid = humanoid
    local currentSpeed = flightSpeed
    local lastSpeedRecoveryAt = 0
    local lastExpectedPosition = root.Position
    local startedAt = os.clock()
    local moveTimeout = math.clamp((initialDistance / flightSpeed) * 2.5 + 20, 20, 300)
    local reachedTarget = false

    while true do
        if not isFeatureActive(featureName, farmToken) or movementToken ~= Hub.MovementToken then
            break
        end
        if featureName == "AutoChest" then
            local heldSpecialItem = getHeldSpecialChestItem()
            if heldSpecialItem then
                Hub.ChestPausedItem = heldSpecialItem
                setStatus("Auto Chest | paused: holding " .. heldSpecialItem)
                break
            end
        end
        if os.clock() - startedAt > moveTimeout then
            setStatus("Flight timed out; movement was stopped safely")
            break
        end

        local liveCharacter = getCharacter()
        local liveHumanoid = getHumanoid()
        local liveRoot = getRoot()
        if liveCharacter ~= movementCharacter or not liveHumanoid or liveHumanoid.Health <= 0
            or not liveRoot or liveRoot ~= root or root.Anchored or not floatForce.Parent then
            break
        end

        local dt = RunService.Heartbeat:Wait()
        dt = math.max(0, math.min(tonumber(dt) or 0, 0.1))
        local currentPosition = root.Position
        local offset = targetPosition - currentPosition
        local remainingDistance = offset.Magnitude

        if remainingDistance <= 2.5 then
            root.CFrame = targetCFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            reachedTarget = true
            break
        end

        -- Directly ported speed recovery behavior from Kaitun:
        -- large corrections temporarily reduce speed; otherwise it ramps back up.
        if (currentPosition - lastExpectedPosition).Magnitude > 40 then
            currentSpeed = math.max(120, currentSpeed * 0.7)
            lastSpeedRecoveryAt = os.clock() + 3
        elseif os.clock() >= lastSpeedRecoveryAt then
            currentSpeed = math.min(flightSpeed, currentSpeed * 1.08)
            lastSpeedRecoveryAt = os.clock() + 1.5
        end

        local stepDistance = math.min(currentSpeed * dt, 18, remainingDistance)
        if stepDistance > 0 and remainingDistance > 0 then
            local nextPosition = currentPosition + offset.Unit * stepDistance
            root.CFrame = CFrame.new(nextPosition) * targetCFrame.Rotation
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            lastExpectedPosition = nextPosition
        end
    end

    destroyMovementObjects()
    if movementHumanoid and movementHumanoid.Parent then
        pcall(function()
            movementHumanoid.PlatformStand = false
        end)
    end
    if movementToken == Hub.MovementToken then
        stopNoClip()
    end
    return reachedTarget and isFeatureActive(featureName, farmToken) and movementToken == Hub.MovementToken
end

local function startHoverAboveTarget(targetRoot, farmToken, secondTargetRoot, featureName)
    featureName = featureName or "FarmLevel"
    local character = getCharacter()
    local humanoid = getHumanoid()
    local playerRoot = getRoot()
    if not targetRoot or not targetRoot.Parent or not character or not humanoid or humanoid.Health <= 0 or not playerRoot then
        stopHover()
        return false
    end

    local hover = Hub.Hover
    if hover.TargetRoot == targetRoot and hover.SecondTargetRoot == secondTargetRoot
        and hover.Character == character and hover.Connection then
        return true
    end

    stopHover()
    disableCollisionForCharacter(character)
    local positionMover = Instance.new("BodyPosition")
    positionMover.Name = "MinhDZFarmHoverPosition"
    positionMover.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    positionMover.P = 18000
    positionMover.D = 1800
    positionMover.Position = targetRoot.Position + Vector3.new(0, Hub.Settings.AttackHeight, 0)
    positionMover.Parent = playerRoot

    local gyro = Instance.new("BodyGyro")
    gyro.Name = "MinhDZFarmHoverOrientation"
    gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    gyro.P = 15000
    gyro.D = 1400
    gyro.CFrame = CFrame.lookAt(playerRoot.Position, targetRoot.Position)
    gyro.Parent = playerRoot

    hover.Position = positionMover
    hover.Gyro = gyro
    hover.TargetRoot = targetRoot
    hover.SecondTargetRoot = secondTargetRoot
    hover.Character = character
    hover.Humanoid = humanoid
    hover.AutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false

    hover.Connection = RunService.Heartbeat:Connect(function()
        if not isFeatureActive(featureName, farmToken)
            or not targetRoot.Parent
            or not targetRoot:IsDescendantOf(workspace)
            or not positionMover.Parent
            or not gyro.Parent then
            stopHover()
            return
        end

        local liveCharacter = getCharacter()
        local liveRoot = getRoot()
        local liveHumanoid = getHumanoid()
        local targetHumanoid = targetRoot.Parent:FindFirstChildOfClass("Humanoid")
        if liveCharacter ~= character or not liveRoot or not liveHumanoid or liveHumanoid.Health <= 0
            or not targetHumanoid or targetHumanoid.Health <= 0 then
            stopHover()
            return
        end

        local targetPosition = targetRoot.Position
        if secondTargetRoot and secondTargetRoot.Parent and secondTargetRoot:IsDescendantOf(workspace) then
            local secondHumanoid = secondTargetRoot.Parent:FindFirstChildOfClass("Humanoid")
            if secondHumanoid and secondHumanoid.Health > 0 then
                targetPosition = (targetPosition + secondTargetRoot.Position) * 0.5
            end
        end
        local height = math.clamp(tonumber(Hub.Settings.AttackHeight) or 18, 8, 60)
        positionMover.Position = targetPosition + Vector3.new(0, height, 0)
        gyro.CFrame = CFrame.lookAt(liveRoot.Position, targetPosition)
    end)
    return true
end

--// Enemy helpers
local function findNearestQuestMob(mobName)
    local enemies = workspace:FindFirstChild("Enemies")
    local playerRoot = getRoot()
    if not enemies or not playerRoot then
        return nil
    end

    local closest, closestDistance = nil, math.huge
    for _, model in ipairs(enemies:GetChildren()) do
        if mobNamesMatch(model.Name, mobName) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            local ignoredUntil = Hub.UnresponsiveFarmTargets[model]
            if humanoid and root and humanoid.Health > 0
                and (not ignoredUntil or ignoredUntil <= os.clock()) then
                if ignoredUntil then
                    Hub.UnresponsiveFarmTargets[model] = nil
                end
                local distance = (root.Position - playerRoot.Position).Magnitude
                if distance < closestDistance then
                    closest = model
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

local function findMobSpawnCFrame(mobName)
    local spawnFolder = ReplicatedStorage:FindFirstChild("FortBuilderReplicatedSpawnPositionsFolder")
    if not spawnFolder then
        return nil
    end

    for _, spawnObject in ipairs(spawnFolder:GetChildren()) do
        local candidates = { spawnObject.Name, tostring(spawnObject) }
        if spawnObject:IsA("StringValue") then
            table.insert(candidates, spawnObject.Value)
        end
        for _, candidate in ipairs(candidates) do
            if mobNamesMatch(candidate, mobName) then
                local spawnCFrame = getObjectCFrame(spawnObject)
                if spawnCFrame then
                    return spawnCFrame
                end
            end
        end
    end
    return nil
end

--// Shared farm context + safe two-mob grouping controller.
-- This controller does not move NPCs or modify their physics. It maintains a
-- stable pair of same-quest targets; Farm Level hovers above their midpoint and
-- sends both through the normal hit-registration path when using Melee/Sword.
function Hub.SetFarmTarget(mobName, anchorPosition)
    if type(mobName) ~= "string" or mobName == "" then
        Hub.FarmTarget = nil
        return
    end
    Hub.FarmTarget = {
        Name = normalizeMobName(mobName),
        Anchor = typeof(anchorPosition) == "Vector3" and anchorPosition or nil,
        UpdatedAt = os.clock()
    }
end

function Hub.ClearFarmTarget()
    Hub.FarmTarget = nil
    Hub.FarmTargetWatch.Model = nil
    Hub.FarmTargetWatch.LastHealth = nil
    Hub.FarmTargetWatch.LastDamageAt = 0
    Hub.FarmTargetWatchers = setmetatable({}, { __mode = "k" })
    Hub.ActiveFarmPair = nil
end

local BRING_EXCLUDED_MOBS = {
    ["Ice Admiral"] = true,
    ["Awakened Ice Admiral"] = true,
    ["Saber Expert"] = true,
    ["The Gorilla King"] = true,
    Bobby = true,
    ["Mob Leader"] = true,
    ["Vice Admiral"] = true,
    Swan = true,
    ["Magma Admiral"] = true,
    ["Fishman Lord"] = true,
    Wysper = true,
    ["Thunder God"] = true,
    Cyborg = true,
    ["Don Swan"] = true,
    Greybeard = true,
    ["The Saw"] = true,
    Core = true,
    ["Cake Prince"] = true,
    ["Dough King"] = true
}

local function getEligibleFarmMob(model, mobName)
    if not model or not model.Parent or not model:IsDescendantOf(workspace)
        or not mobNamesMatch(model.Name, mobName) or BRING_EXCLUDED_MOBS[model.Name] then
        return nil, nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return nil, nil
    end
    local ignoredUntil = Hub.UnresponsiveFarmTargets[model]
    if ignoredUntil and ignoredUntil > os.clock() then
        return nil, nil
    elseif ignoredUntil then
        Hub.UnresponsiveFarmTargets[model] = nil
    end
    return humanoid, root
end

local function findNearestPartner(anchorModel, mobName, excludedModels)
    local _, anchorRoot = getEligibleFarmMob(anchorModel, mobName)
    local enemies = workspace:FindFirstChild("Enemies")
    if not anchorRoot or not enemies then
        return nil
    end
    local maxDistance = math.clamp(tonumber(Hub.Settings.BringPairRadius) or 300, 40, 300)
    local closest, closestDistance = nil, maxDistance
    for _, model in ipairs(enemies:GetChildren()) do
        if not (excludedModels and excludedModels[model]) then
            local _, root = getEligibleFarmMob(model, mobName)
            if root then
                local distance = (root.Position - anchorRoot.Position).Magnitude
                if distance < closestDistance then
                    closest = model
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

local function getFarmTargetPair(primaryTarget, mobName)
    if not primaryTarget then
        Hub.ActiveFarmPair = nil
        return {}
    end
    local normalizedName = normalizeMobName(mobName)
    local pairState = Hub.ActiveFarmPair
    local pair = {}
    if pairState and pairState.Name == normalizedName then
        for _, model in ipairs(pairState.Models or {}) do
            local humanoid = getEligibleFarmMob(model, mobName)
            if humanoid then
                table.insert(pair, model)
            end
        end
    end

    if #pair == 0 then
        local humanoid = getEligibleFarmMob(primaryTarget, mobName)
        if humanoid then
            table.insert(pair, primaryTarget)
        end
    end

    -- If an NPC walks out of the grouping radius, retain the first valid target
    -- and select a closer replacement instead of hovering between distant mobs.
    if #pair == 2 then
        local _, firstRoot = getEligibleFarmMob(pair[1], mobName)
        local _, secondRoot = getEligibleFarmMob(pair[2], mobName)
        local maxDistance = math.clamp(tonumber(Hub.Settings.BringPairRadius) or 300, 40, 300)
        if not firstRoot or not secondRoot
            or (firstRoot.Position - secondRoot.Position).Magnitude > maxDistance then
            pair = { pair[1] }
        end
    end

    if #pair == 1 then
        local excluded = { [pair[1]] = true }
        local partner = findNearestPartner(pair[1], mobName, excluded)
        if partner then
            table.insert(pair, partner)
        end
    end

    if #pair == 0 then
        Hub.ActiveFarmPair = nil
        return {}
    end

    -- Stable pair lock and stable anchor: keep the current farm point while
    -- at least one member survives. When the whole pair is defeated, establish
    -- a new anchor from the next nearest quest NPC.
    local pairHasSurvivor = false
    if pairState and pairState.Name == normalizedName then
        local activeSet = {}
        for _, activeModel in ipairs(pair) do
            activeSet[activeModel] = true
        end
        for _, previousModel in ipairs(pairState.Models or {}) do
            if activeSet[previousModel] then
                pairHasSurvivor = true
                break
            end
        end
    end
    local anchorPosition = pairHasSurvivor and pairState.AnchorPosition or nil
    if typeof(anchorPosition) ~= "Vector3" then
        local _, firstRoot = getEligibleFarmMob(pair[1], mobName)
        anchorPosition = firstRoot and firstRoot.Position or nil
    end
    Hub.ActiveFarmPair = {
        Name = normalizedName,
        Models = pair,
        AnchorPosition = anchorPosition,
        UpdatedAt = os.clock()
    }
    return pair
end

--// Farm-integrated Kaitun-style two-NPC grouping.
-- Kaitun's reference controller refreshes SimulationRadius, selects quest NPCs
-- inside an approximately 280-300 stud camp radius, then pins them to one anchor
-- with BodyPosition (P=20000, D=1250, MaxForce=1e6). This port limits the group
-- to two NPCs, applies the constraint at a throttled interval, and restores only
-- properties owned by MinhDZ. It never repeatedly teleports NPCs or writes zero
-- velocity every frame.
local BRING_POSITION_NAME = "MinhDZ_FarmingPosition_v513"
local BRING_BODY_POSITION_P = 20000
local BRING_BODY_POSITION_D = 1250
local BRING_MAX_FORCE = 1000000
local BRING_UPDATE_INTERVAL = 0.10
local BRING_OWNERSHIP_CHECK_INTERVAL = 0.75
local BRING_STALL_SECONDS = 3.0
local BRING_MAX_PLAYER_DISTANCE = 360
local BRING_GROUPED_DISTANCE = 12
local bringRetryAfter = setmetatable({}, { __mode = "k" })

local function getExecutorFunction(name)
    local sources = { ENV, _G }
    for _, source in ipairs(sources) do
        if type(source) == "table" then
            local candidate = rawget(source, name)
            if type(candidate) == "function" then
                return candidate
            end
        end
    end
    local getRuntimeEnv = rawget(_G, "getrenv")
    if type(getRuntimeEnv) == "function" then
        local ok, runtimeEnv = pcall(getRuntimeEnv)
        if ok and type(runtimeEnv) == "table" then
            local candidate = rawget(runtimeEnv, name)
            if type(candidate) == "function" then
                return candidate
            end
        end
    end
    return nil
end

local function refreshBringSimulationRadius()
    local now = os.clock()
    if now - (Hub.LastBringRadiusRefresh or 0) < 2 then
        return Hub.BringSimulationRadiusAvailable == true
    end
    Hub.LastBringRadiusRefresh = now

    local setter = getExecutorFunction("sethiddenproperty")
    if not setter then
        Hub.BringSimulationRadiusAvailable = false
        return false
    end

    local changed = false
    local okA = pcall(setter, LocalPlayer, "SimulationRadius", math.huge)
    local okB = pcall(setter, LocalPlayer, "MaxSimulationRadius", math.huge)
    changed = okA or okB
    Hub.BringSimulationRadiusAvailable = changed
    return changed
end

local function readNpcNetworkOwnership(root)
    local checker = getExecutorFunction("isnetworkowner")
    if not checker then
        return nil -- Older Kaitun pin loop did not require this optional API.
    end
    local ok, owned = pcall(checker, root)
    if not ok then
        return nil
    end
    return owned == true
end

local function captureBroughtMobState(model, humanoid, root)
    local record = Hub.BroughtMobs[model]
    if record then
        return record
    end

    record = {
        Mover = nil,
        Root = root,
        Humanoid = humanoid,
        OriginalHumanoid = {
            WalkSpeed = humanoid.WalkSpeed,
            JumpPower = humanoid.JumpPower,
            JumpHeight = humanoid.JumpHeight,
            UseJumpPower = humanoid.UseJumpPower,
            AutoRotate = humanoid.AutoRotate,
            PlatformStand = humanoid.PlatformStand
        },
        OriginalCollision = {},
        DescendantConnection = nil,
        LastDesiredPosition = nil,
        LastAppliedAt = 0,
        LastOwnershipCheck = 0,
        HasNetworkOwnership = nil,
        LastDistance = nil,
        LastProgressAt = os.clock(),
        InitialSnapDone = false
    }

    local function disablePartCollision(part)
        if part and part:IsA("BasePart") then
            if record.OriginalCollision[part] == nil then
                record.OriginalCollision[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        disablePartCollision(descendant)
    end
    record.DescendantConnection = model.DescendantAdded:Connect(disablePartCollision)

    -- Match Kaitun's low-physics setup, but keep the original values so they can
    -- be restored when the NPC leaves the pair or Farm Level is stopped.
    pcall(function()
        humanoid.PlatformStand = false
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.JumpHeight = 0
        humanoid.AutoRotate = false
    end)

    Hub.BroughtMobs[model] = record
    return record
end

local function ensureBringBodyPosition(root, record)
    local mover = record.Mover
    if not mover or mover.Parent ~= root then
        mover = root:FindFirstChild(BRING_POSITION_NAME)
        if mover and not mover:IsA("BodyPosition") then
            mover:Destroy()
            mover = nil
        end
        if not mover then
            mover = Instance.new("BodyPosition")
            mover.Name = BRING_POSITION_NAME
            mover.Parent = root
        end
        record.Mover = mover
    end

    mover.MaxForce = Vector3.new(BRING_MAX_FORCE, BRING_MAX_FORCE, BRING_MAX_FORCE)
    mover.P = BRING_BODY_POSITION_P
    mover.D = BRING_BODY_POSITION_D
    return mover
end

local restoreBroughtMob

local function applyKaitunBring(model, humanoid, root, anchorPosition, playerRoot)
    local existingRecord = model and Hub.BroughtMobs[model]
    if not model or not model.Parent or not humanoid or humanoid.Health <= 0
        or not root or not root.Parent or root.Anchored
        or typeof(anchorPosition) ~= "Vector3" then
        if existingRecord then
            restoreBroughtMob(model, existingRecord)
            Hub.BroughtMobs[model] = nil
        end
        return false, "invalid or anchored NPC"
    end

    if playerRoot and (root.Position - playerRoot.Position).Magnitude > BRING_MAX_PLAYER_DISTANCE then
        if existingRecord then
            restoreBroughtMob(model, existingRecord)
            Hub.BroughtMobs[model] = nil
        end
        return false, "NPC is outside the 360-stud player radius"
    end

    local now = os.clock()
    local retryUntil = bringRetryAfter[model]
    if retryUntil and retryUntil > now and not Hub.BroughtMobs[model] then
        return false, "NPC pull cooling down after server correction"
    elseif retryUntil then
        bringRetryAfter[model] = nil
    end

    local record = Hub.BroughtMobs[model]
    if not record then
        record = captureBroughtMobState(model, humanoid, root)
    end

    if now - (record.LastOwnershipCheck or 0) >= BRING_OWNERSHIP_CHECK_INTERVAL then
        refreshBringSimulationRadius()
        record.HasNetworkOwnership = readNpcNetworkOwnership(root)
        record.LastOwnershipCheck = now
    end

    local mover = ensureBringBodyPosition(root, record)
    local distance = (root.Position - anchorPosition).Magnitude

    -- Kaitun's pin loop teleports only when the NPC is still visibly separated
    -- from the camp anchor. Do this once per NPC and only when ownership is
    -- confirmed; otherwise let BodyPosition attempt a gradual pull.
    if not record.InitialSnapDone and distance > 6 and record.HasNetworkOwnership == true then
        local ok = pcall(function()
            root.CFrame = CFrame.new(anchorPosition) * root.CFrame.Rotation
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        record.InitialSnapDone = ok
    elseif distance <= 6 then
        record.InitialSnapDone = true
    end

    if now - (record.LastAppliedAt or 0) >= BRING_UPDATE_INTERVAL
        and (not record.LastDesiredPosition
            or (record.LastDesiredPosition - anchorPosition).Magnitude > 0.35
            or (mover.Position - anchorPosition).Magnitude > 0.35) then
        mover.Position = anchorPosition
        record.LastDesiredPosition = anchorPosition
        record.LastAppliedAt = now
    end

    local currentDistance = (root.Position - anchorPosition).Magnitude
    if record.LastDistance == nil or currentDistance < record.LastDistance - 0.20 then
        record.LastProgressAt = now
    elseif currentDistance <= BRING_GROUPED_DISTANCE then
        record.LastProgressAt = now
    end
    record.LastDistance = currentDistance

    if currentDistance > BRING_GROUPED_DISTANCE
        and now - (record.LastProgressAt or now) >= BRING_STALL_SECONDS then
        restoreBroughtMob(model, record)
        Hub.BroughtMobs[model] = nil
        bringRetryAfter[model] = now + 4
        Hub.BringControlStatus = "server corrected NPC position; pin paused to prevent lag"
        return false, Hub.BringControlStatus
    end

    return currentDistance <= BRING_GROUPED_DISTANCE,
        currentDistance <= BRING_GROUPED_DISTANCE and "2 NPCs grouped" or "pinning NPC to shared anchor"
end

restoreBroughtMob = function(model, record)
    if not record then
        return
    end

    if record.DescendantConnection then
        pcall(function() record.DescendantConnection:Disconnect() end)
        record.DescendantConnection = nil
    end

    local mover = record.Mover
    if mover and mover.Parent == record.Root and mover.Name == BRING_POSITION_NAME then
        pcall(function() mover:Destroy() end)
    end

    local humanoid = record.Humanoid
    local original = record.OriginalHumanoid
    if humanoid and humanoid.Parent and original then
        pcall(function()
            humanoid.WalkSpeed = original.WalkSpeed
            humanoid.UseJumpPower = original.UseJumpPower
            humanoid.JumpPower = original.JumpPower
            humanoid.JumpHeight = original.JumpHeight
            humanoid.AutoRotate = original.AutoRotate
            humanoid.PlatformStand = original.PlatformStand
        end)
    end

    for part, canCollide in pairs(record.OriginalCollision or {}) do
        if part and part.Parent then
            pcall(function() part.CanCollide = canCollide end)
        end
    end
end

local function restoreAllBroughtMobs()
    for model, record in pairs(Hub.BroughtMobs) do
        restoreBroughtMob(model, record)
        Hub.BroughtMobs[model] = nil
    end
    Hub.ActiveFarmPair = nil
    Hub.BringControlStatus = "not active"
end

local function restoreBroughtMobsOutsidePair(activeModels)
    for model, record in pairs(Hub.BroughtMobs) do
        if not activeModels[model] then
            restoreBroughtMob(model, record)
            Hub.BroughtMobs[model] = nil
        end
    end
end

local function bringFarmMobPair(pair)
    local activeModels = {}
    for _, model in ipairs(pair or {}) do
        activeModels[model] = true
    end
    restoreBroughtMobsOutsidePair(activeModels)

    if not pair or #pair == 0 then
        Hub.BringControlStatus = "waiting for quest NPC"
        return {}, Hub.BringControlStatus, false
    end
    if #pair < 2 then
        Hub.BringControlStatus = "looking for a second quest NPC inside 300 studs"
        return pair, Hub.BringControlStatus, false
    end

    local playerRoot = getRoot()
    local anchorHumanoid, anchorRoot = getEligibleFarmMob(pair[1], pair[1].Name)
    local secondHumanoid, secondRoot = getEligibleFarmMob(pair[2], pair[2].Name)
    if not anchorHumanoid or not anchorRoot then
        return { pair[2] }, "primary NPC is no longer valid", false
    end
    if not secondHumanoid or not secondRoot then
        return { pair[1] }, "second NPC is no longer valid", false
    end

    -- Both NPCs are pinned to the same anchor, as in Kaitun's BringConnV6.
    -- The primary is already at the anchor; the secondary is pulled into it.
    local anchorPosition = anchorRoot.Position
    local firstGrouped, firstStatus = applyKaitunBring(pair[1], anchorHumanoid, anchorRoot, anchorPosition, playerRoot)
    local secondGrouped, secondStatus = applyKaitunBring(pair[2], secondHumanoid, secondRoot, anchorPosition, playerRoot)
    local grouped = firstGrouped and secondGrouped

    if grouped then
        Hub.BringControlStatus = "2 NPCs grouped at shared anchor"
    elseif secondStatus and secondStatus:find("server corrected", 1, true) then
        Hub.BringControlStatus = secondStatus
    elseif secondStatus and secondStatus:find("outside", 1, true) then
        Hub.BringControlStatus = secondStatus
    else
        Hub.BringControlStatus = secondStatus or firstStatus or "pinning two NPCs to shared anchor"
    end

    return { pair[1], pair[2] }, Hub.BringControlStatus, grouped
end

--// Weapon helpers: lock the selected category and re-equip it if another tool is selected.
local VALID_WEAPON_CATEGORIES = { "Melee", "Sword", "Gun", "Blox Fruit" }

local function getToolCategory(tool)
    if not tool or not tool:IsA("Tool") then
        return nil
    end
    if tool.Name == "Combat" then
        return "Melee"
    end
    local tip = tostring(tool.ToolTip or "")
    for _, category in ipairs(VALID_WEAPON_CATEGORIES) do
        if tip == category then
            return category
        end
    end
    return nil
end

local function findToolForCategory(category)
    local character = getCharacter()
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if getToolCategory(tool) == category then
                return tool, true
            end
        end
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if getToolCategory(tool) == category and tool.Name ~= "Tool" then
                return tool, false
            end
        end
    end
    return nil, false
end

local function equipSelectedWeapon()
    local category = Hub.Settings.WeaponCategory
    if not table.find(VALID_WEAPON_CATEGORIES, category) then
        category = "Melee"
        Hub.Settings.WeaponCategory = category
    end

    local tool, alreadyEquipped = findToolForCategory(category)
    if alreadyEquipped then
        return tool
    end
    if not tool then
        return nil
    end

    local humanoid = getHumanoid()
    if not humanoid or humanoid.Health <= 0 then
        return nil
    end
    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)
    if not ok then
        return nil
    end
    return tool
end

local function hasBuso(character)
    character = character or getCharacter()
    -- Kaitun checks the HasBuso marker under Character. Keep the Player tag as
    -- a second authoritative indicator for game versions that expose it there.
    if character and character:FindFirstChild("HasBuso") then
        return true
    end
    local ok, result = pcall(function()
        return LocalPlayer:HasTag("Buso")
    end)
    return ok and result == true
end

--// Combat: melee/sword use the source hit pipeline; guns activate their Tool;
-- Blox Fruit uses the selected fruit skill key (same VirtualInputManager pattern as KaitunBF).
local LastAttackAt = 0
local LastFruitSkillAt = 0
local function pressFruitSkill()
    local skillName = tostring(Hub.Settings.FruitSkill or "Z")
    local validSkills = { Z = true, X = true, C = true, V = true }
    if not validSkills[skillName] then
        skillName = "Z"
    end
    local keyCode = Enum.KeyCode[skillName]
    if not keyCode then
        return false
    end

    local ok, err = pcall(function()
        local inputManager = game:GetService("VirtualInputManager")
        inputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.12)
        inputManager:SendKeyEvent(false, keyCode, false, game)
    end)
    if not ok then
        warn("[MinhDZ Hub] Fruit skill input unavailable: " .. tostring(err))
    end
    return ok
end

local function attackNearbyQuestMobs(primaryTarget, mobName, selectedTool, lockedTargets)
    local category = Hub.Settings.WeaponCategory
    local interval = Hub.Settings.AttackInterval
    if category == "Blox Fruit" then
        interval = math.max(0.8, interval)
        if os.clock() - LastFruitSkillAt < interval then
            return
        end
        if not selectedTool then
            return
        end
        LastFruitSkillAt = os.clock()
        pressFruitSkill()
        return
    elseif category == "Gun" then
        interval = math.max(0.35, interval)
        if os.clock() - LastAttackAt < interval then
            return
        end
        if not selectedTool then
            return
        end
        LastAttackAt = os.clock()
        local ok, err = pcall(function()
            selectedTool:Activate()
        end)
        if not ok then
            warn("[MinhDZ Hub] Gun activation failed: " .. tostring(err))
        end
        return
    end

    if os.clock() - LastAttackAt < interval then
        return
    end

    local playerRoot = getRoot()
    local enemies = workspace:FindFirstChild("Enemies")
    if not playerRoot or not enemies then
        return
    end

    local hitTargets = {}
    local hitPart = nil
    local seenTargets = {}
    local function addHitTarget(model)
        if not model or seenTargets[model] or #hitTargets >= 2 then
            return
        end
        seenTargets[model] = true
        local humanoid, root = getEligibleFarmMob(model, mobName)
        if humanoid and root and (root.Position - playerRoot.Position).Magnitude <= 65 then
            local candidatePart = model:FindFirstChild("Head") or model.PrimaryPart or root
            hitPart = hitPart or candidatePart
            table.insert(hitTargets, { model, root })
        end
    end

    -- Attack only the two NPCs in the active pair. Do not sweep unrelated mobs
    -- in Workspace order; that was the source of inconsistent target selection.
    addHitTarget(primaryTarget)
    for _, model in ipairs(lockedTargets or {}) do
        if #hitTargets >= 2 then
            break
        end
        if model ~= primaryTarget then
            addHitTarget(model)
        end
    end

    if #hitTargets == 0 or not hitPart then
        return
    end

    LastAttackAt = os.clock()
    local ok, err = pcall(function()
        RegisterAttack:FireServer(0.16, 1)
        local global = getGlobalModule()
        if global and type(global.SendHitsToServer) == "function" then
            global.SendHitsToServer(hitPart, hitTargets)
        else
            RegisterHit:FireServer(hitPart, hitTargets)
        end
    end)
    if not ok then
        warn("[MinhDZ Hub] Attack remote error: " .. tostring(err))
    end
end

--// Per-NPC health watchdog. Each member of a two-mob group has its own timer,
-- so alternating health updates cannot accidentally reset the other NPC's timer.
local FARM_TARGET_STALL_SECONDS = 14
local FARM_TARGET_RETRY_SECONDS = 10
local function watchFarmTargetHealth(model, humanoid)
    if not model then
        return false
    end
    if not humanoid or humanoid.Health <= 0 then
        Hub.FarmTargetWatchers[model] = nil
        return false
    end

    local now = os.clock()
    local health = humanoid.Health
    local watch = Hub.FarmTargetWatchers[model]
    if not watch then
        Hub.FarmTargetWatchers[model] = { LastHealth = health, LastDamageAt = now }
        return false
    end

    if health < watch.LastHealth - 0.01 then
        watch.LastHealth = health
        watch.LastDamageAt = now
        return false
    elseif health > watch.LastHealth + 0.01 then
        -- Regeneration is not progress; update the comparison baseline only.
        watch.LastHealth = health
    end

    if now - watch.LastDamageAt >= FARM_TARGET_STALL_SECONDS then
        Hub.UnresponsiveFarmTargets[model] = now + FARM_TARGET_RETRY_SECONDS
        Hub.FarmTargetWatchers[model] = nil
        if Hub.ActiveFarmPair then
            local remaining = {}
            for _, activeModel in ipairs(Hub.ActiveFarmPair.Models or {}) do
                if activeModel ~= model then
                    table.insert(remaining, activeModel)
                end
            end
            Hub.ActiveFarmPair.Models = remaining
        end
        setStatus("Farm Level | NPC not taking damage; skipping that NPC and refreshing the 2-mob group")
        return true
    end
    return false
end

--// Farm Level feature step
local function farmLevelStep(token)
    if not isFeatureActive("FarmLevel", token) then
        return
    end

    local level = getPlayerLevel()
    if not level then
        restoreAllBroughtMobs()
        Hub.ClearFarmTarget()
        stopHover()
        setStatus("Waiting for player level data...")
        task.wait(1)
        return
    end

    local sea = getSeaIndex()
    local quest, questError = selectQuestForLevel(level, sea)
    if not quest then
        restoreAllBroughtMobs()
        Hub.ClearFarmTarget()
        stopHover()
        setStatus(questError)
        task.wait(2)
        return
    end

    local activeMob, activeTitle, activeProgress, activeMaximum = readActiveQuest()
    local hasProgress = (tonumber(activeProgress) or 0) > 0
    if activeMob and not mobNamesMatch(activeMob, quest.MobName) and not hasProgress then
        Hub.MismatchCount = Hub.MismatchCount + 1
        if Hub.MismatchCount >= 3 then
            setStatus("Different quest detected; abandoning it before level farm...")
            pcall(function()
                CommF:InvokeServer("AbandonQuest")
            end)
            Hub.MismatchCount = 0
            Hub.LastFarmQuestStart = os.clock()
            task.wait(0.8)
        end
        return
    end

    if not activeMob then
        restoreAllBroughtMobs()
        Hub.ClearFarmTarget()
        stopHover()
        Hub.MismatchCount = 0
        if os.clock() - Hub.LastFarmQuestStart < 3 then
            return
        end

        local questGiver = getQuestGiverCFrame(quest.LevelReq)
        if questGiver then
            local root = getRoot()
            if root and (root.Position - questGiver.Position).Magnitude > 14 then
                setStatus(string.format("Travelling to quest giver | %s | Lv. %d", tostring(quest.QuestId), quest.LevelReq))
                moveTo(questGiver * CFrame.new(0, 4, 4), token)
                return
            end
        end

        if not isFeatureActive("FarmLevel", token) then
            return
        end

        setStatus(string.format("Accepting quest | %s | %s", tostring(quest.QuestId), quest.MobName))
        Hub.LastFarmQuestStart = os.clock()
        local ok, result = pcall(function()
            return CommF:InvokeServer("StartQuest", quest.QuestId, quest.StageId)
        end)
        if not ok then
            setStatus("StartQuest failed: " .. tostring(result))
        end
        task.wait(0.8)
        return
    end

    Hub.MismatchCount = 0
    local farmMobName = (activeMob and hasProgress) and activeMob or quest.MobName
    local target = findNearestQuestMob(farmMobName)
    if not target then
        restoreAllBroughtMobs()
        stopHover()
        local spawnCFrame = findMobSpawnCFrame(farmMobName)
        if spawnCFrame then
            Hub.SetFarmTarget(farmMobName, spawnCFrame.Position)
            local root = getRoot()
            if root and (root.Position - spawnCFrame.Position).Magnitude > 25 then
                setStatus("Searching mob spawn | " .. farmMobName)
                moveTo(spawnCFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token)
                return
            end
        else
            Hub.ClearFarmTarget()
        end
        setStatus("Waiting for mob spawn | " .. farmMobName)
        task.wait(1)
        return
    end

    local farmTargets = getFarmTargetPair(target, farmMobName)
    if #farmTargets == 0 then
        Hub.ActiveFarmPair = nil
        task.wait(0.1)
        return
    end

    target = farmTargets[1]
    local targetHumanoid, targetRoot = getEligibleFarmMob(target, farmMobName)
    local playerRoot = getRoot()
    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 or not playerRoot then
        Hub.ActiveFarmPair = nil
        return
    end

    -- Actual Bring Mob runs before selecting the hover point and attack list.
    -- Both selected same-quest NPCs are pinned to one shared camp anchor; the
    -- attack pipeline retains both targets while the secondary moves inward.
    local farmAttackTargets, bringStatus, pairGrouped = bringFarmMobPair(farmTargets)
    local secondRoot = nil
    local pairCenter = targetRoot.Position
    if pairGrouped and #farmAttackTargets > 1 then
        local _, candidateRoot = getEligibleFarmMob(farmAttackTargets[2], farmMobName)
        if candidateRoot then
            secondRoot = candidateRoot
            pairCenter = (targetRoot.Position + candidateRoot.Position) * 0.5
        end
    end

    local attackPosition = pairCenter + Vector3.new(0, Hub.Settings.AttackHeight, 0)
    local attackCFrame = CFrame.lookAt(attackPosition, pairCenter)
    local distance = (playerRoot.Position - attackPosition).Magnitude
    Hub.SetFarmTarget(farmMobName, pairCenter)

    if distance > 18 then
        stopHover()
        local groupedText = secondRoot and "2-mob group" or ("single mob | " .. tostring(bringStatus))
        setStatus(string.format("Farm Level | %s | flying to %s", farmMobName, groupedText))
        moveTo(attackCFrame, token)
        return
    end

    if not startHoverAboveTarget(targetRoot, token, secondRoot) then
        return
    end

    if (playerRoot.Position - attackPosition).Magnitude > 7 then
        setStatus(string.format("Farm Level | %s | stabilizing group hover", farmMobName))
        task.wait(0.08)
        return
    end

    local selectedTool = equipSelectedWeapon()
    if not selectedTool then
        setStatus("Selected weapon not found: " .. tostring(Hub.Settings.WeaponCategory) .. ". Check Backpack tools.")
        task.wait(1)
        return
    end

    local stalledTarget = false
    for _, model in ipairs(farmAttackTargets) do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local mobRoot = model:FindFirstChild("HumanoidRootPart")
        -- Only start the no-damage watchdog for NPCs that are currently inside
        -- the actual hit pipeline range. A distant partner must not be marked
        -- unresponsive merely because it has not reached the player yet.
        if humanoid and mobRoot and (mobRoot.Position - playerRoot.Position).Magnitude <= 65 then
            if watchFarmTargetHealth(model, humanoid) then
                stalledTarget = true
            end
        end
    end
    if stalledTarget then
        task.wait(0.12)
        return
    end

    local activeCount = 0
    for _, model in ipairs(farmAttackTargets) do
        local _, candidateRoot = getEligibleFarmMob(model, farmMobName)
        if candidateRoot and (candidateRoot.Position - playerRoot.Position).Magnitude <= 65 then
            activeCount = activeCount + 1
        end
    end
    local bringSuffix
    if pairGrouped then
        bringSuffix = " | Bring Mob: grouped 2"
    elseif activeCount == 2 then
        bringSuffix = " | Bring Mob: 2 targets in range; " .. tostring(bringStatus)
    else
        bringSuffix = " | Bring Mob: " .. tostring(bringStatus)
    end
    setStatus(string.format("Farm Level | %s | %d target(s) | %s%s | Lv. %d",
        farmMobName, activeCount, selectedTool.Name, bringSuffix, level))
    attackNearbyQuestMobs(target, farmMobName, selectedTool, farmAttackTargets)
    task.wait(0.06)
end

--// Independent special farms. These workers do not modify Farm Level's quest,
-- two-mob grouping, damage watchdog, or Bring Mob ownership controller.
local BONE_ENEMY_NAMES = {
    "Reborn Skeleton",
    "Living Zombie",
    "Demonic Soul",
    "Posessed Mummy",
    "Possessed Mummy"
}
local CAKE_ENEMY_NAMES = {
    "Cookie Crafter",
    "Cake Guard",
    "Baking Staff",
    "Head Baker"
}
local ELITE_ENEMY_NAMES = { "Diablo", "Deandre", "Urban" }
local BONE_CAMP_CFRAME = CFrame.new(-9506.234375, 172.130615234375, 6117.0771484375)
local CAKE_CAMP_CFRAME = CFrame.new(-2130.80712890625, 69.95634460449219, -12327.83984375)

local function hasInventoryItem(itemName)
    local character = getCharacter()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    return (character and character:FindFirstChild(itemName) ~= nil)
        or (backpack and backpack:FindFirstChild(itemName) ~= nil)
end

local function enemyNameMatchesAny(modelName, names, allowBossSuffix)
    local normalized = normalizeMobName(modelName):lower()
    for _, expectedName in ipairs(names) do
        local expected = expectedName:lower()
        if normalized == expected then
            return true
        end
        if allowBossSuffix and normalized:sub(1, #expected + 1) == expected .. " " then
            return true
        end
    end
    return false
end

local function findNearestNamedEnemy(folder, names, allowBossSuffix)
    if not folder then return nil end
    local playerRoot = getRoot()
    local best, bestDistance
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and enemyNameMatchesAny(model.Name, names, allowBossSuffix) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then
                local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                if not best or distance < bestDistance then
                    best, bestDistance = model, distance
                end
            end
        end
    end
    return best
end

local function getQuestTitleText()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = playerGui and playerGui:FindFirstChild("Main")
    local questFrame = main and main:FindFirstChild("Quest")
    local container = questFrame and questFrame:FindFirstChild("Container")
    local titleFolder = container and container:FindFirstChild("QuestTitle")
    local title = titleFolder and titleFolder:FindFirstChild("Title")
    return questFrame and questFrame.Visible == true, title and title.Text or ""
end

local function attackSingleSpecialEnemy(model, selectedTool)
    local category = Hub.Settings.WeaponCategory
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    local root = model and model:FindFirstChild("HumanoidRootPart")
    local playerRoot = getRoot()
    if not humanoid or humanoid.Health <= 0 or not root or not playerRoot
        or (root.Position - playerRoot.Position).Magnitude > 65 then
        return
    end

    if category == "Blox Fruit" then
        local interval = math.max(0.8, Hub.Settings.AttackInterval)
        if os.clock() - LastFruitSkillAt >= interval and selectedTool then
            LastFruitSkillAt = os.clock()
            pressFruitSkill()
        end
        return
    elseif category == "Gun" then
        local interval = math.max(0.35, Hub.Settings.AttackInterval)
        if os.clock() - LastAttackAt >= interval and selectedTool then
            LastAttackAt = os.clock()
            pcall(function() selectedTool:Activate() end)
        end
        return
    end

    if os.clock() - LastAttackAt < Hub.Settings.AttackInterval then
        return
    end
    local hitPart = model:FindFirstChild("Head") or model.PrimaryPart or root
    if not hitPart then return end
    LastAttackAt = os.clock()
    local hitTargets = { { model, root } }
    local ok, err = pcall(function()
        RegisterAttack:FireServer(0.16, 1)
        local global = getGlobalModule()
        if global and type(global.SendHitsToServer) == "function" then
            global.SendHitsToServer(hitPart, hitTargets)
        else
            RegisterHit:FireServer(hitPart, hitTargets)
        end
    end)
    if not ok then
        warn("[MinhDZ Hub] Special farm attack error: " .. tostring(err))
    end
end

local function fightSpecialEnemy(model, token, modeLabel)
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
    local playerRoot = getRoot()
    if not humanoid or humanoid.Health <= 0 or not targetRoot or not playerRoot then
        stopHover()
        return
    end

    local targetPosition = targetRoot.Position + Vector3.new(0, Hub.Settings.AttackHeight, 0)
    local distance = (playerRoot.Position - targetPosition).Magnitude
    if distance > 18 then
        stopHover()
        setStatus(string.format("%s | travelling to %s | %.0f studs", modeLabel, model.Name, distance))
        moveTo(CFrame.lookAt(targetPosition, targetRoot.Position), token, "SpecialFarm")
        return
    end

    if not startHoverAboveTarget(targetRoot, token, nil, "SpecialFarm") then
        return
    end
    local selectedTool = equipSelectedWeapon()
    if not selectedTool then
        setStatus(modeLabel .. " | selected weapon not found: " .. tostring(Hub.Settings.WeaponCategory))
        task.wait(0.8)
        return
    end
    if humanoid.Health > 0 then
        setStatus(string.format("%s | attacking %s | HP %.0f", modeLabel, model.Name, humanoid.Health))
        attackSingleSpecialEnemy(model, selectedTool)
    end
end

local function requestCakePortalIfReady(modeLabel)
    if os.clock() - Hub.LastCakeSpawnerCall < 4 then
        return nil
    end
    Hub.LastCakeSpawnerCall = os.clock()
    local ok, result = pcall(function()
        return CommF:InvokeServer("CakePrinceSpawner")
    end)
    if not ok then
        setStatus(modeLabel .. " | CakePrinceSpawner request failed: " .. tostring(result))
        return nil
    end

    local message = tostring(result or "")
    if message:find("Do you want to open the portal now?", 1, true) then
        local openOk, openResult = pcall(function()
            return CommF:InvokeServer("CakePrinceSpawner")
        end)
        if openOk then
            setStatus(modeLabel .. " | portal request sent; waiting for boss spawn")
        else
            setStatus(modeLabel .. " | portal request failed: " .. tostring(openResult))
        end
    elseif message:find("%d+%s*/%s*500") then
        setStatus(modeLabel .. " | " .. message)
    end
    return message
end

local function findBossOrSpawn(names)
    local enemies = workspace:FindFirstChild("Enemies")
    local live = findNearestNamedEnemy(enemies, names, true)
    if live then return live, true end
    local replicated = findNearestNamedEnemy(ReplicatedStorage, names, true)
    if replicated then return replicated, false end
    return nil, false
end

local function farmCakeMobs(token, modeLabel)
    local enemies = workspace:FindFirstChild("Enemies")
    local target = findNearestNamedEnemy(enemies, CAKE_ENEMY_NAMES, false)
    if target then
        fightSpecialEnemy(target, token, modeLabel .. " | Cake Island mobs")
        return true
    end

    local replicated = findNearestNamedEnemy(ReplicatedStorage, CAKE_ENEMY_NAMES, false)
    if replicated then
        local targetRoot = replicated:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            stopHover()
            setStatus(modeLabel .. " | waiting for cake mob: " .. replicated.Name)
            moveTo(targetRoot.CFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token, "SpecialFarm")
            return true
        end
    end

    stopHover()
    local root = getRoot()
    if root and (root.Position - CAKE_CAMP_CFRAME.Position).Magnitude > 18 then
        setStatus(modeLabel .. " | searching Cake Island mobs")
        moveTo(CAKE_CAMP_CFRAME, token, "SpecialFarm")
    else
        setStatus(modeLabel .. " | waiting for Cake Island mobs / boss spawn")
        task.wait(1)
    end
    return false
end

local function doughKingPrerequisiteStep(token)
    -- Reuse the source script's prerequisite order conservatively: process an
    -- existing Red Key with Cake Scientist, request Elite Hunter when no quest
    -- is active, and only open the cake portal when Sweet Chalice is present.
    local hasSweetChalice = hasInventoryItem("Sweet Chalice")
    local hasGodsChalice = hasInventoryItem("God's Chalice")
    local hasRedKey = hasInventoryItem("Red Key")

    if hasGodsChalice and not hasSweetChalice then
        if os.clock() - Hub.LastDoughNpcCall >= 5 then
            Hub.LastDoughNpcCall = os.clock()
            local ok, response = pcall(function()
                return CommF:InvokeServer("SweetChaliceNpc")
            end)
            if ok and type(response) == "string" and response:find("Where", 1, true) then
                pcall(function() CommF:InvokeServer("SweetChaliceNpc") end)
                setStatus("Farm Dough King | Sweet Chalice NPC interaction requested")
            elseif not ok then
                setStatus("Farm Dough King | Sweet Chalice NPC unavailable: " .. tostring(response))
            else
                setStatus("Farm Dough King | God's Chalice found; check Sweet Chalice NPC requirements")
            end
        end
        return true
    end

    if hasSweetChalice then
        requestCakePortalIfReady("Farm Dough King")
        return farmCakeMobs(token, "Farm Dough King")
    end

    if hasRedKey then
        if os.clock() - Hub.LastDoughNpcCall >= 5 then
            Hub.LastDoughNpcCall = os.clock()
            local ok, result = pcall(function()
                return CommF:InvokeServer("CakeScientist", "Check")
            end)
            if ok then
                setStatus("Farm Dough King | Red Key checked with Cake Scientist")
            else
                setStatus("Farm Dough King | Cake Scientist check failed: " .. tostring(result))
            end
        end
        task.wait(0.5)
        return true
    end

    local questVisible, questTitle = getQuestTitleText()
    local eliteName = nil
    for _, name in ipairs(ELITE_ENEMY_NAMES) do
        if questTitle:find(name, 1, true) then
            eliteName = name
            break
        end
    end

    if eliteName then
        local enemies = workspace:FindFirstChild("Enemies")
        local target = findNearestNamedEnemy(enemies, { eliteName }, false)
        if target then
            fightSpecialEnemy(target, token, "Farm Dough King | Elite Hunter")
            return true
        end
        local replicated = findNearestNamedEnemy(ReplicatedStorage, { eliteName }, false)
        local replicatedRoot = replicated and replicated:FindFirstChild("HumanoidRootPart")
        if replicatedRoot then
            stopHover()
            setStatus("Farm Dough King | waiting for Elite target " .. eliteName)
            moveTo(replicatedRoot.CFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token, "SpecialFarm")
            return true
        end
        setStatus("Farm Dough King | Elite Hunter target not spawned: " .. eliteName)
        task.wait(1)
        return true
    end

    if not questVisible and os.clock() - Hub.LastEliteHunterCall >= 8 then
        Hub.LastEliteHunterCall = os.clock()
        local ok, result = pcall(function()
            return CommF:InvokeServer("EliteHunter")
        end)
        if not ok then
            setStatus("Farm Dough King | Elite Hunter request failed: " .. tostring(result))
        else
            setStatus("Farm Dough King | Elite Hunter quest requested; waiting for Red Key / Sweet Chalice")
        end
    else
        setStatus("Farm Dough King | needs God's Chalice / Sweet Chalice or an Elite Hunter Red Key")
        task.wait(1)
    end
    return true
end

local function specialFarmStep(token)
    if not isFeatureActive("SpecialFarm", token) then return end
    local mode = Hub.Settings.SelectedFarmMode
    if mode == "Farm Level" then
        setStatus("Select a special farm type or use Farm Level")
        task.wait(0.5)
        return
    end
    if getSeaIndex() ~= 3 then
        stopHover()
        setStatus(mode .. " | available in Third Sea only")
        task.wait(2)
        return
    end

    local character = getCharacter()
    local humanoid = getHumanoid()
    if not character or not humanoid or humanoid.Health <= 0 or not getRoot() then
        stopHover()
        setStatus(mode .. " | waiting for character")
        task.wait(1)
        return
    end

    if mode == "Farm Bone" then
        local enemies = workspace:FindFirstChild("Enemies")
        local target = findNearestNamedEnemy(enemies, BONE_ENEMY_NAMES, false)
        if target then
            fightSpecialEnemy(target, token, "Farm Bone")
            return
        end
        local replicated = findNearestNamedEnemy(ReplicatedStorage, BONE_ENEMY_NAMES, false)
        local replicatedRoot = replicated and replicated:FindFirstChild("HumanoidRootPart")
        if replicatedRoot then
            stopHover()
            setStatus("Farm Bone | waiting for " .. replicated.Name)
            moveTo(replicatedRoot.CFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token, "SpecialFarm")
            return
        end
        local root = getRoot()
        if root and (root.Position - BONE_CAMP_CFRAME.Position).Magnitude > 18 then
            stopHover()
            setStatus("Farm Bone | travelling to Haunted Castle")
            moveTo(BONE_CAMP_CFRAME, token, "SpecialFarm")
        else
            setStatus("Farm Bone | searching for Reborn Skeleton / Living Zombie / Demonic Soul / Possessed Mummy")
            task.wait(1)
        end
        return
    end

    if mode == "Farm Cake Prince" then
        local boss, isLive = findBossOrSpawn({ "Cake Prince" })
        if boss and isLive then
            fightSpecialEnemy(boss, token, "Farm Cake Prince | boss")
            return
        elseif boss and not isLive then
            local bossRoot = boss:FindFirstChild("HumanoidRootPart")
            if bossRoot then
                stopHover()
                setStatus("Farm Cake Prince | boss is queued; moving to spawn")
                moveTo(bossRoot.CFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token, "SpecialFarm")
                return
            end
        end
        requestCakePortalIfReady("Farm Cake Prince")
        farmCakeMobs(token, "Farm Cake Prince")
        return
    end

    if mode == "Farm Dough King" then
        local boss, isLive = findBossOrSpawn({ "Dough King" })
        if boss and isLive then
            fightSpecialEnemy(boss, token, "Farm Dough King | boss")
            return
        elseif boss and not isLive then
            local bossRoot = boss:FindFirstChild("HumanoidRootPart")
            if bossRoot then
                stopHover()
                setStatus("Farm Dough King | boss is queued; moving to spawn")
                moveTo(bossRoot.CFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token, "SpecialFarm")
                return
            end
        end
        doughKingPrerequisiteStep(token)
        return
    end

    stopHover()
    setStatus("Unknown farm mode: " .. tostring(mode))
    task.wait(1)
end

-- Forward declaration is shared by Auto Chest's completion path and shop workers.
local stopFeature

--// Auto Chest: find active chest instances and travel to their touch parts.
local function getChestPart(instance)
    if not instance or not instance.Parent then return nil end
    if instance:IsA("BasePart") then return instance end
    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return instance:FindFirstChildWhichIsA("BasePart", true)
end

local chestScanCache = { At = 0, Part = nil, Distance = nil }
local chestCooldowns = setmetatable({}, { __mode = "k" })

local function findNearestChest()
    local now = os.clock()
    local cachedPart = chestScanCache.Part
    if now - chestScanCache.At < 0.8 and cachedPart
        and cachedPart:IsDescendantOf(workspace)
        and (chestCooldowns[cachedPart] or 0) <= now then
        return cachedPart, chestScanCache.Distance
    end
    chestScanCache.At = now
    chestScanCache.Part = nil
    chestScanCache.Distance = nil

    local root = getRoot()
    if not root then return nil end
    local best, bestDistance
    for _, item in ipairs(workspace:GetDescendants()) do
        if item.Name:lower():match("^chest%d*$") then
            local part = getChestPart(item)
            if part and part:IsDescendantOf(workspace)
                and (chestCooldowns[part] or 0) <= now then
                local distance = (part.Position - root.Position).Magnitude
                if not bestDistance or distance < bestDistance then
                    best, bestDistance = part, distance
                end
            end
        end
    end
    chestScanCache.Part, chestScanCache.Distance = best, bestDistance
    return best, bestDistance
end

local function setAutoChestToggleOff()
    local option = Fluent.Options.AutoChest
    if option and type(option.SetValue) == "function" then
        pcall(function() option:SetValue(false) end)
    end
end

local function finishAutoChestAtLimit()
    local targetCount = math.clamp(math.floor(tonumber(Hub.Settings.ChestTargetCount) or 5), 1, 50)
    stopFeature("AutoChest")
    Hub.ChestPending = nil
    setAutoChestToggleOff()
    setStatus(string.format("Auto Chest | target reached: %d/%d", Hub.ChestCollectedCount, targetCount))
    notify("Auto Chest", string.format("Collected %d/%d chests. Auto Chest stopped.", Hub.ChestCollectedCount, targetCount), 6)
end

local function autoChestStep(token)
    if not isFeatureActive("AutoChest", token) then return end

    local heldSpecialItem = getHeldSpecialChestItem()
    if heldSpecialItem then
        if Hub.ChestPausedItem ~= heldSpecialItem then
            Hub.ChestPausedItem = heldSpecialItem
            stopMovement()
            notify("Auto Chest paused", heldSpecialItem .. " detected. Chest collection will resume after it is no longer held.", 6)
        end
        setStatus("Auto Chest | paused: holding " .. heldSpecialItem)
        task.wait(1)
        return
    elseif Hub.ChestPausedItem then
        local previousItem = Hub.ChestPausedItem
        Hub.ChestPausedItem = nil
        chestScanCache.At = 0
        notify("Auto Chest resumed", previousItem .. " is no longer held. Continuing chest collection.", 4)
    end

    local targetCount = math.clamp(math.floor(tonumber(Hub.Settings.ChestTargetCount) or 5), 1, 50)
    if Hub.ChestCollectedCount >= targetCount then
        finishAutoChestAtLimit()
        return
    end

    -- Count only when the chest instance disappears after a close-range touch.
    -- If it remains, apply a short retry cooldown rather than counting a false pickup.
    local pending = Hub.ChestPending
    if pending then
        if not pending.Part or not pending.Part:IsDescendantOf(workspace) then
            Hub.ChestCollectedCount = math.min(Hub.ChestCollectedCount + 1, targetCount)
            Hub.ChestPending = nil
            chestScanCache.At = 0
            setStatus(string.format("Auto Chest | collected %d/%d", Hub.ChestCollectedCount, targetCount))
            if Hub.ChestCollectedCount >= targetCount then
                finishAutoChestAtLimit()
                return
            end
        elseif os.clock() >= pending.VerifyAt then
            chestCooldowns[pending.Part] = os.clock() + 8
            Hub.ChestPending = nil
            chestScanCache.At = 0
            setStatus(string.format("Auto Chest | pickup not confirmed | %d/%d", Hub.ChestCollectedCount, targetCount))
            task.wait(0.4)
            return
        else
            task.wait(0.2)
            return
        end
    end

    local character = getCharacter()
    local humanoid = getHumanoid()
    local root = getRoot()
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        setStatus("Auto Chest | waiting for character")
        task.wait(1)
        return
    end

    local chest, distance = findNearestChest()
    if not chest then
        setStatus(string.format("Auto Chest | searching | %d/%d", Hub.ChestCollectedCount, targetCount))
        task.wait(1.5)
        return
    end

    if distance and distance > 7 then
        setStatus(string.format("Auto Chest | flying to chest | %d/%d", Hub.ChestCollectedCount, targetCount))
        moveTo(CFrame.new(chest.Position + Vector3.new(0, 2.5, 0)), token, "AutoChest")
    else
        setStatus(string.format("Auto Chest | collecting | %d/%d", Hub.ChestCollectedCount, targetCount))
        Hub.ChestPending = { Part = chest, VerifyAt = os.clock() + 2.2 }
        task.wait(0.25)
    end
end

--// Auto Berry: visit every active BerryBush marker in this server. It does not hop.
local berryRetryAfter = setmetatable({}, { __mode = "k" })

local function resolveBerryBush(tag)
    if not tag or not tag.Parent then return nil end
    local parent = tag.Parent
    local attributes = tag:GetAttributes()
    local berryName, targetPart

    for attributeName, attributeValue in pairs(attributes) do
        if attributeValue ~= nil then
            local candidateName = tostring(attributeValue)
            local candidate = parent:FindFirstChild(candidateName, true)
            if candidate then
                local part = candidate:IsA("BasePart") and candidate or candidate:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    berryName = candidateName
                    targetPart = part
                    break
                end
            end
            if not berryName then
                berryName = tostring(attributeName)
            end
        end
    end

    if not targetPart then
        if tag:IsA("BasePart") then
            targetPart = tag
        elseif parent:IsA("Model") then
            targetPart = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
        elseif parent:IsA("BasePart") then
            targetPart = parent
        end
    end
    if not targetPart or not targetPart:IsDescendantOf(workspace) then return nil end
    return targetPart, berryName or tag.Name
end

local function findNearestBerry()
    local root = getRoot()
    if not root then return nil end
    local bestTag, bestPart, bestName, bestDistance
    for _, tag in ipairs(CollectionService:GetTagged("BerryBush")) do
        if tag and tag.Parent and (berryRetryAfter[tag] or 0) <= os.clock() then
            local attributes = tag:GetAttributes()
            if next(attributes) ~= nil then
                local part, berryName = resolveBerryBush(tag)
                if part then
                    local distance = (part.Position - root.Position).Magnitude
                    if not bestDistance or distance < bestDistance then
                        bestTag, bestPart, bestName, bestDistance = tag, part, berryName, distance
                    end
                end
            end
        end
    end
    return bestTag, bestPart, bestName, bestDistance
end

local function autoBerryStep(token)
    if not isFeatureActive("AutoBerry", token) then return end
    local character = getCharacter()
    local humanoid = getHumanoid()
    local root = getRoot()
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        setStatus("Auto Berry | waiting for character")
        task.wait(1)
        return
    end

    local tag, part, berryName, distance = findNearestBerry()
    if not tag or not part then
        setStatus("Auto Berry | waiting berry")
        if not Hub.BerryWaitingNotified then
            Hub.BerryWaitingNotified = true
            notify("Auto Berry", "Waiting berry — no active berries remain in this server.", 6)
        end
        task.wait(2)
        return
    end

    Hub.BerryWaitingNotified = false
    setStatus("Auto Berry | collecting " .. tostring(berryName))
    if distance and distance > 5 then
        moveTo(CFrame.new(part.Position + Vector3.new(0, 2, 0)), token, "AutoBerry")
    else
        task.wait(0.45)
    end

    if tag and tag.Parent then
        local currentAttributes = tag:GetAttributes()
        if next(currentAttributes) ~= nil then
            berryRetryAfter[tag] = os.clock() + 3
        else
            berryRetryAfter[tag] = nil
        end
    end
    task.wait(0.25)
end

--// Lightweight local ESP objects; all generated instances are owned and cleaned by this hub.
local ESP_GUI_PREFIX = "MinhDZ_ESP_"
local espPlayerRecords = {}
local espBerryRecords = setmetatable({}, { __mode = "k" })
local espIslandRecords = setmetatable({}, { __mode = "k" })

local function destroyESPRecord(record)
    if not record then return end
    for _, object in ipairs({ record.Billboard, record.Highlight }) do
        if object and object.Parent then
            pcall(function() object:Destroy() end)
        end
    end
end

local function makeESPBillboard(part, name, text, color, offsetY)
    if not part or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return nil end
    local billboard = part:FindFirstChild(name)
    if not billboard or not billboard:IsA("BillboardGui") then
        billboard = Instance.new("BillboardGui")
        billboard.Name = name
        billboard.Adornee = part
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.Size = UDim2.fromOffset(190, 44)
        billboard.StudsOffset = Vector3.new(0, offsetY or 2.5, 0)
        billboard.Parent = part
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.TextWrapped = true
        label.TextStrokeTransparency = 0.35
        label.TextColor3 = color
        label.Parent = billboard
    end
    local label = billboard:FindFirstChild("Label")
    if label and label:IsA("TextLabel") then
        label.Text = text
        label.TextColor3 = color
    end
    return billboard
end

local function makeESPHighlight(character, name, fillColor, outlineColor)
    if not character or not character:IsA("Model") then return nil end
    local highlight = character:FindFirstChild(name)
    if not highlight or not highlight:IsA("Highlight") then
        highlight = Instance.new("Highlight")
        highlight.Name = name
        highlight.Adornee = character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = character
    end
    highlight.FillColor = fillColor
    highlight.OutlineColor = outlineColor
    highlight.FillTransparency = 0.78
    highlight.OutlineTransparency = 0.08
    return highlight
end

local function clearESPRecordTable(records)
    for key, record in pairs(records) do
        destroyESPRecord(record)
        records[key] = nil
    end
end

local function updatePlayersESP()
    local seen = {}
    local localRoot = getRoot()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
            if character and humanoid and humanoid.Health > 0 and head and head:IsA("BasePart") then
                seen[player] = true
                local record = espPlayerRecords[player]
                if record and record.Character ~= character then
                    destroyESPRecord(record)
                    record = nil
                end
                local distance = localRoot and math.floor((localRoot.Position - head.Position).Magnitude + 0.5) or 0
                local healthPercent = humanoid.MaxHealth > 0 and math.floor((humanoid.Health / humanoid.MaxHealth) * 100 + 0.5) or 0
                local isEnemy = player.Team ~= LocalPlayer.Team
                local color = isEnemy and Color3.fromRGB(235, 115, 115) or Color3.fromRGB(115, 190, 245)
                local billboard = makeESPBillboard(head, ESP_GUI_PREFIX .. "Player", string.format("%s (@%s)\n%d studs | HP %d%%", player.DisplayName, player.Name, distance, healthPercent), color, 2.5)
                local highlight = makeESPHighlight(character, ESP_GUI_PREFIX .. "PlayerHighlight", color, color)
                espPlayerRecords[player] = { Character = character, Billboard = billboard, Highlight = highlight }
            end
        end
    end
    for player, record in pairs(espPlayerRecords) do
        if not seen[player] then
            destroyESPRecord(record)
            espPlayerRecords[player] = nil
        end
    end
end

local function updateBerryESP()
    local seen = {}
    local localRoot = getRoot()
    for _, tag in ipairs(CollectionService:GetTagged("BerryBush")) do
        if tag and tag.Parent and next(tag:GetAttributes()) ~= nil then
            local part, berryName = resolveBerryBush(tag)
            if part then
                seen[tag] = true
                local distance = localRoot and math.floor((localRoot.Position - part.Position).Magnitude + 0.5) or 0
                local billboard = makeESPBillboard(part, ESP_GUI_PREFIX .. "Berry", string.format("Berry: %s\n%d studs", tostring(berryName), distance), Color3.fromRGB(140, 225, 160), 2)
                local record = espBerryRecords[tag]
                if record and record.Part ~= part then destroyESPRecord(record); record = nil end
                espBerryRecords[tag] = { Part = part, Billboard = billboard }
            end
        end
    end
    for tag, record in pairs(espBerryRecords) do
        if not seen[tag] then
            destroyESPRecord(record)
            espBerryRecords[tag] = nil
        end
    end
end

local function updateIslandESP()
    local locations = workspace:FindFirstChild("_WorldOrigin")
    locations = locations and locations:FindFirstChild("Locations")
    local seen = {}
    local localRoot = getRoot()
    if locations then
        for _, location in ipairs(locations:GetChildren()) do
            if location.Name ~= "Sea" then
                local part = location:IsA("BasePart") and location or getChestPart(location)
                if part and part:IsDescendantOf(workspace) then
                    seen[location] = true
                    local distance = localRoot and math.floor((localRoot.Position - part.Position).Magnitude + 0.5) or 0
                    local billboard = makeESPBillboard(part, ESP_GUI_PREFIX .. "Island", string.format("%s\n%d studs", location.Name, distance), Color3.fromRGB(130, 205, 235), 3)
                    local record = espIslandRecords[location]
                    if record and record.Part ~= part then destroyESPRecord(record); record = nil end
                    espIslandRecords[location] = { Part = part, Billboard = billboard }
                end
            end
        end
    end
    for location, record in pairs(espIslandRecords) do
        if not seen[location] then
            destroyESPRecord(record)
            espIslandRecords[location] = nil
        end
    end
end

local function espPlayersStep()
    updatePlayersESP()
    task.wait(0.7)
end

local function espBerryStep()
    updateBerryESP()
    task.wait(0.8)
end

local function espIslandsStep()
    updateIslandESP()
    task.wait(1.5)
end

local function clearAllESP()
    clearESPRecordTable(espPlayerRecords)
    clearESPRecordTable(espBerryRecords)
    clearESPRecordTable(espIslandRecords)
end

--// Auto Equip Selected Weapon is a separate utility feature.
local function autoEquipMeleeStep()
    if os.clock() - Hub.LastEquipCheck < 0.75 then
        return
    end
    Hub.LastEquipCheck = os.clock()
    local tool = equipSelectedWeapon()
    if not tool then
        setStatus("Auto Equip Selected Weapon: no " .. tostring(Hub.Settings.WeaponCategory) .. " tool found")
    else
        setStatus("Auto Equip Selected Weapon: " .. tool.Name)
    end
end

--// Auto Buso follows Kaitun's character-spawn behavior: wait for the character,
-- check Character.HasBuso first, then invoke the toggle remote once only if absent.
-- Never poll the toggle remote: repeated calls can turn Buso back OFF.
local function autoBusoStep()
    local character = getCharacter()
    if not character then
        Hub.BusoCharacter = nil
        Hub.BusoAttemptedCharacter = nil
        return
    end

    if Hub.BusoCharacter ~= character then
        Hub.BusoCharacter = character
        Hub.BusoCharacterReadyAt = os.clock()
        Hub.BusoAttemptedCharacter = nil
    end

    if hasBuso(character) then
        Hub.BusoAttemptedCharacter = character
        setStatus("Auto Buso: active")
        return
    end

    -- One attempt per spawned character. The 3-second delay mirrors the
    -- supplied Kaitun startup activation while allowing Character data to load.
    if Hub.BusoAttemptedCharacter == character then
        return
    end
    if os.clock() - Hub.BusoCharacterReadyAt < 3 then
        return
    end
    if not character:FindFirstChildOfClass("Humanoid") or not character:FindFirstChild("HumanoidRootPart") then
        return
    end

    -- Mark before invoking so even an ambiguous remote response cannot cause
    -- a second toggle on this same character.
    Hub.BusoAttemptedCharacter = character
    local ok, result = pcall(function()
        return CommF:InvokeServer("Buso")
    end)
    if not ok then
        warn("[MinhDZ Hub] Auto Buso activation error: " .. tostring(result))
        setStatus("Auto Buso activation error: " .. tostring(result))
    else
        setStatus("Auto Buso activation sent; waiting for HasBuso")
    end
end

--// Auto Stats follows Banana Hub's AutomateStats + AutoStats concept, but uses
--// exactly one selected target at a time. Changing the dropdown is the only way
--// to redirect future points; no second stat can be selected concurrently.
local AUTO_STAT_REMOTE_NAMES = {
    ["Melee"] = "Melee",
    ["Sword"] = "Sword",
    ["Gun"] = "Gun",
    ["Blox Fruit"] = "Demon Fruit"
}
local MAX_STAT_POINTS_PER_REQUEST = 100

local function pauseAutoStats(reason)
    local feature = Hub.Features.AutoStats
    local option = Fluent.Options.AutoStats
    if option then
        pcall(function() option:SetValue(false) end)
    end
    if feature.Enabled then
        feature.Enabled = false
        feature.Token = feature.Token + 1
    end
    notify("MinhDZ Hub", "Auto Stats paused: " .. tostring(reason), 6)
end

local function getAvailableStatPoints()
    local data = LocalPlayer:FindFirstChild("Data")
    local points = data and data:FindFirstChild("Points")
    return points and math.max(0, math.floor(tonumber(points.Value) or 0)) or nil
end

local function autoStatsStep()
    if os.clock() - Hub.LastStatAllocation < 0.45 then
        return
    end

    local selectedCategory = Hub.Settings.AutoStatCategory
    local remoteStat = AUTO_STAT_REMOTE_NAMES[selectedCategory]
    if not remoteStat then
        setStatus("Auto Stats: choose Melee, Sword, Gun or Blox Fruit")
        return
    end

    local availablePoints = getAvailableStatPoints()
    if availablePoints == nil then
        setStatus("Auto Stats: player stat data is not ready")
        return
    end
    if availablePoints < 1 then
        Hub.AutoStatFailureCount = 0
        setStatus("Auto Stats: waiting for points | target " .. selectedCategory)
        return
    end

    local amount = math.min(availablePoints, MAX_STAT_POINTS_PER_REQUEST)
    local pointsBefore = availablePoints
    Hub.LastStatAllocation = os.clock()

    local ok, result = pcall(function()
        return CommF:InvokeServer("AddPoint", remoteStat, amount)
    end)
    if not ok then
        Hub.AutoStatFailureCount = Hub.AutoStatFailureCount + 1
        setStatus("Auto Stats request error: " .. tostring(result))
        if Hub.AutoStatFailureCount >= 4 then
            pauseAutoStats("the server remote failed repeatedly. Check connection and try again.")
        end
        return
    end

    -- Give replicated Data.Points a moment to reflect the server response.
    task.wait(0.2)
    local pointsAfter = getAvailableStatPoints()
    if pointsAfter ~= nil and pointsAfter < pointsBefore then
        local spent = pointsBefore - pointsAfter
        Hub.AutoStatFailureCount = 0
        setStatus(string.format("Auto Stats: +%d %s | %d points left", spent, selectedCategory, pointsAfter))
    else
        Hub.AutoStatFailureCount = Hub.AutoStatFailureCount + 1
        setStatus(string.format("Auto Stats: server did not spend points on %s (response: %s)", selectedCategory, tostring(result)))
        if Hub.AutoStatFailureCount >= 4 then
            -- Stop instead of hammering the remote if the selected stat is capped
            -- or the server rejects the request. The user can choose another stat.
            pauseAutoStats("the server rejected repeated point allocations. Choose another stat or inspect your points.")
        end
    end
end

--// Auto Sea Travel: keeps the unlock checks visible and conservative.
local function getServerMeleeMastery(styleName)
    local highest = 0
    pcall(function()
        local itemServiceModule = ReplicatedStorage:FindFirstChild("ItemReplicationService")
        local itemConfigModule = ReplicatedStorage:FindFirstChild("ItemConfig")
        if not itemServiceModule or not itemConfigModule then
            return
        end

        local itemService = require(itemServiceModule)
        local itemConfig = require(itemConfigModule)
        local userCache = itemService._UserCache and itemService._UserCache[LocalPlayer.UserId]
        local masteryItems = userCache and userCache:GetItems("Mastery")
        if type(masteryItems) ~= "table" then
            return
        end

        local wanted = tostring(styleName):lower():gsub("[^%w]", "")
        for _, entry in pairs(masteryItems) do
            if entry and entry.ItemId then
                local ok, item = pcall(function()
                    return itemConfig.match(entry.ItemId):unwrap()
                end)
                local debugLabel = ok and item and item.Index and item.Index.DebugLabel
                if debugLabel then
                    local label = tostring(debugLabel):lower():gsub("[^%w]", "")
                    local matches = label == wanted or (wanted == "dragonclaw" and label == "dragonbreath")
                    if matches then
                        highest = math.max(highest, tonumber(entry.Value) or 0)
                    end
                end
            end
        end
    end)
    return highest
end

local function findDragonClawMastery()
    local mastery = getServerMeleeMastery("Dragon Claw")
    local owned = mastery > 0
    local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }
    for _, container in ipairs(containers) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and (tool.Name:lower():find("dragon claw", 1, true) or tool.Name:lower():find("dragon breath", 1, true)) then
                    owned = true
                    local masteryValue = tool:FindFirstChild("Level", true)
                    mastery = math.max(mastery, masteryValue and tonumber(masteryValue.Value) or 0)
                end
            end
        end
    end
    return mastery, owned
end

local function autoSeaTravelStep(token)
    if not isFeatureActive("AutoSeaTravel", token) then
        return
    end
    local level = getPlayerLevel()
    if not level then
        return
    end

    local sea = getSeaIndex()
    if sea == 1 and level < 700 then
        setStatus("Auto Sea Travel: Sea 1 requires level 700")
        return
    elseif sea == 2 and level < 1500 then
        setStatus("Auto Sea Travel: Sea 2 requires level 1500")
        return
    elseif sea >= 3 then
        setStatus("Auto Sea Travel: already in Sea 3")
        return
    end

    if os.clock() - Hub.LastSeaCheck < 10 then
        return
    end
    Hub.LastSeaCheck = os.clock()
    if os.clock() - Hub.LastSeaTravel < 60 then
        return
    end

    if sea == 1 and level >= 700 then
        Hub.LastSeaTravel = os.clock()
        setStatus("Checking Second Sea access...")
        pcall(function()
            CommF:InvokeServer("DressrosaQuestProgress", "Detective")
        end)
        task.wait(1)
        if not isFeatureActive("AutoSeaTravel", token) then
            return
        end
        local ok, result = pcall(function()
            return CommF:InvokeServer("TravelDressrosa")
        end)
        if ok then
            notify("MinhDZ Hub", "Second Sea travel request sent. Server unlock requirements still apply.", 5)
            setStatus("Second Sea travel requested | " .. tostring(result))
        else
            setStatus("Second Sea travel failed: " .. tostring(result))
        end
        return
    end

    if sea == 2 and level >= 1500 then
        local mastery, hasDragonClaw = findDragonClawMastery()
        if not hasDragonClaw or mastery < 400 then
            setStatus("Third Sea: Dragon Claw mastery 400 is still required by the source logic")
            return
        end

        local phoeyuDoorExists = false
        pcall(function()
            local map = workspace:FindFirstChild("Map")
            local iceCastle = map and map:FindFirstChild("IceCastle")
            local hall = iceCastle and iceCastle:FindFirstChild("Hall")
            local libraryDoor = hall and hall:FindFirstChild("LibraryDoor")
            phoeyuDoorExists = libraryDoor and libraryDoor:FindFirstChild("PhoeyuDoor") ~= nil
        end)

        if not phoeyuDoorExists then
            if not isFeatureActive("AutoSeaTravel", token) then
                return
            end
            Hub.LastSeaTravel = os.clock()
            setStatus("Checking Third Sea access...")
            local ok, result = pcall(function()
                return CommF:InvokeServer("TravelZou")
            end)
            if ok then
                notify("MinhDZ Hub", "Third Sea travel request sent. Server unlock requirements still apply.", 5)
                setStatus("Third Sea travel requested | " .. tostring(result))
            else
                setStatus("Third Sea travel failed: " .. tostring(result))
            end
        end
    end
end

--// Shop navigation. This locates vendor NPCs in the active server and travels
-- to them; purchases are completed through the game's normal NPC dialogue/UI.
-- No shop purchase remote is invoked from a distance and no server checks are bypassed.
local SHOP_VENDOR_ALIASES = {
    ["Blox Fruit Dealer"] = { "Blox Fruit Dealer" },
    ["Advanced Fruit Dealer"] = { "Advanced Fruit Dealer" },
    ["Melee / Fighting Style Teacher"] = {
        "Dark Step Teacher", "Water Kung Fu Teacher", "Mad Scientist", "Sabi",
        "Martial Arts Master", "Phoeyu, the Reformed", "Sharkman Teacher",
        "Previous Hero", "Uzoth", "Ancient Monk", "Shafi"
    },
    ["Haki / Ability Teacher"] = { "Ability Teacher" },
    ["Sword Dealer"] = { "Sword Dealer", "Sword Dealer of the East", "Sword Dealer of the West" },
    ["Master Sword Dealer"] = { "Master Sword Dealer" },
    ["Legendary Sword Dealer"] = { "Legendary Sword Dealer" },
    ["Weapon Dealer"] = { "Weapon Dealer" },
    ["Advanced Weapon Dealer"] = { "Advanced Weapon Dealer" }
}

local SHOP_VENDOR_OPTIONS = {
    "Blox Fruit Dealer",
    "Advanced Fruit Dealer",
    "Melee / Fighting Style Teacher",
    "Haki / Ability Teacher",
    "Sword Dealer",
    "Master Sword Dealer",
    "Legendary Sword Dealer",
    "Weapon Dealer",
    "Advanced Weapon Dealer"
}

local function normalizeShopName(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function findShopVendor(selection)
    local aliases = SHOP_VENDOR_ALIASES[selection]
    if not aliases then
        return nil, nil
    end

    local wanted = {}
    for _, alias in ipairs(aliases) do
        wanted[normalizeShopName(alias)] = alias
    end

    local playerRoot = getRoot()
    local closestModel, closestRoot, closestAlias, closestDistance
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") and instance ~= getCharacter() then
            local humanoid = instance:FindFirstChildOfClass("Humanoid")
            local root = instance:FindFirstChild("HumanoidRootPart") or instance.PrimaryPart
            if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
                local modelName = normalizeShopName(instance.Name)
                local displayName = normalizeShopName(instance:GetAttribute("DisplayName"))
                local alias = wanted[modelName] or wanted[displayName]
                if alias then
                    local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                    if not closestDistance or distance < closestDistance then
                        closestModel, closestRoot, closestAlias, closestDistance = instance, root, alias, distance
                    end
                end
            end
        end
    end
    return closestModel, closestRoot, closestAlias
end

local function tryOpenVendorPrompt(vendorModel, vendorRoot)
    if not vendorModel or not vendorModel.Parent then
        return false
    end

    local playerRoot = getRoot()
    if not playerRoot then
        return false
    end

    for _, descendant in ipairs(vendorModel:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant.Enabled then
            local promptParent = descendant.Parent
            local promptPart
            if promptParent and promptParent:IsA("Attachment") then
                promptPart = promptParent.Parent
            elseif promptParent and promptParent:IsA("BasePart") then
                promptPart = promptParent
            elseif promptParent then
                promptPart = promptParent:FindFirstAncestorWhichIsA("BasePart")
            end

            local promptPosition = promptPart and promptPart.Position or vendorRoot.Position
            local distance = (playerRoot.Position - promptPosition).Magnitude
            local activationDistance = tonumber(descendant.MaxActivationDistance) or 0
            local keyCode = descendant.KeyboardKeyCode

            -- Only synthesize the prompt's normal key after the player is already
            -- within the prompt's configured range. No direct prompt/remote firing.
            if activationDistance > 0 and distance <= activationDistance
                and keyCode and keyCode ~= Enum.KeyCode.Unknown then
                local ok = pcall(function()
                    local inputManager = game:GetService("VirtualInputManager")
                    local holdDuration = math.clamp(tonumber(descendant.HoldDuration) or 0, 0, 3)
                    inputManager:SendKeyEvent(true, keyCode, false, game)
                    task.wait(math.max(0.08, holdDuration + 0.05))
                    inputManager:SendKeyEvent(false, keyCode, false, game)
                end)
                if ok then
                    return true
                end
            end
        end
    end
    return false
end

local function shopTravelStep(token)
    if not isFeatureActive("ShopTravel", token) then
        return
    end

    local selection = Hub.Settings.ShopVendor
    local vendor, vendorRoot, matchedAlias = findShopVendor(selection)
    if not vendor or not vendorRoot then
        setStatus("Shop | " .. tostring(selection) .. " is not present in this server/sea")
        notify("Shop Navigator", "Vendor not found in the current server. This vendor may be in another sea or unavailable now.", 6)
        stopFeature("ShopTravel")
        return
    end

    local playerRoot = getRoot()
    if not playerRoot then
        setStatus("Shop | waiting for character")
        task.wait(0.5)
        return
    end

    local distance = (playerRoot.Position - vendorRoot.Position).Magnitude
    if distance > 11 then
        local approachPosition = vendorRoot.Position + vendorRoot.CFrame.RightVector * 5 + Vector3.new(0, 2, 0)
        setStatus(string.format("Shop | travelling to %s | %.0f studs", matchedAlias, distance))
        moveTo(CFrame.lookAt(approachPosition, vendorRoot.Position), token, "ShopTravel")
        return
    end

    stopMovement()
    local promptSent = tryOpenVendorPrompt(vendor, vendorRoot)
    if promptSent then
        setStatus("Shop | arrived at " .. matchedAlias .. " | normal in-range interaction key sent")
        notify("Shop Navigator", "Reached " .. matchedAlias .. " and sent its normal in-range prompt key. Complete/confirm the shop dialogue if it appears.", 7)
    else
        setStatus("Shop | arrived at " .. matchedAlias .. " | use the NPC's normal prompt/dialogue")
        notify("Shop Navigator", "Reached " .. matchedAlias .. ". No usable in-range prompt key was found; interact with the NPC normally.", 7)
    end
    stopFeature("ShopTravel")
end

--// Independent Auto Click worker; this is separate from attack registration and
-- can be tuned without enabling or changing Farm Level.
local function autoClickWorker(token)
    local virtualUser = game:GetService("VirtualUser")
    while isFeatureActive("AutoClick", token) do
        local cps = math.clamp(tonumber(Hub.Settings.ClicksPerSecond) or 20, 1, 30)
        local interval = 1 / cps
        local camera = workspace.CurrentCamera
        if camera then
            local viewport = camera.ViewportSize
            local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
            local downOk = pcall(function()
                virtualUser:CaptureController()
                virtualUser:Button1Down(center, camera.CFrame)
            end)
            local holdTime = math.min(0.02, interval * 0.35)
            if downOk then
                task.wait(holdTime)
                pcall(function()
                    virtualUser:Button1Up(center, camera.CFrame)
                end)
            end
            task.wait(math.max(0.005, interval - holdTime))
        else
            task.wait(0.05)
        end
    end
    local camera = workspace.CurrentCamera
    if camera then
        local viewport = camera.ViewportSize
        pcall(function()
            virtualUser:Button1Up(Vector2.new(viewport.X * 0.5, viewport.Y * 0.5), camera.CFrame)
        end)
    end
end

--// Independent feature runner
local function startFeature(name, worker)
    local feature = Hub.Features[name]
    if not feature or feature.Enabled then
        return
    end

    feature.Enabled = true
    feature.Token = feature.Token + 1
    local token = feature.Token

    task.spawn(function()
        while isFeatureActive(name, token) do
            local ok, err = pcall(worker, token)
            if not ok then
                warn("[MinhDZ Hub] " .. name .. " error: " .. tostring(err))
                setStatus(name .. " error: " .. tostring(err))
                task.wait(1)
            else
                task.wait(0.12)
            end
        end
    end)

    notify("MinhDZ Hub", name .. " enabled", 3)
end

stopFeature = function(name)
    local feature = Hub.Features[name]
    if not feature or not feature.Enabled then
        return
    end

    feature.Enabled = false
    feature.Token = feature.Token + 1
    if name == "FarmLevel" or name == "SpecialFarm" or name == "AutoChest" or name == "AutoBerry" or name == "ShopTravel" then
        stopMovement()
    end
    if name == "AutoChest" then
        Hub.ChestPending = nil
        Hub.ChestPausedItem = nil
        chestScanCache.At = 0
    elseif name == "AutoBerry" then
        Hub.BerryWaitingNotified = false
    elseif name == "ESPPlayers" then
        clearESPRecordTable(espPlayerRecords)
    elseif name == "ESPBerry" then
        clearESPRecordTable(espBerryRecords)
    elseif name == "ESPIslands" then
        clearESPRecordTable(espIslandRecords)
    end
    if name == "SpecialFarm" then
        stopHover()
        setStatus("Special farm stopped; movement and hover cancelled")
    end
    if name == "FarmLevel" then
        -- Farm Level owns Bring Mob directly; restore any still-living NPCs it moved.
        stopHover()
        restoreAllBroughtMobs()
        Hub.ClearFarmTarget()
        Hub.MismatchCount = 0
        setStatus("Farm Level stopped; movement and hover cancelled")
    end
    notify("MinhDZ Hub", name .. " disabled", 3)
end

local function setFeature(name, enabled, worker)
    if enabled then
        startFeature(name, worker)
    else
        stopFeature(name)
    end
end

--// Unified Farm toggle. Turning the same switch ON starts the selected mode;
-- turning it OFF stops the active Farm Level or special-farm worker.
Tabs.Farming:AddParagraph({
    Title = "Minhdz hub (beta) by dev Minh",
    Content = "Chọn kiểu farm bằng mũi tên, sau đó bật công tắc Farm. Tắt chính công tắc này để dừng. Farm Level giữ nguyên worker và hệ thống Bring Mob hai mục tiêu."
})

local FarmToggle

local function stopActiveFarmModes()
    if Hub.Features.FarmLevel.Enabled then
        stopFeature("FarmLevel")
    end
    if Hub.Features.SpecialFarm.Enabled then
        stopFeature("SpecialFarm")
    end
    stopMovement()
    stopHover()
end

Tabs.Farming:AddDropdown("SelectedFarmMode", {
    Title = "Select Farm Type",
    Description = "Level / Bone / Cake Prince / Dough King",
    Values = { "Farm Level", "Farm Bone", "Farm Cake Prince", "Farm Dough King" },
    Default = Hub.Settings.SelectedFarmMode,
    Callback = function(value)
        if table.find({ "Farm Level", "Farm Bone", "Farm Cake Prince", "Farm Dough King" }, value) then
            if Hub.Features.FarmLevel.Enabled or Hub.Features.SpecialFarm.Enabled then
                if FarmToggle then
                    FarmToggle:SetValue(false)
                else
                    stopActiveFarmModes()
                end
            end
            Hub.Settings.SelectedFarmMode = value
            setStatus("Selected: " .. value)
        end
    end
})

FarmToggle = Tabs.Farming:AddToggle("Farm", {
    Title = "Farm",
    Description = "",
    Default = false,
    Callback = function(value)
        if value then
            stopActiveFarmModes()
            local mode = Hub.Settings.SelectedFarmMode
            if mode == "Farm Level" then
                startFeature("FarmLevel", farmLevelStep)
            else
                startFeature("SpecialFarm", specialFarmStep)
            end
            setStatus("Farm ON | " .. mode)
        else
            stopActiveFarmModes()
            setStatus("Farm OFF")
        end
    end
})

local BoneCountParagraph = Tabs.Farming:AddParagraph({
    Title = "Bone Counter",
    Content = "Bone count: loading..."
})

task.spawn(function()
    while not Hub.Unloading do
        if getSeaIndex() == 3 then
            local ok, count = pcall(function()
                return CommF:InvokeServer("Bones", "Check")
            end)
            if ok then
                BoneCountParagraph:SetDesc("You have: " .. tostring(count) .. " Bones")
            else
                BoneCountParagraph:SetDesc("Bone count unavailable in this server")
            end
        else
            BoneCountParagraph:SetDesc("Bone counter is available in Third Sea")
        end
        task.wait(8)
    end
end)

Tabs.FarmOther:AddParagraph({
    Title = "Auto Chest",
    Content = "Collects the selected number of chests. Pauses while Fist of Darkness, God's Chalice, Sweet Chalice or Red Key is held, then resumes after it is gone."
})

local ChestProgressParagraph = Tabs.FarmOther:AddParagraph({
    Title = "Chest Progress",
    Content = "Collected: 0/5"
})

task.spawn(function()
    while not Hub.Unloading do
        local target = math.clamp(math.floor(tonumber(Hub.Settings.ChestTargetCount) or 5), 1, 50)
        ChestProgressParagraph:SetDesc(string.format("Collected: %d/%d%s",
            Hub.ChestCollectedCount, target,
            Hub.ChestPausedItem and (" | Paused: " .. Hub.ChestPausedItem) or ""))
        task.wait(1)
    end
end)

Tabs.FarmOther:AddTextBox("ChestTargetCount", {
    Title = "Chest Amount",
    Description = "Enter 1-50. Auto Chest stops after this many confirmed pickups.",
    Default = "5",
    PlaceholderText = "5 default | 1-50",
    Callback = function(value)
        local amount = tonumber(value)
        if not amount or amount % 1 ~= 0 then
            setStatus("Chest amount must be a whole number from 1 to 50")
            notify("Auto Chest", "Enter a whole number from 1 to 50.", 4)
            return
        end
        local clamped = math.clamp(amount, 1, 50)
        Hub.Settings.ChestTargetCount = clamped
        setStatus("Chest target set to " .. tostring(clamped))
        if clamped ~= amount then
            notify("Auto Chest", "Chest amount is limited to 1-50. Set to " .. tostring(clamped) .. ".", 4)
        end
    end
})

Tabs.FarmOther:AddToggle("AutoChest", {
    Title = "Auto Chest",
    Description = "Toggle chest collection ON/OFF.",
    Default = false,
    Callback = function(value)
        if value then
            Hub.ChestCollectedCount = 0
            Hub.ChestPending = nil
            Hub.ChestPausedItem = nil
            chestScanCache.At = 0
            table.clear(chestCooldowns)
        end
        setFeature("AutoChest", value, autoChestStep)
    end
})

Tabs.FarmOther:AddParagraph({
    Title = "Auto Berry",
    Content = "Visits every active BerryBush in this server. When none remain, it displays Waiting berry and keeps checking this server; it does not hop."
})

Tabs.FarmOther:AddToggle("AutoBerry", {
    Title = "Auto Berry",
    Description = "Collect all currently spawned berries in this server.",
    Default = false,
    Callback = function(value)
        if value then
            Hub.BerryWaitingNotified = false
            table.clear(berryRetryAfter)
        end
        setFeature("AutoBerry", value, autoBerryStep)
    end
})

Tabs.ESP:AddParagraph({
    Title = "ESP",
    Content = "Local-only labels and highlights. Toggle each category independently."
})

Tabs.ESP:AddToggle("ESPPlayers", {
    Title = "ESP Players",
    Description = "Names, distance, health and team-colored highlights for other players in this server.",
    Default = false,
    Callback = function(value)
        setFeature("ESPPlayers", value, espPlayersStep)
    end
})

Tabs.ESP:AddToggle("ESPBerry", {
    Title = "ESP Berry",
    Description = "Shows the active berry bush name and distance.",
    Default = false,
    Callback = function(value)
        setFeature("ESPBerry", value, espBerryStep)
    end
})

Tabs.ESP:AddToggle("ESPIslands", {
    Title = "ESP Island",
    Description = "Shows island location names and distance from Workspace._WorldOrigin.Locations.",
    Default = false,
    Callback = function(value)
        setFeature("ESPIslands", value, espIslandsStep)
    end
})

--// Stats tab: one target dropdown prevents simultaneous allocation into multiple stats.
Tabs.Stats:AddParagraph({
    Title = "Automatic Stat Allocation",
    Content = "Choose exactly one stat. When points become available, the hub spends them only on that selection. Changing the dropdown redirects future allocations; Defense is intentionally not included."
})

Tabs.Stats:AddDropdown("AutoStatCategory", {
    Title = "Target Stat",
    Description = "Only this stat receives points while Auto Stats is enabled.",
    Values = { "Melee", "Sword", "Gun", "Blox Fruit" },
    Default = Hub.Settings.AutoStatCategory,
    Callback = function(value)
        if AUTO_STAT_REMOTE_NAMES[value] then
            Hub.Settings.AutoStatCategory = value
            Hub.AutoStatFailureCount = 0
            setStatus("Auto Stats target changed to " .. value)
        end
    end
})

Tabs.Stats:AddToggle("AutoStats", {
    Title = "Auto Stats",
    Description = "Automatically spend available stat points on the selected category only.",
    Default = false,
    Callback = function(value)
        Hub.AutoStatFailureCount = 0
        setFeature("AutoStats", value, autoStatsStep)
    end
})

local AutoStatsStatusParagraph = Tabs.Stats:AddParagraph({
    Title = "Allocation Status",
    Content = "Auto Stats is OFF. Select a target stat and enable the toggle to begin."
})

--// Status tab: current-server roster, similar to the game's Player Profile Server Tab.
local function readPlayerValue(player, containerNames, valueNames)
    for _, containerName in ipairs(containerNames) do
        local container = player:FindFirstChild(containerName)
        if container then
            for _, valueName in ipairs(valueNames) do
                local valueObject = container:FindFirstChild(valueName)
                if valueObject then
                    local ok, value = pcall(function() return valueObject.Value end)
                    if ok and value ~= nil then
                        return value
                    end
                end
            end
        end
    end
    return nil
end

local function getPlayerLevelForStatus(player)
    return tonumber(readPlayerValue(player, { "Data", "leaderstats" }, { "Level", "Lv" }))
end

local function buildServerStatusText()
    local currentPlayers = Players:GetPlayers()
    table.sort(currentPlayers, function(a, b)
        local levelA = getPlayerLevelForStatus(a) or -1
        local levelB = getPlayerLevelForStatus(b) or -1
        if levelA ~= levelB then
            return levelA > levelB
        end
        return a.Name:lower() < b.Name:lower()
    end)

    local maxPlayers = "?"
    pcall(function() maxPlayers = tostring(Players.MaxPlayers) end)
    local serverId = tostring(game.JobId or "")
    if #serverId > 12 then
        serverId = serverId:sub(1, 12) .. "…"
    elseif serverId == "" then
        serverId = "Unavailable"
    end

    local lines = {
        string.format("Players online: %d / %s", #currentPlayers, maxPlayers),
        "Place ID: " .. tostring(game.PlaceId),
        "Server ID: " .. serverId,
        "Hub status: " .. tostring(Hub.Status),
        string.format("Auto Stats: %s | Target: %s | Points: %s",
            Hub.Features.AutoStats.Enabled and "ON" or "OFF",
            tostring(Hub.Settings.AutoStatCategory),
            tostring(getAvailableStatPoints() or "?")),
        "",
        "PLAYERS IN THIS SERVER:"
    }

    if #currentPlayers == 0 then
        table.insert(lines, "No players detected.")
    else
        for index, player in ipairs(currentPlayers) do
            local level = getPlayerLevelForStatus(player)
            local race = readPlayerValue(player, { "Data" }, { "Race" })
            local bounty = readPlayerValue(player, { "leaderstats", "Data" }, { "Bounty/Honor", "Bounty", "Honor" })
            local team = player.Team and player.Team.Name or "No Team"
            local line = string.format("%02d. %s (@%s) | Lv %s | Race %s | %s",
                index,
                tostring(player.DisplayName or player.Name),
                tostring(player.Name),
                level and tostring(level) or "?",
                race and tostring(race) or "?",
                tostring(team))
            if bounty ~= nil then
                line = line .. " | Bounty " .. tostring(bounty)
            end
            table.insert(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

local ServerStatusParagraph = Tabs.Status:AddParagraph({
    Title = "Current Server",
    Content = "Reading current server information..."
})

Tabs.Status:AddParagraph({
    Title = "About this list",
    Content = "Shows players currently connected to this server only. Level, race and bounty are shown when the game replicates those values to your client. It does not search or reveal players from other servers."
})

local function refreshServerStatus()
    local content = buildServerStatusText()
    pcall(function()
        ServerStatusParagraph:SetDesc(content)
    end)
    local points = getAvailableStatPoints()
    local allocationText
    if Hub.Features.AutoStats.Enabled then
        allocationText = string.format("ON | Target: %s | Points remaining: %s",
            tostring(Hub.Settings.AutoStatCategory), tostring(points or "?"))
    else
        allocationText = "OFF | Target: " .. tostring(Hub.Settings.AutoStatCategory)
    end
    pcall(function()
        AutoStatsStatusParagraph:SetDesc(allocationText)
    end)
end

Tabs.Status:AddButton({
    Title = "Refresh Server List",
    Description = "Refresh the current-server player roster immediately.",
    Callback = refreshServerStatus
})

task.spawn(function()
    while not Hub.Unloading do
        refreshServerStatus()
        task.wait(2)
    end
end)

Tabs.Farming:AddParagraph({
    Title = "Bring Mob – Kaitun-style 2 target grouping",
    Content = "Farm Level keeps up to two nearby same-quest NPCs in the attack pair. The second NPC is softly pulled when local network ownership is granted; otherwise it remains a secondary attack target only while inside normal hit range. No hard CFrame snap or forced velocity reset is used."
})

Tabs.Farming:AddParagraph({
    Title = "NPC Stability Guard",
    Content = "Each NPC has an independent damage-progress timer. A stalled target is temporarily skipped; Farm Level keeps the healthy partner and recruits a replacement when possible. Pull constraints are removed on stop; no saved-position teleport is used."
})

Tabs.Farming:AddParagraph({
    Title = "Farm Status",
    Content = "Runtime status and errors are printed with the [MinhDZ Hub] prefix in the executor console."
})

Tabs.Utility:AddParagraph({
    Title = "Independent utilities",
    Content = "Auto Buso checks the Kaitun HasBuso marker and activates once per character spawn. Auto Equip starts automatically. Farm is controlled by one switch on the Farming tab."
})

Tabs.Utility:AddToggle("AutoEquipMelee", {
    Title = "Auto Equip Selected Weapon",
    Description = "Automatically keep the selected weapon category equipped from startup.",
    Default = true,
    Callback = function(value)
        setFeature("AutoEquipMelee", value, autoEquipMeleeStep)
    end
})

Tabs.Utility:AddToggle("AutoBuso", {
    Title = "Auto Buso (Haki)",
    Description = "Activate once per character spawn only when Buso is missing; never repeatedly toggle the Buso remote.",
    Default = true,
    Callback = function(value)
        setFeature("AutoBuso", value, autoBusoStep)
    end
})

--// Shop tab: a safe vendor navigator that retains the official purchase flow.
Tabs.Shop:AddParagraph({
    Title = "Shop Navigator",
    Content = "Choose a vendor in the current server. The hub travels to the NPC and sends its normal ProximityPrompt key only when already inside activation range; confirm the official shop dialogue to purchase. It does not bypass distance, currency, level or item requirements."
})

Tabs.Shop:AddDropdown("ShopVendor", {
    Title = "Select Shop",
    Description = "Fighting-style teachers and shop NPCs currently loaded in this sea/server.",
    Values = SHOP_VENDOR_OPTIONS,
    Default = Hub.Settings.ShopVendor,
    Callback = function(value)
        if SHOP_VENDOR_ALIASES[value] then
            Hub.Settings.ShopVendor = value
            setStatus("Shop target selected: " .. value)
        end
    end
})

Tabs.Shop:AddButton({
    Title = "Go to Selected Shop",
    Description = "Find the selected vendor in the current server and travel to its NPC.",
    Callback = function()
        if Hub.Features.ShopTravel.Enabled then
            stopFeature("ShopTravel")
        end
        startFeature("ShopTravel", shopTravelStep)
    end
})

Tabs.Shop:AddButton({
    Title = "Go to Blox Fruit Dealer",
    Description = "Travel to the regular Blox Fruit Dealer and try its normal in-range prompt to open the fruit shop.",
    Callback = function()
        Hub.Settings.ShopVendor = "Blox Fruit Dealer"
        if Hub.Features.ShopTravel.Enabled then
            stopFeature("ShopTravel")
        end
        startFeature("ShopTravel", shopTravelStep)
    end
})

Tabs.Shop:AddButton({
    Title = "Stop Shop Travel",
    Description = "Cancel travel to the selected vendor.",
    Callback = function()
        stopFeature("ShopTravel")
    end
})

Tabs.Travel:AddParagraph({
    Title = "Sea Travel",
    Content = "Uses the travel calls and unlock checks found in the supplied KaitunBF source. It cannot complete missing story/puzzle requirements by itself."
})

Tabs.Travel:AddToggle("AutoSeaTravel", {
    Title = "Auto Sea Travel",
    Description = "Request Second Sea at Lv. 700; request Third Sea when Dragon Claw mastery conditions are met.",
    Default = false,
    Callback = function(value)
        setFeature("AutoSeaTravel", value, autoSeaTravelStep)
    end
})

Tabs.Settings:AddParagraph({
    Title = "Menu Appearance",
    Content = "Resize the RedzLib window and choose a calm accent palette. The circular MZ button stays at the top-left and only opens/closes the menu."
})

Tabs.Settings:AddDropdown("MenuSize", {
    Title = "Menu Size",
    Description = "Choose Small, Medium or Big.",
    Values = { "Small", "Medium", "Big" },
    Default = Hub.Settings.MenuSize,
    Callback = function(value)
        if value == "Small" or value == "Medium" or value == "Big" then
            Hub.Settings.MenuSize = value
            if not applyMenuScale(value) then
                task.spawn(function()
                    for _ = 1, 20 do
                        if applyMenuScale(value) then break end
                        task.wait(0.5)
                    end
                end)
            end
        end
    end
})

Tabs.Settings:AddDropdown("MenuColor", {
    Title = "Menu Color",
    Description = "Dark, Blue, Purple, Red or Green; all use muted tones.",
    Values = { "Dark", "Blue", "Purple", "Red", "Green" },
    Default = Hub.Settings.MenuColor,
    Callback = function(value)
        if MenuPalettes[value] then
            Hub.Settings.MenuColor = value
            applyMenuPalette(value)
        end
    end
})

Tabs.Settings:AddParagraph({
    Title = "RedzLib Menu Visibility",
    Content = "Drag the circular MZ button anywhere on screen. Tap it or press RightControl to hide/reopen the menu; hiding the menu does not stop enabled features."
})

Tabs.Settings:AddParagraph({
    Title = "Team Selection",
    Content = "MinhDZ waits for Pirates/Marines selection before creating this menu. Preferred Team is remembered for the next execution; it never switches your live team."
})

Tabs.Settings:AddDropdown("PreferredTeam", {
    Title = "Preferred Team",
    Description = "Preferred faction for the next execution. The current live team is never changed.",
    Values = { "Pirates", "Marines" },
    Default = Hub.Settings.PreferredTeam,
    Callback = function(value)
        if value == "Pirates" or value == "Marines" then
            Hub.Settings.PreferredTeam = value
            ENV.MinhDZPreferredTeam = value
        end
    end
})

Tabs.Settings:AddToggle("AutoJoinTeam", {
    Title = "Auto Join Team on Startup",
    Description = "Automatically requests the preferred team before the main menu is created on the next execution.",
    Default = Hub.Settings.AutoJoinTeam,
    Callback = function(value)
        Hub.Settings.AutoJoinTeam = value == true
        ENV.MinhDZAutoJoinTeam = Hub.Settings.AutoJoinTeam
    end
})

Tabs.Skills:AddParagraph({
    Title = "Chọn và giữ kỹ năng",
    Content = "Chọn nhóm vũ khí cho Farm Level và phím kỹ năng trái. Auto Equip ở tab Nhân vật sẽ giữ đúng nhóm vũ khí đã chọn."
})

Tabs.Skills:AddDropdown("WeaponCategory", {
    Title = "Farm Weapon Category",
    Description = "The selected category is kept equipped during farming. Switching this dropdown changes the locked weapon category.",
    Values = { "Melee", "Sword", "Gun", "Blox Fruit" },
    Default = Hub.Settings.WeaponCategory,
    Callback = function(value)
        if table.find(VALID_WEAPON_CATEGORIES, value) then
            Hub.Settings.WeaponCategory = value
            if Hub.Features.FarmLevel.Enabled or Hub.Features.AutoEquipMelee.Enabled then
                task.defer(equipSelectedWeapon)
            end
            setStatus("Weapon category locked: " .. value)
        end
    end
})

Tabs.Skills:AddDropdown("FruitSkill", {
    Title = "Blox Fruit Skill",
    Description = "Skill key used while Blox Fruit is selected. Only available/unlocked skills will work.",
    Values = { "Z", "X", "C", "V" },
    Default = Hub.Settings.FruitSkill,
    Callback = function(value)
        if value == "Z" or value == "X" or value == "C" or value == "V" then
            Hub.Settings.FruitSkill = value
        end
    end
})


Tabs.Skills:AddParagraph({
    Title = "Auto Click",
    Content = "Independent click loop similar to the supplied Banana/Kaitun reference. It clicks the center of the game viewport and is separate from Farm Level's registered hit system."
})

Tabs.Skills:AddToggle("AutoClick", {
    Title = "Auto Click",
    Description = "Automatically press and release the primary mouse button.",
    Default = false,
    Callback = function(value)
        setFeature("AutoClick", value, autoClickWorker)
    end
})

Tabs.Skills:AddSlider("ClicksPerSecond", {
    Title = "Auto Click Speed (CPS)",
    Description = "Click rate for Auto Click. Default 20 CPS; range 1–30.",
    Default = 20,
    Min = 1,
    Max = 30,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.ClicksPerSecond = math.clamp(math.floor(tonumber(value) or 20), 1, 30)
    end
})

Tabs.Settings:AddSlider("BringPairRadius", {
    Title = "Bring Mob Pair Radius",
    Description = "Kaitun-style camp radius for selecting a same-quest partner. Default 300 studs; the player must be within the normal simulation range.",
    Default = 300,
    Min = 40,
    Max = 300,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.BringPairRadius = math.clamp(tonumber(value) or 300, 40, 300)
        Hub.ActiveFarmPair = nil
    end
})

Tabs.Settings:AddSlider("FlightSpeed", {
    Title = "Flight Speed",
    Description = "Kaitun-style direct CFrame flight. Default 250 studs/second (Kaitun default 275, reduced slightly); NoClip is re-applied every physics step.",
    Default = 250,
    Min = 50,
    Max = 325,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.FlightSpeed = math.clamp(tonumber(value) or 250, 50, 325)
    end
})

Tabs.Settings:AddSlider("AttackHeight", {
    Title = "Attack Height",
    Description = "Continuous hover height above the target mob; maintained even while attacks are cooling down.",
    Default = 18,
    Min = 8,
    Max = 60,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.AttackHeight = math.clamp(tonumber(value) or 18, 8, 60)
    end
})

Tabs.Settings:AddSlider("AttackInterval", {
    Title = "Attack Interval",
    Description = "Cooldown for melee/sword hits; Gun and Blox Fruit use their own minimum cooldowns.",
    Default = 0.18,
    Min = 0.12,
    Max = 0.6,
    Rounding = 2,
    Callback = function(value)
        Hub.Settings.AttackInterval = math.clamp(tonumber(value) or 0.18, 0.12, 0.6)
    end
})

Tabs.Settings:AddButton({
    Title = "Stop All Features",
    Description = "Stops every enabled feature and cancels active movement.",
    Callback = function()
        if FarmToggle then
            pcall(function() FarmToggle:SetValue(false) end)
        else
            stopActiveFarmModes()
        end
        local optionNames = {
            AutoClick = "AutoClick",
            AutoChest = "AutoChest",
            AutoBerry = "AutoBerry",
            ESPPlayers = "ESPPlayers",
            ESPBerry = "ESPBerry",
            ESPIslands = "ESPIslands",
            AutoEquipMelee = "AutoEquipMelee",
            AutoBuso = "AutoBuso",
            AutoStats = "AutoStats",
            AutoSeaTravel = "AutoSeaTravel",
            ShopTravel = "ShopTravel"
        }
        for featureName, optionName in pairs(optionNames) do
            local option = Fluent.Options[optionName]
            if option and Hub.Features[featureName].Enabled then
                option:SetValue(false)
            else
                stopFeature(featureName)
            end
        end
        stopMovement()
        stopHover()
        restoreAllBroughtMobs()
        Hub.ClearFarmTarget()
        notify("MinhDZ Hub", "All features stopped", 4)
    end
})

Tabs.Settings:AddButton({
    Title = "Unload Hub",
    Description = "Stops all loops, restores collisions and removes the RedzLib UI.",
    Callback = function()
        Hub.Unload()
    end
})

function Hub.Unload()
    if Hub.Unloading then
        return
    end
    Hub.Unloading = true
    for _, feature in pairs(Hub.Features) do
        feature.Enabled = false
        feature.Token = feature.Token + 1
    end
    stopMovement()
    stopHover()
    restoreAllBroughtMobs()
    Hub.ClearFarmTarget()
    clearAllESP()
    if toggleInputConnection then
        pcall(function()
            toggleInputConnection:Disconnect()
        end)
        toggleInputConnection = nil
    end
    for _, connection in ipairs(toggleDragConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(toggleDragConnections)
    pcall(function()
        FloatingGui:Destroy()
    end)
    pcall(function()
        Fluent:Destroy()
    end)
end

-- Start fixed baseline utilities automatically. Farm remains OFF until its toggle is enabled.
-- Calling startFeature explicitly avoids relying on RedzLib initial Default callbacks.
startFeature("AutoEquipMelee", autoEquipMeleeStep)
startFeature("AutoBuso", autoBusoStep)

Window:SelectTab(Tabs.Farming)

-- Team selection has already completed before the RedzLib window was constructed.
-- No background SetTeam worker runs after the menu becomes available.

Fluent:Notify({
    Title = "Minhdz hub (beta) by dev Minh",
    Content = "Minhdz hub (beta) is ready. Choose a farm mode and use the Farm switch. Auto Buso and weapon lock are active; Auto Click, Auto Berry, Auto Chest and ESP are OFF by default.",
    Duration = 6
})

print("[Minhdz hub (beta) by dev Minh] Loaded v5.15.1 | Farm toggle | Auto Berry | Auto Chest pause/count | Player/Berry/Island ESP | draggable MZ toggle")
