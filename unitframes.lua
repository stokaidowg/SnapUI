-- SnapUI unit frames: player, target, target-of-target and pet, plus the player's power bar,
-- the target cast bar and combo points. Every frame is built from settings, so a profile can
-- make it look like ReatUI (name in caps above a flat bar), ElvUI (dark bars, class-coloured
-- names, overlay portrait), Blizzard (portrait on the side, green health) and so on:
--   name: above / inside / below / none, in caps or not, its size
--   hp / powerText: the text format; mirror swaps the sides; vertical makes "orb" bars
--   portrait: none / left / right / overlay, 2D or 3D; classIcon; status icons
-- Health colours come from the theme (class, dark, gradient, Blizzard green).

local S = SnapUI
local frames = {}

local FORMATS = {
  { "percent", "87%" }, { "value", "1.2K" }, { "curmax", "1.2K / 1.5K" }, { "percentfirst", "87% | 1.2K" },
  { "valuefirst", "1.2K | 87%" }, { "deficit", "-300" }, { "none", "None" },
}
local NAME_MODES = { { "above", "Above" }, { "top", "On the top edge" }, { "inside", "Inside" }, { "below", "Below" }, { "none", "Hidden" } }
local PORTRAITS = { { "none", "None" }, { "left", "Left" }, { "right", "Right" }, { "overlay", "Over the bar" } }

-- the text for `cur` of `max` in format `fmt`; NPC health on 1.12 often arrives as 0-100
function S.FormatValue(fmt, cur, max)
  max = math.max(max or 1, 1)
  local pct = math.floor(cur / max * 100 + 0.5) .. "%"
  if fmt == "none" then
    return ""
  elseif fmt == "percent" or (max == 100 and fmt ~= "deficit") then
    return pct
  elseif fmt == "value" then
    return S.ShortNumber(cur)
  elseif fmt == "curmax" then
    return S.ShortNumber(cur) .. " / " .. S.ShortNumber(max)
  elseif fmt == "valuefirst" then
    return S.ShortNumber(cur) .. " | " .. pct
  elseif fmt == "deficit" then
    return cur < max and ("-" .. S.ShortNumber(max - cur)) or ""
  end
  return pct .. " | " .. S.ShortNumber(cur)
end

-- "Treant Seedling" -> "T. Seedling" when a name is too long for the frame
local function ShortName(name, max)
  if not name or string.len(name) <= max then
    return name
  end
  local words = {}
  for w in string.gfind(name, "%S+") do
    table.insert(words, w)
  end
  local n = table.getn(words)
  if n < 2 then
    return string.sub(name, 1, max)
  end
  for i = 1, n - 1 do
    words[i] = string.sub(words[i], 1, 1) .. "."
  end
  return table.concat(words, " ")
end

local function LevelText(unit)
  local level = UnitLevel(unit)
  local text = (level and level > 0) and ("Lv " .. level) or "Lv ??"
  local c = UnitClassification(unit)
  if c == "elite" or c == "worldboss" or c == "rareelite" then
    text = text .. "+"
  end
  return text
end

