-- ====================================================================
-- UA Killer Hub | YBA — Methion Instant SafeZone Farm & AutoSell (No-Kick Edition)
-- Інстант фарм через SafeZone Decoy (як у Methion 1.txt) + 100с Snapshot AutoSell + Shutdown
-- ====================================================================
print("[UA Killer Hub | Init] Початок запуску скрипта...")

if not game:IsLoaded() then
    print("[UA Killer Hub | Init] Очікування повного завантаження гри...")
    game.Loaded:Wait()
end
print("[UA Killer Hub | Init] Гра завантажена.")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
while not player do
    task.wait(0.1)
    player = Players.LocalPlayer
end
print("[UA Killer Hub | Init] Гравець ідентифікований: " .. player.Name)

-- =======================================================
-- СИСТЕМА УПРАВЛІННЯ ЖИТТЄВИМ ЦИКЛОМ (SHUTDOWN)
-- =======================================================
local isShutdown = false
local scriptConnections = {}

local function trackConnection(conn)
    if conn then
        table.insert(scriptConnections, conn)
    end
    return conn
end

local autoLoadFile = "UAKillerHub/YBA_AutoLoad.txt"
local configFile   = "UAKillerHub/YBA_Config.json"
local shouldAutoLoad = false

-- =======================================================
-- НАДІЙНІ ТА БЕЗПЕЧНІ АНТИЧИТ-БАЙПАСИ (БЕЗ ВИЛЬОТІВ)
-- =======================================================
local RETURNER_KEY = "idklolbrah2de"
local RETURNER_RESPONSE = "  ___XP DE KEY"
local bypassSupported = false

-- 1. YBA Returner Remote Hook (Namecall - безпечний, не крашить гру)
pcall(function()
    if hookmetamethod and newcclosure and checkcaller then
        local old
        old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if not checkcaller() and typeof(self) == "Instance" and self.Name == "Returner" and rawequal((...), RETURNER_KEY) then
                return RETURNER_RESPONSE
            end
            return old(self, ...)
        end))
        bypassSupported = true
        print("[UA Killer Hub | Init] Returner Remote Hook (No-Kick) активовано.")
    end
end)

-- 2. Глобальний Vector3 Metatable Magnitude Bypass (як у Methion 1.txt)
pcall(function()
    local meta = getrawmetatable(Vector3.new())
    if not meta then return end
    setreadonly(meta, false)
    local old = meta.__index
    meta.__index = newcclosure(function(self, index)
        if not checkcaller() and (index == "magnitude" or index == "Magnitude") then
            local cs = getcallingscript()
            if cs then
                local name = typeof(cs) == "Instance" and (cs.Name or "") or tostring(cs)
                if name == "ItemSpawn" then return 0 end
            end
        end
        return old(self, index)
    end)
    setreadonly(meta, true)
    print("[UA Killer Hub | Init] Vector3 Metatable Magnitude Bypass активовано.")
end)

-- 3. Безпечний WalkSpeed/Crash Bypass
pcall(function()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local fl = modules and modules:FindFirstChild("FunctionLibrary")
    if fl and getupvalues then
        local FunctionLibrary = require(fl)
        if FunctionLibrary and FunctionLibrary.pcall then
            local OldPcall = FunctionLibrary.pcall
            FunctionLibrary.pcall = function(...)
                local args = { ... }
                local ok, ups = pcall(getupvalues, args[1])
                if ok and type(ups) == "table" and #ups == 11 then
                    return
                end
                return OldPcall(...)
            end
            print("[UA Killer Hub | Init] WalkSpeed/Crash Bypass активовано.")
        end
    end
end)

-- Ініціалізація папки та конфігурації
pcall(function()
    if makefolder and not isfolder("UAKillerHub") then
        makefolder("UAKillerHub")
    end
    if isfile and isfile(autoLoadFile) then
        shouldAutoLoad = (readfile(autoLoadFile) == "true")
    elseif writefile then
        writefile(autoLoadFile, "false")
    end
end)

-- ====================
-- ГЛОБАЛЬНІ НАЛАШТУВАННЯ
-- ====================
_G.AutoSell        = false
_G.AutoEventCandy  = false
_G.AutoBuy         = false
_G.ItemFarm        = false
_G.InstantFarm     = true -- Інстант-фарм через SafeZone телепортацію з 1.txt (без кіків)
_G.ItemESP         = false
_G.FlySpeed        = 180 -- Безпечна та швидка швидкість польоту (не викликає кік)
_G.AntiAFK         = false
_G.StandaloneNoClip= false
_G.AutoRespawn     = true

_G.SelectedItems = {
    ["Ancient Scroll"] = false,
    ["Blue Candy"] = false,
    ["Caesar's Headband"] = false,
    ["Christmas Present"] = false,
    ["Clackers"] = false,
    ["Diamond"] = false,
    ["Dio's Diary"] = false,
    ["Gold Coin"] = false,
    ["Gold Umbrella"] = false,
    ["Green Candy"] = false,
    ["Lucky Arrow"] = false,
    ["Lucky Stone Mask"] = false,
    ["Mysterious Arrow"] = false,
    ["Pure Rokakaka"] = false,
    ["Quinton's Glove"] = false,
    ["Red Candy"] = false,
    ["Rib Cage of The Saint's Corpse"] = false,
    ["Rokakaka"] = false,
    ["Steel Ball"] = false,
    ["Stone Mask"] = false,
    ["Yellow Candy"] = false,
    ["Zepellin's Headband"] = false,
    ["Zeppeli's Hat"] = false,
}

local FARM_PRIORITY = {
    ["Lucky Arrow"] = true,
    ["Lucky Stone Mask"] = true,
    ["Christmas Present"] = true,
}

-- =======================================================
-- МОДУЛЬ ВІДСТЕЖЕННЯ ТА ЗБОРУ ПРЕДМЕТІВ (HIGH PERFORMANCE)
-- =======================================================
local Tracked            = {}
local TrackedRev         = {}
local Pending            = {}
local bannedCoordinates  = {}
local failedItemAttempts = {}
local espObjects         = {}
local BAN_TTL            = 30

local farmThreadActive   = false
local farmSessionId      = 0
local farmStatusText     = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection
local JP_Value = 50

-- Стан готовності систем
local TeleportService = game:GetService("TeleportService")

local uiElementsRegistry = {}

local manuallyChanged = {
    ItemFarm         = false,
    AutoSell         = false,
    AutoEventCandy   = false,
    AutoBuy          = false,
    ItemESP          = false,
    AntiAFK          = false,
    StandaloneNoClip = false,
    AutoRespawn      = false,
}

local function setFarmStatus(text)
    farmStatusText = text
end

local function getCharacter()
    local char = player.Character
    if not char or not char:IsDescendantOf(workspace) then
        return nil, nil, nil
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function zeroHrpVelocity(hrp)
    if not hrp then return end
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.Velocity                = Vector3.zero
        hrp.RotVelocity             = Vector3.zero
    end)
end

-- =======================================================
-- БЕЗПЕЧНЕ РОЗВАНТАЖЕННЯ ІНВЕНТАРЯ ТА SAFEZONE (METHION)
-- =======================================================
local SafeZone = Vector3.new(-212.241150, -33.486183, -283.842651)

local function forceUnequipAllTools()
    pcall(function()
        local char, _, hum = getCharacter()
        if hum then
            pcall(function() hum:UnequipTools() end)
        end
        local bp = player:FindFirstChild("Backpack")
        if char and bp then
            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") then
                    pcall(function() child.Parent = bp end)
                end
            end
        end
    end)
end

-- Початкове очищення руки від предметів, щоб не з'являлася кнопка DROP
pcall(forceUnequipAllTools)

local function cleanupFlight()
    if not flightState then return end
    if flightState.tween then pcall(function() flightState.tween:Cancel() end) end
    if flightState.heartbeatConn then pcall(function() flightState.heartbeatConn:Disconnect() end) end
    if flightState.cframeValue and flightState.cframeValue.Parent then
        pcall(function() flightState.cframeValue:Destroy() end)
    end
    flightState = nil

    local char, hrp = getCharacter()
    if hrp then zeroHrpVelocity(hrp) end
    if char and not _G.StandaloneNoClip and not _G.ItemFarm then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
end

local function stopFlight()
    cleanupFlight()
    if noclipConnection and not _G.StandaloneNoClip and not _G.ItemFarm then
        pcall(function() noclipConnection:Disconnect() end)
        noclipConnection = nil
    end
    pcall(function()
        for _, obj in ipairs(player:GetChildren()) do
            if obj.Name == "YBA_VirtualCFrame" then obj:Destroy() end
        end
    end)
end

local function ensureNoClip()
    if noclipConnection or isShutdown then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if isShutdown or (not _G.ItemFarm and not _G.StandaloneNoClip) then
            if noclipConnection and isShutdown then
                pcall(function() noclipConnection:Disconnect() end)
                noclipConnection = nil
            end
            return
        end
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= hrp then
                part.CanCollide = false
            end
        end
    end)
end

local function isPlayerOwned(part)
    if not part or not part.Parent then return true end
    for _, plr in ipairs(Players:GetPlayers()) do
        local c = plr.Character
        local b = plr:FindFirstChild("Backpack")
        if (c and part:IsDescendantOf(c)) or (b and part:IsDescendantOf(b)) then
            return true
        end
    end
    return false
end

