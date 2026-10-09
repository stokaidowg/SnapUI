-- SnapUI bank: the bank in the same look as the bag window. One window holds the 24 bank
-- slots and every bank bag, with the bank bag slots along the top (drop a bag on one to
-- equip it, drag one off to swap it, + buys the next slot through Blizzard's own "are you
-- sure" box). Blizzard's bank frame stays open but invisible underneath, so talking to the
-- banker, closing and every item click behave exactly like the default bank: the 24 main
-- slots use Blizzard's bank button template, the bank bags the normal bag button template.

local S = SnapUI

local BAGS = { -1, 5, 6, 7, 8, 9, 10 }
local HEADER, FOOTER, PAD = 22, 8, 6
local SLOT_SIZE = 24
local SLOT_ROW = SLOT_SIZE + 6

local main, holder, s
local bagFrames, buttons, slotButtons = {}, {}, {}
local atBank = false

local function QualityColor(link)
  local _, _, hex = string.find(link or "", "|c(%x%x%x%x%x%x%x%x)")
  if not hex or hex == "ffffffff" or hex == "ff9d9d9d" then
    return nil
  end
  return tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255, tonumber(string.sub(hex, 7, 8), 16) / 255
end

local function GetButton(bag, slot)
  buttons[bag] = buttons[bag] or {}
  local b = buttons[bag][slot]
  if b then
    return b
  end
  local name = "SnapUIBank" .. (bag == -1 and "Main" or bag) .. "Item" .. slot
  local tpl = bag == -1 and "BankItemButtonGenericTemplate" or "ContainerFrameItemButtonTemplate"
  b = CreateFrame("Button", name, bagFrames[bag], tpl)
  b:SetID(slot)
  local normal = getglobal(name .. "NormalTexture")
  if normal then normal:SetTexture(nil) end
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
  buttons[bag][slot] = b
  return b
end

local function UpdateButton(bag, slot)
  local b = buttons[bag] and buttons[bag][slot]
  if not b then
    return
  end
  local texture, count, locked = GetContainerItemInfo(bag, slot)
  SetItemButtonTexture(b, texture)
  SetItemButtonCount(b, count)
  SetItemButtonDesaturated(b, locked, 0.5, 0.5, 0.5)
  local cd = getglobal(b:GetName() .. "Cooldown") -- bag buttons only
  if texture then
    if cd then ContainerFrame_UpdateCooldown(bag, b) end
    b.hasItem = 1
  else
    if cd then cd:Hide() end
    b.hasItem = nil
  end
  local r, g, bl = QualityColor(GetContainerItemLink(bag, slot))
  if r then
    b.bg:SetBackdropBorderColor(r, g, bl, 1)
  else
    S.ResetBorder(b.bg)
  end
end

-- [[ bank bag slots ]] --
local function BagInv(i)
  return BankButtonIDToInvSlotID(i, 1)
end

local function Owned()
  local n, full = GetNumBankSlots()
  return n or 0, full
end

local function UpdateSlots()
  local owned, full = Owned()
  for i = 1, NUM_BANKBAGSLOTS or 6 do
    local b = slotButtons[i]
    b.icon:SetTexture(GetInventoryItemTexture("player", BagInv(i)))
    if i <= owned then
      b.bg:SetBackdropColor(0.06, 0.06, 0.06, 0.6)
      b.icon:SetVertexColor(1, 1, 1)
    else
      b.bg:SetBackdropColor(0.5, 0.05, 0.05, 0.5) -- not bought yet
    end
    local n = i <= owned and GetContainerNumSlots(4 + i) or 0
    local free = 0
    for slot = 1, n do
      if not GetContainerItemInfo(4 + i, slot) then free = free + 1 end
    end
    b.count:SetText(n > 0 and free or "")
  end
  if full then main.buy:Hide() else main.buy:Show() end
end

local function CreateSlot(i)
  local b = CreateFrame("Button", "SnapUIBankBagSlot" .. i, main)
  b:SetWidth(SLOT_SIZE)
  b:SetHeight(SLOT_SIZE)
  b:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + (i - 1) * (SLOT_SIZE + 3), -HEADER - 2)
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
  local function PutOrPick()
    if i > Owned() then
      return
    end
    if CursorHasItem() then
      PutItemInBag(BagInv(i))
    else
      PickupBagFromSlot(BagInv(i))
    end
  end
  b:SetScript("OnClick", PutOrPick)
  b:SetScript("OnReceiveDrag", PutOrPick)
  b:SetScript("OnDragStart", function()
    if i <= Owned() then PickupBagFromSlot(BagInv(i)) end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    if i > Owned() then
      GameTooltip:SetText(BANK_BAG_PURCHASE or "Purchasable bag slot")
      GameTooltip:AddLine("Buy it with the + button.", 0.8, 0.8, 0.8)
    elseif not GameTooltip:SetInventoryItem("player", BagInv(i)) then
      GameTooltip:SetText(BANK_BAG or "Bank bag")
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slotButtons[i] = b
end

-- [[ window ]] --
local function Layout()
  local size, sp, cols = s.size, 3, s.columns
  local top = HEADER + SLOT_ROW
  local i, free, total = 0, 0, 0
  for _, bag in ipairs(BAGS) do
    local n = GetContainerNumSlots(bag) or 0
    if bag == -1 then n = NUM_BANKGENERIC_SLOTS or 24 end
    for slot = 1, n do
      local b = GetButton(bag, slot)
      b:SetWidth(size)
      b:SetHeight(size)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + math.mod(i, cols) * (size + sp), -top - math.floor(i / cols) * (size + sp))
      b:Show()
      UpdateButton(bag, slot)
      if not GetContainerItemInfo(bag, slot) then free = free + 1 end
      i = i + 1
    end
    total = total + n
    for slot = n + 1, table.getn(buttons[bag] or {}) do
      buttons[bag][slot]:Hide()
    end
  end
  local rows = math.max(1, math.ceil(i / cols))
  main:SetWidth(math.max(PAD * 2 + cols * size + (cols - 1) * sp, PAD * 2 + 7 * (SLOT_SIZE + 3)))
  main:SetHeight(top + rows * size + (rows - 1) * sp + FOOTER)
  main:SetScale(s.scale)
  main.free:SetText((total - free) .. "/" .. total)
  UpdateSlots()
  S:Fit(holder, main)
