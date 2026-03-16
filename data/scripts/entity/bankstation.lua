package.path = package.path .. ";data/scripts/lib/?.lua;"
package.path = package.path .. ";data/scripts/?.lua;"

include("stringutility")
include("randomext")
include("utility")
include("randomext")
include("faction")
include("callable")

local Dialog = include("dialogutility")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace BankStation
BankStation = {}

BankStation.upgradeLevel = 1
-- These are stored in n* millions
local upgradePrices = {1, 10, 25, 40, 100, 200}
local maxBalances = {1, 11, 36, 76, 176, 376}

BankStation.storedMoney = 0;

local interestPercent = 0.02

local window
local lblBalance
local txtDeposit
local txtWithdraw

local lblUpgrade
local lblUpgradePrice
local btnUpgrade

-- if this function returns false, the script will not be listed in the interaction window on the client,
-- even though its UI may be registered
function BankStation.formatNumber(number)
    local formatted = tostring(math.floor(tonumber(number) or 0))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end

function BankStation.interactionPossible(playerIndex, option)
    if Entity().factionIndex == Player().craftFaction.index then
        if Player().craftFaction.isAlliance then
            if Player().craftFaction:hasPrivilege(playerIndex, AlliancePrivilege.SpendResources) and
                Player().craftFaction:hasPrivilege(playerIndex, AlliancePrivilege.ManageStations) then
                return true
            else
                return false
            end
        else
            return true
        end
    end
end

function BankStation.secure()
    local data = {}
    data.storedMoney = BankStation.storedMoney or 0
    data.upgradeLevel = BankStation.upgradeLevel or 1
    data.timeUntilNextPayout = BankStation.timeUntilNextPayout or 300
    return data
end

function BankStation.restore(data)
    BankStation.storedMoney = data.storedMoney or 0
    BankStation.upgradeLevel = data.upgradeLevel or 1
    BankStation.timeUntilNextPayout = data.timeUntilNextPayout or 300
end

-- Ensure the UI ticks every 1 second
function BankStation.getUpdateInterval()
    return 1
end

function BankStation.initialize()
    local station = Entity()
    if station.title == "" then
        station.title = Faction().name .. "'s Bank" % _t
    end

    if onClient() and EntityIcon().icon == "" then
        EntityIcon().icon = "data/textures/icons/pixel/credits.png"
        InteractionText().text = Dialog.generateStationInteractionText(Entity(), random())
    end

    -- Only add our script to the server
    if onServer() then
        -- Grabt the current Entity (Station)
        local station = Entity()
        -- If the station is non-NPC owned, then we want to trigger our script
        -- This helps ensure our script isn't running to sectors where it won't be doing anything.
        if station.playerOwned or station.allianceOwned then
            -- Sector():addScriptOnce("sector/background/bankrobbers.lua")
            Sector():removeScript("sector/background/bankrobbers.lua")
            -- Register the onDestroyed function defined below, so that it is triggered when the entity is destroyed
            station:registerCallback("onDestroyed", "onDestroyed")
            station:registerCallback("onJump", "onJump")
            station:registerCallback("onUndockedFromEntity", "onUndockedFromEntity")
        end
    end
end

function BankStation.initializationFinished()
    -- use the initilizationFinished() function on the client since in initialize() we may not be able to access Sector scripts on the client
    if onClient() then
        local ok, r = Sector():invokeFunction("radiochatter", "addSpecificLines", Entity().id.string,
            {"Your Credits are safe with us!" % _t, "Prepare for your future, start investing today." % _t,
             "Do you have tons of cash but nothing to spend it on yet? Open an account today! We'll keep them safe for you." %
                _t, "I sure hope no one tries to rob us today, I hate pirates." % _t,
             "Our new vault security system is impenetrable, so don't even try to rob us." % _t,
             "Trust us, storing a bunch of credits with us has NO downsides." % _t})
    end
end

-- this function gets called on creation of the entity the script is attached to, on client only
-- AFTER initialize above
-- create all required UI elements for the client side
local lblCapacityDetails
local progressBar
local lblInterestInfo
local lblNextPayout

