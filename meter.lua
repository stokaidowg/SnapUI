-- SnapUI meter: a Details-style damage / healing / threat meter.
-- Data comes from Nampower's combat events (structured, with GUIDs, no combat-log text
-- parsing) and threat from the server's TWThreat API (OctoWoW answers TWT_UDTSv4).
-- Fights are split into segments: one per combat, named after the boss or the enemy that
-- took the most damage, plus an Overall segment. Pets count towards their owner.
-- Data lives in memory only, so a /reload starts fresh.

local S = SnapUI

local MAX_HISTORY = 20
local THREAT_API, THREAT_REQUEST = "TWTv4=", "TWT_UDTSv4"

-- [[ modes ]] --
-- field: what a bar measures; perSec: show a per-second figure; spells: breakdown table
local MODES = {
  { key = "damage", label = "Damage Done", field = "damage", perSec = true, spells = "dspells" },
  { key = "healing", label = "Healing Done", field = "heal", perSec = true, spells = "hspells", over = true },
  { key = "overheal", label = "Overhealing", field = "overheal", perSec = true, spells = "ospells" },
  { key = "taken", label = "Damage Taken", field = "taken", perSec = true, spells = "tspells" },
  { key = "deaths", label = "Deaths", field = "deaths" },
  { key = "threat", label = "Threat" },
}
local MODE_BY_KEY = {}
for _, m in ipairs(MODES) do
  MODE_BY_KEY[m.key] = m
end

-- [[ roster: who counts ]] --
local roster = {} -- guid -> { name, class }
local pets = {}   -- pet guid -> owner guid
local names = {}  -- guid -> name cache for enemies
local unitOf = {} -- guid -> unit token, for everyone in the group and their pets
local guidOf = {} -- unit token -> guid

local function GUID(unit)
  local f = UnitGUID or GetUnitGUID
  return f and UnitExists(unit) and f(unit)
end

local function AddUnit(unit, petUnit)
  local guid = GUID(unit)
  if not guid then
    return
  end
  local _, class = UnitClass(unit)
  roster[guid] = { name = UnitName(unit), class = class }
  unitOf[guid], guidOf[unit] = unit, guid
  local pet = petUnit and GUID(petUnit)
  if pet then
    pets[pet] = guid
    unitOf[pet], guidOf[petUnit] = petUnit, pet
  end
end

local function BuildRoster()
  for _, t in ipairs({ roster, pets, unitOf, guidOf }) do
    for k in pairs(t) do t[k] = nil end
  end
  AddUnit("player", "pet")
  local raid = GetNumRaidMembers()
  if raid > 0 then
    for i = 1, raid do
      AddUnit("raid" .. i, "raidpet" .. i)
    end
  else
    for i = 1, GetNumPartyMembers() do
      AddUnit("party" .. i, "partypet" .. i)
    end
  end
end

