-- ====================================================================
-- UA Killer Hub | YBA — Instant SafeZone Farm & AutoSell (Fixed Edition)
-- Виправлено: відображення вкладок, розблокування інвентаря, зняття кнопки DROP
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
-- НАДІЙНІ ТА ПЕРЕВІРЕНІ АНТИЧИТ-БАЙПАСИ (БЕЗ ДЕТЕКТУ)
-- =======================================================
-- 1. Безпечний Item Magnitude Bypass
pcall(function()
    if hookmetamethod and newcclosure and checkcaller and getcallingscript then
        local char = player.Character or player.CharacterAdded:Wait()
        local primary = char:WaitForChild("HumanoidRootPart", 3) or char.PrimaryPart
        if primary then
            local OldIndexItem
            OldIndexItem = hookmetamethod(primary.Position, "__index", newcclosure(function(self, Key)
                if not checkcaller() and Key:lower() == "magnitude" and getcallingscript().Name == "ItemSpawn" then
                    return 0
                end
                return OldIndexItem(self, Key)
            end))
            print("[UA Killer Hub | Init] Item Magnitude Bypass активовано.")
        end
    end
end)

-- 2. Безпечний WalkSpeed/Crash Bypass
pcall(function()
    local FunctionLibrary = require(
        ReplicatedStorage:WaitForChild("Modules", 2):WaitForChild("FunctionLibrary", 2)
    )
    local OldPcall = FunctionLibrary.pcall
    FunctionLibrary.pcall = function(...)
        local args = { ... }
        if type(args[1]) == "function" and #getupvalues(args[1]) == 11 then
            return
        end
        return OldPcall(...)
    end
    print("[UA Killer Hub | Init] WalkSpeed/Crash Bypass активовано.")
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
_G.ItemESP         = false
_G.InstantFarm     = true -- Миттєвий фарм (SafeZone Decoy + Instant Teleport без кіку)
_G.FlySpeed        = 180 -- Швидкість польоту (для режиму плавного польоту)
_G.PickupDistance  = 3.5
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

-- Пріоритетні рідкісні предмети
local FARM_PRIORITY = {
    ["Lucky Arrow"] = true,
    ["Lucky Stone Mask"] = true,
    ["Dio's Diary"] = true,
    ["Rib Cage of The Saint's Corpse"] = true,
    ["Pure Rokakaka"] = true,
}

-- Чорний список проблемних координат (де предмети застрягли)
local BannedCoordinates = {}
local failedItemAttempts = {}

local function isCoordinateBanned(pos, part)
    if not pos then return false end
    for bannedPos, expiry in pairs(BannedCoordinates) do
        if tick() > expiry then
            BannedCoordinates[bannedPos] = nil
        else
            if (pos - bannedPos).Magnitude <= 3.5 then
                return true
            end
        end
    end
    return false
end

local function banFailedItem(itemData, reason)
    if not itemData or not itemData.position then return end
    BannedCoordinates[itemData.position] = tick() + 60
    print(string.format("[UA Killer Hub | Farm] Пропуск застряглого предмета '%s' на 60с (%s)", tostring(itemData.name or "Item"), tostring(reason or "timeout")))
end

-- ====================
-- УТИЛІТИ СТАНУ ТА РУХУ
-- ====================
local farmThreadActive = false
local farmSessionId    = 0
local farmStatusText   = "Зупинено"
local noclipConnection = nil
local antiAfkConnection= nil
local flightState      = nil

local manuallyChanged = {
    ItemFarm         = false,
    InstantFarm      = false,
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
    if not char then
        char = player.CharacterAdded:Wait()
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
    end)
end

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

-- NoClip контролер
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
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
    trackConnection(noclipConnection)
end

-- =======================================================
-- БАЗА ДАНИХ ТА СКАНИНГ ПРЕДМЕТІВ (РЕАКТИВНА СИСТЕМА)
-- =======================================================
local TrackedItems = {}

local function resolveItemName(obj)
    if not obj then return nil end

    local surfaceGui = obj:FindFirstChildWhichIsA("SurfaceGui", true)
    if surfaceGui then
        local textLabel = surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
        if textLabel and textLabel.Text ~= "" and _G.SelectedItems[textLabel.Text] ~= nil then
            return textLabel.Text
        end
    end

    local billboardGui = obj:FindFirstChildWhichIsA("BillboardGui", true)
    if billboardGui then
        local textLabel = billboardGui:FindFirstChildWhichIsA("TextLabel", true)
        if textLabel and textLabel.Text ~= "" and _G.SelectedItems[textLabel.Text] ~= nil then
            return textLabel.Text
        end
    end

    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local txt = prompt.ObjectText
        if txt and txt ~= "" and _G.SelectedItems[txt] ~= nil then
            return txt
        end
        local act = prompt.ActionText
        if act and act ~= "" and _G.SelectedItems[act] ~= nil then
            return act
        end
    end

    if _G.SelectedItems[obj.Name] ~= nil then
        return obj.Name
    end

    if obj.Parent and _G.SelectedItems[obj.Parent.Name] ~= nil then
        return obj.Parent.Name
    end

    return nil
end

local function isPlayerOwned(part)
    if not part then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        if c and part:IsDescendantOf(c) then
            return true
        end
        local bp = p:FindFirstChild("Backpack")
        if bp and part:IsDescendantOf(bp) then
            return true
        end
    end
    return false
end

local function registerItem(part, obj, name)
    if isShutdown or not part or not part:IsA("BasePart") or isPlayerOwned(part) then return end
    if TrackedItems[part] then
        if name and TrackedItems[part].Name ~= name then
            TrackedItems[part].Name = name
        end
        return
    end

    TrackedItems[part] = {
        Part = part,
        Obj  = obj or part,
        Name = name or "Предмет",
    }
end

local function unregisterItem(part)
    if not part then return end
    TrackedItems[part] = nil
    failedItemAttempts[part] = nil
end

local function checkAndRegister(descendant)
    if isShutdown or not descendant then return end
    if isPlayerOwned(descendant) then return end

    local name = resolveItemName(descendant)
    if not name then
        if descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") or descendant:IsA("ProximityPrompt") then
            local part = descendant:FindFirstAncestorWhichIsA("BasePart")
            if part then
                task.delay(0.2, function()
                    if isShutdown or not part.Parent then return end
                    local lateName = resolveItemName(descendant) or resolveItemName(part)
                    if lateName then
                        registerItem(part, descendant, lateName)
                    end
                end)
            end
        end
        return
    end

    local part = descendant:IsA("BasePart") and descendant or descendant:FindFirstChildWhichIsA("BasePart", true)
    if not part and descendant.Parent and descendant.Parent:IsA("BasePart") then
        part = descendant.Parent
    end

    if part and not isPlayerOwned(part) then
        registerItem(part, descendant, name)
    end
end

local function scanAllItems()
    table.clear(TrackedItems)
    local itemsFolder = workspace:FindFirstChild("Item_Spawns") or workspace:FindFirstChild("Items") or workspace
    for _, descendant in ipairs(itemsFolder:GetDescendants()) do
        if isShutdown then break end
        checkAndRegister(descendant)
    end
end

trackConnection(workspace.DescendantAdded:Connect(function(descendant)
    if isShutdown then return end
    checkAndRegister(descendant)
end))

trackConnection(workspace.DescendantRemoving:Connect(function(descendant)
    if descendant:IsA("BasePart") then
        unregisterItem(descendant)
    end
end))

-- ESP Контролер
local activeHighlights = {}
local activeBillboards  = {}

local function clearESP()
    for part, hl in pairs(activeHighlights) do
        if hl and hl.Parent then pcall(function() hl:Destroy() end) end
    end
    table.clear(activeHighlights)

    for part, bb in pairs(activeBillboards) do
        if bb and bb.Parent then pcall(function() bb:Destroy() end) end
    end
    table.clear(activeBillboards)
end

local function updateESP()
    if isShutdown or not _G.ItemESP then
        clearESP()
        return
    end

    for part, data in pairs(TrackedItems) do
        if isShutdown then break end
        if not part or not part.Parent or not part:IsDescendantOf(workspace) then
            if activeHighlights[part] then activeHighlights[part]:Destroy() activeHighlights[part] = nil end
            if activeBillboards[part]  then activeBillboards[part]:Destroy()  activeBillboards[part] = nil end
            continue
        end

        local isSelected = _G.SelectedItems[data.Name] == true

        if isSelected then
            if not activeHighlights[part] then
                local hl = Instance.new("Highlight")
                hl.Name = "UA_Killer_ESP"
                hl.Adornee = part
                hl.FillColor = FARM_PRIORITY[data.Name] and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 255, 170)
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.4
                hl.OutlineTransparency = 0.1
                hl.Parent = part
                activeHighlights[part] = hl
            end

            if not activeBillboards[part] then
                local bb = Instance.new("BillboardGui")
                bb.Name = "UA_Killer_Label"
                bb.Adornee = part
                bb.Size = UDim2.new(0, 120, 0, 30)
                bb.StudsOffset = Vector3.new(0, 2, 0)
                bb.AlwaysOnTop = true

                local lbl = Instance.new("TextLabel")
                lbl.Size                   = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text                   = data.Name
                lbl.TextColor3             = FARM_PRIORITY[data.Name] and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
                lbl.TextStrokeTransparency = 0.2
                lbl.TextSize               = 13
                lbl.Font                   = Enum.Font.GothamBold
                lbl.Parent                 = bb

                bb.Parent = part
                activeBillboards[part] = bb
            end
        else
            if activeHighlights[part] then activeHighlights[part]:Destroy() activeHighlights[part] = nil end
            if activeBillboards[part]  then activeBillboards[part]:Destroy()  activeBillboards[part] = nil end
        end
    end
