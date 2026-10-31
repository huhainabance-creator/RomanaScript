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
        local OldIndexItem;
        OldIndexItem = hookmetamethod(game, "__index", newcclosure(function(self, Key)
            if not checkcaller() and typeof(Key) == "string" and Key:lower() == "magnitude" then
                local calling = getcallingscript()
                if calling and calling.Name == "ItemSpawn" then
                    return 0
                end
            end
            return OldIndexItem(self, Key)
        end))
        print("[UA Killer Hub | Bypass] Item Magnitude Bypass активовано.")
    end
end)

-- =======================================================
-- БЕЗПЕЧНА АКТИВАЦІЯ CRASH & WALKSPEED BYPASS
-- =======================================================
pcall(function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local FunctionLibraryModule = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("FunctionLibrary")
    if FunctionLibraryModule then
        local FunctionLibrary = require(FunctionLibraryModule)
        if FunctionLibrary and FunctionLibrary.pcall and getupvalues then
            local OldPcall = FunctionLibrary.pcall
            FunctionLibrary.pcall = function(...)
                local args = {...}
                if type(args[1]) == "function" then
                    local ups = getupvalues(args[1])
                    if ups and #ups == 11 then
                        return
                    end
                end
                return OldPcall(...)
            end
            print("[UA Killer Hub | Bypass] WalkSpeed/Crash Bypass активовано.")
        end
    end
end)

-- =======================================================
-- ПЕРЕВІРКА ТА ІНІЦІАЛІЗАЦІЯ ФАЙЛІВ КОНФІГУРАЦІЇ
-- =======================================================
pcall(function()
    if makefolder and isfolder and not isfolder("UAKillerHub") then
        makefolder("UAKillerHub")
    end
    if isfile and isfile(autoLoadFile) then
        if readfile then
            shouldAutoLoad = (readfile(autoLoadFile) == "true")
        end
    elseif writefile then
        writefile(autoLoadFile, "false")
    end
end)

-- =======================================================
-- ГЛОБАЛЬНІ ЗМІННІ СТАНУ ТА НАЛАШТУВАНЬ
-- =======================================================
_G.ItemFarm         = false
_G.FarmSpeed        = 60
_G.ItemDistance     = 5000
_G.ItemESP          = false
_G.SelectedItems    = {}
_G.AntiAFK          = false
_G.StandaloneNoClip = false
_G.AutoRespawn      = true
_G.AutoSell         = false
_G.AutoEventCandy   = false
_G.AutoBuy          = false

local defaultSettings = {
    FarmSpeed    = 60,
    ItemDistance = 5000,
    AutoRespawn  = true,
}

local bannedCoordinates  = {}
local failedItemAttempts = {}
local espObjects         = {}
local itemCache          = {}
local lastCacheRefresh   = 0
local CACHE_REFRESH_INTERVAL = 1.25
local BAN_TTL            = 30

local farmThreadActive   = false
local farmSessionId      = 0
local farmStatusText     = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection
local JP_Value = 50

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

local function markManuallyChanged(flag)
    manuallyChanged[flag] = true
end

-- =======================================================
-- ДОПОМІЖНІ ФУНКЦІЇ ДЛЯ ГРАВЦЯ ТА ПЕРСОНАЖА
-- =======================================================
local function getCharacter()
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart", 5) or char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    local hum  = char:WaitForChild("Humanoid", 5) or char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function ensureNoClip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if not _G.ItemFarm and not _G.StandaloneNoClip then
            if noclipConnection then
                noclipConnection:Disconnect()
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
end

local function cleanupFlight()
    if flightState then
        pcall(function()
            if flightState.bodyPos and flightState.bodyPos.Parent then
                flightState.bodyPos:Destroy()
            end
            if flightState.bodyGyro and flightState.bodyGyro.Parent then
                flightState.bodyGyro:Destroy()
            end
            if flightState.heartbeatConn then
                flightState.heartbeatConn:Disconnect()
            end
        end)
        flightState = nil
    end

    local char, root, hum = getCharacter()
    if hum then
        hum.PlatformStand = false
    end
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

player.CharacterAdded:Connect(function(char)
    cleanupFlight()
    task.wait(0.5)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        hum.Died:Connect(function()
            cleanupFlight()
            if _G.AutoRespawn then
                task.wait(0.2)
                pcall(function()
                    player:LoadCharacter()
                end)
            end
        end)
    end
end)

-- =======================================================
-- СИСТЕМА ДІАЛОГОВОГО GUI ТА ВИЗНАЧЕННЯ ВИДИМОСТІ
-- =======================================================
local function getDialogueGui()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("DialogueGui") or pg:FindFirstChild("Dialogue") or pg:FindFirstChild("DialogueBox")
    if gui and gui:IsA("ScreenGui") and not gui.Enabled then
        return nil
    end
    return gui
end

-- Перевірка фактичної видимості GUI-елемента на екрані
local function isGuiElementVisible(elem)
    if not elem or not elem:IsA("GuiObject") then return false end
    if not elem.Visible then return false end
    if elem.AbsoluteSize.X <= 0 or elem.AbsoluteSize.Y <= 0 then return false end
    if elem:IsA("TextLabel") or elem:IsA("TextButton") then
        if elem.TextTransparency >= 1 and elem.BackgroundTransparency >= 1 then
            return false
        end
    end
    local current = elem.Parent
    while current and current:IsA("GuiObject") do
        if not current.Visible then return false end
        if current:IsA("CanvasGroup") and current.GroupTransparency >= 1 then return false end
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

-- =======================================================
-- МОДУЛЬ АВТОПРОДАЖУ ТА ОБРОБКИ ІНВЕНТАРЮ
-- =======================================================
local sellQueue  = {}
local isBusy     = false

local function isItemInQueue(item)
    for _, queuedItem in ipairs(sellQueue) do
        if queuedItem == item then return true end
    end
    return false
end

local function queueItemForSale(item)
    if not _G.AutoSell or not item or not item:IsA("Tool") then return end
    if item.Name == "Lucky Arrow" then return end
    if isItemInQueue(item) then return end
    table.insert(sellQueue, item)
end

local function syncSellQueue()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            queueItemForSale(item)
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            queueItemForSale(item)
        end
    end
end

local function hasSellableItems()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and item.Name ~= "Lucky Arrow" then return true end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name ~= "Lucky Arrow" then return true end
        end
    end
    return false
end

local function autoClickDialogueButtons()
    local gui = getDialogueGui()
    if not gui then return false end
    local clicked = false
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then txt = childText.Text end
            local lowerTxt = txt:lower()
            if lowerTxt:find("sell") or lowerTxt:find("yes") or lowerTxt:find("deal") or lowerTxt:find("sure") or lowerTxt:find("anything else") then
                pcall(function()
                    if firesignal then
                        firesignal(btn.MouseButton1Click)
                        firesignal(btn.Activated)
                    else
                        btn.Activated:Fire()
                    end
                end)
                clicked = true
            end
        end
    end
    return clicked
end

