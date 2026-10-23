-- UA Killer Hub | YBA — Версія з поетапним Auto Load Config
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

local player = Players.LocalPlayer
while not player do
    task.wait(0.1)
    player = Players.LocalPlayer
end
print("[UA Killer Hub | Init] Гравець ідентифікований: " .. player.Name)

local autoLoadFile = "UAKillerHub/YBA_AutoLoad.txt"
local configFile   = "UAKillerHub/YBA_Config.json"
local shouldAutoLoad = false

-- =======================================================
-- БЕЗПЕЧНА АКТИВАЦІЯ ITEM MAGNITUDE BYPASS
-- =======================================================
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

-- ====================================================
-- БЕЗПЕЧНИЙ CRASH & WALKSPEED BYPASS
-- ====================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Ініціалізація папки та флагу авто-завантаження
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
_G.FlySpeed        = 150
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

local bannedCoordinates = {}
local espObjects        = {}
local itemCache         = {}
local lastCacheRefresh  = 0
local CACHE_REFRESH_INTERVAL = 1.25
local BAN_TTL           = 45

local farmThreadActive  = false
local farmStatusText    = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection
local JP_Value = 50

local uiElementsRegistry = {}

-- Прапорці ручних змін (захист від перезапису при авто-завантаженні)
local manuallyChanged = {
    ItemFarm        = false,
    AutoSell        = false,
    AutoEventCandy  = false,
    AutoBuy         = false,
    ItemESP         = false,
    AntiAFK         = false,
    StandaloneNoClip= false,
    AutoRespawn     = false,
}

-- ====================
-- ДОПОМІЖНІ ФУНКЦІЇ
-- ====================
local function setFarmStatus(text)
    farmStatusText = text
end

local function isInvalidItemPart(obj)
    if not obj then return true end
    local current = obj
    while current and current ~= workspace do
        if current:IsA("Backpack") then return true end
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then return true end
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
        if (pos - entry.pos).Magnitude < 3 then return true end
    end
    return false
end

local function banCoordinate(pos)
    table.insert(bannedCoordinates, { pos = pos, time = tick() })
end

local function resolveItemFromPrompt(desc)
    if not desc or not desc:IsA("ProximityPrompt") or not desc.Parent then return nil end

    local parent    = desc.Parent
    local model     = parent:IsA("Model") and parent or parent.Parent
    local itemName  = ""

    if _G.SelectedItems[parent.Name] ~= nil then
        itemName = parent.Name
    elseif model and _G.SelectedItems[model.Name] ~= nil then
        itemName = model.Name
    elseif desc.ObjectText and _G.SelectedItems[desc.ObjectText] ~= nil then
        itemName = desc.ObjectText
    end

    if itemName == "" then return nil end

    local targetPart = parent:IsA("BasePart") and parent
        or parent:FindFirstChildWhichIsA("BasePart")
        or (model and model:FindFirstChildWhichIsA("BasePart"))

    if not targetPart or targetPart.Transparency >= 1 then return nil end
    if isCoordinateBanned(targetPart.Position) or isInvalidItemPart(targetPart) then return nil end
    if not desc.Enabled then return nil end

    return {
        prompt   = desc,
        part     = targetPart,
        parent   = parent,
        name     = itemName,
        position = targetPart.Position,
    }
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

local function refreshItemCache()
    local now = tick()
    if now - lastCacheRefresh < CACHE_REFRESH_INTERVAL then return itemCache end

    lastCacheRefresh = now
    table.clear(itemCache)

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local item = resolveItemFromPrompt(desc)
            if item and shouldFarmItem(item.name) then
                table.insert(itemCache, item)
            end
        end
    end
    return itemCache
end

local function getNearestItem(hrp)
    local nearest, shortest = nil, math.huge
    for _, item in ipairs(refreshItemCache()) do
        if item.prompt:IsDescendantOf(workspace) and not isInvalidItemPart(item.parent) then
            local dist = (hrp.Position - item.position).Magnitude
            if dist < shortest then
                shortest = dist
                nearest  = item
            end
        end
    end
    return nearest, shortest
end

local function applyESP(part, name)
    if espObjects[part] then return end
    if not part or part.Transparency == 1 or isCoordinateBanned(part.Position) or isInvalidItemPart(part) then return end

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
        if gui then gui:Destroy() end
        espObjects[part] = nil
    end
    table.clear(espObjects)
end

local function getCharacter()
    local char = player.Character
    return char, char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

local function zeroHrpVelocity(hrp)
    if not hrp then return end
    hrp.AssemblyLinearVelocity  = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function cleanupFlight()
    if not flightState then return end
    if flightState.tween then pcall(function() flightState.tween:Cancel() end) end
    if flightState.heartbeatConn then flightState.heartbeatConn:Disconnect() end
    if flightState.cframeValue then flightState.cframeValue:Destroy() end
    flightState = nil
end

local function stopFlight()
    cleanupFlight()
    if noclipConnection and not _G.StandaloneNoClip and not _G.ItemFarm then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end

local function ensureNoClip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if not _G.ItemFarm and not _G.StandaloneNoClip then return end
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