-- [[ auras (target) ]] --
local function AuraButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(size)
  b:SetHeight(size)
  b.time = S.Text(b, 10, "CENTER")
  b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
  S.Backdrop(b, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.count = S.Text(b, 10, "RIGHT")
  b.count:SetPoint("BOTTOMRIGHT", 0, 1)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
    if this.playerIndex then
      GameTooltip:SetPlayerBuff(this.playerIndex)
    elseif this.debuff then
      GameTooltip:SetUnitDebuff(this.unit, this.index)
    else
      GameTooltip:SetUnitBuff(this.unit, this.index)
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- debuffs and buffs each live in their own box so they can be moved apart. The box is the
-- full grid (per row x max shown), so it doesn't jump about as auras come and go.
-- icons can be wider than tall (ElvUI's 37x28); crop the art to match
local function IconShape(b, w, h)
  b:SetWidth(w)
  b:SetHeight(h)
  local cut = (1 - math.min(w, h) / math.max(w, h)) / 2 * 0.84
  if w > h then
    b.icon:SetTexCoord(0.08, 0.92, 0.08 + cut, 0.92 - cut)
  else
    b.icon:SetTexCoord(0.08 + cut, 0.92 - cut, 0.08, 0.92)
  end
end

local function TimeText(left)
  if left >= 3600 then return math.floor(left / 3600 + 0.5) .. "h" end
  if left >= 60 then return math.floor(left / 60 + 0.5) .. "m" end
  return math.floor(left + 0.5) .. "s"
end

local function LayoutAuras(g)
  local s = g.s
  local w = (s.width and s.width > 0) and s.width or s.size
  local stepX = w + s.spacing
  local stepY = s.size + s.spacing + (s.durations and 11 or 0)
  local step = stepX
  local per = math.max(1, math.min(s.perRow, s.max))
  local rows = math.ceil(s.max / per)
  g.anchor = (s.growDown and "TOP" or "BOTTOM") .. (s.growLeft and "RIGHT" or "LEFT")
  g.frame:SetWidth(math.max(1, per * stepX - s.spacing))
  g.frame:SetHeight(math.max(1, rows * stepY - s.spacing))
  g.frame:ClearAllPoints()
  g.frame:SetPoint(g.anchor, g.holder, g.anchor, 0, 0)
  g.holder.growDown = s.growDown
  S:Fit(g.holder, g.frame)
  for _, b in ipairs(g.buttons) do
    IconShape(b, w, s.size)
  end
end

-- the player's own buffs, through the player-buff API: it knows the time left, so these can
-- show only timed buffs (no permanent auras or mounts) and a countdown under each
local function PlayerBuffList(timedOnly, max)
  local list = {}
  for i = 0, 31 do
    local index = GetPlayerBuff(i, "HELPFUL")
    if not index or index < 0 then break end
    local left = GetPlayerBuffTimeLeft(index) or 0
    if not timedOnly or left > 0 then
      table.insert(list, { tex = GetPlayerBuffTexture(index), count = GetPlayerBuffApplications(index), left = left, index = index })
      if table.getn(list) >= max then break end
    end
  end
  return list
end

local function FillAuras(g, unit)
  local s = g.s
  if s.enabled == false then
    g.frame:Hide()
    return
  end
  local w = (s.width and s.width > 0) and s.width or s.size
  local stepX = w + s.spacing
  local stepY = s.size + s.spacing + (s.durations and 11 or 0)
  local per = math.max(1, math.min(s.perRow, s.max))
  local own = g.player and PlayerBuffList(s.timedOnly, s.max)
  local n = 0
  for i = 1, s.max do
    local tex, count, dtype, left, pindex
    if own then
      local a = own[i]
      if a then tex, count, left, pindex = a.tex, a.count, a.left, a.index end
    elseif g.debuff then
      tex, count, dtype = UnitDebuff(unit, i)
    else
      tex, count = UnitBuff(unit, i)
    end
    if not tex then break end
    n = n + 1
    local b = g.buttons[n]
    if not b then
      b = AuraButton(g.frame, s.size)
      g.buttons[n] = b
    end
    b.unit, b.index, b.debuff, b.playerIndex = unit, i, g.debuff, pindex
    IconShape(b, w, s.size)
    if s.durations and left and left > 0 then
      b.time:SetText(TimeText(left))
      b.time:Show()
    else
      b.time:Hide()
    end
    b.icon:SetTexture(tex)
    b.count:SetText((count and count > 1) and tostring(count) or "")
    if g.debuff then
      local c = DebuffTypeColor and DebuffTypeColor[dtype or "none"]
      if c then b:SetBackdropBorderColor(c.r, c.g, c.b, 1) else b:SetBackdropBorderColor(0.8, 0, 0, 1) end
    else
      S.ResetBorder(b)
    end
    local col, row = math.mod(n - 1, per), math.floor((n - 1) / per)
    b:ClearAllPoints()
    b:SetPoint(g.anchor, g.frame, g.anchor, col * stepX * (s.growLeft and -1 or 1), row * stepY * (s.growDown and -1 or 1))
    b:Show()
  end
  for i = n + 1, table.getn(g.buttons) do
    g.buttons[i]:Hide()
  end
  if s.centered and n > 0 then
    -- each row sits in the middle of the box instead of starting at a corner
    local vert = s.growDown and "TOP" or "BOTTOM"
    for i = 1, n do
      local row = math.floor((i - 1) / per)
      local inRow = math.min(per, n - row * per)
      local col = math.mod(i - 1, per)
      local b = g.buttons[i]
      b:ClearAllPoints()
      b:SetPoint(vert, g.frame, vert, (col - (inRow - 1) / 2) * stepX, row * stepY * (s.growDown and -1 or 1))
    end
  end
  g.frame:Show()
end

local function UpdateAuras(f)
  if not f.auraGroups then
    return
  end
  for _, g in ipairs(f.auraGroups) do
    FillAuras(g, f.unit)
  end
end

local function HideAuras(f)
  if f.auraGroups then
    for _, g in ipairs(f.auraGroups) do
      g.frame:Hide()
    end
  end
end

-- [[ portraits ]] --
local function UpdatePortrait(f)
  local s = f.settings
  if s.portrait == "none" then
    return
  end
  local unit = f.unit
  if s.portrait3d or s.portrait == "overlay" then
    local guid = UnitGUID and UnitGUID(unit) or UnitName(unit)
    if guid ~= f.portraitGuid then
      f.portraitGuid = guid
      f.model:SetUnit(unit)
      f.model:SetCamera(0)
    end
  else
    SetPortraitTexture(f.portraitTex, unit)
  end
end

-- [[ frame ]] --
local function Update(f)
  local unit, s = f.unit, f.settings
  if not s.enabled or not UnitExists(unit) then
    f:Hide()
    HideAuras(f)
    if f.levelFrame then f.levelFrame:Hide() end
    return
  end
  f:Show()

  local hp, max = UnitHealth(unit), UnitHealthMax(unit)
  f.health:SetMinMaxValues(0, math.max(max, 1))
  f.health:SetValue(hp)
  S.ColorHealth(f.health, unit, hp / math.max(max, 1))
  if S.DrawPrediction then
    S.DrawPrediction(f.health, unit, s.healPrediction)
  end

  if not UnitIsConnected(unit) then
    f.hpText:SetText("Offline")
  elseif UnitIsGhost(unit) then
    f.hpText:SetText("Ghost")
  elseif UnitIsDead(unit) then
    f.hpText:SetText("Dead")
  else
    f.hpText:SetText(S.FormatValue(s.hp, hp, max))
  end

  local name = UnitName(unit) or ""
  if s.name == "inside" then
    name = ShortName(name, math.max(6, math.floor(s.width / 9)))
  else
    name = ShortName(name, math.max(8, math.floor(s.width / 12)))
  end
  if s.caps then
    name = string.upper(name)
  end
  f.name:SetText(name)
  f.name:SetTextColor(S.NameColor(unit))

  if f.levelFrame then
    if s.level then
      f.level:SetText(LevelText(unit))
      f.levelFrame:Show()
    else
      f.levelFrame:Hide()
    end
  end

  if s.power > 0 then
    local pmax = UnitManaMax(unit)
    if pmax > 0 then
      local p = S.POWER[UnitPowerType(unit)] or S.POWER[0]
      local cur = UnitMana(unit)
      f.power:SetMinMaxValues(0, pmax)
      f.power:SetValue(cur)
      f.power:SetStatusBarColor(p[1], p[2], p[3])
      f.powerText:SetText(S.FormatValue(s.powerText, cur, pmax))
      if S.DrawCost and unit == "player" then
        S.DrawCost(f.power, s.costPrediction ~= false, s.vertical)
      end
    else
      f.power:SetMinMaxValues(0, 1)
      f.power:SetValue(0)
      f.powerText:SetText("")
    end
  end

  local _, class = UnitClass(unit)
  if s.classIcon and UnitIsPlayer(unit) and class and S.CLASS_ICON_COORDS[class] then
    local c = S.CLASS_ICON_COORDS[class]
    f.classIcon:SetTexCoord(c[1], c[2], c[3], c[4])
    f.classIcon:Show()
  else
    f.classIcon:Hide()
  end

  local icon = GetRaidTargetIndex(unit)
  if icon and s.icons then
    SetRaidTargetIconTexture(f.raidIcon, icon)
    f.raidIcon:Show()
  else
    f.raidIcon:Hide()
  end
  if s.icons and UnitIsPartyLeader(unit) then f.leader:Show() else f.leader:Hide() end
  if s.icons and unit == "player" and UnitAffectingCombat("player") then
    f.state:SetTexCoord(0.5, 1, 0, 0.49)
    f.state:Show()
  elseif s.icons and unit == "player" and IsResting() then
    f.state:SetTexCoord(0, 0.5, 0, 0.421875)
    f.state:Show()
  else
    f.state:Hide()
  end

  UpdatePortrait(f)
  UpdateAuras(f)
end

local MENUS = {
  player = function() return PlayerFrameDropDown end,
  target = function() return TargetFrameDropDown end,
  pet = function() return PetFrameDropDown end,
}

local function CreateAuraGroup(f, key, label, debuff, default, max, player)
  local g = { debuff = debuff, buttons = {}, player = player }
  g.s = S:Settings("frames", key, { size = 20, width = 0, spacing = 2, perRow = 10, max = max, growLeft = false, growDown = true,
    enabled = not player, timedOnly = true, durations = player and true or false })
  g.holder = S:Holder(key, label, default, {})
  g.holder.isOff = function() return not f.settings.enabled or g.s.enabled == false end
  g.frame = CreateFrame("Frame", "SnapUI_" .. key, g.holder)
  local s = g.s
  local function Changed()
    LayoutAuras(g)
    Update(f)
  end
  local function Num(text, k, min, top, step)
    return { label = text, get = function() return s[k] end, set = function(v) s[k] = v; Changed() end, min = min, max = top, step = step }
  end
  local function Toggle(text, k)
    return { label = text, toggle = true, get = function() return s[k] end, set = function(v) s[k] = v; Changed() end }
  end
  g.holder.options = {
    Num("Icon size", "size", 12, 48, 1),
    Num("Icon width (0 = square)", "width", 0, 64, 1),
    Toggle("Time left", "durations"),
    Num("Per row", "perRow", 1, max, 1),
    Num("Max shown", "max", 1, max, 1),
    Num("Spacing", "spacing", 0, 12, 1),
    Toggle("Grow left", "growLeft"),
    Toggle("Centre each row", "centered"),
    Toggle("Grow down", "growDown"),
    Toggle("Enabled", "enabled"),
  }
  if player then
    table.insert(g.holder.options, Toggle("Timed buffs only", "timedOnly"))
  end
  LayoutAuras(g)
  table.insert(f.auraGroups, g)
  return g
end

-- place everything inside the frame for its current settings
local function Arrange(f)
  local s = f.settings
  local inset = 1
  f:SetWidth(s.width)
  f:SetHeight(s.height)
  f:SetScale(s.scale)

  -- a side portrait takes a square off one end of the bars
  local left, right = inset, inset
  f.portraitBox:Hide()
  f.model:Hide()
  f.portraitTex:Hide()
  local side = s.portrait == "left" or s.portrait == "right"
  if side then
    local size = s.height - 2 * inset
    f.portraitBox:ClearAllPoints()
    f.portraitBox:SetWidth(size)
    f.portraitBox:SetHeight(size)
    if s.portrait == "left" then
      f.portraitBox:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
      left = inset + size + 1
    else
      f.portraitBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
      right = inset + size + 1
    end
    f.portraitBox:Show()
    if s.portrait3d then
      f.model:SetParent(f.portraitBox)
      f.model:ClearAllPoints()
      f.model:SetAllPoints(f.portraitBox)
      f.model:SetAlpha(1)
      f.model:Show()
    else
      f.portraitTex:Show()
    end
  end

  -- health above, power below (or power down the side for vertical bars)
  f.health:ClearAllPoints()
  f.power:ClearAllPoints()
  local orient = s.vertical and "VERTICAL" or "HORIZONTAL"
  if f.health.SetOrientation then
    f.health:SetOrientation(orient)
    f.power:SetOrientation(orient)
  end
  if s.power > 0 and s.powerWidth < 1 and not s.vertical then
    -- ElvUI's "spaced" power: a short strip over the bottom of the health bar, on the name's side
    f.power:Show()
    local side = s.mirror and "RIGHT" or "LEFT"
    local x = side == "LEFT" and left or -right
    f.power:SetPoint("BOTTOM" .. side, f, "BOTTOM" .. side, x, inset)
    f.power:SetWidth(math.max(4, (s.width - left - right) * s.powerWidth))
    f.power:SetHeight(s.power)
    f.power:SetFrameLevel(f.health:GetFrameLevel() + 3)
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", left, -inset)
    f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -right, inset)
  elseif s.power > 0 then
    f.power:Show()
    if s.vertical then
      f.power:SetPoint("TOPRIGHT", f, "TOPRIGHT", -right, -inset)
      f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -right, inset)
      f.power:SetWidth(s.power)
      f.health:SetPoint("TOPLEFT", f, "TOPLEFT", left, -inset)
      f.health:SetPoint("BOTTOMRIGHT", f.power, "BOTTOMLEFT", -1, 0)
    else
      f.power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, inset)
      f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -right, inset)
      f.power:SetHeight(s.power)
      f.health:SetPoint("TOPLEFT", f, "TOPLEFT", left, -inset)
      f.health:SetPoint("BOTTOMRIGHT", f.power, "TOPRIGHT", 0, 1)
    end
  else
    f.power:Hide()
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", left, -inset)
    f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -right, inset)
  end

  S.SetReverse(f.health, s.reverse and not s.vertical)
  S.SetReverse(f.power, s.reverse and not s.vertical)

  if s.portrait == "overlay" then
    f.model:SetParent(f.health)
    f.model:ClearAllPoints()
    f.model:SetAllPoints(f.health)
    f.model:SetFrameLevel(f.health:GetFrameLevel() + 1)
    f.model:SetAlpha(0.35)
    f.model:Show()
  end
  f.portraitGuid = nil

  -- texts
  local nameSide, textSide = "LEFT", "RIGHT"
  if s.mirror then
    nameSide, textSide = "RIGHT", "LEFT"
  end
  if s.vertical then
    nameSide, textSide = "CENTER", "CENTER"
  end
  S.SetFont(f.name, s.nameSize)
  S.SetFont(f.hpText, s.hpSize)
  S.SetFont(f.powerText, math.max(8, s.hpSize - 3))
  f.name:ClearAllPoints()
  f.hpText:ClearAllPoints()
  f.name:SetJustifyH(nameSide)
  f.hpText:SetJustifyH(textSide)
  local nx = nameSide == "LEFT" and 5 or (nameSide == "RIGHT" and -5 or 0)
  local tx = textSide == "LEFT" and 6 or (textSide == "RIGHT" and -6 or 0)
  local edge = nameSide == "CENTER" and "" or nameSide
  if s.name == "above" then
    f.name:SetPoint("BOTTOM" .. edge, f, "TOP" .. edge, 0, 3)
  elseif s.name == "top" then
    local nxo = nameSide == "LEFT" and s.nameX or (nameSide == "RIGHT" and -s.nameX or 0)
    f.name:SetPoint("TOP" .. edge, f, "TOP" .. edge, nxo, s.nameY)
  elseif s.name == "below" then
    f.name:SetPoint("TOP" .. edge, f, "BOTTOM" .. edge, 0, -3)
  else
    f.name:SetPoint(nameSide, f.health, nameSide, nx, s.vertical and 10 or 0)
  end
  if s.name == "none" then f.name:Hide() else f.name:Show() end
  f.hpText:SetPoint(textSide, f.health, textSide, tx, s.vertical and -6 or 0)
  if s.name == "inside" and not s.vertical and s.hp ~= "none" then
    f.name:SetPoint(textSide, f.hpText, nameSide, s.mirror and 4 or -4, 0)
  end
  f.powerText:ClearAllPoints()
  f.powerText:SetPoint("CENTER", f.power, "CENTER", 0, 0)
  if s.power >= 8 and s.powerText ~= "none" then f.powerText:Show() else f.powerText:Hide() end

  -- class icon on the name side, outside the frame
  f.classIcon:ClearAllPoints()
  local isize = math.max(12, math.floor(s.height * 0.7))
  f.classIcon:SetWidth(isize)
  f.classIcon:SetHeight(isize)
  if s.mirror then
    f.classIcon:SetPoint("LEFT", f, "RIGHT", 3, 0)
  else
    f.classIcon:SetPoint("RIGHT", f, "LEFT", -3, 0)
  end

  -- status icons on the frame's corners
  f.leader:ClearAllPoints()
  f.leader:SetPoint("CENTER", f, s.mirror and "TOPRIGHT" or "TOPLEFT", 0, 0)
  f.state:ClearAllPoints()
  f.state:SetPoint("CENTER", f, s.mirror and "TOPLEFT" or "TOPRIGHT", 0, 0)