function BankStation.initUI()
    local res = getResolution()
    local size = vec2(780, 270) -- Taller to fit the progress bar and timer!

    local menu = ScriptUI()
    window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Banking Options" % _t
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Banking Options" % _t, 10);

    -- Use the Lister from BSE for clean vertical stacking
    local lister = UIVerticalLister(Rect(vec2(15, 15), size - vec2(15, 15)), 10, 10)

    -- ROW 1: Capacity details
    local capRect = lister:nextRect(20)
    lblCapacityDetails = window:createLabel(capRect, "0 / 0 Cr", 16)
    lblCapacityDetails:setCenterAligned()

    -- ROW 2: Progress Bar
    local barRect = lister:nextRect(20)
    window:createFrame(barRect)
    progressBar = window:createProgressBar(barRect, ColorRGB(0.2, 0.6, 1.0))

    -- ROW 3: Interest Info
    local infoRect = lister:nextRect(20)
    lblInterestInfo = window:createLabel(infoRect, "Interest Rate: 2% every 5 Minutes", 14)
    lblInterestInfo:setCenterAligned()
    lblInterestInfo.color = ColorRGB(0.5, 0.8, 1.0)

    lister:nextRect(10) -- Spacer

    -- ROW 4: 3-Column Actions
    local options_vSplit = UIVerticalMultiSplitter(lister:nextRect(60), 20, 0, 3)
    
    -- Column 1: Deposit
    local dep_split = UIHorizontalSplitter(options_vSplit:partition(0), 10, 0, 0.5)
    window:createFrame(dep_split.top) 
    txtDeposit = window:createTextBox(dep_split.top, "onDepositBoxChange")
    txtDeposit.text = "0"
    -- THE FIX: Added the comma here!
    txtDeposit.allowedCharacters = "0123456789,"
    txtDeposit.clearOnClick = 1
    local btnDeposit = window:createButton(dep_split.bottom, "Deposit (Store)", "onBtnDepositClick")
    btnDeposit.maxTextSize = 14

    -- Column 2: Withdraw
    local wit_split = UIHorizontalSplitter(options_vSplit:partition(1), 10, 0, 0.5)
    window:createFrame(wit_split.top) 
    txtWithdraw = window:createTextBox(wit_split.top, "onWithdrawBoxChange")
    txtWithdraw.text = "0"
    -- THE FIX: Added the comma here!
    txtWithdraw.allowedCharacters = "0123456789,"
    txtWithdraw.clearOnClick = 1
    local btnWithdraw = window:createButton(wit_split.bottom, "Withdraw (Take)", "onBtnWithdrawClick")
    btnWithdraw.maxTextSize = 14

    -- Column 3: Upgrade
    local upg_split = UIHorizontalSplitter(options_vSplit:partition(2), 10, 0, 0.45)
    local upg_lister = UIVerticalLister(upg_split.top, 2, 0)
    
    lblUpgradePrice = window:createLabel(upg_lister:nextRect(14), "Cost: --", 12)
    lblUpgradePrice:setCenterAligned()
    
    lblUpgradeEffect = window:createLabel(upg_lister:nextRect(14), "Cap: --", 12)
    lblUpgradeEffect:setCenterAligned()
    lblUpgradeEffect.color = ColorRGB(0.5, 0.8, 1.0) 
    
    btnUpgrade = window:createButton(upg_split.bottom, "Upgrade Vault", "onUpgradeButtonPressed")
    btnUpgrade.maxTextSize = 14

    lister:nextRect(10) -- Spacer

    -- ROW 5: Timer Footer
    local footerRect = lister:nextRect(20)
    lblNextPayout = window:createLabel(footerRect, "Next Payout: 05:00", 14)
    lblNextPayout:setCenterAligned()
end

function BankStation.onShowWindow(isSync)
    if isSync ~= false then
        invokeServerFunction("sync")
    end

    local maxMoney = maxBalances[BankStation.upgradeLevel] * 1000000
    local current = math.floor(BankStation.storedMoney)

    if lblCapacityDetails then
        lblCapacityDetails.caption = "Current Balance: " .. createMonetaryString(current) .. " / " .. createMonetaryString(maxMoney) .. " Cr"
    end

    if progressBar then
        progressBar.progress = math.min(1.0, current / maxMoney)
        progressBar.color = (progressBar.progress > 0.9) and ColorRGB(1, 0.2, 0.2) or ColorRGB(0.2, 0.6, 1)
    end

    if lblUpgradePrice and lblUpgradeEffect then
        if BankStation.upgradeLevel < #upgradePrices then
            local nextPrice = upgradePrices[BankStation.upgradeLevel + 1] * 1000000
            local nextCap = maxBalances[BankStation.upgradeLevel + 1] * 1000000
            
            lblUpgradePrice.caption = "Cost: " .. createMonetaryString(nextPrice) .. " Cr"
            lblUpgradeEffect.caption = "New Cap: " .. createMonetaryString(nextCap) .. " Cr"
            
            lblUpgradePrice:show()
            lblUpgradeEffect:show()
            btnUpgrade:show()
            
            local tooltip = "Level " .. (BankStation.upgradeLevel + 1) .. " Benefits:\n- Max Capacity: " .. createMonetaryString(nextCap) .. " Cr"
            btnUpgrade.tooltip = tooltip
        else
            lblUpgradePrice.caption = "Max Level"
            lblUpgradeEffect.caption = "Reached"
            btnUpgrade:hide()
        end
    end
