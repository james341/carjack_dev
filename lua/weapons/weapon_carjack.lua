-- lua/weapons/weapon_carjack.lua
-- Carjacker SWEP (occupied-only + window-break on Reload)
-- Plays one random job-specific sound on success via AN_CJ_PlayJobRandom (if available)
-- Author: Alliance Networks + ChatGPT (final)

if SERVER then AddCSLuaFile() end

SWEP.PrintName      = "Carjacker"
SWEP.Author         = "Alliance Networks + ChatGPT"
SWEP.Instructions   = "Primary (LMB): Hold to carjack an OCCUPIED vehicle.\nReload (R): Break the window of a LOCKED vehicle (short hold)."
SWEP.Category     = "DarkRP (Weapon)"   -- ← this decides where it shows in Q-menu
SWEP.Spawnable      = true
SWEP.AdminOnly      = false

SWEP.ViewModel      = "models/weapons/c_arms.mdl"
SWEP.WorldModel     = "models/weapons/w_pistol.mdl"
SWEP.UseHands       = true
SWEP.HoldType       = "normal"

SWEP.Primary.ClipSize     = -1
SWEP.Primary.DefaultClip  = -1
SWEP.Primary.Automatic    = false
SWEP.Primary.Ammo         = "none"
SWEP.Secondary            = SWEP.Primary
SWEP.DrawAmmo             = false

------------------------------
-- SERVER-CONFIG / NETWORK / RESOURCES
------------------------------
if SERVER then
    AddCSLuaFile()

    -- Shared door sound: ensure clients download (change path if you use .ogg)
    resource.AddFile("sound/carjacktime/carDoorsound.mp3")

    -- ConVars
    CreateConVar("carjack_debug", "0", FCVAR_ARCHIVE, "Enable debug prints (0/1)")
    CreateConVar("carjack_range", "130", FCVAR_ARCHIVE, "Max range to start a carjack")
    CreateConVar("carjack_time", "2.5", FCVAR_ARCHIVE, "Seconds required to complete a carjack")
    CreateConVar("carjack_cooldown", "6", FCVAR_ARCHIVE, "Cooldown seconds after attempt")
    CreateConVar("carjack_move_cancel", "85", FCVAR_ARCHIVE, "Max distance player can move during attempt")
    CreateConVar("carjack_allow_drivers_protect", "1", FCVAR_ARCHIVE, "Prevent jacking moving vehicles (0/1)")
    CreateConVar("carjack_speed_threshold", "100", FCVAR_ARCHIVE, "Speed threshold when protection enabled")

    CreateConVar("carjack_window_time", "1.5", FCVAR_ARCHIVE, "Seconds to break a window with Reload")
    CreateConVar("carjack_window_cooldown", "4", FCVAR_ARCHIVE, "Cooldown after breaking a window")
    CreateConVar("carjack_window_reset", "30", FCVAR_ARCHIVE, "Seconds a broken window stays broken before 'relocking'")

    util.AddNetworkString("Carjack_Start")
    util.AddNetworkString("Carjack_Cancel")
    util.AddNetworkString("Carjack_Success")
    util.AddNetworkString("Carjack_Fail")
    util.AddNetworkString("Carjack_WindowStart")
    util.AddNetworkString("Carjack_WindowBroken")
    util.AddNetworkString("Carjack_WindowCancel")
end

local function dbg(...)
    if SERVER and GetConVar("carjack_debug"):GetInt() == 1 then
        print("[Carjack]", ...)
    end
end

------------------------------
-- VEHICLE HELPERS
------------------------------
local function IsAnyVehicle(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end
    local cls = ent:GetClass()
    if cls == "gmod_sent_vehicle_fphysics_base" then return true end
    if cls == "gmod_sent_vehicle_fphysics_seat" then return true end
    return false
end

local function VehicleFromSeat(ent)
    if not IsValid(ent) then return nil end
    if ent:IsVehicle() then return ent end
    local cls = ent:GetClass()
    if cls == "gmod_sent_vehicle_fphysics_seat" and ent.GetParent then
        local base = ent:GetParent()
        if IsValid(base) then return base end
    end
    return nil
end

local function GetDriverOfVehicle(veh)
    if not IsValid(veh) then return nil end
    if veh.GetDriver then
        local drv = veh:GetDriver()
        if IsValid(drv) then return drv end
    end
    if veh:GetClass() == "gmod_sent_vehicle_fphysics_base" and veh.GetDriverSeat and IsValid(veh:GetDriverSeat()) then
        local seat = veh:GetDriverSeat()
        local drv = IsValid(seat) and seat:GetDriver() or nil
        if IsValid(drv) then return drv end
    end
    return nil
end

local function GetBestSeatToEnter(ply, veh)
    if not IsValid(veh) then return nil end
    if veh:IsVehicle() then return veh end
    if veh.GetDriverSeat then
        local driverSeat = veh:GetDriverSeat()
        if IsValid(driverSeat) and not IsValid(driverSeat:GetDriver()) then
            return driverSeat
        end
    end
    return veh
end

local function FindNearbyVehicle(ply, range)
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * range,
        filter = ply,
        mask = MASK_SHOT
    })

    if tr.Hit and IsValid(tr.Entity) and IsAnyVehicle(tr.Entity) then
        local v = VehicleFromSeat(tr.Entity) or tr.Entity
        return v
    end

    local pos = ply:GetPos()
    local best, bestDist = nil, range + 1
    for _, ent in ipairs(ents.FindInSphere(pos, range)) do
        if IsAnyVehicle(ent) then
            local d = ent:GetPos():Distance(pos)
            if d < bestDist then
                best, bestDist = ent, d
            end
        end
    end
    return best