end

-- def: unit, key, label, default point, and defaults for the settings
local function CreateUnitFrame(def)
  local defaults = {
    width = 222, height = 34, power = 0, scale = 1, enabled = true,
    name = "inside", caps = false, nameSize = 13, hp = "percent", hpSize = 13, powerText = "none",
    mirror = false, portrait = "none", portrait3d = false, classIcon = false, icons = true, vertical = false,
    reverse = false, powerWidth = 1, nameX = 4, nameY = 6, healPrediction = true,
  }
  for k, v in pairs(def.settings or {}) do defaults[k] = v end
  local s = S:Settings("frames", def.key, defaults)
  local holder = S:Holder(def.key, def.label, def.default, {})
  holder.isOff = function() return not s.enabled end

  local f = CreateFrame("Button", "SnapUI_" .. def.key, holder)
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  f.unit = def.unit
  f.label, f.id = def.unit, "" -- lets SuperCleveRoidMacros resolve the unit under the mouse
  f.settings = s
  S.Panel(f, 0.85)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- text that sits outside the bars (names above/below) goes on this layer
  f.over = CreateFrame("Frame", nil, f)
  f.over:SetAllPoints(f)
  f.over:SetFrameLevel(f:GetFrameLevel() + 6)

  f.health = S.StatusBar(f)
  f.power = S.StatusBar(f)
  f.name = S.Text(f.over, 13, "LEFT")
  f.hpText = S.Text(f.health.over, 13, "RIGHT")
  f.powerText = S.Text(f.power.over, 10, "CENTER")

  f.portraitBox = CreateFrame("Frame", nil, f)
  f.portraitTex = f.portraitBox:CreateTexture(nil, "ARTWORK")
  f.portraitTex:SetAllPoints(f.portraitBox)
  f.portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
  f.model = CreateFrame("PlayerModel", nil, f)

  f.classIcon = f.over:CreateTexture(nil, "OVERLAY")
  f.classIcon:SetTexture(S.CLASS_ICONS)
  f.classIcon:Hide()
  f.raidIcon = f.over:CreateTexture(nil, "OVERLAY")
  f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  f.raidIcon:SetWidth(18)
  f.raidIcon:SetHeight(18)
  f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
  f.raidIcon:Hide()
  f.leader = f.over:CreateTexture(nil, "OVERLAY")
  f.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
  f.leader:SetWidth(14)
  f.leader:SetHeight(14)
  f.leader:Hide()
  f.state = f.over:CreateTexture(nil, "OVERLAY")
  f.state:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
  f.state:SetWidth(18)
  f.state:SetHeight(18)
  f.state:Hide()

  if def.level then
    -- the level line has its own box ("Target level") so it can be moved off the frame;
    -- it starts just under the bar on the name's side
    local nameSide = s.mirror and "RIGHT" or "LEFT"
    local ls = S:Settings("frames", def.key .. "level", { size = 11 })
    if s.level == nil then s.level = true end
    local lh = S:Holder(def.key .. "level", def.label .. " level", { "TOP" .. nameSide, "BOTTOM" .. nameSide, 0, -3, holder }, {})
    lh.isOff = function() return not s.enabled or not s.level end
    f.levelFrame = CreateFrame("Frame", nil, lh)
    f.levelFrame:SetAllPoints(lh)
    f.level = S.Text(f.levelFrame, ls.size, nameSide)
    f.level:SetPoint(nameSide, f.levelFrame, nameSide, 0, 0)
    f.level:SetTextColor(0.75, 0.75, 0.75)
    local function LayoutLevel()
      S.SetFont(f.level, ls.size)
      lh:SetWidth(ls.size * 4)
      lh:SetHeight(ls.size + 2)
    end
    LayoutLevel()
    lh.options = {
      { label = "Text size", get = function() return ls.size end,
        set = function(v) ls.size = v; LayoutLevel() end, min = 8, max = 24, step = 1 },
      { label = "Shown", toggle = true, get = function() return s.level end,
        set = function(v) s.level = v; Update(f) end },
    }
  end

  if def.playerBuffs then
    f.auraGroups = {}
    CreateAuraGroup(f, "playerbuffs", "Player buffs", false, { "BOTTOM", "TOP", 0, 30, holder }, 32, true)
  end
  if def.auras then
    -- debuffs under the frame (below the level line), buffs under the debuffs
    f.auraGroups = {}
    local debuffs = CreateAuraGroup(f, def.key .. "debuffs", def.label .. " debuffs", true,
      { "TOPLEFT", "BOTTOMLEFT", 0, -16, holder }, 16)
    CreateAuraGroup(f, def.key .. "buffs", def.label .. " buffs", false,
      { "TOPLEFT", "BOTTOMLEFT", 0, -2, debuffs.holder }, 32)
  end

  local function Layout()
    Arrange(f)
    S:Fit(holder, f, s.width, s.height)
    Update(f)
  end
  f.Layout = Layout

  local function Opt(label, key, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[key] end, set = function(v) s[key] = v; Layout() end, min = min, max = max, step = step })
  end
  local function Toggle(label, key)
    table.insert(holder.options, { label = label, toggle = true, get = function() return s[key] end, set = function(v) s[key] = v; Layout() end })
  end
  local function Choice(label, key, choices)
    table.insert(holder.options, { label = label, choices = choices, get = function() return s[key] end, set = function(v) s[key] = v; Layout() end })
  end
  Opt("Width", "width", 40, 500, 10)
  Opt("Height", "height", 10, 160, 2)
  Opt("Power bar", "power", 0, 30, 1)
  Opt("Scale", "scale", 0.5, 2, 0.05)
  Choice("Name", "name", NAME_MODES)
  Toggle("Name in caps", "caps")
  Opt("Name size", "nameSize", 7, 28, 1)
  Choice("Health text", "hp", FORMATS)
  Opt("Health text size", "hpSize", 7, 28, 1)
  Choice("Power text", "powerText", FORMATS)
  Toggle("Mirror", "mirror")
  Toggle("Fill from the right", "reverse")
  table.insert(holder.options, { label = "Power bar width", get = function() return s.powerWidth end,
    set = function(v) s.powerWidth = v; Layout() end, min = 0.1, max = 1, step = 0.05 })
  Toggle("Vertical bars", "vertical")
  Choice("Portrait", "portrait", PORTRAITS)
  Toggle("3D portrait", "portrait3d")
  Toggle("Heal prediction", "healPrediction")
  if f.unit == "player" then
    if s.costPrediction == nil then s.costPrediction = true end
    Toggle("Mana cost of your cast", "costPrediction")
  end
  Toggle("Class icon", "classIcon")
  Toggle("Status icons", "icons")
  if f.level then
    Toggle("Level", "level")
  end
  Toggle("Enabled", "enabled")

  f:SetScript("OnClick", function()
    local unit = this.unit
    if arg1 == "LeftButton" then
      if SpellIsTargeting() then
        SpellTargetUnit(unit)
      elseif CursorHasItem() then
        DropItemOnUnit(unit)
      else
        TargetUnit(unit)
      end
    elseif MENUS[unit] then
      ToggleDropDownMenu(1, nil, MENUS[unit](), "cursor", 0, 0)
    end
  end)
  f:SetScript("OnEnter", function()
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    GameTooltip:SetUnit(this.unit)
    GameTooltip:Show()
    if SetMouseoverUnit then SetMouseoverUnit(this.unit) end
  end)
  f:SetScript("OnLeave", function()
    GameTooltip:Hide()
    if SetMouseoverUnit then SetMouseoverUnit("") end
  end)

  frames[def.unit] = f
  Layout()
  return f
