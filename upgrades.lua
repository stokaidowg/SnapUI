-- SnapUI upgrade check: item tooltips get an "Upgrade" / "Downgrade" line comparing the item
-- with what you have on in that slot. Both are scored with stat weights for your class and
-- spec (rough Pawn-style values for vanilla): the item's stats are read off the tooltip
-- itself, the equipped item's off a hidden scanning tooltip. Rings and trinkets compare with
-- the weaker of your two, a two-hander with main hand + off hand together.
--
-- The spec is picked from your talents (the tree with the most points) once you have 10 or
-- more points; before that you're levelling and get the class's levelling weights (for a
-- paladin, Retribution). The Tooltip box's "Upgrades for" option can force a spec or turn
-- the line off. Enchants on your gear are left out of its score (they'd come off anyway).

local S = SnapUI

-- [[ stat weights ]] --
-- per point; hit/crit/dodge/parry/block per 1%; dps = weapon damage per second (rdps for the
-- ranged slot); sp = spell damage and healing, heal = healing only; school_x = one school
local MELEE = { str = 1, agi = 0.65, sta = 0.3, ap = 0.5, crit = 12, hit = 12, dps = 6, armor = 0.025 }
local function With(base, extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local TANK = { sta = 1, def = 1.3, armor = 0.06, dodge = 12, parry = 10, block = 6, blockvalue = 0.3,
  str = 0.5, agi = 0.6, hit = 6, dps = 2 }
local HEALER = { heal = 1, sp = 1, int = 0.6, spi = 0.3, mp5 = 2, spellcrit = 6, sta = 0.2, armor = 0.01 }
local CASTER = { sp = 1, int = 0.4, spi = 0.2, mp5 = 0.8, spellcrit = 9, spellhit = 10, sta = 0.3, armor = 0.01, rdps = 2 }

local SPECS = {
  PALADIN = { levelling = 3,
    { "Holy", With(HEALER, { int = 1, spi = 0.2, spellcrit = 9 }) },
    { "Protection", With(TANK, { sp = 0.5, int = 0.3 }) },
    { "Retribution", With(MELEE, { int = 0.2, sp = 0.2 }) } },
  WARRIOR = { levelling = 1,
    { "Arms", With(MELEE, { rdps = 0.5 }) },
    { "Fury", With(MELEE, { rdps = 0.5 }) },
    { "Protection", With(TANK, { rdps = 0.5 }) } },
  ROGUE = { levelling = 2,
    { "Assassination", With(MELEE, { agi = 1, str = 0.5, dps = 7, rdps = 0.3 }) },
    { "Combat", With(MELEE, { agi = 1, str = 0.5, dps = 7, hit = 15, rdps = 0.3 }) },
    { "Subtlety", With(MELEE, { agi = 1, str = 0.5, dps = 7, rdps = 0.3 }) } },
  HUNTER = { levelling = 1,
    { "Beast Mastery", { agi = 1, rap = 0.45, ap = 0.15, crit = 13, hit = 13, int = 0.3, sta = 0.4, rdps = 6, dps = 1, armor = 0.02 } },
    { "Marksmanship", { agi = 1, rap = 0.45, ap = 0.15, crit = 13, hit = 13, int = 0.3, sta = 0.3, rdps = 6, dps = 1, armor = 0.02 } },
    { "Survival", { agi = 1.1, rap = 0.45, ap = 0.15, crit = 13, hit = 13, int = 0.3, sta = 0.3, rdps = 6, dps = 1, armor = 0.02 } } },
  SHAMAN = { levelling = 2,
    { "Elemental", With(CASTER, { school_nature = 1, school_fire = 0.6, rdps = 0 }) },
    { "Enhancement", With(MELEE, { int = 0.25 }) },
    { "Restoration", With(HEALER, { mp5 = 2.2 }) } },
  DRUID = { levelling = 2,
    { "Balance", With(CASTER, { school_arcane = 0.9, school_nature = 0.9, rdps = 0 }) },
    { "Feral Combat", { agi = 1, str = 1.2, ap = 0.5, feralap = 0.5, crit = 12, hit = 12, sta = 0.6, armor = 0.03, int = 0.1 } },
    { "Restoration", With(HEALER, { spi = 0.6 }) } },
  MAGE = { levelling = 3,
    { "Arcane", With(CASTER, { school_arcane = 0.9, school_frost = 0.6, school_fire = 0.6 }) },
    { "Fire", With(CASTER, { school_fire = 1 }) },
    { "Frost", With(CASTER, { school_frost = 1 }) } },
  PRIEST = { levelling = 3,
    { "Discipline", With(HEALER, { spi = 0.6 }) },
    { "Holy", With(HEALER, { spi = 0.7 }) },
    { "Shadow", With(CASTER, { school_shadow = 1, spi = 0.4, spellcrit = 4 }) } },
  WARLOCK = { levelling = 1,
    { "Affliction", With(CASTER, { school_shadow = 1, sta = 0.5, spellcrit = 4 }) },
    { "Demonology", With(CASTER, { school_shadow = 0.9, sta = 0.6 }) },
    { "Destruction", With(CASTER, { school_shadow = 0.9, school_fire = 0.6 }) } },
}

-- [[ reading a tooltip ]] --
-- the slot line (left text) -> inventory slots it can go in
local SLOTS = {
  ["Head"] = { 1 }, ["Neck"] = { 2 }, ["Shoulder"] = { 3 }, ["Chest"] = { 5 }, ["Waist"] = { 6 },
  ["Legs"] = { 7 }, ["Feet"] = { 8 }, ["Wrist"] = { 9 }, ["Hands"] = { 10 }, ["Finger"] = { 11, 12 },
  ["Trinket"] = { 13, 14 }, ["Back"] = { 15 }, ["Main Hand"] = { 16 }, ["One-Hand"] = { 16 },
  ["Two-Hand"] = { 16 }, ["Off Hand"] = { 17 }, ["Held In Off-hand"] = { 17 }, ["Ranged"] = { 18 },
  ["Thrown"] = { 18 }, ["Relic"] = { 18 },
}
local ATTRS = { Strength = "str", Agility = "agi", Stamina = "sta", Intellect = "int", Spirit = "spi" }
-- "Equip:" effects, most specific first
local EFFECTS = {
  { "critical strike with spells by (%d+)%%", "spellcrit" },
  { "chance to hit with spells by (%d+)%%", "spellhit" },
  { "critical strike by (%d+)%%", "crit" },
  { "chance to hit by (%d+)%%", "hit" },
  { "healing done by spells and effects by up to (%d+)", "heal" },
  { "damage and healing done by magical spells and effects by up to (%d+)", "sp" },
  { "damage done by (%a+) spells and effects by up to (%d+)", "school" },
  { "(%d+) mana per 5 sec", "mp5" },
  { "%+(%d+) Attack Power in Cat, Bear", "feralap" },
  { "%+(%d+) ranged Attack Power", "rap" },
  { "%+(%d+) Attack Power", "ap" },
  { "Increased Defense %+(%d+)", "def" },
  { "dodge an attack by (%d+)%%", "dodge" },
  { "parry an attack by (%d+)%%", "parry" },
  { "block attacks with a shield by (%d+)%%", "block" },
  { "block value of your shield by (%d+)", "blockvalue" },
}

local function IsRed(r, g, b) return r and r > 0.9 and g < 0.2 and b < 0.2 end
local function IsGreen(r, g, b) return r and g > 0.9 and r < 0.2 and b < 0.2 end

-- read an item tooltip: its slot text, stats, and whether something on it is in red
-- (returns nil when it isn't something you wear)
local function Read(tip)
  local name = tip:GetName()
  local item = { stats = {} }
  local st = item.stats
  local n = tip:NumLines() or 0
  for i = 1, n do
    local left = getglobal(name .. "TextLeft" .. i)
    local right = getglobal(name .. "TextRight" .. i)
    local text = left and left:GetText()
    if text then
      local r, g, b = left:GetTextColor()
      if i == 1 then item.name = text end
      if not item.slot and SLOTS[text] then item.slot = text end
      local _, _, lvl = string.find(text, "^Requires Level (%d+)")
      if lvl then
        item.level = tonumber(lvl)
      elseif IsRed(r, g, b) and not string.find(text, "^Durability") then
        item.red = true
      end
      local rt = right and right:IsShown() and right:GetText()
      if rt and IsRed(right:GetTextColor()) then item.red = true end

      local _, _, sign, num, attr = string.find(text, "^([%+%-])(%d+) (%a+)$")
      local _, _, armor = string.find(text, "^(%d+) Armor$")
      local _, _, block = string.find(text, "^(%d+) Block$")
      local _, _, dps = string.find(text, "%(([%d%.]+) damage per second%)")
      if attr and ATTRS[attr] and not IsGreen(r, g, b) then
        -- white "+5 Strength" (random "of the Bear" stats too); green ones are enchants
        local k = ATTRS[attr]
        st[k] = (st[k] or 0) + tonumber(num) * (sign == "-" and -1 or 1)
      elseif armor then
        st.armor = (st.armor or 0) + tonumber(armor)
      elseif block then
        st.blockvalue = (st.blockvalue or 0) + tonumber(block)
      elseif dps then
        st.dps = (st.dps or 0) + tonumber(dps)
      elseif string.find(text, "^Equip: ") and not string.find(text, " when fighting ") then
        for _, e in ipairs(EFFECTS) do
          local _, _, a, c = string.find(text, e[1])
          if a then
            if e[2] == "school" then
              local k = "school_" .. string.lower(a)
              st[k] = (st[k] or 0) + tonumber(c)
            else
              st[e[2]] = (st[e[2]] or 0) + tonumber(a)
            end
            break
          end
        end
      end
    end
  end
  if not item.slot then
    return nil
  end
  item.slots = SLOTS[item.slot]
  item.twoHand = item.slot == "Two-Hand"
  -- a ranged weapon's damage counts as ranged
  if item.slots[1] == 18 and item.stats.dps then
    item.stats.rdps, item.stats.dps = item.stats.dps, nil
  end
  return item
end

-- [[ spec and score ]] --
local function ClassSpecs()
  local _, class = UnitClass("player")
  return SPECS[class or ""]
end

-- which spec: the setting, else the tree with the most points (10+), else the levelling one
local function Spec(setting)
  local specs = ClassSpecs()
  if not specs or setting == "off" then
    return nil
  end
  if type(setting) == "number" and specs[setting] then
    return specs[setting]
  end
  local best, most, total = nil, 0, 0
  for i = 1, (GetNumTalentTabs and GetNumTalentTabs() or 0) do
    local _, _, points = GetTalentTabInfo(i)
    points = points or 0
    total = total + points
    if points > most then best, most = i, points end
  end
  if best and total >= 10 and specs[best] then
    return specs[best]
  end
  return specs[specs.levelling]
end

local function Score(item, weights)
  local score = 0
  for k, v in pairs(item.stats) do
    local w = weights[k]
    if w then
      score = score + v * w
    end
  end
  return score
end

-- [[ equipped items, read once and kept until gear changes ]] --
local scan, equipped, bagCache, linkCache = nil, {}, {}, {}

-- the hidden tooltip items are read from, ready for a Set* call
local function Scan()
  if not scan then
    scan = CreateFrame("GameTooltip", "SnapUIScanTip", nil, "GameTooltipTemplate")
  end
  scan:SetOwner(WorldFrame, "ANCHOR_NONE")
  scan:ClearLines()
  return scan
end

local function Equipped(slot)
  if equipped[slot] == nil then
    Scan():SetInventoryItem("player", slot)
    equipped[slot] = Read(scan) or false
    scan:Hide()
  end
  return equipped[slot] or nil
end

-- gear, level, talents or the setting changed: read everything again, and let the bag
-- window redraw its arrows
local function Changed()
  equipped, bagCache, linkCache = {}, {}, {}
  if S.OnUpgradesChanged then S.OnUpgradesChanged() end
end

local watch = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_INVENTORY_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED" }) do
  watch:RegisterEvent(e)
end
watch:SetScript("OnEvent", function()
  if event ~= "UNIT_INVENTORY_CHANGED" or arg1 == "player" then
    Changed()
  end
end)

-- what the new item would replace, and that score
local function Current(item, w)
  local slots = item.slots
  if table.getn(slots) == 2 then
    -- rings, trinkets: the weaker of the two (an empty one is weakest)
    local a, b = Equipped(slots[1]), Equipped(slots[2])
    if not a or not b then return 0, nil, true end
    local sa, sb = Score(a, w), Score(b, w)
    if sa <= sb then return sa, a end
    return sb, b
  end
  local slot = slots[1]
  if item.twoHand then
    local mh, oh = Equipped(16), Equipped(17)
    if not mh and not oh then return 0, nil, true end
    return (mh and Score(mh, w) or 0) + (oh and Score(oh, w) or 0), mh or oh
  end
  local cur = Equipped(slot)
  if not cur then
    -- an off hand when a two-hander is on replaces the two-hander
    local mh = slot == 17 and Equipped(16)
    if mh and mh.twoHand then return Score(mh, w), mh end
    return 0, nil, true
  end
  return Score(cur, w), cur
end

-- item vs what it would replace, for a spec: percent better (nil if neither scores), the
-- equipped item it was compared with, and whether that slot is empty
local function Compare(item, spec)
  local w = spec[2]
  local new = Score(item, w)
  local old, cur, empty = Current(item, w)
  if new <= 0 and old <= 0 then
    return nil
  end
  if empty then
    return 100, nil, true
  end
  return old > 0 and (new - old) / old * 100 or 100, cur, false
end

-- [[ the tooltip line ]] --
-- tip has just been filled by `method`; s.upgrades is "auto", "off" or a spec number
function S:AddUpgrade(tip, method, unit, s)
  if method == "SetInventoryItem" and unit == "player" then
    return -- that's what you have on
  end
  local spec = Spec(s and s.upgrades or "auto")
  if not spec then
    return
  end
  local item = Read(tip)
  if not item or item.red then
    return
  end
  local pct, cur, empty = Compare(item, spec)
  if not pct then
    return
  end
  local label, value, r, g, b
  if empty then
    label, value, r, g, b = "Upgrade", "empty slot", 0.3, 1, 0.3
  else
    if pct >= 1 then
      label, value, r, g, b = "Upgrade", string.format("+%d%%", math.floor(pct + 0.5)), 0.3, 1, 0.3
    elseif pct <= -1 then
      label, value, r, g, b = "Downgrade", string.format("%d%%", math.floor(pct - 0.5)), 1, 0.35, 0.35
    else
      label, value, r, g, b = "About the same", "0%", 0.75, 0.75, 0.75
    end
  end
  local playerLevel = UnitLevel("player") or 0
  local note = spec[1]
  if item.level and item.level > playerLevel then
    note = note .. ", at level " .. item.level
  end
  tip:AddDoubleLine(label .. " |cff888888(" .. note .. ")|r", value, r, g, b, r, g, b)
  if cur and table.getn(item.slots) == 2 and not empty then
    tip:AddLine("|cff888888vs " .. (cur.name or "?") .. "|r")
  end
end

-- [[ bag arrows ]] --
-- is the item in this bag slot an upgrade you can wear now? (kept per item link until gear,
-- level, talents or the setting change)
local function Setting()
  local t = S.db and S.db.frames and S.db.frames.tooltip
  return t and t.upgrades or "auto"
end

function S:BagUpgrade(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if not link then
    return false
  end
  local spec = Spec(Setting())
  if not spec then
    return false
  end
  if bagCache[link] == nil then
    Scan():SetBagItem(bag, slot)
    local item = Read(scan)
    scan:Hide()
    local up = false
    if item and not item.red and not (item.level and item.level > (UnitLevel("player") or 0)) then
      local pct, _, empty = Compare(item, spec)
      up = pct ~= nil and (empty or pct >= 1)
    end
    bagCache[link] = up
  end
  return bagCache[link]
end

-- [[ your gear's totals ]] --
-- a stat summed over everything you have on (read off the same tooltips; kept until your
-- gear changes), e.g. "heal" + "sp" for heal prediction
function S:GearStat(key)
  local total = 0
  for slot = 1, 19 do
    local item = Equipped(slot)
    if item and item.stats[key] then
      total = total + item.stats[key]
    end
  end
  return total
end

-- [[ any item link ]] --
-- for SnapAuction's Upgrades search: how much better an item would be, for an "item:..."
-- string or full link. Returns percent better (100 for an empty slot), whether the slot is
-- empty, and the spec name; nil when it isn't an upgrade you can wear now. A second value of
-- true with no first means the client hasn't got the item yet (ask again later).
function S:UpgradeSpecName()
  local spec = Spec(Setting())
  return spec and spec[1]
end

-- your class's specs ({ { index, name }, ... }) and the setting now ("auto", "off" or an
-- index), for picking one outside the settings window
function S:UpgradeSpecs()
  local list = {}
  for i, sp in ipairs(ClassSpecs() or {}) do
    table.insert(list, { i, sp[1] })
  end
  return list, Setting()
end

-- the "Upgrades for" setting (shared with tooltips and bag arrows)
function S:SetUpgradeSpec(v)
  local t = S.db and S.db.frames and S.db.frames.tooltip
  if t then
    t.upgrades = v
    Changed()
  end
end

-- ahead: also count items needing up to that many levels more than you have (4th value:
-- the level an item needs, when it says)
function S:LinkUpgrade(link, ahead)
  local _, _, s = string.find(link or "", "(item:[%-%d:]+)")
  local spec = s and Spec(Setting())
  if not spec then
    return nil
  end
  local c = linkCache[s]
  if c == nil then
    Scan():SetHyperlink(s)
    local lines = scan:NumLines() or 0
    local item = Read(scan)
    scan:Hide()
    if lines == 0 then
      return nil, true
    end
    c = false
    if item and not item.red then
      local pct, _, empty = Compare(item, spec)
      if pct and (empty or pct >= 1) then
        c = { pct, empty, item.level }
      end
    end
    linkCache[s] = c
  end
  if not c or (c[3] and c[3] > (UnitLevel("player") or 0) + (ahead or 0)) then
    return nil
  end
  return c[1], c[2], spec[1], c[3]
end

-- the Tooltip box option: Auto, each of your class's specs, Off
function S:UpgradeOption(s)
  local choices = { { "auto", "Auto" } }
  local specs = ClassSpecs()
  if specs then
    for i, sp in ipairs(specs) do
      table.insert(choices, { i, sp[1] })
    end
  end
  table.insert(choices, { "off", "Off" })
  return { label = "Upgrades for", choices = choices,
    get = function() return s.upgrades end, set = function(v) s.upgrades = v; Changed() end }
end

-- for the harness tests (not a HarnessExtra entry: those get called)
S.HarnessUpgrades = { Read = Read, Score = Score, Spec = Spec, reset = function() equipped = {} end }