local function moveToItemAndPickup(item)
    if not item or not item.part or not item.part:IsDescendantOf(workspace) then return false end
    if not item.prompt or not item.prompt:IsDescendantOf(workspace) then return false end
    if isInvalidItemPart(item.parent) then return false end

    local char, hrp = getCharacter()
    if not hrp then return false end

    cleanupFlight()

    local cframeValue = Instance.new("CFrameValue")
    cframeValue.Name   = "YBA_VirtualCFrame"
    cframeValue.Value  = hrp.CFrame
    cframeValue.Parent = player

    local targetCFrame = CFrame.new(item.part.Position + Vector3.new(0, 1.2, 0))
    local distance     = (targetCFrame.Position - hrp.Position).Magnitude
    local tweenTime    = math.max(distance / _G.FlySpeed, 0.05)

    local tween = TweenService:Create(cframeValue, TweenInfo.new(tweenTime, Enum.EasingStyle.Linear), { Value = targetCFrame })

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent then return end
        local currentHrp = char:FindFirstChild("HumanoidRootPart")
        if not currentHrp or not cframeValue.Parent then return end
        currentHrp.CFrame = cframeValue.Value
        zeroHrpVelocity(currentHrp)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= currentHrp then
                part.CanCollide = false
            end
        end
    end)

    flightState = { cframeValue = cframeValue, tween = tween, heartbeatConn = heartbeatConn }

    local function shouldContinue()
        return _G.ItemFarm
            and item.part:IsDescendantOf(workspace)
            and not isInvalidItemPart(item.part)
            and item.prompt:IsDescendantOf(workspace)
    end

    tween:Play()
    local finished = false
    tween.Completed:Once(function() finished = true end)

    while not finished do
        if not shouldContinue() or not hrp or not hrp.Parent then
            cleanupFlight()
            return false
        end
        RunService.Heartbeat:Wait()
    end

    if not shouldContinue() then cleanupFlight() return false end

    targetCFrame      = CFrame.new(item.part.Position + Vector3.new(0, 1.2, 0))
    cframeValue.Value = targetCFrame
    local currentHrp  = char:FindFirstChild("HumanoidRootPart")
    if currentHrp then
        currentHrp.CFrame = targetCFrame
        zeroHrpVelocity(currentHrp)
    end

    task.wait(0.03)

    if shouldContinue() then
        item.prompt.RequiresLineOfSight = false
        item.prompt.HoldDuration        = 0
        if fireproximityprompt then fireproximityprompt(item.prompt, 0) end
    end

    local pickedUp = not item.prompt:IsDescendantOf(workspace) or isInvalidItemPart(item.parent)
    cleanupFlight()
    return pickedUp
end

local function tryRespawn()
    if not _G.AutoRespawn then return end
    local _, _, hum = getCharacter()
    if hum and hum.Health <= 0 then
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("Remotes")
            remote = remote and remote:FindFirstChild("LoadCharacter")
            if remote then remote:FireServer() end
        end)
    end
end

local function startFarmThread()
    if farmThreadActive then return end
    farmThreadActive = true
    task.spawn(function()
        setFarmStatus("Пошук предметів...")
        while _G.ItemFarm and farmThreadActive do
            tryRespawn()
            local _, hrp = getCharacter()
            if not hrp then
                setFarmStatus("Очікування персонажа...")
                task.wait(0.5)
                continue
            end
            local targetItem = getNearestItem(hrp)
            if not targetItem then
                setFarmStatus("Предметів не знайдено")
                task.wait(0.35)
                continue
            end
            setFarmStatus("Лечу до: " .. targetItem.name)
            if moveToItemAndPickup(targetItem) then
                banCoordinate(targetItem.position)
                if espObjects[targetItem.part] then
                    espObjects[targetItem.part]:Destroy()
                    espObjects[targetItem.part] = nil
                end
                lastCacheRefresh = 0
            end
            task.wait(0.08)
        end
        farmThreadActive = false
        setFarmStatus("Зупинено")
        stopFlight()
    end)
end

-- =======================================================
-- МАГАЗИН ТА ІВЕНТ
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

local sellQueue = {}
local isBusy    = false

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
    if not gui then return end
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
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
                if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
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
end

local function sellSingleItem(item)
    if not item or isItemSold(item) or DontSell[item.Name] then return true, "AlreadySold" end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()
    if not hum or not remote or not merchant then return false, "MissingCharacterOrNPC" end

    hum:EquipTool(item)
    local equipTimeout = tick() + 0.8
    while tick() < equipTimeout and item.Parent ~= char do task.wait(0.04) end
    if item.Parent ~= char then return false, "EquipTimeout" end

    task.wait(0.12)
    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.12)
    autoClickDialogueButtons()

    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue1", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    local sellTimeout = tick() + 1.2
    while tick() < sellTimeout do
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

    return isItemSold(item), isItemSold(item) and "Success" or "ItemStillExists"
end

local function sellSingleItemWithRetries(item, maxRetries)
    maxRetries = maxRetries or 3
    local lastError = "Unknown"
    for attempt = 1, maxRetries do
        if isItemSold(item) then return true, "Success" end
        local ok, errStage = sellSingleItem(item)
        if ok then return true, "Success" end
        lastError = errStage
        task.wait(0.2)
    end
    return false, lastError
end

local function isItemInQueue(item)
    for _, q in ipairs(sellQueue) do if q == item then return true end end
    return false
end

local function queueItemForSale(item)
    if not item or not item:IsA("Tool") or DontSell[item.Name] then return end
    if isItemSold(item) or isItemInQueue(item) then return end
    table.insert(sellQueue, item)
end

local function syncSellQueue()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do queueItemForSale(item) end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] then queueItemForSale(item) end
        end
    end
end

local function hasSellableItems()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] then return true end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] then return true end
        end
    end
    return false
end

local function setupBackpackListener(backpack)
    for _, item in ipairs(backpack:GetChildren()) do queueItemForSale(item) end
    backpack.ChildAdded:Connect(function(item)
        task.wait(0.2)
        if _G.AutoSell then queueItemForSale(item) end
    end)
end