local function closeMerchantDialogue()
    local char = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")
    if remote then
        remote:FireServer("EndDialogue", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Merchant" })
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
    end
    local gui = getDialogueGui()
    if gui then
        for _, btn in ipairs(gui:GetDescendants()) do
            if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
                local txt = (btn.Text or ""):lower()
                local childText = btn:FindFirstChildOfClass("TextLabel")
                if childText then txt = (childText.Text or ""):lower() end
                if txt:find("bye") or txt:find("no") or txt:find("leave") or txt:find("close") or txt:find("see ya") then
                    pcall(function()
                        if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                        else btn.Activated:Fire() end
                    end)
                end
            end
        end
    end
end

local function initBackpackTracking()
    local function hookBackpack(bp)
        if not bp then return end
        bp.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and _G.AutoSell then
                task.wait(0.1)
                queueItemForSale(child)
            end
        end)
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then hookBackpack(bp) end
    player.ChildAdded:Connect(function(child)
        if child.Name == "Backpack" and child:IsA("Backpack") then
            hookBackpack(child)
        end
    end)
    player.CharacterAdded:Connect(function(char)
        char.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and _G.AutoSell then
                queueItemForSale(child)
            end
        end)
    end)
end
initBackpackTracking()

-- =======================================================
-- МОДУЛЬ HALLOWEEN EVENT (NPC JACK)
-- =======================================================
local function getEventNPC()
    local npcs = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("NPC") or workspace
    for _, desc in ipairs(npcs:GetDescendants()) do
        if desc:IsA("Model") and (desc.Name:find("Jack") or desc.Name:find("Cauldron") or desc.Name:find("Specter")) then
            return desc
        end
    end
    return nil
end

local function countTotalCandies()
    local count = 0
    local backpack = player:FindFirstChild("Backpack")
    local char = player.Character
    local function checkContainer(cont)
        if not cont then return end
        for _, item in ipairs(cont:GetChildren()) do
            if item:IsA("Tool") and (item.Name:lower():find("candy") or item.Name:lower():find("candies")) then
                count = count + 1
            end
        end
    end
    checkContainer(backpack)
    checkContainer(char)
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

local function findJackDialogue()
    local gui = getDialogueGui()
    if not gui then return nil end

    local hasJack      = false
    local hasPoints    = false
    local continueElem = nil
    local pointsElem   = nil
    local dialogueBox  = nil
    local continueBtn  = nil

    local camera = workspace.CurrentCamera
    local vpSize = (camera and camera.ViewportSize) or Vector2.new(1920, 1080)

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
                end

                if lower:find("click to continue") or lower:find("click to contnue") or (lower:find("continue") and not lower:find("option")) then
                    continueElem = desc
                    if desc:IsA("GuiButton") then
                        continueBtn = desc
                    elseif desc.Parent and desc.Parent:IsA("GuiButton") then
                        continueBtn = desc.Parent
                    end
                end
            end
        end

        if desc:IsA("Frame") and isGuiElementVisible(desc) then
            local size = desc.AbsoluteSize
            if size.X >= 180 and size.X <= vpSize.X * 0.92 and size.Y >= 50 and size.Y <= vpSize.Y * 0.65 then
                if not dialogueBox or (continueElem and desc:IsAncestorOf(continueElem)) or (pointsElem and desc:IsAncestorOf(pointsElem)) then
                    dialogueBox = desc
                end
            end
        end
    end

    if not dialogueBox then
        local ref = continueElem or pointsElem
        local cur = ref and ref.Parent
        while cur and cur:IsA("GuiObject") do
            if cur:IsA("Frame") and cur.AbsoluteSize.Y >= 40 then
                dialogueBox = cur
                break
            end
            cur = cur.Parent
        end
    end

    if (hasJack or hasPoints or continueElem) then
        return {
            gui          = gui,
            hasJack      = hasJack,
            hasPoints    = hasPoints,
            continueElem = continueElem,
            pointsElem   = pointsElem,
            dialogueBox  = dialogueBox,
            continueBtn  = continueBtn,
        }
    end

    return nil
end

local function clickContinueButton(jackData)
    if not jackData then
        warn("[UA Killer Hub | Event] clickContinueButton: jackData відсутній (nil).")
        return false
    end

    print("[UA Killer Hub | Event] Діагностика елементів діалогу перед кліком:")
    if jackData.pointsElem then
        print(string.format("  • [PointsElem] Class: %s | Text: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.pointsElem.ClassName, jackData.pointsElem.Text,
            math.floor(jackData.pointsElem.AbsolutePosition.X), math.floor(jackData.pointsElem.AbsolutePosition.Y),
            math.floor(jackData.pointsElem.AbsoluteSize.X), math.floor(jackData.pointsElem.AbsoluteSize.Y)))
    else
        print("  • [PointsElem] не знайдено")
    end

    if jackData.continueElem then
        print(string.format("  • [ContinueElem] Class: %s | Text: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.continueElem.ClassName, jackData.continueElem.Text,
            math.floor(jackData.continueElem.AbsolutePosition.X), math.floor(jackData.continueElem.AbsolutePosition.Y),
            math.floor(jackData.continueElem.AbsoluteSize.X), math.floor(jackData.continueElem.AbsoluteSize.Y)))
    else
        print("  • [ContinueElem] не знайдено (напис ще формується або не видимий)")
    end

    if jackData.dialogueBox then
        print(string.format("  • [DialogueBox] Class: %s | Name: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.dialogueBox.ClassName, jackData.dialogueBox.Name,
            math.floor(jackData.dialogueBox.AbsolutePosition.X), math.floor(jackData.dialogueBox.AbsolutePosition.Y),
            math.floor(jackData.dialogueBox.AbsoluteSize.X), math.floor(jackData.dialogueBox.AbsoluteSize.Y)))
    else
        print("  • [DialogueBox] не знайдено")
    end

    if jackData.continueBtn then
        print(string.format("  • [ContinueBtn] Class: %s | Name: '%s' (справжня кнопка)",
            jackData.continueBtn.ClassName, jackData.continueBtn.Name))
    end

    local clicked = false

    if jackData.continueBtn then
        local ok, err = pcall(function()
            if firesignal then
                firesignal(jackData.continueBtn.MouseButton1Click)
                firesignal(jackData.continueBtn.Activated)
            else
                jackData.continueBtn.Activated:Fire()
            end
        end)
        if ok then
            print("[UA Killer Hub | Event] Сигнал кнопки продовження успішно відправлено.")
            clicked = true
        else
            warn("[UA Killer Hub | Event] Помилка виклику сигналу кнопки: " .. tostring(err))
        end
    end

    if VirtualInputManager and jackData.continueElem and jackData.continueElem:IsA("GuiObject") and isGuiElementVisible(jackData.continueElem) then
        local absPos = jackData.continueElem.AbsolutePosition
        local absSize = jackData.continueElem.AbsoluteSize
        local clickX = math.floor(absPos.X + absSize.X / 2)
        local clickY = math.floor(absPos.Y + absSize.Y / 2)

        local ok, err = pcall(function()
            print(string.format("[UA Killer Hub | Event] Клік мишкою по ContinueElem: (%d, %d)", clickX, clickY))
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end)
        if ok then
            clicked = true
        else
            warn("[UA Killer Hub | Event] Помилка SendMouseButtonEvent (ContinueElem): " .. tostring(err))
        end
    end

    if VirtualInputManager and jackData.dialogueBox and jackData.dialogueBox:IsA("GuiObject") and isGuiElementVisible(jackData.dialogueBox) then
        local absPos = jackData.dialogueBox.AbsolutePosition
        local absSize = jackData.dialogueBox.AbsoluteSize
        local clickX = math.floor(absPos.X + absSize.X / 2)
        local clickY = math.floor(absPos.Y + absSize.Y / 2)

        local ok, err = pcall(function()
            print(string.format("[UA Killer Hub | Event] Клік мишкою по центру DialogueBox: (%d, %d)", clickX, clickY))
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end)
        if ok then
            clicked = true
        else
            warn("[UA Killer Hub | Event] Помилка SendMouseButtonEvent (DialogueBox): " .. tostring(err))
        end
    end

    return clicked
