-- SnapUI action bars: Bartender-style bars built from Blizzard's own buttons, so key
-- bindings, macros and drag-and-drop keep working. Each bar can change buttons shown,
-- buttons per row, spacing, scale, show-empty and hidden. Also moves the pet bar, stance
-- bar, micro menu, bags, cast bar and minimap, and adds a slim XP/rep bar.

local S = SnapUI
-- no inner padding: a bar's buttons reach the edge of its holder, so bars can sit flush
-- against the screen edge
local PAD = 0
local bars = {}
-- the minimap button bar state (set up further down; the minimap code reads it too)
local bb

-- [[ button skin ]] --
local function SkinButton(b)
  local name = b:GetName()
  -- textures have no SetAlpha on 1.12: blank the border art and stop Blizzard putting it back
  for _, suffix in ipairs({ "NormalTexture", "NormalTexture2" }) do
    local t = getglobal(name .. suffix)
    if t and t.SetTexture then t:SetTexture(nil) end
  end
  if b.GetNormalTexture then
    local t = b:GetNormalTexture()
    if t and t.SetTexture then t:SetTexture(nil) end
  end
  b.SetNormalTexture = S.noop

  local icon = getglobal(name .. "Icon") or getglobal(name .. "IconTexture")
  if icon then
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  end

  local bg = CreateFrame("Frame", nil, b)
  bg:SetAllPoints(b)
  bg:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
  S.Backdrop(bg, 0.55)

  local hotkey = getglobal(name .. "HotKey")
  if hotkey then
    hotkey:SetFont(S.FONT, 11, "OUTLINE")
    hotkey:ClearAllPoints()
    hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
  end
  local count = getglobal(name .. "Count")
  if count then
    count:SetFont(S.FONT, 12, "OUTLINE")
    count:ClearAllPoints()
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  end
  local macro = getglobal(name .. "Name")
  if macro then
    macro:SetFont(S.FONT, 10, "OUTLINE")
  end
end

-- "SHIFT-1" is too wide for a 36px button
local ABBREV = {
  { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" },
  { "Mouse Button ", "M" }, { "Middle Mouse", "M3" }, { "Mouse Wheel Up", "WU" },
  { "Mouse Wheel Down", "WD" }, { "Num Pad ", "N" }, { "Spacebar", "Spc" },
}
S.PostHook("ActionButton_UpdateHotkeys", function()
  local hotkey = this and this.GetName and getglobal(this:GetName() .. "HotKey")
  local text = hotkey and hotkey:GetText()
  if not text or text == RANGE_INDICATOR then
    return
  end
  for _, a in ipairs(ABBREV) do
    text = string.gsub(text, a[1], a[2])
  end
  hotkey:SetText(text)
end)

-- keep "show empty" slots visible even when Blizzard hides the grid after dragging
S.PostHook("ActionButton_HideGrid", function(button)
  button = button or this
  if button and button.snapGrid and button.showgrid < 1 then
    button.showgrid = 1
    button:Show()
  end
end)

local function SetShowEmpty(b, show)
  if not b.snapAction then
    return
  end
  if show and not b.snapGrid then
    b.snapGrid = true
    ActionButton_ShowGrid(b)
  elseif not show and b.snapGrid then
    b.snapGrid = nil
    ActionButton_HideGrid(b)
  end
end

-- [[ cooldown numbers ]] --
-- 1.12 only draws the clock sweep; put the time left on top of it. Every button cooldown
-- goes through CooldownFrame_SetTimer, so hook that and drive a small timer per button.
local function CooldownText(left)
  if left >= 600 then
    return math.ceil(left / 60) .. "m", 1, 1, 1
  elseif left >= 60 then
    local sec = math.ceil(left)
    return string.format("%d:%02d", math.floor(sec / 60), math.mod(sec, 60)), 1, 1, 1
  elseif left >= 3 then
    return tostring(math.ceil(left)), 1, 0.85, 0.3
  end
  return string.format("%.1f", left), 1, 0.3, 0.3
end

local function CooldownTimer(b)
  local t = CreateFrame("Frame", nil, b)
  t:SetAllPoints(b)
  t:SetFrameLevel(b:GetFrameLevel() + 3)
  t.text = S.Text(t, math.max(10, math.floor(b:GetWidth() * 0.45)), "CENTER")
  t.text:SetPoint("CENTER", 1, 0)
  t.elapsed = 0
  t:Hide()
  t:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 0.1 then
      return
    end
    this.elapsed = 0
    local left = this.start + this.duration - GetTime()
    -- also stop when the slot has been emptied or its sweep hidden: dragging a spell off a
    -- button only hides the sweep, it doesn't go through CooldownFrame_SetTimer
    local button = this:GetParent()
    local gone = this.cd and not this.cd:IsShown()
    if not gone and button.snapAction and ActionButton_GetPagedID then
      gone = not HasAction(ActionButton_GetPagedID(button))
    end
    if left <= 0 or gone then
      this:Hide()
      return
    end
    local text, r, g, bl = CooldownText(left)
    this.text:SetText(text)
    this.text:SetTextColor(r, g, bl)
  end)
  b.snapTimer = t
  return t
end

S.PostHook("CooldownFrame_SetTimer", function(cooldown, start, duration, enable)
  local b = cooldown and cooldown.GetParent and cooldown:GetParent()
  if not b or not b.snapSkinned then
    return
  end
  -- 1.5s and under is just the global cooldown
  if b.snapNoCooldownText or not enable or enable == 0 or not start or start == 0 or not duration or duration <= 1.5 then
    if b.snapTimer then b.snapTimer:Hide() end
    return
  end
  local t = b.snapTimer or CooldownTimer(b)
  t.start, t.duration, t.elapsed, t.cd = start, duration, 1, cooldown
  t:Show()
end)

-- keybind / macro name text on and off
local function SetButtonText(b, s)
  local name = b:GetName()
  local hotkey, macro = getglobal(name .. "HotKey"), getglobal(name .. "Name")
  if hotkey then
    if s.hotkeys == false then hotkey:Hide() else hotkey:Show() end
  end
  if macro then
    if s.macros == false then macro:Hide() else macro:Show() end
  end
  b.snapNoCooldownText = s.cooldowns == false
  b.snapRange = s.range ~= false
  if not b.snapRange and b.snapOut then
    b.snapOut = nil
    if ActionButton_UpdateUsable then S.CallAs(b, ActionButton_UpdateUsable) end
  end
  if b.snapNoCooldownText and b.snapTimer then
    b.snapTimer:Hide()
  end
end

