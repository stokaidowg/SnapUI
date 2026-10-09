-- SnapUI chat: restyles Blizzard's chat windows to match (flat dark panel with a thin
-- border, text-only tabs, flat input box, SnapUI font), drops the scroll/menu buttons in
-- favour of mouse-wheel scrolling, and lets edit mode move and resize the main window.

local S = SnapUI
local s, holder
local inputSettings, inputHolder

local function Strip(name)
  local t = getglobal(name)
  if t and t.SetTexture then
    t:SetTexture(nil)
  end
end

local function StyleWindow(i)
  local f = getglobal("ChatFrame" .. i)
  if not f or f.snapStyled then
    return
  end
  f.snapStyled = true
  local name = f:GetName()

  -- Blizzard's own background and resize-border art
  for _, suffix in ipairs({ "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
    "TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }) do
    Strip(name .. suffix)
  end
  for _, suffix in ipairs({ "ResizeTopLeft", "ResizeTopRight", "ResizeBottomLeft", "ResizeBottomRight",
    "ResizeTop", "ResizeBottom", "ResizeLeft", "ResizeRight" }) do
    Strip(name .. suffix .. "Texture")
  end

  local bg = CreateFrame("Frame", nil, f)
  bg:SetPoint("TOPLEFT", -5, 5)
  bg:SetPoint("BOTTOMRIGHT", 5, -5)
  bg:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
  S.Backdrop(bg, s.alpha)
  f.snapBg = bg

  -- text-only tabs
  local tab = getglobal(name .. "Tab")
  if tab then
    for _, suffix in ipairs({ "Left", "Middle", "Right", "Highlight" }) do
      Strip(name .. "Tab" .. suffix)
    end
    local text = getglobal(name .. "TabText")
    if text then
      text:SetFont(S.FONT, 12, "OUTLINE")
    end
  end

  -- wheel scrolling replaces the arrow buttons; Shift jumps to top/bottom
  for _, suffix in ipairs({ "UpButton", "DownButton", "BottomButton" }) do
    S.Kill(getglobal(name .. suffix))
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function()
    if arg1 > 0 then
      if IsShiftKeyDown() then this:ScrollToTop() else this:ScrollUp() end
    else
      if IsShiftKeyDown() then this:ScrollToBottom() else this:ScrollDown() end
    end
  end)

  -- Blizzard keeps chat windows clamped inside the screen with a margin; the holder already
  -- keeps it on screen, so let the window sit flush against the edge
  f:SetClampedToScreen(false)

  local _, size = f:GetFont()
  f:SetFont(S.FONT, size or 13, "")
  f:SetShadowOffset(1, -1)
end

local function StyleEditBox()
  local e = ChatFrameEditBox
  if not e then
    return
  end
  -- every piece of Blizzard's border art, whatever this client calls it (done before our
  -- backdrop goes on, so that isn't caught too); text regions stay
  for _, r in ipairs({ e:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "Texture" then
      r:SetTexture(nil)
      r:Hide()
    end
  end
  S.PixelBackdrop(e)
  e:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
  S.ResetBorder(e)
  e:SetFont(S.FONT, 13, "")
  local header = getglobal("ChatFrameEditBoxHeader")
  if header then
    header:SetFont(S.FONT, 13, "")
  end
end

-- the input box sits in its own holder so edit mode can move it anywhere
-- the input line is open (Enter pressed)
local function Typing()
  return ChatFrameEditBox and ChatFrameEditBox:IsShown() and true or false
end

local function ApplyEditBox()
  local e = ChatFrameEditBox
  if not e or not inputHolder then
    return
  end
  local w = inputSettings.width
  if not w or w <= 0 then
    w = s.width + 10 -- follow the chat window's width
  end
  -- just the text over the game, or a dark box with a border
  if inputSettings.background then
    local bg = S.theme and S.theme.bg or { 0.05, 0.05, 0.05 }
    e:SetBackdropColor(bg[1], bg[2], bg[3], 0.9)
    S.ResetBorder(e)
  else
    e:SetBackdropColor(0, 0, 0, 0)
    -- the line only shows while typing, so "border while typing" is just its border
    if s.typingBorder then
      S.ResetBorder(e)
    else
      e:SetBackdropBorderColor(0, 0, 0, 0)
    end
  end
  inputHolder:SetWidth(w)
  inputHolder:SetHeight(24)
  e:ClearAllPoints()
  e:SetPoint("TOPLEFT", inputHolder, "TOPLEFT", 0, 0)
  e:SetPoint("BOTTOMRIGHT", inputHolder, "BOTTOMRIGHT", 0, 0)
end

local function Apply()
  ChatFrame1:ClearAllPoints()
  ChatFrame1:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 5, 5)
  ChatFrame1:SetWidth(s.width)
  ChatFrame1:SetHeight(s.height)
  holder:SetWidth(s.width + 10)
  holder:SetHeight(s.height + 10)
  for i = 1, NUM_CHAT_WINDOWS or 7 do
    local f = getglobal("ChatFrame" .. i)
    if f and f.snapBg then
      local bg = S.theme and S.theme.bg or { 0.05, 0.05, 0.05 }
      f.snapBg:SetBackdropColor(bg[1], bg[2], bg[3], s.alpha * (S.theme and S.theme.bgAlpha or 1))
      -- the edge (and a thick or shadowed theme's extra edges) can go on its own, and come
      -- back while you're typing
      local edge = s.border or (s.typingBorder and Typing())
      if edge then
        S.ResetBorder(f.snapBg)
      else
        f.snapBg:SetBackdropBorderColor(0, 0, 0, 0)
      end
      for _, extra in ipairs({ f.snapBg.snapInner, f.snapBg.snapShadow }) do
        if edge then extra:Show() else extra:Hide() end
      end
    end
  end
  ApplyEditBox()
end

S:RegisterModule("chat", function()
  s = S:Settings("frames", "chat", { width = ChatFrame1:GetWidth(), height = ChatFrame1:GetHeight(), alpha = 0.55, menu = false, border = true, typingBorder = true })
  holder = S:Holder("chat", "Chat", { "BOTTOMLEFT", nil, 8, 26 }, {})
  -- the chat windows and tabs fade with the box; it stays up while you're typing
  holder.fadeFrames = {}
  for i = 1, NUM_CHAT_WINDOWS or 7 do
    for _, name in ipairs({ "ChatFrame" .. i, "ChatFrame" .. i .. "Tab" }) do
      local f = getglobal(name)
      if f then table.insert(holder.fadeFrames, f) end
    end
  end
  holder.forceShow = function() return ChatFrameEditBox and ChatFrameEditBox:IsVisible() end

  if UIPARENT_MANAGED_FRAME_POSITIONS then
    UIPARENT_MANAGED_FRAME_POSITIONS["ChatFrame1"] = nil
    UIPARENT_MANAGED_FRAME_POSITIONS["ChatFrame2"] = nil
  end

  for i = 1, NUM_CHAT_WINDOWS or 7 do
    StyleWindow(i)
  end
  StyleEditBox()
  if not s.menu and ChatFrameMenuButton then
    ChatFrameMenuButton:Hide()
  end

  local function Opt(label, key, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[key] end, set = function(v) s[key] = v; Apply() end, min = min, max = max, step = step })
  end
  Opt("Width", "width", 200, 900, 10)
  Opt("Height", "height", 60, 500, 10)
  Opt("Background", "alpha", 0, 1, 0.05)
  table.insert(holder.options, { label = "Border", toggle = true, get = function() return s.border end,
    set = function(v) s.border = v; Apply() end })
  table.insert(holder.options, { label = "Border while typing", toggle = true, get = function() return s.typingBorder end,
    set = function(v) s.typingBorder = v; Apply() end })
  table.insert(holder.options, { label = "Chat menu button", toggle = true, get = function() return s.menu end,
    set = function(v) s.menu = v; if v then ChatFrameMenuButton:Show() else ChatFrameMenuButton:Hide() end end })

  -- width 0 = same width as the chat window; by default it sits just above the chat
  inputSettings = S:Settings("frames", "chatinput", { width = 0, background = false })
  inputHolder = S:Holder("chatinput", "Chat input", { "BOTTOMLEFT", "TOPLEFT", 0, 23, holder }, {})
  inputHolder.noFade = true
  table.insert(inputHolder.options, { label = "Background and border", toggle = true,
    get = function() return inputSettings.background end, set = function(v) inputSettings.background = v; ApplyEditBox() end })
  table.insert(inputHolder.options, { label = "Width (0 = chat)", get = function() return inputSettings.width end,
    set = function(v) inputSettings.width = v; ApplyEditBox() end, min = 0, max = 900, step = 10 })
  -- put it back in its box whenever it opens, in case Blizzard moved it
  if ChatFrameEditBox then
    local onShow = ChatFrameEditBox:GetScript("OnShow")
    ChatFrameEditBox:SetScript("OnShow", function()
      if onShow then onShow() end
      Apply()
    end)
    -- and the typing borders go again when it closes
    local onHide = ChatFrameEditBox:GetScript("OnHide")
    ChatFrameEditBox:SetScript("OnHide", function()
      if onHide then onHide() end
      Apply()
    end)
  end

  Apply()
  -- Blizzard restores saved chat positions after login and on some UI changes
  S.PostHook("UIParent_ManageFramePositions", Apply)
  S.PostHook("FCF_RestorePositionAndDimensions", Apply)
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("UPDATE_CHAT_WINDOWS")
  events:SetScript("OnEvent", function()
    for i = 1, NUM_CHAT_WINDOWS or 7 do
      StyleWindow(i)
    end
    Apply()
  end)
end, "Chat", "Restyled chat windows, tabs and input box.")