end

function BankStation.update(timeStep)
    if onServer() then
        BankStation.timeUntilNextPayout = (BankStation.timeUntilNextPayout or 300) - timeStep

        if BankStation.timeUntilNextPayout <= 0 then
            BankStation.timeUntilNextPayout = 300
            
            if BankStation.storedMoney > 0 then
                local interestPercent = 0.02
                local interest = math.floor(BankStation.storedMoney * interestPercent)
                BankStation.storedMoney = BankStation.storedMoney + interest

                local maxMoney = maxBalances[BankStation.upgradeLevel] * 1000000
                if BankStation.storedMoney >= maxMoney then
                    local overflow = BankStation.storedMoney - maxMoney
                    BankStation.storedMoney = maxMoney
                    if overflow > 0 then
                        Faction():receive("Received %1% Credits: Bank Interest Overflow."%_T, overflow)
                    end
                end

                Faction():sendChatMessage(Entity(), ChatMessageType.Chatter, "Earned %1% credits in interest."%_T, createMonetaryString(interest))
            end
            
            broadcastInvokeClientFunction("sync", BankStation.secure())
        end

    elseif onClient() then
        BankStation.timeUntilNextPayout = (BankStation.timeUntilNextPayout or 300) - timeStep
        if BankStation.timeUntilNextPayout < 0 then BankStation.timeUntilNextPayout = 0 end

        if window and window.visible then
            if lblNextPayout then
                local mins = math.floor(BankStation.timeUntilNextPayout / 60)
                local secs = math.floor(BankStation.timeUntilNextPayout % 60)
                lblNextPayout.caption = string.format("Next Payout: %02d:%02d", mins, secs)
            end
        end
    end
end

-- Server/Client Helper
function BankStation.sync(data)
    if onClient() then
        if not data then
            invokeServerFunction("sync")
        else
            BankStation.restore(data)
            if window then
                BankStation.onShowWindow(true)
            end
        end
    else
        local data = BankStation.secure()
        Entity():setValue("AccountValue", data.storedMoney)
        invokeClientFunction(Player(callingPlayer), "sync", data)
    end
end
callable(BankStation, "sync")

-- If this Resource Depot is destroyed, and it was the last player owned one in system, clean up our script.
function BankStation.onDestroyed(index, lastDamageInflictor)
    local destroyed_station = Sector():getEntity(index)
    local OtherBanks = false

    -- Get Depot Entities By Script
    local Banks = {Sector():getEntitiesByScript("entity/bankstation.lua")}
    for _, station in pairs(Banks) do

        -- If any of the Depots in this sector are still player/allinace owned then keep the script, by setting this to true.
        -- Note that the current semi-deleted entity is also techincally still in the sector so filter that out.
        if station.id.string ~= destroyed_station.id.string and (station.playerOwned or station.allianceOwned) then
            OtherBanks = true
        end
    end

    -- Clean up the script only if there are no more player owned stations in sector
    if OtherBanks == false then
        -- Sector():removeScript("sector/background/bankrobbers.lua")
    end
end

-- UI Event Functions
function BankStation.onDepositBoxChange(box)
    local rawText = string.gsub(box.text, ",", "") -- Strip commas for math
    local enteredNumber = tonumber(rawText) or 0
    
    local maxMoney = maxBalances[BankStation.upgradeLevel] * 1000000
    if (BankStation.storedMoney + enteredNumber) >= maxMoney then
        enteredNumber = maxMoney - BankStation.storedMoney
    end
    
    box.text = BankStation.formatNumber(enteredNumber) -- Put commas back!
end

function BankStation.onWithdrawBoxChange(box)
    local rawText = string.gsub(box.text, ",", "")
    local enteredNumber = tonumber(rawText) or 0
    
    if enteredNumber >= BankStation.storedMoney then
        enteredNumber = BankStation.storedMoney
    end
    
    box.text = BankStation.formatNumber(enteredNumber)
end

