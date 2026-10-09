-- SnapUI built-in profiles.
--
-- "Roilorcas UI": Roilorcas' minimalistic healer ElvUI profile (wago.io/rJygU8e-G, v5.5.3,
-- Naowh inspired), rebuilt from its own settings: every size and position below is the
-- ElvUI value at 2560x1440 (ElvUI units are screen pixels there), scaled to this screen.
-- Made once and switched to; /snap config > Profiles > Reset puts it back.
--
-- Also: the twenty retail-style presets that used to live here were removed; the clean-up
-- below deletes their untouched copies from your saved settings.

local S = SnapUI
local ROIL = "Roilorcas UI"

-- [[ builder ]] --
local B = {}
-- fields given in 1440p pixels that become UI units
local PX = { width = true, height = true, power = true, w = true, h = true, barHeight = true, size = true,
  nameX = true, nameY = true, nameSize = true, hpSize = true, textSize = true, zoneSize = true, debuffSize = true,
  arrowSize = true, spacing = true }

local function New(db)
  return setmetatable({ db = db, k = UIParent:GetHeight() / 1440 }, { __index = B })
end

function B:theme(t)
  for key, v in pairs(t) do self.db.theme[key] = v end
end

-- a holder's spot, ElvUI mover style: point, relative point, x, y (1440p px), relative holder
function B:at(key, point, rel, x, y, relTo)
  self.db.pos[key] = { (x or 0) * self.k, (y or 0) * self.k, point = point, rel = rel or point, relTo = relTo }
end

function B:set(group, key, t)
  self.db[group] = self.db[group] or {}
  local dst = self.db[group]
  if key then
    dst[key] = dst[key] or {}
    dst = dst[key]
  end
  for name, v in pairs(t) do
    if PX[name] and type(v) == "number" then
      dst[name] = math.max(name == "spacing" and 0 or 1, math.floor(v * self.k + 0.5))
    else
      dst[name] = v
    end
  end
end

function B:frame(key, t) self:set("frames", key, t) end

-- an action bar: buttons `size` px with `gap` px between them
function B:bar(key, t)
  local s = {}
  for name, v in pairs(t) do s[name] = v end
  if t.size then
    s.scale = math.floor(t.size * self.k / 36 * 1000 + 0.5) / 1000
    s.size = nil
  end
  if t.gap then
    s.spacing = math.floor(t.gap * self.k / (s.scale or 1) + 0.5)
    s.gap = nil
  end
  if s.hidden == nil then s.hidden = false end
  self.db.bars[key] = self.db.bars[key] or {}
  for name, v in pairs(s) do self.db.bars[key][name] = v end
end

function B:raids(t)
  for _, key in ipairs({ "raid", "raid10", "raid25" }) do self:set(key, nil, t) end
end

