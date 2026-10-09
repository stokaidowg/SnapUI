-- SnapUI edit mode: a see-through grid over the screen, a draggable box over every holder,
-- live snapping to the grid (edges or centre, whichever is closest), and a small options
-- panel on right-click.

local S = SnapUI

local grid, toolbar, panel
local overlays = {}
local editing = false

-- [[ grid ]] --
local function BuildGrid()
  if not grid then
    grid = CreateFrame("Frame", "SnapUIGrid", UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:SetFrameLevel(0)
    grid.lines = {}
  end
  for _, line in ipairs(grid.lines) do
    line:Hide()
  end

  local step = S.db.grid
  local w, h = UIParent:GetWidth(), UIParent:GetHeight()
  local n = 0
  local function Line(vertical, offset)
    n = n + 1
    local line = grid.lines[n]
    if not line then
      line = grid:CreateTexture(nil, "BACKGROUND")
      line:SetTexture(S.TEX)
      grid.lines[n] = line
    end
    line:ClearAllPoints()
    if vertical then
      line:SetWidth(1)
      line:SetPoint("TOP", grid, "TOP", offset, 0)
      line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
    else
      line:SetHeight(1)
      line:SetPoint("LEFT", grid, "LEFT", 0, offset)
      line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
    end
    if offset == 0 then
      line:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.55)
    elseif math.mod(math.floor(math.abs(offset) / step + 0.5), 4) == 0 then
      line:SetVertexColor(1, 1, 1, 0.16)
    else
      line:SetVertexColor(1, 1, 1, 0.07)
    end
    line:Show()
  end

  -- lines run out from the screen centre so the centre is always on the grid
  for x = 0, w / 2, step do
    Line(true, x)
    if x > 0 then Line(true, -x) end
  end
  for y = 0, h / 2, step do
    Line(false, y)
    if y > 0 then Line(false, -y) end
  end
end

-- [[ snapping ]] --
-- offset of a holder's centre from the screen centre
local function CenterOffset(h)
  local x, y = h:GetCenter()
  local cx, cy = UIParent:GetCenter()
  return x - cx, y - cy
end

-- the screen's edges as offsets from UIParent's centre. Normally UIParent is the whole
-- screen, but if something has shrunk it, the 3D view (WorldFrame) still is, so take
-- whichever reaches further.
function S.ScreenBounds()
  local cx, cy = UIParent:GetCenter()
  local hw, hh = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
  local l, r, b, t = -hw, hw, -hh, hh
  local wl, wb = WorldFrame:GetLeft(), WorldFrame:GetBottom()
  if wl and wb and cx then
    local k = WorldFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l = math.min(l, wl * k - cx)
    b = math.min(b, wb * k - cy)
    r = math.max(r, (wl + WorldFrame:GetWidth()) * k - cx)
    t = math.max(t, (wb + WorldFrame:GetHeight()) * k - cy)
  end
  return l, r, b, t
end

-- move v so that one of v-half, v, v+half lands on a grid line, or an edge lands on the
-- screen edge (the grid runs out from the centre, so the edges are rarely on it), picking
-- whichever is closest
local function SnapAxis(v, half, low, high)
  local step = S.db.grid
  local best, bestDist = v, nil
  local function Try(target)
    local dist = math.abs(target - v)
    if not bestDist or dist < bestDist then
      best, bestDist = target, dist
    end
  end
  for _, edge in ipairs({ -half, 0, half }) do
    Try(math.floor((v + edge) / step + 0.5) * step - edge)
  end
  Try(low + half)
  Try(high - half)
  return best
end

-- keep a holder fully on screen; its edges may sit right on the screen edge
function S.ClampToScreen(h, x, y)
  local hw, hh = h:GetWidth() / 2, h:GetHeight() / 2
  local l, r, b, t = S.ScreenBounds()
  return math.max(l + hw, math.min(r - hw, x)), math.max(b + hh, math.min(t - hh, y))
end
local Clamp = S.ClampToScreen