-- the group member a guid belongs to (itself, or its pet's owner)
local function Owner(guid)
  if roster[guid] then
    return guid
  end
  return pets[guid]
end

local function NameOf(guid)
  if names[guid] then
    return names[guid]
  end
  local ok, n = pcall(UnitName, guid)
  if ok and n and n ~= "" and n ~= UNKNOWNOBJECT then
    names[guid] = n
    return n
  end
  return "Unknown"
end

local function IsBoss(guid)
  local ok, c = pcall(UnitClassification, guid)
  return ok and c == "worldboss"
end

local spellNames = {}
local function SpellName(id)
  if id == 0 then
    return "Melee"
  end
  if not spellNames[id] then
    local n = GetSpellInfo and GetSpellInfo(id)
    spellNames[id] = n or ("Spell " .. id)
  end
  return spellNames[id]
end

-- [[ segments ]] --
local overall, current
local history = {} -- finished fights, newest first
local lastEvent = 0

local function NewSegment(name)
  return { name = name, start = GetTime(), actors = {}, enemies = {}, bosses = {} }
end

-- seconds of fighting: one fight's length, or for Overall every fight added up (so idle
-- time between pulls doesn't drag its DPS down)
local function Duration(seg)
  if seg == overall then
    return math.max(1, (seg.combatTime or 0) + (current and (GetTime() - current.start) or 0))
  end
  return math.max(1, (seg.finish or GetTime()) - seg.start)
end

local function Actor(seg, guid)
  local a = seg.actors[guid]
  if not a then
    local r = roster[guid]
    a = { name = r and r.name or NameOf(guid), class = r and r.class, damage = 0, heal = 0, overheal = 0, taken = 0,
      deaths = 0, dspells = {}, hspells = {}, ospells = {}, tspells = {} }
    seg.actors[guid] = a
  end
  return a
end

-- the fight's name: the boss, else the enemy that took the most damage
local function SegmentName(seg)
  local best, bestDmg, count = nil, -1, 0
  for guid, dmg in pairs(seg.enemies) do
    count = count + 1
    if seg.bosses[guid] then
      return NameOf(guid)
    end
    if dmg > bestDmg then
      best, bestDmg = guid, dmg
    end
  end
  if not best then
    return "Fight"
  end
  return NameOf(best) .. (count > 1 and (" +" .. (count - 1)) or "")
end

local function StartFight()
  current = NewSegment()
  overall = overall or NewSegment("Overall")
end

local function EndFight()
  if not current then
    return
  end
  current.finish = lastEvent > current.start and lastEvent or GetTime()
  current.name = SegmentName(current)
  overall.combatTime = (overall.combatTime or 0) + (current.finish - current.start)
  table.insert(history, 1, current)
  while table.getn(history) > MAX_HISTORY do
    table.remove(history)
  end
  current = nil
end

-- everything we record goes into the current fight and Overall
local function Record(fn)
  fn(current)
  fn(overall)
end

-- [[ combat events (Nampower) ]] --
local function Damage(sourceGuid, targetGuid, amount, spellId)
  if not amount or amount <= 0 then
    return
  end
  local src, dst = Owner(sourceGuid), Owner(targetGuid)
  if src and dst then
    return -- friendly fire / self damage
  end
  if not src and not dst then
    return -- nothing to do with us
  end
  if not current then
    StartFight()
  end
  lastEvent = GetTime()
  if src then
    if not names[targetGuid] then NameOf(targetGuid) end
    local boss = not current.bosses[targetGuid] and IsBoss(targetGuid)
    Record(function(seg)
      local a = Actor(seg, src)
      a.damage = a.damage + amount
      a.dspells[spellId] = (a.dspells[spellId] or 0) + amount
      seg.enemies[targetGuid] = (seg.enemies[targetGuid] or 0) + amount
      if boss then seg.bosses[targetGuid] = true end
    end)
  else
    Record(function(seg)
      local a = Actor(seg, dst)
      a.taken = a.taken + amount
      local key = sourceGuid
      a.tspells[key] = (a.tspells[key] or 0) + amount
    end)
    if not names[sourceGuid] then NameOf(sourceGuid) end
  end
end

-- [[ overhealing ]] --
-- Nampower reports the full size of a heal. The server sends the heal log before the
-- target's new health, so at this point UnitHealth is still the health before the heal:
-- what fits under max health is effective, the rest overheal. `pending` holds healing
-- already counted since the target's last health update, so several heals landing
-- together don't each think they have the whole gap to fill. Heals on units outside the
-- group (whose health we can't read exactly) count as fully effective.
local pending = {} -- guid -> effective healing not yet in their health

local function Split(targetGuid, amount)
  local unit = unitOf[targetGuid]
  if not unit or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
    return amount, 0
  end
  local hp, max = UnitHealth(unit), UnitHealthMax(unit)
  if not hp or not max or max <= 0 then
    return amount, 0
  end
  local missing = math.max(0, max - hp - (pending[targetGuid] or 0))
  local effective = math.min(amount, missing)
  pending[targetGuid] = (pending[targetGuid] or 0) + effective
  return effective, amount - effective
end

local function Heal(targetGuid, casterGuid, amount, spellId)
  local src = Owner(casterGuid)
  if not amount or amount <= 0 then
    return
  end
  -- always split, so `pending` stays right even for heals we don't record
  local effective, over = Split(targetGuid, amount)
  -- heals don't start a fight (topping people off), they only count during one
  if not src or not current then
    return
  end
  Record(function(seg)
    local a = Actor(seg, src)
    a.heal = a.heal + effective
    a.overheal = a.overheal + over
    a.hspells[spellId] = (a.hspells[spellId] or 0) + effective
    if over > 0 then
      a.ospells[spellId] = (a.ospells[spellId] or 0) + over
    end
  end)
end

local function Died(guid)
  local who = roster[guid] and guid
  if who and current then
    Record(function(seg)
      local a = Actor(seg, who)
      a.deaths = a.deaths + 1
    end)
  end
end

local combat = CreateFrame("Frame")
combat:SetScript("OnEvent", function()
  if event == "SPELL_DAMAGE_EVENT_SELF" or event == "SPELL_DAMAGE_EVENT_OTHER" then
    -- target, caster, spellId, amount, mitigation, hitInfo, school, "eff1,eff2,eff3,auraType"
    -- aura type 89 reports a percentage of health, not damage: skip those
    if arg8 and string.find(arg8, ",89$") then
      return
    end
    Damage(arg2, arg1, arg4, arg3)
  elseif event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
    -- attacker, target, totalDamage, ...
    Damage(arg1, arg2, arg3, 0)
  elseif event == "DAMAGE_SHIELD_SELF" or event == "DAMAGE_SHIELD_OTHER" then
    -- shield owner, attacker who got hit, damage, school
    Damage(arg1, arg2, arg3, -1)
  elseif event == "SPELL_HEAL_BY_SELF" or event == "SPELL_HEAL_BY_OTHER" then
    -- target, caster, spellId, amount, critical, periodic
    Heal(arg1, arg2, arg4, arg3)
  elseif event == "UNIT_HEALTH" then
    -- their health now includes the heals we were holding (arg1 is a unit token, or a
    -- GUID with Nampower's GUID unit events)
    local guid = guidOf[arg1] or arg1
    if guid then pending[guid] = nil end
  elseif event == "UNIT_DIED" then
    Died(arg1)
  else
    BuildRoster()
  end
end)

-- [[ threat (server TWThreat API) ]] --
local threat = { list = {}, at = 0 }

local function ThreatChannel()
  if GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers() > 0 then return "PARTY" end
end

local function RequestThreat()
  local channel = ThreatChannel()
  if not channel or not UnitExists("target") or not UnitCanAttack("player", "target") or not UnitAffectingCombat("target") then
    return
  end
  SendAddonMessage(THREAT_REQUEST, "limit=40", channel)
end

-- "TWTv4=Name:tank:threat:percent:melee;Name:..." for your current target
local function ThreatPacket(msg)
  local _, e = string.find(msg, THREAT_API, 1, true)
  if not e then
    return
  end
  local list = {}
  for name, tank, value, perc in string.gfind(string.sub(msg, e + 1), "([^:;]+):(%d):(%d+):(%d+):%d") do
    table.insert(list, { name = name, tank = tank == "1", threat = tonumber(value), perc = tonumber(perc) })
  end
  table.sort(list, function(a, b) return a.threat > b.threat end)
  threat.list, threat.at = list, GetTime()
  threat.target = UnitName("target")
end


-- [[ windows ]] --
-- Any number of windows, each with its own settings (what it shows, which fight, size) and
-- its own holder for /snap. The fight data above is shared by all of them. Window 1 keeps
-- the original "meter" keys, so its settings and position carried over from one window.
local windows = {} -- open windows in creation order
local cfg          -- db.frames.meters = { ids = { 1, 3, ... }, nextId = n }
local HEADER = 20

local function Key(id)
  return id == 1 and "meter" or ("meter" .. id)
end

local function Short(n)
  if n < 1000 then
    return tostring(math.floor(n + 0.5))
  end
  return S.ShortNumber(math.floor(n + 0.5))
end

local function PerSec(n)
  if n < 100 then
    return string.format("%.1f", n)
  end
  return Short(n)
end

local function Clock(sec)
  sec = math.floor(sec)
  return string.format("%d:%02d", math.floor(sec / 60), math.mod(sec, 60))
end

-- share of all healing cast that was wasted, as a whole percentage
local function Pct(part, whole)
  return whole > 0 and math.floor(part / whole * 100 + 0.5) or 0
end

local function OverPct(a)
  return Pct(a.overheal, a.heal + a.overheal)
end

-- the segment a window shows: s.segment is "current", "overall" or a history index
local function Shown(w)
  local seg = w.s.segment
  if seg == "overall" then
    return overall
  elseif seg == "current" then
    return current or history[1]
  end
  return history[seg] or current or history[1]
end

local function SegmentLabel(seg)
  if not seg then
    return "No fights yet"
  end
  if seg == overall then
    return "Overall"
  end
  if seg == current then
    return "Current " .. Clock(Duration(seg))
  end
  return (seg.name or "Fight") .. " " .. Clock(Duration(seg))
end

-- sorted { name, class, value, actor } for what a window shows
local function Entries(w)
  local mode = MODE_BY_KEY[w.s.mode] or MODES[1]
  local list = {}
  if mode.key == "threat" then
    for _, t in ipairs(threat.list) do
      local class
      for _, r in pairs(roster) do
        if r.name == t.name then class = r.class end
      end
      table.insert(list, { name = t.name, class = class, value = t.perc, threat = t })
    end
    return list, mode
  end
  local seg = Shown(w)
  if not seg then
    return list, mode
  end
  for _, a in pairs(seg.actors) do
    local v = a[mode.field] or 0
    if v > 0 then
      table.insert(list, { name = a.name, class = a.class, value = v, actor = a })
    end
  end
  table.sort(list, function(x, y) return x.value > y.value end)
  return list, mode
end

local function Refresh(w)
  local s, win = w.s, w.win
  if not win or not win:IsShown() then
    return
  end
  local list, mode = Entries(w)
  local seg = Shown(w)
  local total, top = 0, 0
  for _, e in ipairs(list) do
    total = total + e.value
    if e.value > top then top = e.value end
  end
  win.mode.text:SetText(mode.label)
  if mode.key == "threat" then
    win.segment.text:SetText(threat.target or (ThreatChannel() and "No target" or "Needs a group"))
  else
    win.segment.text:SetText(SegmentLabel(seg))
  end

  local n = table.getn(list)
  w.scroll = math.max(0, math.min(w.scroll, n - s.rows))
  for i = 1, s.rows do
    local row = w.rows[i]
    local e = list[i + w.scroll]
    if e then
      local c = (e.class and S.CLASS[e.class]) or { 0.6, 0.6, 0.6 }
      row.bar:SetStatusBarColor(c[1], c[2], c[3], 0.85)
      row.bar:SetValue(top > 0 and e.value / top or 0)
      row.left:SetText((i + w.scroll) .. ". " .. e.name)
      if mode.key == "threat" then
        local t = e.threat
        row.right:SetText(Short(t.threat) .. "  " .. t.perc .. "%" .. (t.tank and "  |cffff5050tank|r" or ""))
      elseif mode.key == "deaths" then
        row.right:SetText(tostring(e.value))
      else
        local pct = total > 0 and math.floor(e.value / total * 100 + 0.5) or 0
        local text = Short(e.value) .. " (" .. PerSec(e.value / Duration(seg)) .. ", " .. pct .. "%)"
        -- healing also shows how much of it was wasted
        if mode.over then
          text = text .. " |cff9999ff" .. OverPct(e.actor) .. "% OH|r"
        end
        row.right:SetText(text)
      end
      row.entry, row.mode, row.seg = e, mode, seg
      row:Show()
    else
      row.entry = nil
      row:Hide()
    end
  end
end

local function RefreshAll()
  for _, w in ipairs(windows) do
    Refresh(w)
  end
end

-- [[ bar tooltip: the spell (or attacker) breakdown ]] --
local function RowTooltip()
  local e, mode = this.entry, this.mode
  if not e then
    return
  end
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText(e.name)
  if e.threat then
    GameTooltip:AddDoubleLine("Threat", Short(e.threat.threat), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Of the tank's / pull", e.threat.perc .. "%", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:Show()
    return
  end
  local a = e.actor
  local tbl = mode.spells and a[mode.spells]
  if mode.over then
    GameTooltip:AddDoubleLine("Effective", Short(a.heal), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Overhealing", Short(a.overheal) .. " (" .. OverPct(a) .. "%)", 0.8, 0.8, 0.8, 0.6, 0.6, 1)
    GameTooltip:AddLine(" ")
  end
  if tbl then
    local spells = {}
    for key, v in pairs(tbl) do
      table.insert(spells, { key = key, v = v })
    end
    table.sort(spells, function(x, y) return x.v > y.v end)
    for i = 1, math.min(10, table.getn(spells)) do
      local sp = spells[i]
      local label
      if mode.key == "taken" then
        label = NameOf(sp.key)
      elseif sp.key == -1 then
        label = "Damage shield"
      else
        label = SpellName(sp.key)
      end
      local right = Short(sp.v) .. " (" .. Pct(sp.v, e.value) .. "%)"
      -- each heal spell's own wasted share
      if mode.over then
        local over = a.ospells[sp.key] or 0
        right = right .. " |cff9999ff" .. Pct(over, sp.v + over) .. "% OH|r"
      end
      GameTooltip:AddDoubleLine(label, right, 1, 1, 1, 0.8, 0.8, 0.8)
    end
  end
  if this.seg then
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Fight length", Clock(Duration(this.seg)), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

-- [[ little pop-up menu for picking a mode or a segment ]] --
local menu
local function Menu(anchor, items)
  if not menu then
    menu = CreateFrame("Frame", "SnapUI_MeterMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    S.Backdrop(menu, 0.97)
    menu.items = {}
    menu:SetScript("OnUpdate", function()
      if MouseIsOver(menu) or (menu.anchor and MouseIsOver(menu.anchor)) then
        this.away = 0
      else
        this.away = (this.away or 0) + arg1
        if this.away > 0.8 then this:Hide() end
      end
    end)
  end
  if menu:IsShown() and menu.anchor == anchor then
    menu:Hide()
    return
  end
  for _, b in ipairs(menu.items) do b:Hide() end
  local width = 120
  for i, it in ipairs(items) do
    local item = it
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(18)
      b.text = S.Text(b, 12, "LEFT")
      b.text:SetPoint("LEFT", 6, 0)
      b.hl = b:CreateTexture(nil, "BACKGROUND")
      b.hl:SetAllPoints(b)
      b.hl:SetTexture(S.TEX)
      b.hl:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.25)
      b.hl:Hide()
      b:SetScript("OnEnter", function() this.hl:Show() end)
      b:SetScript("OnLeave", function() this.hl:Hide() end)
      menu.items[i] = b
    end
    b.text:SetText(item.selected and ("|cff4fc3f7" .. item.label .. "|r") or item.label)
    b:SetScript("OnClick", function() menu:Hide(); item.fn() end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 18)
    b:SetPoint("RIGHT", menu, "RIGHT", -2, 0)
    b:Show()
    width = math.max(width, b.text:GetStringWidth() + 16)
  end
  menu:SetWidth(width)
  menu:SetHeight(4 + table.getn(items) * 18)
  menu:ClearAllPoints()
  local _, y = anchor:GetCenter()
  if y and y > UIParent:GetHeight() / 2 then
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  else
    menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
  end
  menu.anchor = anchor
  menu.away = 0
  menu:Show()
end

local function ModeMenu(w)
  local items = {}
  for _, m in ipairs(MODES) do
    local key = m.key
    table.insert(items, { label = m.label, selected = w.s.mode == key,
      fn = function() w.s.mode = key; w.scroll = 0; Refresh(w) end })
  end
  Menu(w.win.mode, items)
end

local function SegmentMenu(w)
  local s = w.s
  local items = {
    { label = "Current fight", selected = s.segment == "current", fn = function() s.segment = "current"; Refresh(w) end },
    { label = "Overall", selected = s.segment == "overall", fn = function() s.segment = "overall"; Refresh(w) end },
  }
  for i, seg in ipairs(history) do
    local idx = i
    table.insert(items, { label = SegmentLabel(seg) .. (next(seg.bosses) and " |cffff9926(boss)|r" or ""),
      selected = s.segment == idx, fn = function() s.segment = idx; Refresh(w) end })
  end
  table.insert(items, { label = "|cffff6060Clear all fights|r", fn = function() StaticPopup_Show("SNAPUI_METER_RESET") end })
  Menu(w.win.segment, items)
end

local function Reset()
  current, overall = nil, nil
  for i = table.getn(history), 1, -1 do
    table.remove(history, i)
  end
  for _, w in ipairs(windows) do
    w.s.segment = "current"
  end
  RefreshAll()
end

-- [[ building a window ]] --
local function HeaderButton(parent, justify)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(HEADER)
  b.text = S.Text(b, 12, justify)
  b.text:SetAllPoints(b)
  b:SetScript("OnEnter", function() this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3]) end)
  b:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1) end)
  return b
end

local function Layout(w)
  local s, win, rows = w.s, w.win, w.rows
  local bh = s.barHeight
  win:SetWidth(s.width)
  win:SetHeight(HEADER + s.rows * (bh + 1) + 1)
  win:SetScale(s.scale)
  win:SetBackdropColor(0.05, 0.05, 0.05, s.alpha)
  for i = 1, math.max(s.rows, table.getn(rows)) do
    local row = rows[i]
    if not row and i <= s.rows then
      row = CreateFrame("Button", nil, win)
      row.bar = S.StatusBar(row)
      row.bar:SetAllPoints(row)
      row.left = S.Text(row.bar.over, 12, "LEFT")
      row.left:SetPoint("LEFT", 4, 0)
      row.right = S.Text(row.bar.over, 12, "RIGHT")
      row.right:SetPoint("RIGHT", -4, 0)
      row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
      row:EnableMouse(true)
      row:SetScript("OnEnter", RowTooltip)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
      rows[i] = row
    end
    if row then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -HEADER - (i - 1) * (bh + 1))
      row:SetPoint("RIGHT", win, "RIGHT", -1, 0)
      row:SetHeight(bh)
      if i > s.rows then row:Hide() end
    end
  end
  S:Fit(w.holder, win)
  if s.hidden then win:Hide() else win:Show() end
  Refresh(w)
