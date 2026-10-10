-- SnapUI error log: every Lua error is kept (with a short stack) in SnapUIDB.errors, so it
-- survives a reload and can be read from SavedVariables afterwards. Repeats of the same
-- error just bump its count. Errors that mention SnapUI print one line in chat (at most
-- every few seconds); /snap errors lists them, /snap errors all includes other addons',
-- /snap errors clear empties the log. Blizzard's own error handling still runs after ours.
-- Loaded straight after core.lua so it's in place before the other files run.

local S = SnapUI
local MAX = 40
local pending = {} -- errors from before SavedVariables loaded
local lastNotice = 0

local function Log()
  if type(SnapUIDB) ~= "table" then
    return nil
  end
  SnapUIDB.errors = SnapUIDB.errors or {}
  local log = SnapUIDB.errors
  for _, e in ipairs(pending) do
    table.insert(log, e)
  end
  pending = {}
  return log
end

local function Now()
  return date and date("%m-%d %H:%M:%S") or ""
end

local function Record(msg)
  msg = tostring(msg or "?")
  local stack = debugstack and debugstack(3, 6, 0) or ""
  local mine = string.find(msg, "SnapUI", 1, true) or string.find(stack, "SnapUI", 1, true)
  local log = Log()
  local list = log or pending
  for _, e in ipairs(list) do
    if e.msg == msg then
      e.count = (e.count or 1) + 1
      e.last = Now()
      return
    end
  end
  table.insert(list, { msg = msg, stack = stack, count = 1, first = Now(), last = Now(), snap = mine and true or nil })
  while table.getn(list) > MAX do
    table.remove(list, 1)
  end
  local t = GetTime and GetTime() or 0
  if mine and t - lastNotice > 5 and DEFAULT_CHAT_FRAME then
    lastNotice = t
    local short = string.gsub(msg, "^Interface\\AddOns\\", "")
    if string.len(short) > 140 then short = string.sub(short, 1, 140) .. "..." end
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7SnapUI|r |cffff6060error:|r " .. short .. "  |cff888888(/snap errors)|r")
  end
end

if seterrorhandler then
  local previous = geterrorhandler and geterrorhandler()
  seterrorhandler(function(msg)
    -- never let the logger itself get in the way of the real handler
    if pcall then pcall(Record, msg) else Record(msg) end
    if previous then
      return previous(msg)
    end
  end)
end

function S:ErrorsCommand(arg)
  local log = Log() or pending
  if arg == "clear" then
    for i = table.getn(log), 1, -1 do
      table.remove(log, i)
    end
    S.Print("error log cleared")
    return
  end
  local all = arg == "all"
  local shown = 0
  for i = table.getn(log), 1, -1 do
    local e = log[i]
    if all or e.snap then
      shown = shown + 1
      if shown <= 8 then
        S.Print(string.format("|cffff6060x%d|r |cff888888%s|r %s", e.count or 1, e.last or "", e.msg))
      end
    end
  end
  if shown == 0 then
    S.Print(all and "no Lua errors logged" or "no SnapUI errors logged (/snap errors all for every addon)")
  elseif shown > 8 then
    S.Print(string.format("...and %d older (all %d are in SavedVariables\\SnapUI.lua)", shown - 8, shown))
  end
  if shown > 0 then
    S.Print("|cff888888/snap bug: a report to copy into a GitHub issue|r")
  end
end

-- [[ /snap bug ]] --
-- A copyable report for a GitHub issue: versions of our add-ons, the client build, your class
-- and level (no name or realm), and the most recent errors with their stacks. The text is
-- selected when the window opens, so Ctrl+C copies it.
local OURS = { "SnapUI", "SnapGuide", "SnapAuction", "PallyLite", "HitNumbers", "pfQuestGuide" }

function S:BugReport()
  local lines = {}
  local function add(s) table.insert(lines, s) end
  local version, build = "?", "?"
  if GetBuildInfo then version, build = GetBuildInfo() end
  add("Client: " .. tostring(version) .. " (" .. tostring(build) .. ")")
  local _, class = UnitClass("player")
  add("Character: level " .. tostring(UnitLevel("player")) .. " " .. tostring(UnitRace("player")) .. " " .. tostring(class))
  local ours = {}
  for _, name in ipairs(OURS) do
    if IsAddOnLoaded and IsAddOnLoaded(name) then
      local v = GetAddOnMetadata and GetAddOnMetadata(name, "Version")
      table.insert(ours, name .. " " .. tostring(v or "?"))
    end
  end
  add("Our add-ons: " .. (table.getn(ours) > 0 and table.concat(ours, ", ") or "none loaded"))
  local others = {}
  if GetNumAddOns then
    for i = 1, GetNumAddOns() do
      local name = GetAddOnInfo(i)
      local mine = false
      for _, o in ipairs(OURS) do if o == name then mine = true end end
      if not mine and IsAddOnLoaded(i) then table.insert(others, name) end
    end
  end
  add("Other add-ons: " .. (table.getn(others) > 0 and table.concat(others, ", ") or "none"))
  add("")
  local log = Log() or pending
  if table.getn(log) == 0 then
    add("No Lua errors logged.")
  else
    add("Errors, newest first:")
    local shown = 0
    for i = table.getn(log), 1, -1 do
      local e = log[i]
      shown = shown + 1
      if shown > 10 then break end
      add("")
      add(string.format("x%d (%s .. %s) %s", e.count or 1, e.first or "", e.last or "", tostring(e.msg)))
      if e.stack and e.stack ~= "" then add(e.stack) end
    end
  end
  return table.concat(lines, "\n")
end

local bugFrame
function S:ShowBugReport()
  if not bugFrame then
    local f = CreateFrame("Frame", "SnapUIBugReport", UIParent)
    f:SetWidth(560)
    f:SetHeight(380)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    S.Panel(f, 0.95)
    table.insert(UISpecialFrames, "SnapUIBugReport")

    local title = S.Text(f, 13, "LEFT")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("|cff4fc3f7SnapUI|r bug report: press Ctrl+C to copy, then paste it into a GitHub issue")

    local close = CreateFrame("Button", nil, f)
    close:SetWidth(18)
    close:SetHeight(18)
    close:SetPoint("TOPRIGHT", -3, -2)
    close.text = S.Text(close, 13, "CENTER")
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3]) end)
    close:SetScript("OnLeave", function() this.text:SetTextColor(1, 1, 1) end)

    local scroll = CreateFrame("ScrollFrame", "SnapUIBugReportScroll", f)
    scroll:SetPoint("TOPLEFT", 8, -28)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function()
      local max = this:GetVerticalScrollRange() or 0
      local v = (this:GetVerticalScroll() or 0) - arg1 * 40
      if v < 0 then v = 0 elseif v > max then v = max end
      this:SetVerticalScroll(v)
    end)

    local box = CreateFrame("EditBox", "SnapUIBugReportText", scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetWidth(540)
    box:SetHeight(340)
    box:SetFontObject(ChatFontNormal)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    -- keep the report as it is: typing puts it back
    box:SetScript("OnTextChanged", function()
      if this.report and this:GetText() ~= this.report then
        this:SetText(this.report)
        this:HighlightText()
      end
    end)
    scroll:SetScrollChild(box)
    f.box = box
    bugFrame = f
  end
  local text = self:BugReport()
  bugFrame.box.report = text
  bugFrame.box:SetText(text)
  bugFrame:Show()
  bugFrame.box:SetFocus()
  bugFrame.box:HighlightText()
end