end

local function shouldFarmItem(itemName)
    return _G.SelectedItems[itemName] == true
end

local function getNearestFarmItem(originPart)
    local origin = originPart.Position
    local nearest, nearestPart, nearestData = nil, nil, nil
    local nearestDist = math.huge

    local prioItem, prioPart, prioData = nil, nil, nil
    local prioDist = math.huge

    for part, data in pairs(TrackedItems) do
        if isShutdown then break end
        if part and part.Parent and part:IsDescendantOf(workspace)
            and not isPlayerOwned(part)
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

-- =======================================================
-- СИСТЕМА SAFEZONE DECOY ТА МИТТЄВОГО ПЕРЕСУВАННЯ (INSTANT)
-- =======================================================
local SAFE_ZONE = Vector3.new(-212.241150, -33.486183, -283.842651)

local FarmVisual = {
    OriginalVisuals = setmetatable({}, {__mode = "k"}),
    AnimationMap = setmetatable({}, {__mode = "k"}),
    DecoyUpdateConnection = nil,
    FallbackWalkTrack = nil,
    FallbackWalkAnimation = nil,
    CameraBindBefore = "Phantom_Farm_Decoy_Camera_Before",
    CameraBindAfter = "Phantom_Farm_Decoy_Camera_After",
    Character = nil,
    Decoy = nil,
    DecoyHumanoid = nil,
    DecoyRoot = nil,
    PreviousCameraSubject = nil,
    PreviousCameraType = nil,
    CharacterConnection = nil,
}

local function hideFarmVisual(instance)
    if not instance or not instance.Parent then return end

    -- НІКОЛИ не приховувати інструменти (Tools) та їхні частини, щоб інвентар залишався видимим!
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
    local char = player.Character
    return FarmVisual.Character == char
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
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if camera then
            pcall(function()
                camera.CameraType = previousCameraType or Enum.CameraType.Custom
                local subject = humanoid or previousSubject
                if subject and subject.Parent then
                    camera.CameraSubject = subject
                end
            end)
        end
    end
end

