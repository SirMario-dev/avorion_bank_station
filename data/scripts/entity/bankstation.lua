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

function BankStation.restore(data)
    BankStation.storedMoney = data.storedMoney or 0
    BankStation.upgradeLevel = data.upgradeLevel or 1
end

function BankStation.secure()
    local data = {}
    data.storedMoney = BankStation.storedMoney or 0
    data.upgradeLevel = BankStation.upgradeLevel or 1
    return data
end

function BankStation.getUpdateInterval()
    return 5 * 60
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
function BankStation.initUI()
    local res = getResolution()
    local size = vec2(780, 580)

    local menu = ScriptUI()
    window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Banking Options" % _t
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Banking Options" % _t, 10);

    local hsplit = UIHorizontalSplitter(Rect(window.size), 10, 10, 0.2)

    -- Top Split -- Show Current Stored Amount
    local bal_vSplit = UIVerticalMultiSplitter(hsplit.top, 10, 0, 2)
    local bal_hSplit = UIHorizontalSplitter(bal_vSplit:partition(1), 10, 10, 0.5)

    window:createLabel(bal_hSplit.top, "Account Balance", 18)
    lblBalance = window:createLabel(bal_hSplit.bottom, createMonetaryString(BankStation.storedMoney) .. " Cr" % _t, 14)
    lblBalance:setRightAligned()

    -- Bottom Split -- Show Deposit/Withdrawl Options
    local options_vSplit = UIVerticalMultiSplitter(hsplit.bottom, 2, 0, 3)
    local options_hSplit1 = UIHorizontalMultiSplitter(options_vSplit:partition(1), 2, 2, 2)
    local options_hSplit2 = UIHorizontalMultiSplitter(options_vSplit:partition(2), 2, 2, 2)

    -- Deposit Text Box Background Frame
    local frame = window:createFrame(options_hSplit1:partition(0))
    frame.width = 180
    frame.height = 30

    -- Deposit Text Box
    txtDeposit = window:createTextBox(options_hSplit1:partition(0), "onDepositBoxChange")
    txtDeposit.width = 180
    txtDeposit.height = 30
    txtDeposit.text = "0"
    txtDeposit.allowedCharacters = "0123456789"
    txtDeposit.clearOnClick = 1

    -- Deposit Button
    local btnDeposit = window:createButton(options_hSplit2:partition(0), "Deposit (Store)", "onBtnDepositClick")
    btnDeposit.maxTextSize = 14
    btnDeposit.width = 150
    btnDeposit.height = 30

    -- Deposit Text Box Background Frame
    local frame = window:createFrame(options_hSplit1:partition(1))
    frame.width = 180
    frame.height = 30

    -- Deposit Text Box
    txtWithdraw = window:createTextBox(options_hSplit1:partition(1), "onWithdrawBoxChange")
    txtWithdraw.width = 180
    txtWithdraw.height = 30
    txtWithdraw.text = "0"
    txtWithdraw.allowedCharacters = "0123456789"
    txtWithdraw.clearOnClick = 1

    -- Deposit Button
    local btnWithdraw = window:createButton(options_hSplit2:partition(1), "Withdraw (Take)", "onBtnWithdrawClick")
    btnWithdraw.maxTextSize = 14
    btnWithdraw.width = 150
    btnWithdraw.height = 30

    -- Upgrade Button
    local upgradeHsplit = UIHorizontalMultiSplitter(options_hSplit1:partition(2), 0, 5, 3)
    lblUpgrade = window:createLabel(upgradeHsplit:partition(0), "Upgrade Price:", 14)
    lblUpgrade:setCenterAligned()

    lblUpgradePrice = window:createLabel(upgradeHsplit:partition(1), "${price} Cr" % _t % {
        price = createMonetaryString(upgradePrices[BankStation.upgradeLevel + 1] * 1000000)
    }, 14)
    lblUpgradePrice:setRightAligned()

    local upgradebtnHsplit = UIHorizontalMultiSplitter(options_hSplit2:partition(2), 0, 0, 3)
    btnUpgrade = window:createButton(upgradebtnHsplit:partition(1), "Upgrade" % _t, "onUpgradeButtonPressed")
    btnUpgrade.maxTextSize = 14
    btnUpgrade.width = 150
    btnUpgrade.height = 30

end

function BankStation.onShowWindow(isSync)
    -- On Window Shown
    if isSync ~= nil then
        invokeServerFunction("sync")
    end

    if lblBalance then
        lblBalance.caption = createMonetaryString(BankStation.storedMoney) .. " Cr" % _t
    end

    if lblUpgradePrice and BankStation.upgradeLevel < 6 then
        lblUpgradePrice.caption = "${price} Cr" % _t % {
            price = createMonetaryString(upgradePrices[BankStation.upgradeLevel + 1] * 1000000)
        }
    else
        lblUpgrade:hide()
        lblUpgradePrice:hide()
        btnUpgrade:hide()
    end

end

function BankStation.update(timeStep)
    if onServer() then
        if BankStation.storedMoney > 0 then
            local interest = math.floor(BankStation.storedMoney * interestPercent)
            BankStation.storedMoney = BankStation.storedMoney + interest

            local maxMoney = maxBalances[BankStation.upgradeLevel] * 1000000
            if BankStation.storedMoney >= maxMoney then
                local overflow = BankStation.storedMoney - maxMoney
                BankStation.storedMoney = maxMoney
                Faction():receive("Received %1% Credits: Bank Interest Overflow." % _T, overflow)
            end

            Faction():sendChatMessage(Entity(), ChatMessageType.Chatter, "Earned %1% credits in interest." % _T,
                createMonetaryString(interest))
        end
    elseif onClient() then
        invokeServerFunction("sync")
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
function BankStation.onWithdrawBoxChange(box)
    local enteredNumber = tonumber(box.text) or 0
    if enteredNumber >= BankStation.storedMoney then
        enteredNumber = BankStation.storedMoney
    end
    box.text = enteredNumber
end
callable(BankStation, "onWithdrawBoxChange")

function BankStation.onDepositBoxChange(box)
    local enteredNumber = tonumber(box.text) or 0
    local maxMoney = maxBalances[BankStation.upgradeLevel] * 1000000
    if (BankStation.storedMoney + enteredNumber) >= maxMoney then
        enteredNumber = maxMoney - BankStation.storedMoney
    end
    box.text = enteredNumber
end
callable(BankStation, "onDepositBoxChange")

function BankStation.onBtnDepositClick(depositAmount)
    if onClient() then
        local depositAmount = tonumber(txtDeposit.text) or 0
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
        local withdrawAmount = tonumber(txtWithdraw.text) or 0
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

    local buyer, _, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources,
        AlliancePrivilege.ManageStations)
    if not buyer then
        return
    end

    if upgradeLevel == 5 then
        player:sendChatMessage("", ChatMessageType.Error, "This station cannot be upgraded farther." % _t)
        return
    end

    local price = upgradePrices[BankStation.upgradeLevel + 1] * 1000000

    local canPay, msg, args = buyer:canPay(price)
    if not canPay then -- if there was an error, print it
        player:sendChatMessage(Entity(), 1, msg, unpack(args))
        return
    end

    buyer:pay(price)

    BankStation.upgradeLevel = BankStation.upgradeLevel + 1

    BankStation:sync()
end
callable(BankStation, "onUpgradeButtonPressed")

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