end

local NewWindow, CloseWindow

local function CreateWindow(w)
  local win = CreateFrame("Frame", "SnapUI_" .. w.key, w.holder)
  w.win = win
  win:SetPoint("TOPLEFT", w.holder, "TOPLEFT", 0, 0)
  win:SetFrameStrata("MEDIUM")
  S.Backdrop(win, w.s.alpha)
  win:EnableMouseWheel(true)
  win:SetScript("OnMouseWheel", function()
    w.scroll = math.max(0, w.scroll - arg1)
    Refresh(w)
  end)

  local head = win:CreateTexture(nil, "BORDER")
  head:SetTexture(S.TEX)
  head:SetVertexColor(0, 0, 0, 0.5)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEADER - 2)

  win.mode = HeaderButton(win, "LEFT")
  win.mode:SetPoint("TOPLEFT", win, "TOPLEFT", 6, 0)
  win.mode:SetWidth(100)
  win.mode:SetScript("OnClick", function() ModeMenu(w) end)

  local close = HeaderButton(win, "CENTER")
  close:SetWidth(14)
  close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -3, 0)
  close.text:SetText("x")
  close:SetScript("OnClick", function() CloseWindow(w) end)
  close:SetScript("OnEnter", function()
    this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3])
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(table.getn(windows) > 1 and "Close this window" or "Hide the meter (/meter shows it)")
    GameTooltip:Show()
  end)
  close:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1); GameTooltip:Hide() end)

  local add = HeaderButton(win, "CENTER")
  add:SetWidth(14)
  add:SetPoint("RIGHT", close, "LEFT", -2, 0)
  add.text:SetText("+")
  add:SetScript("OnClick", function() NewWindow() end)
  add:SetScript("OnEnter", function()
    this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3])
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("New meter window")
    GameTooltip:Show()
  end)
  add:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1); GameTooltip:Hide() end)

  win.segment = HeaderButton(win, "RIGHT")
  win.segment:SetPoint("TOPRIGHT", add, "TOPLEFT", -4, 0)
  win.segment:SetPoint("LEFT", win.mode, "RIGHT", 4, 0)
  win.segment:SetScript("OnClick", function() SegmentMenu(w) end)
