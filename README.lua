-- UA Killer Hub | YBA — Версія з автоматично згорнутим GUI на старті
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
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- =======================================================
-- АКТИВАЦІЯ ITEM MAGNITUDE BYPASS
-- =======================================================
local OldIndexItem;
OldIndexItem = hookmetamethod(player.Character.PrimaryPart.Position, "__index", newcclosure(function(self, Key)
    if not checkcaller() and Key:lower() == 'magnitude' and getcallingscript().Name == "ItemSpawn" then
        return 0
    end
                                                
    return OldIndexItem(self, Key)
end))

-- =======================================================
-- CRASH & WALKSPEED BYPASS
-- =======================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FunctionLibrary = require(ReplicatedStorage.Modules.FunctionLibrary)
local OldPcall = FunctionLibrary.pcall

FunctionLibrary.pcall = function(...)
    local args = {...}
    
    if type(args[1]) == 'function' and #getupvalues(args[1]) == 11 then
        return
    end
 
    return OldPcall(...)
end
-- =======================================================

-- ====================
-- СИСТЕМА ФАЙЛІВ ТА ПАПОК
-- ====================
local autoLoadFile = "UAKillerHub/YBA_AutoLoad.txt"
local configFile = "UAKillerHub/YBA_Config.json"
local shouldAutoLoad = false

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
_G.AutoSell = false
_G.AutoEventCandy = false
_G.AutoBuy = false
_G.ItemFarm = false
_G.ItemESP = false
_G.FlySpeed = 150
_G.PickupDistance = 3.5
_G.AntiAFK = false
_G.StandaloneNoClip = false
_G.AutoRespawn = true

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

local bannedCoordinates = {}
local espObjects = {}
local itemCache = {}
local lastCacheRefresh = 0
local CACHE_REFRESH_INTERVAL = 1.25
local BAN_TTL = 45

local farmThreadActive = false
local farmStatusText = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection

-- Зберігаємо посилання на елементи управління для оновлення їхнього візуального стану
local GuiControls = {
    Toggles = {},
    Sliders = {},
    ItemButtons = {}
}

-- ====================
-- ДОПОМІЖНІ ФУНКЦІЇ ФАРМУ
-- ====================
local function setFarmStatus(text)
    farmStatusText = text
end

local function isInvalidItemPart(obj)
    if not obj then return true end
    local current = obj
    while current and current ~= workspace do
        if current:IsA("Backpack") then
            return true
        end
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
            return true
        end
        current = current.Parent
    end
    return false
end

local function cleanupBannedCoordinates()
    local now = tick()
    for i = #bannedCoordinates, 1, -1 do
        if now - bannedCoordinates[i].time > BAN_TTL then
            table.remove(bannedCoordinates, i)
        end
    end
end

local function isCoordinateBanned(pos)
    cleanupBannedCoordinates()
    for _, entry in ipairs(bannedCoordinates) do
        if (pos - entry.pos).Magnitude < 3 then
            return true
        end
    end
    return false
end

local function banCoordinate(pos)
    table.insert(bannedCoordinates, { pos = pos, time = tick() })
end

local function refreshItemCache()
    local now = tick()
    if now - lastCacheRefresh < CACHE_REFRESH_INTERVAL then
        return itemCache
    end

    lastCacheRefresh = now
    table.clear(itemCache)

    local itemSpawns = workspace:FindFirstChild("Item_Spawns")
    local itemsFolder = itemSpawns and itemSpawns:FindFirstChild("Items")
    if not itemsFolder then
        return itemCache
    end

    for _, model in ipairs(itemsFolder:GetChildren()) do
        if model:IsA("Model") and _G.SelectedItems[model.Name] then
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") and not isInvalidItemPart(part) then
                    table.insert(itemCache, {
                        model = model,
                        part = part,
                        name = model.Name,
                    })
                    break
                end
            end
        end
    end

    return itemCache
end

local function getNearestItem()
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local myPos = rootPart.Position
    local items = refreshItemCache()
    local bestTarget = nil
    local shortestDist = math.huge

    for i = #items, 1, -1 do
        local entry = items[i]
        if not entry.model:IsDescendantOf(workspace) or not entry.part:IsDescendantOf(workspace) or isInvalidItemPart(entry.part) then
            table.remove(items, i)
        else
            local pos = entry.part.Position
            if not isCoordinateBanned(pos) then
                local dist = (myPos - pos).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    bestTarget = entry
                end
            end
        end
    end

    return bestTarget
end

-- ====================
-- ESP СИСТЕМА
-- ====================
local function clearEspForModel(model)
    local esp = espObjects[model]
    if esp then
        pcall(function()
            if esp.highlight then esp.highlight:Destroy() end
            if esp.billboard then esp.billboard:Destroy() end
        end)
        espObjects[model] = nil
    end
end

local function clearAllEsp()
    for model in pairs(espObjects) do
        clearEspForModel(model)
    end
end

