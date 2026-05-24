----------------------------------------------------------------------
-- ZugZug M+ — Settings Panel
-- Registered under "ZugZug M+" in the Blizzard AddOns options. Each
-- feature is its own toggle; all default off.
----------------------------------------------------------------------

local MPlus = _G.ZugZugMPlus

local function CreateToggle(parent, x, y, label, dbKey, subtitle)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.text:SetText(label .. (subtitle and ("  |cff888888" .. subtitle .. "|r") or ""))
  cb:SetChecked(ZugZugMPlusDB[dbKey])
  cb:SetScript("OnClick", function(self)
    ZugZugMPlusDB[dbKey] = self:GetChecked()
  end)
  return cb
end

local function CreateSettingsPanel()
  local canvas = CreateFrame("Frame", "ZugZugMPlusSettingsPanel")
  canvas.name = "ZugZug M+"

  local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("|cff8fbf3fZugZug|r M+ Settings")

  local sub = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  sub:SetText("Mythic+ tools and tweaks — each feature is off by default.")

  -- BNet status broadcast
  local bnToggle = CreateToggle(canvas, 16, -70, "BNet Status Broadcast", "bnStatus",
    "(updates your Battle.net custom message when a key starts)")

  local bnNote = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  bnNote:SetPoint("TOPLEFT", bnToggle, "BOTTOMLEFT", 4, -2)
  bnNote:SetText("|cff666666Posts once at key start with start/estimated finish time. Restores your previous message after the key ends.|r")

  return canvas
end

----------------------------------------------------------------------
-- Register with the Settings system
----------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  local ok, err = pcall(function()
    local panel = CreateSettingsPanel()
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    MPlus.settingsCategory = category
  end)
  if not ok then
    print("|cff8fbf3fZugZug M+:|r Settings panel failed: " .. tostring(err))
  end
  self:UnregisterEvent("PLAYER_LOGIN")
end)

----------------------------------------------------------------------
-- /zzmp slash command — open settings + show toggles state
----------------------------------------------------------------------

SLASH_ZUGZUGMPLUS1 = "/zzmp"
SLASH_ZUGZUGMPLUS2 = "/mplus"
SlashCmdList["ZUGZUGMPLUS"] = function(msg)
  local cmd = (msg and msg:match("^(%S+)") or ""):lower()
  if cmd == "settings" or cmd == "options" or cmd == "config" or cmd == "" then
    local ok = pcall(function()
      if MPlus.settingsCategory then
        Settings.OpenToCategory(MPlus.settingsCategory:GetID())
      else
        Settings.OpenToCategory("ZugZug M+")
      end
    end)
    if not ok then print("|cff8fbf3fZugZug M+:|r Could not open settings.") end
    return
  end
  if cmd == "debug" then
    ZugZugMPlusDB.mpDebug = not ZugZugMPlusDB.mpDebug
    print("|cff8fbf3fZugZug M+:|r debug "
      .. (ZugZugMPlusDB.mpDebug and "|cff4DFF4Don|r" or "|cffFF6666off|r"))
    return
  end
  if cmd == "refresh" then
    if MPlus.refreshStatus then
      MPlus.refreshStatus()
      print("|cff8fbf3fZugZug M+:|r status refreshed (broadcast updated if in a key + toggle on)")
    else
      print("|cff8fbf3fZugZug M+:|r refresh unavailable (Status module not loaded)")
    end
    return
  end
  if cmd == "forcebcast" or cmd == "force" then
    if not MPlus.sendStatusNow then
      print("|cff8fbf3fZugZug M+:|r forcebcast unavailable (Status module not loaded)")
      return
    end
    local rest = msg:match("^%S+%s+(.+)$")
    local text = rest or ("ZZMP test " .. date("%H:%M:%S"))
    local bn = MPlus.sendStatusNow(text)
    print(string.format("|cff8fbf3fZugZug M+:|r forced broadcast: '%s'  (bn=%s)", text, tostring(bn)))
    if not ZugZugMPlusDB.bnStatus then
      print("  |cffFF6666BNet toggle is off — nothing was sent.|r")
    end
    return
  end
  if cmd == "status" then
    print("|cff8fbf3fZugZug M+:|r feature toggles —")
    print("  BNet Status: " .. (ZugZugMPlusDB.bnStatus and "|cff4DFF4Don|r" or "|cffFF6666off|r"))
    return
  end
  if cmd == "testbcast" or cmd == "testbroadcast" then
    local s = MPlus.state
    print("|cff8fbf3fZugZug M+:|r diagnostic —")
    print(string.format("  inActiveKey=%s · keyName=%s · keyLevel=%s · keyTimeLimit=%s",
      tostring(s.inActiveKey), tostring(s.keyName), tostring(s.keyLevel), tostring(s.keyTimeLimit)))
    print(string.format("  setting bnStatus=%s · API BNSetCustomMessage=%s",
      tostring(ZugZugMPlusDB.bnStatus), tostring(BNSetCustomMessage ~= nil)))
    if BNSetCustomMessage then
      local ok, err = pcall(BNSetCustomMessage, "ZZMP test " .. date("%H:%M:%S"))
      print("  BNSetCustomMessage call: ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
    end
    return
  end
  print("|cff8fbf3fZugZug M+|r — Mythic+ tools")
  print("  /zzmp settings  — open the settings panel")
  print("  /zzmp status    — show which features are on")
  print("  /zzmp refresh   — re-fire the key-start broadcast for the current key")
  print("  /zzmp forcebcast [text] — push text to BNet (works outside a key)")
  print("  /zzmp testbcast — diagnose the BNet broadcast API")
  print("  /zzmp debug     — toggle verbose event logging")
end