player.ChildAdded:Connect(function(child)
    if child.Name == "Backpack" then setupBackpackListener(child) end
end)
if player:FindFirstChild("Backpack") then setupBackpackListener(player.Backpack) end

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
    if not gui then return false end
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then txt = childText.Text end
            local lower = txt:lower()
            if lower:find("turn in") or (lower:find("candy") and not lower:find("what do i do") and not lower:find("could you please")) then
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
    if not gui then return nil end

    local hasJack, hasPoints   = false, false
    local continueElem, pointsElem, fallbackFrame = nil, nil, nil

    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local txt   = desc.Text or ""
            local lower = txt:lower()
            if lower:find("jack") or lower:find("cauldron specter") then hasJack = true end
            if lower:find("point") then hasPoints = true; pointsElem = desc end
            if lower:find("click to continue") then continueElem = desc end
        end
        if desc:IsA("Frame") and desc.Visible and desc.AbsoluteSize.Y > 50 then
            fallbackFrame = desc
        end
    end

    local visible = gui:IsA("ScreenGui") and gui.Enabled or gui.Visible
    if visible and (hasJack or hasPoints) then
        return { gui = gui, hasJack = hasJack, hasPoints = hasPoints,
                 continueElem = continueElem, pointsElem = pointsElem, fallbackFrame = fallbackFrame }
    end
    return nil
end