function FarmVisual.showSafeZoneDecoy()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not root or not humanoid then return false end
    if FarmVisual.isActive() then return true end

    FarmVisual.cleanup()

    local wasArchivable = character.Archivable
    local ok, decoy
    pcall(function() character.Archivable = true end)
    ok, decoy = pcall(function() return character:Clone() end)
    pcall(function() character.Archivable = wasArchivable end)
    if not ok or not decoy or not decoy:IsA("Model") then
        return false
    end

    decoy.Name = "Phantom_FarmSafeZoneDecoy"
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
                descendant.Anchored = (descendant == decoyRoot)
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
                descendant.Massless = (descendant ~= decoyRoot)
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
        decoyHumanoid.WalkSpeed = humanoid.WalkSpeed
        decoyHumanoid.JumpPower = humanoid.JumpPower
        decoyHumanoid.UseJumpPower = humanoid.UseJumpPower
    end)

    local safeRootCFrame = CFrame.new(SAFE_ZONE) * root.CFrame.Rotation
    local pivotOffset = root.CFrame:ToObjectSpace(character:GetPivot())
    decoy.Parent = workspace
    decoy:PivotTo(safeRootCFrame * pivotOffset)

    FarmVisual.Character = character
    FarmVisual.Decoy = decoy
    FarmVisual.DecoyHumanoid = decoyHumanoid
    FarmVisual.DecoyRoot = decoyRoot
    FarmVisual.AnimationMap = setmetatable({}, {__mode = "k"})
    FarmVisual.OriginalVisuals = setmetatable({}, {__mode = "k"})

    local decoyAnimator = decoyHumanoid:FindFirstChildOfClass("Animator")
    if not decoyAnimator then
        decoyAnimator = Instance.new("Animator")
        decoyAnimator.Parent = decoyHumanoid
    end

    local function findWalkAnimationId()
        local animateScript = character:FindFirstChild("Animate")
        if not animateScript then return nil end
        local fallbackRun
        for _, animationObject in ipairs(animateScript:GetDescendants()) do
            if animationObject:IsA("Animation") and animationObject.AnimationId ~= "" then
                local name = string.lower(animationObject.Name or "")
                if name == "walkanim" or name == "walk" or name:find("walk", 1, true) then
                    return animationObject.AnimationId
                elseif (name == "runanim" or name == "run" or name:find("run", 1, true)) and not fallbackRun then
                    fallbackRun = animationObject.AnimationId
                end
            end
        end
        return fallbackRun
    end

    local fallbackWalkId = findWalkAnimationId()
    if fallbackWalkId then
        local fallbackAnimation = Instance.new("Animation")
        fallbackAnimation.Name = "Phantom_FallbackWalkAnimation"
        fallbackAnimation.AnimationId = fallbackWalkId
        local fallbackTrack
        local fallbackLoaded = pcall(function()
            fallbackTrack = decoyAnimator:LoadAnimation(fallbackAnimation)
        end)
        if fallbackLoaded and fallbackTrack then
            pcall(function()
                fallbackTrack.Priority = Enum.AnimationPriority.Movement
                fallbackTrack.Looped = true
            end)
            FarmVisual.FallbackWalkAnimation = fallbackAnimation
            FarmVisual.FallbackWalkTrack = fallbackTrack
        else
            pcall(function() fallbackAnimation:Destroy() end)
        end
    end

    local nextAnimationSync = 0
    local function syncCurrentAnimations()
        local sourceAnimator = humanoid.Parent and humanoid:FindFirstChildOfClass("Animator")
        local visualAnimator = decoyHumanoid.Parent and decoyHumanoid:FindFirstChildOfClass("Animator")
        if not sourceAnimator or not visualAnimator then return end

        local playing = {}
        local hasMovementAnimation = false
        for _, sourceTrack in ipairs(sourceAnimator:GetPlayingAnimationTracks()) do
            if sourceTrack and sourceTrack.IsPlaying then
                if sourceTrack.Priority == Enum.AnimationPriority.Movement then
                    hasMovementAnimation = true
                end
                local sourceAnimation = sourceTrack.Animation
                local animationId = sourceAnimation and sourceAnimation.AnimationId or ""
                if animationId ~= "" then
                    playing[sourceTrack] = true
                    local entry = FarmVisual.AnimationMap[sourceTrack]
                    if not entry or entry.AnimationId ~= animationId then
                        if entry then
                            if entry.Track then
                                pcall(function() entry.Track:Stop(0) end)
                                pcall(function() entry.Track:Destroy() end)
                            end
                            if entry.Animation then
                                pcall(function() entry.Animation:Destroy() end)
                            end
                        end

                        local copiedAnimation = Instance.new("Animation")
                        copiedAnimation.Name = "Phantom_MirroredAnimation"
                        copiedAnimation.AnimationId = animationId
                        local copiedTrack
                        local loaded = pcall(function()
                            copiedTrack = visualAnimator:LoadAnimation(copiedAnimation)
                        end)
                        if loaded and copiedTrack then
                            pcall(function()
                                copiedTrack.Priority = sourceTrack.Priority
                                copiedTrack.Looped = sourceTrack.Looped
                                copiedTrack:Play(0.05, sourceTrack.WeightCurrent, sourceTrack.Speed)
                                copiedTrack.TimePosition = sourceTrack.TimePosition
                            end)
                            entry = {
                                Track = copiedTrack,
                                Animation = copiedAnimation,
                                AnimationId = animationId,
                                LastSync = 0,
                            }
                            FarmVisual.AnimationMap[sourceTrack] = entry
                        else
                            pcall(function() copiedAnimation:Destroy() end)
                            FarmVisual.AnimationMap[sourceTrack] = nil
                            entry = nil
                        end
                    end

                    if entry and entry.Track then
                        pcall(function()
                            local targetTrack = entry.Track
                            local speed = tonumber(sourceTrack.Speed) or 1
                            if targetTrack.Priority ~= sourceTrack.Priority then
                                targetTrack.Priority = sourceTrack.Priority
                            end
                            if targetTrack.Looped ~= sourceTrack.Looped then
                                targetTrack.Looped = sourceTrack.Looped
                            end
                            if not targetTrack.IsPlaying then
                                targetTrack:Play(0.05, sourceTrack.WeightCurrent, speed)
                            end
                            targetTrack:AdjustSpeed(speed)
                            if math.abs(targetTrack.TimePosition - sourceTrack.TimePosition) > 0.14 then
                                targetTrack.TimePosition = sourceTrack.TimePosition
                            end
                            local targetWeight = tonumber(sourceTrack.WeightTarget) or 1
                            if math.abs(targetTrack.WeightTarget - targetWeight) > 0.05 then
                                targetTrack:AdjustWeight(targetWeight, 0.06)
                            end
                        end)
                    end
                end
            end
        end

        for sourceTrack, entry in pairs(FarmVisual.AnimationMap) do
            if not playing[sourceTrack] then
                if entry.Track then
                    pcall(function() entry.Track:Stop(0.08) end)
                    pcall(function() entry.Track:Destroy() end)
                end
                if entry.Animation then
                    pcall(function() entry.Animation:Destroy() end)
                end
                FarmVisual.AnimationMap[sourceTrack] = nil
            end
        end

        local movement = humanoid.MoveDirection
        local isMoving = Vector3.new(movement.X, 0, movement.Z).Magnitude > 0.04
        local fallbackTrack = FarmVisual.FallbackWalkTrack
        if fallbackTrack then
            if isMoving and not hasMovementAnimation then
                if not fallbackTrack.IsPlaying then
                    pcall(function() fallbackTrack:Play(0.08, 1, 1) end)
                end
                pcall(function()
                    fallbackTrack:AdjustSpeed(math.clamp((tonumber(humanoid.WalkSpeed) or 16) / 16, 0.5, 2.5))
                end)
            elseif fallbackTrack.IsPlaying then
                pcall(function() fallbackTrack:Stop(0.08) end)
            end
        end
    end

    FarmVisual.DecoyUpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if FarmVisual.Decoy ~= decoy or not decoy.Parent
            or FarmVisual.Character ~= character or player.Character ~= character
            or not decoyRoot.Parent or not humanoid.Parent then
            return
        end

        local movement = humanoid.MoveDirection
        local horizontal = Vector3.new(movement.X, 0, movement.Z)
        if horizontal.Magnitude > 0.04 then
            local direction = horizontal.Unit
            local currentPivot = decoy:GetPivot()
            local speed = math.clamp(tonumber(humanoid.WalkSpeed) or 16, 0, 80)
            local step = math.min(math.max(tonumber(deltaTime) or 0, 0), 0.05)
            local nextPosition = currentPivot.Position + direction * speed * step
            local nextPivot = CFrame.lookAt(nextPosition, nextPosition + direction)
            pcall(function() decoy:PivotTo(nextPivot) end)
        end

        local now = os.clock()
        if now >= nextAnimationSync then
            nextAnimationSync = now + 0.05
            pcall(syncCurrentAnimations)
        end
    end)

    for _, descendant in ipairs(character:GetDescendants()) do
        hideFarmVisual(descendant)
    end

    FarmVisual.CharacterConnection = character.DescendantAdded:Connect(function(descendant)
        if FarmVisual.Character == character and FarmVisual.Decoy == decoy then
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
        RunService:BindToRenderStep(
            FarmVisual.CameraBindBefore,
            Enum.RenderPriority.Camera.Value - 1,
            maintainDecoyCamera
        )
        RunService:BindToRenderStep(
            FarmVisual.CameraBindAfter,
            Enum.RenderPriority.Camera.Value + 1,
            maintainDecoyCamera
        )
        maintainDecoyCamera()
    end)

    return true
end

function FarmVisual.restoreAtSafe()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and (root.Position - SAFE_ZONE).Magnitude > 6 then
        root.CFrame = CFrame.new(SAFE_ZONE)
        zeroHrpVelocity(root)
    end
    FarmVisual.cleanup()
    return root ~= nil
end

local Move = {}

function Move.teleSafe()
    if isShutdown then return false end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end

    root.CFrame = CFrame.new(SAFE_ZONE)
    zeroHrpVelocity(root)
    return true
end

function Move.telePart(part)
    if isShutdown or not part or not part.Parent or not part:IsDescendantOf(workspace) then return false end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end

    root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
    zeroHrpVelocity(root)
    return true
end

local function moveToSafeIfNeeded()
    if isShutdown then return false end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and (root.Position - SAFE_ZONE).Magnitude > 6 then
        return Move.teleSafe()
    end
    return root ~= nil
end

local function waitForArrival(part, timeout)
    timeout = math.clamp(tonumber(timeout) or 2.5, 1.0, 4.0)
    local started = os.clock()
    local expectedCharacter = player.Character
    local previousPosition = nil
    local stableFrames = 0
    local settleTime = 0.25

    while _G.ItemFarm and not isShutdown and part and part.Parent and part:IsDescendantOf(workspace)
        and os.clock() - started < timeout do
        local character = player.Character
        if not character or character ~= expectedCharacter then return false end
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return false end

        local targetPosition = part.Position + Vector3.new(0, 3, 0)
        if (root.Position - targetPosition).Magnitude > 0.1 then
            root.CFrame = CFrame.new(targetPosition)
        end
        zeroHrpVelocity(root)

        local currentPosition = root.Position
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
                character = player.Character
                if not character or character ~= expectedCharacter then return false end
                root = character:FindFirstChild("HumanoidRootPart")
                if not root then return false end

                targetPosition = part.Position + Vector3.new(0, 3, 0)
                if (root.Position - targetPosition).Magnitude > 0.1 then
                    root.CFrame = CFrame.new(targetPosition)
                end
                zeroHrpVelocity(root)
                RunService.Heartbeat:Wait()
            end

            if not _G.ItemFarm or isShutdown or not part or not part.Parent or not part:IsDescendantOf(workspace) then
                return false
            end
            character = player.Character
            root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return false end
            targetPosition = part.Position + Vector3.new(0, 3, 0)
            if (root.Position - targetPosition).Magnitude > 0.1 then
                root.CFrame = CFrame.new(targetPosition)
                zeroHrpVelocity(root)
                RunService.Heartbeat:Wait()
            end

            return _G.ItemFarm
                and not isShutdown
                and player.Character == expectedCharacter
                and part.Parent ~= nil
                and part:IsDescendantOf(workspace)
                and (root.Position - (part.Position + Vector3.new(0, 3, 0))).Magnitude <= 0.5
                and (part.Position - root.Position).Magnitude <= 4.0
        end

        RunService.Heartbeat:Wait()
    end

    return false
end

-- ====================
-- ПЛАВНИЙ ТА БЕЗПЕЧНИЙ ПОЛІТ (РЕЖИМ TWEEN)
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