end

local function submitAllCandies()
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()

    if not remote or not hum or not eventNPC then
        warn("[UA Killer Hub | Event] Не знайдено RemoteEvent, Humanoid або Jack NPC.")
        return false
    end

    pcall(function()
        hum:UnequipTools()
    end)
    task.wait(0.1)

    local success = false
    local outerOk, outerErr = pcall(function()
        print("[UA Killer Hub | Event] Взаємодія з Jack...")
        remote:FireServer("PromptTriggered", eventNPC)

        local optionFound   = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy do
            if clickEventCandyOption() then
                optionFound = true
                break
            end
            task.wait(0.15)
        end

        if not optionFound then
            print("[UA Killer Hub | Event] Меню здачі цукерок не з'явилося.")
            return
        end

        print("[UA Killer Hub | Event] Очікування появи очок та напису CLICK TO CONTINUE...")
        local pointsFound   = false
        local continueFound = false
        local jackData      = nil
        local waitTimeout   = tick() + 5.0

        while tick() < waitTimeout and _G.AutoEventCandy do
            jackData = findJackDialogue()
            if jackData then
                if jackData.hasPoints then
                    pointsFound = true
                end
                if jackData.continueElem and isGuiElementVisible(jackData.continueElem) then
                    continueFound = true
                    print("[UA Killer Hub | Event] Напис CLICK TO CONTINUE успішно розпізнано.")
                    break
                end
            end
            task.wait(0.15)
        end

        if not pointsFound and not continueFound then
            warn("[UA Killer Hub | Event] Повідомлення про очки або Continue не з'явилося (таймаут).")
            return
        end

        task.wait(0.25)

        local isClosed = false
        for attempt = 1, 3 do
            local currentData = findJackDialogue()
            if not currentData then
                isClosed = true
                break
            end

            print(string.format("[UA Killer Hub | Event] Спроба закриття діалогу #%d...", attempt))
            clickContinueButton(currentData)

            local checkStart = tick()
            while tick() - checkStart < 0.8 do
                task.wait(0.1)
                if not findJackDialogue() then
                    isClosed = true
                    break
                end
            end

            if isClosed then break end
        end

        if isClosed then
            print("[UA Killer Hub | Event] Діалог Jack успішно закрито!")
            success = true
        else
            warn("[UA Killer Hub | Event] Діалог Jack не закрито після 3 спроб.")
        end
    end)

    if not outerOk then
        warn("[UA Killer Hub | Event] Помилка під час виконання submitAllCandies: " .. tostring(outerErr))
    end

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

            while #sellQueue > 0 and _G.AutoSell do
                local currentItem = table.remove(sellQueue, 1)

                if currentItem and currentItem.Parent and currentItem:IsA("Tool") and currentItem.Name ~= "Lucky Arrow" then
                    local char, _, hum = getCharacter()
                    local remote = char and char:FindFirstChild("RemoteEvent")

                    if hum and remote then
                        local sellSuccess = false
                        local attempts = 0

                        while attempts < 3 and not sellSuccess and _G.AutoSell do
                            attempts = attempts + 1

                            if currentItem.Parent == player:FindFirstChild("Backpack") then
                                hum:EquipTool(currentItem)
                                task.wait(0.15)
                            end

                            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue2", NPC = "Merchant" })
                            task.wait(0.2)
                            autoClickDialogueButtons()
                            task.wait(0.2)
                            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
                            task.wait(0.2)
                            autoClickDialogueButtons()

                            local checkStart = tick()
                            while tick() - checkStart < 1.0 do
                                task.wait(0.1)
                                if isItemSold(currentItem) then
                                    sellSuccess = true
                                    break
                                end
                            end

                            if not sellSuccess then
                                task.wait(0.3)
                            end
                        end

                        if not sellSuccess then
                            warn("[UA Killer Hub | AutoSell] Не вдалося підтвердити продаж предмета: " .. currentItem.Name)
                        else
                            print("[UA Killer Hub | AutoSell] Успішно продано предмет: " .. currentItem.Name)
                        end
                    end
                end

                task.wait(0.2)
            end

            closeMerchantDialogue()
            isBusy = false
            continue
        end
    end
end)

-- =======================================================
-- МОДУЛЬ АВТОФАРМУ (ITEM FARM) ТА ESP
-- =======================================================
local function flyTo(targetCFrame, speed, onStep)
    local char, root, hum = getCharacter()
    if not root or not hum then return false end

    cleanupFlight()
    ensureNoClip()

    local startPos = root.Position
    local targetPos = targetCFrame.Position
    local totalDist = (targetPos - startPos).Magnitude

    if totalDist < 5 then
        root.CFrame = targetCFrame
        return true
    end

    local actualSpeed = math.clamp(speed or _G.FarmSpeed or 60, 10, 150)
    local duration = totalDist / actualSpeed

    local bodyPos = Instance.new("BodyPosition")
    bodyPos.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bodyPos.P = 15000
    bodyPos.D = 1200
    bodyPos.Position = startPos
    bodyPos.Parent = root

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bodyGyro.P = 15000
    bodyGyro.D = 500
    bodyGyro.CFrame = targetCFrame
    bodyGyro.Parent = root

    hum.PlatformStand = true

    flightState = {
        bodyPos = bodyPos,
        bodyGyro = bodyGyro,
        targetCFrame = targetCFrame,
        heartbeatConn = nil,
    }

    local startTime = tick()
    local reached = false

    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not _G.ItemFarm or not flightState then
            if conn then conn:Disconnect() end
            return
        end

        local elapsed = tick() - startTime
        local alpha = math.clamp(elapsed / duration, 0, 1)

        local currentTargetPos = startPos:Lerp(targetPos, alpha)
        bodyPos.Position = currentTargetPos
        bodyGyro.CFrame = targetCFrame

        if onStep then
            pcall(onStep, currentTargetPos, alpha)
        end

        if alpha >= 1 or (root.Position - targetPos).Magnitude < 4 then
            reached = true
            if conn then conn:Disconnect() end
        end
    end)

    flightState.heartbeatConn = conn

    local waitTimeout = tick() + duration + 1.5
    while not reached and tick() < waitTimeout and _G.ItemFarm and flightState do
        task.wait(0.05)
    end

    cleanupFlight()

    if reached and root then
        root.CFrame = targetCFrame
    end

    return reached