local function createEspForEntry(entry)
    local model = entry.model
    local part = entry.part
    if espObjects[model] then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "UA_ItemHighlight"
    highlight.Adornee = model
    highlight.FillColor = Color3.fromRGB(139, 124, 246)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "UA_ItemTag"
    billboard.Adornee = part
    billboard.Size = UDim2.new(0, 120, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Text = entry.name
    label.Parent = billboard

    billboard.Parent = model

    espObjects[model] = {
        highlight = highlight,
        billboard = billboard,
        model = model,
    }
end

local function updateEsp()
    if not _G.ItemESP then
        clearAllEsp()
        return
    end

    local items = refreshItemCache()
    local validModels = {}

    for _, entry in ipairs(items) do
        if entry.model:IsDescendantOf(workspace) and entry.part:IsDescendantOf(workspace) and not isInvalidItemPart(entry.part) then
            validModels[entry.model] = true
            createEspForEntry(entry)
        end
    end

    for model in pairs(espObjects) do
        if not validModels[model] or not model:IsDescendantOf(workspace) then
            clearEspForModel(model)
        end
    end
end

-- ====================
-- СИСТЕМА ПОЛЬОТУ
-- ====================
local function startFlying(rootPart)
    if flightState and flightState.active then return end

    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bodyVelocity.Velocity = Vector3.zero
    bodyVelocity.Parent = rootPart

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bodyGyro.CFrame = rootPart.CFrame
    bodyGyro.Parent = rootPart

    flightState = {
        active = true,
        bodyVelocity = bodyVelocity,
        bodyGyro = bodyGyro,
        rootPart = rootPart,
    }
end

local function stopFlying()
    if not flightState then return end
    if flightState.bodyVelocity then flightState.bodyVelocity:Destroy() end
    if flightState.bodyGyro then flightState.bodyGyro:Destroy() end
    flightState = nil
end

local function flyTo(destination, speed, arrivalDist, timeout)
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    startFlying(rootPart)

    local startedAt = tick()
    local threshold = arrivalDist or 3.5
    local maxTime = timeout or 15

    while flightState and flightState.active do
        if not character or not character.Parent or not rootPart:IsDescendantOf(workspace) then
            stopFlying()
            return false
        end

        local currentPos = rootPart.Position
        local delta = destination - currentPos
        local dist = delta.Magnitude

        if dist <= threshold then
            flightState.bodyVelocity.Velocity = Vector3.zero
            return true
        end

        if tick() - startedAt > maxTime then
            flightState.bodyVelocity.Velocity = Vector3.zero
            return false
        end

        local moveDir = delta.Unit
        flightState.bodyVelocity.Velocity = moveDir * speed
        flightState.bodyGyro.CFrame = CFrame.new(currentPos, currentPos + moveDir)

        RunService.Heartbeat:Wait()
    end

    return false
end

-- ====================
-- NOCLIP ТА АНТИ-AFK
-- ====================
local function setNoclip(enable)
    if enable then
        if not noclipConnection then
            noclipConnection = RunService.Stepped:Connect(function()
                local character = player.Character
                if character then
                    for _, part in ipairs(character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        end
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
        local character = player.Character
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end
    end
end

local function setAntiAfk(enable)
    if enable then
        if not antiAfkConnection then
            antiAfkConnection = player.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    else
        if antiAfkConnection then
            antiAfkConnection:Disconnect()
            antiAfkConnection = nil
        end
    end
end

-- ====================
-- ПІДБИРАННЯ ПРЕДМЕТІВ
-- ====================
local function isItemStillPresent(entry)
    if not entry or not entry.model or not entry.part then return false end
    if not entry.model:IsDescendantOf(workspace) or not entry.part:IsDescendantOf(workspace) then
        return false
    end
    if isInvalidItemPart(entry.part) then
        return false
    end
    return true
end

local function attemptItemPickup(entry)
    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart or not isItemStillPresent(entry) then return false end

    setFarmStatus("Збір: " .. entry.name)

    local targetPos = entry.part.Position
    local originalY = rootPart.Position.Y
    local approachPos = Vector3.new(targetPos.X, originalY, targetPos.Z)

    setNoclip(true)

    local success = flyTo(approachPos, _G.FlySpeed, _G.PickupDistance, 8)
    if not success then
        setFarmStatus("Не долетів")
        stopFlying()
        banCoordinate(targetPos)
        return false
    end

    success = flyTo(targetPos + Vector3.new(0, 1.5, 0), math.min(_G.FlySpeed, 40), 2.5, 3)
    if not success then
        stopFlying()
        banCoordinate(targetPos)
        return false
    end

    local settledPos = rootPart.Position
    local promptFound = false

    for _, desc in ipairs(entry.model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            promptFound = true
            pcall(function()
                fireproximityprompt(desc)
            end)
            break
        end
    end

    if not promptFound then
        for _, desc in ipairs(entry.part:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                promptFound = true
                pcall(function()
                    fireproximityprompt(desc)
                end)
                break
            end
        end
    end

    if not promptFound then
        pcall(function()
            if typeof(VirtualInputManager) == "Instance" then
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.1)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end
        end)
    end

    local waitStart = tick()
    while tick() - waitStart < 0.6 do
        if not isItemStillPresent(entry) then
            setFarmStatus("Зібрано: " .. entry.name)
            stopFlying()
            return true
        end
        task.wait(0.05)
    end

    banCoordinate(targetPos)
    setFarmStatus("Невдача збору")
    stopFlying()
    return false
end

-- ====================
-- ОСНОВНИЙ ПОТІК ФАРМУ
-- ====================
local function startFarmThread()
    if farmThreadActive then return end
    farmThreadActive = true

    task.spawn(function()
        while _G.ItemFarm do
            local character = player.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")

            if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
                setFarmStatus("Очікування персонажа...")
                task.wait(1)
            else
                local target = getNearestItem()
                if target then
                    attemptItemPickup(target)
                else
                    setFarmStatus("Пошук предметів...")
                    task.wait(0.5)
                end
            end
            task.wait(0.1)
        end

        stopFlying()
        if not _G.StandaloneNoClip then
            setNoclip(false)
        end
        farmThreadActive = false
        setFarmStatus("Вимкнено")
    end)
end

local function setItemFarmState(state)
    _G.ItemFarm = state
    if state then
        startFarmThread()
    else
        stopFlying()
        if not _G.StandaloneNoClip then
            setNoclip(false)
        end
        setFarmStatus("Вимкнено")
    end
end

-- ====================
-- ДІАЛОГОВІ СИСТЕМИ (HALLOWEEN ТА ПРОДАЖ)
-- ====================
local function getDialogueGui()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end

    local hud = pg:FindFirstChild("HUD")
    if hud then
        local dialogue = hud:FindFirstChild("Dialogue")
        if dialogue then return dialogue end
    end

    for _, name in ipairs({ "DialogueGui", "Dialogue", "NPCDialogue", "HUD" }) do
        local g = pg:FindFirstChild(name)
        if g then return g end
    end

    for _, c in ipairs(pg:GetChildren()) do
        if c:IsA("ScreenGui") and c.Name:lower():find("dialog") then
            return c
        end
    end

    return hud or pg
end

local function isGuiElementVisible(elem)
    if not elem or not elem:IsDescendantOf(game) then return false end
    local current = elem
    while current and current:IsA("GuiObject") do
        if not current.Visible then return false end
        current = current.Parent
    end
    return true
end

local function fireGuiClick(btn)
    pcall(function()
        local events = {"MouseButton1Click", "MouseButton1Down", "Activated"}
        for _, ev in ipairs(events) do
            if btn[ev] then
                for _, conn in ipairs(getconnections(btn[ev])) do
                    conn:Fire()
                end
            end
        end
    end)
    pcall(function()
        if typeof(VirtualInputManager) == "Instance" then
            local pos = btn.AbsolutePosition + (btn.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end
    end)
end

local function clickDialogueElement(elem)
    if not elem then return false end

    if elem:IsA("TextButton") or elem:IsA("ImageButton") then
        fireGuiClick(elem)
        return true
    end

    local btn = elem:FindFirstChildWhichIsA("TextButton", true) or elem:FindFirstChildWhichIsA("ImageButton", true)
    if btn and isGuiElementVisible(btn) then
        fireGuiClick(btn)
        return true
    end

    local parent = elem.Parent
    while parent and parent:IsA("GuiObject") do
        if parent:IsA("TextButton") or parent:IsA("ImageButton") then
            fireGuiClick(parent)
            return true
        end
        parent = parent.Parent
    end

    pcall(function()
        if typeof(VirtualInputManager) == "Instance" then
            local pos = elem.AbsolutePosition + (elem.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end
    end)
    return true
end

local function findJackDialogue()
    local gui = getDialogueGui()
    if not gui then return nil end

    local hasJack, hasPoints   = false, false
    local continueElem, pointsElem, fallbackFrame = nil, nil, nil

    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local txt   = desc.Text or ""
            local lower = txt:lower()

            if lower:find("jack") or lower:find("cauldron specter") then
                hasJack = true
            end
            if lower:find("point") then
                hasPoints = true
                pointsElem = desc
            end
            if lower:find("continue") then
                continueElem = desc
            end
        end
        if desc:IsA("Frame") and desc.Name:lower():find("dialog") and isGuiElementVisible(desc) then
            fallbackFrame = desc
        end
    end

    if hasJack or hasPoints or continueElem then
        local target = continueElem
        if not target and pointsElem then
            local p = pointsElem.Parent
            target = (p and p:IsA("GuiObject")) and p or pointsElem
        end
        if not target then
            target = fallbackFrame or gui
        end
        return {
            gui          = gui,
            continueElem = continueElem,
            pointsElem   = pointsElem,
            target       = target,
            hasPoints    = hasPoints,
            hasJack      = hasJack,
        }
    end

    return nil
end

local function closeJackDialogue()
    local d = findJackDialogue()
    if not d then return false end

    if d.continueElem and isGuiElementVisible(d.continueElem) then
        clickDialogueElement(d.continueElem)
    elseif d.pointsElem and isGuiElementVisible(d.pointsElem) then
        local p = d.pointsElem.Parent
        if p and p:IsA("GuiObject") and isGuiElementVisible(p) then
            clickDialogueElement(p)
        else
            clickDialogueElement(d.pointsElem)
        end
    elseif d.target then
        clickDialogueElement(d.target)
    end

    task.wait(0.3)

    pcall(function()
        if typeof(VirtualInputManager) == "Instance" then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end
    end)

    return findJackDialogue() == nil
end

local function submitAllCandies()
    local candyNames = {
        ["Candy"]        = true,
        ["Blue Candy"]   = true,
        ["Green Candy"]  = true,
        ["Red Candy"]    = true,
        ["Yellow Candy"] = true,
    }

    local function getJackNpc()
        local npcs = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("NPC") or workspace
        for _, m in ipairs(npcs:GetDescendants()) do
            if m:IsA("Model") and (m.Name:lower():find("jack") or m.Name:lower():find("cauldron specter")) then
                return m
            end
        end
        return nil
    end

    local jack = getJackNpc()
    local prompt = nil
    if jack then
        for _, p in ipairs(jack:GetDescendants()) do
            if p:IsA("ProximityPrompt") then
                prompt = p
                break
            end
        end
    end

    local function interactJack()
        if prompt then
            pcall(function() fireproximityprompt(prompt) end)
        else
            pcall(function()
                if typeof(VirtualInputManager) == "Instance" then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end
            end)
        end
    end

    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    if not backpack then return end

    local toSubmit = {}
    for _, item in ipairs(backpack:GetChildren()) do
        if candyNames[item.Name] then
            table.insert(toSubmit, item)
        end
    end
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and candyNames[item.Name] then
                table.insert(toSubmit, item)
            end
        end
    end

    for _, candy in ipairs(toSubmit) do
        if not _G.AutoEventCandy then break end
        if candy.Parent == backpack and character then
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(candy) end
            task.wait(0.3)
        end

        interactJack()
        task.wait(0.5)

        local closed = false
        for _ = 1, 6 do
            if closeJackDialogue() then
                closed = true
                break
            end
            task.wait(0.2)
        end

        task.wait(0.3)
    end

    for _ = 1, 4 do
        if not findJackDialogue() then break end
        closeJackDialogue()
        task.wait(0.25)
    end
end

-- ====================
-- AUTO SELL
-- ====================
local function findMerchantDialogue()
    local gui = getDialogueGui()
    if not gui then return nil end

    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local txt = (desc.Text or ""):lower()
            if txt:find("merchant") or txt:find("sell") or txt:find("deal") or txt:find("offer") then
                return desc
            end
        end
    end
    return nil
end

local function closeMerchantDialogue()
    local gui = getDialogueGui()
    if not gui then return end

    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("TextButton") then
            local txt = (desc.Text or ""):lower()
            if txt:find("bye") or txt:find("leave") or txt:find("close") or txt:find("no") or txt:find("cancel") then
                clickDialogueElement(desc)
                task.wait(0.2)
                return
            end
        end
    end

    pcall(function()
        if typeof(VirtualInputManager) == "Instance" then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        end
    end)
end

local function isItemSold(itemName, initialCount)
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    local currentCount = 0

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item.Name == itemName then currentCount = currentCount + 1 end
        end
    end
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and item.Name == itemName then currentCount = currentCount + 1 end
        end
    end

    return currentCount < initialCount
end

local function sellItem(itemName)
    local character = player.Character
    local backpack = player:FindFirstChild("Backpack")
    if not character or not backpack then return false end

    local tool = backpack:FindFirstChild(itemName) or character:FindFirstChild(itemName)
    if not tool then return false end

    local countBefore = 0
    for _, item in ipairs(backpack:GetChildren()) do
        if item.Name == itemName then countBefore = countBefore + 1 end
    end
    for _, item in ipairs(character:GetChildren()) do
        if item:IsA("Tool") and item.Name == itemName then countBefore = countBefore + 1 end
    end

    local hum = character:FindFirstChildOfClass("Humanoid")
    if tool.Parent == backpack and hum then
        hum:EquipTool(tool)
        task.wait(0.25)
    end

    local function getMerchantNpc()
        local npcs = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("NPC") or workspace
        for _, m in ipairs(npcs:GetDescendants()) do
            if m:IsA("Model") and (m.Name:lower():find("merchant") or m.Name:lower():find("shop")) then
                return m
            end
        end
        return nil
    end

    local merchant = getMerchantNpc()
    local prompt = nil
    if merchant then
        for _, p in ipairs(merchant:GetDescendants()) do
            if p:IsA("ProximityPrompt") then prompt = p; break end
        end
    end

    if prompt then
        pcall(function() fireproximityprompt(prompt) end)
    else
        pcall(function()
            if typeof(VirtualInputManager) == "Instance" then
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end
        end)
    end

    task.wait(0.4)

    local gui = getDialogueGui()
    if gui then
        for _, desc in ipairs(gui:GetDescendants()) do
            if desc:IsA("TextButton") then
                local txt = (desc.Text or ""):lower()
                if txt:find("sell") or txt:find("deal") or txt:find("yes") then
                    clickDialogueElement(desc)
                    break
                end
            end
        end
    end

    local sold = false
    local checkStart = tick()
    while tick() - checkStart < 1.5 do
        if isItemSold(itemName, countBefore) then
            sold = true
            break
        end
        task.wait(0.1)
    end

    closeMerchantDialogue()
    return sold
end

local function runAutoSell()
    local sellableList = {
        "Ancient Scroll", "Caesar's Headband", "Clackers", "Diamond",
        "Gold Coin", "Gold Umbrella", "Quinton's Glove", "Steel Ball",
        "Stone Mask", "Zepellin's Headband", "Zeppeli's Hat"
    }

    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end

    local sellQueue = {}
    for _, item in ipairs(backpack:GetChildren()) do
        if _G.SelectedItems[item.Name] then
            for _, sName in ipairs(sellableList) do
                if item.Name == sName then
                    table.insert(sellQueue, item.Name)
                    break
                end
            end
        end
    end

    for _, itemName in ipairs(sellQueue) do
        if not _G.AutoSell then break end
        sellItem(itemName)
        task.wait(0.3)
    end
end

-- ====================
-- СИСТЕМА КОНФІГУРАЦІЇ
-- ====================
local function saveCurrentConfig()
    if not writefile then return false end

    local configData = {
        AutoSell         = _G.AutoSell or false,
        AutoEventCandy   = _G.AutoEventCandy or false,
        AutoBuy          = _G.AutoBuy or false,
        ItemFarm         = _G.ItemFarm or false,
        ItemESP          = _G.ItemESP or false,
        FlySpeed         = _G.FlySpeed or 150,
        PickupDistance   = _G.PickupDistance or 3.5,
        AntiAFK          = _G.AntiAFK or false,
        StandaloneNoClip = _G.StandaloneNoClip or false,
        AutoRespawn      = _G.AutoRespawn ~= false,
        SelectedItems    = _G.SelectedItems or {},
    }

    local success, err = pcall(function()
        local json = HttpService:JSONEncode(configData)
        writefile(configFile, json)
    end)

    return success
end

local function loadCurrentConfig()
    if not isfile or not readfile then return false end
    if not isfile(configFile) then return false end

    local success, content = pcall(function()
        return readfile(configFile)
    end)
    if not success or not content then return false end

    local parseSuccess, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not parseSuccess or type(data) ~= "table" then return false end

    if data.FlySpeed ~= nil then
        _G.FlySpeed = tonumber(data.FlySpeed) or _G.FlySpeed
        if GuiControls.Sliders["FlySpeed"] then
            GuiControls.Sliders["FlySpeed"]:Set(_G.FlySpeed)
        end
    end

    if data.PickupDistance ~= nil then
        _G.PickupDistance = tonumber(data.PickupDistance) or _G.PickupDistance
        if GuiControls.Sliders["PickupDistance"] then
            GuiControls.Sliders["PickupDistance"]:Set(_G.PickupDistance)
        end
    end

    if type(data.SelectedItems) == "table" then
        for itemName, state in pairs(data.SelectedItems) do
            if _G.SelectedItems[itemName] ~= nil then
                _G.SelectedItems[itemName] = (state == true)
                if GuiControls.ItemButtons[itemName] then
                    GuiControls.ItemButtons[itemName]:Set(state == true)
                end
            end
        end
    end

    local boolKeys = {
        "AutoSell", "AutoEventCandy", "AutoBuy", "ItemFarm",
        "ItemESP", "AntiAFK", "StandaloneNoClip", "AutoRespawn"
    }

    for _, key in ipairs(boolKeys) do
        if data[key] ~= nil then
            local val = (data[key] == true)
            if key == "ItemFarm" then
                setItemFarmState(val)
                if GuiControls.Toggles[key] then
                    GuiControls.Toggles[key]:Set(val, false)
                end
            else
                _G[key] = val
                if GuiControls.Toggles[key] then
                    GuiControls.Toggles[key]:Set(val)
                end
            end
        end
    end

    return true
end

-- ====================
-- ПОЕТАПНЕ АВТОЗАВАНТАЖЕННЯ (Auto Load Config)
-- ====================
local function runSteppedAutoLoad()
    print("[UA Killer Hub | AutoLoad] Початок відліку 15 секунд...")
    showNotification("UA Killer Hub", "Автозавантаження налаштувань почнеться через 15 секунд...", 4)
    task.wait(15)

    if not isfile or not readfile or not isfile(configFile) then
        print("[UA Killer Hub | AutoLoad] Файл конфігурації не знайдено.")
        return
    end

    local success, content = pcall(function() return readfile(configFile) end)
    if not success or not content then return end

    local parseSuccess, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not parseSuccess or type(data) ~= "table" then return end

    print("[UA Killer Hub | AutoLoad] Файл конфігурації зчитано, починається відновлення...")
    showNotification("UA Killer Hub", "Відновлення збережених налаштувань...", 3)

    if data.FlySpeed ~= nil then
        _G.FlySpeed = tonumber(data.FlySpeed) or _G.FlySpeed
        if GuiControls.Sliders["FlySpeed"] then
            GuiControls.Sliders["FlySpeed"]:Set(_G.FlySpeed)
        end
    end

    if data.PickupDistance ~= nil then
        _G.PickupDistance = tonumber(data.PickupDistance) or _G.PickupDistance
        if GuiControls.Sliders["PickupDistance"] then
            GuiControls.Sliders["PickupDistance"]:Set(_G.PickupDistance)
        end
    end

    if type(data.SelectedItems) == "table" then
        for itemName, state in pairs(data.SelectedItems) do
            if _G.SelectedItems[itemName] ~= nil then
                _G.SelectedItems[itemName] = (state == true)
                if GuiControls.ItemButtons[itemName] then
                    GuiControls.ItemButtons[itemName]:Set(state == true)
                end
            end
        end
    end

    local steppedKeys = {
        { key = "ItemESP",          name = "Item ESP" },
        { key = "AntiAFK",          name = "Anti-AFK" },
        { key = "StandaloneNoClip", name = "NoClip" },
        { key = "AutoRespawn",      name = "Auto Respawn" },
        { key = "AutoBuy",          name = "Auto Buy" },
        { key = "AutoEventCandy",   name = "Auto Candy" },
        { key = "AutoSell",         name = "Auto Sell" },
        { key = "ItemFarm",         name = "Item Farm" },
    }

    for _, entry in ipairs(steppedKeys) do
        local key = entry.key
        local savedVal = data[key]

        if savedVal == true then
            if _G[key] == true then
                print("[UA Killer Hub | AutoLoad] " .. entry.name .. " вже активовано гравцем, пропуск.")
            else
                print("[UA Killer Hub | AutoLoad] Відновлення стану " .. entry.name .. " -> true")

                if key == "ItemFarm" then
                    setItemFarmState(true)
                    if GuiControls.Toggles[key] then
                        GuiControls.Toggles[key]:Set(true, false)
                    end
                else
                    _G[key] = true
                    if GuiControls.Toggles[key] then
                        GuiControls.Toggles[key]:Set(true)
                    end
                end

                showNotification("Auto Load", entry.name .. " відновлено", 1.5)
                task.wait(1)
            end
        end
    end

    showNotification("UA Killer Hub", "Усі збережені налаштування успішно відновлено!", 3.5)
    print("[UA Killer Hub | AutoLoad] Поетапне відновлення завершено.")
end

-- =======================================================
-- СТВОРЕННЯ ГРАФІЧНОГО ІНТЕРФЕЙСУ (MonHub Style)
-- =======================================================
local function getSafeGuiParent()
    local success, core = pcall(function()
        return CoreGui
    end)
    if success and core then
        local test = pcall(function()
            local f = Instance.new("Folder")
            f.Parent = core
            f:Destroy()
        end)
        if test then return core end
    end
    return player:WaitForChild("PlayerGui", 10) or player:FindFirstChildOfClass("PlayerGui")
end

local targetGuiParent = getSafeGuiParent()

pcall(function()
    if CoreGui then
        local old = CoreGui:FindFirstChild("UAKillerHub_GUI")
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

-- ГОЛОВНЕ ВІКНО: Початковий стан — Згорнутий (520x42)
local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 520, 0, 42)
MainFrame.Position         = UDim2.new(0.5, -260, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
MainFrame.BorderSizePixel  = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent       = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color        = Color3.fromRGB(42, 45, 58)
MainStroke.Thickness    = 1
MainStroke.Parent       = MainFrame

-- СИСТЕМА СПОВІЩЕНЬ (Toast Notifications)
local NotificationContainer = Instance.new("Frame")
NotificationContainer.Name                   = "NotificationContainer"
NotificationContainer.Size                   = UDim2.new(0, 260, 1, -20)
NotificationContainer.Position               = UDim2.new(1, -270, 0, 10)
NotificationContainer.BackgroundTransparency = 1
NotificationContainer.Parent                 = ScreenGui

local NotifList = Instance.new("UIListLayout")
NotifList.SortOrder            = Enum.SortOrder.LayoutOrder
NotifList.VerticalAlignment    = Enum.VerticalAlignment.Bottom
NotifList.HorizontalAlignment  = Enum.HorizontalAlignment.Right
NotifList.Padding              = UDim.new(0, 8)
NotifList.Parent               = NotificationContainer

function showNotification(title, text, duration)
    duration = duration or 3
    task.spawn(function()
        local box = Instance.new("Frame")
        box.Size                   = UDim2.new(0, 250, 0, 60)
        box.BackgroundColor3       = Color3.fromRGB(28, 31, 40)
        box.BorderSizePixel        = 0
        box.BackgroundTransparency = 1
        box.Parent                 = NotificationContainer

        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
        local stroke = Instance.new("UIStroke", box)
        stroke.Color        = Color3.fromRGB(139, 124, 246)
        stroke.Thickness    = 1
        stroke.Transparency = 1

        local accent = Instance.new("Frame", box)
        accent.Size                   = UDim2.new(0, 4, 1, 0)
        accent.BackgroundColor3       = Color3.fromRGB(139, 124, 246)
        accent.BorderSizePixel        = 0
        accent.BackgroundTransparency = 1
        Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

        local tLabel = Instance.new("TextLabel", box)
        tLabel.Size                   = UDim2.new(1, -16, 0, 20)
        tLabel.Position               = UDim2.new(0, 12, 0, 8)
        tLabel.BackgroundTransparency = 1
        tLabel.Text                   = title
        tLabel.Font                   = Enum.Font.GothamBold
        tLabel.TextSize               = 13
        tLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
        tLabel.TextXAlignment         = Enum.TextXAlignment.Left
        tLabel.TextTransparency       = 1

        local dLabel = Instance.new("TextLabel", box)
        dLabel.Size                   = UDim2.new(1, -16, 0, 26)
        dLabel.Position               = UDim2.new(0, 12, 0, 26)
        dLabel.BackgroundTransparency = 1
        dLabel.Text                   = text
        dLabel.Font                   = Enum.Font.Gotham
        dLabel.TextSize               = 11
        dLabel.TextColor3             = Color3.fromRGB(160, 165, 175)
        dLabel.TextXAlignment         = Enum.TextXAlignment.Left
        dLabel.TextWrapped            = true
        dLabel.TextTransparency       = 1

        local tiIn = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(box, tiIn, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(stroke, tiIn, { Transparency = 0 }):Play()
        TweenService:Create(accent, tiIn, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(tLabel, tiIn, { TextTransparency = 0 }):Play()
        TweenService:Create(dLabel, tiIn, { TextTransparency = 0 }):Play()

        task.wait(duration)

        local tiOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(box, tiOut, { BackgroundTransparency = 1 }):Play()
        TweenService:Create(stroke, tiOut, { Transparency = 1 }):Play()
        TweenService:Create(accent, tiOut, { BackgroundTransparency = 1 }):Play()
        TweenService:Create(tLabel, tiOut, { TextTransparency = 1 }):Play()
        local lastTween = TweenService:Create(dLabel, tiOut, { TextTransparency = 1 })
        lastTween:Play()
        lastTween.Completed:Wait()

        box:Destroy()
    end)
end

-- ВЕРХНЯ ПАНЕЛЬ (TitleBar)
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
TitleLine.BackgroundColor3 = Color3.fromRGB(42, 45, 58)
TitleLine.BorderSizePixel  = 0

local TitleText = Instance.new("TextLabel", TitleBar)
TitleText.Size             = UDim2.new(0, 140, 1, 0)
TitleText.Position         = UDim2.new(0, 14, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text             = "UA Killer Hub"
TitleText.Font             = Enum.Font.GothamBold
TitleText.TextSize         = 14
TitleText.TextColor3       = Color3.fromRGB(255, 255, 255)
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

-- Перетягування вікна
local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Початковий стан isMinimized = true (згорнуто)
local isMinimized = true
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetSize = isMinimized and UDim2.new(0, 520, 0, 42) or UDim2.new(0, 520, 0, 400)
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = targetSize }):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    showNotification("UA Killer Hub", "Натисніть RightShift, щоб знову відкрити меню", 3.5)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- БІЧНА ПАНЕЛЬ НАВІГАЦІЇ (Sidebar)
local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Name             = "Sidebar"
Sidebar.Size             = UDim2.new(0, 115, 1, -42)
Sidebar.Position         = UDim2.new(0, 0, 0, 42)
Sidebar.BackgroundColor3 = Color3.fromRGB(19, 21, 26)
Sidebar.BorderSizePixel  = 0

local SidebarSep = Instance.new("Frame", Sidebar)
SidebarSep.Size             = UDim2.new(0, 1, 1, 0)
SidebarSep.Position         = UDim2.new(1, -1, 0, 0)
SidebarSep.BackgroundColor3 = Color3.fromRGB(42, 45, 58)
SidebarSep.BorderSizePixel  = 0

local SidebarList = Instance.new("UIListLayout", Sidebar)
SidebarList.SortOrder = Enum.SortOrder.LayoutOrder
SidebarList.Padding   = UDim.new(0, 4)

local SidebarPad = Instance.new("UIPadding", Sidebar)
SidebarPad.PaddingTop    = UDim.new(0, 8)
SidebarPad.PaddingLeft   = UDim.new(0, 6)
SidebarPad.PaddingRight  = UDim.new(0, 6)

-- ОСНОВНА ОБЛАСТЬ КОНТЕНТУ (ContentArea)
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Name                   = "ContentArea"
ContentArea.Size                   = UDim2.new(1, -115, 1, -42)
ContentArea.Position               = UDim2.new(0, 115, 0, 42)
ContentArea.BackgroundTransparency = 1

local pages = {}
local tabButtons = {}
local currentTab = nil

local function switchTab(tabName)
    if currentTab == tabName then return end
    currentTab = tabName

    for name, page in pairs(pages) do
        page.Visible = (name == tabName)
    end

    for name, btn in pairs(tabButtons) do
        local isAct = (name == tabName)
        local targetBg   = isAct and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(19, 21, 26)
        local targetText = isAct and Color3.fromRGB(255, 255, 255)  or Color3.fromRGB(160, 165, 175)
        TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = targetBg, TextColor3 = targetText }):Play()
    end
end

local function createTab(tabName, order)
    local btn = Instance.new("TextButton", Sidebar)
    btn.Name             = "Tab_" .. tabName
    btn.Size             = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = Color3.fromRGB(19, 21, 26)
    btn.Text             = tabName
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 12
    btn.TextColor3       = Color3.fromRGB(160, 165, 175)
    btn.LayoutOrder      = order
    btn.BorderSizePixel  = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local page = Instance.new("ScrollingFrame", ContentArea)
    page.Name                   = "Page_" .. tabName
    page.Size                   = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel        = 0
    page.ScrollBarThickness     = 3
    page.ScrollBarImageColor3   = Color3.fromRGB(139, 124, 246)
    page.CanvasSize             = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize    = Enum.AutomaticSize.Y
    page.Visible                = false

    local pageList = Instance.new("UIListLayout", page)
    pageList.SortOrder = Enum.SortOrder.LayoutOrder
    pageList.Padding   = UDim.new(0, 8)

    local pagePad = Instance.new("UIPadding", page)
    pagePad.PaddingTop    = UDim.new(0, 12)
    pagePad.PaddingBottom = UDim.new(0, 12)
    pagePad.PaddingLeft   = UDim.new(0, 14)
    pagePad.PaddingRight  = UDim.new(0, 14)

    btn.MouseButton1Click:Connect(function()
        switchTab(tabName)
    end)

    pages[tabName]      = page
    tabButtons[tabName] = btn
    return page
end

-- ====================
-- UI КОМПОНЕНТИ
-- ====================
local function addSection(page, titleText)
    local sec = Instance.new("Frame", page)
    sec.Size                   = UDim2.new(1, 0, 0, 24)
    sec.BackgroundTransparency = 1

    local label = Instance.new("TextLabel", sec)
    label.Size                   = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text                   = string.upper(titleText)
    label.Font                   = Enum.Font.GothamBold
    label.TextSize               = 10
    label.TextColor3             = Color3.fromRGB(139, 124, 246)
    label.TextXAlignment         = Enum.TextXAlignment.Left

    local line = Instance.new("Frame", sec)
    line.Size             = UDim2.new(1, 0, 0, 1)
    line.Position         = UDim2.new(0, 0, 1, -1)
    line.BackgroundColor3 = Color3.fromRGB(42, 45, 58)
    line.BorderSizePixel  = 0
end

local function addToggle(page, labelText, defaultVal, callback, controlKey)
    local frame = Instance.new("Frame", page)
    frame.Size             = UDim2.new(1, 0, 0, 38)
    frame.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
    frame.BorderSizePixel  = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local title = Instance.new("TextLabel", frame)
    title.Size                   = UDim2.new(1, -60, 1, 0)
    title.Position               = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text                   = labelText
    title.Font                   = Enum.Font.Gotham
    title.TextSize               = 12
    title.TextColor3             = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment         = Enum.TextXAlignment.Left

    local switch = Instance.new("Frame", frame)
    switch.Size             = UDim2.new(0, 36, 0, 18)
    switch.Position         = UDim2.new(1, -48, 0.5, -9)
    switch.BackgroundColor3 = defaultVal and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 45, 58)
    switch.BorderSizePixel  = 0
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", switch)
    knob.Size             = UDim2.new(0, 14, 0, 14)
    knob.Position         = defaultVal and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local clickBtn = Instance.new("TextButton", frame)
    clickBtn.Size                   = UDim2.new(1, 0, 1, 0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text                   = ""

    local state = defaultVal

    local function updateVisual(val)
        local targetColor = val and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 45, 58)
        local targetPos   = val and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        TweenService:Create(switch, TweenInfo.new(0.2), { BackgroundColor3 = targetColor }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), { Position = targetPos }):Play()
    end

    clickBtn.MouseButton1Click:Connect(function()
        state = not state
        updateVisual(state)
        pcall(callback, state)
    end)

    local toggleControl = {
        Set = function(self, val, triggerCallback)
            state = val
            updateVisual(state)
            if triggerCallback ~= false then
                pcall(callback, state)
            end
        end,
        Get = function() return state end
    }

    if controlKey then
        GuiControls.Toggles[controlKey] = toggleControl
    end

    return toggleControl
end

local function addSlider(page, labelText, minVal, maxVal, defaultVal, callback, controlKey)
    local frame = Instance.new("Frame", page)
    frame.Size             = UDim2.new(1, 0, 0, 52)
    frame.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
    frame.BorderSizePixel  = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local title = Instance.new("TextLabel", frame)
    title.Size                   = UDim2.new(1, -60, 0, 24)
    title.Position               = UDim2.new(0, 12, 0, 4)
    title.BackgroundTransparency = 1
    title.Text                   = labelText
    title.Font                   = Enum.Font.Gotham
    title.TextSize               = 12
    title.TextColor3             = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment         = Enum.TextXAlignment.Left

    local valueLabel = Instance.new("TextLabel", frame)
    valueLabel.Size                   = UDim2.new(0, 40, 0, 24)
    valueLabel.Position               = UDim2.new(1, -52, 0, 4)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text                   = tostring(defaultVal)
    valueLabel.Font                   = Enum.Font.GothamBold
    valueLabel.TextSize               = 12
    valueLabel.TextColor3             = Color3.fromRGB(139, 124, 246)
    valueLabel.TextXAlignment         = Enum.TextXAlignment.Right

    local track = Instance.new("Frame", frame)
    track.Size             = UDim2.new(1, -24, 0, 4)
    track.Position         = UDim2.new(0, 12, 0, 36)
    track.BackgroundColor3 = Color3.fromRGB(42, 45, 58)
    track.BorderSizePixel  = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    fill.Size             = UDim2.new((defaultVal - minVal) / (maxVal - minVal), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel  = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local currentVal = defaultVal
    local draggingSlider = false

    local function updateFromInput(input)
        local posX = input.Position.X - track.AbsolutePosition.X
        local pct = math.clamp(posX / track.AbsoluteSize.X, 0, 1)
        currentVal = math.floor(minVal + (maxVal - minVal) * pct)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valueLabel.Text = tostring(currentVal)
        pcall(callback, currentVal)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            updateFromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)

    local sliderControl = {
        Set = function(self, val)
            local safeVal = tonumber(val) or defaultVal
            currentVal = math.clamp(safeVal, minVal, maxVal)
            local pct = (currentVal - minVal) / (maxVal - minVal)
            fill.Size = UDim2.new(pct, 0, 1, 0)
            valueLabel.Text = tostring(currentVal)
            pcall(callback, currentVal)
        end,
        Get = function() return currentVal end
    }

    if controlKey then
        GuiControls.Sliders[controlKey] = sliderControl
    end

    return sliderControl
end

local function addButton(page, text, callback)
    local btn = Instance.new("TextButton", page)
    btn.Size             = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    btn.BorderSizePixel  = 0
    btn.Text             = text
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 12
    btn.TextColor3       = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    btn.MouseButton1Click:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(115, 102, 220) }):Play()
        task.wait(0.1)
        TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        pcall(callback)
    end)
end

-- ====================
-- СТВОРЕННЯ СТОРІНОК ІНТЕРФЕЙСУ
-- ====================
local mainPage     = createTab("Головна", 1)
local farmPage     = createTab("Фарм", 2)
local itemsPage    = createTab("Предмети", 3)
local visualPage   = createTab("Візуал", 4)
local playerPage   = createTab("Гравець", 5)
local settingsPage = createTab("Конфіг", 6)

-- 1. СТОРІНКА «ГОЛОВНА»
addSection(mainPage, "Статус фарму")

local statusCard = Instance.new("Frame", mainPage)
statusCard.Size             = UDim2.new(1, 0, 0, 48)
statusCard.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
statusCard.BorderSizePixel  = 0
Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 6)

