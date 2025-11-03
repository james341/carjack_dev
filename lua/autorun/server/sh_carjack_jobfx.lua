--============================================================
-- Alliance Networks - Carjack Job FX Registry (FINAL, no-repeat)
--  * Plays ONE random clip per event (carjack_success / window_break)
--  * Remembers last clip per player to avoid immediate repeats
--  * Auto resource.AddFile for all registered .ogg files
--============================================================

CARJACK_JOB_FX = CARJACK_JOB_FX or {}

-----------------------------------------------------
-- Helpers
-----------------------------------------------------
local function _jobkey_from_player(ply)
    local name = team.GetName(ply:Team()) or ""
    return string.Trim(string.lower(name))
end

function AN_CJ_GetFxForPlayer(ply)
    if not IsValid(ply) then return nil end
    return CARJACK_JOB_FX[_jobkey_from_player(ply)]
end

-----------------------------------------------------
-- Register per-job FX definition
-- t fields:
--   base_path       : "folder/" under /sound
--   carjack_success : { "a.ogg", "b.ogg", ... }  -- REQUIRED
--   window_break    : { "x.ogg", ... }           -- OPTIONAL
--   volume          : 0..1 (default 1)
--   pitch           : 50..255 (default 100)
--   resources       : extra "path/with.ext" under /sound (optional)
-----------------------------------------------------
function AN_CJ_RegisterJobFX(job_name, t)
    if not job_name or not t then return end
    local key = string.Trim(string.lower(job_name))
    CARJACK_JOB_FX[key] = t

    if SERVER then
        local function addRes(path)
            if not path or path == "" then return end
            if path:StartWith("sound/") then
                resource.AddFile(path)
            else
                resource.AddFile("sound/" .. path)
            end
        end

        local function addSeq(seq)
            if not seq then return end
            for _, s in ipairs(seq) do addRes((t.base_path or "") .. s) end
        end

        addSeq(t.carjack_success)
        addSeq(t.window_break)
        if t.resources then for _, r in ipairs(t.resources) do addRes(r) end end
    end
end

-----------------------------------------------------
-- Non-repeating random playback
-----------------------------------------------------
if SERVER then
    CreateConVar("carjack_fx_norepeat", "1", FCVAR_ARCHIVE,
        "Avoid repeating the same clip twice in a row per player (0/1)")
end

local _LAST_CLIP = _LAST_CLIP or {} -- [steamid64] = { [eventKey] = "clip.ext" }

if SERVER then
    hook.Add("PlayerDisconnected", "AN_CJ_ClearLastClip", function(ply)
        if IsValid(ply) then _LAST_CLIP[ply:SteamID64()] = nil end
    end)
end

local function _pick_no_repeat(ply, eventKey, list)
    if not istable(list) or #list == 0 then return nil end
    if #list == 1 then return list[1] end
    if SERVER and not GetConVar("carjack_fx_norepeat"):GetBool() then
        return list[math.random(#list)]
    end
    local sid = IsValid(ply) and ply:SteamID64() or "0"
    _LAST_CLIP[sid] = _LAST_CLIP[sid] or {}
    local last = _LAST_CLIP[sid][eventKey]

    local pool = {}
    for _, v in ipairs(list) do
        if v ~= last then table.insert(pool, v) end
    end
    if #pool == 0 then pool = list end
    local choice = pool[math.random(#pool)]
    _LAST_CLIP[sid][eventKey] = choice
    return choice
end

-----------------------------------------------------
-- Playback (server-side EmitSound on veh + player)
-----------------------------------------------------
function AN_CJ_PlayJobRandom(ply, which, veh)
    if not IsValid(ply) then return end
    local fx = AN_CJ_GetFxForPlayer(ply)
    if not fx then return end

    local seq = fx[which]
    if not seq or #seq == 0 then return end

    local vol  = fx.volume or 1.0
    local pit  = fx.pitch  or 100
    local base = fx.base_path or ""

    local choice = _pick_no_repeat(ply, which, seq)
    if not choice then return end
    local path = base .. choice

    if SERVER then
        if IsValid(veh) then veh:EmitSound(path, 90, pit, vol) end
        if IsValid(ply) then ply:EmitSound(path, 90, pit, vol) end
    end
end

--============================================================
-- JOB REGISTRATIONS
--============================================================

-- Dave Miller
-- Folder: garrysmod/sound/catjacktimetwo/davecarjack/
AN_CJ_RegisterJobFX("Dave Miller", {
    base_path = "catjacktimetwo/davecarjack/",
    carjack_success = {
        "davecarjack.ogg",
        "davesnewcar.ogg",
        "timetogofarawalk.ogg",
        "trywalkingolds.ogg"
    },
    volume = 1.0,
    pitch  = 100,
})

-- Thief (TEAM_BADTHIEFS)
-- Folder: garrysmod/sound/catjacktimetwo/maincarjack/
AN_CJ_RegisterJobFX("Thief", {
    base_path = "catjacktimetwo/maincarjack/",
    carjack_success = {
        "ionlywanthecar.ogg",
        "maincarjacksound.ogg",
    },
    volume = 1.0,
    pitch  = 100,
})

-- Henry Miller (unique window-break set)
-- Folder: garrysmod/sound/catjacktimetwo/henreycarjack/
AN_CJ_RegisterJobFX("Henry Miller", {
    base_path = "catjacktimetwo/henreycarjack/",
    carjack_success = {
        "cari8singoodhands.ogg",
        "givehenreythecar.ogg",
        "handitover.ogg",
        "henreywantsjustjusthercar.ogg",
        "henreywantyoutomoveit.ogg"
    },
    window_break = {
        "handitover.ogg",
        "henreywantyoutomoveit.ogg",
        "givehenreythecar.ogg",
        "cari8singoodhands.ogg"
    },
    volume = 1.0,
    pitch  = 100,
})

-- Phone Guy
-- Folder: garrysmod/sound/catjacktimetwo/phoneguycarjack/
AN_CJ_RegisterJobFX("Phone Guy", {
    base_path = "catjacktimetwo/phoneguycarjack/",
    carjack_success = {
        "insurancepal.ogg",
        "hellowuhhellow.ogg",
        "lolxd.ogg",
        "phoneguysnewcar.ogg",
        "phonehuyquirky.ogg",
        "whatareyoudoing.ogg"
    },
    window_break = {
        "hellowuhhellow.ogg",
        "whatareyoudoing.ogg",
        "insurancepal.ogg"
    },
    volume = 1.0,
    pitch  = 100,
})

-- Old Sport
-- Folder: garrysmod/sound/catjacktimetwo/oldsportcarjack/
-- Files from your screenshot:
--   ahomicide.ogg
--   getyourselfajob.ogg
--   goworkatfreddys.ogg
--   jackkennedycommandeeringyourcar.ogg
--   suchaheightfromgod.ogg
AN_CJ_RegisterJobFX("Old Sport", {
    base_path = "catjacktimetwo/oldsportcarjack/",
    carjack_success = {
        "ahomicide.ogg",
        "getyourselfajob.ogg",
        "goworkatfreddys.ogg",
        "jackkennedycommandeeringyourcar.ogg",
        "suchaheightfromgod.ogg",
    },
    -- Optional: uncomment if you want separate window-break lines for Old Sport
    -- window_break = {
    --     "getyourselfajob.ogg",
    --     "goworkatfreddys.ogg",
    -- },
    volume = 1.0,
    pitch  = 100,
})

--============================================================
-- Add more jobs by copying one block above and editing:
--  * Job display name (must match team.GetName(ply:Team()))
--  * base_path and .ogg filenames
--============================================================