end

local function cleanBannedCoordinates()
    local now = tick()
    for key, timestamp in pairs(bannedCoordinates) do
        if now - timestamp > BAN_TTL then
            bannedCoordinates[key] = nil
        end
    end
end

local function isCoordBanned(pos)
    cleanBannedCoordinates()
    local key = string.format("%d_%d_%d", math.floor(pos.X / 4), math.floor(pos.Y / 4), math.floor(pos.Z / 4))
    return bannedCoordinates[key] ~= nil
end

local function banCoordinate(pos)
    local key = string.format("%d_%d_%d", math.floor(pos.X / 4), math.floor(pos.Y / 4), math.floor(pos.Z / 4))
    bannedCoordinates[key] = tick()
end

local function isItemSpawnDescendant(inst)
    local current = inst
    while current and current ~= workspace do
        if current.Name == "ItemSpawn" then return true end
        current = current.Parent
    end
    return false
end

local function refreshItemCache()
    local now = tick()
    if now - lastCacheRefresh < CACHE_REFRESH_INTERVAL and #itemCache > 0 then
        local filtered = {}
        for _, item in ipairs(itemCache) do
            if item and item.Parent and item:IsDescendantOf(workspace) then
                table.insert(filtered, item)
            end
        end
        itemCache = filtered
        return itemCache
    end

    local scanStart = tick()
    local found = {}

    local function scanContainer(cont)
        if not cont then return end
        for _, obj in ipairs(cont:GetChildren()) do
            if obj:IsA("Tool") or (obj:IsA("Model") and obj:FindFirstChildOfClass("TouchTransmitter", true)) then
                table.insert(found, obj)
            elseif obj.Name == "ItemSpawn" then
                for _, child in ipairs(obj:GetChildren()) do
                    if child:IsA("Tool") or child:IsA("BasePart") or child:IsA("Model") then
                        table.insert(found, child)
                    end
                end
            end
        end
    end

    scanContainer(workspace)
    local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("ItemSpawns")
    if mapFolder then scanContainer(mapFolder) end

    itemCache = found
    lastCacheRefresh = tick()
    return itemCache
end

local function findTargetItems()
    local candidates = {}
    local _, root = getCharacter()
    if not root then return candidates end

    local myPos = root.Position
    local items = refreshItemCache()

    for _, obj in ipairs(items) do
        if obj and obj.Parent and obj:IsDescendantOf(workspace) then
            local isSelected = _G.SelectedItems[obj.Name] == true

            if isSelected then
                local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                if part and not isCoordBanned(part.Position) then
                    local dist = (part.Position - myPos).Magnitude
                    if dist <= (_G.ItemDistance or 5000) then
                        table.insert(candidates, {
                            instance = obj,
                            part = part,
                            distance = dist,
                            name = obj.Name,
                        })
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    return candidates
end

local function pickupItem(itemObj, part)
    if not itemObj or not itemObj.Parent then return false end

    local char, root = getCharacter()
    if not root then return false end

    local prompt = itemObj:FindFirstChildOfClass("ProximityPrompt", true)
    local touch  = part:FindFirstChildOfClass("TouchTransmitter") or itemObj:FindFirstChildOfClass("TouchTransmitter", true)

    local targetPos = part.Position
    local targetCFrame = CFrame.new(targetPos)

    local reached = flyTo(targetCFrame, _G.FarmSpeed, function(curPos)
        if touch and root then
            firetouchinterest(root, part, 0)
            task.wait()
            firetouchinterest(root, part, 1)
        end
    end)

    if not reached then return false end

    local function checkPickedUp()
        if not itemObj or not itemObj.Parent or not itemObj:IsDescendantOf(workspace) then
            return true
        end
        return false
    end

    if prompt and prompt.Parent then
        local fired = false
        pcall(function()
            if fireproximityprompt then
                fireproximityprompt(prompt)
                fired = true
            end
        end)
        if not fired then
            pcall(function()
                prompt:InputHoldBegin()
                task.wait(prompt.HoldDuration + 0.05)
                prompt:InputHoldEnd()
            end)
        end
    end

    if touch and root then
        firetouchinterest(root, part, 0)
        task.wait(0.05)
        firetouchinterest(root, part, 1)
    end

    local waitConfirm = tick() + 0.6
    while tick() < waitConfirm do
        if checkPickedUp() then return true end
        task.wait(0.05)
    end

    return checkPickedUp()
end

local function runItemFarmLoop(sessionId)
    task.spawn(function()
        while _G.ItemFarm and sessionId == farmSessionId do
            task.wait(0.1)

            if isBusy then
                setFarmStatus("Очікування завершення продажів...")
                task.wait(0.5)
                continue
            end

            local targets = findTargetItems()

            if #targets == 0 then
                setFarmStatus("Пошук предметів на карті...")
                task.wait(0.8)
                continue
            end

            for _, target in ipairs(targets) do
                if not _G.ItemFarm or sessionId ~= farmSessionId or isBusy then break end

                local obj = target.instance
                local part = target.part

                if not obj or not obj.Parent or not part or not part.Parent then continue end
                if isCoordBanned(part.Position) then continue end

                setFarmStatus(string.format("Збір: %s (%.0f м)", target.name, target.distance))

                local attempts = failedItemAttempts[obj] or 0
                local success = pickupItem(obj, part)

                if success then
                    failedItemAttempts[obj] = nil
                    setFarmStatus("Предмет підібрано успішно!")
                    task.wait(0.1)
                    break
                else
                    attempts = attempts + 1
                    failedItemAttempts[obj] = attempts

                    if attempts >= 2 then
                        banCoordinate(part.Position)
                        failedItemAttempts[obj] = nil
                        setFarmStatus(string.format("Предмет %s пропущено (чорний список)", target.name))
                    else
                        setFarmStatus(string.format("Помилка підбору %s, повторна спроба...", target.name))
                    end
                end
            end
        end

        cleanupFlight()
        setFarmStatus("Фарм зупинено.")
        farmThreadActive = false
    end)
end

-- =======================================================
-- СИСТЕМА ПІДТРИМКИ ESP
-- =======================================================
local function clearESP()
    for obj, esp in pairs(espObjects) do
        pcall(function()
            if esp.box then esp.box:Destroy() end
            if esp.billboard then esp.billboard:Destroy() end
        end)
    end
    table.clear(espObjects)
end

