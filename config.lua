-- SnapUI settings window (/snap config, or SnapUI in the Esc menu): every element's settings,
-- profiles (switch, copy, reset, delete), the theme,
-- which modules run, nameplates, automation, and tools (edit mode, keybind mode, resets).
-- Theme and module changes need a reload; a "Reload UI to apply" button shows when they do.

local S = SnapUI
local win, pages, tabs = nil, {}, {}
local current
local needsReload = false

local W, H, TAB_W = 640, 460, 118

-- [[ widgets ]] --
local function Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w or 80)
  b:SetHeight(h or 20)
  S.Backdrop(b, 1)
  b:SetBackdropColor(0.16, 0.16, 0.16, 1)
  b.text = S.Text(b, 12, "CENTER")
  b.text:SetPoint("CENTER", 0, 0)
  b.text:SetText(text)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", function() this:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1) end)
  b:SetScript("OnLeave", function() S.ResetBorder(this) end)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

local function MarkReload()
  needsReload = true
  if win and win.reload then win.reload:Show() end
end

-- one row per option spec ({label, get, set, min/max/step | toggle | choices}); `reload`
-- marks the window as needing a reload when a row changes
local function OptionRows(page, list, y, reload)
  for _, o in ipairs(list) do
    local opt = o
    local row = CreateFrame("Frame", nil, page)
    row:SetWidth(W - TAB_W - 40)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
    row.label = S.Text(row, 12, "LEFT")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetText(opt.label)
    local function Changed()
      if reload then MarkReload() end
    end
    if opt.choices then
      local b = Button(row, "", 170, 20)
      b:SetPoint("RIGHT", 0, 0)
      local function Refresh() b.text:SetText(S.ChoiceLabel(opt, opt.get())) end
      b:SetScript("OnClick", function()
        opt.set(S.NextChoice(opt, opt.get(), arg1 == "RightButton" and -1 or 1))
        Refresh()
        Changed()
      end)
      Refresh()
    elseif opt.toggle then
      local b = Button(row, "", 70, 20)
      b:SetPoint("RIGHT", 0, 0)
      local function Refresh() b.text:SetText(opt.get() and "|cff60ff60On|r" or "|cffff6060Off|r") end
      b:SetScript("OnClick", function() opt.set(not opt.get()); Refresh(); Changed() end)
      Refresh()
    else
      local value = S.Text(row, 12, "CENTER")
      value:SetWidth(50)
      local plus = Button(row, "+", 22, 20)
      plus:SetPoint("RIGHT", 0, 0)
      value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
      local minus = Button(row, "-", 22, 20)
      minus:SetPoint("RIGHT", value, "LEFT", -2, 0)
      local function Refresh()
        local v = opt.get() or 0
        value:SetText(math.floor(v) == v and tostring(v) or string.format("%.2f", v))
      end
      local function Step(dir)
        local v = (opt.get() or 0) + dir * opt.step
        v = math.floor(v / opt.step + 0.5) * opt.step
        opt.set(math.max(opt.min, math.min(opt.max, v)))
        Refresh()
        Changed()
      end
      minus:SetScript("OnClick", function() Step(-1) end)
      plus:SetScript("OnClick", function() Step(1) end)
      Refresh()
    end
    y = y - 25
  end
  return y
end

local function Header(page, text, y)
  local t = S.Text(page, 14, "LEFT")
  t:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
  t:SetText("|cff4fc3f7" .. text .. "|r")
  return y - 24
end

local function Note(page, text, y)
  local t = S.Text(page, 11, "LEFT")
  t:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
  t:SetWidth(W - TAB_W - 40)
  t:SetJustifyH("LEFT")
  t:SetTextColor(0.75, 0.75, 0.75)
  t:SetText(text)
  return y - 18
end