-- ====================
-- АКТИВАЦІЯ ТА ЗБІР ПРЕДМЕТА
-- ====================
local function triggerPickupPrompt(prompt)
    if isShutdown or not prompt or not prompt.Parent or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    local oldHoldDuration
    pcall(function()
        oldHoldDuration = prompt.HoldDuration
        prompt.HoldDuration = 0
    end)

    local function restoreHoldDuration()
        if oldHoldDuration ~= nil and prompt.Parent then
            pcall(function() prompt.HoldDuration = oldHoldDuration end)
        end
    end

    if type(fireproximityprompt) == "function" then
        local ok = pcall(function()
            fireproximityprompt(prompt, 0, true)
        end)
        if not ok then
            ok = pcall(function() fireproximityprompt(prompt) end)
        end
        restoreHoldDuration()
        if ok then return true end
    end

    local fired = false
    if type(getconnections) == "function" then
        local connectionsOk, connections = pcall(function()
            return getconnections(prompt.Triggered)
        end)
        if connectionsOk and connections then
            for _, connection in pairs(connections) do
                if connection and type(connection.Fire) == "function" then
                    local connectionFired = pcall(function()
                        connection:Fire(prompt)
                    end)
                    if connectionFired then fired = true end
                end
            end
        end
    end

    if not fired and prompt.Parent then
        local inputOk = pcall(function()
            prompt:InputHoldBegin()
            task.wait(0.08)
            prompt:InputHoldEnd()
        end)
        if inputOk then fired = true end
    end

    restoreHoldDuration()
    return fired
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

    local instantMode = (_G.InstantFarm == true)

    if instantMode then
        -- Переконуємось, що SafeZone Decoy активний
        if not FarmVisual.isActive() then
            moveToSafeIfNeeded()
            task.wait(0.06)
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
                        moveToSafeIfNeeded()
                        return true
                    end
                end
            end
        end

        -- Миттєве повернення у SafeZone після завершення підбору
        moveToSafeIfNeeded()

        if not part.Parent or not part:IsDescendantOf(workspace) then
            unregisterItem(part)
            return true
        end
        return false
    else
        -- Режим звичайного плавного польоту (Tween)
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
local instantFarmToggle

local function startFarmThread()
    if farmThreadActive or isShutdown then return end
    farmThreadActive = true
    farmSessionId    = farmSessionId + 1
    local currentSession = farmSessionId
    ensureNoClip()

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

            local instantMode = (_G.InstantFarm == true)

            -- Якщо активний режим Instant — підтримуємо Decoy у SafeZone
            if instantMode then
                if not FarmVisual.isActive() then
                    moveToSafeIfNeeded()
                    task.wait(0.06)
                    FarmVisual.showSafeZoneDecoy()
                end
            elseif FarmVisual.Decoy then
                FarmVisual.cleanup()
            end

            local anySelected = false
            for _, sel in pairs(_G.SelectedItems) do
                if sel == true then anySelected = true break end
            end

            local item, part, data = getNearestFarmItem(hrp)
            if not item or not part then
                if instantMode then
                    moveToSafeIfNeeded()
                end
                if not anySelected then
                    setFarmStatus("Оберіть предмети у вкладці Автофарм!")
                else
                    setFarmStatus("Очікування спавну предметів...")
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
        if FarmVisual.Decoy then
            FarmVisual.restoreAtSafe()
        end
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

-- Функція гарантованого повернення всіх інструментів у рюкзак (прибирає кнопку DROP)
local function forceUnequipAllTools()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:UnequipTools() end)
    end
    if char then
        local bp = player:FindFirstChild("Backpack")
        for _, obj in ipairs(char:GetChildren()) do
            if obj:IsA("Tool") then
                pcall(function()
                    if bp then
                        obj.Parent = bp
                    elseif hum then
                        hum:UnequipTools()
                    end
                end)
            end
        end
    end
end

local function closeMerchantDialogue()
    pcall(forceUnequipAllTools)
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
    pcall(forceUnequipAllTools)
end

-- Натискання опції в меню діалогу YBA (Option1, Option6 тощо)
local function clickDialogueOption(optionName, timeout)
    timeout = timeout or 2.0
    local deadline = tick() + timeout
    while tick() < deadline and not isShutdown do
        local gui = getDialogueGui()
        if gui then
            local frame = gui:FindFirstChild("Frame")
            local options = frame and frame:FindFirstChild("Options")
            if options then
                local opt = options:FindFirstChild(optionName) or options:FindFirstChild(optionName, true)
                local btn = (opt and opt:IsA("GuiButton")) and opt or (opt and opt:FindFirstChildWhichIsA("GuiButton", true))
                if btn and isGuiElementVisible(btn) then
                    pcall(function()
                        if firesignal then
                            firesignal(btn.MouseButton1Click)
                            firesignal(btn.Activated)
                        else
                            btn.Activated:Fire()
                        end
                    end)
                    return true
                end
            end
        end
        task.wait(0.05)
    end
    return false
end

local function sellSingleItem(item)
    if isShutdown then return false, "Shutdown" end
    if not item or isItemSold(item) or DontSell[item.Name] then return true, "AlreadySold" end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()
    if not hum or not remote or not merchant then return false, "MissingCharacterOrNPC" end

    -- Одягаємо предмет для продажу
    hum:EquipTool(item)
    local equipTimeout = tick() + 0.8
    while tick() < equipTimeout and item.Parent ~= char and not isShutdown do task.wait(0.04) end
    if item.Parent ~= char or isShutdown then
        forceUnequipAllTools()
        return false, "EquipTimeoutOrShutdown"
    end

    task.wait(0.08)
    if isShutdown then forceUnequipAllTools() return false, "Shutdown" end

    -- Крок 1: Відкриваємо Merchant
    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.12)
    clickDialogueOption("Option1", 1.8)
    autoClickDialogueButtons()

    task.wait(0.08)
    if isShutdown then forceUnequipAllTools() return false, "Shutdown" end

    -- Крок 2: Обираємо предмет
    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.12)
    clickDialogueOption("Option1", 1.8)
    autoClickDialogueButtons()

    task.wait(0.08)
    if isShutdown then forceUnequipAllTools() return false, "Shutdown" end

    -- Крок 3: Підтверджуємо угоду (Deal)
    local dealClicked = clickDialogueOption("Option6", 1.5)
    if not dealClicked then
        clickDialogueOption("Option1", 0.6)
    end
    autoClickDialogueButtons()

    local sellTimeout = tick() + 1.2
    while tick() < sellTimeout and not isShutdown do
        if isItemSold(item) then break end
        autoClickDialogueButtons()
        task.wait(0.08)
    end

    local sold = isItemSold(item)

    -- ЗАВЖДИ закриваємо діалог та повертаємо інструменти назад у Backpack!
    closeMerchantDialogue()
    forceUnequipAllTools()

    return sold, sold and "Success" or "ItemStillExists"
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
    end
end