task.spawn(function()
    while true do
        task.wait(1.0)
        if _G.ItemESP then
            local items = refreshItemCache()
            local activeSet = {}

            for _, obj in ipairs(items) do
                if obj and obj.Parent and obj:IsDescendantOf(workspace) then
                    activeSet[obj] = true
                    if not espObjects[obj] then
                        local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                        if part then
                            local highlight = Instance.new("Highlight")
                            highlight.Adornee = obj
                            highlight.FillColor = Color3.fromRGB(139, 124, 246)
                            highlight.FillTransparency = 0.5
                            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                            highlight.OutlineTransparency = 0
                            highlight.Parent = part

                            local billboard = Instance.new("BillboardGui")
                            billboard.Adornee = part
                            billboard.Size = UDim2.new(0, 100, 0, 30)
                            billboard.StudsOffset = Vector3.new(0, 2, 0)
                            billboard.AlwaysOnTop = true

                            local label = Instance.new("TextLabel")
                            label.Size = UDim2.new(1, 0, 1, 0)
                            label.BackgroundTransparency = 1
                            label.Text = obj.Name
                            label.TextColor3 = Color3.fromRGB(255, 255, 255)
                            label.TextStrokeTransparency = 0
                            label.Font = Enum.Font.GothamBold
                            label.TextSize = 12
                            label.Parent = billboard

                            billboard.Parent = part

                            espObjects[obj] = { box = highlight, billboard = billboard }
                        end
                    end
                end
            end

            for obj, esp in pairs(espObjects) do
                if not activeSet[obj] or not obj.Parent then
                    pcall(function()
                        if esp.box then esp.box:Destroy() end
                        if esp.billboard then esp.billboard:Destroy() end
                    end)
                    espObjects[obj] = nil
                end
            end
        else
            if next(espObjects) then
                clearESP()
            end
        end
    end
end)

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЙ ТА ПОЕТАПНОГО ЗАВАНТАЖЕННЯ
-- =======================================================
local function saveCurrentConfig()
    local configData = {
        FarmSpeed    = _G.FarmSpeed,
        ItemDistance = _G.ItemDistance,
        AutoRespawn  = _G.AutoRespawn,
        AntiAFK      = _G.AntiAFK,
        AutoSell     = _G.AutoSell,
        AutoEventCandy = _G.AutoEventCandy,
        AutoBuy      = _G.AutoBuy,
        ItemESP      = _G.ItemESP,
        ItemFarm     = _G.ItemFarm,
        StandaloneNoClip = _G.StandaloneNoClip,
        SelectedItems = _G.SelectedItems,
    }

    local ok, jsonStr = pcall(function()
        return HttpService:JSONEncode(configData)
    end)

    if ok and jsonStr and writefile then
        writefile(configFile, jsonStr)
        print("[UA Killer Hub | Config] Конфігурація успішно збережена у " .. configFile)
        return true
    else
        warn("[UA Killer Hub | Config] Помилка збереження конфігурації у JSON!")
        return false
    end
end

local function loadCurrentConfig()
    if not isfile or not isfile(configFile) or not readfile then
        return nil
    end

    local raw = readfile(configFile)
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if ok and type(decoded) == "table" then
        return decoded
    end

    warn("[UA Killer Hub | Config] Пошкоджений файл конфігурації!")
    return nil
end

local function runSteppedAutoLoad()
    print("[UA Killer Hub | AutoLoad] Початок поетапного застосування налаштувань...")
    local cfg = loadCurrentConfig()
    if not cfg then return end

    local AUTOLOAD_STEP = 0.08

    local function applyValue(key, val)
        if manuallyChanged[key] then return end

        if key == "FarmSpeed" and uiElementsRegistry["FarmSpeed_Slider"] then
            uiElementsRegistry["FarmSpeed_Slider"]:SetValue(val)
        elseif key == "ItemDistance" and uiElementsRegistry["ItemDistance_Slider"] then
            uiElementsRegistry["ItemDistance_Slider"]:SetValue(val)
        elseif key == "AutoRespawn" and uiElementsRegistry["AutoRespawn_Toggle"] then
            uiElementsRegistry["AutoRespawn_Toggle"]:SetValue(val)
        elseif key == "AntiAFK" and uiElementsRegistry["AntiAFK_Toggle"] then
            uiElementsRegistry["AntiAFK_Toggle"]:SetValue(val)
        elseif key == "StandaloneNoClip" and uiElementsRegistry["StandaloneNoClip_Toggle"] then
            uiElementsRegistry["StandaloneNoClip_Toggle"]:SetValue(val)
        elseif key == "ItemESP" and uiElementsRegistry["ItemESP_Toggle"] then
            uiElementsRegistry["ItemESP_Toggle"]:SetValue(val)
        elseif key == "AutoSell" and uiElementsRegistry["AutoSell_Toggle"] then
            uiElementsRegistry["AutoSell_Toggle"]:SetValue(val)
        elseif key == "AutoEventCandy" and uiElementsRegistry["AutoEventCandy_Toggle"] then
            uiElementsRegistry["AutoEventCandy_Toggle"]:SetValue(val)
        elseif key == "AutoBuy" and uiElementsRegistry["AutoBuy_Toggle"] then
            uiElementsRegistry["AutoBuy_Toggle"]:SetValue(val)
        elseif key == "ItemFarm" and uiElementsRegistry["ItemFarm_Toggle"] then
            uiElementsRegistry["ItemFarm_Toggle"]:SetValue(val)
        end
    end

    applyValue("FarmSpeed", cfg.FarmSpeed or defaultSettings.FarmSpeed)
    task.wait(AUTOLOAD_STEP)
    applyValue("ItemDistance", cfg.ItemDistance or defaultSettings.ItemDistance)
    task.wait(AUTOLOAD_STEP)
    applyValue("AutoRespawn", cfg.AutoRespawn ~= nil and cfg.AutoRespawn or defaultSettings.AutoRespawn)
    task.wait(AUTOLOAD_STEP)

    if cfg.SelectedItems and type(cfg.SelectedItems) == "table" then
        for itemName, state in pairs(cfg.SelectedItems) do
            _G.SelectedItems[itemName] = state
            local regKey = "ItemSelect_" .. itemName
            if uiElementsRegistry[regKey] then
                uiElementsRegistry[regKey]:SetValue(state)
            end
        end
    end
    task.wait(AUTOLOAD_STEP)

    if cfg.AntiAFK ~= nil then applyValue("AntiAFK", cfg.AntiAFK) task.wait(AUTOLOAD_STEP) end
    if cfg.StandaloneNoClip ~= nil then applyValue("StandaloneNoClip", cfg.StandaloneNoClip) task.wait(AUTOLOAD_STEP) end
    if cfg.ItemESP ~= nil then applyValue("ItemESP", cfg.ItemESP) task.wait(AUTOLOAD_STEP) end
    if cfg.AutoSell ~= nil then applyValue("AutoSell", cfg.AutoSell) task.wait(AUTOLOAD_STEP) end
    if cfg.AutoEventCandy ~= nil then applyValue("AutoEventCandy", cfg.AutoEventCandy) task.wait(AUTOLOAD_STEP) end
    if cfg.AutoBuy ~= nil then applyValue("AutoBuy", cfg.AutoBuy) task.wait(AUTOLOAD_STEP) end
    if cfg.ItemFarm ~= nil then applyValue("ItemFarm", cfg.ItemFarm) task.wait(AUTOLOAD_STEP) end

    print("[UA Killer Hub | AutoLoad] Поетапне відновлення конфігурації завершено.")
