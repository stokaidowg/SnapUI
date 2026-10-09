-- SnapUI party and raid frames, Grid style: small class-coloured cells with the name,
-- missing health, a thin mana bar, a white border on your target, a coloured border and
-- icon for debuffs you can dispel, and fading when out of range.
-- Party and raid each have their own holder; party hides while you're in a raid.

local S = SnapUI

local DISPEL = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }
local CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "DRUID", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "SHAMAN" }

-- [[ dispels ]] --
-- what each removal spell takes off; the spell book says which of them you know
local CURES = {
  ["Purify"] = { "Poison", "Disease" }, ["Cleanse"] = { "Poison", "Disease", "Magic" },
  ["Cure Poison"] = { "Poison" }, ["Abolish Poison"] = { "Poison" },
  ["Cure Disease"] = { "Disease" }, ["Abolish Disease"] = { "Disease" },
  ["Remove Curse"] = { "Curse" }, ["Remove Lesser Curse"] = { "Curse" },
  ["Dispel Magic"] = { "Magic" },
}
local canCure, knowsCure = {}, false

local function ScanCures()
  canCure, knowsCure = {}, false
  local i = 1
  while true do
    local name = GetSpellName(i, BOOKTYPE_SPELL)
    if not name then break end
    for _, t in ipairs(CURES[name] or {}) do
      canCure[t] = true
      knowsCure = true
    end
    i = i + 1
  end
end

-- the type of the first debuff on `unit` that you can remove, or nil
local function Dispellable(unit)
  if not knowsCure then
    -- no removal spell found by name (another client language?): the client's own filter
    local tex, _, dtype = UnitDebuff(unit, 1, 1)
    return tex and (dtype or "")
  end
  for i = 1, 16 do
    local tex, _, dtype = UnitDebuff(unit, i)
    if not tex then break end
    if dtype and canCure[dtype] then return dtype end
  end
end

-- [[ range ]] --
local function InRange(unit)
  if UnitIsUnit(unit, "player") then
    return true
  end
  if UnitXP then
    local ok, d = pcall(UnitXP, "distanceBetween", "player", unit)
    if ok and type(d) == "number" then
      return d <= 40
    end
  end
  return CheckInteractDistance(unit, 4)
end

-- cut a name to what fits in a cell (about 7 units a letter at the cell font size), or to
-- a set number of letters
local function FitName(name, width, letters)
  local max = math.max(3, math.floor((width - 4) / 7))
  if letters and letters > 0 then
    max = math.min(max, letters)
  end
  if name and string.len(name) > max then
    return string.sub(name, 1, max)
  end
  return name
end