local statusTitle = Instance.new("TextLabel", statusCard)
statusTitle.Size                   = UDim2.new(1, -24, 0, 18)
statusTitle.Position               = UDim2.new(0, 12, 0, 6)
statusTitle.BackgroundTransparency = 1
statusTitle.Text                   = "ПОТОЧНИЙ СТАН"
statusTitle.Font                   = Enum.Font.GothamBold
statusTitle.TextSize               = 10
statusTitle.TextColor3             = Color3.fromRGB(139, 124, 246)
statusTitle.TextXAlignment         = Enum.TextXAlignment.Left

local statusVal = Instance.new("TextLabel", statusCard)
statusVal.Size                   = UDim2.new(1, -24, 0, 18)
statusVal.Position               = UDim2.new(0, 12, 0, 24)
statusVal.BackgroundTransparency = 1
statusVal.Text                   = farmStatusText
statusVal.Font                   = Enum.Font.Gotham
statusVal.TextSize               = 12
statusVal.TextColor3             = Color3.fromRGB(255, 255, 255)
statusVal.TextXAlignment         = Enum.TextXAlignment.Left

task.spawn(function()
    while true do
        if statusVal and statusVal.Parent then
            statusVal.Text = farmStatusText
        end
        task.wait(0.2)
    end
end)