end

-- a window for `id`; `default` is where it goes when it has no saved spot yet
local function OpenWindow(id, default, mode)
  local key = Key(id)
  local w = { id = id, key = key, rows = {}, scroll = 0 }
  w.s = S:Settings("frames", key, { width = 240, rows = 8, barHeight = 16, scale = 1, alpha = 0.6,
    hidden = false, mode = mode or "damage", segment = "current" })
  -- history indexes don't survive a reload
  if type(w.s.segment) == "number" then
    w.s.segment = "current"
  end
  w.holder = S:Holder(key, id == 1 and "Meter" or ("Meter " .. id), default, {})
  w.holder.isOff = function() return w.s.hidden end
  CreateWindow(w)

  local s = w.s
  local function Opt(label, field, min, max, step)
    table.insert(w.holder.options, { label = label, get = function() return s[field] end,
      set = function(v) s[field] = v; Layout(w) end, min = min, max = max, step = step })
  end
  Opt("Width", "width", 140, 500, 10)
  Opt("Bars", "rows", 3, 25, 1)
  Opt("Bar height", "barHeight", 10, 30, 1)
  Opt("Scale", "scale", 0.5, 2, 0.05)
  Opt("Background", "alpha", 0, 1, 0.05)
  table.insert(w.holder.options, { label = "Hidden", toggle = true, get = function() return s.hidden end,
    set = function(v) s.hidden = v; Layout(w) end })

  table.insert(windows, w)
  Layout(w)
  return w