end

-- =======================================================
-- МОДУЛЬ ІНТЕРФЕЙСУ MONHUB GUI
-- =======================================================
local parentGui = (gethui and gethui()) or game:GetService("CoreGui"):FindFirstChild("RobloxGui") or player:WaitForChild("PlayerGui")
local existingHub = parentGui:FindFirstChild("UAKillerHub_MonHub")
if existingHub then existingHub:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UAKillerHub_MonHub"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = parentGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 520, 0, 400)
mainFrame.Position = UDim2.new(0.5, -260, 0.5, -200)
mainFrame.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(45, 49, 61)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

-- Верхня панель (TopBar)
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(0, 200, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "UA Killer Hub  <font color='#8B7CF6'>[YBA]</font>"
titleLabel.RichText = true
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = topBar

-- Кнопки керування вікном (Згорнути / Закрити)
local controlContainer = Instance.new("Frame")
controlContainer.Size = UDim2.new(0, 60, 1, 0)
controlContainer.Position = UDim2.new(1, -65, 0, 0)
controlContainer.BackgroundTransparency = 1
controlContainer.Parent = topBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 24, 0, 24)
closeButton.Position = UDim2.new(1, -26, 0.5, -12)
closeButton.BackgroundColor3 = Color3.fromRGB(45, 49, 61)
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.fromRGB(200, 200, 200)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 12
closeButton.BorderSizePixel = 0
closeButton.Parent = controlContainer

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeButton

closeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
end)

local minButton = Instance.new("TextButton")
minButton.Size = UDim2.new(0, 24, 0, 24)
minButton.Position = UDim2.new(1, -54, 0.5, -12)
minButton.BackgroundColor3 = Color3.fromRGB(45, 49, 61)
minButton.Text = "—"
minButton.TextColor3 = Color3.fromRGB(200, 200, 200)
minButton.Font = Enum.Font.GothamBold
minButton.TextSize = 12
minButton.BorderSizePixel = 0
minButton.Parent = controlContainer

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minButton

local isMinimized = false
minButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart), { Size = UDim2.new(0, 520, 0, 40) }):Play()
    else
        TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart), { Size = UDim2.new(0, 520, 0, 400) }):Play()
    end
end)

-- Перетягування вікна мишкою
local dragging, dragInput, dragStart, startPos
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

topBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Гаряча клавіша приховування (RightShift)
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then
        mainFrame.Visible = not mainFrame.Visible
    end
end)

-- Сайдбар меню та навігації
local sideBar = Instance.new("Frame")
sideBar.Name = "SideBar"
sideBar.Size = UDim2.new(0, 130, 1, -40)
sideBar.Position = UDim2.new(0, 0, 0, 40)
sideBar.BackgroundColor3 = Color3.fromRGB(27, 30, 38)
sideBar.BorderSizePixel = 0
sideBar.Parent = mainFrame

local tabListLayout = Instance.new("UIListLayout")
tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabListLayout.Padding = UDim.new(0, 4)
tabListLayout.Parent = sideBar

local sidePadding = Instance.new("UIPadding")
sidePadding.PaddingTop = UDim.new(0, 8)
sidePadding.PaddingLeft = UDim.new(0, 8)
sidePadding.PaddingRight = UDim.new(0, 8)
sidePadding.Parent = sideBar

-- Контейнер для вмісту сторінок
local contentArea = Instance.new("Frame")
contentArea.Name = "ContentArea"
contentArea.Size = UDim2.new(1, -130, 1, -40)
contentArea.Position = UDim2.new(0, 130, 0, 40)
contentArea.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
contentArea.BorderSizePixel = 0
contentArea.Parent = mainFrame

-- Поле пошуку функцій
local searchBar = Instance.new("TextBox")
searchBar.Name = "SearchBar"
searchBar.Size = UDim2.new(1, -20, 0, 30)
searchBar.Position = UDim2.new(0, 10, 0, 8)
searchBar.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
searchBar.PlaceholderText = "Пошук функцій..."
searchBar.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
searchBar.Text = ""
searchBar.TextColor3 = Color3.fromRGB(255, 255, 255)
searchBar.Font = Enum.Font.Gotham
searchBar.TextSize = 12
searchBar.BorderSizePixel = 0
searchBar.Parent = contentArea

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 6)
searchCorner.Parent = searchBar

local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 10)
searchPadding.Parent = searchBar

local pagesFolder = Instance.new("Folder")
pagesFolder.Name = "Pages"
pagesFolder.Parent = contentArea

local tabs = {}
local currentTab = nil

local function showNotification(title, content, duration)
    task.spawn(function()
        local notifyFrame = Instance.new("Frame")
        notifyFrame.Size = UDim2.new(0, 220, 0, 50)
        notifyFrame.Position = UDim2.new(1, -230, 1, -60)
        notifyFrame.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
        notifyFrame.BorderSizePixel = 0
        notifyFrame.Parent = screenGui

        local notifCorner = Instance.new("UICorner")
        notifCorner.CornerRadius = UDim.new(0, 8)
        notifCorner.Parent = notifyFrame

        local notifStroke = Instance.new("UIStroke")
        notifStroke.Color = Color3.fromRGB(139, 124, 246)
        notifStroke.Thickness = 1
        notifStroke.Parent = notifyFrame

        local notifTitle = Instance.new("TextLabel")
        notifTitle.Size = UDim2.new(1, -12, 0, 20)
        notifTitle.Position = UDim2.new(0, 8, 0, 4)
        notifTitle.BackgroundTransparency = 1
        notifTitle.Text = title
        notifTitle.TextColor3 = Color3.fromRGB(139, 124, 246)
        notifTitle.Font = Enum.Font.GothamBold
        notifTitle.TextSize = 12
        notifTitle.TextXAlignment = Enum.TextXAlignment.Left
        notifTitle.Parent = notifyFrame

        local notifDesc = Instance.new("TextLabel")
        notifDesc.Size = UDim2.new(1, -12, 0, 20)
        notifDesc.Position = UDim2.new(0, 8, 0, 24)
        notifDesc.BackgroundTransparency = 1
        notifDesc.Text = content
        notifDesc.TextColor3 = Color3.fromRGB(220, 220, 220)
        notifDesc.Font = Enum.Font.Gotham
        notifDesc.TextSize = 11
        notifDesc.TextXAlignment = Enum.TextXAlignment.Left
        notifDesc.Parent = notifyFrame

        task.wait(duration or 3)
        if notifyFrame and notifyFrame.Parent then
            TweenService:Create(notifyFrame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
            task.wait(0.3)
            notifyFrame:Destroy()
        end
    end)
end

local function switchTab(tabName)
    for name, data in pairs(tabs) do
        local isActive = (name == tabName)
        data.Page.Visible = isActive

        if isActive then
            TweenService:Create(data.Button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(139, 124, 246),
                TextColor3 = Color3.fromRGB(255, 255, 255),
            }):Play()
            currentTab = tabName
        else
            TweenService:Create(data.Button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(31, 34, 43),
                TextColor3 = Color3.fromRGB(180, 180, 190),
            }):Play()
        end
    end