-- range tint: Blizzard only reddens the keybind text when the target is out of range (so
-- with keybind text off there's no sign at all); tint the whole icon red instead. Checked
-- five times a second; back in range, Blizzard's own usable / out-of-mana colours return.
S.PostHook("ActionButton_OnUpdate", function(elapsed)
  local b = this
  if not b or not b.snapRange then
    return
  end
  b.snapRangeWait = (b.snapRangeWait or 0) - (elapsed or 0)
  if b.snapRangeWait > 0 then
    return
  end
  b.snapRangeWait = 0.2
  local action = b.action or (ActionButton_GetPagedID and ActionButton_GetPagedID(b))
  local out = action and HasAction(action) and IsActionInRange(action) == 0
  local icon = getglobal(b:GetName() .. "Icon")
  if out and icon then
    icon:SetVertexColor(0.85, 0.2, 0.2)
    b.snapOut = true
  elseif b.snapOut then
    b.snapOut = nil
    if ActionButton_UpdateUsable then S.CallAs(b, ActionButton_UpdateUsable) end
  end
end)

-- [[ bars ]] --
local function Layout(bar)
  local s = bar.settings
  local n = math.min(s.buttons, table.getn(bar.buttons))
  if bar.dynamicCount then
    n = math.min(n, bar.dynamicCount())
  end
  local per = math.max(1, math.min(s.perRow, math.max(n, 1)))
  local rows = math.max(1, math.ceil(n / per))
  local size, hsize, sp = bar.size, bar.hsize, s.spacing

  for i, b in ipairs(bar.buttons) do
    b:ClearAllPoints()
    if i <= n then
      local col = math.mod(i - 1, per)
      local row = math.floor((i - 1) / per)
      b:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", PAD + col * (size + sp), -PAD - row * (hsize + sp) + bar.yOffset)
      b:SetAlpha(1)
      b:EnableMouse(true)
    else
      -- out of the bar but still bound: the keybind keeps firing its own slot
      b:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", PAD, -PAD + bar.yOffset)
      b:SetAlpha(0)
      b:EnableMouse(false)
    end
    SetShowEmpty(b, s.empty and i <= n)
    if b.snapAction then
      SetButtonText(b, s)
    end
  end

  local cols = math.min(per, math.max(n, 1))
  bar.frame:SetWidth(PAD * 2 + cols * size + (cols - 1) * sp)
  bar.frame:SetHeight(PAD * 2 + rows * hsize + (rows - 1) * sp)
  bar.frame:SetScale(s.scale)
  bar.frame:ClearAllPoints()
  bar.frame:SetPoint("TOPLEFT", bar.holder, "TOPLEFT", 0, 0)
  S:Fit(bar.holder, bar.frame)
  bar:UpdateVisibility()
end

local function UpdateVisibility(bar)
  local show = not bar.settings.hidden
  if show and bar.visible then
    show = bar.visible()
  end
  if show then
    bar.frame:Show()
  else
    bar.frame:Hide()
  end
end

-- [[ fading ]] --
-- "mouseover": faded until the mouse is over the bar; "combat": also shown in combat;
-- "target": also shown while you have a target. A bar being dragged onto (spell on the
-- cursor) always shows.
local FADES = { { "none", "Always shown" }, { "mouseover", "On mouseover" }, { "combat", "In combat" },
  { "target", "In combat or with a target" } }

local function FadeAlpha(bar)
  local s = bar.settings
  if not s.fade or s.fade == "none" or S:IsEditing() then
    return 1
  end
  if MouseIsOver(bar.frame) or (CursorHasSpell and CursorHasSpell()) then
    return 1
  end
  if (s.fade == "combat" or s.fade == "target") and UnitAffectingCombat("player") then
    return 1
  end
  if s.fade == "target" and UnitExists("target") then
    return 1
  end
  return s.fadeAlpha or 0
end

local fader = CreateFrame("Frame")
local fadeTick = 0
fader:SetScript("OnUpdate", function()
  fadeTick = fadeTick + arg1
  if fadeTick < 0.1 then
    return
  end
  fadeTick = 0
  for _, bar in pairs(bars) do
    if bar.frame:IsShown() then
      local a = FadeAlpha(bar)
      if a ~= bar.alpha then
        bar.alpha = a
        bar.frame:SetAlpha(a)
      end
    end
  end
end)

local function BarOptions(bar)
  local s = bar.settings
  local max = table.getn(bar.buttons)
  local function Set(key)
    return function(v) s[key] = v; Layout(bar) end
  end
  local list = {
    { label = "Buttons", get = function() return s.buttons end, set = Set("buttons"), min = 1, max = max, step = 1 },
    { label = "Per row", get = function() return s.perRow end, set = Set("perRow"), min = 1, max = max, step = 1 },
    { label = "Spacing", get = function() return s.spacing end, set = Set("spacing"), min = 0, max = 12, step = 1 },
    { label = "Scale", get = function() return s.scale end, set = Set("scale"), min = 0.5, max = 2, step = 0.05 },
    { label = "Visible", choices = FADES, get = function() return s.fade or "none" end, set = function(v) s.fade = v; bar.alpha = nil end },
    { label = "Faded opacity", get = function() return s.fadeAlpha or 0 end, set = function(v) s.fadeAlpha = v; bar.alpha = nil end, min = 0, max = 1, step = 0.1 },
  }
  if bar.hasEmpty then
    table.insert(list, { label = "Show empty slots", toggle = true, get = function() return s.empty end, set = Set("empty") })
    table.insert(list, { label = "Cooldown numbers", toggle = true, get = function() return s.cooldowns end, set = Set("cooldowns") })
    table.insert(list, { label = "Keybind text", toggle = true, get = function() return s.hotkeys end, set = Set("hotkeys") })
    table.insert(list, { label = "Macro text", toggle = true, get = function() return s.macros end, set = Set("macros") })
    table.insert(list, { label = "Range tint", toggle = true, get = function() return s.range end, set = Set("range") })
  end
  table.insert(list, { label = "Hidden", toggle = true, get = function() return s.hidden end, set = Set("hidden") })
  return list
end

-- def: key, label, buttons (names), frame (existing Blizzard bar frame to adopt, optional),
--      default point, defaults for settings, size, visible(), dynamicCount()
local function CreateBar(def)
  local bar = { key = def.key }
  if def.actions then
    def.settings.cooldowns, def.settings.hotkeys, def.settings.macros, def.settings.range = true, true, true, true
  end
  bar.settings = S:Settings("bars", def.key, def.settings)
  bar.buttons = {}
  for _, name in ipairs(def.buttons) do
    local b = getglobal(name)
    if b then
      table.insert(bar.buttons, b)
    end
  end
  bar.size = def.size or (bar.buttons[1] and bar.buttons[1]:GetWidth()) or 36
  bar.hsize = def.height or bar.size
  bar.yOffset = def.yOffset or 0
  bar.visible = def.visible
  bar.dynamicCount = def.dynamicCount
  bar.hasEmpty = def.actions
  bar.UpdateVisibility = UpdateVisibility

  local options = {}
  bar.holder = S:Holder(def.key, def.label, def.default, options)
  bar.holder.isOff = function() return bar.settings.hidden end
  if def.frame then
    bar.frame = getglobal(def.frame)
    bar.frame:SetParent(bar.holder)
  else
    bar.frame = CreateFrame("Frame", "SnapUI_" .. def.key, bar.holder)
    for _, b in ipairs(bar.buttons) do
      b:SetParent(bar.frame)
    end
  end
  bar.frame:SetFrameStrata("MEDIUM")

  for _, b in ipairs(bar.buttons) do
    b.snapAction = def.actions
    if def.skin ~= false and not (def.noSkin and def.noSkin[b:GetName()]) then
      SkinButton(b)
      b.snapSkinned = true
    end
  end
  for _, o in ipairs(BarOptions(bar)) do
    table.insert(options, o)
  end

  bars[def.key] = bar
  Layout(bar)
  return bar
end

local function Names(prefix, n)
  local t = {}
  for i = 1, n do
    t[i] = prefix .. i
  end
  return t
end

-- [[ xp / rep bar ]] --
local function CreateXPBar()
  local holder = S:Holder("xp", "XP / rep bar", { "BOTTOM", nil, 0, 6 }, {})
  local s = S:Settings("bars", "xp", { width = 460, height = 8, hidden = false })
  holder.isOff = function() return s.hidden end

  local f = CreateFrame("Frame", "SnapUI_XP", holder)
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  S.Backdrop(f, 0.8)
  f.rested = S.StatusBar(f)
  f.rested:SetPoint("TOPLEFT", 1, -1)
  f.rested:SetPoint("BOTTOMRIGHT", -1, 1)
  f.rested.bg:Hide()
  f.rested:SetStatusBarColor(0.25, 0.4, 0.9, 0.5)
  f.bar = S.StatusBar(f)
  f.bar:SetAllPoints(f.rested)
  f.bar.bg:Hide()
  -- on the fill bar's top layer, or the coloured bars cover it
  f.text = S.Text(f.bar.over, 10, "CENTER")
  f.text:SetPoint("CENTER", f, "CENTER", 0, 1)
  f.text:Hide()
  f:EnableMouse(true)
  f:SetScript("OnEnter", function() this.text:Show() end)
  f:SetScript("OnLeave", function() this.text:Hide() end)

  local function Update()
    local level, max = UnitLevel("player"), MAX_PLAYER_LEVEL or 60
    if level < max then
      local xp, xpMax = UnitXP("player"), UnitXPMax("player")
      local rested = math.floor(GetXPExhaustion() or 0)
      f.bar:SetMinMaxValues(0, xpMax)
      f.bar:SetValue(xp)
      f.bar:SetStatusBarColor(0.62, 0.25, 0.85)
      f.rested:SetMinMaxValues(0, xpMax)
      f.rested:SetValue(math.min(xpMax, xp + rested))
      f.rested:Show()
      local text = S.ShortNumber(xp) .. " / " .. S.ShortNumber(xpMax) .. "  (" .. math.floor(xp / xpMax * 100) .. "%)"
      if rested > 0 then
        text = text .. "  rested " .. S.ShortNumber(rested)
      end
      f.text:SetText(text)
      f:Show()
    else
      local name, standing, low, high, value
      if GetWatchedFactionInfo then
        name, standing, low, high, value = GetWatchedFactionInfo()
      end
      if name then
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing] or { r = 0, g = 0.6, b = 0.1 }
        f.bar:SetMinMaxValues(low, high)
        f.bar:SetValue(value)
        f.bar:SetStatusBarColor(c.r, c.g, c.b)
        f.rested:Hide()
        f.text:SetText(name .. "  " .. (value - low) .. " / " .. (high - low))
        f:Show()
      else
        f:Hide()
      end
    end
    if s.hidden then
      f:Hide()
    end
  end

  local function Layout()
    f:SetWidth(s.width)
    f:SetHeight(s.height)
    S:Fit(holder, f)
    Update()
  end
  holder.options[1] = { label = "Width", get = function() return s.width end, set = function(v) s.width = v; Layout() end, min = 100, max = 1200, step = 20 }
  holder.options[2] = { label = "Height", get = function() return s.height end, set = function(v) s.height = v; Layout() end, min = 2, max = 30, step = 1 }
  holder.options[3] = { label = "Hidden", toggle = true, get = function() return s.hidden end, set = function(v) s.hidden = v; Layout() end }

  local events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", Update)
  Layout()
