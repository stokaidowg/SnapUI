-- SnapUI bags: one window for the backpack and the four bag slots, styled like the rest of
-- the UI. Items use Blizzard's ContainerFrameItemButtonTemplate, which reads the bag from
-- the button's parent ID and the slot from its own ID, so clicking, dragging, splitting,
-- selling and tooltips all behave exactly like the default bags. The bank and keyring keep
-- Blizzard's windows.

local S = SnapUI

local BAGS = { 0, 1, 2, 3, 4 }
local HEADER, FOOTER, PAD = 22, 20, 6

local main, holder, s
local bagFrames, buttons = {}, {}
local orig = {}
local installed = false

local function Money(copper)
  local g = math.floor(copper / 10000)
  local sv = math.floor(math.mod(copper, 10000) / 100)
  local c = math.mod(copper, 100)
  local text = ""
  if g > 0 then text = text .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or sv > 0 then text = text .. "|cffc7c7cf" .. sv .. "s|r " end
  return text .. "|cffeda55f" .. c .. "c|r"
end

local function QualityColor(link)
  local _, _, hex = string.find(link or "", "|c%x%x(%x%x%x%x%x%x)")
  if not hex or hex == "ffffff" or hex == "9d9d9d" then
    return nil
  end
  return tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255
end

-- [[ item buttons ]] --
local function GetButton(bag, slot)
  buttons[bag] = buttons[bag] or {}
  local b = buttons[bag][slot]
  if b then
    return b
  end
  local name = "SnapUIBag" .. bag .. "Item" .. slot
  b = CreateFrame("Button", name, bagFrames[bag], "ContainerFrameItemButtonTemplate")
  b:SetID(slot)
  getglobal(name .. "NormalTexture"):SetTexture(nil)
  local icon = getglobal(name .. "IconTexture")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", -1, 1)
  local count = getglobal(name .. "Count")
  count:SetFont(S.FONT, 12, "OUTLINE")
  count:ClearAllPoints()
  count:SetPoint("BOTTOMRIGHT", -2, 2)

  b.bg = CreateFrame("Frame", nil, b)
  b.bg:SetAllPoints(b)
  b.bg:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
  S.Backdrop(b.bg, 0.6)
  -- green arrow in the top-left corner on items that are upgrades (see upgrades.lua)
  b.up = b:CreateTexture(nil, "OVERLAY")
  b.up:SetTexture("Interface\\AddOns\\SnapUI\\media\\upgrade")
  b.up:SetWidth(14)
  b.up:SetHeight(14)
  b.up:SetPoint("TOPLEFT", 1, -1)
  b.up:Hide()
  buttons[bag][slot] = b
  return b
end

-- [[ search and hover dimming ]] --
-- The title bar's search box dims every item whose name doesn't contain what you type;
-- hovering a bag in the bag slots row dims the other bags. Both use the item's alpha.
local query, hoverBag

local function Matches(bag, slot)
  if not query then
    return true
  end
  local _, _, name = string.find(GetContainerItemLink(bag, slot) or "", "%[(.-)%]")
  return name ~= nil and string.find(string.lower(name), query, 1, true) ~= nil
end

local function Dim(b, bag, slot)
  local on = (hoverBag == nil or bag == hoverBag) and Matches(bag, slot)
  b:SetAlpha(on and 1 or 0.25)
end

local function UpdateButton(bag, slot)
  local b = buttons[bag] and buttons[bag][slot]
  if not b then
    return
  end
  Dim(b, bag, slot)
  local texture, count, locked = GetContainerItemInfo(bag, slot)
  SetItemButtonTexture(b, texture)
  SetItemButtonCount(b, count)
  SetItemButtonDesaturated(b, locked, 0.5, 0.5, 0.5)
  if texture then
    ContainerFrame_UpdateCooldown(bag, b)
    b.hasItem = 1
  else
    getglobal(b:GetName() .. "Cooldown"):Hide()
    b.hasItem = nil
  end
  if texture and s.arrows and S.BagUpgrade and S:BagUpgrade(bag, slot) then
    b.up:Show()
  else
    b.up:Hide()
  end
  local r, g, bl = QualityColor(GetContainerItemLink(bag, slot))
  if r then
    b.bg:SetBackdropBorderColor(r, g, bl, 1)
  else
    S.ResetBorder(b.bg)
  end