end

-- [[ player power bar ]] --
-- the player's mana/rage/energy on its own bar (centred under the action bar in ReatUI)
local function CreatePowerBar()
  local s = S:Settings("frames", "power", { width = 300, height = 10, enabled = true, text = "value", vertical = false })
  local holder = S:Holder("power", "Power bar", { "BOTTOM", nil, 0, 200 }, {})
  holder.isOff = function() return not s.enabled end

  local f = CreateFrame("Frame", "SnapUI_Power", holder)
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  S.Panel(f, 0.85)
  f.bar = S.StatusBar(f)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.text = S.Text(f.bar.over, 11, "CENTER")
  f.text:SetPoint("CENTER", 0, 0)

  local function Update()
    local pmax = UnitManaMax("player")
    if not s.enabled or pmax <= 0 then
      f:Hide()
      return
    end
    local cur, ptype = UnitMana("player"), UnitPowerType("player")
    local p = S.POWER[ptype] or S.POWER[0]
    f.bar:SetMinMaxValues(0, pmax)
    f.bar:SetValue(cur)
    f.bar:SetStatusBarColor(p[1], p[2], p[3])
    if S.DrawCost then
      S.DrawCost(f.bar, s.costPrediction ~= false, s.vertical)
    end
    if s.text == "value" then
      -- mana as "1.2K (80%)", rage and energy as just the number
      if ptype == 0 then
        f.text:SetText(S.ShortNumber(cur) .. " (" .. math.floor(cur / pmax * 100 + 0.5) .. "%)")
      else
        f.text:SetText(cur)
      end
    else
      f.text:SetText(S.FormatValue(s.text, cur, pmax))
    end
    f:Show()
  end

  local function Layout()
    f:SetWidth(s.width)
    f:SetHeight(s.height)
    if f.bar.SetOrientation then
      f.bar:SetOrientation(s.vertical and "VERTICAL" or "HORIZONTAL")
    end
    if s.height < 8 and not s.vertical then f.text:Hide() else f.text:Show() end
    S:Fit(holder, f, s.width, s.height)
    Update()
  end
  local function Opt(label, key, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[key] end, set = function(v) s[key] = v; Layout() end, min = min, max = max, step = step })
  end
  Opt("Width", "width", 4, 600, 2)
  Opt("Height", "height", 2, 300, 1)
  table.insert(holder.options, { label = "Text", choices = { { "value", "Mana (%)" }, { "percent", "87%" }, { "curmax", "Cur / max" }, { "none", "None" } },
    get = function() return s.text end, set = function(v) s.text = v; Layout() end })
  table.insert(holder.options, { label = "Vertical", toggle = true, get = function() return s.vertical end, set = function(v) s.vertical = v; Layout() end })
  if s.costPrediction == nil then s.costPrediction = true end
  table.insert(holder.options, { label = "Mana cost of your cast", toggle = true, get = function() return s.costPrediction end, set = function(v) s.costPrediction = v; Layout() end })
  table.insert(holder.options, { label = "Enabled", toggle = true, get = function() return s.enabled end, set = function(v) s.enabled = v; Layout() end })
  if S.OnPrediction then
    S:OnPrediction(function()
      if f:IsShown() then S.DrawCost(f.bar, s.costPrediction ~= false, s.vertical) end
    end)
  end

  local events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_MANA", "UNIT_MAXMANA", "UNIT_RAGE", "UNIT_MAXRAGE",
    "UNIT_ENERGY", "UNIT_MAXENERGY", "UNIT_FOCUS", "UNIT_MAXFOCUS", "UNIT_DISPLAYPOWER" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" or arg1 == "player" then
      Update()
    end
  end)
  Layout()