local function getBasePart(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj.Parent:IsA("BasePart") then return obj.Parent end
    return obj.Parent:FindFirstChildWhichIsA("BasePart", true)
        or (obj.Parent.Parent and obj.Parent.Parent:FindFirstChildWhichIsA("BasePart", true))
end

local function isValidPosition(part)
    if not part or not part:IsDescendantOf(workspace) then return false end
    local p = part.Position
    return not (math.abs(p.X) < 1 and math.abs(p.Y) < 1 and math.abs(p.Z) < 1)
end

local function isPartInvisible(part)
    if not part or not part.Parent or not part:IsDescendantOf(workspace) then return true end
    if part.Transparency >= 1 then return true end
    if part.LocalTransparencyModifier >= 1 then return true end
    return false
end

local function isSpawnedItemPrompt(obj)
    if not obj or (obj.ObjectText or "") == "" then return false end
    local spawns = workspace:FindFirstChild("Item_Spawns")
    local folder = spawns and spawns:FindFirstChild("Items")
    return folder ~= nil and obj:IsDescendantOf(folder)
end

local function anyItemSelected()
    for _, v in pairs(_G.SelectedItems) do
        if v then return true end
    end
    return false
end

local function shouldFarmItem(itemName)
    if not anyItemSelected() then return true end
    return _G.SelectedItems[itemName] == true
end

local function cleanupBannedCoordinates()
    local now = tick()
    for i = #bannedCoordinates, 1, -1 do
        if now - bannedCoordinates[i].time > BAN_TTL then
            table.remove(bannedCoordinates, i)
        end
    end
end

local function isCoordinateBanned(pos, itemPart)
    cleanupBannedCoordinates()
    for _, entry in ipairs(bannedCoordinates) do
        if (pos - entry.pos).Magnitude < 3 then
            if entry.instance and itemPart and entry.instance == itemPart then
                return true
            elseif not entry.instance then
                return true
            end
        end
    end
    return false
end

local function banFailedItem(item, reason)
    if not item or not item.part then return end
    local pos = item.position or item.part.Position
    local partInstance = item.part
    local itemName = item.name or "Unknown"

    table.insert(bannedCoordinates, {
        pos = pos,
        time = tick(),
        instance = partInstance,
        reason = reason or "failed_pickup",
        name = itemName,
    })
end

-- ====================
-- ESP ПРЕДМЕТІВ
-- ====================
local function applyESP(part, name)
    if isShutdown or not part or espObjects[part] then return end
    if isPartInvisible(part) or isCoordinateBanned(part.Position) or isPlayerOwned(part) then return end

    local bgui = Instance.new("BillboardGui")
    bgui.Name        = "YBA_Item_ESP"
    bgui.AlwaysOnTop = true
    bgui.Size        = UDim2.new(0, 140, 0, 32)
    bgui.Adornee     = part

    local text = Instance.new("TextLabel")
    text.Parent              = bgui
    text.BackgroundTransparency = 1
    text.Size                = UDim2.new(1, 0, 1, 0)
    text.Text                = name
    text.TextColor3          = Color3.fromRGB(139, 124, 246)
    text.TextSize            = 13
    text.Font                = Enum.Font.GothamBold
    text.TextStrokeTransparency = 0

    bgui.Parent       = part
    espObjects[part]  = bgui
end

local function clearESP()
    for part, gui in pairs(espObjects) do
        if gui then pcall(function() gui:Destroy() end) end
        espObjects[part] = nil
    end
    table.clear(espObjects)
end

local function unregisterItem(part)
    if not part then return end
    if Tracked[part] then Tracked[part] = nil end
    for obj, mapped in pairs(TrackedRev) do
        if mapped == part then TrackedRev[obj] = nil end
    end
    for i = #Pending, 1, -1 do
        if Pending[i] and Pending[i].part == part then
            table.remove(Pending, i)
        end
    end
    if espObjects[part] then
        pcall(function() espObjects[part]:Destroy() end)
        espObjects[part] = nil
    end
end

local function registerItem(obj)
    if isShutdown or not obj then return end
    if TrackedRev[obj] then return end

    local name, part = nil, nil
    if obj:IsA("ProximityPrompt") then
        local text = obj.ObjectText or ""
        if _G.SelectedItems[text] ~= nil or isSpawnedItemPrompt(obj) then
            name = text ~= "" and text or (obj.Parent and obj.Parent.Name)
            part = getBasePart(obj)
        end
    elseif obj:IsA("BasePart") then
        if _G.SelectedItems[obj.Name] ~= nil then
            name = obj.Name
            part = obj
        end
    end

    if not name or not part or isPlayerOwned(part) then return end
    if Tracked[part] then
        TrackedRev[obj] = part
        return
    end

    if not isValidPosition(part) then
        table.insert(Pending, { obj = obj, part = part, name = name })
        return
    end

    Tracked[part] = { Name = name, Obj = obj }
    TrackedRev[obj] = part

    if _G.ItemESP and not isPartInvisible(part) then
        applyESP(part, name)
    end
end

local function scanAllItems()
    for _, o in ipairs(workspace:GetDescendants()) do
        if isShutdown then break end
        if o:IsA("ProximityPrompt") or o:IsA("BasePart") then
            registerItem(o)
        end
    end
end

-- Реактивний перехоплювач появи предметів (з 1.txt)
trackConnection(workspace.DescendantAdded:Connect(function(o)
    if isShutdown or not o or not o.Parent then return end
    if o:IsA("ProximityPrompt") then
        registerItem(o)
        if (o.ObjectText or "") == "" then
            local conn
            conn = o:GetPropertyChangedSignal("ObjectText"):Connect(function()
                if isShutdown or not o.Parent then
                    if conn then conn:Disconnect() end
                    return
                end
                if (o.ObjectText or "") ~= "" then
                    registerItem(o)
                    if conn then conn:Disconnect() end
                end
            end)
            trackConnection(conn)
        end
    elseif o:IsA("BasePart") then
        registerItem(o)
    end
end))

trackConnection(workspace.DescendantRemoving:Connect(function(o)
    if isShutdown or not o then return end
    if o:IsA("BasePart") and Tracked[o] then
        unregisterItem(o)
    elseif TrackedRev[o] then
        unregisterItem(TrackedRev[o])
    end
end))

-- Пошук найближчого або пріоритетного предмета
local function getNearestFarmItem(hrp)
    if not hrp then return nil, nil, nil end
    local origin = hrp.Position
    local nearest, nearestPart, nearestData, nearestDist = nil, nil, nil, math.huge
    local prioItem, prioPart, prioData, prioDist = nil, nil, nil, math.huge

    for part, data in pairs(Tracked) do
        if part and part.Parent and part:IsDescendantOf(workspace)
            and isValidPosition(part)
            and not isPlayerOwned(part)
            and not isPartInvisible(part)
            and not isCoordinateBanned(part.Position, part)
            and shouldFarmItem(data.Name) then

            local dist = (part.Position - origin).Magnitude
            local candidate = part:FindFirstAncestorOfClass("Model") or part

            if dist < nearestDist then
                nearestDist = dist
                nearest = candidate
                nearestPart = part
                nearestData = data
            end

            if FARM_PRIORITY[data.Name] and dist < prioDist then
                prioDist = dist
                prioItem = candidate
                prioPart = part
                prioData = data
            end
        end
    end

    if prioItem then
        return prioItem, prioPart, prioData, prioDist
    end
    return nearest, nearestPart, nearestData, nearestDist
end

-- ====================
-- ПЛАВНИЙ ТА БЕЗПЕЧНИЙ ПОЛІТ (НЕ ВИКЛИКАЄ КІК)
-- ====================
local function flyToItem(targetPart, speed, shouldContinue)
    speed = math.max(tonumber(speed) or _G.FlySpeed or 180, 20)
    local char, hrp = getCharacter()
    if not hrp or not hrp.Parent then return false end

    cleanupFlight()

    local cframeValue = Instance.new("CFrameValue")
    cframeValue.Name   = "YBA_VirtualCFrame"
    cframeValue.Value  = hrp.CFrame
    cframeValue.Parent = player

    local targetCFrame = CFrame.new(targetPart.Position + Vector3.new(0, 1.2, 0))
    local distance     = (targetCFrame.Position - hrp.Position).Magnitude
    local tweenTime    = math.max(distance / speed, 0.04)

    local tween = TweenService:Create(cframeValue, TweenInfo.new(tweenTime, Enum.EasingStyle.Linear), { Value = targetCFrame })

    local cancelled = false
    local heartbeatConn
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if isShutdown or cancelled then return end
        if not char or not char.Parent or not cframeValue.Parent then
            cancelled = true
            pcall(function() tween:Cancel() end)
            return
        end

        local currentHrp = char:FindFirstChild("HumanoidRootPart")
        if not currentHrp then return end

        currentHrp.CFrame = cframeValue.Value
        zeroHrpVelocity(currentHrp)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= currentHrp then
                part.CanCollide = false
            end
        end

        if shouldContinue then
            local ok, keepGoing = pcall(shouldContinue)
            if not ok or not keepGoing then
                cancelled = true
                pcall(function() tween:Cancel() end)
            end
        end
    end)

    flightState = { cframeValue = cframeValue, tween = tween, heartbeatConn = heartbeatConn }

    tween:Play()
    local finished = false
    local tweenCompletedConn
    tweenCompletedConn = tween.Completed:Once(function() finished = true end)

    local flightTimeout = tick() + tweenTime + 2.0
    while not finished and not cancelled and not isShutdown do
        if tick() > flightTimeout then break end
        RunService.Heartbeat:Wait()
    end

    if tweenCompletedConn then tweenCompletedConn:Disconnect() end
    cleanupFlight()

    if not cancelled and not isShutdown and hrp.Parent then
        local currentHrp = char:FindFirstChild("HumanoidRootPart")
        if currentHrp then
            currentHrp.CFrame = targetCFrame
            zeroHrpVelocity(currentHrp)
        end
        return true
    end
    return false
end

-- =======================================================
-- METHION TELEPORT & SAFEZONE DECOY SYSTEM (З 1.TXT)
-- =======================================================
local Move = {}

function Move.telePart(part)
    if not part or not part.Parent or not part:IsDescendantOf(workspace) then return false end
    local char, hrp = getCharacter()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
    zeroHrpVelocity(hrp)
    return true
end

function Move.teleSafe()
    local char, hrp = getCharacter()
    if not hrp then return false end
    hrp.CFrame = CFrame.new(SafeZone)
    zeroHrpVelocity(hrp)
    task.wait(0.05)
    return true
end

local function moveToSafeIfNeeded()
    local char, hrp = getCharacter()
    if hrp and (hrp.Position - SafeZone).Magnitude > 6 then
        return Move.teleSafe()
    end
    return hrp ~= nil
end

local FarmVisual = {
    OriginalVisuals = setmetatable({}, {__mode = "k"}),
    AnimationMap = setmetatable({}, {__mode = "k"}),
    DecoyUpdateConnection = nil,
    FallbackWalkTrack = nil,
    FallbackWalkAnimation = nil,
    CameraBindBefore = "UA_Farm_Decoy_Camera_Before",
    CameraBindAfter = "UA_Farm_Decoy_Camera_After",
}

local function hideFarmVisual(instance)
    if not instance or not instance.Parent then return end
    -- ВАЖЛИВО: Інструменти та предмети в інвентарі ніколи не чіпаємо, щоб не блокувати інвентар!
    if instance:IsA("Tool") or instance:FindFirstAncestorWhichIsA("Tool") then
        return
    end
    if instance:IsA("BasePart") then
        if FarmVisual.OriginalVisuals[instance] == nil then
            FarmVisual.OriginalVisuals[instance] = {
                Kind = "BasePart",
                LocalTransparencyModifier = instance.LocalTransparencyModifier,
                Transparency = instance.Transparency,
            }
        end
        pcall(function()
            instance.LocalTransparencyModifier = 1
            instance.Transparency = 1
        end)
    elseif instance:IsA("Decal") or instance:IsA("Texture") then
        if FarmVisual.OriginalVisuals[instance] == nil then
            FarmVisual.OriginalVisuals[instance] = {
                Kind = "Texture",
                Transparency = instance.Transparency,
            }
        end
        pcall(function() instance.Transparency = 1 end)
    end
end

function FarmVisual.isActive()
    return FarmVisual.Character == player.Character
        and FarmVisual.Decoy ~= nil
        and FarmVisual.Decoy.Parent ~= nil
        and FarmVisual.DecoyHumanoid ~= nil
        and FarmVisual.DecoyHumanoid.Parent ~= nil
end

