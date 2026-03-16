package.path = package.path .. ";data/scripts/lib/?.lua"
local Placer = include("placer")
local AsyncPirateGenerator = include("asyncpirategenerator")
local SpawnUtility = include("spawnutility")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace BankRobbers
BankRobbers = {}

local updateTimer
local updateInterval

local knownRobbers = {}

function BankRobbers.secure()
    return {
        updateTimer = updateTimer,
        updateInterval = updateInterval,
        knownRobbers = knownRobbers
    }
end

function BankRobbers.restore(data)
    updateTimer = data.updateTimer or 0
    updateInterval = data.updateInterval or 900
    knownRobbers = data.knownRobbers or {}
end

function BankRobbers.getUpdateInterval()
    return 60
end

function BankRobbers.onRestoredFromDisk(time)
    BankRobbers.updateServer(time)
end

function BankRobbers.initialize()
    if onServer() then
        Sector():registerCallback("onRestoredFromDisk", "onRestoredFromDisk")
        Sector():registerCallback("onDestroyed", "onEntityDestroyed")
    end
end

function BankRobbers.getTotalValue()
    local stations = {Sector():getEntitiesByScript("entity/bankstation.lua")}
    local totalValue = 0

    for _, station in pairs(stations) do
        totalValue = totalValue + (station:getValue("AccountValue") or 0)
    end

    return totalValue
end

function BankRobbers.getShipCount(totalValue)
    local shipCount = 1 -- make sure we at least send 1 ship
    local _mil = 1000000

    -- Some Static Break Points, then linerarlly every 40 mil
    if totalValue >= 1 * _mil then
        shipCount = shipCount + 1
    end
    if totalValue >= 10 * _mil then
        shipCount = shipCount + 1
    end
    if totalValue >= 35 * _mil then
        shipCount = shipCount + 2
    end
    if totalValue >= 70 * _mil then
        shipCount = shipCount + 2
    end
    if totalValue >= 150 * _mil then
        shipCount = shipCount + 2
    end
    if totalValue >= 225 * _mil then
        shipCount = shipCount + 2
    end
    if totalValue >= 350 * _mil then
        shipCount = shipCount + 1
    end

    -- Don't crash the server so max 12 ships
    shipCount = math.min(shipCount, 12)

    return shipCount
end

function BankRobbers.updateServer(timeStep)
    -- actually tick once every 15 minutes
    updateInterval = updateInterval or math.random(15 * 60, 20 * 60) -- default is every 15 - 20 minutes

    updateTimer = (updateTimer or 0) + timeStep
    if updateTimer < updateInterval then
        return
    end
    updateInterval = math.random(15 * 60, 20 * 60) -- random a new time so it's not predictable
    updateTimer = updateTimer - updateInterval

    local sector = Sector()
    if not sector then
        return
    end

    -- make sure the bank still exists
    local totalBankValue = BankRobbers.getTotalValue()

    -- If the bank is poor then lets not bother with the server load of spawning ships
    if totalBankValue < 100000 then
        return
    end

    -- ADDED FIX: Check if there are already robbers alive in the sector
    local existingRobbers = 0
    local sectorShips = {Sector():getEntitiesByType(EntityType.Ship)}
    
    for _, ship in pairs(sectorShips) do
        if ship:getValue("is_bank_robber") then
            existingRobbers = existingRobbers + 1
        end
    end

    -- If robbers are already here, abort the spawn and wait for the next timer cycle
    if existingRobbers > 0 then
        return
    end

    -- Calculate how many pirates to send based on system bank's total value
    local shipCount = BankRobbers.getShipCount(totalBankValue)

    -- Send Pirates
    -- print("Bank Robbers Sending " .. shipCount .. " ships")
    BankRobbers.SendPirates(shipCount)
end

function BankRobbers.SendPirates(shipCount)
    local generator = AsyncPirateGenerator(BankRobbers, BankRobbers.onPiratesGenerated)
    local faction = generator:getPirateFaction()

    -- create attacking ships
    local dir = normalize(vec3(getFloat(-1, 1), getFloat(-1, 1), getFloat(-1, 1)))
    local up = vec3(0, 1, 0)
    local right = normalize(cross(dir, up))
    local pos = dir * 1000

    local attackType = getInt(1, 4)

    local distance = 50

    generator:startBatch()

    -- Adds variety to the pirate waves trying to scale based on value/number of ships
    for i = 1, shipCount do
        local offset = right * distance * math.floor(i / 2)
        if math.fmod(i, 2) == 0 then
            offset = offset * -1
        end

        local relativePos = pos + offset

        if i <= 2 then
            generator:createPirate(MatrixLookUpPosition(-dir, up, relativePos))
        elseif i <= 4 then
            generator:createMarauder(MatrixLookUpPosition(-dir, up, relativePos))
        elseif i == 5 or i == 9 then
            generator:createDisruptor(MatrixLookUpPosition(-dir, up, relativePos))
        elseif i <= 8 then
            generator:createRaider(MatrixLookUpPosition(-dir, up, relativePos))
        elseif i <= 11 then
            generator:createRavager(MatrixLookUpPosition(-dir, up, relativePos))
        elseif i == 12 then
            generator:createBoss(MatrixLookUpPosition(-dir, up, relativePos))
        end
    end

    generator:endBatch()

    Sector():broadcastChatMessage("Server" % _t, 2, "Bank robbers are attacking the sector!" % _t)
    AlertAbsentPlayers(2, "Bank robbers are attacking sector \\s(%1%:%2%)!" % _t, Sector():getCoordinates())
end

function BankRobbers.onPiratesGenerated(generated)
    -- add enemy buffs
    SpawnUtility.addEnemyBuffs(generated)

    -- resolve intersections between generated ships
    Placer.resolveIntersections(generated)

    -- ADDED FIX: Tag these specific ships so we can find them later
    for _, ship in pairs(generated) do
        knownRobbers[ship.index.string] = true
        if valid(ship) then
            ship:setValue("is_bank_robber", true)
        end
    end
end

-- == THE VACUUM SWEEP ==
function BankRobbers.onEntityDestroyed(index, lastDamageInflictor)
    local idString = index.string
    
    -- If it wasn't a robber, ignore it completely
    if not knownRobbers[idString] then return end
    knownRobbers[idString] = nil
    
    local entity = Sector():getEntity(index)
    if entity and valid(entity) then
        local pos = entity.translationf
        -- Vacuum immediately, then again 0.5s later to catch delayed drops
        BankRobbers.vacuumRobberLoot(pos.x, pos.y, pos.z)
        deferredCallback(0.5, "vacuumRobberLoot", pos.x, pos.y, pos.z)
    end
end

function BankRobbers.vacuumRobberLoot(x, y, z)
    local sector = Sector()
    
    -- 1. Vacuum Loot (Turrets, Systems, Credits)
    local loots = {sector:getEntitiesByType(EntityType.Loot)}
    for _, loot in pairs(loots) do
        if valid(loot) then
            local lpos = loot.translationf
            -- Use squared distance (1000 * 1000 = 1000000) for instant math
            local distSq = (lpos.x - x)^2 + (lpos.y - y)^2 + (lpos.z - z)^2
            if distSq < 1000000 then
                sector:deleteEntity(loot)
            end
        end
    end
end