end

-- best-effort locked detection
local function IsVehicleLocked(veh)
    if not IsValid(veh) then return false end
    if veh.GetNWBool then
        if veh:GetNWBool("locked", false) then return true end
        if veh:GetNWBool("Locked", false) then return true end
        if veh:GetNWBool("CarLocked", false) then return true end
        if veh:GetNWBool("vehicle_locked", false) then return true end
    end
    if veh.GetNWInt and veh:GetNWInt("locked", 0) == 1 then return true end
    if veh.Locked ~= nil and veh.Locked == true then return true end
    return false
end

local function UnlockVehicle(veh)
    if not IsValid(veh) then return end
    if veh.SetNWBool then
        veh:SetNWBool("locked", false)
        veh:SetNWBool("Locked", false)
        veh:SetNWBool("CarLocked", false)
        veh:SetNWBool("vehicle_locked", false)
    end
    if veh.SetNWInt then
        veh:SetNWInt("locked", 0)
    end
    if veh.Unlock then
        pcall(function() veh:Unlock() end)
    end
    veh:SetNWBool("Carjack_WindowBroken", true)
    local resetTime = GetConVar("carjack_window_reset"):GetFloat()
    timer.Create("carjack_window_reset_" .. tostring(veh:EntIndex()), resetTime, 1, function()
        if IsValid(veh) then
            veh:SetNWBool("Carjack_WindowBroken", false)
        end
    end)
end

------------------------------
-- CANCEL/HOOKS
------------------------------
local function CancelCarjack(ply, reason)
    if not IsValid(ply) then return end
    local tname = "carjack_timer_" .. ply:SteamID64()
    if timer.Exists(tname) then timer.Remove(tname) end
    ply._carjack_active = false
    ply._carjack_target = nil
    if SERVER then
        net.Start("Carjack_Cancel") net.Send(ply)
        if reason then ply:ChatPrint(reason) end
    end
end

hook.Add("EntityTakeDamage", "Carjack_CancelOnDamage", function(ent, dmg)
    if not SERVER then return end
    if IsValid(ent) and ent:IsPlayer() and ent._carjack_active then
        dbg(ent, "took damage; cancel")
        CancelCarjack(ent, "You took damage. Carjack canceled.")
    end
end)

hook.Add("PlayerSwitchWeapon", "Carjack_CancelOnSwitch", function(ply, old, new)
    if not SERVER then return end
    if IsValid(ply) and ply._carjack_active then
        dbg(ply, "weapon switch; cancel")
        CancelCarjack(ply, "You switched weapons. Carjack canceled.")
    end
end)

function SWEP:Holster()
    if SERVER and IsValid(self:GetOwner()) then
        local ply = self:GetOwner()
        if ply._carjack_active then CancelCarjack(ply, "Carjack canceled (holster).") end
        if ply._window_active then
            local tname = "carjack_window_timer_" .. ply:SteamID64()
            if timer.Exists(tname) then timer.Remove(tname) end
            ply._window_active = false
            net.Start("Carjack_WindowCancel") net.Send(ply)
            ply:ChatPrint("Window smash canceled (holster).")
        end
    end
    return true
end

function SWEP:OnRemove()
    if SERVER and IsValid(self:GetOwner()) then
        local ply = self:GetOwner()
        if ply._carjack_active then CancelCarjack(ply, "Carjack canceled (weapon removed).") end
        if ply._window_active then
            local tname = "carjack_window_timer_" .. ply:SteamID64()
            if timer.Exists(tname) then timer.Remove(tname) end
            ply._window_active = false
            net.Start("Carjack_WindowCancel") net.Send(ply)
            ply:ChatPrint("Window smash canceled (weapon removed).")
        end
    end
end