function BankStation.onBtnDepositClick(depositAmount)
    if onClient() then
        local rawText = string.gsub(txtDeposit.text, ",", "")
        depositAmount = tonumber(rawText) or 0
        invokeServerFunction("onBtnDepositClick", depositAmount)
        return
    end

    local buyer, _, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources,
        AlliancePrivilege.ManageStations)
    if not buyer then
        return
    end

    local maxMoney = maxBalances[BankStation.upgradeLevel] * 1000000
    if (BankStation.storedMoney + depositAmount) > maxMoney then
        player:sendChatMessage("", ChatMessageType.Error, "This bank can only hold %1% credits" % _t,
            createMonetaryString(maxMoney))
        return
    end

    local canPay, msg, args = buyer:canPay(depositAmount)
    if not canPay then -- if there was an error, print it
        player:sendChatMessage(Entity(), 1, msg, unpack(args))
        return
    end

    -- Take the money from the player
    buyer:pay("Deposited %1% Credits: Bank Deposit." % _T, depositAmount)

    -- Add the money to the bank
    BankStation.storedMoney = BankStation.storedMoney + depositAmount

    BankStation:sync()
end
callable(BankStation, "onBtnDepositClick")

function BankStation.onBtnWithdrawClick(withdrawAmount)
    if onClient() then
        local rawText = string.gsub(txtWithdraw.text, ",", "")
        withdrawAmount = tonumber(rawText) or 0
        invokeServerFunction("onBtnWithdrawClick", withdrawAmount)
        return
    end

    local buyer, _, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources,
        AlliancePrivilege.ManageStations)
    if not buyer then
        return
    end

    withdrawAmount = math.min(withdrawAmount, BankStation.storedMoney)

    -- Take the money from the player
    buyer:receive("Received %1% Credits: Bank Withdrawal." % _T, withdrawAmount)

    -- Add the money to the bank
    BankStation.storedMoney = BankStation.storedMoney - withdrawAmount

    BankStation:sync()
end
callable(BankStation, "onBtnWithdrawClick")

function BankStation.onUpgradeButtonPressed()
    if onClient() then
        invokeServerFunction("onUpgradeButtonPressed")
        return
    end

    local buyer, _, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources, AlliancePrivilege.ManageStations)
    if not buyer then return end

    if BankStation.upgradeLevel >= #upgradePrices then
        player:sendChatMessage("", ChatMessageType.Error, "This station cannot be upgraded further." % _t)
        return
    end

    local price = upgradePrices[BankStation.upgradeLevel + 1] * 1000000
    local canPay, msg, args = buyer:canPay(price)
    
    if not canPay then
        player:sendChatMessage(Entity(), 1, msg, unpack(args))
        return
    end

    buyer:pay("Vault Upgrade: %1% Credits"%_T, price)
    BankStation.upgradeLevel = BankStation.upgradeLevel + 1
    BankStation:sync()
end
callable(BankStation, "onUpgradeButtonPressed")

function BankStation.onCustomPayChange(box)
    local rawText = string.gsub(box.text, ",", "")
    local entered = tonumber(rawText) or 0
    
    if selectedActiveLoanIndex then
        local loan = BankStation.activeLoans[selectedActiveLoanIndex]
        if entered > loan.repayment then entered = loan.repayment end
    end
    
    box.text = BankStation.formatNumber(entered)
end

-- This is called right before the Entity leaves a sector due to a jump
function BankStation.onJump(shipIndex, x, y)
    local destroyed_station = Sector():getEntity(shipIndex)
    local OtherPlayerOwnedDepots = false

    -- Get BankStation Entities By Script
    local BankStations = {Sector():getEntitiesByScript("entity/bankstation.lua")}
    for _, station in pairs(BankStations) do

        -- If any of the Depots in this sector are still player/allinace owned then keep the script, by setting this to true.
        -- Note that the current semi-deleted entity is also techincally still in the sector so filter that out.
        if station.id.string ~= destroyed_station.id.string and (station.playerOwned or station.allianceOwned) then
            OtherPlayerOwnedDepots = true
        end
    end

    -- Clean up the script only if there are no more player owned stations in sector
    if OtherPlayerOwnedDepots == false then
        -- Sector():removeScript("sector/background/bankrobbers.lua")
    end
end

-- This is called when a ship carrying this stations undocks
function BankStation.onUndockedFromEntity(dockeeId, dockerId)
    -- Add our script to the new sector
    if onServer() then
        -- Grabt the current Entity (Station)
        local station = Entity()
        -- If the station is non-NPC owned, then we want to trigger our script
        -- This helps ensure our script isn't running to sectors where it won't be doing anything.
        if station.playerOwned or station.allianceOwned then
            -- Sector():addScriptOnce("sector/background/bankrobbers.lua")
        end
    end
end
