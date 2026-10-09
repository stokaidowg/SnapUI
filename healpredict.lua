-- SnapUI heal prediction and cast targets, HealComm-style but with no addon needed on the
-- other end: nampower reports every spell start with its caster, target and cast time
-- (SPELL_START_SELF/OTHER), and when it lands or stops (SPELL_GO_*, SPELL_FAILED_*).
-- For heals, the amount is the spell's own base value from GetSpellRec (the average of its
-- heal effects), so incoming heals show on health bars as a translucent segment past the
-- current health. Your own heals add your gear's +healing (the "Equip: Increases healing"
-- and spell damage lines) at the usual cast time / 3.5 s share; other healers' gear isn't
-- known, so theirs run a little low.
-- The same tracking gives every cast's target, which the cast bars can show, and the power
-- your own cast is about to spend (ClassicAPI's C_Spell.GetSpellPowerCost, talents included),
-- which the player's power bars shade in until the cast lands or stops.

local S = SnapUI
local casts = {}      -- caster guid -> { target = guid, ends = time, amount = n or nil, spell = id }
local healAmount = {} -- spell id -> average heal, or false for spells that don't heal
local listeners = {}
local dirty = false
local HEAL_EFFECT = 10 -- SPELL_EFFECT_HEAL
local s

local function Norm(guid)
  if not guid or guid == "" then
    return nil
  end
  guid = string.upper(guid)
  guid = string.gsub(guid, "^0X", "")
  guid = string.gsub(guid, "^0+", "")
  if guid == "" then
    return nil
  end
  return guid
end
S.NormGuid = Norm

-- spell record fields may be per-effect tables (1- or 0-based) or numbered fields
local function Field(rec, name, i)
  local v = rec[name]
  if type(v) == "table" then
    if v[i] ~= nil then return v[i] end
    return v[i - 1]
  end
  if i == 1 and v ~= nil then
    return v
  end
  return rec[name .. i] or rec[name .. (i - 1)]
end

function S.HealAmount(spellId)
  if not spellId then
    return nil
  end
  local cached = healAmount[spellId]
  if cached ~= nil then
    return cached or nil
  end
  local total = 0
  local ok, rec = pcall(GetSpellRec or S.noop, spellId)
  if ok and type(rec) == "table" then
    for i = 1, 3 do
      local ok2, effect = pcall(Field, rec, "effect", i)
      if ok2 and effect == HEAL_EFFECT then
        local base = tonumber(Field(rec, "effectBasePoints", i)) or 0
        local die = tonumber(Field(rec, "effectDieSides", i)) or 0
        total = total + base + (die > 0 and (die + 1) / 2 or 1)
      end
    end
  end
  healAmount[spellId] = total > 0 and total or false
  return total > 0 and total or nil
end

-- what one cast costs you right now, in your current power type (nil if nothing)
function S.SpellCost(spellId)
  if not (spellId and C_Spell and C_Spell.GetSpellPowerCost) then return nil end
  local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellId)
  if not ok or type(costs) ~= "table" then return nil end
  local ptype = UnitPowerType("player")
  for _, c in ipairs(costs) do
    if c.type == ptype and (tonumber(c.cost) or 0) > 0 then
      return tonumber(c.cost)
    end
  end
end

local function Changed()
  dirty = true
end

-- what your gear adds to a heal with this cast time (ms)
local function GearBonus(castMs)
  if not S.GearStat then
    return 0
  end
  local ok, bonus = pcall(function() return S:GearStat("heal") + S:GearStat("sp") end)
  if not ok or not bonus or bonus <= 0 then
    return 0
  end
  return bonus * math.min(1, castMs / 3500)
end

