-- SnapUI buffs: Blizzard's own buff, debuff and weapon-enchant buttons (so right-click to
-- cancel, tooltips and timers all still work), laid out by us in two boxes, Buffs and
-- Debuffs. Each box has scale, per row, spacing, grow direction, rows or columns, sort by
-- time left, reverse order and duration text. Boxes are sized to their buttons with no
-- padding, so they sit flush against a screen edge.

local S = SnapUI

local TEXT = 12 -- room under each icon for its duration
local groups = {}

local function Style(name)
  local icon = getglobal(name .. "Icon")
  if icon then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  local duration = getglobal(name .. "Duration")
  if duration then
    duration:SetFont(S.FONT, 11, "OUTLINE")
  end
  local count = getglobal(name .. "Count")
  if count then
    count:SetFont(S.FONT, 12, "OUTLINE")
  end
end

-- seconds left on an aura button; permanent ones (auras, mounts) count as longest
local function TimeLeft(b)
  local index = GetPlayerBuff(b:GetID(), b.snapFilter)
  local left = index and index >= 0 and GetPlayerBuffTimeLeft(index)
  if not left or left <= 0 then
    return 1000000
  end
  return left
end

-- durations off: Blizzard calls Show() on the text every update, so stub it out
local function SetDurations(g)
  for _, b in ipairs(g.buttons) do
    local d = getglobal(b:GetName() .. "Duration")
    if d then
      if g.s.durations then
        d.Show = nil
      else
        d:Hide()
        d.Show = S.noop
      end
    end
  end
end

local function Layout(g)
  local s = g.s
  local size, sp = g.size, s.spacing
  local textH = s.durations and TEXT or 0
  local stepX, stepY = size + sp, size + textH + sp
  local per = math.max(1, math.min(s.perRow, g.max))
  local anchor = (s.growDown and "TOP" or "BOTTOM") .. (s.growLeft and "RIGHT" or "LEFT")
  -- growing upwards, the first row's duration text hangs under it: lift everything by it
  local lift = s.growDown and 0 or textH

  -- the box is the full grid, so it doesn't jump about as buffs come and go
  local lines = math.ceil(g.max / per)
  local cols, rows = per, lines
  if s.vertical then
    cols, rows = lines, per
  end
  g.frame:SetWidth(math.max(1, cols * stepX - sp))
  g.frame:SetHeight(math.max(1, rows * stepY - sp))
  g.frame:SetScale(s.scale)
  g.frame:ClearAllPoints()
  g.frame:SetPoint(anchor, g.holder, anchor, 0, 0)
  S:Fit(g.holder, g.frame)
  -- a bigger box (more rows, a larger scale) grows from its centre: keep it on screen
  local p = S.db.pos[g.holder.name]
  if p and not p.point and S.ClampToScreen then
    local x, y = S.ClampToScreen(g.holder, p[1], p[2])
    if x ~= p[1] or y ~= p[2] then
      S:SavePosition(g.holder, x, y)
      S:Place(g.holder)
    end
  end

  -- what's showing: weapon enchants first, then auras in Blizzard's order (or by time left)
  local list, auras = {}, {}
  for _, b in ipairs(g.buttons) do
    if b:IsShown() then
      table.insert(b.snapEnchant and list or auras, b)
    end
  end
  if s.sortTime then
    local left = {}
    for _, b in ipairs(auras) do
      left[b] = TimeLeft(b)
    end
    table.sort(auras, function(a, b)
      if left[a] ~= left[b] then
        return left[a] < left[b]
      end
      return a:GetID() < b:GetID()
    end)
  end
  for _, b in ipairs(auras) do
    table.insert(list, b)
  end
  if s.reverse then
    local n = table.getn(list)
    for i = 1, math.floor(n / 2) do
      list[i], list[n - i + 1] = list[n - i + 1], list[i]
    end
  end

  for k, b in ipairs(list) do
    local i = k - 1
    local major, minor = math.floor(i / per), math.mod(i, per)
    local col, row = minor, major
    if s.vertical then
      col, row = major, minor
    end
    b:ClearAllPoints()
    b:SetPoint(anchor, g.frame, anchor, col * stepX * (s.growLeft and -1 or 1), row * stepY * (s.growDown and -1 or 1) + lift)
  end