function FarmVisual.cleanup()
    pcall(function()
        RunService:UnbindFromRenderStep(FarmVisual.CameraBindBefore)
        RunService:UnbindFromRenderStep(FarmVisual.CameraBindAfter)
    end)

    if FarmVisual.CharacterConnection then
        pcall(function() FarmVisual.CharacterConnection:Disconnect() end)
        FarmVisual.CharacterConnection = nil
    end
    if FarmVisual.DecoyUpdateConnection then
        pcall(function() FarmVisual.DecoyUpdateConnection:Disconnect() end)
        FarmVisual.DecoyUpdateConnection = nil
    end
    for _, entry in pairs(FarmVisual.AnimationMap or {}) do
        if type(entry) == "table" then
            if entry.Track then
                pcall(function() entry.Track:Stop(0) end)
                pcall(function() entry.Track:Destroy() end)
            end
            if entry.Animation then
                pcall(function() entry.Animation:Destroy() end)
            end
        end
    end
    FarmVisual.AnimationMap = setmetatable({}, {__mode = "k"})
    if FarmVisual.FallbackWalkTrack then
        pcall(function() FarmVisual.FallbackWalkTrack:Stop(0) end)
        pcall(function() FarmVisual.FallbackWalkTrack:Destroy() end)
        FarmVisual.FallbackWalkTrack = nil
    end
    if FarmVisual.FallbackWalkAnimation then
        pcall(function() FarmVisual.FallbackWalkAnimation:Destroy() end)
        FarmVisual.FallbackWalkAnimation = nil
    end

    for instance, saved in pairs(FarmVisual.OriginalVisuals or {}) do
        if instance and instance.Parent and type(saved) == "table" then
            pcall(function()
                if saved.Kind == "BasePart" then
                    instance.LocalTransparencyModifier = saved.LocalTransparencyModifier
                    instance.Transparency = saved.Transparency
                elseif saved.Kind == "Texture" then
                    instance.Transparency = saved.Transparency
                end
            end)
        end
    end
    FarmVisual.OriginalVisuals = setmetatable({}, {__mode = "k"})

    local wasActive = FarmVisual.Decoy ~= nil
    local previousSubject = FarmVisual.PreviousCameraSubject
    local previousCameraType = FarmVisual.PreviousCameraType
    local decoy = FarmVisual.Decoy

    FarmVisual.Character = nil
    FarmVisual.Decoy = nil
    FarmVisual.DecoyHumanoid = nil
    FarmVisual.DecoyRoot = nil
    FarmVisual.PreviousCameraSubject = nil
    FarmVisual.PreviousCameraType = nil

    if decoy then
        pcall(function() decoy:Destroy() end)
    end

    if wasActive then
        local camera = workspace.CurrentCamera
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if camera then
            pcall(function()
                camera.CameraType = previousCameraType or Enum.CameraType.Custom
                local subject = hum or previousSubject
                if subject and subject.Parent then
                    camera.CameraSubject = subject
                end
            end)
        end
    end
end

function FarmVisual.showSafeZoneDecoy()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not root or not hum then return false end
    if FarmVisual.isActive() then return true end

    FarmVisual.cleanup()

    local wasArchivable = char.Archivable
    local ok, decoy
    pcall(function() char.Archivable = true end)
    ok, decoy = pcall(function() return char:Clone() end)
    pcall(function() char.Archivable = wasArchivable end)
    if not ok or not decoy or not decoy:IsA("Model") then
        return false
    end

    decoy.Name = "UA_FarmSafeZoneDecoy"
    local decoyRoot = decoy:FindFirstChild("HumanoidRootPart")
    local decoyHumanoid = decoy:FindFirstChildOfClass("Humanoid")
    if not decoyRoot or not decoyHumanoid then
        pcall(function() decoy:Destroy() end)
        return false
    end

    for _, descendant in ipairs(decoy:GetDescendants()) do
        if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript")
            or descendant:IsA("Trail") or descendant:IsA("Beam") or descendant:IsA("ParticleEmitter")
            or descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
            pcall(function() descendant:Destroy() end)
        elseif descendant:IsA("BasePart") then
            pcall(function()
                descendant.LocalTransparencyModifier = 0
                descendant.Anchored = descendant == decoyRoot
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
                descendant.Massless = descendant ~= decoyRoot
            end)
        end
    end

    pcall(function()
        decoyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        decoyHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        decoyHumanoid.BreakJointsOnDeath = false
        decoyHumanoid.AutoRotate = false
        decoyHumanoid.PlatformStand = false
        decoyHumanoid.Sit = false
        decoyHumanoid.WalkSpeed = hum.WalkSpeed
        decoyHumanoid.JumpPower = hum.JumpPower
        decoyHumanoid.UseJumpPower = hum.UseJumpPower
    end)

    local safeRootCFrame = CFrame.new(SafeZone) * root.CFrame.Rotation
    local pivotOffset = root.CFrame:ToObjectSpace(char:GetPivot())
    decoy.Parent = workspace
    decoy:PivotTo(safeRootCFrame * pivotOffset)

    FarmVisual.Character = char
    FarmVisual.Decoy = decoy
    FarmVisual.DecoyHumanoid = decoyHumanoid
    FarmVisual.DecoyRoot = decoyRoot
    FarmVisual.AnimationMap = setmetatable({}, {__mode = "k"})
    FarmVisual.OriginalVisuals = setmetatable({}, {__mode = "k"})

    for _, descendant in ipairs(char:GetDescendants()) do
        hideFarmVisual(descendant)
    end

    FarmVisual.CharacterConnection = char.DescendantAdded:Connect(function(descendant)
        if FarmVisual.Character == char and FarmVisual.Decoy == decoy then
            hideFarmVisual(descendant)
        end
    end)

    local camera = workspace.CurrentCamera
    if camera then
        FarmVisual.PreviousCameraSubject = camera.CameraSubject
        FarmVisual.PreviousCameraType = camera.CameraType
        pcall(function()
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = decoyHumanoid
        end)
    end

    local function maintainDecoyCamera()
        if FarmVisual.Decoy ~= decoy or not decoy.Parent or not decoyHumanoid.Parent then
            return
        end

        for instance, saved in pairs(FarmVisual.OriginalVisuals or {}) do
            if instance and instance.Parent and type(saved) == "table" then
                pcall(function()
                    if saved.Kind == "BasePart" then
                        if instance.LocalTransparencyModifier ~= 1 then
                            instance.LocalTransparencyModifier = 1
                        end
                        if instance.Transparency ~= 1 then
                            instance.Transparency = 1
                        end
                    elseif saved.Kind == "Texture" and instance.Transparency ~= 1 then
                        instance.Transparency = 1
                    end
                end)
            end
        end

        local currentCamera = workspace.CurrentCamera
        if currentCamera then
            pcall(function()
                if currentCamera.CameraType ~= Enum.CameraType.Custom then
                    currentCamera.CameraType = Enum.CameraType.Custom
                end
                if currentCamera.CameraSubject ~= decoyHumanoid then
                    currentCamera.CameraSubject = decoyHumanoid
                end
            end)
        end
    end

    pcall(function()
        RunService:BindToRenderStep(FarmVisual.CameraBindBefore, Enum.RenderPriority.Camera.Value - 1, maintainDecoyCamera)
        RunService:BindToRenderStep(FarmVisual.CameraBindAfter, Enum.RenderPriority.Camera.Value + 1, maintainDecoyCamera)
        maintainDecoyCamera()
    end)

    return true
end

function FarmVisual.restoreAtSafe()
    local char, hrp = getCharacter()
    if hrp and (hrp.Position - SafeZone).Magnitude > 6 then
        Move.teleSafe()
    end
    FarmVisual.cleanup()
    return hrp ~= nil
end

local function waitForArrival(part, timeout)
    timeout = math.clamp(tonumber(timeout) or 2.5, 1.0, 4.0)
    local started = os.clock()
    local char, root = getCharacter()
    if not char or not root then return false end
    local expectedCharacter = char
    local previousPosition = nil
    local stableFrames = 0
    local settleTime = 0.35 -- Точна затримка Methion для підтвердження реплікації позиції на сервері

    while _G.ItemFarm and not isShutdown and part and part.Parent and part:IsDescendantOf(workspace)
        and os.clock() - started < timeout do
        local currentChar, currentRoot = getCharacter()
        if not currentChar or currentChar ~= expectedCharacter or not currentRoot then return false end

        local targetPosition = part.Position + Vector3.new(0, 3, 0)
        if (currentRoot.Position - targetPosition).Magnitude > 0.1 then
            currentRoot.CFrame = CFrame.new(targetPosition)
        end
        zeroHrpVelocity(currentRoot)

        local currentPosition = currentRoot.Position
        local moved = previousPosition and (currentPosition - previousPosition).Magnitude or 0
        if (currentPosition - targetPosition).Magnitude <= 0.15 and moved <= 0.35 then
            stableFrames = stableFrames + 1
        else
            stableFrames = 0
        end
        previousPosition = currentPosition

        if stableFrames >= 5 then
            local settleUntil = os.clock() + settleTime
            while _G.ItemFarm and not isShutdown and part and part.Parent and part:IsDescendantOf(workspace)
                and os.clock() < settleUntil do
                local c, r = getCharacter()
                if not c or c ~= expectedCharacter or not r then return false end
                targetPosition = part.Position + Vector3.new(0, 3, 0)
                if (r.Position - targetPosition).Magnitude > 0.1 then
                    r.CFrame = CFrame.new(targetPosition)
                end
                zeroHrpVelocity(r)
                RunService.Heartbeat:Wait()
            end

            if isShutdown or not _G.ItemFarm or not part or not part.Parent or not part:IsDescendantOf(workspace) then
                return false
            end

            local finalChar, finalRoot = getCharacter()
            if not finalRoot then return false end
            targetPosition = part.Position + Vector3.new(0, 3, 0)
            if (finalRoot.Position - targetPosition).Magnitude > 0.1 then
                finalRoot.CFrame = CFrame.new(targetPosition)
                zeroHrpVelocity(finalRoot)
                RunService.Heartbeat:Wait()
            end

            return _G.ItemFarm and not isShutdown
                and player.Character == expectedCharacter
                and part.Parent ~= nil
                and part:IsDescendantOf(workspace)
                and (finalRoot.Position - (part.Position + Vector3.new(0, 3, 0))).Magnitude <= 0.8
                and (part.Position - finalRoot.Position).Magnitude <= 4.5
        end

        RunService.Heartbeat:Wait()
    end

    return false
end

-- ====================
-- АКТИВАЦІЯ ТА ЗБІР ПРЕДМЕТА
-- ====================
local function triggerPickupPrompt(prompt)
    if isShutdown or not prompt or not prompt.Parent or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    prompt.RequiresLineOfSight = false
    local oldHoldDuration = prompt.HoldDuration
    pcall(function() prompt.HoldDuration = 0 end)

    local success = false
    if fireproximityprompt then
        local ok = pcall(function() fireproximityprompt(prompt, 0, true) end)
        if not ok then
            pcall(function() fireproximityprompt(prompt, 0) end)
        end
        success = true
    end

    task.delay(0.2, function()
        if prompt and prompt.Parent and oldHoldDuration ~= nil then
            pcall(function() prompt.HoldDuration = oldHoldDuration end)
        end
    end)

    return success
end