end

-- [[ adopting other Blizzard frames ]] --
-- move a Blizzard frame into a holder; reapply keeps it there if Blizzard moves it back
local adopted = {}
local function Adopt(key, label, frame, default, point, w, h)
  if not frame then
    return
  end
  local holder = S:Holder(key, label, default, nil)
  -- the frame isn't the holder's child, so hover-to-show has to fade it directly
  holder.fadeFrames = { frame }
  local entry = { holder = holder, frame = frame, point = point or "CENTER" }
  function entry.apply()
    frame:ClearAllPoints()
    frame:SetPoint(entry.point, holder, entry.point, 0, 0)
  end
  holder:SetWidth(w or frame:GetWidth())
  holder:SetHeight(h or frame:GetHeight())
  entry.apply()
  table.insert(adopted, entry)
  return entry
end

-- [[ cast bar ]] --
-- Restyle Blizzard's CastingBarFrame (it keeps all the casting logic): flat bar, theme
-- colours, spell icon, name on the left, time remaining on the right.
local CAST_COLORS = {
  cast = { S.ACCENT[1], S.ACCENT[2], S.ACCENT[3] },
  done = { 0.3, 0.85, 0.4 },
  fail = { 0.85, 0.25, 0.25 },
}

local function SpellIcon(name)
  if not name then
    return nil
  end
  local i = 1
  while true do
    local spell = GetSpellName(i, BOOKTYPE_SPELL)
    if not spell then
      return nil
    end
    if spell == name then
      return GetSpellTexture(i, BOOKTYPE_SPELL)
    end
    i = i + 1
  end
end