------------------------------
-- PRIMARY: Carjack (occupied vehicles only)
------------------------------
function SWEP:PrimaryAttack()
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:Alive() then return end

    local range        = GetConVar("carjack_range"):GetFloat()
    local jackTime     = GetConVar("carjack_time"):GetFloat()
    local cooldown     = GetConVar("carjack_cooldown"):GetFloat()
    local moveCancel   = GetConVar("carjack_move_cancel"):GetFloat()
    local protectMove  = GetConVar("carjack_allow_drivers_protect"):GetInt() == 1
    local speedThresh  = GetConVar("carjack_speed_threshold"):GetFloat()

    ply._carjack_cd = ply._carjack_cd or 0
    if CurTime() < ply._carjack_cd then
        ply:ChatPrint("Carjack cooldown: " .. math.ceil(ply._carjack_cd - CurTime()) .. "s.")
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return
    end

    local veh = FindNearbyVehicle(ply, range)
    if not IsValid(veh) then
        ply:ChatPrint("No vehicle nearby.")
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return
    end

    -- require driver
    local drv = GetDriverOfVehicle(veh)
    if not IsValid(drv) then
        ply:ChatPrint("That vehicle has no driver. You can only carjack OCCUPIED vehicles.")
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return
    end

    -- check lock: if locked and window not previously broken, block carjack
    if IsVehicleLocked(veh) and not veh:GetNWBool("Carjack_WindowBroken", false) then
        ply:ChatPrint("That vehicle is locked. Break the window (press R) first.")
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return
    end

    if veh:GetNWBool("Carjack_InProgress", false) then
        ply:ChatPrint("That vehicle is already being tampered with.")
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return
    end

    if protectMove and veh:GetVelocity():Length() > speedThresh then
        ply:ChatPrint("Vehicle is moving too fast to carjack right now.")
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return
    end

    -- start carjack attempt
    dbg(ply, "starting carjack on", veh)
    ply._carjack_cd = CurTime() + cooldown
    ply._carjack_active = true
    ply._carjack_target = veh
    veh:SetNWBool("Carjack_InProgress", true)

    local startPos = ply:GetPos()
    local startTime = CurTime()
    net.Start("Carjack_Start") net.WriteEntity(veh) net.Send(ply)
    ply:ChatPrint("Carjack started. Hold still for " .. jackTime .. "s...")
    ply:EmitSound("buttons/button14.wav")

    local tname = "carjack_timer_" .. ply:SteamID64()
    timer.Create(tname, 0.1, 0, function()
        if not IsValid(ply) or not ply:Alive() then
            if IsValid(veh) then veh:SetNWBool("Carjack_InProgress", false) end
            CancelCarjack(ply, "Carjack canceled.")
            return
        end
        if not IsValid(veh) then
            CancelCarjack(ply, "Vehicle disappeared. Carjack failed.")
            return
        end
        if ply:GetPos():Distance(startPos) > moveCancel then
            veh:SetNWBool("Carjack_InProgress", false)
            CancelCarjack(ply, "You moved too far. Carjack canceled.")
            return
        end
        if ply:GetPos():Distance(veh:GetPos()) > range + 20 then
            veh:SetNWBool("Carjack_InProgress", false)
            CancelCarjack(ply, "You moved away. Carjack canceled.")
            return
        end
        if protectMove and veh:GetVelocity():Length() > speedThresh then
            veh:SetNWBool("Carjack_InProgress", false)
            CancelCarjack(ply, "Vehicle drove off. Carjack canceled.")
            return
        end

        if CurTime() - startTime >= jackTime then
            timer.Remove(tname)
            ply._carjack_active = false

            -- eject driver
            local drv2 = GetDriverOfVehicle(veh)
            if IsValid(drv2) and drv2:IsPlayer() then
                drv2:ExitVehicle()
                drv2:SetPos(veh:GetPos() + Vector(0, 0, 52))
                drv2:ChatPrint("You were carjacked!")
                drv2:EmitSound("npc/headcrab_poison/pz_warn1.wav")

                -- play car door slam on vehicle (so nearby hear it)
                if IsValid(veh) then
                    veh:EmitSound("carjacktime/carDoorsound.mp3", 90, 100)
                end
            end

            -- attempt to enter
            local seat = GetBestSeatToEnter(ply, veh)
            if IsValid(seat) then
                if seat:IsVehicle() then
                    ply:EnterVehicle(seat)
                else
                    -- simfphys seat: use to enter
                    seat:Use(ply, ply, USE_ON, 1)
                end
                ply:ChatPrint("Carjack successful!")

                -- play shared car door slam for everyone / local feedback
                if IsValid(veh) then veh:EmitSound("carjacktime/carDoorsound.mp3", 90, 100) end
                ply:EmitSound("carjacktime/carDoorsound.mp3", 90, 100)

                -- JOB-SPECIFIC RANDOM SFX (play exactly ONE random clip)
                if type(AN_CJ_PlayJobRandom) == "function" then
                    pcall(function() AN_CJ_PlayJobRandom(ply, "carjack_success", veh) end)
                end

                net.Start("Carjack_Success") net.WriteEntity(veh) net.Send(ply)
            else
                ply:ChatPrint("Carjack failed: no free seat.")
                net.Start("Carjack_Fail") net.Send(ply)
            end

            if IsValid(veh) then veh:SetNWBool("Carjack_InProgress", false) end
        end
    end)

    self:SetNextPrimaryFire(CurTime() + 0.2)