local function farmItem(model, part, trackedData)
    if isShutdown or not part or not part.Parent or not part:IsDescendantOf(workspace) then
        if part then unregisterItem(part) end
        return false
    end

    local char, hrp = getCharacter()
    if not hrp then return false end

    local function findPrompt()
        if trackedData and trackedData.Obj and trackedData.Obj.Parent and trackedData.Obj:IsA("ProximityPrompt") then
            return trackedData.Obj
        end
        local prompt = model and model:FindFirstChildWhichIsA("ProximityPrompt", true)
            or (part and part:FindFirstChildWhichIsA("ProximityPrompt", true))
        return prompt
    end

    if _G.InstantFarm then
        -- Швидкий інстант-фарм через SafeZone телепортацію (як у 1.txt)
        if not FarmVisual.isActive() then
            moveToSafeIfNeeded()
            FarmVisual.showSafeZoneDecoy()
        end

        local moved = Move.telePart(part)
        if moved and waitForArrival(part, 2.5) then
            local prompt = findPrompt()
            if prompt and prompt.Parent and prompt.Enabled then
                for attempt = 1, 3 do
                    if isShutdown or not _G.ItemFarm or not part.Parent or not part:IsDescendantOf(workspace) then break end
                    triggerPickupPrompt(prompt)
                    task.wait(0.08)
                    if not part.Parent or not part:IsDescendantOf(workspace) or not prompt.Parent or not prompt.Enabled then
                        unregisterItem(part)
                        break
                    end
                end
            end
        end

        -- Затримка для завершення обробки підбору сервером перед поверненням у SafeZone
        task.wait(0.06)
        moveToSafeIfNeeded()
        task.wait(0.03)

        if not part.Parent or not part:IsDescendantOf(workspace) then
            unregisterItem(part)
            return true
        end
        return false
    else
        -- Звичайний плавний політ (якщо InstantFarm вимкнено)
        if FarmVisual.Decoy then
            FarmVisual.cleanup()
        end

        local arrived = flyToItem(part, _G.FlySpeed, function()
            return _G.ItemFarm and not isShutdown and part.Parent ~= nil and part:IsDescendantOf(workspace)
        end)

        if isShutdown or not _G.ItemFarm then return false end
        if not part.Parent or not part:IsDescendantOf(workspace) then
            unregisterItem(part)
            return true
        end

        task.wait(0.04)

        local prompt = findPrompt()
        if prompt and prompt.Parent and prompt.Enabled then
            for attempt = 1, 3 do
                if isShutdown or not _G.ItemFarm or not part.Parent or not part:IsDescendantOf(workspace) then break end
                triggerPickupPrompt(prompt)
                task.wait(0.12)
                if not part.Parent or not part:IsDescendantOf(workspace) or not prompt.Parent or not prompt.Enabled then
                    unregisterItem(part)
                    return true
                end
            end
        end

        if not part.Parent or not part:IsDescendantOf(workspace) then
            unregisterItem(part)
            return true
        end
        return false
    end
end

local function tryRespawn()
    if not _G.AutoRespawn or isShutdown then return end
    local char, _, hum = getCharacter()
    if hum and hum.Health <= 0 then
        local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        local remote = remotesFolder and remotesFolder:FindFirstChild("LoadCharacter")
        if remote then
            pcall(function() remote:FireServer() end)
        end
    end
end

-- =======================================================
-- ЄДИНИЙ КОНТРОЛЕР СТАНУ ITEMFARM
-- =======================================================
local itemFarmToggle

local function startFarmThread()
    if farmThreadActive or isShutdown then return end
    farmThreadActive = true
    farmSessionId    = farmSessionId + 1
    local currentSession = farmSessionId

    task.spawn(function()
        setFarmStatus("Пошук предметів...")
        while _G.ItemFarm and farmThreadActive and (farmSessionId == currentSession) and not isShutdown do
            tryRespawn()
            if isShutdown then break end
            local _, hrp = getCharacter()
            if not hrp then
                setFarmStatus("Очікування персонажа...")
                task.wait(0.5)
                continue
            end

            local item, part, data = getNearestFarmItem(hrp)
            if not item or not part then
                setFarmStatus("Очікування спавну предметів...")
                if _G.InstantFarm then
                    moveToSafeIfNeeded()
                end
                task.wait(0.25)
                continue
            end

            setFarmStatus("Збір: " .. tostring(data and data.Name or "Item"))
            local success = farmItem(item, part, data)

            if isShutdown then break end

            if not success and part and part.Parent then
                local attempts = (failedItemAttempts[part] or 0) + 1
                failedItemAttempts[part] = attempts
                if attempts >= 2 then
                    banFailedItem({ part = part, position = part.Position, name = data and data.Name }, "failed_pickup")
                    unregisterItem(part)
                    failedItemAttempts[part] = nil
                else
                    task.wait(0.1)
                end
            else
                failedItemAttempts[part] = nil
            end

            task.wait(0.04)
        end

        if farmSessionId == currentSession then
            farmThreadActive = false
            setFarmStatus("Зупинено")
            stopFlight()
            if FarmVisual.Decoy then
                FarmVisual.restoreAtSafe()
            end
        end
    end)
end

local function setItemFarmState(enabled)
    if isShutdown then return end
    _G.ItemFarm = (enabled == true)

    if itemFarmToggle and itemFarmToggle:Get() ~= _G.ItemFarm then
        itemFarmToggle:Set(_G.ItemFarm, false)
    end

    if _G.ItemFarm then
        startFarmThread()
    else
        farmSessionId    = farmSessionId + 1
        farmThreadActive = false
        setFarmStatus("Зупинено")
        stopFlight()
    end

    print(string.format("[UA Killer Hub | Farm] Стан синхронізовано: _G.ItemFarm=%s, farmThreadActive=%s",
        tostring(_G.ItemFarm), tostring(farmThreadActive)))
end

-- =======================================================
-- МАГАЗИН ТА ІВЕНТ (ВЗАЄМОДІЯ З ДІАЛОГАМИ)
-- =======================================================
local DontSell = {
    ["Lucky Arrow"] = true, ["Christmas Present"] = true,
    ["Green Candy"] = true, ["Yellow Candy"] = true,
    ["Blue Candy"]  = true, ["Red Candy"]    = true,
    ["Lucky Stone Mask"] = true,
}

local EventCandies = {
    ["Green Candy"] = true, ["Yellow Candy"] = true,
    ["Blue Candy"]  = true, ["Red Candy"]    = true,
}

local isBusy = false

local function getMerchant()
    local d = ReplicatedStorage:FindFirstChild("Dialogue")
    return d and d:FindFirstChild("Merchant")
end

local function getEventNPC()
    local d = ReplicatedStorage:FindFirstChild("Dialogue")
    return d and d:FindFirstChild("Halloween Event")
end

local function getDialogueGui()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("DialogueGui") or pg:FindFirstChild("Dialogue") or pg:FindFirstChild("DialogueBox")
end

local function isGuiElementVisible(elem)
    if not elem or not elem:IsA("GuiObject") then return false end
    if not elem.Visible then return false end
    if elem.AbsoluteSize.X <= 0 or elem.AbsoluteSize.Y <= 0 then return false end

    local current = elem.Parent
    while current and current:IsA("GuiObject") do
        if not current.Visible then return false end
        current = current.Parent
    end

    local screenGui = elem:FindFirstAncestorWhichIsA("ScreenGui")
    if screenGui and not screenGui.Enabled then return false end

    return true
end

local function isItemSold(item)
    if not item or not item.Parent or not item:IsDescendantOf(game) then return true end
    local char    = player.Character
    local backpack = player:FindFirstChild("Backpack")
    if (backpack and item:IsDescendantOf(backpack)) or (char and item:IsDescendantOf(char)) then
        return false
    end
    return true
end

local function autoClickDialogueButtons()
    local gui = getDialogueGui()
    if not gui or isShutdown then return end
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then txt = childText.Text end
            local lower = txt:lower()
            if lower:find("sell this") or lower:find("i'd like to sell") or lower:find("deal") or lower:find("all") then
                pcall(function()
                    if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                    else btn.Activated:Fire() end
                end)
            end
        end
    end
end