local function StyleCastBar(entry)
  local bar, holder = CastingBarFrame, entry.holder
  local s = S:Settings("bars", "cast", { width = 240, height = 20, icon = true, enabled = true, textSize = 12, alpha = 1, showTarget = true })
  holder.isOff = function() return not s.enabled end

  bar:SetStatusBarTexture(S.TEX)
  CastingBarBorder:SetTexture(nil)
  CastingBarFlash:SetTexture(nil)

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetTexture(S.TEX)
  bg:SetVertexColor(0.12, 0.12, 0.12, 1)
  local border = CreateFrame("Frame", nil, bar)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
  S.Backdrop(border, 0)
  -- a see-through backdrop (ElvUI's "transparent" cast bar)
  bg:SetVertexColor(0.07, 0.07, 0.07, s.alpha)

  S.SetFont(CastingBarText, s.textSize)
  CastingBarText:SetJustifyH("LEFT")
  CastingBarText:ClearAllPoints()
  CastingBarText:SetPoint("LEFT", bar, "LEFT", 5, 0)
  local timer = S.Text(bar, s.textSize, "RIGHT")
  timer:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
  CastingBarText:SetPoint("RIGHT", timer, "LEFT", -4, 0)

  local icon = CreateFrame("Frame", nil, bar)
  S.Backdrop(icon, 1)
  icon.tex = icon:CreateTexture(nil, "ARTWORK")
  icon.tex:SetPoint("TOPLEFT", 1, -1)
  icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Blizzard paints yellow (casting), green (done) and red (failed); map those onto the theme
  local origColor = bar.SetStatusBarColor
  local _, playerClass = UnitClass("player")
  bar.SetStatusBarColor = function(self, r, g, b)
    local t = S.theme or {}
    local c = (t.castClass and S.CLASS[playerClass]) or t.castColor or CAST_COLORS.cast
    if r == 0 and g == 1 then
      c = CAST_COLORS.done
    elseif r == 1 and g == 0 then
      c = CAST_COLORS.fail
    end
    origColor(self, c[1], c[2], c[3])
  end

  local origEvent = bar:GetScript("OnEvent")
  bar:SetScript("OnEvent", function()
    origEvent()
    if not s.enabled then
      this:Hide()
      return
    end
    local name
    if event == "SPELLCAST_START" then
      name = arg1
    elseif event == "SPELLCAST_CHANNEL_START" then
      name = arg2
    end
    if name then
      icon.tex:SetTexture(SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
      bar.snapSpell, bar.snapText = name, nil
    end
  end)

  -- Blizzard places the spark for a 195px bar; place it for ours and run the timer
  local origUpdate = bar:GetScript("OnUpdate")
  bar:SetScript("OnUpdate", function()
    origUpdate()
    local min, max = this:GetMinMaxValues()
    local frac = max > min and (this:GetValue() - min) / (max - min) or 0
    CastingBarSpark:ClearAllPoints()
    CastingBarSpark:SetPoint("CENTER", this, "LEFT", frac * this:GetWidth(), 0)
    -- the spell's target after its name, once nampower has told us who it is
    if s.showTarget and bar.snapSpell and (this.casting or this.channeling) and S.CastTarget then
      local aim = S.CastTargetText(S.CastTarget(UnitGUID and UnitGUID("player")))
      local text = aim and (bar.snapSpell .. " > " .. aim) or bar.snapSpell
      if text ~= bar.snapText then
        bar.snapText = text
        CastingBarText:SetText(text)
      end
    end
    local left
    if this.casting then
      left = this.maxValue - GetTime()
    elseif this.channeling then
      left = this.endTime - GetTime()
    end
    if left and left > 0 then
      timer:SetText(string.format("%.1f", left))
    else
      timer:SetText("")
    end
  end)

  entry.apply = function()
    bar:ClearAllPoints()
    bar:SetPoint("RIGHT", holder, "RIGHT", -1, 0)
  end

  local function Layout()
    bar:SetWidth(s.width)
    bar:SetHeight(s.height)
    CastingBarSpark:SetWidth(16)
    CastingBarSpark:SetHeight(s.height * 2.2)
    icon:SetWidth(s.height + 2)
    icon:SetHeight(s.height + 2)
    icon:ClearAllPoints()
    icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
    local extra = 0
    if s.icon then
      icon:Show()
      extra = s.height + 5
    else
      icon:Hide()
    end
    holder:SetWidth(s.width + extra + 2)
    holder:SetHeight(s.height + 2)
    entry.apply()
  end
  holder.options = {
    { label = "Width", get = function() return s.width end, set = function(v) s.width = v; Layout() end, min = 100, max = 500, step = 10 },
    { label = "Height", get = function() return s.height end, set = function(v) s.height = v; Layout() end, min = 10, max = 40, step = 1 },
    { label = "Spell icon", toggle = true, get = function() return s.icon end, set = function(v) s.icon = v; Layout() end },
    { label = "Show cast target", toggle = true, get = function() return s.showTarget end, set = function(v) s.showTarget = v end },
    { label = "Enabled", toggle = true, get = function() return s.enabled end, set = function(v) s.enabled = v; if not v then bar:Hide() end end },
  }
  Layout()
end

-- [[ loot rolls ]] --
-- Restyle Blizzard's four need/greed windows (they keep the rolling, the timer and the BoP
-- confirmation): a flat bar with the item icon, its name in quality colour, a BoP/BoE tag,
-- a thin timer bar, and need / greed / pass on the right. The border takes the quality colour.
-- Who picked what comes from the loot chat lines ("X has selected Need for: [item]").
local rollChoices = {} -- "item:id:enchant:suffix:unique" -> { need = {names}, greed = {}, pass = {}, time = t }

-- a Lua pattern for one of the LOOT_ROLL_* strings: the name a capture, the item link
-- captured as its "item:..." string
local function RollPattern(fmt)
  if not fmt then
    return nil
  end
  fmt = string.gsub(fmt, "%%s|Hitem:%%d:%%d:%%d:%%d|h%[%%s%]|h%%s", "\001")
  fmt = string.gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
  fmt = string.gsub(fmt, "%%%%s", "(.-)")
  fmt = string.gsub(fmt, "%%%%d", "%%d+")
  fmt = string.gsub(fmt, "\001", function() return ".-|H(item:%d+:%d+:%d+:%d+)|h%[.-%]|h.-" end)
  return "^" .. fmt .. "$"
end

local ROLL_LINES = {
  { "need", RollPattern(LOOT_ROLL_NEED) }, { "greed", RollPattern(LOOT_ROLL_GREED) },
  { "pass", RollPattern(LOOT_ROLL_PASSED) },
  { "need", RollPattern(LOOT_ROLL_NEED_SELF), true }, { "greed", RollPattern(LOOT_ROLL_GREED_SELF), true },
  { "pass", RollPattern(LOOT_ROLL_PASSED_SELF), true },
}

-- "Name" in class colour when they're in the group
local function RollerName(name)
  local units = { "player" }
  for i = 1, GetNumRaidMembers() do table.insert(units, "raid" .. i) end
  for i = 1, GetNumPartyMembers() do table.insert(units, "party" .. i) end
  for _, unit in ipairs(units) do
    if UnitName(unit) == name then
      local _, class = UnitClass(unit)
      local c = S.CLASS[class]
      if c then
        return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, name)
      end
    end
  end
  return name
end

-- note a loot chat line; true if it was someone's need/greed/pass
local function ReadRollChoice(msg)
  if not msg then
    return
  end
  for _, line in ipairs(ROLL_LINES) do
    if line[2] then
      local _, _, a, b = string.find(msg, line[2])
      local name, item = a, b
      if line[3] then
        name, item = UnitName("player"), a
      end
      if item and name then
        local now = GetTime()
        local entry = rollChoices[item]
        if not entry or now - entry.time > 300 then
          entry = { need = {}, greed = {}, pass = {}, time = now }
          rollChoices[item] = entry
        end
        local list = entry[line[1]]
        local shown = RollerName(name)
        for _, n in ipairs(list) do
          if n == shown then
            return true
          end
        end
        table.insert(list, shown)
        return true
      end
    end
  end
end

local NO_CHOICES = { need = {}, greed = {}, pass = {} }
local function RollItem(f)
  local link = f.rollID and GetLootRollItemLink and GetLootRollItemLink(f.rollID)
  local _, _, item = string.find(link or "", "(item:%d+:%d+:%d+:%d+)")
  return item
end

local function RollChoices(f)
  local item = RollItem(f)
  return item and rollChoices[item] or NO_CHOICES
end

-- a new roll starts with no choices, unless the same item is still being rolled on
local function NewRoll(f, frames)
  local item = RollItem(f)
  if not item then
    return
  end
  for _, r in ipairs(frames) do
    if r.f ~= f and r.f:IsShown() and RollItem(r.f) == item then
      return
    end
  end
  rollChoices[item] = nil
end

local function ShowRollCounts(r)
  local c = RollChoices(r.f)
  for _, choice in ipairs({ "need", "greed", "pass" }) do
    local n = getn(c[choice])
    r[choice].count:SetText(n > 0 and n or "")
  end
end