-- =======================================================
-- АВТО-ЗДАЧА ЦУКЕРОК HALLOWEEN EVENT
-- =======================================================
local function closeHalloweenDialogue()
    pcall(forceUnequipAllTools)
    local char   = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")
    pcall(function()
        if remote then
            remote:FireServer("EndDialogue", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue3" })
            remote:FireServer("DialogueEnd", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue3" })
            remote:FireServer("EndDialogue", { NPC = "Halloween Event", Option = "Option2", Dialogue = "Dialogue1" })
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
                    if lower:find("bye") or lower:find("leave") or lower:find("close") or lower:find("nevermind") or lower:find("nothing") or lower:find("exit") or lower:find("no") then
                        if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                        else btn.Activated:Fire() end
                    end
                end
            end
        end)
        task.wait(0.12)
        if gui:IsA("ScreenGui") and gui.Enabled then pcall(function() gui.Enabled = false end) end
    end
    pcall(forceUnequipAllTools)
end

local function turnInCandy(candyItem)
    if isShutdown or not candyItem or isItemSold(candyItem) then return false end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not hum or not remote or not eventNPC then return false end

    hum:EquipTool(candyItem)
    local t = tick() + 0.8
    while tick() < t and candyItem.Parent ~= char and not isShutdown do task.wait(0.04) end
    if candyItem.Parent ~= char or isShutdown then forceUnequipAllTools() return false end

    task.wait(0.12)
    if isShutdown then forceUnequipAllTools() return false end
    remote:FireServer("PromptTriggered", eventNPC)
    task.wait(0.12)
    autoClickDialogueButtons()

    if isShutdown then forceUnequipAllTools() return false end
    remote:FireServer("DialogueType", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue1" })
    task.wait(0.12)
    autoClickDialogueButtons()

    if isShutdown then forceUnequipAllTools() return false end
    remote:FireServer("DialogueType", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue2" })
    task.wait(0.12)
    autoClickDialogueButtons()

    local sellTimeout = tick() + 1.2
    while tick() < sellTimeout and not isShutdown do
        if isItemSold(candyItem) then break end
        autoClickDialogueButtons()
        task.wait(0.08)
    end

    pcall(function()
        remote:FireServer("EndDialogue", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue2" })
        remote:FireServer("DialogueType", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue3" })
        remote:FireServer("EndDialogue", { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue3" })
        remote:FireServer("DialogueEnd",  { NPC = "Halloween Event", Option = "Option1", Dialogue = "Dialogue3" })
    end)
    task.wait(0.1)

    forceUnequipAllTools()
    return isItemSold(candyItem)
end

-- =======================================================
-- АВТО-КУПІВЛЯ ПРЕДМЕТІВ У MERCHANT
-- =======================================================
local function buySingleItem(itemName)
    if isShutdown then return end
    local char   = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()
    if not remote or not merchant then return end

    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.15)
    autoClickDialogueButtons()

    if isShutdown then return end
    remote:FireServer("DialogueType", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Merchant" })
    task.wait(0.15)
    autoClickDialogueButtons()

    local dialogueMap = {
        ["Mysterious Arrow"] = "Dialogue8",
        ["Rokakaka"]         = "Dialogue9",
    }
    local targetDialogue = dialogueMap[itemName]
    if targetDialogue and not isShutdown then
        remote:FireServer("DialogueType", { Option = "Option1", Dialogue = targetDialogue, NPC = "Merchant" })
        task.wait(0.2)
        autoClickDialogueButtons()
    end

    pcall(function()
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = targetDialogue or "Dialogue8", NPC = "Merchant" })
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
    end)
    task.wait(0.1)
    closeMerchantDialogue()
end

-- Фоновий потік AutoEventCandy
task.spawn(function()
    while not isShutdown do
        task.wait(1.5)
        if isShutdown then break end
        if _G.AutoEventCandy and not isBusy then
            local backpack = player:FindFirstChild("Backpack")
            local char     = player.Character
            local foundCandy = nil

            local function check(cont)
                if not cont or isShutdown then return end
                for _, item in ipairs(cont:GetChildren()) do
                    if item:IsA("Tool") and EventCandies[item.Name] and not isItemSold(item) then
                        foundCandy = item
                        return
                    end
                end
            end

            check(backpack)
            if not foundCandy then check(char) end

            if foundCandy and not isShutdown then
                isBusy = true
                turnInCandy(foundCandy)
                if not isShutdown then closeHalloweenDialogue() end
                isBusy = false
            end
        end
    end
end)

-- Фоновий потік AutoBuy
task.spawn(function()
    while not isShutdown do
        task.wait(3.0)
        if isShutdown then break end
        if _G.AutoBuy and not isBusy then
            local goldCoinCount = 0
            local function countCoins(cont)
                if not cont or isShutdown then return end
                for _, item in ipairs(cont:GetChildren()) do
                    if item:IsA("Tool") and item.Name == "Gold Coin" then
                        goldCoinCount = goldCoinCount + 1
                    end
                end
            end
            countCoins(player:FindFirstChild("Backpack"))
            countCoins(player.Character)

            if goldCoinCount >= 2 and not isShutdown then
                isBusy = true
                buySingleItem("Mysterious Arrow")
                isBusy = false
            end
        end
    end
end)

-- JumpPower система
local JP_Value = 50
local function applyJumpPower()
    if isShutdown then return end
    local _, _, hum = getCharacter()
    if hum then hum.JumpPower = JP_Value end
end

trackConnection(player.CharacterAdded:Connect(function(newChar)
    if isShutdown then return end
    if FarmVisual.Decoy then
        pcall(function() FarmVisual.cleanup() end)
    end
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
            updateESP()
        end
    end
end)

-- =======================================================
-- ІНТЕРФЕЙС КОРИСТУВАЧА (UA KILLER HUB — GUI)
-- =======================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "UAKillerHub_YBA"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then
        ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = game:GetService("CoreGui")
    elseif game:GetService("CoreGui") then
        ScreenGui.Parent = game:GetService("CoreGui")
    else
        ScreenGui.Parent = player:WaitForChild("PlayerGui")
    end
end)

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 560, 0, 360)
MainFrame.Position         = UDim2.new(0.5, -280, 0.5, -180)
MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 21)
MainFrame.BorderSizePixel  = 0
MainFrame.Active           = true
MainFrame.Draggable        = true
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent       = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color       = Color3.fromRGB(35, 39, 48)
MainStroke.Thickness   = 1
MainStroke.Parent      = MainFrame

-- Контейнер сповіщень (Toasts)
local ToastContainer = Instance.new("Frame")
ToastContainer.Name                   = "ToastContainer"
ToastContainer.Size                   = UDim2.new(0, 260, 1, -20)
ToastContainer.Position               = UDim2.new(1, -270, 0, 10)
ToastContainer.BackgroundTransparency = 1
ToastContainer.ZIndex                 = 100
ToastContainer.Parent                 = ScreenGui

local ToastLayout = Instance.new("UIListLayout")
ToastLayout.FillDirection        = Enum.FillDirection.Vertical
ToastLayout.VerticalAlignment    = Enum.VerticalAlignment.Bottom
ToastLayout.HorizontalAlignment  = Enum.HorizontalAlignment.Right
ToastLayout.Padding              = UDim.new(0, 8)
ToastLayout.Parent               = ToastContainer

local function showNotification(title, message, duration)
    if isShutdown then return end
    duration = duration or 3.5

    local toast = Instance.new("Frame")
    toast.Size                 = UDim2.new(1, 0, 0, 56)
    toast.BackgroundColor3     = Color3.fromRGB(22, 25, 32)
    toast.BorderSizePixel      = 0
    toast.BackgroundTransparency = 1
    toast.Parent               = ToastContainer

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(0, 8)
    tc.Parent       = toast

    local ts = Instance.new("UIStroke")
    ts.Color       = Color3.fromRGB(0, 180, 255)
    ts.Thickness   = 1.2
    ts.Transparency = 1
    ts.Parent      = toast

    local tLbl = Instance.new("TextLabel")
    tLbl.Size                   = UDim2.new(1, -16, 0, 20)
    tLbl.Position               = UDim2.new(0, 10, 0, 6)
    tLbl.BackgroundTransparency = 1
    tLbl.Text                   = title
    tLbl.TextColor3             = Color3.fromRGB(0, 200, 255)
    tLbl.Font                   = Enum.Font.GothamBold
    tLbl.TextSize               = 13
    tLbl.TextXAlignment         = Enum.TextXAlignment.Left
    tLbl.TextTransparency       = 1
    tLbl.Parent                 = toast

    local mLbl = Instance.new("TextLabel")
    mLbl.Size                   = UDim2.new(1, -16, 0, 22)
    mLbl.Position               = UDim2.new(0, 10, 0, 26)
    mLbl.BackgroundTransparency = 1
    mLbl.Text                   = message
    mLbl.TextColor3             = Color3.fromRGB(200, 205, 215)
    mLbl.Font                   = Enum.Font.Gotham
    mLbl.TextSize               = 11
    mLbl.TextXAlignment         = Enum.TextXAlignment.Left
    mLbl.TextTransparency       = 1
    mLbl.TextTruncate           = Enum.TextTruncate.AtEnd
    mLbl.Parent                 = toast

    TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
    TweenService:Create(ts,    TweenInfo.new(0.25), { Transparency = 0 }):Play()
    TweenService:Create(tLbl,  TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    TweenService:Create(mLbl,  TweenInfo.new(0.25), { TextTransparency = 0 }):Play()

    task.delay(duration, function()
        if not toast.Parent then return end
        local tOut = TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
        TweenService:Create(ts,    TweenInfo.new(0.3), { Transparency = 1 }):Play()
        TweenService:Create(tLbl,  TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
        TweenService:Create(mLbl,  TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
        tOut:Play()
        tOut.Completed:Connect(function()
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
    _G.InstantFarm      = false
    _G.AutoSell         = false
    _G.AutoEventCandy   = false
    _G.AutoBuy          = false
    _G.ItemESP          = false
    _G.AntiAFK          = false
    _G.StandaloneNoClip = false
    _G.AutoRespawn      = false

    farmSessionId        = farmSessionId + 1
    farmThreadActive     = false
    autoSellSessionId    = autoSellSessionId + 1
    autoSellThreadActive = false
    isBusy               = false

    pcall(stopFlight)
    pcall(cleanupFlight)
    pcall(function()
        if FarmVisual.Decoy or FarmVisual.isActive() then
            FarmVisual.restoreAtSafe()
        end
    end)
    pcall(function() FarmVisual.cleanup() end)
    pcall(function()
        RunService:UnbindFromRenderStep("Phantom_Farm_Decoy_Camera_Before")
        RunService:UnbindFromRenderStep("Phantom_Farm_Decoy_Camera_After")
    end)
    pcall(function()
        local cam = workspace.CurrentCamera
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if cam then
            cam.CameraType = Enum.CameraType.Custom
            if hum then cam.CameraSubject = hum end
        end
    end)
    pcall(clearESP)
    pcall(closeMerchantDialogue)
    pcall(forceUnequipAllTools)

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

local TitleBarBottomLine = Instance.new("Frame")
TitleBarBottomLine.Size             = UDim2.new(1, 0, 0, 1)
TitleBarBottomLine.Position         = UDim2.new(0, 0, 1, -1)
TitleBarBottomLine.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
TitleBarBottomLine.BorderSizePixel  = 0
TitleBarBottomLine.Parent           = TitleBar

local FlagStripe = Instance.new("Frame")
FlagStripe.Size             = UDim2.new(0, 4, 0, 22)
FlagStripe.Position         = UDim2.new(0, 14, 0.5, -11)
FlagStripe.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
FlagStripe.BorderSizePixel  = 0
FlagStripe.Parent           = TitleBar

local FlagCorner = Instance.new("UICorner")
FlagCorner.CornerRadius = UDim.new(0, 2)
FlagCorner.Parent       = FlagStripe

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size                   = UDim2.new(0, 260, 1, 0)
TitleLabel.Position               = UDim2.new(0, 26, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text                   = "UA KILLER HUB  <font color=\"#556070\">|</font>  <font color=\"#00d4ff\">YBA</font>"
TitleLabel.RichText               = true
TitleLabel.TextColor3             = Color3.fromRGB(240, 243, 248)
TitleLabel.Font                   = Enum.Font.GothamBold
TitleLabel.TextSize               = 13
TitleLabel.TextXAlignment         = Enum.TextXAlignment.Left
TitleLabel.Parent                 = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name                   = "CloseBtn"
CloseBtn.Size                   = UDim2.new(0, 28, 0, 28)
CloseBtn.Position               = UDim2.new(1, -36, 0.5, -14)
CloseBtn.BackgroundColor3       = Color3.fromRGB(25, 28, 35)
CloseBtn.BorderSizePixel        = 0
CloseBtn.Text                   = "✕"
CloseBtn.TextColor3             = Color3.fromRGB(160, 170, 185)
CloseBtn.Font                   = Enum.Font.GothamMedium
CloseBtn.TextSize               = 12
CloseBtn.Parent                 = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent       = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    shutdownScript()
end)

local MinBtn = Instance.new("TextButton")
MinBtn.Name                   = "MinBtn"
MinBtn.Size                   = UDim2.new(0, 28, 0, 28)
MinBtn.Position               = UDim2.new(1, -68, 0.5, -14)
MinBtn.BackgroundColor3       = Color3.fromRGB(25, 28, 35)
MinBtn.BorderSizePixel        = 0
MinBtn.Text                   = "—"
MinBtn.TextColor3             = Color3.fromRGB(160, 170, 185)
MinBtn.Font                   = Enum.Font.GothamMedium
MinBtn.TextSize               = 11
MinBtn.Parent                 = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent       = MinBtn

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetHeight = isMinimized and 42 or 360
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 560, 0, targetHeight)
    }):Play()
    MinBtn.Text = isMinimized and "□" or "—"
end)

-- Бічна панель вкладок (Sidebar)
local Sidebar = Instance.new("Frame")
Sidebar.Name             = "Sidebar"
Sidebar.Size             = UDim2.new(0, 135, 1, -42)
Sidebar.Position         = UDim2.new(0, 0, 0, 42)
Sidebar.BackgroundColor3 = Color3.fromRGB(17, 19, 24)
Sidebar.BorderSizePixel  = 0
Sidebar.Parent           = MainFrame

-- Розділювальна лінія між сайдбаром та вмістом (розміщена в MainFrame, щоб не збивати UIListLayout списку)
local SidebarRightLine = Instance.new("Frame")
SidebarRightLine.Size             = UDim2.new(0, 1, 1, -42)
SidebarRightLine.Position         = UDim2.new(0, 134, 0, 42)
SidebarRightLine.BackgroundColor3 = Color3.fromRGB(27, 30, 38)
SidebarRightLine.BorderSizePixel  = 0
SidebarRightLine.Parent           = MainFrame

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.FillDirection        = Enum.FillDirection.Vertical
TabListLayout.HorizontalAlignment  = Enum.HorizontalAlignment.Center
TabListLayout.SortOrder            = Enum.SortOrder.LayoutOrder
TabListLayout.Padding              = UDim.new(0, 3)
TabListLayout.Parent               = Sidebar

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingTop = UDim.new(0, 8)
TabPadding.Parent     = Sidebar

-- Область вмісту сторінок
local ContentArea = Instance.new("Frame")
ContentArea.Name             = "ContentArea"
ContentArea.Size             = UDim2.new(1, -135, 1, -42)
ContentArea.Position         = UDim2.new(0, 135, 0, 42)
ContentArea.BackgroundColor3 = Color3.fromRGB(15, 17, 21)
ContentArea.BorderSizePixel  = 0
ContentArea.Parent           = MainFrame

local pages    = {}
local tabBtns  = {}
local currentTab = nil
local itemToggleControls = {}

local function switchTab(tabName)
    if isShutdown or currentTab == tabName then return end
    currentTab = tabName

    for name, page in pairs(pages) do
        page.Visible = (name == tabName)
    end
    for name, btn in pairs(tabBtns) do
        local isAct = (name == tabName)
        btn.BackgroundColor3 = isAct and Color3.fromRGB(26, 30, 39) or Color3.fromRGB(17, 19, 24)
        local lbl = btn:FindFirstChildOfClass("TextLabel")
        if lbl then
            lbl.TextColor3 = isAct and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(130, 140, 155)
            lbl.Font       = isAct and Enum.Font.GothamBold or Enum.Font.Gotham
        end
        local bar = btn:FindFirstChild("ActiveIndicator")
        if bar then bar.Visible = isAct end
    end
end

local function createTab(tabName, iconText)
    local btn = Instance.new("TextButton")
    btn.Name                   = tabName .. "TabBtn"
    btn.Size                   = UDim2.new(1, -12, 0, 34)
    btn.BackgroundColor3       = Color3.fromRGB(17, 19, 24)
    btn.BorderSizePixel        = 0
    btn.Text                   = ""
    btn.AutoButtonColor        = false
    btn.Parent                 = Sidebar

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent       = btn

    local ind = Instance.new("Frame")
    ind.Name             = "ActiveIndicator"
    ind.Size             = UDim2.new(0, 3, 0, 18)
    ind.Position         = UDim2.new(0, 0, 0.5, -9)
    ind.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
    ind.BorderSizePixel  = 0
    ind.Visible          = false
    ind.Parent           = btn

    local indCorner = Instance.new("UICorner")
    indCorner.CornerRadius = UDim.new(0, 2)
    indCorner.Parent       = ind

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -18, 1, 0)
    lbl.Position               = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = (iconText or "") .. "  " .. tabName
    lbl.TextColor3             = Color3.fromRGB(130, 140, 155)
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 12
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = btn

    btn.MouseButton1Click:Connect(function()
        switchTab(tabName)
    end)

    local page = Instance.new("ScrollingFrame")
    page.Name                   = tabName .. "Page"
    page.Size                   = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel        = 0
    page.ScrollBarThickness     = 3
    page.ScrollBarImageColor3   = Color3.fromRGB(40, 45, 58)
    page.CanvasSize             = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize    = Enum.AutomaticSize.Y
    page.Visible                = false
    page.Parent                 = ContentArea

    local pLayout = Instance.new("UIListLayout")
    pLayout.FillDirection        = Enum.FillDirection.Vertical
    pLayout.HorizontalAlignment  = Enum.HorizontalAlignment.Center
    pLayout.SortOrder            = Enum.SortOrder.LayoutOrder
    pLayout.Padding              = UDim.new(0, 7)
    pLayout.Parent               = page

    local pPadding = Instance.new("UIPadding")
    pPadding.PaddingTop    = UDim.new(0, 10)
    pPadding.PaddingBottom = UDim.new(0, 12)
    pPadding.PaddingLeft   = UDim.new(0, 12)
    pPadding.PaddingRight  = UDim.new(0, 12)
    pPadding.Parent        = page

    pages[tabName]   = page
    tabBtns[tabName] = btn
    return page
end

-- ====================
-- UI ХЕЛПЕРИ ДЛЯ СТОРІНОК
-- ====================
local function createSection(page, tabName, text)
    local sec = Instance.new("Frame")
    sec.Name                   = "Section_" .. text
    sec.Size                   = UDim2.new(1, 0, 0, 24)
    sec.BackgroundTransparency = 1
    sec.Parent                 = page

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text:upper()
    lbl.TextColor3             = Color3.fromRGB(0, 180, 255)
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = 10
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = sec
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local isChecked = defaultVal or false

    local row = Instance.new("Frame")
    row.Name             = "ToggleRow_" .. text
    row.Size             = UDim2.new(1, 0, 0, 36)
    row.BackgroundColor3 = Color3.fromRGB(20, 23, 29)
    row.BorderSizePixel  = 0
    row.Parent           = page

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 6)
    rc.Parent       = row

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -60, 1, 0)
    lbl.Position               = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = Color3.fromRGB(220, 225, 235)
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 12
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row

    local track = Instance.new("TextButton")
    track.Name             = "Track"
    track.Size             = UDim2.new(0, 38, 0, 20)
    track.Position         = UDim2.new(1, -48, 0.5, -10)
    track.BackgroundColor3 = isChecked and Color3.fromRGB(0, 160, 230) or Color3.fromRGB(34, 38, 48)
    track.BorderSizePixel  = 0
    track.Text             = ""
    track.AutoButtonColor  = false
    track.Parent           = row

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent       = track

    local knob = Instance.new("Frame")
    knob.Name             = "Knob"
    knob.Size             = UDim2.new(0, 14, 0, 14)
    knob.Position         = isChecked and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    knob.Parent           = track

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(1, 0)
    kc.Parent       = knob

    local function updateVisual(animate)
        local targetColor = isChecked and Color3.fromRGB(0, 160, 230) or Color3.fromRGB(34, 38, 48)
        local targetPos   = isChecked and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        if animate then
            TweenService:Create(track, TweenInfo.new(0.18), { BackgroundColor3 = targetColor }):Play()
            TweenService:Create(knob,  TweenInfo.new(0.18), { Position = targetPos }):Play()
        else
            track.BackgroundColor3 = targetColor
            knob.Position          = targetPos
        end
    end

    track.MouseButton1Click:Connect(function()
        if isShutdown then return end
        isChecked = not isChecked
        updateVisual(true)
        if callback then
            task.spawn(callback, isChecked)
        end
    end)

    return {
        Set = function(_, val, fireCallback)
            isChecked = val
            updateVisual(false)
            if fireCallback and callback then
                task.spawn(callback, isChecked)
            end
        end,
        Get = function(_) return isChecked end,
        Row = row,
    }
end

local function createSlider(page, tabName, text, min, max, step, defaultVal, callback)
    local curVal = math.clamp(defaultVal or min, min, max)

    local row = Instance.new("Frame")
    row.Name             = "SliderRow_" .. text
    row.Size             = UDim2.new(1, 0, 0, 46)
    row.BackgroundColor3 = Color3.fromRGB(20, 23, 29)
    row.BorderSizePixel  = 0
    row.Parent           = page

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 6)
    rc.Parent       = row

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -70, 0, 20)
    lbl.Position               = UDim2.new(0, 12, 0, 5)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = Color3.fromRGB(220, 225, 235)
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 12
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size                   = UDim2.new(0, 50, 0, 20)
    valLbl.Position               = UDim2.new(1, -58, 0, 5)
    valLbl.BackgroundTransparency = 1
    valLbl.Text                   = tostring(curVal)
    valLbl.TextColor3             = Color3.fromRGB(0, 200, 255)
    valLbl.Font                   = Enum.Font.GothamBold
    valLbl.TextSize               = 12
    valLbl.TextXAlignment         = Enum.TextXAlignment.Right
    valLbl.Parent                 = row

    local track = Instance.new("Frame")
    track.Name             = "SliderTrack"
    track.Size             = UDim2.new(1, -24, 0, 5)
    track.Position         = UDim2.new(0, 12, 0, 31)
    track.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
    track.BorderSizePixel  = 0
    track.Parent           = row

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent       = track

    local fill = Instance.new("Frame")
    fill.Name             = "Fill"
    local pctInit         = (curVal - min) / (max - min)
    fill.Size             = UDim2.new(pctInit, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 160, 230)
    fill.BorderSizePixel  = 0
    fill.Parent           = track

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(1, 0)
    fc.Parent       = fill

    local dragging = false
    local function applyPercent(pct)
        pct = math.clamp(pct, 0, 1)
        local raw = min + (max - min) * pct
        if step and step > 0 then
            raw = math.floor((raw / step) + 0.5) * step
        end
        curVal = math.clamp(raw, min, max)
        local displayPct = (curVal - min) / (max - min)
        fill.Size = UDim2.new(displayPct, 0, 1, 0)
        valLbl.Text = tostring(curVal)
    end

    track.InputBegan:Connect(function(input)
        if isShutdown then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local absX = track.AbsolutePosition.X
            local absW = track.AbsoluteSize.X
            applyPercent((input.Position.X - absX) / absW)
            if callback then task.spawn(callback, curVal) end
        end
    end)

    track.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if isShutdown or not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local absX = track.AbsolutePosition.X
            local absW = track.AbsoluteSize.X
            applyPercent((input.Position.X - absX) / absW)
            if callback then task.spawn(callback, curVal) end
        end
    end))

    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    return {
        Set = function(_, val, fireCallback)
            curVal = math.clamp(val, min, max)
            local pct = (curVal - min) / (max - min)
            fill.Size = UDim2.new(pct, 0, 1, 0)
            valLbl.Text = tostring(curVal)
            if fireCallback and callback then
                task.spawn(callback, curVal)
            end
        end,
        Get = function(_) return curVal end,
    }