-- [[ profiles page ]] --
local PER_PAGE = 10
local function BuildProfiles(page)
  local y = Header(page, "Profiles", -8)
  page.active = S.Text(page, 12, "LEFT")
  page.active:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
  y = y - 22
  page.rows = {}
  page.offset = 0
  for i = 1, PER_PAGE do
    local row = CreateFrame("Frame", nil, page)
    row:SetWidth(W - TAB_W - 30)
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y - (i - 1) * 28)
    S.Backdrop(row, 0.5)
    row.name = S.Text(row, 12, "LEFT")
    row.name:SetPoint("LEFT", 6, 0)
    row.desc = S.Text(row, 10, "LEFT")
    row.desc:SetPoint("LEFT", row, "LEFT", 150, 0)
    row.desc:SetWidth(170)
    row.desc:SetTextColor(0.7, 0.7, 0.7)
    row.delete = Button(row, "Delete", 50, 20)
    row.delete:SetPoint("RIGHT", -3, 0)
    row.reset = Button(row, "Reset", 46, 20)
    row.reset:SetPoint("RIGHT", row.delete, "LEFT", -3, 0)
    row.use = Button(row, "Use", 40, 20)
    row.use:SetPoint("RIGHT", row.reset, "LEFT", -3, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function()
      if not this.profile then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(this.profile)
      local p = S.PresetFor and S:PresetFor(this.profile)
      if p then GameTooltip:AddLine(p.desc, 0.85, 0.85, 0.85, 1) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.rows[i] = row
  end
  local by = y - PER_PAGE * 28 - 4
  page.prev = Button(page, "<", 26, 20, function() page.offset = math.max(0, page.offset - PER_PAGE); page:Refresh() end)
  page.prev:SetPoint("TOPLEFT", page, "TOPLEFT", 10, by)
  page.pageText = S.Text(page, 12, "CENTER")
  page.pageText:SetPoint("LEFT", page.prev, "RIGHT", 6, 0)
  page.next = Button(page, ">", 26, 20, function()
    if page.offset + PER_PAGE < table.getn(S:ProfileNames()) then page.offset = page.offset + PER_PAGE end
    page:Refresh()
  end)
  page.next:SetPoint("LEFT", page.pageText, "RIGHT", 6, 0)

  -- copy the current profile to a new name
  local box = CreateFrame("EditBox", nil, page)
  box:SetWidth(150)
  box:SetHeight(20)
  box:SetAutoFocus(false)
  box:SetFontObject(GameFontHighlightSmall)
  if box.SetFont then box:SetFont(S.FONT, 12, "") end
  box:SetTextInsets(4, 4, 0, 0)
  box:SetMaxLetters(32)
  S.Backdrop(box, 1)
  box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -80, by)
  box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  page.box = box
  local copyLabel = S.Text(page, 12, "RIGHT")
  copyLabel:SetPoint("RIGHT", box, "LEFT", -6, 0)
  copyLabel:SetText("Copy current to:")
  local copy = Button(page, "Copy", 60, 20, function()
    local name = strtrim and strtrim(box:GetText() or "") or (box:GetText() or "")
    if name == "" then return end
    S:CopyProfile(name)
    box:SetText("")
    box:ClearFocus()
    S.Print("copied |cff4fc3f7" .. S.root.profile .. "|r to |cff4fc3f7" .. name .. "|r")
    page:Refresh()
  end)
  copy:SetPoint("LEFT", box, "RIGHT", 6, 0)
  box:SetScript("OnEnterPressed", function() copy:Click() end)

  function page:Refresh()
    local names = S:ProfileNames()
    self.active:SetText("Using: |cff4fc3f7" .. S.root.profile .. "|r   (switching reloads the UI)")
    local pagesN = math.max(1, math.ceil(table.getn(names) / PER_PAGE))
    self.pageText:SetText((math.floor(self.offset / PER_PAGE) + 1) .. " / " .. pagesN)
    for i, row in ipairs(self.rows) do
      local name = names[self.offset + i]
      row.profile = name
      if name then
        local preset = S.PresetFor and S:PresetFor(name)
        row.name:SetText(name == S.root.profile and ("|cff4fc3f7" .. name .. "|r") or name)
        row.desc:SetText(preset and preset.short or "")
        row.use:SetScript("OnClick", function() if name ~= S.root.profile then S:SetProfile(name) end end)
        row.reset:SetScript("OnClick", function()
          if S.ResetPreset and S:ResetPreset(name) then
            if name == S.root.profile then ReloadUI() else S.Print(name .. " reset to its preset") end
          end
        end)
        row.delete:SetScript("OnClick", function()
          if name == S.root.profile then
            S.Print("can't delete the profile you're using")
          else
            S:DeleteProfile(name)
            self:Refresh()
          end
        end)
        if preset then row.reset:Show() else row.reset:Hide() end
        if name == S.root.profile then row.delete:Hide() else row.delete:Show() end
        row:Show()
      else
        row:Hide()
      end
    end
  end
