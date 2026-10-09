-- SnapUI mail: an "Open all" button in the inbox that takes the gold and items out of every
-- letter (auction sales, won auctions, expired listings...). One thing at a time: the next
-- goes once the server has answered for the last (or after two seconds), the same reason
-- the grey seller waits. Letters asking for cash on delivery are left alone, and it stops
-- when your bags are full or the mailbox closes. Emptied letters are not deleted.

local S = SnapUI
local job, btn, mailOpen
local runner = CreateFrame("Frame")
runner:Hide()

local function Money(c)
  local g, sv, cc = math.floor(c / 10000), math.floor(math.mod(c, 10000) / 100), math.mod(c, 100)
  local t = ""
  if g > 0 then t = t .. g .. "g " end
  if g > 0 or sv > 0 then t = t .. sv .. "s " end
  return t .. cc .. "c"
end

local function FreeSlots()
  local free = 0
  for bag = 0, 4 do
    for slot = 1, (GetContainerNumSlots(bag) or 0) do
      if not GetContainerItemLink(bag, slot) then
        free = free + 1
      end
    end
  end
  return free
end

-- money, cash on delivery, has an item
local function Header(i)
  local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
  return money or 0, cod or 0, hasItem
end

-- what's waiting: letters, gold, letters with an item
local function Waiting()
  local n, gold, items = GetInboxNumItems() or 0, 0, 0
  for i = 1, n do
    local money, cod, hasItem = Header(i)
    if cod == 0 then
      gold = gold + money
      if hasItem then items = items + 1 end
    end
  end
  return n, gold, items
end

local function Finish(reason)
  local j = job
  job = nil
  runner:Hide()
  if btn then btn:SetText("Open all") end
  if not j then
    return
  end
  local parts = {}
  if j.gold > 0 then table.insert(parts, Money(j.gold)) end
  if j.items > 0 then table.insert(parts, j.items .. " item" .. (j.items > 1 and "s" or "")) end
  local got = table.getn(parts) > 0 and ("took " .. table.concat(parts, " and ")) or "nothing to take"
  if j.cod > 0 then
    got = got .. " (" .. j.cod .. " cash-on-delivery letter" .. (j.cod > 1 and "s" or "") .. " left for you)"
  end
  S.Print("mail: " .. got .. (reason and (", " .. reason) or "") .. ".")
end

runner:SetScript("OnUpdate", function()
  local j = job
  if not j then
    this:Hide()
    return
  end
  if not mailOpen then
    Finish("stopped: mailbox closed")
    return
  end
  local now = GetTime()
  local n = GetInboxNumItems() or 0
  if j.wait then
    local money, _, hasItem = Header(j.i)
    local gone = n ~= j.count
    local done = gone or (j.wait == "money" and money == 0) or (j.wait == "item" and not hasItem)
    if not done then
      if now - j.sent < 2 then
        return
      end
      j.i = j.i - 1 -- no answer: leave that letter and carry on
    elseif j.wait == "money" then
      j.gold = j.gold + j.amount
    else
      j.items = j.items + 1
    end
    if gone then
      -- the emptied letter went away: the ones after it moved up a place, and those are
      -- done already, so carry on with the one before it
      j.i = j.i - 1
    end
    j.wait, j.next = nil, now + 0.2
  end
  if j.next and now < j.next then
    return
  end
  j.count = n
  if j.i > n then j.i = n end
  if j.i < 1 then
    Finish()
    return
  end
  local money, cod, hasItem = Header(j.i)
  if cod > 0 then
    j.cod = j.cod + 1
    j.i = j.i - 1
  elseif money > 0 then
    j.wait, j.sent, j.amount = "money", now, money
    TakeInboxMoney(j.i)
  elseif hasItem then
    if FreeSlots() == 0 then
      Finish("stopped: your bags are full")
      return
    end
    j.wait, j.sent = "item", now
    TakeInboxItem(j.i)
  else
    j.i = j.i - 1
  end
end)

function S:OpenAllMail()
  if job then
    Finish("stopped")
    return
  end
  local n = GetInboxNumItems() or 0
  -- from the last letter back, so letters that vanish once empty don't move the ones ahead
  job = { i = n, count = n, gold = 0, items = 0, cod = 0 }
  if btn then btn:SetText("Stop") end
  runner:Show()
end

local function Build()
  if btn or not InboxFrame then
    return
  end
  btn = CreateFrame("Button", "SnapUIOpenAllMail", InboxFrame, "UIPanelButtonTemplate")
  btn:SetWidth(76)
  btn:SetHeight(20)
  -- the page row at the bottom, between the back arrow and "Page 1"
  btn:SetPoint("CENTER", InboxFrame, "BOTTOMLEFT", 108, 104)
  btn:SetText("Open all")
  btn:SetScript("OnClick", function() S:OpenAllMail() end)
  btn:SetScript("OnEnter", function()
    local n, gold, items = Waiting()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Open all")
    GameTooltip:AddLine(n .. " letter" .. (n == 1 and "" or "s") .. ": " .. Money(gold) .. ", " .. items .. " with an item", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Takes the gold and items out of every letter, one at a time. Cash-on-delivery letters are skipped.", 0.8, 0.8, 0.8, 1)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

S:RegisterModule("mail", function()
  Build()
  local events = CreateFrame("Frame")
  events:RegisterEvent("MAIL_SHOW")
  events:RegisterEvent("MAIL_CLOSED")
  events:SetScript("OnEvent", function()
    mailOpen = event == "MAIL_SHOW"
    if mailOpen then Build() end
  end)
end, "Mail", "An Open all button in the inbox: takes the gold and items out of every letter.")