end

local function createButton(page, tabName, text, callback)
    local btn = Instance.new("TextButton")
    btn.Name                   = "Btn_" .. text
    btn.Size                   = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3       = Color3.fromRGB(24, 28, 36)
    btn.BorderSizePixel        = 0
    btn.Text                   = text
    btn.TextColor3             = Color3.fromRGB(220, 225, 235)
    btn.Font                   = Enum.Font.GothamMedium
    btn.TextSize               = 12
    btn.AutoButtonColor        = true
    btn.Parent                 = page

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent       = btn

    local bs = Instance.new("UIStroke")
    bs.Color       = Color3.fromRGB(38, 43, 55)
    bs.Thickness   = 1
    bs.Parent      = btn

    btn.MouseButton1Click:Connect(function()
        if isShutdown then return end
        if callback then task.spawn(callback) end
    end)

    return btn
end

local function createStatusLabel(page, tabName, initialText)
    local frame = Instance.new("Frame")
    frame.Size             = UDim2.new(1, 0, 0, 28)
    frame.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
    frame.BorderSizePixel  = 0
    frame.Parent           = page

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(0, 6)
    fc.Parent       = frame

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -16, 1, 0)
    lbl.Position               = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = initialText or "Статус: Очікування"
    lbl.TextColor3             = Color3.fromRGB(150, 160, 175)
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 11
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = frame

    return {
        Set = function(_, text) lbl.Text = text end,
        SetColor = function(_, color) lbl.TextColor3 = color end,
    }