local function closeMerchantDialogue()
    local char   = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")
    pcall(function()
        if remote then
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("DialogueEnd", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("EndDialogue", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Merchant" })
        end
    end)
    local gui = getDialogueGui()
    if gui then
        pcall(function()
            for _, btn in ipairs(gui:GetDescendants()) do
                if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
                    local txt = btn.Text or ""
                    local childText = btn:FindFirstChildOfClass("TextLabel")
                    if childText and childText.Text ~= "" then txt = childText.Text end
                    local lower = txt:lower()
                    if lower:find("nevermind") or lower:find("nothing") or lower:find("bye") or lower:find("leave") or lower:find("no") or lower:find("exit") or lower:find("close") or lower:find("goodbye") then
                        if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                        else btn.Activated:Fire() end
                    end
                end
            end
        end)
        task.wait(0.12)
        if gui:IsA("ScreenGui") and gui.Enabled then pcall(function() gui.Enabled = false end) end
    end
    forceUnequipAllTools()
end

local function sellSingleItem(item)
    if isShutdown then return false, "Shutdown" end
    if not item or isItemSold(item) or DontSell[item.Name] then return true, "AlreadySold" end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()
    if not hum or not remote or not merchant then return false, "MissingCharacterOrNPC" end

    hum:EquipTool(item)
    local equipTimeout = tick() + 0.8
    while tick() < equipTimeout and item.Parent ~= char and not isShutdown do task.wait(0.04) end
    if item.Parent ~= char or isShutdown then return false, "EquipTimeoutOrShutdown" end

    task.wait(0.12)
    if isShutdown then return false, "Shutdown" end
    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.12)
    autoClickDialogueButtons()

    if isShutdown then return false, "Shutdown" end
    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue1", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    if isShutdown then return false, "Shutdown" end
    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    local sellTimeout = tick() + 1.2
    while tick() < sellTimeout and not isShutdown do
        if isItemSold(item) then break end
        autoClickDialogueButtons()
        task.wait(0.08)
    end

    pcall(function()
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
        remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
        remote:FireServer("DialogueEnd",  { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
    end)
    task.wait(0.1)

    if hum then
        pcall(function() hum:UnequipTools() end)
    end
    forceUnequipAllTools()

    return isItemSold(item), isItemSold(item) and "Success" or "ItemStillExists"
end

local function sellSingleItemWithRetries(item, maxRetries)
    if isShutdown then return false, "Shutdown" end
    maxRetries = maxRetries or 3
    local lastError = "Unknown"
    for attempt = 1, maxRetries do
        if isShutdown then return false, "Shutdown" end
        if isItemSold(item) then return true, "Success" end
        local ok, errStage = sellSingleItem(item)
        if ok then return true, "Success" end
        lastError = errStage
        task.wait(0.2)
    end
    return false, lastError
end

-- =======================================================
-- СИСТЕМА ФІКСОВАНОГО ЗНІМКА (SNAPSHOT) ТА ЦИКЛУ ПРОДАЖУ
-- =======================================================
local autoSellToggle       = nil
local autoSellThreadActive = false
local autoSellSessionId    = 0
local FARM_CYCLE_DURATION  = 100 -- 100 секунд фарму перед кожним продажем

local function getSellableSnapshot()
    local snapshot = {}
    local seen = {}

    local function collect(container)
        if not container or isShutdown then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] and not isItemSold(item) and not seen[item] then
                seen[item] = true
                table.insert(snapshot, item)
            end
        end
    end

    collect(player:FindFirstChild("Backpack"))
    collect(player.Character)
    return snapshot
end

local function startAutoSellThread()
    if autoSellThreadActive or isShutdown then return end
    autoSellThreadActive = true
    autoSellSessionId    = autoSellSessionId + 1
    local currentSession = autoSellSessionId

    task.spawn(function()
        print(string.format("[UA Killer Hub | AutoSell] Потік запущено. Фарм триває %d с перед першим продажем...", FARM_CYCLE_DURATION))

        while _G.AutoSell and autoSellThreadActive and (autoSellSessionId == currentSession) and not isShutdown do
            local elapsed = 0
            while elapsed < FARM_CYCLE_DURATION and _G.AutoSell and (autoSellSessionId == currentSession) and not isShutdown do
                task.wait(1)
                elapsed = elapsed + 1
            end

            if not _G.AutoSell or (autoSellSessionId ~= currentSession) or isShutdown then break end

            while isBusy and _G.AutoSell and (autoSellSessionId == currentSession) and not isShutdown do
                task.wait(0.2)
            end

            if not _G.AutoSell or (autoSellSessionId ~= currentSession) or isShutdown then break end

            isBusy = true

            local snapshot = getSellableSnapshot()

            if #snapshot > 0 and not isShutdown then
                print(string.format("[UA Killer Hub | AutoSell] Створено snapshot: %d предметів. Початок продажу (Farm працює паралельно)...", #snapshot))
                for _, item in ipairs(snapshot) do
                    if not _G.AutoSell or (autoSellSessionId ~= currentSession) or isShutdown then break end
                    if not isItemSold(item) and not DontSell[item.Name] then
                        sellSingleItemWithRetries(item, 3)
                        task.wait(0.15)
                    end
                end
                if not isShutdown then
                    closeMerchantDialogue()
                end
                print("[UA Killer Hub | AutoSell] Продаж поточного snapshot повністю завершено!")
            else
                if not isShutdown then
                    print("[UA Killer Hub | AutoSell] Snapshot порожній: предметів для продажу немає.")
                end
            end

            isBusy = false

            if _G.AutoSell and (autoSellSessionId == currentSession) and not isShutdown then
                print(string.format("[UA Killer Hub | AutoSell] Запуск наступного 100-секундного циклу фарму.", FARM_CYCLE_DURATION))
            end
        end

        if autoSellSessionId == currentSession then
            autoSellThreadActive = false
            isBusy               = false
            if not isShutdown then
                closeMerchantDialogue()
            end
            print("[UA Killer Hub | AutoSell] Потік автопродажу повністю зупинено.")
        end
    end)
end

local function setAutoSellState(enabled)
    if isShutdown then return end
    _G.AutoSell = (enabled == true)

    if autoSellToggle and autoSellToggle:Get() ~= _G.AutoSell then
        autoSellToggle:Set(_G.AutoSell, false)
    end

    if _G.AutoSell then
        startAutoSellThread()
    else
        autoSellSessionId    = autoSellSessionId + 1
        autoSellThreadActive = false
        isBusy               = false
        closeMerchantDialogue()
    end

    print(string.format("[UA Killer Hub | AutoSell] Стан синхронізовано: _G.AutoSell=%s, Active=%s",
        tostring(_G.AutoSell), tostring(autoSellThreadActive)))
end

-- ====================
-- ЛОГІКА ХЕЛОВІНСЬКИХ ЦУКЕРОК
-- ====================
local function countTotalCandies()
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return 0 end
    local count = 0
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and EventCandies[item.Name] then count += 1 end
    end
    return count
end

local function clickEventCandyOption()
    local gui = getDialogueGui()
    if not gui or isShutdown then return false end
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then txt = childText.Text end
            local lowerTxt = txt:lower()
            if lowerTxt:find("turn in") or (lowerTxt:find("candy") and not lowerTxt:find("what do i do") and not lowerTxt:find("could you please")) then
                pcall(function()
                    if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                    else btn.Activated:Fire() end
                end)
                return true
            end
        end
    end
    return false
end

local function findJackDialogue()
    local gui = getDialogueGui()
    if not gui or isShutdown then return nil end

    local isGuiEnabled = (gui:IsA("ScreenGui") and gui.Enabled) or gui.Visible
    if not isGuiEnabled then return nil end

    local hasJack      = false
    local hasPoints    = false
    local continueElem = nil
    local pointsElem   = nil
    local dialogueBox  = nil
    local anyButton    = nil

    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            if isGuiElementVisible(desc) then
                local txt   = desc.Text or ""
                local lower = txt:lower()

                if lower:find("jack") or lower:find("cauldron specter") then hasJack = true end
                if lower:find("point") then
                    hasPoints = true
                    pointsElem = desc
                    if desc.Parent and desc.Parent:IsA("GuiObject") and desc.Parent.AbsoluteSize.Y > 40 then
                        dialogueBox = desc.Parent
                    end
                end
                if lower:find("click to continue") or (lower:find("continue") and not lower:find("option")) then
                    continueElem = desc
                end
            end
        end

        if desc:IsA("GuiButton") and isGuiElementVisible(desc) then
            anyButton = desc
        end

        if not dialogueBox and desc:IsA("Frame") and isGuiElementVisible(desc) and desc.AbsoluteSize.Y > 60 then
            dialogueBox = desc
        end
    end

    if (hasJack or hasPoints) and (pointsElem or continueElem or dialogueBox) then
        return {
            gui          = gui,
            hasJack      = hasJack,
            hasPoints    = hasPoints,
            continueElem = continueElem,
            pointsElem   = pointsElem,
            dialogueBox  = dialogueBox or (pointsElem and pointsElem.Parent) or (continueElem and continueElem.Parent),
            anyButton    = anyButton,
        }
    end
    return nil
end

local function clickContinueButton(jackData)
    if not jackData or isShutdown then return end

    pcall(function()
        local targetBtn = (jackData.continueElem and jackData.continueElem:IsA("GuiButton") and jackData.continueElem)
            or (jackData.continueElem and jackData.continueElem.Parent and jackData.continueElem.Parent:IsA("GuiButton") and jackData.continueElem.Parent)
            or jackData.anyButton

        if targetBtn then
            if firesignal then
                firesignal(targetBtn.MouseButton1Click)
                firesignal(targetBtn.Activated)
            else
                targetBtn.Activated:Fire()
            end
        end

        local targetBox = jackData.dialogueBox or (jackData.pointsElem and jackData.pointsElem.Parent) or jackData.pointsElem
        if VirtualInputManager and targetBox and targetBox:IsA("GuiObject") and not isShutdown then
            local absPos = targetBox.AbsolutePosition
            local absSize = targetBox.AbsoluteSize
            local clickX = absPos.X + absSize.X / 2
            local clickY = absPos.Y + absSize.Y / 2

            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end

        if VirtualInputManager and jackData.continueElem and jackData.continueElem:IsA("GuiObject") and jackData.continueElem ~= targetBox and not isShutdown then
            local absPos = jackData.continueElem.AbsolutePosition
            local absSize = jackData.continueElem.AbsoluteSize
            local clickX = absPos.X + absSize.X / 2
            local clickY = absPos.Y + absSize.Y / 2

            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end
    end)
end

local function submitAllCandies()
    if isShutdown then return false end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not remote or not hum or not eventNPC then return false end

    local success = false
    pcall(function()
        remote:FireServer("PromptTriggered", eventNPC)

        local optionFound   = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy and not isShutdown do
            if clickEventCandyOption() then optionFound = true break end
            task.wait(0.15)
        end
        if not optionFound or isShutdown then return end

        local pointsFound   = false
        local jackData      = nil
        local pointsTimeout = tick() + 4.0
        while tick() < pointsTimeout and _G.AutoEventCandy and not isShutdown do
            jackData = findJackDialogue()
            if jackData and jackData.hasPoints then
                pointsFound = true
                break
            end
            task.wait(0.15)
        end
        if not pointsFound or not jackData or isShutdown then return end

        task.wait(0.35)
        if isShutdown then return end
        clickContinueButton(jackData)

        local closeTimeout = tick() + 2.0
        local isClosed     = false
        while tick() < closeTimeout and not isShutdown do
            task.wait(0.15)
            if not findJackDialogue() then
                isClosed = true
                break
            end
        end

        if isClosed then
            success = true
        else
            local retryData = findJackDialogue()
            if retryData and not isShutdown then
                clickContinueButton(retryData)
                task.wait(0.3)
                if not findJackDialogue() then success = true end
            end
        end
    end)
    return success
end

task.spawn(function()
    while not isShutdown do
        task.wait(0.5)
        if isShutdown then break end
        if isBusy then continue end

        if _G.AutoEventCandy and countTotalCandies() >= 10 then
            isBusy = true
            closeMerchantDialogue()
            while countTotalCandies() > 0 and _G.AutoEventCandy and not isShutdown do
                submitAllCandies()
                task.wait(0.5)
            end
            isBusy = false
        end
    end
end)

task.spawn(function()
    while not isShutdown do
        task.wait(0.5)
        if isShutdown then break end
        for i = #Pending, 1, -1 do
            local e = Pending[i]
            if e and e.obj and e.obj:IsDescendantOf(game) and isValidPosition(e.part) then
                table.remove(Pending, i)
                if not Tracked[e.part] then registerItem(e.obj) end
            elseif not e or not e.obj or not e.obj:IsDescendantOf(game) then
                table.remove(Pending, i)
            end
        end
    end
end)

local function applyJumpPower()
    if isShutdown then return end
    local _, _, hum = getCharacter()
    if hum then hum.JumpPower = JP_Value end
end

trackConnection(player.CharacterAdded:Connect(function(newChar)
    if isShutdown then return end
    task.wait(0.5)
    if isShutdown then return end
    applyJumpPower()
end))

task.spawn(function()
    while not isShutdown do
        task.wait(0.2)
        if isShutdown then break end
        applyJumpPower()
    end
end)

task.spawn(function()
    while not isShutdown do
        task.wait(0.8)
        if isShutdown then break end
        if _G.ItemESP then
            for part, gui in pairs(espObjects) do
                if not part or not part.Parent or not part:IsDescendantOf(workspace) then
                    if gui then pcall(function() gui:Destroy() end) end
                    espObjects[part] = nil
                end
            end
            for part, data in pairs(Tracked) do
                if isShutdown or not _G.ItemESP then break end
                if part and part.Parent and isValidPosition(part) and not isPartInvisible(part) and not isPlayerOwned(part) then
                    applyESP(part, data.Name)
                end
            end
        else
            clearESP()
        end
    end
end)

-- =======================================================
-- БЕЗПЕЧНЕ СТВОРЕННЯ MONHUB GUI
-- =======================================================
print("[UA Killer Hub | GUI] Початок створення графічного інтерфейсу...")

local function getSafeGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then
        local testOk = pcall(function()
            local f = Instance.new("Folder", core)
            f:Destroy()
        end)
        if testOk then return core end
    end
    return player:WaitForChild("PlayerGui", 5) or player:FindFirstChildOfClass("PlayerGui")
end

local targetGuiParent = getSafeGuiParent()

pcall(function()
    if targetGuiParent then
        local old = targetGuiParent:FindFirstChild("UAKillerHub_GUI")
        if old then old:Destroy() end
    end
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        local oldPg = pg:FindFirstChild("UAKillerHub_GUI")
        if oldPg then oldPg:Destroy() end
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "UAKillerHub_GUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = targetGuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 520, 0.5, -300)
MainFrame.Position         = UDim2.new(0.5, -260, 0, 100)
MainFrame.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
MainFrame.BorderSizePixel  = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent       = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color     = Color3.fromRGB(38, 42, 53)
MainStroke.Thickness = 1
MainStroke.Parent    = MainFrame

local ToastContainer = Instance.new("Frame")
ToastContainer.Name                  = "ToastContainer"
ToastContainer.Size                  = UDim2.new(0, 240, 1, -20)
ToastContainer.Position              = UDim2.new(1, -250, 0, 10)
ToastContainer.BackgroundTransparency = 1
ToastContainer.Parent                = ScreenGui

local ToastList = Instance.new("UIListLayout")
ToastList.Padding             = UDim.new(0, 6)
ToastList.SortOrder           = Enum.SortOrder.LayoutOrder
ToastList.VerticalAlignment   = Enum.VerticalAlignment.Bottom
ToastList.HorizontalAlignment = Enum.HorizontalAlignment.Center
ToastList.Parent              = ToastContainer

local function showNotification(title, message, duration)
    if isShutdown or not ToastContainer or not ToastContainer.Parent then return end
    duration = duration or 3
    local toast = Instance.new("Frame")
    toast.Size             = UDim2.new(1, 0, 0, 0)
    toast.BackgroundColor3 = Color3.fromRGB(27, 30, 38)
    toast.BorderSizePixel  = 0
    toast.ClipsDescendants = true
    toast.Parent           = ToastContainer

    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", toast)
    stroke.Color       = Color3.fromRGB(139, 124, 246)
    stroke.Thickness   = 1
    stroke.Transparency = 1

    local titleLbl = Instance.new("TextLabel", toast)
    titleLbl.Size                  = UDim2.new(1, -16, 0, 20)
    titleLbl.Position              = UDim2.new(0, 10, 0, 6)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = title
    titleLbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    titleLbl.Font                  = Enum.Font.GothamBold
    titleLbl.TextSize              = 13
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left
    titleLbl.TextTransparency      = 1

    local msgLbl = Instance.new("TextLabel", toast)
    msgLbl.Size                  = UDim2.new(1, -16, 0, 22)
    msgLbl.Position              = UDim2.new(0, 10, 0, 26)
    msgLbl.BackgroundTransparency = 1
    msgLbl.Text                  = message
    msgLbl.TextColor3            = Color3.fromRGB(200, 205, 215)
    msgLbl.Font                  = Enum.Font.Gotham
    msgLbl.TextSize              = 11
    msgLbl.TextXAlignment        = Enum.TextXAlignment.Left
    msgLbl.TextTransparency      = 1

    TweenService:Create(toast,    TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 55) }):Play()
    TweenService:Create(stroke,   TweenInfo.new(0.2), { Transparency = 0 }):Play()
    TweenService:Create(titleLbl, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
    TweenService:Create(msgLbl,   TweenInfo.new(0.2), { TextTransparency = 0 }):Play()

    task.delay(duration, function()
        pcall(function()
            if isShutdown or not toast.Parent then return end
            TweenService:Create(toast,    TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 0) }):Play()
            TweenService:Create(stroke,   TweenInfo.new(0.2), { Transparency = 1 }):Play()
            TweenService:Create(titleLbl, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
            local tw = TweenService:Create(msgLbl, TweenInfo.new(0.2), { TextTransparency = 1 })
            tw:Play()
            tw.Completed:Wait()
            toast:Destroy()
        end)
    end)
end

-- =======================================================
-- ЄДИНА ФУНКЦІЯ ПОВНОГО ВИМКНЕННЯ СКРИПТА (SHUTDOWN)
-- =======================================================
local function shutdownScript()
    if isShutdown then return end
    isShutdown = true
    print("[UA Killer Hub] Ініціалізація повного вимкнення скрипта (Shutdown)...")

    _G.ItemFarm         = false
    _G.AutoSell         = false
    _G.AutoEventCandy   = false
    _G.AutoBuy          = false
    _G.ItemESP          = false
    _G.AntiAFK          = false
    _G.StandaloneNoClip = false
    _G.AutoRespawn      = false
    _G.InstantFarm      = false

    farmSessionId        = farmSessionId + 1
    farmThreadActive     = false
    autoSellSessionId    = autoSellSessionId + 1
    autoSellThreadActive = false
    isBusy               = false

    pcall(stopFlight)
    pcall(cleanupFlight)
    pcall(clearESP)
    pcall(closeMerchantDialogue)
    pcall(forceUnequipAllTools)
    if FarmVisual.Decoy then
        pcall(FarmVisual.cleanup)
    end

    if noclipConnection then
        pcall(function() noclipConnection:Disconnect() end)
        noclipConnection = nil
    end
    if antiAfkConnection then
        pcall(function() antiAfkConnection:Disconnect() end)
        antiAfkConnection = nil
    end

    for _, conn in ipairs(scriptConnections) do
        pcall(function()
            if conn and conn.Connected then
                conn:Disconnect()
            end
        end)
    end
    table.clear(scriptConnections)

    pcall(function()
        local char = player.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.JumpPower = 50
            end
        end
    end)

    pcall(function()
        for _, obj in ipairs(player:GetChildren()) do
            if obj.Name == "YBA_VirtualCFrame" then
                obj:Destroy()
            end
        end
    end)

    pcall(function()
        if ScreenGui then
            ScreenGui:Destroy()
        end
    end)

    print("[UA Killer Hub] Скрипт успішно та повністю вимкнено.")
end

-- Верхня панель
local TitleBar = Instance.new("Frame")
TitleBar.Name             = "TitleBar"
TitleBar.Size             = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(19, 21, 26)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = MainFrame

Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TitleLine = Instance.new("Frame", TitleBar)
TitleLine.Size             = UDim2.new(1, 0, 0, 1)
TitleLine.Position         = UDim2.new(0, 0, 1, -1)
TitleLine.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
TitleLine.BorderSizePixel  = 0

local TitleText = Instance.new("TextLabel", TitleBar)
TitleText.Size             = UDim2.new(0, 140, 1, 0)
TitleText.Position         = UDim2.new(0, 14, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text             = "UA Killer Hub"
TitleText.Font             = Enum.Font.GothamBold
TitleText.TextSize         = 14
TitleText.TextColor3       = Color3.fromRGB(240, 242, 245)
TitleText.TextXAlignment   = Enum.TextXAlignment.Left

local Badge = Instance.new("TextLabel", TitleBar)
Badge.Size             = UDim2.new(0, 36, 0, 18)
Badge.Position         = UDim2.new(0, 126, 0.5, -9)
Badge.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
Badge.Text             = "YBA"
Badge.Font             = Enum.Font.GothamBold
Badge.TextSize         = 10
Badge.TextColor3       = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", Badge).CornerRadius = UDim.new(0, 4)

local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size             = UDim2.new(0, 26, 0, 26)
CloseBtn.Position         = UDim2.new(1, -34, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
CloseBtn.Text             = "✕"
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.TextSize         = 12
CloseBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local MinBtn = Instance.new("TextButton", TitleBar)
MinBtn.Size             = UDim2.new(0, 26, 0, 26)
MinBtn.Position         = UDim2.new(1, -66, 0.5, -13)
MinBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
MinBtn.Text             = "—"
MinBtn.Font             = Enum.Font.GothamBold
MinBtn.TextSize         = 12
MinBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

local dragging, dragInput, dragStart, startPos
trackConnection(TitleBar.InputBegan:Connect(function(input)
    if isShutdown then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = MainFrame.Position
        local chConn
        chConn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End or isShutdown then
                dragging = false
                if chConn then chConn:Disconnect() end
            end
        end)
        trackConnection(chConn)
    end
end))

trackConnection(TitleBar.InputChanged:Connect(function(input)
    if isShutdown then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end))

trackConnection(UserInputService.InputChanged:Connect(function(input)
    if isShutdown then return end
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        if MainFrame and MainFrame.Parent then
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end
end))

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    if isShutdown then return end
    isMinimized = not isMinimized
    local targetSize = isMinimized and UDim2.new(0, 520, 0, 42) or UDim2.new(0, 520, 0, 400)
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = targetSize }):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    shutdownScript()
end)

trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if isShutdown then return end
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        if MainFrame and MainFrame.Parent then
            MainFrame.Visible = not MainFrame.Visible
        end
    end
end))

