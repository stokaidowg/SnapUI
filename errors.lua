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
end