local function StyleLootRolls(entry)
  local holder = entry.holder
  local s = S:Settings("bars", "lootroll", { width = 280, height = 38 })
  local frames = {}

  for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
    local f = getglobal("GroupLootFrame" .. i)
    if not f then
      break
    end
    local name = f:GetName()
    local icon, iconTex = getglobal(name .. "IconFrame"), getglobal(name .. "IconFrameIcon")
    local need, greed, pass = getglobal(name .. "RollButton"), getglobal(name .. "GreedButton"), getglobal(name .. "PassButton")
    local timer, text = getglobal(name .. "Timer"), getglobal(name .. "Name")
    if not (icon and iconTex and need and greed and pass and timer and text) then
      break
    end
    for _, t in ipairs({ "SlotTexture", "NameFrame", "Decoration", "Corner" }) do
      local tex = getglobal(name .. t)
      if tex then
        tex:SetTexture(nil)
        tex:Hide()
      end
    end

    icon:ClearAllPoints()
    S.Backdrop(icon, 1)
    iconTex:ClearAllPoints()
    iconTex:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    pass:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    pass:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    pass:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")

    -- the timer: theme bar texture on a dark track with a thin border, no Blizzard frame
    for _, r in ipairs({ timer:GetRegions() }) do
      local path = r.GetTexture and r:GetTexture()
      if type(path) == "string" and string.find(string.lower(path), "barborder", 1, true) then
        r:SetTexture(nil)
        r:Hide()
      end
    end
    timer:SetStatusBarTexture(S.BAR or S.TEX)
    local track = timer:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(timer)
    track:SetTexture(S.TEX)
    track:SetVertexColor(0.07, 0.07, 0.07, 1)
    local edge = CreateFrame("Frame", nil, timer)
    edge:SetPoint("TOPLEFT", timer, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", timer, "BOTTOMRIGHT", 1, -1)
    edge:SetFrameLevel(math.max(0, timer:GetFrameLevel() - 1))
    S.Backdrop(edge, 0)

    S.SetFont(text, 12)
    text:SetJustifyH("LEFT")
    local bind = S.Text(f, 10, "RIGHT")

    local r = { f = f, icon = icon, need = need, greed = greed, pass = pass, timer = timer, text = text, bind = bind }
    -- how many picked each, on the buttons; who, in their tooltips
    for choice, button in pairs({ need = need, greed = greed, pass = pass }) do
      button.count = S.Text(button, 12, "CENTER")
      button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
      local c, origEnter = choice, button:GetScript("OnEnter")
      button:SetScript("OnEnter", function()
        if origEnter then origEnter() else GameTooltip:SetOwner(this, "ANCHOR_RIGHT") end
        local names = RollChoices(this:GetParent())[c]
        for _, n in ipairs(names) do
          GameTooltip:AddLine(n)
        end
        if getn(names) == 0 then
          GameTooltip:AddLine("nobody yet", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
      end)
    end

    -- Blizzard's OnShow puts its dialog backdrop (gold for BoP) back: restyle after it
    local origShow = f:GetScript("OnShow")
    f:SetScript("OnShow", function()
      origShow()
      if not this:IsShown() then
        return
      end
      NewRoll(this, frames)
      ShowRollCounts(r)
      getglobal(this:GetName() .. "Corner"):Hide()
      getglobal(this:GetName() .. "Decoration"):Hide()
      S.Backdrop(this, 0.85)
      local _, _, _, quality, bop = GetLootRollItemInfo(this.rollID)
      local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
      if c then
        this:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        icon:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        timer:SetStatusBarColor(c.r, c.g, c.b)
      end
      if bop then
        bind:SetText("BoP")
        bind:SetTextColor(1, 0.3, 0.3)
      else
        bind:SetText("BoE")
        bind:SetTextColor(0.3, 1, 0.3)
      end
    end)

    frames[i] = r
  end
  if not frames[1] then
    return
  end

  local chat = CreateFrame("Frame")
  chat:RegisterEvent("CHAT_MSG_LOOT")
  chat:SetScript("OnEvent", function()
    if ReadRollChoice(arg1) then
      for _, r in ipairs(frames) do
        if r.f:IsShown() then
          ShowRollCounts(r)
        end
      end
    end
  end)

  local function Layout()
    local h = s.height
    local size = h - 8
    local button = math.min(28, h - 10)
    for i, r in ipairs(frames) do
      local f = r.f
      f:SetWidth(s.width)
      f:SetHeight(h)
      if i > 1 then
        f:ClearAllPoints()
        f:SetPoint("BOTTOM", frames[i - 1].f, "TOP", 0, 4)
      end
      r.icon:SetWidth(size)
      r.icon:SetHeight(size)
      r.icon:SetPoint("LEFT", f, "LEFT", 4, 0)

      r.pass:SetWidth(button - 6)
      r.pass:SetHeight(button - 6)
      r.pass:ClearAllPoints()
      r.pass:SetPoint("RIGHT", f, "RIGHT", -5, 0)
      r.greed:SetWidth(button)
      r.greed:SetHeight(button)
      r.greed:ClearAllPoints()
      r.greed:SetPoint("RIGHT", r.pass, "LEFT", -3, 1)
      r.need:SetWidth(button)
      r.need:SetHeight(button)
      r.need:ClearAllPoints()
      r.need:SetPoint("RIGHT", r.greed, "LEFT", -2, 0)

      r.timer:ClearAllPoints()
      r.timer:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 1)
      r.timer:SetPoint("RIGHT", r.need, "LEFT", -6, 0)
      r.timer:SetHeight(math.max(3, math.floor(h / 7)))

      r.bind:ClearAllPoints()
      r.bind:SetPoint("TOPRIGHT", r.need, "TOPLEFT", -6, -1)
      r.text:ClearAllPoints()
      r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1)
      r.text:SetPoint("RIGHT", r.bind, "LEFT", -4, 0)
      r.text:SetHeight(14)
    end
    holder:SetWidth(s.width)
    holder:SetHeight(h)
    entry.apply()
    S.pixelDirty = true
  end
  holder.options = {
    { label = "Width", get = function() return s.width end, set = function(v) s.width = v; Layout() end, min = 200, max = 450, step = 10 },
    { label = "Height", get = function() return s.height end, set = function(v) s.height = v; Layout() end, min = 26, max = 60, step = 1 },
  }
  Layout()
end

-- [[ minimap ]] --
-- square, thin border, no zoom buttons (mouse wheel zooms), zone name inside the top edge
local mapBorder
local function MinimapShape()
  local round = bb.s and bb.s.round
  if Minimap.SetMaskTexture then
    Minimap:SetMaskTexture(round and "Textures\\MinimapMask" or S.TEX)
  end
  if mapBorder then
    if round then mapBorder:Hide() else mapBorder:Show() end
  end
end
-- addons that draw round the map ask for its shape
function GetMinimapShape()
  return (bb.s and bb.s.round) and "ROUND" or "SQUARE"
end

local function StyleMinimap()
  if not Minimap.SetMaskTexture then
    return
  end
  Minimap:SetMaskTexture(S.TEX)
  for _, f in ipairs({ MinimapBorder, MinimapBorderTop, MinimapZoomIn, MinimapZoomOut, MinimapToggleButton }) do
    if f then f:Hide() end
  end
  Minimap:ClearAllPoints()
  -- 1px in, so the map's 1px border is the cluster's (and the holder's) top-right corner
  Minimap:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", -1, -1)
  local border = CreateFrame("Frame", nil, Minimap)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
  S.Backdrop(border, 1)
  mapBorder = border

  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", function()
    local zoom = Minimap:GetZoom() + (arg1 > 0 and 1 or -1)
    if zoom >= 0 and zoom < Minimap:GetZoomLevels() then
      Minimap:SetZoom(zoom)
    end
  end)

  -- Blizzard's zone text ends up under the square map; we draw our own (see CreateZoneText)
  if MinimapZoneTextButton then
    MinimapZoneTextButton:Hide()
  end
  -- the day/night clock sat on the round border; tuck it into the bottom corner
  if GameTimeFrame then
    GameTimeFrame:ClearAllPoints()
    GameTimeFrame:SetScale(0.7)
    GameTimeFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
  end
end

-- [[ addon button bar ]] --
-- Like HidingBar: addon minimap buttons come off the map into a bar that opens from a small
-- button in the map's bottom-left corner, and closes again when the mouse leaves it.
-- Only frames named like buttons are taken (pfQuest's map pins are frames on the minimap
-- too); Blizzard's own tracking/mail/battleground icons stay on the map.
local BLIZZARD_BUTTONS = {
  MinimapZoomIn = 1, MinimapZoomOut = 1, MiniMapTrackingFrame = 1, MiniMapMailFrame = 1,
  MiniMapBattlefieldFrame = 1, MiniMapMeetingStoneFrame = 1, MinimapToggleButton = 1,
  MinimapZoneTextButton = 1, GameTimeFrame = 1, MiniMapWorldMapButton = 1, MinimapBackdrop = 1,
  Minimap = 1, MiniMapPing = 1, MinimapPing = 1, TimeManagerClockButton = 1,
}
local CELL, BAR_PAD = 34, 4
bb = { taken = {}, list = {} }