end

-- [[ bag slots ]] --
-- the backpack and the four bags as a row of icons under the title bar, shown with the bag
-- button next to Sort: drop a bag on one to equip it, drag one off to swap it, hover one to
-- light up its slots in the window. The number on each is its free slots.
local SLOT_SIZE = 24
local SLOT_ROW = SLOT_SIZE + 6
local slotButtons = {}

local function Top()
  return HEADER + (s.bagSlots and SLOT_ROW or 0)
end

local function InvSlot(bag)
  return ContainerIDToInventoryID(bag)
end

-- dim every item slot that isn't in this bag (nil: all back to normal), keeping the search
local function Highlight(bag)
  hoverBag = bag
  for b, list in pairs(buttons) do
    for slot, btn in pairs(list) do
      Dim(btn, b, slot)
    end
  end
end

local function UpdateSlots()
  for i, bag in ipairs(BAGS) do
    local b = slotButtons[bag]
    if s.bagSlots then
      local tex, free = nil, 0
      local n = GetContainerNumSlots(bag) or 0
      for slot = 1, n do
        if not GetContainerItemInfo(bag, slot) then free = free + 1 end
      end
      if bag == 0 then
        tex = "Interface\\Buttons\\Button-Backpack-Up"
      else
        tex = GetInventoryItemTexture("player", InvSlot(bag))
      end
      b.icon:SetTexture(tex)
      b.count:SetText(n > 0 and free or "")
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + (i - 1) * (SLOT_SIZE + 3), -HEADER - 2)
      b:Show()
    else
      b:Hide()
    end
  end
  local key = slotButtons.key
  if key then
    if s.bagSlots then
      key:ClearAllPoints()
      key:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + table.getn(BAGS) * (SLOT_SIZE + 3) + 6, -HEADER - 2)
      key:Show()
    else
      key:Hide()
    end
  end
  if main.slotsBtn then
    local a = s.bagSlots and S.ACCENT or { 1, 1, 1 }
    main.slotsBtn.icon:SetVertexColor(a[1], a[2], a[3])
  end
end

local function PutOrPick(bag)
  if bag == 0 then
    if CursorHasItem() then PutItemInBackpack() end
  elseif CursorHasItem() then
    PutItemInBag(InvSlot(bag))
  else
    PickupBagFromSlot(InvSlot(bag))
  end
end

local function CreateSlot(bag)
  local b = CreateFrame("Button", "SnapUIBagSlot" .. bag, main)
  b:SetWidth(SLOT_SIZE)
  b:SetHeight(SLOT_SIZE)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.bg = CreateFrame("Frame", nil, b)
  b.bg:SetAllPoints(b)
  b.bg:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
  S.Backdrop(b.bg, 0.6)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.count = S.Text(b, 10, "RIGHT")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(1, 1, 1, 0.2)
  hl:SetAllPoints(b)
  b:SetScript("OnClick", function() PutOrPick(bag) end)
  b:SetScript("OnReceiveDrag", function() PutOrPick(bag) end)
  b:SetScript("OnDragStart", function()
    if bag > 0 then PickupBagFromSlot(InvSlot(bag)) end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    if bag == 0 then
      GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack")
    elseif not GameTooltip:SetInventoryItem("player", InvSlot(bag)) then
      GameTooltip:SetText(EQUIP_CONTAINER or "Equip Container")
    end
    GameTooltip:Show()
    Highlight(bag)
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
    Highlight(nil)
  end)
  b:Hide()
  slotButtons[bag] = b