end

-- Blizzard's bank frame stays open (the bank needs it) but can't be seen or clicked
local function HideBlizzard(hide)
  if not BankFrame then return end
  if hide then
    BankFrame:SetScale(0.001)
    BankFrame:SetAlpha(0)
  else
    BankFrame:SetScale(1)
    BankFrame:SetAlpha(1)
  end
end

function S:BankWindowShown()
  return main and main:IsShown() and true or false
end

local function CreateWindow()
  main = CreateFrame("Frame", "SnapUI_Bank", holder)
  main:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  main:SetFrameStrata("HIGH")
  S:MakeDraggable(main, holder)
  S.Backdrop(main, 0.92)
  main:Hide()
  table.insert(UISpecialFrames, "SnapUI_Bank")

  main.title = S.Text(main, 13, "LEFT")
  main.title:SetPoint("TOPLEFT", PAD, -5)
  main.title:SetText(BANK or "Bank")
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
  close:SetScript("OnClick", function() main:Hide() end)
  close:SetScript("OnEnter", function() this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3]) end)
  close:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1) end)
  -- closing ours (x or Escape) ends the bank visit like Blizzard's close button does
  main:SetScript("OnHide", function()
    if atBank then CloseBankFrame() end
  end)

  for _, bag in ipairs(BAGS) do
    local f = CreateFrame("Frame", "SnapUIBankBag" .. (bag == -1 and "Main" or bag), main)
    f:SetID(bag)
    f:SetAllPoints(main)
    bagFrames[bag] = f
  end
  for i = 1, NUM_BANKBAGSLOTS or 6 do
    CreateSlot(i)
  end
  -- + buys the next bank bag slot (Blizzard asks to confirm and shows the price)
  local buy = CreateFrame("Button", "SnapUIBankBuySlot", main)
  buy:SetWidth(SLOT_SIZE)
  buy:SetHeight(SLOT_SIZE)
  buy:SetPoint("LEFT", slotButtons[NUM_BANKBAGSLOTS or 6], "RIGHT", 6, 0)
  S.Backdrop(buy, 0.6)
  buy.text = S.Text(buy, 14, "CENTER")
  buy.text:SetPoint("CENTER", 0, 0)
  buy.text:SetText("+")
  buy:SetScript("OnClick", function() StaticPopup_Show("CONFIRM_BUY_BANK_SLOT") end)
  buy:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Buy a bank bag slot")
    local cost = GetBankSlotCost(Owned())
    if cost then
      GameTooltip:AddLine(math.floor(cost / 10000) .. "g " .. math.floor(math.mod(cost, 10000) / 100) .. "s", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  buy:SetScript("OnLeave", function() GameTooltip:Hide() end)
  main.buy = buy
end

S:RegisterModule("bank", function()
  s = S:Settings("frames", "bank", { columns = 14, size = 34, scale = 1, enabled = true })
  holder = S:Holder("bankwindow", "Bank window", { "TOPLEFT", nil, 20, -140 }, {})
  holder.isOff = function() return not s.enabled end
  CreateWindow()

  local function Opt(label, key, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[key] end,
      set = function(v) s[key] = v; if main:IsShown() then Layout() end end, min = min, max = max, step = step })
  end
  Opt("Columns", "columns", 7, 24, 1)
  Opt("Slot size", "size", 24, 48, 2)
  Opt("Scale", "scale", 0.5, 2, 0.05)
  table.insert(holder.options, { label = "Enabled", toggle = true, get = function() return s.enabled end,
    set = function(v)
      s.enabled = v
      if not v then
        HideBlizzard(false)
        main:Hide()
      end
    end })

  local events = CreateFrame("Frame")
  for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE", "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function()
    if event == "BANKFRAME_OPENED" then
      atBank = true
      if not s.enabled then return end
      HideBlizzard(true)
      main:Show()
      Layout()
      if OpenBackpack then OpenBackpack() end
    elseif event == "BANKFRAME_CLOSED" then
      atBank = false
      main:Hide()
    elseif main:IsShown() then
      if event == "ITEM_LOCK_CHANGED" or event == "BAG_UPDATE_COOLDOWN" then
        for bag, list in pairs(buttons) do
          for slot in pairs(list) do UpdateButton(bag, slot) end
        end
      else
        Layout()
      end
    end
  end)
end, "Bank", "The bank in the bag window's look: bank slots and bank bags in one window.")
