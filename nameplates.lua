-- SnapUI nameplates: themed plates over the client's own. The client's bar and texts are
-- blanked (they keep running, so health and colours stay right) and an overlay draws a flat
-- health bar in the theme, the name above it, the level beside it, a cast bar under it and
-- the unit's debuffs on top. Uses ClassicAPI's NAME_PLATE_* events and unit tokens, the same
-- way pfUI did. HitNumbers floats its numbers above plate.nameplate.health.

local S = SnapUI
local s
local overlays = {}

-- like pfUI: textures blanked, font strings squashed, the client bar's texture cleared
local function Disable(object)
  if not object or not object.GetObjectType then
    return
  end
  local t = object:GetObjectType()
  if t == "Texture" then
    object:SetTexture("")
    object:SetTexCoord(0, 0, 0, 0)
  elseif t == "FontString" then
    object:SetWidth(0.001)
  elseif t == "StatusBar" then
    object:SetStatusBarTexture("")
  end
end

-- the client colours plates red / yellow / green / blue (friendly player) / grey (tapped)
local function ReactionColor(r, g, b)
  if r > 0.9 and g < 0.2 and b < 0.2 then
    return S.REACTION.hostile
  elseif r > 0.9 and g > 0.9 and b < 0.2 then
    return S.REACTION.neutral
  elseif r < 0.2 and g > 0.9 and b < 0.2 then
    return S.REACTION.friendly
  elseif r < 0.2 and g < 0.2 and b > 0.9 then
    return { 0.31, 0.45, 0.9 }
  end
  return { r, g, b }
end

local function Layout(o)
  o:SetScale(UIParent:GetScale())
  o.health:SetWidth(s.width)
  o.health:SetHeight(s.height)
  S.SetFont(o.name, s.nameSize)
  S.SetFont(o.level, math.max(7, s.nameSize - 1))
  S.SetFont(o.hp, s.hpSize)
  S.SetFont(o.arrowL, s.arrowSize)
  S.SetFont(o.arrowR, s.arrowSize)
  -- "center": name over the middle, level on the right. "elvui": name top-left, health %
  -- top-right, level under the bar's right end
  o.name:ClearAllPoints()
  o.level:ClearAllPoints()
  o.hp:ClearAllPoints()
  if s.style == "elvui" then
    o.name:SetJustifyH("LEFT")
    o.name:SetPoint("BOTTOMLEFT", o.health, "TOPLEFT", 0, 2)
    o.name:SetPoint("RIGHT", o.hp, "LEFT", -4, 0)
    o.hp:SetPoint("BOTTOMRIGHT", o.health, "TOPRIGHT", 0, 1)
    o.level:SetPoint("TOPRIGHT", o.health, "BOTTOMRIGHT", 0, -1)
  else
    o.name:SetJustifyH("CENTER")
    o.name:SetPoint("BOTTOM", o.health, "TOP", 0, 3)
    o.hp:SetPoint("CENTER", o.health, "CENTER", 0, 0)
    o.level:SetPoint("LEFT", o.health, "RIGHT", 3, 0)
  end
  if s.hpText then o.hp:Show() else o.hp:Hide() end
  o.arrowL:ClearAllPoints()
  o.arrowL:SetPoint("RIGHT", o.health, "LEFT", -6, s.style == "elvui" and 5 or 0)
  o.arrowR:ClearAllPoints()
  o.arrowR:SetPoint("LEFT", o.health, "RIGHT", 6, s.style == "elvui" and 5 or 0)
  o.cast:SetWidth(s.width)
  o.cast:SetHeight(math.max(4, s.height - 2))
  o.castIcon:SetWidth(s.height * 2)
  o.castIcon:SetHeight(s.height * 2)
  for _, d in ipairs(o.debuffs) do
    d:SetWidth(s.debuffSize)
    d:SetHeight(s.debuffSize)
  end
end

local function Refresh(o)
  local hb = o.original.healthbar
  local min, max = hb:GetMinMaxValues()
  o.health:SetMinMaxValues(min, max)
  o.health:SetValue(hb:GetValue())
  local unit = o.unit
  local c
  if unit and s.classColors and UnitIsPlayer(unit) then
    local _, class = UnitClass(unit)
    c = S.CLASS[class]
  end
  c = c or ReactionColor(hb:GetStatusBarColor())
  o.health:SetStatusBarColor(c[1], c[2], c[3])
  o.name:SetText(o.original.name:GetText() or "")
  o.hp:SetText(max > min and (math.floor((hb:GetValue() - min) / (max - min) * 100 + 0.5) .. "%") or "")
  if s.level and o.original.level and o.original.level.GetText then
    o.level:SetText(o.original.level:GetText() or "")
    local r, g, b = o.original.level:GetTextColor()
    o.level:SetTextColor(r or 1, g or 1, b or 1)
    o.level:Show()
  else
    o.level:Hide()
  end
