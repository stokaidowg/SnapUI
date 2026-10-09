-- SnapUI friend notes: 1.12 has no notes on friends, so SnapUI keeps them. Right-click a friend
-- (online or offline) > Set Note. The note shows on the friend's row in the friends list, on
-- the right of the level/class line, and in full when you hover the row. Kept per character
-- in SnapUIDB.friendNotes, by name.

local S = SnapUI
local NOTE = "SNAPUI_FRIEND_NOTE"
local editing

local function Notes()
  S.root.friendNotes = S.root.friendNotes or {}
  return S.root.friendNotes
end

function S:FriendNote(name)
  return name and Notes()[name]
end

function S:SetFriendNote(name, note)
  if not name then return end
  note = string.gsub(note or "", "^%s*(.-)%s*$", "%1")
  Notes()[name] = note ~= "" and note or nil
  if FriendsFrame:IsVisible() then FriendsList_Update() end
end

local function IsFriend(name)
  for i = 1, GetNumFriends() do
    if GetFriendInfo(i) == name then return true end
  end
end

function S:EditFriendNote(name)
  editing = name
  StaticPopup_Show(NOTE, name)
end

StaticPopupDialogs[NOTE] = {
  text = "Note for %s:",
  button1 = ACCEPT,
  button2 = CANCEL,
  hasEditBox = 1,
  hasWideEditBox = 1,
  maxLetters = 60,
  OnAccept = function()
    S:SetFriendNote(editing, getglobal(this:GetParent():GetName() .. "WideEditBox"):GetText())
  end,
  OnShow = function()
    local box = getglobal(this:GetName() .. "WideEditBox")
    box:SetText(S:FriendNote(editing) or "")
    box:SetFocus()
  end,
  OnHide = function()
    getglobal(this:GetName() .. "WideEditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    S:SetFriendNote(editing, this:GetText())
    this:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- [[ rows ]] --
local function RowEnter()
  local name = GetFriendInfo(this:GetID())
  local note = S:FriendNote(name)
  if not note then return end
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:SetText(name)
  GameTooltip:AddLine(note, 1, 1, 1, 1)
  GameTooltip:AddLine("Right-click > Set Note to change it", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function RowLeave()
  GameTooltip:Hide()
end

local function Row(i)
  local b = getglobal("FriendsFrameFriendButton" .. i)
  if b and not b.snapNote then
    local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    -- the level/class line, right side
    fs:SetPoint("TOPRIGHT", b, "TOPRIGHT", -10, -16)
    fs:SetWidth(150)
    fs:SetHeight(12)
    fs:SetJustifyH("RIGHT")
    fs:SetTextColor(0.65, 0.65, 0.65)
    b.snapNote = fs
    b:SetScript("OnEnter", RowEnter)
    b:SetScript("OnLeave", RowLeave)
  end
  return b
end

local function UpdateRows()
  for i = 1, FRIENDS_TO_DISPLAY or 10 do
    local b = Row(i)
    if b then
      local note = b:IsShown() and S:FriendNote((GetFriendInfo(b:GetID())))
      b.snapNote:SetText(note or "")
    end
  end
end

-- [[ right-click menu ]] --
local function Hook()
  UnitPopupButtons[NOTE] = { text = "Set Note", dist = 0 }
  -- before Cancel in the friend menu (also used for names in chat: hidden there unless a friend)
  local menu = UnitPopupMenus["FRIEND"]
  local at = table.getn(menu) + 1
  for i, v in ipairs(menu) do
    if v == "CANCEL" then at = i break end
  end
  table.insert(menu, at, NOTE)
  -- offline friends get no menu in 1.12: give them one with just the note
  UnitPopupMenus["SNAPUI_FRIEND_OFFLINE"] = { NOTE, "CANCEL" }

  local hide = UnitPopup_HideButtons
  UnitPopup_HideButtons = function()
    hide()
    local menuFrame = getglobal(UIDROPDOWNMENU_INIT_MENU)
    local which = menuFrame and menuFrame.which
    if which ~= "FRIEND" then return end
    for i, v in ipairs(UnitPopupMenus[which]) do
      if v == NOTE and not IsFriend(menuFrame.name) then
        UnitPopupShown[UIDROPDOWNMENU_MENU_LEVEL][i] = 0
      end
    end
  end

  local click = UnitPopup_OnClick
  UnitPopup_OnClick = function()
    if this.value == NOTE then
      local menuFrame = getglobal(UIDROPDOWNMENU_INIT_MENU)
      S:EditFriendNote(menuFrame and menuFrame.name)
      return
    end
    click()
  end

  local show = FriendsFrame_ShowDropdown
  FriendsFrame_ShowDropdown = function(name, connected)
    if connected or not IsFriend(name) then return show(name, connected) end
    HideDropDownMenu(1)
    FriendsDropDown.initialize = function()
      UnitPopup_ShowMenu(getglobal(UIDROPDOWNMENU_OPEN_MENU), "SNAPUI_FRIEND_OFFLINE", nil, FriendsDropDown.name)
    end
    FriendsDropDown.displayMode = "MENU"
    FriendsDropDown.name = name
    ToggleDropDownMenu(1, nil, FriendsDropDown, "cursor")
  end

  local update = FriendsList_Update
  FriendsList_Update = function()
    update()
    UpdateRows()
  end
end

S:RegisterModule("friendnotes", function()
  Hook()
end, "Friend notes", "Notes on friends: right-click a friend > Set Note. Shown on their row in the friends list.")