end

-- [[ combo points ]] --
local function CreateComboPoints()
  local s = S:Settings("frames", "combo", { size = 12, spacing = 3, enabled = true })
  local holder = S:Holder("combo", "Combo points", { "BOTTOM", "TOP", 0, 22, S.byName.target }, {})
  holder.isOff = function() return not s.enabled end
  local f = CreateFrame("Frame", "SnapUI_Combo", holder)
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  f.pips = {}
  for i = 1, 5 do
    local p = CreateFrame("Frame", nil, f)
    S.Backdrop(p, 0.8)
    p.fill = p:CreateTexture(nil, "ARTWORK")
    p.fill:SetTexture(S.BAR)
    p.fill:SetPoint("TOPLEFT", 1, -1)
    p.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    f.pips[i] = p
  end
  local _, class = UnitClass("player")
  local uses = class == "ROGUE" or class == "DRUID"

  local function Update()
    local n = (UnitExists("target") and GetComboPoints()) or 0
    if S:IsEditing() then
      n = 3
    end
    if not s.enabled or (not uses and not S:IsEditing()) or n == 0 then
      f:Hide()
      return
    end
    for i, p in ipairs(f.pips) do
      if i <= n then
        local c = i == 5 and { 1, 0.3, 0.2 } or S.ACCENT
        p.fill:SetVertexColor(c[1], c[2], c[3], 1)
        p.fill:Show()
      else
        p.fill:Hide()
      end
    end
    f:Show()
  end
  local function Layout()
    for i, p in ipairs(f.pips) do
      p:SetWidth(s.size)
      p:SetHeight(s.size)
      p:ClearAllPoints()
      p:SetPoint("LEFT", f, "LEFT", (i - 1) * (s.size + s.spacing), 0)
    end
    f:SetWidth(5 * s.size + 4 * s.spacing)
    f:SetHeight(s.size)
    S:Fit(holder, f)
    Update()
  end
  holder.options = {
    { label = "Size", get = function() return s.size end, set = function(v) s.size = v; Layout() end, min = 4, max = 40, step = 1 },
    { label = "Spacing", get = function() return s.spacing end, set = function(v) s.spacing = v; Layout() end, min = 0, max = 20, step = 1 },
    { label = "Enabled", toggle = true, get = function() return s.enabled end, set = function(v) s.enabled = v; Update() end },
  }
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_COMBO_POINTS")
  events:RegisterEvent("PLAYER_TARGET_CHANGED")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:SetScript("OnEvent", Update)
  S:OnEdit(Update)
  Layout()