end

local function IsTarget(o)
  if o.unit then
    return UnitIsUnit(o.unit, "target")
  end
  return UnitExists("target") and o:GetParent():GetAlpha() == 1
end

local function UpdateCast(o)
  local name, tex, start, finish, channel, noInterrupt
  if s.castbar and o.unit then
    name, tex, start, finish, channel, noInterrupt = S.UnitCast(o.unit)
  end
  local now = GetTime()
  if not name or now > finish then
    o.cast:Hide()
    return
  end
  o.cast:SetMinMaxValues(start, finish)
  o.cast:SetValue(channel and (start + finish - now) or now)
  if noInterrupt then
    o.cast:SetStatusBarColor(0.6, 0.6, 0.6)
  else
    o.cast:SetStatusBarColor(1, 0.55, 0.15)
  end
  o.castText:SetText(name)
  o.castIcon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
  o.cast:Show()
end

local function UpdateDebuffs(o)
  local n = 0
  if s.debuffs and o.unit and UnitCanAttack("player", o.unit) then
    for i = 1, s.maxDebuffs do
      local tex, count = UnitDebuff(o.unit, i)
      if not tex then break end
      n = n + 1
      local d = o.debuffs[n]
      d.tex:SetTexture(tex)
      d.count:SetText((count and count > 1) and tostring(count) or "")
      d:ClearAllPoints()
      d:SetPoint("BOTTOMLEFT", o.health, "TOPLEFT", (n - 1) * (s.debuffSize + 2), s.nameSize + 6)
      d:Show()
    end
  end
  for i = n + 1, table.getn(o.debuffs) do
    o.debuffs[i]:Hide()
  end
end

local function OverlayUpdate()
  local o = this
  o.tick = (o.tick or 0) + arg1
  UpdateCast(o)
  if o.tick < 0.1 then
    return
  end
  o.tick = 0
  Refresh(o)
  if IsTarget(o) then
    o.border:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
    if s.arrows then o.arrowL:Show(); o.arrowR:Show() end
  else
    S.ResetBorder(o.border)
    o.arrowL:Hide()
    o.arrowR:Hide()
  end
  UpdateDebuffs(o)
end

local function Skin(plate)
  if not plate or plate.snap then
    return plate and plate.snap
  end
  local hb, cb = plate:GetChildren()
  if not hb or not hb.GetObjectType or hb:GetObjectType() ~= "StatusBar" then
    return nil
  end
  local regions = { plate:GetRegions() }
  local o = CreateFrame("Frame", nil, plate)
  o:SetAllPoints(plate)
  o:SetFrameLevel(plate:GetFrameLevel() + 2)
  o.original = { healthbar = hb, castbar = cb, name = regions[3], level = regions[4], raidicon = regions[6] }
  Disable(hb)
  Disable(cb)
  for i, r in ipairs(regions) do
    if i ~= 6 then Disable(r) end
  end

  o.health = S.StatusBar(o)
  o.health:SetPoint("CENTER", o, "CENTER", 0, 0)
  o.border = CreateFrame("Frame", nil, o)
  o.border:SetPoint("TOPLEFT", o.health, "TOPLEFT", -1, 1)
  o.border:SetPoint("BOTTOMRIGHT", o.health, "BOTTOMRIGHT", 1, -1)
  o.border:SetFrameLevel(math.max(0, o.health:GetFrameLevel() - 1))
  S.Backdrop(o.border, 0.85)

  o.name = S.Text(o.health.over, 10, "CENTER")
  o.name:SetPoint("BOTTOM", o.health, "TOP", 0, 3)
  o.level = S.Text(o.health.over, 9, "LEFT")
  o.hp = S.Text(o.health.over, 10, "RIGHT")
  -- the target's yellow arrows either side of its bar
  o.arrowL = S.Text(o.health.over, 18, "RIGHT")
  o.arrowL:SetText(">>")
  o.arrowL:SetTextColor(1, 0.82, 0.1)
  o.arrowL:Hide()
  o.arrowR = S.Text(o.health.over, 18, "LEFT")
  o.arrowR:SetText("<<")
  o.arrowR:SetTextColor(1, 0.82, 0.1)
  o.arrowR:Hide()
  if o.original.raidicon then
    o.original.raidicon:ClearAllPoints()
    o.original.raidicon:SetPoint("RIGHT", o.health, "LEFT", -4, 0)
    o.original.raidicon:SetWidth(16)
    o.original.raidicon:SetHeight(16)
  end

  o.cast = S.StatusBar(o)
  o.cast:SetPoint("TOP", o.health, "BOTTOM", 0, -3)
  o.castBorder = CreateFrame("Frame", nil, o.cast)
  o.castBorder:SetPoint("TOPLEFT", -1, 1)
  o.castBorder:SetPoint("BOTTOMRIGHT", 1, -1)
  o.castBorder:SetFrameLevel(math.max(0, o.cast:GetFrameLevel() - 1))
  S.Backdrop(o.castBorder, 0.85)
  o.castText = S.Text(o.cast.over, 8, "CENTER")
  o.castText:SetPoint("CENTER", 0, 0)
  o.castIcon = CreateFrame("Frame", nil, o.cast)
  o.castIcon:SetPoint("TOPRIGHT", o.health, "TOPLEFT", -3, 0)
  S.Backdrop(o.castIcon, 1)
  o.castIcon.tex = o.castIcon:CreateTexture(nil, "ARTWORK")
  o.castIcon.tex:SetPoint("TOPLEFT", 1, -1)
  o.castIcon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  o.castIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  o.cast:Hide()

  o.debuffs = {}
  for i = 1, 8 do
    local d = CreateFrame("Frame", nil, o)
    S.Backdrop(d, 1)
    d.tex = d:CreateTexture(nil, "ARTWORK")
    d.tex:SetPoint("TOPLEFT", 1, -1)
    d.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    d.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.count = S.Text(d, 9, "RIGHT")
    d.count:SetPoint("BOTTOMRIGHT", 1, 0)
    d:Hide()
    o.debuffs[i] = d
  end

  -- the client keeps updating its own bar; follow it straight away
  local old = hb:GetScript("OnValueChanged")
  hb:SetScript("OnValueChanged", function()
    if old then old() end
    Refresh(o)
  end)
  o:SetScript("OnUpdate", OverlayUpdate)

  plate.snap = o
  plate.nameplate = o
  table.insert(overlays, o)
  Layout(o)
  Refresh(o)
  return o