local function clickContinueButton(targetElement)
    pcall(function()
        if not targetElement then return end
        if targetElement:IsA("GuiButton") then
            if firesignal then firesignal(targetElement.MouseButton1Click) firesignal(targetElement.Activated)
            else targetElement.Activated:Fire() end
        end
        if VirtualInputManager and targetElement:IsA("GuiObject") then
            local absPos  = targetElement.AbsolutePosition
            local absSize = targetElement.AbsoluteSize
            VirtualInputManager:SendMouseButtonEvent(absPos.X + absSize.X / 2, absPos.Y + absSize.Y / 2, 0, true,  game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(absPos.X + absSize.X / 2, absPos.Y + absSize.Y / 2, 0, false, game, 0)
        end
    end)
end

local function submitAllCandies()
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not remote or not hum or not eventNPC then return false end

    local success = false
    pcall(function()
        remote:FireServer("PromptTriggered", eventNPC)
        local optionFound  = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy do
            if clickEventCandyOption() then optionFound = true break end
            task.wait(0.15)
        end
        if not optionFound then return end

        local pointsFound    = false
        local jackData       = nil
        local pointsTimeout  = tick() + 4.0
        while tick() < pointsTimeout and _G.AutoEventCandy do
            jackData = findJackDialogue()
            if jackData and jackData.hasPoints then pointsFound = true break end
            task.wait(0.15)
        end
        if not pointsFound or not jackData then return end

        task.wait(0.3)
        local clickTarget = jackData.continueElem or jackData.pointsElem or jackData.fallbackFrame
        if clickTarget then
            clickContinueButton(clickTarget)
            local closeTimeout = tick() + 1.5
            local isClosed     = false
            while tick() < closeTimeout do
                task.wait(0.15)
                if not findJackDialogue() then isClosed = true break end
            end
            if isClosed then success = true
            else clickContinueButton(clickTarget) task.wait(0.2) end
        end
    end)
    return success
end

-- Головний потік продажів та цукерок
task.spawn(function()
    while true do
        task.wait(0.3)
        if isBusy then continue end

        if _G.AutoEventCandy and countTotalCandies() >= 10 then
            isBusy = true
            closeMerchantDialogue()
            while countTotalCandies() > 0 and _G.AutoEventCandy do
                submitAllCandies()
                task.wait(0.5)
            end
            isBusy = false
            continue
        end

        if _G.AutoSell and (#sellQueue > 0 or hasSellableItems()) then
            isBusy = true
            syncSellQueue()
            while _G.AutoSell and #sellQueue > 0 do
                local item = table.remove(sellQueue, 1)
                if item and not isItemSold(item) and not DontSell[item.Name] then
                    sellSingleItemWithRetries(item, 3)
                    task.wait(0.15)
                end
            end
            closeMerchantDialogue()
            isBusy = false
        end
    end
end)

local function applyJumpPower()
    local _, _, hum = getCharacter()
    if hum then hum.JumpPower = JP_Value end
end

player.CharacterAdded:Connect(function(newChar)
    task.wait(0.5)
    applyJumpPower()
    newChar.ChildAdded:Connect(function(item)
        task.wait(0.2)
        if _G.AutoSell and item:IsA("Tool") and not DontSell[item.Name] then
            queueItemForSale(item)
        end
    end)
end)

if player.Character then
    player.Character.ChildAdded:Connect(function(item)
        task.wait(0.2)
        if _G.AutoSell and item:IsA("Tool") and not DontSell[item.Name] then
            queueItemForSale(item)
        end
    end)
end

task.spawn(function()
    while task.wait(0.2) do applyJumpPower() end
end)

task.spawn(function()
    while true do
        task.wait(0.8)
        if _G.ItemESP then
            for _, item in ipairs(refreshItemCache()) do applyESP(item.part, item.name) end
        else
            clearESP()
        end
    end
end)

-- =======================================================
-- ОПТИМІЗОВАНЕ СТВОРЕННЯ MONHUB GUI
-- =======================================================
print("[UA Killer Hub | GUI] Початок створення графічного інтерфейсу...")

-- ── Кольори теми ─────────────────────────────────────────
local C = {
    bg       = Color3.fromRGB(23, 25, 31),
    bgDark   = Color3.fromRGB(19, 21, 26),
    card     = Color3.fromRGB(28, 31, 39),
    cardHov  = Color3.fromRGB(36, 40, 52),
    accent   = Color3.fromRGB(139, 124, 246),
    text     = Color3.fromRGB(240, 242, 245),
    textSub  = Color3.fromRGB(230, 233, 240),
    textDim  = Color3.fromRGB(150, 155, 165),
    stroke   = Color3.fromRGB(38, 42, 53),
    sidebar  = Color3.fromRGB(18, 20, 25),
    tabBg    = Color3.fromRGB(23, 25, 32),
    switchOff= Color3.fromRGB(42, 46, 58),
    line     = Color3.fromRGB(34, 38, 48),
    btnBg    = Color3.fromRGB(28, 31, 40),
    btnText  = Color3.fromRGB(160, 165, 175),
    statusBg = Color3.fromRGB(24, 27, 34),
    statusSt = Color3.fromRGB(42, 46, 58),
    toastBg  = Color3.fromRGB(27, 30, 38),
    toastMsg = Color3.fromRGB(200, 205, 215),
    searchBg = Color3.fromRGB(28, 31, 39),
    searchPh = Color3.fromRGB(110, 115, 130),
    searchIc = Color3.fromRGB(150, 155, 165),
    white    = Color3.fromRGB(255, 255, 255),
}

-- ── Хелпер: створення Instance з пропсами ────────────────
local function new(className, parent, props)
    local inst = Instance.new(className)
    if props then
        for k, v in pairs(props) do inst[k] = v end
    end
    inst.Parent = parent
    return inst
end

local function corner(parent, radius)
    return new("UICorner", parent, { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(parent, color, thickness, transparency)
    return new("UIStroke", parent, { Color = color or C.stroke, Thickness = thickness or 1, Transparency = transparency or 0 })
end

-- ── Безпечний батьківський контейнер GUI ─────────────────
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
print("[UA Killer Hub | GUI] Контейнер GUI: " .. tostring(targetGuiParent and targetGuiParent.Name))

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

-- ── ScreenGui та MainFrame ───────────────────────────────
local ScreenGui = new("ScreenGui", targetGuiParent, {
    Name = "UAKillerHub_GUI", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local MainFrame = new("Frame", ScreenGui, {
    Name = "MainFrame", Size = UDim2.new(0, 520, 0, 400),
    Position = UDim2.new(0.5, -260, 0.5, -200),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true,
})
corner(MainFrame, 10)
stroke(MainFrame, C.stroke)

-- ── Сповіщення ───────────────────────────────────────────
local ToastContainer = new("Frame", ScreenGui, {
    Name = "ToastContainer", Size = UDim2.new(0, 240, 1, -20),
    Position = UDim2.new(1, -250, 0, 10), BackgroundTransparency = 1,
})
new("UIListLayout", ToastContainer, {
    Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
})

local function showNotification(title, message, duration)
    duration = duration or 3
    local toast = new("Frame", ToastContainer, {
        Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.toastBg,
        BorderSizePixel = 0, ClipsDescendants = true,
    })
    corner(toast, 8)
    local tStroke = stroke(toast, C.accent, 1, 1)

    local titleLbl = new("TextLabel", toast, {
        Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 10, 0, 6),
        BackgroundTransparency = 1, Text = title, TextColor3 = C.accent,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1,
    })
    local msgLbl = new("TextLabel", toast, {
        Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 10, 0, 26),
        BackgroundTransparency = 1, Text = message, TextColor3 = C.toastMsg,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1,
    })

    local tw = TweenInfo.new(0.2)
    TweenService:Create(toast,    tw, { Size = UDim2.new(1, 0, 0, 55) }):Play()
    TweenService:Create(tStroke,  tw, { Transparency = 0 }):Play()
    TweenService:Create(titleLbl, tw, { TextTransparency = 0 }):Play()
    TweenService:Create(msgLbl,   tw, { TextTransparency = 0 }):Play()

    task.delay(duration, function()
        pcall(function()
            TweenService:Create(toast,    tw, { Size = UDim2.new(1, 0, 0, 0) }):Play()
            TweenService:Create(tStroke,  tw, { Transparency = 1 }):Play()
            TweenService:Create(titleLbl, tw, { TextTransparency = 1 }):Play()
            local last = TweenService:Create(msgLbl, tw, { TextTransparency = 1 })
            last:Play(); last.Completed:Wait(); toast:Destroy()
        end)
    end)
end

-- ── Верхня панель (Title Bar) ────────────────────────────
local TitleBar = new("Frame", MainFrame, {
    Name = "TitleBar", Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = C.bgDark, BorderSizePixel = 0,
})
corner(TitleBar, 10)
new("Frame", TitleBar, {
    Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = C.line, BorderSizePixel = 0,
})
new("TextLabel", TitleBar, {
    Size = UDim2.new(0, 140, 1, 0), Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1, Text = "UA Killer Hub",
    Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
})
local Badge = new("TextLabel", TitleBar, {
    Size = UDim2.new(0, 36, 0, 18), Position = UDim2.new(0, 126, 0.5, -9),
    BackgroundColor3 = C.accent, Text = "YBA",
    Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.white,
})
corner(Badge, 4)

local function titleButton(text, xOffset)
    local btn = new("TextButton", TitleBar, {
        Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, xOffset, 0.5, -13),
        BackgroundColor3 = C.btnBg, Text = text,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.btnText,
    })
    corner(btn, 6)
    return btn
end

local CloseBtn = titleButton("✕", -34)
local MinBtn   = titleButton("—", -66)

-- Перетягування
local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = MainFrame.Position
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

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        Size = isMinimized and UDim2.new(0, 520, 0, 42) or UDim2.new(0, 520, 0, 400)
    }):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    showNotification("UA Killer Hub", "Натисніть RightShift, щоб відкрити знову", 3.5)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ── Sidebar ──────────────────────────────────────────────
local Sidebar = new("Frame", MainFrame, {
    Name = "Sidebar", Size = UDim2.new(0, 130, 1, -42),
    Position = UDim2.new(0, 0, 0, 42),
    BackgroundColor3 = C.sidebar, BorderSizePixel = 0,
})
new("UIListLayout", Sidebar, {
    Padding = UDim.new(0, 6),
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
})
new("UIPadding", Sidebar, {
    PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
})

-- ── Контентна панель ─────────────────────────────────────
local ContentArea = new("Frame", MainFrame, {
    Name = "ContentArea", Size = UDim2.new(1, -130, 1, -42),
    Position = UDim2.new(0, 130, 0, 42), BackgroundTransparency = 1,
})

local SearchFrame = new("Frame", ContentArea, {
    Name = "SearchFrame", Size = UDim2.new(1, -24, 0, 32),
    Position = UDim2.new(0, 12, 0, 10),
    BackgroundColor3 = C.searchBg, BorderSizePixel = 0,
})
corner(SearchFrame, 6)
new("TextLabel", SearchFrame, {
    Size = UDim2.new(0, 24, 1, 0), BackgroundTransparency = 1,
    Text = "🔍", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.searchIc,
})
local SearchBox = new("TextBox", SearchFrame, {
    Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 28, 0, 0),
    BackgroundTransparency = 1, PlaceholderText = "Пошук функцій...",
    PlaceholderColor3 = C.searchPh, TextColor3 = C.text,
    Font = Enum.Font.Gotham, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
})