local function IsAddonButton(f)
  local name = f.GetName and f:GetName()
  if not name or BLIZZARD_BUTTONS[name] or bb.taken[f] or string.find(name, "^SnapUI") then
    return false
  end
  if string.find(name, "Pin") or string.find(name, "Node") or string.find(name, "Note") or string.find(name, "Blip") then
    return false
  end
  if not (string.find(name, "[Bb]utton") or string.find(name, "[Ii]con") or string.find(name, "[Mm]ini[Mm]ap")) then
    return false
  end
  local t = f:GetObjectType()
  if t ~= "Button" and t ~= "Frame" and t ~= "CheckButton" then
    return false
  end
  local w, h = f:GetWidth(), f:GetHeight()
  return w >= 12 and w <= 48 and h >= 12 and h <= 48
end

local function LayoutButtonBar()
  local per = math.max(1, bb.s.perRow)
  local n = 0
  for _, b in ipairs(bb.list) do
    if b:IsShown() then
      local col, row = math.mod(n, per), math.floor(n / per)
      b.snapClear(b)
      b.snapPoint(b, "CENTER", bb.bar, "TOPRIGHT", -BAR_PAD - CELL / 2 - col * CELL, -BAR_PAD - CELL / 2 - row * CELL)
      n = n + 1
    end
  end
  local cols = math.max(1, math.min(per, n))
  local rows = math.max(1, math.ceil(n / per))
  bb.bar:SetWidth(BAR_PAD * 2 + cols * CELL)
  bb.bar:SetHeight(BAR_PAD * 2 + rows * CELL)
  bb.toggle.text:SetText(n > 0 and tostring(n) or "-")
end

local function Take(f)
  bb.taken[f] = true
  table.insert(bb.list, f)
  f:SetParent(bb.bar)
  f:SetFrameStrata("HIGH")
  f:SetFrameLevel(bb.bar:GetFrameLevel() + 2)
  -- the addon can't drag it round the map or put it back any more
  f.snapPoint, f.snapClear = f.SetPoint, f.ClearAllPoints
  f.SetPoint, f.ClearAllPoints = S.noop, S.noop
  f:SetScript("OnDragStart", nil)
  f:SetScript("OnDragStop", nil)
  -- showing or hiding one reflows the bar
  local onShow, onHide = f:GetScript("OnShow"), f:GetScript("OnHide")
  f:SetScript("OnShow", function() if onShow then onShow() end; LayoutButtonBar() end)
  f:SetScript("OnHide", function() if onHide then onHide() end; LayoutButtonBar() end)
end

local function CollectButtons()
  if not bb.s.collect then
    return
  end
  local found = false
  for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
    if parent then
      local kids = { parent:GetChildren() }
      for _, f in ipairs(kids) do
        if IsAddonButton(f) then
          Take(f)
          found = true
        end
      end
    end
  end
  if found then
    LayoutButtonBar()
  end
end

-- the holder is exactly the square map plus its 1px border, nothing else from the cluster
local function MinimapBox()
  return Minimap:GetWidth() + 2, Minimap:GetHeight() + 2
end

-- minimap size: scale the whole cluster (map, icons, zone text) and fit the holder to it
local function ApplyMinimapSize(holder)
  local scale = bb.s.scale
  MinimapCluster:SetScale(scale)
  local w, h = MinimapBox()
  S:Fit(holder, MinimapCluster, w, h)
  -- growing from the centre can push a corner map off screen: pull it back on
  local p = S.db.pos[holder.name]
  if p and not p.point and S.ClampToScreen then
    local x, y = S.ClampToScreen(holder, p[1], p[2])
    if x ~= p[1] or y ~= p[2] then
      S:SavePosition(holder, x, y)
      S:Place(holder)
    end
  end
  -- a map that was in a corner stays tight in it
  if S.HugEdges then
    S:HugEdges(holder, 10)
  end
end

-- [[ zone name ]] --
-- the zone (or subzone) name on the map, coloured like Blizzard's: green friendly, red
-- hostile, orange contested, blue sanctuary. Inside the top edge, or under the map.
local zone

local ZONE_COLORS = {
  friendly = { 0.1, 1, 0.1 }, hostile = { 1, 0.1, 0.1 }, combat = { 1, 0.1, 0.1 }, arena = { 1, 0.1, 0.1 },
  contested = { 1, 0.7, 0 }, sanctuary = { 0.41, 0.8, 0.94 },
}

local function UpdateZoneText()
  local s = bb.s
  if not zone then
    return
  end
  if not s.zone then
    zone:Hide()
    return
  end
  zone:ClearAllPoints()
  if s.zoneBelow then
    zone:SetPoint("TOP", Minimap, "BOTTOM", 0, -3)
  else
    zone:SetPoint("TOP", Minimap, "TOP", 0, -3)
  end
  zone:SetWidth(Minimap:GetWidth() - 6)
  zone:SetHeight(s.zoneSize + 4)
  zone.text:SetFont(S.FONT, s.zoneSize, "OUTLINE")
  zone.text:SetText(GetMinimapZoneText() or "")
  local c = ZONE_COLORS[GetZonePVPInfo() or ""] or { 1, 0.82, 0 }
  zone.text:SetTextColor(c[1], c[2], c[3])
  zone:Show()
end

local function CreateZoneText()
  zone = CreateFrame("Frame", "SnapUI_ZoneText", Minimap)
  zone:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  zone.text = S.Text(zone, bb.s.zoneSize, "CENTER")
  zone.text:SetAllPoints(zone)
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    zone:RegisterEvent(e)
  end
  zone:SetScript("OnEvent", UpdateZoneText)
  UpdateZoneText()
end

