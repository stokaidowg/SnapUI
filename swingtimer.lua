-- SnapUI swing timer: a bar that fills over your main-hand swing, so you can see when the next
-- hit lands (time a Judgement or a seal swap between swings). Swings come from nampower's
-- AUTO_ATTACK_SELF when it's there, and from the combat log (your hits and misses) either way;
-- a swing seen twice within a moment counts once. Finishing a spell with a cast time restarts
-- the swing, as it does in vanilla. Shown while you're auto-attacking (or always, as an option),
-- and in edit mode so it can be placed.

local S = SnapUI

local swing = { start = nil, speed = 2, attacking = false, preview = false }

local function Speed()
  local main = UnitAttackSpeed and UnitAttackSpeed("player")
  return (main and main > 0) and main or 2
end

local function Swung()
  local now = GetTime()
  -- nampower and the combat log both report the same swing
  if swing.start and now - swing.start < 0.2 then return end
  swing.start = now
  swing.speed = Speed()
end

S:RegisterModule("swingtimer", function()
  local s = S:Settings("frames", "swing", { width = 240, height = 10, always = false, text = true, enabled = true })
  -- just above the cast bar to start with, wherever that is
  local cast = S.byName.cast
  local holder = S:Holder("swing", "Swing timer", cast and { "BOTTOM", "TOP", 0, 4, cast } or { "BOTTOM", nil, 0, 166 }, {})
  holder.isOff = function() return not s.enabled end

  local f = CreateFrame("Frame", "SnapUI_Swing", holder)
  f:SetPoint("CENTER", holder, "CENTER", 0, 0)
  S.Backdrop(f, 0.8)
  f.bar = S.StatusBar(f)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.bar:SetMinMaxValues(0, 1)
  f.bar:SetStatusBarColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3])
  f.text = S.Text(f.bar.over or f.bar, 10, "RIGHT")
  f.text:SetPoint("RIGHT", f, "RIGHT", -3, 0)
  f.speed = S.Text(f.bar.over or f.bar, 10, "LEFT")
  f.speed:SetPoint("LEFT", f, "LEFT", 3, 0)

  local function Layout()
    f:SetWidth(s.width)
    f:SetHeight(s.height)
    S:Fit(holder, f)
    if s.text and s.height >= 8 then f.text:Show() f.speed:Show() else f.text:Hide() f.speed:Hide() end
  end

  local function Visible()
    if not s.enabled then return false end
    return swing.preview or swing.attacking or s.always
  end

  local elapsed = 0
  f:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < 0.02 then return end
    elapsed = 0
    if not Visible() then
      if this:GetAlpha() > 0 then this:SetAlpha(0) end
      return
    end
    this:SetAlpha(1)
    local speed = swing.speed or Speed()
    local left
    if swing.preview and not swing.start then
      left = speed * 0.4
    elseif swing.start then
      left = math.max(0, speed - (GetTime() - swing.start))
    else
      left = 0
    end
    this.bar:SetValue(1 - left / speed)
    if left <= 0 then
      this.bar:SetStatusBarColor(0.3, 0.85, 0.4) -- ready to swing
    else
      this.bar:SetStatusBarColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3])
    end
    this.text:SetText(left > 0 and string.format("%.1f", left) or "")
    this.speed:SetText(string.format("%.2f", speed))
  end)

  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "CHAT_MSG_COMBAT_SELF_HITS",
    "CHAT_MSG_COMBAT_SELF_MISSES", "AUTO_ATTACK_SELF", "SPELLCAST_START", "SPELLCAST_STOP",
    "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED", "UNIT_ATTACK_SPEED" }) do
    ev:RegisterEvent(e)
  end
  local casting = false
  ev:SetScript("OnEvent", function()
    if event == "PLAYER_ENTER_COMBAT" then
      -- auto attack on: the first swing is immediate if the last one is long done
      swing.attacking = true
      if not swing.start or GetTime() - swing.start > Speed() then
        swing.start = nil
      end
    elseif event == "PLAYER_LEAVE_COMBAT" then
      swing.attacking = false
    elseif event == "AUTO_ATTACK_SELF" or event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
      Swung()
    elseif event == "SPELLCAST_START" then
      casting = true
    elseif event == "SPELLCAST_STOP" then
      -- a finished cast-time spell restarts the swing (instants never send SPELLCAST_START)
      if casting and swing.attacking then
        swing.start = GetTime()
        swing.speed = Speed()
      end
      casting = false
    elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
      casting = false
    elseif event == "UNIT_ATTACK_SPEED" and arg1 == "player" then
      -- haste changed mid-swing: keep the same share of the swing done
      if swing.start then
        local new, old = Speed(), swing.speed or Speed()
        local done = (GetTime() - swing.start) / old
        swing.speed = new
        swing.start = GetTime() - done * new
      end
    end
  end)

  S:OnEdit(function(on) swing.preview = on end)

  holder.options = {
    { label = "Show", get = function() return s.enabled end, set = function(v) s.enabled = v end, toggle = true },
    { label = "Width", get = function() return s.width end, set = function(v) s.width = v; Layout() end, min = 80, max = 450, step = 10 },
    { label = "Height", get = function() return s.height end, set = function(v) s.height = v; Layout() end, min = 4, max = 30, step = 1 },
    { label = "Time and speed text", get = function() return s.text end, set = function(v) s.text = v; Layout() end, toggle = true },
    { label = "Show when not attacking", get = function() return s.always end, set = function(v) s.always = v end, toggle = true },
  }
  Layout()
  S.Swing = swing
end, "Swing timer", "A bar that fills over your weapon swing, so you can see when your next hit lands.")
