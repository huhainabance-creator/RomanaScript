-- UA Killer Hub | YBA — Версія з виправленим закриттям діалогу Halloween Event
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

-- =======================================================
-- ЄДИНИЙ КОНТРОЛЕР СТАНУ ITEMFARM
-- =======================================================
local itemFarmToggle

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

local function setItemFarmState(enabled)
    _G.ItemFarm = (enabled == true)

    if itemFarmToggle and itemFarmToggle:Get() ~= _G.ItemFarm then
        itemFarmToggle:Set(_G.ItemFarm, false)
    end

    if _G.ItemFarm then
        startFarmThread()
    else
        farmThreadActive = false
        setFarmStatus("Зупинено")
        stopFlight()
    end

    print(string.format("[UA Killer Hub | Farm] Стан синхронізовано: _G.ItemFarm=%s, farmThreadActive=%s, GUI=%s",
        tostring(_G.ItemFarm),
        tostring(farmThreadActive),
        tostring(itemFarmToggle and itemFarmToggle:Get())))
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

-- Перевірка фактичної видимості GUI-елемента на екрані
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
    if not gui then return end
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

-- Надійне визначення активного діалогового вікна Jack із перевіркою видимості
local function findJackDialogue()
    local gui = getDialogueGui()
    if not gui then return nil end

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

                if lower:find("jack") or lower:find("cauldron specter") then
                    hasJack = true
                end
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

