
local oldInitialize = StationFounder.initialize or function() end
function StationFounder.initialize(shipyardFaction)
    oldInitialize(shipyardFaction)

    --Add our new bank station to the list.
    table.insert(StationFounder.stations, 
        {
            name = "Bank"%_t,
            tooltip = "Allows players to deposit money. Money stored in the bank earns 2% interest every 5 minutes. Deposited money cannot be used until it is withdrawn."%_t .. "\n\n" ..
                    "This station will attract pirates even while the player is not in the system!"%_t,
            scripts = {
                {script = "data/scripts/entity/bankstation.lua"}
            },
            getPrice = function()
                return 1 * 1000000
            end
        }
    )
end