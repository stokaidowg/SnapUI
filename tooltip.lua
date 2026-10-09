-- SnapUI tooltips: flat dark panel with a 1px border (item quality colour for items, class
-- colour for players), the SnapUI font, a slim health bar, and a movable home: tooltips that
-- would use the default spot open from a holder edit mode can move, or sit beside the cursor
-- and follow it (Follow cursor option, or /snap cursor).

local S = SnapUI
local s, holder

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "WorldMapTooltip" }

-- is this (r, g, b) one of the item quality colours from uncommon up?
local function QualityColor(r, g, b)
  if not ITEM_QUALITY_COLORS or not r then
    return nil
  end
  for q = 2, 6 do
    local c = ITEM_QUALITY_COLORS[q]
    if c and math.abs(c.r - r) < 0.02 and math.abs(c.g - g) < 0.02 and math.abs(c.b - b) < 0.02 then
      return c
    end
  end
end

local function Border(tip)
  local r, g, b = 0, 0, 0
  local first = getglobal(tip:GetName() .. "TextLeft1")
  local title = first and first:GetText()
  if tip == GameTooltip and title and UnitIsPlayer("mouseover") and title == UnitName("mouseover") then
    -- a player's tooltip: class colour
    local _, class = UnitClass("mouseover")
    local c = S.CLASS[class]
    if c then r, g, b = c[1], c[2], c[3] end
  else
    local c = first and QualityColor(first:GetTextColor())
    if c then r, g, b = c.r, c.g, c.b end
  end
  tip:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
  tip:SetBackdropBorderColor(r, g, b, 1)
end

local function Style(tip)
  S.PixelBackdrop(tip)
  Border(tip)
  local onShow = tip:GetScript("OnShow")
  tip:SetScript("OnShow", function()
    if onShow then onShow() end
    Border(this)
  end)
end

local function Fonts()
  local function Set(font, size)
    if font and font.SetFont then
      font:SetFont(S.FONT, size, "")
    end
  end
  Set(GameTooltipHeaderText, 15)
  Set(GameTooltipText, 13)
  Set(GameTooltipTextSmall, 12)
  -- lines that already exist were made from those fonts before we changed them
  for _, name in ipairs(TOOLTIPS) do
    for i = 1, 30 do
      local left, right = getglobal(name .. "TextLeft" .. i), getglobal(name .. "TextRight" .. i)
      local size = i == 1 and 15 or 13
      if left then left:SetFont(S.FONT, size, "") end
      if right then right:SetFont(S.FONT, size, "") end
    end
  end
end

local function StyleHealthBar()
  local bar = GameTooltipStatusBar
  if not bar then
    return
  end
  bar:SetStatusBarTexture(S.TEX)
  bar:SetHeight(4)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 1, -2)
  bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -1, -2)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetTexture(S.TEX)
  bg:SetVertexColor(0.1, 0.1, 0.1, 0.9)
end

-- cursor mode: the tooltip sits beside the pointer (up and to the right, flipping when it
-- would run off screen) and follows it every frame. `following` is cleared by any other
-- SetOwner call, so tooltips that pick their own spot (action buttons, bags) are left alone.
local following = false

local function FollowCursor()
  local tip = GameTooltip
  local scale = tip:GetEffectiveScale()
  local x, y = GetCursorPosition()
  x, y = x / scale, y / scale
  local off = s.offset
  local w, h = tip:GetWidth(), tip:GetHeight()
  local ui = UIParent:GetEffectiveScale() / scale
  local sw, sh = UIParent:GetRight() * ui, UIParent:GetTop() * ui
  local px, py, side, edge = x + off, y + off, "LEFT", "BOTTOM"
  if px + w > sw then px, side = x - off, "RIGHT" end
  -- +8 leaves room for the health bar under the tooltip
  if py + h > sh then py, edge = y - off - 8, "TOP" end
  tip:ClearAllPoints()
  tip:SetPoint(edge .. side, UIParent, "BOTTOMLEFT", px, py)