end

-- the keyring keeps Blizzard's window; this just opens and closes it
local function CreateKeySlot()
  if not ToggleKeyRing then
    return
  end
  local b = CreateFrame("Button", "SnapUIBagSlotKey", main)
  b:SetWidth(SLOT_SIZE)
  b:SetHeight(SLOT_SIZE)
  b.bg = CreateFrame("Frame", nil, b)
  b.bg:SetAllPoints(b)
  b.bg:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
  S.Backdrop(b.bg, 0.6)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture("Interface\\Icons\\INV_Misc_Key_04")
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(1, 1, 1, 0.2)
  hl:SetAllPoints(b)
  b:SetScript("OnClick", function() ToggleKeyRing() end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(KEYRING or "Keyring")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  slotButtons.key = b
end

-- [[ window ]] --
local function Layout()
  local size, sp, cols = s.size, 3, s.columns
  local i, free, total = 0, 0, 0
  for _, bag in ipairs(BAGS) do
    local n = GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local b = GetButton(bag, slot)
      b:SetWidth(size)
      b:SetHeight(size)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + math.mod(i, cols) * (size + sp), -Top() - math.floor(i / cols) * (size + sp))
      b:Show()
      UpdateButton(bag, slot)
      if not GetContainerItemInfo(bag, slot) then
        free = free + 1
      end
      i = i + 1
    end
    total = total + n
    -- a smaller bag was swapped in: hide the slots it no longer has
    for slot = n + 1, table.getn(buttons[bag] or {}) do
      buttons[bag][slot]:Hide()
    end
  end

  local rows = math.max(1, math.ceil(i / cols))
  main:SetWidth(PAD * 2 + cols * size + (cols - 1) * sp)
  main:SetHeight(Top() + rows * size + (rows - 1) * sp + FOOTER + 2)
  main:SetScale(s.scale)
  main.free:SetText((total - free) .. "/" .. total)
  main.money:SetText(Money(GetMoney()))
  UpdateSlots()
  S:Fit(holder, main)
end

local function Open()
  if not main:IsShown() then
    main:Show()
    Layout()
  end
end

local function Close()
  main:Hide()
end

local function Toggle()
  if main:IsShown() then Close() else Open() end
end

local function Mine(id)
  return id and id >= 0 and id <= 4
end

-- [[ taking over the bag functions ]] --
local NAMES = { "ToggleBag", "OpenBag", "CloseBag", "ToggleBackpack", "OpenBackpack", "CloseBackpack", "OpenAllBags", "IsBagOpen" }

local function Install()
  if installed then
    return
  end
  installed = true
  for _, n in ipairs(NAMES) do
    orig[n] = getglobal(n)
  end
  ToggleBag = function(id) if Mine(id) then Toggle() else orig.ToggleBag(id) end end
  OpenBag = function(id) if Mine(id) then Open() else orig.OpenBag(id) end end
  CloseBag = function(id) if Mine(id) then Close() else orig.CloseBag(id) end end
  ToggleBackpack = Toggle
  OpenBackpack = Open
  CloseBackpack = Close
  OpenAllBags = function(forceOpen)
    if main:IsShown() and not forceOpen then
      Close()
    else
      Open()
    end
    if BankFrame and BankFrame:IsVisible() and not (S.BankWindowShown and S:BankWindowShown()) then
      for id = 5, 10 do orig.OpenBag(id) end
    end
  end
  IsBagOpen = function(id)
    if Mine(id) then
      return main:IsShown() and id or nil
    end
    return orig.IsBagOpen(id)
  end
  -- any default bag windows already open go away
  for i = 1, NUM_CONTAINER_FRAMES or 0 do
    local f = getglobal("ContainerFrame" .. i)
    if f and f:IsShown() and Mine(f:GetID()) then
      f:Hide()
    end
  end
end

local function Uninstall()
  if not installed then
    return
  end
  installed = false
  for _, n in ipairs(NAMES) do
    setglobal(n, orig[n])
  end
  Close()