end

-- [[ theme page ]] --
local function ChoicesFrom(list)
  local c = {}
  for _, m in ipairs(list) do table.insert(c, { m[1], m[2] }) end
  return c
end

S.ACCENTS = {
  { "blue", "Sky blue", { 0.31, 0.76, 0.97 } }, { "elvui", "ElvUI blue", { 0.09, 0.52, 0.82 } },
  { "gold", "Gold", { 1, 0.78, 0.2 } }, { "red", "Red", { 0.85, 0.2, 0.2 } }, { "green", "Green", { 0.3, 0.85, 0.4 } },
  { "purple", "Purple", { 0.6, 0.4, 0.95 } }, { "teal", "Teal", { 0.2, 0.8, 0.7 } }, { "orange", "Orange", { 1, 0.5, 0.15 } },
  { "white", "White", { 0.9, 0.9, 0.9 } }, { "class", "Class colour" },
}

local function BuildTheme(page)
  local t = S.theme
  local function Opt(label, key, min, max, step)
    return { label = label, get = function() return t[key] end, set = function(v) t[key] = v end, min = min, max = max, step = step }
  end
  local function Toggle(label, key)
    return { label = label, toggle = true, get = function() return t[key] end, set = function(v) t[key] = v end }
  end
  local function Choice(label, key, choices)
    return { label = label, choices = choices, get = function() return t[key] end, set = function(v) t[key] = v end }
  end
  local accentChoices = {}
  for _, a in ipairs(S.ACCENTS) do table.insert(accentChoices, { a[1], a[2] }) end
  local accent = { label = "Accent colour", choices = accentChoices,
    get = function()
      if t.accentClass then return "class" end
      for _, a in ipairs(S.ACCENTS) do
        if a[3] and math.abs(a[3][1] - t.accent[1]) < 0.01 and math.abs(a[3][2] - t.accent[2]) < 0.01 then return a[1] end
      end
      return "blue"
    end,
    set = function(v)
      for _, a in ipairs(S.ACCENTS) do
        if a[1] == v then
          t.accentClass = v == "class"
          if a[3] then t.accent = { a[3][1], a[3][2], a[3][3] } end
        end
      end
    end }
  local y = Header(page, "Theme", -8)
  y = Note(page, "Changes apply after a reload. Each profile has its own theme.", y)
  OptionRows(page, {
    Choice("Font", "font", ChoicesFrom(S.FONTS)),
    Opt("Font size", "fontScale", 0.6, 1.6, 0.05),
    Choice("Font outline", "outline", { { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" }, { "", "Shadow only" } }),
    Choice("Bar texture", "bar", ChoicesFrom(S.BARS)),
    Choice("Border", "borderStyle", { { "pixel", "1px pixel" }, { "thick", "Thick (Tukui)" }, { "none", "None" } }),
    Toggle("Drop shadows", "shadow"),
    Toggle("Accent strips (BenikUI)", "strip"),
    Opt("Panel opacity", "bgAlpha", 0, 1.2, 0.05),
    Choice("Health colours", "health", { { "class", "Class / reaction" }, { "dark", "Dark (ElvUI)" }, { "gradient", "Red to green" },
      { "blizzard", "Blizzard green" }, { "custom", "Single colour" } }),
    Toggle("Class colour behind dark bars", "classBackdrop"),
    Toggle("Class-coloured names", "nameClass"),
    Toggle("Bar shading", "shade"),
    accent,
  }, y, true)
end

-- [[ modules page ]] --
local function BuildModules(page)
  local y = Header(page, "Modules", -8)
  y = Note(page, "Turn whole parts of SnapUI off; Blizzard's own frames come back for those. Needs a reload.", y)
  local list = {}
  for _, m in ipairs(S.modules) do
    local mod = m
    if not mod.required and mod.label then
      table.insert(list, { label = mod.label, toggle = true,
        get = function() return S:ModuleEnabled(mod.name) end,
        set = function(v) S.db.modules[mod.name] = v and true or false end })
    end
  end
  OptionRows(page, list, y, true)
end

local function BuildList(page, title, note, list)
  local y = Header(page, title, -8)
  if note then y = Note(page, note, y) end
  OptionRows(page, list or {}, y, false)
end

-- [[ elements page ]] --
-- every element edit mode can move (bars, frames, tooltip, minimap...) in a list, with that
-- element's own options beside it: the same options as its right-click panel in edit mode.
-- Where things sit is still done by dragging in edit mode.
local LIST_W, ROW_H, OPT_H = 160, 20, 25

-- the list is a tree, ElvUI style: elements grouped under headers you can fold, and a
-- search box that keeps only elements whose name or settings match
local CATEGORIES = {
  { "Unit frames", { "player", "target", "targettarget", "petframe", "targetlevel", "power", "combo" } },
  { "Cast bars", { "cast", "targetcast", "mirror" } },
  { "Auras", { "buffs", "debuffs", "playerbuffs", "targetbuffs", "targetdebuffs" } },
  { "Group frames", { "party", "pets", "raid", "raid25", "raid10", "tanks" } },
  { "Action bars", { "bar1", "bar2", "bar3", "bar4", "bar5", "pet", "stance", "micro", "bags", "xp" } },
  { "Bags and bank", { "bagwindow", "bankwindow", "lootroll" } },
  { "Chat and info", { "chat", "chatinput", "tooltip", "info1", "info2", "info3", "meter", "meter2" } },
  { "Map and quests", { "minimap", "questwatch", "durability" } },
  { "Panels", { "panel1", "panel2", "panel3", "panel4" } },
}
local CATEGORY_OF = {}
for _, c in ipairs(CATEGORIES) do
  for _, name in ipairs(c[2]) do CATEGORY_OF[name] = c[1] end
end

-- does this element's name, or any of its settings, contain the search text?
local function HolderMatches(h, q)
  if not q then return true end
  if string.find(string.lower(h.label or ""), q, 1, true) then return true end
  for _, o in ipairs(h.options or {}) do
    if o.label and string.find(string.lower(o.label), q, 1, true) then return true end
  end
  return false
end

local function FormatNumber(v)
  if math.floor(v) == v then return tostring(v) end
  return string.format("%.2f", v)
end

local function OptionRow(parent, width)
  local row = CreateFrame("Frame", nil, parent)
  row:SetWidth(width)
  row:SetHeight(22)
  row.label = S.Text(row, 12, "LEFT")
  row.label:SetPoint("LEFT", 0, 0)
  row.plus = Button(row, "+", 22, 20)
  row.plus:SetPoint("RIGHT", 0, 0)
  -- the number is a text box: click, type, Enter (Esc or clicking away puts it back)
  local v = CreateFrame("EditBox", nil, row)
  v:SetWidth(54)
  v:SetHeight(20)
  v:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
  v:SetAutoFocus(false)
  v:SetFontObject(GameFontHighlightSmall)
  if v.SetFont then v:SetFont(S.FONT, 12, "") end
  v:SetJustifyH("CENTER")
  v:SetTextInsets(2, 2, 0, 0)
  v:SetMaxLetters(8)
  S.Backdrop(v, 1)
  v:SetBackdropColor(0.08, 0.08, 0.08, 1)
  v:SetScript("OnEditFocusGained", function()
    this:SetBackdropBorderColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
    this:HighlightText()
  end)
  v:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  row.value = v
  row.minus = Button(row, "-", 22, 20)
  row.minus:SetPoint("RIGHT", v, "LEFT", -2, 0)
  row.toggle = Button(row, "", 70, 20)
  row.toggle:SetPoint("RIGHT", 0, 0)
  row.choice = Button(row, "", 170, 20)
  row.choice:SetPoint("RIGHT", 0, 0)
  return row
end

-- point a pooled row at one option of holder h
local function BindRow(row, opt, h)
  row.label:SetText(opt.label)
  for _, part in ipairs({ row.plus, row.value, row.minus, row.toggle, row.choice }) do
    part:Hide()
  end
  local function Changed()
    if S.RefreshOverlay then S.RefreshOverlay(h) end
  end
  if opt.choices then
    local function Refresh() row.choice.text:SetText(S.ChoiceLabel(opt, opt.get())) end
    row.choice:SetScript("OnClick", function()
      opt.set(S.NextChoice(opt, opt.get(), arg1 == "RightButton" and -1 or 1))
      Refresh()
      Changed()
    end)
    Refresh()
    row.choice:Show()
  elseif opt.toggle then
    local function Refresh() row.toggle.text:SetText(opt.get() and "|cff60ff60On|r" or "|cffff6060Off|r") end
    row.toggle:SetScript("OnClick", function() opt.set(not opt.get()); Refresh(); Changed() end)
    Refresh()
    row.toggle:Show()
  else
    local function Refresh()
      row.value:SetText((opt.format or FormatNumber)(opt.get() or 0))
    end
    local function Set(v)
      opt.set(math.max(opt.min, math.min(opt.max, v)))
      Refresh()
      Changed()
    end
    local function Step(dir)
      local v = (opt.get() or 0) + dir * opt.step
      Set(math.floor(v / opt.step + 0.5) * opt.step)
    end
    row.minus:SetScript("OnClick", function() Step(-1) end)
    row.plus:SetScript("OnClick", function() Step(1) end)
    -- typed values aren't snapped to the step, only kept in range
    row.value:SetScript("OnEnterPressed", function()
      local v = tonumber((string.gsub(this:GetText() or "", "[^%d%.%-]", "")))
      if v then Set(math.floor(v * 100 + 0.5) / 100) end
      this:ClearFocus()
    end)
    row.value:SetScript("OnEditFocusLost", function()
      this:SetBackdropBorderColor(0, 0, 0, 1)
      this:HighlightText(0, 0)
      Refresh()
    end)
    Refresh()
    row.minus:Show()
    row.value:Show()
    row.plus:Show()
  end
  row:Show()
end

local function BuildElements(page)
  local y = Header(page, "Elements", -8)
  y = Note(page, "Every part of the UI and its settings. To move things, use edit mode (/snap).", y)
  local pageW, pageH = W - TAB_W - 8, H - 44

  -- search over the list
  local search = CreateFrame("EditBox", "SnapUIConfigSearch", page)
  search:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y - 2)
  search:SetWidth(LIST_W)
  search:SetHeight(18)
  search:SetAutoFocus(false)
  search:SetFontObject(GameFontHighlightSmall)
  search:SetTextInsets(4, 4, 0, 0)
  S.Backdrop(search, 0.6)
  search.hint = S.Text(search, 11, "LEFT")
  search.hint:SetPoint("LEFT", 4, 0)
  search.hint:SetTextColor(0.5, 0.5, 0.5)
  search.hint:SetText("Search settings")
  search:SetScript("OnTextChanged", function()
    local t = string.lower(string.gsub(this:GetText() or "", "^%s*(.-)%s*$", "%1"))
    page.query = t ~= "" and t or nil
    if page.query then this.hint:Hide() else this.hint:Show() end
    page.offset = 0
    page:Rebuild()
  end)
  search:SetScript("OnEscapePressed", function() this:SetText(""); this:ClearFocus() end)
  search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  page.search = search

  -- the list on the left, scrolled with the mouse wheel
  local list = CreateFrame("Frame", nil, page)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y - 24)
  list:SetWidth(LIST_W)
  list:SetHeight(pageH + y - 30)
  S.Backdrop(list, 0.5)
  list:EnableMouseWheel(true)
  local visible = math.floor((list:GetHeight() - 8) / ROW_H)
  page.items, page.listRows, page.offset, page.folded = {}, {}, 0, {}
  for i = 1, visible do
    local b = CreateFrame("Button", nil, list)
    b:SetWidth(LIST_W - 8)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    b.text = S.Text(b, 12, "LEFT")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetWidth(LIST_W - 16)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints(b)
    b.hl:SetTexture(S.TEX)
    b.hl:SetVertexColor(0, 0, 0, 0)
    b:SetScript("OnClick", function()
      if this.cat then
        page.folded[this.cat] = not page.folded[this.cat]
        page:Rebuild()
      elseif this.holder then
        page:Pick(this.holder)
      end
    end)
    b:SetScript("OnEnter", function() if this.holder ~= page.holder then this.hl:SetVertexColor(1, 1, 1, 0.08) end end)
    b:SetScript("OnLeave", function() if this.holder ~= page.holder then this.hl:SetVertexColor(0, 0, 0, 0) end end)
    page.listRows[i] = b
  end
  list:SetScript("OnMouseWheel", function()
    local most = math.max(0, table.getn(page.items) - visible)
    page.offset = math.max(0, math.min(most, page.offset - arg1 * 3))
    page:RefreshList()
  end)

  -- the chosen element's settings on the right
  local dx = 6 + LIST_W + 12
  local dw = pageW - dx - 8
  local detail = CreateFrame("Frame", nil, page)
  detail:SetPoint("TOPLEFT", page, "TOPLEFT", dx, y - 2)
  detail:SetWidth(dw)
  detail:SetHeight(list:GetHeight())
  detail:EnableMouseWheel(true)
  page.detail = detail
  detail.title = S.Text(detail, 14, "LEFT")
  detail.title:SetPoint("TOPLEFT", 0, -2)
  detail.title:SetWidth(dw - 110)
  detail.reset = Button(detail, "Reset position", 104, 20, function()
    local h = page.holder
    if h then
      S.db.pos[h.name] = nil
      S:Place(h)
      S.Print(h.label .. " moved back to its default spot")
    end
  end)
  detail.reset:SetPoint("TOPRIGHT", 0, 0)
  detail.empty = S.Text(detail, 12, "LEFT")
  detail.empty:SetPoint("TOPLEFT", 0, -34)
  detail.empty:SetTextColor(0.7, 0.7, 0.7)
  local optRows = math.floor((detail:GetHeight() - 32) / OPT_H)
  detail.rows, detail.offset = {}, 0
  for i = 1, optRows do
    local row = OptionRow(detail, dw)
    row:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -30 - (i - 1) * OPT_H)
    row:Hide()
    detail.rows[i] = row
  end
  detail.more = S.Text(detail, 11, "RIGHT")
  detail.more:SetPoint("BOTTOMRIGHT", 0, 0)
  detail.more:SetTextColor(0.6, 0.6, 0.6)
  detail:SetScript("OnMouseWheel", function()
    local h = page.holder
    if not h or not h.options then return end
    local most = math.max(0, table.getn(h.options) - optRows)
    detail.offset = math.max(0, math.min(most, detail.offset - arg1 * 2))
    page:RefreshDetail()
  end)

  function page:RefreshList()
    for i, b in ipairs(self.listRows) do
      local item = self.items[self.offset + i]
      local h = item and item.holder
      b.holder, b.cat = h, item and item.cat
      if item and item.cat then
        -- a category header: fold/unfold
        local open = self.query or not self.folded[item.cat]
        b.text:SetText("|cff4fc3f7" .. (open and "- " or "+ ") .. item.cat .. "|r  |cff888888" .. item.n .. "|r")
        b.text:SetPoint("LEFT", 4, 0)
        b.hl:SetVertexColor(1, 1, 1, 0.04)
        b:Show()
      elseif h then
        local off = h.isOff and h.isOff()
        b.text:SetText(h.label .. (off and "  |cff888888(off)|r" or ""))
        b.text:SetPoint("LEFT", 14, 0)
        if h == self.holder then
          b.hl:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.35)
        else
          b.hl:SetVertexColor(0, 0, 0, 0)
        end
        b:Show()
      else
        b:Hide()
      end
    end
  end

  function page:RefreshDetail()
    local h = self.holder
    for _, row in ipairs(detail.rows) do row:Hide() end
    detail.more:SetText("")
    if not h then
      detail.title:SetText("")
      detail.reset:Hide()
      detail.empty:SetText("Pick something from the list.")
      return
    end
    detail.title:SetText("|cff4fc3f7" .. h.label .. "|r")
    detail.reset:Show()
    local opts = h.options or {}
    local n = table.getn(opts)
    detail.empty:SetText(n == 0 and "Nothing to set here; it can only be moved (edit mode)." or "")
    for i, row in ipairs(detail.rows) do
      local opt = opts[detail.offset + i]
      if opt then BindRow(row, opt, h) end
    end
    local shown = table.getn(detail.rows)
    if n > shown then
      detail.more:SetText(string.format("%d-%d of %d  (scroll for more)", detail.offset + 1, math.min(n, detail.offset + shown), n))
    end
  end

  function page:Pick(h)
    self.holder = h
    detail.offset = 0
    self:RefreshList()
    self:RefreshDetail()
  end

  -- the tree: each category's elements (alphabetical), folded ones as just their header;
  -- while searching, only matching elements under open headers
  function page:Rebuild()
    local groups, order = {}, {}
    for _, c in ipairs(CATEGORIES) do
      groups[c[1]] = {}
      table.insert(order, c[1])
    end
    groups["Other"] = {}
    table.insert(order, "Other")
    for _, h in ipairs(S.holders) do
      if HolderMatches(h, self.query) then
        table.insert(groups[CATEGORY_OF[h.name] or "Other"], h)
      end
    end
    self.items = {}
    for _, cat in ipairs(order) do
      local list = groups[cat]
      if table.getn(list) > 0 then
        table.sort(list, function(a, b) return string.lower(a.label or "") < string.lower(b.label or "") end)
        table.insert(self.items, { cat = cat, n = table.getn(list) })
        if self.query or not self.folded[cat] then
          for _, h in ipairs(list) do
            table.insert(self.items, { holder = h })
          end
        end
      end
    end
    local most = math.max(0, table.getn(self.items) - table.getn(self.listRows))
    self.offset = math.min(self.offset, most)
    self:RefreshList()
  end

  -- holders are made as modules start, so gather them each time the page opens
  function page:Refresh()
    self:Rebuild()
    if not self.holder then
      for _, item in ipairs(self.items) do
        if item.holder then self.holder = item.holder break end
      end
    end
    self:RefreshList()
    self:RefreshDetail()
  end