-- Сайдбар
local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Name             = "Sidebar"
Sidebar.Size             = UDim2.new(0, 130, 1, -42)
Sidebar.Position         = UDim2.new(0, 0, 0, 42)
Sidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
Sidebar.BorderSizePixel  = 0

local SidebarList = Instance.new("UIListLayout", Sidebar)
SidebarList.Padding             = UDim.new(0, 6)
SidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarList.SortOrder           = Enum.SortOrder.LayoutOrder

local SidebarPad = Instance.new("UIPadding", Sidebar)
SidebarPad.PaddingTop   = UDim.new(0, 12)
SidebarPad.PaddingLeft  = UDim.new(0, 6)
SidebarPad.PaddingRight = UDim.new(0, 6)

-- Контентна панель
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Name                  = "ContentArea"
ContentArea.Size                  = UDim2.new(1, -130, 1, -42)
ContentArea.Position              = UDim2.new(0, 130, 0, 42)
ContentArea.BackgroundTransparency = 1

local SearchFrame = Instance.new("Frame", ContentArea)
SearchFrame.Name             = "SearchFrame"
SearchFrame.Size             = UDim2.new(1, -24, 0, 32)
SearchFrame.Position         = UDim2.new(0, 12, 0, 10)
SearchFrame.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
SearchFrame.BorderSizePixel  = 0
Instance.new("UICorner", SearchFrame).CornerRadius = UDim.new(0, 6)

local SearchIcon = Instance.new("TextLabel", SearchFrame)
SearchIcon.Size                  = UDim2.new(0, 24, 1, 0)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Text                  = "🔍"
SearchIcon.Font                  = Enum.Font.Gotham
SearchIcon.TextSize              = 11
SearchIcon.TextColor3            = Color3.fromRGB(150, 155, 165)

local SearchBox = Instance.new("TextBox", SearchFrame)
SearchBox.Size                  = UDim2.new(1, -30, 1, 0)
SearchBox.Position              = UDim2.new(0, 28, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.PlaceholderText       = "Пошук функцій..."
SearchBox.PlaceholderColor3     = Color3.fromRGB(110, 115, 130)
SearchBox.TextColor3            = Color3.fromRGB(240, 242, 245)
SearchBox.Font                  = Enum.Font.Gotham
SearchBox.TextSize              = 12
SearchBox.TextXAlignment        = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus      = false

local PagesFolder = Instance.new("Folder", ContentArea)
PagesFolder.Name = "Pages"

local tabs      = {}
local activeTab = nil

local function filterItems(query)
    if isShutdown then return end
    query = query:lower()
    for _, item in ipairs(uiElementsRegistry) do
        if item.Page == activeTab and item.Frame and item.Frame.Parent then
            item.Frame.Visible = (query == "" or item.Name:lower():find(query, 1, true) ~= nil)
        end
    end
end

trackConnection(SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if isShutdown then return end
    filterItems(SearchBox.Text)
end))