end

-- which buttons are up, plus the order they'd sort in, so we only lay out on a change
local function Signature(g)
  local sig = ""
  for _, b in ipairs(g.buttons) do
    if b:IsShown() then
      sig = sig .. b:GetName() .. ","
    end
  end
  return sig
end

local function Options(g)
  local s = g.s
  local function Num(label, key, min, max, step)
    return { label = label, get = function() return s[key] end, set = function(v) s[key] = v; Layout(g) end, min = min, max = max, step = step }
  end
  local function Toggle(label, key, after)
    return { label = label, toggle = true, get = function() return s[key] end,
      set = function(v) s[key] = v; if after then after(g) end; Layout(g) end }
  end
  return {
    Num("Scale", "scale", 0.5, 2.5, 0.05),
    Num("Per row", "perRow", 1, g.max, 1),
    Num("Spacing", "spacing", 0, 16, 1),
    Toggle("Grow left", "growLeft"),
    Toggle("Grow down", "growDown"),
    Toggle("Columns first", "vertical"),
    Toggle("Sort by time left", "sortTime"),
    Toggle("Reverse order", "reverse"),
    Toggle("Durations", "durations", SetDurations),
  }
end

local function CreateGroup(key, label, buttonNames, filter, default, defaults)
  local g = { key = key }
  g.s = S:Settings("frames", key, defaults)
  g.holder = S:Holder(key, label, default, {})
  g.frame = CreateFrame("Frame", "SnapUI_" .. key, g.holder)
  g.buttons = {}
  for _, name in ipairs(buttonNames) do
    local b = getglobal(name)
    if b then
      Style(name)
      b.snapFilter = b.buffFilter or filter
      b.snapEnchant = string.find(name, "^TempEnchant") and true or nil
      b:SetParent(g.frame)
      table.insert(g.buttons, b)
    end
  end
  g.max = table.getn(g.buttons)
  g.size = (g.buttons[1] and g.buttons[1]:GetWidth()) or 30
  g.holder.options = Options(g)
  SetDurations(g)
  Layout(g)
  g.sig = Signature(g)
  groups[key] = g
  return g
end

