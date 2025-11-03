--============================================================
-- Alliance Networks - Global Car Door Sound System (Enter/Exit Split)
--  * Plays "cardooreenter.ogg" when players enter vehicles
--  * Plays "cardoorexit.ogg" when players exit vehicles
--  * Skips standalone GMod chairs (prop_vehicle_prisoner_pod not attached to a car)
--============================================================

if SERVER then
    resource.AddFile("sound/carjacktime/cardooreenter.ogg")
    resource.AddFile("sound/carjacktime/cardoorexit.ogg")

    ------------------------------
    -- SETTINGS
    ------------------------------
    CreateConVar("cardoor_sfx_enable", "1", FCVAR_ARCHIVE, "Enable car door sound system (0/1)")
    CreateConVar("cardoor_sfx_cooldown", "0.5", FCVAR_ARCHIVE, "Minimum seconds between sounds per vehicle")
    CreateConVar("cardoor_sfx_volume", "1.0", FCVAR_ARCHIVE, "Volume (0.0 - 1.0)")
    CreateConVar("cardoor_sfx_pitch", "100", FCVAR_ARCHIVE, "Pitch (50 - 255)")
    CreateConVar("cardoor_sfx_exit_delay", "0.2", FCVAR_ARCHIVE, "Delay before playing sound on exit")

    local lastPlay = {}

    ------------------------------
    -- CHAIR DETECTION (skip standalone pods)
    ------------------------------
    local function IsStandaloneChair(ent)
        if not IsValid(ent) then return false end
        if ent:GetClass() ~= "prop_vehicle_prisoner_pod" then return false end

        -- parented seats (part of vehicles) are fine
        local parent = ent:GetParent()
        if IsValid(parent) then
            local pcls = parent:GetClass()
            if parent:IsVehicle() and pcls ~= "prop_vehicle_prisoner_pod" then return false end
            if pcls == "gmod_sent_vehicle_fphysics_base" then return false end
            if pcls:find("scar", 1, true) then return false end
        end

        -- check if constrained to a vehicle
        local constrained = constraint.GetAllConstrainedEntities and constraint.GetAllConstrainedEntities(ent) or {}
        for _, e in pairs(constrained) do
            if IsValid(e) then
                local cls = e:GetClass()
                if (e:IsVehicle() and cls ~= "prop_vehicle_prisoner_pod")
                    or cls == "gmod_sent_vehicle_fphysics_base"
                    or (cls and cls:find("scar", 1, true)) then
                    return false
                end
            end
        end

        return true -- standalone chair
    end

    local function ShouldPlayFor(veh)
        if not IsValid(veh) then return false end
        if not GetConVar("cardoor_sfx_enable"):GetBool() then return false end
        if IsStandaloneChair(veh) then return false end
        return true
    end

    ------------------------------
    -- SOUND PLAYER
    ------------------------------
    local function playDoorSound(veh, isExit)
        if not ShouldPlayFor(veh) then return end

        local now = CurTime()
        local id  = veh:EntIndex()
        local cd  = GetConVar("cardoor_sfx_cooldown"):GetFloat()
        if (lastPlay[id] or 0) + cd > now then return end
        lastPlay[id] = now

        local vol = math.Clamp(GetConVar("cardoor_sfx_volume"):GetFloat(), 0, 1)
        local pit = math.Clamp(GetConVar("cardoor_sfx_pitch"):GetInt(), 50, 255)
        local snd = isExit and "carjacktime/cardoorexit.ogg" or "carjacktime/cardooreenter.ogg"

        veh:EmitSound(snd, math.floor(vol * 100), pit, vol)
    end

    ------------------------------
    -- ENTER SOUND
    ------------------------------
    hook.Add("PlayerEnteredVehicle", "AN_CarDoor_EnterSFX", function(ply, veh, role)
        if not IsValid(ply) or not IsValid(veh) then return end
        playDoorSound(veh, false)
    end)

    ------------------------------
    -- EXIT SOUND
    ------------------------------
    hook.Add("PlayerLeaveVehicle", "AN_CarDoor_ExitSFX", function(ply, veh)
        if not IsValid(ply) or not IsValid(veh) then return end
        local delay = GetConVar("cardoor_sfx_exit_delay"):GetFloat()
        timer.Simple(delay, function()
            if IsValid(veh) then playDoorSound(veh, true) end
        end)
    end)

    ------------------------------
    -- SEAT SWITCH (Edge case)
    ------------------------------
    hook.Add("OnPlayerChangedVehicle", "AN_CarDoor_SwitchSFX", function(ply, oldVeh, newVeh)
        if IsValid(newVeh) then playDoorSound(newVeh, false) end
    end)

    print("[Alliance Networks] Car Door SFX (enter/exit split) loaded successfully.")
end