end

-- [[ target cast bar ]] --
-- 1.12 has no target casting API; ClassicAPI adds the retail C_Spell.UnitCastingInfo and
-- UnitChannelInfo, so poll those for the target every frame.
function S.UnitCast(unit)
  if not (C_Spell and C_Spell.UnitCastingInfo) or not UnitExists(unit) then
    return nil
  end
  local ok, name, _, tex, startMs, endMs, _, _, noInterrupt = pcall(C_Spell.UnitCastingInfo, unit)
  local channel
  if not (ok and name) and C_Spell.UnitChannelInfo then
    ok, name, _, tex, startMs, endMs, _, noInterrupt = pcall(C_Spell.UnitChannelInfo, unit)
    channel = true
  end
  if not ok or not name or not startMs or not endMs then
    return nil
  end
  return name, tex, startMs / 1000, endMs / 1000, channel, noInterrupt
end

local function CreateTargetCastBar()
  local s = S:Settings("frames", "targetcast", { width = 230, height = 16, icon = true, enabled = true, showTarget = true })
  local holder = S:Holder("targetcast", "Target cast bar", { "BOTTOM", nil, 280, 262 }, {})
  holder.isOff = function() return not s.enabled end

  local f = CreateFrame("Frame", "SnapUI_TargetCast", holder)
  f:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
  S.Backdrop(f, 0.85)
  f.bar = S.StatusBar(f)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.name = S.Text(f.bar.over, 12, "LEFT")
  f.name:SetPoint("LEFT", 5, 0)
  f.timer = S.Text(f.bar.over, 12, "RIGHT")
  f.timer:SetPoint("RIGHT", -5, 0)
  f.name:SetPoint("RIGHT", f.timer, "LEFT", -4, 0)
  f.icon = CreateFrame("Frame", nil, f)
  S.Backdrop(f.icon, 1)
  f.icon.tex = f.icon:CreateTexture(nil, "ARTWORK")
  f.icon.tex:SetPoint("TOPLEFT", 1, -1)
  f.icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  f.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f:Hide()

  local function Layout()
    f:SetWidth(s.width)
    f:SetHeight(s.height + 2)
    f.icon:SetWidth(s.height + 2)
    f.icon:SetHeight(s.height + 2)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("RIGHT", f, "LEFT", -3, 0)
    local extra = 0
    if s.icon then
      f.icon:Show()
      extra = s.height + 5
    else
      f.icon:Hide()
    end
    holder:SetWidth(s.width + extra)
    holder:SetHeight(s.height + 2)
  end
  local function Opt(label, key, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[key] end, set = function(v) s[key] = v; Layout() end, min = min, max = max, step = step })
  end
  Opt("Width", "width", 100, 500, 10)
  Opt("Height", "height", 10, 40, 1)
  table.insert(holder.options, { label = "Spell icon", toggle = true, get = function() return s.icon end, set = function(v) s.icon = v; Layout() end })
  table.insert(holder.options, { label = "Show cast target", toggle = true, get = function() return s.showTarget end, set = function(v) s.showTarget = v end })
  table.insert(holder.options, { label = "Enabled", toggle = true, get = function() return s.enabled end, set = function(v) s.enabled = v end })
  Layout()

  -- a separate driver keeps polling while the bar itself is hidden
  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function()
    if not s.enabled then
      f:Hide()
      return
    end
    local now = GetTime()
    local name, tex, start, finish, channel, noInterrupt = S.UnitCast("target")
    if not name and S:IsEditing() then
      name, tex, start, finish = "Target cast bar", "Interface\\Icons\\Spell_Fire_FlameBolt", now - 1, now + 1.5
    end
    if not name or now > finish then
      f:Hide()
      return
    end
    f.bar:SetMinMaxValues(start, finish)
    f.bar:SetValue(channel and (start + finish - now) or now)
    if noInterrupt then
      f.bar:SetStatusBarColor(0.6, 0.6, 0.6)
    else
      f.bar:SetStatusBarColor(1, 0.55, 0.15)
    end
    local aim = s.showTarget and S.CastTarget and S.CastTargetText(S.CastTarget(UnitGUID and UnitGUID("target")))
    f.name:SetText(aim and (name .. " > " .. aim) or name)
    f.timer:SetText(string.format("%.1f", finish - now))
    f.icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    f:Show()
  end)