-- a saved spot that's within `within` of a screen edge goes flush against it (for elements
-- that just got smaller, so they don't end up a few pixels off the edge they were on)
function S:HugEdges(h, within)
  local p = self.db.pos[h.name]
  if not p or p.point then
    return
  end
  local hw, hh = h:GetWidth() / 2, h:GetHeight() / 2
  local l, r, b, t = S.ScreenBounds()
  local x, y = p[1], p[2]
  if math.abs(x - hw - l) <= within then x = l + hw elseif math.abs(r - x - hw) <= within then x = r - hw end
  if math.abs(y - hh - b) <= within then y = b + hh elseif math.abs(t - y - hh) <= within then y = t - hh end
  if x ~= p[1] or y ~= p[2] then
    p[1], p[2] = x, y
    self:Place(h)
  end
end

local function CursorPos()
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  local cx, cy = UIParent:GetCenter()
  return x / s - cx, y / s - cy
end

-- [[ selection ]] --
-- Ctrl-click boxes to select several; dragging any selected box moves them all together,
-- and option changes in the right-click panel apply to every selected element
local selected = {}

local function SelectedList()
  local list = {}
  for _, h in ipairs(S.holders) do
    if selected[h] then table.insert(list, h) end
  end
  return list
end

-- [[ overlays ]] --
local function RefreshOverlay(h)
  local o = overlays[h]
  if not o then
    return
  end
  local off = h.isOff and h.isOff()
  o.text:SetText(h.label .. (off and "  |cffff6060(off)|r" or ""))
  if selected[h] then
    o:SetBackdropColor(1, 0.6, 0.15, 0.35)
    o:SetBackdropBorderColor(1, 0.6, 0.15, 1)
  elseif off then
    o:SetBackdropColor(0.4, 0.4, 0.4, 0.25)
    o:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
  else
    o:SetBackdropColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.28)
    o:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
  end
end
-- the settings window refreshes the box label too when an option changes there
S.RefreshOverlay = RefreshOverlay

local function ClearSelection()
  for h in pairs(selected) do
    selected[h] = nil
    RefreshOverlay(h)
  end
end

local function OverlayUpdate()
  local o = this
  if not o.dragging then
    return
  end
  local h = o.holder
  local cx, cy = CursorPos()
  local x, y = cx + o.dx, cy + o.dy
  local l, r, b, t = S.ScreenBounds()
  if S.db.snap and not IsShiftKeyDown() then
    x = SnapAxis(x, h:GetWidth() / 2, l, r)
    y = SnapAxis(y, h:GetHeight() / 2, b, t)
  end

  -- move the whole group by the same amount, stopping when any member hits an edge
  local dx, dy = x - o.x0, y - o.y0
  for _, m in ipairs(o.group) do
    local hw, hh = m.h:GetWidth() / 2, m.h:GetHeight() / 2
    dx = math.max(l + hw - m.x, math.min(r - hw - m.x, dx))
    dy = math.max(b + hh - m.y, math.min(t - hh - m.y, dy))
  end
  for _, m in ipairs(o.group) do
    m.h:ClearAllPoints()
    m.h:SetPoint("CENTER", UIParent, "CENTER", m.x + dx, m.y + dy)
  end
  o.moveX, o.moveY = dx, dy
end