local function switchTab(tabName)
    if isShutdown then return end
    activeTab    = tabName
    SearchBox.Text = ""
    for name, tabData in pairs(tabs) do
        local active = (name == tabName)
        if tabData.Page and tabData.Page.Parent then
            tabData.Page.Visible = active
        end
        if tabData.Button and tabData.Button.Parent then
            TweenService:Create(tabData.Button, TweenInfo.new(0.2), {
                BackgroundColor3 = active and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(23, 25, 32),
                TextColor3       = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 165),
            }):Play()
        end
    end
    filterItems("")
end

local function createTab(tabName, iconText)
    local btn = Instance.new("TextButton", Sidebar)
    btn.Name             = tabName .. "_Tab"
    btn.Size             = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Color3.fromRGB(23, 25, 32)
    btn.Text             = (iconText or "•") .. "  " .. tabName
    btn.Font             = Enum.Font.GothamMedium
    btn.TextSize         = 12
    btn.TextColor3       = Color3.fromRGB(150, 155, 165)
    btn.TextXAlignment   = Enum.TextXAlignment.Left
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIPadding", btn).PaddingLeft = UDim.new(0, 10)

    local page = Instance.new("ScrollingFrame", PagesFolder)
    page.Name                = tabName .. "_Page"
    page.Size                = UDim2.new(1, -24, 1, -56)
    page.Position            = UDim2.new(0, 12, 0, 48)
    page.BackgroundTransparency = 1
    page.BorderSizePixel     = 0
    page.ScrollBarThickness  = 3
    page.ScrollBarImageColor3 = Color3.fromRGB(139, 124, 246)
    page.CanvasSize          = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible             = false

    local list = Instance.new("UIListLayout", page)
    list.Padding   = UDim.new(0, 8)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    local pad = Instance.new("UIPadding", page)
    pad.PaddingRight  = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 10)

    tabs[tabName] = { Button = btn, Page = page }
    trackConnection(btn.MouseButton1Click:Connect(function() switchTab(tabName) end))
    return page
end

local function createSection(page, tabName, text)
    local sec = Instance.new("Frame", page)
    sec.Size                  = UDim2.new(1, 0, 0, 24)
    sec.BackgroundTransparency = 1

    local lbl = Instance.new("TextLabel", sec)
    lbl.Size                  = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = text:upper()
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 10
    lbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = sec })
    return sec
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local toggleState = (defaultVal == true)

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -56, 1, 0)
    titleLbl.Position              = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 12
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local switch = Instance.new("TextButton", card)
    switch.Size             = UDim2.new(0, 36, 0, 20)
    switch.Position         = UDim2.new(1, -44, 0.5, -10)
    switch.BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58)
    switch.Text             = ""
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", switch)
    knob.Size             = UDim2.new(0, 14, 0, 14)
    knob.Position         = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function setState(val, triggerCallback)
        if isShutdown then return end
        toggleState = (val == true)
        if switch.Parent then
            TweenService:Create(switch, TweenInfo.new(0.2), {
                BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58),
            }):Play()
        end
        if knob.Parent then
            TweenService:Create(knob, TweenInfo.new(0.2), {
                Position = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
            }):Play()
        end
        if triggerCallback and callback and not isShutdown then callback(toggleState) end
    end

    trackConnection(switch.MouseButton1Click:Connect(function()
        if isShutdown then return end
        setState(not toggleState, true)
    end))

    local controlObj = {
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, val, triggerCallback)
            if isShutdown then return end
            if triggerCallback == nil then triggerCallback = true end
            setState(val, triggerCallback)
        end,
        Get   = function() return toggleState end,
    }
    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createSlider(page, tabName, text, min, max, step, defaultVal, callback)
    local currentVal = defaultVal or min

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 48)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -60, 0, 20)
    titleLbl.Position              = UDim2.new(0, 12, 0, 4)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 12
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local valLabel = Instance.new("TextLabel", card)
    valLabel.Size                  = UDim2.new(0, 46, 0, 20)
    valLabel.Position              = UDim2.new(1, -54, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Text                  = tostring(currentVal)
    valLabel.Font                  = Enum.Font.GothamBold
    valLabel.TextSize              = 11
    valLabel.TextColor3            = Color3.fromRGB(139, 124, 246)
    valLabel.TextXAlignment        = Enum.TextXAlignment.Right

    local bar = Instance.new("TextButton", card)
    bar.Size             = UDim2.new(1, -24, 0, 6)
    bar.Position         = UDim2.new(0, 12, 0, 32)
    bar.BackgroundColor3 = Color3.fromRGB(42, 46, 58)
    bar.Text             = ""
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", bar)
    fill.Size             = UDim2.new(math.clamp((currentVal - min) / (max - min), 0, 1), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel  = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local draggingSlider = false

    local function updateFromPos(x)
        if isShutdown then return end
        local rel     = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local raw     = min + (max - min) * rel
        local stepped = math.floor(raw / step + 0.5) * step
        if step < 1 then stepped = tonumber(string.format("%.1f", stepped)) end
        currentVal    = math.clamp(stepped, min, max)
        valLabel.Text = tostring(currentVal)
        fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
        if callback and not isShutdown then callback(currentVal) end
    end

    trackConnection(bar.InputBegan:Connect(function(input)
        if isShutdown then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            updateFromPos(input.Position.X)
        end
    end))

    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end))

    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if isShutdown then draggingSlider = false return end
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromPos(input.Position.X)
        end
    end))

    local controlObj = {
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, val, triggerCallback)
            if isShutdown then return end
            val = tonumber(val)
            if not val then return end
            if triggerCallback == nil then triggerCallback = true end
            currentVal    = math.clamp(val, min, max)
            valLabel.Text = tostring(currentVal)
            fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
            if triggerCallback and callback and not isShutdown then callback(currentVal) end
        end,
        Get   = function() return currentVal end,
    }
    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createButton(page, tabName, text, callback)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local btn = Instance.new("TextButton", card)
    btn.Size                  = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text                  = text
    btn.Font                  = Enum.Font.GothamMedium
    btn.TextSize              = 12
    btn.TextColor3            = Color3.fromRGB(240, 242, 245)

    trackConnection(btn.MouseEnter:Connect(function()
        if isShutdown then return end
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(36, 40, 52) }):Play()
    end))
    trackConnection(btn.MouseLeave:Connect(function()
        if isShutdown then return end
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
    end))
    trackConnection(btn.MouseButton1Click:Connect(function()
        if isShutdown then return end
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        task.wait(0.08)
        if isShutdown then return end
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
        if callback and not isShutdown then callback() end
    end))

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return btn
end

local function createStatusLabel(page, tabName, initialText)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 34)
    card.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", card)
    stroke.Color     = Color3.fromRGB(42, 46, 58)
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel", card)
    lbl.Size                  = UDim2.new(1, -20, 1, 0)
    lbl.Position              = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = initialText
    lbl.Font                  = Enum.Font.GothamMedium
    lbl.TextSize              = 12
    lbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    table.insert(uiElementsRegistry, { Name = "Статус", Page = tabName, Frame = card })
    return { Set = function(self, txt) if not isShutdown and lbl.Parent then lbl.Text = txt end end }
end

-- =======================================================
-- СТОРІНКИ ТА ЕЛЕМЕНТИ UI
-- =======================================================
local mainPage = createTab("Головна",  "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин",  "🛒")
local miscPage = createTab("Інше",     "⚙")

local autoLoadToggle, jumpPowerSlider, flySpeedSlider
local itemEspToggle, autoCandyToggle, instantFarmToggle
local autoBuyToggle, antiAfkToggle, noclipToggle, autoRespawnToggle
local itemToggleControls = {}

local saveCurrentConfig, loadCurrentConfig

-- ── Головна ──────────────────────────────────────────────
createSection(mainPage, "Головна", "Конфігурація")

autoLoadToggle = createToggle(mainPage, "Головна", "Автозавантаження при старті", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    pcall(function()
        if writefile then writefile(autoLoadFile, tostring(value)) end
    end)
    print("[UA Killer Hub | Config] Автозавантаження збережено: " .. tostring(value))
end)

createButton(mainPage, "Головна", "Завантажити конфіг вручну", function()
    if loadCurrentConfig and not isShutdown then loadCurrentConfig(false) end
end)

createButton(mainPage, "Головна", "Зберегти поточний конфіг", function()
    if saveCurrentConfig and not isShutdown then saveCurrentConfig() end
end)

createSection(mainPage, "Головна", "Характеристики")

jumpPowerSlider = createSlider(mainPage, "Головна", "Висота стрибка (JumpPower)", 50, 200, 1, JP_Value, function(val)
    JP_Value = val
    applyJumpPower()
end)

-- ── Автофарм ─────────────────────────────────────────────
createSection(farmPage, "Автофарм", "Параметри збору")

local statusLabel = createStatusLabel(farmPage, "Автофарм", "Статус: Очікування...")
task.spawn(function()
    while not isShutdown do
        task.wait(0.35)
        if isShutdown then break end
        pcall(function() statusLabel:Set("Статус: " .. farmStatusText) end)
    end
end)

flySpeedSlider = createSlider(farmPage, "Автофарм", "Швидкість польоту (FlySpeed)", 50, 300, 5, _G.FlySpeed, function(val)
    _G.FlySpeed = val
end)

instantFarmToggle = createToggle(farmPage, "Автофарм", "Інстант фарм (SafeZone Methion)", _G.InstantFarm, function(value)
    manuallyChanged.InstantFarm = true
    _G.InstantFarm = value
    if not value and FarmVisual.Decoy then
        FarmVisual.restoreAtSafe()
    end
end)

itemEspToggle = createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    manuallyChanged.ItemESP = true
    _G.ItemESP = val
end)

itemFarmToggle = createToggle(farmPage, "Автофарм", "Увімкнути автофарм", _G.ItemFarm, function(value)
    manuallyChanged.ItemFarm = true
    setItemFarmState(value)
end)

createSection(farmPage, "Автофарм", "Фільтр предметів")

createButton(farmPage, "Автофарм", "Увімкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = true
        if itemToggleControls[name] then itemToggleControls[name]:Set(true, false) end
    end
end)

createButton(farmPage, "Автофарм", "Вимкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = false
        if itemToggleControls[name] then itemToggleControls[name]:Set(false, false) end
    end
end)

local sortedItems = {}
for name in pairs(_G.SelectedItems) do table.insert(sortedItems, name) end
table.sort(sortedItems)

for _, itemName in ipairs(sortedItems) do
    local ctrl = createToggle(farmPage, "Автофарм", itemName, _G.SelectedItems[itemName], function(val)
        _G.SelectedItems[itemName] = val
    end)
    itemToggleControls[itemName] = ctrl
end

-- ── Магазин ──────────────────────────────────────────────
createSection(shopPage, "Магазин", "Торгівля та івенти")

autoSellToggle = createToggle(shopPage, "Магазин", "Автопродаж (100с Farm -> Sell)", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    setAutoSellState(value)
end)

