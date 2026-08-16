-- R = ativar/desativar | U = atualizar friendcache

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local StarterGui        = cloneref(game:GetService("StarterGui"))
local Players           = cloneref(game:GetService("Players"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local RunService        = cloneref(game:GetService("RunService"))

pcall(function()
    local OldNamecall
    OldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and tostring(self) == "AutoclickerDetected" then
            return
        end
        return OldNamecall(self, ...)
    end))
end)

local Settings       = {
    Enabled        = false,
    DetectionRange = 9999,
    CPS            = 2000,
}

local LocalPlayer    = Players.LocalPlayer
local lastExecution  = 0
local _friendCache   = {}
local _carryDebounce = false

local function cacheFriendship(player)
    if not player or player == LocalPlayer then return end
    task.spawn(function()
        local ok, isFriend = pcall(function()
            return LocalPlayer:IsFriendsWith(player.UserId)
        end)
        if ok then _friendCache[player.UserId] = isFriend end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do cacheFriendship(p) end
Players.PlayerAdded:Connect(cacheFriendship)
Players.PlayerRemoving:Connect(function(p) _friendCache[p.UserId] = nil end)

local remotes        = ReplicatedStorage:WaitForChild("Remotes")
local releaseRemote  = remotes:WaitForChild("CarryService"):WaitForChild("RequestToReleasePlayer")

local PlayerScripts  = LocalPlayer:WaitForChild("PlayerScripts")
local ModuleScripts  = PlayerScripts:WaitForChild("ModuleScripts")
local AbilityHandler = require(ModuleScripts:WaitForChild("AbilityHandler"))
local ClientDebounce = require(ModuleScripts:WaitForChild("ClientDebounce"))

local function SendNotification(text)
    StarterGui:SetCore("SendNotification", {
        Title    = "AUTO CLICK",
        Text     = text,
        Duration = 2,
    })
end

local function refreshFriendCache()
    _friendCache = {}
    for _, p in ipairs(Players:GetPlayers()) do cacheFriendship(p) end
    SendNotification("Amigos atualizados")
end

local function getCarriedPlayer()
    local char = LocalPlayer.Character
    if not char then return nil end

    for _, child in ipairs(char:GetDescendants()) do
        if child:IsA("Weld") or child:IsA("WeldConstraint") then
            local p0, p1 = child.Part0, child.Part1
            if p0 and p1 then
                local other = (p0:IsDescendantOf(char) and p1) or (p1:IsDescendantOf(char) and p0)
                if other and other.Parent and other.Parent:FindFirstChild("Humanoid") and other.Parent ~= char then
                    return other.Parent
                end
            end
        end
    end

    local cv = char:GetAttribute("Carry") or char:GetAttribute("Carrying") or char:GetAttribute("IsCarrying")
    if cv then
        if typeof(cv) == "Instance" then
            return cv:IsA("Player") and cv.Character or (cv:IsA("Model") and cv)
        elseif typeof(cv) == "string" then
            local plr = Players:FindFirstChild(cv)
            return plr and plr.Character
        end
    end
    return nil
end

local function getTargetInContact()
    local character = LocalPlayer.Character
    if not character then return nil end
    local myRoot = character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local closestTarget = nil
    local shortestDist  = Settings.DetectionRange

    local entities      = workspace:FindFirstChild("Entities")
    local searchGroup   = entities and entities:GetChildren() or Players:GetPlayers()

    for _, target in pairs(searchGroup) do
        local targetChar = target:IsA("Player") and target.Character or target
        if targetChar and targetChar ~= character and targetChar:FindFirstChild("HumanoidRootPart") then
            local plr = target:IsA("Player") and target or Players:GetPlayerFromCharacter(targetChar)
            if plr and _friendCache[plr.UserId] then continue end

            local h = targetChar:FindFirstChildOfClass("Humanoid")
            if h and h.Health <= 0 then continue end

            local dist = (myRoot.Position - targetChar.HumanoidRootPart.Position).Magnitude
            if dist < shortestDist then
                shortestDist  = dist
                closestTarget = targetChar
            end
        end
    end
    return closestTarget
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end

    if input.KeyCode == Enum.KeyCode.R then
        Settings.Enabled = not Settings.Enabled
        SendNotification(Settings.Enabled and "ATIVADO" or "DESATIVADO")
    elseif input.KeyCode == Enum.KeyCode.U then
        refreshFriendCache()
    end
end)

RunService.Heartbeat:Connect(function()
    if not Settings.Enabled then return end

    if not _carryDebounce then
        local carried = getCarriedPlayer()
        if carried then
            _carryDebounce = true
            task.spawn(function()
                pcall(function() releaseRemote:InvokeServer(carried) end)
                task.wait(1)
                _carryDebounce = false
            end)
        end
    end

    local ability = AbilityHandler.activeAbility
    if not ability then return end

    local abilityName = ability._name
    if abilityName and ClientDebounce.isAlive(abilityName) then return end

    if ability._animTracks and ability._animTracks["activated"] then
        if ability._animTracks["activated"].IsPlaying then return end
    end

    local now = tick()
    if now - lastExecution < (1 / Settings.CPS) then return end

    local targetEntity = getTargetInContact()
    if not targetEntity then return end

    lastExecution = now

    if ability._targetSystem then
        ability._targetSystem.ValidTarget = targetEntity
    end
    if ability._target ~= nil then
        ability._target = targetEntity
    end
    ability._isHolding = true

    pcall(mouse1press)
    pcall(mouse1release)

    ability._isHolding = false
end)

SendNotification("R = toggle | U = amigos")