local function Start(spellId, caster, target, castTime)
  caster = Norm(caster)
  if not caster then return end
  local raw = Norm(target) and target or nil
  target = Norm(target) or caster
  local t = tonumber(castTime) or 0
  local amount = t > 0 and S.HealAmount(spellId) or nil
  local mine = caster == Norm(UnitGUID and UnitGUID("player"))
  if amount and mine then
    amount = amount + GearBonus(t)
  end
  -- instant casts pay at once, so only a cast with a cast time has a cost still to come
  local cost = mine and t > 0 and S.SpellCost(spellId) or nil
  casts[caster] = { target = target, raw = raw, spell = spellId, ends = GetTime() + t / 1000 + 0.3,
    amount = amount, cost = cost }
  Changed()
end

local function Stop(caster)
  caster = Norm(caster)
  if caster and casts[caster] then
    casts[caster] = nil
    Changed()
  end
end

-- [[ what other modules ask ]] --
-- the guid the caster's current cast is aimed at (nil for self casts and no cast)
function S.CastTarget(casterGuid)
  local c = casts[Norm(casterGuid) or ""]
  if c and c.raw and c.ends > GetTime() and c.target ~= Norm(casterGuid) then
    return c.raw
  end
end

-- "Name" in its class colour, for "Flash of Light > Name"
function S.CastTargetText(guid)
  local name = guid and UnitName(guid)
  if not name then return nil end
  local hex = "ffffff"
  if UnitIsPlayer(guid) then
    local _, class = UnitClass(guid)
    local c = S.CLASS[class]
    if c then hex = string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
  end
  return "|cff" .. hex .. name .. "|r"
end

-- heals on their way to `unit`
function S.IncomingHeal(unit)
  local guid = Norm(UnitGUID and UnitGUID(unit))
  if not guid then return 0 end
  local now, sum = GetTime(), 0
  for _, c in pairs(casts) do
    if c.amount and c.target == guid and c.ends > now then
      sum = sum + c.amount
    end
  end
  return sum
end

-- draw the incoming part on a health bar, just past its fill (either fill direction)
function S.DrawPrediction(bar, unit, enabled)
  if not bar.pred then
    bar.pred = bar:CreateTexture(nil, "ARTWORK")
    bar.pred:SetTexture(S.BAR or S.TEX)
    bar.pred:Hide()
  end
  local inc = (enabled and unit and (not s or s.enabled)) and S.IncomingHeal(unit) or 0
  local min, max = bar:GetMinMaxValues()
  local cur, w = bar:GetValue(), bar:GetWidth()
  -- NPC health on 1.12 is a percentage, so the heal's size can't be placed on it
  if inc <= 0 or max <= min or w <= 0 or cur >= max or (max == 100 and not UnitPlayerControlled(unit)) then
    bar.pred:Hide()
    return
  end
  local start = (cur - min) / (max - min)
  local frac = math.min(inc, max - cur) / (max - min)
  local c = s and s.color or { 0.25, 1, 0.45, 0.45 }
  bar.pred:ClearAllPoints()
  if bar.snapReverse then
    bar.pred:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -w * start, 0)
    bar.pred:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -w * start, 0)
  else
    bar.pred:SetPoint("TOPLEFT", bar, "TOPLEFT", w * start, 0)
    bar.pred:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", w * start, 0)
  end
  bar.pred:SetWidth(math.max(1, w * frac))
  bar.pred:SetVertexColor(c[1], c[2], c[3], c[4] or 0.45)
  bar.pred:Show()
end

-- the power your current cast will spend, 0 when not casting one
function S.PendingCost()
  local c = casts[Norm(UnitGUID and UnitGUID("player")) or ""]
  if c and c.cost and c.ends > GetTime() then
    return c.cost
  end
  return 0
end