end

local function CreateWindow()
  main = CreateFrame("Frame", "SnapUI_Bags", holder)
  main:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  main:SetFrameStrata("HIGH")
  main:SetClampedToScreen(false)
  -- drag the window by its background or title bar to move it (no need for /snap)
  S:MakeDraggable(main, holder)
  S.Backdrop(main, 0.92)
  main:Hide()
  -- Escape closes it like any other window
  table.insert(UISpecialFrames, "SnapUI_Bags")

  main.title = S.Text(main, 13, "LEFT")
  main.title:SetPoint("TOPLEFT", PAD, -5)
  main.title:SetText("Bags")
  main.free = S.Text(main, 12, "LEFT")
  main.free:SetPoint("LEFT", main.title, "RIGHT", 8, 0)
  main.free:SetTextColor(0.7, 0.7, 0.7)

  local close = CreateFrame("Button", nil, main)
  close:SetWidth(18)
  close:SetHeight(18)
  close:SetPoint("TOPRIGHT", -3, -2)
  close.text = S.Text(close, 13, "CENTER")
  close.text:SetPoint("CENTER", 0, 0)
  close.text:SetText("x")
  close:SetScript("OnClick", Close)
  close:SetScript("OnEnter", function() this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3]) end)
  close:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1) end)

  -- ClassicAPI does the sorting (stacks merged, gear grouped by slot, junk to the end);
  -- right-click flips which end of the bags it fills from
  local left = close -- what the next title bar button sits left of
  if C_Container and C_Container.SortBags then
    local sort = CreateFrame("Button", nil, main)
    left = sort
    sort:SetWidth(34)
    sort:SetHeight(18)
    sort:SetPoint("RIGHT", close, "LEFT", -2, 0)
    sort:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sort.text = S.Text(sort, 12, "CENTER")
    sort.text:SetPoint("CENTER", 0, 0)
    sort.text:SetText("Sort")
    local function Tip()
      GameTooltip:SetOwner(sort, "ANCHOR_TOP")
      GameTooltip:SetText("Sort bags")
      local rtl = C_Container.GetSortBagsRightToLeft and C_Container.GetSortBagsRightToLeft()
      GameTooltip:AddLine("Fills from the " .. (rtl and "last" or "first") .. " slot. Right-click to switch.", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
    sort:SetScript("OnClick", function()
      if arg1 == "RightButton" and C_Container.SetSortBagsRightToLeft then
        C_Container.SetSortBagsRightToLeft(not C_Container.GetSortBagsRightToLeft())
        Tip()
      else
        C_Container.SortBags()
      end
    end)
    sort:SetScript("OnEnter", function() this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3]); Tip() end)
    sort:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1); GameTooltip:Hide() end)
  end

  -- the bag slots row on/off
  local slots = CreateFrame("Button", nil, main)
  slots:SetWidth(18)
  slots:SetHeight(18)
  slots:SetPoint("RIGHT", left, "LEFT", -2, 0)
  slots.icon = slots:CreateTexture(nil, "ARTWORK")
  slots.icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
  slots.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  slots.icon:SetPoint("TOPLEFT", 2, -2)
  slots.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  local function SlotsTip()
    GameTooltip:SetOwner(slots, "ANCHOR_TOP")
    GameTooltip:SetText((s.bagSlots and "Hide" or "Show") .. " bag slots")
    GameTooltip:AddLine("Drop a bag on a slot to equip it, drag one off to swap it.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  slots:SetScript("OnClick", function()
    s.bagSlots = not s.bagSlots
    Layout()
    SlotsTip()
  end)
  slots:SetScript("OnEnter", SlotsTip)
  slots:SetScript("OnLeave", function() GameTooltip:Hide() end)
  main.slotsBtn = slots

  -- the search box fills the title bar between the free count and the buttons
  local search = CreateFrame("EditBox", "SnapUIBagSearch", main)
  search:SetHeight(16)
  search:SetPoint("LEFT", main.free, "RIGHT", 8, 0)
  search:SetPoint("RIGHT", slots, "LEFT", -6, 0)
  search:SetAutoFocus(false)
  search:SetFontObject(GameFontHighlightSmall)
  search:SetTextInsets(4, 4, 0, 0)
  S.Backdrop(search, 0.5)
  search.hint = S.Text(search, 11, "LEFT")
  search.hint:SetPoint("LEFT", search, "LEFT", 4, 0)
  search.hint:SetTextColor(0.5, 0.5, 0.5)
  search.hint:SetText("Search")
  search:SetScript("OnTextChanged", function()
    local t = string.lower(string.gsub(this:GetText() or "", "^%s*(.-)%s*$", "%1"))
    query = t ~= "" and t or nil
    if query then this.hint:Hide() else this.hint:Show() end
    Highlight(hoverBag)
  end)
  search:SetScript("OnEscapePressed", function()
    this:SetText("")
    this:ClearFocus()
  end)
  search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  main.search = search
  -- closing the bags clears the search
  local onHide = main:GetScript("OnHide")
  main:SetScript("OnHide", function()
    if onHide then onHide() end
    if search:GetText() ~= "" then search:SetText("") end
    search:ClearFocus()
  end)

  main.money = S.Text(main, 12, "RIGHT")
  main.money:SetPoint("BOTTOMRIGHT", -PAD, 5)

  for _, bag in ipairs(BAGS) do
    local f = CreateFrame("Frame", "SnapUIBag" .. bag, main)
    f:SetID(bag)
    f:SetAllPoints(main)
    bagFrames[bag] = f
    CreateSlot(bag)
  end
  CreateKeySlot()