end

local function createTab(tabName, iconText)
    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = tabName .. "_Tab"
    tabBtn.Size = UDim2.new(1, 0, 0, 32)
    tabBtn.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
    tabBtn.Text = (iconText or "•") .. "  " .. tabName
    tabBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    tabBtn.Font = Enum.Font.GothamBold
    tabBtn.TextSize = 12
    tabBtn.TextXAlignment = Enum.TextXAlignment.Left
    tabBtn.BorderSizePixel = 0
    tabBtn.Parent = sideBar

    local btnPad = Instance.new("UIPadding")
    btnPad.PaddingLeft = UDim.new(0, 10)
    btnPad.Parent = tabBtn

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = tabBtn

    local page = Instance.new("ScrollingFrame")
    page.Name = tabName .. "_Page"
    page.Size = UDim2.new(1, -20, 1, -50)
    page.Position = UDim2.new(0, 10, 0, 44)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(139, 124, 246)
    page.Visible = false
    page.Parent = pagesFolder

    local pageLayout = Instance.new("UIListLayout")
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Padding = UDim.new(0, 6)
    pageLayout.Parent = page

    pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, pageLayout.AbsoluteContentSize.Y + 10)
    end)

    tabs[tabName] = {
        Button = tabBtn,
        Page = page,
    }

    tabBtn.MouseButton1Click:Connect(function()
        switchTab(tabName)
    end)

    return page
end

-- Фільтрація елементів через рядок пошуку
searchBar:GetPropertyChangedSignal("Text"):Connect(function()
    local query = searchBar.Text:lower()
    if not currentTab or not tabs[currentTab] then return end

    local activePage = tabs[currentTab].Page
    for _, item in ipairs(activePage:GetChildren()) do
        if item:IsA("Frame") and item:FindFirstChild("ItemName") then
            local itemName = item.ItemName.Text:lower()
            if query == "" or itemName:find(query) then
                item.Visible = true
            else
                item.Visible = false
            end
        end
    end
end)

-- Компоненти інтерфейсу (Секції, Перемикачі, Слайдери, Кнопки)
local function createSection(page, tabName, text)
    local secFrame = Instance.new("Frame")
    secFrame.Name = "Section_" .. text
    secFrame.Size = UDim2.new(1, 0, 0, 24)
    secFrame.BackgroundTransparency = 1
    secFrame.Parent = page

    local secLabel = Instance.new("TextLabel")
    secLabel.Name = "ItemName"
    secLabel.Size = UDim2.new(1, 0, 1, 0)
    secLabel.BackgroundTransparency = 1
    secLabel.Text = "— " .. text
    secLabel.TextColor3 = Color3.fromRGB(139, 124, 246)
    secLabel.Font = Enum.Font.GothamBold
    secLabel.TextSize = 11
    secLabel.TextXAlignment = Enum.TextXAlignment.Left
    secLabel.Parent = secFrame
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local card = Instance.new("Frame")
    card.Name = "Toggle_" .. text
    card.Size = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
    card.BorderSizePixel = 0
    card.Parent = page

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local label = Instance.new("TextLabel")
    label.Name = "ItemName"
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(230, 230, 230)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local switchBtn = Instance.new("TextButton")
    switchBtn.Size = UDim2.new(0, 40, 0, 20)
    switchBtn.Position = UDim2.new(1, -48, 0.5, -10)
    switchBtn.BackgroundColor3 = defaultVal and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(50, 54, 66)
    switchBtn.Text = ""
    switchBtn.BorderSizePixel = 0
    switchBtn.Parent = card

    local switchCorner = Instance.new("UICorner")
    switchCorner.CornerRadius = UDim.new(1, 0)
    switchCorner.Parent = switchBtn

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = defaultVal and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = switchBtn

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local state = defaultVal or false

    local function updateVisuals()
        if state then
            TweenService:Create(switchBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), { Position = UDim2.new(1, -18, 0.5, -8) }):Play()
        else
            TweenService:Create(switchBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(50, 54, 66) }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2), { Position = UDim2.new(0, 2, 0.5, -8) }):Play()
        end
    end

    switchBtn.MouseButton1Click:Connect(function()
        state = not state
        updateVisuals()
        if callback then
            task.spawn(callback, state)
        end
    end)

    return {
        SetValue = function(_, val)
            state = val
            updateVisuals()
            if callback then
                task.spawn(callback, state)
            end
        end,
    }
end

local function createSlider(page, tabName, text, min, max, defaultVal, callback)
    local card = Instance.new("Frame")
    card.Name = "Slider_" .. text
    card.Size = UDim2.new(1, 0, 0, 50)
    card.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
    card.BorderSizePixel = 0
    card.Parent = page

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local label = Instance.new("TextLabel")
    label.Name = "ItemName"
    label.Size = UDim2.new(1, -80, 0, 24)
    label.Position = UDim2.new(0, 12, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(230, 230, 230)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0, 60, 0, 24)
    valLabel.Position = UDim2.new(1, -70, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = tostring(defaultVal)
    valLabel.TextColor3 = Color3.fromRGB(139, 124, 246)
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextSize = 12
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent = card

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 6)
    track.Position = UDim2.new(0, 12, 0, 34)
    track.BackgroundColor3 = Color3.fromRGB(50, 54, 66)
    track.BorderSizePixel = 0
    track.Parent = card

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    local initRatio = math.clamp((defaultVal - min) / (max - min), 0, 1)
    fill.Size = UDim2.new(initRatio, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local draggingSlider = false

    local function updateFromInput(input)
        local posX = input.Position.X - track.AbsolutePosition.X
        local ratio = math.clamp(posX / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * ratio)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        valLabel.Text = tostring(val)
        if callback then
            task.spawn(callback, val)
        end
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

    return {
        SetValue = function(_, val)
            local clamped = math.clamp(val, min, max)
            local ratio = (clamped - min) / (max - min)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            valLabel.Text = tostring(clamped)
            if callback then
                task.spawn(callback, clamped)
            end
        end,
    }
end

local function createButton(page, tabName, text, callback)
    local card = Instance.new("Frame")
    card.Name = "Button_" .. text
    card.Size = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
    card.BorderSizePixel = 0
    card.Parent = page

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local btn = Instance.new("TextButton")
    btn.Name = "ItemName"
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(230, 230, 230)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Parent = card

    btn.MouseButton1Click:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        task.wait(0.1)
        TweenService:Create(card, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(31, 34, 43) }):Play()
        if callback then
            task.spawn(callback)
        end
    end)
end

-- =======================================================
-- СТВОРЕННЯ СТОРІНОК ТА ПРИВ'ЯЗКА ФУНКЦІЙ
-- =======================================================
local mainPage = createTab("Головна",  "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин",  "🛒")
local miscPage = createTab("Інше",     "⚙")