end

-- a new window opens beside the newest one, showing the next view along
function NewWindow()
  local id = cfg.nextId
  cfg.nextId = id + 1
  table.insert(cfg.ids, id)
  local last = windows[table.getn(windows)]
  local default = last and { "TOPRIGHT", "TOPLEFT", -6, 0, last.holder } or { "BOTTOMRIGHT", nil, -4, 200 }
  local mode = MODES[math.mod(table.getn(windows), table.getn(MODES)) + 1].key
  local w = OpenWindow(id, default, mode)
  w.s.hidden = false
  -- save its spot straight away, so it stays put if the window it opened beside closes
  local x, y = w.holder:GetCenter()
  local cx, cy = UIParent:GetCenter()
  if x and cx then
    S:SavePosition(w.holder, x - cx, y - cy)
    S:Place(w.holder)
  end
  Layout(w)
  return w
end

-- the last window just hides; any other one goes for good (settings and spot too)
function CloseWindow(w)
  if table.getn(windows) <= 1 then
    w.s.hidden = true
    Layout(w)
    S.Print("meter hidden. |cff4fc3f7/meter|r shows it again.")
    return
  end
  w.holder:Hide()
  for i, other in ipairs(windows) do
    if other == w then table.remove(windows, i) break end
  end
  for i, id in ipairs(cfg.ids) do
    if id == w.id then table.remove(cfg.ids, i) break end
  end
  for i, h in ipairs(S.holders) do
    if h == w.holder then table.remove(S.holders, i) break end
  end
  S.byName[w.key] = nil
  S.db.frames[w.key] = nil
  S.db.pos[w.key] = nil