end

-- [[ tools page ]] --
local function BuildTools(page)
  local y = Header(page, "Tools", -8)
  local function Tool(text, desc, fn)
    local b = Button(page, text, 150, 22, fn)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
    local d = S.Text(page, 11, "LEFT")
    d:SetPoint("LEFT", b, "RIGHT", 10, 0)
    d:SetTextColor(0.75, 0.75, 0.75)
    d:SetText(desc)
    y = y - 28
  end
  Tool("Edit mode", "Move and resize everything on a snapping grid (/snap).", function() win:Hide(); S:ToggleEdit() end)
  Tool("Keybind mode", "Hover a button and press a key to bind it (/snap kb).", function() win:Hide(); if S.ToggleKeybind then S:ToggleKeybind() end end)
  Tool("Reset positions", "Put every element of this profile back to its default spot.", function() S:ResetPositions() end)
  Tool("Damage meter", "Show or hide the meter windows (/meter).", function() if SlashCmdList.SNAPMETER then SlashCmdList.SNAPMETER("") end end)
  Tool("Reload UI", "Apply theme and module changes.", function() ReloadUI() end)
end

-- [[ window ]] --
local function Select(name)
  current = name
  for n, p in pairs(pages) do
    if n == name then p:Show() else p:Hide() end
  end
  for n, t in pairs(tabs) do
    if n == name then t:SetBackdropColor(S.ACCENT[1] * 0.4, S.ACCENT[2] * 0.4, S.ACCENT[3] * 0.4, 1) else t:SetBackdropColor(0.16, 0.16, 0.16, 1) end
  end
  if pages[name] and pages[name].Refresh then pages[name]:Refresh() end