addSection(mainPage, "Швидке перемикання")
addToggle(mainPage, "Item Farm (Авто-збір)", _G.ItemFarm, function(val)
    setItemFarmState(val)
end, "ItemFarm")

addToggle(mainPage, "Item ESP (Підсвічування)", _G.ItemESP, function(val)
    _G.ItemESP = val
    updateEsp()
end, "ItemESP")

-- 2. СТОРІНКА «ФАРМ»
addSection(farmPage, "Автоматизація фарму")
addToggle(farmPage, "Увімкнути Item Farm", _G.ItemFarm, function(val)
    setItemFarmState(val)
end, "ItemFarm_Page2")

addSlider(farmPage, "Швидкість польоту (Fly Speed)", 50, 300, _G.FlySpeed, function(val)
    _G.FlySpeed = val
end, "FlySpeed")

addSlider(farmPage, "Дистанція підбору (Studs)", 2, 8, math.floor(_G.PickupDistance), function(val)
    _G.PickupDistance = val
end, "PickupDistance")

addSection(farmPage, "Події та торгівля")
addToggle(farmPage, "Auto Sell (Продаж торговцю)", _G.AutoSell, function(val)
    _G.AutoSell = val
    if val then
        task.spawn(function()
            while _G.AutoSell do
                runAutoSell()
                task.wait(3)
            end
        end)
    end
end, "AutoSell")