local PagesFolder = new("Folder", ContentArea, { Name = "Pages" })

local tabs      = {}
local activeTab = nil

local function filterItems(query)
    query = query:lower()
    for _, item in ipairs(uiElementsRegistry) do
        if item.Page == activeTab then
            item.Frame.Visible = (query == "" or item.Name:lower():find(query, 1, true) ~= nil)
        end
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    filterItems(SearchBox.Text)
end)

local function switchTab(tabName)
    activeTab = tabName
    SearchBox.Text = ""
    for name, tabData in pairs(tabs) do
        local active = (name == tabName)
        tabData.Page.Visible = active
        TweenService:Create(tabData.Button, TweenInfo.new(0.2), {
            BackgroundColor3 = active and C.accent or C.tabBg,
            TextColor3       = active and C.white  or C.textDim,
        }):Play()
    end
    filterItems("")
end

-- ── Фабрики UI-компонентів ───────────────────────────────
local function createTab(tabName, iconText)
    local btn = new("TextButton", Sidebar, {
        Name = tabName .. "_Tab", Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.tabBg,
        Text = (iconText or "•") .. "  " .. tabName,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = C.textDim, TextXAlignment = Enum.TextXAlignment.Left,
    })
    corner(btn, 6)
    new("UIPadding", btn, { PaddingLeft = UDim.new(0, 10) })

    local page = new("ScrollingFrame", PagesFolder, {
        Name = tabName .. "_Page", Size = UDim2.new(1, -24, 1, -56),
        Position = UDim2.new(0, 12, 0, 48), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    })
    new("UIListLayout", page, { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder })
    new("UIPadding", page, { PaddingRight = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10) })

    tabs[tabName] = { Button = btn, Page = page }
    btn.MouseButton1Click:Connect(function() switchTab(tabName) end)
    return page
end

local function createSection(page, tabName, text)
    local sec = new("Frame", page, { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 })
    new("TextLabel", sec, {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Text = text:upper(), Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Left,
    })
    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = sec })
    return sec
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local toggleState = (defaultVal == true)
    local card = new("Frame", page, {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.card, BorderSizePixel = 0,
    })
    corner(card, 6)
    new("TextLabel", card, {
        Size = UDim2.new(1, -56, 1, 0), Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = C.textSub, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local switch = new("TextButton", card, {
        Size = UDim2.new(0, 36, 0, 20), Position = UDim2.new(1, -44, 0.5, -10),
        BackgroundColor3 = toggleState and C.accent or C.switchOff, Text = "",
    })
    corner(switch, 999)
    local knob = new("Frame", switch, {
        Size = UDim2.new(0, 14, 0, 14),
        Position = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = C.white, BorderSizePixel = 0,
    })
    corner(knob, 999)

    local function setState(val, triggerCb)
        toggleState = (val == true)
        TweenService:Create(switch, TweenInfo.new(0.2), {
            BackgroundColor3 = toggleState and C.accent or C.switchOff,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        }):Play()
        if triggerCb and callback then callback(toggleState) end
    end

    switch.MouseButton1Click:Connect(function() setState(not toggleState, true) end)

    local controlObj = {
        Name = text, Page = tabName, Frame = card,
        Set  = function(self, val, triggerCb)
            if triggerCb == nil then triggerCb = true end
            setState(val, triggerCb)
        end,
        Get  = function() return toggleState end,
    }
    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createSlider(page, tabName, text, min, max, step, defaultVal, callback)
    local currentVal = defaultVal or min
    local card = new("Frame", page, {
        Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = C.card, BorderSizePixel = 0,
    })
    corner(card, 6)
    new("TextLabel", card, {
        Size = UDim2.new(1, -60, 0, 20), Position = UDim2.new(0, 12, 0, 4),
        BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = C.textSub, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local valLabel = new("TextLabel", card, {
        Size = UDim2.new(0, 46, 0, 20), Position = UDim2.new(1, -54, 0, 4),
        BackgroundTransparency = 1, Text = tostring(currentVal),
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Right,
    })
    local bar = new("TextButton", card, {
        Size = UDim2.new(1, -24, 0, 6), Position = UDim2.new(0, 12, 0, 32),
        BackgroundColor3 = C.switchOff, Text = "",
    })
    corner(bar, 999)
    local fill = new("Frame", bar, {
        Size = UDim2.new(math.clamp((currentVal - min) / (max - min), 0, 1), 0, 1, 0),
        BackgroundColor3 = C.accent, BorderSizePixel = 0,
    })
    corner(fill, 999)

    local draggingSlider = false
    local function updateFromPos(x)
        local rel     = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local raw     = min + (max - min) * rel
        local stepped = math.floor(raw / step + 0.5) * step
        if step < 1 then stepped = tonumber(string.format("%.1f", stepped)) end
        currentVal    = math.clamp(stepped, min, max)
        valLabel.Text = tostring(currentVal)
        fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
        if callback then callback(currentVal) end
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true; updateFromPos(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromPos(input.Position.X)
        end
    end)

    local controlObj = {
        Name = text, Page = tabName, Frame = card,
        Set  = function(self, val, triggerCb)
            val = tonumber(val); if not val then return end
            if triggerCb == nil then triggerCb = true end
            currentVal    = math.clamp(val, min, max)
            valLabel.Text = tostring(currentVal)
            fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
            if triggerCb and callback then callback(currentVal) end
        end,
        Get  = function() return currentVal end,
    }
    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createButton(page, tabName, text, callback)
    local card = new("Frame", page, {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.card, BorderSizePixel = 0,
    })
    corner(card, 6)
    local btn = new("TextButton", card, {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
    })
    btn.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = C.cardHov }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = C.card }):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = C.accent }):Play()
        task.wait(0.08)
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = C.card }):Play()
        if callback then callback() end
    end)
    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return btn