end

local function Build()
  win = CreateFrame("Frame", "SnapUIConfig", UIParent)
  win:SetWidth(W)
  win:SetHeight(H)
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  win:SetFrameStrata("FULLSCREEN_DIALOG") -- above edit mode's boxes
  win:EnableMouse(true)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function() this:StartMoving() end)
  win:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  S.Panel(win, 0.95)
  table.insert(UISpecialFrames, "SnapUIConfig")

  local title = S.Text(win, 16, "LEFT")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cff4fc3f7Snap|rUI")
  local close = Button(win, "x", 22, 20, function() win:Hide() end)
  close:SetPoint("TOPRIGHT", -8, -8)
  win.reload = Button(win, "Reload UI to apply", 150, 20, function() ReloadUI() end)
  win.reload:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, 0)
  win.reload.text:SetTextColor(1, 0.8, 0.3)
  if not needsReload then win.reload:Hide() end

  local list = {
    { "profiles", "Profiles", BuildProfiles },
    { "elements", "Elements", BuildElements },
    { "theme", "Theme", BuildTheme },
    { "modules", "Modules", BuildModules },
    { "nameplates", "Nameplates", function(p) BuildList(p, "Nameplates", "Applies to new plates straight away; a reload restyles every plate.", S.NameplateOptions and S:NameplateOptions()) end },
    { "automation", "Automation", function(p) BuildList(p, "Automation", nil, S.AutomationOptions and S:AutomationOptions()) end },
    { "tools", "Tools", BuildTools },
  }
  for i, def in ipairs(list) do
    local key = def[1]
    local tab = Button(win, def[2], TAB_W - 16, 24, function() Select(key) end)
    tab:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -40 - (i - 1) * 28)
    tabs[key] = tab
    local page = CreateFrame("Frame", nil, win)
    page:SetPoint("TOPLEFT", win, "TOPLEFT", TAB_W, -36)
    page:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 8)
    def[3](page)
    page:Hide()
    pages[key] = page
  end
  Select("profiles")