-- [[ cells ]] --
local function CreateCell(parent)
  local c = CreateFrame("Button", nil, parent)
  S.Backdrop(c, 0.9)
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  c.health = S.StatusBar(c)
  c.health:SetPoint("TOPLEFT", 1, -1)
  c.power = S.StatusBar(c)
  c.power:SetPoint("BOTTOMLEFT", 1, 1)
  c.power:SetPoint("BOTTOMRIGHT", -1, 1)
  c.power:SetHeight(3)
  c.health:SetPoint("BOTTOMRIGHT", c.power, "TOPRIGHT", 0, 1)

  c.name = S.Text(c.health.over, 12, "CENTER")
  c.name:SetPoint("CENTER", 0, 5)
  c.status = S.Text(c.health.over, 11, "CENTER")
  c.status:SetPoint("TOP", c.name, "BOTTOM", 0, -1)

  -- a small square in the top-right corner, in the debuff type's colour, when you can
  -- remove one of their debuffs (black edge so it shows on any health colour)
  c.debuff = c.health.over:CreateTexture(nil, "OVERLAY")
  c.debuff:SetTexture(0, 0, 0, 1)
  c.debuff:SetWidth(10)
  c.debuff:SetHeight(10)
  c.debuff:SetPoint("TOPRIGHT", -1, -1)
  c.debuff:Hide()
  c.debuffFill = c.health.over:CreateTexture(nil, "OVERLAY")
  c.debuffFill:SetPoint("TOPLEFT", c.debuff, "TOPLEFT", 1, -1)
  c.debuffFill:SetPoint("BOTTOMRIGHT", c.debuff, "BOTTOMRIGHT", -1, 1)
  c.debuffFill:Hide()

  -- tank / healer (roles.lua)
  c.role = c.health.over:CreateTexture(nil, "OVERLAY")
  c.role:SetWidth(12)
  c.role:SetHeight(12)
  c.role:SetPoint("TOPLEFT", c.health, "TOPLEFT", 1, -1)
  c.role:Hide()

  c:SetScript("OnClick", function()
    local unit = this.unit
    if not unit or S:IsEditing() then
      return
    end
    if SpellIsTargeting() then
      SpellTargetUnit(unit)
    elseif CursorHasItem() then
      DropItemOnUnit(unit)
    elseif arg1 == "RightButton" and IsAltKeyDown() and S.CycleRole then
      S.CycleRole(unit)
    elseif arg1 == "RightButton" then
      local _, _, n = string.find(unit, "^party(%d)$")
      local menu = n and getglobal("PartyMemberFrame" .. n .. "DropDown")
      if menu then
        ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
      else
        TargetUnit(unit)
      end
    else
      TargetUnit(unit)
    end
  end)
  c:SetScript("OnEnter", function()
    if not this.unit then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    GameTooltip:SetUnit(this.unit)
    if this.showRoles and S.RoleText then
      GameTooltip:AddLine(S.RoleText(this.unit), 0.6, 0.8, 1)
      GameTooltip:AddLine("Alt-right-click to change", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
    if SetMouseoverUnit then SetMouseoverUnit(this.unit) end
  end)
  c:SetScript("OnLeave", function()
    GameTooltip:Hide()
    if SetMouseoverUnit then SetMouseoverUnit("") end
  end)
  c:Hide()
  return c
end

local function UpdateCell(c)
  local unit = c.unit
  if not unit then
    return
  end
  if c.preview then
    return
  end
  if not UnitExists(unit) then
    c:Hide()
    return
  end

  local hp, max = UnitHealth(unit), math.max(UnitHealthMax(unit), 1)
  c.health:SetMinMaxValues(0, max)
  c.health:SetValue(hp)
  S.ColorHealth(c.health, unit, hp / max)
  if S.DrawPrediction then
    S.DrawPrediction(c.health, unit, c.predict)
  end
  c.name:SetText(FitName(UnitName(unit), c:GetWidth(), c.nameLen))
  c.name:SetTextColor(S.NameColor(unit))

  if not UnitIsConnected(unit) then
    c.status:SetText("Offline")
    c.health:SetStatusBarColor(0.3, 0.3, 0.3)
  elseif UnitIsGhost(unit) then
    c.status:SetText("Ghost")
    c.health:SetValue(0)
  elseif UnitIsDead(unit) then
    c.status:SetText("Dead")
    c.health:SetValue(0)
  elseif c.statusMode == "percent" then
    c.status:SetText(math.floor(hp / max * 100 + 0.5) .. "%")
  elseif c.statusMode ~= "none" and hp < max then
    c.status:SetText("|cffff8080-" .. S.ShortNumber(max - hp) .. "|r")
  else
    c.status:SetText("")
  end

  if UnitPowerType(unit) == 0 and UnitManaMax(unit) > 0 then
    c.power:SetMinMaxValues(0, UnitManaMax(unit))
    c.power:SetValue(UnitMana(unit))
    c.power:SetStatusBarColor(S.POWER[0][1], S.POWER[0][2], S.POWER[0][3])
  else
    c.power:SetValue(0)
  end

  -- a debuff you can remove
  local dtype = c.showDispel and Dispellable(unit)
  local dc = dtype and DISPEL[dtype]
  if dtype then
    local col = dc or { 1, 1, 1 }
    c.debuffFill:SetTexture(col[1], col[2], col[3], 1)
    c.debuff:Show()
    c.debuffFill:Show()
  else
    c.debuff:Hide()
    c.debuffFill:Hide()
  end

  if UnitIsUnit(unit, "target") then
    c:SetBackdropBorderColor(1, 1, 1, 1)
  elseif dc then
    c:SetBackdropBorderColor(dc[1], dc[2], dc[3], 1)
  else
    S.ResetBorder(c)
  end

  local role = c.showRoles and S.Role and S.Role(unit)
  if role then
    c.role:SetTexture(S.RoleIcon(role))
    c.role:Show()
  else
    c.role:Hide()
  end
  -- a top-left name moves over to make room for the icon
  if c.namePos == "topleft" and c.nameShift ~= (role and 12 or 0) then
    c.nameShift = role and 12 or 0
    c.name:ClearAllPoints()
    c.name:SetPoint("TOPLEFT", c, "TOPLEFT", (c.nameX or 4) + c.nameShift, c.nameY or -2)
  end

  c:SetAlpha(InRange(unit) and 1 or 0.4)
  c:Show()
end

local function ShowPreview(c, i)
  c.preview = true
  local class = CLASSES[math.mod(i - 1, table.getn(CLASSES)) + 1]
  local color = S.CLASS[class] or { 0.5, 0.5, 0.5 }
  c.health:SetMinMaxValues(0, 100)
  c.health:SetValue(100 - math.mod(i * 17, 60))
  c.health:SetStatusBarColor(color[1], color[2], color[3])
  c.power:SetValue(0)
  c.name:SetText((c.previewName or "Player") .. " " .. i)
  c.status:SetText("")
  -- edit mode: show the square on one cell so its size can be judged
  if c.showDispel and i == 3 then
    c.debuffFill:SetTexture(DISPEL.Poison[1], DISPEL.Poison[2], DISPEL.Poison[3], 1)
    c.debuff:Show()
    c.debuffFill:Show()
  else
    c.debuff:Hide()
    c.debuffFill:Hide()
  end
  local role = c.showRoles and ((i == 1 and "tank") or (i == 2 and "healer"))
  if role and S.RoleIcon then
    c.role:SetTexture(S.RoleIcon(role))
    c.role:Show()
  else
    c.role:Hide()
  end
  S.ResetBorder(c)
  c:SetAlpha(1)
  c:Show()
end

-- [[ headers ]] --
local function CreateHeader(key, label, default, settings)
  local h = { key = key, cells = {} }
  h.s = settings
  h.holder = S:Holder(key, label, default, {})
  h.frame = CreateFrame("Frame", "SnapUI_" .. key, h.holder)
  h.frame:SetPoint("TOPLEFT", h.holder, "TOPLEFT", 0, 0)
  function h:Cell(i)
    if not self.cells[i] then
      self.cells[i] = CreateCell(self.frame)
    end
    return self.cells[i]
  end
  function h:Size(c)
    local s = self.s
    c:SetWidth(s.w)
    c:SetHeight(s.h)
    -- the thin mana strip along the bottom (0 = none)
    local ph = s.power or 3
    if ph > 0 then
      c.power:SetHeight(ph)
      c.power:Show()
      c.health:SetPoint("BOTTOMRIGHT", c.power, "TOPRIGHT", 0, 1)
    else
      c.power:Hide()
      c.health:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
    end
    if c.fontSize ~= (s.nameSize or 12) then
      c.fontSize = s.nameSize or 12
      S.SetFont(c.name, c.fontSize)
      S.SetFont(c.status, math.max(7, c.fontSize - 1))
    end
    c.statusMode = s.text or "deficit"
    c.nameLen = s.nameLen or 0
    c.predict = s.healPrediction ~= false
    c.showRoles = s.roles ~= false
    local icon = math.max(8, math.min(14, math.floor((s.h or 34) / 3)))
    c.role:SetWidth(icon)
    c.role:SetHeight(icon)
    c.showDispel = s.dispel ~= false
    local sq = s.dispelSize or 10
    c.debuff:SetWidth(sq)
    c.debuff:SetHeight(sq)
    c.nameX, c.nameY = s.nameX, s.nameY
    -- name in the middle (Grid) or in the top-left corner (ElvUI)
    if c.namePos ~= s.namePos then
      c.namePos = s.namePos
      c.name:ClearAllPoints()
      c.status:ClearAllPoints()
      c.nameShift = nil
      if s.namePos == "topleft" then
        c.name:SetJustifyH("LEFT")
        c.name:SetPoint("TOPLEFT", c, "TOPLEFT", s.nameX or 4, s.nameY or -2)
        c.status:SetPoint("BOTTOMRIGHT", c.health, "BOTTOMRIGHT", -2, 2)
      else
        c.name:SetJustifyH("CENTER")
        c.name:SetPoint("CENTER", c.health, "CENTER", 0, 5)
        c.status:SetPoint("TOP", c.name, "BOTTOM", 0, -1)
      end
    end
    S.SetReverse(c.health, s.reverse)
  end
  return h
end

local party
-- one raid layout per raid size; the one that fits how many are in the raid is shown.
-- Raid (40) keeps the original "raid" key so its settings and position carried over.
local RAID_SIZES = {
  { size = 40, key = "raid", label = "Raid (40)" },
  { size = 25, key = "raid25", label = "Raid (25)" },
  { size = 10, key = "raid10", label = "Raid (10)" },
}
local raids = {}

-- the layout for a raid of `count` people: the smallest size they fit in
local function RaidSize(count)
  if count <= 10 then return 10 end
  if count <= 25 then return 25 end
  return 40
end

local function LayoutParty()
  local s = party.s
  local units = {}
  if s.player then table.insert(units, "player") end
  for i = 1, 4 do table.insert(units, "party" .. i) end

  local inRaid = GetNumRaidMembers() > 0
  local active = s.enabled and (S:IsEditing() or (not inRaid and (GetNumPartyMembers() > 0 or s.solo)))
  local n = table.getn(units)
  for i = 1, 5 do
    local c = party:Cell(i)
    party:Size(c)
    c:ClearAllPoints()
    local off = (i - 1) * ((s.vertical and s.h or s.w) + s.spacing)
    if s.vertical then
      c:SetPoint("TOPLEFT", party.frame, "TOPLEFT", 0, -off)
    else
      c:SetPoint("TOPLEFT", party.frame, "TOPLEFT", off, 0)
    end
    c.unit = units[i]
    c.preview = nil
    if not active or i > n then
      c:Hide()
    elseif S:IsEditing() and not UnitExists(c.unit) then
      ShowPreview(c, i)
    else
      UpdateCell(c)
    end
  end
  local long = n * (s.vertical and s.h or s.w) + (n - 1) * s.spacing
  if s.vertical then
    party.frame:SetWidth(s.w)
    party.frame:SetHeight(long)
  else
    party.frame:SetWidth(long)
    party.frame:SetHeight(s.h)
  end
  S:Fit(party.holder, party.frame)
end

-- One raid layout. Groups in use are packed together in subgroup order, so a 10-man in
-- groups 1 and 3 still fills the first two columns (or rows). It shows when the raid's
-- size picks it; in edit mode every layout shows, with stand-in players if it isn't the
-- live one.
local function LayoutRaid(raid)
  local s = raid.s
  local count = GetNumRaidMembers()
  local editing = S:IsEditing()
  local live = count > 0 and RaidSize(count) == raid.size
  local preview = editing and not live

  for _, c in ipairs(raid.cells) do
    c.preview = nil
    c.unit = nil
    c:Hide()
  end

  -- who goes where: { unit index, group } in roster order
  local members = {}
  if s.enabled and live then
    for i = 1, count do
      local _, _, subgroup = GetRaidRosterInfo(i)
      table.insert(members, { i = i, group = subgroup or 1 })
    end
  elseif s.enabled and preview then
    for i = 1, raid.size do
      table.insert(members, { i = i, group = math.floor((i - 1) / 5) + 1 })
    end
  end

  -- pack the groups in use into consecutive columns/rows
  local used = {}
  for _, m in ipairs(members) do used[m.group] = true end
  local column, groups = {}, 0
  for g = 1, 8 do
    if used[g] then
      groups = groups + 1
      column[g] = groups
    end
  end

  local slots = {}
  for n, m in ipairs(members) do
    local slot = slots[m.group] or 0
    if slot < 5 then
      slots[m.group] = slot + 1
      local c = raid:Cell(n)
      raid:Size(c)
      local col = column[m.group] - 1
      c:ClearAllPoints()
      if s.rows then
        c:SetPoint("TOPLEFT", raid.frame, "TOPLEFT", slot * (s.w + s.spacing), -col * (s.h + s.spacing))
      else
        c:SetPoint("TOPLEFT", raid.frame, "TOPLEFT", col * (s.w + s.spacing), -slot * (s.h + s.spacing))
      end
      c.unit = "raid" .. m.i
      if preview then
        ShowPreview(c, m.i)
      else
        UpdateCell(c)
      end
    end
  end

  -- the box is sized for this raid size (2, 5 or 8 groups), or more if they're spread out
  local span = math.max(raid.size / 5, groups)
  if s.rows then
    -- one row per group in use, growing down (the holder keeps its top edge)
    local rows = math.max(1, groups)
    raid.frame:SetWidth(5 * s.w + 4 * s.spacing)
    raid.frame:SetHeight(rows * s.h + (rows - 1) * s.spacing)
  else
    raid.frame:SetWidth(span * s.w + (span - 1) * s.spacing)
    raid.frame:SetHeight(5 * s.h + 4 * s.spacing)
  end
  S:Fit(raid.holder, raid.frame)
end

-- [[ pets ]] --
-- Their own window: the party's pets (yours too, if you like) or every pet in the raid,
-- in lines of `perRow`.
local pets

local function PetUnits()
  local s, units = pets.s, {}
  if not s.enabled then return units end
  if GetNumRaidMembers() > 0 then
    for i = 1, 40 do
      if UnitExists("raidpet" .. i) then table.insert(units, "raidpet" .. i) end
    end
  elseif GetNumPartyMembers() > 0 or s.solo then
    if s.player and UnitExists("pet") then table.insert(units, "pet") end
    for i = 1, 4 do
      if UnitExists("partypet" .. i) then table.insert(units, "partypet" .. i) end
    end
  end
  return units
end

local function LayoutPets()
  local s = pets.s
  local units = PetUnits()
  pets.roster = table.concat(units, ",")
  local preview = S:IsEditing() and s.enabled and table.getn(units) == 0
  local n = preview and 5 or table.getn(units)
  for _, c in ipairs(pets.cells) do
    c.unit = nil
    c.preview = nil
    c:Hide()
  end
  local per = math.max(1, s.perRow or 5)
  for i = 1, n do
    local c = pets:Cell(i)
    pets:Size(c)
    c:ClearAllPoints()
    -- along a line of `per`, then the next line
    local a, b = math.mod(i - 1, per), math.floor((i - 1) / per)
    if s.vertical then
      c:SetPoint("TOPLEFT", pets.frame, "TOPLEFT", b * (s.w + s.spacing), -a * (s.h + s.spacing))
    else
      c:SetPoint("TOPLEFT", pets.frame, "TOPLEFT", a * (s.w + s.spacing), -b * (s.h + s.spacing))
    end
    if preview then
      c.unit = "pet"
      c.previewName = "Pet"
      ShowPreview(c, i)
    else
      c.unit = units[i]
      UpdateCell(c)
    end
  end
  local along = math.max(1, math.min(n, per))
  local lines = math.max(1, math.ceil(n / per))
  local long = along * ((s.vertical and s.h or s.w) + s.spacing) - s.spacing
  local wide = lines * ((s.vertical and s.w or s.h) + s.spacing) - s.spacing
  if s.vertical then
    pets.frame:SetWidth(wide)
    pets.frame:SetHeight(long)
  else
    pets.frame:SetWidth(long)
    pets.frame:SetHeight(wide)
  end
  S:Fit(pets.holder, pets.frame)
end

-- [[ tanks ]] --
-- Raid only: everyone whose role is tank (set with Alt-right-click or /snap role, from the
-- dungeon finder, or guessed) gets a second, bigger cell in a window of its own.
local tanks

local function TankUnits()
  local units = {}
  if not tanks.s.enabled or not S.Role then return units end
  for i = 1, GetNumRaidMembers() do
    if S.Role("raid" .. i) == "tank" then table.insert(units, "raid" .. i) end
  end
  return units
end

local function LayoutTanks()
  local s = tanks.s
  local units = TankUnits()
  tanks.roster = table.concat(units, ",")
  local preview = S:IsEditing() and s.enabled and table.getn(units) == 0
  local n = preview and 2 or table.getn(units)
  for _, c in ipairs(tanks.cells) do
    c.unit = nil
    c.preview = nil
    c:Hide()
  end
  for i = 1, n do
    local c = tanks:Cell(i)
    tanks:Size(c)
    c:ClearAllPoints()
    local off = (i - 1) * ((s.vertical and s.h or s.w) + s.spacing)
    if s.vertical then
      c:SetPoint("TOPLEFT", tanks.frame, "TOPLEFT", 0, -off)
    else
      c:SetPoint("TOPLEFT", tanks.frame, "TOPLEFT", off, 0)
    end
    if preview then
      c.unit = "player"
      c.previewName = "Tank"
      ShowPreview(c, i)
    else
      c.unit = units[i]
      UpdateCell(c)
    end
  end
  -- the box keeps room for two so it can be placed before any tank is known
  local slots = math.max(2, n)
  local long = slots * ((s.vertical and s.h or s.w) + s.spacing) - s.spacing
  if s.vertical then
    tanks.frame:SetWidth(s.w)
    tanks.frame:SetHeight(long)
  else
    tanks.frame:SetWidth(long)
    tanks.frame:SetHeight(s.h)
  end
  S:Fit(tanks.holder, tanks.frame)
end

local function LayoutAll()
  LayoutParty()
  for _, raid in ipairs(raids) do
    LayoutRaid(raid)
  end
  if pets then LayoutPets() end
  if tanks then LayoutTanks() end
end

-- party, every raid layout, the pets and the tanks
local function Headers()
  local list = { party }
  for _, raid in ipairs(raids) do
    table.insert(list, raid)
  end
  if pets then table.insert(list, pets) end
  if tanks then table.insert(list, tanks) end
  return list
end

local function UpdateAll()
  for _, h in ipairs(Headers()) do
    for _, c in ipairs(h.cells) do
      if c:IsShown() then UpdateCell(c) end
    end
  end
end

-- extra: true for the party, "pets" / "tanks" for those windows, nil for a raid layout
local function Options(h, extra)
  local s = h.s
  local isPets = extra == "pets"
  local isTanks = extra == "tanks"
  local function Opt(label, key, min, max, step)
    table.insert(h.holder.options, { label = label, get = function() return s[key] end, set = function(v) s[key] = v; LayoutAll() end, min = min, max = max, step = step })
  end
  local function Toggle(label, key)
    table.insert(h.holder.options, { label = label, toggle = true, get = function() return s[key] end, set = function(v) s[key] = v; LayoutAll() end })
  end
  if s.enabled == nil then
    s.enabled = true
  end
  if s.power == nil then s.power = 3 end
  if s.nameSize == nil then s.nameSize = 12 end
  if s.text == nil then s.text = "deficit" end
  if s.namePos == nil then s.namePos = "center" end
  if s.nameLen == nil then s.nameLen = 0 end
  if s.reverse == nil then s.reverse = false end
  h.holder.growUp = s.growUp
  if s.growUp then h.holder.growDown = nil end
  h.holder.isOff = function() return not s.enabled end
  Toggle("Enabled", "enabled")
  Opt("Cell width", "w", 30, 200, 2)
  Opt("Cell height", "h", 16, 100, 2)
  Opt("Spacing", "spacing", 0, 12, 1)
  Opt("Mana bar", "power", 0, 12, 1)
  Opt("Name size", "nameSize", 7, 20, 1)
  table.insert(h.holder.options, { label = "Health text", choices = { { "deficit", "Missing (-300)" }, { "percent", "Percent" }, { "none", "None" } },
    get = function() return s.text or "deficit" end, set = function(v) s.text = v; LayoutAll() end })
  table.insert(h.holder.options, { label = "Name", choices = { { "center", "Middle" }, { "topleft", "Top left" } },
    get = function() return s.namePos end, set = function(v) s.namePos = v; LayoutAll() end })
  Opt("Name letters (0 = fit)", "nameLen", 0, 12, 1)
  Toggle("Fill from the right", "reverse")
  if s.healPrediction == nil then s.healPrediction = true end
  Toggle("Heal prediction", "healPrediction")
  -- everyone in the tank window is a tank, so no icon there unless asked for
  if s.roles == nil then s.roles = not isPets and not isTanks end
  if not isPets then Toggle("Role icons (tank, healer)", "roles") end
  if s.dispel == nil then s.dispel = true end
  if s.dispelSize == nil then s.dispelSize = 10 end
  Toggle("Square for debuffs you can remove", "dispel")
  Opt("Debuff square size", "dispelSize", 4, 20, 1)
  if extra == true and S.RoleOptions then
    for _, o in ipairs(S:RoleOptions()) do
      table.insert(h.holder.options, o)
    end
  end
  table.insert(h.holder.options, { label = "Grow upwards", toggle = true, get = function() return s.growUp end,
    set = function(v) s.growUp = v; h.holder.growUp = v; h.holder.growDown = (not v) and h.growDefault or nil end })
  if isTanks then
    Toggle("Vertical", "vertical")
  elseif isPets then
    Toggle("Vertical", "vertical")
    Opt("Pets per line", "perRow", 1, 40, 1)
    Toggle("Include your pet", "player")
    Toggle("Show when solo", "solo")
  elseif extra then
    Toggle("Vertical", "vertical")
    Toggle("Include yourself", "player")
    Toggle("Show when solo", "solo")
  else
    Toggle("Groups as rows", "rows")
  end
end

S:RegisterModule("group", function()
  for i = 1, 4 do
    S.Kill(getglobal("PartyMemberFrame" .. i))
  end
  -- Blizzard's raid pullout frames still work from the Raid tab if anyone wants them

  party = CreateHeader("party", "Party", { "LEFT", nil, 20, 60 }, S.db.party)
  Options(party, true)
  -- biggest first, so the smaller layouts' edit-mode boxes sit on top and stay grabbable
  local first
  for _, def in ipairs(RAID_SIZES) do
    -- a new size starts as a copy of the 40-man layout, in the same spot
    if not S.db[def.key] then
      S.db[def.key] = {}
      for k, v in pairs(S.db.raid) do S.db[def.key][k] = v end
    end
    local default = first and { "TOPLEFT", "TOPLEFT", 0, 0, first.holder } or { "TOPLEFT", nil, 20, -220 }
    local raid = CreateHeader(def.key, def.label, default, S.db[def.key])
    raid.size = def.size
    raid.holder.growDown = true
    raid.growDefault = true
    raid.holder:SetFrameLevel(raid.holder:GetFrameLevel() + table.getn(raids) * 3)
    Options(raid, false)
    table.insert(raids, raid)
    first = first or raid
  end

  -- pets: smaller cells without a mana strip, to the right of the party frames to start with
  S.db.pets = S.db.pets or {}
  for k, v in pairs({ w = 70, h = 28, spacing = 2, power = 0, nameSize = 10, perRow = 5, player = true, solo = false }) do
    if S.db.pets[k] == nil then S.db.pets[k] = v end
  end
  pets = CreateHeader("pets", "Pets", { "BOTTOMLEFT", "BOTTOMRIGHT", 8, 0, party.holder }, S.db.pets)
  Options(pets, "pets")

  -- tanks: raid only, a column of bigger cells above the raid frames to start with
  -- (starts off in a profile with every raid layout switched off)
  if not S.db.tanks then
    local anyRaid = false
    for _, raid in ipairs(raids) do
      if raid.s.enabled then anyRaid = true end
    end
    S.db.tanks = { enabled = anyRaid }
  end
  for k, v in pairs({ w = 110, h = 36, spacing = 2, power = 3, nameSize = 12, vertical = true }) do
    if S.db.tanks[k] == nil then S.db.tanks[k] = v end
  end
  tanks = CreateHeader("tanks", "Tanks", { "BOTTOMLEFT", "TOPLEFT", 0, 8, first.holder }, S.db.tanks)
  Options(tanks, "tanks")
  LayoutAll()

  local events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MANA", "UNIT_MAXMANA", "UNIT_DISPLAYPOWER", "UNIT_AURA",
    "UNIT_NAME_UPDATE", "PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "UNIT_PET" }) do
    events:RegisterEvent(e)
  end
  ScanCures()
  events:SetScript("OnEvent", function()
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
      ScanCures()
      UpdateAll()
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      LayoutAll()
    elseif event == "UNIT_PET" then
      -- a pet called, dismissed or died
      LayoutPets()
    elseif event == "PLAYER_TARGET_CHANGED" then
      UpdateAll()
    elseif arg1 then
      -- PARTY_MEMBER_ENABLE/DISABLE pass a party index, not a unit token
      local unit = arg1
      if tonumber(unit) then unit = "party" .. unit end
      for _, h in ipairs(Headers()) do
        for _, c in ipairs(h.cells) do
          if c.unit and c:IsShown() and (c.unit == unit or UnitIsUnit(c.unit, unit)) then
            UpdateCell(c)
          end
        end
      end
    end
  end)

  -- range and anything events missed
  local elapsed = 0
  events:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed > 0.5 then
      elapsed = 0
      -- raid pets don't always send UNIT_PET: re-lay the pets when the set changes
      if not S:IsEditing() and table.concat(PetUnits(), ",") ~= pets.roster then
        LayoutPets()
      end
      if not S:IsEditing() and table.concat(TankUnits(), ",") ~= tanks.roster then
        LayoutTanks()
      end
      UpdateAll()
    end
  end)

  S:OnEdit(LayoutAll)
  if S.OnRoles then
    S:OnRoles(function()
      LayoutTanks()
      UpdateAll()
    end)
  end
  if S.OnPrediction then
    S:OnPrediction(function()
      for _, h in ipairs(Headers()) do
        for _, c in ipairs(h.cells) do
          if c:IsShown() and c.unit and not c.preview then S.DrawPrediction(c.health, c.unit, c.predict) end
        end
      end
    end)
  end
end, "Party & raid", "Grid-style party frames, 10/25/40 raid layouts, a pet window and a raid tank window.")
