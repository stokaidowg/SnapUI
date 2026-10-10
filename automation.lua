-- SnapUI automation: little chores done for you. At a vendor: sell grey items (on opening,
-- and with a "Sell grays" button in the vendor window) and repair
-- (if you can afford it). Accept and hand in quests (Shift skips it). Optionally hide the red
-- "Not enough mana" style error text.

local S = SnapUI
local s

local function Money(c)
  local g, sv, cc = math.floor(c / 10000), math.floor(math.mod(c, 10000) / 100), math.mod(c, 100)
  local t = ""
  if g > 0 then t = t .. g .. "g " end
  if g > 0 or sv > 0 then t = t .. sv .. "s " end
  return t .. cc .. "c"
end

-- every grey (poor quality) item in your bags: calls fn(bag, slot, link, value) for each,
-- returns how many and what they sell for (value 0 if the sell price isn't known)
local function EachJunk(fn)
  local n, value = 0, 0
  for bag = 0, 4 do
    for slot = 1, (GetContainerNumSlots(bag) or 0) do
      local link = GetContainerItemLink(bag, slot)
      if link and string.find(link, "|cff9d9d9d") then
        local _, count, locked = GetContainerItemInfo(bag, slot)
        if not locked then
          local _, _, id = string.find(link, "item:(%d+)")
          local each = id and C_Item and C_Item.GetItemSellPriceByID and C_Item.GetItemSellPriceByID(tonumber(id)) or 0
          n = n + 1
          value = value + (each or 0) * (count or 1)
          if fn then fn(bag, slot, link, (each or 0) * (count or 1)) end
        end
      end
    end
  end
  return n, value
end

-- Selling them all at once sends a burst of sell requests; the server can drop some, and an
-- item it never answers for stays locked (greyed out in the bags, can't be sold or moved)
-- until you log out. So one at a time: the next goes once the last has left your bags (or
-- after 1.5 seconds), and only while the vendor is open.
local selling, merchantOpen
local seller = CreateFrame("Frame")
seller:Hide()

-- grey items that are locked with nothing on the cursor: a sell the server never answered
-- (nothing an addon can undo; logging out frees them)
local function WarnStuck()
  if CursorHasItem and CursorHasItem() then
    return
  end
  for bag = 0, 4 do
    for slot = 1, (GetContainerNumSlots(bag) or 0) do
      local link = GetContainerItemLink(bag, slot)
      if link and string.find(link, "|cff9d9d9d") then
        local _, _, locked = GetContainerItemInfo(bag, slot)
        if locked then
          S.Print(link .. " looks stuck (locked: the server never confirmed a sale). Log out to character select and back in to free it.")
        end
      end
    end
  end
end

local function SellDone(finished)
  local j = selling
  selling = nil
  seller:Hide()
  if j and j.sold > 0 then
    S.Print("sold " .. j.sold .. " grey item" .. (j.sold > 1 and "s" or "") .. (j.value > 0 and (" for " .. Money(j.value)) or ""))
  end
  if finished then
    WarnStuck()
  end
end

seller:SetScript("OnUpdate", function()
  local j = selling
  if not j or not merchantOpen then
    SellDone()
    return
  end
  local cur = j.list[j.i]
  if cur and j.sent then
    if GetContainerItemLink(cur[1], cur[2]) == cur[3] then
      if GetTime() - j.sent < 1.5 then
        return -- not gone yet
      end
    else
      j.sold, j.value = j.sold + 1, j.value + cur[4]
    end
  end
  j.i, j.sent = j.i + 1, nil
  local it = j.list[j.i]
  if not it then
    SellDone(true)
    return
  end
  local _, _, locked = GetContainerItemInfo(it[1], it[2])
  if GetContainerItemLink(it[1], it[2]) == it[3] and not locked then
    UseContainerItem(it[1], it[2])
    j.sent = GetTime()
  end
end)

local function SellJunk(quiet)
  if selling then
    return
  end
  local list = {}
  EachJunk(function(bag, slot, link, value) table.insert(list, { bag, slot, link, value }) end)
  if table.getn(list) == 0 then
    if not quiet then S.Print("no grey items to sell") end
    WarnStuck()
    return
  end
  selling = { list = list, i = 0, sold = 0, value = 0 }
  seller:Show()
end

-- a "Sell grays" button in the vendor window's bottom strip, left of your money
local function SellButton()
  if not MerchantFrame or getglobal("SnapUISellGrays") then
    return
  end
  local b = CreateFrame("Button", "SnapUISellGrays", MerchantFrame, "UIPanelButtonTemplate")
  b:SetWidth(90)
  b:SetHeight(20)
  b:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 24, 66)
  b:SetText("Sell grays")
  b:SetScript("OnClick", function() SellJunk() end)
  b:SetScript("OnEnter", function()
    local n, value = EachJunk()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Sell grays")
    if n == 0 then
      GameTooltip:AddLine("No grey items in your bags", 0.8, 0.8, 0.8)
    else
      GameTooltip:AddLine(n .. " grey item" .. (n > 1 and "s" or "") .. (value > 0 and (", " .. Money(value)) or ""), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Repair()
  if not CanMerchantRepair or not CanMerchantRepair() then
    return
  end
  local cost, can = GetRepairAllCost()
  if not cost or cost <= 0 or not can then
    return
  end
  if GetMoney() >= cost then
    RepairAllItems()
    S.Print("repaired for " .. Money(cost))
  else
    S.Print("can't afford repairs (" .. Money(cost) .. ")")
  end
end

-- "Not enough rage", "Out of range" and friends, while in combat
local ERRORS_SPAM = { "Not enough", "Out of range", "not ready", "Another action", "Can't do that", "You have no target", "Invalid target" }
local function HookErrors()
  if not UIErrorsFrame or UIErrorsFrame.snapHooked then
    return
  end
  UIErrorsFrame.snapHooked = true
  local orig = UIErrorsFrame.AddMessage
  UIErrorsFrame.AddMessage = function(self, msg, r, g, b, a, hold)
    if s.hideErrors and msg and UnitAffectingCombat("player") then
      for _, pattern in ipairs(ERRORS_SPAM) do
        if string.find(msg, pattern, 1, true) then
          return
        end
      end
    end
    return orig(self, msg, r, g, b, a, hold)
  end
end

-- [[ quests ]] --
-- Auto accept: quests an NPC offers are taken straight away. Auto turn in: quests that are
-- done are handed in, and the reward taken when there's no choice to make (with a choice of
-- rewards the window stays open for you). Hold Shift while talking to an NPC to do it all
-- by hand. Quests that ask for money are left to you as well.
-- With SnapGuide following a route, only the quests the guide picks up are accepted by
-- themselves (s.guideOnly, default on): an NPC with several quests gets the guide's one chosen,
-- and anything else is left for you to click. Without the guide (or with it hidden), all are.

-- does the guide want this quest? true / false, or nil when there's no guide to ask
local function GuideWants(title)
  if not s.guideOnly or not (SnapGuide and SnapGuide.WantsQuest) then return nil end
  return SnapGuide:WantsQuest(title)
end

-- the first offered quest to take: the guide's choice, or the first one when there's no guide
local function PickOffered(titles)
  for i, title in ipairs(titles) do
    local want = GuideWants(title)
    if want == nil then return i end
    if want then return i end
  end
end

-- is the quest with this title in your log ready to hand in? (done, or nothing to collect,
-- like "talk to so-and-so")
local function QuestReady(title)
  for i = 1, (GetNumQuestLogEntries() or 0) do
    local t, _, _, header, _, complete = GetQuestLogTitle(i)
    if not header and t == title then
      if complete == 1 then
        return true
      end
      return complete == nil and (GetNumQuestLeaderBoards(i) or 0) == 0
    end
  end
  return false
end

-- gossip lists come as title, level, title, level... (up to 10 quests; no varargs, they
-- differ between Lua 5.0 and later)
local function Titles(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
  local all = { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20 }
  local list = {}
  for i = 1, 19, 2 do
    if not all[i] then break end
    table.insert(list, all[i])
  end
  return list
end

local function OnQuestEvent()
  if IsShiftKeyDown() then
    return
  end
  if event == "GOSSIP_SHOW" then
    if s.questTurnIn then
      for i, title in ipairs(Titles(GetGossipActiveQuests())) do
        if QuestReady(title) then
          SelectGossipActiveQuest(i)
          return
        end
      end
    end
    if s.questAccept then
      local i = PickOffered(Titles(GetGossipAvailableQuests()))
      if i then SelectGossipAvailableQuest(i) end
    end
  elseif event == "QUEST_GREETING" then
    if s.questTurnIn then
      for i = 1, (GetNumActiveQuests() or 0) do
        if QuestReady(GetActiveTitle(i)) then
          SelectActiveQuest(i)
          return
        end
      end
    end
    if s.questAccept then
      local titles = {}
      for i = 1, (GetNumAvailableQuests() or 0) do table.insert(titles, GetAvailableTitle(i)) end
      local i = PickOffered(titles)
      if i then SelectAvailableQuest(i) end
    end
  elseif event == "QUEST_DETAIL" then
    if s.questAccept and GuideWants(GetTitleText and GetTitleText()) ~= false then
      AcceptQuest()
    end
  elseif event == "QUEST_PROGRESS" then
    if s.questTurnIn and IsQuestCompletable() and (GetQuestMoneyToGet() or 0) == 0 then
      CompleteQuest()
    end
  elseif event == "QUEST_COMPLETE" then
    local choices = GetNumQuestChoices() or 0
    if s.questTurnIn and choices <= 1 and (GetQuestMoneyToGet() or 0) == 0 then
      GetQuestReward(choices)
    end
  end
end

function S:AutomationOptions()
  local function Toggle(label, key)
    return { label = label, toggle = true, get = function() return s[key] end, set = function(v) s[key] = v end }
  end
  return {
    Toggle("Sell grey items at vendors", "sellJunk"),
    Toggle("Repair at vendors", "repair"),
    Toggle("Hide error spam in combat", "hideErrors"),
    Toggle("Accept quests automatically", "questAccept"),
    Toggle("Turn in finished quests", "questTurnIn"),
    Toggle("With SnapGuide: only accept the guide's quests", "guideOnly"),
  }
end

S:RegisterModule("automation", function()
  s = S:Settings("frames", "auto", { sellJunk = true, repair = true, hideErrors = false, questAccept = true, questTurnIn = true, guideOnly = true })
  HookErrors()
  SellButton()
  local events = CreateFrame("Frame")
  events:RegisterEvent("MERCHANT_SHOW")
  events:RegisterEvent("MERCHANT_CLOSED")
  events:SetScript("OnEvent", function()
    merchantOpen = event == "MERCHANT_SHOW"
    if not merchantOpen then return end
    if s.sellJunk then SellJunk(true) end
    if s.repair then Repair() end
  end)
  local quests = CreateFrame("Frame")
  for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
    quests:RegisterEvent(e)
  end
  quests:SetScript("OnEvent", OnQuestEvent)
end, "Automation", "Sell grey items and repair at vendors, accept and hand in quests, hide combat error spam.")