-- shade the part of a power bar the cast will spend: the end of the fill, back by the cost
function S.DrawCost(bar, enabled, vertical)
  if not bar.cost then
    bar.cost = (bar.over or bar):CreateTexture(nil, "BORDER")
    bar.cost:SetTexture(S.BAR or S.TEX)
    bar.cost:Hide()
  end
  local cost = enabled and S.PendingCost() or 0
  local min, max = bar:GetMinMaxValues()
  local cur = bar:GetValue()
  local size = vertical and bar:GetHeight() or bar:GetWidth()
  if cost <= 0 or max <= min or size <= 0 or cur <= min then
    bar.cost:Hide()
    return
  end
  local stop = (cur - min) / (max - min)
  local frac = math.min(cost, cur - min) / (max - min)
  local from = size * (stop - frac)
  local c = s and s.costColor or { 0, 0, 0, 0.5 }
  bar.cost:ClearAllPoints()
  if vertical then
    bar.cost:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, from)
    bar.cost:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, from)
    bar.cost:SetHeight(math.max(1, size * frac))
  elseif bar.snapReverse then
    bar.cost:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -from, 0)
    bar.cost:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -from, 0)
    bar.cost:SetWidth(math.max(1, size * frac))
  else
    bar.cost:SetPoint("TOPLEFT", bar, "TOPLEFT", from, 0)
    bar.cost:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", from, 0)
    bar.cost:SetWidth(math.max(1, size * frac))
  end
  bar.cost:SetVertexColor(c[1], c[2], c[3], c[4] or 0.5)
  bar.cost:Show()
end

-- modules redraw their bars' predictions when something changes
function S:OnPrediction(fn)
  table.insert(listeners, fn)
end

function S:PredictionOptions()
  return {
    { label = "Heal prediction", toggle = true, get = function() return s.enabled end, set = function(v) s.enabled = v; Changed() end },
    { label = "Prediction opacity", get = function() return s.color[4] end, set = function(v) s.color[4] = v; Changed() end,
      min = 0.1, max = 1, step = 0.05 },
  }
end

S:RegisterModule("healpredict", function()
  s = S:Settings("frames", "healpred", { enabled = true, color = { 0.25, 1, 0.45, 0.45 }, costColor = { 0, 0, 0, 0.5 } })
  local f = CreateFrame("Frame", "SnapUI_HealPredict")
  for _, e in ipairs({ "SPELL_START_SELF", "SPELL_START_OTHER", "SPELL_GO_SELF", "SPELL_GO_OTHER",
    "SPELL_FAILED_SELF", "SPELL_FAILED_OTHER" }) do
    pcall(f.RegisterEvent, f, e)
  end
  for _, e in ipairs({ "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED", "SPELLCAST_CHANNEL_STOP" }) do
    f:RegisterEvent(e)
  end
  -- nampower only sends these with its start/go events switched on
  for _, cvar in ipairs({ "NP_EnableSpellStartEvents", "NP_EnableSpellGoEvents" }) do
    pcall(SetCVar, cvar, "1")
  end
  f:SetScript("OnEvent", function()
    if event == "SPELL_START_SELF" or event == "SPELL_START_OTHER" then
      -- itemId, spellId, casterGuid, targetGuid, castFlags, castTime
      Start(arg2, arg3, arg4, arg6)
    elseif event == "SPELL_GO_SELF" or event == "SPELL_GO_OTHER" then
      Stop(arg3)
    elseif event == "SPELL_FAILED_OTHER" then
      Stop(arg1)
    else
      -- our own cast ended one way or another
      Stop(UnitGUID and UnitGUID("player"))
    end
  end)
  local t = 0
  f:SetScript("OnUpdate", function()
    t = t + arg1
    if t < 0.05 then return end
    t = 0
    local now = GetTime()
    for caster, c in pairs(casts) do
      if c.ends < now then
        casts[caster] = nil
        dirty = true
      end
    end
    if dirty then
      dirty = false
      for _, fn in ipairs(listeners) do
        pcall(fn)
      end
    end
  end)
end, "Heal prediction", "Incoming heals on health bars, cast targets on cast bars and the mana your cast will spend on your power bars, from nampower's spell events.")