-- 1. СТОРІНКА ГОЛОВНА
createSection(mainPage, "Головна", "Управління конфігурацією")

local autoLoadToggle = createToggle(mainPage, "Головна", "Автозавантаження при старті", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    if writefile then
        writefile(autoLoadFile, value and "true" or "false")
    end
    showNotification("UA Killer Hub", "Автозавантаження: " .. (value and "Увімкнено" or "Вимкнено"), 2)
end)
uiElementsRegistry["AutoLoad_Toggle"] = autoLoadToggle

createButton(mainPage, "Головна", "Зберегти налаштування", function()
    if saveCurrentConfig() then
        showNotification("UA Killer Hub", "Конфігурацію збережено успішно!", 3)
    else
        showNotification("UA Killer Hub", "Помилка збереження конфігу!", 3)
    end
end)

createButton(mainPage, "Головна", "Завантажити збережені налаштування", function()
    runSteppedAutoLoad()
    showNotification("UA Killer Hub", "Налаштування відновлено!", 3)
end)

-- 2. СТОРІНКА АВТОФАРМ
createSection(farmPage, "Автофарм", "Параметри польоту та збору")

local statusCard = Instance.new("Frame")
statusCard.Size = UDim2.new(1, 0, 0, 32)
statusCard.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
statusCard.BorderSizePixel = 0
statusCard.Parent = farmPage

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 6)
statusCorner.Parent = statusCard

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 1, 0)
statusLabel.Position = UDim2.new(0, 10, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Статус: Очікування..."
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = statusCard

task.spawn(function()
    while true do
        task.wait(0.2)
        statusLabel.Text = "Статус: " .. farmStatusText
    end
end)

local speedSlider = createSlider(farmPage, "Автофарм", "Швидкість польоту", 20, 120, _G.FarmSpeed, function(val)
    _G.FarmSpeed = val
end)
uiElementsRegistry["FarmSpeed_Slider"] = speedSlider

local distSlider = createSlider(farmPage, "Автофарм", "Максимальна дистанція", 500, 10000, _G.ItemDistance, function(val)
    _G.ItemDistance = val
end)
uiElementsRegistry["ItemDistance_Slider"] = distSlider

local itemEspToggle = createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    markManuallyChanged("ItemESP")
    _G.ItemESP = val
end)
uiElementsRegistry["ItemESP_Toggle"] = itemEspToggle

local itemFarmToggle = createToggle(farmPage, "Автофарм", "Увімкнути автофарм", _G.ItemFarm, function(value)
    markManuallyChanged("ItemFarm")
    _G.ItemFarm = value
    if value then
        farmSessionId = farmSessionId + 1
        farmThreadActive = true
        runItemFarmLoop(farmSessionId)
    else
        farmSessionId = farmSessionId + 1
        cleanupFlight()
    end
end)
uiElementsRegistry["ItemFarm_Toggle"] = itemFarmToggle

createSection(farmPage, "Автофарм", "Вибір предметів для збору")

local itemList = {
    "Mysterious Arrow", "Rokakaka", "Pure Rokakaka", "Lucky Arrow",
    "Rib Cage of The Saint's Corpse", "Left Arm of The Saint's Corpse",
    "Heart of The Saint's Corpse", "Pelvis of The Saint's Corpse",
    "Deo's Diary", "Steel Ball", "Quinton's Glove", "Ancient Scroll",
    "Clackers", "Stone Mask", "Diamond", "Gold Coin",
    "Candy", "Candy Corn",
}

for _, itemName in ipairs(itemList) do
    if _G.SelectedItems[itemName] == nil then
        _G.SelectedItems[itemName] = true
    end

    local ctrl = createToggle(farmPage, "Автофарм", itemName, _G.SelectedItems[itemName], function(val)
        _G.SelectedItems[itemName] = val
    end)
    uiElementsRegistry["ItemSelect_" .. itemName] = ctrl
end

-- 3. СТОРІНКА МАГАЗИН
createSection(shopPage, "Магазин", "Торговець та Івенти")

local autoSellToggle = createToggle(shopPage, "Магазин", "Автопродаж (крім Lucky Arrow)", _G.AutoSell, function(value)
    markManuallyChanged("AutoSell")
    _G.AutoSell = value
    if value then
        syncSellQueue()
    else
        table.clear(sellQueue)
        closeMerchantDialogue()
    end
end)
uiElementsRegistry["AutoSell_Toggle"] = autoSellToggle

local autoCandyToggle = createToggle(shopPage, "Магазин", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    markManuallyChanged("AutoEventCandy")
    _G.AutoEventCandy = value
end)
uiElementsRegistry["AutoEventCandy_Toggle"] = autoCandyToggle

local autoBuyToggle = createToggle(shopPage, "Магазин", "Автокупівля (Lucky Arrow)", _G.AutoBuy, function(value)
    markManuallyChanged("AutoBuy")
    _G.AutoBuy = value
    if value then
        task.spawn(function()
            while _G.AutoBuy do
                local char = player.Character
                local remote = char and char:FindFirstChild("RemoteEvent")
                if remote then
                    remote:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
                end
                task.wait(2.5 + math.random() * 1.5)
            end
        end)
    end
end)
uiElementsRegistry["AutoBuy_Toggle"] = autoBuyToggle

-- 4. СТОРІНКА ІНШЕ
createSection(miscPage, "Інше", "Додаткові функції")

local antiAfkToggle = createToggle(miscPage, "Інше", "Anti-AFK", _G.AntiAFK, function(value)
    markManuallyChanged("AntiAFK")
    _G.AntiAFK = value
    if antiAfkConnection then
        antiAfkConnection:Disconnect()
        antiAfkConnection = nil
    end
    if value then
        antiAfkConnection = player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)
uiElementsRegistry["AntiAFK_Toggle"] = antiAfkToggle

local noclipToggle = createToggle(miscPage, "Інше", "NoClip (окремо від фарму)", _G.StandaloneNoClip, function(value)
    markManuallyChanged("StandaloneNoClip")
    _G.StandaloneNoClip = value
    if value then
        ensureNoClip()
    elseif not _G.ItemFarm and noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end)
uiElementsRegistry["StandaloneNoClip_Toggle"] = noclipToggle

local autoRespawnToggle = createToggle(miscPage, "Інше", "Авто-респawn при смерті", _G.AutoRespawn, function(value)
    markManuallyChanged("AutoRespawn")
    _G.AutoRespawn = value
end)
uiElementsRegistry["AutoRespawn_Toggle"] = autoRespawnToggle

createButton(miscPage, "Інше", "Очистити заблоковані координати", function()
    table.clear(bannedCoordinates)
    lastCacheRefresh = 0
    showNotification("UA Killer Hub", "Чорний список координат очищено", 3)
end)

-- =======================================================
-- ВІДКРИТТЯ ІНТЕРФЕЙСУ
-- =======================================================
switchTab("Головна")

print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

if shouldAutoLoad then
    task.spawn(runSteppedAutoLoad)
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