autoCandyToggle = createToggle(shopPage, "Магазин", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = value
end)

autoBuyToggle = createToggle(shopPage, "Магазин", "Автокупівля (Lucky Arrow)", _G.AutoBuy, function(value)
    if isShutdown then return end
    manuallyChanged.AutoBuy = true
    _G.AutoBuy = value
    if value then
        task.spawn(function()
            while _G.AutoBuy and not isShutdown do
                local char   = player.Character
                local remote = char and char:FindFirstChild("RemoteEvent")
                if remote and not isShutdown then
                    remote:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
                end
                local waitSec = 2.5 + math.random() * 1.5
                local waited = 0
                while waited < waitSec and _G.AutoBuy and not isShutdown do
                    task.wait(0.2)
                    waited = waited + 0.2
                end
            end
        end)
    end
end)

-- ── Інше ─────────────────────────────────────────────────
createSection(miscPage, "Інше", "Додаткові функції")

antiAfkToggle = createToggle(miscPage, "Інше", "Anti-AFK", _G.AntiAFK, function(value)
    if isShutdown then return end
    manuallyChanged.AntiAFK = true
    _G.AntiAFK = value
    if antiAfkConnection then antiAfkConnection:Disconnect() antiAfkConnection = nil end
    if value and not isShutdown then
        antiAfkConnection = player.Idled:Connect(function()
            if isShutdown then
                if antiAfkConnection then antiAfkConnection:Disconnect() antiAfkConnection = nil end
                return
            end
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

noclipToggle = createToggle(miscPage, "Інше", "NoClip (окремо від фарму)", _G.StandaloneNoClip, function(value)
    if isShutdown then return end
    manuallyChanged.StandaloneNoClip = true
    _G.StandaloneNoClip = value
    if value then ensureNoClip()
    elseif not _G.ItemFarm and noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end)

autoRespawnToggle = createToggle(miscPage, "Інше", "Авто-респawn при смерті", _G.AutoRespawn, function(value)
    manuallyChanged.AutoRespawn = true
    _G.AutoRespawn = value
end)

createButton(miscPage, "Інше", "Очистити чорний список предметів", function()
    table.clear(bannedCoordinates)
    showNotification("UA Killer Hub", "Чорний список координат очищено", 3)
end)

print("[UA Killer Hub | GUI] Усі елементи інтерфейсу створено.")

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЇ
-- =======================================================
local function readConfigFromDisk()
    if isShutdown or not (readfile and isfile) then return nil, "readfile/isfile недоступні" end

    local fileExists = false
    local ok = pcall(function() fileExists = isfile(configFile) end)
    if not ok or not fileExists then return nil, "файл не знайдено" end

    local rawContent
    ok = pcall(function() rawContent = readfile(configFile) end)
    if not ok or not rawContent or rawContent == "" then return nil, "помилка читання файлу" end

    local data
    ok = pcall(function() data = HttpService:JSONDecode(rawContent) end)
    if not ok or type(data) ~= "table" then return nil, "пошкоджений JSON" end

    return data, nil
end

saveCurrentConfig = function()
    if isShutdown or not writefile then return end

    local cfgData = {
        SelectedItems    = _G.SelectedItems,
        FlySpeed         = _G.FlySpeed,
        JumpPower        = JP_Value,
        ItemESP          = _G.ItemESP,
        InstantFarm      = _G.InstantFarm,
        ItemFarm         = _G.ItemFarm,
        AutoSell         = _G.AutoSell,
        AutoEventCandy   = _G.AutoEventCandy,
        AutoBuy          = _G.AutoBuy,
        AntiAFK          = _G.AntiAFK,
        StandaloneNoClip = _G.StandaloneNoClip,
        AutoRespawn      = _G.AutoRespawn,
    }

    local jsonString
    local ok, err = pcall(function() jsonString = HttpService:JSONEncode(cfgData) end)
    if not ok or not jsonString then return end

    ok, err = pcall(function() writefile(configFile, jsonString) end)
    if ok then
        showNotification("Успіх", "Налаштування збережено!", 3)
    end
end

loadCurrentConfig = function(isAutoLoad)
    if isShutdown then return false end
    local data, errMsg = readConfigFromDisk()
    if not data then return false end

    if data.JumpPower and jumpPowerSlider then jumpPowerSlider:Set(data.JumpPower, true) end
    if data.FlySpeed  and flySpeedSlider  then flySpeedSlider:Set(data.FlySpeed, true) end

    if type(data.SelectedItems) == "table" and not isShutdown then
        for itemName, state in pairs(data.SelectedItems) do
            if isShutdown then return false end
            if _G.SelectedItems[itemName] ~= nil then
                _G.SelectedItems[itemName] = state
                if itemToggleControls[itemName] then itemToggleControls[itemName]:Set(state, false) end
            end
        end
    end

    if isShutdown then return false end

    if data.ItemESP          ~= nil and itemEspToggle      then itemEspToggle:Set(data.ItemESP, false) _G.ItemESP = data.ItemESP end
    if data.AntiAFK          ~= nil and antiAfkToggle      then antiAfkToggle:Set(data.AntiAFK, true) end
    if data.AutoRespawn      ~= nil and autoRespawnToggle  then autoRespawnToggle:Set(data.AutoRespawn, true) end
    if data.StandaloneNoClip ~= nil and noclipToggle       then noclipToggle:Set(data.StandaloneNoClip, true) end
    if data.AutoEventCandy   ~= nil and autoCandyToggle    then autoCandyToggle:Set(data.AutoEventCandy, true) end
    if data.AutoBuy          ~= nil and autoBuyToggle      then autoBuyToggle:Set(data.AutoBuy, true) end

    if data.InstantFarm ~= nil and not isShutdown then
        _G.InstantFarm = (data.InstantFarm == true)
        if instantFarmToggle and instantFarmToggle:Get() ~= _G.InstantFarm then
            instantFarmToggle:Set(_G.InstantFarm, false)
        end
    end

    if data.AutoSell ~= nil and not isShutdown then
        setAutoSellState(data.AutoSell == true)
    end

    if data.ItemFarm ~= nil and not isShutdown then
        setItemFarmState(data.ItemFarm == true)
    end

    print("[UA Killer Hub | Config] Конфігурацію відновлено.")
    showNotification("Конфіг", "Налаштування завантажено!", 3)
    return true
end

-- =======================================================
-- ПОЕТАПНЕ АВТОЗАВАНТАЖЕННЯ (З SHUTDOWN CHECK)
-- =======================================================
local AUTOLOAD_WAIT = 15
local AUTOLOAD_STEP = 1.0

local function runSteppedAutoLoad()
    showNotification("Auto Load", string.format("Завантаження через %ds...", AUTOLOAD_WAIT), AUTOLOAD_WAIT - 1)
    
    local waitCount = 0
    while waitCount < AUTOLOAD_WAIT and not isShutdown do
        task.wait(1)
        waitCount = waitCount + 1
    end
    if isShutdown then return end

    local data, errMsg = readConfigFromDisk()
    if not data or isShutdown then return end

    showNotification("Auto Load", "Відновлення налаштувань...", 3)

    if data.JumpPower and jumpPowerSlider then jumpPowerSlider:Set(data.JumpPower, true) end
    if data.FlySpeed  and flySpeedSlider  then flySpeedSlider:Set(data.FlySpeed, true) end

    if type(data.SelectedItems) == "table" and not isShutdown then
        for itemName, state in pairs(data.SelectedItems) do
            if isShutdown then return end
            if _G.SelectedItems[itemName] ~= nil then
                _G.SelectedItems[itemName] = state
                if itemToggleControls[itemName] then itemToggleControls[itemName]:Set(state, false) end
            end
        end
    end

    local stepWait = 0
    while stepWait < AUTOLOAD_STEP and not isShutdown do
        task.wait(0.2)
        stepWait = stepWait + 0.2
    end
    if isShutdown then return end

    local steps = {
        {
            key = "InstantFarm",
            control = instantFarmToggle,
            label = "Інстант фарм (SafeZone)",
            activate = function(val)
                _G.InstantFarm = (val == true)
                if instantFarmToggle and instantFarmToggle:Get() ~= _G.InstantFarm then
                    instantFarmToggle:Set(_G.InstantFarm, false)
                end
            end,
        },
        {
            key = "ItemFarm",
            control = itemFarmToggle,
            label = "Автофарм",
            activate = function(val) setItemFarmState(val == true) end,
        },
        {
            key = "AutoSell",
            control = autoSellToggle,
            label = "Автопродаж",
            activate = function(val) setAutoSellState(val == true) end,
        },
        {
            key = "AutoEventCandy",
            control = autoCandyToggle,
            label = "Авто-здача конфет",
            activate = function(val)
                _G.AutoEventCandy = (val == true)
                if autoCandyToggle then autoCandyToggle:Set(_G.AutoEventCandy, false) end
            end,
        },
        {
            key = "AutoBuy",
            control = autoBuyToggle,
            label = "Автокупівля",
            activate = function(val)
                _G.AutoBuy = (val == true)
                if autoBuyToggle then autoBuyToggle:Set(_G.AutoBuy, false) end
            end,
        },
        {
            key = "ItemESP",
            control = itemEspToggle,
            label = "ESP",
            activate = function(val)
                _G.ItemESP = (val == true)
                if itemEspToggle then itemEspToggle:Set(_G.ItemESP, false) end
            end,
        },
        {
            key = "AntiAFK",
            control = antiAfkToggle,
            label = "Anti-AFK",
            activate = function(val)
                if antiAfkToggle then antiAfkToggle:Set((val == true), true) end
            end,
        },
        {
            key = "StandaloneNoClip",
            control = noclipToggle,
            label = "NoClip",
            activate = function(val)
                if noclipToggle then noclipToggle:Set((val == true), true) end
            end,
        },
        {
            key = "AutoRespawn",
            control = autoRespawnToggle,
            label = "Авто-респавн",
            activate = function(val)
                if autoRespawnToggle then autoRespawnToggle:Set((val == true), true) end
            end,
        },
    }

    local totalSteps = #steps
    for i, step in ipairs(steps) do
        if isShutdown then return end
        if manuallyChanged[step.key] then
            local sw = 0
            while sw < AUTOLOAD_STEP and not isShutdown do
                task.wait(0.2)
                sw = sw + 0.2
            end
            if isShutdown then return end
            continue
        end

        local savedVal = data[step.key]
        if savedVal == true and not isShutdown then
            showNotification("Auto Load", string.format("(%d/%d) %s", i, totalSteps, step.label), AUTOLOAD_STEP + 0.5)
            step.activate(true)
        end

        local sw = 0
        while sw < AUTOLOAD_STEP and not isShutdown do
            task.wait(0.2)
            sw = sw + 0.2
        end
        if isShutdown then return end
    end

    if isShutdown then return end
    showNotification("Auto Load", "✓ Всі налаштування відновлено!", 4)
end

-- =======================================================
-- ПЕРВИННИЙ СКАНИНГ ТА СТАРТ
-- =======================================================
scanAllItems()
switchTab("Головна")
print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

if shouldAutoLoad and not isShutdown then
    task.spawn(runSteppedAutoLoad)
end

if _G.AutoSell and not isShutdown then
    startAutoSellThread()
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