local function CreateButtonBar(holder)
  bb.s = S:Settings("frames", "minimap", { collect = true, perRow = 6, scale = 1, zone = true, zoneSize = 12, zoneBelow = false, round = false })
  ApplyMinimapSize(holder)
  MinimapShape()
  CreateZoneText()

  bb.toggle = CreateFrame("Button", "SnapUI_MinimapButtons", Minimap)
  bb.toggle:SetWidth(16)
  bb.toggle:SetHeight(16)
  bb.toggle:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 2)
  bb.toggle:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  S.Backdrop(bb.toggle, 0.85)
  bb.toggle.text = S.Text(bb.toggle, 11, "CENTER")
  bb.toggle.text:SetPoint("CENTER", 1, 0)

  bb.bar = CreateFrame("Frame", "SnapUI_ButtonBar", UIParent)
  bb.bar:SetFrameStrata("HIGH")
  bb.bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 1, -4)
  S.Backdrop(bb.bar, 0.9)
  bb.bar:EnableMouse(true)
  bb.bar:Hide()

  -- close a moment after the mouse leaves both the bar and the toggle
  bb.bar:SetScript("OnUpdate", function()
    if MouseIsOver(bb.bar) or MouseIsOver(bb.toggle) then
      bb.away = 0
      return
    end
    bb.away = (bb.away or 0) + arg1
    if bb.away > 1 then
      bb.bar:Hide()
    end
  end)

  bb.toggle:SetScript("OnClick", function()
    if bb.bar:IsShown() then
      bb.bar:Hide()
    else
      CollectButtons()
      LayoutButtonBar()
      bb.away = 0
      bb.bar:Show()
    end
  end)
  bb.toggle:SetScript("OnEnter", function()
    this:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("Addon buttons")
    GameTooltip:AddLine("Click to show or hide", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  bb.toggle:SetScript("OnLeave", function()
    S.ResetBorder(this)
    GameTooltip:Hide()
  end)
  if not bb.s.collect then
    bb.toggle:Hide()
  end

  holder.options = {
    { label = "Size", get = function() return bb.s.scale end,
      set = function(v) bb.s.scale = v; ApplyMinimapSize(holder) end, min = 0.5, max = 2.5, step = 0.05 },
    { label = "Hide addon buttons", toggle = true, get = function() return bb.s.collect end,
      set = function(v)
        bb.s.collect = v
        if v then
          bb.toggle:Show()
          CollectButtons()
        else
          S.Print("addon buttons go back on the map after a |cff4fc3f7/reload|r")
        end
      end },
    { label = "Buttons per row", get = function() return bb.s.perRow end,
      set = function(v) bb.s.perRow = v; LayoutButtonBar() end, min = 1, max = 12, step = 1 },
    { label = "Zone name", toggle = true, get = function() return bb.s.zone end,
      set = function(v) bb.s.zone = v; UpdateZoneText() end },
    { label = "Zone text size", get = function() return bb.s.zoneSize end,
      set = function(v) bb.s.zoneSize = v; UpdateZoneText() end, min = 8, max = 24, step = 1 },
    { label = "Zone under map", toggle = true, get = function() return bb.s.zoneBelow end,
      set = function(v) bb.s.zoneBelow = v; UpdateZoneText() end },
    { label = "Round", toggle = true, get = function() return bb.s.round end,
      set = function(v) bb.s.round = v; MinimapShape() end },
  }

  LayoutButtonBar()
  CollectButtons()
  -- addons make their buttons at different times; look again for the first few seconds
  local scan, t, tick = CreateFrame("Frame"), 0, 0
  scan:RegisterEvent("PLAYER_ENTERING_WORLD")
  scan:SetScript("OnEvent", function() t = 0; this:Show() end)
  scan:SetScript("OnUpdate", function()
    t, tick = t + arg1, tick + arg1
    if t > 10 then
      this:Hide()
    elseif tick > 1 then
      tick = 0
      CollectButtons()
    end
  end)
end

-- [[ keybind mode ]] --
-- /snap kb: hover any action, pet or stance button and press a key (with Shift/Ctrl/Alt
-- if you like) to bind it there. Escape leaves, Backspace/Delete clears the hovered button.
local BIND_PREFIX = {
  ActionButton = "ACTIONBUTTON", MultiBarBottomLeftButton = "MULTIACTIONBAR1BUTTON",
  MultiBarBottomRightButton = "MULTIACTIONBAR2BUTTON", MultiBarRightButton = "MULTIACTIONBAR3BUTTON",
  MultiBarLeftButton = "MULTIACTIONBAR4BUTTON", ShapeshiftButton = "SHAPESHIFTBUTTON", PetActionButton = "BONUSACTIONBUTTON",
}
local kb

-- the binding command for a button, e.g. ActionButton3 -> ACTIONBUTTON3
local function BindCommand(b)
  local name = b and b.GetName and b:GetName()
  if not name then return nil end
  local _, _, prefix, n = string.find(name, "^(%a+)(%d+)$")
  local cmd = prefix and BIND_PREFIX[prefix]
  return cmd and (cmd .. n), name
end

local function HoveredButton()
  for _, bar in pairs(bars) do
    if bar.frame:IsVisible() then
      for _, b in ipairs(bar.buttons) do
        if b:IsVisible() and MouseIsOver(b) and BindCommand(b) then
          return b
        end
      end
    end
  end
end

local function KeyName(key)
  if key == "LeftButton" or key == "RightButton" then return nil end
  if key == "MiddleButton" then key = "BUTTON3" end
  if key == "Button4" then key = "BUTTON4" end
  if key == "Button5" then key = "BUTTON5" end
  local mods = ""
  if IsAltKeyDown() then mods = mods .. "ALT-" end
  if IsControlKeyDown() then mods = mods .. "CTRL-" end
  if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
  return mods .. key
end

local function RefreshHotkeys()
  for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
    for i = 1, 12 do
      local b = getglobal(prefix .. i)
      if b then S.CallAs(b, ActionButton_UpdateHotkeys, b.buttonType) end
    end
  end
end

local function Bind(key)
  local b = HoveredButton()
  if not b then return end
  local cmd = BindCommand(b)
  if key == "BACKSPACE" or key == "DELETE" then
    -- clear every key on this button
    local k1, k2 = GetBindingKey(cmd)
    if k1 then SetBinding(k1) end
    if k2 then SetBinding(k2) end
    S.Print("cleared " .. cmd)
  else
    SetBinding(key, cmd)
    S.Print(key .. " -> " .. cmd)
  end
  SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
  RefreshHotkeys()
end

function S:ToggleKeybind()
  if not kb then
    kb = CreateFrame("Frame", "SnapUI_Keybind", UIParent)
    kb:SetAllPoints(UIParent)
    kb:SetFrameStrata("TOOLTIP")
    kb:EnableKeyboard(true)
    kb:EnableMouse(false)
    kb.text = S.Text(kb, 16, "CENTER")
    kb.text:SetPoint("TOP", 0, -120)
    kb.text:SetText("|cff4fc3f7Keybind mode|r: hover a button and press a key.  Backspace clears it, Escape is done.")
    kb.hint = S.Text(kb, 13, "CENTER")
    kb.hint:SetPoint("TOP", kb.text, "BOTTOM", 0, -6)
    kb:SetScript("OnKeyDown", function()
      local key = arg1
      if key == "ESCAPE" then
        S:ToggleKeybind()
        return
      end
      if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
        return
      end
      local name = KeyName(key)
      if name then Bind(name) end
    end)
    kb:SetScript("OnUpdate", function()
      local b = HoveredButton()
      local cmd = BindCommand(b)
      if cmd then
        local k1, k2 = GetBindingKey(cmd)
        this.hint:SetText(b:GetName() .. ":  " .. (k1 or "not bound") .. (k2 and (", " .. k2) or ""))
      else
        this.hint:SetText("")
      end
    end)
    kb:Hide()
  end
  if kb:IsShown() then
    kb:Hide()
    S.Print("keybind mode off")
  else
    kb:Show()
  end
end

-- flip one text option (cooldowns / hotkeys / macros) on every action bar at once:
-- off if any bar has it on, otherwise on
function S:ToggleBarText(key)
  local on = false
  for _, bar in pairs(bars) do
    if bar.hasEmpty and bar.settings[key] ~= false then on = true end
  end
  for _, bar in pairs(bars) do
    if bar.hasEmpty then
      bar.settings[key] = not on
      Layout(bar)
    end
  end
  return not on
end

local function ReapplyAll()
  for _, bar in pairs(bars) do
    bar.frame:ClearAllPoints()
    bar.frame:SetPoint("TOPLEFT", bar.holder, "TOPLEFT", 0, 0)
    bar:UpdateVisibility()
  end
  for _, entry in ipairs(adopted) do
    entry.apply()
  end
end

-- [[ setup ]] --
S:RegisterModule("actionbars", function()
  -- Blizzard stops managing what we now own
  if UIPARENT_MANAGED_FRAME_POSITIONS then
    for _, name in ipairs({ "MultiBarBottomLeft", "CastingBarFrame", "ShapeshiftBarFrame" }) do
      UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
    end
  end

  -- all four extra bars exist (visibility is ours); this also stops the main bar paging into them
  SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2, SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 = 1, 1, 1, 1
  MultiActionBar_Update()

  -- stance/stealth paging happens on the main bar itself instead of the bonus bar overlay
  for i = 1, 12 do
    local b = getglobal("ActionButton" .. i)
    if b then b.snapMain = true end
  end
  local origPaged = ActionButton_GetPagedID
  ActionButton_GetPagedID = function(button)
    if button.snapMain and CURRENT_ACTIONBAR_PAGE == 1 then
      local offset = GetBonusBarOffset()
      if offset > 0 then
        return button:GetID() + (NUM_ACTIONBAR_PAGES + offset - 1) * NUM_ACTIONBAR_BUTTONS
      end
    end
    return origPaged(button)
  end
  S.Kill(BonusActionBarFrame)

  CreateBar({
    key = "bar1", label = "Action bar 1", buttons = Names("ActionButton", 12), actions = true,
    default = { "BOTTOM", nil, 0, 18 }, settings = { buttons = 12, perRow = 12, spacing = 2, scale = 1, empty = true, hidden = false },
  })
  CreateBar({
    key = "bar2", label = "Action bar 2", buttons = Names("MultiBarBottomLeftButton", 12), frame = "MultiBarBottomLeft", actions = true,
    default = { "BOTTOM", nil, 0, 60 }, settings = { buttons = 12, perRow = 12, spacing = 2, scale = 1, empty = true, hidden = false },
  })
  CreateBar({
    key = "bar3", label = "Action bar 3", buttons = Names("MultiBarBottomRightButton", 12), frame = "MultiBarBottomRight", actions = true,
    default = { "BOTTOM", nil, 0, 102 }, settings = { buttons = 12, perRow = 12, spacing = 2, scale = 1, empty = true, hidden = false },
  })
  CreateBar({
    key = "bar4", label = "Action bar 4", buttons = Names("MultiBarRightButton", 12), frame = "MultiBarRight", actions = true,
    default = { "RIGHT", nil, -4, 0 }, settings = { buttons = 12, perRow = 1, spacing = 2, scale = 1, empty = true, hidden = false },
  })
  CreateBar({
    key = "bar5", label = "Action bar 5", buttons = Names("MultiBarLeftButton", 12), frame = "MultiBarLeft", actions = true,
    default = { "RIGHT", nil, -46, 0 }, settings = { buttons = 12, perRow = 1, spacing = 2, scale = 1, empty = true, hidden = false },
  })
  local pet = CreateBar({
    key = "pet", label = "Pet bar", buttons = Names("PetActionButton", 10),
    default = { "BOTTOM", nil, 0, 146 }, settings = { buttons = 10, perRow = 10, spacing = 2, scale = 1, hidden = false },
    visible = function() return PetHasActionBar() end,
  })
  local stance = CreateBar({
    key = "stance", label = "Stance bar", buttons = Names("ShapeshiftButton", 10),
    default = { "BOTTOMLEFT", "BOTTOM", -230, 146 }, settings = { buttons = 10, perRow = 10, spacing = 2, scale = 1, hidden = false },
    visible = function() return GetNumShapeshiftForms() > 0 end,
    dynamicCount = function() return GetNumShapeshiftForms() end,
  })
  CreateBar({
    key = "micro", label = "Micro menu", skin = false, size = 26, height = 36, yOffset = 21,
    buttons = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
      "SocialsMicroButton", "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton" },
    default = { "BOTTOMRIGHT", nil, -4, 4 }, settings = { buttons = 8, perRow = 8, spacing = 0, scale = 1, hidden = false },
  })
  -- micro buttons are 29x58 with the art at the bottom; let them hang down into a 26x36 slot
  for _, name in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
    "SocialsMicroButton", "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton" }) do
    local b = getglobal(name)
    if b then b:SetHitRectInsets(0, 0, 18, 0) end
  end
  CreateBar({
    key = "bags", label = "Bags", size = 32, noSkin = { KeyRingButton = true },
    buttons = { "KeyRingButton", "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" },
    default = { "BOTTOMRIGHT", nil, -4, 44 }, settings = { buttons = 6, perRow = 6, spacing = 2, scale = 1, hidden = false },
  })
  for _, name in ipairs({ "KeyRingButton", "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" }) do
    local b = getglobal(name)
    if b and name ~= "KeyRingButton" then
      b:SetWidth(32)
      b:SetHeight(32)
    end
  end
  if KeyRingButton then
    KeyRingButton:SetHeight(32)
  end

  CreateXPBar()

  -- Blizzard's own bar art goes away; everything useful has been moved out of it
  MainMenuBar:Hide()
  MainMenuBar.Show = S.noop
  S.Kill(ReputationWatchBar)
  S.Kill(MainMenuBarMaxLevelBar)
  S.Kill(MainMenuBarPerformanceBarFrame)
  -- these stay alive for their events, but their own art and mouse area must not show
  for _, f in ipairs({ PetActionBarFrame, ShapeshiftBarFrame }) do
    if f then
      f:SetAlpha(0)
      f:EnableMouse(false)
    end
  end
  -- buttons ran their hotkey update before our abbreviations existed
  for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
    for i = 1, 12 do
      local b = getglobal(prefix .. i)
      if b then S.CallAs(b, ActionButton_UpdateHotkeys, b.buttonType) end
    end
  end

  local cast = Adopt("cast", "Cast bar", CastingBarFrame, { "BOTTOM", nil, 0, 190 }, "CENTER", 240, 22)
  if cast then
    StyleCastBar(cast)
  end
  -- the cluster is bigger than the square map in its corner; the holder covers just the map
  -- (ApplyMinimapSize sizes it to the map once it's styled)
  local minimap = Adopt("minimap", "Minimap", MinimapCluster, { "TOPRIGHT", nil, 0, 0 }, "TOPRIGHT", 142, 142)
  StyleMinimap()
  if minimap then
    CreateButtonBar(minimap.holder)
  end
  -- buffs and debuffs have their own module (buffs.lua)
  -- Blizzard hangs these under the minimap; they get their own boxes instead
  Adopt("questwatch", "Quest tracker", QuestWatchFrame, { "TOPRIGHT", nil, -10, -260 }, "TOPRIGHT", 220, 300)
  Adopt("durability", "Durability figure", DurabilityFrame, { "TOPRIGHT", nil, -240, -260 }, "TOPRIGHT", 60, 75)
  -- breath / fatigue / feign death bars (2 and 3 hang under the first) and the need/greed
  -- roll windows (2-4 stack above the first), at Blizzard's own spots to begin with
  Adopt("mirror", "Breath bar", MirrorTimer1, { "TOP", nil, 0, -96 }, "TOP", 206, 26)
  local lootroll = Adopt("lootroll", "Loot rolls", GroupLootFrame1, { "BOTTOM", nil, 0, 60 }, "BOTTOM", 243, 84)
  if lootroll then
    StyleLootRolls(lootroll)
  end

  -- events that change which bars should be showing
  local events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_PET", "PET_BAR_UPDATE", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_BONUS_ACTIONBAR" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function()
    if event == "UPDATE_BONUS_ACTIONBAR" or event == "PLAYER_ENTERING_WORLD" then
      for i = 1, 12 do
        local b = getglobal("ActionButton" .. i)
        if b then S.CallAs(b, ActionButton_UpdateAction) end
      end
    end
    if event == "UPDATE_SHAPESHIFT_FORMS" or event == "PLAYER_ENTERING_WORLD" then
      Layout(stance)
    end
    pet:UpdateVisibility()
    stance:UpdateVisibility()
  end)

  S.PostHook("MultiActionBar_Update", ReapplyAll)
  S.PostHook("UIParent_ManageFramePositions", ReapplyAll)
  S.PostHook("ShapeshiftBar_UpdatePosition", ReapplyAll)
  ReapplyAll()
end, "Action bars", "Bars 1-5, pet and stance bars, micro menu, bag buttons, XP bar, cast bar and minimap.", true)
