-- Who's the tank and who's the healer, for the role icons on party and raid cells.
-- 1.12 has no group roles, so they come from, best first:
--   set     you picked it (Alt-right-click a cell, or /snap role)
--   finder  OctoWoW's dungeon finder said so (your own queued role, role-check answers)
--   guess   seen in play: Bear Form or Righteous Fury, holding the mobs, healing others
-- Set and finder roles are saved while that person stays in your group; guesses are
-- rebuilt each session.

local S = SnapUI

local ICONS = {
  tank = "Interface\\FrameXML\\LFT\\images\\tank2",
  healer = "Interface\\FrameXML\\LFT\\images\\healer2",
}
S.ROLE_ICONS = ICONS

local NAMES = { tank = "Tank", healer = "Healer", none = "Damage" }
local FROM = { set = "set by you", finder = "from the dungeon finder", guess = "guessed" }

local saved -- SnapUIDB.roles[name] = { role = "tank" | "healer" | "none", from = "set" | "finder" }
local guessed, why = {}, {} -- this session's guesses, and the reason shown in tooltips
local aggro, heals = {}, {} -- per name: mobs seen on them, heals cast on others
local listeners = {}
local s

local function Changed()
  for _, fn in ipairs(listeners) do
    fn()
  end
end

function S:OnRoles(fn)
  table.insert(listeners, fn)
end

-- [[ the group ]] --
local function Units()
  local list = {}
  if GetNumRaidMembers() > 0 then
    for i = 1, 40 do
      table.insert(list, "raid" .. i)
    end
  else
    table.insert(list, "player")
    for i = 1, 4 do
      table.insert(list, "party" .. i)
    end
  end
  return list
end

local function InGroup()
  return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

local function Norm(guid)
  if not guid or guid == "" then return nil end
  guid = string.gsub(string.upper(guid), "^0X", "")
  guid = string.gsub(guid, "^0+", "")
  return guid ~= "" and guid or nil
end

-- forget everyone who isn't with us any more
local function Prune()
  local here = {}
  for _, u in ipairs(Units()) do
    local n = UnitExists(u) and UnitName(u)
    if n then here[n] = true end
  end
  for _, list in ipairs({ saved, guessed, why, aggro, heals }) do
    for name in pairs(list) do
      if not here[name] then list[name] = nil end
    end
  end
end

-- [[ what the frames ask ]] --
-- role ("tank", "healer" or nil) and where it came from
function S.Role(unit)
  local name = unit and UnitExists(unit) and UnitName(unit)
  if not name then return nil end
  local r = saved and saved[name]
  if r then
    if r.role == "none" then return nil, r.from end
    return r.role, r.from
  end
  if s and s.guess and guessed[name] then
    return guessed[name], "guess"
  end
end

function S.RoleIcon(role)
  return role and ICONS[role]
end

-- a line for the cell's tooltip
function S.RoleText(unit)
  local name = UnitName(unit)
  local r = saved and name and saved[name]
  local role, from = S.Role(unit)
  local text
  if r and r.role == "none" then
    text = "Damage (" .. FROM[r.from] .. ")"
  elseif role then
    text = NAMES[role] .. " (" .. (from == "guess" and (why[name] or "guessed") or FROM[from]) .. ")"
  else
    text = "unknown"
  end
  return "Role: " .. text
end

-- set by you: a role, "none" (no icon even if guessed), or nil to go back to automatic
function S.SetRole(unit, role)
  local name = unit and UnitExists(unit) and UnitName(unit)
  if not name or not saved then return end
  saved[name] = role and { role = role, from = "set" } or nil
  Changed()
  return name
end

-- Alt-right-click: automatic -> tank -> healer -> damage -> automatic
function S.CycleRole(unit)
  local name = UnitName(unit)
  local r = saved and name and saved[name]
  local now = r and r.from == "set" and r.role or nil
  local nextRole = (not now and "tank") or (now == "tank" and "healer") or (now == "healer" and "none") or nil
  S.SetRole(unit, nextRole)
  S.Print(name .. ": " .. (nextRole and NAMES[nextRole] or "automatic") .. ".")