-- Автоматичне закриття діалогу через штатну взаємодію з інтерфейсом
local function clickContinueButton(jackData)
    if not jackData then return end

    -- Повна діагностика знайдених елементів
    print("[UA Killer Hub | Event] Діагностика GUI-елементів діалогу Jack:")
    if jackData.pointsElem then
        print(string.format("  • [PointsLabel] Class: %s | Name: '%s' | Text: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.pointsElem.ClassName, jackData.pointsElem.Name, jackData.pointsElem.Text,
            jackData.pointsElem.AbsolutePosition.X, jackData.pointsElem.AbsolutePosition.Y,
            jackData.pointsElem.AbsoluteSize.X, jackData.pointsElem.AbsoluteSize.Y))
    end
    if jackData.continueElem then
        print(string.format("  • [ContinueElem] Class: %s | Name: '%s' | Text: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.continueElem.ClassName, jackData.continueElem.Name, jackData.continueElem.Text,
            jackData.continueElem.AbsolutePosition.X, jackData.continueElem.AbsolutePosition.Y,
            jackData.continueElem.AbsoluteSize.X, jackData.continueElem.AbsoluteSize.Y))
    end
    if jackData.dialogueBox then
        print(string.format("  • [DialogueBox] Class: %s | Name: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.dialogueBox.ClassName, jackData.dialogueBox.Name,
            jackData.dialogueBox.AbsolutePosition.X, jackData.dialogueBox.AbsolutePosition.Y,
            jackData.dialogueBox.AbsoluteSize.X, jackData.dialogueBox.AbsoluteSize.Y))
    end
    if jackData.anyButton then
        print(string.format("  • [FoundButton] Class: %s | Name: '%s' | Text: '%s'",
            jackData.anyButton.ClassName, jackData.anyButton.Name, tostring(jackData.anyButton.Text or "")))
    end

    pcall(function()
        -- 1. Якщо елемент мітки чи її батьківський контейнер є кнопкою — викликаємо штатні сигнали
        local targetBtn = (jackData.continueElem and jackData.continueElem:IsA("GuiButton") and jackData.continueElem)
            or (jackData.continueElem and jackData.continueElem.Parent and jackData.continueElem.Parent:IsA("GuiButton") and jackData.continueElem.Parent)
            or jackData.anyButton

        if targetBtn then
            print("[UA Killer Hub | Event] Виклик сигналу кнопки: " .. targetBtn.Name)
            if firesignal then
                firesignal(targetBtn.MouseButton1Click)
                firesignal(targetBtn.Activated)
            else
                targetBtn.Activated:Fire()
            end
        end

        -- 2. Штатний клік мишкою по центру чорного діалогового вікна (де розташований текст і де клікає гравець)
        local targetBox = jackData.dialogueBox or (jackData.pointsElem and jackData.pointsElem.Parent) or jackData.pointsElem
        if VirtualInputManager and targetBox and targetBox:IsA("GuiObject") then
            local absPos = targetBox.AbsolutePosition
            local absSize = targetBox.AbsoluteSize
            local clickX = absPos.X + absSize.X / 2
            local clickY = absPos.Y + absSize.Y / 2

            print(string.format("[UA Killer Hub | Event] Клік мишкою по центру рамки діалогу: (%d, %d)", math.floor(clickX), math.floor(clickY)))
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end

        -- 3. Додатковий клік по центру тексту Continue (якщо він окремий від головної рамки)
        if VirtualInputManager and jackData.continueElem and jackData.continueElem:IsA("GuiObject") and jackData.continueElem ~= targetBox then
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
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not remote or not hum or not eventNPC then return false end

    local success = false
    pcall(function()
        print("[UA Killer Hub | Event] Взаємодія з Jack...")
        remote:FireServer("PromptTriggered", eventNPC)

        local optionFound   = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy do
            if clickEventCandyOption() then optionFound = true break end
            task.wait(0.15)
        end
        if not optionFound then
            print("[UA Killer Hub | Event] Меню здачі цукерок не з'явилося.")
            return
        end

        print("[UA Killer Hub | Event] Очікування повідомлення про отримані очки...")
        local pointsFound   = false
        local jackData      = nil
        local pointsTimeout = tick() + 4.0
        while tick() < pointsTimeout and _G.AutoEventCandy do
            jackData = findJackDialogue()
            if jackData and jackData.hasPoints then
                pointsFound = true
                local msgText = jackData.pointsElem and jackData.pointsElem.Text or "Очки отримано"
                print(string.format("[UA Killer Hub | Event] Отримано підтвердження: '%s'", msgText))
                break
            end
            task.wait(0.15)
        end
        if not pointsFound or not jackData then
            print("[UA Killer Hub | Event] Повідомлення про очки не з'явилося (таймаут).")
            return
        end

        task.wait(0.35)

        -- Спроба закриття через визначені елементи
        clickContinueButton(jackData)

        -- Перевірка моменту закриття діалогу
        local closeTimeout = tick() + 2.0
        local isClosed     = false
        while tick() < closeTimeout do
            task.wait(0.15)
            if not findJackDialogue() then
                isClosed = true
                break
            end
        end

        if isClosed then
            print("[UA Killer Hub | Event] Діалог Jack успішно закрито!")
            success = true
        else
            print("[UA Killer Hub | Event] Діалог ще відкритий, виконуємо повторний клік...")
            local retryData = findJackDialogue()
            if retryData then
                clickContinueButton(retryData)
                task.wait(0.3)
                if not findJackDialogue() then
                    print("[UA Killer Hub | Event] Діалог Jack успішно закрито після повторного кліку!")
                    success = true
                end
            end
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

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "UAKillerHub_GUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = targetGuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 520, 0, 400)
MainFrame.Position         = UDim2.new(0.5, -260, 0.5, -200)
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

-- Контейнер сповіщень
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

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetSize = isMinimized and UDim2.new(0, 520, 0, 42) or UDim2.new(0, 520, 0, 400)
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = targetSize }):Play()
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
    activeTab    = tabName
    SearchBox.Text = ""
    for name, tabData in pairs(tabs) do
        local active = (name == tabName)
        tabData.Page.Visible = active
        TweenService:Create(tabData.Button, TweenInfo.new(0.2), {
            BackgroundColor3 = active and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(23, 25, 32),
            TextColor3       = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 165),
        }):Play()
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
    btn.MouseButton1Click:Connect(function() switchTab(tabName) end)
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
        toggleState = (val == true)
        TweenService:Create(switch, TweenInfo.new(0.2), {
            BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58),
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        }):Play()
        if triggerCallback and callback then callback(toggleState) end
    end

    switch.MouseButton1Click:Connect(function()
        setState(not toggleState, true)
    end)

    local controlObj = {
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, val, triggerCallback)
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
            draggingSlider = true
            updateFromPos(input.Position.X)
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
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, val, triggerCallback)
            val = tonumber(val)
            if not val then return end
            if triggerCallback == nil then triggerCallback = true end
            currentVal    = math.clamp(val, min, max)
            valLabel.Text = tostring(currentVal)
            fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
            if triggerCallback and callback then callback(currentVal) end
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

    btn.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(36, 40, 52) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        task.wait(0.08)
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
        if callback then callback() end
    end)

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
    return { Set = function(self, txt) lbl.Text = txt end }