end

local function createStatusLabel(page, tabName, initialText)
    local card = new("Frame", page, {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.statusBg, BorderSizePixel = 0,
    })
    corner(card, 6)
    stroke(card, C.statusSt)
    local lbl = new("TextLabel", card, {
        Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1, Text = initialText,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Left,
    })
    table.insert(uiElementsRegistry, { Name = "Статус", Page = tabName, Frame = card })
    return { Set = function(self, txt) lbl.Text = txt end }
end

print("[UA Killer Hub | GUI] Усі компоненти MonHub створено.")

-- =======================================================
-- СТОРІНКИ ТА ЕЛЕМЕНТИ UI (через таблиці конфігурації)
-- =======================================================
local mainPage = createTab("Головна",  "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин",  "🛒")
local miscPage = createTab("Інше",     "⚙")

-- Посилання на контроли для системи конфігурації
local itemToggleControls = {}
local saveCurrentConfig, loadCurrentConfig   -- forward declaration

-- ── Головна ──────────────────────────────────────────────
createSection(mainPage, "Головна", "Конфігурація")

local autoLoadToggle = createToggle(mainPage, "Головна", "Автозавантаження при старті", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    pcall(function()
        if writefile then writefile(autoLoadFile, tostring(value)) end
    end)
    print("[UA Killer Hub | Config] Автозавантаження збережено: " .. tostring(value))
end)

createButton(mainPage, "Головна", "Завантажити конфіг вручну", function()
    if loadCurrentConfig then loadCurrentConfig(false) end
end)

createButton(mainPage, "Головна", "Зберегти поточний конфіг", function()
    if saveCurrentConfig then saveCurrentConfig() end
end)

createSection(mainPage, "Головна", "Характеристики")

local jumpPowerSlider = createSlider(mainPage, "Головна", "Висота стрибка (JumpPower)", 50, 200, 1, JP_Value, function(val)
    JP_Value = val
    applyJumpPower()
end)

-- ── Автофарм ─────────────────────────────────────────────
createSection(farmPage, "Автофарм", "Основні параметри")

local statusLabel = createStatusLabel(farmPage, "Автофарм", "Статус: Очікування...")
task.spawn(function()
    while task.wait(0.35) do
        pcall(function() statusLabel:Set("Статус: " .. farmStatusText) end)
    end
end)

local flySpeedSlider = createSlider(farmPage, "Автофарм", "Швидкість польоту", 50, 350, 5, _G.FlySpeed, function(val)
    _G.FlySpeed = val
end)

local pickupDistanceSlider = createSlider(farmPage, "Автофарм", "Дистанція підбору", 2, 8, 0.5, _G.PickupDistance, function(val)
    _G.PickupDistance = val
end)

local itemEspToggle = createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    manuallyChanged.ItemESP = true
    _G.ItemESP = val
end)

local itemFarmToggle = createToggle(farmPage, "Автофарм", "Увімкнути автофарм", _G.ItemFarm, function(value)
    manuallyChanged.ItemFarm = true
    _G.ItemFarm = value
    if not value then
        farmThreadActive = false
        setFarmStatus("Зупинено")
        stopFlight()
    else
        startFarmThread()
    end
end)

createSection(farmPage, "Автофарм", "Фільтр предметів")

createButton(farmPage, "Автофарм", "Увімкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = true
        if itemToggleControls[name] then itemToggleControls[name]:Set(true, false) end
    end
    lastCacheRefresh = 0
end)

createButton(farmPage, "Автофарм", "Вимкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = false
        if itemToggleControls[name] then itemToggleControls[name]:Set(false, false) end
    end
    lastCacheRefresh = 0
end)

local sortedItems = {}
for name in pairs(_G.SelectedItems) do table.insert(sortedItems, name) end
table.sort(sortedItems)

for _, itemName in ipairs(sortedItems) do
    itemToggleControls[itemName] = createToggle(farmPage, "Автофарм", itemName, _G.SelectedItems[itemName], function(val)
        _G.SelectedItems[itemName] = val
        lastCacheRefresh = 0
    end)
end

-- ── Магазин ──────────────────────────────────────────────
createSection(shopPage, "Магазин", "Торгівля та івенти")

local autoSellToggle = createToggle(shopPage, "Магазин", "Автопродаж (крім Lucky Arrow)", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    _G.AutoSell = value
    if value then syncSellQueue()
    else table.clear(sellQueue) closeMerchantDialogue() end
end)

local autoCandyToggle = createToggle(shopPage, "Магазин", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = value
end)

local autoBuyToggle = createToggle(shopPage, "Магазин", "Автокупівля (Lucky Arrow)", _G.AutoBuy, function(value)
    manuallyChanged.AutoBuy = true
    _G.AutoBuy = value
    if value then
        task.spawn(function()
            while _G.AutoBuy do
                local char   = player.Character
                local remote = char and char:FindFirstChild("RemoteEvent")
                if remote then remote:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" }) end
                task.wait(2.5 + math.random() * 1.5)
            end
        end)
    end
end)