end

------------------------------
-- RELOAD: window-break mechanic for LOCKED vehicles
------------------------------
function SWEP:Reload()
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:Alive() then return end

    local range = GetConVar("carjack_range"):GetFloat()
    local windowTime = GetConVar("carjack_window_time"):GetFloat()
    local windowCooldown = GetConVar("carjack_window_cooldown"):GetFloat()

    ply._window_cd = ply._window_cd or 0
    if CurTime() < ply._window_cd then
        ply:ChatPrint("Window smash cooldown: " .. math.ceil(ply._window_cd - CurTime()) .. "s.")
        return
    end

    local veh = FindNearbyVehicle(ply, range)
    if not IsValid(veh) then
        ply:ChatPrint("No vehicle nearby to smash.")
        return
    end

    if not IsVehicleLocked(veh) and not veh:GetNWBool("Carjack_WindowBroken", false) then
        ply:ChatPrint("This vehicle isn't locked or already has an open window.")
        return
    end

    if ply._window_active then
        ply:ChatPrint("You're already smashing a window.")
        return
    end

    -- start window smash attempt
    ply._window_cd = CurTime() + windowCooldown
    ply._window_active = true
    ply._window_target = veh
    net.Start("Carjack_WindowStart") net.Send(ply)
    ply:ChatPrint("Smashing window... Hold still for " .. windowTime .. "s")
    ply:EmitSound("physics/glass/glass_bottle_break1.wav")

    local startPos = ply:GetPos()
    local startTime = CurTime()
    local tname = "carjack_window_timer_" .. ply:SteamID64()

    timer.Create(tname, 0.1, 0, function()
        if not IsValid(ply) or not ply:Alive() then
            if IsValid(veh) then veh:SetNWBool("Carjack_WindowBroken", false) end
            ply._window_active = false
            net.Start("Carjack_WindowCancel") net.Send(ply)
            timer.Remove(tname)
            return
        end
        if not IsValid(veh) then
            ply._window_active = false
            net.Start("Carjack_WindowCancel") net.Send(ply)
            ply:ChatPrint("Vehicle disappeared. Smash failed.")
            timer.Remove(tname)
            return
        end
        if ply:GetPos():Distance(startPos) > GetConVar("carjack_move_cancel"):GetFloat() then
            ply._window_active = false
            net.Start("Carjack_WindowCancel") net.Send(ply)
            ply:ChatPrint("You moved too far. Smash canceled.")
            timer.Remove(tname)
            return
        end

        if CurTime() - startTime >= windowTime then
            timer.Remove(tname)
            ply._window_active = false

            -- glass break effect & sound
            ply:EmitSound("physics/glass/glass_bottle_break2.wav")
            local effectdata = EffectData()
            effectdata:SetOrigin(veh:GetPos() + vector_up * 40)
            util.Effect("GlassImpact", effectdata, true, true)

            if IsValid(veh) then
                veh:EmitSound("carjacktime/carDoorsound.mp3", 90, 100)
            end

            -- unlock vehicle and mark window broken
            UnlockVehicle(veh)

            -- JOB-SPECIFIC RANDOM SFX for window-break (play exactly ONE random clip)
            if type(AN_CJ_PlayJobRandom) == "function" then
                pcall(function() AN_CJ_PlayJobRandom(ply, "window_break", veh) end)
            end

            net.Start("Carjack_WindowBroken") net.WriteEntity(veh) net.Send(ply)
            ply:ChatPrint("Window smashed! Vehicle unlocked for a short time.")
        end
    end)
end

------------------------------
-- secondary mirrors primary
------------------------------
function SWEP:SecondaryAttack()
    self:PrimaryAttack()
end

------------------------------
-- CLIENT small hooks for future HUD updates
------------------------------
if CLIENT then
    language.Add("weapon_carjack", "Carjacker")
    net.Receive("Carjack_WindowStart", function() end)
    net.Receive("Carjack_WindowBroken", function() end)
    net.Receive("Carjack_WindowCancel", function() end)
    net.Receive("Carjack_Start", function() end)
    net.Receive("Carjack_Cancel", function() end)
    net.Receive("Carjack_Success", function() end)
    net.Receive("Carjack_Fail", function() end)
end