local function CreateOverlay(h)
  local o = CreateFrame("Button", nil, h)
  o:SetAllPoints(h)
  o:SetFrameStrata("DIALOG")
  o:EnableMouse(true)
  o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  S.PixelBackdrop(o)
  o:SetBackdropColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.28)
  o:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
  o.holder = h
  o.text = S.Text(o, 11, "CENTER")
  o.text:SetPoint("CENTER", 0, 0)
  o.text:SetText(h.label)

  o:SetScript("OnMouseDown", function()
    if arg1 ~= "LeftButton" then
      return
    end
    local h = this.holder
    if IsControlKeyDown() then
      selected[h] = not selected[h] or nil
      RefreshOverlay(h)
      return
    end
    -- grabbing something outside the selection drops the selection
    if not selected[h] then
      ClearSelection()
    end
    local x, y = CenterOffset(h)
    local cx, cy = CursorPos()
    this.dx, this.dy = x - cx, y - cy
    this.x0, this.y0 = x, y
    this.moveX, this.moveY = 0, 0
    this.group = {}
    local members = selected[h] and SelectedList() or { h }
    for _, m in ipairs(members) do
      local mx, my = CenterOffset(m)
      table.insert(this.group, { h = m, x = mx, y = my })
    end
    this.dragging = true
  end)
  o:SetScript("OnMouseUp", function()
    if arg1 == "LeftButton" and this.dragging then
      this.dragging = false
      for _, m in ipairs(this.group) do
        local x, y = m.x + this.moveX, m.y + this.moveY
        S:SavePosition(m.h, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10)
      end
    elseif arg1 == "RightButton" then
      S:OpenOptions(this.holder)
    end
  end)
  o:SetScript("OnUpdate", OverlayUpdate)
  o:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(this.holder.label)
    GameTooltip:AddLine("Drag to move. Hold Shift to place freely.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Ctrl-click to select several and move them together.", 0.8, 0.8, 0.8)
    if this.holder.options then
      GameTooltip:AddLine("Right-click for options.", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end)
  o:SetScript("OnLeave", function() GameTooltip:Hide() end)
  o:Hide()
  overlays[h] = o
  return o
end

-- [[ options panel ]] --
-- holder.options = { { label, get, set, min, max, step } or { label, get, set, toggle = true }
--   or { label, get, set, choices = { { value, "Label" }, ... } } (a button that cycles them), ... }

-- the label of a choice option's current value, and the value after it
function S.ChoiceLabel(opt, v)
  for _, c in ipairs(opt.choices) do
    if c[1] == v then return c[2] end
  end
  return tostring(v)
end
function S.NextChoice(opt, v, dir)
  local n = table.getn(opt.choices)
  for i, c in ipairs(opt.choices) do
    if c[1] == v then
      return opt.choices[math.mod(i - 1 + (dir or 1) + n, n) + 1][1]
    end
  end
  return opt.choices[1][1]
end
local function PanelButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w or 20)
  b:SetHeight(18)
  S.Backdrop(b, 1)
  b:SetBackdropColor(0.18, 0.18, 0.18, 1)
  b.text = S.Text(b, 11, "CENTER")
  b.text:SetPoint("CENTER", 0, 0)
  b.text:SetText(text)
  b:SetScript("OnEnter", function() this:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1) end)
  b:SetScript("OnLeave", function() S.ResetBorder(this) end)
  return b
end

local function FormatValue(v)
  if math.floor(v) == v then
    return tostring(v)
  end
  return string.format("%.2f", v)
end