end

-- [[ the dungeon finder ]] --
local CODE = { t = "tank", h = "healer", d = "none" }

local function Split(text, sep)
  local out = {}
  for part in string.gfind(text or "", "([^" .. sep .. "]+)") do
    table.insert(out, part)
  end
  return out
end

local function FromFinder(name, code)
  local role = CODE[code]
  if not name or not role then return end
  local r = saved[name]
  if r and r.from == "set" then return end -- yours wins
  saved[name] = { role = role, from = "finder" }
  Changed()
end

local function FinderMessage(msg, sender)
  local field = LFT_ADDON_FIELD_DELIMITER or ";"
  local array = LFT_ADDON_ARRAY_DELIMITER or ":"
  if string.find(msg, "S2C_OFFER_NEW", 1, true) then
    -- a group was found for you: instance;your role
    local p = Split(msg, field)
    FromFinder(UnitName("player"), p[3])
  elseif string.find(msg, "S2C_ROLECHECK_INFO", 1, true) then
    -- someone answered the role check; only a single role tells us anything
    local p = Split(msg, field)
    local roles = Split(p[3], array)
    if table.getn(roles) == 1 then
      FromFinder(p[2], roles[1])
    end
  elseif string.find(msg, "C2C_ROLECHECK_RESPONSE", 1, true) then
    FromFinder(sender, string.sub(msg, -1))
  end
end

-- [[ guessing ]] --
local TANK_AURAS = {
  { "Bear Form", "Interface\\Icons\\Ability_Racial_BearForm" },
  { "Dire Bear Form", "Interface\\Icons\\Ability_Racial_BearForm" },
  { "Righteous Fury", "Interface\\Icons\\Spell_Holy_SealOfFury" },
}

local function TankAura(unit)
  for _, a in ipairs(TANK_AURAS) do
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
      if C_UnitAuras.GetAuraDataBySpellName(unit, a[1], "HELPFUL") then return a[1] end
    else
      for i = 1, 32 do
        local tex = UnitBuff(unit, i)
        if not tex then break end
        if tex == a[2] then return a[1] end
      end
    end
  end
end

local function Best(list, minimum)
  local best, top, total = nil, 0, 0
  for name, n in pairs(list) do
    total = total + n
    if n > top then best, top = name, n end
  end
  if top >= minimum then return best, top, total end
end

local function Guess()
  local old = {}
  for k, v in pairs(guessed) do old[k] = v end
  for k in pairs(guessed) do guessed[k] = nil end
  for k in pairs(why) do why[k] = nil end
  -- the tank: a tanking form or aura, else whoever the mobs keep hitting (most of the time)
  for _, u in ipairs(Units()) do
    local name = UnitExists(u) and UnitName(u)
    local aura = name and TankAura(u)
    if aura then
      guessed[name], why[name] = "tank", "guessed: " .. aura
    end
  end
  local tank, n, total = Best(aggro, 8)
  if tank and not guessed[tank] and n >= total * 0.5 then
    guessed[tank], why[tank] = "tank", "guessed: holds the mobs"
  end
  -- the healer: whoever heals other people the most
  local healer = Best(heals, 3)
  if healer and not guessed[healer] then
    guessed[healer], why[healer] = "healer", "guessed: heals the group"
  end
  for k, v in pairs(guessed) do
    if old[k] ~= v then return Changed() end
  end
  for k in pairs(old) do
    if not guessed[k] then return Changed() end
  end
end

-- every half second in combat: which group member each mob we're fighting is on
local function SampleAggro()
  local seen = {}
  local members = {}
  for _, u in ipairs(Units()) do
    if UnitExists(u) then members[UnitName(u) or ""] = true end
  end
  for _, u in ipairs(Units()) do
    local mob = u .. "target"
    if UnitExists(mob) and UnitCanAttack("player", mob) and UnitAffectingCombat(mob) and not UnitIsPlayer(mob) then
      local id = (UnitGUID and UnitGUID(mob)) or (UnitName(mob) .. UnitHealth(mob))
      local on = UnitExists(mob .. "target") and UnitName(mob .. "target")
      if not seen[id] and on and members[on] then
        seen[id] = true
        aggro[on] = (aggro[on] or 0) + 1
      end
    end
  end
  -- older fights count for less
  for name, n in pairs(aggro) do
    aggro[name] = n * 0.995
  end
