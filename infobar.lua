-- SnapUI info bars: ElvUI-style datatext bars. Up to three bars ("Info bar 1-3"), each with
-- 1-8 slots; every slot shows one datatext (FPS, latency, gold, durability, bag space, clock,
-- XP, zone, coordinates, friends, guild, talents, memory). Hovering shows details, clicking
-- opens the matching window.

local S = SnapUI
local bars = {}

-- [[ datatexts ]] --
local function Color(text)
  return "|cff" .. string.format("%02x%02x%02x", S.ACCENT[1] * 255, S.ACCENT[2] * 255, S.ACCENT[3] * 255) .. text .. "|r"
end

local function MoneyText(c)
  local g, sv, cc = math.floor(c / 10000), math.floor(math.mod(c, 10000) / 100), math.mod(c, 100)
  if g > 0 then return g .. "|cffffd700g|r " .. sv .. "|cffc7c7cfs|r" end
  if sv > 0 then return sv .. "|cffc7c7cfs|r " .. cc .. "|cffeda55fc|r" end
  return cc .. "|cffeda55fc|r"
end

-- lowest durability across equipped items, read off their tooltips (1.12 has no API for it)
local scan
local function Durability()
  if not scan then
    scan = CreateFrame("GameTooltip", "SnapUIScanTip", nil, "GameTooltipTemplate")
  end
  local lowest, worst = 100, nil
  for slot = 1, 18 do
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    if scan:SetInventoryItem("player", slot) then
      for i = 1, scan:NumLines() do
        local line = getglobal("SnapUIScanTipTextLeft" .. i)
        local text = line and line:GetText()
        local _, _, cur, max = string.find(text or "", "(%d+) / (%d+)")
        if cur and string.find(text, "urability") then
          local pct = math.floor(tonumber(cur) / math.max(1, tonumber(max)) * 100)
          if pct < lowest then lowest, worst = pct, slot end
          break
        end
      end
    end
  end
  return lowest, worst
end

local function BagSpace()
  local free, total = 0, 0
  for bag = 0, 4 do
    local n = GetContainerNumSlots(bag) or 0
    total = total + n
    for slot = 1, n do
      if not GetContainerItemInfo(bag, slot) then free = free + 1 end
    end
  end
  return free, total
end

local startMoney
local durCache, durAt = 100, -100