addToggle(farmPage, "Auto Candy (Halloween Event)", _G.AutoEventCandy, function(val)
    _G.AutoEventCandy = val
    if val then
        task.spawn(function()
            while _G.AutoEventCandy do
                submitAllCandies()
                task.wait(2)
            end
        end)
    end
end, "AutoEventCandy")

addButton(farmPage, "Здати цукерки Jack (Разово)", function()
    task.spawn(submitAllCandies)
    showNotification("Halloween Event", "Розпочато здачу цукерок...", 2)
end)

-- 3. СТОРІНКА «ПРЕДМЕТИ»
addSection(itemsPage, "Вибір предметів для фарму")

local selectAllFrame = Instance.new("Frame", itemsPage)
selectAllFrame.Size                   = UDim2.new(1, 0, 0, 32)
selectAllFrame.BackgroundTransparency = 1

local selAllBtn = Instance.new("TextButton", selectAllFrame)
selAllBtn.Size             = UDim2.new(0.48, 0, 1, 0)
selAllBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
selAllBtn.Text             = "Вибрати все"
selAllBtn.Font             = Enum.Font.GothamBold
selAllBtn.TextSize         = 11
selAllBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", selAllBtn).CornerRadius = UDim.new(0, 6)

local deselAllBtn = Instance.new("TextButton", selectAllFrame)
deselAllBtn.Size             = UDim2.new(0.48, 0, 1, 0)
deselAllBtn.Position         = UDim2.new(0.52, 0, 0, 0)
deselAllBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
deselAllBtn.Text             = "Зняти все"
deselAllBtn.Font             = Enum.Font.GothamBold
deselAllBtn.TextSize         = 11
deselAllBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", deselAllBtn).CornerRadius = UDim.new(0, 6)