end

-- =======================================================
-- СТОРІНКИ ТА ЕЛЕМЕНТИ UI
-- =======================================================
local mainPage = createTab("Головна",  "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин",  "🛒")
local miscPage = createTab("Інше",     "⚙")

local autoLoadToggle, jumpPowerSlider, flySpeedSlider, pickupDistanceSlider
local itemEspToggle, autoSellToggle, autoCandyToggle
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
    if loadCurrentConfig then loadCurrentConfig(false) end
end)

createButton(mainPage, "Головна", "Зберегти поточний конфіг", function()
    if saveCurrentConfig then saveCurrentConfig() end
end)

createSection(mainPage, "Головна", "Характеристики")

jumpPowerSlider = createSlider(mainPage, "Головна", "Висота стрибка (JumpPower)", 50, 200, 1, JP_Value, function(val)
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

flySpeedSlider = createSlider(farmPage, "Автофарм", "Швидкість польоту", 50, 350, 5, _G.FlySpeed, function(val)
    _G.FlySpeed = val
end)

pickupDistanceSlider = createSlider(farmPage, "Автофарм", "Дистанція підбору", 2, 8, 0.5, _G.PickupDistance, function(val)
    _G.PickupDistance = val
end)

itemEspToggle = createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    manuallyChanged.ItemESP = true
    _G.ItemESP = val
end)

-- Ініціалізація перемикача ItemFarm через єдиний контролер
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
    local ctrl = createToggle(farmPage, "Автофарм", itemName, _G.SelectedItems[itemName], function(val)
        _G.SelectedItems[itemName] = val
        lastCacheRefresh = 0
    end)
    itemToggleControls[itemName] = ctrl
end

-- ── Магазин ──────────────────────────────────────────────
createSection(shopPage, "Магазин", "Торгівля та івенти")

autoSellToggle = createToggle(shopPage, "Магазин", "Автопродаж (крім Lucky Arrow)", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    _G.AutoSell = value
    if value then syncSellQueue()
    else table.clear(sellQueue) closeMerchantDialogue() end
end)

autoCandyToggle = createToggle(shopPage, "Магазин", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = value
end)