end

-- =======================================================
-- СТВОРЕННЯ СТОРІНОК ТА ПРИВ'ЯЗКА ОРГАНІВ КЕРУВАННЯ
-- =======================================================
local mainPage = createTab("Головна",  "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин",  "💰")
local miscPage = createTab("Інше",     "⚙")

-- СТОРІНКА: ГОЛОВНА
createSection(mainPage, "Головна", "Інформація про персонажа")

local charInfoLabel = Instance.new("TextLabel")
charInfoLabel.Size                   = UDim2.new(1, 0, 0, 48)
charInfoLabel.BackgroundColor3       = Color3.fromRGB(20, 23, 29)
charInfoLabel.BorderSizePixel        = 0
charInfoLabel.Text                   = string.format("Гравець: %s\nСтатус скрипта: Активний", player.Name)
charInfoLabel.TextColor3             = Color3.fromRGB(180, 190, 205)
charInfoLabel.Font                   = Enum.Font.Gotham
charInfoLabel.TextSize               = 12
charInfoLabel.Parent                 = mainPage

local ciCorner = Instance.new("UICorner")
ciCorner.CornerRadius = UDim.new(0, 6)
ciCorner.Parent       = charInfoLabel

createSection(mainPage, "Головна", "Керування конфігурацією")