function S:OpenOptions(h)
  if not h.options then
    return
  end
  if not panel then
    panel = CreateFrame("Frame", "SnapUIOptions", UIParent)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    S.Backdrop(panel, 0.95)
    panel.title = S.Text(panel, 13, "LEFT")
    panel.title:SetPoint("TOPLEFT", 10, -8)
    panel.close = PanelButton(panel, "x")
    panel.close:SetPoint("TOPRIGHT", -6, -6)
    panel.close:SetScript("OnClick", function() panel:Hide() end)
    panel.rows = {}
    -- a hidden text box can keep the keyboard; let go of it when the panel closes
    panel:SetScript("OnHide", function()
      for _, row in ipairs(this.rows) do
        row.value:ClearFocus()
      end
    end)
  end
  for _, row in ipairs(panel.rows) do
    row:Hide()
  end

  local count = selected[h] and table.getn(SelectedList()) or 1
  panel.title:SetText(h.label .. (count > 1 and ("  |cffff9926+" .. (count - 1) .. " selected|r") or ""))
  for i, o in ipairs(h.options) do
    -- Lua 5.0 shares loop variables between iterations, so closures need their own copy
    local opt = o
    local row = panel.rows[i]
    if not row then
      row = CreateFrame("Frame", nil, panel)
      row:SetWidth(200)
      row:SetHeight(20)
      row:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 24)
      row.label = S.Text(row, 12, "LEFT")
      row.label:SetPoint("LEFT", 0, 0)
      row.minus = PanelButton(row, "-")
      row.minus:SetPoint("RIGHT", row, "RIGHT", -60, 0)
      -- the value is a text box: click it, type a number, Enter (Esc puts it back)
      row.value = CreateFrame("EditBox", nil, row)
      row.value:SetWidth(40)
      row.value:SetHeight(18)
      row.value:SetPoint("LEFT", row.minus, "RIGHT", 0, 0)
      row.value:SetAutoFocus(false)
      row.value:SetFontObject(GameFontHighlightSmall)
      if row.value.SetFont then row.value:SetFont(S.FONT, 12, "") end
      row.value:SetJustifyH("CENTER")
      row.value:SetTextInsets(2, 2, 0, 0)
      row.value:SetMaxLetters(8)
      S.Backdrop(row.value, 1)
      row.value:SetBackdropColor(0.08, 0.08, 0.08, 1)
      row.value:SetScript("OnEnter", function() this:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1) end)
      row.value:SetScript("OnLeave", function() if not this.focused then S.ResetBorder(this) end end)
      row.value:SetScript("OnEditFocusGained", function()
        this.focused = true
        this:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
        this:HighlightText()
      end)
      row.plus = PanelButton(row, "+")
      row.plus:SetPoint("LEFT", row.value, "RIGHT", 0, 0)
      row.toggle = PanelButton(row, "", 80)
      row.toggle:SetPoint("RIGHT", row, "RIGHT", 0, 0)
      row.toggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      panel.rows[i] = row
    end
    row.label:SetText(opt.label)
    -- with several selected, the same option on the others changes too
    local function SetAll(v)
      opt.set(v)
      if not selected[h] then
        return
      end
      for _, other in ipairs(SelectedList()) do
        if other ~= h and other.options then
          for _, o2 in ipairs(other.options) do
            if o2.label == opt.label and not o2.toggle == not opt.toggle and not o2.choices == not opt.choices then
              o2.set(v)
            end
          end
          RefreshOverlay(other)
        end
      end
    end
    local function Refresh()
      if opt.choices then
        row.toggle.text:SetText(S.ChoiceLabel(opt, opt.get()))
      elseif opt.toggle then
        row.toggle.text:SetText(opt.get() and "|cff60ff60On|r" or "|cffff6060Off|r")
      else
        row.value:SetText((opt.format or FormatValue)(opt.get()))
      end
    end
    if opt.choices then
      -- left-click for the next choice, right-click for the one before
      row.minus:Hide()
      row.plus:Hide()
      row.value:Hide()
      row.toggle:SetWidth(110)
      row.toggle:Show()
      row.toggle:SetScript("OnClick", function()
        SetAll(S.NextChoice(opt, opt.get(), arg1 == "RightButton" and -1 or 1))
        Refresh()
        RefreshOverlay(h)
      end)
    elseif opt.toggle then
      row.minus:Hide()
      row.plus:Hide()
      row.value:Hide()
      row.toggle:SetWidth(80)
      row.toggle:Show()
      row.toggle:SetScript("OnClick", function() SetAll(not opt.get()); Refresh(); RefreshOverlay(h) end)
    else
      row.toggle:Hide()
      row.minus:Show()
      row.plus:Show()
      row.value:Show()
      local function Step(dir)
        local v = opt.get() + dir * opt.step
        v = math.floor(v / opt.step + 0.5) * opt.step
        SetAll(math.max(opt.min, math.min(opt.max, v)))
        Refresh()
      end
      row.minus:SetScript("OnClick", function() Step(-1) end)
      row.plus:SetScript("OnClick", function() Step(1) end)
      -- typed values aren't snapped to the step (width 223 is fine), only kept in range
      local function Typed()
        local text = string.gsub(row.value:GetText() or "", "[^%d%.%-]", "")
        local v = tonumber(text)
        if v then
          v = math.floor(v * 100 + 0.5) / 100
          SetAll(math.max(opt.min, math.min(opt.max, v)))
        end
      end
      local function Done()
        row.value.focused = nil
        S.ResetBorder(row.value)
        row.value:HighlightText(0, 0)
        Refresh()
      end
      row.value:SetScript("OnEnterPressed", function() Typed(); this:ClearFocus() end)
      row.value:SetScript("OnEscapePressed", function() this:ClearFocus() end)
      row.value:SetScript("OnEditFocusLost", function() Done() end)
    end
    Refresh()
    row:Show()
  end

  local n = table.getn(h.options)
  for i = 1, n do
    panel.rows[i]:SetWidth(230)
  end
  panel:SetWidth(250)
  panel:SetHeight(40 + n * 24)
  panel:ClearAllPoints()
  local _, y = h:GetCenter()
  if y > UIParent:GetHeight() / 2 then
    panel:SetPoint("TOP", h, "BOTTOM", 0, -8)
  else
    panel:SetPoint("BOTTOM", h, "TOP", 0, 8)
  end
  panel:Show()