local itemBtns = {}

local sortedItemNames = {}
for name in pairs(_G.SelectedItems) do
    table.insert(sortedItemNames, name)
end
table.sort(sortedItemNames)

for _, name in ipairs(sortedItemNames) do
    local iBtn = Instance.new("TextButton", itemsPage)
    iBtn.Size             = UDim2.new(1, 0, 0, 32)
    iBtn.BackgroundColor3 = _G.SelectedItems[name] and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(28, 31, 40)
    iBtn.BorderSizePixel  = 0
    iBtn.Text             = (_G.SelectedItems[name] and "✓  " or "   ") .. name
    iBtn.Font             = Enum.Font.Gotham
    iBtn.TextSize         = 11
    iBtn.TextColor3       = _G.SelectedItems[name] and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 165, 175)
    iBtn.TextXAlignment   = Enum.TextXAlignment.Left
    Instance.new("UICorner", iBtn).CornerRadius = UDim.new(0, 6)

    local pad = Instance.new("UIPadding", iBtn)
    pad.PaddingLeft = UDim.new(0, 12)

    local function updateItemVisual(val)
        local targetBg   = val and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(28, 31, 40)
        local targetText = val and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 165, 175)
        iBtn.Text = (val and "✓  " or "   ") .. name
        TweenService:Create(iBtn, TweenInfo.new(0.15), { BackgroundColor3 = targetBg, TextColor3 = targetText }):Play()
    end

    iBtn.MouseButton1Click:Connect(function()
        _G.SelectedItems[name] = not _G.SelectedItems[name]
        updateItemVisual(_G.SelectedItems[name])
    end)

    local control = {
        Set = function(self, val)
            _G.SelectedItems[name] = val
            updateItemVisual(val)
        end
    }

    itemBtns[name] = control
    GuiControls.ItemButtons[name] = control
