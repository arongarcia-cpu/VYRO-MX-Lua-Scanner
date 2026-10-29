local Shared = _G
pcall(function()
    if type(getgenv)=="function" then Shared = getgenv() end
end)

-- Keep executor aliases in Shared instead of top-level locals.
-- This preserves Wave compatibility without exhausting Luau's 200-register chunk limit.
Shared.__VYRO_EXEC = {
    _G2 = type(getgenv)=="function" and getgenv or function() return _G end,
    _LS = type(loadstring)=="function" and loadstring or function() return nil, "no_loadstring" end,
    _QOT = queueonteleport or queue_on_teleport or (type(syn)=="table" and syn.queue_on_teleport or nil),
    _WF = writefile,
    _RF = readfile,
    _IF = isfile,
    _DF = delfile,
    _SC = setclipboard or toclipboard,
}

if Shared.__VYRO_CORE_RUNTIME and type(Shared.__VYRO_CORE_RUNTIME.stop) == "function" then
    pcall(Shared.__VYRO_CORE_RUNTIME.stop)
end

local Runtime = {
    alive = true,
    connections = {},
    huntToken = nil,
    huntLoopRunning = false,
    teleporting = false,
    preclaiming = false,
    chatScanBusy = false,
}

Shared.__VYRO_CORE_RUNTIME = Runtime

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
if not LP then
    warn("[VYRO] LocalPlayer no disponible")
    return
end

local ULTRA_LITE_TEST = false
local ULTRA_LITE_AGGRESSIVE_UIDS = {
    [11667182309]=true, -- Shiifu_34
    [11667184794]=true, -- Shiifu_35
    [11667216629]=true, -- Shiifu_36
    [11667871928]=true, -- Shiifu_38
    [11667882153]=true, -- Shiifu_39
    [11667897999]=true, -- Shiifu_40
    [11667165475]=true, -- Shiifu_33
    [11667171288]=true, -- Shiifu_32
    [11667161512]=true, -- Shiifu_31
    [11667116681]=true, -- Shiifu_30
    [11667092223]=true, -- Shiifu_29
    [11667096629]=true, -- Shiifu_28
    [11667078774]=true, -- Shiifu_26
}
local ULTRA_LITE_AGGRESSIVE = ULTRA_LITE_AGGRESSIVE_UIDS[LP.UserId] == true

-- Per-account randomization seed.
math.randomseed((LP.UserId * 2654435761) % 2^32)

Shared.__VYRO_JITTER = function(base, percent)
    return base * (1 + (math.random() * 2 - 1) * (percent or 0.2))
end

local CFG = {
    VERSION = "VYRO-PRIME-CORE-4.10.79-MAIN-ASYNC-HOP-EF1-CG2-JG1-C1-" .. tostring(math.random(1000,9999)),
    VERSION_MARKER = "VYRO-PRIME-CORE-4.10.79-MAIN-ASYNC-HOP-EF1-CG2",
    HUNT_SECONDS = 289,
    HUNT_LONG_SECONDS = 289,
    CONTINUOUS_SCAN = false,
    SCANNER_CONTINUOUS_HUNT_SECONDS = 3600,
    TELEPORT_WATCHDOG_SEC = 14.0,
    TELEPORT_WATCHDOG_MIN = 10.0,
    TELEPORT_WATCHDOG_MAX = 40.0,
    TELEPORT_ADAPTIVE_MIN_SAMPLES = 3,
    TELEPORT_MAX_CONSECUTIVE_RETRIES = 3,
    LANDING_CONFIRM_TIMEOUT_SEC = 40,

    -- Fast scanner. It leaves as soon as ClientRenderedAssets stabilizes.
    ASSET_TIMEOUT = Shared.__VYRO_JITTER(2.50, 0.3),
    ASSET_POLL = Shared.__VYRO_JITTER(0.04, 0.25),
    ASSET_STABLE_WINDOW = Shared.__VYRO_JITTER(0.16, 0.3),
    PREMIUM_SCAN_TIMEOUT = Shared.__VYRO_JITTER(1.10, 0.3),
    PREMIUM_READY_TIMEOUT = Shared.__VYRO_JITTER(6.00, 0.2),
    PREMIUM_VISUAL_TIMEOUT = Shared.__VYRO_JITTER(0.90, 0.4),
    PREMIUM_VISUAL_HARD_TIMEOUT = Shared.__VYRO_JITTER(8.00, 0.15),
    PREMIUM_EXPECTED_SLOTS = 25,
    PREMIUM_SCAN_POLL = Shared.__VYRO_JITTER(0.02, 0.3),
    PREMIUM_STABLE_WINDOW = Shared.__VYRO_JITTER(0.05, 0.3),
    CHAT_HINT_TTL = 15,
    CHAT_PROVISIONAL_TTL = 20,
    MIN_SERVER_DWELL = Shared.__VYRO_JITTER(0.16, 0.4),
    TARGET_WATCH_SEC = Shared.__VYRO_JITTER(0.90, 0.3),
    FAST_STATE_POLL = Shared.__VYRO_JITTER(0.10, 0.3),

    SERVER_LIMIT = 100,
    SERVER_PREFETCH_MIN = math.random(10, 14),
    SERVER_FETCH_COOLDOWN = Shared.__VYRO_JITTER(45, 0.25),
    SERVER_NODE_REFRESH_COOLDOWN = Shared.__VYRO_JITTER(4, 0.3),
    SERVER_BACKOFF_BASE = Shared.__VYRO_JITTER(12, 0.3),
    SERVER_BACKOFF_MAX = 75,
    MIN_FREE_SLOTS = math.random(2, 4),

    REEXEC_ARM_ATTEMPTS = 4,
    REEXEC_ARM_RETRY_SEC = Shared.__VYRO_JITTER(0.08, 0.4),
    TELEPORT_RETRY_DELAY = Shared.__VYRO_JITTER(1.25, 0.15),
    FULL_SERVER_RETRY_DELAY = Shared.__VYRO_JITTER(0.75, 0.20),

    CYCLE_POLL = Shared.__VYRO_JITTER(0.35, 0.2),
    CYCLE_DEBOUNCE = Shared.__VYRO_JITTER(8, 0.15),
    STARTUP_CYCLE_BASELINE = Shared.__VYRO_JITTER(6, 0.3),
    DAY_START_CLOCK = 6.0,
    NIGHT_START_CLOCK = 18.0,
    daynight = {
        enabled = true,
        night_start_offset = nil, -- auto-calibrated
        cycle_period = 300,
        night_duration = 10,
        send_interval = 1,
        monitor_interval = 0.5,
        desync_checks = 3,
        console_interval = 5,
        transition_tolerance = 2,
        verify_seconds = 600,
        config_file = "VYRO_DAYNIGHT_CONFIG.json",
        log_file = "VYRO_DAYNIGHT_SYNC.txt",
    },

    STATUS_WRITE_SEC = 1,
    PASSIVE_SCAN_SEC = 8,

    LITE_MODE = true,
    FPS_CAP = math.random(6, 12),
    AUTO_CENSUS = false,

    MAX_UI_EGGS = 32,
    MAX_LOGS = 18,
    CENSUS_MAX_UNMATCHED = 120,
    CENSUS_MAX_EVENT_PROBE = 160,
    CENSUS_MAX_ATTRS = 30,

    BASE_REGION_REFRESH = 20,
    BASE_REGION_MARGIN = 2.5,
    REQUIRE_BASE_MAP_FOR_COMMERCIAL = false,
    REQUIRE_NATURAL5_FOR_COMMERCIAL = true,
    NATURAL_EGGS_PER_BIOME = 5,
    NATURAL_SLOT_MATCH_TOLERANCE = 24.0,
    NEST_CANDIDATE_MAX_DISTANCE = 28.0,
    EGG_VISUAL_EXACT_DISTANCE = 1.75,
    NEST_DIRECT_CONFIDENCE = 0.999,
    NEST_NEAR_CONFIDENCE = 0.985,
    NEST_METADATA_CONFIDENCE = 0.960,
    WORLD_MIN_CONFIDENCE = 0.92,
    MAX_BASE_REGIONS = 12,
    BASE_REGION_MAX_XZ = 360,
    BASE_REGION_MAX_Y = 220,

    QUALITY_POLICY_VERSION = "prime-q1",
    QUALITY_ABSOLUTE_SCALE_KEEP = 3.00,
    QUALITY_MIN_SCORE = 78.0,
    QUALITY_MUTATION_DISCOUNT = 0.10,
    QUALITY_MAX_UPLOAD_PER_SERVER = 6,
    QUALITY_REFRESH_SEC = 30,

    CLOUD_BASE = "https://example.invalid",
    CLOUD_TIMEOUT_SEC = 4,
    NODE_BASE = "http://127.0.0.1:8790",
    NODE_REFRESH_SEC = 30,

    RUNTIME_FILE = "Vyro_Prime_Core_Runtime.lua",
    TEST_ANY_EGG_FILE = "VYRO_TEST_ANY_EGG_ONCE.flag",
    STATE_PREFIX = "Vyro_Core_State_",
    STATUS_PREFIX = "Vyro_Core_Status_",
    SNAPSHOT_PREFIX = "Vyro_Core_Snapshot_",
}

-- Expose the exact running build to the AutoExecute supervisor.
Runtime.version = CFG.VERSION

local STATE_FILE = CFG.STATE_PREFIX .. tostring(LP.UserId) .. ".json"
local STATUS_FILE = CFG.STATUS_PREFIX .. tostring(LP.UserId) .. ".json"
local SNAPSHOT_FILE = CFG.SNAPSHOT_PREFIX .. tostring(LP.UserId) .. ".json"
local CENSUS_FILE = "VYRO_CENSUS_RESULT.txt"
Runtime.JOB_CACHE_FILE = "VYRO_JOBID_CACHE.json"

function Runtime.loadJobCache()
    if type(Shared.__VYRO_EXEC._IF)~="function" or type(Shared.__VYRO_EXEC._RF)~="function" then
        return {lastUpdated=0,servers={}}
    end
    local okExists,exists=pcall(Shared.__VYRO_EXEC._IF,Runtime.JOB_CACHE_FILE)
    if not okExists or exists~=true then return {lastUpdated=0,servers={}} end
    local okRaw,raw=pcall(Shared.__VYRO_EXEC._RF,Runtime.JOB_CACHE_FILE)
    if not okRaw or type(raw)~="string" then return {lastUpdated=0,servers={}} end
    local okJson,data=pcall(function() return HttpService:JSONDecode(raw) end)
    if not okJson or type(data)~="table" or type(data.servers)~="table" then
        return {lastUpdated=0,servers={}}
    end
    return data
end

function Runtime.saveJobCache(data)
    if type(Shared.__VYRO_EXEC._WF)~="function" then return false end
    data=type(data)=="table" and data or {servers={}}
    data.lastUpdated=os.time()
    data.servers=type(data.servers)=="table" and data.servers or {}
    while #data.servers>500 do table.remove(data.servers,1) end
    return pcall(Shared.__VYRO_EXEC._WF,Runtime.JOB_CACHE_FILE,HttpService:JSONEncode(data))
end

function Runtime.cacheJobCandidates(rows)
    local data=Runtime.loadJobCache()
    local byId={}
    for _,row in ipairs(data.servers or {}) do
        local jid=tostring(row.jobId or "")
        if jid~="" then byId[jid]=row end
    end
    for _,row in ipairs(rows or {}) do
        local jid=tostring(row.id or row.job_id or "")
        if jid~="" and jid~=tostring(game.JobId) then
            local cached=byId[jid] or {jobId=jid,lastSeen=0,account=""}
            cached.playing=tonumber(row.playing) or tonumber(cached.playing) or 0
            cached.maxPlayers=tonumber(row.maxPlayers or row.max_players) or tonumber(cached.maxPlayers) or 0
            byId[jid]=cached
        end
    end
    local out={}
    for _,row in pairs(byId) do out[#out+1]=row end
    table.sort(out,function(a,b) return tostring(a.jobId)<tostring(b.jobId) end)
    data.servers=out
    Runtime.saveJobCache(data)
    return data
end

function Runtime.markJobCache(jobId,account)
    local jid=tostring(jobId or "")
    if jid=="" then return false end
    local data=Runtime.loadJobCache()
    local found=false
    for _,row in ipairs(data.servers or {}) do
        if tostring(row.jobId or "")==jid then
            row.lastSeen=os.time()
            row.account=tostring(account or LP.Name)
            found=true
            break
        end
    end
    if not found then
        data.servers[#data.servers+1]={jobId=jid,lastSeen=os.time(),account=tostring(account or LP.Name),bad=false}
    end
    return Runtime.saveJobCache(data)
end

function Runtime.markBadJobCache(jobId,reason)
    local jid=tostring(jobId or "")
    if jid=="" or jid=="random" then return false end
    local data=Runtime.loadJobCache()
    local found=false
    for _,row in ipairs(data.servers or {}) do
        if tostring(row.jobId or "")==jid then
            row.bad=true
            row.badReason=tostring(reason or "teleport_failed")
            row.badAt=os.time()
            found=true
            break
        end
    end
    if not found then
        data.servers[#data.servers+1]={
            jobId=jid,lastSeen=0,account=tostring(LP.Name),
            bad=true,badReason=tostring(reason or "teleport_failed"),badAt=os.time(),
        }
    end
    return Runtime.saveJobCache(data)
end

function Runtime.clearJobCache()
    return Runtime.saveJobCache({lastUpdated=os.time(),servers={}})
end

local KNOWN_BIOMES = {
    -- Legacy numeric keys are retained only for older diagnostic reports.
    -- Runtime 3.7 does NOT treat ClientRenderedAssets owner prefixes as biome IDs.
    ["1372180370"] = "Forest",
    ["2513543462"] = "Light Dark",
    ["3174792497"] = "Snow",
    ["9212288879"] = "Volcano",
    ["11577464277"] = "Titan Temple",
    ["8998603942"] = "Angels",
    ["8401926448"] = "Angels & Demons",

    ["Forest"]="Forest",
    ["Desert"]="Desert",
    ["Prehistoric"]="Prehistoric",
    ["Abyss Ocean"]="Abyss Ocean",
    ["Snow"]="Snow",
    ["Cosmic"]="Cosmic",
    ["Lake"]="Lake",
    ["Volcano"]="Volcano",
    ["Cherry Blossom"]="Cherry Blossom",
    ["Jungle"]="Jungle",
    ["Titan Temple"]="Titan Temple",
    ["Light Dark"]="Light Dark",
    ["Enchanted Forest"]="Enchanted Forest",
    ["The Enchanted Forest"]="Enchanted Forest",
}

local TARGET_KNOWN_IDS = {
    ["11577464277"] = "Titan Temple",
    ["8998603942"] = "Angels",
    ["8401926448"] = "Angels & Demons",
    ["Titan Temple"]="Titan Temple",
    ["Light Dark"]="Angels & Demons",
    ["Enchanted Forest"]="Enchanted Forest",
    ["The Enchanted Forest"]="Enchanted Forest",
}

local PREMIUM_ZONE_SET = {
    ["Cosmic"]=true,
    ["Cherry Blossom"]=true,
    ["Titan Temple"]=true,
    ["Light Dark"]=true,
    ["Angels & Demons"]=true,
    ["Enchanted Forest"]=true,
}


-- EF1: keep the new biome separate from the legacy Forest everywhere.
Runtime.canonicalBiome=function(value)
    local label=tostring(value or ""):gsub("<[^>]*>",""):gsub("[%s_%-]+"," ")
    label=label:match("^%s*(.-)%s*$") or label
    local low=label:lower()
    if low=="enchanted forest" or low=="the enchanted forest" then return "Enchanted Forest" end
    for name,canonical in pairs(KNOWN_BIOMES) do
        if tostring(name):find("%a") and tostring(name):lower()==low then return canonical end
    end
    return label
end

local MUTATION_ALIASES = {
    ["Golden"]="Golden", ["Gold"]="Golden", ["Silver"]="Silver", ["Rainbow"]="Rainbow",
    ["Golden + Silver"]="Golden + Silver",
    ["GreatBloom"]="Spirit Bloom", ["Spirit Bloom"]="Spirit Bloom",
    ["Sakura"]="Bloom", ["Bloom"]="Bloom",
    ["Boss"]="Fractured", ["Fractured"]="Fractured",
    ["Scrambled Mutation"]="Scrambled Mutation", ["Scrambled"]="Scrambled",
    ["Monstrous"]="Parasite", ["Parasite"]="Parasite", ["Parasyte"]="Parasite",
    ["Mutant"]="Mutant", ["Pure"]="Pure",
    ["Cosmic"]="Cosmic", ["Dark"]="Dark", ["Shadow"]="Shadow",
    ["Crystal"]="Crystal", ["Neon"]="Neon",
    ["Enchanted"]="Enchanted", ["Enchanted Mutation"]="Enchanted",
    ["Nitro"]="Nitro", ["Spectral"]="Spectral",
}
local MUTATIONS = {
    "Scrambled Mutation", "Golden + Silver", "Spirit Bloom", "GreatBloom",
    "Fractured", "Monstrous", "Parasite", "Parasyte", "Scrambled",
    "Rainbow", "Golden", "Gold", "Silver", "Mutant", "Sakura", "Bloom", "Boss",
    "Pure", "Cosmic", "Crystal", "Shadow", "Dark", "Neon", "Enchanted Mutation", "Enchanted",
    "Nitro", "Spectral",
}
table.sort(MUTATIONS, function(a,b) return #a > #b end)

Shared.__VYRO_LIVE_MUTATION_ALIASES=Shared.__VYRO_LIVE_MUTATION_ALIASES or {}
Shared.__VYRO_EGGSTATE_MUTATION_VALUES=Shared.__VYRO_EGGSTATE_MUTATION_VALUES or {}

local function literalMutationName(value)
    local s=tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if s=="" then return nil end
    local low=s:lower()
    for alias,canonical in pairs(MUTATION_ALIASES) do
        if tostring(alias):lower()==low then return canonical end
    end
    return nil
end

local function normalizeMutationName(value)
    local s=tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if s=="" then return nil end
    local literal=literalMutationName(s)
    if literal then return literal end
    return Shared.__VYRO_LIVE_MUTATION_ALIASES[s:lower()]
end

local function rememberEggStateMutationValue(value)
    if value==nil then return end
    if type(value)=="table" then
        for k,v in pairs(value) do
            if v==true then rememberEggStateMutationValue(k) else rememberEggStateMutationValue(v) end
        end
        return
    end
    local s=tostring(value):match("^%s*(.-)%s*$") or ""
    if s~="" then Shared.__VYRO_EGGSTATE_MUTATION_VALUES[s]=os.time() end
end

-- RAZOR_REQUIRE_CANARY_BEGIN: avoid initializing game modules before their owner.
Runtime.requireLoadedGameModule=function(module)
    local enumerate=getloadedmodules
    if type(enumerate)~="function" then return nil end
    local ok,loaded=pcall(enumerate)
    if not ok or type(loaded)~="table" then return nil end
    for _,alreadyLoaded in pairs(loaded) do
        if alreadyLoaded==module then
            return require(module)
        end
    end
    return nil
end
-- RAZOR_REQUIRE_CANARY_END

local function refreshLiveMutationAliases()
    local data=ReplicatedStorage:FindFirstChild("Data")
    if not data then return false end
    local aliases=Shared.__VYRO_LIVE_MUTATION_ALIASES
    local function register(alias,canonical)
        local a=tostring(alias or ""):match("^%s*(.-)%s*$") or ""
        if a~="" and canonical then aliases[a:lower()]=canonical end
    end
    local function walk(value,parentKey,seen,depth)
        if type(value)~="table" or (depth or 0)>8 then return end
        seen=seen or {}
        if seen[value] then return end
        seen[value]=true

        local canonical=literalMutationName(parentKey)
        for _,field in ipairs({"DisplayName","Name","_id","Id","ID","MutationId","MutationID","Key","Value"}) do
            if not canonical then canonical=literalMutationName(rawget(value,field)) end
        end
        if canonical then
            register(parentKey,canonical)
            for _,field in ipairs({"DisplayName","Name","_id","Id","ID","MutationId","MutationID","Key","Value"}) do
                register(rawget(value,field),canonical)
            end
        end

        for k,v in pairs(value) do
            if type(v)=="table" then
                walk(v,k,seen,(depth or 0)+1)
            else
                local c=literalMutationName(v) or literalMutationName(k)
                if c then
                    register(k,c)
                    register(v,c)
                end
            end
        end
    end

    local loaded=false
    for _,obj in ipairs(data:GetDescendants()) do
        if obj:IsA("ModuleScript") and tostring(obj.Name):lower():find("mutation",1,true) then
            local ok,result=pcall(Runtime.requireLoadedGameModule,obj)
            if ok and type(result)=="table" then
                walk(result,obj.Name,{},0)
                loaded=true
            end
        end
    end
    return loaded
end
do
    local ok,loaded=pcall(refreshLiveMutationAliases)
    Runtime.mutationAliasesLoaded=(ok and loaded==true)
end

local ANGEL_PETS = {
    ["Light Dove"]=true, ["Winged Lamb"]=true, ["Sacred Moth"]=true,
    ["Holy Peacock"]=true, ["Centaur"]=true, ["Pegasus"]=true,
    ["ArchAngel"]=true,
}
local DEMON_PETS = {
    ["Flame Sprite"]=true, ["Toro"]=true, ["Imp"]=true,
    ["Demon Hound"]=true, ["Gargoyle"]=true, ["RazorFang"]=true,
    ["Skeleton Horse"]=true, ["World Burner"]=true,
}
local TITAN_PETS = {
    ["Nightflame"]=true, ["Gorilla King"]=true, ["Mutant Shark"]=true,
    ["Rhinotaur"]=true, ["Mantaris"]=true, ["Bladehide"]=true,
    ["Crustacia"]=true, ["Spideron"]=true,
}
local PET_CATALOG = {
    ["Ankylosaurus"]={biome="Prehistoric",rarity="Mythic",egg="Ankylosaurus Egg"},
    ["ArchAngel"]={biome="Angels",rarity="Divine",egg="ArchAngel Egg"},
    ["Axolotl"]={biome="Lake",rarity="Legendary",egg="Axolotl Egg"},
    ["Bear"]={biome="Forest",rarity="Epic",egg="Bear Egg"},
    ["Beluga Whale"]={biome="Abyss Ocean",rarity="Cosmic",egg="Beluga Whale Egg"},
    ["Bird"]={biome="Forest",rarity="Uncommon",egg="Bird Egg"},
    ["Bladehide"]={biome="Titan Temple",rarity="Mythic",egg="Bladehide Egg"},
    ["Bronto"]={biome="Prehistoric",rarity="Cosmic",egg="Bronto Egg"},
    ["Brr Brr Patapim"]={biome="Forest",rarity="Legendary",egg="Brr Brr Patapim Egg"},
    ["Burrowing Owl"]={biome="Forest",rarity="Rare",egg="Burrowing Owl Egg"},
    ["Camel"]={biome="Desert",rarity="Rare",egg="Camel Egg"},
    ["Catfish"]={biome="Lake",rarity="Uncommon",egg="Catfish Egg"},
    ["Centapede"]={biome="Cosmic",rarity="Epic",egg="Centapede Egg"},
    ["Centaur"]={biome="Angels",rarity="Secret",egg="Centaur Egg"},
    ["Cerberus"]={biome="Volcano",rarity="Secret",egg="Cerberus Egg"},
    ["Chicken"]={biome="Forest",rarity="Common",egg="Chicken Egg"},
    ["Chillin Chilli"]={biome="Volcano",rarity="Mythic",egg="Chillin Chilli Egg"},
    ["Chimpanzee"]={biome="Jungle",rarity="Rare",egg="Chimpanzee Egg"},
    ["Cosmic Dragon"]={biome="Cosmic",rarity="Secret",egg="Cosmic Dragon Egg"},
    ["Cosmic Gecko"]={biome="Cosmic",rarity="Legendary",egg="Cosmic Gecko Egg"},
    ["Cosmic Gorilla"]={biome="Cosmic",rarity="Mythic",egg="Cosmic Gorilla Egg"},
    ["Cosmic Skeleton Boss"]={biome="Cosmic",rarity="Secret",egg="Cosmic Skeleton Boss Egg"},
    ["Crane"]={biome="Cherry Blossom",rarity="Epic",egg="Crane Egg"},
    ["Crocodile"]={biome="Jungle",rarity="Epic",egg="Crocodile Egg"},
    ["Crustacia"]={biome="Titan Temple",rarity="Legendary",egg="Crustacia Egg"},
    ["Demon Hound"]={biome="Demons",rarity="Cosmic",egg="Demon Hound Egg"},
    ["Dodo"]={biome="Prehistoric",rarity="Rare",egg="Dodo Egg"},
    ["Dog"]={biome="Forest",rarity="Common",egg="Dog Egg"},
    ["Duckling"]={biome="Lake",rarity="Common",egg="Duckling Egg"},
    ["El Maja"]={biome="Abyss Ocean",rarity="Eternal",egg="El Maja Egg"},
    ["Eternal Lunar Dragon"]={biome="Cosmic",rarity="Eternal",egg="Eternal Lunar Dragon Egg"},
    ["Fennec"]={biome="Desert",rarity="Uncommon",egg="Fennec Egg"},
    ["Flame Sprite"]={biome="Demons",rarity="Legendary",egg="Flame Sprite Egg"},
    ["Flaming Bull"]={biome="Volcano",rarity="Legendary",egg="Flaming Bull Egg"},
    ["Fox"]={biome="Forest",rarity="Epic",egg="Fox Egg"},
    ["Frog"]={biome="Lake",rarity="Common",egg="Frog Egg"},
    ["Gargoyle"]={biome="Demons",rarity="Secret",egg="Gargoyle Egg"},
    ["Gorilla"]={biome="Jungle",rarity="Legendary",egg="Gorilla Egg"},
    ["Gorilla King"]={biome="Titan Temple",rarity="Eternal",egg="Gorilla King Egg"},
    ["Holy Peacock"]={biome="Angels",rarity="Cosmic",egg="Holy Peacock Egg"},
    ["Ice Dragon"]={biome="Snow",rarity="Eternal",egg="Ice Dragon Egg"},
    ["Imp"]={biome="Demons",rarity="Cosmic",egg="Imp Egg"},
    ["Jellyfish"]={biome="Angels",rarity="Secret",egg="Pure Jellyfish Egg"},
    ["Jerboa"]={biome="Desert",rarity="Common",egg="Jerboa Egg"},
    ["King Mammoth"]={biome="Snow",rarity="Cosmic",egg="King Mammoth Egg"},
    ["King Snake"]={biome="Jungle",rarity="Secret",egg="King Snake Egg"},
    ["Kitsune"]={biome="Cherry Blossom",rarity="Divine",egg="Kitsune Egg"},
    ["Koi"]={biome="Cherry Blossom",rarity="Cosmic",egg="Koi Egg"},
    ["Kraken"]={biome="Abyss Ocean",rarity="Secret",egg="Kraken Egg"},
    ["La Vacca Saturno Saturnita"]={biome="Cosmic",rarity="Cosmic",egg="La Vacca Saturno Saturnita Egg"},
    ["Lava Dragon"]={biome="Volcano",rarity="Eternal",egg="Lava Dragon Egg"},
    ["Lava Gecko"]={biome="Volcano",rarity="Rare",egg="Lava Gecko Egg"},
    ["Lava Iguana"]={biome="Volcano",rarity="Legendary",egg="Lava Iguana Egg"},
    ["Lava frog"]={biome="Volcano",rarity="Epic",egg="Lava frog Egg"},
    ["Leviathan"]={biome="Lake",rarity="Cosmic",egg="Leviathan Egg"},
    ["Light Dove"]={biome="Angels",rarity="Legendary",egg="Light Dove Egg"},
    ["Lunar Dragon"]={biome="Cosmic",rarity="Eternal",egg="Eternal Lunar Dragon Egg"},
    ["Mammoth"]={biome="Snow",rarity="Mythic",egg="Mammoth Egg"},
    ["Mantaris"]={biome="Titan Temple",rarity="Cosmic",egg="Mantaris Egg"},
    ["Mosasaurus"]={biome="Prehistoric",rarity="Eternal",egg="Mosasaurus Egg"},
    ["Mutant Shark"]={biome="Titan Temple",rarity="Secret",egg="Mutant Shark Egg"},
    ["Nightflame"]={biome="Titan Temple",rarity="Divine",egg="Nightflame Egg"},
    ["Oni Tiger"]={biome="Cherry Blossom",rarity="Eternal",egg="Oni Tiger Egg"},
    ["Orangutini Ananassini"]={biome="Jungle",rarity="Legendary",egg="Orangutini Ananassini Egg"},
    ["Orca"]={biome="Abyss Ocean",rarity="Mythic",egg="Orca Egg"},
    ["Parrotfish"]={biome="Abyss Ocean",rarity="Rare",egg="Parrotfish Egg"},
    ["Pegasus"]={biome="Angels",rarity="Eternal",egg="Pegasus Egg"},
    ["Penguin"]={biome="Snow",rarity="Rare",egg="Penguin Egg"},
    ["Phoenix"]={biome="Volcano",rarity="Eternal",egg="Phoenix Egg"},
    ["Polar Bear"]={biome="Snow",rarity="Legendary",egg="Polar Bear Egg"},
    ["Pterodactyl"]={biome="Prehistoric",rarity="Legendary",egg="Pterodactyl Egg"},
    ["Pure Jellyfish"]={biome="Angels",rarity="Secret",egg="Pure Jellyfish Egg"},
    ["Raccoon"]={biome="Forest",rarity="Rare",egg="Raccoon Egg"},
    ["RazorFang"]={biome="Demons",rarity="Secret",egg="RazorFang Egg"},
    ["Red Panda"]={biome="Cherry Blossom",rarity="Mythic",egg="Red Panda Egg"},
    ["Rhinotaur"]={biome="Titan Temple",rarity="Cosmic",egg="Rhinotaur Egg"},
    ["Royal Sphinx"]={biome="Desert",rarity="Cosmic",egg="Royal Sphinx Egg"},
    ["Sabertooth Tiger"]={biome="Snow",rarity="Mythic",egg="Sabertooth Tiger Egg"},
    ["Sacred Moth"]={biome="Angels",rarity="Cosmic",egg="Sacred Moth Egg"},
    ["Salamander"]={biome="Cherry Blossom",rarity="Legendary",egg="Salamander Egg"},
    ["Sand Spider"]={biome="Desert",rarity="Mythic",egg="Sand Spider Egg"},
    ["Scorpion"]={biome="Desert",rarity="Mythic",egg="Scorpion Egg"},
    ["Shark"]={biome="Abyss Ocean",rarity="Legendary",egg="Shark Egg"},
    ["Skeleton Horse"]={biome="Demons",rarity="Eternal",egg="Skeleton Horse Egg"},
    ["Snake"]={biome="Desert",rarity="Legendary",egg="Snake Egg"},
    ["Snowy Owl"]={biome="Cherry Blossom",rarity="Cosmic",egg="Snowy Owl Egg"},
    ["Spider"]={biome="Jungle",rarity="Mythic",egg="Spider Egg"},
    ["Spideron"]={biome="Titan Temple",rarity="Legendary",egg="Spideron Egg"},
    ["Stag"]={biome="Cherry Blossom",rarity="Secret",egg="Stag Egg"},
    ["Swan"]={biome="Lake",rarity="Epic",egg="Swan Egg"},
    ["Swordfish"]={biome="Abyss Ocean",rarity="Epic",egg="Swordfish Egg"},
    ["TRex"]={biome="Prehistoric",rarity="Secret",egg="TRex Egg"},
    ["Tiger"]={biome="Jungle",rarity="Mythic",egg="Tiger Egg"},
    ["Tob Tobi Tob Tob"]={biome="Desert",rarity="Epic",egg="Tob Tob Tob Tob Egg"},
    ["Tob Tob Tob Tob"]={biome="Desert",rarity="Epic",egg="Tob Tob Tob Tob Egg"},
    ["Toro"]={biome="Demons",rarity="Mythic",egg="Toro Egg"},
    ["Toucan"]={biome="Jungle",rarity="Rare",egg="Toucan Egg"},
    ["Tralaledon"]={biome="Prehistoric",rarity="Secret",egg="Tralaledon Egg"},
    ["Triceratops"]={biome="Prehistoric",rarity="Cosmic",egg="Triceratops Egg"},
    ["Trulimero Trulicina"]={biome="Lake",rarity="Epic",egg="Trulimero Trulicina Egg"},
    ["Turtle"]={biome="Lake",rarity="Rare",egg="Turtle Egg"},
    ["Unicorn"]={biome="Cosmic",rarity="Divine",egg="Unicorn Egg"},
    ["Walrus"]={biome="Snow",rarity="Epic",egg="Walrus Egg"},
    ["Whale Shark"]={biome="Abyss Ocean",rarity="Cosmic",egg="Whale Shark Egg"},
    ["Winged Lamb"]={biome="Angels",rarity="Mythic",egg="Winged Lamb Egg"},
    ["World Burner"]={biome="Demons",rarity="Divine",egg="World Burner Egg"},
    ["Yeti"]={biome="Snow",rarity="Secret",egg="Yeti Egg"},
    ["Riftwing"]={biome="Unknown Update",rarity="Mythic",egg="Riftwing Egg"},
    ["Dreadclaw"]={biome="Unknown Update",rarity="Cosmic",egg="Dreadclaw Egg"},
    ["Ringlord"]={biome="Unknown Update",rarity="Secret",egg="Ringlord Egg"},
    ["Shardwing"]={biome="Unknown Update",rarity="Secret",egg="Shardwing Egg"},
    ["67"]={biome="Unknown Update",rarity="Secret",egg="67 Egg"},
    ["Starry Fox"]={biome="Enchanted Forest",rarity="Secret",egg="Starry Fox Egg"},
    ["Celestial Sunlion"]={biome="Enchanted Forest",rarity="Eternal",egg="Celestial Sunlion Egg"},
    ["Royal Skywhale"]={biome="Enchanted Forest",rarity="Divine",egg="Royal Skywhale Egg"},
}

-- PATCH G/P/Q: learning/validation scope. Retail publication remains TARGET_ONLY.
local PATCH_TARGET_BIOMES = {
    ["Titan Temple"]=true, ["Light Dark"]=true, ["Angels"]=true, ["Demons"]=true,
    ["Angels & Demons"]=true, ["Cosmic"]=true, ["Prehistoric"]=true,
}
local PATCH_TARGET_RARITIES = {
    Mythic=true, Cosmic=true, Secret=true, Eternal=true, Divine=true,
}
local PATCH_HATCH_MIN = {
    ["Crustacia"]=4,["Spideron"]=6,["Bladehide"]=9,["Mantaris"]=17,["Rhinotaur"]=29,
    ["Mutant Shark"]=180,["Gorilla King"]=540,["Nightflame"]=960,
    ["Light Dove"]=5,["Winged Lamb"]=8,["Sacred Moth"]=20,["Holy Peacock"]=25,
    ["Pure Jellyfish"]=240,["Centaur"]=300,["Pegasus"]=600,["ArchAngel"]=1200,
    ["Flame Sprite"]=5,["Toro"]=8,["Imp"]=20,["Demon Hound"]=25,["Gargoyle"]=240,
    ["RazorFang"]=300,["Skeleton Horse"]=600,["World Burner"]=1200,
    ["Centapede"]=2,["Cosmic Gecko"]=4,["Cosmic Gorilla"]=7,
    ["La Vacca Saturno Saturnita"]=13,["Cosmic Dragon"]=180,
    ["Cosmic Skeleton Boss"]=150,["Eternal Lunar Dragon"]=420,["Unicorn"]=720,
    ["Dodo"]=1.5,["Pterodactyl"]=3,["Ankylosaurus"]=5,["Triceratops"]=8,
    ["Bronto"]=11,["Tralaledon"]=150,["TRex"]=180,["Mosasaurus"]=360,
}
for pet,hatchMin in pairs(PATCH_HATCH_MIN) do
    if PET_CATALOG[pet] then PET_CATALOG[pet].hatchMin=hatchMin end
end

local PATCH_PET_ALIASES = {
    ["T-Rex"]="TRex",["Razor Fang"]="RazorFang",["Archangel"]="ArchAngel",
    ["King Gorilla"]="Gorilla King",["Rey Gorila"]="Gorilla King",
    ["Unicornio"]="Unicorn",["Ciervo"]="Stag",["Deer"]="Stag",
    ["Cosmic Fox"]="Starry Fox",
    ["Cosmic Lion"]="Celestial Sunlion",
}
Shared.__VYRO_NORMALIZE_EGG_NAME = function(name)
    if name==nil then return nil end
    local clean=tostring(name):gsub("<.->","")
    clean=clean:gsub("^%s+",""):gsub("%s+$","")
    clean=clean:gsub("^[Ee][Gg][Gg]%s+","")
    clean=clean:gsub("%s+[Ee][Gg][Gg]$","")
    clean=clean:gsub("%s+"," ")
    return clean:lower()
end

Shared.__VYRO_PET_CATALOG_NORMALIZED={}
Shared.__VYRO_REBUILD_PET_NAME_INDEX=function()
    local index={}
    for pet,info in pairs(PET_CATALOG) do
        local petNorm=Shared.__VYRO_NORMALIZE_EGG_NAME(pet)
        local eggNorm=Shared.__VYRO_NORMALIZE_EGG_NAME(info and info.egg)
        if petNorm and petNorm~="" then index[petNorm]={info=info,canonical=pet} end
        if eggNorm and eggNorm~="" then index[eggNorm]={info=info,canonical=pet} end
    end
    for alias,canonical in pairs(PATCH_PET_ALIASES) do
        local info=PET_CATALOG[canonical]
        local aliasNorm=Shared.__VYRO_NORMALIZE_EGG_NAME(alias)
        if info and aliasNorm and aliasNorm~="" then index[aliasNorm]={info=info,canonical=canonical} end
    end
    Shared.__VYRO_PET_CATALOG_NORMALIZED=index
end
Shared.__VYRO_REBUILD_PET_NAME_INDEX()

local function lookupEggInfo(name)
    local clean=tostring(name or ""):gsub("^Golden%s+",""):gsub("^Gold%s+",""):gsub("^Silver%s+","")
    clean=clean:match("^%s*(.-)%s*$") or clean
    local norm=Shared.__VYRO_NORMALIZE_EGG_NAME(clean)
    local hit=norm and Shared.__VYRO_PET_CATALOG_NORMALIZED[norm] or nil
    if hit then return hit.info,hit.canonical end
    return nil,clean
end

local function getBiomeFromLocation(location)
    local loc=Runtime.canonicalBiome(location):lower()
    if loc:find("%f[%a]enchanted forest%f[%A]") then return "Enchanted Forest" end
    if loc:find("titan",1,true) then return "Titan Temple" end
    if loc:find("light",1,true) or loc:find("dark",1,true) or loc:find("angel",1,true) or loc:find("demon",1,true) then return "Light Dark" end
    if loc:find("cosmic",1,true) then return "Cosmic" end
    if loc:find("prehistoric",1,true) or loc:find("dino",1,true) then return "Prehistoric" end
    if loc:find("cherry",1,true) then return "Cherry Blossom" end
    if loc:find("abyss",1,true) or loc:find("ocean",1,true) then return "Abyss Ocean" end
    for biome in pairs(KNOWN_BIOMES) do
        if loc:find(tostring(biome):lower(),1,true) then return tostring(biome) end
    end
    return "Unknown"
end


local IMAGE_REFERENCE_ZONE_PETS = {
    ["Forest"]={"Chicken","Dog","Bird","Burrowing Owl","Raccoon","Bear","Fox","Brr Brr Patapim"},
    ["Lake"]={"Frog","Duckling","Catfish","Turtle","Trulimero Trulicina","Swan","Axolotl","Leviathan"},
    ["Desert"]={"Jerboa","Fennec","Camel","Tob Tob Tob Tob","Snake","Scorpion","Sand Spider","Royal Sphinx"},
    ["Jungle"]={"Toucan","Chimpanzee","Crocodile","Gorilla","Orangutini Ananassini","Spider","Tiger","King Snake"},
    ["Snow"]={"Penguin","Walrus","Polar Bear","Sabertooth Tiger","Mammoth","King Mammoth","Yeti","Ice Dragon"},
    ["Volcano"]={"Lava Gecko","Lava frog","Flaming Bull","Lava Iguana","Chillin Chilli","Cerberus","Phoenix","Lava Dragon"},
    ["Abyss Ocean"]={"Parrotfish","Swordfish","Shark","Orca","Whale Shark","Beluga Whale","Kraken","El Maja"},
    ["Prehistoric"]={"Dodo","Pterodactyl","Ankylosaurus","Triceratops","Bronto","Tralaledon","TRex","Mosasaurus"},
    ["Cosmic"]={"Centapede","Cosmic Gecko","Cosmic Gorilla","La Vacca Saturno Saturnita","Cosmic Dragon","Cosmic Skeleton Boss","Eternal Lunar Dragon","Unicorn"},
    ["Cherry Blossom"]={"Crane","Salamander","Red Panda","Koi","Snowy Owl","Stag","Oni Tiger","Kitsune"},
    ["Titan Temple"]={"Crustacia","Spideron","Bladehide","Mantaris","Rhinotaur","Mutant Shark","Gorilla King","Nightflame"},
    ["Angels"]={"Light Dove","Winged Lamb","Sacred Moth","Holy Peacock","Pure Jellyfish","Centaur","Pegasus","ArchAngel"},
}


local FP = {}

FP.catalog = {
    ["136766116179912,139964663735318,91933382174212"]={key="verified-starry-egg-20261004",pet="Starry Fox",egg="Starry Fox Egg",rarity="Secret",side="Enchanted Forest",biome="Enchanted Forest",asset_key="Cosmic Fox",identity_confidence=0.999,fixed=true},
    ["123062848475827,123062848475827,123062848475827,123062848475827,123062848475827,123062848475827,123062848475827,123062848475827,123062848475827,84553431056109"]={
        key="cosmic-unicorn-v1", pet="Unicorn", egg="Unicorn Egg",
        rarity="Divine", side="Cosmic", identity_confidence=0.999,
    },
    ["113271829732780,124914150801447,134168453921347,137279551475347,90476958232901,92084046762678"]={
        key="titan-nightflame-v1", pet="Nightflame", egg="Nightflame Egg",
        rarity="Divine", side="Titan Temple", identity_confidence=0.999,
    },
    ["102003537836228,102200656171397,102621908072583,102673456168687,106879537207492,122021375633069,123236440820771,125672807606902,126445234180053,139468480570719,74070373623840,78699221458082,85602940683256,87796199724459"]={
        key="enchanted-starry-fox-v1", pet="Starry Fox", egg="Starry Fox Egg",
        rarity="Secret", side="Enchanted Forest", biome="Enchanted Forest",
        asset_key="Cosmic Fox", identity_confidence=0.999, fixed=true,
    },
    ["106168025026381,116443011665599,117679977851578,121262897144401,82288124797180"]={
        key="titan-mantaris-v1", pet="Mantaris", egg="Mantaris Egg",
        rarity="Cosmic", side="Titan Temple", identity_confidence=0.995,
    },
    ["121503805427792,123911194500602,71106146867483,92607953357433,97972468786566"]={
        key="titan-spideron-v1", pet="Spideron", egg="Spideron Egg",
        rarity="Legendary", side="Titan Temple", identity_confidence=0.985,
    },
    ["133766443033676,79718692685424,80652325597335"]={
        key="titan-mutant-shark-v1", pet="Mutant Shark", egg="Mutant Shark Egg",
        rarity="Secret", side="Titan Temple", identity_confidence=0.995,
    },
    ["111156166521303,118162272223907"]={
        key="angel-winged-lamb-v1", pet="Winged Lamb", egg="Winged Lamb Egg",
        rarity="Mythic", side="Angels", identity_confidence=0.985,
    },
    ["118500773831896,130377078822792,71719862501973,98851980224803"]={
        key="angel-sacred-moth-v1", pet="Sacred Moth", egg="Sacred Moth Egg",
        rarity="Cosmic", side="Angels", identity_confidence=0.985,
    },
    ["80771667349618,82150594108441,97952137869085"]={
        key="angel-light-dove-v1", pet="Light Dove", egg="Light Dove Egg",
        rarity="Legendary", side="Angels", identity_confidence=0.970,
    },
    ["100930618149195,106229985197722,96353059287645"]={key="verified-enchanted:Cosmic Lion",pet="Celestial Sunlion",egg="Celestial Sunlion Egg",rarity="Eternal",side="Enchanted Forest",biome="Enchanted Forest",asset_key="Cosmic Lion",identity_confidence=0.999,fixed=true},
    ["104378174606214,113111878613423,122191195170332,128172657504205,134978503209267,136224384895087,73150993887085,78052982115099,78796332628954,84405384012122,86820677378743"]={key="verified-enchanted:Cosmic Lion",pet="Celestial Sunlion",egg="Celestial Sunlion Egg",rarity="Eternal",side="Enchanted Forest",biome="Enchanted Forest",asset_key="Cosmic Lion",identity_confidence=0.999,fixed=true},
    ["124995783922799,136947781078663,83536291600253"]={key="verified-enchanted:Royal Skywhale",pet="Royal Skywhale",egg="Royal Skywhale Egg",rarity="Divine",side="Enchanted Forest",biome="Enchanted Forest",asset_key="Royal Skywhale",identity_confidence=0.999,fixed=true},
    ["100682055834872,100830024649226,104957003295290,105705420927550,109716127243465,114078217807665,78619508886073,83114320942082,84824833881670,90582139896510,90781931686225,93214447227784"]={key="verified-enchanted:Royal Skywhale",pet="Royal Skywhale",egg="Royal Skywhale Egg",rarity="Divine",side="Enchanted Forest",biome="Enchanted Forest",asset_key="Royal Skywhale",identity_confidence=0.999,fixed=true},
}

function FP.stripAssetId(value)
    local s=tostring(value or "")
    return s:match("(%d+)") or ""
end

FP.meshFingerprintCache=setmetatable({}, {__mode="k"})

function FP.fingerprint(model)
    if not model or not model:IsA("Model") then return nil end
    local cached=FP.meshFingerprintCache[model]
    if cached~=nil then return cached or nil end
    local ids={}
    for _,obj in ipairs(model:GetDescendants()) do
        if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") then
            local id=FP.stripAssetId(obj.MeshId)
            if id~="" then ids[#ids+1]=id end
        end
    end
    table.sort(ids)
    local fingerprint=(#ids>0) and table.concat(ids,",") or false
    FP.meshFingerprintCache[model]=fingerprint
    return fingerprint or nil
end

-- Prefer an explicit/visual asset that Roblox can thumbnail. A mesh fingerprint
-- remains the identity signal, but it is not always a valid preview asset.
function FP.previewAssetId(model,fingerprint)
    if model then
        for _,attr in ipairs({"PetIconAssetId","PetImageAssetId","IconAssetId","ThumbnailAssetId","PreviewAssetId","ThumbnailId","AssetId","ImageId","TextureId"}) do
            local ok,value=pcall(function() return model:GetAttribute(attr) end)
            local id=ok and FP.stripAssetId(value) or ""
            if id~="" then return id end
        end
        local ok,desc=pcall(function() return model:GetDescendants() end)
        if ok and type(desc)=="table" then
            for _,obj in ipairs(desc) do
                local candidates={}
                if obj:IsA("MeshPart") then
                    candidates={obj.TextureID,obj.MeshId}
                elseif obj:IsA("SpecialMesh") then
                    candidates={obj.TextureId,obj.MeshId}
                elseif obj:IsA("Decal") or obj:IsA("Texture") then
                    candidates={obj.Texture}
                elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                    candidates={obj.Image}
                end
                for _,value in ipairs(candidates) do
                    local id=FP.stripAssetId(value)
                    if id~="" then return id end
                end
            end
        end
    end
    return fingerprint and tostring(fingerprint):match("^(%d+)") or nil
end


function FP.position(model)
    if not model then return nil end
    if model:IsA("Model") then
        local ok,p=pcall(function() return model:GetPivot().Position end)
        if ok and p then return p end
    end
    if model:IsA("BasePart") then return model.Position end
    local hitbox=model:FindFirstChild("Hitbox",true)
    if hitbox and hitbox:IsA("BasePart") then return hitbox.Position end
    local part=model:FindFirstChildWhichIsA("BasePart",true)
    return part and part.Position or nil
end

function FP.collectVisuals(withFingerprint)
    local out={}
    local includeFingerprint=(withFingerprint~=false)
    local seen={}

    local function scanRoot(root,origin)
        if not root then return end
        for _,obj in ipairs(root:GetChildren()) do
            if obj:IsA("Model") and not seen[obj] then
                local ownerId=nil
                pcall(function() ownerId=obj:GetAttribute("OwnerUserId") end)
                if ownerId==nil then
                    local pos=FP.position(obj)
                    if pos then
                        seen[obj]=true
                        out[#out+1]={
                            model=obj,
                            pos=pos,
                            origin=origin,
                            fingerprint=includeFingerprint and FP.fingerprint(obj) or nil,
                        }
                    end
                end
            end
        end
    end

    -- Preferred authoritative visual root.
    scanRoot(workspace:FindFirstChild("AreaEggSlotsClient"),"AreaEggSlotsClient")

    -- Newer game builds may render live nest models here. These candidates are
    -- accepted only at near-exact nest distance by nearestForSlot below.
    scanRoot(workspace:FindFirstChild("ClientRenderedAssets"),"ClientRenderedAssets")

    return out
end

function FP.exactForSlot(slot,visuals,used)
    local best,bestDist=nil,math.huge
    for _,candidate in ipairs(visuals or {}) do
        local model=candidate.model
        if model and not used[model] then
            local d=(candidate.pos-slot.position).Magnitude
            if d<bestDist then
                best=candidate
                bestDist=d
            end
        end
    end
    if best and bestDist<=CFG.EGG_VISUAL_EXACT_DISTANCE then
        used[best.model]=true
        return best,bestDist
    end
    return nil,bestDist
end

function FP.nearestForSlot(slot,visuals,used,maxDistance)
    local best,bestDist=nil,math.huge
    local broad=tonumber(maxDistance or CFG.NATURAL_SLOT_MATCH_TOLERANCE)
    for _,candidate in ipairs(visuals or {}) do
        local model=candidate.model
        if model and not used[model] then
            local d=(candidate.pos-slot.position).Magnitude
            local limit=broad
            if tostring(candidate.origin or "")=="ClientRenderedAssets" then
                limit=math.max(CFG.EGG_VISUAL_EXACT_DISTANCE,2.75)
            end
            if d<=limit and d<bestDist then
                best=candidate
                bestDist=d
            end
        end
    end
    if best then return best,bestDist end
    return nil,math.huge
end

function FP.countExactMatches(slots,visuals)
    local used={}
    local matched=0
    for _,slot in ipairs(slots or {}) do
        local visual=FP.exactForSlot(slot,visuals,used)
        if visual then matched=matched+1 end
    end
    return matched
end

function FP.lightDarkSide(slot)
    if not slot or tostring(slot.zone)~="Light Dark" then
        return tostring(slot and slot.zone or "")
    end

    local function decodeSide(value)
        local low=tostring(value or ""):lower()
        if low=="" then return nil end
        if low:find("both",1,true) or low:find("merged",1,true) or low:find("angel",1,true) and low:find("demon",1,true) then
            return "Angels & Demons"
        end
        if low:find("light",1,true) or low:find("angel",1,true) then return "Angels" end
        if low:find("dark",1,true) or low:find("demon",1,true) then return "Demons" end
        return nil
    end

    local guard=slot.area and slot.area:FindFirstChild("Guard")
    if guard then
        for _,attrName in ipairs({"SubBiomeGuardId","AreaId","CurrentSide","Winner","Mode"}) do
            local ok,value=pcall(function() return guard:GetAttribute(attrName) end)
            if ok and value~=nil then
                local side=decodeSide(value)
                if side then return side end
            end
        end
    end

    local okFlag,flag=pcall(function()
        return workspace:GetAttribute("LiveEventFlag_LightDarkReveal")
    end)
    if okFlag and flag~=nil then
        if type(flag)=="string" then
            local okJson,data=pcall(function() return HttpService:JSONDecode(flag) end)
            if okJson and type(data)=="table" then
                local side=decodeSide(data.Winner or data.Side or data.Mode)
                if side then return side end
            else
                local side=decodeSide(flag)
                if side then return side end
            end
        else
            local side=decodeSide(flag)
            if side then return side end
        end
    end

    return "Angels & Demons"
end

function FP.infoForSlot(slot,fingerprint)
    if FP.learnedFpBlacklist and FP.learnedFpBlacklist[tostring(fingerprint or "")] then
        return nil
    end
    if tostring(fingerprint or "")==FP.CONFLICT_MUTANT_TRALA_FP then
        return nil
    end
    local info=fingerprint and FP.catalog[fingerprint] or nil
    if not info then return nil end
    local side=FP.lightDarkSide(slot)
    if tostring(slot.zone)=="Light Dark" and info.side~="Angels & Demons" and info.side~=side then
        return nil
    end
    if tostring(slot.zone)=="Titan Temple" and info.side~="Titan Temple" then
        return nil
    end
    return info
end

local TITAN_STRONG = {
    ["Nightflame"]=true, ["Rhinotaur"]=true, ["Mantaris"]=true,
    ["Bladehide"]=true, ["Crustacia"]=true, ["Spideron"]=true,
}

local TARGET_PET_INFO = {
    ["Crustacia"]={rarity="Legendary",side="Titan Temple",egg="Crustacia Egg"},
    ["Spideron"]={rarity="Legendary",side="Titan Temple",egg="Spideron Egg"},
    ["Bladehide"]={rarity="Mythic",side="Titan Temple",egg="Bladehide Egg"},
    ["Mantaris"]={rarity="Cosmic",side="Titan Temple",egg="Mantaris Egg"},
    ["Rhinotaur"]={rarity="Cosmic",side="Titan Temple",egg="Rhinotaur Egg"},
    ["Mutant Shark"]={rarity="Secret",side="Titan Temple",egg="Mutant Shark Egg"},
    ["Gorilla King"]={rarity="Eternal",side="Titan Temple",egg="Gorilla King Egg"},
    ["Nightflame"]={rarity="Divine",side="Titan Temple",egg="Nightflame Egg"},

    ["Light Dove"]={rarity="Legendary",side="Angels",egg="Light Dove Egg"},
    ["Winged Lamb"]={rarity="Mythic",side="Angels",egg="Winged Lamb Egg"},
    ["Sacred Moth"]={rarity="Cosmic",side="Angels",egg="Sacred Moth Egg"},
    ["Holy Peacock"]={rarity="Cosmic",side="Angels",egg="Holy Peacock Egg"},
    ["Pure Jellyfish"]={rarity="Secret",side="Angels",egg="Pure Jellyfish Egg"},
    ["Centaur"]={rarity="Secret",side="Angels",egg="Centaur Egg"},
    ["Pegasus"]={rarity="Eternal",side="Angels",egg="Pegasus Egg"},
    ["ArchAngel"]={rarity="Divine",side="Angels",egg="ArchAngel Egg"},

    ["Flame Sprite"]={rarity="Legendary",side="Demons",egg="Flame Sprite Egg"},
    ["Toro"]={rarity="Mythic",side="Demons",egg="Toro Egg"},
    ["Imp"]={rarity="Cosmic",side="Demons",egg="Imp Egg"},
    ["Demon Hound"]={rarity="Cosmic",side="Demons",egg="Demon Hound Egg"},
    ["Gargoyle"]={rarity="Secret",side="Demons",egg="Gargoyle Egg"},
    ["RazorFang"]={rarity="Secret",side="Demons",egg="RazorFang Egg"},
    ["Skeleton Horse"]={rarity="Eternal",side="Demons",egg="Skeleton Horse Egg"},
    ["World Burner"]={rarity="Divine",side="Demons",egg="World Burner Egg"},
    ["Starry Fox"]={rarity="Secret",side="Enchanted Forest",egg="Starry Fox Egg",pet="Starry Fox",asset_key="Cosmic Fox"},
    ["Cosmic Fox"]={rarity="Secret",side="Enchanted Forest",egg="Starry Fox Egg",pet="Starry Fox",asset_key="Cosmic Fox"},
    ["Celestial Sunlion"]={rarity="Eternal",side="Enchanted Forest",egg="Celestial Sunlion Egg",pet="Celestial Sunlion",asset_key="Cosmic Lion"},
    ["Cosmic Lion"]={rarity="Eternal",side="Enchanted Forest",egg="Celestial Sunlion Egg",pet="Celestial Sunlion",asset_key="Cosmic Lion"},
    ["Royal Skywhale"]={rarity="Divine",side="Enchanted Forest",egg="Royal Skywhale Egg",pet="Royal Skywhale",asset_key="Royal Skywhale"},
    ["Starry Wolf"]={rarity="Secret",side="Enchanted Forest",egg="Starry Fox Egg",pet="Starry Fox",asset_key="Cosmic Fox"},
}

-- Retail target set: ONLY these pets are ever published to Buyer.
-- AUTO-GENERATED by sync_target_catalog.py from VYRO_TARGET_CATALOG.json.
local TARGET_ONLY = {
    ["Unicorn"]={zone="Cosmic",rarity="Divine",side="Cosmic"},
    ["Unicornio"]={zone="Cosmic",rarity="Divine",side="Cosmic"},
    ["Stag"]={zone="Cherry Blossom",rarity="Secret",side="Cherry Blossom"},
    ["Deer"]={zone="Cherry Blossom",rarity="Secret",side="Cherry Blossom"},
    ["Ciervo"]={zone="Cherry Blossom",rarity="Secret",side="Cherry Blossom"},
    ["Oni Tiger"]={zone="Cherry Blossom",rarity="Eternal",side="Cherry Blossom"},
    ["Kitsune"]={zone="Cherry Blossom",rarity="Divine",side="Cherry Blossom"},
    ["Mutant Shark"]={zone="Titan Temple",rarity="Secret",side="Titan Temple"},
    ["Tiburón Mutante"]={zone="Titan Temple",rarity="Secret",side="Titan Temple"},
    ["Tiburon Mutante"]={zone="Titan Temple",rarity="Secret",side="Titan Temple"},
    ["Gorilla King"]={zone="Titan Temple",rarity="Eternal",side="Titan Temple"},
    ["King Gorilla"]={zone="Titan Temple",rarity="Eternal",side="Titan Temple"},
    ["Rey Gorila"]={zone="Titan Temple",rarity="Eternal",side="Titan Temple"},
    ["Nightflame"]={zone="Titan Temple",rarity="Divine",side="Titan Temple"},
    ["Godzilla"]={zone="Titan Temple",rarity="Divine",side="Titan Temple"},
    ["Gotzilla"]={zone="Titan Temple",rarity="Divine",side="Titan Temple"},
    ["Centaur"]={zone="Light Dark",rarity="Secret",side="Angels"},
    ["RazorFang"]={zone="Light Dark",rarity="Secret",side="Demons"},
    ["Razor Fang"]={zone="Light Dark",rarity="Secret",side="Demons"},
    ["Pegasus"]={zone="Light Dark",rarity="Eternal",side="Angels"},
    ["Skeleton Horse"]={zone="Light Dark",rarity="Eternal",side="Demons"},
    ["ArchAngel"]={zone="Light Dark",rarity="Divine",side="Angels"},
    ["Arch Angel"]={zone="Light Dark",rarity="Divine",side="Angels"},
    ["World Burner"]={zone="Light Dark",rarity="Divine",side="Demons"},
    ["Starry Fox"]={zone="Enchanted Forest",rarity="Secret",side="Enchanted Forest"},
    ["Cosmic Fox"]={zone="Enchanted Forest",rarity="Secret",side="Enchanted Forest"},
    ["Celestial Sunlion"]={zone="Enchanted Forest",rarity="Eternal",side="Enchanted Forest"},
    ["Cosmic Lion"]={zone="Enchanted Forest",rarity="Eternal",side="Enchanted Forest"},
    ["Royal Skywhale"]={zone="Enchanted Forest",rarity="Divine",side="Enchanted Forest"},
}
Shared.__VYRO_TARGET_ONLY_NORMALIZED={}
Shared.__VYRO_REBUILD_TARGET_NAME_INDEX=function()
    local index={}
    for pet,info in pairs(TARGET_ONLY) do
        local norm=Shared.__VYRO_NORMALIZE_EGG_NAME(pet)
        if norm and norm~="" and not index[norm] then
            index[norm]={info=info,canonical=pet}
        end
    end
    Shared.__VYRO_TARGET_ONLY_NORMALIZED=index
end
Shared.__VYRO_REBUILD_TARGET_NAME_INDEX()

Shared.__VYRO_LOOKUP_TARGET_ONLY=function(name)
    local norm=Shared.__VYRO_NORMALIZE_EGG_NAME(name)
    local hit=norm and Shared.__VYRO_TARGET_ONLY_NORMALIZED[norm] or nil
    if hit then return hit.info,hit.canonical,norm end
    return nil,nil,norm
end

local ALLOWED_MUTATIONS = {
    Rainbow=true, Golden=true, Silver=true, ["Golden + Silver"]=true,
    ["Spirit Bloom"]=true, Mutant=true, Bloom=true, Pure=true, Fractured=true,
    Parasite=true, Scrambled=true, ["Scrambled Mutation"]=true,
    Cosmic=true, Dark=true, Shadow=true, Crystal=true, Neon=true, Enchanted=true,
    Nitro=true, Spectral=true,
}
local function retailMutations(muts)
    local out,seen={},{}
    for _,m in ipairs(muts or {}) do
        local s=normalizeMutationName(m) or tostring(m or "")
        if ALLOWED_MUTATIONS[s] and not seen[s] then
            seen[s]=true
            out[#out+1]=s
        end
    end
    return out
end

-- Live game-data catalog. Static definitions remain as a safe fallback, but
-- updates can extend the target set directly from Data.Assets/Data.Areas.
local LIVE_ASSET_DIRECTORY = nil
local LIVE_TARGET_KEYS = {}

-- Enchanted Forest live targets are intentionally NOT seeded from target catalog.
-- Only fingerprints already present in the learned/verified FP catalog may identify slots.

local function liveSideFromLabel(value, fallback)
    local low=tostring(value or ""):lower()
    if low:find("mixed",1,true) or (low:find("angel",1,true) and low:find("demon",1,true)) then
        return "Angels & Demons"
    end
    if low=="light" or low:find("angel",1,true) then return "Angels" end
    if low=="dark" or low:find("demon",1,true) then return "Demons" end
    if low:find("titan",1,true) then return "Titan Temple" end
    if low:find("enchanted",1,true) then return "Enchanted Forest" end
    return fallback
end

local function liveRarity(asset)
    if type(asset)~="table" then return "Unknown" end
    local r=asset.Rarity
    if type(r)=="table" then
        return tostring(r.DisplayName or r._id or r.Id or "Unknown")
    end
    return tostring(r or "Unknown")
end

local function livePreviewAssetId(asset)
    if type(asset)~="table" then return nil end
    local preferred={
        "PetIconAssetId","PetImageAssetId","IconAssetId","ThumbnailAssetId","PreviewAssetId",
        "ThumbnailId","ImageId","TextureId","Icon","Image","Thumbnail","Texture","AssetId",
    }
    for _,field in ipairs(preferred) do
        local id=FP.stripAssetId(rawget(asset,field))
        if id~="" then return id end
    end
    local seen={}
    local function walk(value,depth)
        if type(value)~="table" or (depth or 0)>4 or seen[value] then return nil end
        seen[value]=true
        for k,v in pairs(value) do
            local key=tostring(k or ""):lower()
            if type(v)~="table"
                and (key:find("icon",1,true) or key:find("image",1,true)
                    or key:find("thumb",1,true) or key:find("texture",1,true))
            then
                local id=FP.stripAssetId(v)
                if id~="" then return id end
            end
        end
        for _,v in pairs(value) do
            if type(v)=="table" then
                local id=walk(v,(depth or 0)+1)
                if id then return id end
            end
        end
        return nil
    end
    return walk(asset,0)
end

local function registerLiveTarget(assetKey, side)
    if type(LIVE_ASSET_DIRECTORY)~="table" then return end
    local asset=LIVE_ASSET_DIRECTORY[assetKey]
    if type(asset)~="table" then return end
    local display=tostring(asset.DisplayName or asset._id or assetKey or "")
    if display=="" then return end
    -- Enchanted Forest area data can reference unreleased/config-only assets.
    -- Live data is discovery evidence, not retail authorization: only promote
    -- entries already enabled in the generated TARGET_ONLY catalog.
    if tostring(side or "")=="Enchanted Forest" then
        local approved=nil
        if type(Shared.__VYRO_LOOKUP_TARGET_ONLY)=="function" then
            approved=select(1,Shared.__VYRO_LOOKUP_TARGET_ONLY(display))
            if not approved then
                approved=select(1,Shared.__VYRO_LOOKUP_TARGET_ONLY(tostring(assetKey)))
            end
        end
        if not approved then return end
    end
    local egg=type(asset.Egg)=="table" and tostring(asset.Egg.DisplayName or asset.Egg.ModelName or (display.." Egg")) or (display.." Egg")
    local info={
        rarity=liveRarity(asset),
        side=side or "Unknown",
        egg=egg,
        pet=display,
        asset_key=tostring(assetKey),
        preview_asset_id=livePreviewAssetId(asset),
        live=true,
    }
    TARGET_PET_INFO[tostring(assetKey)]=info
    TARGET_PET_INFO[display]=info
    LIVE_TARGET_KEYS[tostring(assetKey)]=info
    LIVE_TARGET_KEYS[display]=info
    if tostring(side or "")=="Enchanted Forest" then
        PET_CATALOG[display]={biome="Enchanted Forest",rarity=info.rarity,egg=info.egg}
        TARGET_ONLY[display]={zone="Enchanted Forest",rarity=info.rarity,side="Enchanted Forest"}
        TARGET_ONLY[tostring(assetKey)]={zone="Enchanted Forest",rarity=info.rarity,side="Enchanted Forest"}
    end
end

local function collectLiveAreaTargets(value, fallbackSide, seen, depth)
    if type(value)~="table" or (depth or 0)>9 then return end
    seen=seen or {}
    if seen[value] then return end
    seen[value]=true

    local localSide=fallbackSide
    for _,field in ipairs({"Id","_id","DisplayName","Name"}) do
        local v=rawget(value,field)
        if type(v)=="string" then localSide=liveSideFromLabel(v,localSide) end
    end

    for k,v in pairs(value) do
        if type(k)=="string" and LIVE_ASSET_DIRECTORY and type(LIVE_ASSET_DIRECTORY[k])=="table" then
            registerLiveTarget(k,localSide)
        end
        if type(v)=="string" and LIVE_ASSET_DIRECTORY and type(LIVE_ASSET_DIRECTORY[v])=="table" then
            registerLiveTarget(v,localSide)
        elseif type(v)=="table" then
            collectLiveAreaTargets(v,localSide,seen,(depth or 0)+1)
        end
    end
end

local function refreshLiveTargetCatalog()
    local data=ReplicatedStorage:FindFirstChild("Data")
    if not data then return false end
    local assetsModule=data:FindFirstChild("Assets")
    local areasModule=data:FindFirstChild("Areas")
    if not assetsModule or not areasModule then return false end

    local okAssets,assets=pcall(Runtime.requireLoadedGameModule,assetsModule)
    local okAreas,areas=pcall(Runtime.requireLoadedGameModule,areasModule)
    if not okAssets or type(assets)~="table" or type(assets.Directory)~="table" then return false end
    if not okAreas or type(areas)~="table" or type(areas.Directory)~="table" then return false end

    LIVE_ASSET_DIRECTORY=assets.Directory
    local titan=areas.Directory["Titan Temple"]
    local lightDark=areas.Directory["Light Dark"]
    local enchanted=areas.Directory["Enchanted Forest"] or areas.Directory["The Enchanted Forest"]
    if type(enchanted)~="table" then
        for areaName,area in pairs(areas.Directory) do
            if Runtime.canonicalBiome(areaName)=="Enchanted Forest" and type(area)=="table" then enchanted=area; break end
        end
    end
    if type(titan)=="table" then collectLiveAreaTargets(titan,"Titan Temple",{},0) end
    if type(lightDark)=="table" then collectLiveAreaTargets(lightDark,"Angels & Demons",{},0) end
    if type(enchanted)=="table" then collectLiveAreaTargets(enchanted,"Enchanted Forest",{},0) end
    if type(Shared.__VYRO_REBUILD_TARGET_NAME_INDEX)=="function" then Shared.__VYRO_REBUILD_TARGET_NAME_INDEX() end
    if type(Shared.__VYRO_REBUILD_PET_NAME_INDEX)=="function" then Shared.__VYRO_REBUILD_PET_NAME_INDEX() end
    Runtime.enchantedCatalogLive=false
    for _,info in pairs(LIVE_TARGET_KEYS) do
        if info.live and info.side=="Enchanted Forest" then Runtime.enchantedCatalogLive=true; break end
    end
    return Runtime.enchantedCatalogLive
end

pcall(refreshLiveTargetCatalog)

local function enchantedCatalogSnapshot()
    local out,seen={},{}
    for key,info in pairs(LIVE_TARGET_KEYS or {}) do
        if type(info)=="table" and tostring(info.side or info.biome or "")=="Enchanted Forest" then
            local pet=tostring(info.pet or key or "")
            if pet~="" and not seen[pet] then
                seen[pet]=true
                out[#out+1]={
                    pet=pet,
                    egg=tostring(info.egg or (pet.." Egg")),
                    rarity=tostring(info.rarity or "Unknown"),
                    asset_key=tostring(info.asset_key or key or ""),
                    preview_asset_id=info.preview_asset_id,
                    catalog_source=info.live and "live_game_data" or "verified_fallback",
                }
            end
        end
    end
    table.sort(out,function(a,b) return tostring(a.pet)<tostring(b.pet) end)
    return out
end

FP.dynamicCatalog = {}
FP.dynamicLoaded = false
FP.dynamicScanned = false
FP.dynamicConflicts = {}
FP.templateAliases = {}
local DYNAMIC_FP_FILE = "VYRO_Dynamic_FP_Catalog.json"

-- Persistent catalog for genuinely new pets learned from trustworthy BillboardGui data.
FP.learnedCatalog = {}
FP.learnedLoaded = false
FP.LEARNED_CATALOG_FILE = "VYRO_CATALOG_LEARNED.json"
FP.CONFLICT_MUTANT_TRALA_FP="133766443033676,79718692685424,80652325597335"
FP.learnedFpBlacklist = {
    ["110983711538857"]=true, -- ambiguous Cosmic shell/shared mesh; never authoritative
    ["no_mesh_id"]=true,
    ["124301723787295,99775630939236"]=true,
    ["128270793496397"]=true,
    ["133766443033676,79718692685424,80652325597335"]=true,
}

local function normalizedTemplateName(value)
    local s=tostring(value or ""):lower()
    s=s:gsub("[%c%p_]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$") or s
    s=s:gsub("%s+egg$",""):gsub("%s+model$",""):gsub("%s+pet$","")
    return s
end

local function rebuildTemplateAliases()
    FP.templateAliases={}

    local function addAlias(candidate,info)
        if not candidate or type(info)~="table" then return end
        local norm=normalizedTemplateName(candidate)
        if norm=="" then return end
        local existing=FP.templateAliases[norm]
        if existing and existing~=info and tostring(existing.pet)~=tostring(info.pet) then
            FP.templateAliases[norm]=false
        elseif existing~=false then
            FP.templateAliases[norm]=info
        end
    end

    -- Full catalog first: current game builds may change mesh ids for any biome.
    for key,c in pairs(PET_CATALOG) do
        local info={
            pet=tostring(key),
            egg=tostring(c.egg or (tostring(key).." Egg")),
            rarity=tostring(c.rarity or "Unknown"),
            side=tostring(c.biome or "Unknown"),
            biome=tostring(c.biome or "Unknown"),
            asset_key=tostring(key),
        }
        for _,candidate in ipairs({key,c.egg}) do addAlias(candidate,info) end
    end

    -- Premium live-directory aliases can be more specific and keep asset_key names.
    for key,info in pairs(TARGET_PET_INFO) do
        for _,candidate in ipairs({key,info.pet,info.egg,info.asset_key}) do
            addAlias(candidate,info)
        end
    end
end
rebuildTemplateAliases()


-- Data modules can arrive after the runtime. Retry without holding scanning or hops.
-- VYRO-ALIAS-RETRY-BOUNDED-20261004: share the existing task; never initialize game modules.
task.spawn(function()
    local attempts=0
    while Runtime.alive
        and (not Runtime.enchantedCatalogLive
            or (not Runtime.mutationAliasesLoaded and attempts<30))
    do
        attempts=attempts+1
        if not Runtime.mutationAliasesLoaded and attempts<=30 then
            local aliasOk,aliasesLoaded=pcall(refreshLiveMutationAliases)
            if aliasOk and aliasesLoaded==true then Runtime.mutationAliasesLoaded=true end
        end
        if not Runtime.enchantedCatalogLive then
            local ok,ready=pcall(refreshLiveTargetCatalog)
            if ok and ready then
                rebuildTemplateAliases()
                FP.dynamicScanned=false
            end
        end
        if Runtime.enchantedCatalogLive
            and (Runtime.mutationAliasesLoaded or attempts>=30)
        then
            break
        end
        task.wait(attempts<30 and 2 or 30)
    end
end)

local function targetInfoForTemplateName(value)
    local norm=normalizedTemplateName(value)
    if norm=="" then return nil end
    local info=FP.templateAliases[norm]
    return type(info)=="table" and info or nil
end

function FP.cleanLearnedText(value)
    local s=tostring(value or ""):gsub("<.->","")
    s=s:match("^%s*(.-)%s*$") or ""
    return s
end

function FP.genericLearnedName(value)
    local s=FP.cleanLearnedText(value)
    local low=s:lower()
    if s=="" or s=="?" or low=="padding" or low=="unknown" or low=="none"
        or low=="egg" or low=="pet" or low=="model" or low=="loading"
    then return true end
    if not s:find("%a") then return true end
    return false
end

function FP.readableBillboardText(root,name)
    if not root then return nil end
    local obj=root:FindFirstChild(name,true)
    if obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
        local text=FP.cleanLearnedText(obj.Text)
        if text~="" and text~="?" and text:lower()~="padding" then return text end
    end
    return nil
end

local function compatibleDynamicInfo(slot,info)
    if type(info)~="table" then return nil end
    local zone=tostring(slot and slot.zone or "")
    local home=tostring(info.biome or info.side or "")
    local side=FP.lightDarkSide(slot)

    if zone=="Light Dark" or zone=="Angels & Demons" then
        if home=="Angels" or home=="Demons" then
            return (side=="Angels & Demons" or side==home) and info or nil
        end
        return (tostring(info.side)=="Angels & Demons") and info or nil
    end

    if home~="" and home~="Unknown" then
        return home==zone and info or nil
    end

    if zone=="Titan Temple" and tostring(info.side)=="Titan Temple" then return info end
    return nil
end

function FP.loadLearnedCatalog()
    if FP.learnedLoaded then return end
    FP.learnedLoaded=true
    if type(Shared.__VYRO_EXEC._IF)~="function" or type(Shared.__VYRO_EXEC._RF)~="function" then return end
    if not Shared.__VYRO_EXEC._IF(FP.LEARNED_CATALOG_FILE) then return end
    local ok,raw=pcall(Shared.__VYRO_EXEC._RF,FP.LEARNED_CATALOG_FILE)
    if not ok or type(raw)~="string" then return end
    local okJson,data=pcall(function() return HttpService:JSONDecode(raw) end)
    if not okJson or type(data)~="table" or type(data.entries)~="table" then return end
    if data.place_id and tostring(data.place_id)~=tostring(game.PlaceId) then return end
    for fp,stored in pairs(data.entries) do
        if type(stored)=="table" and not FP.learnedFpBlacklist[tostring(fp)] and not FP.genericLearnedName(stored.pet) then
            FP.learnedCatalog[tostring(fp)]={
                key=tostring(stored.key or ("auto-learn-new:"..tostring(stored.pet))),
                pet=tostring(stored.pet),
                egg=tostring(stored.egg or (tostring(stored.pet).." Egg")),
                rarity=tostring(stored.rarity or "Unknown"),
                side=tostring(stored.side or stored.biome or "Unknown"),
                biome=tostring(stored.biome or stored.side or "Unknown"),
                identity_confidence=tonumber(stored.identity_confidence) or 0.95,
                source="auto-learn-new",
                odds=tostring(stored.odds or ""),
                learned_at=tonumber(stored.learned_at),
                last_seen_at=tonumber(stored.last_seen_at),
                times_seen=tonumber(stored.times_seen) or 1,
                dynamic=true,
                cached=true,
            }
            if FP.catalog[tostring(fp)]==nil then
                FP.catalog[tostring(fp)]=FP.learnedCatalog[tostring(fp)]
            end
        end
    end
end

function FP.saveLearnedCatalog()
    if type(Shared.__VYRO_EXEC._WF)~="function" then return false end
    local entries={}
    for fp,info in pairs(FP.learnedCatalog) do
        if type(info)=="table" and not FP.learnedFpBlacklist[tostring(fp)] and not FP.dynamicConflicts[tostring(fp)] then
            entries[tostring(fp)]={
                key=info.key,pet=info.pet,egg=info.egg,rarity=info.rarity,
                side=info.side,biome=info.biome,identity_confidence=info.identity_confidence,
                source="auto-learn-new",odds=info.odds,learned_at=info.learned_at,
                last_seen_at=info.last_seen_at,times_seen=info.times_seen,
            }
        end
    end
    return pcall(function()
        Shared.__VYRO_EXEC._WF(FP.LEARNED_CATALOG_FILE,HttpService:JSONEncode({
            version="vyro-learned-v1",
            place_id=tostring(game.PlaceId),
            entries=entries,
        }))
    end)
end

function FP.learnUnknownFromBillboard(model,slot,fingerprint)
    FP.loadLearnedCatalog()
    local fp=tostring(fingerprint or "")
    if fp=="" or FP.learnedFpBlacklist[fp] or FP.dynamicConflicts[fp] then
        return nil,"blacklisted_fingerprint"
    end

    local data=model and model:FindFirstChild("Data",true) or nil
    if not data then return nil,"no_data" end
    local display=FP.readableBillboardText(data,"DisplayName")
    local odds=FP.readableBillboardText(data,"Odds")
    local rarity=FP.readableBillboardText(data,"Rarity")
    if FP.genericLearnedName(display) then return nil,"invalid_display" end
    if not odds or not rarity then return nil,"missing_odds_or_rarity" end
    if fp==FP.CONFLICT_MUTANT_TRALA_FP then return nil,"shared_fingerprint_requires_name" end
    local knownInfo,knownCanonical=lookupEggInfo(display)
    if not knownInfo then return nil,"unknown_pet" end
    display=tostring(knownCanonical or display)
    rarity=tostring(knownInfo.rarity or rarity)

    local existingStatic=FP.catalog[fp]
    if existingStatic and tostring(existingStatic.pet or "")~=tostring(display) then
        return nil,"static_fingerprint_conflict"
    end
    local existingDynamic=FP.dynamicCatalog[fp]
    if existingDynamic and tostring(existingDynamic.pet or "")~=tostring(display) then
        FP.dynamicConflicts[fp]=true
        return nil,"dynamic_fingerprint_conflict"
    end

    local current=FP.learnedCatalog[fp]
    if current and tostring(current.pet or "")~=tostring(display) then
        FP.dynamicConflicts[fp]=true
        FP.learnedCatalog[fp]=nil
        FP.saveLearnedCatalog()
        return nil,"learned_fingerprint_conflict"
    end

    local zone=tostring(slot and slot.zone or "Unknown")
    local side=zone
    local biome=zone
    if zone=="Light Dark" or zone=="Angels & Demons" then
        side=FP.lightDarkSide(slot)
        if side=="Angels" or side=="Demons" then biome=side end
    end
    local now=os.time()
    local eggName=tostring(display)
    if not eggName:lower():match("%segg$") then eggName=eggName.." Egg" end

    local row=current or {
        key="auto-learn-new:"..tostring(display):gsub("%s+","-"):lower(),
        pet=tostring(display),
        egg=eggName,
        rarity=tostring(rarity),
        side=tostring(side),
        biome=tostring(biome),
        identity_confidence=0.95,
        source="auto-learn-new",
        odds=tostring(odds),
        learned_at=now,
        times_seen=0,
        dynamic=true,
        cached=false,
    }
    row.last_seen_at=now
    row.times_seen=(tonumber(row.times_seen) or 0)+1
    row.rarity=tostring(rarity)
    row.odds=tostring(odds)
    row.identity_confidence=0.95
    FP.learnedCatalog[fp]=row
    if FP.catalog[fp]==nil then FP.catalog[fp]=row end
    FP.saveLearnedCatalog()
    return row
end

function FP.learnUnknownFromNearbyBillboard(slot,visuals,fingerprint)
    for _,candidate in ipairs(visuals or {}) do
        if tostring(candidate.origin or "")=="ClientRenderedAssets" and candidate.model and candidate.pos then
            local distance=(candidate.pos-slot.position).Magnitude
            if distance<=math.max(CFG.EGG_VISUAL_EXACT_DISTANCE,2.75) then
                local learned,err=FP.learnUnknownFromBillboard(candidate.model,slot,fingerprint)
                if learned then return learned end
                if err=="blacklisted_fingerprint" or err=="static_fingerprint_conflict"
                    or err=="dynamic_fingerprint_conflict" or err=="learned_fingerprint_conflict"
                then return nil,err end
            end
        end
    end
    return nil,"no_billboard_match"
end

function FP.loadDynamicCatalog()
    if FP.dynamicLoaded then return end
    FP.dynamicLoaded=true
    if type(Shared.__VYRO_EXEC._IF)~="function" or type(Shared.__VYRO_EXEC._RF)~="function" or not Shared.__VYRO_EXEC._IF(DYNAMIC_FP_FILE) then return end
    local ok,raw=pcall(Shared.__VYRO_EXEC._RF,DYNAMIC_FP_FILE)
    if not ok or type(raw)~="string" then return end
    local okJson,data=pcall(function() return HttpService:JSONDecode(raw) end)
    if not okJson or type(data)~="table" or tostring(data.version)~="dynamic-fp-v1" then return end
    if data.place_id and tostring(data.place_id)~=tostring(game.PlaceId) then return end
    if type(data.entries)~="table" then return end

    for fp,stored in pairs(data.entries) do
        if type(stored)=="table" and not FP.learnedFpBlacklist[tostring(fp)] then
            local lookup=tostring(stored.asset_key or stored.pet or "")
            local current=TARGET_PET_INFO[lookup] or TARGET_PET_INFO[tostring(stored.pet or "")]
            if not current then
                local c,canonical=lookupEggInfo(lookup)
                if not c then c,canonical=lookupEggInfo(stored.pet) end
                if c then
                    local canonicalPet=canonical or lookup
                    current={
                        pet=canonicalPet,
                        egg=c.egg,
                        rarity=c.rarity,
                        side=c.biome,
                        biome=c.biome,
                        asset_key=canonicalPet,
                    }
                end
            end
            if current then
                FP.dynamicCatalog[tostring(fp)]={
                    key=tostring(stored.key or ("live-template:"..tostring(current.asset_key or current.pet))),
                    pet=tostring(current.pet or stored.pet or ""),
                    egg=tostring(current.egg or stored.egg or ""),
                    rarity=tostring(current.rarity or stored.rarity or "Unknown"),
                    side=tostring(current.side or stored.side or current.biome or "Unknown"),
                    biome=tostring(current.biome or stored.biome or current.side or stored.side or "Unknown"),
                    asset_key=tostring(current.asset_key or stored.asset_key or ""),
                    identity_confidence=tonumber(stored.identity_confidence) or 0.965,
                    dynamic=true,
                    cached=true,
                    learned_at=tonumber(stored.learned_at),
                    last_seen_at=tonumber(stored.last_seen_at),
                    times_seen=tonumber(stored.times_seen) or 1,
                }
            end
        end
    end
end

function FP.saveDynamicCatalog()
    if type(Shared.__VYRO_EXEC._WF)~="function" then return false end
    local entries={}
    for fp,info in pairs(FP.dynamicCatalog) do
        if type(info)=="table" and not FP.dynamicConflicts[fp] and not FP.learnedFpBlacklist[tostring(fp)] then
            entries[tostring(fp)]={
                key=info.key,pet=info.pet,egg=info.egg,rarity=info.rarity,
                side=info.side,asset_key=info.asset_key,
                identity_confidence=info.identity_confidence,
                learned_at=info.learned_at,last_seen_at=info.last_seen_at,
                times_seen=info.times_seen,
            }
        end
    end
    return pcall(function()
        Shared.__VYRO_EXEC._WF(DYNAMIC_FP_FILE,HttpService:JSONEncode({
            version="dynamic-fp-v1",
            place_id=tostring(game.PlaceId),
            entries=entries,
        }))
    end)
end

function FP.buildDynamicCatalog()
    FP.loadDynamicCatalog()
    if FP.dynamicScanned then return FP.dynamicCatalog end
    FP.dynamicScanned=true
    FP.dynamicConflicts={}

    local function consider(model)
        if not model:IsA("Model") then return end
        local info=nil
        local cursor=model
        for _=1,5 do
            if not cursor or cursor==ReplicatedStorage then break end
            info=targetInfoForTemplateName(cursor.Name)
            if info then break end
            cursor=cursor.Parent
        end
        if not info then return end
        local fp=FP.fingerprint(model)
        if not fp then return end
        local existing=FP.dynamicCatalog[fp]
        if existing and tostring(existing.pet)~=tostring(info.pet) then
            FP.dynamicCatalog[fp]=nil
            FP.dynamicConflicts[fp]=true
            return
        end
        if not FP.dynamicConflicts[fp] then
            FP.dynamicCatalog[fp]={
                key="live-template:"..tostring(info.asset_key or info.pet),
                pet=tostring(info.pet or info.asset_key or ""),
                egg=tostring(info.egg or ((info.pet or info.asset_key or "Unknown").." Egg")),
                rarity=tostring(info.rarity or "Unknown"),
                side=tostring(info.side or info.biome or "Unknown"),
                biome=tostring(info.biome or info.side or "Unknown"),
                asset_key=tostring(info.asset_key or ""),
                identity_confidence=0.965,
                dynamic=true,
                cached=false,
            }
        end
    end

    -- One O(n) traversal, O(1) alias lookup per model. Only exact target/egg
    -- names can enter the catalog, so unknown content remains fail-closed.
    local ok,desc=pcall(function() return ReplicatedStorage:GetDescendants() end)
    if ok and type(desc)=="table" then
        for _,obj in ipairs(desc) do
            if obj:IsA("Model") then consider(obj) end
        end
    end
    FP.saveDynamicCatalog()
    return FP.dynamicCatalog
end

function FP.learnFingerprint(fingerprint,petName,rarity,biome)
    fingerprint=tostring(fingerprint or "")
    if fingerprint=="" or fingerprint=="no_mesh_id" then return false,"no_fingerprint" end
    if FP.learnedFpBlacklist[fingerprint] then return false,"blacklisted_fingerprint" end
    if fingerprint==FP.CONFLICT_MUTANT_TRALA_FP then return false,"shared_fingerprint_requires_name" end
    local catalog,canonical=lookupEggInfo(petName)
    if not catalog then return false,"unknown_pet" end
    local expectedBiome=tostring(catalog.biome or "")
    local observedBiome=tostring(biome or "")
    local compatible=(expectedBiome==observedBiome)
        or (observedBiome=="Light Dark" and (expectedBiome=="Angels" or expectedBiome=="Demons"))
        or (observedBiome=="Angels & Demons" and (expectedBiome=="Angels" or expectedBiome=="Demons"))
    if not compatible then return false,"biome_mismatch" end
    local now=os.time()
    local current=FP.dynamicCatalog[fingerprint]
    if current and tostring(current.pet)~=tostring(canonical) then
        FP.dynamicConflicts[fingerprint]=true
        FP.dynamicCatalog[fingerprint]=nil
        FP.saveDynamicCatalog()
        return false,"fingerprint_conflict"
    end
    FP.dynamicCatalog[fingerprint]=current or {
        key="chat-learned:"..canonical,pet=canonical,egg=catalog.egg or (canonical.." Egg"),
        rarity=rarity or catalog.rarity or "Unknown",side=expectedBiome,biome=expectedBiome,
        asset_key=canonical,identity_confidence=0.95,dynamic=true,cached=false,
        learned_at=now,times_seen=0,
    }
    local row=FP.dynamicCatalog[fingerprint]
    row.last_seen_at=now
    row.times_seen=(tonumber(row.times_seen) or 0)+1
    row.rarity=tostring(catalog.rarity or rarity or row.rarity or "Unknown")
    row.identity_confidence=math.max(tonumber(row.identity_confidence) or 0,0.95)
    FP.saveDynamicCatalog()
    return true,row
end

function FP.dynamicInfoForSlot(slot,fingerprint)
    if not fingerprint then return nil end
    if FP.learnedFpBlacklist[tostring(fingerprint)] then return nil end
    if tostring(fingerprint)==FP.CONFLICT_MUTANT_TRALA_FP then return nil end
    FP.loadDynamicCatalog()
    FP.loadLearnedCatalog()
    local info=compatibleDynamicInfo(slot,FP.dynamicCatalog[fingerprint])
    if info then return info end
    info=compatibleDynamicInfo(slot,FP.learnedCatalog[fingerprint])
    if info then return info end
    if not FP.dynamicScanned then
        FP.buildDynamicCatalog()
        info=compatibleDynamicInfo(slot,FP.dynamicCatalog[fingerprint])
        if info then return info end
        info=compatibleDynamicInfo(slot,FP.learnedCatalog[fingerprint])
    end
    return info
end

pcall(FP.loadLearnedCatalog)

local S = {
    state = "BOOTING",
    stateDetail = "Inicializando",
    mode = "waiting",

    rawEggs = {},
    eggs = {},
    targets = {},
    qualifiedTargets = {},
    skippedQuality = 0,
    qualityReasonCounts = {},
    targetPreview = {},
    uiView = "QUALIFIED",
    excludedBase = 0,
    excludedUncertain = 0,
    baseRegions = {},
    baseRegionsAt = 0,
    baseMapResolved = false,
    baseDiscoverySource = "none",
    baseRegionNames = {},
    exclusionReasons = {},
    learnedWorldSlots = {},
    biomeGroupCounts = {},
    biomeWorldCounts = {},
    natural5LearnedBiomes = 0,
    natural5OverflowExcluded = 0,
    natural5PartialGroups = 0,
    censusLastAt = nil,
    censusUnknownBiomes = {},
    censusUnknownPets = {},
    censusUnknownPrefixes = {},
    censusUnmatchedAssets = 0,
    nestSlotsTotal = 0,
    nestSlotsResolved = 0,
    nestBiomeCounts = {},
    baseRenderedIgnored = 0,
    nestUnresolved = {},
    nestIdentityUnresolved = {},
    eventFlags = {},
    fingerprintKnown = 0,
    fingerprintUnknown = 0,
    staleSideVisuals = 0,
    sharedFingerprintConflicts = 0,
    blacklistedIdentity = 0,
    genericSlotShells = 0,
    noMeshIdentity = 0,
    unknownFingerprints = {},
    unknownFingerprintDetails = {},
    pendingFingerprintCandidates = {},
    newEggSeen = {},
    patchEvents = {},
    chatHint = nil,
    quarantinedEgg = nil,
    quarantineUpdatedAt = nil,
    lightDarkSide = nil,
    visualPresent = 0,

    phase = "?",
    lightingClockTime = nil,
    lightingSampleClock = nil,
    lightingSampleAt = nil,
    lightingRateHoursPerSec = nil,
    dayNightEtaSeconds = nil,
    cyclePeriodHint = nil,
    cycleNightSecondsHint = nil,
    cycleWinner = nil,
    cycleEtaSeconds = nil,
    cycleEtaSource = "learning",
    cycleFingerprint = nil,
    cycleBaselineReadyAt = os.clock() + CFG.STARTUP_CYCLE_BASELINE,
    lastCycleEdgeAt = nil,
    previousCycleEdgeAt = nil,
    lastSignalEdgeAt = nil,
    observedCycleSeconds = nil,
    cycleEdgeCount = 0,
    fleetCycleGeneration = 0,
    fleetCycleEpoch = nil,
    fleetCycleEnd = nil,
    fleetCyclePhase = nil,
    serverSeenTargetUids = {},

    huntEnd = nil,
    huntStartedAt = nil,
    huntStartedClock = nil,
    huntHopsStart = 0,

    visited = {},
    landedJobs = {[tostring(game.JobId)] = true},
    hops = 0,
    serverQueue = {},
    serverFetchNotBefore = 0,
    serverFetchFailures = 0,
    lastServerHttpStatus = nil,

    landedJobId = tostring(game.JobId),
    currentJobId = tostring(game.JobId),
    pendingJobId = nil,
    lastHopAttempt = nil,
    lastHopTarget = nil,
    lastHopAccepted = nil,
    lastLandingConfirmedAt = nil,
    lastLandingConfirmedMs = nil,
    lastLandingConfirmedJob = tostring(game.JobId),
    lastLandingPendingJob = nil,
    silentTeleportFailures = 0,
    reexecArmed = false,
    reexecError = nil,

    scans = 0,
    totalEggsSent = 0,
    lastEggsSent = 0,
    lastRawAccepted = 0,
    lastRawIgnored = 0,
    lastScanMs = nil,
    lastStableWaitMs = nil,
    lastEggCount = 0,
    lastError = nil,
    lastTeleportFailure = nil,
    fullServerFailures = 0,
    pendingStartedMs = nil,
    teleportAvgSec = nil,
    teleportSuccessSamples = 0,
    adaptiveWatchdogSec = CFG.TELEPORT_WATCHDOG_SEC,

    memoryMb = nil,
    instanceCount = nil,
    queueAvailable = false,
    qualityPolicyVersion = CFG.QUALITY_POLICY_VERSION,
    lastCloudStatus = nil,
    lastCloudError = nil,
    lastCloudOkAt = nil,
    cloudUploadMs = nil,
    fastFanoutMs = nil,
    fastAckCount = 0,
    fastAckLast = nil,
    cloudRetryPersisted = false,
    cloudRoute = nil,
    claimLatencyMs = nil,
    claimSource = nil,
    claimScore = nil,
    lastClaimRecentlyScanned = nil,
    claimFresh = 0,
    claimRecent = 0,
    nodeConnected = false,
    lastNodeRefresh = 0,
}

Shared.VYRO_CORE_STATE = S

local ui = {}
local logs = {}

local function nowUnix()
    return os.time()
end

local function nowMs()
    local ok,value=pcall(function() return DateTime.now().UnixTimestampMillis end)
    if ok and tonumber(value) then return tonumber(value) end
    return os.time()*1000
end

-- CYCLE HOP GUARD START
-- One clock window and one completed scan belong to one JobId/token/generation.
-- All teleport paths must recheck this immediately before the Roblox call.
function Runtime.cycleWindow(now)
    local epoch=math.floor((now-290)/300)*300+290
    return math.floor(epoch/300),epoch+11,epoch+300,epoch
end

function Runtime.cycleDayReady()
    local ok,clock=pcall(function() return tonumber(Lighting.ClockTime) end)
    return ok and clock~=nil and clock>=CFG.DAY_START_CLOCK and clock<CFG.NIGHT_START_CLOCK
end

function Runtime.captureCycleHopContext()
    local now=nowUnix()
    local generation=Runtime.cycleWindow(now)
    return {jobId=tostring(game.JobId),token=Runtime.huntToken,generation=generation,
        scanStartedAt=now,dayReady=Runtime.cycleDayReady()}
end

function Runtime.cycleContextValid(context)
    local now=nowUnix()
    local generation,scanStart,endAt=Runtime.cycleWindow(now)
    if not Runtime.alive or S.mode~="hunting" then return false,"not_hunting" end
    if now<scanStart or now>=endAt then return false,"reset_window" end
    if not context or context.token==nil or context.token~=Runtime.huntToken
        or context.jobId~=tostring(game.JobId) or context.generation~=generation then
        return false,"stale_context"
    end
    if not S.huntEnd or now>=S.huntEnd then return false,"hunt_closed" end
    if not Runtime.cycleDayReady() then return false,"server_still_night" end
    return true
end

function Runtime.canCommitHop(context)
    if Shared.VYRO_SCANNER_MODE~=true then return true end
    local valid,why=Runtime.cycleContextValid(context)
    if not valid then return false,why end
    local now=nowUnix()
    local generation,scanStart,endAt=Runtime.cycleWindow(now)
    local proof=Runtime.cycleScanAck
    local proofOk=proof and proof.token==context.token and proof.jobId==context.jobId
        and proof.generation==generation and proof.dayReady
        and (tonumber(proof.scanStartedAt) or 0)>=scanStart
        and (tonumber(proof.ackedAt) or 0)>=proof.scanStartedAt
    if not proofOk then
        local escape=context and context.allowCoordConflictEscape==true and S.coordConflict==true
        local scan=Runtime.cycleScanResult
        local scanOk=escape and scan and scan.token==context.token and scan.jobId==context.jobId
            and scan.generation==generation and scan.dayReady
            and (tonumber(scan.scanStartedAt) or 0)>=scanStart
        if not scanOk then
            return false,"fresh_scan_pending"
        end
    end
    local budget=math.max(14,math.min(32,((tonumber(S.teleportAvgSec) or 16)*1.15)+6))
    if math.min(endAt,tonumber(S.huntEnd) or endAt)-now<=budget then
        return false,"final_hold"
    end
    return true
end
-- CYCLE HOP GUARD END


local function adaptiveTeleportWatchdog()
    local samples=tonumber(S.teleportSuccessSamples) or 0
    local avg=tonumber(S.teleportAvgSec)
    if samples<CFG.TELEPORT_ADAPTIVE_MIN_SAMPLES or not avg or avg<=0 then
        S.adaptiveWatchdogSec=CFG.TELEPORT_WATCHDOG_SEC
        return CFG.TELEPORT_WATCHDOG_SEC
    end
    local target=(avg*2.0)+1.0
    target=math.max(CFG.TELEPORT_WATCHDOG_MIN,math.min(CFG.TELEPORT_WATCHDOG_MAX,target))
    S.adaptiveWatchdogSec=math.floor(target*100+0.5)/100
    return S.adaptiveWatchdogSec
end

local function finite(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function countKeys(t)
    local n = 0
    for _,v in pairs(t or {}) do if v then n = n + 1 end end
    return n
end

local function track(c)
    Runtime.connections[#Runtime.connections+1] = c
    return c
end

local function disconnectAll()
    for _,c in ipairs(Runtime.connections) do
        pcall(function() c:Disconnect() end)
    end
    Runtime.connections = {}
end

local function setState(state, detail)
    S.state = tostring(state or "UNKNOWN")
    S.stateDetail = tostring(detail or "")
end

local function logLine(text)
    local line = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(text)
    logs[#logs+1] = line
    while #logs > CFG.MAX_LOGS do table.remove(logs,1) end
    print("[VYRO] " .. tostring(text))
    if ui.logText then
        ui.logText.Text = table.concat(logs, "\n")
    end
end

local function readMemory()
    pcall(function()
        S.memoryMb = math.floor(Stats:GetTotalMemoryUsageMb()*10+0.5)/10
    end)
    pcall(function()
        S.instanceCount = Stats.InstanceCount
    end)
end

local function getRequestFn()
    if type(request)=="function" then return request end
    if type(http_request)=="function" then return http_request end
    if type(syn)=="table" and type(syn.request)=="function" then return syn.request end
    if type(http)=="table" and type(http.request)=="function" then return http.request end
    return nil
end

local function requestJson(method,url,body,headers)
    local req=getRequestFn()
    if not req then return nil,"request_unavailable",nil end
    local h={ ["Accept"]="application/json" }
    for k,v in pairs(headers or {}) do h[k]=v end
    local spec={Url=url,Method=method or "GET",Headers=h}
    if body~=nil then
        h["Content-Type"]="application/json"
        spec.Body=type(body)=="string" and body or HttpService:JSONEncode(body)
    end
    local ok,res=pcall(req,spec)
    if not ok then return nil,tostring(res),nil end
    if type(res)~="table" then return nil,"invalid_response",nil end
    local status=tonumber(res.StatusCode or res.Status)
    local raw=tostring(res.Body or "")
    if not status or status<200 or status>=300 then return nil,"HTTP "..tostring(status),status end
    if raw=="" then return {},nil,status end
    local decodedOk,data=pcall(function() return HttpService:JSONDecode(raw) end)
    if not decodedOk then return nil,"invalid_json",status end
    return data,nil,status
end

local function localConfig()
    local cfg={}
    if type(Shared.__VYRO_EXEC._IF)=="function" and type(Shared.__VYRO_EXEC._RF)=="function" then
        pcall(function()
            if Shared.__VYRO_EXEC._IF("Vyro_Prime_Config.json") then
                local raw=HttpService:JSONDecode(Shared.__VYRO_EXEC._RF("Vyro_Prime_Config.json"))
                if type(raw)=="table" then cfg=raw end
            end
        end)
    end
    return cfg
end

local LOCAL_CFG=localConfig()
local CLOUD_BASE=tostring(Shared.VYRO_VPS_URL or LOCAL_CFG.vps_url or CFG.CLOUD_BASE)
local CLOUD_KEY=Shared.VYRO_VPS_API_KEY or LOCAL_CFG.vps_api_key
local NODE_BASE=tostring(Shared.VYRO_NODE_URL or LOCAL_CFG.node_url or CFG.NODE_BASE)
local NODE_KEY=Shared.VYRO_COORD_KEY or LOCAL_CFG.node_key or ""
local MULTI_ACCOUNT=(Shared.VYRO_MULTI_ACCOUNT==true) or (LOCAL_CFG.multi_account==true)

local function nodeHeaders()
    local h={}
    if NODE_KEY~="" then h["X-Vyro-Node-Key"]=tostring(NODE_KEY) end
    return h
end

local function refreshNodeConfig(force)
    if not force and os.clock()-(S.lastNodeRefresh or 0)<CFG.NODE_REFRESH_SEC then return S.nodeConnected end
    S.lastNodeRefresh=os.clock()
    local data,err=requestJson("GET",NODE_BASE.."/v1/config",nil,nodeHeaders())
    if type(data)=="table" then
        S.nodeConnected=true
        if data.multi_account==true then MULTI_ACCOUNT=true end
        if type(data.quality_policy)=="table" then Shared.VYRO_QUALITY_POLICY=data.quality_policy end
        if type(data.runtime_version)=="string" then S.nodeRuntimeVersion=data.runtime_version end
        return true
    end
    S.nodeConnected=false
    S.lastNodeError=tostring(err)
    return false
end

local function formatSeconds(seconds)
    local n = tonumber(seconds)
    if not n or n < 0 then return "--:--" end
    n = math.floor(n+0.5)
    return string.format("%02d:%02d", math.floor(n/60), n%60)
end

local function huntRemaining()
    if S.mode ~= "hunting" or not S.huntEnd then return "--:--" end
    return formatSeconds(math.max(0, S.huntEnd-nowUnix()))
end

local function serversPerMinute()
    if not S.huntStartedAt then return 0 end
    local elapsed = math.max(1, nowUnix()-(tonumber(S.huntStartedAt) or nowUnix()))
    local completed = math.max(0,(tonumber(S.hops) or 0)-(tonumber(S.huntHopsStart) or 0))
    return (completed/elapsed)*60
end

local function stripRichText(text)
    return tostring(text or ""):gsub("<[^>]+>", "")
end

local function readValueObject(obj)
    if not obj then return nil end
    local ok, value = pcall(function()
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            return obj.Text
        end
        return obj.Value
    end)
    if ok and value ~= nil and tostring(value) ~= "" then
        return tostring(value)
    end
    return nil
end

local function readDisplayName(egg)
    local data = egg:FindFirstChild("Data")
    if data then
        for _,key in ipairs({"DisplayName","PetName","EggName","Name"}) do
            local v = readValueObject(data:FindFirstChild(key))
            if v then return v end
        end
    end

    local recursive = egg:FindFirstChild("DisplayName", true)
    local v = readValueObject(recursive)
    if v then return v end

    for _,attr in ipairs({"DisplayName","PetName","EggName"}) do
        local ok,val = pcall(function() return egg:GetAttribute(attr) end)
        if ok and val ~= nil and tostring(val) ~= "" then return tostring(val) end
    end

    return ""
end

local function parseDisplayName(text)
    local clean = stripRichText(text):gsub("^%s+",""):gsub("%s+$","")
    if clean == "" then return {}, "?" end

    -- Exact catalog/target names always win over mutation-prefix parsing.
    -- Important examples:
    --   Mutant Shark
    --   Pure Jellyfish
    --   Eternal Lunar Dragon
    -- Exact-name guard must NOT use lookupEggInfo(), because that helper
    -- intentionally strips Silver/Golden for catalog lookup and would erase
    -- a real mutation before prefix parsing gets a chance to see it.
    local exactNorm=Shared.__VYRO_NORMALIZE_EGG_NAME(clean)
    local exactHit=exactNorm and Shared.__VYRO_PET_CATALOG_NORMALIZED[exactNorm] or nil
    local exactCatalog=exactHit and exactHit.info or nil
    local exactCanonical=exactHit and exactHit.canonical or nil
    local exactTarget,exactTargetCanonical=Shared.__VYRO_LOOKUP_TARGET_ONLY(clean)
    if exactCatalog or exactTarget or TARGET_PET_INFO[clean] then
        return {}, exactTargetCanonical or exactCanonical or clean
    end

    local muts = {}
    local rest = clean

    while true do
        -- After stripping a real mutation, stop if the remainder is itself
        -- the exact canonical name of a pet.
        local restCatalog=select(1,lookupEggInfo(rest))
        local restTarget=select(1,Shared.__VYRO_LOOKUP_TARGET_ONLY(rest))
        if restCatalog or restTarget or TARGET_PET_INFO[rest] then
            break
        end

        local found = false
        for _,mutation in ipairs(MUTATIONS) do
            if rest:sub(1,#mutation):lower() == mutation:lower() then
                local after = rest:sub(#mutation+1)
                if after == "" or after:sub(1,1) == " " then
                    muts[#muts+1] = mutation
                    if after:sub(1,3) == " + " then
                        rest = after:sub(4)
                    elseif after:sub(1,1) == " " then
                        rest = after:sub(2)
                    else
                        rest = ""
                    end
                    found = true
                    break
                end
            end
        end
        if not found then break end
    end

    return muts, (rest ~= "" and rest or "?")
end

local function getScale(egg)
    if egg:IsA("Model") then
        local ok,v = pcall(function() return egg:GetScale() end)
        if ok then
            local n = finite(v)
            if n and n > 0 then
                return math.floor(n*100+0.5)/100, "Model:GetScale", "egg_visual_model_scale"
            end
        end
    end

    -- Last-resort visual estimate. Keep this explicitly separate from Roblox
    -- Model:GetScale so the Node Agent never treats a geometric ratio as exact.
    local part = egg:FindFirstChildWhichIsA("BasePart",true)
    if part then
        local y = finite(part.Size.Y)
        if y and y > 0 then
            return math.floor((y/10.278)*100+0.5)/100, "BasePartY", "egg_visual_size_ratio"
        end
    end

    return nil, "unknown", "unknown"
end

local BASE_CONTAINER_NAMES = {
    plots=true,
    bases=true,
    playerplots=true,
    playerbases=true,
    player_bases=true,
}

local OWNER_KEYS = {
    owner=true,
    ownerid=true,
    owneruserid=true,
    userid=true,
    claimedby=true,
    claimed_by=true,
    plotowner=true,
    baseowner=true,
}

local PLACED_KEYS = {
    placed=true,
    isplaced=true,
    placedinbase=true,
    storedinbase=true,
    inbase=true,
}

local function lower(value)
    return tostring(value or ""):lower()
end

local function normalizedKey(value)
    return lower(value):gsub("[%s_%-]","")
end

local function objectFullName(obj)
    local ok,v=pcall(function() return obj:GetFullName() end)
    return ok and tostring(v) or tostring(obj.Name)
end

local function markerValueActive(value)
    if value==nil then return false end
    if type(value)=="boolean" then return value end
    local s=lower(value)
    return s~="" and s~="0" and s~="false" and s~="nil" and s~="none" and s~="unclaimed"
end

local function explicitMarker(obj)
    if not obj then return false,nil end
    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if ok and type(attrs)=="table" then
        for key,value in pairs(attrs) do
            local n=normalizedKey(key)
            if OWNER_KEYS[n] and markerValueActive(value) then
                return true,"owner_attr:"..tostring(key)
            end
            if PLACED_KEYS[n] and markerValueActive(value) then
                return true,"placed_attr:"..tostring(key)
            end
        end
    end

    for _,child in ipairs(obj:GetChildren()) do
        if child:IsA("ValueBase") then
            local n=normalizedKey(child.Name)
            if OWNER_KEYS[n] or PLACED_KEYS[n] then
                local okValue,value=pcall(function() return child.Value end)
                if okValue and markerValueActive(value) then
                    return true,"value:"..tostring(child.Name)
                end
            end
        end
    end
    return false,nil
end

local function placementMarkerOnly(obj)
    if not obj then return false,nil end

    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if ok and type(attrs)=="table" then
        for key,value in pairs(attrs) do
            local n=normalizedKey(key)
            if PLACED_KEYS[n] and markerValueActive(value) then
                return true,"placed_attr:"..tostring(key)
            end
        end
    end

    for _,child in ipairs(obj:GetChildren()) do
        if child:IsA("ValueBase") then
            local n=normalizedKey(child.Name)
            if PLACED_KEYS[n] then
                local okValue,value=pcall(function() return child.Value end)
                if okValue and markerValueActive(value) then
                    return true,"placed_value:"..tostring(child.Name)
                end
            end
        end
    end
    return false,nil
end

local function ownerMetadataOnly(obj)
    if not obj then return false,nil end
    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if ok and type(attrs)=="table" then
        for key,value in pairs(attrs) do
            local n=normalizedKey(key)
            if OWNER_KEYS[n] and markerValueActive(value) then
                return true,"owner_metadata:"..tostring(key)
            end
        end
    end
    for _,child in ipairs(obj:GetChildren()) do
        if child:IsA("ValueBase") then
            local n=normalizedKey(child.Name)
            if OWNER_KEYS[n] then
                local okValue,value=pcall(function() return child.Value end)
                if okValue and markerValueActive(value) then
                    return true,"owner_metadata_value:"..tostring(child.Name)
                end
            end
        end
    end
    return false,nil
end

local function eggPlacementMarker(egg)
    -- OwnerUserId/Owner metadata exists on ordinary world eggs in this game.
    -- It is diagnostic only. Only explicit placed/stored flags can exclude
    -- an egg without consulting the actual plot geometry.
    local hit,reason=placementMarkerOnly(egg)
    if hit then return true,reason end

    local data=egg:FindFirstChild("Data")
    if data then
        local h,r=placementMarkerOnly(data)
        if h then return true,r end
    end

    for _,obj in ipairs(egg:GetChildren()) do
        if obj~=data then
            local h,r=placementMarkerOnly(obj)
            if h then return true,r end
        end
    end
    return false,nil
end

local function eggOwnerMetadata(egg)
    local hit,reason=ownerMetadataOnly(egg)
    if hit then return true,reason end

    local data=egg:FindFirstChild("Data")
    if data then
        local h,r=ownerMetadataOnly(data)
        if h then return true,r end
    end

    for _,obj in ipairs(egg:GetChildren()) do
        if obj~=data then
            local h,r=ownerMetadataOnly(obj)
            if h then return true,r end
        end
    end
    return false,nil
end

local function regionFromObject(obj)
    if obj:IsA("BasePart") then
        return {cf=obj.CFrame,size=obj.Size,name=objectFullName(obj)}
    end
    if obj:IsA("Model") then
        local ok,cf,size=pcall(function()
            local a,b=obj:GetBoundingBox()
            return a,b
        end)
        if ok and cf and size and size.Magnitude>1 then
            return {cf=cf,size=size,name=objectFullName(obj)}
        end
    end
    return nil
end

local function plausibleBaseRegion(region)
    if not region or not region.size then return false end
    local sx,sy,sz=math.abs(region.size.X),math.abs(region.size.Y),math.abs(region.size.Z)
    local maxXZ=math.max(sx,sz)
    local minXZ=math.min(sx,sz)
    if minXZ<3 or maxXZ<8 then return false end
    if maxXZ>CFG.BASE_REGION_MAX_XZ or sy>CFG.BASE_REGION_MAX_Y then return false end
    return true
end

local function findBaseContainers()
    local containers,seen={},{}

    local function add(obj)
        if not obj then return end
        local key=objectFullName(obj)
        if not seen[key] then
            containers[#containers+1]=obj
            seen[key]=true
        end
    end

    for _,obj in ipairs(workspace:GetChildren()) do
        if BASE_CONTAINER_NAMES[lower(obj.Name)] then add(obj) end
    end

    local objects=workspace:FindFirstChild("__OBJECTS")
    if objects then
        for _,obj in ipairs(objects:GetChildren()) do
            if BASE_CONTAINER_NAMES[lower(obj.Name)] then add(obj) end
        end
    end

    -- Exact container names only. Do not use substring matches such as Home/Base.
    if #containers==0 then
        for _,obj in ipairs(workspace:GetDescendants()) do
            if (obj:IsA("Folder") or obj:IsA("Model")) and BASE_CONTAINER_NAMES[lower(obj.Name)] then
                add(obj)
                if #containers>=4 then break end
            end
        end
    end

    return containers
end

local function discoverBaseRegions(force)
    if not force and os.clock()-(S.baseRegionsAt or 0)<CFG.BASE_REGION_REFRESH then
        return S.baseRegions or {}
    end

    S.baseRegionsAt=os.clock()
    local regions,seen={},{}
    local source="none"
    local containers=findBaseContainers()

    local function addRegion(obj,label)
        if #regions>=CFG.MAX_BASE_REGIONS then return end
        if not obj or not (obj:IsA("Model") or obj:IsA("BasePart")) then return end
        local region=regionFromObject(obj)
        if not plausibleBaseRegion(region) then return end
        local key=objectFullName(obj)
        if seen[key] then return end
        region.name=label or key
        regions[#regions+1]=region
        seen[key]=true
    end

    -- One region per direct plot/base child, never every nested part.
    for _,container in ipairs(containers) do
        source="container:"..objectFullName(container)
        for _,child in ipairs(container:GetChildren()) do
            if child:IsA("Model") or child:IsA("BasePart") then
                addRegion(child,objectFullName(child))
            elseif child:IsA("Folder") then
                -- Some experiences keep plot models one folder deeper.
                for _,grand in ipairs(child:GetChildren()) do
                    if grand:IsA("Model") or grand:IsA("BasePart") then
                        addRegion(grand,objectFullName(grand))
                    end
                end
            end
        end
        if #regions>0 then break end
    end

    -- Fallback: explicit owner-marked MODELS only, with plausible size.
    if #regions==0 then
        source="owner_fallback"
        local rendered=workspace:FindFirstChild("ClientRenderedAssets")
        for _,obj in ipairs(workspace:GetDescendants()) do
            if #regions>=CFG.MAX_BASE_REGIONS then break end
            if obj:IsA("Model") and (not rendered or not obj:IsDescendantOf(rendered)) then
                local owned=select(1,explicitMarker(obj))
                if owned then addRegion(obj,objectFullName(obj)) end
            end
        end
    end

    local resolved=(#regions>0 and #regions<=CFG.MAX_BASE_REGIONS)
    if not resolved then regions={} end

    S.baseRegions=regions
    S.baseMapResolved=resolved
    S.baseDiscoverySource=source
    S.baseRegionNames={}
    S.baseRegionSizes={}
    for i,region in ipairs(regions) do
        if i>8 then break end
        S.baseRegionNames[#S.baseRegionNames+1]=tostring(region.name)
        S.baseRegionSizes[#S.baseRegionSizes+1]=string.format(
            "%.1fx%.1fx%.1f",
            math.abs(region.size.X),
            math.abs(region.size.Y),
            math.abs(region.size.Z)
        )
    end
    return regions
end

local function eggPosition(egg)
    if egg:IsA("Model") then
        local ok,cf=pcall(function() return egg:GetPivot() end)
        if ok and cf then return cf.Position end
    end
    local part=egg:FindFirstChildWhichIsA("BasePart",true)
    return part and part.Position or nil
end

local function pointInsideRegion(position,region)
    local localPos=region.cf:PointToObjectSpace(position)
    local half=region.size*0.5 + Vector3.new(CFG.BASE_REGION_MARGIN,CFG.BASE_REGION_MARGIN,CFG.BASE_REGION_MARGIN)
    return math.abs(localPos.X)<=half.X and math.abs(localPos.Y)<=half.Y and math.abs(localPos.Z)<=half.Z
end

local function classifyWorldLocation(egg,biomeId)
    -- 3.3: plot bounding boxes are diagnostic only. They overlap natural map
    -- spawn lanes in this experience and cannot be used as a base filter.
    local placed,placedReason=eggPlacementMarker(egg)
    if placed then
        return false,1.0,"placement:"..tostring(placedReason)
    end

    local pos=eggPosition(egg)
    if not pos then return false,0.0,"no_position" end

    return true,0.70,"natural5_unverified"
end

local function vecToTable(v)
    return {x=v.X,y=v.Y,z=v.Z}
end

local function tableToVec(t)
    if type(t)~="table" then return nil end
    local x,y,z=tonumber(t.x),tonumber(t.y),tonumber(t.z)
    if not x or not y or not z then return nil end
    return Vector3.new(x,y,z)
end

local function positionDistance(entry,slot)
    local a=entry and entry._position
    local b=tableToVec(slot)
    if not a or not b then return math.huge end
    return (a-b).Magnitude
end

local function learnNaturalSlots(biomeId,entries)
    if #entries~=CFG.NATURAL_EGGS_PER_BIOME then return false end
    local slots={}
    for _,entry in ipairs(entries) do
        if not entry._position then return false end
        slots[#slots+1]=vecToTable(entry._position)
    end
    S.learnedWorldSlots[tostring(biomeId)]=slots
    return true
end

local function matchLearnedNaturalSlots(biomeId,entries)
    local slots=S.learnedWorldSlots[tostring(biomeId)]
    if type(slots)~="table" or #slots~=CFG.NATURAL_EGGS_PER_BIOME then
        return nil
    end

    local chosen={}
    local used={}
    local maxDistance=0

    for _,slot in ipairs(slots) do
        local bestIndex,bestDistance=nil,math.huge
        for index,entry in ipairs(entries) do
            if not used[index] then
                local d=positionDistance(entry,slot)
                if d<bestDistance then
                    bestIndex,bestDistance=index,d
                end
            end
        end

        if not bestIndex or bestDistance>CFG.NATURAL_SLOT_MATCH_TOLERANCE then
            return nil
        end

        used[bestIndex]=true
        chosen[#chosen+1]=entries[bestIndex]
        if bestDistance>maxDistance then maxDistance=bestDistance end
    end

    return chosen,maxDistance
end

local function selectNaturalFive(rawEntries)
    local groups={}
    for _,entry in ipairs(rawEntries or {}) do
        local id=tostring(entry.biomeId or "")
        groups[id]=groups[id] or {}
        groups[id][#groups[id]+1]=entry
    end

    local world={}
    local counts={}
    local worldCounts={}
    local learned=0
    local overflow=0
    local partial=0

    for id,entries in pairs(groups) do
        counts[id]=#entries

        -- Explicit placement flags still win even before the natural-five rule.
        local candidates={}
        for _,entry in ipairs(entries) do
            if entry._explicitPlaced then
                entry.source="excluded"
                entry.sourceConfidence=1.0
                entry.locationReason="placement:"..tostring(entry._placementReason or "explicit")
                S.excludedBase=(S.excludedBase or 0)+1
                local reason=entry.locationReason
                S.exclusionReasons[reason]=(S.exclusionReasons[reason] or 0)+1
            else
                candidates[#candidates+1]=entry
            end
        end

        if #candidates==CFG.NATURAL_EGGS_PER_BIOME then
            learnNaturalSlots(id,candidates)
            learned=learned+1
            for _,entry in ipairs(candidates) do
                entry.source="world_spawn"
                entry.sourceConfidence=0.995
                entry.locationReason="natural5_exact"
                world[#world+1]=entry
            end
            worldCounts[id]=#candidates

        elseif #candidates>CFG.NATURAL_EGGS_PER_BIOME then
            local chosen,maxDistance=matchLearnedNaturalSlots(id,candidates)
            local chosenSet={}

            if chosen then
                for _,entry in ipairs(chosen) do
                    chosenSet[entry]=true
                    entry.source="world_spawn"
                    entry.sourceConfidence=0.99
                    entry.locationReason=string.format("natural5_slot_match:%.1f",maxDistance or 0)
                    world[#world+1]=entry
                end
                worldCounts[id]=#chosen

                for _,entry in ipairs(candidates) do
                    if not chosenSet[entry] then
                        entry.source="excluded"
                        entry.sourceConfidence=1.0
                        entry.locationReason="natural5_overflow"
                        overflow=overflow+1
                        S.excludedBase=(S.excludedBase or 0)+1
                        S.exclusionReasons["natural5_overflow"]=(S.exclusionReasons["natural5_overflow"] or 0)+1
                    end
                end
            else
                -- We have more than five eggs for this biome but no trustworthy
                -- learned slot map yet. Show them locally as candidates, never cloud.
                partial=partial+1
                worldCounts[id]=#candidates
                for _,entry in ipairs(candidates) do
                    entry.source="world_candidate"
                    entry.sourceConfidence=0.72
                    entry.locationReason="natural5_overflow_unlearned"
                    world[#world+1]=entry
                end
            end

        else
            -- Streaming/replication may still be incomplete. Keep visible locally
            -- but fail closed for commercial feed until all five are present.
            partial=partial+1
            worldCounts[id]=#candidates
            for _,entry in ipairs(candidates) do
                entry.source="world_candidate"
                entry.sourceConfidence=0.75
                entry.locationReason="natural5_partial:"..tostring(#candidates)
                world[#world+1]=entry
            end
        end
    end

    S.biomeGroupCounts=counts
    S.biomeWorldCounts=worldCounts
    S.natural5LearnedBiomes=learned
    S.natural5OverflowExcluded=overflow
    S.natural5PartialGroups=partial

    return world
end

local function hasMutation(entry,name)
    for _,m in ipairs(entry.muts or {}) do if m==name then return true end end
    return false
end

local function isDivineSignal(entry)
    local rarity=string.lower(tostring(entry and (entry.rarity or entry.catalogRarity) or ""))
    if rarity=="divine" or rarity=="divino" then return true end
    for _,m in ipairs((entry and entry.muts) or {}) do
        local key=string.lower(tostring(m or ""))
        if key=="divine" or key=="divino" then return true end
    end
    return false
end

local function targetPetKey(entry)
    if entry.pet=="Jellyfish" and hasMutation(entry,"Pure") then return "Pure Jellyfish" end
    local raw=tostring(entry.pet or entry.displayName or entry.eggName or "")
    local wanted,canonical=Shared.__VYRO_LOOKUP_TARGET_ONLY(raw)
    if wanted and canonical then return canonical end
    local _,catalogCanonical=lookupEggInfo(raw)
    return catalogCanonical or entry.pet
end

local function buyerAnnouncementGate(pet)
    if tostring(pet or "")~="Mutant Shark" then return true end
    local h=S.chatHint
    local age=(type(h)=="table") and (nowUnix()-(tonumber(h.at) or 0)) or math.huge
    return type(h)=="table"
        and age>=0 and age<=CFG.CHAT_HINT_TTL
        and tostring(h.pet)=="Mutant Shark"
        and tostring(h.zone)=="Titan Temple"
        and tostring(h.job or "")==tostring(game.JobId)
end

local function catalogInfo(entry)
    local key=targetPetKey(entry)
    local info,canonical=lookupEggInfo(key or entry.pet)
    return info,canonical or key
end

local function enrichCatalog(entry)
    local info,key=catalogInfo(entry)
    if info then
        entry.catalogPet=key
        entry.catalogBiome=info.biome
        entry.catalogRarity=info.rarity
        entry.catalogEgg=info.egg
        if not entry.previewAssetId and info.preview_asset_id then
            entry.previewAssetId=tostring(info.preview_asset_id)
        end
    end
    if not entry.previewAssetId and entry.eggFingerprint then
        entry.previewAssetId=FP.previewAssetId(entry._model,entry.eggFingerprint)
    end
end

local function filterMixedUnknownPools(entries)
    local groups={}
    for _,egg in ipairs(entries) do
        local id=tostring(egg.biomeId or "")
        groups[id]=groups[id] or {}
        local info=catalogInfo(egg)
        if info and info.biome then groups[id][info.biome]=true end
    end

    local mixed={}
    for id,homes in pairs(groups) do
        if not KNOWN_BIOMES[id] then
            local count=0
            for _ in pairs(homes) do count=count+1 end
            if count>=3 then mixed[id]=true end
        end
    end

    if next(mixed)==nil then return entries end

    local clean={}
    for _,egg in ipairs(entries) do
        if mixed[tostring(egg.biomeId or "")] then
            egg.source="excluded"
            egg.sourceConfidence=1.0
            egg.locationReason="base_pool_mixed"
            S.excludedBase=(S.excludedBase or 0)+1
        else
            clean[#clean+1]=egg
        end
    end
    return clean
end

local function enrichTarget(entry)
    local key=targetPetKey(entry)
    local _,normalizedTargetKey=Shared.__VYRO_LOOKUP_TARGET_ONLY(key or entry.pet)
    key=normalizedTargetKey or key
    local info=TARGET_PET_INFO[key] or TARGET_PET_INFO[entry.pet]
    if info then
        entry.rarity=entry.rarity or info.rarity
        entry.eggName=entry.eggName or info.egg
        entry.catalogSide=info.side
    else
        entry.rarity=entry.rarity or "Unknown"
        entry.eggName=entry.eggName or (entry.pet.." Egg")
    end
end

Shared.__VYRO_DEBUG_IGNORED_EGG_SEEN=Shared.__VYRO_DEBUG_IGNORED_EGG_SEEN or {}
Shared.__VYRO_DEBUG_IGNORED_EGG=function(entry,reason)
    entry=type(entry)=="table" and entry or {}
    local displayName=tostring(entry.displayName or entry.pet or entry.eggName or "")
    local normalized=Shared.__VYRO_NORMALIZE_EGG_NAME(displayName) or ""
    local catalogEntry=select(1,lookupEggInfo(displayName))
    local targetEntry=select(1,Shared.__VYRO_LOOKUP_TARGET_ONLY(displayName))
    local fingerprint=tostring(entry.eggFingerprint or entry.fingerprint or "N/A")
    local key=tostring(game.JobId).."|"..tostring(entry.uid or displayName).."|"..tostring(reason or "ninguna")
    if Shared.__VYRO_DEBUG_IGNORED_EGG_SEEN[key] then return end
    Shared.__VYRO_DEBUG_IGNORED_EGG_SEEN[key]=true
    print(string.format(
        "[VYRO-DEBUG] Huevo: %s | normalizado: %s | fp: %s | en_catalogo: %s | target: %s | razón: %s",
        displayName,normalized,fingerprint,tostring(catalogEntry~=nil),tostring(targetEntry~=nil),tostring(reason or "ninguna")
    ))
end

local DEFAULT_MIN_SCALE_BY_RARITY={
    Divine=0.80,
    Eternal=0.90,
    Secret=1.35,
    Cosmic=1.75,
    Mythic=2.10,
    Legendary=2.50,
}
local RARITY_SCORE={Legendary=42,Mythic=50,Cosmic=60,Secret=70,Eternal=82,Divine=90}

local function qualityPolicy()
    local external=Shared.VYRO_QUALITY_POLICY
    local p={
        version=CFG.QUALITY_POLICY_VERSION,
        absolute_scale_keep=CFG.QUALITY_ABSOLUTE_SCALE_KEEP,
        min_score=CFG.QUALITY_MIN_SCORE,
        mutation_scale_discount=CFG.QUALITY_MUTATION_DISCOUNT,
        max_upload_per_server=CFG.QUALITY_MAX_UPLOAD_PER_SERVER,
        min_scale_by_rarity={},
    }
    for k,v in pairs(DEFAULT_MIN_SCALE_BY_RARITY) do p.min_scale_by_rarity[k]=v end
    if type(external)=="table" then
        for k,v in pairs(external) do
            if k~="min_scale_by_rarity" then p[k]=v end
        end
        if type(external.min_scale_by_rarity)=="table" then
            for k,v in pairs(external.min_scale_by_rarity) do p.min_scale_by_rarity[k]=tonumber(v) or p.min_scale_by_rarity[k] end
        end
    end
    S.qualityPolicyVersion=tostring(p.version or CFG.QUALITY_POLICY_VERSION)
    return p
end

local function evaluateQuality(entry)
    local p=qualityPolicy()
    local rarity=tostring(entry.rarity or entry.catalogRarity or "Unknown")
    local scale=tonumber(entry.scale)
    local muts=entry.muts or {}
    local rarityScore=RARITY_SCORE[rarity] or 0
    local sizeScore=scale and math.min(30,math.max(0,(scale-0.75)*13)) or 0
    local mutationScore=math.min(12,#muts*4)
    local mergedBonus=(entry.targetBiome=="Angels & Demons") and 3 or 0
    local score=math.min(100,rarityScore+sizeScore+mutationScore+mergedBonus)
    score=math.floor(score*100+0.5)/100
    local minScale=p.min_scale_by_rarity[rarity]
    local adjusted=nil
    if minScale then
        adjusted=math.max(0.65,tonumber(minScale)*(1-math.min(0.30,#muts*(tonumber(p.mutation_scale_discount) or 0))))
    end
    local absolute=scale and scale>=tonumber(p.absolute_scale_keep or 3.0)
    local rarityScale=scale and adjusted and scale>=adjusted
    local scoreRule=scale and score>=tonumber(p.min_score or 78)
    local verifiedWorld=(entry.source=="world_spawn") and ((tonumber(entry.sourceConfidence) or 0)>=CFG.WORLD_MIN_CONFIDENCE)
    local globalDivine=isDivineSignal(entry)
    local canonicalPet=tostring(targetPetKey(entry) or "")
    local announcementOk=buyerAnnouncementGate(canonicalPet)
    local qualified=verifiedWorld and announcementOk and ((entry.targetBiome~=nil) or globalDivine) and (globalDivine or absolute or rarityScale or scoreRule)
    local reason=verifiedWorld and "below_quality_gate" or "world_unverified"
    if not verifiedWorld then reason="world_unverified"
    elseif not announcementOk then reason="mutant_shark_unannounced"
    elseif globalDivine then reason="global_divine"
    elseif not scale then reason="scale_missing"
    elseif absolute then reason="absolute_big"
    elseif rarityScale then reason="rarity_scale:"..rarity
    elseif scoreRule then reason="quality_score" end
    entry.globalDivine=globalDivine
    entry.qualityScore=score
    entry.qualityReason=reason
    entry.commercialQualified=qualified==true
    entry.qualityMinScale=adjusted
    return qualified,score,reason
end

local function applyQualityGate(targets)
    local qualified={}
    for _,entry in ipairs(targets or {}) do
        if evaluateQuality(entry) then qualified[#qualified+1]=entry end
    end
    table.sort(qualified,function(a,b)
        -- Global Divine always wins upload priority. After that, physical size
        -- remains the commercial ordering for premium-zone matches.
        local ad,bd=isDivineSignal(a),isDivineSignal(b)
        if ad~=bd then return ad end
        local as,bs=tonumber(a.scale) or -1,tonumber(b.scale) or -1
        if as~=bs then return as>bs end
        local aq,bq=tonumber(a.qualityScore) or 0,tonumber(b.qualityScore) or 0
        if aq~=bq then return aq>bq end
        return tostring(a.pet)<tostring(b.pet)
    end)
    local p=qualityPolicy()
    local divineCount=0
    for _,entry in ipairs(qualified) do if isDivineSignal(entry) then divineCount=divineCount+1 end end
    local cap=math.max(divineCount,tonumber(p.max_upload_per_server or CFG.QUALITY_MAX_UPLOAD_PER_SERVER))
    while #qualified>cap do table.remove(qualified) end
    return qualified
end

local function classifyTargets(results)
    local targets={}
    local map={}
    for _,egg in ipairs(results or {}) do
        local zone=tostring(egg.biomeName or egg.biomeId or "")
        local key=targetPetKey(egg)
        local wanted,canonicalTarget=Shared.__VYRO_LOOKUP_TARGET_ONLY(key or egg.pet or egg.displayName)
        if canonicalTarget then key=canonicalTarget end
        local zoneOk=wanted and (
            zone==wanted.zone
            or (wanted.zone=="Light Dark" and (zone=="Angels & Demons" or zone=="Angels" or zone=="Demons"))
        )
        if zoneOk then
            egg.pet=key
            egg.rarity=wanted.rarity
            egg.muts=retailMutations(egg.muts)
            egg.targetBiome=wanted.side
            egg.side=wanted.side
            enrichTarget(egg)
            if wanted.rarity=="Divine" then egg.globalDivine=true end
            targets[#targets+1]=egg
            map[zone]=wanted.side
        else
            Shared.__VYRO_DEBUG_IGNORED_EGG(egg,wanted and "target_zone_mismatch" or "not_target_whitelist")
        end
    end
    table.sort(targets,function(a,b)
        local ar={Divine=3,Eternal=2,Secret=1}
        local av,bv=ar[tostring(a.rarity)] or 0,ar[tostring(b.rarity)] or 0
        if av~=bv then return av>bv end
        local as,bs=a.scale or -1,b.scale or -1
        if as~=bs then return as>bs end
        return tostring(a.pet)<tostring(b.pet)
    end)
    return targets,map
end

local saveState

Runtime.GLOBAL_SLOT_MAP_FILE="VYRO_GLOBAL_SLOT_MAP.json"
Runtime.loadGlobalSlotMap=function(force)
    local now=nowUnix()
    if not force
        and type(Runtime.globalSlotMapCache)=="table"
        and now-(tonumber(Runtime.globalSlotMapLoadedAt) or 0)<5
    then
        return Runtime.globalSlotMapCache
    end
    local rows={}
    local meta=nil
    if type(Shared.__VYRO_EXEC._IF)=="function" and type(Shared.__VYRO_EXEC._RF)=="function" then
        local okExists,exists=pcall(Shared.__VYRO_EXEC._IF,Runtime.GLOBAL_SLOT_MAP_FILE)
        if okExists and exists==true then
            local okRaw,raw=pcall(Shared.__VYRO_EXEC._RF,Runtime.GLOBAL_SLOT_MAP_FILE)
            if okRaw and type(raw)=="string" then
                local okJson,data=pcall(function() return HttpService:JSONDecode(raw) end)
                if okJson and type(data)=="table" and type(data.slots)=="table" then
                    meta=data
                    for _,slot in ipairs(data.slots) do
                        if type(slot)=="table"
                            and tostring(slot.zone or "")~=""
                            and tonumber(slot.x) and tonumber(slot.y) and tonumber(slot.z)
                        then
                            rows[#rows+1]=slot
                        end
                    end
                end
            end
        end
    end
    Runtime.globalSlotMapCache=rows
    Runtime.globalSlotMapMeta=meta
    Runtime.globalSlotMapLoadedAt=now
    return rows
end

Runtime.saveGlobalSlotMap=function(slots)
    if type(slots)~="table" or #slots<55 or type(Shared.__VYRO_EXEC._WF)~="function" then return false end
    local now=nowUnix()
    local existing=Runtime.loadGlobalSlotMap(true)
    local meta=Runtime.globalSlotMapMeta
    if type(existing)=="table" and #existing>=55 and type(meta)=="table"
        and now-(tonumber(meta.saved_at) or 0)<3600
    then
        return true
    end
    local rows={}
    local counts={}
    for _,slot in ipairs(slots) do
        local p=slot and slot.position
        local zone=tostring(slot and slot.zone or "")
        local idx=tonumber(slot and slot.index)
        if p and zone~="" and idx then
            rows[#rows+1]={zone=zone,index=idx,x=p.X,y=p.Y,z=p.Z}
            counts[zone]=(counts[zone] or 0)+1
        end
    end
    local biomeCount=0
    for _,count in pairs(counts) do
        if count>=5 then biomeCount=biomeCount+1 end
    end
    if #rows<55 or biomeCount<10 then return false end
    local payload={
        version="vyro-global-slot-map-v1",
        saved_at=now,
        source_account=tostring(LP.Name),
        source_job=tostring(game.JobId),
        count=#rows,
        slots=rows,
    }
    local ok=pcall(function()
        Shared.__VYRO_EXEC._WF(Runtime.GLOBAL_SLOT_MAP_FILE,HttpService:JSONEncode(payload))
    end)
    if ok then
        Runtime.globalSlotMapCache=rows
        Runtime.globalSlotMapMeta=payload
        Runtime.globalSlotMapLoadedAt=now
    end
    return ok
end

local function guardAreasRoot()
    -- Authoritative route used by the current game build.
    local world=workspace:FindFirstChild("World")
    local areas=world and world:FindFirstChild("Areas")
    local guard=areas and areas:FindFirstChild("GuardAreas")
    if guard then return guard end

    -- Legacy compatibility.
    local objects=workspace:FindFirstChild("__OBJECTS")
    areas=objects and objects:FindFirstChild("Areas")
    guard=areas and areas:FindFirstChild("GuardAreas")
    if guard then return guard end

    -- Last-resort recursive fallback.
    return workspace:FindFirstChild("GuardAreas",true)
end

local function valueByNames(root,names)
    if not root then return nil end
    local wanted={}
    for _,name in ipairs(names or {}) do wanted[normalizedKey(name)]=true end

    local function inspect(obj)
        local ok,attrs=pcall(function() return obj:GetAttributes() end)
        if ok and type(attrs)=="table" then
            for key,value in pairs(attrs) do
                if wanted[normalizedKey(key)] and value~=nil and tostring(value)~="" then
                    return tostring(value)
                end
            end
        end

        if wanted[normalizedKey(obj.Name)] then
            local v=readValueObject(obj)
            if v and v~="" then return tostring(v) end
        end
        return nil
    end

    local v=inspect(root)
    if v then return v end
    for _,obj in ipairs(root:GetDescendants()) do
        v=inspect(obj)
        if v then return v end
    end
    return nil
end

local function findNestContainerForAnchor(anchor,nestsRoot)
    local cur=anchor
    while cur and cur.Parent and cur.Parent~=nestsRoot do
        cur=cur.Parent
    end
    if cur and cur.Parent==nestsRoot then return cur end
    return anchor.Parent
end

local function collectNestSlots(zoneFilter)
    local root=guardAreasRoot()
    local slots={}
    local biomeCounts={}
    S.nestSlotSource="none"

    if root then
        for _,area in ipairs(root:GetChildren()) do
            local zoneName=Runtime.canonicalBiome(area.Name)
            local nests=(not zoneFilter or zoneFilter[zoneName]) and area:FindFirstChild("Nests") or nil
            if nests then
                local seenNest={}
                local anchorParts={}
                for _,obj in ipairs(nests:GetDescendants()) do
                    if obj:IsA("BasePart") and (obj.Name=="EggFitBounds" or obj.Name=="EggSpotBottom") then
                        anchorParts[#anchorParts+1]=obj
                    end
                end

                table.sort(anchorParts,function(a,b)
                    if a.Name~=b.Name then return a.Name=="EggFitBounds" end
                    if a.Position.Z~=b.Position.Z then return a.Position.Z<b.Position.Z end
                    return a.Position.X<b.Position.X
                end)

                for _,part in ipairs(anchorParts) do
                    local nest=findNestContainerForAnchor(part,nests)
                    if nest and not seenNest[nest] then
                        local fit=nest:FindFirstChild("EggFitBounds",true)
                        local bottom=nest:FindFirstChild("EggSpotBottom",true)
                        local anchor=(fit and fit:IsA("BasePart") and fit)
                            or (bottom and bottom:IsA("BasePart") and bottom)
                            or part

                        seenNest[nest]=true
                        local zone=zoneName
                        biomeCounts[zone]=(biomeCounts[zone] or 0)+1
                        slots[#slots+1]={
                            zone=zone,
                            index=biomeCounts[zone],
                            area=area,
                            nests=nests,
                            nest=nest,
                            anchor=anchor,
                            position=anchor.Position,
                            boundsSize=(fit and fit:IsA("BasePart")) and fit.Size or Vector3.new(8,8,8),
                            slotSource="GuardAreas",
                        }
                    end
                end
            end
        end
    end

    if #slots>0 then
        S.nestSlotSource="GuardAreas"
        pcall(Runtime.saveGlobalSlotMap,slots)
    else
        -- Some low-FPS/headless clients receive AreaEggSlotsClient before
        -- __OBJECTS.Areas.GuardAreas. Treat each live visual as its own slot
        -- rather than declaring the whole server blind. This path is used only
        -- when the authoritative GuardAreas source produced zero slots.
        local visualRoot=workspace:FindFirstChild("AreaEggSlotsClient")
        local rows={}
        local globalSlots=Runtime.loadGlobalSlotMap(false)
        local usedGlobal={}
        if visualRoot then
            for _,model in ipairs(visualRoot:GetChildren()) do
                if model:IsA("Model") then
                    local ownerId=nil
                    pcall(function() ownerId=model:GetAttribute("OwnerUserId") end)
                    local pos=FP.position(model)
                    if ownerId==nil and pos then
                        local mapped=nil
                        local mappedIndex=nil
                        local mappedDistance=math.huge
                        for mapIndex,slotMap in ipairs(globalSlots or {}) do
                            if not usedGlobal[mapIndex] then
                                local x,y,z=tonumber(slotMap.x),tonumber(slotMap.y),tonumber(slotMap.z)
                                if x and y and z then
                                    local d=(pos-Vector3.new(x,y,z)).Magnitude
                                    if d<mappedDistance then
                                        mapped=slotMap
                                        mappedIndex=mapIndex
                                        mappedDistance=d
                                    end
                                end
                            end
                        end
                        if mapped and mappedDistance<=36 then
                            usedGlobal[mappedIndex]=true
                        else
                            mapped=nil
                            mappedIndex=nil
                        end

                        local rawName=readDisplayName(model) or tostring(model.Name)
                        local _,parsedPet=parseDisplayName(tostring(rawName))
                        local info,canonical=lookupEggInfo(parsedPet or rawName)
                        local wanted,wantedCanonical=Shared.__VYRO_LOOKUP_TARGET_ONLY(parsedPet or rawName)
                        local nameZone,nameSlot=tostring(model.Name):match("^FirstAreaEgg_%d+_%d+_(.-):Slot_(%d+)$")
                        local zone=(mapped and tostring(mapped.zone or ""))
                            or (info and info.biome)
                            or (wanted and wanted.zone)
                            or (nameZone and tostring(nameZone))
                            or valueByNames(model,{"Biome","Zone","Area","Location","GuardArea"})
                            or "Unknown"
                        local mappedSlot=(mapped and tonumber(mapped.index)) or tonumber(nameSlot)
                        zone=Runtime.canonicalBiome(zone)
                        if zone=="Angels" or zone=="Demons" then zone="Light Dark" end
                        if not zoneFilter or zoneFilter[tostring(zone)] then
                            rows[#rows+1]={
                                model=model,
                                position=pos,
                                zone=tostring(zone),
                                slotIndex=mappedSlot,
                                mapDistance=mapped and mappedDistance or nil,
                                display=tostring(canonical or wantedCanonical or parsedPet or rawName or ""),
                            }
                        end
                    end
                end
            end
        end

        table.sort(rows,function(a,b)
            if a.zone~=b.zone then return a.zone<b.zone end
            if a.position.Z~=b.position.Z then return a.position.Z<b.position.Z end
            if a.position.X~=b.position.X then return a.position.X<b.position.X end
            return tostring(a.model.Name)<tostring(b.model.Name)
        end)

        local mappedCount=0
        for _,row in ipairs(rows) do
            local zone=row.zone
            biomeCounts[zone]=(biomeCounts[zone] or 0)+1
            local idx=tonumber(row.slotIndex) or biomeCounts[zone]
            local mapped=row.mapDistance~=nil and zone~="Unknown"
            if mapped then mappedCount=mappedCount+1 end
            slots[#slots+1]={
                zone=zone,
                index=idx,
                area=visualRoot,
                nests=visualRoot,
                nest=row.model,
                anchor=row.model,
                position=row.position,
                boundsSize=Vector3.new(8,8,8),
                slotSource=mapped and "GlobalSlotMap" or "AreaEggSlotsClient",
                mapDistance=row.mapDistance,
                eventId=mapped
                    and table.concat({tostring(game.JobId),"slot",zone,tostring(idx),"g0"},":")
                    or table.concat({tostring(game.JobId),"visual",tostring(row.model.Name)},":"),
            }
        end
        if #slots>0 then
            S.nestSlotSource=(mappedCount>0)
                and ("AreaEggSlotsClient+GlobalMap("..tostring(mappedCount)..")")
                or "AreaEggSlotsClient"
            if Runtime.lastVisualSlotFallbackJob~=tostring(game.JobId) then
                Runtime.lastVisualSlotFallbackJob=tostring(game.JobId)
                logLine("SLOT FALLBACK · AreaEggSlotsClient · "..tostring(#slots).." slots")
            end
        end
    end

    table.sort(slots,function(a,b)
        if a.zone~=b.zone then return a.zone<b.zone end
        return a.index<b.index
    end)
    return slots,biomeCounts
end

local function modelHasPetData(model)
    if not model or not model:IsA("Model") then return false end
    if not model:FindFirstChild("Data") then return false end
    local name=readDisplayName(model)
    return name~=nil and tostring(name)~=""
end

local function currentPlayerIdSet()
    local out={}
    for _,player in ipairs(Players:GetPlayers()) do
        out[tostring(player.UserId)]=true
    end
    return out
end

local function candidateOwnerId(model)
    if not model then return nil end
    local ok,value=pcall(function() return model:GetAttribute("OwnerUserId") end)
    if ok and value~=nil then return tostring(value) end
    return nil
end

local function collectPetCandidates(premiumOnly)
    local out,seen={},{}
    local playerIds=currentPlayerIdSet()
    local ignoredBase=0

    local function add(obj,origin)
        if not obj or seen[obj] or not modelHasPetData(obj) then return end
        seen[obj]=true

        local ownerId=candidateOwnerId(obj)
        if ownerId then
            ignoredBase=ignoredBase+1
            return
        end

        local pos=eggPosition(obj)
        if not pos then return end
        out[#out+1]={model=obj,pos=pos,origin=origin,ownerId=ownerId}
    end

    local rendered=workspace:FindFirstChild("ClientRenderedAssets")
    if rendered then
        for _,obj in ipairs(rendered:GetChildren()) do add(obj,"ClientRenderedAssets") end
    end

    if not premiumOnly then
        local root=guardAreasRoot()
        if root then
            for _,obj in ipairs(root:GetDescendants()) do
                if obj:IsA("Model") then add(obj,"GuardAreas") end
            end
        end
    end

    return out,ignoredBase
end

local function readLiveRarity(obj)
    local v=valueByNames(obj,{"Odds","Rarity","Tier"})
    if not v then return nil end
    v=tostring(v):gsub("^%s+",""):gsub("%s+$","")
    return v~="" and v or nil
end

local function readPerSecond(obj)
    local v=valueByNames(obj,{"PerSecond","Income","IncomePerSecond","Generation","Generates"})
    if v and tostring(v)~="" then return tostring(v) end

    -- PATCH T: only treat visible "$.../s" style text as exact PV.
    -- Do not invent a rarity-based value here; Buyer already exposes estimates
    -- separately and must not confuse an estimate with an exact live PV.
    local data=obj and obj:FindFirstChild("Data",true)
    if data then
        for _,child in ipairs(data:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                local text=stripRichText(child.Text or ""):gsub("^%s+",""):gsub("%s+$","")
                local lower=text:lower()
                if text:find("%$") and (lower:find("/s",1,true) or lower:find("per second",1,true)) then
                    return text
                end
            end
        end
    end
    return nil
end

local function readUid(obj)
    local v=valueByNames(obj,{"UID","EggUID","PetUID"})
    return (v and tostring(v)~="") and tostring(v) or nil
end

-- Exact carrying signal: only when a target model has a stable UID, an owner,
-- and is physically close to that owner character. No guessing by pet name alone.
local function collectCarriedTargets()
    local out,seen={},{}
    local playersById={}
    for _,p in ipairs(Players:GetPlayers()) do playersById[tostring(p.UserId)]=p end
    local rendered=workspace:FindFirstChild("ClientRenderedAssets")
    if not rendered then return out end
    for _,model in ipairs(rendered:GetChildren()) do
        if model:IsA("Model") and modelHasPetData(model) then
            local ownerId=candidateOwnerId(model)
            local player=ownerId and playersById[ownerId] or nil
            local root=player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") or nil
            local pos=eggPosition(model)
            if player and root and pos and (pos-root.Position).Magnitude<=16 then
                local uid=readUid(model)
                local display=readDisplayName(model)
                local muts,pet=parseDisplayName(display)
                local temp={pet=pet,muts=muts}
                local key=targetPetKey(temp)
                local wanted,canonicalTarget=Shared.__VYRO_LOOKUP_TARGET_ONLY(key or pet or display)
                if canonicalTarget then key=canonicalTarget end
                if uid and uid~="" and wanted and S.serverSeenTargetUids and S.serverSeenTargetUids[uid] and not seen[uid] then
                    seen[uid]=true
                    local carriedScale,carriedScaleSource,carriedScaleKind=getScale(model)
                    local carriedCatalog=select(1,lookupEggInfo(key))
                    out[#out+1]={
                        uid=uid,pet=key,eggName=(carriedCatalog and carriedCatalog.egg) or (key.." Egg"),
                        rarity=wanted.rarity,biomeName=wanted.side,targetBiome=wanted.side,side=wanted.side,
                        muts=retailMutations(muts),sourceConfidence=1.0,areaState="carrying",scale=carriedScale,scaleSource=carriedScaleSource,scaleKind=carriedScaleKind,perSecond=readPerSecond(model),
                        carrierUserId=ownerId,carrierName=tostring(player.Name),previewAssetId=FP.previewAssetId(model,FP.fingerprint(model)),
                    }
                end
            end
        end
    end
    return out
end

local function refreshTrackedTargetStates()
    local carried=collectCarriedTargets()
    local carriedIds={}
    for _,e in ipairs(carried) do carriedIds[tostring(e.uid or "")]=true end

    local previousCarried={}
    for _,e in ipairs(S.carriedTargets or {}) do previousCarried[tostring(e.uid or "")]=true end
    local changed=false
    if countKeys(carriedIds)~=countKeys(previousCarried) then changed=true end
    if not changed then
        for uid in pairs(carriedIds) do if not previousCarried[uid] then changed=true break end end
    end

    local kept={}
    for _,e in ipairs(S.targets or {}) do
        local uid=tostring(e.uid or "")
        if carriedIds[uid] then
            changed=true
        else
            local model=e._model
            local pos=(model and model.Parent) and eggPosition(model) or nil
            local anchor=e.nestPosition or e._position
            local stillAtNest=false
            if model and model.Parent and pos and anchor then
                stillAtNest=(pos-anchor).Magnitude<=CFG.NATURAL_SLOT_MATCH_TOLERANCE
            end
            if stillAtNest then
                kept[#kept+1]=e
            else
                changed=true
            end
        end
    end
    S.targets=kept
    S.qualifiedTargets=kept
    S.carriedTargets=carried
    return changed
end

local function directNestPetModel(slot)
    if not slot or not slot.nest then return nil end
    if slot.nest:IsA("Model") and modelHasPetData(slot.nest) then return slot.nest end
    for _,obj in ipairs(slot.nest:GetDescendants()) do
        if obj:IsA("Model") and modelHasPetData(obj) then return obj end
    end
    return nil
end

local function nearestCandidateForSlot(slot,candidates,used)
    local direct=directNestPetModel(slot)
    if direct and not used[direct] then
        used[direct]=true
        return direct,0,"nest_descendant"
    end

    local best,bestDist=nil,math.huge
    for _,candidate in ipairs(candidates or {}) do
        local model=candidate.model
        if not used[model] then
            local d=(candidate.pos-slot.position).Magnitude
            if d<bestDist then
                best,bestDist=model,d
            end
        end
    end

    local dynamic=math.max(
        CFG.NEST_CANDIDATE_MAX_DISTANCE,
        math.max(slot.boundsSize.X,slot.boundsSize.Z)*1.5
    )
    dynamic=math.min(dynamic,48)

    if best and bestDist<=dynamic then
        used[best]=true
        return best,bestDist,"nearest"
    end
    return nil,bestDist,"none"
end

local function nestMetadataName(slot)
    return valueByNames(slot and slot.nest,{
        "DisplayName","PetName","EggName","HatchName",
        "CurrentPet","CurrentEgg","Pet","Egg"
    })
end

local function metadataIdentityForSlot(slot,model)
    local names={}
    local live=(model and readDisplayName(model)) or ""
    if live~="" then names[#names+1]=live end
    local nestName=nestMetadataName(slot)
    if nestName and tostring(nestName)~="" and tostring(nestName)~=live then
        names[#names+1]=tostring(nestName)
    end

    local side=FP.lightDarkSide(slot)
    for _,name in ipairs(names) do
        local muts,pet=parseDisplayName(name)
        local key=targetPetKey({pet=pet,muts=muts})
        local info=TARGET_PET_INFO[key] or TARGET_PET_INFO[pet]
        if info then
            local zone=tostring(slot.zone or "")
            local compatible=(tostring(info.side or "")==zone)
            if zone=="Light Dark" or zone=="Angels & Demons" then
                compatible=(side=="Angels & Demons") or (tostring(info.side or "")==side)
            end
            if compatible then
                return {
                    display=tostring(name), pet=key or pet, muts=muts,
                    egg=info.egg, rarity=info.rarity, side=info.side,
                }
            end
        end
    end
    return nil
end

local function catalogIdentityForSlot(slot,model)
    if not slot or not model then return nil end
    local live=readDisplayName(model)
    if not live or tostring(live)=="" then return nil end

    local muts,pet=parseDisplayName(live)
    local key=targetPetKey({pet=pet,muts=muts})
    local info,canonical=lookupEggInfo(key or pet)
    if canonical then key=canonical end
    if not info then return nil end

    local zone=tostring(slot.zone or "")
    local home=tostring(info.biome or "")
    local compatible=(zone==home)

    if zone=="Light Dark" or zone=="Angels & Demons" then
        local side=FP.lightDarkSide(slot)
        if home=="Angels" or home=="Demons" then
            compatible=(side=="Angels & Demons") or (side==home)
        end
    end

    if not compatible then return nil end

    return {
        display=tostring(live),
        pet=key or pet,
        muts=muts,
        egg=info.egg,
        rarity=info.rarity,
        biome=home,
    }
end

local function scalarAttributes(obj,maxItems)
    local out={}
    if not obj then return out end
    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if not ok or type(attrs)~="table" then return out end
    local n=0
    for k,v in pairs(attrs) do
        local tv=type(v)
        if tv=="string" or tv=="number" or tv=="boolean" then
            n=n+1
            if n>(maxItems or 24) then break end
            out[tostring(k)]=v
        end
    end
    return out
end

local function probeUnknownFingerprint(slot,model,fingerprint,distance,matchKind)
    local row={
        fingerprint=tostring(fingerprint or "no_mesh_id"),
        zone=tostring(slot and slot.zone or ""),
        nest_index=tonumber(slot and slot.index) or 0,
        distance=(distance and distance<math.huge) and distance or nil,
        match=tostring(matchKind or "none"),
        model_name=model and tostring(model.Name) or "",
        model_path=model and tostring(model:GetFullName()) or "",
        nest_name=slot and slot.nest and tostring(slot.nest.Name) or "",
        model_attrs=scalarAttributes(model,30),
        nest_attrs=scalarAttributes(slot and slot.nest,30),
        values={},
        texts={},
        children={},
    }
    if model then
        for _,child in ipairs(model:GetChildren()) do
            if #row.children>=24 then break end
            row.children[#row.children+1]=tostring(child.Name)..":"..tostring(child.ClassName)
        end
        for _,obj in ipairs(model:GetDescendants()) do
            if #row.values<24 and (obj:IsA("StringValue") or obj:IsA("NumberValue") or obj:IsA("IntValue") or obj:IsA("BoolValue")) then
                local ok,v=pcall(function() return obj.Value end)
                if ok then row.values[#row.values+1]=tostring(obj.Name).."="..tostring(v) end
            elseif #row.texts<20 and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
                local ok,v=pcall(function() return stripRichText(obj.Text or "") end)
                if ok and v and v~="" then
                    v=tostring(v)
                    if #v>120 then v=v:sub(1,120) end
                    row.texts[#row.texts+1]=tostring(obj.Name).."="..v
                end
            end
            if #row.values>=24 and #row.texts>=20 then break end
        end
    end
    return row
end

-- UPDATE8_BANNERS_BEGIN: passive replicated event observation only.
function Runtime.update8EventSnapshot(out)
    local job=tostring(game.JobId)
    local state=Shared.__VYRO_UPDATE8_BANNERS
    if not state or state.job~=job then
        if state then
            for _,connection in pairs(state.connections or {}) do pcall(function() connection:Disconnect() end) end
        end
        state={job=job,connections={},flagRefs={},flagValues={},flagKnown={},lookupStarted=false}
        Shared.__VYRO_UPDATE8_BANNERS=state
    end
    out["update8.probe_version"]=1
    local function finite(value)
        return type(value)=="number" and value==value and value>=0 and value<math.huge
    end
    local keys={"ContentEnabled","ScheduleEnabled","ScheduleIntervalSeconds","ScheduleOffsetSeconds","JoinSeconds"}
    local packages=ReplicatedStorage:FindFirstChild("Packages")
    local network=packages and packages:FindFirstChild("Networking")
    local fall=network and network:FindFirstChild("RE/ShootingStar/Fall")
    if fall and fall:IsA("RemoteEvent") and not (state.connections.fall and state.connections.fall.Connected) then
        state.connections.fall=fall.OnClientEvent:Connect(function(payload)
            if type(payload)~="table" then return end
            local at=payload.FallAt
            local expires=payload.ExpiresAt
            local now=workspace:GetServerTimeNow()
            if finite(at) and finite(expires) and expires>now and at>=now-90 and at<=now+120 then
                state.starFallAt=at
            end
        end)
    end
    out["update8.star_listener"]=state.connections.fall~=nil and state.connections.fall.Connected
    if finite(state.starFallAt) then out["update8.star_fall_at"]=state.starFallAt end

    -- Observe the existing flag broadcast; never request or alter game state.
    local generated=ReplicatedStorage:FindFirstChild("UserGenerated")
    local fast=generated and generated:FindFirstChild("FastFlags")
    local shared=fast and fast:FindFirstChild("SharedFastFlags")
    local update=shared and shared:FindFirstChild("Update")
    if update and update:IsA("RemoteEvent") and not (state.connections.flags and state.connections.flags.Connected) then
        state.connections.flags=update.OnClientEvent:Connect(function(values,loaded)
            if type(values)~="table" then return end
            for _,name in ipairs(keys) do
                local value=values["Game.RaceRally."..name]
                if type(value)=="boolean" or finite(value) then
                    state.flagValues[name]=value
                    state.flagKnown[name]=loaded==true or state.flagKnown[name]==true
                end
            end
        end)
    end

    -- Bootstrap from already loaded flag objects once per client. Retain only
    -- five references, then read their live values without another heap scan.
    if not state.lookupStarted and type(getgc)=="function" then
        state.lookupStarted=true
        task.spawn(function()
            local ok,objects=pcall(getgc,true)
            if not ok or type(objects)~="table" then return end
            local found=0
            local target={}
            for _,name in ipairs(keys) do target["Game.RaceRally."..name]=name end
            local slice=os.clock()
            for i,object in ipairs(objects) do
                if type(object)=="table" and rawget(object,"ValueLoaded")==true then
                    local name=target[rawget(object,"Key")]
                    if name and not state.flagRefs[name] then
                        state.flagRefs[name]=object;found=found+1
                        if found>=#keys then break end
                    end
                end
                if i%256==0 and os.clock()-slice>0.008 then task.wait();slice=os.clock() end
            end
        end)
    end
    local values={};local loaded=true
    for _,name in ipairs(keys) do
        local ref=state.flagRefs[name]
        if ref and rawget(ref,"ValueLoaded")==true then values[name]=rawget(ref,"Value")
        elseif state.flagKnown[name] then values[name]=state.flagValues[name]
        else loaded=false end
    end
    out["update8.race_schedule_loaded"]=loaded
    if loaded then
        out["update8.race_schedule_enabled"]=values.ContentEnabled==true and values.ScheduleEnabled==true
        out["update8.race_period"]=values.ScheduleIntervalSeconds
        out["update8.race_offset"]=values.ScheduleOffsetSeconds
        out["update8.race_join_seconds"]=values.JoinSeconds
    end
    local track=workspace:FindFirstChild("RaceTrack")
    if track and track:GetAttribute("RaceName")=="Race Rally" then
        local phase=track:GetAttribute("RacePhase")
        if type(phase)=="string" then out["update8.race_phase"]=phase end
        for attribute,key in pairs({RaceJoinEndsAt="join_ends_at",RaceGoAt="go_at",RaceEndsAt="ends_at"}) do
            local value=track:GetAttribute(attribute)
            if finite(value) then out["update8.race_"..key]=value end
        end
    end
    local join=workspace:GetAttribute("RaceRallyJoinEndsAt")
    if workspace:GetAttribute("RaceRallyRunning")==true and not out["update8.race_phase"] then
        if finite(join) and join>workspace:GetServerTimeNow() then
            out["update8.race_phase"]="Joining";out["update8.race_join_ends_at"]=join
        else out["update8.race_phase"]="Racing" end
    end
end
-- UPDATE8_BANNERS_END

local function eventFlagsSnapshot()
    local keys={
        "LiveEventFlag_RiftOpen",
        "ScrambleOutbreakActive",
        "ScrambleOutbreakEndsAt",
        "LiveEventFlag_LightDarkReveal",
        "AreaEggCyclePeriodSeconds",
        "AreaEggCycleDefaultNightSeconds",
    }
    local out={VyroScrambleProbeVersion=1,VyroEventProbeVersion=2}
    pcall(Runtime.update8EventSnapshot,out)
    for _,key in ipairs(keys) do
        local ok,value=pcall(function() return workspace:GetAttribute(key) end)
        if ok and value~=nil then out[key]=value end
    end

    local dynamicCount=0
    local eventTokens={
        "scramble","boss","portal","lab","butterfly","bloom","event","wisp","enchanted",
        "essence","emerald","sapphire","amethyst","radiant","outbreak",
        "start","end","duration","period","cooldown","interval","remaining","next","progress","count","active",
    }
    local function eventKey(low)
        low=tostring(low or ""):lower()
        for _,token in ipairs(eventTokens) do
            if low:find(token,1,true) then return true end
        end
        return false
    end
    local function collectAttributes(obj,prefix)
        if not obj or dynamicCount>=96 then return end
        local ok,attrs=pcall(function() return obj:GetAttributes() end)
        if not ok or type(attrs)~="table" then return end
        local objectRelevant=eventKey(obj.Name)
        for key,value in pairs(attrs) do
            if dynamicCount>=96 then break end
            local low=tostring(key):lower()
            local valueRelevant=type(value)=="string" and eventKey(value)
            if objectRelevant or eventKey(low) or valueRelevant then
                local tv=type(value)
                if tv=="string" or tv=="number" or tv=="boolean" then
                    out[prefix.."."..tostring(key)]=value
                    dynamicCount=dynamicCount+1
                end
            end
        end
    end

    collectAttributes(workspace,"workspace")
    collectAttributes(ReplicatedStorage,"replicated")
    local objects=workspace:FindFirstChild("__OBJECTS")
    local build=objects and objects:FindFirstChild("Build")
    collectAttributes(build,"build")

    if build and dynamicCount<96 then
        for _,forest in ipairs(build:GetChildren()) do
            local forestLow=tostring(forest.Name):lower()
            if forestLow:find("forest",1,true) then
                local prefix="forest."..tostring(forest.Name)
                collectAttributes(forest,prefix)
                for _,child in ipairs(forest:GetChildren()) do
                    if dynamicCount>=96 then break end
                    local low=tostring(child.Name):lower()
                    if eventKey(low) then
                        out[prefix..".object."..tostring(child.Name)]=true
                        dynamicCount=dynamicCount+1
                        collectAttributes(child,prefix..".object."..tostring(child.Name))
                    end
                end
            end
        end
    end
    return out
end

local function cycleProbeSnapshot()
    local out={}
    local function scan(obj,prefix)
        if not obj then return end
        local ok,attrs=pcall(function() return obj:GetAttributes() end)
        if not ok or type(attrs)~="table" then return end
        for key,value in pairs(attrs) do
            local low=tostring(key):lower()
            if low:find("cycle",1,true) or low:find("day",1,true) or low:find("night",1,true)
                or low:find("light",1,true) or low:find("dark",1,true) or low:find("period",1,true)
                or low:find("reveal",1,true) or low:find("winner",1,true) or low:find("time",1,true)
            then
                local tv=type(value)
                if tv=="string" or tv=="number" or tv=="boolean" then
                    out[prefix.."."..tostring(key)]=value
                end
            end
        end
    end
    scan(workspace,"workspace")
    scan(Lighting,"lighting")
    local objects=workspace:FindFirstChild("__OBJECTS")
    local build=objects and objects:FindFirstChild("Build")
    scan(build,"build")
    local okServer,serverTime=pcall(function() return workspace:GetServerTimeNow() end)
    if okServer then out["runtime.server_time"]=serverTime end
    out["runtime.clock_time"]=Lighting.ClockTime
    out["runtime.unix_time"]=nowUnix()
    out["runtime.cycle_hop_guard"]="CG1"
    out["runtime.cycle_server_day_ready"]=Runtime.cycleDayReady()
    if Runtime.cycleScanAck then
        out["runtime.cycle_scan_ack_generation"]=Runtime.cycleScanAck.generation
        out["runtime.cycle_scan_ack_job"]=Runtime.cycleScanAck.jobId
        out["runtime.cycle_scan_started_at"]=Runtime.cycleScanAck.scanStartedAt
        out["runtime.cycle_scan_acked_at"]=Runtime.cycleScanAck.ackedAt
    end
    return out
end

local function writePremiumMetadataProbe(slots)
    if Shared.VYRO_PREMIUM_METADATA_PROBE~=true then return end
    if type(Shared.__VYRO_EXEC._WF)~="function" then return end
    local rows={}
    for _,slot in ipairs(slots or {}) do
        rows[#rows+1]={
            zone=tostring(slot.zone or ""),
            index=tonumber(slot.index) or 0,
            name=nestMetadataName(slot),
            rarity=valueByNames(slot.nest,{"Odds","Rarity","Tier"}),
            scale=valueByNames(slot.nest,{"Scale","AssetScale","EggScale","SizeScale","SizeMultiplier","PetScale","ModelScale"}),
            per_second=valueByNames(slot.nest,{"PerSecond","Income","IncomePerSecond"}),
            uid=valueByNames(slot.nest,{"UID","EggUID","PetUID"}),
            attrs=scalarAttributes(slot.nest,48),
        }
    end
    local payload={version=CFG.VERSION,job_id=tostring(game.JobId),at=nowUnix(),slots=rows}
    pcall(function() Shared.__VYRO_EXEC._WF("VYRO_PREMIUM_META_PROBE.json",HttpService:JSONEncode(payload)) end)
end

-- PATCH C/D/I/M/N/Q helpers. They enrich the existing scan; cloud flow is unchanged.
local function pushPatchEvent(kind,data)
    local row={type=tostring(kind),timestamp=nowUnix(),job_id=tostring(game.JobId),account=tostring(LP.Name)}
    for k,v in pairs(data or {}) do row[k]=v end
    S.patchEvents[#S.patchEvents+1]=row
    while #S.patchEvents>12 do table.remove(S.patchEvents,1) end
end

-- PATCH U/V/W/X helpers. Keep them as one shared namespace to avoid
-- increasing Luau's top-level local/register pressure.
Shared.__VYRO_PATCH_SZ=Shared.__VYRO_PATCH_SZ or {}
local PatchSZ=Shared.__VYRO_PATCH_SZ
PatchSZ.restockJob=PatchSZ.restockJob or ""
PatchSZ.restockSlots=PatchSZ.restockSlots or {}
PatchSZ.eventEggs=PatchSZ.eventEggs or {
    ["Rifborn"]={rarity="Variable",source="Rift"},
    ["Riftbeasts"]={rarity="Variable",source="Rift"},
    ["Shattered Rift"]={rarity="Variable",source="Rift"},
    ["Nibbles #013"]={rarity="Cosmic",source="Dr. Scramble"},
    ["Experiment #001"]={rarity="Secret",source="Dr. Scramble"},
    ["Experiment Egg"]={rarity="Variable",source="Dr. Scramble Lab Mastery"},
    ["Biohazard Egg"]={rarity="Variable",source="Dr. Scramble Lab Mastery"},
    ["Baby Aurora Dragon"]={rarity="Legendary",source="Dragon Event"},
    ["Shadow Dragon"]={rarity="Mythic",source="Dragon Event"},
    ["Scorched Dragon"]={rarity="Secret",source="Dragon Event"},
    ["Void Dragon"]={rarity="Eternal",source="Dragon Event"},
    ["Ember Dragon"]={rarity="Secret",source="Dragon Event"},
    ["Equinox"]={rarity="Eternal",source="Fusion"},
    ["Aetheron"]={rarity="Divine",source="Fusion"},
}

-- Authoritative mutation metadata is already replicated in Client.EggState.
-- Read it locally once per scan and index by the exact field-egg UID. This
-- never invokes an EggWorld RemoteFunction and does not change scan/hop flow.
PatchSZ.fieldEggState=PatchSZ.fieldEggState or nil
function PatchSZ.readFieldRecordsByUid()
    local out={}
    local state=PatchSZ.fieldEggState
    if type(state)~="table" then
        local client=ReplicatedStorage:FindFirstChild("Client")
        local module=client and client:FindFirstChild("EggState")
        if not (module and module:IsA("ModuleScript")) then
            return out,"eggstate_module_missing"
        end
        local ok,result=pcall(Runtime.requireLoadedGameModule,module)
        if not ok or type(result)~="table" then
            return out,"eggstate_require_failed"
        end
        PatchSZ.fieldEggState=result
        state=result
    end
    if type(state.ReadFieldEggs)~="function" then
        return out,"read_field_eggs_missing"
    end
    local ok,snapshot=pcall(state.ReadFieldEggs)
    if not ok or type(snapshot)~="table" or type(snapshot.Records)~="table" then
        return out,"field_records_unavailable"
    end
    for _,record in pairs(snapshot.Records) do
        if type(record)=="table" then
            local uid=tostring(record.Uid or "")
            if uid~="" then out[uid]=record end
        end
    end
    return out,nil
end

function PatchSZ.mergeEggStateMutations(uid,currentMuts,recordsByUid)
    local muts=currentMuts or {}
    local record=(uid and recordsByUid) and recordsByUid[tostring(uid)] or nil
    if type(record)~="table" then return muts,false end
    local changed=false
    local function add(value)
        if value==nil then return end
        rememberEggStateMutationValue(value)
        if type(value)=="table" then
            for k,v in pairs(value) do
                if v==true then add(k) else add(v) end
            end
            return
        end
        local canonical=normalizeMutationName(value)
        if not canonical then return end
        for _,existing in ipairs(muts) do
            if (normalizeMutationName(existing) or tostring(existing))==canonical then
                return
            end
        end
        muts[#muts+1]=canonical
        changed=true
    end
    if type(record.Mutations)=="table" then
        for k,value in pairs(record.Mutations) do
            if value==true then add(k) else add(value) end
        end
    elseif record.Mutations~=nil then
        add(record.Mutations)
    end
    add(record.BaseMutation)
    return muts,changed
end

PatchSZ.eggStateScaleAliases=PatchSZ.eggStateScaleAliases or {
    ["king kong"]="gorilla king",
    ["godzilla"]="nightflame",
    ["gotzilla"]="nightflame",
}
local function eggStateScaleName(value)
    local raw=tostring(value or "")
    local info,catalogCanonical=lookupEggInfo(raw)
    if info and catalogCanonical and tostring(catalogCanonical)~="" then
        raw=tostring(catalogCanonical)
    else
        local wanted,targetCanonical=Shared.__VYRO_LOOKUP_TARGET_ONLY(raw)
        if wanted and targetCanonical then raw=tostring(targetCanonical) end
    end
    local norm=Shared.__VYRO_NORMALIZE_EGG_NAME(raw) or raw:lower()
    return PatchSZ.eggStateScaleAliases[norm] or norm
end

function PatchSZ.safeEggStateScale(uid,slot,pet,recordsByUid)
    local record=(uid and recordsByUid) and recordsByUid[tostring(uid)] or nil
    if type(record)~="table" then return nil,nil,"uid_missing" end
    local assetScale=finite(record.AssetScale)
    if not assetScale or assetScale<=0 then return nil,record,"scale_invalid" end
    local function zoneNorm(value)
        local zone=tostring(value or "")
        if zone=="Angels" or zone=="Demons" or zone=="Angels & Demons" then return "Light Dark" end
        return Runtime.canonicalBiome(zone)
    end
    local slotZone=zoneNorm(slot and slot.zone)
    local recordZone=zoneNorm(record.AreaId)
    if slotZone=="" or recordZone=="" or slotZone~=recordZone then
        return nil,record,"zone_mismatch"
    end
    local currentPet=eggStateScaleName(pet)
    local recordPet=eggStateScaleName(record.AssetCategory)
    -- VYRO_SHARK_RECORD_IDENTITY_20261017
    -- The live asset key Shark denotes Mutant Shark; the static fallback catalog
    -- also has an ordinary Shark. Bind only this final pet in its exact world zone,
    -- with an immutable matching UID and the observed live catalog definition.
    if tostring(record.AssetCategory or "")=="Shark" and currentPet=="mutant shark" then
        local liveAsset=type(LIVE_ASSET_DIRECTORY)=="table" and LIVE_ASSET_DIRECTORY["Shark"] or nil
        local liveEgg=type(liveAsset)=="table" and liveAsset.Egg or nil
        local liveRarity=type(liveAsset)=="table" and liveAsset.Rarity or nil
        local modelUid=tostring(uid or "")
        if type(liveAsset)=="table" and liveAsset.DisplayName=="Mutant Shark"
            and type(liveEgg)=="table" and liveEgg.DisplayName=="Mutant Shark Egg"
            and type(liveRarity)=="table" and liveRarity._id=="Secret"
            and slotZone=="Titan Temple"
            and tostring(record.Uid or "")==modelUid and #modelUid==32
            and modelUid:match("^[%da-fA-F]+$")
        then
            recordPet="mutant shark"
        end
    end
    if currentPet=="" or recordPet=="" or currentPet~=recordPet then
        return nil,record,"identity_mismatch"
    end
    local slotIndex=tonumber(slot and slot.index)
    local recordIndex=tonumber(tostring(record.NestId or ""):match("(%d+)$"))
    if not slotIndex or not recordIndex then
        return nil,record,"slot_unavailable"
    end
    if slotIndex~=recordIndex then
        -- Different orderings: require immutable 32-hex UID, zone and identity.
        -- Do NOT infer any fixed slot offset.
        local eggUid=tostring(record.Uid or "")
        local modelUid=tostring(uid or "")
        if eggUid~=modelUid or #modelUid~=32 or not modelUid:match("^[%da-fA-F]+$") then
            return nil,record,"slot_mismatch_no_exact_guid"
        end
        return assetScale,record,"exact_uid_zone_identity_slot_number_diff"
    end
    return assetScale,record,"exact_uid_zone_slot_identity"
end

function PatchSZ.mutationTelemetry()
    local out={}
    local cutoff=os.time()-1800
    for value,seenAt in pairs(Shared.__VYRO_EGGSTATE_MUTATION_VALUES or {}) do
        if tonumber(seenAt) and tonumber(seenAt)>=cutoff then out[#out+1]=tostring(value) end
    end
    table.sort(out)
    while #out>32 do table.remove(out,1) end
    return out
end

function PatchSZ.enchantedMutationAliases()
    local out={}
    for alias,canonical in pairs(Shared.__VYRO_LIVE_MUTATION_ALIASES or {}) do
        if tostring(canonical)=="Enchanted" then out[#out+1]=tostring(alias) end
    end
    table.sort(out)
    return out
end

function PatchSZ.explicitVariant(model,displayName)
    local text=tostring(displayName or "")
    local lower=text:lower()
    if lower:find("shiny",1,true) then return "Shiny" end
    if lower:find("luminous",1,true) then return "Luminous" end
    if model then
        for _,name in ipairs({"Shiny","Luminous","Variant","VariantName","SpecialVariant"}) do
            local ok,value=pcall(function() return model:GetAttribute(name) end)
            if ok and value~=nil then
                if value==true and (name=="Shiny" or name=="Luminous") then return name end
                local s=tostring(value):lower()
                if s:find("shiny",1,true) then return "Shiny" end
                if s:find("luminous",1,true) then return "Luminous" end
            end
        end
    end
    return nil
end

function PatchSZ.isDecorative(model)
    if not model then return false end
    local parts=0
    local total=0
    for _,child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") then
            parts=parts+1
            total=total+child.Size.Magnitude
        end
    end
    return parts==0 or total<0.25
end

function PatchSZ.tagEvent(entry)
    local pet=tostring(entry and (entry.pet or entry.displayName) or "")
    local info=PatchSZ.eventEggs[pet]
    if not info then return nil end
    entry.eventSource=info.source
    if not entry.rarity or tostring(entry.rarity)=="" or tostring(entry.rarity)=="Unknown" then
        entry.rarity=info.rarity
    end
    return info
end

function PatchSZ.trackRestock(entry)
    local job=tostring(game.JobId or "")
    if PatchSZ.restockJob~=job then
        PatchSZ.restockJob=job
        PatchSZ.restockSlots={}
    end
    local key=tostring(entry.biomeName or entry.targetBiome or "").."#"..tostring(entry.nestIndex or 0)
    local sig=table.concat({
        tostring(entry.uid or ""),
        tostring(entry.eggFingerprint or ""),
        tostring(entry.pet or entry.displayName or ""),
    },"|")
    local previous=PatchSZ.restockSlots[key]
    local previousSig=nil
    local generation=0
    if type(previous)=="table" then
        previousSig=tostring(previous.sig or "")
        generation=tonumber(previous.generation) or 0
    elseif previous~=nil then
        previousSig=tostring(previous)
    end
    if previousSig and previousSig~="" and previousSig~=sig then
        generation=generation+1
        entry.restock=true
        entry.restockAt=nowUnix()
        pushPatchEvent("restock",{
            name=tostring(entry.pet or entry.displayName or "?"),
            rarity=tostring(entry.rarity or "Unknown"),
            biome=tostring(entry.biomeName or entry.targetBiome or ""),
            scale=tonumber(entry.scale),
            nest_index=tonumber(entry.nestIndex) or 0,
            generation=generation,
        })
    end
    entry.restockGeneration=generation
    PatchSZ.restockSlots[key]={sig=sig,generation=generation}
    return entry.restock==true
end

local function billboardIdentityForModel(model,slot)
    if not model then return nil end
    local data=model:FindFirstChild("Data",true)
    if not data then return nil end
    local display=data:FindFirstChild("DisplayName",true)
    if not display or not (display:IsA("TextLabel") or display:IsA("TextButton") or display:IsA("TextBox")) then return nil end
    local raw=tostring(display.Text or ""):match("^%s*(.-)%s*$") or ""
    if raw=="" or raw=="?" then return nil end
    local catalog,pet=lookupEggInfo(raw)
    if not catalog then return nil end
    local zone=tostring(slot and slot.zone or "")
    local home=tostring(catalog.biome or "")
    local compatible=(home==zone)
        or (zone=="Light Dark" and (home=="Angels" or home=="Demons"))
        or (zone=="Angels & Demons" and (home=="Angels" or home=="Demons"))
    if not compatible then return nil end
    local rarity=tostring(catalog.rarity or "Unknown")
    local odds=data:FindFirstChild("Odds",true)
    if odds and (odds:IsA("TextLabel") or odds:IsA("TextButton") or odds:IsA("TextBox")) then
        local t=tostring(odds.Text or "")
        for wanted in pairs(PATCH_TARGET_RARITIES) do
            if t:lower():find(tostring(wanted):lower(),1,true) then
                rarity=wanted
                break
            end
        end
    end
    return {pet=pet,egg=catalog.egg or (pet.." Egg"),rarity=rarity,biome=home,confidence=0.95}
end

local function realVisualMutation(model)
    if not model then return nil end
    local data=model:FindFirstChild("Data",true)
    local display=data and data:FindFirstChild("DisplayName",true)
    if not display or not (display:IsA("TextLabel") or display:IsA("TextButton") or display:IsA("TextBox")) then return nil end
    local name=tostring(display.Text or "")
    local mutation=nil
    if name:find("^Silver%s") then mutation="Silver"
    elseif name:find("^Golden%s") then mutation="Golden" end
    if not mutation then return nil end
    local fx=model:FindFirstChild("FXPart",true)
    if not fx then return nil end
    return mutation
end

local function validateCatalogEntry(entry)
    local catalog,canonical=lookupEggInfo(entry.pet or entry.displayName)
    if not catalog then return nil,"catalog_unknown" end
    local observed=tostring(entry.biomeName or entry.targetBiome or "")
    local home=tostring(catalog.biome or "")
    local compatible=(observed==home)
        or (observed=="Light Dark" and (home=="Angels" or home=="Demons"))
        or (observed=="Angels & Demons" and (home=="Angels" or home=="Demons"))
    if not compatible then return false,"catalog_biome_mismatch" end
    entry.pet=canonical
    entry.eggName=catalog.egg or entry.eggName or (canonical.." Egg")
    entry.rarity=catalog.rarity or entry.rarity
    entry.hatchMin=catalog.hatchMin
    entry.catalogValidated=true
    return true,"catalog"
end

local function updateQuarantine(entry)
    local biome=tostring(entry.biomeName or entry.targetBiome or "")
    local rarity=tostring(entry.rarity or entry.catalogRarity or "")
    if not PATCH_TARGET_BIOMES[biome] or not PATCH_TARGET_RARITIES[rarity] then return end
    local mutation=(entry.muts and entry.muts[1]) or nil
    local scale=tonumber(entry.scale) or 1
    local sizeTier=(scale>=2 and "huge") or (scale>=1.5 and "large") or (scale<=0.5 and "tiny") or (scale<=0.7 and "small") or "normal"
    if not mutation and sizeTier~="huge" and sizeTier~="tiny" and rarity~="Secret" then return end
    local score=50
    if mutation=="Golden" or mutation=="Gold" then score=score+40 elseif mutation=="Silver" then score=score+25 end
    if sizeTier=="huge" then score=score+15 elseif sizeTier=="tiny" then score=score+10 elseif sizeTier~="normal" then score=score+5 end
    if rarity=="Secret" then score=score+20 elseif rarity=="Cosmic" then score=score+15 elseif rarity=="Mythic" then score=score+10 end
    score=math.min(100,score)
    if not S.quarantinedEgg or score>tonumber(S.quarantinedEgg.valueScore or -1) then
        S.quarantinedEgg={uid=tostring(entry.uid or ""),name=tostring(entry.pet or "?"),rarity=rarity,biome=biome,scale=scale,mutation=mutation or "none",sizeTier=sizeTier,valueScore=score}
        S.quarantineUpdatedAt=nowUnix()
        pushPatchEvent("quarantine",S.quarantinedEgg)
    end
end

local function scanNow(mode,retryPass)
    local cycleScanContext=Runtime.captureCycleHopContext()
    retryPass=tonumber(retryPass) or 0
    FP.meshFingerprintCache=setmetatable({}, {__mode="k"})
    local t0=os.clock()
    local chatOnly=(mode=="chat")
    local premiumOnly=(mode=="premium" or chatOnly)
    local hint=(S.chatHint and (nowUnix()-(tonumber(S.chatHint.at) or 0)<=CFG.CHAT_HINT_TTL)) and S.chatHint or nil
    if S.chatHint and not hint then S.chatHint=nil end
    S.scanMode=chatOnly and "CHAT-TARGET" or (premiumOnly and "PREMIUM+DIVINE_GLOBAL" or "FULL")
    S.excludedBase=0
    S.excludedUncertain=0
    S.ownerMetadataSeen=0
    S.ownerMetadataReasons={}
    S.exclusionReasons={}
    S.biomeGroupCounts={}
    S.biomeWorldCounts={}
    S.natural5LearnedBiomes=0
    S.natural5OverflowExcluded=0
    S.natural5PartialGroups=0
    S.nestSlotsTotal=0
    S.nestSlotsResolved=0
    S.nestBiomeCounts={}
    S.nestUnresolved={}
    S.nestIdentityUnresolved={}
    S.qualityReasonCounts={}
    S.targetPreview={}
    S.eventFlags=eventFlagsSnapshot()

    -- Chat fast-path scans only the announced zone first. Premium fallback
    -- still inspects every target biome so we never depend exclusively on chat.
    local zoneFilter=(chatOnly and hint and hint.zone) and {[tostring(hint.zone)]=true} or nil
    local slots,biomeCounts=collectNestSlots(zoneFilter)
    if premiumOnly then
        pcall(writePremiumMetadataProbe,slots)
    end
    if premiumOnly then
        table.sort(slots,function(a,b)
            local az,bz=tostring(a.zone),tostring(b.zone)
            local ah=(hint and az==tostring(hint.zone)) and 0 or 1
            local bh=(hint and bz==tostring(hint.zone)) and 0 or 1
            if ah~=bh then return ah<bh end
            local ap=PREMIUM_ZONE_SET[az] and 0 or 1
            local bp=PREMIUM_ZONE_SET[bz] and 0 or 1
            if ap~=bp then return ap<bp end
            if az~=bz then return az<bz end
            return (tonumber(a.index) or 0)<(tonumber(b.index) or 0)
        end)
    end
    S.nestSlotsTotal=#slots
    S.nestBiomeCounts=biomeCounts
    S.biomeGroupCounts=biomeCounts

    if #slots==0 then
        S.rawEggs={}
        S.eggs={}
        S.targets={}
        S.qualifiedTargets={}
        S.skippedQuality=0
        S.lastEggCount=0
        S.lastError="GuardAreas/Nests no disponibles"
        if S.mode=="parked" then
            if not Runtime.parkedNestsMissing then
                logLine("PARKED · NESTS MISSING · retry 4s")
            end
            Runtime.parkedNestsMissing=true
            Runtime.parkedNestRetryAt=nowUnix()+4
            setState("PARKED","Nidos no disponibles · reintento 4s")
        end
        S.lastScanMs=math.max(1,math.floor((os.clock()-t0)*1000+0.5))
        return {}
    end

    if Runtime.parkedNestsMissing then
        Runtime.parkedNestsMissing=false
        Runtime.parkedNestRetryAt=nil
        if tostring(S.lastError or "")=="GuardAreas/Nests no disponibles" then S.lastError=nil end
        logLine("NESTS RECOVERED · "..tostring(#slots).." slots")
        if S.mode=="parked" then setState("PARKED","Nidos recuperados · vigilancia activa") end
    elseif tostring(S.lastError or "")=="GuardAreas/Nests no disponibles" then
        S.lastError=nil
    end

    local visuals=FP.collectVisuals()
    local sharedConflictVisualCount=0
    for _,candidate in ipairs(visuals or {}) do
        if tostring(candidate.fingerprint or "")==FP.CONFLICT_MUTANT_TRALA_FP then
            sharedConflictVisualCount=sharedConflictVisualCount+1
        end
    end
    local rendered=workspace:FindFirstChild("ClientRenderedAssets")
    local ignoredBase=rendered and #rendered:GetChildren() or 0
    S.baseRenderedIgnored=ignoredBase
    S.excludedBase=ignoredBase
    S.fingerprintKnown=0
    S.fingerprintUnknown=0
    S.staleSideVisuals=0
    S.sharedFingerprintConflicts=0
    S.blacklistedIdentity=0
    S.genericSlotShells=0
    S.noMeshIdentity=0
    S.unknownFingerprints={}
    S.unknownFingerprintDetails={}
    S.pendingFingerprintCandidates={}
    S.lightDarkSide=nil
    S.visualPresent=0

    local used={}
    local raw={}
    local world={}
    local worldCounts={}
    -- EggState mutation enrichment must never block the scan/hop path.
    -- Consume the last completed cache and refresh it in the background.
    local fieldJob=tostring(game.JobId or "")
    if tostring(PatchSZ.fieldRecordsCacheJob or "")~=fieldJob then
        PatchSZ.fieldRecordsCacheJob=fieldJob
        PatchSZ.fieldRecordsCache={}
    end
    local fieldRecordsByUid=PatchSZ.fieldRecordsCache or {}
    if PatchSZ.fieldRecordsRefreshBusy~=true then
        PatchSZ.fieldRecordsRefreshBusy=true
        task.spawn(function()
            local ok,records,readErr=pcall(PatchSZ.readFieldRecordsByUid)
            if ok and type(records)=="table" and tostring(game.JobId or "")==fieldJob then
                PatchSZ.fieldRecordsCache=records
                PatchSZ.fieldRecordsError=readErr
            elseif not ok then
                PatchSZ.fieldRecordsError=tostring(records)
            end
            PatchSZ.fieldRecordsRefreshBusy=false
        end)
    end

    -- VYRO-EXACT-FIRST-20261004: reserve exact ownership before near fallback.
    local exactMatches={}
    for index,slot in ipairs(slots) do
        local visual,distance=FP.exactForSlot(slot,visuals,used)
        exactMatches[index]={visual=visual,distance=distance}
    end

    for index,slot in ipairs(slots) do
        local exact=exactMatches[index]
        local visual,distance=exact.visual,exact.distance
        local matchKind=visual and "exact" or "none"

        if not visual then
            local near,nearDistance=FP.nearestForSlot(slot,visuals,used,CFG.NATURAL_SLOT_MATCH_TOLERANCE)
            if near then
                visual=near
                distance=nearDistance
                matchKind="near"
            end
        end

        local model=visual and visual.model or nil
        local fingerprint=visual and visual.fingerprint or nil
        local rawVisualName=model and readDisplayName(model) or ""
        local info=FP.infoForSlot(slot,fingerprint)
        local meta=metadataIdentityForSlot(slot,model)
        if not info and not meta then
            info=FP.dynamicInfoForSlot(slot,fingerprint)
        end
        local dynamicCandidate=nil
        if fingerprint then
            pcall(FP.loadDynamicCatalog)
            pcall(FP.loadLearnedCatalog)
            dynamicCandidate=FP.dynamicCatalog[tostring(fingerprint)] or FP.learnedCatalog[tostring(fingerprint)]
        end
        local catalogLive=nil
        if not info and not meta then
            catalogLive=catalogIdentityForSlot(slot,model)
        end
        local billboard=nil
        if not info and not meta and not catalogLive and model then
            billboard=billboardIdentityForModel(model,slot)
            if not billboard then
                local learned=FP.learnUnknownFromBillboard(model,slot,fingerprint)
                if not learned then
                    learned=FP.learnUnknownFromNearbyBillboard(slot,visuals,fingerprint)
                end
                if learned then
                    billboard={
                        pet=learned.pet,
                        egg=learned.egg,
                        rarity=learned.rarity,
                        biome=learned.biome,
                        confidence=0.95,
                        source="auto-learn-new",
                    }
                end
            end
        end

        local displayName="?"
        local rarity=nil
        local perSecond=nil
        local uid=nil
        local scale=nil
        local scaleSource=nil
        local scaleKind=nil
        local mutationSource=nil
        local confidence=0.0
        local reason="nest_unresolved"
        local identitySource="unresolved"
        local eggName=nil
        local side=FP.lightDarkSide(slot)

        if tostring(slot.zone)=="Light Dark" then
            S.lightDarkSide=side
        end

        if model then
            S.visualPresent=S.visualPresent+1
            uid=readUid(model) or tostring(model.Name)
            perSecond=readPerSecond(model)
            scale,scaleSource,scaleKind=getScale(model)

            if info then
                displayName=info.pet
                eggName=info.egg
                rarity=info.rarity
                local matchConfidence=(matchKind=="exact") and CFG.NEST_DIRECT_CONFIDENCE or CFG.NEST_NEAR_CONFIDENCE
                confidence=math.min(matchConfidence,tonumber(info.identity_confidence) or matchConfidence)
                reason="fingerprint:"..tostring(info.key)..":"..matchKind
                identitySource=(info.dynamic and "replicated_template_fingerprint+nest_" or "mesh_fingerprint+nest_")..matchKind
                S.fingerprintKnown=S.fingerprintKnown+1
            elseif meta then
                displayName=meta.display or meta.pet
                eggName=meta.egg
                rarity=meta.rarity
                confidence=CFG.NEST_METADATA_CONFIDENCE
                reason="client_metadata:"..tostring(meta.pet)..":"..matchKind
                identitySource="client_metadata+nest_"..matchKind
                local fp=tostring(fingerprint or "no_mesh_id")
                S.fingerprintUnknown=S.fingerprintUnknown+1
                S.unknownFingerprints[fp]=(S.unknownFingerprints[fp] or 0)+1
                if #S.unknownFingerprintDetails<12 then
                    S.unknownFingerprintDetails[#S.unknownFingerprintDetails+1]=probeUnknownFingerprint(slot,model,fingerprint,distance,matchKind)
                end
            elseif catalogLive then
                displayName=catalogLive.display or catalogLive.pet
                eggName=catalogLive.egg
                rarity=catalogLive.rarity
                local base=(matchKind=="exact") and 0.975 or 0.945
                confidence=base
                reason="live_catalog:"..tostring(catalogLive.pet)..":"..matchKind
                identitySource="live_display_catalog+nest_"..matchKind
                local fp=tostring(fingerprint or "no_mesh_id")
                S.fingerprintUnknown=S.fingerprintUnknown+1
                S.unknownFingerprints[fp]=(S.unknownFingerprints[fp] or 0)+1
                if #S.unknownFingerprintDetails<12 then
                    S.unknownFingerprintDetails[#S.unknownFingerprintDetails+1]=probeUnknownFingerprint(slot,model,fingerprint,distance,matchKind)
                end
                local fpLearn=tostring(fingerprint or "no_mesh_id")
                local canLearn=(matchKind=="exact" and fpLearn~="no_mesh_id" and confidence>=0.95)
                if tostring(catalogLive.pet)=="Mutant Shark" and not buyerAnnouncementGate("Mutant Shark") then
                    canLearn=false
                end
                if canLearn then
                    local learned=FP.learnFingerprint(fpLearn,catalogLive.pet,catalogLive.rarity,tostring(slot.zone))
                    if learned then reason=reason.."|fingerprint_learned" end
                end
            elseif billboard then
                displayName=billboard.pet
                eggName=billboard.egg
                rarity=billboard.rarity
                confidence=tonumber(billboard.confidence) or 0.94
                local learnedNew=tostring(billboard.source or "")=="auto-learn-new"
                reason=(learnedNew and "auto_learn_new:" or "billboard_gui:")..tostring(billboard.pet)..":"..matchKind
                identitySource=(learnedNew and "auto-learn-new+nest_" or "billboard_gui+nest_")..matchKind
                local fp=tostring(fingerprint or "no_mesh_id")
                S.fingerprintUnknown=S.fingerprintUnknown+1
                S.unknownFingerprints[fp]=(S.unknownFingerprints[fp] or 0)+1
                local canLearn=(not learnedNew and matchKind=="exact" and fp~="no_mesh_id" and confidence>=0.95)
                if tostring(billboard.pet)=="Mutant Shark" and not buyerAnnouncementGate("Mutant Shark") then
                    canLearn=false
                end
                if canLearn then
                    local learned=FP.learnFingerprint(fp,billboard.pet,billboard.rarity,tostring(slot.zone))
                    if learned then
                        reason=reason.."|fingerprint_learned"
                    end
                end
            else
                local fp=tostring(fingerprint or "no_mesh_id")
                local activeSide=FP.lightDarkSide(slot)
                local candidateHome=dynamicCandidate and tostring(dynamicCandidate.biome or dynamicCandidate.side or "") or ""
                if fp==FP.CONFLICT_MUTANT_TRALA_FP then
                    S.sharedFingerprintConflicts=(tonumber(S.sharedFingerprintConflicts) or 0)+1
                    confidence=0
                    reason="shared_fingerprint_conflict:"..fp..":"..matchKind
                    identitySource="shared_fingerprint_conflict"
                elseif dynamicCandidate and tostring(slot.zone)=="Light Dark"
                    and (candidateHome=="Angels" or candidateHome=="Demons")
                    and activeSide~="Angels & Demons" and candidateHome~=activeSide
                then
                    S.staleSideVisuals=(tonumber(S.staleSideVisuals) or 0)+1
                    confidence=0
                    reason="stale_side_visual:"..candidateHome.."->"..activeSide..":"..matchKind
                    identitySource="stale_side_visual"
                elseif model and tostring(model.Name):find("FirstAreaEgg_",1,true)==1 then
                    S.genericSlotShells=(tonumber(S.genericSlotShells) or 0)+1
                    confidence=0
                    reason="generic_slot_shell:"..fp..":"..matchKind
                    identitySource="generic_slot_shell"
                elseif FP.learnedFpBlacklist[fp] then
                    S.blacklistedIdentity=(tonumber(S.blacklistedIdentity) or 0)+1
                    confidence=0
                    reason="blacklisted_identity:"..fp..":"..matchKind
                    identitySource="blacklisted_identity"
                elseif fp=="no_mesh_id" then
                    S.noMeshIdentity=(tonumber(S.noMeshIdentity) or 0)+1
                    S.fingerprintUnknown=S.fingerprintUnknown+1
                    S.unknownFingerprints[fp]=(S.unknownFingerprints[fp] or 0)+1
                    confidence=0.70
                    reason="no_mesh_identity:"..matchKind
                    identitySource="no_mesh_identity"
                else
                    S.fingerprintUnknown=S.fingerprintUnknown+1
                    S.unknownFingerprints[fp]=(S.unknownFingerprints[fp] or 0)+1
                    if #S.unknownFingerprintDetails<12 then
                        S.unknownFingerprintDetails[#S.unknownFingerprintDetails+1]=probeUnknownFingerprint(slot,model,fingerprint,distance,matchKind)
                    end
                    confidence=0.80
                    reason="unknown_fingerprint:"..fp..":"..matchKind
                    identitySource="mesh_fingerprint_unknown"
                end
            end
        end

        -- Metadata-first fallback: the nest is authoritative enough to identify
        -- a target even when ClientRenderedAssets has not rendered a nearby model.
        -- This is critical for low-FPS/headless scanner sessions.
        if not model and meta then
            displayName=meta.display or meta.pet
            eggName=meta.egg
            rarity=meta.rarity
            confidence=CFG.NEST_METADATA_CONFIDENCE
            reason="nest_metadata:"..tostring(meta.pet)
            identitySource="nest_metadata"
            uid=valueByNames(slot.nest,{"UID","EggUID","PetUID","SpawnUID","Id"})
                or (slot.zone..":"..tostring(slot.index)..":"..tostring(game.JobId))
            perSecond=valueByNames(slot.nest,{"PerSecond","Income","IncomePerSecond","Generation","Generates"})
            local nestScale=valueByNames(slot.nest,{
                "Scale","AssetScale","EggScale","SizeScale","SizeMultiplier","PetScale","VisualScale"
            })
            if nestScale~=nil then
                scale=tonumber(nestScale)
                if scale then
                    scaleSource="nest_metadata"
                    scaleKind="nest_metadata_scale"
                end
            end
        end

        local muts,pet=parseDisplayName(displayName)
        if info and info.pet then
            pet=info.pet
            -- Keep mutations parsed from the live display name. The fingerprint
            -- identifies the base pet, but it must not erase server mutations.
            muts=info.muts or muts
        elseif meta and meta.pet then
            pet=meta.pet
            muts=meta.muts or muts
        elseif catalogLive and catalogLive.pet then
            pet=catalogLive.pet
            muts=catalogLive.muts or muts
        elseif billboard and billboard.pet then
            pet=billboard.pet
        end

        -- Identity may come from a fingerprint, but mutations belong to the live
        -- rendered egg. Preserve mutation prefixes from the raw visual label before
        -- canonical pet naming can erase them (Rainbow, Spirit Bloom, etc.).
        local visualMuts={}
        if rawVisualName~="" then
            visualMuts=select(1,parseDisplayName(rawVisualName)) or {}
            if #visualMuts>0 then mutationSource="live_display_name" end
        end
        for _,m in ipairs(visualMuts) do
            local canonicalMutation=normalizeMutationName(m) or tostring(m)
            local exists=false
            for _,existing in ipairs(muts or {}) do
                if (normalizeMutationName(existing) or tostring(existing))==canonicalMutation then exists=true break end
            end
            if not exists then
                muts=muts or {}
                muts[#muts+1]=canonicalMutation
                mutationSource="live_display_name"
            end
        end

        local visualMutation=realVisualMutation(model)
        if visualMutation then
            local canonicalMutation=normalizeMutationName(visualMutation) or tostring(visualMutation)
            local exists=false
            for _,m in ipairs(muts or {}) do
                if (normalizeMutationName(m) or tostring(m))==canonicalMutation then exists=true break end
            end
            if not exists then
                muts=muts or {}
                muts[#muts+1]=canonicalMutation
                mutationSource=mutationSource or "live_visual_fx"
            end
        end

        -- Exact UID join against the game's already-replicated field egg record.
        -- Scanner identity/visual scale stay untouched. EggState scale is only
        -- carried forward as a separately validated payload enrichment.
        local eggStateChanged=false
        muts,eggStateChanged=PatchSZ.mergeEggStateMutations(uid,muts,fieldRecordsByUid)
        if eggStateChanged then mutationSource="eggstate_record" end

        muts=retailMutations(muts)
        if not mutationSource and #(muts or {})>0 then mutationSource="identity_metadata" end

        local recognized=(info~=nil or meta~=nil or catalogLive~=nil or billboard~=nil)

        -- Mutant Shark and Tralaledon share this mesh fingerprint. Mesh alone
        -- is never authoritative. IMPORTANT: resolve from RAW live/nest text,
        -- never from displayName after fingerprint classification, otherwise the
        -- static fingerprint entry could self-confirm as Mutant Shark.
        if tostring(fingerprint or "")==FP.CONFLICT_MUTANT_TRALA_FP then
            local rawConflictName=(model and readDisplayName(model)) or nestMetadataName(slot) or ""
            local _,rawConflictPet=parseDisplayName(tostring(rawConflictName))
            local conflictName=Shared.__VYRO_NORMALIZE_EGG_NAME(rawConflictPet or rawConflictName)
            if conflictName=="mutant shark" then
                pet="Mutant Shark"
                displayName="Mutant Shark"
                eggName="Mutant Shark Egg"
                rarity=rarity or "Secret"
                reason=tostring(reason).."|shared_fp_raw_name_confirmed:mutant_shark"
                recognized=true
            elseif conflictName=="tralaledon" then
                pet="Tralaledon"
                displayName="Tralaledon"
                eggName="Tralaledon Egg"
                rarity=rarity or "Secret"
                reason=tostring(reason).."|shared_fp_raw_name_confirmed:tralaledon"
                recognized=true
            elseif hint
                and sharedConflictVisualCount==1
                and tostring(hint.pet)=="Mutant Shark"
                and tostring(hint.zone)=="Titan Temple"
                and tostring(hint.job or "")==tostring(game.JobId)
                and tostring(slot.zone)=="Titan Temple"
            then
                pet="Mutant Shark"
                displayName="Mutant Shark"
                eggName="Mutant Shark Egg"
                rarity=rarity or "Secret"
                confidence=math.max(tonumber(confidence) or 0,0.995)
                reason="shared_fingerprint_chat_confirmed:mutant_shark:"..tostring(matchKind)
                identitySource="shared_fingerprint+chat_confirmed+nest_"..tostring(matchKind)
                recognized=true
            else
                recognized=false
                confidence=0
                reason="shared_fingerprint_unconfirmed_raw_name:"..tostring(rawConflictName)
                identitySource="shared_fingerprint_ambiguous"
                print("[VYRO-DEBUG] Fingerprint conflictivo sin nombre crudo válido: "..tostring(rawConflictName))
            end
        end

        -- Some canonical pet names contain a mutation-looking word. Never
        -- treat that intrinsic name token as an applied mutation.
        if tostring(pet)=="Mutant Shark" and type(muts)=="table" then
            local cleaned={}
            for _,m in ipairs(muts) do
                local canonicalMutation=normalizeMutationName(m) or tostring(m)
                if canonicalMutation~="Mutant" then cleaned[#cleaned+1]=canonicalMutation end
            end
            muts=retailMutations(cleaned)
            if #muts==0 and mutationSource=="identity_metadata" then mutationSource=nil end
        end

        -- Join after final shared-fingerprint identity resolution; a prior pet name
        -- must never authorize the saved scale of a different emitted pet.
        local eggStateScale,eggStateScaleRecord,eggStateScaleMatch=
            PatchSZ.safeEggStateScale(uid,slot,pet,fieldRecordsByUid)

        local visualResolved=(model~=nil and distance and distance<=CFG.NATURAL_SLOT_MATCH_TOLERANCE)
        local metadataResolved=(meta~=nil and nestMetadataName(slot)~=nil)
        local source=(recognized and (visualResolved or metadataResolved)
            and confidence>=CFG.WORLD_MIN_CONFIDENCE) and "world_spawn" or "world_candidate"

        if source=="world_spawn" and model then
            used[model]=true
        end

        local entry={
            uid=uid or (slot.zone..":"..tostring(slot.index)..":"..tostring(game.JobId)),
            eventId=slot.eventId,
            biomeId=slot.zone,
            biomeName=slot.zone,
            displayName=tostring(displayName),
            rawVisualName=tostring(rawVisualName or ""),
            pet=tostring(pet),
            eggName=eggName,
            muts=muts,
            mutationSource=mutationSource or "none",
            scale=scale,
            visualScale=scale,
            visualScaleSource=scaleSource or "unknown",
            visualScaleKind=scaleKind or "unknown",
            eggStateScale=eggStateScale,
            eggStateScaleMatch=eggStateScaleMatch,
            eggStateAssetCategory=(type(eggStateScaleRecord)=="table" and tostring(eggStateScaleRecord.AssetCategory or "")) or "",
            scaleSource=scaleSource or "unknown",
            scaleKind=scaleKind or "unknown",
            rarity=rarity,
            perSecond=perSecond,
            source=source,
            sourceConfidence=confidence,
            locationReason=reason,
            identitySource=identitySource,
            identityConfidence=confidence,
            eggFingerprint=fingerprint,
            previewAssetId=FP.previewAssetId(model,fingerprint),
            fingerprintKey=info and info.key or nil,
            nestIndex=slot.index,
            nestPosition=slot.position,
            nestDistance=distance,
            detectedSide=side,
            matchKind=matchKind,
            _position=slot.position,
            _model=model,
        }

        if model and PatchSZ.isDecorative(model) then
            entry.isFake=true
            entry.source="world_candidate"
            entry.sourceConfidence=math.min(tonumber(entry.sourceConfidence) or 0,0.40)
            entry.locationReason=tostring(entry.locationReason or "").."|decorative_filter"
        end

        local explicitVariant=PatchSZ.explicitVariant(model,entry.displayName)
        if explicitVariant then entry.specialVariant=explicitVariant end

        enrichCatalog(entry)
        local eventInfo=PatchSZ.tagEvent(entry)
        local fallbackRarity=rawget(entry,"catalogRarity")
        if not entry.rarity and fallbackRarity then entry.rarity=fallbackRarity end
        local catalogValid,catalogReason=validateCatalogEntry(entry)
        if catalogValid==false and entry.source=="world_spawn" then
            entry.source="world_candidate"
            entry.sourceConfidence=math.min(tonumber(entry.sourceConfidence) or 0,0.80)
            entry.locationReason=tostring(entry.locationReason or "").."|"..tostring(catalogReason)
        end
        if entry.source~="world_spawn" then
            Shared.__VYRO_DEBUG_IGNORED_EGG(entry,entry.locationReason or "world_candidate")
        end
        if entry.source=="world_candidate" and entry.eggFingerprint and PATCH_TARGET_BIOMES[tostring(entry.biomeName or "")] then
            local fp=tostring(entry.eggFingerprint)
            S.pendingFingerprintCandidates[#S.pendingFingerprintCandidates+1]={
                fingerprint=fp,biome=tostring(entry.biomeName or ""),nest_index=tonumber(entry.nestIndex) or 0,
                uid=tostring(entry.uid or ""),at=nowUnix(),model_name=entry._model and tostring(entry._model.Name) or "",
            }
            local key=tostring(entry.biomeName or "").."|"..fp
            if not S.newEggSeen[key] then
                S.newEggSeen[key]=nowUnix()
                pushPatchEvent("new_egg",{biome=tostring(entry.biomeName or ""),fingerprint=fp,nest_index=tonumber(entry.nestIndex) or 0})
            end
        end
        -- If the system announcement includes a mutation, use it as an
        -- immediate high-confidence hint for the announced target only.
        if hint and hint.mutation
            and tostring(targetPetKey(entry))==tostring(hint.pet)
            and tostring(slot.zone)==tostring(hint.zone)
        then
            local exists=false
            for _,m in ipairs(entry.muts or {}) do
                if tostring(m)==tostring(hint.mutation) then
                    exists=true
                    break
                end
            end
            if not exists then
                entry.muts=entry.muts or {}
                entry.muts[#entry.muts+1]=tostring(hint.mutation)
            end
        end

        if hint
            and tostring(targetPetKey(entry))==tostring(hint.pet)
            and tostring(slot.zone)==tostring(hint.zone)
            and tostring(hint.job or "")==tostring(game.JobId)
        then
            entry.chatConfirmed=true
            entry.chatAnnouncementAt=tonumber(hint.at)
            entry.eventId=tostring(hint.eventId or "")
            entry.locationReason=tostring(entry.locationReason or "").."|chat_confirmed"
        end

        if entry.specialVariant then
            local key="variant|"..tostring(entry.uid).."|"..tostring(entry.specialVariant)
            if not S.newEggSeen[key] then
                S.newEggSeen[key]=nowUnix()
                pushPatchEvent("special_variant",{
                    name=tostring(entry.pet or entry.displayName or "?"),
                    biome=tostring(entry.biomeName or ""),
                    variant=tostring(entry.specialVariant),
                })
            end
        end
        if eventInfo then
            local key="event|"..tostring(entry.uid).."|"..tostring(eventInfo.source)
            if not S.newEggSeen[key] then
                S.newEggSeen[key]=nowUnix()
                pushPatchEvent("event_egg",{
                    name=tostring(entry.pet or entry.displayName or "?"),
                    rarity=tostring(entry.rarity or eventInfo.rarity or "Unknown"),
                    biome=tostring(entry.biomeName or ""),
                    event=tostring(eventInfo.source),
                })
            end
        end

        if entry.source=="world_spawn" then
            PatchSZ.trackRestock(entry)
            updateQuarantine(entry)
        end
        raw[#raw+1]=entry

        if entry.source=="world_spawn" then
            world[#world+1]=entry
            worldCounts[slot.zone]=(worldCounts[slot.zone] or 0)+1
            S.nestSlotsResolved=S.nestSlotsResolved+1
        else
            local dist=(distance and distance<math.huge) and string.format("%.2f",distance) or "inf"
            local fp=tostring(fingerprint or "none")
            local metaName=tostring((meta and meta.pet) or nestMetadataName(slot) or "")
            local diagnostic=string.format(
                "%s#%d dist=%s match=%s fp=%s meta=%s",
                tostring(slot.zone),tonumber(slot.index) or 0,dist,matchKind,fp,metaName
            )
            -- A nest can be spatially resolved even when identity is intentionally
            -- withheld (shared/blacklisted mesh fingerprints). Do not retry those.
            if visualResolved or metadataResolved then
                S.nestSlotsResolved=S.nestSlotsResolved+1
                S.nestIdentityUnresolved[#S.nestIdentityUnresolved+1]=diagnostic
            else
                S.nestUnresolved[#S.nestUnresolved+1]=diagnostic
            end
            S.excludedUncertain=S.excludedUncertain+1
        end
    end

    -- SEND-ALL architecture: never delay the first raw payload while waiting
    -- for unresolved nests. Background 1s retries are scheduled by writeSnapshot().

    if type(Shared.__VYRO_EXEC._WF)=="function" and (S.excludedUncertain or 0)>0 then
        local preview={}
        for i,entry in ipairs(raw) do
            if i>24 then break end
            preview[#preview+1]={
                zone=tostring(entry.biomeName or ""),
                nest_index=tonumber(entry.nestIndex) or 0,
                display=tostring(entry.displayName or ""),
                pet=tostring(entry.pet or ""),
                rarity=tostring(entry.rarity or entry.catalogRarity or ""),
                source=tostring(entry.source or ""),
                confidence=tonumber(entry.sourceConfidence) or 0,
                reason=tostring(entry.locationReason or ""),
                identity_source=tostring(entry.identitySource or ""),
                fingerprint=tostring(entry.eggFingerprint or ""),
                scale=tonumber(entry.scale),
                scale_source=tostring(entry.scaleSource or ""),
                match=tostring(entry.matchKind or ""),
                distance=(entry.nestDistance and entry.nestDistance<math.huge) and entry.nestDistance or nil,
                model_name=entry._model and tostring(entry._model.Name) or "",
                model_path=entry._model and tostring(entry._model:GetFullName()) or "",
            }
        end
        local payload={
            version=CFG.VERSION,
            job_id=tostring(game.JobId),
            at=nowUnix(),
            raw_count=#raw,
            world_count=#world,
            excluded_uncertain=S.excludedUncertain or 0,
            fingerprint_known=S.fingerprintKnown or 0,
            fingerprint_unknown=S.fingerprintUnknown or 0,
            unknown_details=S.unknownFingerprintDetails or {},
            unresolved=S.nestUnresolved or {},
            identity_unresolved=S.nestIdentityUnresolved or {},
            preview=preview,
        }
        pcall(function()
            Shared.__VYRO_EXEC._WF("VYRO_UNRESOLVED_PROBE_"..tostring(LP.UserId)..".json",HttpService:JSONEncode(payload))
        end)
    end

    local function byZoneScale(a,b)
        if tostring(a.biomeName)~=tostring(b.biomeName) then
            return tostring(a.biomeName)<tostring(b.biomeName)
        end
        local as,bs=a.scale or -1,b.scale or -1
        if as~=bs then return as>bs end
        return tostring(a.pet)<tostring(b.pet)
    end

    table.sort(raw,byZoneScale)
    table.sort(world,byZoneScale)

    S.rawEggs=raw
    S.eggs=world
    S.biomeWorldCounts=worldCounts
    for _,count in pairs(worldCounts) do
        if count==CFG.NATURAL_EGGS_PER_BIOME then
            S.natural5LearnedBiomes=S.natural5LearnedBiomes+1
        end
    end
    S.natural5PartialGroups=math.max(0,countKeys(biomeCounts)-S.natural5LearnedBiomes)

    S.targets=select(1,classifyTargets(world))
    S.serverSeenTargetUids=S.serverSeenTargetUids or {}
    for _,entry in ipairs(S.targets or {}) do
        local uid=tostring(entry.uid or "")
        if uid~="" then S.serverSeenTargetUids[uid]=true end
    end
    S.carriedTargets=collectCarriedTargets()
    -- Publish every whitelisted retail target, but keep special announcement
    -- gates on the main payload too. Size/value filtering still belongs in Buyer.
    local publishable={}
    for _,entry in ipairs(S.targets or {}) do
        local canonicalPet=targetPetKey(entry)
        if buyerAnnouncementGate(canonicalPet) then
            entry.commercialQualified=true
            entry.qualityReason=entry.qualityReason or "retail_target"
            publishable[#publishable+1]=entry
        else
            entry.commercialQualified=false
            entry.qualityReason="mutant_shark_unannounced"
        end
    end
    S.qualifiedTargets=publishable
    S.skippedQuality=math.max(0,#(S.targets or {})-#publishable)

    local reasonCounts={}
    local preview={}
    for i,entry in ipairs(S.targets or {}) do
        local reason=tostring(entry.qualityReason or "unknown")
        reasonCounts[reason]=(reasonCounts[reason] or 0)+1
        if i<=12 then
            preview[#preview+1]={
                pet=tostring(entry.pet or "?"),
                rarity=tostring(entry.rarity or entry.catalogRarity or "Unknown"),
                scale=tonumber(entry.scale),
                biome=tostring(entry.targetBiome or entry.biomeName or ""),
                reason=reason,
                confidence=tonumber(entry.sourceConfidence) or 0,
                source=tostring(entry.source or ""),
                match=tostring(entry.matchKind or ""),
            }
        end
    end
    S.qualityReasonCounts=reasonCounts
    S.targetPreview=preview
    S.lastVisualExpected=#slots
    S.lastVisualMatched=S.visualPresent
    S.lastEggCount=#world
    S.scans=S.scans+1
    S.lastScanMs=math.max(1,math.floor((os.clock()-t0)*1000+0.5))
    S.lastError=nil
    if mode~="chat" and Runtime.cycleContextValid(cycleScanContext)
        and cycleScanContext.dayReady and S.nestSlotsTotal>0 then
        Runtime.cycleScanResult=cycleScanContext
    end
    readMemory()
    if type(saveState)=="function" then pcall(saveState) end
    return world
end

local function waitForStableAssets(mode)
    local t0=time()
    local premiumOnly=(mode=="premium")
    local timeout=premiumOnly and CFG.PREMIUM_SCAN_TIMEOUT or CFG.ASSET_TIMEOUT
    local poll=premiumOnly and CFG.PREMIUM_SCAN_POLL or CFG.ASSET_POLL
    local stableWindow=premiumOnly and CFG.PREMIUM_STABLE_WINDOW or CFG.ASSET_STABLE_WINDOW
    local filter=premiumOnly and PREMIUM_ZONE_SET or nil
    local lastSlots=-1
    local lastMatched=-1
    local lastChange=t0
    local finalSlots=0
    local finalMatched=0
    local finalZonesReady=false
    local finalComplete=false
    local readyAt=nil
    local deadline=t0+timeout
    local readyDeadline=t0+(premiumOnly and CFG.PREMIUM_READY_TIMEOUT or timeout)
    local visualHardDeadline=nil

    while Runtime.alive do
        local now=time()
        local slots=select(1,collectNestSlots(filter))
        local visuals=FP.collectVisuals(false)
        local slotCount=#slots
        local matched=FP.countExactMatches(slots,visuals)
        -- READ25: require all five distinct premium biomes, including Enchanted.
        local zoneCounts={}
        for _,slot in ipairs(slots) do
            local zone=Runtime.canonicalBiome(slot.zone)
            if zone=="Angels & Demons" then zone="Light Dark" end
            zoneCounts[zone]=(zoneCounts[zone] or 0)+1
        end
        local zonesReady=slotCount>=CFG.PREMIUM_EXPECTED_SLOTS
        for _,zone in ipairs({"Cosmic","Cherry Blossom","Titan Temple","Light Dark","Enchanted Forest"}) do
            if (zoneCounts[zone] or 0)<5 then zonesReady=false end
        end
        finalZonesReady=zonesReady
        finalComplete=(not premiumOnly or zonesReady) and slotCount>0 and matched>=slotCount

        finalSlots=slotCount
        finalMatched=matched

        if slotCount~=lastSlots or matched~=lastMatched then
            lastSlots=slotCount
            lastMatched=matched
            lastChange=now
        end

        if premiumOnly then
            -- Model readiness is independent of Roblox IsLoaded().
            -- Keep the bounded grace period for partially streamed premium zones.
            if not readyAt then
                if zonesReady or now>=readyDeadline then
                    readyAt=now
                    visualHardDeadline=now+CFG.PREMIUM_VISUAL_HARD_TIMEOUT
                end
            end
            if readyAt then
                if finalComplete and (now-lastChange)>=stableWindow then
                    break
                end
                if now>=visualHardDeadline then break end
            end
        else
            if slotCount>0 and matched>=slotCount and (now-lastChange)>=stableWindow then
                break
            end
            if now>=deadline then break end
        end

        task.wait(poll)
    end

    local finished=time()
    S.lastReadyWaitMs=math.max(0,math.floor(((readyAt or finished)-t0)*1000+0.5))
    S.lastVisualWaitMs=readyAt and math.max(0,math.floor((finished-readyAt)*1000+0.5)) or 0
    S.lastVisualExpected=finalSlots
    S.lastVisualMatched=finalMatched
    S.lastStableWaitMs=math.max(1,math.floor((finished-t0)*1000+0.5))
    S.lastStableJobId=tostring(game.JobId)

    local ok,result=pcall(scanNow,mode)
    if ok then
        if premiumOnly then
            S.premiumReadComplete=finalComplete
            S.readinessPolicy="premium25-v1"
            if not finalComplete then
                S.lastError="premium_assets_incomplete:"..tostring(finalMatched).."/"..tostring(finalSlots)
                    ..(finalZonesReady and "" or ":missing_biomes")
            end
        end
        return result
    end

    S.lastError="scanNow:"..tostring(result)
    logLine("SCAN ERROR Â· "..tostring(result))
    return S.eggs or {}
end

local function dictToArray(dict)
    local out = {}
    for k,v in pairs(dict or {}) do
        if v then out[#out+1] = tostring(k) end
    end
    return out
end

local function arrayToDict(arr)
    local out = {}
    if type(arr)=="table" then
        for _,v in ipairs(arr) do out[tostring(v)] = true end
    end
    return out
end

saveState = function()
    if type(Shared.__VYRO_EXEC._WF) ~= "function" then return false end
    local payload = {
        version=CFG.VERSION,
        mode=S.mode,
        state=S.state,
        huntEnd=S.huntEnd,
        huntStartedAt=S.huntStartedAt,
        huntHopsStart=S.huntHopsStart,
        testDuration=S.testDuration,
        teleportRetryCount=S.teleportRetryCount or 0,
        lastHopAttempt=S.lastHopAttempt,
        lastHopTarget=S.lastHopTarget,
        lastHopAccepted=S.lastHopAccepted,
        currentJobId=S.currentJobId,
        silentTeleportFailures=S.silentTeleportFailures or 0,
        visited=dictToArray(S.visited),
        landedJobs=dictToArray(S.landedJobs),
        hops=S.hops,
        serverQueue=S.serverQueue,
        serverFetchNotBefore=S.serverFetchNotBefore,
        landedJobId=S.landedJobId,
        pendingJobId=S.pendingJobId,
        pendingStartedMs=S.pendingStartedMs,
        teleportAvgSec=S.teleportAvgSec,
        teleportSuccessSamples=S.teleportSuccessSamples,
        adaptiveWatchdogSec=S.adaptiveWatchdogSec,
        cycleFingerprint=S.cycleFingerprint,
        lastCycleEdgeAt=S.lastCycleEdgeAt,
        previousCycleEdgeAt=S.previousCycleEdgeAt,
        observedCycleSeconds=S.observedCycleSeconds,
        cycleEdgeCount=S.cycleEdgeCount,
        learnedWorldSlots=S.learnedWorldSlots,
    }
    local ok = pcall(function()
        Shared.__VYRO_EXEC._WF(STATE_FILE,HttpService:JSONEncode(payload))
    end)
    return ok
end

local function loadState()
    if type(Shared.__VYRO_EXEC._RF)~="function" or type(Shared.__VYRO_EXEC._IF)~="function" then return nil end
    local ok,data = pcall(function()
        if not Shared.__VYRO_EXEC._IF(STATE_FILE) then return nil end
        return HttpService:JSONDecode(Shared.__VYRO_EXEC._RF(STATE_FILE))
    end)
    if ok and type(data)=="table" then return data end
    return nil
end

local function clearState()
    if type(Shared.__VYRO_EXEC._IF)=="function" and type(Shared.__VYRO_EXEC._DF)=="function" then
        pcall(function()
            if Shared.__VYRO_EXEC._IF(STATE_FILE) then Shared.__VYRO_EXEC._DF(STATE_FILE) end
        end)
    end
end

local function writeStatus()
    if type(Shared.__VYRO_EXEC._WF)~="function" then return false end

    local biggest = S.qualifiedTargets[1] or S.targets[1]
    local payload = {
        version=CFG.VERSION,
        account_name=tostring(LP.Name),
        display_name=tostring(LP.DisplayName or LP.Name),
        user_id=tostring(LP.UserId),
        place_id=tostring(game.PlaceId),
        job_id=tostring(game.JobId),

        state=S.state,
        state_detail=S.stateDetail,
        mode=S.mode,
        hunt_remaining=huntRemaining(),
        hunt_end=S.huntEnd,

        raw_eggs=#(S.rawEggs or {}),
        world_eggs=#S.eggs,
        excluded_base=S.excludedBase or 0,
        excluded_uncertain=S.excludedUncertain or 0,
        base_regions=#(S.baseRegions or {}),
        eggs=#S.qualifiedTargets,
        targets=#S.targets,
        qualified_eggs=#S.qualifiedTargets,
        skipped_quality=S.skippedQuality or 0,
        quality_policy_version=S.qualityPolicyVersion,
        biggest_target=biggest and {
            pet=biggest.pet,
            scale=biggest.scale,
            target=biggest.targetBiome,
            biome_id=biggest.biomeId,
            mutations=biggest.muts,
        } or nil,

        scan_mode=S.scanMode,
        visual_expected=S.lastVisualExpected or 0,
        visual_matched=S.lastVisualMatched or 0,
        scan_ms=S.lastScanMs,
        stable_wait_ms=S.lastStableWaitMs,
        ready_wait_ms=S.lastReadyWaitMs,
        visual_wait_ms=S.lastVisualWaitMs,
        scans=S.scans,
        total_eggs_sent=S.totalEggsSent or 0,
        last_eggs_sent=S.lastEggsSent or 0,
        backend_whitelist_accepted=S.lastRawAccepted or 0,
        backend_whitelist_ignored=S.lastRawIgnored or 0,
        duplicate_rows_dropped=S.lastDuplicateRowsDropped or 0,
        hops=S.hops,
        servers_per_min=serversPerMinute(),

        queue_available=S.queueAvailable,
        reexec_armed=S.reexecArmed,
        reexec_error=S.reexecError,
        pending_job_id=S.pendingJobId,
        pending_started_ms=S.pendingStartedMs,
        joining_elapsed_ms=(S.pendingStartedMs and math.max(0,nowMs()-S.pendingStartedMs) or nil),
        server_queue=#S.serverQueue,
        visited_servers=countKeys(S.visited),
        last_hop_attempt=S.lastHopAttempt,
        last_hop_target=S.lastHopTarget,
        current_job_id=S.currentJobId,
        landing_confirmed_at=S.lastLandingConfirmedAt,
        landing_confirmed_ms=S.lastLandingConfirmedMs,
        landing_confirmed_job=S.lastLandingConfirmedJob,
        landing_pending_job=S.lastLandingPendingJob,
        silent_teleport_failures=S.silentTeleportFailures or 0,
        last_http_status=S.lastServerHttpStatus,
        server_pool_source=S.serverPoolSource,
        server_pool_count=S.serverPoolCount,
        server_pool_generation=S.serverPoolGeneration,
        server_pool_cache_age=S.serverPoolCacheAge,

        phase=S.phase,
        lighting_clock_time=S.lightingClockTime,
        day_night_eta_seconds=S.dayNightEtaSeconds,
        cycle_eta_seconds=S.cycleEtaSeconds,
        cycle_eta_source=S.cycleEtaSource,
        cycle_winner=S.cycleWinner,
        cycle_edge_count=S.cycleEdgeCount,
        last_cycle_edge_at=S.lastCycleEdgeAt,
        observed_cycle_seconds=S.observedCycleSeconds,
        fleet_cycle_generation=S.fleetCycleGeneration or 0,
        fleet_cycle_epoch=S.fleetCycleEpoch,
        fleet_cycle_end=S.fleetCycleEnd,
        fleet_cycle_phase=S.fleetCyclePhase,

        memory_mb=S.memoryMb,
        instance_count=S.instanceCount,
        base_map_resolved=S.baseMapResolved==true,
        base_regions=#(S.baseRegions or {}),
        nest_slots_total=S.nestSlotsTotal or 0,
        nest_slots_resolved=S.nestSlotsResolved or 0,
        nest_slot_source=S.nestSlotSource or "none",
        nest_unresolved=S.nestUnresolved or {},
        nest_identity_unresolved=S.nestIdentityUnresolved or {},
        base_rendered_ignored=S.baseRenderedIgnored or 0,
        nest_biome_counts=S.nestBiomeCounts,
        fingerprint_known=S.fingerprintKnown or 0,
        fingerprint_unknown=S.fingerprintUnknown or 0,
        stale_side_visuals=S.staleSideVisuals or 0,
        shared_fingerprint_conflicts=S.sharedFingerprintConflicts or 0,
        blacklisted_identity=S.blacklistedIdentity or 0,
        generic_slot_shells=S.genericSlotShells or 0,
        no_mesh_identity=S.noMeshIdentity or 0,
        unknown_fingerprints=S.unknownFingerprints,
        light_dark_side=S.lightDarkSide,
        event_flags=S.eventFlags,
        coordinator_active=S.coordinatorActive==true,
        node_connected=S.nodeConnected==true,
        cloud_status=S.lastCloudStatus,
        cloud_error=S.lastCloudError,
        cloud_last_ok_at=S.lastCloudOkAt,
        prime_probe_optin=true,
        cloud_upload_ms=S.cloudUploadMs,
        snapshot_ack_ms=S.snapshotAckMs,
        snapshot_ack_ok=S.snapshotAckOk==true,
        snapshot_ack_job=S.snapshotAckJob,
        snapshot_ack_at=S.snapshotAckAt,
        fast_fanout_ms=S.fastFanoutMs,
        fast_ack_count=S.fastAckCount or 0,
        fast_ack_last=S.fastAckLast,
        fast_retry_queued=S.fastRetryQueued==true,
        cloud_retry_persisted=S.cloudRetryPersisted==true,
        cloud_route=S.cloudRoute,
        claim_latency_ms=S.claimLatencyMs,
        claim_source=S.claimSource,
        claim_score=S.claimScore,
        claim_recently_scanned=S.lastClaimRecentlyScanned,
        claim_fresh=S.claimFresh or 0,
        claim_recent=S.claimRecent or 0,
        coverage_new_ratio=((tonumber(S.claimFresh) or 0)+(tonumber(S.claimRecent) or 0))>0 and ((tonumber(S.claimFresh) or 0)/((tonumber(S.claimFresh) or 0)+(tonumber(S.claimRecent) or 0))) or nil,
        teleport_avg_ms=S.teleportAvgSec and math.floor((tonumber(S.teleportAvgSec) or 0)*1000+0.5) or nil,
        teleport_success_samples=S.teleportSuccessSamples or 0,
        adaptive_watchdog_sec=S.adaptiveWatchdogSec or CFG.TELEPORT_WATCHDOG_SEC,
        last_error=S.lastError,
        premium_read_complete=S.premiumReadComplete,
        readiness_policy=S.readinessPolicy,
        last_node_error=S.lastNodeError,
        last_teleport_failure=S.lastTeleportFailure,
        patch_ar="A-R-v1",
        patch_events=S.patchEvents or {},
        pending_fingerprints=#(S.pendingFingerprintCandidates or {}),
        quarantine=S.quarantinedEgg,
        quarantine_updated_at=S.quarantineUpdatedAt,
        timestamp=nowUnix(),
    }

    return pcall(function()
        Shared.__VYRO_EXEC._WF(STATUS_FILE,HttpService:JSONEncode(payload))
    end)
end

Shared.__VYRO_RAW_EGG_PAYLOAD=function(e)
    e=type(e)=="table" and e or {}
    local pet=tostring(e.pet or "")
    local display=tostring(e.displayName or "")
    local function missingName(v)
        local n=tostring(v or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        return n=="" or n=="?" or n=="nil" or n=="unknown"
    end
    -- Preserve the literal DisplayName read from the live egg. This is our
    -- audit trail when canonical identity resolution changes the display name.
    local rawDisplay=tostring(e.rawVisualName or "")
    if missingName(rawDisplay) then rawDisplay=display end
    if missingName(pet) and not missingName(rawDisplay) then
        local _,parsed=parseDisplayName(rawDisplay)
        pet=tostring(parsed or "")
    end
    local known=not missingName(pet)
    if not known then pet="Unknown" end
    if missingName(display) then display=known and pet or "?" end
    local eggName=tostring(e.eggName or "")
    if missingName(eggName) then eggName=known and (pet.." Egg") or "Unknown" end

    -- Mutation fallback from the visible Billboard/DisplayName. Metadata/attrs
    -- remain primary, but mutated names like "Silver Cerberus" or
    -- "Scrambled Mutation Stag" must still resolve when mutation attrs are absent.
    local mutationList=retailMutations(e.muts or {})
    if #mutationList==0 and not missingName(rawDisplay) then
        local displayMuts,displayPet=parseDisplayName(rawDisplay)
        mutationList=retailMutations(displayMuts or {})
        if (missingName(pet) or pet=="Unknown") and displayPet and displayPet~="?" then
            pet=tostring(displayPet)
            known=true
        end
    end
    local normalizedName=known and pet or "Unknown"
    local primaryMutation=(#mutationList>0) and tostring(mutationList[1]) or "none"
    local fp=tostring(e.eggFingerprint or e.fingerprint or "no_mesh_id")
    local pos=e._position or e.nestPosition
    local position=""
    if typeof(pos)=="Vector3" then
        position=string.format("%.3f,%.3f,%.3f",pos.X,pos.Y,pos.Z)
    elseif pos~=nil then
        position=tostring(pos)
    end
    local ownerId=candidateOwnerId(e._model)
    local uid=tostring(e.uid or "")
    local biomeKey=tostring(e.biomeName or e.targetBiome or "Unknown")
    local nestIndex=tonumber(e.nestIndex)
    local slotKey=biomeKey.."#"..tostring(nestIndex or 0)
    local generation=tonumber(e.restockGeneration)
    if generation==nil and type(PatchSZ.restockSlots)=="table" then
        local slotState=PatchSZ.restockSlots[slotKey]
        if type(slotState)=="table" then generation=tonumber(slotState.generation) end
    end
    generation=math.max(0,math.floor(tonumber(generation) or 0))
    local eventId=tostring(e.eventId or "")
    if eventId=="" then
        if nestIndex then
            eventId=table.concat({tostring(game.JobId),"slot",biomeKey,tostring(nestIndex),"g"..tostring(generation)},":")
        else
            eventId=tostring(game.JobId)..":"..(uid~="" and uid or biomeKey)
        end
    end
    local stableInstanceId=eventId
    if nestIndex then
        stableInstanceId=table.concat({tostring(game.JobId),"slot",biomeKey,tostring(nestIndex)},":")
    end
    local visualScale=tonumber(e.visualScale or e.scale)
    local eggStateScale=finite(e.eggStateScale)
    if eggStateScale and eggStateScale<=0 then eggStateScale=nil end
    -- safeEggStateScale already joins UID, zone and identity. Model:GetScale is
    -- a rendered scale (authored template, growth and clamping), not AssetScale.
    -- Prefer the validated saved scale at every size, not only at the visual cap.
    local exactScaleMatch=e.eggStateScaleMatch=="exact_uid_zone_slot_identity"
        or e.eggStateScaleMatch=="exact_uid_zone_identity_slot_number_diff"
    local exactScaleOverride=eggStateScale~=nil and exactScaleMatch
    local capOverride=exactScaleOverride and ((visualScale~=nil and visualScale>=7.95) or eggStateScale>8.0)
    local reportedScale=exactScaleOverride and eggStateScale or tonumber(e.scale)
    local reportedScaleSource=exactScaleOverride and "EggState.AssetScale" or tostring(e.scaleSource or "unknown")
    local reportedScaleKind=exactScaleOverride and "eggstate_asset_scale_exact_uid" or tostring(e.scaleKind or "unknown")
    return {
        event_id=eventId,uid=uid,source_uid=uid,instance_id=stableInstanceId,
        egg=eggName,egg_name=eggName,egg_type=eggName,
        raw_name=rawDisplay,visual_raw_name=rawDisplay,display_name=display,
        normalized_name=normalizedName,pet=normalizedName,pet_name=normalizedName,
        mutation=primaryMutation,
        fingerprint=fp,egg_fingerprint=fp,
        biome=tostring(e.biomeName or e.targetBiome or "Unknown"),
        biomeName=tostring(e.biomeName or e.targetBiome or "Unknown"),
        guard_area=tostring(e.biomeName or e.targetBiome or "Unknown"),
        rarity=tostring(e.rarity or e.catalogRarity or "Unknown"),
        scale=reportedScale,asset_scale=reportedScale,
        visual_scale=visualScale,eggstate_asset_scale=eggStateScale,
        scale_cap_override=capOverride==true,
        scale_exact_override=exactScaleOverride==true,
        scale_match=tostring(e.eggStateScaleMatch or ""),
        scale_source=reportedScaleSource,
        scale_kind=reportedScaleKind,
        visual_scale_source=tostring(e.visualScaleSource or e.scaleSource or "unknown"),
        visual_scale_kind=tostring(e.visualScaleKind or e.scaleKind or "unknown"),
        position=position,timestamp=nowUnix(),timestamp_ms=nowMs(),
        account=tostring(LP.Name),account_name=tostring(LP.Name),
        job_id=tostring(game.JobId),
        source=tostring(e.source or "world_candidate"),
        source_confidence=tonumber(e.sourceConfidence) or 0,
        identity_source=tostring(e.identitySource or "unresolved"),
        identity_confidence=tonumber(e.identityConfidence) or 0,
        reason=tostring(e.locationReason or "unknown"),
        location_reason=tostring(e.locationReason or "unknown"),
        nest_index=nestIndex,restock_generation=generation,per_second=e.perSecond,
        mutations=mutationList,muts=mutationList,
        mutation_source=tostring(e.mutationSource or "none"),
        owner_user_id=ownerId,is_player_model=ownerId~=nil,
        chat_confirmed=e.chatConfirmed==true,
        chat_announcement_at=tonumber(e.chatAnnouncementAt),
        chat_text=tostring(e.chatText or ""),
        area_state="slot",stable_instance_id=(nestIndex~=nil) or uid~="" or eventId~="",
    }
end

-- VYRO_HALLOWEEN_WORLD_COLLECTOR_BEGIN_20261017
do
-- Pure identity resolver. No Instance access, waits, game actions, or income assumptions.
local HC = {}
HC.contract = "halloween-contract-r2"
HC.maxModels = 40
local targets = {
    ["Abomination Kong"] = {display = "Gorillastein", rarity = "Eternal", zone = 3},
    ["Voidseer Pumpkin"] = {display = "Voidseer Pumpkin", rarity = "Divine", zone = 3},
    ["Shelltide Voyager"] = {display = "Shelltide Voyager", zone = 2},
    ["Werewolf"] = {display = "Werewolf", zone = 3},
}

local function normalized(value)
    if type(value) ~= "string" or #value > 160 then return "" end
    return value:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function validUid(value)
    return type(value) == "string" and #value == 32 and value:match("^[%da-fA-F]+$") ~= nil
end

function HC.makeIndex(specs)
    if type(specs) ~= "table" then return nil, "catalog_missing" end
    local index, count, entries = {}, 0, 0
    for key, spec in pairs(specs) do
        entries = entries + 1
        if entries > 256 then return nil, "catalog_limit" end
        if type(key) == "string" and type(spec) == "table" then
            local id = key
            local wanted = targets[id] or targets[spec.DisplayName]
            local eligible = wanted ~= nil and spec.Id == id and spec.DisplayName == wanted.display
                and (wanted.rarity == nil and (spec.Rarity == "Secret" or spec.Rarity == "Eternal" or spec.Rarity == "Divine")
                    or spec.Rarity == wanted.rarity) and spec.Group == "World"
                and tonumber(spec.Zone) == tonumber(wanted.zone) and spec.SharedEggFallback == false
                and type(spec.EggModel) == "string" and spec.EggModel ~= ""
            if eligible then count = count + 1 end
            local item = {id = id, spec = spec, eligible = eligible}
            local aliases = {key, spec.Id, spec.DisplayName, spec.Source, spec.EggSource, spec.EggModel}
            -- A numeric loop retains aliases after absent optional catalog fields.
            for n = 1, 6 do
                local alias = normalized(aliases[n])
                if alias ~= "" then
                    local prior = index[alias]
                    if prior == nil then index[alias] = item
                    elseif prior == false or prior.id ~= id then index[alias] = false end
                end
            end
        end
    end
    if count < 2 then return nil, "catalog_targets_unverified" end
    return index
end

function HC.resolve(index, records)
    local output = {}
    local diagnostic = {observed = 0, valid_uids = 0, catalog_resolved = 0, targets = 0, rejected = {}, contract = HC.contract}
    local function reject(reason)
        diagnostic.rejected[reason] = (diagnostic.rejected[reason] or 0) + 1
    end
    if type(index) ~= "table" then reject("catalog_unavailable"); return output, diagnostic end
    if type(records) ~= "table" then reject("records_unavailable"); return output, diagnostic end
    if #records > HC.maxModels then reject("world_models_limit"); return output, diagnostic end
    local seen, candidates, conflicts = {}, {}, {}
    for _, record in ipairs(records) do
        diagnostic.observed = diagnostic.observed + 1
        if type(record) ~= "table" or not validUid(record.uid) then
            reject("invalid_uid")
        else
            diagnostic.valid_uids = diagnostic.valid_uids + 1
            local uid = record.uid:lower()
            local source = normalized(record.source)
            local item = index[source]
            if item then diagnostic.catalog_resolved = diagnostic.catalog_resolved + 1 end
            local zone = tonumber(record.zone)
            local identity = item and item.id or ("unresolved:" .. source)
            local signature = identity .. "|zone:" .. tostring(zone)
            if seen[uid] ~= nil and seen[uid] ~= signature then conflicts[uid] = true end
            seen[uid] = signature
            if item == false then reject("ambiguous_alias")
            elseif item == nil then reject("unknown_source")
            elseif not item.eligible then reject("not_target_world_egg")
            elseif zone ~= tonumber(item.spec.Zone) then reject("zone_mismatch")
            elseif candidates[uid] == nil then
                candidates[uid] = {
                    uid = uid, id = item.id, pet = item.spec.DisplayName,
                    rarity = item.spec.Rarity, egg = item.spec.EggModel,
                    preparedSourceName = record.source, zone = zone,
                    modelSnapshotScale = record.modelSnapshotScale,
                }
            end
        end
    end
    for uid, candidate in pairs(candidates) do
        if conflicts[uid] then reject("conflicting_uid")
        else output[#output + 1] = candidate end
    end
    table.sort(output, function(a, b) return a.uid < b.uid end)
    diagnostic.targets = #output
    return output, diagnostic
end

-- This body follows the pure resolver inside its own do/end scope.
-- Catalogue loading runs separately; neither snapshot building nor hopping waits for require.
HC.catalogIndex = nil
HC.catalogBusy = false
HC.catalogAttemptAt = -math.huge
HC.catalogError = "catalog_pending"

function HC.requestCatalog()
    if HC.catalogIndex or HC.catalogBusy or os.clock() - HC.catalogAttemptAt < 5 then return end
    HC.catalogAttemptAt = os.clock()
    local data = ReplicatedStorage:FindFirstChild("Data")
    local module = data and data:FindFirstChild("HalloweenPets")
    if not module or not module:IsA("ModuleScript") then HC.catalogError = "catalog_missing"; return end
    HC.catalogBusy = true
    task.defer(function()
        local ok, value = pcall(require, module)
        if ok and type(value) == "table" then
            local indexed, index, reason = pcall(HC.makeIndex, value.Specs)
            if indexed then
                HC.catalogIndex = index
                HC.catalogError = reason
            else
                HC.catalogError = "catalog_invalid"
            end
        else
            HC.catalogError = "catalog_load_failed"
        end
        HC.catalogBusy = false
    end)
end

function HC.collect()
    local started = os.clock()
    HC.requestCatalog()
    local dimension = workspace:FindFirstChild("HalloweenDimension")
    local folder = dimension and dimension:FindFirstChild("WorldEggs")
    if not folder then return {}, {contract=HC.contract, observed=0, targets=0, status="world_folder_missing"} end
    local children = folder:GetChildren()
    if #children > HC.maxModels then
        return {}, {contract=HC.contract, observed=#children, targets=0, status="world_models_limit"}
    end
    local records = {}
    for _, model in ipairs(children) do
        if model:IsA("Model") then
            -- Read from the real physical egg, not from a UID-based scale lookup.
            -- This is a visual model measurement, not a SavedEgg.AssetScale claim.
            local okScale, modelScale = pcall(function() return model:GetScale() end)
            local numericScale = okScale and tonumber(modelScale) or nil
            if not (numericScale and numericScale == numericScale and numericScale > 0
                and numericScale <= 200 and numericScale ~= math.huge) then
                numericScale = nil
            end
            records[#records+1] = {
                uid = model:GetAttribute("HalloweenEggUid"),
                source = model:GetAttribute("PreparedSourceName"),
                zone = model:GetAttribute("Zone"),
                modelSnapshotScale = numericScale,
            }
        end
    end
    if not HC.catalogIndex then
        return {}, {contract=HC.contract, observed=#records, targets=0, status=HC.catalogError or "catalog_pending"}
    end
    local resolved, diagnostic = HC.resolve(HC.catalogIndex, records)
    local rows = {}
    for _, egg in ipairs(resolved) do
        local eventId = tostring(game.JobId) .. ":halloween:" .. egg.uid
        local worldArea = ({[1]="Graveyard",[2]="Haunted Swamp",[3]="Abandoned Manor"})[egg.zone]
        local eggDisplay = (egg.pet == "Werewolf" or egg.pet == "Shelltide Voyager") and (egg.pet .. " Egg") or egg.egg
        rows[#rows+1] = {
            uid=egg.uid, source_uid=egg.uid, event_id=eventId, instance_id=eventId,
            stable_instance_id=true,
            egg=eggDisplay, egg_name=eggDisplay, egg_type=eggDisplay,
            pet=egg.pet, pet_name=egg.pet, normalized_name=egg.pet, display_name=egg.pet,
            raw_name=egg.preparedSourceName, visual_raw_name=egg.preparedSourceName,
            rarity=egg.rarity, biome=worldArea, biomeName=worldArea,
            guard_area=worldArea, halloween_zone=egg.zone,
            source="world_spawn", source_confidence=1,
            entity_source="halloween_dimension_world",
            identity_source="HalloweenPets.PreparedSourceName", identity_confidence=1,
            reason="halloween_world_exact_uid_catalog", location_reason="halloween_world_exact_uid_catalog",
            field_exact={pet_name=true, egg_name=true, rarity=true, asset_scale=false, scale=false, mutations=false, per_second=false},
            field_sources={
                halloween_contract=HC.contract,
                identity="ReplicatedStorage.Data.HalloweenPets:PreparedSourceName",
                uid="Workspace.HalloweenDimension.WorldEggs.HalloweenEggUid",
                asset_scale="unobserved", scale="unobserved", mutations="unobserved", per_second="unobserved",
                world_model_scale_kind=egg.modelSnapshotScale and "Model:GetScale" or "unobserved",
                world_model_scale_status=egg.modelSnapshotScale and "visual_unverified" or "unobserved",
                world_model_scale_value=egg.modelSnapshotScale and string.format("%.17g", egg.modelSnapshotScale) or nil,
                world_model_scale_uid=egg.uid,
                world_model_scale_job=tostring(game.JobId),
            },
            scale_source="unobserved", scale_kind="unobserved", mutation_source="unobserved",
            income_estimate_partial=true, join_enabled=false, ready_for_production=false, fixture_only=false,
            area_state="world", is_player_model=false,
            account=tostring(LP.Name), account_name=tostring(LP.Name), job_id=tostring(game.JobId),
            timestamp=nowUnix(), timestamp_ms=nowMs(),
        }
    end
    diagnostic.status="ok"
    diagnostic.scan_ms=math.floor((os.clock()-started)*10000+0.5)/10
    diagnostic.job_id=tostring(game.JobId)
    return rows, diagnostic
end

Runtime.halloweenCollector = HC
HC.requestCatalog()
end
-- VYRO_HALLOWEEN_WORLD_COLLECTOR_END_20261017

local function buildSnapshotPayload()
    local allEggs={}
    local eventSeen={}
    for _,entry in ipairs(S.rawEggs or {}) do
        if entry.source=="world_spawn" or entry.source=="world_candidate" then
            local rawPayload=Shared.__VYRO_RAW_EGG_PAYLOAD(entry)
            local eid=tostring(rawPayload.event_id or "")
            allEggs[#allEggs+1]=rawPayload
            if eid~="" then eventSeen[eid]=true end
        end
    end
    local keptChat={}
    local now=nowUnix()
    for _,entry in ipairs(S.chatProvisionalTargets or {}) do
        local age=now-(tonumber(entry.chatAnnouncementAt) or tonumber(entry.at) or 0)
        local sameJob=tostring(entry.job or game.JobId)==tostring(game.JobId)
        if sameJob and age>=0 and age<=CFG.CHAT_PROVISIONAL_TTL then
            keptChat[#keptChat+1]=entry
            local rawPayload=Shared.__VYRO_RAW_EGG_PAYLOAD(entry)
            local eid=tostring(rawPayload.event_id or "")
            if eid=="" or not eventSeen[eid] then
                allEggs[#allEggs+1]=rawPayload
                if eid~="" then eventSeen[eid]=true end
            end
        end
    end
    S.chatProvisionalTargets=keptChat
    -- Independent WorldEggs observation also works when normal GuardAreas/Nests are absent.
    local halloweenDiagnostic={contract="halloween-contract-r2", observed=0, targets=0, status="collector_unavailable"}
    local halloweenCount=0
    if Runtime.halloweenCollector then
        local ok,rows,diagnostic=pcall(Runtime.halloweenCollector.collect)
        if ok then
            halloweenDiagnostic=diagnostic
            for _,row in ipairs(rows) do
                local eid=tostring(row.event_id or "")
                if eid~="" and not eventSeen[eid] then
                    allEggs[#allEggs+1]=row
                    eventSeen[eid]=true
                    halloweenCount=halloweenCount+1
                end
            end
        else
            halloweenDiagnostic.status="collector_error"
        end
    end
    local eggs={}
    local testAnyEgg=false
    local testProbe=nil
    pcall(function()
        testAnyEgg = type(Shared.__VYRO_EXEC._IF)=="function" and Shared.__VYRO_EXEC._IF(CFG.TEST_ANY_EGG_FILE)
    end)
    if testAnyEgg then
        for _,candidate in ipairs(S.eggs or {}) do
            local pet=targetPetKey(candidate)
            if candidate.source=="world_spawn"
                and (tonumber(candidate.sourceConfidence) or 0)>=CFG.WORLD_MIN_CONFIDENCE
                and pet and tostring(pet)~="" and tostring(pet)~="?"
            then
                testProbe=candidate
                break
            end
        end
        if testProbe then
            local pet=targetPetKey(testProbe)
            eggs[#eggs+1]={
                uid=testProbe.uid,
                pet=pet,pet_name=pet,
                egg_name=testProbe.eggName or testProbe.catalogEgg or (pet.." Egg"),
                egg_type=testProbe.eggName or testProbe.catalogEgg or (pet.." Egg"),
                rarity=testProbe.rarity or testProbe.catalogRarity or "Unknown",
                biome=testProbe.targetBiome or testProbe.biomeName,
                biomeName=testProbe.targetBiome or testProbe.biomeName,
                guard_area=testProbe.biomeName,
                side=testProbe.side or testProbe.targetBiome or testProbe.biomeName,
                target=testProbe.targetBiome or testProbe.biomeName,
                scale=testProbe.scale,scale_raw=testProbe.scale,
                asset_scale=testProbe.scale,
                preview_asset_id=testProbe.previewAssetId,
                muts=testProbe.muts,mutations=testProbe.muts,
                source="world_spawn",
                source_confidence=testProbe.sourceConfidence or 0,
                commercial_qualified=true,
                test_probe=true,
                area_state="slot",
            }
        end
    end
    local carriedIds={}
    for _,c in ipairs(S.carriedTargets or {}) do carriedIds[tostring(c.uid or "")]=true end
    for _,e in ipairs(S.qualifiedTargets) do
        if not carriedIds[tostring(e.uid or "")] then
        local canonicalPet=targetPetKey(e)
        eggs[#eggs+1]={
            uid=e.uid,
            pet=canonicalPet,
            pet_name=canonicalPet,
            egg_name=e.eggName or (canonicalPet.." Egg"),
            egg_type=e.eggName or (canonicalPet.." Egg"),
            rarity=e.rarity or e.catalogRarity or "Unknown",
            catalog_biome=e.catalogBiome,
            catalog_egg=e.catalogEgg,
            biome=e.targetBiome,
            biomeName=e.targetBiome,
            guard_area=e.biomeName,
            biome_id=e.biomeId,
            biomeId=e.biomeId,
            side=e.side or e.targetBiome,
            target=e.targetBiome,
            scale=e.scale,
            scale_raw=e.scale,
            scale_kind=e.scaleKind or "unknown",
            egg_fingerprint=e.eggFingerprint,
            preview_asset_id=e.previewAssetId,
            fingerprint_key=e.fingerprintKey,
            identity_source=e.identitySource,
            identity_confidence=e.identityConfidence,
            nest_distance=e.nestDistance,
            muts=e.muts,
            mutations=e.muts,
            source="world_spawn",
            source_confidence=e.sourceConfidence or 0,
            location_reason=e.locationReason,
            quality_score=e.qualityScore or 0,
            quality_reason=e.qualityReason,
            commercial_qualified=e.commercialQualified==true,
            global_divine=e.globalDivine==true,
            quality_policy_version=S.qualityPolicyVersion,
            nest_index=e.nestIndex,
            per_second=e.perSecond,
            area_state="slot",
        }
        end
    end
    for _,e in ipairs(S.carriedTargets or {}) do
        local canonicalPet=targetPetKey(e)
        if buyerAnnouncementGate(canonicalPet) then
            eggs[#eggs+1]={
                uid=e.uid,pet=canonicalPet,pet_name=canonicalPet,
                egg_name=e.eggName or (canonicalPet.." Egg"),egg_type=e.eggName or (canonicalPet.." Egg"),
                rarity=e.rarity or "Unknown",biome=e.targetBiome,biomeName=e.targetBiome,
                guard_area=e.biomeName,side=e.side or e.targetBiome,target=e.targetBiome,
                scale=e.scale,preview_asset_id=e.previewAssetId,muts=e.muts,mutations=e.muts,
                source="world_spawn",source_confidence=e.sourceConfidence or 1.0,
                commercial_qualified=true,area_state="carrying",carrier_user_id=e.carrierUserId,carrier_name=e.carrierName,
            }
        end
    end

    local liveCandidates={}
    for _,e in ipairs(S.targets or {}) do
        local canonicalPet=targetPetKey(e)
        if e.source=="world_spawn"
            and (tonumber(e.sourceConfidence) or 0)>=CFG.WORLD_MIN_CONFIDENCE
            and canonicalPet
            and tostring(canonicalPet)~=""
            and tostring(canonicalPet)~="?"
            and buyerAnnouncementGate(canonicalPet)
        then
            liveCandidates[#liveCandidates+1]=e
        end
    end
    table.sort(liveCandidates,function(a,b)
        local ad=isDivineSignal(a) and 1 or 0
        local bd=isDivineSignal(b) and 1 or 0
        if ad~=bd then return ad>bd end
        local as,bs=tonumber(a.scale) or -1,tonumber(b.scale) or -1
        if as~=bs then return as>bs end
        return tostring(targetPetKey(a))<tostring(targetPetKey(b))
    end)

    local liveEggs={}
    for i=1,math.min(#liveCandidates,24) do
        local e=liveCandidates[i]
        if not carriedIds[tostring(e.uid or "")] then
        local canonicalPet=targetPetKey(e)
        liveEggs[#liveEggs+1]={
            uid=e.uid,
            pet=canonicalPet,
            pet_name=canonicalPet,
            egg_name=e.eggName or e.catalogEgg or (canonicalPet.." Egg"),
            egg_type=e.eggName or e.catalogEgg or (canonicalPet.." Egg"),
            rarity=e.rarity or e.catalogRarity or "Unknown",
            biome=e.biomeName,
            biomeName=e.biomeName,
            guard_area=e.biomeName,
            side=e.side or e.biomeName,
            scale=e.scale,
            asset_scale=e.scale,
            scale_kind=e.scaleKind or "unknown",
            preview_asset_id=e.previewAssetId,
            egg_fingerprint=e.eggFingerprint,
            identity_source=e.identitySource,
            identity_confidence=e.identityConfidence,
            muts=e.muts,
            mutations=e.muts,
            source="world_spawn",
            source_confidence=e.sourceConfidence or 0,
            location_reason=e.locationReason,
            nest_index=e.nestIndex,
            per_second=e.perSecond,
            area_state="slot",
        }
        end
    end
    for _,e in ipairs(S.carriedTargets or {}) do
        local canonicalPet=targetPetKey(e)
        if buyerAnnouncementGate(canonicalPet) then
            liveEggs[#liveEggs+1]={
                uid=e.uid,pet=canonicalPet,pet_name=canonicalPet,
                egg_name=e.eggName or (canonicalPet.." Egg"),egg_type=e.eggName or (canonicalPet.." Egg"),
                rarity=e.rarity or "Unknown",biome=e.targetBiome,biomeName=e.targetBiome,
                guard_area=e.biomeName,side=e.side or e.targetBiome,
                scale=e.scale,asset_scale=e.scale,per_second=e.perSecond,preview_asset_id=e.previewAssetId,muts=e.muts,mutations=e.muts,
                source="world_spawn",source_confidence=e.sourceConfidence or 1.0,
                area_state="carrying",carrier_user_id=e.carrierUserId,carrier_name=e.carrierName,
            }
        end
    end

    return {
        version=CFG.VERSION,
        strict_world_only=true,
        quality_gate=true,
        quality_policy_version=S.qualityPolicyVersion,
        account_name=tostring(LP.Name),
        client_id=tostring(LP.UserId),
        user_id=tostring(LP.UserId),
        place_id=game.PlaceId,
        job_id=tostring(game.JobId),
        server_population=#Players:GetPlayers(),
        timestamp=nowUnix(),
        observed_at=DateTime.now():ToIsoDate(),
        observed_at_ms=nowMs(),
        scan_ms=S.lastScanMs,
        stable_wait_ms=S.lastStableWaitMs,
        ready_wait_ms=S.lastReadyWaitMs,
        visual_wait_ms=S.lastVisualWaitMs,
        raw_eggs=#(S.rawEggs or {}),
        world_eggs=#(S.eggs or {}),
        nest_slots_total=S.nestSlotsTotal or 0,
        nest_slots_resolved=S.nestSlotsResolved or 0,
        nest_slot_source=S.nestSlotSource or "none",
        nest_unresolved=S.nestUnresolved or {},
        nest_identity_unresolved=S.nestIdentityUnresolved or {},
        base_rendered_ignored=S.baseRenderedIgnored or 0,
        excluded_base=S.excludedBase or 0,
        excluded_uncertain=S.excludedUncertain or 0,
        base_regions=#(S.baseRegions or {}),
        base_map_resolved=S.baseMapResolved==true,
        natural_eggs_per_biome=CFG.NATURAL_EGGS_PER_BIOME,
        natural5_learned_biomes=S.natural5LearnedBiomes or 0,
        commercial_fail_closed=CFG.REQUIRE_NATURAL5_FOR_COMMERCIAL,
        coordinator_active=S.coordinatorActive==true,
        fingerprint_known=S.fingerprintKnown or 0,
        fingerprint_unknown=S.fingerprintUnknown or 0,
        stale_side_visuals=S.staleSideVisuals or 0,
        shared_fingerprint_conflicts=S.sharedFingerprintConflicts or 0,
        blacklisted_identity=S.blacklistedIdentity or 0,
        generic_slot_shells=S.genericSlotShells or 0,
        no_mesh_identity=S.noMeshIdentity or 0,
        unknown_fingerprints=S.unknownFingerprints,
        light_dark_side=S.lightDarkSide,
        test_any_egg_once=testProbe~=nil,
        test_any_egg_name=testProbe and tostring(targetPetKey(testProbe) or "") or nil,
        send_all=true,
        raw_send_count=#allEggs,
        halloween_world_eggs=halloweenCount,
        halloween_diagnostics=halloweenDiagnostic,
        eggs=allEggs,
        live_eggs=allEggs,
    }
end

local lastCloudHash=nil
local lastPublishedHadTargets=false
local function snapshotHash(payload)
    local parts={
        tostring(payload.job_id),
        tostring(#(payload.eggs or {})),
        tostring(payload.send_all==true),
        tostring(payload.quality_policy_version),
    }
    for i=1,#(payload.eggs or {}) do
        local e=payload.eggs[i]
        parts[#parts+1]=tostring(e.event_id or e.uid or "")
        parts[#parts+1]=tostring(e.pet_name or e.pet or "")
        parts[#parts+1]=tostring(e.egg_name or e.egg or "")
        parts[#parts+1]=tostring(e.display_name or "")
        parts[#parts+1]=tostring(e.fingerprint or e.egg_fingerprint or "")
        parts[#parts+1]=tostring(e.biome or e.biomeName or "")
        parts[#parts+1]=tostring(e.rarity or "Unknown")
        parts[#parts+1]=tostring(e.scale)
        parts[#parts+1]=tostring(e.source or "")
        parts[#parts+1]=tostring(e.reason or e.location_reason or "")
        parts[#parts+1]=table.concat(e.mutations or {},",")
    end
    return table.concat(parts,"|")
end

local function uploadSnapshot(payload)
    local hash=snapshotHash(payload)
    if hash==lastCloudHash then return true,"duplicate" end
    if Runtime.lastCountedSnapshotHash~=hash then
        Runtime.lastCountedSnapshotHash=hash
        S.lastEggsSent=#(payload.eggs or {})
        S.totalEggsSent=(tonumber(S.totalEggsSent) or 0)+S.lastEggsSent
    end

    -- Preferred route: local Node Agent does immediate delivery and persists
    -- failed snapshots for retry so transient cloud loss does not lose a spawn.
    Runtime.sendAllLogged=Runtime.sendAllLogged or {}
    S.lastEggsSent=#(payload.eggs or {})
    for _,e in ipairs(payload.eggs or {}) do
        local key=tostring(e.event_id or e.uid or "").."|"..tostring(e.fingerprint or e.egg_fingerprint or "").."|"..tostring(e.pet_name or e.pet or "")
        if not Runtime.sendAllLogged[key] then
            Runtime.sendAllLogged[key]=true
            logLine(string.format("[SEND-ALL] Enviando huevo: %s | biome=%s | fingerprint=%s",
                tostring(e.egg_name or e.egg or "Unknown"),
                tostring(e.biome or e.biomeName or "Unknown"),
                tostring(e.fingerprint or e.egg_fingerprint or "no_mesh_id")
            ))
        end
    end
    local started=os.clock()
    local nodeData,nodeErr,nodeStatus=requestJson("POST",NODE_BASE.."/v1/snapshot",payload,nodeHeaders())
    -- VYRO_SAFE_NODE409_RETRY_20261024: retry only transient mapping/
    -- coordinator delays. Server-side JobId, cycle and whitelist stay enforced.
    local function canRetryNodeSnapshot409(status,err)
        if status~=409 then return false end
        local text=tostring(err or "")
        if text=="HTTP 409" then
            -- Some executors omit the JSON rejection body. Retry at most
            -- once, only while this same job is in the active scan window.
            local now=nowUnix()
            local _,scanStart,scanEnd=Runtime.cycleWindow(now)
            return S.mode=="hunting" and scanStart and scanEnd
                and now>=scanStart and now<scanEnd-3
        end
        return text:find("snapshot_account_not_mapped",1,true)~=nil
            or text:find("snapshot_heartbeat_stale",1,true)~=nil
            or text:find("snapshot_job_not_current",1,true)~=nil
            or text:find("snapshot_cloud_coord_not_ready",1,true)~=nil
    end
    if not nodeData and canRetryNodeSnapshot409(nodeStatus,nodeErr)
        and tostring(game.JobId)==tostring(payload.job_id or "")
    then
        -- Avoid coordinator overload: only one jittered retry for
        -- cloud_coord_not_ready; other transient local races get two.
        local generic409=(nodeStatus==409 and tostring(nodeErr or "")=="HTTP 409")
        local coordPending=tostring(nodeErr or ""):find("snapshot_cloud_coord_not_ready",1,true)~=nil or generic409
        for retry=1,(coordPending and 1 or 2) do
            if not Runtime.alive or Runtime.teleporting
                or tostring(game.JobId)~=tostring(payload.job_id or "")
            then break end
            task.wait((retry==1 and (coordPending and (generic409 and 1.40 or 0.95) or 0.30) or 0.80)+math.random()*0.30)
            if not Runtime.alive or Runtime.teleporting
                or tostring(game.JobId)~=tostring(payload.job_id or "")
            then break end
            nodeData,nodeErr,nodeStatus=requestJson("POST",NODE_BASE.."/v1/snapshot",payload,nodeHeaders())
            if nodeData or not canRetryNodeSnapshot409(nodeStatus,nodeErr) then break end
        end
    end

    S.cloudUploadMs=math.floor((os.clock()-started)*10000+0.5)/10
    if nodeData then
        S.nodeConnected=true
        S.lastCloudStatus=nodeStatus or 202
        S.lastCloudError=nil
        S.lastCloudOkAt=nowUnix()
        S.cloudRetryPersisted=(nodeData.retry_persisted==true) or (nodeData.queued==true)
        S.cloudRoute=S.cloudRetryPersisted and "node_retry_queue" or "node_direct"
        if tonumber(nodeData.cloud_ms) then S.cloudUploadMs=tonumber(nodeData.cloud_ms) end
        if tonumber(nodeData.fast_ms) then S.fastFanoutMs=tonumber(nodeData.fast_ms) end
        S.fastAckCount=tonumber(nodeData.fast_count) or 0
        S.fastRetryQueued=(nodeData.fast_retry_queued==true)
        local rawReceived=tonumber(nodeData.raw_received) or #(payload.eggs or {})
        S.lastEggsSent=rawReceived
        S.lastRawAccepted=tonumber(nodeData.whitelist_accepted) or 0
        S.lastRawIgnored=tonumber(nodeData.whitelist_ignored) or 0
        S.lastDuplicateRowsDropped=tonumber(nodeData.duplicate_rows_dropped) or 0
        if type(nodeData.fast_ack_ids)=="table" and #nodeData.fast_ack_ids>0 then
            S.fastAckLast=tostring(nodeData.fast_ack_ids[1])
        end
        lastCloudHash=hash
        return true,S.cloudRoute
    end

    -- SEND-ALL raw payloads must never bypass the backend whitelist.
    if payload.send_all==true then
        S.lastCloudError="node_required_send_all:"..tostring(nodeErr)
        S.cloudRoute="node_required_send_all"
        return false,S.lastCloudError
    end

    -- Optional emergency direct fallback for legacy single-machine testing.
    if type(CLOUD_KEY)~="string" or #CLOUD_KEY<12 then
        S.lastCloudError="node:"..tostring(nodeErr).."; direct_key_missing"
        S.cloudRoute="failed"
        return false,S.lastCloudError
    end
    local directStarted=os.clock()
    local _,err,status=requestJson("POST",CLOUD_BASE.."/api/eggs",payload,{["X-Api-Key"]=CLOUD_KEY})
    S.cloudUploadMs=math.floor((os.clock()-directStarted)*10000+0.5)/10
    S.lastCloudStatus=status
    if err then S.lastCloudError=tostring(err);S.cloudRoute="direct_failed";return false,err end
    S.lastCloudError=nil;S.lastCloudOkAt=nowUnix();S.cloudRetryPersisted=false;S.cloudRoute="direct";lastCloudHash=hash
    return true,"direct"
end

local function writeSnapshot(requireNodeAck)
    local cycleScanResult=Runtime.cycleScanResult
    local payload = buildSnapshotPayload()

    if type(Shared.__VYRO_EXEC._WF)=="function" then
        pcall(function()
            Shared.__VYRO_EXEC._WF(SNAPSHOT_FILE,HttpService:JSONEncode(payload))
        end)
    end

    -- Cloud upload is non-blocking. Send the first EMPTY snapshot after a
    -- previously non-empty one so MapState can emit spawn_gone immediately.
    local hasTargets=(#(payload.eggs or {})>0 or #(payload.live_eggs or {})>0)
    local shouldUpload=hasTargets or lastPublishedHadTargets
    lastPublishedHadTargets=hasTargets
    local function recordUploadResult(ok,err)
        if ok and payload.test_any_egg_once then
            S.testAnyEggSentAt=nowUnix()
            S.testAnyEggSentName=tostring(payload.test_any_egg_name or "")
            pcall(function()
                if type(Shared.__VYRO_EXEC._IF)=="function"
                    and type(Shared.__VYRO_EXEC._DF)=="function"
                    and Shared.__VYRO_EXEC._IF(CFG.TEST_ANY_EGG_FILE)
                then
                    Shared.__VYRO_EXEC._DF(CFG.TEST_ANY_EGG_FILE)
                end
            end)
            logLine("TEST ANY EGG · uploaded "..tostring(S.testAnyEggSentName))
        elseif not ok and err~="cloud_key_missing" then
            logLine("CLOUD · "..tostring(err))
        end
    end

    if shouldUpload then
        if requireNodeAck==true then
            -- Critical ordering guarantee: SCAN -> NODE ACK/PERSIST -> HOP.
            -- NodeAgent returns after accepting/persisting the snapshot; cloud
            -- fanout/retry remains asynchronous behind the local durable queue.
            local ackStarted=os.clock()
            local ok,err=uploadSnapshot(payload)
            S.snapshotAckMs=math.floor((os.clock()-ackStarted)*10000+0.5)/10
            S.snapshotAckOk=(ok==true)
            S.snapshotAckJob=tostring(payload.job_id or "")
            S.snapshotAckAt=ok and nowUnix() or nil
            recordUploadResult(ok,err)
            if not ok then
                return false,err,payload
            end
        else
            -- Snapshot backpressure: scans must never fan out unlimited local
            -- HTTP requests when NodeAgent is slow. Keep one upload in flight
            -- and a tiny FIFO of changed snapshots so scanning remains fast
            -- without losing short-lived state transitions.
            Runtime.snapshotUploadQueue=Runtime.snapshotUploadQueue or {}
            if Runtime.snapshotUploadInFlight then
                local q=Runtime.snapshotUploadQueue
                if #q<4 then
                    q[#q+1]=payload
                else
                    q[#q]=payload
                end
            else
                Runtime.snapshotUploadInFlight=true
                task.spawn(function()
                    local currentPayload=payload
                    while Runtime.alive and currentPayload do
                        local callOk,ok,err=pcall(uploadSnapshot,currentPayload)
                        if not callOk then
                            ok=false
                            err="snapshot_upload_exception:"..tostring(ok)
                        end
                        recordUploadResult(ok,err)
                        currentPayload=table.remove(Runtime.snapshotUploadQueue,1)
                    end
                    Runtime.snapshotUploadInFlight=false
                end)
            end
        end
    else
        S.lastCloudStatus="skip_no_verified"
        S.lastCloudError=nil
        S.snapshotAckOk=true
        S.snapshotAckJob=tostring(payload.job_id or "")
    end

    -- Optional external bridge remains supported.
    if type(Shared.VYRO_CORE_ON_SNAPSHOT)=="function" then
        task.spawn(function()
            local ok,err=pcall(Shared.VYRO_CORE_ON_SNAPSHOT,payload)
            if not ok then
                S.lastBridgeError=tostring(err)
            else
                S.lastBridgeError=nil
            end
        end)
    end

    -- Unresolved nests get a small adaptive retry window. Never hammer the same
    -- server with repeated full scans when the rendered set is not improving.
    local retryJob=tostring(game.JobId)
    if #(S.nestUnresolved or {})>0
        and Runtime.unresolvedRetryJob~=retryJob
        and Runtime.unresolvedRetryDoneJob~=retryJob
    then
        Runtime.unresolvedRetryJob=retryJob
        task.spawn(function()
            local previousCount=#(S.nestUnresolved or {})
            for attempt=1,3 do
                task.wait(attempt==1 and 0.75 or (attempt==2 and 1.50 or 2.50))
                if not Runtime.alive
                    or Runtime.teleporting
                    or tostring(game.JobId)~=retryJob
                    or S.state=="JOINING"
                    or S.state=="RECOVERING"
                then
                    break
                end

                local retryMode=(S.mode=="hunting") and "premium" or "full"
                local ok,err=pcall(scanNow,retryMode,99)
                if not ok then
                    logLine("NEST RETRY ERROR · "..tostring(err))
                    break
                end

                local remaining=#(S.nestUnresolved or {})
                local improved=remaining<previousCount
                logLine("NEST RETRY · "..tostring(previousCount).." -> "..tostring(remaining))

                if improved then
                    writeSnapshot()
                end
                if remaining==0 then
                    logLine("NEST RETRY · resolved")
                    break
                end
                if not improved then
                    logLine("NEST RETRY no progress attempt "..tostring(attempt).."/3")
                end
                previousCount=remaining
            end
            if tostring(game.JobId)==retryJob then
                Runtime.unresolvedRetryDoneJob=retryJob
            end
            if Runtime.unresolvedRetryJob==retryJob then Runtime.unresolvedRetryJob=nil end
        end)
    end

    if requireNodeAck==true and cycleScanResult
        and tostring(payload.job_id or "")==cycleScanResult.jobId
        and Runtime.cycleContextValid(cycleScanResult) then
        local generation,scanStart=Runtime.cycleWindow(nowUnix())
        if cycleScanResult.generation==generation and cycleScanResult.scanStartedAt>=scanStart then
            Runtime.cycleScanAck={jobId=cycleScanResult.jobId,token=cycleScanResult.token,
                generation=generation,scanStartedAt=cycleScanResult.scanStartedAt,
                dayReady=cycleScanResult.dayReady,ackedAt=nowUnix()}
        end
    end
    Shared.VYRO_CORE_LAST_SNAPSHOT = payload
    return true
end

local function getQueueFn()
    if type(Shared.__VYRO_EXEC._QOT)=="function" then return Shared.__VYRO_EXEC._QOT,"queue" end
    if type(syn)=="table" and type(syn.queue_on_teleport)=="function" then
        return syn.queue_on_teleport,"syn.queue"
    end
    return nil,"unavailable"
end

local function refreshRuntimeFromNode()
    local req=getRequestFn()
    if not req or type(Shared.__VYRO_EXEC._WF)~="function" then return false end
    local headers=nodeHeaders();headers["Accept"]="text/plain"
    local ok,res=pcall(req,{Url=NODE_BASE.."/v1/runtime",Method="GET",Headers=headers})
    if not ok or type(res)~="table" then return false end
    local status=tonumber(res.StatusCode or res.Status)
    local body=tostring(res.Body or "")
    if not status or status<200 or status>=300 or #body<1000 then return false end
    if not body:find("VYRO%-PRIME%-CORE",1,false) then return false end
    return pcall(function() Shared.__VYRO_EXEC._WF(CFG.RUNTIME_FILE,body) end)
end

local function queueSelf()
    -- Best effort refresh now, but the queued boot also fetches fresh after teleport.
    pcall(refreshRuntimeFromNode)

    local fn,queueName = getQueueFn()
    S.queueAvailable = fn ~= nil
    S.queueFunction = queueName
    if not fn then return false,"queueonteleport no disponible" end

    local _rnd = tostring(math.random(10000,99999))
    local code = string.format([[
task.spawn(function()
    local P=game:GetService("Players")
    local HS=game:GetService("HttpService")
    -- A slow GPU worker can change JobId long before Roblox reports
    -- game:IsLoaded(). The old bootstrap spent its entire 30s budget waiting
    -- here, then had zero time left to fetch/run VYRO. Use a readiness budget
    -- and a separate execution budget so slow landings never exhaust bootstrap.
    local landingDeadline=time()+35
    local lp=nil
    local worldReady=false
    repeat
        pcall(function() lp=P.LocalPlayer end)
        local loaded=false
        pcall(function() loaded=game:IsLoaded() end)
        worldReady=false
        pcall(function()
            local RS=game:GetService("ReplicatedStorage")
            local objects=workspace:FindFirstChild("__OBJECTS")
            local areas=objects and objects:FindFirstChild("Areas")
            local guards=areas and areas:FindFirstChild("GuardAreas")
            local rendered=workspace:FindFirstChild("ClientRenderedAssets")
            local data=RS:FindFirstChild("Data")
            local camera=workspace.CurrentCamera
            worldReady=(guards~=nil) or (rendered~=nil) or (data~=nil and camera~=nil)
        end)
        if lp and tostring(game.JobId or "")~="" and (loaded or worldReady) then break end
        task.wait(0.10)
    until time()>=landingDeadline

    local marker=%q
    local runtimeFile=%q
    local nodeBase=%q
    local lastErr=worldReady and "world_ready_executor_wait" or "landing_slow_executor_wait"
    local execDeadline=time()+30
    while time()<execDeadline do
        lp=P.LocalPlayer or lp
        local body=nil
        local good=false
        local R=request or http_request or (type(syn)=="table" and syn.request) or (type(http)=="table" and http.request)
        if lp and type(R)=="function" then
            local url=nodeBase.."/v1/loader/bot.lua?account="..HS:UrlEncode(lp.Name or "").."&t="..tostring(os.time())
            local rq,rs=pcall(R,{Url=url,Method="GET",Headers={["Accept"]="text/plain"}})
            if rq and type(rs)=="table" then
                local st=tonumber(rs.StatusCode or rs.Status)
                local candidate=tostring(rs.Body or "")
                if st and st>=200 and st<300 and #candidate>1000 and candidate:find(marker,1,true) then
                    body=candidate
                    good=true
                else
                    lastErr="http_"..tostring(st)
                end
            else
                lastErr="request_failed"
            end
        end

        if not good and type(readfile)=="function" then
            local okRead,candidate=pcall(readfile,runtimeFile)
            if okRead and type(candidate)=="string" and #candidate>1000 and candidate:find(marker,1,true) then
                body=candidate
                good=true
            end
        end

        if good and type(loadstring)=="function" then
            local fn,compileErr=loadstring(body)
            if fn then
                local okRun,runErr=pcall(fn)
                if okRun then return end
                lastErr="runtime_"..tostring(runErr)
            else
                lastErr="compile_"..tostring(compileErr)
            end
        elseif good then
            lastErr="loadstring_not_ready"
        end
        task.wait(0.25)
    end
    warn("[VYRO BOOT] teleport bootstrap exhausted: "..tostring(lastErr))
end)
local _=%q
]],CFG.VERSION_MARKER,CFG.RUNTIME_FILE,NODE_BASE,_rnd)

    -- Avoid stacking stale VYRO reexec entries when TEST/HOP is pressed repeatedly.
    if type(clearteleportqueue)=="function" then
        pcall(clearteleportqueue)
    elseif type(clear_teleport_queue)=="function" then
        pcall(clear_teleport_queue)
    end

    local before=nil
    if type(getteleportqueue)=="function" then
        local okBefore,q=pcall(getteleportqueue)
        if okBefore and type(q)=="table" then before=#q end
    end

    local ok,err=pcall(fn,code)
    if not ok then return false,tostring(err) end

    if type(getteleportqueue)=="function" then
        local okAfter,q=pcall(getteleportqueue)
        if okAfter and type(q)=="table" then
            S.teleportQueueCount=#q
            if #q==0 then
                return false,"Wave queueonteleport aceptÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³ llamada pero queue quedÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³ vacÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­a"
            end
            if before~=nil and #q<=before and before>0 then
                logLine("QUEUE VERIFY ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· count="..tostring(#q))
            end
        end
    end

    return true,queueName
end

local function armReexec(quiet)
    if S.reexecArmed then return true end
    if Runtime.reexecArming then
        local deadline=time()+1.50
        repeat task.wait(0.02) until not Runtime.reexecArming or time()>=deadline
        return S.reexecArmed==true
    end

    Runtime.reexecArming=true
    S.reexecError=nil
    if not quiet then
        setState("ARMING","Preparando auto-reexec")
        writeStatus()
    end

    for attempt=1,CFG.REEXEC_ARM_ATTEMPTS do
        local ok,err=queueSelf()
        if ok then
            S.reexecArmed=true
            S.reexecError=nil
            Runtime.reexecArming=false
            if not quiet then
                setState("ARMED","Auto-reexec listo Â· "..tostring(S.queueFunction or "queue"))
                writeStatus()
            end
            return true
        end
        S.reexecError=tostring(err)
        task.wait(CFG.REEXEC_ARM_RETRY_SEC)
    end

    Runtime.reexecArming=false
    if not quiet then
        setState("BLOCKED","Auto-reexec no disponible")
        writeStatus()
        logLine("HOP BLOQUEADO Â· "..tostring(S.reexecError))
    end
    return false
end



local function httpGet(url)
    local req = getRequestFn()
    if req then
        local ok,res = pcall(req,{
            Url=url,
            Method="GET",
            Headers={["Accept"]="application/json"},
        })
        if not ok then return nil,nil,nil,tostring(res) end
        if type(res)~="table" then return nil,nil,nil,"respuesta invalida" end
        return tostring(res.Body or ""),tonumber(res.StatusCode or res.Status),res.Headers,nil
    end

    return nil,nil,nil,"request_unavailable"
end

local function trimServerQueue()
    local clean,seen = {},{}
    for _,server in ipairs(S.serverQueue or {}) do
        if type(server)=="table" then
            local id = tostring(server.id or "")
            if id~=""
                and id~=tostring(game.JobId)
                and not S.visited[id]
                and not seen[id]
            then
                clean[#clean+1] = {
                    id=id,
                    playing=tonumber(server.playing) or 0,
                    maxPlayers=tonumber(server.maxPlayers) or 0,
                }
                seen[id]=true
            end
        end
    end
    S.serverQueue=clean
end

local function refillServers(force)
    trimServerQueue()
    if #S.serverQueue>CFG.SERVER_PREFETCH_MIN and not force then return true end

    local now=nowUnix()
    if not force and now < (S.serverFetchNotBefore or 0) then
        return false,"cooldown"
    end

    local rows=nil
    local source=""

    -- Production path: all scanner accounts share one node-side server pool.
    -- The bridge caches/paginates Roblox's public list and keeps the last good
    -- pool through transient 429s, so 8 accounts do not hammer the same API.
    local nodeData,nodeErr=requestJson("POST",NODE_BASE.."/v1/server-pool",{
        place_id=tostring(game.PlaceId),
        limit=CFG.SERVER_LIMIT,
    },nodeHeaders())

    if type(nodeData)=="table" and type(nodeData.servers)=="table" and #nodeData.servers>0 then
        rows=nodeData.servers
        source=tostring(nodeData.source or "node_shared_cache")
        S.serverPoolSource=source
        S.serverPoolCount=tonumber(nodeData.count) or #rows
        S.serverPoolGeneration=tonumber(nodeData.generation) or 0
        S.serverPoolCacheAge=tonumber(nodeData.cache_age_seconds) or 0
        S.lastServerHttpStatus=tonumber(nodeData.http_status) or 200
        S.serverFetchFailures=0
        S.serverFetchNotBefore=now+CFG.SERVER_NODE_REFRESH_COOLDOWN
    else
        -- CENTRALPOOL: Runtime never calls Roblox server-list APIs directly.
        -- Producer -> CentralPool -> NodeAgent is the only discovery path.
        S.serverPoolSource="centralpool_wait"
        S.lastServerHttpStatus=type(nodeData)=="table" and tonumber(nodeData.http_status) or nil
        local waitSec=CFG.SERVER_NODE_REFRESH_COOLDOWN
        if type(nodeData)=="table" then
            waitSec=math.max(waitSec,math.min(15,tonumber(nodeData.cooldown_seconds) or waitSec))
        end
        S.serverFetchNotBefore=now+waitSec
        return false,"centralpool:"..tostring(nodeErr or (type(nodeData)=="table" and nodeData.http_status) or "empty")
    end

    pcall(function() Runtime.cacheJobCandidates(rows or {}) end)

    local candidates={}
    local queued={}
    for _,server in ipairs(S.serverQueue) do queued[tostring(server.id or "")]=true end
    for _,server in ipairs(rows or {}) do
        local id=tostring(server.id or "")
        local playing=tonumber(server.playing) or 999999
        local maxPlayers=tonumber(server.maxPlayers) or 0
        if id~=""
            and id~=tostring(game.JobId)
            and maxPlayers>0
            and (maxPlayers-playing)>=CFG.MIN_FREE_SLOTS
            and not S.visited[id]
            and not queued[id]
        then
            candidates[#candidates+1]={id=id,playing=playing,maxPlayers=maxPlayers}
        end
    end

    table.sort(candidates,function(a,b)
        if a.playing~=b.playing then return a.playing<b.playing end
        return a.id<b.id
    end)

    for _,server in ipairs(candidates) do S.serverQueue[#S.serverQueue+1]=server end
    table.sort(S.serverQueue,function(a,b)
        if a.playing~=b.playing then return a.playing<b.playing end
        return a.id<b.id
    end)

    if #S.serverQueue==0 then return false,"sin JobIds nuevos:"..source end
    return true
end

local function takeServer()
    trimServerQueue()
    if #S.serverQueue==0 then return nil end
    return table.remove(S.serverQueue,1)
end

local function nodeIdentity()
    return {account_id=tostring(LP.UserId),label=tostring(LP.Name),current_job_id=tostring(game.JobId)}
end

local function nodeClaimServer(candidates,collisionRecovery)
    if not refreshNodeConfig(false) then return nil,"node_offline" end
    local current=tostring(game.JobId)
    local filtered={}
    for _,candidate in ipairs(candidates or {}) do
        if tostring(candidate.id or candidate.job_id or "")~=current then
            filtered[#filtered+1]=candidate
        end
    end
    if #filtered==0 and collisionRecovery~=true then return nil,"node_no_noncurrent_candidate" end
    local payload=nodeIdentity();payload.candidates=filtered;payload.collision_recovery=collisionRecovery==true
    local claimStarted=os.clock()
    local data,err=requestJson("POST",NODE_BASE.."/v1/claim",payload,nodeHeaders())
    S.claimLatencyMs=math.floor((os.clock()-claimStarted)*10000+0.5)/10
    if not data then return nil,err end
    if data.claimed~=true or not data.job_id then return nil,"node_no_unique_server" end
    S.claimSource=tostring(data.selection_reason or data.source or "node")
    S.claimScore=tonumber(data.selection_score)
    S.lastClaimRecentlyScanned=data.recently_scanned==true
    if S.lastClaimRecentlyScanned then
        S.claimRecent=(tonumber(S.claimRecent) or 0)+1
    else
        S.claimFresh=(tonumber(S.claimFresh) or 0)+1
    end
    if tostring(data.job_id)==current then return nil,"node_returned_current_job" end
    local candidate=data.candidate or {}
    return {id=tostring(data.job_id),playing=tonumber(candidate.playing) or 0,maxPlayers=tonumber(candidate.maxPlayers or candidate.max_players) or 0,lease_expires_at=tonumber(data.lease_expires_epoch or data.lease_expires_at)},nil
end

function Runtime.claimCachedJob(reason)
    local data=Runtime.loadJobCache()
    local now=os.time()
    local current=tostring(game.JobId)
    local eligible={}
    for _,row in ipairs(data.servers or {}) do
        local jid=tostring(row.jobId or "")
        local seen=tonumber(row.lastSeen) or 0
        if jid~="" and jid~=current and row.bad~=true and (seen<=0 or (now-seen)>=60) then
            eligible[#eligible+1]={
                id=jid,
                playing=tonumber(row.playing) or 0,
                maxPlayers=tonumber(row.maxPlayers) or 0,
            }
        end
    end
    while #eligible>0 do
        local index=math.random(1,#eligible)
        local candidate=table.remove(eligible,index)
        local claimed,err=nodeClaimServer({candidate})
        if claimed and claimed.id then
            S.claimSource="cache_claim:"..tostring(reason or "429")
            return claimed,nil
        end
        if err=="node_offline" then return nil,err end
    end
    return nil,"cache_no_alternate"
end

local beginHunt
local function sendNodeHeartbeat()
    if not refreshNodeConfig(false) then return false end
    local payload=nodeIdentity()
    payload.details={
        state=S.state,
        state_detail=S.stateDetail,
        mode=S.mode,
        hunt_remaining=huntRemaining(),
        hunt_remaining_seconds=(S.mode=="hunting" and S.huntEnd) and math.max(0,math.floor(S.huntEnd-nowUnix())) or 0,
        scan_window_seconds=CFG.HUNT_SECONDS,
        parked=S.mode=="parked",
        ultra_lite_test=S.ultraLiteTest==true,
        ultra_aggressive=S.ultraAggressive==true,
        ultra_fps_target=S.ultraFpsTarget,
        ultra_render_enabled=S.ultraRenderEnabled,
        raw_eggs=#(S.rawEggs or {}),
        world_eggs=#(S.eggs or {}),
        premium_eggs=#(S.targets or {}),
        qualified_eggs=#(S.qualifiedTargets or {}),
        hops=S.hops,
        server_queue=#(S.serverQueue or {}),
        servers_per_min=serversPerMinute(),
        memory_mb=S.memoryMb,
        base_map_resolved=S.baseMapResolved==true,
        node_connected=S.nodeConnected==true,
        cloud_ok=(S.lastCloudStatus=="skip_no_qualified" or S.lastCloudStatus=="skip_no_verified") or (S.lastCloudError==nil and S.lastCloudOkAt~=nil),
        cloud_last_ok_at=S.lastCloudOkAt,
        quality_policy_version=S.qualityPolicyVersion,
        eggstate_mutation_values=PatchSZ.mutationTelemetry(),
        enchanted_mutation_aliases=PatchSZ.enchantedMutationAliases(),
        quality_reason_counts=S.qualityReasonCounts or {},
        target_preview=S.targetPreview or {},
        live_mutation_aliases=Shared.__VYRO_LIVE_MUTATION_ALIASES or {},
        eggstate_mutation_values_raw=Shared.__VYRO_EGGSTATE_MUTATION_VALUES or {},
        enchanted_catalog=enchantedCatalogSnapshot(),
        fingerprint_known=S.fingerprintKnown or 0,
        fingerprint_unknown=S.fingerprintUnknown or 0,
        stale_side_visuals=S.staleSideVisuals or 0,
        shared_fingerprint_conflicts=S.sharedFingerprintConflicts or 0,
        blacklisted_identity=S.blacklistedIdentity or 0,
        generic_slot_shells=S.genericSlotShells or 0,
        no_mesh_identity=S.noMeshIdentity or 0,
        unknown_fingerprints=S.unknownFingerprints or {},
        unknown_fingerprint_details=S.unknownFingerprintDetails or {},
        light_dark_side=S.lightDarkSide,
        nest_slots_total=S.nestSlotsTotal or 0,
        nest_slots_resolved=S.nestSlotsResolved or 0,
        nest_slot_source=S.nestSlotSource or "none",
        nest_unresolved=S.nestUnresolved or {},
        nest_identity_unresolved=S.nestIdentityUnresolved or {},
        visual_expected=S.lastVisualExpected or 0,
        visual_matched=S.lastVisualMatched or 0,
        visual_present=S.visualPresent or 0,
        event_flags=S.eventFlags or {},
        cycle_probe=cycleProbeSnapshot(),
        phase=S.phase,
        lighting_clock_time=S.lightingClockTime,
        lighting_rate_hours_per_sec=S.lightingRateHoursPerSec,
        day_night_eta_seconds=S.dayNightEtaSeconds,
        cycle_period_hint=S.cyclePeriodHint,
        cycle_night_seconds_hint=S.cycleNightSecondsHint,
        cycle_winner=S.cycleWinner,
        cycle_eta_seconds=S.cycleEtaSeconds,
        cycle_eta_source=S.cycleEtaSource,
        cycle_edge_count=S.cycleEdgeCount or 0,
        last_cycle_edge_at=S.lastCycleEdgeAt,
        hunt_started_at=S.huntStartedAt,
        fleet_cycle_generation=S.fleetCycleGeneration or 0,
        fleet_cycle_epoch=S.fleetCycleEpoch,
        fleet_scan_start=S.fleetScanStart,
        fleet_cycle_end=S.fleetCycleEnd,
        observed_cycle_seconds=S.observedCycleSeconds,
        scan_ms=S.lastScanMs,
        scans=S.scans,
        total_eggs_sent=S.totalEggsSent or 0,
        last_eggs_sent=S.lastEggsSent or 0,
        cycle_eggs_sent=math.max(0,(tonumber(S.totalEggsSent) or 0)-(tonumber(S.huntEggsSentStart) or 0)),
        cycle_servers_visited=countKeys(S.visited or {}),
        first10_world_eggs_max=tonumber(S.first10WorldEggsMax) or 0,
        first10_raw_eggs_max=tonumber(S.first10RawEggsMax) or 0,
        first10_scans=tonumber(S.first10Scans) or 0,
        nonempty_confirmed=(S.nonEmptyConfirmed==true),
        nonempty_retry_attempts=tonumber(S.nonEmptyRetryAttempts) or 0,
        backend_whitelist_accepted=S.lastRawAccepted or 0,
        backend_whitelist_ignored=S.lastRawIgnored or 0,
        duplicate_rows_dropped=S.lastDuplicateRowsDropped or 0,
        last_error=S.lastError,
        premium_read_complete=S.premiumReadComplete,
        readiness_policy=S.readinessPolicy,
        last_node_error=S.lastNodeError,
        last_teleport_failure=S.lastTeleportFailure,
        last_hop_attempt=S.lastHopAttempt,
        pending_started_ms=S.pendingStartedMs,
        joining_elapsed_ms=(S.pendingStartedMs and math.max(0,nowMs()-S.pendingStartedMs) or nil),
        last_hop_target=S.lastHopTarget,
        current_job_id=S.currentJobId,
        landing_confirmed_at=S.lastLandingConfirmedAt,
        landing_confirmed_ms=S.lastLandingConfirmedMs,
        landing_confirmed_job=S.lastLandingConfirmedJob,
        landing_pending_job=S.lastLandingPendingJob,
        silent_teleport_failures=S.silentTeleportFailures or 0,
        reexec_armed=S.reexecArmed==true,
        queue_available=S.queueAvailable==true,
        coordinator_active=S.coordinatorActive==true,
        coord_conflict=S.coordConflict==true,
        coord_source=S.coordSource,
        claim_latency_ms=S.claimLatencyMs,
        claim_source=S.claimSource,
        claim_score=S.claimScore,
        claim_recently_scanned=S.lastClaimRecentlyScanned,
        claim_fresh=S.claimFresh or 0,
        claim_recent=S.claimRecent or 0,
        coverage_new_ratio=((tonumber(S.claimFresh) or 0)+(tonumber(S.claimRecent) or 0))>0 and ((tonumber(S.claimFresh) or 0)/((tonumber(S.claimFresh) or 0)+(tonumber(S.claimRecent) or 0))) or nil,
        teleport_avg_ms=S.teleportAvgSec and math.floor((tonumber(S.teleportAvgSec) or 0)*1000+0.5) or nil,
        teleport_success_samples=S.teleportSuccessSamples or 0,
        adaptive_watchdog_sec=S.adaptiveWatchdogSec or CFG.TELEPORT_WATCHDOG_SEC,
        cloud_upload_ms=S.cloudUploadMs,
        snapshot_ack_ms=S.snapshotAckMs,
        snapshot_ack_ok=S.snapshotAckOk==true,
        snapshot_ack_job=S.snapshotAckJob,
        snapshot_ack_at=S.snapshotAckAt,
        fast_fanout_ms=S.fastFanoutMs,
        fast_ack_count=S.fastAckCount or 0,
        fast_ack_last=S.fastAckLast,
        fast_retry_queued=S.fastRetryQueued==true,
        cloud_retry_persisted=S.cloudRetryPersisted==true,
        cloud_route=S.cloudRoute,
        snapshot_transport_rev="safe409v3",
        snapshot_transport_last_error=(S.cloudRoute=="node_required_send_all") and tostring(S.lastCloudError or ""):sub(1,160) or nil,
        patch_events=S.patchEvents or {},
        quarantine=S.quarantinedEgg,
        quarantine_updated_at=S.quarantineUpdatedAt,
        cycle_time_left=S.cycleEtaSeconds,
        version=CFG.VERSION,
    }
    local data,err=requestJson("POST",NODE_BASE.."/v1/heartbeat",payload,nodeHeaders())
    if err then S.lastNodeError=tostring(err);return false end
    S.lastNodeError=nil;S.nodeConnected=true
    S.coordConflict=(type(data)=="table" and data.conflict==true) or false
    S.coordSource=(type(data)=="table" and tostring(data.coord_source or data.source or "")) or ""
    S.coordConflictJob=(type(data)=="table" and tostring(data.coord_conflict_job or "")) or ""
    S.coordConflictAt=(type(data)=="table" and tonumber(data.coord_conflict_at)) or 0
    S.coordCollisionAllowed=(type(data)=="table" and data.coord_collision_allowed==true) or false
    if type(data)=="table" and data.coord_error and tostring(data.coord_error)~="" then
        S.lastNodeError="coord:"..tostring(data.coord_error)
    end
    -- Authoritative fleet cycle. The reset edge begins an explicit RESET_WAIT
    -- phase; eggs are expected only after scan_start, then the full 240s hunt begins.
    if type(data)=="table" and data.fleet_cycle_authoritative==true and type(beginHunt)=="function" then
        local gen=tonumber(data.fleet_cycle_generation) or 0
        local epoch=tonumber(data.fleet_cycle_epoch)
        local scanStart=tonumber(data.fleet_scan_start)
        local endAt=tonumber(data.fleet_hunt_until)
        local resetRemaining=math.max(0,tonumber(data.fleet_reset_wait_remaining_seconds) or 0)
        local cycleNow=nowUnix()
        local currentGen,currentStart,currentEnd=Runtime.cycleWindow(cycleNow)
        if gen~=currentGen or scanStart~=currentStart or endAt~=currentEnd then
            return not S.coordConflict
        end
        -- Timestamps are authoritative for the local wake boundary. A delayed
        -- heartbeat that was computed during RESET_WAIT must never re-park a
        -- client after scanStart has already passed.
        local active=scanStart and endAt and cycleNow>=scanStart and endAt>cycleNow
        local newGeneration=(gen>0 and gen~=(tonumber(S.fleetCycleGeneration) or 0))

        S.fleetCycleGeneration=gen
        S.fleetCycleEpoch=epoch
        S.fleetScanStart=scanStart
        S.fleetCycleEnd=endAt
        S.fleetCyclePhase=tostring(data.fleet_cycle_phase or "")

        -- Arm a local wake-up from the authoritative NodeAgent schedule.
        -- The old path waited for a *later* heartbeat response after scan_start;
        -- under 39-account HTTP bursts that could leave a healthy client in
        -- RESET_WAIT for 60-100+ seconds. NodeAgent still owns the timestamp;
        -- this timer only guarantees the client wakes at that timestamp.
        if gen>0 and scanStart and endAt and endAt>scanStart then
            local timerKey=tostring(gen).."|"..tostring(scanStart).."|"..tostring(endAt)
            if Runtime.fleetScanTimerKey~=timerKey then
                Runtime.fleetScanTimerKey=timerKey
                local wakeDelay=math.max(0,scanStart-nowUnix())+0.02
                task.delay(wakeDelay,function()
                    if not Runtime.alive then return end
                    if Runtime.fleetScanTimerKey~=timerKey then return end
                    if tonumber(S.fleetCycleGeneration)~=gen then return end
                    local wakeNow=nowUnix()
                    if wakeNow<scanStart or wakeNow>=endAt then return end
                    if S.mode~="hunting" or tonumber(S.huntEnd)~=tonumber(endAt) then
                        local remaining=math.max(1,endAt-wakeNow)
                        local ok,started=pcall(beginHunt,"Fleet timer wake #"..tostring(gen),true,remaining)
                        if ok and started~=false then
                            S.huntEnd=endAt
                            S.huntStartedAt=scanStart
                            S.first10EndsAt=scanStart+10
                            S.testDuration=CFG.HUNT_SECONDS
                            saveState()
                            writeStatus()
                            logLine(string.format("FLEET TIMER WAKE · gen=%s · late=%.2fs",tostring(gen),math.max(0,wakeNow-scanStart)))
                        elseif not ok then
                            S.lastError="fleet_timer_wake:"..tostring(started)
                        end
                    end
                end)
            end
        end

        if (not active) and resetRemaining>0 and scanStart and nowUnix()<scanStart then
            -- Invalidate every old hunt callback/retry and freeze on the current server.
            Runtime.huntToken=nil
            Runtime.huntLoopRunning=false
            Runtime.teleporting=false
            Runtime.preclaiming=false
            S.mode="parked"
            S.huntEnd=nil
            S.testDuration=nil
            S.pendingJobId=nil
            S.pendingStartedMs=nil
            S.serverQueue={}
            S.reexecArmed=false
            S.preclaimedServer=nil
            S.preclaimFromJobId=nil
            S.preclaimAt=nil
            S.preclaimError=nil

            -- Flush previous-cycle egg state exactly once per generation.
            if newGeneration or tonumber(S.resetWaitGeneration)~=gen then
                S.resetWaitGeneration=gen
                S.rawEggs={}
                S.eggs={}
                S.targets={}
                S.qualifiedTargets={}
                S.carriedTargets={}
                S.chatProvisionalTargets={}
                S.serverSeenTargetUids={}
                S.lastEggCount=0
                S.lastEggsSent=0
                S.lastRawAccepted=0
                S.lastRawIgnored=0
                S.first10WorldEggsMax=0
                S.first10RawEggsMax=0
                S.first10Scans=0
            end
            setState("RESET_WAIT","Reinicio nocturno · huevos en ~"..tostring(resetRemaining).."s")
            saveState()
            writeStatus()
        elseif active then
            local remaining=math.max(0,endAt-nowUnix())
            if S.mode~="hunting" or tonumber(S.huntEnd)~=tonumber(endAt) then
                if beginHunt("Fleet post-reset #"..tostring(gen),true,remaining)==false then
                    return not S.coordConflict
                end
                S.huntEnd=endAt
                S.huntStartedAt=scanStart or (endAt-CFG.HUNT_SECONDS)
                S.first10EndsAt=(S.huntStartedAt or nowUnix())+10
                S.testDuration=CFG.HUNT_SECONDS
                saveState()
                writeStatus()
            else
                S.huntEnd=endAt
            end
        elseif (not CFG.CONTINUOUS_SCAN) and S.mode=="hunting" and endAt and nowUnix()>=endAt and type(Runtime.stopHunt)=="function" then
            Runtime.stopHunt("Ventana global terminada")
        end
    end
    return not S.coordConflict
end


local function clearPreclaim()
    S.preclaimedServer=nil
    S.preclaimFromJobId=nil
    S.preclaimAt=nil
    S.preclaimError=nil
end

local function validPreclaim()
    local row=S.preclaimedServer
    if type(row)~="table" or not row.id then return nil end
    if tostring(S.preclaimFromJobId or "")~=tostring(game.JobId) then
        clearPreclaim()
        return nil
    end
    local age=nowUnix()-(tonumber(S.preclaimAt) or 0)
    if age<0 or age>18 then
        clearPreclaim()
        return nil
    end
    return row
end

local function takePreclaim()
    local row=validPreclaim()
    if not row then return nil end
    S.preclaimedServer=nil
    S.preclaimFromJobId=nil
    S.preclaimAt=nil
    S.preclaimError=nil
    return row
end

local function beginServerPreclaim(reason)
    if Runtime.preclaiming or Runtime.teleporting then return false end
    if validPreclaim() then return true end
    trimServerQueue()
    if #S.serverQueue==0 then return false end

    local current=tostring(game.JobId)
    local candidates={}
    for _,server in ipairs(S.serverQueue) do
        if tostring(server.id or "")~=current then
            candidates[#candidates+1]={id=server.id,playing=server.playing,maxPlayers=server.maxPlayers}
        end
    end
    if #candidates==0 then return false end

    Runtime.preclaiming=true
    task.spawn(function()
        local claimed,err=nodeClaimServer(candidates)
        if Runtime.alive
            and tostring(game.JobId)==current
            and not Runtime.teleporting
        then
            if claimed and claimed.id then
                local wanted=tostring(claimed.id)
                for i,server in ipairs(S.serverQueue) do
                    if tostring(server.id)==wanted then
                        table.remove(S.serverQueue,i)
                        break
                    end
                end
                S.preclaimedServer=claimed
                S.preclaimFromJobId=current
                S.preclaimAt=nowUnix()
                S.preclaimError=nil
                S.preclaimReason=tostring(reason or "scan")
            else
                S.preclaimError=tostring(err or "no_claim")
            end
        end
        Runtime.preclaiming=false
    end)
    return true
end

local function chooseServerForAccount(reason)
    trimServerQueue()

    local preclaimed=takePreclaim()
    if preclaimed then
        S.coordinatorActive=true
        S.claimSource="preclaimed"
        return preclaimed,nil
    end

    if Runtime.preclaiming then
        -- A preclaim normally finishes in sub-second time. Give the
        -- in-flight reservation a short chance to finish before issuing a
        -- second synchronous claim on the hop critical path.
        local deadline=time()+0.85
        repeat task.wait(0.01) until not Runtime.preclaiming or time()>=deadline
        preclaimed=takePreclaim()
        if preclaimed then
            S.coordinatorActive=true
            S.claimSource="preclaimed_wait"
            return preclaimed,nil
        end
    end

    if #S.serverQueue==0 then return nil,"queue_empty" end

    -- Randomize the front of the queue so accounts do not follow identical hop order.
    if #S.serverQueue > 1 then
        local _r = math.random(1, math.min(3, #S.serverQueue))
        local _tmp = S.serverQueue[1]
        S.serverQueue[1] = S.serverQueue[_r]
        S.serverQueue[_r] = _tmp
    end

    -- Optional external coordinator hook. When installed, the coordinator is
    -- authoritative: failure blocks the hop instead of falling back and risking
    -- two accounts covering the same JobId.
    if (not MULTI_ACCOUNT) and type(Shared.VYRO_CORE_CLAIM_SERVER)=="function" then
        local candidates={}
        for i,server in ipairs(S.serverQueue) do
            candidates[i]={id=server.id,playing=server.playing,maxPlayers=server.maxPlayers}
        end
        local ok,result=pcall(Shared.VYRO_CORE_CLAIM_SERVER,{
            account_id=tostring(LP.UserId),
            label=tostring(LP.Name),
            current_job_id=tostring(game.JobId),
            reason=tostring(reason or "hop"),
            candidates=candidates,
        })
        if not ok then
            return nil,"coordinator_error:"..tostring(result)
        end
        if type(result)~="table" or not result.id then
            return nil,"coordinator_no_unique_server"
        end
        local wanted=tostring(result.id)
        for i,server in ipairs(S.serverQueue) do
            if tostring(server.id)==wanted then
                table.remove(S.serverQueue,i)
                S.coordinatorActive=true
                return server,nil
            end
        end
        return nil,"coordinator_returned_unknown_job"
    end

    -- Native node coordinator path: required in multi-account production.
    local candidates={}
    local currentJob=tostring(game.JobId)
    for _,server in ipairs(S.serverQueue) do
        if tostring(server.id)~=currentJob then
            candidates[#candidates+1]={id=server.id,playing=server.playing,maxPlayers=server.maxPlayers}
        end
    end
    if #candidates==0 then
        return nil,"no_noncurrent_server"
    end
    local claimed,claimErr=nodeClaimServer(candidates)
    if claimed then
        for i,server in ipairs(S.serverQueue) do
            if tostring(server.id)==tostring(claimed.id) then table.remove(S.serverQueue,i);break end
        end
        S.coordinatorActive=true
        return claimed,nil
    end
    if MULTI_ACCOUNT then
        S.coordinatorActive=false
        return nil,"coordinator_required:"..tostring(claimErr)
    end

    S.coordinatorActive=false
    return takeServer(),nil
end

local function applyLite()
    if not CFG.LITE_MODE then
        pcall(function()
            if type(setfpscap)=="function" then setfpscap(60) end
        end)
        pcall(function()
            if RunService and type(RunService.Set3dRenderingEnabled)=="function" then
                RunService:Set3dRenderingEnabled(true)
            end
        end)
        S.ultraLiteTest=false
        S.ultraAggressive=false
        S.ultraFpsTarget=60
        S.ultraRenderEnabled=true
        return
    end

    local fps = ULTRA_LITE_AGGRESSIVE and 10 or (ULTRA_LITE_TEST and 8 or (CFG.FPS_CAP + (math.random() * 2 - 1)))
    pcall(function()
        if type(setfpscap)=="function" then setfpscap(fps) end
    end)
    pcall(function() Lighting.GlobalShadows=false end)
    pcall(function()
        local rendering=settings().Rendering
        if rendering then rendering.QualityLevel=Enum.QualityLevel.Level01 end
    end)

    -- Keep replication/rendering alive. Only cheap post-processing is disabled.
    for _,obj in ipairs(Lighting:GetChildren()) do
        pcall(function()
            if obj:IsA("BloomEffect")
                or obj:IsA("BlurEffect")
                or obj:IsA("DepthOfFieldEffect")
                or obj:IsA("SunRaysEffect")
            then
                obj.Enabled=false
            end
        end)
    end
end

local function applyUltraLiteDynamic()
    -- PARKED must keep full visual replication/rendering alive.
    -- Never disable 3D or throttle the client just because it is waiting for reset.
    pcall(function()
        if type(setfpscap)=="function" then setfpscap(5) end
    end)
    pcall(function()
        if RunService and type(RunService.Set3dRenderingEnabled)=="function" then
            RunService:Set3dRenderingEnabled(true)
        end
    end)
    S.ultraLiteTest=false
    S.ultraAggressive=false
    S.ultraFpsTarget=5
    S.ultraRenderEnabled=true
end

local function readCycleFingerprint()
    local flag=nil
    pcall(function() flag=workspace:GetAttribute("LiveEventFlag_LightDarkReveal") end)

    local zone=nil
    local objects=workspace:FindFirstChild("__OBJECTS")
    local build=objects and objects:FindFirstChild("Build")
    if build then
        pcall(function() zone=build:GetAttribute("LightDarkZoneRevealed") end)
    end

    local winnerPeriod,revealPeriod,winner=nil,nil,nil
    if type(flag)=="string" and flag~="" then
        local ok,data=pcall(function() return HttpService:JSONDecode(flag) end)
        if ok and type(data)=="table" then
            winnerPeriod=tonumber(data.WinnerPeriod)
            revealPeriod=tonumber(data.RevealPeriod)
            winner=data.Winner and tostring(data.Winner) or nil
        end
    end

    local clockTime=nil
    pcall(function() clockTime=tonumber(Lighting.ClockTime) end)
    local phase="UNKNOWN"
    if clockTime then
        phase=(clockTime>=CFG.DAY_START_CLOCK and clockTime<CFG.NIGHT_START_CLOCK) and "DAY" or "NIGHT"
    end

    local sampleAt=os.clock()
    if clockTime and S.lightingSampleClock and S.lightingSampleAt then
        local dt=sampleAt-S.lightingSampleAt
        if dt>=0.20 then
            local dh=clockTime-S.lightingSampleClock
            if dh < -12 then dh=dh+24 elseif dh > 12 then dh=dh-24 end
            local rate=dh/dt
            if rate>0.0001 and rate<12 then
                if S.lightingRateHoursPerSec then
                    S.lightingRateHoursPerSec=(S.lightingRateHoursPerSec*0.75)+(rate*0.25)
                else
                    S.lightingRateHoursPerSec=rate
                end
            end
        end
    end
    if clockTime then
        S.lightingSampleClock=clockTime
        S.lightingSampleAt=sampleAt
    end

    local periodHint=nil
    local nightHint=nil
    pcall(function() periodHint=tonumber(workspace:GetAttribute("AreaEggCyclePeriodSeconds")) end)
    pcall(function() nightHint=tonumber(workspace:GetAttribute("AreaEggCycleDefaultNightSeconds")) end)

    S.phase=phase
    S.lightingClockTime=clockTime
    S.cyclePeriodHint=periodHint
    S.cycleNightSecondsHint=nightHint
    S.cycleWinner=winner or (zone and tostring(zone)) or nil
    S.dayNightEtaSeconds=nil
    S.cycleEtaSource=nil

    local remainingHours=nil
    if clockTime then
        if phase=="DAY" then
            remainingHours=CFG.NIGHT_START_CLOCK-clockTime
            if remainingHours<0 then remainingHours=remainingHours+24 end
        elseif phase=="NIGHT" then
            if clockTime>=CFG.NIGHT_START_CLOCK then
                remainingHours=(24-clockTime)+CFG.DAY_START_CLOCK
            else
                remainingHours=CFG.DAY_START_CLOCK-clockTime
            end
        end
    end
    if remainingHours and remainingHours>=0 and S.lightingRateHoursPerSec and S.lightingRateHoursPerSec>0 then
        S.dayNightEtaSeconds=math.max(0,math.floor(remainingHours/S.lightingRateHoursPerSec+0.5))
    elseif remainingHours and remainingHours>=0 and periodHint and periodHint>0 then
        local nightSeconds=(nightHint and nightHint>0 and nightHint<periodHint) and nightHint or (periodHint/2)
        local phaseSeconds=(phase=="NIGHT") and nightSeconds or math.max(1,periodHint-nightSeconds)
        local phaseHours=(phase=="NIGHT")
            and ((24-CFG.NIGHT_START_CLOCK)+CFG.DAY_START_CLOCK)
            or (CFG.NIGHT_START_CLOCK-CFG.DAY_START_CLOCK)
        if phaseHours>0 then
            S.dayNightEtaSeconds=math.max(0,math.floor((remainingHours/phaseHours)*phaseSeconds+0.5))
            S.cycleEtaSource="cycle_period_metadata"
        end
    end

    if S.dayNightEtaSeconds then
        S.cycleEtaSeconds=S.dayNightEtaSeconds
        if not S.cycleEtaSource then S.cycleEtaSource="lighting_rate" end
    elseif S.lastCycleEdgeAt and S.observedCycleSeconds then
        S.cycleEtaSeconds=math.max(0,math.floor(S.observedCycleSeconds-(nowUnix()-S.lastCycleEdgeAt)))
        S.cycleEtaSource="observed_edges"
    else
        S.cycleEtaSeconds=nil
        S.cycleEtaSource="learning"
    end

    -- Once UTC auto-calibration is trusted, it becomes the single phase/ETA
    -- authority for status, snapshots and the dedicated day/night relay.
    pcall(function()
        if Shared.__VYRO_DAYNIGHT_SYNC and Shared.__VYRO_DAYNIGHT_SYNC.calibrated and type(Shared.__VYRO_DAYNIGHT_SYNC.Compute)=="function" then
            local precise=Shared.__VYRO_DAYNIGHT_SYNC:Compute(nowUnix())
            S.phase=precise.phase
            S.dayNightEtaSeconds=precise.secondsUntilPhaseChange
            S.cycleEtaSeconds=precise.secondsUntilPhaseChange
            S.cycleEtaSource="utc_autocalibrated"
            S.cyclePeriodHint=precise.cyclePeriod
            S.cycleNightSecondsHint=precise.nightSeconds
        end
    end)

    return table.concat({
        tostring(phase),
        tostring(winnerPeriod or "nil"),
        tostring(revealPeriod or "nil"),
        tostring(zone),
        tostring(winner or "nil"),
    },"|")
end

local startHuntLoop
local refreshEggUI
local refreshStatus

local function cycleWatcherTick()
    local fp=readCycleFingerprint()

    if S.cycleFingerprint==nil then
        S.cycleFingerprint=fp
        return
    end

    -- While hunting, servers naturally expose different snapshots.
    -- Update baseline but never restart the hunt because of a server hop.
    if S.mode=="hunting" then
        S.cycleFingerprint=fp
        return
    end

    if time() < S.cycleBaselineReadyAt then
        S.cycleFingerprint=fp
        return
    end

    if fp~=S.cycleFingerprint then
        local now=nowUnix()
        local old=S.cycleFingerprint
        local oldPhase=tostring(old or ""):match("^([^|]+)") or "UNKNOWN"
        local phaseChanged=(oldPhase~=tostring(S.phase))
        S.cycleFingerprint=fp

        if phaseChanged and (not S.lastCycleEdgeAt or now-S.lastCycleEdgeAt>=CFG.CYCLE_DEBOUNCE) then
            S.previousCycleEdgeAt=S.lastCycleEdgeAt
            S.lastCycleEdgeAt=now
            S.cycleEdgeCount=S.cycleEdgeCount+1
            S.quarantinedEgg=nil
            S.quarantineUpdatedAt=nil
            pushPatchEvent("quarantine_reset",{phase=tostring(S.phase),cycle_edge=S.cycleEdgeCount})

            if S.previousCycleEdgeAt then
                local observed=now-S.previousCycleEdgeAt
                if observed>=20 and observed<=1200 then
                    S.observedCycleSeconds=observed
                end
            end

            logLine("DAY/NIGHT EDGE #"..tostring(S.cycleEdgeCount).." ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..oldPhase.." -> "..tostring(S.phase))
        else
            logLine("LIGHT/DARK SIGNAL ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..oldPhase.." ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· winner="..tostring(S.cycleWinner))
        end

        -- Production scanning is edge-gated: only a real DAY<->NIGHT
        -- transition creates a fresh egg window. Other Light/Dark metadata
        -- changes update telemetry but must not waste hops mid-cycle.
        if phaseChanged and (not S.lastSignalEdgeAt or now-S.lastSignalEdgeAt>=CFG.CYCLE_DEBOUNCE) then
            S.lastSignalEdgeAt=now
            if S.nodeConnected then
                setState("PARKED","Reset "..oldPhase.."->"..tostring(S.phase).." detectado ? sincronizando flota")
                writeStatus()
                task.spawn(function() pcall(sendNodeHeartbeat) end)
            else
                -- Offline fail-safe follows the real egg mechanic too: the DAY->NIGHT
                -- edge is the 10s reset interval, not the moment eggs are available.
                local resetWait=math.max(1,(tonumber(S.cycleNightSecondsHint) or 10)+2)
                if tostring(S.phase)=="NIGHT" then
                    local resetEdge=now
                    S.localResetPendingAt=resetEdge
                    setState("RESET_WAIT","Reinicio nocturno · esperando "..tostring(math.floor(resetWait)).."s")
                    writeStatus()
                    task.delay(resetWait,function()
                        if Runtime.alive and not S.nodeConnected and S.mode=="parked" and tonumber(S.localResetPendingAt)==tonumber(resetEdge) then
                            S.localResetPendingAt=nil
                            beginHunt("reset local post-night",true,CFG.HUNT_SECONDS)
                        end
                    end)
                elseif tostring(S.phase)=="DAY" then
                    local pending=tonumber(S.localResetPendingAt)
                    if pending and now-pending<=resetWait+4 then
                        local due=pending+resetWait
                        local delaySec=math.max(0,due-now)
                        setState("RESET_WAIT","Reinicio nocturno · respetando espera mínima")
                        writeStatus()
                        task.delay(delaySec,function()
                            if Runtime.alive and not S.nodeConnected and S.mode=="parked" and tonumber(S.localResetPendingAt)==tonumber(pending) then
                                S.localResetPendingAt=nil
                                beginHunt("reset local night->day post-wait",true,CFG.HUNT_SECONDS)
                            end
                        end)
                    end
                end
            end
        end
    end
end

local function markLanding()
    local current=tostring(game.JobId or "")
    if current=="" then return end

    local previous=tostring(S.landedJobId or S.currentJobId or "")
    if previous~="" and previous~=current then
        S.hops=S.hops+1
        S.visited[current]=true
        S.landedJobs[current]=true
        S.currentJobId=current
        S.silentTeleportFailures=0
        logLine("SERVER_CHANGED old="..previous.." new="..current)

        local attempted=tostring(S.lastHopTarget or "")
        if attempted~="" and attempted~="random" and current~=attempted then
            pcall(function() Runtime.markBadJobCache(attempted,"landed_unexpected_job") end)
        end

        task.spawn(function()
            pcall(function()
                requestJson("POST",NODE_BASE.."/v1/release",{
                    account_id=tostring(LP.UserId),
                    label=tostring(LP.Name),
                    job_id=previous,
                    current_job_id=current,
                },nodeHeaders())
            end)
        end)
        if tonumber(S.pendingStartedMs) then
            local elapsed=math.max(0.05,(nowMs()-tonumber(S.pendingStartedMs))/1000)
            -- GPU workers can legitimately land in the 30-40s range under
        -- VRAM/commit pressure. Learn those successful landings instead of
        -- biasing the adaptive watchdog toward only the fastest teleports.
        if elapsed<=40 then
                local samples=(tonumber(S.teleportSuccessSamples) or 0)+1
                local prior=tonumber(S.teleportAvgSec)
                if prior and prior>0 then
                    S.teleportAvgSec=(prior*0.75)+(elapsed*0.25)
                else
                    S.teleportAvgSec=elapsed
                end
                S.teleportSuccessSamples=math.min(samples,1000)
                adaptiveTeleportWatchdog()
                logLine(string.format("LANDED %sâ€¦ Â· teleport %.2fs Â· watchdog %.2fs",current:sub(1,12),elapsed,tonumber(S.adaptiveWatchdogSec) or CFG.TELEPORT_WATCHDOG_SEC))
            end
        else
            logLine("LANDED "..current:sub(1,12).."ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦")
        end
    else
        S.currentJobId=current
    end

    pcall(function() Runtime.markJobCache(current,LP.Name) end)
    S.lastLandingPendingJob=tostring(S.pendingJobId or "")
    S.lastLandingConfirmedAt=nowUnix()
    S.lastLandingConfirmedMs=nowMs()
    S.lastLandingConfirmedJob=current
    S.landedJobId=current
    S.pendingJobId=nil
    S.pendingStartedMs=nil
    S.reexecArmed=false
    Runtime.teleporting=false
    Runtime.preclaiming=false
    clearPreclaim()
    S.serverSeenTargetUids={}
    S.totalEggsSent=0
    S.lastEggsSent=0
    S.lastRawAccepted=0
    S.lastRawIgnored=0
    Runtime.sendAllLogged={}
    Runtime.unresolvedRetryJob=nil
    Runtime.unresolvedRetryDoneJob=nil
    Runtime.lastCountedSnapshotHash=nil
    S.teleportRetryCount=0
    S.lastTeleportFailure=nil

    -- New server: rebaseline cycle snapshot. Never create a fake edge.
    S.cycleFingerprint=readCycleFingerprint()
    S.cycleBaselineReadyAt=time()+CFG.STARTUP_CYCLE_BASELINE

    if S.mode=="hunting" then
        setState("HUNTING","Aterrizo ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· escaneando")
    else
        setState("READY","Esperando ciclo")
    end

    -- Stagger post-landing work across accounts.
    task.wait(0.3 + math.random() * 1.2)

    saveState()
    writeStatus()
end

    function Runtime.deferRejectedCycleHop(context,target,why)
        logLine("CYCLE HOP DEFERRED · "..tostring(why))
        if context.token~=Runtime.huntToken or context.jobId~=tostring(game.JobId) then return end
        if tostring(S.pendingJobId or "")~=target then return end
        Runtime.teleporting=false
        S.pendingJobId=nil
        S.pendingStartedMs=nil
        Runtime.huntToken=nil
        Runtime.huntLoopRunning=false
        S.mode="parked"
        S.huntEnd=nil
        Runtime.cycleScanAck=nil
        setState("RESET_WAIT","Hop cancelado · esperando escaneo del ciclo vigente")
    end

function Runtime.randomTeleportFallback(reason)
    local hopContext=Runtime.captureCycleHopContext()
    if not Runtime.canCommitHop(hopContext) then return false end
    local oldJob=tostring(game.JobId or "")
    pcall(Runtime.clearJobCache)
    S.serverQueue={}
    S.cachedFallbackServer=nil
    S.teleportRetryCount=0
    S.silentTeleportFailures=0
    -- A fallback must still land on a DIFFERENT public JobId. Reset the
    -- visited set except for the current server, refill, and claim an explicit
    -- alternate instead of using Teleport(placeId), which may rejoin this JobId.
    S.visited={[oldJob]=true}
    local refillOk,refillErr=refillServers(true)
    if not refillOk then
        S.lastError="random_no_alternate:"..tostring(refillErr)
        setState("RECOVERING","Sin servidor alterno · esperando backoff")
        logLine("RANDOM FALLBACK · no alternate · "..tostring(refillErr))
        writeStatus()
        refreshStatus()
        return false
    end
    local alternate,chooseErr=chooseServerForAccount("random_fallback")
    local alternateId=alternate and tostring(alternate.id or "") or ""
    if alternateId=="" or alternateId==oldJob then
        S.lastError="random_invalid_alternate:"..tostring(chooseErr or alternateId)
        setState("RECOVERING","Servidor alterno inválido · esperando backoff")
        if alternateId==oldJob then pcall(function() Runtime.markBadJobCache(alternateId,"fallback_equals_current_job") end) end
        logLine("RANDOM FALLBACK · rejected current/empty JobId · "..tostring(alternateId))
        writeStatus()
        refreshStatus()
        return false
    end

    if not armReexec() then
        S.lastError="random_reexec_unavailable"
        setState("RECOVERING","Reexec no disponible · esperando backoff")
        writeStatus()
        refreshStatus()
        return false
    end

    if not Runtime.canCommitHop(hopContext) then return false end
    S.lastHopAttempt=nowUnix()
    S.lastHopTarget=alternateId
    S.pendingJobId=alternateId
    S.pendingStartedMs=nowMs()
    S.currentJobId=oldJob
    Runtime.teleporting=true
    setState("JOINING","Servidor alterno · "..alternateId:sub(1,12))
    saveState()
    writeStatus()
    refreshStatus()
    logLine("RANDOM TELEPORT · target="..alternateId.." · reason="..tostring(reason or "retry_limit"))

    task.spawn(function()
        local allowed,why=Runtime.canCommitHop(hopContext)
        if not allowed then
            Runtime.deferRejectedCycleHop(hopContext,alternateId,why)
            return
        end
        local ok,err=pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId,alternateId,LP)
        end)
        if ok then return end
        if tostring(game.JobId)~=oldJob then return end
        Runtime.teleporting=false
        S.reexecArmed=false
        S.pendingJobId=nil
        S.pendingStartedMs=nil
        S.lastTeleportFailure="random_call_error:"..tostring(err)
        S.lastError=S.lastTeleportFailure
        setState("RECOVERING","Teleport alterno rechazado")
        writeStatus()
        refreshStatus()
    end)

    local watchdogSec=adaptiveTeleportWatchdog()
    task.delay(watchdogSec,function()
        if not Runtime.alive or tostring(game.JobId)~=oldJob then return end
        if not Runtime.teleporting or tostring(S.pendingJobId or "")~=alternateId then return end
        Runtime.teleporting=false
        S.reexecArmed=false
        S.pendingJobId=nil
        S.pendingStartedMs=nil
        pcall(function() Runtime.markBadJobCache(alternateId,"fallback_watchdog_same_job") end)
        S.silentTeleportFailures=(tonumber(S.silentTeleportFailures) or 0)+1
        S.lastTeleportFailure="random_watchdog_same_job"
        S.lastError="random_teleport_watchdog:"..alternateId
        setState("RECOVERING","Teleport alterno no cambio de servidor")
        writeStatus()
        refreshStatus()
        logLine("RANDOM WATCHDOG · mismo JobId · target="..alternateId)
    end)
    return true
end

-- JG1: collision recovery is independent of normal hunt/scan windows.
function Runtime.jg1ConflictCurrent()
    local age=nowMs()/1000-(tonumber(S.coordConflictAt) or 0)
    return Runtime.alive and S.coordConflict==true and S.coordCollisionAllowed==true
        and S.coordSource=="cloud_node_coord"
        and tostring(S.coordConflictJob or "")==tostring(game.JobId)
        and age>=0 and age<=10
end

function Runtime.relocateConflict()
    if Runtime.collisionBusy or Runtime.teleporting or not Runtime.jg1ConflictCurrent() then return false end
    Runtime.collisionBusy=true
    local origin=tostring(game.JobId)
    local destination=nil
    local function validReservation()
        -- The central coordinator verified the conflict before this unique claim.
        -- Once granted, validate the live lease, not the expired 10s trigger.
        return Runtime.alive and tostring(game.JobId)==origin
            and destination and tostring(destination.id or "")~="" and tostring(destination.id)~=origin
            and (tonumber(destination.lease_expires_at) or 0)>nowUnix()+5
    end
    local function releaseDestination()
        if destination and destination.id then
            pcall(function()
                local payload=nodeIdentity();payload.job_id=tostring(destination.id)
                payload.release_kind="reservation_cancelled"
                requestJson("POST",NODE_BASE.."/v1/release",payload,nodeHeaders())
            end)
        end
    end
    local ok,result=pcall(function()
        local err
        destination,err=nodeClaimServer({},true)
        if not destination then
            S.lastError="coord_relocation_wait:"..tostring(err)
            return false
        end
        if not validReservation() then releaseDestination();return false end
        if not armReexec() then releaseDestination();return false end
        if not validReservation() then releaseDestination();return false end
        local target=tostring(destination.id)
        Runtime.teleporting=true
        S.pendingJobId=target;S.pendingStartedMs=nowMs()
        S.currentJobId=origin;S.landedJobId=origin
        S.lastHopAttempt=nowUnix();S.lastHopTarget=target
        S.lastHopReason="coord_collision_jg1"
        setState("JOINING","Separando cuenta duplicada")
        saveState();writeStatus();refreshStatus()
        task.delay(45,function()
            if not Runtime.alive or tostring(game.JobId)~=origin then return end
            if not Runtime.teleporting or tostring(S.pendingJobId or "")~=target then return end
            Runtime.teleporting=false;Runtime.collisionBusy=false
            S.pendingJobId=nil;S.pendingStartedMs=nil;S.reexecArmed=false
            S.lastError="coord_relocation_timeout";S.lastTeleportFailure="coord_relocation_timeout"
            setState("RECOVERING","Reintentando separacion")
            releaseDestination();writeStatus();refreshStatus()
        end)
        logLine("JG1 COLLISION RELOCATE "..origin.." -> "..target)
        local sent,sendErr=pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId,target,LP)
        end)
        if not sent and tostring(game.JobId)==origin then
            Runtime.teleporting=false;S.pendingJobId=nil;S.pendingStartedMs=nil
            S.reexecArmed=false;S.lastError="coord_relocation_call:"..tostring(sendErr)
            S.lastTeleportFailure=S.lastError
            setState("RECOVERING","Teleport rechazado")
            releaseDestination();writeStatus();refreshStatus()
            return false
        end
        return sent
    end)
    Runtime.collisionBusy=false
    if not ok then
        if tostring(game.JobId)==origin and not Runtime.teleporting then releaseDestination() end
        S.lastError="coord_relocation_error:"..tostring(result)
        pcall(writeStatus)
        return false
    end
    return result==true
end

Runtime.doRejoin=function(reason)
    local reasonText=tostring(reason or "")
    local hopContext=Runtime.captureCycleHopContext()
    hopContext.allowCoordConflictEscape=(reasonText:find("coord_conflict",1,true)~=nil)
    if not Runtime.canCommitHop(hopContext) then return false end
    local parkedDedupe=(S.mode=="parked" and reasonText:find("coord_conflict",1,true)~=nil)

    -- Never let parked duplicate-resolution punch through the reset/final-hold
    -- barrier. This path used to be the only doRejoin exception that could
    -- start a teleport after huntEnd, including 4-10s before the next scan.
    if parkedDedupe then
        local n=nowUnix()
        local fleetStart=tonumber(S.fleetScanStart)
        local fleetEnd=tonumber(S.fleetCycleEnd)
        local protected=(S.state=="RESET_WAIT" or S.state=="FINAL_HOLD")
            or (fleetStart and n<fleetStart)
            or (fleetEnd and n>=fleetEnd)
        if protected then
            Runtime.lastParkedDedupeDeferredAt=n
            logLine("COORD DEDUPE DEFERRED · protected reset/final window")
            return false
        end
    end

    if Runtime.teleporting then
        logLine("HOP WAIT ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· teleport ya pendiente ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ "..tostring(S.pendingJobId or "?"):sub(1,12))
        return true
    end
    if not parkedDedupe and (S.mode~="hunting" or not S.huntEnd or nowUnix()>=S.huntEnd) then return false end

    S.cachedFallbackServer=nil
    if #S.serverQueue==0 then
        setState("DISCOVERING","Buscando servidores")
        refreshStatus()
        local ok,err=refillServers(false)
        if not ok then
            local errText=tostring(err or "pool_empty")
            local retryDelay=math.max(1,math.min(15,math.ceil(math.max(0,(S.serverFetchNotBefore or (nowUnix()+4))-nowUnix()))))
            S.cachedFallbackServer=nil
            S.claimSource=errText:find("429",1,true) and "pool_429_wait" or "pool_empty_wait"
            S.lastError="server_list:"..errText
            logLine("SERVER POOL WAIT · "..errText.." · retry "..tostring(retryDelay).."s")
            writeStatus()
            refreshStatus()
            task.wait(math.min(3,retryDelay))
            return false
        else
            logLine("QUEUE "..tostring(#S.serverQueue).." JobIds")
        end
    end

    local chosen,chooseErr=nil,nil
    if S.cachedFallbackServer then
        chosen=S.cachedFallbackServer
        S.cachedFallbackServer=nil
        S.coordinatorActive=true
    else
        chosen,chooseErr=chooseServerForAccount(reason)
    end
    if not chosen then
        S.lastError="choose_server:"..tostring(chooseErr)
        if chooseErr and tostring(chooseErr):find("coordinator",1,true) then
            setState("COORD_BLOCKED",tostring(chooseErr))
            logLine("COORDINATOR BLOCK ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(chooseErr))
        else
            setState("DISCOVERING","Sin JobId elegible")
            logLine("CHOOSE SERVER ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(chooseErr))
        end
        writeStatus()
        refreshStatus()
        return false
    end

    local chosenId=tostring(chosen.id)
    local currentJob=tostring(game.JobId)
    if chosenId=="" then
        S.lastError="invalid_target_job:empty"
        return false
    end
    if chosenId==currentJob then
        S.lastError="invalid_target_job:current"
        S.lastHopTarget=chosenId
        pcall(function() Runtime.markBadJobCache(chosenId,"target_equals_current_job") end)
        logLine("HOP SAME JOB · target actual · random fallback")
        return Runtime.randomTeleportFallback("target_equals_current_job")
    end

    if not armReexec() then
        table.insert(S.serverQueue,1,chosen)
        refreshStatus()
        return false
    end

    if not Runtime.canCommitHop(hopContext) then return false end
    S.pendingJobId=chosenId
    S.pendingStartedMs=nowMs()
    S.landedJobId=tostring(game.JobId)
    S.currentJobId=tostring(game.JobId)
    S.lastHopAttempt=nowUnix()
    S.lastHopTarget=chosenId
    S.teleportRetryCount=tonumber(S.teleportRetryCount) or 0
    Runtime.teleporting=true
    setState("JOINING","ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ "..chosenId:sub(1,12))
    saveState()
    writeStatus()
    refreshStatus()

    logLine(string.format(
        "JOIN TRY ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ %sÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ (%d/%d) via %s",
        chosenId:sub(1,12),chosen.playing,chosen.maxPlayers,
        tostring(S.queueFunction or "?")
    ))

    local oldJob=tostring(game.JobId)

    -- Roblox/Wave can occasionally leave TeleportToPlaceInstance yielding
    -- instead of returning or throwing. Run the call off-thread so the
    -- watchdog below is always armed and can recover the hunt.
    task.spawn(function()
        local allowed,why=Runtime.canCommitHop(hopContext)
        if not allowed then
            Runtime.deferRejectedCycleHop(hopContext,chosenId,why)
            return
        end
        local ok,err=pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId,chosenId,LP)
        end)
        if ok then return end
        if not Runtime.alive or (S.mode~="hunting" and not parkedDedupe) then return end
        if tostring(game.JobId)~=oldJob then return end
        if tostring(S.pendingJobId or "")~=chosenId then return end

        Runtime.teleporting=false
        S.pendingJobId=nil
        S.pendingStartedMs=nil
        S.reexecArmed=false
        S.lastTeleportFailure="call_error:"..tostring(err)
        pcall(function() Runtime.markBadJobCache(chosenId,"call_error") end)
        S.teleportRetryCount=(tonumber(S.teleportRetryCount) or 0)+1
        setState("RECOVERING","Teleport rechazado")
        writeStatus()
        refreshStatus()
        logLine("JOIN CALL ERROR · "..tostring(err))
        if S.teleportRetryCount>=CFG.TELEPORT_MAX_CONSECUTIVE_RETRIES then
            Runtime.randomTeleportFallback("call_error_limit")
            return
        end
    end)

    S.lastHopAccepted=chosenId
    local watchdogSec=adaptiveTeleportWatchdog()
    logLine("JOIN ACCEPTED Â· watchdog "..tostring(watchdogSec).."s")

    -- Critical fix: TeleportToPlaceInstance can return without throwing even when
    -- the client never leaves. Never stop the hunt solely because pcall returned true.
    local token=Runtime.huntToken
    task.delay(watchdogSec,function()
        if not Runtime.alive then return end
        if Runtime.huntToken~=token or (S.mode~="hunting" and not parkedDedupe) then return end
        if tostring(game.JobId)~=oldJob then return end
        if not Runtime.teleporting or tostring(S.pendingJobId or "")~=chosenId then return end

        Runtime.teleporting=false
        S.reexecArmed=false
        S.pendingJobId=nil
        S.pendingStartedMs=nil
        pcall(function() Runtime.markBadJobCache(chosenId,"watchdog_same_job") end)
        S.teleportRetryCount=(tonumber(S.teleportRetryCount) or 0)+1
        S.silentTeleportFailures=(tonumber(S.silentTeleportFailures) or 0)+1
        S.lastTeleportFailure="watchdog_timeout_same_job"
        S.lastError="teleport_watchdog:"..chosenId
        setState("RECOVERING","Teleport no cambio de servidor")
        writeStatus()
        refreshStatus()
        logLine("WATCHDOG · mismo JobId · target="..chosenId.." · retry #"..tostring(S.teleportRetryCount))

        if S.teleportRetryCount>=CFG.TELEPORT_MAX_CONSECUTIVE_RETRIES
            or S.silentTeleportFailures>=3
        then
            logLine("HOP RECOVERY · 3 fallos -> cache clear + random")
            Runtime.randomTeleportFallback("same_job_3x")
            return
        end

        -- Force a fresh list if the current queue was exhausted/stale.
        if #S.serverQueue==0 then
            pcall(refillServers,true)
        end

        task.defer(function()
            if Runtime.alive
                and Runtime.huntToken==token
                and S.mode=="hunting"
                and S.huntEnd
                and nowUnix()<S.huntEnd
            then
                local retryOk,retryResult=pcall(Runtime.doRejoin,"watchdog_retry")
                if not retryOk then
                    S.lastError="watchdog_retry:"..tostring(retryResult)
                    setState("ERROR","Retry de teleport fallÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³")
                    writeStatus()
                    refreshStatus()
                elseif not retryResult then
                    Runtime.huntLoopRunning=false
                    startHuntLoop(token)
                end
            end
        end)
    end)

    -- Second-stage landing watchdog. Roblox can change game.JobId while the
    -- client is still frozen on "Joining server". A JobId change alone is not
    -- considered success; markLanding() must clear pendingJobId and confirm
    -- the actual landed job.
    local landingWatchdogSec=math.max(
        tonumber(CFG.LANDING_CONFIRM_TIMEOUT_SEC) or 30,
        (tonumber(watchdogSec) or 8)+10
    )
    task.delay(landingWatchdogSec,function()
        if not Runtime.alive then return end
        if Runtime.huntToken~=token then return end
        if tostring(S.pendingJobId or "")~=chosenId then return end

        local currentNow=tostring(game.JobId or "")
        if currentNow=="" or currentNow==oldJob then
            -- Same-job timeout is handled by the first watchdog.
            return
        end
        if tostring(S.lastLandingConfirmedJob or "")==currentNow then
            return
        end

        S.silentTeleportFailures=(tonumber(S.silentTeleportFailures) or 0)+1
        S.teleportRetryCount=(tonumber(S.teleportRetryCount) or 0)+1
        S.lastTeleportFailure="landing_unconfirmed_timeout:"..currentNow
        S.lastError=S.lastTeleportFailure
        S.lastLandingPendingJob=chosenId
        setState("JOINING","Landing no confirmado · reinicio requerido")
        pcall(function() Runtime.markBadJobCache(chosenId,"landing_unconfirmed_timeout") end)
        saveState()
        writeStatus()
        refreshStatus()
        logLine(
            "LANDING WATCHDOG · JobId cambio pero landing no confirmado · current="
            ..currentNow:sub(1,12).." · target="..chosenId:sub(1,12)
        )

        -- Never terminate Roblox for a slow landing. Keep the client alive so
        -- late streaming/replication can still complete and AutoExecute can recover.
        setState("JOINING","Landing lento · esperando sin cerrar Roblox")
        saveState()
        writeStatus()
        refreshStatus()
        logLine("LANDING WATCHDOG · hold-open · Roblox permanece vivo")
    end)

    return true
end

Runtime.stopHunt=function(reason)
    Runtime.huntToken=nil
    Runtime.huntLoopRunning=false
    Runtime.teleporting=false
    S.mode="parked"
    S.huntEnd=nil
    S.testDuration=nil
    S.pendingJobId=nil
    S.serverQueue={}
    S.reexecArmed=false
    S.cycleFingerprint=readCycleFingerprint()
    S.cycleBaselineReadyAt=time()+1
    if CFG.CONTINUOUS_SCAN and tostring(reason or "")~="manual" then
        setState("READY","Ventana prioritaria terminada · rotación continua")
        saveState()
        writeStatus()
        refreshStatus()
        logLine("HUNT END · CONTINUOUS RESTART · "..tostring(reason or ""))
        task.defer(function()
            if Runtime.alive and type(beginHunt)=="function" then
                beginHunt("background continuous",true,CFG.SCANNER_CONTINUOUS_HUNT_SECONDS)
            end
        end)
    else
        setState("PARKED",reason or "Detenido manualmente")
        saveState()
        writeStatus()
        refreshStatus()
        logLine("HUNT END · PARKED · "..tostring(reason or ""))
    end
end

beginHunt=function(reason,force,durationSec)
    local now=nowUnix()
    local duration=math.max(30,tonumber(durationSec) or CFG.HUNT_SECONDS)
    if Shared.VYRO_SCANNER_MODE==true then
        local generation,scanStart,endAt,epoch=Runtime.cycleWindow(now)
        S.fleetCycleGeneration=generation
        S.fleetCycleEpoch=epoch
        S.fleetScanStart=scanStart
        S.fleetCycleEnd=endAt
        if now<scanStart or not Runtime.cycleDayReady() then
            Runtime.huntToken=nil
            Runtime.huntLoopRunning=false
            S.mode="parked"
            S.huntEnd=nil
            setState("RESET_WAIT","Esperando reinicio real del servidor")
            return false
        end
        duration=endAt-now
    end
    local fleetStart=tonumber(S.fleetScanStart)
    local fleetEnd=tonumber(S.fleetCycleEnd)
    if Shared.VYRO_SCANNER_MODE==true and fleetStart and fleetEnd then
        if now<fleetStart then
            Runtime.huntToken=nil
            Runtime.huntLoopRunning=false
            Runtime.teleporting=false
            S.mode="parked"
            S.huntEnd=nil
            setState("RESET_WAIT","Bloqueo autoritativo · esperando scan_start")
            writeStatus()
            refreshStatus()
            return false
        elseif now>=fleetEnd then
            Runtime.huntToken=nil
            Runtime.huntLoopRunning=false
            Runtime.teleporting=false
            S.mode="parked"
            S.huntEnd=nil
            setState("PARKED","Ventana global cerrada · esperando próximo reset")
            writeStatus()
            refreshStatus()
            return false
        end
    end
    if not force and S.mode=="hunting" and S.huntEnd and now<S.huntEnd then
        refreshStatus()
        return true
    end

    Runtime.huntToken={}
    Runtime.huntLoopRunning=false
    Runtime.teleporting=false
    Runtime.cycleScanResult=nil
    Runtime.cycleScanAck=nil

    S.mode="hunting"
    S.serverSeenTargetUids={}
    S.huntEnd=now+duration
    S.testDuration=duration
    S.huntStartedAt=now
    S.huntStartedClock=os.clock()
    S.huntHopsStart=tonumber(S.hops) or 0
    S.visited={[tostring(game.JobId)]=true}
    S.landedJobs={[tostring(game.JobId)]=true}
    S.serverQueue={}
    S.pendingJobId=nil
    S.landedJobId=tostring(game.JobId)
    S.lastError=nil
    S.teleportRetryCount=0
    S.lastHopAttempt=nil
    S.lastHopAccepted=nil
    S.huntEggsSentStart=tonumber(S.totalEggsSent) or 0
    S.first10WorldEggsMax=0
    S.first10RawEggsMax=0
    S.first10Scans=0
    S.first10EndsAt=now+10

    setState("HUNTING",reason or "hunt")
    saveState()
    writeStatus()
    refreshStatus()

    logLine("HUNT START "..formatSeconds(duration).." ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(reason))

    task.defer(function()
        local ok,err=pcall(function()
            startHuntLoop(Runtime.huntToken)
        end)
        if not ok then
            S.lastError="startHuntLoop:"..tostring(err)
            setState("ERROR","Hunt no pudo iniciar")
            logLine("HUNT START ERROR ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(err))
            writeStatus()
            refreshStatus()
        end
    end)

    return true
end

startHuntLoop=function(token)
    if Runtime.huntLoopRunning then return end
    Runtime.huntLoopRunning=true

    task.spawn(function()
        while Runtime.alive
            and Runtime.huntToken==token
            and S.mode=="hunting"
            and S.huntEnd
            and nowUnix()<S.huntEnd
        do
            if Shared.VYRO_SCANNER_MODE==true then
                local roundContext=Runtime.captureCycleHopContext()
                if not Runtime.cycleContextValid(roundContext) then
                    task.wait(0.20)
                    continue
                end
            end
            local roundStart=time()
            setState("SCANNING","Esperando assets estables")
            writeStatus()

            -- Hide server discovery under the same readiness window.
            if #S.serverQueue<=CFG.SERVER_PREFETCH_MIN and nowUnix()>=(S.serverFetchNotBefore or 0) then
                task.spawn(function()
                    local ok,err=pcall(refillServers,false)
                    if not ok then S.lastError="prefetch_early:"..tostring(err) end
                end)
            end

            -- Hide reexec preparation inside the visual readiness window.
            if not S.reexecArmed and not Runtime.reexecArming then
                task.spawn(function()
                    local ok,err=pcall(armReexec,true)
                    if not ok then
                        Runtime.reexecArming=false
                        S.reexecError="prearm:"..tostring(err)
                    end
                end)
            end

            -- EARLY FAST: make one fail-closed premium pass immediately.
            -- If a target already resolves cleanly, publish it before the
            -- visual-stability window. The normal stable pass below remains
            -- authoritative and reconciles any later detail changes.
            local earlyOk,earlyErr=pcall(scanNow,"premium")
            if earlyOk and tostring(S.lastJoinEventJob or "")~=tostring(game.JobId) then
                S.lastJoinEventJob=tostring(game.JobId)
                pushPatchEvent("server_joined",{
                    totalEggs=#(S.rawEggs or {}),pendingEggs=#(S.pendingFingerprintCandidates or {}),
                    timeLeft=S.cycleEtaSeconds,
                })
            end
            if earlyOk and (#(S.rawEggs or {})>0 or #(S.chatProvisionalTargets or {})>0) then
                S.lastStableWaitMs=0
                S.lastReadyWaitMs=0
                S.lastVisualWaitMs=0
                writeSnapshot()
                logLine("EARLY SEND-ALL · raw="..tostring(#(S.rawEggs or {})).." chat="..tostring(#(S.chatProvisionalTargets or {})).." targets="..tostring(#S.qualifiedTargets))
            elseif not earlyOk then
                S.lastError="early_scan:"..tostring(earlyErr)
            end

            local scanOk,scanErr=pcall(waitForStableAssets,"premium")
            if Runtime.huntToken~=token or S.mode~="hunting" or not S.huntEnd then break end
            if not scanOk then
                S.lastError="hunt_scan:"..tostring(scanErr)
                setState("ERROR","Scan hunt fallo")
                logLine("HUNT SCAN ERROR ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(scanErr))
                writeStatus()
                refreshStatus()
                Runtime.huntLoopRunning=false
                return
            end

            -- POST-RESET NON-EMPTY GATE:
            -- A valid server in the active egg window should expose at least one
            -- fresh world egg. Stable slot shells alone are not enough: during
            -- reset/load races they can settle a moment before the eggs respawn.
            -- Never hop away from a zero-world snapshot; retry the same JobId.
            local nonEmptyAttempts=0
            local nonEmptyDeadline=time()+2.5
            while Runtime.alive
                and Runtime.huntToken==token
                and S.mode=="hunting"
                and nowUnix()<S.huntEnd
                and #(S.eggs or {})==0
                and time()<nonEmptyDeadline
            do
                nonEmptyAttempts=nonEmptyAttempts+1
                setState("SCANNING","Esperando huevos frescos post-reset")
                task.wait(math.min(0.18+(nonEmptyAttempts*0.08),0.50))
                local retryOk,retryErr=pcall(scanNow,"premium",100+nonEmptyAttempts)
                if not retryOk then
                    S.lastError="nonempty_retry:"..tostring(retryErr)
                    break
                end
            end
            S.nonEmptyRetryAttempts=nonEmptyAttempts
            S.nonEmptyConfirmed=(#(S.eggs or {})>0)
            if not S.nonEmptyConfirmed then
                S.lastError="post_reset_zero_world_failopen"
                setState("SCANNING","0 huevos resueltos · hop permitido")
                writeSnapshot()
                writeStatus()
                refreshEggUI()
                refreshStatus()
                logLine("NONEMPTY GATE · 0 world after retries · fail-open to next JobId")
                task.wait(0.15)
            end

            if Runtime.huntToken~=token or S.mode~="hunting" or not S.huntEnd then break end
            local snapshotOk,snapshotErr=writeSnapshot(true)
            if Runtime.huntToken~=token or S.mode~="hunting" or not S.huntEnd then break end
            if not snapshotOk then
                S.lastError="snapshot_ack:"..tostring(snapshotErr or "node_no_ack")
                setState("SCANNING","Envío pendiente · esperando ACK local")
                writeStatus()
                refreshEggUI()
                refreshStatus()
                logLine("SNAPSHOT ACK HOLD · "..tostring(snapshotErr or "node_no_ack").." · no hop")
                task.wait(0.25)
                continue
            end
            local first10Until=tonumber(S.first10EndsAt) or ((tonumber(S.huntStartedAt) or nowUnix())+10)
            if nowUnix()<=first10Until then
                S.first10Scans=(tonumber(S.first10Scans) or 0)+1
                S.first10WorldEggsMax=math.max(tonumber(S.first10WorldEggsMax) or 0,#(S.eggs or {}))
                S.first10RawEggsMax=math.max(tonumber(S.first10RawEggsMax) or 0,#(S.rawEggs or {}))
            end
            refreshEggUI()
            refreshStatus()

            -- Reserve the next unique JobId while we are still watching the
            -- current server. The 25s coordinator lease covers the short
            -- watch + teleport start and removes claim latency from the hop
            -- critical path.
            beginServerPreclaim("post_scan")

            -- FAST STATE: only valuable servers get a short state watch.
            -- This is cheap: no full rescan, only target UID / nest / carrier state.
            if #S.qualifiedTargets>0 or #(S.carriedTargets or {})>0 then
                local watchUntil=time()+CFG.TARGET_WATCH_SEC
                while Runtime.alive
                    and Runtime.huntToken==token
                    and S.mode=="hunting"
                    and time()<watchUntil
                    and nowUnix()<S.huntEnd
                do
                    task.wait(CFG.FAST_STATE_POLL)
                    if refreshTrackedTargetStates() then
                        writeSnapshot()
                        refreshEggUI()
                        refreshStatus()
                    end
                end
            end

            -- Prefetch public-server candidates while we are still in the
            -- current scan round. The cloud coordinator remains authoritative
            -- and leases only the JobId actually selected for the next hop.
            if #S.serverQueue<=CFG.SERVER_PREFETCH_MIN and nowUnix()>=(S.serverFetchNotBefore or 0) then
                task.spawn(function()
                    local ok,err=pcall(refillServers,false)
                    if not ok then S.lastError="prefetch:"..tostring(err) end
                end)
            end

            local biggest=S.qualifiedTargets[1]
            if #S.qualifiedTargets==0 then
                logLine(string.format("SKIP ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %d world / %d premium / 0 good ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %dms",#S.eggs,#S.targets,tonumber(S.lastStableWaitMs) or -1))
            else
                logLine(string.format("HIT ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %d GOOD ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· TOP Q%.1f %.2fx %s ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %s",#S.qualifiedTargets,tonumber(biggest.qualityScore or 0),tonumber(biggest.scale or 0),tostring(biggest.pet),tostring(biggest.targetBiome)))
            end
            logLine(string.format(
                "SCAN %d world ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %d premium ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %d good ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %dms stable=%dms%s",
                #S.eggs,#S.targets,#S.qualifiedTargets,
                tonumber(S.lastScanMs) or -1,
                tonumber(S.lastStableWaitMs) or -1,
                biggest and string.format(" ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· TOP %.2fx %s",biggest.scale or 0,biggest.pet) or ""
            ))

            if Runtime.huntToken~=token or nowUnix()>=S.huntEnd then break end

            -- Use the existing dwell budget as a fast state watcher. If a
            -- whitelisted egg is lifted or disappears, publish the transition
            -- immediately instead of sleeping and waiting for a later refresh.
            local watchUntil=roundStart+CFG.MIN_SERVER_DWELL
            while time()<watchUntil
                and Runtime.huntToken==token
                and nowUnix()<S.huntEnd
            do
                task.wait(math.min(0.05,math.max(0,watchUntil-time())))
                if (#(S.targets or {})>0 or #(S.carriedTargets or {})>0)
                    and refreshTrackedTargetStates()
                then
                    writeSnapshot()
                    refreshEggUI()
                    refreshStatus()
                end
            end

            if Runtime.huntToken~=token or nowUnix()>=S.huntEnd then break end

            local finalSnapshotOk,finalSnapshotErr=writeSnapshot(true)
            if not finalSnapshotOk then
                S.lastError="final_snapshot_ack:"..tostring(finalSnapshotErr or "node_no_ack")
                setState("SCANNING","Último envío pendiente · sin hop")
                writeStatus()
                refreshStatus()
                logLine("FINAL SNAPSHOT ACK HOLD · "..tostring(finalSnapshotErr or "node_no_ack"))
                task.wait(0.25)
                continue
            end

            -- Final-hop guard: do not start a teleport that is unlikely to land
            -- and scan before the strict 240s window closes. Stay on the current
            -- server and keep tracking target state until the real window end.
            local remainingForHop=math.max(0,(tonumber(S.huntEnd) or nowUnix())-nowUnix())
            local avgTeleport=tonumber(S.teleportAvgSec) or 16.0
            local adaptiveWatchdog=tonumber(S.adaptiveWatchdogSec) or 32.0
            -- FINAL_HOLD only needs one normal landing plus a short scan margin.
            -- The adaptive watchdog includes failed-teleport recovery and was
            -- making healthy workers stop 30-45s early every cycle.
            local projectedHop=(avgTeleport*1.15)+6.0
            local finalHopBudget=math.max(14.0,math.min(32.0,projectedHop))
            S.finalHopBudgetSec=finalHopBudget
            if remainingForHop<=finalHopBudget then
                setState("FINAL_HOLD",string.format("Cierre de ventana · %.0fs · sin hop tardío",remainingForHop))
                writeStatus()
                refreshStatus()
                logLine(string.format("FINAL HOP GUARD · remain=%.1fs budget=%.1fs avgTeleport=%.1fs",remainingForHop,finalHopBudget,avgTeleport))
                while Runtime.alive
                    and Runtime.huntToken==token
                    and S.mode=="hunting"
                    and S.huntEnd
                    and nowUnix()<S.huntEnd
                do
                    task.wait(math.min(0.25,math.max(0.05,S.huntEnd-nowUnix())))
                    if (#(S.targets or {})>0 or #(S.carriedTargets or {})>0)
                        and refreshTrackedTargetStates()
                    then
                        writeSnapshot()
                        refreshEggUI()
                        refreshStatus()
                    end
                end
                break
            end

            setState("HOPPING","Buscando siguiente servidor")
            refreshStatus()

            -- Spread synchronized cycle-edge teleports across a sub-second window.
            -- This reduces GameFull/unknown races without materially lowering coverage.
            task.wait((tonumber(LP.UserId) % 7) * 0.08)
            local hopOk,hoppedOrErr=pcall(Runtime.doRejoin,"hunt")
            if not hopOk then
                S.lastError="hunt_hop:"..tostring(hoppedOrErr)
                setState("ERROR","Hop fallo")
                logLine("HUNT HOP ERROR ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(hoppedOrErr))
                writeStatus()
                refreshStatus()
                Runtime.huntLoopRunning=false
                return
            end

            local hopped=hoppedOrErr
            if hopped then
                Runtime.huntLoopRunning=false
                return
            end

            if S.state=="BLOCKED" then
                logLine("TEST BLOCKED ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(S.reexecError or S.lastError or "reexec unavailable"))
                refreshStatus()
                Runtime.huntLoopRunning=false
                return
            end

            task.wait(0.35)
        end

        Runtime.huntLoopRunning=false
        if Runtime.huntToken==token
            and S.mode=="hunting"
            and S.huntEnd
            and nowUnix()>=S.huntEnd
        then
            stopHunt("Ventana de 3 min terminada Â· esperando prÃ³ximo reset")
        end
    end)
end

function Runtime.restoreState()
    local saved=loadState()

    if type(saved)=="table" then
        S.visited=arrayToDict(saved.visited)
        S.landedJobId=tostring(saved.landedJobId or game.JobId)
        S.landedJobs=arrayToDict(saved.landedJobs)
        if next(S.landedJobs)==nil and S.landedJobId~="" then
            S.landedJobs[S.landedJobId]=true
        end
        S.hops=tonumber(saved.hops) or 0
        S.serverQueue=type(saved.serverQueue)=="table" and saved.serverQueue or {}
        S.serverFetchNotBefore=tonumber(saved.serverFetchNotBefore) or 0
        local restoredPending=saved.pendingJobId and tostring(saved.pendingJobId) or nil
        local actualJob=tostring(game.JobId or "")
        if restoredPending and restoredPending~="" and restoredPending==actualJob then
            -- Queue-on-teleport successfully landed on the expected target.
            -- Keep timing metadata until markLanding() confirms this landing.
            S.pendingJobId=restoredPending
            S.pendingStartedMs=tonumber(saved.pendingStartedMs)
        else
            -- A fresh Roblox/runtime must never inherit an unfinished teleport
            -- to a different JobId. Otherwise a killed JOINING client can keep
            -- retrying the same dead/stuck target after every relaunch.
            if restoredPending and restoredPending~="" then
                S.lastTeleportFailure="stale_pending_cleared:"..restoredPending
                S.lastError=S.lastTeleportFailure
                pcall(function() Runtime.markBadJobCache(restoredPending,"stale_pending_on_restore") end)
                logLine("RESTORE CLEAR PENDING · target="..restoredPending:sub(1,12).." · current="..actualJob:sub(1,12))
            end
            S.pendingJobId=nil
            S.pendingStartedMs=nil
        end
        S.teleportAvgSec=tonumber(saved.teleportAvgSec)
        S.teleportSuccessSamples=tonumber(saved.teleportSuccessSamples) or 0
        S.adaptiveWatchdogSec=tonumber(saved.adaptiveWatchdogSec) or CFG.TELEPORT_WATCHDOG_SEC
        S.lastCycleEdgeAt=tonumber(saved.lastCycleEdgeAt)
        S.previousCycleEdgeAt=tonumber(saved.previousCycleEdgeAt)
        S.observedCycleSeconds=tonumber(saved.observedCycleSeconds)
        S.cycleEdgeCount=tonumber(saved.cycleEdgeCount) or 0
        S.learnedWorldSlots=type(saved.learnedWorldSlots)=="table" and saved.learnedWorldSlots or {}
        S.testDuration=tonumber(saved.testDuration)
        S.teleportRetryCount=tonumber(saved.teleportRetryCount) or 0
        S.lastHopAttempt=tonumber(saved.lastHopAttempt)
        S.lastHopTarget=saved.lastHopTarget and tostring(saved.lastHopTarget) or nil
        S.lastHopAccepted=saved.lastHopAccepted and tostring(saved.lastHopAccepted) or nil
        S.currentJobId=tostring(saved.currentJobId or game.JobId)
        S.silentTeleportFailures=tonumber(saved.silentTeleportFailures) or 0
        if restoredPending and restoredPending~="" and restoredPending~=actualJob then
            S.silentTeleportFailures=S.silentTeleportFailures+1
        end

        local savedEnd=tonumber(saved.huntEnd)
        local savedStart=tonumber(saved.huntStartedAt) or nowUnix()
        local savedDuration=tonumber(saved.testDuration) or (savedEnd and math.max(0,savedEnd-savedStart)) or 0
        local legacyContinuous=(Shared.VYRO_SCANNER_MODE==true and savedDuration>600)
        if legacyContinuous then
            logLine("RESET GATE MIGRATION Â· discarded legacy continuous hunt")
            S.serverQueue={}
            S.pendingJobId=nil
            S.testDuration=nil
        end
        if saved.mode=="hunting" and savedEnd and savedEnd>nowUnix() and not legacyContinuous then
            S.mode="hunting"
            S.huntEnd=savedEnd
            S.huntStartedAt=tonumber(saved.huntStartedAt) or nowUnix()
            S.huntHopsStart=tonumber(saved.huntHopsStart) or 0
            if not S.testDuration then
                local inferred=math.max(0,savedEnd-S.huntStartedAt)
                S.testDuration=(inferred>600) and CFG.HUNT_LONG_SECONDS or CFG.HUNT_SECONDS
            end
            S.huntStartedClock=os.clock()
            Runtime.huntToken={}
            markLanding()
            logLine("HUNT RESTORED ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..huntRemaining())

            task.delay(0.05,function()
                if Runtime.alive and S.mode=="hunting" then
                    startHuntLoop(Runtime.huntToken)
                end
            end)
            return
        end
    end

    S.mode="parked"
    S.huntEnd=nil
    S.pendingJobId=nil
    S.serverQueue={}
    S.landedJobId=tostring(game.JobId)
    S.currentJobId=tostring(game.JobId)
    S.cycleFingerprint=readCycleFingerprint()
    S.cycleBaselineReadyAt=os.clock()+CFG.STARTUP_CYCLE_BASELINE
    setState("PARKED","Esperando prÃ³ximo reset dÃ­a/noche")
    saveState()
end

function Runtime.isFullFailure(result,message)
    local t=(tostring(result).." "..tostring(message)):lower()
    return t:find("full",1,true)~=nil
        or t:find("gamefull",1,true)~=nil
        or t:find("server is full",1,true)~=nil
end

function ui.destroyOldGui()
    pcall(function()
        local parent=nil
        if type(gethui)=="function" then parent=gethui() end
        parent=parent or LP:FindFirstChildOfClass("PlayerGui")
        local old=parent and parent:FindFirstChild("VyroPrimeCoreUI")
        if old then old:Destroy() end
    end)
end

function ui.new(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    o.Parent=parent
    return o
end

function ui.round(parent,r)
    ui.new("UICorner",{CornerRadius=UDim.new(0,r or 8)},parent)
end

function ui.stroke(parent)
    ui.new("UIStroke",{Color=Color3.fromRGB(53,67,88),Thickness=1,Transparency=0.15},parent)
end

function ui.button(parent,text)
    local b=ui.new("TextButton",{
        BackgroundColor3=Color3.fromRGB(27,34,45),
        BorderSizePixel=0,
        Text=text,
        TextColor3=Color3.fromRGB(235,242,255),
        TextSize=11,
        Font=Enum.Font.GothamBold,
        AutoButtonColor=true,
    },parent)
    ui.round(b,8);ui.stroke(b)
    return b
end

refreshEggUI=function()
    if not ui.eggsText then return end
    local source=S.uiView=="WORLD" and S.eggs or (S.uiView=="PREMIUM" and S.targets or S.qualifiedTargets)
    local lines={}

    lines[#lines+1]=string.format(
        "%s ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· raw:%d world:%d premium:%d GOOD:%d skip:%d excl:%d ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· scan %sms stable %sms",
        S.uiView,#(S.rawEggs or {}),#S.eggs,#S.targets,#S.qualifiedTargets,S.skippedQuality or 0,
        (S.excludedBase or 0)+(S.excludedUncertain or 0),
        tostring(S.lastScanMs or "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â"),tostring(S.lastStableWaitMs or "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â")
    )

    for i=1,math.min(#source,CFG.MAX_UI_EGGS) do
        local e=source[i]
        lines[#lines+1]=string.format(
            "%02d Q%5.1f %6s %-18s %-14s %-9s %s",
            i,tonumber(e.qualityScore or 0),e.scale and string.format("%.2fx",e.scale) or "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â",
            tostring(e.pet):sub(1,18),
            tostring(e.targetBiome or e.biomeName):sub(1,14),
            tostring(e.rarity or ""),
            #(e.muts or {})>0 and ("["..table.concat(e.muts,"+").."]") or ""
        )
    end
    if #source==0 then lines[#lines+1]="Sin huevos QUALIFIED en este server ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· SKIP." end
    ui.eggsText.Text=table.concat(lines,"\n")
    if ui.viewBtn then ui.viewBtn.Text=S.uiView=="QUALIFIED" and "VISTA GOOD" or (S.uiView=="PREMIUM" and "VISTA PREMIUM" or "VISTA WORLD") end
end

refreshStatus=function()
    if not ui.status and not ui.badge then return end
    readMemory()

    if ui.badge then
        local eta="SYNC"
        local etaSeconds=tonumber(S.cycleEtaSeconds)
        -- Until DAY/NIGHT calibration finishes loading, show the already-known
        -- authoritative fleet schedule instead of the misleading "LEARN".
        if not etaSeconds then
            local n=nowUnix()
            local scanAt=tonumber(S.fleetScanStart)
            local endAt=tonumber(S.fleetCycleEnd)
            if scanAt and n<scanAt then
                etaSeconds=math.max(0,scanAt-n)
            elseif endAt and n<endAt then
                etaSeconds=math.max(0,endAt-n)
            end
        end
        if etaSeconds then
            local sec=math.max(0,math.floor(etaSeconds))
            eta=string.format("%02d:%02d",math.floor(sec/60),sec%60)
        end
        ui.badge.Text=string.format(
            "VYRO SCANNER 4.2 | %s | %s | %d/%d NESTS | Q:%d | %s",
            S.nodeConnected and "ONLINE" or "NODE...",
            tostring(S.phase or "?"),
            tonumber(S.nestSlotsResolved) or 0,
            tonumber(S.nestSlotsTotal) or 0,
            #(S.qualifiedTargets or {}),
            eta
        )
    end
    if not ui.status then return end

    local big=S.qualifiedTargets[1] or S.targets[1]
    local bigText=big and string.format("%.2fx %s ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %s",big.scale or 0,big.pet,big.targetBiome) or "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â"

    ui.status.Text=string.format(
        "%s ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· %s  HUNT:%s\nJOB:%s  Q:%d  HOPS:%d  %.1f srv/min\nNESTS:%d/%d WORLD:%d PREMIUM:%d GOOD:%d BASE-IGN:%d TOP:%s\nSOURCE:NEST TRUTH ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· NODE:%s CLOUD:%s RAM:%s",
        S.state,S.mode:upper(),huntRemaining(),
        tostring(game.JobId):sub(1,12),
        #S.serverQueue,S.hops,serversPerMinute(),
        tonumber(S.nestSlotsResolved) or 0,tonumber(S.nestSlotsTotal) or 0,#S.eggs,#S.targets,#S.qualifiedTargets,tonumber(S.baseRenderedIgnored) or 0,bigText,
        S.nodeConnected and "ON" or (MULTI_ACCOUNT and "REQ" or "OFF"),
        S.lastCloudError and "ERR" or (S.lastCloudOkAt and "OK" or "IDLE"),
        S.memoryMb and string.format("%.0fMB",S.memoryMb) or "ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â"
    )

    if ui.testBtn then
        if S.mode=="hunting" and S.huntEnd and nowUnix()<S.huntEnd and S.testDuration==CFG.HUNT_SECONDS then
            ui.testBtn.Text="TEST "..huntRemaining()
            ui.testBtn.BackgroundColor3=Color3.fromRGB(31,112,82)
        else
            ui.testBtn.Text="TEST 3 MIN"
            ui.testBtn.BackgroundColor3=Color3.fromRGB(27,34,45)
        end
    end
    if ui.test20Btn then
        if S.mode=="hunting" and S.huntEnd and nowUnix()<S.huntEnd and S.testDuration==CFG.HUNT_LONG_SECONDS then
            ui.test20Btn.Text="20M "..huntRemaining()
            ui.test20Btn.BackgroundColor3=Color3.fromRGB(126,76,28)
        else
            ui.test20Btn.Text="TEST 20 MIN"
            ui.test20Btn.BackgroundColor3=Color3.fromRGB(27,34,45)
        end
    end
end

if type(refreshEggUI)~="function" or type(refreshStatus)~="function" then
    error("UI refresh forward binding failed")
end

function ui.buildUI()
    local new,round,stroke,button=ui.new,ui.round,ui.stroke,ui.button
    ui.destroyOldGui()

    local parent=nil
    pcall(function() if type(gethui)=="function" then parent=gethui() end end)
    if not parent then
        parent=LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui",10)
    end
    if not parent then
        Shared.__VYRO_CORE_UI_ERROR="PlayerGui/gethui unavailable after 10s"
        return false
    end

    local gui=new("ScreenGui",{
        Name="VyroPrimeCoreUI",
        ResetOnSpawn=false,
        IgnoreGuiInset=true,
        DisplayOrder=9999,
    },parent)

    local badge=new("TextButton",{
        Position=UDim2.fromOffset(18,18),
        Size=UDim2.fromOffset(340,38),
        BackgroundColor3=Color3.fromRGB(8,21,31),
        BorderSizePixel=0,
        Text="VYRO SCANNER 4.2 ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· STARTING...",
        TextColor3=Color3.fromRGB(73,229,171),
        TextSize=11,
        Font=Enum.Font.GothamBold,
        AutoButtonColor=false,
    },gui)
    round(badge,10);stroke(badge)

    local frame=new("Frame",{
        Position=UDim2.fromOffset(18,70),
        Size=UDim2.fromOffset(560,570),
        BackgroundColor3=Color3.fromRGB(9,13,20),
        BorderSizePixel=0,
        Visible=false,
    },gui)
    round(frame,12);stroke(frame)

    local title=new("TextLabel",{
        Position=UDim2.fromOffset(16,10),
        Size=UDim2.new(1,-32,0,24),
        BackgroundTransparency=1,
        Text="VYRO PRIME CORE ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(LP.Name).." ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· FAST SCANNER",
        TextColor3=Color3.fromRGB(91,185,255),
        TextSize=14,
        Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,
    },frame)

    local status=new("TextLabel",{
        Position=UDim2.fromOffset(16,40),
        Size=UDim2.new(1,-32,0,82),
        BackgroundColor3=Color3.fromRGB(17,23,33),
        BorderSizePixel=0,
        Text="",
        TextColor3=Color3.fromRGB(230,239,252),
        TextSize=11,
        Font=Enum.Font.Code,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,
        TextWrapped=true,
    },frame)
    round(status,9);stroke(status)
    new("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingTop=UDim.new(0,8)},status)

    local bar=new("Frame",{
        Position=UDim2.fromOffset(16,132),
        Size=UDim2.new(1,-32,0,68),
        BackgroundTransparency=1,
    },frame)

    local scanBtn=button(bar,"SCAN TODO")
    scanBtn.Position=UDim2.fromOffset(0,0);scanBtn.Size=UDim2.fromOffset(82,30)

    local testBtn=button(bar,"TEST 3 MIN")
    testBtn.Position=UDim2.fromOffset(88,0);testBtn.Size=UDim2.fromOffset(108,30)

    local hopBtn=button(bar,"HOP")
    hopBtn.Position=UDim2.fromOffset(202,0);hopBtn.Size=UDim2.fromOffset(70,30)

    local stopBtn=button(bar,"STOP")
    stopBtn.Position=UDim2.fromOffset(278,0);stopBtn.Size=UDim2.fromOffset(70,30)

    local resetBtn=button(bar,"RESET")
    resetBtn.Position=UDim2.fromOffset(354,0);resetBtn.Size=UDim2.fromOffset(70,30)

    local viewBtn=button(bar,"VISTA GOOD")
    viewBtn.Position=UDim2.fromOffset(430,0);viewBtn.Size=UDim2.fromOffset(98,30)

    local copyBtn=button(bar,"REPORTE")
    copyBtn.Position=UDim2.fromOffset(0,36);copyBtn.Size=UDim2.fromOffset(92,30)

    local censusBtn=button(bar,"GUARDAR CENSUS")
    censusBtn.Position=UDim2.fromOffset(98,36);censusBtn.Size=UDim2.fromOffset(126,30)

    local test20Btn=button(bar,"TEST 20 MIN")
    test20Btn.Position=UDim2.fromOffset(230,36);test20Btn.Size=UDim2.fromOffset(108,30)

    local reportHint=new("TextLabel",{
        Position=UDim2.fromOffset(344,36),
        Size=UDim2.fromOffset(184,30),
        BackgroundColor3=Color3.fromRGB(15,20,29),
        BorderSizePixel=0,
        Text="20 MIN = cambios + hops",
        TextColor3=Color3.fromRGB(117,140,169),
        TextSize=10,
        Font=Enum.Font.Gotham,
    },bar)
    round(reportHint,8);stroke(reportHint)

    local scroll=new("ScrollingFrame",{
        Position=UDim2.fromOffset(16,208),
        Size=UDim2.new(1,-32,0,236),
        BackgroundColor3=Color3.fromRGB(15,20,29),
        BorderSizePixel=0,
        ScrollBarThickness=5,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.new(),
    },frame)
    round(scroll,9);stroke(scroll)

    local eggsText=new("TextLabel",{
        Position=UDim2.fromOffset(10,8),
        Size=UDim2.new(1,-20,0,0),
        AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,
        Text="",
        TextColor3=Color3.fromRGB(208,221,240),
        TextSize=10,
        Font=Enum.Font.Code,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,
    },scroll)

    local logText=new("TextLabel",{
        Position=UDim2.fromOffset(16,452),
        Size=UDim2.new(1,-32,0,100),
        BackgroundColor3=Color3.fromRGB(12,17,25),
        BorderSizePixel=0,
        Text="",
        TextColor3=Color3.fromRGB(120,145,176),
        TextSize=9,
        Font=Enum.Font.Code,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,
        TextWrapped=false,
    },frame)
    round(logText,9);stroke(logText)
    new("UIPadding",{PaddingLeft=UDim.new(0,9),PaddingTop=UDim.new(0,7)},logText)

    ui.gui=gui
    ui.badge=badge
    ui.frame=frame
    ui.status=status
    ui.eggsText=eggsText
    ui.logText=logText
    ui.scanBtn=scanBtn
    ui.testBtn=testBtn
    ui.test20Btn=test20Btn
    ui.hopBtn=hopBtn
    ui.stopBtn=stopBtn
    ui.resetBtn=resetBtn
    ui.viewBtn=viewBtn
    ui.copyBtn=copyBtn
    ui.censusBtn=censusBtn

    track(badge.Activated:Connect(function()
        frame.Visible=not frame.Visible
        pcall(refreshStatus)
    end))

    local dragging=false
    local dragStart,startPos
    track(frame.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true
            dragStart=input.Position
            startPos=frame.Position
        end
    end))
    track(frame.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local d=input.Position-dragStart
            frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end))

    Shared.__VYRO_CORE_UI_READY=true
    Shared.__VYRO_CORE_UI_ERROR=nil
    return true
end

function PatchSZ.countVerifiedWorld()
    local n=0
    for _,egg in ipairs(S.eggs or {}) do
        if egg.source=="world_spawn" and (tonumber(egg.sourceConfidence) or 0)>=CFG.WORLD_MIN_CONFIDENCE then n=n+1 end
    end
    return n
end

function PatchSZ.compactExclusionReasons()
    local parts={}
    for reason,count in pairs(S.exclusionReasons or {}) do
        parts[#parts+1]={reason=tostring(reason),count=tonumber(count) or 0}
    end
    table.sort(parts,function(a,b) return a.count>b.count end)
    local out={}
    for i,item in ipairs(parts) do
        if i>6 then break end
        out[#out+1]=item.reason..":"..tostring(item.count)
    end
    return #out>0 and table.concat(out," | ") or "none"
end

function PatchSZ.compactReasonMap(map)
    local rows={}
    for key,count in pairs(map or {}) do
        rows[#rows+1]={key=tostring(key),count=tonumber(count) or 0}
    end
    table.sort(rows,function(a,b)
        if a.count~=b.count then return a.count>b.count end
        return a.key<b.key
    end)
    local out={}
    for i,row in ipairs(rows) do
        if i>8 then break end
        out[#out+1]=row.key..":"..tostring(row.count)
    end
    return table.concat(out," || ")
end

function PatchSZ.compactCountMap(map)
    local rows={}
    for id,count in pairs(map or {}) do
        rows[#rows+1]={id=tostring(id),count=tonumber(count) or 0}
    end
    table.sort(rows,function(a,b) return a.id<b.id end)
    local out={}
    for _,row in ipairs(rows) do
        out[#out+1]=row.id..":"..tostring(row.count)
    end
    return table.concat(out," || ")
end


function PatchSZ.primitiveToString(value)
    local t=typeof(value)
    if t=="string" or t=="number" or t=="boolean" then
        return tostring(value)
    elseif t=="Vector3" then
        return string.format("(%.2f,%.2f,%.2f)",value.X,value.Y,value.Z)
    elseif t=="Vector2" then
        return string.format("(%.2f,%.2f)",value.X,value.Y)
    elseif t=="Color3" then
        return string.format("(%.3f,%.3f,%.3f)",value.R,value.G,value.B)
    elseif t=="CFrame" then
        local p=value.Position
        return string.format("CFrame(%.2f,%.2f,%.2f)",p.X,p.Y,p.Z)
    elseif t=="BrickColor" or t=="EnumItem" then
        return tostring(value)
    end
    return "<"..t..">"
end

function PatchSZ.attributesSummary(obj,maxAttrs)
    if not obj then return "none" end
    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if not ok or type(attrs)~="table" then return "none" end

    local keys={}
    for key in pairs(attrs) do keys[#keys+1]=tostring(key) end
    table.sort(keys)

    local out={}
    for i,key in ipairs(keys) do
        if i>(maxAttrs or CFG.CENSUS_MAX_ATTRS) then
            out[#out+1]="...+"..tostring(#keys-(maxAttrs or CFG.CENSUS_MAX_ATTRS))
            break
        end
        out[#out+1]=key.."="..PatchSZ.primitiveToString(attrs[key])
    end
    return #out>0 and table.concat(out,";") or "none"
end

function PatchSZ.directChildrenSummary(obj,maxChildren)
    if not obj then return "none" end
    local children=obj:GetChildren()
    table.sort(children,function(a,b) return a.Name<b.Name end)
    local out={}
    local maxN=maxChildren or 24
    for i,child in ipairs(children) do
        if i>maxN then
            out[#out+1]="...+"..tostring(#children-maxN)
            break
        end

        local value=""
        if child:IsA("ValueBase") then
            local ok,v=pcall(function() return child.Value end)
            if ok then value="="..PatchSZ.primitiveToString(v) end
        elseif child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
            value="="..tostring(child.Text)
        end

        out[#out+1]=child.Name.."["..child.ClassName.."]"..value
    end
    return #out>0 and table.concat(out,";") or "none"
end

function PatchSZ.eggPositionString(entry)
    local p=entry and entry._position
    if not p then return "nil" end
    return string.format("%.2f,%.2f,%.2f",p.X,p.Y,p.Z)
end

function PatchSZ.inferUnknownPrefix(displayName)
    local raw=tostring(displayName or "")
    local bestPet,bestPrefix=nil,nil

    for pet in pairs(PET_CATALOG) do
        if #pet<#raw and raw:sub(-#pet)==pet then
            local prefix=raw:sub(1,#raw-#pet):gsub("%s+$","")
            if prefix~="" then
                if not bestPet or #pet>#bestPet then
                    bestPet=pet
                    bestPrefix=prefix
                end
            end
        end
    end

    return bestPrefix,bestPet
end

function PatchSZ.interestingEventProbe()
    local rows={}
    local seen={}
    local patterns={"sammy","event","rift","biome","angel","demon","titan","egg","shrine","luminous","monster","admin"}
    local roots={workspace,workspace:FindFirstChild("__OBJECTS"),Lighting}

    local function interesting(name)
        local low=tostring(name or ""):lower()
        for _,p in ipairs(patterns) do
            if low:find(p,1,true) then return true end
        end
        return false
    end

    local function add(obj)
        if not obj or seen[obj] or #rows>=CFG.CENSUS_MAX_EVENT_PROBE then return end
        seen[obj]=true
        if interesting(obj.Name) or obj==workspace or obj==Lighting then
            rows[#rows+1]=string.format(
                "%s | class=%s | attrs=%s",
                obj:GetFullName(),
                obj.ClassName,
                PatchSZ.attributesSummary(obj,16)
            )
        end
    end

    local visitBudget=1500
    local visited=0
    for _,root in ipairs(roots) do
        if root and visited<visitBudget and #rows<CFG.CENSUS_MAX_EVENT_PROBE then
            local stack={root}
            while #stack>0 and visited<visitBudget and #rows<CFG.CENSUS_MAX_EVENT_PROBE do
                local obj=table.remove(stack)
                visited=visited+1
                add(obj)
                local ok,children=pcall(function() return obj:GetChildren() end)
                if ok and type(children)=="table" then
                    for i=#children,1,-1 do
                        stack[#stack+1]=children[i]
                    end
                end
            end
        end
    end

    return rows
end

function PatchSZ.buildCensusReport()
    local refreshOk,refreshErr=pcall(waitForStableAssets,"full")
    if not refreshOk then
        S.lastError="census_refresh:"..tostring(refreshErr)
        logLine("CENSUS REFRESH WARN ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(refreshErr))
    end

    local folder=workspace:FindFirstChild("ClientRenderedAssets")
    local raw=S.rawEggs or {}
    local groups={}
    local unknownBiomes={}
    local unknownPets={}
    local unknownPrefixes={}
    local matchedNames={}
    local unmatched={}

    for _,entry in ipairs(raw) do
        local id=tostring(entry.biomeId or "?")
        groups[id]=groups[id] or {}
        groups[id][#groups[id]+1]=entry
        matchedNames[id.."_"..tostring(entry.uid or "")]=true

        if not KNOWN_BIOMES[id] then
            unknownBiomes[id]=(unknownBiomes[id] or 0)+1
        end

        if not select(1,lookupEggInfo(entry.pet)) then
            unknownPets[tostring(entry.pet or "?")]=(unknownPets[tostring(entry.pet or "?")] or 0)+1
            local prefix,basePet=PatchSZ.inferUnknownPrefix(entry.displayName)
            if prefix and basePet then
                local key=prefix.." -> "..basePet
                unknownPrefixes[key]=(unknownPrefixes[key] or 0)+1
            end
        end
    end

    if folder then
        for _,obj in ipairs(folder:GetChildren()) do
            local biomeId,uid=tostring(obj.Name):match("^(%d+)_(.+)$")
            if not (biomeId and uid) then
                unmatched[#unmatched+1]=obj
            end
        end
    end

    S.censusLastAt=nowUnix()
    S.censusUnknownBiomes=unknownBiomes
    S.censusUnknownPets=unknownPets
    S.censusUnknownPrefixes=unknownPrefixes
    S.censusUnmatchedAssets=#unmatched

    local function countMapRows(map)
        local rows={}
        for key,count in pairs(map or {}) do
            rows[#rows+1]={key=tostring(key),count=tonumber(count) or 0}
        end
        table.sort(rows,function(a,b)
            if a.count~=b.count then return a.count>b.count end
            return a.key<b.key
        end)
        local out={}
        for _,r in ipairs(rows) do out[#out+1]=r.key..":"..tostring(r.count) end
        return #out>0 and table.concat(out," || ") or "none"
    end

    local lines={
        "===== VYRO FULL CENSUS REPORT =====",
        "version="..CFG.VERSION,
        "account="..tostring(LP.Name),
        "user_id="..tostring(LP.UserId),
        "place_id="..tostring(game.PlaceId),
        "job_id="..tostring(game.JobId),
        "timestamp="..tostring(nowUnix()),
        "state="..tostring(S.state),
        "state_detail="..tostring(S.stateDetail),
        "mode="..tostring(S.mode),
        "hunt_remaining="..tostring(huntRemaining()),
        "hops="..tostring(S.hops or 0),
        "visited_servers="..tostring(countKeys(S.visited or {})),
        "queue_available="..tostring(S.queueAvailable),
        "reexec_armed="..tostring(S.reexecArmed),
        "last_error="..tostring(S.lastError),
        "last_teleport_failure="..tostring(S.lastTeleportFailure),
        "last_hop_attempt="..tostring(S.lastHopAttempt),
        "last_hop_target="..tostring(S.lastHopTarget),
        "current_job_id="..tostring(S.currentJobId),
        "silent_teleport_failures="..tostring(S.silentTeleportFailures or 0),
        "last_hop_accepted="..tostring(S.lastHopAccepted),
        "teleport_retry_count="..tostring(S.teleportRetryCount or 0),
        "teleport_queue_count="..tostring(S.teleportQueueCount),
        "queue_function="..tostring(S.queueFunction),
        "scan_mode="..tostring(S.scanMode),
        "visual_expected="..tostring(S.lastVisualExpected or 0),
        "visual_matched="..tostring(S.lastVisualMatched or 0),
        "fingerprint_known="..tostring(S.fingerprintKnown or 0),
        "fingerprint_unknown="..tostring(S.fingerprintUnknown or 0),
        "light_dark_side="..tostring(S.lightDarkSide),
        "client_rendered_assets="..tostring(folder~=nil),
        "client_rendered_children="..tostring(folder and #folder:GetChildren() or 0),
        "raw_egg_assets="..tostring(#raw),
        "unmatched_client_assets="..tostring(#unmatched),
        "biome_id_count="..tostring(countKeys(groups)),
        "known_catalog_pets="..tostring(countKeys(PET_CATALOG)),
        "unknown_biomes="..countMapRows(unknownBiomes),
        "unknown_parsed_pets="..countMapRows(unknownPets),
        "unknown_prefix_candidates="..countMapRows(unknownPrefixes),
        "natural_eggs_per_biome="..tostring(CFG.NATURAL_EGGS_PER_BIOME),
        "stable_wait_ms="..tostring(S.lastStableWaitMs),
        "scan_ms="..tostring(S.lastScanMs),
        "",
        "----- BIOME GROUP SUMMARY -----",
    }

    local ids={}
    for id in pairs(groups) do ids[#ids+1]=id end
    table.sort(ids,function(a,b)
        local an,bn=tonumber(a),tonumber(b)
        if an and bn then return an<bn end
        return a<b
    end)

    for _,id in ipairs(ids) do
        local entries=groups[id]
        local known=KNOWN_BIOMES[id]
        local status
        if #entries==CFG.NATURAL_EGGS_PER_BIOME then status="NATURAL5_EXACT"
        elseif #entries>CFG.NATURAL_EGGS_PER_BIOME then status="OVERFLOW_OR_EXTRA"
        else status="PARTIAL_OR_STREAMING" end

        lines[#lines+1]=string.format(
            "[%s] %s | count=%d | %s",
            id,
            tostring(known or "UNKNOWN_BIOME"),
            #entries,
            status
        )

        table.sort(entries,function(a,b)
            local as,bs=a.scale or -1,b.scale or -1
            if as~=bs then return as>bs end
            return tostring(a.displayName)<tostring(b.displayName)
        end)

        for index,e in ipairs(entries) do
            local cat,canonicalKey=catalogInfo(e)
            local prefix,basePet=nil,nil
            if not cat then prefix,basePet=PatchSZ.inferUnknownPrefix(e.displayName) end

            lines[#lines+1]=string.format(
                "  %02d | uid=%s | display=%q | parsed_pet=%q | scale=%s | scale_src=%s | pos=%s | source=%s | conf=%.3f | reason=%s | catalog=%s | catalog_biome=%s | rarity=%s | egg=%s | possible_new_prefix=%s | prefix_base_pet=%s | muts=%s",
                index,
                tostring(e.uid or ""),
                tostring(e.displayName or ""),
                tostring(e.pet or ""),
                e.scale and string.format("%.3f",e.scale) or "nil",
                tostring(e.scaleSource or ""),
                PatchSZ.eggPositionString(e),
                tostring(e.source or ""),
                tonumber(e.sourceConfidence or 0),
                tostring(e.locationReason or ""),
                cat and "known" or "UNKNOWN",
                cat and tostring(cat.biome or "") or "",
                cat and tostring(cat.rarity or "") or "",
                cat and tostring(cat.egg or "") or "",
                tostring(prefix or ""),
                tostring(basePet or ""),
                #(e.muts or {})>0 and table.concat(e.muts,"+") or "none"
            )
        end
    end

    lines[#lines+1]=""
    lines[#lines+1]="----- PLAYER-BASE RENDERED ASSETS (DIAGNOSTIC ONLY) -----"

    if folder then
        local rawByKey={}
        for _,e in ipairs(raw) do rawByKey[tostring(e.biomeId).."_"..tostring(e.uid)]=e end

        local children=folder:GetChildren()
        table.sort(children,function(a,b) return a.Name<b.Name end)

        for _,obj in ipairs(children) do
            local biomeId,uid=tostring(obj.Name):match("^(%d+)_(.+)$")
            local key=biomeId and uid and (tostring(biomeId).."_"..tostring(uid)) or nil
            local e=key and rawByKey[key] or nil
            local data=obj:FindFirstChild("Data")

            lines[#lines+1]=string.format(
                "OBJ | name=%q | class=%s | matched=%s | biomeId=%s | uid=%s | display=%q | attrs={%s} | children={%s} | data_attrs={%s} | data_children={%s}",
                tostring(obj.Name),
                tostring(obj.ClassName),
                tostring(e~=nil),
                tostring(biomeId or ""),
                tostring(uid or ""),
                tostring(e and e.displayName or readDisplayName(obj)),
                PatchSZ.attributesSummary(obj,CFG.CENSUS_MAX_ATTRS),
                PatchSZ.directChildrenSummary(obj,24),
                PatchSZ.attributesSummary(data,CFG.CENSUS_MAX_ATTRS),
                PatchSZ.directChildrenSummary(data,24)
            )
        end
    end

    lines[#lines+1]=""
    lines[#lines+1]="----- UNMATCHED CLIENTRENDEREDASSETS -----"
    for i,obj in ipairs(unmatched) do
        if i>CFG.CENSUS_MAX_UNMATCHED then
            lines[#lines+1]="... +"..tostring(#unmatched-CFG.CENSUS_MAX_UNMATCHED).." more"
            break
        end
        lines[#lines+1]=string.format(
            "%03d | %q | class=%s | attrs={%s} | children={%s}",
            i,tostring(obj.Name),tostring(obj.ClassName),
            PatchSZ.attributesSummary(obj,CFG.CENSUS_MAX_ATTRS),
            PatchSZ.directChildrenSummary(obj,24)
        )
    end

    lines[#lines+1]=""
    lines[#lines+1]="----- EVENT / UPDATE PROBE -----"
    local probe=PatchSZ.interestingEventProbe()
    for _,row in ipairs(probe) do lines[#lines+1]=row end

    lines[#lines+1]=""
    lines[#lines+1]="----- NORMAL COMMERCIAL SUMMARY -----"
    lines[#lines+1]="world_candidates="..tostring(#(S.eggs or {}))
    lines[#lines+1]="premium_eggs="..tostring(#(S.targets or {}))
    lines[#lines+1]="qualified_eggs="..tostring(#(S.qualifiedTargets or {}))
    lines[#lines+1]="total_eggs_sent="..tostring(S.totalEggsSent or 0)
    lines[#lines+1]="last_eggs_sent="..tostring(S.lastEggsSent or 0)
    lines[#lines+1]="backend_whitelist_accepted="..tostring(S.lastRawAccepted or 0)
    lines[#lines+1]="backend_whitelist_ignored="..tostring(S.lastRawIgnored or 0)
    lines[#lines+1]="===== END FULL CENSUS ====="

    local report=table.concat(lines,"\n")

    if type(Shared.__VYRO_EXEC._WF)=="function" then
        pcall(function() Shared.__VYRO_EXEC._WF(CENSUS_FILE,report) end)
    end

    Shared.VYRO_FULL_CENSUS_LAST=report
    return report
end

function PatchSZ.copyCensus()
    local report=PatchSZ.buildCensusReport()
    local fn=nil
    if type(Shared.__VYRO_EXEC._SC)=="function" then fn=Shared.__VYRO_EXEC._SC
    elseif type(toclipboard)=="function" then fn=toclipboard end

    if fn then
        local ok=pcall(fn,report)
        if ok then
            logLine("FULL CENSUS COPIED ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(#report).." chars")
            return true
        end
    end

    logLine("FULL CENSUS guardado en "..CENSUS_FILE)
    return false
end

Shared.VYRO_FULL_CENSUS=PatchSZ.buildCensusReport
Shared.VYRO_COPY_FULL_CENSUS=PatchSZ.copyCensus

function PatchSZ.buildReport()
    local reportMode=(S.mode=="hunting") and "premium" or "full"
    if S.lastStableJobId~=tostring(game.JobId) then
        waitForStableAssets(reportMode)
        writeSnapshot()
    else
        scanNow(reportMode)
    end

    local lines={
        "===== VYRO SUPER PRIME REPORT =====",
        "version="..CFG.VERSION,
        "account="..tostring(LP.Name),
        "user_id="..tostring(LP.UserId),
        "job_id="..tostring(game.JobId),
        "state="..tostring(S.state),
        "state_detail="..tostring(S.stateDetail),
        "mode="..tostring(S.mode),
        "hunt_remaining="..huntRemaining(),
        "hops="..tostring(S.hops),
        "visited="..tostring(countKeys(S.visited)),
        "server_queue="..tostring(#S.serverQueue),
        "servers_per_min="..string.format("%.2f",serversPerMinute()),
        "scan_mode="..tostring(S.scanMode),
        "visual_expected="..tostring(S.lastVisualExpected or 0),
        "visual_matched="..tostring(S.lastVisualMatched or 0),
        "scan_ms="..tostring(S.lastScanMs),
        "stable_wait_ms="..tostring(S.lastStableWaitMs),
        "raw_eggs="..tostring(#(S.rawEggs or {})),
        "world_candidates="..tostring(#S.eggs),
        "verified_world_eggs="..tostring(PatchSZ.countVerifiedWorld()),
        "premium_eggs="..tostring(#S.targets),
        "qualified_eggs="..tostring(#S.qualifiedTargets),
        "total_eggs_sent="..tostring(S.totalEggsSent or 0),
        "last_eggs_sent="..tostring(S.lastEggsSent or 0),
        "backend_whitelist_accepted="..tostring(S.lastRawAccepted or 0),
        "backend_whitelist_ignored="..tostring(S.lastRawIgnored or 0),
        "skipped_quality="..tostring(S.skippedQuality or 0),
        "quality_policy_version="..tostring(S.qualityPolicyVersion),
        "node_connected="..tostring(S.nodeConnected),
        "node_required_for_cloud_and_updates="..tostring(true),
        "cloud_status="..tostring(S.lastCloudStatus),
        "cloud_error="..tostring(S.lastCloudError),
        "excluded_base="..tostring(S.excludedBase or 0),
        "excluded_uncertain="..tostring(S.excludedUncertain or 0),
        "base_regions="..tostring(#(S.baseRegions or {})),
        "base_map_resolved="..tostring(S.baseMapResolved),
        "base_discovery_source="..tostring(S.baseDiscoverySource),
        "base_region_names="..tostring(table.concat(S.baseRegionNames or {}," || ")),
        "base_region_sizes="..tostring(table.concat(S.baseRegionSizes or {}," || ")),
        "source_truth=Workspace.__OBJECTS.Areas.GuardAreas.<zone>.Nests",
        "nest_slots_total="..tostring(S.nestSlotsTotal or 0),
        "nest_slots_resolved="..tostring(S.nestSlotsResolved or 0),
        "base_rendered_ignored="..tostring(S.baseRenderedIgnored or 0),
        "nest_biome_counts="..tostring(PatchSZ.compactCountMap(S.nestBiomeCounts)),
        "nest_unresolved="..tostring(table.concat(S.nestUnresolved or {}," || ")),
        "fingerprint_known="..tostring(S.fingerprintKnown or 0),
        "fingerprint_unknown="..tostring(S.fingerprintUnknown or 0),
        "unknown_fingerprints="..tostring(PatchSZ.compactReasonMap(S.unknownFingerprints)),
        "light_dark_side="..tostring(S.lightDarkSide),
        "natural_eggs_per_biome="..tostring(CFG.NATURAL_EGGS_PER_BIOME),
        "biome_group_counts="..tostring(PatchSZ.compactCountMap(S.biomeGroupCounts)),
        "biome_world_counts="..tostring(PatchSZ.compactCountMap(S.biomeWorldCounts)),
        "natural5_learned_biomes="..tostring(S.natural5LearnedBiomes or 0),
        "natural5_overflow_excluded="..tostring(S.natural5OverflowExcluded or 0),
        "natural5_partial_groups="..tostring(S.natural5PartialGroups or 0),
        "learned_slot_biomes="..tostring(countKeys(S.learnedWorldSlots)),
        "rift_open="..tostring((S.eventFlags or {}).LiveEventFlag_RiftOpen),
        "scramble_outbreak_active="..tostring((S.eventFlags or {}).ScrambleOutbreakActive),
        "owner_metadata_seen="..tostring(S.ownerMetadataSeen or 0),
        "owner_metadata_reasons="..tostring(PatchSZ.compactReasonMap(S.ownerMetadataReasons)),
        "exclusion_reasons="..compactExclusionReasons(),
        "commercial_fail_closed="..tostring(CFG.REQUIRE_NATURAL5_FOR_COMMERCIAL),
        "coordinator_active="..tostring(S.coordinatorActive),
        "queue_available="..tostring(S.queueAvailable),
        "reexec_armed="..tostring(S.reexecArmed),
        "reexec_error="..tostring(S.reexecError),
        "http_status="..tostring(S.lastServerHttpStatus),
        "cycle_edges="..tostring(S.cycleEdgeCount),
        "observed_cycle_seconds="..tostring(S.observedCycleSeconds),
        "memory_mb="..tostring(S.memoryMb),
        "last_error="..tostring(S.lastError),
        "last_teleport_failure="..tostring(S.lastTeleportFailure),
        "bridge_connected="..tostring(type(Shared.VYRO_CORE_ON_SNAPSHOT)=="function"),
        "bridge_last_error="..tostring(S.lastBridgeError),
        "",
        "----- QUALIFIED SUPER PRIME EGGS ONLY -----",
    }

    for i,e in ipairs(S.qualifiedTargets) do
        lines[#lines+1]=string.format(
            "%02d | Q=%.1f | %.2fx | %s | rarity=%s | biome=%s | why=%s | source=%s | conf=%.2f | muts=%s | uid=%s",
            i,tonumber(e.qualityScore or 0),e.scale or 0,e.pet,tostring(e.rarity or "Unknown"),tostring(e.targetBiome or e.biomeName),tostring(e.qualityReason or ""),
            tostring(e.source or "world_spawn"),tonumber(e.sourceConfidence or 0),
            #(e.muts or {})>0 and table.concat(e.muts,"+") or "none",e.uid
        )
    end

    lines[#lines+1]=""
    lines[#lines+1]="----- LOGS -----"
    for _,line in ipairs(logs) do lines[#lines+1]=line end
    lines[#lines+1]="===== END REPORT ====="

    return table.concat(lines,"\n")
end

function PatchSZ.copyReport()
    local report=PatchSZ.buildReport()
    local fn=nil
    if type(Shared.__VYRO_EXEC._SC)=="function" then fn=Shared.__VYRO_EXEC._SC
    elseif type(toclipboard)=="function" then fn=toclipboard end

    if fn then
        local ok=pcall(fn,report)
        if ok then logLine("REPORT COPIED") return true end
    end

    logLine("Clipboard no disponible. Usa console/Shared.VYRO_CORE_REPORT().")
    return false
end

Shared.VYRO_CORE_REPORT=PatchSZ.buildReport
Shared.VYRO_CORE_COPY_REPORT=PatchSZ.copyReport
Shared.VYRO_CORE_SCAN=scanNow
Shared.VYRO_CORE_SNAPSHOT=buildSnapshotPayload
Shared.VYRO_CORE_QUALITY_POLICY=qualityPolicy
Shared.VYRO_CORE_REFRESH_NODE=refreshNodeConfig
Shared.VYRO_CORE_START_TEST=function()
    return beginHunt("TEST API",true,CFG.HUNT_SECONDS)
end
Shared.VYRO_CORE_START_TEST20=function()
    return beginHunt("TEST20 API",true,CFG.HUNT_LONG_SECONDS)
end
Shared.VYRO_CORE_FORCE_HOP=function(reason)
    local why=tostring(reason or "coord_conflict_external")
    if Runtime.teleporting then
        return false,"teleporting"
    end
    if S.mode~="hunting" and not why:find("coord_conflict",1,true) then
        why="coord_conflict_"..why
    end
    local ok,result=pcall(Runtime.doRejoin,why)
    if not ok then
        S.lastError="force_hop_api:"..tostring(result)
        writeStatus()
        refreshStatus()
        return false,tostring(result)
    end
    return result==true,result
end

function Runtime.stop()
    setState("STOPPED","Runtime detenido")
    writeStatus()
    Runtime.alive=false
    Runtime.huntToken=nil
    disconnectAll()
    if ui.gui then pcall(function() ui.gui:Destroy() end) end
end

Shared.__VYRO_CORE_UI_READY=false
Shared.__VYRO_CORE_UI_ERROR=nil

PatchSZ.uiOk,PatchSZ.uiErr=pcall(ui.buildUI)
if not PatchSZ.uiOk then
    Shared.__VYRO_CORE_UI_ERROR="buildUI: "..tostring(PatchSZ.uiErr)
    error(Shared.__VYRO_CORE_UI_ERROR)
elseif not Shared.__VYRO_CORE_UI_READY then
    error(Shared.__VYRO_CORE_UI_ERROR or "buildUI returned without UI")
end

pcall(applyLite)
pcall(applyUltraLiteDynamic)
task.spawn(function()
    while Runtime.alive do
        pcall(applyUltraLiteDynamic)
        task.wait(1)
    end
end)
pcall(function() refreshNodeConfig(true) end)
pcall(Runtime.restoreState)
pcall(markLanding)
if CFG.CONTINUOUS_SCAN and S.mode=="parked" and type(beginHunt)=="function" then
    task.defer(function()
        if Runtime.alive and S.mode=="parked" then
            beginHunt("startup continuous",true,CFG.SCANNER_CONTINUOUS_HUNT_SECONDS)
        end
    end)
end

PatchSZ.queueFn,PatchSZ.queueFnName=getQueueFn(); S.queueAvailable=PatchSZ.queueFn~=nil; S.queueFunction=PatchSZ.queueFnName
if not S.queueAvailable then
    logLine("AVISO: queue_on_teleport no disponible. Hops quedan bloqueados.")
end


function PatchSZ.dismissSafeRobloxPrompt()
    local allowed={
        ["ok"]=true,["aceptar"]=true,["retry"]=true,["reintentar"]=true,
        ["reconnect"]=true,["volver a intentar"]=true,["continuar"]=true,["continue"]=true,
    }
    local roots={}
    pcall(function() roots[#roots+1]=game:GetService("CoreGui") end)
    pcall(function()
        local pg=LP and LP:FindFirstChildOfClass("PlayerGui")
        if pg then roots[#roots+1]=pg end
    end)
    local clicked=false
    for _,root in ipairs(roots) do
        if root then
            for _,obj in ipairs(root:GetDescendants()) do
                if obj:IsA("GuiButton") and obj.Visible then
                    local txt=""
                    pcall(function() txt=tostring(obj.Text or "") end)
                    txt=txt:lower():gsub("^%s+",""):gsub("%s+$","")
                    if allowed[txt] then
                        local ok=pcall(function() obj:Activate() end)
                        if ok then
                            clicked=true
                            logLine("PROMPT DISMISSED Â· "..txt)
                        end
                    end
                end
            end
        end
    end
    return clicked
end

track(TeleportService.TeleportInitFailed:Connect(function(player,result,message)
    if player~=LP then return end

    Runtime.teleporting=false
    S.reexecArmed=false
    S.lastTeleportFailure=tostring(result).." ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(message)

    local failed=S.pendingJobId
    if failed and tostring(failed)~="random" then
        pcall(function() Runtime.markBadJobCache(tostring(failed),"teleport_init_failed") end)
    end

    local full=Runtime.isFullFailure(result,message)
    if full then S.fullServerFailures=S.fullServerFailures+1 end

    -- Roblox can leave a blocking error prompt on top even though TeleportInitFailed fired.
    -- Dismiss only safe confirmation/retry buttons, then continue with the next JobId.
    pcall(PatchSZ.dismissSafeRobloxPrompt)
    task.delay(0.35,function() pcall(PatchSZ.dismissSafeRobloxPrompt) end)
    task.delay(0.90,function() pcall(PatchSZ.dismissSafeRobloxPrompt) end)

    S.pendingJobId=nil
    S.pendingStartedMs=nil
    S.teleportRetryCount=(tonumber(S.teleportRetryCount) or 0)+1
    if S.teleportRetryCount>=CFG.TELEPORT_MAX_CONSECUTIVE_RETRIES then
        logLine("TELEPORT FAIL · 3 fallos -> cache clear + random")
        local fallbackOk=Runtime.randomTeleportFallback("teleport_init_failed")
        if not fallbackOk then
            Runtime.huntLoopRunning=false
            local token=Runtime.huntToken
            local backoff=math.max(2,math.min(tonumber(CFG.SERVER_BACKOFF_BASE) or 12,15))
            task.delay(backoff,function()
                if Runtime.alive
                    and Runtime.huntToken==token
                    and S.mode=="hunting"
                    and S.huntEnd
                    and nowUnix()<S.huntEnd
                    and not Runtime.teleporting
                then
                    logLine("RECOVERY BACKOFF · reanudando búsqueda de servidor")
                    startHuntLoop(token)
                end
            end)
        end
        return
    end
    setState("RECOVERING",full and "Server lleno" or "Teleport fallo")
    saveState()
    writeStatus()
    logLine((full and "SERVER FULL" or "TELEPORT FAIL").." · retry")

    if S.mode=="hunting" and S.huntEnd and nowUnix()<S.huntEnd then
        Runtime.huntLoopRunning=false
        local token=Runtime.huntToken
        task.delay(full and CFG.FULL_SERVER_RETRY_DELAY or CFG.TELEPORT_RETRY_DELAY,function()
            if Runtime.alive
                and Runtime.huntToken==token
                and S.mode=="hunting"
                and S.huntEnd
                and nowUnix()<S.huntEnd
            then
                if not Runtime.doRejoin("retry") then
                    startHuntLoop(token)
                end
            end
        end)
    end
end))


task.spawn(function()
    while Runtime.alive do
        if Runtime.teleporting or S.state=="JOINING" or S.state=="RECOVERING" then
            pcall(PatchSZ.dismissSafeRobloxPrompt)
        end
        task.wait(0.75)
    end
end)

if ui.scanBtn then
    track(ui.scanBtn.Activated:Connect(function()
        if Runtime.teleporting then
            logLine("SCAN TODO OMITIDO ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· teleport en curso; espera a aterrizar")
            refreshStatus()
            return
        end
        setState("SCANNING","Scan manual")
        waitForStableAssets("full")
        writeSnapshot()
        S.uiView="WORLD"
        refreshEggUI()
        setState(S.mode=="hunting" and "HUNTING" or "READY","Scan terminado")
        refreshStatus()
        writeStatus()
        logLine(string.format(
            "SCAN TODO ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· NESTS=%d/%d WORLD=%d PREMIUM=%d GOOD=%d BASE_IGN=%d",
            tonumber(S.nestSlotsResolved) or 0,
            tonumber(S.nestSlotsTotal) or 0,
            #(S.eggs or {}),
            #(S.targets or {}),
            #(S.qualifiedTargets or {}),
            tonumber(S.baseRenderedIgnored) or 0
        ))
    end))
end

if ui.testBtn then
    track(ui.testBtn.Activated:Connect(function()
        ui.testBtn.Text="INICIANDOÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦"
        ui.testBtn.BackgroundColor3=Color3.fromRGB(38,96,166)
        setState("STARTING","TEST 3 MIN")
        refreshStatus()
        logLine("TEST CLICK ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· iniciando hunt")

        local ok,result=pcall(function()
            return beginHunt("TEST 3 MIN",true,CFG.HUNT_SECONDS)
        end)

        if not ok then
            S.lastError="test_button:"..tostring(result)
            setState("ERROR","TEST no pudo iniciar")
            ui.testBtn.Text="TEST ERROR"
            ui.testBtn.BackgroundColor3=Color3.fromRGB(150,45,54)
            logLine("TEST ERROR ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(result))
            writeStatus()
            refreshStatus()
        else
            logLine("TEST ARMADO ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..huntRemaining())
            refreshStatus()
        end
    end))
end

if ui.test20Btn then
    track(ui.test20Btn.Activated:Connect(function()
        ui.test20Btn.Text="INICIANDOÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦"
        ui.test20Btn.BackgroundColor3=Color3.fromRGB(166,100,38)
        setState("STARTING","TEST 20 MIN")
        refreshStatus()
        logLine("TEST 20 CLICK ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· iniciando hunt largo")

        local ok,result=pcall(function()
            return beginHunt("TEST 20 MIN",true,CFG.HUNT_LONG_SECONDS)
        end)

        if not ok then
            S.lastError="test20_button:"..tostring(result)
            setState("ERROR","TEST 20 no pudo iniciar")
            ui.test20Btn.Text="TEST20 ERROR"
            ui.test20Btn.BackgroundColor3=Color3.fromRGB(150,45,54)
            logLine("TEST20 ERROR ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(result))
            writeStatus()
            refreshStatus()
        else
            logLine("TEST20 ARMADO ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..huntRemaining())
            refreshStatus()
        end
    end))
end

if ui.hopBtn then
    track(ui.hopBtn.Activated:Connect(function()
        if S.mode~="hunting" then beginHunt("HOP MANUAL",true) end
        task.spawn(function() Runtime.doRejoin("manual") end)
    end))
end

if ui.stopBtn then
    track(ui.stopBtn.Activated:Connect(function()
        Runtime.stopHunt("manual")
    end))
end

if ui.resetBtn then
    track(ui.resetBtn.Activated:Connect(function()
        Runtime.huntToken=nil
        Runtime.huntLoopRunning=false
        Runtime.teleporting=false
        clearState()

        S.mode="waiting"
        S.huntEnd=nil
        S.testDuration=nil
        S.teleportRetryCount=0
        S.lastTeleportFailure=nil
        S.hops=0
        S.visited={[tostring(game.JobId)]=true}
        S.serverQueue={}
        S.pendingJobId=nil
        S.reexecArmed=false
        S.cycleFingerprint=readCycleFingerprint()
        S.cycleBaselineReadyAt=os.clock()+CFG.STARTUP_CYCLE_BASELINE
        setState("READY","Reset")
        saveState()
        writeStatus()
        refreshStatus()
        logLine("RESET OK")
    end))
end

if ui.viewBtn then
    track(ui.viewBtn.Activated:Connect(function()
        if S.uiView=="QUALIFIED" then S.uiView="PREMIUM"
        elseif S.uiView=="PREMIUM" then S.uiView="WORLD"
        else S.uiView="QUALIFIED" end
        refreshEggUI()
    end))
end

if ui.censusBtn then
    track(ui.censusBtn.Activated:Connect(function()
        ui.censusBtn.Text="GUARDANDO..."
        if Runtime.teleporting then
            logLine("CENSUS OMITIDO ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· teleport en curso; espera a aterrizar")
            ui.censusBtn.Text="ESPERA..."
            task.delay(1.5,function() if ui.censusBtn then ui.censusBtn.Text="GUARDAR CENSUS" end end)
            refreshStatus()
            return
        end
        setState("CENSUS","Guardando VYRO_CENSUS_RESULT.txt")
        local ok,report=pcall(PatchSZ.buildCensusReport)
        if ok and type(report)=="string" then
            local censusSaved=false
            if type(Shared.__VYRO_EXEC._WF)=="function" then
                local writeOk=pcall(function() Shared.__VYRO_EXEC._WF(CENSUS_FILE,report) end)
                censusSaved=writeOk
            end
            if censusSaved and type(Shared.__VYRO_EXEC._IF)=="function" then
                local checkOk,exists=pcall(Shared.__VYRO_EXEC._IF,CENSUS_FILE)
                censusSaved=checkOk and exists==true
            end
            if censusSaved and type(Shared.__VYRO_EXEC._RF)=="function" then
                local readOk,saved=pcall(Shared.__VYRO_EXEC._RF,CENSUS_FILE)
                censusSaved=readOk and type(saved)=="string" and saved==report
            end
            Shared.VYRO_FULL_CENSUS_LAST=report
            local fn=nil
            if type(Shared.__VYRO_EXEC._SC)=="function" then fn=Shared.__VYRO_EXEC._SC
            elseif type(toclipboard)=="function" then fn=toclipboard end
            if fn then pcall(fn,report) end
            if censusSaved then
                ui.censusBtn.Text="CENSUS OK"
                S.censusLastSavedAt=nowUnix()
                S.censusLastSavedBytes=#report
                logLine("CENSUS SAVED -> "..CENSUS_FILE.." · "..tostring(#report).." chars")
            else
                S.lastError="CENSUS_BUTTON:file_missing_after_write"
                ui.censusBtn.Text="ERROR CENSUS"
                logLine("CENSUS ERROR -> file_missing_after_write")
            end
        else
            S.lastError="CENSUS_BUTTON:"..tostring(report)
            ui.censusBtn.Text="ERROR CENSUS"
            logLine("CENSUS ERROR -> "..tostring(report))
        end
        setState(S.mode=="hunting" and "HUNTING" or "READY","Census terminado")
        refreshEggUI()
        refreshStatus()
        writeStatus()
        task.delay(2,function() if ui.censusBtn then ui.censusBtn.Text="GUARDAR CENSUS" end end)
    end))
end

if ui.copyBtn then
    track(ui.copyBtn.Activated:Connect(function()
        PatchSZ.copyReport()
        refreshEggUI()
        refreshStatus()
    end))
end

PatchSZ.RARE_ANNOUNCE_PATTERNS = {
    "(.+) has appeared in (.+)!",
    "A (.+) egg has spawned at (.+)",
    "(.+) egg spawned in (.+)",
}

function PatchSZ.parseRareAnnouncement(text)
    local raw=stripRichText(text)
    local clean=raw:lower()
    if clean=="" then return nil end
    if not (clean:find("egg",1,true) or clean:find("huevo",1,true) or clean:find("spawn",1,true) or clean:find("appeared",1,true)) then return nil end

    for _,pattern in ipairs(PatchSZ.RARE_ANNOUNCE_PATTERNS) do
        local name,location=raw:match(pattern)
        if name and location then
            local catalog,canonical=lookupEggInfo(name)
            if catalog and PATCH_TARGET_RARITIES[tostring(catalog.rarity)] then
                local zone=getBiomeFromLocation(location)
                if zone=="Unknown" then zone=tostring(catalog.biome or "Unknown") end
                if zone=="Angels" or zone=="Demons" then zone="Light Dark" end
                return {name=canonical,rarity=catalog.rarity,biome=zone,location=location,catalog=catalog}
            end
        end
    end

    for name,catalog in pairs(PET_CATALOG) do
        if PATCH_TARGET_RARITIES[tostring(catalog.rarity)] and clean:find(tostring(name):lower(),1,true) then
            local zone=getBiomeFromLocation(raw)
            if zone=="Unknown" then zone=tostring(catalog.biome or "Unknown") end
            if zone=="Angels" or zone=="Demons" then zone="Light Dark" end
            return {name=name,rarity=catalog.rarity,biome=zone,location=raw,catalog=catalog}
        end
    end

    -- Preserve earlier retail aliases that may not yet exist in PET_CATALOG.
    for name,wanted in pairs(TARGET_ONLY) do
        if clean:find(tostring(name):lower(),1,true) then
            return {name=name,rarity=wanted.rarity,biome=wanted.zone,location=raw,retail=wanted}
        end
    end
    return nil
end

function PatchSZ.learnFingerprintsFromAnnouncement(announcement)
    local unique={}
    local rows={}
    for _,candidate in ipairs(S.pendingFingerprintCandidates or {}) do
        local sameBiome=tostring(candidate.biome)==tostring(announcement.biome)
        if sameBiome and nowUnix()-(tonumber(candidate.at) or 0)<=8 then
            local fp=tostring(candidate.fingerprint or "")
            if fp~="" and fp~="no_mesh_id" and not unique[fp] then
                unique[fp]=true
                rows[#rows+1]=candidate
            end
        end
    end
    if #rows~=1 then
        pushPatchEvent("fingerprint_learning_deferred",{name=announcement.name,biome=announcement.biome,candidates=#rows})
        return false,"ambiguous:"..tostring(#rows)
    end
    local ok,result=FP.learnFingerprint(rows[1].fingerprint,announcement.name,announcement.rarity,announcement.biome)
    if ok then
        pushPatchEvent("egg_confirmed",{name=announcement.name,rarity=announcement.rarity,biome=announcement.biome,fingerprint=rows[1].fingerprint})
        logLine("CHAT LEARNED Â· "..tostring(announcement.name).." Â· "..tostring(rows[1].fingerprint))
        return true
    end
    return false,tostring(result)
end

function PatchSZ.handleSpawnAnnouncement(text,isSystem)
    if not isSystem then return end
    local announcement=PatchSZ.parseRareAnnouncement(text)
    if not announcement then return end
    local pet=tostring(announcement.name)
    local wanted,canonicalTarget=Shared.__VYRO_LOOKUP_TARGET_ONLY(pet)
    if canonicalTarget then pet=canonicalTarget end
    local mutation=nil
    local clean=stripRichText(text):lower()
    local mutationText=clean
    -- The species name is not a mutation hint; keep separate prefixes/tags.
    if tostring(pet):lower()=="mutant shark" then
        mutationText=mutationText:gsub("mutant shark","")
    end
    for _,name in ipairs({"Spirit Bloom","Rainbow","Golden","Gold","Silver","Sakura","Mutant","Bloom","Pure"}) do
        if mutationText:find(name:lower(),1,true) then mutation=(name=="Golden" and "Gold" or name);break end
    end
    local zone=tostring(announcement.biome or (wanted and wanted.zone) or "Unknown")
    local chatAt=nowMs()/1000
    S.chatProvisionalTargets=S.chatProvisionalTargets or {}
    local eventId=nil
    for _,existing in ipairs(S.chatProvisionalTargets) do
        if tostring(existing.job or "")==tostring(game.JobId)
            and tostring(existing.pet or "")==pet
            and tostring(existing.biomeName or "")==zone
            and chatAt-(tonumber(existing.chatAnnouncementAt) or 0)<=2
        then
            eventId=tostring(existing.eventId or "")
            break
        end
    end
    if not eventId or eventId=="" then
        eventId=table.concat({
            tostring(game.JobId),"chat",
            tostring(Shared.__VYRO_NORMALIZE_EGG_NAME(pet) or pet),
            tostring(Shared.__VYRO_NORMALIZE_EGG_NAME(zone) or zone),
            tostring(chatAt)
        },":")
    end
    S.chatHint={
        pet=pet,zone=zone,side=(wanted and wanted.side) or zone,mutation=mutation,
        job=tostring(game.JobId),at=chatAt,text=clean:sub(1,220),eventId=eventId,
    }
    local provisional={
        eventId=eventId,uid=eventId,job=tostring(game.JobId),
        pet=pet,displayName=pet,
        eggName=(announcement.catalog and announcement.catalog.egg) or (pet.." Egg"),
        rarity=announcement.rarity or (wanted and wanted.rarity) or "Unknown",
        biomeName=zone,targetBiome=zone,
        muts=mutation and {mutation} or {},
        scale=nil,scaleKind="unknown",
        source="world_spawn",sourceConfidence=1.0,
        identitySource="system_chat_announcement",identityConfidence=1.0,
        locationReason="system_chat_announcement",
        chatConfirmed=true,chatAnnouncementAt=chatAt,chatText=clean:sub(1,220),
    }
    local duplicate=false
    for _,existing in ipairs(S.chatProvisionalTargets) do
        if tostring(existing.eventId or "")==eventId then duplicate=true break end
    end
    if not duplicate then S.chatProvisionalTargets[#S.chatProvisionalTargets+1]=provisional end
    pushPatchEvent("chat_detection",{name=pet,rarity=announcement.rarity,biome=zone,location=announcement.location,event_id=eventId})
    logLine("CHAT "..(wanted and "TARGET" or "LEARN").." Â· "..pet.." Â· "..zone.." Â· EVENT-FIRST")
    task.spawn(function()
        local ok,err=pcall(writeSnapshot)
        if not ok then S.lastError="chat_event_snapshot:"..tostring(err) end
    end)
    if Runtime.chatScanBusy or Runtime.teleporting then return end
    Runtime.chatScanBusy=true
    task.delay(0.04,function()
        local ok,err=pcall(function()
            scanNow("chat")
            PatchSZ.learnFingerprintsFromAnnouncement(announcement)
            if wanted then
                local foundAnnounced=false
                for _,entry in ipairs(S.qualifiedTargets or {}) do
                    if tostring(targetPetKey(entry))==pet then
                        foundAnnounced=true
                        break
                    end
                end
                if not foundAnnounced then scanNow("premium") end
                writeSnapshot()
            end
            refreshEggUI()
            refreshStatus()
            writeStatus()
        end)
        Runtime.chatScanBusy=false
        if not ok then S.lastError="chat_scan:"..tostring(err) end
        if wanted and Shared.VYRO_SCANNER_MODE==true and S.mode~="hunting" and beginHunt then
            pcall(beginHunt,"chat target "..pet,true,CFG.HUNT_SECONDS)
        end
    end)
end

pcall(function()
    track(TextChatService.MessageReceived:Connect(function(message)
        local isSystem=(message.TextSource==nil)
        PatchSZ.handleSpawnAnnouncement(message.Text,isSystem)
    end))
end)

pcall(function()
    local events=ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
    local remote=events and events:FindFirstChild("OnMessageDoneFiltering")
    if remote and remote.OnClientEvent then
        track(remote.OnClientEvent:Connect(function(data)
            if type(data)~="table" then return end
            local from=tostring(data.FromSpeaker or "")
            local kind=tostring(data.MessageType or ""):lower()
            local isSystem=(from=="" or from=="System" or kind:find("system",1,true)~=nil)
            PatchSZ.handleSpawnAnnouncement(data.Message,isSystem)
        end))
    end
end)

-- DAY/NIGHT SYNC · UTC auto-calibrated, persisted, override-aware.
Shared.__VYRO_DAYNIGHT_SYNC = {
    cfg = CFG.daynight,
    NIGHT_START_OFFSET = nil,
    nightStartOffset = nil,
    calibrated = false,
    calibrationSource = "uncalibrated",
    calibratedAt = nil,
    cyclePeriod = tonumber(CFG.daynight.cycle_period) or 300,
    nightDuration = tonumber(CFG.daynight.night_duration) or 10,
    lastObservedPhase = nil,
    lastObservedSource = nil,
    lastClockTime = nil,
    lastBrightness = nil,
    lastAttrSignature = nil,
    lastSendAt = 0,
    lastConsoleAt = 0,
    lastCountdownProbeAt = 0,
    desyncCount = 0,
    lastNightTransitionAt = nil,
    lastNightTransitionOffset = nil,
    awaitTransition = false,
    awaitTransitionSince = nil,
    verificationStartedAt = nil,
    verificationMismatchCount = 0,
    verificationTransitionCount = 0,
    verifiedTwoCycles = false,
}

function Shared.__VYRO_DAYNIGHT_SYNC:Modulo(value,modulus)
    modulus=math.max(1,tonumber(modulus) or 300)
    return ((tonumber(value) or 0)%modulus+modulus)%modulus
end

function Shared.__VYRO_DAYNIGHT_SYNC:CircularDistance(a,b,period)
    period=math.max(2,tonumber(period) or tonumber(self.cyclePeriod) or 300)
    local d=math.abs(self:Modulo((tonumber(a) or 0)-(tonumber(b) or 0),period))
    return math.min(d,period-d)
end

function Shared.__VYRO_DAYNIGHT_SYNC:IsTransitionGrace(at)
    if not self.calibrated or self.nightStartOffset==nil then return false end
    local period=math.max(2,tonumber(self.cyclePeriod) or 300)
    local night=math.max(1,math.min(period-1,tonumber(self.nightDuration) or 10))
    local pos=self:Modulo(tonumber(at) or os.time(),period)
    local nightEdge=self:Modulo(self.nightStartOffset,period)
    local dayEdge=self:Modulo(nightEdge+night,period)
    local tolerance=math.max(0,tonumber(self.cfg.transition_tolerance) or 2)
    return self:CircularDistance(pos,nightEdge,period)<=tolerance
        or self:CircularDistance(pos,dayEdge,period)<=tolerance
end

function Shared.__VYRO_DAYNIGHT_SYNC:CalibrationPriority(source,calibrated)
    if calibrated==false then return 0 end
    local s=tostring(source or ""):lower()
    if s:find("^transition:") or s:find("^transition_validated_day:") then return 400 end
    if s:find("ui_countdown",1,true) then return 320 end
    if s:find("runtime_countdown",1,true) then return 280 end
    if s:find("persist",1,true) then return 240 end
    return 200
end

function Shared.__VYRO_DAYNIGHT_SYNC:Log(message)
    local line="["..tostring(os.time()).."] "..tostring(message)
    pcall(function()
        local old=""
        if type(Shared.__VYRO_EXEC._IF)=="function" and Shared.__VYRO_EXEC._IF(self.cfg.log_file) and type(Shared.__VYRO_EXEC._RF)=="function" then
            old=tostring(Shared.__VYRO_EXEC._RF(self.cfg.log_file) or "")
            if #old>24000 then old=old:sub(#old-16000) end
        end
        if type(Shared.__VYRO_EXEC._WF)=="function" then
            Shared.__VYRO_EXEC._WF(self.cfg.log_file,old..((#old>0 and "\n") or "")..line)
        end
    end)
    logLine("DAYNIGHT · "..tostring(message))
end

function Shared.__VYRO_DAYNIGHT_SYNC:Save()
    pcall(function()
        if type(Shared.__VYRO_EXEC._WF)~="function" then return end

        local writeData={
            night_start_offset=self.nightStartOffset,
            calibrated=self.calibrated,
            calibrated_at=self.calibratedAt,
            calibration_source=self.calibrationSource,
            cycle_period=self.cyclePeriod,
            night_duration=self.nightDuration,
            last_night_transition_at=self.lastNightTransitionAt,
            last_night_transition_offset=self.lastNightTransitionOffset,
            verification_started_at=self.verificationStartedAt,
            verification_transition_count=self.verificationTransitionCount,
            verified_two_cycles=self.verifiedTwoCycles,
            saved_at=os.time(),
        }

        -- Wave workspace is shared by every Roblox process. Treat the file as
        -- a confidence-ordered canonical record: a weak countdown/desynced
        -- client must never overwrite a stronger real Lighting transition.
        if type(Shared.__VYRO_EXEC._IF)=="function"
            and type(Shared.__VYRO_EXEC._RF)=="function"
            and Shared.__VYRO_EXEC._IF(self.cfg.config_file)
        then
            local okExisting,existing=pcall(function()
                return game:GetService("HttpService"):JSONDecode(Shared.__VYRO_EXEC._RF(self.cfg.config_file))
            end)
            if okExisting and type(existing)=="table"
                and tonumber(existing.cycle_period)==tonumber(self.cyclePeriod)
            then
                local existingPriority=self:CalibrationPriority(existing.calibration_source,existing.calibrated~=false)
                local currentPriority=self:CalibrationPriority(self.calibrationSource,self.calibrated==true)

                if existingPriority>currentPriority
                    and existing.calibrated~=false
                    and tonumber(existing.night_start_offset)~=nil
                then
                    writeData.night_start_offset=self:Modulo(existing.night_start_offset,self.cyclePeriod)
                    writeData.calibrated=true
                    writeData.calibrated_at=tonumber(existing.calibrated_at)
                    writeData.calibration_source=tostring(existing.calibration_source or "persisted")
                    writeData.last_night_transition_at=tonumber(existing.last_night_transition_at)
                    writeData.last_night_transition_offset=tonumber(existing.last_night_transition_offset)
                    writeData.verification_started_at=tonumber(existing.verification_started_at)
                    writeData.verification_transition_count=tonumber(existing.verification_transition_count) or 0
                    writeData.verified_two_cycles=(existing.verified_two_cycles==true)
                elseif existingPriority==currentPriority and currentPriority>=400 then
                    local existingNightAt=tonumber(existing.last_night_transition_at)
                    local existingNightOffset=tonumber(existing.last_night_transition_offset)
                    local currentNightAt=tonumber(self.lastNightTransitionAt)
                    if existingNightAt and existingNightOffset and currentNightAt then
                        local sameEdgeWindow=math.max(3,(tonumber(self.cfg.transition_tolerance) or 2)+1)
                        if math.abs(existingNightAt-currentNightAt)<=sameEdgeWindow
                            and existingNightAt<currentNightAt
                        then
                            local earlierOffset=self:Modulo(existingNightOffset,self.cyclePeriod)
                            writeData.last_night_transition_at=existingNightAt
                            writeData.last_night_transition_offset=earlierOffset
                            if writeData.night_start_offset~=nil
                                and self:CircularDistance(writeData.night_start_offset,earlierOffset,self.cyclePeriod)<=sameEdgeWindow
                            then
                                writeData.night_start_offset=earlierOffset
                            end
                        end
                    end
                end
            end
        end

        Shared.__VYRO_EXEC._WF(self.cfg.config_file,game:GetService("HttpService"):JSONEncode(writeData))
    end)
end

function Shared.__VYRO_DAYNIGHT_SYNC:Load()
    self.nightStartOffset=nil
    self.calibrated=false
    self.calibrationSource="uncalibrated"
    pcall(function()
        if type(Shared.__VYRO_EXEC._IF)~="function" or type(Shared.__VYRO_EXEC._RF)~="function" then return end
        if not Shared.__VYRO_EXEC._IF(self.cfg.config_file) then return end
        local raw=Shared.__VYRO_EXEC._RF(self.cfg.config_file)
        local decoded=game:GetService("HttpService"):JSONDecode(raw)
        if type(decoded)~="table" then return end
        local p=tonumber(decoded.cycle_period)
        local n=tonumber(decoded.night_duration)
        local o=tonumber(decoded.night_start_offset)
        if p and p>1 then self.cyclePeriod=math.floor(p+0.5) end
        if n and n>0 and n<self.cyclePeriod then self.nightDuration=math.floor(n+0.5) end
        if o then
            self.nightStartOffset=self:Modulo(o,self.cyclePeriod)
            self.NIGHT_START_OFFSET=self.nightStartOffset
            self.calibrated=(decoded.calibrated~=false)
            self.calibratedAt=tonumber(decoded.calibrated_at)
            self.calibrationSource=tostring(decoded.calibration_source or "persisted")
            self.lastNightTransitionAt=tonumber(decoded.last_night_transition_at)
            local lno=tonumber(decoded.last_night_transition_offset)
            if lno then self.lastNightTransitionOffset=self:Modulo(lno,self.cyclePeriod) end
            self.verificationStartedAt=tonumber(decoded.verification_started_at)
            self.verificationTransitionCount=tonumber(decoded.verification_transition_count) or 0
            self.verifiedTwoCycles=(decoded.verified_two_cycles==true)
            self.cfg.night_start_offset=self.nightStartOffset
            self:Log("calibration loaded offset="..tostring(self.nightStartOffset).." source="..self.calibrationSource)
        end
    end)
end

function Shared.__VYRO_DAYNIGHT_SYNC:ReadOverrides()
    local oldPeriod=self.cyclePeriod
    local oldNight=self.nightDuration
    local p=nil
    local n=nil
    pcall(function() p=tonumber(workspace:GetAttribute("AreaEggCyclePeriodSeconds")) end)
    pcall(function() n=tonumber(workspace:GetAttribute("AreaEggCycleDefaultNightSeconds")) end)
    if p and p>1 then self.cyclePeriod=math.max(2,math.floor(p+0.5)) else self.cyclePeriod=tonumber(self.cfg.cycle_period) or 300 end
    if n and n>0 and n<self.cyclePeriod then self.nightDuration=math.floor(n+0.5) else self.nightDuration=math.max(1,math.min(self.cyclePeriod-1,tonumber(self.cfg.night_duration) or 10)) end
    if oldPeriod~=self.cyclePeriod and self.nightStartOffset~=nil then
        self:Log("override cycle_period "..tostring(oldPeriod).."->"..tostring(self.cyclePeriod).." recalibration_required")
        self.nightStartOffset=nil
        self.NIGHT_START_OFFSET=nil
        self.calibrated=false
        self.cfg.night_start_offset=nil
        self.calibrationSource="override_recalibration"
        self.awaitTransition=true
        self.awaitTransitionSince=os.time()
        self.verifiedTwoCycles=false
        self.verificationStartedAt=nil
        self:Save()
    elseif oldNight~=self.nightDuration then
        self:Log("override night_duration "..tostring(oldNight).."->"..tostring(self.nightDuration))
        self:Save()
    end
end

function Shared.__VYRO_DAYNIGHT_SYNC:ObservedPhase()
    local attrPhase=nil
    local attrSource=nil
    local sig={}
    pcall(function()
        for key,value in pairs(workspace:GetAttributes()) do
            local lk=tostring(key):lower()
            if lk:find("night",1,true) or lk:find("day",1,true) or lk:find("phase",1,true) or lk:find("cycle",1,true) then
                sig[#sig+1]=tostring(key).."="..tostring(value)
                if type(value)=="string" then
                    local lv=value:lower()
                    if lv:find("night",1,true) then attrPhase="NIGHT";attrSource="workspace_attr:"..tostring(key)
                    elseif lv:find("day",1,true) then attrPhase="DAY";attrSource="workspace_attr:"..tostring(key) end
                elseif type(value)=="boolean" then
                    if lk:find("night",1,true) then attrPhase=value and "NIGHT" or "DAY";attrSource="workspace_attr:"..tostring(key)
                    elseif lk:find("day",1,true) then attrPhase=value and "DAY" or "NIGHT";attrSource="workspace_attr:"..tostring(key) end
                elseif type(value)=="number" and (value==0 or value==1) then
                    if lk:find("night",1,true) then attrPhase=(value==1) and "NIGHT" or "DAY";attrSource="workspace_attr:"..tostring(key)
                    elseif lk:find("day",1,true) then attrPhase=(value==1) and "DAY" or "NIGHT";attrSource="workspace_attr:"..tostring(key) end
                end
            end
        end
    end)
    table.sort(sig)
    self.lastAttrSignature=table.concat(sig,"|")

    local clock=nil
    local brightness=nil
    pcall(function() clock=tonumber(Lighting.ClockTime) end)
    pcall(function() brightness=tonumber(Lighting.Brightness) end)
    local clockPhase=nil
    if clock then
        clockPhase=(clock>=CFG.DAY_START_CLOCK and clock<CFG.NIGHT_START_CLOCK) and "DAY" or "NIGHT"
    end

    local phase=attrPhase or clockPhase
    local source=attrSource or (clockPhase and "lighting_clock" or nil)
    if not phase and brightness and self.lastBrightness then
        local delta=brightness-self.lastBrightness
        if math.abs(delta)>=0.75 and self.lastObservedPhase then
            phase=(delta<0) and "NIGHT" or "DAY"
            source="lighting_brightness_jump"
        end
    end

    self.lastClockTime=clock
    self.lastBrightness=brightness
    return phase,source,clock,brightness
end

function Shared.__VYRO_DAYNIGHT_SYNC:Calibrate(phase,source,at)
    at=math.floor(tonumber(at) or os.time())
    phase=tostring(phase or ""):upper()
    if phase~="DAY" and phase~="NIGHT" then return false end

    local period=math.max(2,tonumber(self.cyclePeriod) or 300)
    local tolerance=math.max(0,tonumber(self.cfg.transition_tolerance) or 2)
    local candidate
    if phase=="NIGHT" then candidate=self:Modulo(at,period)
    else candidate=self:Modulo(at-self.nightDuration,period) end
    local rawCandidate=candidate

    -- A UTC-global cycle must not drift because one client samples Lighting
    -- one second later. If a new NIGHT edge lands inside the configured
    -- tolerance of an existing strong transition anchor, keep the anchor.
    if phase=="NIGHT"
        and self.calibrated
        and self.nightStartOffset~=nil
        and self:CalibrationPriority(self.calibrationSource,true)>=400
    then
        local anchorDiff=self:CircularDistance(candidate,self.nightStartOffset,period)
        if anchorDiff<=tolerance then
            candidate=self.nightStartOffset
            self:Log("night_transition_validated candidate="..tostring(rawCandidate).." kept_offset="..tostring(candidate).." diff="..tostring(anchorDiff))
        end
    end

    -- NIGHT is the strongest edge because it maps directly to NIGHT_START_OFFSET.
    -- DAY can be observed 1-2 seconds late by Lighting on some servers, so use it
    -- to validate a recent night edge instead of shifting a good global offset.
    if phase=="DAY" and self.lastNightTransitionOffset~=nil then
        local diff=self:CircularDistance(candidate,self.lastNightTransitionOffset,period)
        local recentNight=self.lastNightTransitionAt
            and (at-tonumber(self.lastNightTransitionAt))>=0
            and (at-tonumber(self.lastNightTransitionAt))<=period+5
        if diff<=tolerance then
            self.nightStartOffset=self.lastNightTransitionOffset
            self.NIGHT_START_OFFSET=self.nightStartOffset
            self.calibrated=true
            self.calibratedAt=at
            self.calibrationSource="transition_validated_day:"..tostring(source or "observed")
            self.cfg.night_start_offset=self.nightStartOffset
            self.desyncCount=0
            self.awaitTransition=false
            self.awaitTransitionSince=nil
            self.verificationTransitionCount=(tonumber(self.verificationTransitionCount) or 0)+1
            self:Save()
            self:Log("day_transition_validated candidate="..tostring(candidate).." kept_offset="..tostring(self.nightStartOffset).." diff="..tostring(diff))
            return true
        elseif recentNight then
            self:Log("day_transition_candidate_rejected candidate="..tostring(candidate).." strong_offset="..tostring(self.lastNightTransitionOffset).." diff="..tostring(diff))
            return false
        end
    end

    local oldOffset=self.nightStartOffset
    local offset=candidate
    self.nightStartOffset=offset
    self.NIGHT_START_OFFSET=offset
    self.calibrated=true
    self.calibratedAt=at
    self.calibrationSource=tostring(source or "transition")
    self.cfg.night_start_offset=offset
    self.desyncCount=0
    self.awaitTransition=false
    self.awaitTransitionSince=nil

    if phase=="NIGHT" then
        self.lastNightTransitionAt=at
        self.lastNightTransitionOffset=offset
    end

    local changed=(oldOffset==nil) or self:CircularDistance(oldOffset,offset,period)>tolerance
    if changed or not self.verificationStartedAt then
        self.verificationStartedAt=at
        self.verificationMismatchCount=0
        self.verificationTransitionCount=1
        self.verifiedTwoCycles=false
    else
        self.verificationTransitionCount=(tonumber(self.verificationTransitionCount) or 0)+1
    end

    self:Save()
    self:Log("calibration phase="..phase:lower().." offset="..tostring(offset).." source="..self.calibrationSource)
    return true
end

function Shared.__VYRO_DAYNIGHT_SYNC:CalibrateFromCountdown(targetPhase,seconds,source)
    seconds=tonumber(seconds)
    if not seconds or seconds<0 or seconds>self.cyclePeriod then return false end
    local now=os.time()
    targetPhase=tostring(targetPhase or ""):upper()
    if targetPhase=="NIGHT" then
        self.nightStartOffset=self:Modulo(now+math.floor(seconds+0.5),self.cyclePeriod)
    elseif targetPhase=="DAY" then
        self.nightStartOffset=self:Modulo(now+math.floor(seconds+0.5)-self.nightDuration,self.cyclePeriod)
    else return false end
    self.NIGHT_START_OFFSET=self.nightStartOffset
    self.calibrated=true
    self.calibratedAt=now
    self.calibrationSource=tostring(source or "countdown")
    self.cfg.night_start_offset=self.nightStartOffset
    self.desyncCount=0
    self.awaitTransition=false
    self.awaitTransitionSince=nil
    self.verificationStartedAt=now
    self.verificationMismatchCount=0
    self.verificationTransitionCount=0
    self.verifiedTwoCycles=false
    self:Save()
    self:Log("calibration countdown target="..targetPhase:lower().." offset="..tostring(self.nightStartOffset).." eta="..tostring(math.floor(seconds+0.5)).." source="..self.calibrationSource)
    return true
end

function Shared.__VYRO_DAYNIGHT_SYNC:TryCountdownCalibration(observedPhase)
    if self.calibrated then return false end
    local nowClock=os.clock()
    if nowClock-self.lastCountdownProbeAt<2 then return false end
    self.lastCountdownProbeAt=nowClock

    -- After a real desync with a reliable Lighting/attribute phase, wait for
    -- the next observed edge instead of immediately replacing the offset with
    -- another estimate derived from the same clock.
    if self.awaitTransition and observedPhase then
        local since=tonumber(self.awaitTransitionSince) or os.time()
        if os.time()-since<=math.max(5,tonumber(self.cyclePeriod) or 300)+5 then
            return false
        end
        self.awaitTransition=false
        self.awaitTransitionSince=nil
        self:Log("transition_wait_timeout fallback=countdown")
    end

    -- Do NOT calibrate from VYRO's own derived ETA (lighting_rate,
    -- cycle_period_metadata, etc.). That estimate is downstream of the same
    -- signal and can create a feedback loop. Countdown calibration is accepted
    -- only from an actual game UI countdown below.
    local foundTarget=nil
    local foundSeconds=nil
    pcall(function()
        local gui=LP:FindFirstChildOfClass("PlayerGui")
        if not gui then return end
        for _,obj in ipairs(gui:GetDescendants()) do
            if foundTarget then break end
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text=tostring(obj.Text or ""):lower()
                local target=nil
                if text:find("next",1,true) and text:find("night",1,true) then target="NIGHT"
                elseif text:find("next",1,true) and text:find("day",1,true) then target="DAY" end
                if target then
                    local mm,ss=text:match("(%d+)%s*:%s*(%d+)")
                    local total=nil
                    if mm and ss then total=(tonumber(mm) or 0)*60+(tonumber(ss) or 0)
                    else
                        local mins=tonumber(text:match("(%d+)%s*m"))
                        local secs=tonumber(text:match("(%d+)%s*s"))
                        if mins or secs then total=(mins or 0)*60+(secs or 0) end
                    end
                    if total and total>=0 and total<=self.cyclePeriod then foundTarget=target;foundSeconds=total end
                end
            end
        end
    end)
    if foundTarget then return self:CalibrateFromCountdown(foundTarget,foundSeconds,"ui_countdown") end
    return false
end

function Shared.__VYRO_DAYNIGHT_SYNC:Compute(at)
    at=math.floor(tonumber(at) or os.time())
    local period=math.max(2,tonumber(self.cyclePeriod) or 300)
    local night=math.max(1,math.min(period-1,tonumber(self.nightDuration) or 10))
    local offset=self.calibrated and tonumber(self.nightStartOffset) or 0
    offset=self:Modulo(offset,period)
    local pos=self:Modulo(at,period)
    local sinceNight=self:Modulo(pos-offset,period)
    local isNight=sinceNight<night
    local seconds
    if isNight then seconds=night-sinceNight else seconds=period-sinceNight end
    seconds=math.max(0,math.floor(seconds+0.5))
    return {
        phase=isNight and "NIGHT" or "DAY",
        isNight=isNight,
        secondsUntilPhaseChange=seconds,
        nextChangeTimestamp=at+seconds,
        cycleStartTimestamp=at-pos,
        cyclePeriod=period,
        nightSeconds=night,
        calibrated=self.calibrated==true,
        nightStartOffset=self.calibrated and offset or nil,
        calibrationSource=self.calibrationSource,
    }
end

function Shared.__VYRO_DAYNIGHT_SYNC:Tick()
    self:ReadOverrides()
    local observed,source=self:ObservedPhase()
    local now=os.time()

    if observed and self.lastObservedPhase and observed~=self.lastObservedPhase then
        self:Log("transition="..self.lastObservedPhase:lower().."->"..observed:lower()..", offset_pending")
        self:Calibrate(observed,"transition:"..tostring(source or "observed"),now)
        self:Log("transition="..self.lastObservedPhase:lower().."->"..observed:lower()..", offset="..tostring(self.nightStartOffset))
    elseif not self.calibrated then
        if observed and not self.awaitTransition and (tostring(source or ""):find("lighting",1,true) or tostring(source or ""):find("workspace_attr:",1,true)) then
            self.awaitTransition=true
            self.awaitTransitionSince=now
            self:Log("calibration_waiting_transition observed="..observed:lower().." source="..tostring(source))
        end
        self:TryCountdownCalibration(observed)
    end

    local state=self:Compute(now)
    if self.calibrated and observed and observed~=state.phase then
        if self:IsTransitionGrace(now) then
            self.desyncCount=0
        else
            self.desyncCount=(tonumber(self.desyncCount) or 0)+1
            if self.desyncCount>=math.max(3,tonumber(self.cfg.desync_checks) or 3) then
                self.verificationMismatchCount=(tonumber(self.verificationMismatchCount) or 0)+1
                self:Log("desync observed="..observed:lower().." calculated="..state.phase:lower().." checks="..tostring(self.desyncCount).." recalibration_required")
                self.calibrated=false
                self.nightStartOffset=nil
                self.NIGHT_START_OFFSET=nil
                self.cfg.night_start_offset=nil
                self.calibrationSource="desync_transition_mode"
                self.desyncCount=0
                self.awaitTransition=true
                self.awaitTransitionSince=now
                self.verifiedTwoCycles=false
                self.verificationStartedAt=nil
                self:Save()
                state=self:Compute(now)
            end
        end
    else
        self.desyncCount=0
    end

    if observed then
        self.lastObservedPhase=observed
        self.lastObservedSource=source
    end

    if self.calibrated then
        if not self.verificationStartedAt then
            self.verificationStartedAt=now
            self.verificationMismatchCount=0
            self.verificationTransitionCount=0
        end
        local verifyFor=math.max(tonumber(self.cfg.verify_seconds) or 600,(tonumber(self.cyclePeriod) or 300)*2)
        if not self.verifiedTwoCycles
            and now-tonumber(self.verificationStartedAt)>=verifyFor
            and (tonumber(self.verificationMismatchCount) or 0)==0
            and (tonumber(self.verificationTransitionCount) or 0)>=4
        then
            self.verifiedTwoCycles=true
            self:Log("verified_2_cycles seconds="..tostring(now-tonumber(self.verificationStartedAt)).." transitions="..tostring(self.verificationTransitionCount).." offset="..tostring(self.nightStartOffset))
            self:Save()
        end
    end

    S.phase=(self.calibrated and state.phase) or observed or state.phase
    S.dayNightEtaSeconds=state.secondsUntilPhaseChange
    S.cycleEtaSeconds=state.secondsUntilPhaseChange
    S.cycleEtaSource=self.calibrated and "utc_autocalibrated" or "utc_uncalibrated"
    S.cyclePeriodHint=state.cyclePeriod
    S.cycleNightSecondsHint=state.nightSeconds

    return state
end

Shared.__VYRO_DAYNIGHT_SYNC:Load()

task.spawn(function()
    while Runtime.alive and CFG.daynight.enabled~=false do
        local state=Shared.__VYRO_DAYNIGHT_SYNC:Tick()
        local nowClock=os.clock()
        if nowClock-Shared.__VYRO_DAYNIGHT_SYNC.lastSendAt>=math.max(0.5,tonumber(CFG.daynight.send_interval) or 1) then
            Shared.__VYRO_DAYNIGHT_SYNC.lastSendAt=nowClock
            local now=os.time()
            local payload={
                type="daynight_sync",
                phase=string.lower(state.phase),
                seconds_until_next_change=state.secondsUntilPhaseChange,
                next_change_timestamp=state.nextChangeTimestamp,
                cycle_start_timestamp=state.cycleStartTimestamp,
                calibrated=state.calibrated,
                night_start_offset=state.nightStartOffset,
                cycle_period=state.cyclePeriod,
                night_duration=state.nightSeconds,
                send_interval=tonumber(CFG.daynight.send_interval) or 1,
                calibration_source=state.calibrationSource,
                calibrated_at=Shared.__VYRO_DAYNIGHT_SYNC.calibratedAt,
                verified_two_cycles=Shared.__VYRO_DAYNIGHT_SYNC.verifiedTwoCycles==true,
                timestamp=now,
                -- Legacy aliases retained for the existing relay during rollout.
                isNight=state.isNight,
                secondsUntilChange=state.secondsUntilPhaseChange,
                cyclePeriod=state.cyclePeriod,
                nightSeconds=state.nightSeconds,
                winner=S.cycleWinner,
                account_id=tostring(LP.UserId),
                label=tostring(LP.Name),
                current_job_id=tostring(game.JobId),
            }
            task.spawn(function()
                pcall(function()
                    requestJson("POST",NODE_BASE.."/v1/daynight",payload,nodeHeaders())
                end)
            end)
        end
        if nowClock-Shared.__VYRO_DAYNIGHT_SYNC.lastConsoleAt>=math.max(1,tonumber(CFG.daynight.console_interval) or 5) then
            Shared.__VYRO_DAYNIGHT_SYNC.lastConsoleAt=nowClock
            print("DN_SYNC phase="..string.lower(state.phase)..", next_change_in="..tostring(state.secondsUntilPhaseChange).."s, offset="..tostring(state.nightStartOffset or "UNCALIBRATED"))
        end
        task.wait(math.max(0.2,tonumber(CFG.daynight.monitor_interval) or 0.5))
    end
end)

task.spawn(function()
    while Runtime.alive do
        cycleWatcherTick()
        task.wait(CFG.CYCLE_POLL)
    end
end)

task.spawn(function()
    while Runtime.alive do
        writeStatus()
        refreshStatus()
        task.wait(CFG.STATUS_WRITE_SEC)
    end
end)

task.spawn(function()
    while Runtime.alive do
        refreshNodeConfig(false)
        task.wait(CFG.QUALITY_REFRESH_SEC)
    end
end)

-- Local liveness must never depend on NodeAgent HTTP latency. Under a
-- large fleet sendNodeHeartbeat() can yield for several seconds while the
-- runtime itself is healthy. Keep an independent half-second heartbeat so
-- AutoExecute does not falsely recycle a live runtime during NodeAgent bursts.
task.spawn(function()
    while Runtime.alive do
        Shared.__VYRO_CORE_HEARTBEAT=os.clock()
        task.wait(0.5)
    end
end)

task.spawn(function()
    while Runtime.alive do
        local heartbeatOk,heartbeatErr=pcall(sendNodeHeartbeat)
        if not heartbeatOk then S.lastNodeError="heartbeat:"..tostring(heartbeatErr) end
        if Runtime.jg1ConflictCurrent() and not Runtime.teleporting and not Runtime.collisionBusy
            and nowUnix()-(tonumber(Runtime.lastCollisionAttemptAt) or 0)>=5 then
            Runtime.lastCollisionAttemptAt=nowUnix()
            task.spawn(function() pcall(Runtime.relocateConflict) end)
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while Runtime.alive do
        -- Production scanner: PARKED/RESET_WAIT is a hard no-scan state.
        -- The fleet must wait for authoritative scan_start before touching eggs.
        if S.mode=="parked" then
            if Shared.VYRO_SCANNER_MODE~=true then
                local ok,err=pcall(scanNow,"premium")
                if not ok then
                    S.lastError="parked_scan:"..tostring(err)
                    logLine("PARKED SCAN ERROR · "..tostring(err))
                else
                    pcall(writeSnapshot)
                end
                refreshEggUI()
            end
            refreshStatus()
            writeStatus()
        elseif Shared.VYRO_SCANNER_MODE~=true and S.mode~="hunting" then
            scanNow("premium")
            refreshEggUI()
        end
        local waitSec=(S.mode=="parked" and Shared.VYRO_SCANNER_MODE~=true and Runtime.parkedNestsMissing) and 4 or CFG.PASSIVE_SCAN_SEC
        task.wait(waitSec)
    end
end)

-- Arm teleport persistence as soon as the runtime has finished defining its
-- bootstrap functions. This protects Xenith/Wave from an unexpected teleport
-- that happens before VYRO itself requests the first hop.
do
    Runtime.startupReexecOk,Runtime.startupReexecResult=pcall(armReexec,true)
    Runtime.startupReexecArmed=(Runtime.startupReexecOk and Runtime.startupReexecResult==true)
    if Runtime.startupReexecArmed then
        logLine("REEXEC STARTUP ARMED · "..tostring(S.queueFunction or "queue"))
    else
        logLine("REEXEC STARTUP PENDING · "..tostring(S.reexecError or Runtime.startupReexecResult))
    end
end

Runtime.initialOk,Runtime.initialErr=pcall(function()
    if Shared.VYRO_SCANNER_MODE==true then
        S.cycleFingerprint=readCycleFingerprint()
        S.cycleBaselineReadyAt=os.clock()+CFG.STARTUP_CYCLE_BASELINE
        S.mode="parked"
        setState("PARKED","Esperando prÃ³ximo reset DAY/NIGHT · vigilancia activa")
        logLine("PARKED · vigilancia de ciclo activa · scans de huevos bloqueados hasta scan_start")
        writeStatus()
    else
        scanNow("premium")
        writeSnapshot()
    end
end)

-- A late join uses the CURRENT window immediately; no observed edge is required.
function Runtime.wakeCurrentCycle(reason)
    if Shared.VYRO_SCANNER_MODE~=true then return false end
    local now=nowUnix()
    local gen,scanStart,endAt,epoch=Runtime.cycleWindow(now)
    S.fleetCycleGeneration=gen
    S.fleetCycleEpoch=epoch
    S.fleetScanStart=scanStart
    S.fleetCycleEnd=endAt
    if now<scanStart or not Runtime.cycleDayReady() then
        if S.mode~="parked" or S.state~="RESET_WAIT" then
            Runtime.huntToken=nil
            Runtime.huntLoopRunning=false
            Runtime.cycleScanResult=nil
            Runtime.cycleScanAck=nil
            S.mode="parked"
            S.huntEnd=nil
            setState("RESET_WAIT","Esperando reinicio y huevos nuevos en este servidor")
            writeStatus()
        end
        return false
    end
    S.fleetCyclePhase="day"
    if S.mode~="hunting" or tonumber(S.huntEnd)~=endAt then
        local ok,started=pcall(beginHunt,reason.." #"..tostring(gen),true,endAt-now)
        if ok and started~=false then
            S.huntEnd=endAt
            S.huntStartedAt=scanStart
            S.first10EndsAt=scanStart+10
            S.testDuration=CFG.HUNT_SECONDS
            saveState()
            writeStatus()
            logLine(string.format("CURRENT CYCLE WAKE · gen=%s · late=%.2fs",tostring(gen),math.max(0,now-scanStart)))
            return true
        elseif not ok then
            S.lastError="current_cycle_wake:"..tostring(started)
        end
    end
    return false
end
if Shared.VYRO_SCANNER_MODE==true then
    Runtime.wakeCurrentCycle("Landing current cycle")
    task.spawn(function()
        while Runtime.alive do
            Runtime.wakeCurrentCycle("Current cycle")
            task.wait(0.20)
        end
    end)
end

-- Production scanner mode is reset-gated. The scanner remains on its current
-- server between cycles and a real DAY<->NIGHT edge calls beginHunt() above.
-- This avoids revisiting already-looted servers for the rest of the cycle.
if Shared.VYRO_SCANNER_MODE==true then
    logLine("RESET GATE ARMED Â· waiting for DAY/NIGHT edge")
end
if not Runtime.initialOk then
    S.lastError="initial_scan:"..tostring(Runtime.initialErr)
    logLine("INITIAL SCAN ERROR ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(Runtime.initialErr))
end
pcall(refreshEggUI)
pcall(refreshStatus)
pcall(writeStatus)

logLine("CORE READY ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..CFG.VERSION)
logLine("SUPER PRIME: only QUALIFIED premium WORLD eggs go to cloud.")
logLine("QUALITY: rarity + scale + mutations; bad servers are SKIPped immediately.")
logLine("AUTO UPDATE: runtime refreshes from local Node Agent before every hop.")
logLine("4.2.6: fresh reexec + continuous diversity + biggest-first premium ranking.")
logLine("CENSUS MANUAL: disabled in production unless requested; player-base assets never enter cloud.")
logLine("FAIL-CLOSED: only a resolved natural nest can become QUALIFIED/cloud.")
logLine("FAIL-CLOSED: unknown premium fingerprints are logged but never published to buyers.")
logLine("TEST 3 MIN: scan ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ hop ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ scan ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ hop durante 180s.")
logLine("Buyer/VPS bridge: "..SNAPSHOT_FILE.." + "..STATUS_FILE)

-- AUTO CENSUS: diagnostic-only. Disabled by default in production.
if CFG.AUTO_CENSUS then
task.delay(2.5,function()
    if not Runtime.alive then return end
    setState("CENSUS","Generando VYRO_CENSUS_RESULT.txt")
    local ok,report=pcall(PatchSZ.buildCensusReport)
    if ok and type(report)=="string" then
        if type(Shared.__VYRO_EXEC._WF)=="function" then
            local saved=pcall(function() Shared.__VYRO_EXEC._WF(CENSUS_FILE,report) end)
            if saved then
                logLine("AUTO CENSUS SAVED -> "..CENSUS_FILE.." ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· "..tostring(#report).." chars")
            else
                S.lastError="AUTO_CENSUS_WRITEFILE_FAIL"
                logLine("AUTO CENSUS ERROR: writefile fallo")
            end
        else
            S.lastError="AUTO_CENSUS_WRITEFILE_UNAVAILABLE"
            logLine("AUTO CENSUS ERROR: writefile no disponible")
        end
        Shared.VYRO_FULL_CENSUS_LAST=report
    else
        S.lastError="AUTO_CENSUS_BUILD:"..tostring(report)
        logLine("AUTO CENSUS ERROR: "..tostring(report))
    end
    setState(S.mode=="hunting" and "HUNTING" or "READY","Auto Census terminado")
    refreshEggUI()
    refreshStatus()
    writeStatus()
end)
end