end

S:RegisterModule("unitframes", function()
  S.Kill(PlayerFrame)
  S.Kill(TargetFrame)
  S.Kill(ComboFrame)
  S.Kill(TargetofTargetFrame)
  S.Kill(PetFrame)

  -- the defaults are the ReatUI look this module started as
  CreateUnitFrame({ unit = "player", key = "player", label = "Player", default = { "BOTTOM", nil, -280, 220 }, playerBuffs = true,
    settings = { name = "above", caps = true, nameSize = 15, hp = "percentfirst", hpSize = 16 } })
  CreateUnitFrame({ unit = "target", key = "target", label = "Target", default = { "BOTTOM", nil, 280, 220 }, level = true, auras = true,
    settings = { name = "above", caps = true, nameSize = 15, hp = "valuefirst", hpSize = 16, mirror = true } })
  CreateUnitFrame({ unit = "targettarget", key = "targettarget", label = "Target of target", default = { "BOTTOM", nil, 460, 260 },
    settings = { width = 130, height = 24, nameSize = 11, hpSize = 11 } })
  CreateUnitFrame({ unit = "pet", key = "petframe", label = "Pet", default = { "TOPLEFT", "BOTTOMLEFT", 0, -6, S.byName.player },
    settings = { width = 130, height = 20, nameSize = 11, hpSize = 11 } })
  CreatePowerBar()
  CreateTargetCastBar()
  CreateComboPoints()
  if S.OnPrediction then
    S:OnPrediction(function()
      for _, f in pairs(frames) do
        if f:IsShown() then
          S.DrawPrediction(f.health, f.unit, f.settings.healPrediction)
          if f.unit == "player" and f.power:IsShown() then
            S.DrawCost(f.power, f.settings.costPrediction ~= false, f.settings.vertical)
          end
        end
      end
    end)
  end

  local events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_MANA", "UNIT_MAXMANA", "UNIT_RAGE", "UNIT_MAXRAGE", "UNIT_ENERGY", "UNIT_MAXENERGY", "UNIT_FOCUS",
    "UNIT_MAXFOCUS", "UNIT_DISPLAYPOWER", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_FACTION", "RAID_TARGET_UPDATE",
    "PLAYER_FLAGS_CHANGED", "UNIT_LEVEL", "UNIT_PORTRAIT_UPDATE", "UNIT_PET", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PARTY_LEADER_CHANGED", "PARTY_MEMBERS_CHANGED" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function()
    if event == "UNIT_PET" then
      Update(frames.pet)
    elseif arg1 and frames[arg1] then
      Update(frames[arg1])
    else
      for _, f in pairs(frames) do
        Update(f)
      end
    end
  end)

  -- target-of-target has no events on 1.12, so poll it
  local elapsed = 0
  events:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed > 0.2 then
      elapsed = 0
      Update(frames.targettarget)
      local p = frames.player
      if p and p.auraGroups and p:IsShown() then
        UpdateAuras(p)
      end
    end
  end)
end, "Unit frames", "Player, target, target of target, pet, power bar, target cast bar and combo points.")