end

selAllBtn.MouseButton1Click:Connect(function()
    for name, ctrl in pairs(itemBtns) do
        ctrl:Set(true)
    end
end)

deselAllBtn.MouseButton1Click:Connect(function()
    for name, ctrl in pairs(itemBtns) do
        ctrl:Set(false)
    end
end)

-- 4. СТОРІНКА «ВІЗУАЛ»
addSection(visualPage, "ESP Елементи")
addToggle(visualPage, "Item ESP", _G.ItemESP, function(val)
    _G.ItemESP = val
    updateEsp()
end, "ItemESP_Visual")

addButton(visualPage, "Оновити підсвічування ESP", function()
    updateEsp()
    showNotification("Visual", "ESP оновлено", 1.5)
end)

-- 5. СТОРІНКА «ГРАВЕЦЬ»
addSection(playerPage, "Модифікації персонажа")
addToggle(playerPage, "NoClip (Проходження крізь стіни)", _G.StandaloneNoClip, function(val)
    _G.StandaloneNoClip = val
    setNoclip(val)
end, "StandaloneNoClip")

addToggle(playerPage, "Anti-AFK", _G.AntiAFK, function(val)
    _G.AntiAFK = val
    setAntiAfk(val)
end, "AntiAFK")

addToggle(playerPage, "Auto Respawn (Швидкий респавн)", _G.AutoRespawn, function(val)
    _G.AutoRespawn = val
end, "AutoRespawn")