end

-- [[ report to chat ]] --
local function Report(w, count)
  local list, mode = Entries(w)
  if table.getn(list) == 0 then
    S.Print("nothing to report")
    return
  end
  local channel = ThreatChannel() or "SAY"
  local seg = Shown(w)
  local title = mode.label .. (mode.key == "threat" and (" on " .. (threat.target or "?")) or (" - " .. SegmentLabel(seg)))
  SendChatMessage("SnapUI meter: " .. title, channel)
  for i = 1, math.min(count, table.getn(list)) do
    local e = list[i]
    local value
    if mode.key == "threat" then
      value = e.threat.perc .. "%"
    elseif mode.perSec then
      value = Short(e.value) .. " (" .. PerSec(e.value / Duration(seg)) .. "/s)"
      if mode.over then
        value = value .. " " .. OverPct(e.actor) .. "% overheal"
      end
    else
      value = tostring(e.value)
    end
    SendChatMessage(i .. ". " .. e.name .. " " .. value, channel)
  end
end

-- the first window on screen (for /meter report and the like)
local function FirstShown()
  for _, w in ipairs(windows) do
    if not w.s.hidden then return w end
  end
  return windows[1]
end

-- [[ module ]] --
S:RegisterModule("meter", function()
  cfg = S:Settings("frames", "meters", { ids = { 1 }, nextId = 2 })
  for i, id in ipairs(cfg.ids) do
    local prev = windows[i - 1]
    local default = prev and { "TOPRIGHT", "TOPLEFT", -6, 0, prev.holder } or { "BOTTOMRIGHT", nil, -4, 200 }
    OpenWindow(id, default)
  end

  StaticPopupDialogs["SNAPUI_METER_RESET"] = {
    text = "Clear all meter data?",
    button1 = YES, button2 = NO,
    OnAccept = Reset,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
  }

  -- Nampower events (4.5+ turns the auto-attack and heal ones on when registered)
  for _, e in ipairs({ "SPELL_DAMAGE_EVENT_SELF", "SPELL_DAMAGE_EVENT_OTHER", "AUTO_ATTACK_SELF", "AUTO_ATTACK_OTHER",
    "DAMAGE_SHIELD_SELF", "DAMAGE_SHIELD_OTHER", "SPELL_HEAL_BY_SELF", "SPELL_HEAL_BY_OTHER", "UNIT_DIED", "UNIT_HEALTH",
    "PLAYER_ENTERING_WORLD", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET" }) do
    pcall(combat.RegisterEvent, combat, e)
  end
  BuildRoster()

  local addon = CreateFrame("Frame")
  addon:RegisterEvent("CHAT_MSG_ADDON")
  addon:SetScript("OnEvent", function()
    if arg2 and string.find(arg2, THREAT_API, 1, true) then
      ThreatPacket(arg2)
    end
  end)

  -- fight end, threat polling and redraws
  local tick, poll = 0, 0
  local timer = CreateFrame("Frame")
  timer:SetScript("OnUpdate", function()
    tick, poll = tick + arg1, poll + arg1
    if poll >= 1 then
      poll = 0
      for _, w in ipairs(windows) do
        if w.s.mode == "threat" and not w.s.hidden then
          RequestThreat()
          break
        end
      end
    end
    if tick < 0.5 then
      return
    end
    tick = 0
    -- a fight ends once nobody in the group is in combat and things have gone quiet
    if current and GetTime() - lastEvent > 2 then
      local fighting = UnitAffectingCombat("player")
      if not fighting then
        local raid = GetNumRaidMembers()
        for i = 1, (raid > 0 and raid or GetNumPartyMembers()) do
          if UnitAffectingCombat(raid > 0 and ("raid" .. i) or ("party" .. i)) then
            fighting = true
            break
          end
        end
      end
      if not fighting then
        EndFight()
      end
    end
    -- old threat numbers are worse than none
    if threat.at > 0 and GetTime() - threat.at > 5 then
      threat.list, threat.at, threat.target = {}, 0, nil
    end
    RefreshAll()
  end)
end, "Damage meter", "Details-style damage, healing and threat meter.")

-- [[ slash command ]] --
SLASH_SNAPMETER1 = "/meter"
SlashCmdList["SNAPMETER"] = function(msg)
  msg = string.lower(msg or "")
  local _, _, cmd, arg = string.find(msg, "^(%S*)%s*(.-)$")
  if not cfg then
    return
  end
  if cmd == "reset" then
    Reset()
    S.Print("meter cleared")
  elseif cmd == "new" then
    NewWindow()
  elseif cmd == "report" then
    Report(FirstShown(), tonumber(arg) or 5)
  elseif MODE_BY_KEY[cmd] then
    local w = FirstShown()
    w.s.mode = cmd
    Refresh(w)
  elseif cmd == "help" then
    S.Print("/meter  show or hide all meter windows")
    S.Print("/meter new  open another window (or click + on a window)")
    S.Print("/meter damage | healing | overheal | taken | deaths | threat  switch the first window's view")
    S.Print("/meter report [n]  post the first window's top n to party/raid (or say)")
    S.Print("/meter reset  clear all fights")
  else
    -- hide them all if any is showing, otherwise show them all
    local anyShown = false
    for _, w in ipairs(windows) do
      if not w.s.hidden then anyShown = true end
    end
    for _, w in ipairs(windows) do
      w.s.hidden = anyShown
      Layout(w)
    end
  end
end