S:RegisterModule("buffs", function()
  -- sort Blizzard's aura buttons by what they show rather than by number: vanilla has buffs
  -- in 0-15 and debuffs in 16-23, but clients with more buff slots number them differently
  local buffNames = { "TempEnchant1", "TempEnchant2" }
  local debuffNames = {}
  for i = 0, 63 do
    local b = getglobal("BuffButton" .. i)
    if b then
      local harmful
      if b.buffFilter then
        harmful = string.find(b.buffFilter, "HARMFUL") ~= nil
      else
        harmful = i >= 16 and i <= 23 -- no filter recorded: the vanilla numbering
      end
      table.insert(harmful and debuffNames or buffNames, "BuffButton" .. i)
    end
  end

  local common = { scale = 1, spacing = 4, growLeft = true, growDown = true, vertical = false,
    sortTime = false, reverse = false, durations = true }
  local function With(extra)
    local t = {}
    for k, v in pairs(common) do t[k] = v end
    for k, v in pairs(extra) do t[k] = v end
    return t
  end

  local buffs = CreateGroup("buffs", "Buffs", buffNames, "HELPFUL", { "TOPRIGHT", nil, -205, -13 }, With({ perRow = 9 }))
  -- debuffs start under the buffs, wherever those are
  CreateGroup("debuffs", "Debuffs", debuffNames, "HARMFUL", { "TOPRIGHT", "BOTTOMRIGHT", 0, -6, buffs.holder }, With({ perRow = 8 }))

  -- one-off: the old buffs box was 340x110 hung from its top-right corner; keep that corner
  -- where it was now the box is sized to the buttons
  local p = S.db.pos.buffs
  if p and not p.point and not buffs.s.boxed then
    p[1] = p[1] + 170 - buffs.holder:GetWidth() / 2
    p[2] = p[2] + 55 - buffs.holder:GetHeight() / 2
    S:Place(buffs.holder)
  end
  buffs.s.boxed = true

  -- Blizzard shows and hides the buttons in its own handlers (and the weapon enchants on a
  -- timer), so check a few times a second and lay out whenever what's showing changes
  local watch, t = CreateFrame("Frame"), 0
  watch:RegisterEvent("PLAYER_AURAS_CHANGED")
  watch:RegisterEvent("UNIT_INVENTORY_CHANGED")
  watch:SetScript("OnEvent", function()
    for _, g in pairs(groups) do
      g.dirty = true
    end
  end)
  watch:SetScript("OnUpdate", function()
    t = t + arg1
    if t < 0.2 then
      return
    end
    t = 0
    for _, g in pairs(groups) do
      local sig = Signature(g)
      if g.dirty or sig ~= g.sig then
        g.dirty, g.sig = nil, sig
        Layout(g)
      end
    end
  end)

  -- the client re-anchors its rows of buttons when the buff-duration option changes: put
  -- ours back straight after
  S.PostHook("BuffButtons_UpdatePositions", function()
    for _, g in pairs(groups) do
      g.dirty = true
    end
  end)
end, "Buffs & debuffs", "Your buff, debuff and weapon enchant icons.")

-- /snapbuffs: what's in each box and where its first icon is, for when icons go missing
SLASH_SNAPBUFFS1 = "/snapbuffs"
SlashCmdList["SNAPBUFFS"] = function()
  for _, key in ipairs({ "buffs", "debuffs" }) do
    local g = groups[key]
    if not g then
      S.Print(key .. ": not set up (is the Buffs & debuffs module on?)")
    else
      local shown, first = 0, nil
      for _, b in ipairs(g.buttons) do
        if b:IsShown() then
          shown = shown + 1
          first = first or b
        end
      end
      local where = "none showing"
      if first then
        where = string.format("first %s at %d,%d visible=%s alpha=%.2f", first:GetName(), first:GetLeft() or -1,
          first:GetTop() or -1, tostring(first:IsVisible() and true or false), first.GetEffectiveAlpha and first:GetEffectiveAlpha() or first:GetAlpha())
      end
      S.Print(string.format("%s: %d buttons (%s ... %s), %d shown, box %s at %d,%d; %s", key, g.max,
        g.buttons[1] and g.buttons[1]:GetName() or "-", g.buttons[g.max] and g.buttons[g.max]:GetName() or "-", shown,
        g.holder:IsVisible() and "visible" or "HIDDEN", g.holder:GetLeft() or -1, g.holder:GetTop() or -1, where))
      -- every icon that's up: where it is, what it hangs from, its size and texture
      for _, b in ipairs(g.buttons) do
        if b:IsShown() then
          local point, rel, relPoint, x, y = b:GetPoint(1)
          local icon = getglobal(b:GetName() .. "Icon")
          S.Print(string.format("  %s at %d,%d size %dx%d, %s to %s %s %d,%d, icon %s", b:GetName(), b:GetLeft() or -1,
            b:GetTop() or -1, b:GetWidth(), b:GetHeight(), tostring(point), rel and rel.GetName and (rel:GetName() or "?") or "?",
            tostring(relPoint), x or 0, y or 0, icon and tostring(icon:GetTexture()) or "none"))
        end
      end
      S.Print(string.format("  layout: per row %s, grow %s%s, %s", tostring(g.s.perRow), g.s.growDown and "down" or "up",
        g.s.growLeft and " left" or " right", g.s.vertical and "columns first" or "rows first"))
    end
  end
end