end

-- fade out: when the mouse leaves a unit in the world, the tooltip fades over s.fade seconds
-- and hides. The game runs its own fade too and we can't stop that, so we only ever make it
-- quicker (alpha is the lower of ours and the game's); FADE_DEFAULT means leave it alone.
local FADE_DEFAULT = 2
local fades, fadeStart = false, nil

local function Fade(tip)
  if not fades or s.fade > FADE_DEFAULT - 0.05 then
    return
  end
  if not fadeStart then
    if UnitExists("mouseover") then return end
    fadeStart = GetTime()
  end
  local left = 1 - (GetTime() - fadeStart) / math.max(s.fade, 0.01)
  if left <= 0 then
    fades, fadeStart = false, nil
    tip:Hide()
  elseif left < tip:GetAlpha() then
    tip:SetAlpha(left)
  end
end

function S:ToggleTooltipCursor()
  s.cursor = not s.cursor
  return s.cursor
end

-- open from the holder's corner nearest the screen edge, so it grows inward
local function Anchor(tip, parent)
  if s.cursor then
    tip:SetOwner(parent, "ANCHOR_NONE")
    following = true
    FollowCursor()
    return
  end
  local x, y = holder:GetCenter()
  local cx, cy = UIParent:GetCenter()
  local corner = (y > cy and "TOP" or "BOTTOM") .. (x > cx and "RIGHT" or "LEFT")
  tip:SetOwner(parent, "ANCHOR_NONE")
  tip:ClearAllPoints()
  tip:SetPoint(corner, holder, corner, 0, 0)
end

-- [[ item prices ]] --
-- "Sell" and "Buy" lines on item tooltips (with the whole stack's price when there's more
-- than one). Sell price is read from the client through ClassicAPI; buy price is the vendor
-- price list in prices.lua, so items no vendor sells only get a Sell line.

local function Money(c)
  local g, sv, cp = math.floor(c / 10000), math.floor(math.mod(c, 10000) / 100), math.mod(c, 100)
  local text = ""
  if g > 0 then text = "|cffffffff" .. g .. "|cffffd700g|r " end
  if sv > 0 then text = text .. "|cffffffff" .. sv .. "|cffc7c7cfs|r " end
  if cp > 0 or text == "" then text = text .. "|cffffffff" .. cp .. "|cffeda55fc|r" end
  return text
end

local function ItemId(link)
  if type(link) == "number" then return link end
  if type(link) ~= "string" then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  return tonumber(id)
end

-- call a global only if this client has it (some come from ClassicAPI)
local function Call(name, a1, a2, a3)
  local fn = getglobal(name)
  if fn then return fn(a1, a2, a3) end
end

local function Third(name, a1, a2)
  local _, _, n = Call(name, a1, a2)
  return n
end

-- tooltip method -> how to find the item (a link or an id) and the stack size from its arguments
local PRICED = {
  SetBagItem = { function(bag, slot) return Call("GetContainerItemLink", bag, slot) end,
    function(bag, slot) local _, n = Call("GetContainerItemInfo", bag, slot) return n end },
  SetInventoryItem = { function(unit, slot) return Call("GetInventoryItemLink", unit, slot) end,
    function(unit, slot) return Call("GetInventoryItemCount", unit, slot) end },
  SetLootItem = { function(slot) return Call("GetLootSlotLink", slot) end, function(slot) return Third("GetLootSlotInfo", slot) end },
  SetLootRollItem = { function(id) return Call("GetLootRollItemLink", id) end, function(id) return Third("GetLootRollItemInfo", id) end },
  SetQuestItem = { function(t, i) return Call("GetQuestItemLink", t, i) end, function(t, i) return Third("GetQuestItemInfo", t, i) end },
  SetQuestLogItem = { function(t, i) return Call("GetQuestLogItemLink", t, i) end,
    function(t, i) return Third(t == "choice" and "GetQuestLogChoiceInfo" or "GetQuestLogRewardInfo", i) end },
  SetMerchantItem = { function(i) return Call("GetMerchantItemLink", i) end,
    function(i) local _, _, _, n = Call("GetMerchantItemInfo", i) return n end },
  SetBuybackItem = { function(i) return Call("GetBuybackItemLink", i) end,
    function(i) local _, _, _, n = Call("GetBuybackItemInfo", i) return n end },
  SetTradeSkillItem = {
    function(i, r) if r then return Call("GetTradeSkillReagentItemLink", i, r) end return Call("GetTradeSkillItemLink", i) end,
    function(i, r) if r then return Third("GetTradeSkillReagentInfo", i, r) end return Call("GetTradeSkillNumMade", i) end },
  SetCraftItem = { function(i, r) return Call("GetCraftReagentItemLink", i, r) end, function(i, r) return Third("GetCraftReagentInfo", i, r) end },
  SetAuctionItem = { function(t, i) return Call("GetAuctionItemLink", t, i) end, function(t, i) return Third("GetAuctionItemInfo", t, i) end },
  SetAuctionSellItem = { function() return Call("GetAuctionSellItemLink") end, function() return Third("GetAuctionSellItemInfo") end },
  SetTradePlayerItem = { function(i) return Call("GetTradePlayerItemLink", i) end, function(i) return Third("GetTradePlayerItemInfo", i) end },
  SetTradeTargetItem = { function(i) return Call("GetTradeTargetItemLink", i) end, function(i) return Third("GetTradeTargetItemInfo", i) end },
  SetInboxItem = { function(i) return Call("GetInboxItemLink", i) or Call("GetInboxItemID", i) end,
    function(i) local _, _, c, d = Call("GetInboxItem", i) if type(c) == "number" then return c end return d end },
  SetSendMailItem = { function() return Call("GetSendMailItemLink") end, function() return Third("GetSendMailItem") end },
  SetHyperlink = { function(link) return link end },
}

local function AddPrices(tip, method, id, count)
  if not id or not s.prices then
    return
  end
  local sell = C_Item and C_Item.GetItemSellPriceByID and C_Item.GetItemSellPriceByID(id) or 0
  local buy = SnapUI_BuyPrices and SnapUI_BuyPrices[id]
  -- at a vendor the game already prints the sell price on your own bag items
  if method == "SetBagItem" and MerchantFrame and MerchantFrame:IsShown() then
    sell = 0
  end
  if sell <= 0 and not buy then
    return
  end
  count = (count and count > 1) and count or 1
  local function Line(label, each)
    local text = Money(each)
    if count > 1 then
      text = text .. "  |cff888888(" .. count .. ": |r" .. Money(each * count) .. "|cff888888)|r"
    end
    tip:AddDoubleLine(label, text, 0.75, 0.75, 0.75, 1, 1, 1)
  end
  if sell > 0 then Line("Sell", sell) end
  if buy then Line("Buy", buy) end
  -- (the hook below resizes the tooltip)
end

local function HookPrices(tip)
  for method, how in pairs(PRICED) do
    local orig = tip[method]
    if orig then
      -- own copies: Lua 5.0 shares loop variables between iterations
      local m, getLink, getCount = method, how[1], how[2]
      tip[m] = function(self, a1, a2, a3)
        local r1, r2, r3 = orig(self, a1, a2, a3)
        local lines = self:NumLines()
        -- upgrade line first: it reads the item's own lines before anything is added
        if S.AddUpgrade then S:AddUpgrade(self, m, a1, s) end
        local id = ItemId(getLink(a1, a2, a3))
        if id then AddPrices(self, m, id, getCount and getCount(a1, a2, a3)) end
        if self:NumLines() ~= lines and self:IsShown() then self:Show() end -- resize to the new lines
        return r1, r2, r3
      end
    end
  end
end

S:RegisterModule("tooltip", function()
  s = S:Settings("frames", "tooltip", { cursor = false, scale = 1, offset = 16, fade = FADE_DEFAULT, prices = true, upgrades = "auto" })
  holder = S:Holder("tooltip", "Tooltip", { "BOTTOMRIGHT", nil, -8, 180 }, {})
  holder.noFade = true
  holder:SetWidth(180)
  holder:SetHeight(60)

  -- the map's tooltip is a child of the world map, which the client moves between no parent
  -- (fullscreen) and UIParent (windowed) and SnapUI scales; its text, set up at one scale,
  -- then drew wider than its box. On UIParent it measures like every other tooltip (and
  -- goes before Fonts(), which sets its lines up at that scale).
  if WorldMapTooltip and WorldMapFrame then
    WorldMapTooltip:SetParent(UIParent)
    WorldMapTooltip:SetFrameStrata("TOOLTIP")
    local onHide = WorldMapFrame:GetScript("OnHide")
    WorldMapFrame:SetScript("OnHide", function()
      if onHide then onHide() end
      WorldMapTooltip:Hide()
    end)
  end

  for _, name in ipairs(TOOLTIPS) do
    local tip = getglobal(name)
    if tip then Style(tip) end
  end
  Fonts()
  StyleHealthBar()
  GameTooltip:SetScale(s.scale)
  if WorldMapTooltip then WorldMapTooltip:SetScale(s.scale) end

  local setOwner = GameTooltip.SetOwner
  GameTooltip.SetOwner = function(self, a1, a2, a3, a4)
    following, fades, fadeStart = false, false, nil
    self:SetAlpha(1)
    return setOwner(self, a1, a2, a3, a4)
  end
  -- Blizzard frames ask for a fade on mouse leave; start ours as well (the original still runs)
  local fadeOut = GameTooltip.FadeOut
  GameTooltip.FadeOut = function(self, a1, a2)
    if not fadeStart then
      fades, fadeStart = true, GetTime()
    end
    if fadeOut then return fadeOut(self, a1, a2) end
  end
  -- a child of the tooltip only runs OnUpdate while the tooltip is showing
  local mover = CreateFrame("Frame", nil, GameTooltip)
  mover:SetScript("OnUpdate", function()
    if following and s.cursor then FollowCursor() end
    Fade(GameTooltip)
  end)

  HookPrices(GameTooltip)
  HookPrices(ItemRefTooltip) -- item links clicked in chat

  S.PostHook("GameTooltip_SetDefaultAnchor", function(tip, parent)
    if tip == GameTooltip then
      Anchor(tip, parent)
      -- a unit out in the world (our own frames pass themselves as parent)
      fades = parent == UIParent and UnitExists("mouseover")
    end
  end)

  holder.options = {
    { label = "Follow cursor", toggle = true, get = function() return s.cursor end, set = function(v) s.cursor = v end },
    { label = "Cursor gap", get = function() return s.offset end,
      set = function(v) s.offset = v end, min = 0, max = 48, step = 2 },
    { label = "Fade out", get = function() return s.fade end,
      set = function(v) s.fade = v end, min = 0, max = FADE_DEFAULT, step = 0.1,
      format = function(v)
        if v > FADE_DEFAULT - 0.05 then return "Game" end
        return string.format("%.1fs", v)
      end },
    { label = "Item prices", toggle = true, get = function() return s.prices end, set = function(v) s.prices = v end },
    { label = "Scale", get = function() return s.scale end,
      set = function(v)
        s.scale = v
        GameTooltip:SetScale(v)
        if WorldMapTooltip then WorldMapTooltip:SetScale(v) end
      end, min = 0.6, max = 1.6, step = 0.05 },
  }
  if S.UpgradeOption then
    table.insert(holder.options, table.getn(holder.options), S:UpgradeOption(s))
  end
end, "Tooltips", "Restyled tooltips with vendor prices, upgrade checks and a movable home.")