-- [[ Roilorcas UI ]] --
local function Roilorcas(b)
  local function fs(v) return math.max(6, math.floor(v * b.k + 0.5)) end

  -- Expressway, the "Melli"-like smooth texture, class-coloured health on black, black 1px
  -- borders, ElvUI's blue, class-coloured cast bars
  b:theme(S.CopyTable(S.THEME_DEFAULTS))
  b:theme({ font = "expressway", fontScale = 1, outline = "OUTLINE", bar = "smooth", bg = { 0.06, 0.06, 0.06 }, bgAlpha = 1,
    border = { 0, 0, 0, 1 }, borderStyle = "pixel", shadow = false, strip = false, accent = { 0.09, 0.51, 0.82 },
    accentClass = false, health = "class", barBg = { 0, 0, 0 }, shade = false, nameClass = false, castClass = true,
    castColor = { 0.88, 0.88, 0.88 } })

  -- player 264x60: name on the top edge, current health right, 3D portrait over the bar;
  -- its power is the detached 400x8 bar above the cast bar, buffs (37x28) above that
  b:frame("player", { enabled = true, width = 264, height = 60, power = 0, scale = 1, name = "top", caps = false, nameX = 2,
    nameY = 8, nameSize = 19, hp = "value", hpSize = 19, powerText = "none", mirror = false, reverse = false,
    portrait = "overlay", portrait3d = true, classIcon = false, icons = true, vertical = false, powerWidth = 1 })
  b:at("player", "BOTTOMLEFT", "BOTTOMLEFT", 598, 216)
  b:frame("power", { enabled = true, width = 400, height = 8, text = "percent", vertical = false })
  b:at("power", "BOTTOM", "BOTTOM", 0, 394)
  b:set("bars", "cast", { enabled = true, width = 400, height = 16, icon = false, textSize = 16, alpha = 0.5 })
  b:at("cast", "BOTTOM", "BOTTOM", 0, 368)
  b:frame("playerbuffs", { enabled = true, size = 28, width = 37, spacing = 1, perRow = 7, max = 7, growDown = false,
    growLeft = false, centered = true, durations = true, timedOnly = true })
  b:at("playerbuffs", "BOTTOM", "TOP", 0, 15, "power")
  b:frame("combo", { enabled = true, size = 12, spacing = 3 })
  b:at("combo", "BOTTOM", "BOTTOM", 0, 424)

  -- target 264x60, mirrored and filling from the right, name top-right, health left, a
  -- half-width power strip with its %; debuffs and buffs (37x28, 3 a row) above it
  b:frame("target", { enabled = true, width = 264, height = 60, power = 10, powerWidth = 0.5, scale = 1, name = "top",
    caps = false, nameX = 2, nameY = 8, nameSize = 19, hp = "value", hpSize = 19, powerText = "percent", mirror = true,
    reverse = true, portrait = "overlay", portrait3d = true, classIcon = false, icons = true, vertical = false, level = false })
  b:at("target", "BOTTOMRIGHT", "BOTTOMRIGHT", -598, 211)
  b:frame("targetdebuffs", { enabled = true, size = 28, width = 37, spacing = 1, perRow = 3, max = 6, growDown = false,
    growLeft = false, durations = false })
  b:at("targetdebuffs", "BOTTOMLEFT", "TOPLEFT", 0, 5, "target")
  b:frame("targetbuffs", { enabled = true, size = 28, width = 37, spacing = 1, perRow = 3, max = 6, growDown = false,
    growLeft = false, durations = false })
  b:at("targetbuffs", "BOTTOMLEFT", "TOPLEFT", 0, 1, "targetdebuffs")
  b:frame("targetcast", { enabled = true, width = 264, height = 14, icon = false })
  b:at("targetcast", "BOTTOMRIGHT", "BOTTOMRIGHT", -598, 192)
  b:frame("targetlevel", { size = 14 })

  -- target of target and pet, ElvUI's default sizes
  b:frame("targettarget", { enabled = true, width = 130, height = 36, power = 0, name = "top", nameX = 2, nameY = 8,
    nameSize = 17, hp = "none", mirror = true, reverse = true, portrait = "none" })
  b:at("targettarget", "BOTTOMRIGHT", "BOTTOMRIGHT", -450, 234)
  b:frame("petframe", { enabled = true, width = 264, height = 30, power = 0, name = "top", nameX = 2, nameY = 10,
    nameSize = 17, hp = "value", hpSize = 17, portrait = "none" })
  b:at("petframe", "BOTTOMLEFT", "BOTTOMLEFT", 598, 128)

  -- party 180x50 in a column above the action bars; raids in rows of five, 116x55 (100x43
  -- for 40), names in the top-left corner, filling from the right, growing upwards
  b:set("party", nil, { enabled = true, w = 220, h = 50, spacing = 2, vertical = true, player = true, solo = false,
    text = "none", power = 0, nameSize = 19, namePos = "topleft", nameX = 9, nameY = 8, nameLen = 0, reverse = false, growUp = true })
  b:at("party", "BOTTOM", "BOTTOM", 0, 100)
  b:raids({ enabled = true, w = 116, h = 55, spacing = 2, rows = true, text = "none", power = 5, nameSize = 19,
    namePos = "topleft", nameX = 9, nameY = 9, nameLen = 5, reverse = true, growUp = true })
  b:set("raid", nil, { w = 100, h = 43, nameSize = 16 })
  for _, key in ipairs({ "raid", "raid10", "raid25" }) do
    b:at(key, "BOTTOM", "BOTTOM", 0, 58)
  end

  -- action bars: 10+10 small buttons at the bottom centre, no keybind or macro text; three
  -- buttons to the left, a 3-wide block to the right, two on the left edge on mouseover
  local plain = { hotkeys = false, macros = false, cooldowns = true, empty = true }
  local function Bar(key, t)
    for k2, v in pairs(plain) do if t[k2] == nil then t[k2] = v end end
    b:bar(key, t)
  end
  Bar("bar1", { buttons = 10, perRow = 10, size = 28, gap = 1 })
  b:at("bar1", "BOTTOM", "BOTTOM", 0, 0)
  Bar("bar2", { buttons = 10, perRow = 10, size = 28, gap = 1 })
  b:at("bar2", "BOTTOM", "BOTTOM", 0, 29)
  Bar("bar3", { buttons = 3, perRow = 6, size = 28, gap = 1 })
  b:at("bar3", "BOTTOM", "BOTTOM", -200, 1)
  Bar("bar4", { buttons = 12, perRow = 3, size = 28, gap = 1 })
  b:at("bar4", "BOTTOM", "BOTTOM", 365, 1)
  Bar("bar5", { buttons = 2, perRow = 1, size = 28, gap = 1, fade = "mouseover", fadeAlpha = 0 })
  b:at("bar5", "BOTTOMLEFT", "BOTTOMLEFT", 1, 316)
  b:bar("stance", { buttons = 5, perRow = 5, size = 28, gap = 1 })
  b:at("stance", "BOTTOMLEFT", "BOTTOMLEFT", 598, 277)
  b:bar("pet", { size = 28, gap = 1, hidden = true })
  b:at("pet", "BOTTOMLEFT", "BOTTOMLEFT", 598, 160)
  b:bar("micro", { scale = math.floor(21 * b.k / 26 * 1000 + 0.5) / 1000, fade = "mouseover", fadeAlpha = 0 })
  b:at("micro", "BOTTOMRIGHT", "BOTTOMRIGHT", -342, 1)
  b:bar("bags", { hidden = true })
  b:set("bars", "xp", { width = 400, height = 8, hidden = false })
  b:at("xp", "TOP", "TOP", 0, 0)

  -- chat bottom-left with no background, its datatext line under it (spec, durability, gold)
  b:frame("chat", { width = 516, height = 222, alpha = 0, menu = false })
  b:at("chat", "BOTTOMLEFT", "BOTTOMLEFT", 1, 24)
  b:frame("chatinput", { width = 0 })
  b:frame("info1", { enabled = true, width = 526, height = 22, count = 3, alpha = 0, transparent = true, textSize = 14,
    slots = { "talents", "durability", "gold", "time", "xp", "coords", "friends", "guild" } })
  b:at("info1", "BOTTOMLEFT", "BOTTOMLEFT", 1, 1)
  for n = 2, 3 do b:frame("info" .. n, { enabled = false }) end

  -- 194px square minimap top-right with the zone inside its top edge, time and friends under it
  b:frame("minimap", { scale = math.floor(194 * b.k / 140 * 100 + 0.5) / 100, round = false, zone = true, zoneSize = 18,
    zoneBelow = false, collect = true })
  b:at("minimap", "TOPRIGHT", "TOPRIGHT", -4, -4)
  b:frame("info3", { enabled = true, width = 196, height = 20, count = 2, alpha = 0.6, transparent = false, textSize = 14,
    slots = { "time", "friends" } })
  b:at("info3", "TOP", "BOTTOM", 0, -1, "minimap")

  -- buffs 36px left of the minimap, debuffs under them
  b:frame("buffs", { boxed = true, scale = math.floor(36 * b.k / 30 * 100 + 0.5) / 100, perRow = 12, spacing = 1,
    growLeft = true, growDown = true, durations = true })
  b:at("buffs", "TOPRIGHT", "TOPRIGHT", -206, -4)
  b:frame("debuffs", { scale = math.floor(36 * b.k / 30 * 100 + 0.5) / 100, perRow = 12, spacing = 1, growLeft = true,
    growDown = true, durations = true })
  b:at("debuffs", "TOPRIGHT", "TOPRIGHT", -206, -115)

  -- Details-style meters bottom-right: Healing Done over Damage Done, no background; the
  -- tooltip just above them, the quest tracker down the right side
  b:frame("meters", { ids = { 1, 2 }, nextId = 3 })
  b:frame("meter", { width = 324, rows = 5, barHeight = 25, scale = 1, alpha = 0, hidden = false, mode = "damage", segment = "current" })
  b:at("meter", "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 1)
  b:frame("meter2", { width = 324, rows = 5, barHeight = 25, scale = 1, alpha = 0, hidden = false, mode = "healing", segment = "current" })
  b:at("meter2", "BOTTOMRIGHT", "TOPRIGHT", 0, 4, "meter")
  b:frame("tooltip", { cursor = false })
  b:at("tooltip", "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 302)
  b:at("questwatch", "TOPRIGHT", "TOPRIGHT", -59, -292)
  b:at("durability", "BOTTOMLEFT", "BOTTOMLEFT", 176, 300)
  b:frame("bags", { columns = 12, size = 36, scale = 1, enabled = true })
  b:at("bagwindow", "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 1)
  for n = 1, 4 do b:frame("panel" .. n, { enabled = false }) end

  -- nameplates 170 wide, 20 tall: name top-left, health % top-right, level under the bar,
  -- yellow arrows round the target
  b:frame("nameplates", { width = 170, height = 20, nameSize = 15, hpSize = 20, style = "elvui", hpText = true, level = true,
    arrows = true, arrowSize = 26, castbar = true, debuffs = true, maxDebuffs = 4, debuffSize = 33, classColors = true })

  b:frame("auto", { sellJunk = true, repair = true, hideErrors = true })
end

S.PRESETS = { { name = ROIL, short = "Roilorcas' healer ElvUI profile",
  desc = "Roilorcas' minimalistic healer profile for ElvUI (Naowh inspired), rebuilt from its own settings: frames and " ..
    "raid grid low in the middle, small bars at the bottom, no-background chat and meters, square minimap.",
  fn = Roilorcas } }

function S:PresetFor(name)
  if name == ROIL then return S.PRESETS[1] end
end

function S:BuildPreset(p)
  local db = { pos = {}, frames = {}, bars = {}, theme = {}, modules = {}, party = {}, raid = {} }
  p.fn(New(db))
  db.style = S.STYLE_VERSION or 1
  db.builtFrom = p.name
  db.grid, db.snap = 16, true
  return db
end

function S:ResetPreset(name)
  local p = self:PresetFor(name)
  if not p then
    return false
  end
  self.root.profiles[name] = self:BuildPreset(p)
  return true
end

-- [[ at login ]] --
local function OwnProfile(root)
  if root.profiles["Raid/Dungeon"] then
    return "Raid/Dungeon"
  end
  for name, p in pairs(root.profiles) do
    if not p.presetName then
      return name
    end
  end
end

local function Use(self, name)
  self.root.profile = name
  self.db = self.root.profiles[name]
  self.db.modules = self.db.modules or {}
end

-- core calls this at login, before the theme is applied and any module builds itself
function S:EnsurePresets()
  local root = self.root

  -- the old presets go (only copies still marked as an untouched preset)
  if root.presets then
    local removed = 0
    for name in pairs(root.presets) do
      local p = root.profiles[name]
      if p and p.presetName == name then
        root.profiles[name] = nil
        removed = removed + 1
      end
    end
    root.presets = nil
    if removed > 0 then
      S.Print("removed the " .. removed .. " preset profiles")
    end
  end

  -- Roilorcas UI is made once and switched to
  if not root.roilorcasMade then
    root.roilorcasMade = true
    if not root.profiles[ROIL] then
      root.profiles[ROIL] = self:BuildPreset(S.PRESETS[1])
    end
    Use(self, ROIL)
    S.Print("made the |cff4fc3f7" .. ROIL .. "|r profile and switched to it. |cff4fc3f7/snap config|r > Profiles to go back.")
  end

  if not root.profiles[root.profile] then
    local own = OwnProfile(root)
    if not own then
      own = "Raid/Dungeon"
      root.profiles[own] = { pos = {}, frames = {}, bars = {}, party = {}, raid = {} }
    end
    Use(self, own)
  end
end