S.DATATEXTS = {
  { "fps", "FPS", function() return Color(math.floor(GetFramerate() + 0.5)) .. " fps" end },
  { "latency", "Latency", function() local _, _, lag = GetNetStats(); return Color(lag) .. " ms" end },
  { "system", "FPS + latency", function()
    local _, _, lag = GetNetStats()
    return Color(math.floor(GetFramerate() + 0.5)) .. " fps  " .. Color(lag) .. " ms"
  end, function() collectgarbage() end },
  { "memory", "Addon memory", function() return Color(string.format("%.1f", gcinfo() / 1024)) .. " MB" end,
    function() collectgarbage(); S.Print("memory cleaned up") end },
  { "gold", "Gold", function() return MoneyText(GetMoney()) end, function() OpenAllBags() end,
    function(tip)
      local diff = GetMoney() - (startMoney or GetMoney())
      tip:AddDoubleLine("This session", (diff < 0 and "-" or "") .. MoneyText(math.abs(diff)), 1, 1, 1, 1, 1, 1)
    end },
  { "durability", "Durability", function()
    if GetTime() - durAt > 10 then durCache, durAt = Durability(), GetTime() end
    local c = durCache < 25 and "|cffff4040" or (durCache < 50 and "|cffffcc40" or "")
    return "Dur " .. c .. durCache .. "%|r"
  end, function() ToggleCharacter("PaperDollFrame") end },
  { "bags", "Bag space", function() local free, total = BagSpace(); return "Bags " .. Color(free) .. "/" .. total end,
    function() OpenAllBags() end },
  { "time", "Clock", function() return Color(date("%H:%M")) end, nil,
    function(tip)
      local h, m = GetGameTime()
      tip:AddDoubleLine("Server time", string.format("%02d:%02d", h, m), 1, 1, 1, 1, 1, 1)
      tip:AddDoubleLine("Local time", date("%H:%M"), 1, 1, 1, 1, 1, 1)
    end },
  { "xp", "Experience", function()
    if UnitLevel("player") >= (MAX_PLAYER_LEVEL or 60) then return "Max level" end
    local xp, max = UnitXP("player"), math.max(1, UnitXPMax("player"))
    local rested = GetXPExhaustion() or 0
    return "XP " .. Color(math.floor(xp / max * 100) .. "%") .. (rested > 0 and (" |cff6080ff+" .. math.floor(rested / max * 100) .. "%|r") or "")
  end, nil, function(tip)
    tip:AddDoubleLine("XP", UnitXP("player") .. " / " .. UnitXPMax("player"), 1, 1, 1, 1, 1, 1)
    tip:AddDoubleLine("Rested", tostring(GetXPExhaustion() or 0), 1, 1, 1, 1, 1, 1)
  end },
  { "zone", "Zone", function() return Color(GetMinimapZoneText() or "") end, function() ToggleWorldMap() end },
  { "coords", "Coordinates", function()
    local x, y = GetPlayerMapPosition("player")
    if not x or (x == 0 and y == 0) then return "--, --" end
    return Color(string.format("%.1f, %.1f", x * 100, y * 100))
  end, function() ToggleWorldMap() end },
  { "friends", "Friends", function()
    local online = 0
    for i = 1, GetNumFriends() do
      local _, _, _, _, connected = GetFriendInfo(i)
      if connected then online = online + 1 end
    end
    return "Friends " .. Color(online)
  end, function() ToggleFriendsFrame(1) end },
  { "guild", "Guild", function()
    if not GetGuildInfo("player") then return "No guild" end
    local online = 0
    for i = 1, GetNumGuildMembers() do
      local _, _, _, _, _, _, _, _, connected = GetGuildRosterInfo(i)
      if connected then online = online + 1 end
    end
    return "Guild " .. Color(online)
  end, function() ToggleFriendsFrame(3) end },
  { "talents", "Talents", function()
    local parts = {}
    for t = 1, (GetNumTalentTabs and GetNumTalentTabs() or 0) do
      local _, _, points = GetTalentTabInfo(t)
      table.insert(parts, tostring(points or 0))
    end
    return "Spec " .. Color(table.concat(parts, "/"))
  end, function() ToggleTalentFrame() end },
  { "none", "(empty)", function() return "" end },
}
local BY_KEY = {}
local CHOICES = {}
for _, d in ipairs(S.DATATEXTS) do
  BY_KEY[d[1]] = d
  table.insert(CHOICES, { d[1], d[2] })
end

-- [[ bars ]] --
local function UpdateBar(bar)
  for i, slot in ipairs(bar.slots) do
    if slot:IsShown() then
      local d = BY_KEY[bar.s.slots[i] or "none"] or BY_KEY.none
      local ok, text = pcall(d[3])
      slot.text:SetText(ok and text or "?")
    end
  end
end

local function LayoutBar(bar)
  local s = bar.s
  bar.frame:SetWidth(s.width)
  bar.frame:SetHeight(s.height)
  if s.transparent then
    bar.frame:SetBackdropColor(0, 0, 0, 0)
    bar.frame:SetBackdropBorderColor(0, 0, 0, 0)
  else
    S.Panel(bar.frame, s.alpha)
  end
  local w = s.width / s.count
  for i, slot in ipairs(bar.slots) do
    if i <= s.count then
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", (i - 1) * w, 0)
      slot:SetWidth(w)
      slot:SetHeight(s.height)
      S.SetFont(slot.text, s.textSize)
      slot:Show()
    else
      slot:Hide()
    end
  end
  S:Fit(bar.holder, bar.frame)
  if s.enabled then bar.frame:Show() else bar.frame:Hide() end
  UpdateBar(bar)
end

