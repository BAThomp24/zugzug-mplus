----------------------------------------------------------------------
-- ZugZug M+ — Core
-- Shared key state, dungeon-info cache, and event wiring used by the
-- TimeReply and Status feature modules.
----------------------------------------------------------------------

local ADDON_NAME = ...

ZugZugMPlusDB = ZugZugMPlusDB or {}

-- Public addon namespace. Feature modules read MPlus.state and call MPlus.fire().
local MPlus = {}
_G.ZugZugMPlus = MPlus
MPlus.addonName = ADDON_NAME

----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------

local DEFAULTS = {
  bnStatus = false,      -- broadcast key start to your Battle.net custom message
}
MPlus.DEFAULTS = DEFAULTS

local function ensureDefaults()
  for k, v in pairs(DEFAULTS) do
    if ZugZugMPlusDB[k] == nil then ZugZugMPlusDB[k] = v end
  end
end

----------------------------------------------------------------------
-- Helpers (shared)
----------------------------------------------------------------------

function MPlus.safeNum(v)
  return (type(v) == "number") and v or nil
end

function MPlus.formatTime(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

----------------------------------------------------------------------
-- Shared key state. Feature modules read this; Core owns the updates.
----------------------------------------------------------------------

MPlus.state = {
  inActiveKey       = false,
  keyStartTime      = nil,     -- GetTime() at CHALLENGE_MODE_START
  keyName           = nil,     -- dungeon name (plain string)
  keyLevel          = nil,     -- keystone level (plain number)
  keyTimeLimit      = nil,     -- seconds (plain number)
  instanceEnterTime = nil,
  bossesKilled      = 0,
}

----------------------------------------------------------------------
-- Lightweight pub/sub so feature modules can react to lifecycle events
-- without having to register their own challenge-mode handlers.
----------------------------------------------------------------------

local subscribers = {}

function MPlus.on(eventName, fn)
  subscribers[eventName] = subscribers[eventName] or {}
  table.insert(subscribers[eventName], fn)
end

function MPlus.fire(eventName, ...)
  local list = subscribers[eventName]
  if not list then return end
  for _, fn in ipairs(list) do
    pcall(fn, ...)
  end
end

----------------------------------------------------------------------
-- Dungeon-info cache: populated from clean reads (out of lockdown) so
-- the time limit + name stay available even if live calls go secret.
----------------------------------------------------------------------

local function cacheMapInfo()
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo) then return end
  ZugZugMPlusDB.mapInfoCache = ZugZugMPlusDB.mapInfoCache or {}
  local ok, maps = pcall(C_ChallengeMode.GetMapTable)
  if not ok or type(maps) ~= "table" then return end
  for _, mapID in ipairs(maps) do
    local ok2, name, _, timeLimit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if ok2 and MPlus.safeNum(timeLimit) and timeLimit > 0 then
      ZugZugMPlusDB.mapInfoCache[mapID] = { name = name, limit = timeLimit }
    end
  end
end

--- Capture the active key's static info into plain locals on the state table.
local function captureKeyInfo()
  local s = MPlus.state
  s.keyStartTime = GetTime()
  s.inActiveKey = true
  s.keyName, s.keyLevel, s.keyTimeLimit = nil, nil, nil
  s.bossesKilled = 0

  local mapID
  local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
  if ok then mapID = MPlus.safeNum(id) end

  local okL, lvl = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
  if okL then s.keyLevel = MPlus.safeNum(lvl) end

  if mapID then
    local okI, name, _, timeLimit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if okI then
      s.keyName = (type(name) == "string") and name or s.keyName
      s.keyTimeLimit = MPlus.safeNum(timeLimit) or s.keyTimeLimit
    end
    local cached = ZugZugMPlusDB.mapInfoCache and ZugZugMPlusDB.mapInfoCache[mapID]
    if cached then
      s.keyName = s.keyName or cached.name
      s.keyTimeLimit = s.keyTimeLimit or cached.limit
    end
  end
end

----------------------------------------------------------------------
-- Lifecycle events
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("CHALLENGE_MODE_RESET")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("BOSS_KILL")
frame:RegisterEvent("ENCOUNTER_END")
frame:SetScript("OnEvent", function(_, event, arg1, ...)
  if ZugZugMPlusDB and ZugZugMPlusDB.mpDebug then
    print("|cffFFAA00ZZMP evt:|r " .. tostring(event)
      .. (arg1 ~= nil and (" arg1=" .. tostring(arg1)) or ""))
  end
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    ensureDefaults()
    return
  end

  if event == "PLAYER_LOGIN" then
    cacheMapInfo()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    local inInstance, instanceType = IsInInstance()
    local s = MPlus.state
    if inInstance and instanceType == "party" then
      s.instanceEnterTime = s.instanceEnterTime or GetTime()
      -- Recover key state if we reloaded mid-key
      if not s.inActiveKey then
        local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and MPlus.safeNum(id) then
          captureKeyInfo()
          -- Fire keyStart so feature modules can do their setup (broadcast
          -- ticker, etc.) when we recover into an already-running key.
          MPlus.fire("keyStart")
        end
      end
    else
      s.instanceEnterTime = nil
      s.inActiveKey = false
      s.keyStartTime = nil
      -- Outside any dungeon → refresh the cache
      cacheMapInfo()
    end
    return
  end

  if event == "CHALLENGE_MODE_START" then
    captureKeyInfo()
    MPlus.state.instanceEnterTime = GetTime()
    MPlus.fire("keyStart")
    return
  end

  if event == "BOSS_KILL" or event == "ENCOUNTER_END" then
    -- arg1 = encounterID for both events.
    -- ENCOUNTER_END's 4th vararg is the `success` flag; BOSS_KILL always succeeded.
    local encounterID = arg1
    local success = (event == "ENCOUNTER_END") and select(4, ...) or 1
    if MPlus.state.inActiveKey and success == 1 then
      -- Dedupe: BOSS_KILL and ENCOUNTER_END both fire for the same M+ boss.
      -- Skip if we already counted this encounterID in the last 5 seconds.
      local now = GetTime()
      MPlus.state._lastKillID = MPlus.state._lastKillID or {}
      local last = MPlus.state._lastKillID[encounterID]
      if not last or (now - last) > 5 then
        MPlus.state._lastKillID[encounterID] = now
        MPlus.state.bossesKilled = MPlus.state.bossesKilled + 1
        MPlus.fire("bossKill")
      end
    end
    return
  end

  if event == "CHALLENGE_MODE_COMPLETED" then
    MPlus.fire("keyComplete")
    MPlus.state.inActiveKey = false
    MPlus.state.keyStartTime = nil
    return
  end

  if event == "CHALLENGE_MODE_RESET" then
    MPlus.fire("keyReset")
    MPlus.state.inActiveKey = false
    MPlus.state.keyStartTime = nil
    return
  end
end)