-- ── Інше ─────────────────────────────────────────────────
createSection(miscPage, "Інше", "Додаткові функції")

local antiAfkToggle = createToggle(miscPage, "Інше", "Anti-AFK", _G.AntiAFK, function(value)
    manuallyChanged.AntiAFK = true
    _G.AntiAFK = value
    if antiAfkConnection then antiAfkConnection:Disconnect() antiAfkConnection = nil end
    if value then
        antiAfkConnection = player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
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

local autoRespawnToggle = createToggle(miscPage, "Інше", "Авто-респawn при смерті", _G.AutoRespawn, function(value)
    manuallyChanged.AutoRespawn = true
    _G.AutoRespawn = value
end)

createButton(miscPage, "Інше", "Очистити заблоковані координати", function()
    table.clear(bannedCoordinates)
    lastCacheRefresh = 0
    showNotification("UA Killer Hub", "Чорний список координат очищено", 3)
end)

print("[UA Killer Hub | GUI] Усі вкладки та елементи MonHub створено.")

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЇ (визначається після всіх контролів)
-- =======================================================
local function readConfigFromDisk()
    if not (readfile and isfile) then return nil, "readfile/isfile недоступні" end

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
    if not writefile then
        showNotification("Помилка", "writefile не підтримується", 3)
        return
    end

    local cfgData = {
        SelectedItems    = _G.SelectedItems,
        FlySpeed         = _G.FlySpeed,
        PickupDistance   = _G.PickupDistance,
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

    print(string.format("[UA Killer Hub | Config] Збереження: ItemFarm=%s AutoSell=%s AutoEventCandy=%s",
        tostring(cfgData.ItemFarm), tostring(cfgData.AutoSell), tostring(cfgData.AutoEventCandy)))

    local jsonString
    local ok, err = pcall(function() jsonString = HttpService:JSONEncode(cfgData) end)
    if not ok or not jsonString then
        warn("[UA Killer Hub | Config] Помилка JSON: " .. tostring(err))
        showNotification("Помилка", "Не вдалося закодувати конфіг", 3)
        return
    end

    ok, err = pcall(function() writefile(configFile, jsonString) end)
    if ok then
        print("[UA Killer Hub | Config] Збережено в " .. configFile)
        showNotification("Успіх", "Налаштування конфігу збережено!", 3)
    else
        warn("[UA Killer Hub | Config] Помилка запису: " .. tostring(err))
        showNotification("Помилка", "Не вдалося записати файл", 3)
    end
end

-- Негайне (синхронне) завантаження — тільки для ручного виклику
loadCurrentConfig = function(isAutoLoad)
    local data, errMsg = readConfigFromDisk()
    if not data then
        local msg = "Конфіг: " .. errMsg
        if isAutoLoad then print("[UA Killer Hub | Config] " .. msg)
        else warn("[UA Killer Hub | Config] " .. msg)
              showNotification("Конфіг", "Файл не знайдено або пошкоджено!", 3.5) end
        return false
    end

    -- Слайдери та фільтр предметів
    if data.JumpPower      and jumpPowerSlider      then jumpPowerSlider:Set(data.JumpPower, true) end
    if data.FlySpeed       and flySpeedSlider       then flySpeedSlider:Set(data.FlySpeed, true) end
    if data.PickupDistance and pickupDistanceSlider then pickupDistanceSlider:Set(data.PickupDistance, true) end

    if type(data.SelectedItems) == "table" then
        for itemName, state in pairs(data.SelectedItems) do
            if _G.SelectedItems[itemName] ~= nil then
                _G.SelectedItems[itemName] = state
                if itemToggleControls[itemName] then itemToggleControls[itemName]:Set(state, false) end
            end
        end
        lastCacheRefresh = 0
    end

    -- Перемикачі (лише візуальна синхронізація через Set(_, false))
    if data.ItemESP          ~= nil and itemEspToggle      then itemEspToggle:Set(data.ItemESP, false)               _G.ItemESP          = data.ItemESP end
    if data.AntiAFK          ~= nil and antiAfkToggle      then antiAfkToggle:Set(data.AntiAFK, true)                end
    if data.AutoRespawn      ~= nil and autoRespawnToggle  then autoRespawnToggle:Set(data.AutoRespawn, true)         end
    if data.StandaloneNoClip ~= nil and noclipToggle       then noclipToggle:Set(data.StandaloneNoClip, true)         end
    if data.AutoSell         ~= nil and autoSellToggle     then autoSellToggle:Set(data.AutoSell, true)               end
    if data.AutoEventCandy   ~= nil and autoCandyToggle    then autoCandyToggle:Set(data.AutoEventCandy, true)        end
    if data.AutoBuy          ~= nil and autoBuyToggle      then autoBuyToggle:Set(data.AutoBuy, true)                 end

    if data.ItemFarm ~= nil and itemFarmToggle then
        _G.ItemFarm = (data.ItemFarm == true)
        itemFarmToggle:Set(_G.ItemFarm, false)   -- лише візуально, без запуску фарму
        print("[UA Killer Hub | Config] ItemFarm завантажено: " .. tostring(_G.ItemFarm))
        if _G.ItemFarm and not isAutoLoad then
            startFarmThread()
        end
    end

    print("[UA Killer Hub | Config] Конфігурацію відновлено.")
    showNotification("Конфіг", "Налаштування завантажено!", 3)
    return true
end

-- ─────────────────────────────────────────────────────────
-- ПОЕТАПНЕ АВТОЗАВАНТАЖЕННЯ (15 секунд очікування + 1 с між кроками)
-- ─────────────────────────────────────────────────────────
local AUTOLOAD_WAIT    = 15   -- секунд перед початком
local AUTOLOAD_STEP    = 1.0  -- секунд між кроками

local function runSteppedAutoLoad()
    -- Крок 0: очікуємо 15 секунд
    showNotification("Auto Load", string.format("Завантаження через %ds...", AUTOLOAD_WAIT), AUTOLOAD_WAIT - 1)
    print(string.format("[UA Killer Hub | AutoLoad] Очікування %d секунд перед завантаженням конфігу...", AUTOLOAD_WAIT))
    task.wait(AUTOLOAD_WAIT)

    -- Зчитуємо конфіг один раз
    local data, errMsg = readConfigFromDisk()
    if not data then
        warn("[UA Killer Hub | AutoLoad] Не вдалося прочитати конфіг: " .. tostring(errMsg))
        showNotification("Auto Load", "Помилка: конфіг не знайдено або пошкоджено", 4)
        return
    end

    print("[UA Killer Hub | AutoLoad] Початок поетапного відновлення налаштувань...")
    showNotification("Auto Load", "Відновлення налаштувань...", 3)

    -- Крок 1: слайдери та список предметів (без затримки між ними)
    if data.JumpPower      and jumpPowerSlider      then jumpPowerSlider:Set(data.JumpPower, true) end
    if data.FlySpeed       and flySpeedSlider       then flySpeedSlider:Set(data.FlySpeed, true) end
    if data.PickupDistance and pickupDistanceSlider then pickupDistanceSlider:Set(data.PickupDistance, true) end

    if type(data.SelectedItems) == "table" then
        for itemName, state in pairs(data.SelectedItems) do
            if _G.SelectedItems[itemName] ~= nil then
                _G.SelectedItems[itemName] = state
                if itemToggleControls[itemName] then itemToggleControls[itemName]:Set(state, false) end
            end
        end
        lastCacheRefresh = 0
        print("[UA Killer Hub | AutoLoad] Слайдери та фільтр предметів відновлено.")
    end

    task.wait(AUTOLOAD_STEP)

    -- Таблиця поетапного відновлення перемикачів
    local toggleMap = {
        { key = "ItemFarm",         ctrl = itemFarmToggle,    label = "Автофарм" },
        { key = "AutoSell",         ctrl = autoSellToggle,    label = "Автопродаж" },
        { key = "AutoEventCandy",   ctrl = autoCandyToggle,   label = "Авто-здача конфет" },
        { key = "AutoBuy",          ctrl = autoBuyToggle,     label = "Автокупівля" },
        { key = "ItemESP",          ctrl = itemEspToggle,     label = "ESP" },
        { key = "AntiAFK",          ctrl = antiAfkToggle,     label = "Anti-AFK" },
        { key = "StandaloneNoClip", ctrl = noclipToggle,      label = "NoClip" },
        { key = "AutoRespawn",      ctrl = autoRespawnToggle, label = "Авто-респавн" },
    }

    -- Спеціальні активатори для кроків, які потребують додаткової логіки
    local specialActivators = {
        ItemFarm = function(val)
            _G.ItemFarm = (val == true)
            if itemFarmToggle then itemFarmToggle:Set(_G.ItemFarm, false) end
            print("[UA Killer Hub | AutoLoad] ItemFarm відновлено: " .. tostring(_G.ItemFarm)
                .. " (ручне підтвердження для запуску переміщення)")
        end,
        AutoSell = function(val)
            _G.AutoSell = (val == true)
            if autoSellToggle then autoSellToggle:Set(_G.AutoSell, false) end
            if _G.AutoSell then syncSellQueue() end
        end,
        AutoEventCandy = function(val)
            _G.AutoEventCandy = (val == true)
            if autoCandyToggle then autoCandyToggle:Set(_G.AutoEventCandy, false) end
        end,
        AutoBuy = function(val)
            _G.AutoBuy = (val == true)
            if autoBuyToggle then autoBuyToggle:Set(_G.AutoBuy, false) end
            if _G.AutoBuy then
                task.spawn(function()
                    while _G.AutoBuy do
                        local char   = player.Character
                        local remote = char and char:FindFirstChild("RemoteEvent")
                        if remote then remote:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" }) end
                        task.wait(2.5 + math.random() * 1.5)
                    end
                end)
            end
        end,
        ItemESP = function(val)
            _G.ItemESP = (val == true)
            if itemEspToggle then itemEspToggle:Set(_G.ItemESP, false) end
        end,
    }

    local totalSteps = #toggleMap
    for i, step in ipairs(toggleMap) do
        if manuallyChanged[step.key] then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' пропущено (ручна зміна).", i, totalSteps, step.label))
            task.wait(AUTOLOAD_STEP)
            continue
        end

        local savedVal = data[step.key]
        if savedVal == true then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' увімкнено.", i, totalSteps, step.label))
            showNotification("Auto Load", string.format("(%d/%d) %s", i, totalSteps, step.label), AUTOLOAD_STEP + 0.5)

            local activator = specialActivators[step.key]
            if activator then
                activator(true)
            elseif step.ctrl then
                step.ctrl:Set(true, true)
            end
        else
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' збережено як false, пропускаємо.", i, totalSteps, step.label))
        end

        task.wait(AUTOLOAD_STEP)
    end

    print("[UA Killer Hub | AutoLoad] Поетапне відновлення завершено.")
    showNotification("Auto Load", "✓ Всі налаштування відновлено!", 4)
end

-- =======================================================
-- ВІДКРИТТЯ ІНТЕРФЕЙСУ (GUI з'являється одразу)
-- =======================================================
switchTab("Головна")
print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

-- Автозавантаження запускається в окремому потоці після показу GUI
if shouldAutoLoad then
    task.spawn(runSteppedAutoLoad)
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