end

S:RegisterModule("bags", function()
  s = S:Settings("frames", "bags", { columns = 10, size = 34, scale = 1, enabled = true, arrows = true, bagSlots = false })
  -- "bags" is the bag buttons bar; the window has its own box (they used to share one)
  holder = S:Holder("bagwindow", "Bags window", { "BOTTOMRIGHT", nil, -8, 90 }, {})
  holder.isOff = function() return not s.enabled end
  CreateWindow()
  Layout()

  local function Opt(label, key, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[key] end, set = function(v) s[key] = v; Layout() end, min = min, max = max, step = step })
  end
  Opt("Columns", "columns", 4, 24, 1)
  Opt("Slot size", "size", 24, 48, 2)
  Opt("Scale", "scale", 0.5, 2, 0.05)
  table.insert(holder.options, { label = "Bag slots", toggle = true, get = function() return s.bagSlots end,
    set = function(v) s.bagSlots = v; Layout() end })
  table.insert(holder.options, { label = "Upgrade arrows", toggle = true, get = function() return s.arrows end,
    set = function(v) s.arrows = v; if main:IsShown() then Layout() end end })
  -- gear, level or talents changed: the arrows may be different now
  S.OnUpgradesChanged = function()
    if main and main:IsShown() then Layout() end
  end
  table.insert(holder.options, { label = "Enabled", toggle = true, get = function() return s.enabled end,
    set = function(v) s.enabled = v; if v then Install() else Uninstall() end end })

  if s.enabled then
    Install()
  end

  local events = CreateFrame("Frame")
  for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_COOLDOWN", "ITEM_LOCK_CHANGED", "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_ALERTS" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function()
    if not main:IsShown() then
      return
    end
    if event == "PLAYER_MONEY" then
      main.money:SetText(Money(GetMoney()))
    elseif event == "BAG_UPDATE_COOLDOWN" or event == "ITEM_LOCK_CHANGED" then
      for bag, list in pairs(buttons) do
        for slot in pairs(list) do
          UpdateButton(bag, slot)
        end
      end
    else
      Layout()
    end
  end)
end, "Bags", "One bag window for the backpack and bags.")