end

-- [[ toolbar ]] --
local function Popup(key, def)
  def.timeout, def.whileDead, def.hideOnEscape = 0, 1, 1
  def.button1 = def.button1 or YES
  def.button2 = def.button2 or NO
  StaticPopupDialogs[key] = def
end

local function BuildToolbar()
  toolbar = CreateFrame("Frame", "SnapUIToolbar", UIParent)
  toolbar:SetFrameStrata("FULLSCREEN_DIALOG")
  toolbar:SetWidth(520)
  toolbar:SetHeight(54)
  toolbar:SetPoint("TOP", UIParent, "TOP", 0, -60)
  toolbar:EnableMouse(true)
  S.Backdrop(toolbar, 0.95)

  -- [[ top row: grid and layout ]] --
  local title = S.Text(toolbar, 13, "LEFT")
  title:SetPoint("TOPLEFT", 10, -9)
  title:SetText("|cff4fc3f7SnapUI|r edit mode")
  local settings = PanelButton(toolbar, "Settings", 60)
  settings:SetPoint("LEFT", title, "RIGHT", 10, 0)
  settings:SetScript("OnClick", function() if S.ToggleConfig then S:ToggleConfig("elements") end end)

  local done = PanelButton(toolbar, "Done", 50)
  done:SetPoint("TOPRIGHT", -6, -6)
  done:SetScript("OnClick", function() S:ToggleEdit() end)

  local reset = PanelButton(toolbar, "Reset", 50)
  reset:SetPoint("RIGHT", done, "LEFT", -4, 0)
  reset:SetScript("OnClick", function() StaticPopup_Show("SNAPUI_RESET") end)

  local snap = PanelButton(toolbar, "", 64)
  snap:SetPoint("RIGHT", reset, "LEFT", -4, 0)
  local function SnapText()
    snap.text:SetText("Snap: " .. (S.db.snap and "|cff60ff60On|r" or "|cffff6060Off|r"))
  end
  snap:SetScript("OnClick", function() S.db.snap = not S.db.snap; SnapText() end)
  SnapText()

  local plus = PanelButton(toolbar, "+")
  plus:SetPoint("RIGHT", snap, "LEFT", -4, 0)
  local size = S.Text(toolbar, 12, "CENTER")
  size:SetWidth(54)
  size:SetPoint("RIGHT", plus, "LEFT", 0, 0)
  local minus = PanelButton(toolbar, "-")
  minus:SetPoint("RIGHT", size, "LEFT", 0, 0)
  local function SizeText() size:SetText("Grid " .. S.db.grid) end
  local SIZES = { 8, 12, 16, 24, 32, 48, 64 }
  local function Bump(dir)
    for i, v in ipairs(SIZES) do
      if v == S.db.grid then
        S.db.grid = SIZES[math.max(1, math.min(table.getn(SIZES), i + dir))]
        break
      end
    end
    SizeText()
    BuildGrid()
  end
  minus:SetScript("OnClick", function() Bump(-1) end)
  plus:SetScript("OnClick", function() Bump(1) end)
  SizeText()

  -- [[ bottom row: profiles and selection ]] --
  -- profile drop-down: lists every profile; picking another asks first, since it reloads
  local profile = PanelButton(toolbar, "", 150)
  profile:SetPoint("BOTTOMLEFT", 6, 6)
  profile.text:SetText("Profile: |cff4fc3f7" .. S.root.profile .. "|r  v")

  local menu = CreateFrame("Frame", "SnapUIProfileMenu", toolbar)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetFrameLevel(toolbar:GetFrameLevel() + 10)
  menu:SetPoint("TOPLEFT", profile, "BOTTOMLEFT", 0, -2)
  menu:EnableMouse(true)
  S.Backdrop(menu, 0.97)
  menu:Hide()
  menu.items = {}

  local function Pick(name)
    menu:Hide()
    if name == S.root.profile then
      return
    end
    StaticPopupDialogs["SNAPUI_PROFILE"].text = "Switch to the " .. name .. " profile? This reloads the UI."
    StaticPopupDialogs["SNAPUI_PROFILE"].OnAccept = function() S:SetProfile(name) end
    StaticPopup_Show("SNAPUI_PROFILE")
  end

  local function BuildMenu()
    for _, item in ipairs(menu.items) do
      item:Hide()
    end
    local names = S:ProfileNames()
    for i, n in ipairs(names) do
      local name = n
      local item = menu.items[i]
      if not item then
        item = PanelButton(menu, "", 146)
        item.text:ClearAllPoints()
        item.text:SetPoint("LEFT", 6, 0)
        item.text:SetJustifyH("LEFT")
        menu.items[i] = item
      end
      item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 20)
      if name == S.root.profile then
        item.text:SetText("|cff4fc3f7" .. name .. "|r")
      else
        item.text:SetText(name)
      end
      item:SetScript("OnClick", function() Pick(name) end)
      item:Show()
    end
    menu:SetWidth(150)
    menu:SetHeight(4 + table.getn(names) * 20)
  end

  profile:SetScript("OnClick", function()
    if menu:IsShown() then
      menu:Hide()
    else
      BuildMenu()
      menu:Show()
    end
  end)
  -- close it when the mouse wanders off
  menu:SetScript("OnUpdate", function()
    if MouseIsOver(menu) or MouseIsOver(profile) then
      this.away = 0
    else
      this.away = (this.away or 0) + arg1
      if this.away > 1 then this:Hide() end
    end
  end)
  menu:SetScript("OnShow", function() this.away = 0 end)

  local saveAs = PanelButton(toolbar, "Save as", 60)
  saveAs:SetPoint("LEFT", profile, "RIGHT", 4, 0)
  saveAs:SetScript("OnClick", function() StaticPopup_Show("SNAPUI_SAVEAS") end)

  local delete = PanelButton(toolbar, "Delete", 50)
  delete:SetPoint("LEFT", saveAs, "RIGHT", 4, 0)
  delete:SetScript("OnClick", function()
    if table.getn(S:ProfileNames()) < 2 then
      S.Print("can't delete your only profile")
      return
    end
    StaticPopupDialogs["SNAPUI_DELETE"].text = "Delete the " .. S.root.profile .. " profile? You'll switch to another one (reloads)."
    StaticPopup_Show("SNAPUI_DELETE")
  end)

  local clear = PanelButton(toolbar, "Clear selection", 96)
  clear:SetPoint("BOTTOMRIGHT", -6, 6)
  clear:SetScript("OnClick", ClearSelection)
  local hint = S.Text(toolbar, 11, "RIGHT")
  hint:SetPoint("RIGHT", clear, "LEFT", -6, 0)
  hint:SetTextColor(0.7, 0.7, 0.7)
  hint:SetText("Ctrl-click to select several")

  Popup("SNAPUI_PROFILE", { text = "" })
  Popup("SNAPUI_RESET", {
    text = "Move every SnapUI element back to its default position?",
    OnAccept = function() S:ResetPositions() end,
  })
  -- name a copy of the current layout and switch to it
  local function SaveAs(name)
    name = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
    if name == "" then
      return
    end
    S:CopyProfile(name)
    S:SetProfile(name)
  end
  Popup("SNAPUI_SAVEAS", {
    text = "Save this layout as a new profile:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnAccept = function()
      SaveAs(getglobal(this:GetParent():GetName() .. "EditBox"):GetText())
    end,
    EditBoxOnEnterPressed = function()
      local name = this:GetText()
      this:GetParent():Hide()
      SaveAs(name)
    end,
    EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
  })
  Popup("SNAPUI_DELETE", {
    text = "",
    OnAccept = function()
      local gone = S.root.profile
      local nextName
      for _, n in ipairs(S:ProfileNames()) do
        if n ~= gone then nextName = nextName or n end
      end
      S:DeleteProfile(gone)
      S:SetProfile(nextName)
    end,
  })