end

function S:NameplateOptions()
  local function Num(label, key, min, max, step)
    return { label = label, get = function() return s[key] end, set = function(v) s[key] = v; for _, o in ipairs(overlays) do Layout(o) end end, min = min, max = max, step = step }
  end
  local function Toggle(label, key)
    return { label = label, toggle = true, get = function() return s[key] end, set = function(v) s[key] = v end }
  end
  return {
    Num("Width", "width", 40, 250, 5),
    Num("Height", "height", 4, 30, 1),
    Num("Name size", "nameSize", 7, 20, 1),
    Num("Health text size", "hpSize", 7, 24, 1),
    { label = "Style", choices = { { "center", "Name over the middle" }, { "elvui", "ElvUI (name left, % right)" } },
      get = function() return s.style end, set = function(v) s.style = v; for _, o in ipairs(overlays) do Layout(o) end end },
    Toggle("Health %", "hpText"),
    Toggle("Target arrows", "arrows"),
    Num("Debuff size", "debuffSize", 10, 32, 1),
    Num("Debuffs shown", "maxDebuffs", 0, 8, 1),
    Toggle("Cast bar", "castbar"),
    Toggle("Debuffs", "debuffs"),
    Toggle("Level", "level"),
    Toggle("Class colours", "classColors"),
  }
end

S:RegisterModule("nameplates", function()
  s = S:Settings("frames", "nameplates", { width = 110, height = 10, nameSize = 10, castbar = true, debuffs = true,
    maxDebuffs = 4, debuffSize = 16, level = true, classColors = true, style = "center", hpText = false, hpSize = 10,
    arrows = false, arrowSize = 18 })
  if not C_NamePlate then
    S.Print("nameplates need ClassicAPI (OctoWoW launcher mod); leaving the default ones")
    return
  end
  local events = CreateFrame("Frame")
  for _, e in ipairs({ "NAME_PLATE_CREATED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function()
    if event == "NAME_PLATE_CREATED" then
      Skin(arg1)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      local o = Skin(plate)
      if o then
        o.unit = arg1
        Refresh(o)
      end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
      local plate = C_NamePlate.GetNamePlateForUnit(arg1)
      if plate and plate.snap then
        plate.snap.unit = nil
      end
    end
  end)
  -- plates that were already up before we loaded
  if C_NamePlate.GetNamePlates then
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      Skin(plate)
    end
  end
end, "Nameplates", "Themed enemy and friendly nameplates with cast bars and debuffs.")
