-- SnapUI hover-to-show: any element can stay hidden until the mouse is over it (or until
-- combat), and elements can be linked into groups so hovering one shows them all (hover the
-- chat and the info bar under it appears too). Settings live per profile in
-- db.visibility[<holder name>] = { mode, group, alpha }:
--   mode  "always" | "mouseover" | "combat" (mouseover, and always in combat)
--   group 0 = on its own, 1-8 = linked with every other element in that group
--   alpha how see-through it is while hidden (0 = invisible)
-- Fading sets the alpha of the element's box (which carries most elements) and of any
-- frames a module registers in holder.fadeFrames (chat windows, minimap, cast bar...).

local S = SnapUI

local MODES = { { "always", "Always" }, { "mouseover", "On mouseover" }, { "combat", "On mouseover or in combat" } }
local GROUPS = { { 0, "Not linked" } }
for i = 1, 8 do table.insert(GROUPS, { i, "Group " .. i }) end

local LINGER = 0.5 -- seconds it stays after the mouse leaves
local SPEED = 6    -- alpha per second while fading

function S:Visibility(h)
  self.db.visibility = self.db.visibility or {}
  local v = self.db.visibility[h.name]
  if not v then
    v = { mode = "always", group = 0, alpha = 0 }
    self.db.visibility[h.name] = v
  end
  return v
end

local function Over(h)
  if MouseIsOver(h) then
    return true
  end
  for _, f in ipairs(h.fadeFrames or {}) do
    if f:IsVisible() and MouseIsOver(f) then
      return true
    end
  end
  return false
end

local function SetAlpha(h, a)
  h:SetAlpha(a)
  for _, f in ipairs(h.fadeFrames or {}) do
    f:SetAlpha(a)
  end
end

local tracked, groupSeen = {}, {}

local function Driver()
  local dt = arg1
  local now = GetTime()
  local editing = S:IsEditing()
  local combat = UnitAffectingCombat("player")

  -- which groups have the mouse on one of their members (or a member that must show)
  local hot = {}
  for _, h in ipairs(tracked) do
    local v = S:Visibility(h)
    if v.group and v.group > 0 then
      if Over(h) or (h.forceShow and h.forceShow()) then
        hot[v.group] = true
      end
    end
  end
  for g in pairs(hot) do
    groupSeen[g] = now
  end

  for _, h in ipairs(tracked) do
    local v = S:Visibility(h)
    local target = 1
    if v.mode ~= "always" and not editing then
      local show = Over(h) or (h.forceShow and h.forceShow()) or (v.mode == "combat" and combat)
      if v.group and v.group > 0 and groupSeen[v.group] and now - groupSeen[v.group] < LINGER then
        show = true
      end
      if show then
        h.vSeen = now
      elseif h.vSeen and now - h.vSeen < LINGER then
        show = true
      end
      target = show and 1 or (v.alpha or 0)
    end
    local a = h.vAlpha or 1
    if a ~= target then
      if a < target then
        a = math.min(target, a + SPEED * dt)
      else
        a = math.max(target, a - SPEED * dt)
      end
      h.vAlpha = a
      SetAlpha(h, a)
    end
  end
end

-- called by core once every module has made its boxes
function S:AttachVisibility()
  for _, h in ipairs(self.holders) do
    if not h.noFade then
      local holder = h
      local v = self:Visibility(holder)
      holder.options = holder.options or {}
      table.insert(holder.options, { label = "Show", choices = MODES, get = function() return v.mode end,
        set = function(x) v.mode = x end })
      table.insert(holder.options, { label = "Link group", choices = GROUPS, get = function() return v.group or 0 end,
        set = function(x) v.group = x end })
      table.insert(holder.options, { label = "Hidden opacity", get = function() return v.alpha or 0 end,
        set = function(x) v.alpha = x end, min = 0, max = 1, step = 0.1 })
      table.insert(tracked, holder)
    end
  end
  local f = CreateFrame("Frame", "SnapUI_Visibility")
  f:SetScript("OnUpdate", Driver)
end