local autoLoadToggle = createToggle(mainPage, "Головна", "Автозавантаження (AutoLoad при старті)", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    if writefile then
        writefile(autoLoadFile, value and "true" or "false")
    end
    showNotification("AutoLoad", value and "Автозавантаження увімкнено!" or "Автозавантаження вимкнено!", 2.5)
end)

local saveCurrentConfig, loadCurrentConfig

createButton(mainPage, "Головна", "💾 Зберегти налаштування (Config)", function()
    if saveCurrentConfig then saveCurrentConfig() end
end)

createButton(mainPage, "Головна", "📂 Завантажити налаштування (Config)", function()
    if loadCurrentConfig then loadCurrentConfig(false) end
end)

-- СТОРІНКА: АВТОФАРМ
createSection(farmPage, "Автофарм", "Статус та швидкість")

local statusLabel = createStatusLabel(farmPage, "Автофарм", "Статус: Зупинено")

task.spawn(function()
    while not isShutdown do
        task.wait(0.35)
        if isShutdown then break end
        pcall(function() statusLabel:Set("Статус: " .. farmStatusText) end)
    end
end)

instantFarmToggle = createToggle(farmPage, "Автофарм", "Миттєвий фарм (SafeZone Decoy)", _G.InstantFarm, function(val)
    manuallyChanged.InstantFarm = true
    _G.InstantFarm = val
    if not val and FarmVisual.Decoy then
        FarmVisual.cleanup()
    end
end)

flySpeedSlider = createSlider(farmPage, "Автофарм", "Швидкість польоту (FlySpeed)", 50, 300, 5, _G.FlySpeed, function(val)
    _G.FlySpeed = val
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

itemToggleControls = {}
for _, name in ipairs(sortedItems) do
    local isPrio = FARM_PRIORITY[name]
    local displayName = isPrio and ("⭐ " .. name) or name
    local tog = createToggle(farmPage, "Автофарм", displayName, _G.SelectedItems[name], function(val)
        _G.SelectedItems[name] = val
    end)
    itemToggleControls[name] = tog
end

-- СТОРІНКА: МАГАЗИН
createSection(shopPage, "Магазин", "Автоматичний продаж (100с Snapshot Цикл)")

autoSellToggle = createToggle(shopPage, "Магазин", "Авто-продаж непотрібних предметів", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    setAutoSellState(value)
end)

createSection(shopPage, "Магазин", "Хелловін Івент")

local autoCandyToggle = createToggle(shopPage, "Магазин", "Авто-здача івентових цукерок (Jack O' Lantern)", _G.AutoEventCandy, function(val)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = val
end)

createSection(shopPage, "Магазин", "Автокупівля у Merchant")

local autoBuyToggle = createToggle(shopPage, "Магазин", "Автокупівля стріл за монети (2 монети = 1 стріла)", _G.AutoBuy, function(val)
    manuallyChanged.AutoBuy = true
    _G.AutoBuy = val
end)

createButton(shopPage, "Магазин", "Купити Mysterious Arrow зараз", function()
    task.spawn(function()
        buySingleItem("Mysterious Arrow")
        showNotification("Магазин", "Спроба купівлі стріли відправлена!", 2)
    end)
end)

createButton(shopPage, "Магазин", "Купити Rokakaka зараз", function()
    task.spawn(function()
        buySingleItem("Rokakaka")
        showNotification("Магазин", "Спроба купівлі рокакаки відправлена!", 2)
    end)
end)

-- СТОРІНКА: ІНШЕ
createSection(miscPage, "Інше", "Параметри персонажа")

local jumpPowerSlider = createSlider(miscPage, "Інше", "Сила стрибка (JumpPower)", 50, 200, 5, JP_Value, function(val)
    JP_Value = val
    applyJumpPower()
end)

local antiAfkToggle = createToggle(miscPage, "Інше", "Anti-AFK (захист від вильоту)", _G.AntiAFK, function(val)
    manuallyChanged.AntiAFK = true
    _G.AntiAFK = val
    if val then
        if not antiAfkConnection then
            antiAfkConnection = player.Idled:Connect(function()
                if isShutdown or not _G.AntiAFK then return end
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
            trackConnection(antiAfkConnection)
        end
    else
        if antiAfkConnection then
            pcall(function() antiAfkConnection:Disconnect() end)
            antiAfkConnection = nil
        end
    end
end)

local noclipToggle = createToggle(miscPage, "Інше", "NoClip (окремо від фарму)", _G.StandaloneNoClip, function(value)
    manuallyChanged.StandaloneNoClip = true
    _G.StandaloneNoClip = value
    if value then ensureNoClip()
    elseif not _G.ItemFarm and noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end)

local autoRespawnToggle = createToggle(miscPage, "Інше", "Авто-респавн при смерті", _G.AutoRespawn, function(val)
    manuallyChanged.AutoRespawn = true
    _G.AutoRespawn = val
end)

createButton(miscPage, "Інше", "Респавн персонажа (LoadCharacter)", function()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    local remote = remotesFolder and remotesFolder:FindFirstChild("LoadCharacter")
    if remote then
        remote:FireServer()
        showNotification("Персонаж", "Команда респавну відправлена!", 2)
    end
end)

-- Керування видимістю меню на RightShift
trackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if isShutdown or gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end))

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЙ (ЗБЕРЕЖЕННЯ ТА ЧИТАННЯ)
-- =======================================================
local function readConfigFromDisk()
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
        InstantFarm      = _G.InstantFarm,
        FlySpeed         = _G.FlySpeed,
        JumpPower        = JP_Value,
        ItemESP          = _G.ItemESP,
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
    if data.InstantFarm ~= nil and instantFarmToggle then instantFarmToggle:Set(data.InstantFarm, false) _G.InstantFarm = data.InstantFarm end

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
            label = "Миттєвий фарм",
            activate = function(val)
                _G.InstantFarm = (val == true)
                if instantFarmToggle then instantFarmToggle:Set(_G.InstantFarm, false) end
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
-- 1. Гарантовано знімаємо будь-який утримуваний предмет, щоб прибрати кнопку DROP та розблокувати інвентар
forceUnequipAllTools()

-- 2. Первинний сканінг предметів на карті
scanAllItems()

-- 3. Активація головної вкладки
switchTab("Головна")
print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

if shouldAutoLoad and not isShutdown then
    task.spawn(runSteppedAutoLoad)
end

if _G.AutoSell and not isShutdown then
    startAutoSellThread()
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