end

-- a finished heal (nampower's SPELL_GO events) from one group member on another
local function HealCast(spellId, caster, target)
  caster, target = Norm(caster), Norm(target)
  if not caster or not target or caster == target or not S.HealAmount or not S.HealAmount(spellId) then
    return
  end
  local from, to
  for _, u in ipairs(Units()) do
    local g = UnitExists(u) and UnitGUID and Norm(UnitGUID(u))
    if g == caster then from = UnitName(u) end
    if g == target then to = UnitName(u) end
  end
  if from and to then
    heals[from] = (heals[from] or 0) + 1
  end
end

-- [[ /snap role ]] --
function S:RoleCommand(arg)
  local unit = UnitExists("target") and UnitIsPlayer("target") and "target" or "player"
  local roles = { tank = "tank", healer = "healer", heal = "healer", dps = "none", damage = "none", none = "none" }
  if arg == "auto" or arg == "clear" then
    S.Print(S.SetRole(unit, nil) .. ": automatic.")
  elseif roles[arg] then
    S.Print(S.SetRole(unit, roles[arg]) .. ": " .. NAMES[roles[arg]] .. ".")
  else
    S.Print("/snap role tank | healer | dps | auto  sets your target's role (yourself with no target).")
    S.Print("Or Alt-right-click a party or raid cell to cycle it.")
  end
end

function S:RoleOptions()
  return {
    { label = "Guess roles from play", toggle = true, get = function() return s.guess end,
      set = function(v) s.guess = v; Changed() end },
  }
end

S:RegisterModule("roles", function()
  s = S:Settings("frames", "roles", { guess = true })
  SnapUIDB.roles = SnapUIDB.roles or {}
  saved = SnapUIDB.roles

  local f = CreateFrame("Frame")
  for _, e in ipairs({ "CHAT_MSG_ADDON", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_AURA" }) do
    f:RegisterEvent(e)
  end
  pcall(f.RegisterEvent, f, "SPELL_GO_OTHER")
  pcall(f.RegisterEvent, f, "SPELL_GO_SELF")
  f:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
      if arg1 == (LFT_ADDON_PREFIX or "TW_LFG") then
        FinderMessage(arg2 or "", arg4)
      end
    elseif event == "SPELL_GO_OTHER" or event == "SPELL_GO_SELF" then
      -- itemId, spellId, casterGuid, targetGuid, ...
      HealCast(arg2, arg3, arg4)
    elseif event == "UNIT_AURA" then
      f.dirty = true
    else
      if InGroup() then
        f.grouped = true
        Prune()
      elseif f.grouped then
        -- left the group: nothing to remember (only once we've seen the group; right
        -- after a reload the roster can read empty for a moment)
        f.grouped = nil
        for _, list in ipairs({ saved, guessed, why, aggro, heals }) do
          for k in pairs(list) do list[k] = nil end
        end
      end
      Changed()
    end
  end)

  local t, g = 0, 0
  f:SetScript("OnUpdate", function()
    t, g = t + arg1, g + arg1
    if t >= 0.5 then
      t = 0
      if InGroup() and UnitAffectingCombat("player") then
        SampleAggro()
      end
    end
    if g >= 2 or (f.dirty and g >= 0.5) then
      g, f.dirty = 0, nil
      if InGroup() then Guess() end
    end
  end)
end, "Roles", "Tank and healer icons on party and raid frames: from the dungeon finder, set by you, or guessed from play.")

-- for the harness tests (not a HarnessExtra entry: those get called)
S.RolesTest = { finder = FinderMessage, heal = HealCast, sample = SampleAggro, guess = Guess }