-- 6. СТОРІНКА «КОНФІГ»
addSection(settingsPage, "Керування конфігурацією")

addToggle(settingsPage, "Auto Load Config (15с затримка)", shouldAutoLoad, function(val)
    shouldAutoLoad = val
    pcall(function()
        if writefile then
            writefile(autoLoadFile, tostring(val))
        end
    end)
    showNotification("Config", "Автозавантаження: " .. (val and "Увімкнено" or "Вимкнено"), 2)
end)

addButton(settingsPage, "Зберегти поточний конфіг", function()
    local ok = saveCurrentConfig()
    if ok then
        showNotification("Config", "Налаштування успішно збережено в JSON!", 3)
    else
        showNotification("Помилка", "Не вдалося зберегти файл конфігурації", 3)
    end
end)

addButton(settingsPage, "Завантажити збережений конфіг", function()
    local ok = loadCurrentConfig()
    if ok then
        showNotification("Config", "Налаштування завантажено та відновлено!", 3)
    else
        showNotification("Помилка", "Файл YBA_Config.json не знайдено або пошкоджено", 3)
    end
end)

-- Відкриваємо вкладку за замовчуванням
switchTab("Головна")
print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

-- Автозавантаження запускається в окремому потоці після показу GUI
if shouldAutoLoad then
    task.spawn(runSteppedAutoLoad)
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
