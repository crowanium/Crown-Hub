local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local kingdoms = {
    [10035204815] = "https://raw.githubusercontent.com/crowanium/Crown-Hub/main/Games/rideapet.luau",
}

local kingdom = kingdoms[game.GameId]

if not kingdom then
    LocalPlayer:Kick("This game is not supported!")
    return