autoBuyToggle = createToggle(shopPage, "Магазин", "Автокупівля (Lucky Arrow)", _G.AutoBuy, function(value)
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

antiAfkToggle = createToggle(miscPage, "Інше", "Anti-AFK", _G.AntiAFK, function(value)
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

noclipToggle = createToggle(miscPage, "Інше", "NoClip (окремо від фарму)", _G.StandaloneNoClip, function(value)
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

createButton(miscPage, "Інше", "Очистити заблоковані координати", function()
    table.clear(bannedCoordinates)
    lastCacheRefresh = 0
    showNotification("UA Killer Hub", "Чорний список координат очищено", 3)
end)

print("[UA Killer Hub | GUI] Усі вкладки та елементи MonHub створено.")

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЇ
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

-- Ручне синхронне завантаження
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

    -- Перемикачі
    if data.ItemESP          ~= nil and itemEspToggle      then itemEspToggle:Set(data.ItemESP, false) _G.ItemESP = data.ItemESP end
    if data.AntiAFK          ~= nil and antiAfkToggle      then antiAfkToggle:Set(data.AntiAFK, true) end
    if data.AutoRespawn      ~= nil and autoRespawnToggle  then autoRespawnToggle:Set(data.AutoRespawn, true) end
    if data.StandaloneNoClip ~= nil and noclipToggle       then noclipToggle:Set(data.StandaloneNoClip, true) end
    if data.AutoSell         ~= nil and autoSellToggle     then autoSellToggle:Set(data.AutoSell, true) end
    if data.AutoEventCandy   ~= nil and autoCandyToggle    then autoCandyToggle:Set(data.AutoEventCandy, true) end
    if data.AutoBuy          ~= nil and autoBuyToggle      then autoBuyToggle:Set(data.AutoBuy, true) end

    if data.ItemFarm ~= nil then
        setItemFarmState(data.ItemFarm == true)
    end

    print("[UA Killer Hub | Config] Конфігурацію відновлено.")
    showNotification("Конфіг", "Налаштування завантажено!", 3)
    return true
end

-- =======================================================
-- ПОЕТАПНЕ АВТОЗАВАНТАЖЕННЯ (15с затримка + 1с між кроками)
-- =======================================================
local AUTOLOAD_WAIT = 15
local AUTOLOAD_STEP = 1.0

local function runSteppedAutoLoad()
    showNotification("Auto Load", string.format("Завантаження через %ds...", AUTOLOAD_WAIT), AUTOLOAD_WAIT - 1)
    print(string.format("[UA Killer Hub | AutoLoad] Очікування %d секунд перед завантаженням конфігу...", AUTOLOAD_WAIT))
    task.wait(AUTOLOAD_WAIT)

    local data, errMsg = readConfigFromDisk()
    if not data then
        warn("[UA Killer Hub | AutoLoad] Не вдалося прочитати конфіг: " .. tostring(errMsg))
        showNotification("Auto Load", "Помилка: конфіг не знайдено або пошкоджено", 4)
        return
    end

    print("[UA Killer Hub | AutoLoad] Початок поетапного відновлення налаштувань...")
    showNotification("Auto Load", "Відновлення налаштувань...", 3)

    -- 1. Слайдери та фільтр предметів
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

    local steps = {
        {
            key     = "ItemFarm",
            control = itemFarmToggle,
            label   = "Автофарм",
            activate = function(val)
                setItemFarmState(val == true)
            end,
        },
        {
            key     = "AutoSell",
            control = autoSellToggle,
            label   = "Автопродаж",
            activate = function(val)
                _G.AutoSell = (val == true)
                if autoSellToggle then autoSellToggle:Set(_G.AutoSell, false) end
                if _G.AutoSell then syncSellQueue() end
            end,
        },
        {
            key     = "AutoEventCandy",
            control = autoCandyToggle,
            label   = "Авто-здача конфет",
            activate = function(val)
                _G.AutoEventCandy = (val == true)
                if autoCandyToggle then autoCandyToggle:Set(_G.AutoEventCandy, false) end
            end,
        },
        {
            key     = "AutoBuy",
            control = autoBuyToggle,
            label   = "Автокупівля",
            activate = function(val)
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
        },
        {
            key     = "ItemESP",
            control = itemEspToggle,
            label   = "ESP",
            activate = function(val)
                _G.ItemESP = (val == true)
                if itemEspToggle then itemEspToggle:Set(_G.ItemESP, false) end
            end,
        },
        {
            key     = "AntiAFK",
            control = antiAfkToggle,
            label   = "Anti-AFK",
            activate = function(val)
                if antiAfkToggle then antiAfkToggle:Set((val == true), true) end
            end,
        },
        {
            key     = "StandaloneNoClip",
            control = noclipToggle,
            label   = "NoClip",
            activate = function(val)
                if noclipToggle then noclipToggle:Set((val == true), true) end
            end,
        },
        {
            key     = "AutoRespawn",
            control = autoRespawnToggle,
            label   = "Авто-респавн",
            activate = function(val)
                if autoRespawnToggle then autoRespawnToggle:Set((val == true), true) end
            end,
        },
    }

    local totalSteps = #steps
    for i, step in ipairs(steps) do
        if manuallyChanged[step.key] then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' пропущено (ручна зміна гравцем).", i, totalSteps, step.label))
            task.wait(AUTOLOAD_STEP)
            continue
        end

        local savedVal = data[step.key]
        if savedVal == true then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' увімкнено.", i, totalSteps, step.label))
            showNotification("Auto Load", string.format("(%d/%d) %s", i, totalSteps, step.label), AUTOLOAD_STEP + 0.5)
            step.activate(true)
        else
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' збережено як false, пропускаємо.", i, totalSteps, step.label))
        end

        task.wait(AUTOLOAD_STEP)
    end

    print("[UA Killer Hub | AutoLoad] Поетапне відновлення завершено.")
    showNotification("Auto Load", "✓ Всі налаштування відновлено!", 4)
end

-- =======================================================
-- ВІДКРИТТЯ ІНТЕРФЕЙСУ
-- =======================================================
switchTab("Головна")
print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

if shouldAutoLoad then
    task.spawn(runSteppedAutoLoad)
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