local function SlotOnEnter()
  local bar, i = this.bar, this.index
  local d = BY_KEY[bar.s.slots[i] or "none"]
  if not d or d[1] == "none" then return end
  GameTooltip:SetOwner(this, "ANCHOR_TOP")
  GameTooltip:SetText(d[2])
  if d[5] then d[5](GameTooltip) end
  if d[4] then GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7) end
  GameTooltip:Show()
end

local function CreateBar(n, default)
  local key = "info" .. n
  local bar = { key = key, slots = {} }
  local defaults = { enabled = false, width = 420, height = 20, count = 4, alpha = 0.85, transparent = false, textSize = 12,
    slots = { "system", "durability", "bags", "gold", "time", "xp", "coords", "friends" } }
  bar.s = S:Settings("frames", key, defaults)
  bar.holder = S:Holder(key, "Info bar " .. n, default, {})
  bar.holder.isOff = function() return not bar.s.enabled end
  bar.frame = CreateFrame("Frame", "SnapUI_" .. key, bar.holder)
  bar.frame:SetPoint("TOPLEFT", bar.holder, "TOPLEFT", 0, 0)
  bar.frame:SetFrameStrata("LOW")
  for i = 1, 8 do
    local slot = CreateFrame("Button", nil, bar.frame)
    slot.bar, slot.index = bar, i
    slot.text = S.Text(slot, 12, "CENTER")
    slot.text:SetAllPoints(slot)
    slot:SetScript("OnEnter", SlotOnEnter)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot:SetScript("OnClick", function()
      local d = BY_KEY[this.bar.s.slots[this.index] or "none"]
      if d and d[4] then d[4]() end
    end)
    bar.slots[i] = slot
  end

  local s = bar.s
  local opts = bar.holder.options
  local function Num(label, k, min, max, step)
    table.insert(opts, { label = label, get = function() return s[k] end, set = function(v) s[k] = v; LayoutBar(bar) end, min = min, max = max, step = step })
  end
  table.insert(opts, { label = "Enabled", toggle = true, get = function() return s.enabled end, set = function(v) s.enabled = v; LayoutBar(bar) end })
  Num("Width", "width", 60, 1600, 10)
  Num("Height", "height", 12, 40, 1)
  Num("Slots", "count", 1, 8, 1)
  Num("Text size", "textSize", 8, 20, 1)
  Num("Opacity", "alpha", 0, 1, 0.05)
  table.insert(opts, { label = "No background", toggle = true, get = function() return s.transparent end, set = function(v) s.transparent = v; LayoutBar(bar) end })
  for i = 1, 8 do
    local slot = i
    table.insert(opts, { label = "Slot " .. slot, choices = CHOICES,
      get = function() return s.slots[slot] or "none" end, set = function(v) s.slots[slot] = v; UpdateBar(bar) end })
  end

  bars[n] = bar
  LayoutBar(bar)
  return bar
end

S:RegisterModule("infobar", function()
  startMoney = GetMoney()
  CreateBar(1, { "BOTTOM", nil, 0, 0 })
  CreateBar(2, { "TOP", nil, 0, 0 })
  CreateBar(3, { "BOTTOMLEFT", nil, 0, 0 })
  local t = 0
  local ticker = CreateFrame("Frame")
  ticker:SetScript("OnUpdate", function()
    t = t + arg1
    if t < 1 then return end
    t = 0
    for _, bar in pairs(bars) do
      if bar.s.enabled then UpdateBar(bar) end
    end
  end)
  for _, e in ipairs({ "PLAYER_MONEY", "BAG_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "UPDATE_INVENTORY_ALERTS" }) do
    ticker:RegisterEvent(e)
  end
  ticker:SetScript("OnEvent", function()
    if event == "UPDATE_INVENTORY_ALERTS" then durAt = -100 end
    for _, bar in pairs(bars) do
      if bar.s.enabled then UpdateBar(bar) end
    end
  end)
end, "Info bars", "Up to three ElvUI-style datatext bars: FPS, latency, gold, durability, bags, clock and more.")