end

function S:ToggleConfig(page)
  if not win then
    Build()
  end
  if win:IsShown() and not page then
    win:Hide()
  else
    win:Show()
    Select(page or current or "profiles")
  end
end

-- lets the harness reach every page
S.HarnessExtra = S.HarnessExtra or {}
S.HarnessExtra.config = function()
  for _, p in ipairs({ "profiles", "elements", "theme", "modules", "nameplates", "automation", "tools" }) do
    S:ToggleConfig(p)
  end
  S:ToggleConfig()
end
S.HarnessExtra.pages = function() return pages end

-- a "SnapUI" button in the Esc menu, under Macros (OctoWoW: Shop, Interface, Key Bindings,
-- Macros, then Logout after a gap) opens this window
if GameMenuFrame and GameMenuButtonMacros and GameMenuButtonLogout then
  local b = CreateFrame("Button", "GameMenuButtonSnapUI", GameMenuFrame, "GameMenuButtonTemplate")
  b:SetPoint("TOP", GameMenuButtonMacros, "BOTTOM", 0, -1)
  b:SetText("|cff4fc3f7Snap|rUI")
  b:SetScript("OnClick", function()
    HideUIPanel(GameMenuFrame)
    S:ToggleConfig(current or "elements")
  end)
  GameMenuButtonLogout:ClearAllPoints()
  GameMenuButtonLogout:SetPoint("TOP", b, "BOTTOM", 0, -16)
  GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + 22)
end