end

-- [[ toggle ]] --
function S:ToggleEdit()
  editing = not editing
  if editing then
    BuildGrid()
    if not toolbar then
      BuildToolbar()
    end
    grid:Show()
    toolbar:Show()
    for _, h in ipairs(self.holders) do
      (overlays[h] or CreateOverlay(h)):Show()
      RefreshOverlay(h)
    end
  else
    if grid then grid:Hide() end
    if toolbar then toolbar:Hide() end
    if panel then panel:Hide() end
    ClearSelection()
    for _, o in pairs(overlays) do
      o.dragging = false
      o:Hide()
    end
  end
  for _, m in ipairs(self.editListeners or {}) do
    m(editing)
  end
end

function S:IsEditing()
  return editing
end

-- let a window be dragged by its own background outside edit mode (free placement, kept on
-- screen, saved like an edit-mode move). Child buttons still get their own clicks.
function S:MakeDraggable(handle, h)
  handle:EnableMouse(true)
  handle:SetScript("OnMouseDown", function()
    if arg1 ~= "LeftButton" or editing then
      return
    end
    local x, y = CenterOffset(h)
    local cx, cy = CursorPos()
    this.snapDrag = { dx = x - cx, dy = y - cy, x = x, y = y }
  end)
  handle:SetScript("OnMouseUp", function()
    local d = this.snapDrag
    if arg1 ~= "LeftButton" or not d then
      return
    end
    this.snapDrag = nil
    S:SavePosition(h, math.floor(d.x * 10 + 0.5) / 10, math.floor(d.y * 10 + 0.5) / 10)
  end)
  handle:SetScript("OnUpdate", function()
    local d = this.snapDrag
    if not d then
      return
    end
    local cx, cy = CursorPos()
    local x, y = Clamp(h, cx + d.dx, cy + d.dy)
    h:ClearAllPoints()
    h:SetPoint("CENTER", UIParent, "CENTER", x, y)
    d.x, d.y = x, y
  end)
  -- closed mid-drag (Escape): keep where it got to
  handle:SetScript("OnHide", function()
    local d = this.snapDrag
    if d then
      this.snapDrag = nil
      S:SavePosition(h, math.floor(d.x * 10 + 0.5) / 10, math.floor(d.y * 10 + 0.5) / 10)
    end
  end)
end

-- modules that want to show previews while editing (empty party/raid grids)
function S:OnEdit(fn)
  self.editListeners = self.editListeners or {}
  table.insert(self.editListeners, fn)
end

-- no moving things mid-fight by accident
local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:SetScript("OnEvent", function()
  if editing then
    S:ToggleEdit()
    S.Print("left edit mode because you entered combat")
  end
end)
