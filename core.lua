-- SnapUI core: shared helpers, saved settings and "holders".
-- Every element (bar, unit frame, group grid...) sits inside a holder. Holders are the
-- things edit mode drags around and snaps to the grid; positions are saved per character
-- as offsets of the holder's centre from the screen centre.

SnapUI = {}
local S = SnapUI

-- Expressway (copied from pfUI's fonts) gives the condensed ReatUI/ElvUI look
S.FONT = "Interface\\AddOns\\SnapUI\\media\\Expressway.ttf"
S.TEX = "Interface\\Buttons\\WHITE8X8"
S.ACCENT = { 0.31, 0.76, 0.97 }
S.holders = {}
S.byName = {}
S.modules = {}

S.BACKDROP = {
  bgFile = S.TEX, tile = false, tileSize = 0,
  edgeFile = S.TEX, edgeSize = 1,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local DEFAULTS = {
  pos = {},
  grid = 16,
  snap = true,
  bars = {},
  frames = {},
  party = { w = 90, h = 38, spacing = 3, vertical = true, player = true, solo = false },
  raid = { w = 64, h = 34, spacing = 2 },
}

function S.noop() end

function S.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7SnapUI|r: " .. msg)
end

-- [[ look ]] --
function S.Backdrop(frame, alpha)
  frame:SetBackdrop(S.BACKDROP)
  frame:SetBackdropColor(0.05, 0.05, 0.05, alpha or 0.85)
  frame:SetBackdropBorderColor(0, 0, 0, 1)
end

function S.Text(parent, size, justify, layer)
  local t = parent:CreateFontString(nil, layer or "OVERLAY")
  if S.SetFont then
    S.SetFont(t, size or 12)
  else
    t:SetFont(S.FONT, size or 12, "OUTLINE")
  end
  t:SetJustifyH(justify or "LEFT")
  return t
end

function S.StatusBar(parent)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetStatusBarTexture(S.BAR or S.TEX)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(bar)
  bar.bg:SetTexture(S.BAR or S.TEX)
  local bb = S.theme and S.theme.barBg or { 0.12, 0.12, 0.12 }
  bar.bg:SetVertexColor(bb[1], bb[2], bb[3], 1)
  -- texts go on .over so they sit above the shading
  bar.over = CreateFrame("Frame", nil, bar)
  bar.over:SetAllPoints(bar)
  local shade = bar.over:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints(bar.over)
  shade:SetTexture(S.TEX)
  if shade.SetGradientAlpha and not (S.theme and S.theme.shade == false) then
    shade:SetGradientAlpha("VERTICAL", 0, 0, 0, 0.35, 0, 0, 0, 0)
  else
    shade:Hide()
  end
  return bar
end

-- turn a Blizzard frame off for good
function S.Kill(frame)
  if not frame then
    return
  end
  frame:UnregisterAllEvents()
  frame:Hide()
  frame.Show = S.noop
end

-- hooksecurefunc doesn't exist on 1.12; post-hook a global function
function S.PostHook(name, fn)
  local orig = getglobal(name)
  if not orig then
    return
  end
  setglobal(name, function(a1, a2, a3, a4, a5, a6, a7, a8)
    local r1, r2, r3 = orig(a1, a2, a3, a4, a5, a6, a7, a8)
    fn(a1, a2, a3, a4, a5, a6, a7, a8)
    return r1, r2, r3
  end)
end

-- 1.12 Blizzard functions read the global `this`; call one as if `frame` raised it
function S.CallAs(frame, fn, a1)
  local old = this
  this = frame
  fn(a1)
  this = old
end

S.CLASS = {}
for class, c in pairs(RAID_CLASS_COLORS or {}) do
  S.CLASS[class] = { c.r, c.g, c.b }
end

S.POWER = {
  [0] = { 0.2, 0.45, 0.95 }, -- mana
  [1] = { 0.85, 0.2, 0.2 },  -- rage
  [2] = { 0.95, 0.6, 0.2 },  -- focus
  [3] = { 0.95, 0.85, 0.25 }, -- energy
}

function S.ShortNumber(n)
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 10000 then
    return string.format("%.0fK", n / 1000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  end
  return tostring(n)
end

-- [[ holders ]] --
function S:Holder(name, label, default, options)
  local h = CreateFrame("Frame", "SnapUIHolder_" .. name, UIParent)
  h:SetWidth(50)
  h:SetHeight(20)
  h.name = name
  h.label = label
  h.default = default
  h.options = options
  table.insert(self.holders, h)
  self.byName[name] = h
  self:Place(h)
  return h
end

function S:Place(h)
  h:ClearAllPoints()
  local p = self.db.pos[h.name]
  if p and p.point then
    -- a preset spot: a point of the holder pinned to a point of the screen (or of another
    -- holder), in UI units. NormalizePositions turns it into a centre offset after login.
    local rel = p.relTo and self.byName[p.relTo] or UIParent
    h:SetPoint(p.point, rel, p.rel or p.point, p[1] or 0, p[2] or 0)
  elseif p then
    h:SetPoint("CENTER", UIParent, "CENTER", p[1], p[2])
  else
    -- default = { point, relative point, x, y, relative frame (UIParent if left out) }
    local d = h.default
    h:SetPoint(d[1], d[5] or UIParent, d[2] or d[1], d[3] or 0, d[4] or 0)
  end
end

-- size the holder to whatever it carries (which may be scaled)
function S:Fit(h, element, w, ht)
  S.pixelDirty = true
  local scale = element:GetScale()
  h:SetWidth(math.max(8, (w or element:GetWidth()) * scale))
  h:SetHeight(math.max(8, (ht or element:GetHeight()) * scale))
  -- holders that grow downwards keep their top edge where it is: the saved position
  -- remembers the height it was saved at and the centre moves by half the difference
  local dir = (h.growDown and 1) or (h.growUp and -1)
  local p = dir and self.db.pos[h.name]
  if p and not p.point then
    local nh = h:GetHeight()
    if p[3] and p[3] ~= nh then
      p[2] = p[2] + dir * (p[3] - nh) / 2
      self:Place(h)
    end
    p[3] = nh
  end
  if self.OnHolderResized then
    self.OnHolderResized(h)
  end
end

-- every preset (anchored) spot becomes an ordinary centre offset once all holders exist
-- and have their real sizes, so edit mode and everything else only ever see one format
local function CenterOf(h)
  local x, y = h:GetCenter()
  local cx, cy = UIParent:GetCenter()
  if not x or not cx then
    return nil
  end
  return x - cx, y - cy
end

function S:NormalizePositions()
  -- place every anchored holder again now that the holders they hang from exist; a few
  -- passes, so a chain (debuffs on buffs on the minimap) settles whatever order they were made in
  for _ = 1, 4 do
    for _, h in ipairs(self.holders) do
      local p = self.db.pos[h.name]
      if p and p.point then
        self:Place(h)
      end
    end
  end
  local done = {}
  for _, h in ipairs(self.holders) do
    local p = self.db.pos[h.name]
    if p and p.point then
      local x, y = CenterOf(h)
      if x then
        done[h.name] = { math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10, (h.growDown or h.growUp) and h:GetHeight() or nil }
      end
    end
  end
  for name, p in pairs(done) do
    self.db.pos[name] = p
  end
  for _, h in ipairs(self.holders) do
    if done[h.name] then
      self:Place(h)
    end
  end
end

function S:SavePosition(h, x, y)
  self.db.pos[h.name] = { x, y }
end

function S:ResetPositions()
  self.db.pos = {}
  for _, h in ipairs(self.holders) do
    self:Place(h)
  end
end

-- [[ settings ]] --
local function Merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then
        dst[k] = {}
      end
      Merge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- per-element settings with defaults, e.g. S:Settings("bars", "bar1", {buttons = 12})
function S:Settings(group, key, defaults)
  self.db[group][key] = self.db[group][key] or {}
  Merge(self.db[group][key], defaults)
  return self.db[group][key]
end

-- label/desc are for the settings window; required modules can't be switched off
function S:RegisterModule(name, init, label, desc, required)
  table.insert(self.modules, { name = name, init = init, label = label, desc = desc, required = required })
end

function S:ModuleEnabled(name)
  return not (self.db.modules and self.db.modules[name] == false)
end

-- [[ ReatUI layout ]] --
-- Sizes and spots measured off a 1920x1080 ReatUI screenshot and scaled to this screen:
-- compact centre with the action bar between player and target, a power bar under it,
-- the group grid below, side bar blocks, buffs top-left, square minimap top-right.
local STYLE_VERSION = 1
S.STYLE_VERSION = STYLE_VERSION

-- screen maths for the presets: k turns 1080p pixels into UI units, At() a 1080p point
-- into an offset from the screen centre, Scale() the bar scale for 30px buttons
local function Geometry()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local k = H / 1080
  local g = { W = W, H = H, k = k }
  function g.Px(n) return math.floor(n * k + 0.5) end
  function g.At(x, y) return { (x - 960) * k, (540 - y) * k } end
  -- bar scale that makes a 36-unit button `px` pixels wide at 1080p
  function g.ButtonScale(px) return math.floor(px * k / 36 * 100 + 0.5) / 100 end
  g.scale = g.ButtonScale(30)
  return g
end

-- the Solo profile: the same layout without party/raid frames, the three action bars
-- stacked at the bottom of the screen above the XP bar, with bigger 42px buttons
local SOLO_VERSION = 2
local SOLO_BUTTON = 42

function S:ApplySoloLayout(db)
  db = db or self.db
  local g = Geometry()
  db.party.enabled = false
  -- every raid size (group.lua copies "raid" into raid10/raid25 if they don't exist yet)
  for _, key in ipairs({ "raid", "raid10", "raid25", "pets", "tanks" }) do
    if db[key] then db[key].enabled = false end
  end
  for _, key in ipairs({ "bar1", "bar2", "bar3" }) do
    db.bars[key] = db.bars[key] or {}
    db.bars[key].perRow = 12
    db.bars[key].spacing = 2
    db.bars[key].scale = g.ButtonScale(SOLO_BUTTON)
    db.bars[key].hidden = false
  end
  -- bottom up from just above the XP bar, one button height plus a 2px gap per row
  local row = SOLO_BUTTON + 2
  local bottom = 1070 - SOLO_BUTTON / 2
  db.pos.bar1 = g.At(960, bottom)
  db.pos.bar2 = g.At(960, bottom - row)
  db.pos.bar3 = g.At(960, bottom - 2 * row)
  db.preset = "solo"
  db.soloVersion = SOLO_VERSION
end

function S:ApplyReatLayout(db)
  db = db or self.db
  local g = Geometry()
  local W, H, k, Px, At = g.W, g.H, g.k, g.Px, g.At
  local function Set(group, key, values)
    db[group][key] = db[group][key] or {}
    for name, v in pairs(values) do
      db[group][key][name] = v
    end
  end

  -- 30px buttons whatever the UI scale
  local scale = g.scale

  Set("frames", "player", { width = Px(222), height = Px(34), power = 0, scale = 1, enabled = true })
  Set("frames", "target", { width = Px(222), height = Px(34), power = 0, scale = 1, enabled = true, level = true })
  Set("frames", "power", { width = Px(369), height = Px(10), enabled = true })
  Set("frames", "targetcast", { width = Px(200), height = Px(18), icon = true, enabled = true })
  Set("bars", "cast", { width = Px(240), height = Px(22), icon = true, enabled = true })
  Set("bars", "bar1", { buttons = 12, perRow = 12, spacing = 1, scale = scale, hidden = false })
  Set("bars", "bar2", { buttons = 12, perRow = 6, spacing = 1, scale = scale, hidden = false })
  Set("bars", "bar3", { buttons = 12, perRow = 6, spacing = 1, scale = scale, hidden = false })
  Set("bars", "stance", { scale = scale, spacing = 1 })
  Set("bars", "pet", { scale = scale, spacing = 1 })
  Set("bars", "xp", { width = Px(468), height = Px(6) })
  for _, key in ipairs({ "raid", "raid10", "raid25" }) do
    if db[key] then
      for name, v in pairs({ w = Px(92), h = Px(38), spacing = 2, rows = true }) do db[key][name] = v end
    end
  end
  for name, v in pairs({ w = Px(92), h = Px(38), spacing = 2, vertical = false, player = true }) do db.party[name] = v end

  local pos = db.pos
  pos.player = At(656, 722)
  pos.target = At(1264, 722)
  pos.bar1 = At(960, 695)
  pos.power = At(960, 719)
  pos.cast = At(960, 655)
  pos.targetcast = At(1264, 668)
  pos.stance = At(656, 668)
  pos.pet = At(960, 620)
  pos.party = At(960, 769)
  -- the raid grid grows down from its top edge (see S:Fit): give the top and a height of 0
  local top = At(960, 750)
  pos.raid = { top[1], top[2], 0 }
  pos.raid10 = { top[1], top[2], 0 }
  pos.raid25 = { top[1], top[2], 0 }
  pos.bar2 = At(622, 880)
  pos.bar3 = At(1298, 880)
  pos.xp = At(960, 1075)
  -- flush in the top-right corner: the holder is the square map plus its 1px border
  local half = ((Minimap and Minimap:GetWidth() or 140) + 2) / 2
  pos.minimap = { W / 2 - half, H / 2 - half }
  -- given as the old 340x110 buffs box with its right edge left of centre; buffs.lua turns
  -- that into the same top-right corner for the buttons-sized box (the "boxed" step)
  pos.buffs = { (600 - 960) * k - 170, H / 2 - 61 }
  if db.frames.buffs then
    db.frames.buffs.boxed = nil
  end

  db.style = STYLE_VERSION
  if db.preset == "solo" then
    self:ApplySoloLayout(db)
  end
end

-- [[ profiles ]] --
-- SnapUIDB = { profile = "<active>", profiles = { [name] = <settings> }, welcomed = ... }
-- S.db is the active profile, so modules never need to know about profiles. Switching
-- reloads the UI because every module builds itself from the settings at login.
local RAID, SOLO = "Raid/Dungeon", "Solo"

local function Copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and Copy(v) or v
  end
  return c
end

function S:ProfileNames()
  local names = {}
  for name in pairs(self.root.profiles) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- exact name, else case-insensitive, else the first name that starts with it
function S:FindProfile(name)
  if self.root.profiles[name] then
    return name
  end
  local lower = string.lower(name)
  for _, n in ipairs(self:ProfileNames()) do
    if string.lower(n) == lower then return n end
  end
  for _, n in ipairs(self:ProfileNames()) do
    if string.find(string.lower(n), lower, 1, true) == 1 then return n end
  end
end

function S:SetProfile(name)
  self.root.profile = name
  ReloadUI()
end

function S:CopyProfile(name)
  self.root.profiles[name] = Copy(self.db)
end

function S:DeleteProfile(name)
  self.root.profiles[name] = nil
end

local function LoadProfiles()
  SnapUIDB = SnapUIDB or {}
  local root = SnapUIDB
  if not root.profiles then
    -- an older single layout becomes the Raid/Dungeon profile
    local old = {}
    for k, v in pairs(root) do
      if k ~= "welcomed" then old[k] = v end
    end
    for k in pairs(old) do
      root[k] = nil
    end
    root.profiles = { [RAID] = old }
    root.profile = RAID
  end
  if not root.profile or not root.profiles[root.profile] then
    root.profile = next(root.profiles) or RAID
    root.profiles[root.profile] = root.profiles[root.profile] or {}
  end
  for _, p in pairs(root.profiles) do
    Merge(p, DEFAULTS)
  end
  S.root = root
  S.db = root.profiles[root.profile]
  S.db.modules = S.db.modules or {}
  if S.ApplyTheme then
    S:ApplyTheme()
  end
end

-- [[ boot ]] --
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "SnapUI" then
    LoadProfiles()
  elseif event == "PLAYER_LOGIN" then
    if (S.db.style or 0) < STYLE_VERSION then
      S:ApplyReatLayout()
      S.Print("switched to the ReatUI layout. |cff4fc3f7/snap|r to adjust anything.")
    end
    -- older Solo profiles pick up layout changes (e.g. bigger bars)
    for _, p in pairs(S.root.profiles) do
      if p.preset == "solo" and (p.soloVersion or 0) < SOLO_VERSION then
        S:ApplySoloLayout(p)
      end
    end
    -- one-off: a Solo copy of the raid profile
    local base = S.root.profiles[RAID] or S.db
    if not S.root.soloMade and (base.style or 0) >= STYLE_VERSION then
      S.root.soloMade = true
      if not S.root.profiles[SOLO] then
        S.root.profiles[SOLO] = Copy(base)
        S:ApplySoloLayout(S.root.profiles[SOLO])
        S.Print("made a |cff4fc3f7Solo|r profile (no group frames, bars at the bottom). |cff4fc3f7/snap profile solo|r to use it.")
      end
    end
    -- the preset profiles (profiles.lua) exist from the first login on
    if S.EnsurePresets then
      local ok, err = pcall(S.EnsurePresets, S)
      if not ok then
        S.Print("|cffff5050presets failed:|r " .. tostring(err))
      end
    end
    -- the class colour accent needs the player, which exists by now
    if S.ApplyTheme then
      S:ApplyTheme()
    end
    for _, m in ipairs(S.modules) do
      if m.required or S:ModuleEnabled(m.name) then
        local ok, err = pcall(m.init)
        if not ok then
          S.Print("|cffff5050" .. m.name .. " failed:|r " .. tostring(err))
        end
      end
    end
    local ok, err = pcall(S.NormalizePositions, S)
    if not ok then
      S.Print("|cffff5050positions failed:|r " .. tostring(err))
    end
    if S.FixPixels then
      pcall(S.FixPixels)
    end
    if S.AttachVisibility then
      ok, err = pcall(S.AttachVisibility, S)
      if not ok then
        S.Print("|cffff5050hover-to-show failed:|r " .. tostring(err))
      end
    end
    if not S.root.welcomed then
      S.root.welcomed = true
      S.Print("loaded. Type |cff4fc3f7/snap|r to move things around.")
    end
  end
end)

-- [[ combat text names ]] --
-- With SuperWoW the default floating combat text names healers by GUID ("+84 [0x0000...]").
-- Swap the GUID for the unit's name, or drop the bracket if the unit isn't known.
local function FixCombatText()
  if not CombatText_AddMessage or S.combatTextFixed then
    return
  end
  S.combatTextFixed = true
  local orig = CombatText_AddMessage
  CombatText_AddMessage = function(message, a, b, c, d, e, f)
    if message then
      local _, _, hex = string.find(message, "%[(0x%x+)%]")
      if hex then
        local name = UnitName(hex)
        if name then
          message = string.gsub(message, hex, name)
        else
          message = string.gsub(message, "%s*%[" .. hex .. "%]", "")
        end
      end
    end
    return orig(message, a, b, c, d, e, f)
  end
end

local ct = CreateFrame("Frame")
ct:RegisterEvent("ADDON_LOADED")
ct:RegisterEvent("PLAYER_LOGIN")
ct:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" or arg1 == "Blizzard_CombatText" then
    FixCombatText()
  end
end)

SLASH_SNAPUI1 = "/snap"
SLASH_SNAPUI2 = "/snapui"
local function ProfileCommand(args)
  local _, _, sub, name = string.find(args, "^(%S*)%s*(.-)%s*$")
  local lsub = string.lower(sub or "")
  if lsub == "" then
    local list = {}
    for _, n in ipairs(S:ProfileNames()) do
      table.insert(list, n == S.root.profile and ("|cff4fc3f7" .. n .. "|r") or n)
    end
    S.Print("profiles: " .. table.concat(list, ", "))
    S.Print("/snap profile <name>  switch (reloads)   /snap profile copy <name>   /snap profile delete <name>")
  elseif lsub == "copy" and name ~= "" then
    S:CopyProfile(name)
    S.Print("copied |cff4fc3f7" .. S.root.profile .. "|r to |cff4fc3f7" .. name .. "|r")
  elseif lsub == "delete" and name ~= "" then
    local found = S:FindProfile(name)
    if not found then
      S.Print("no profile called " .. name)
    elseif found == S.root.profile then
      S.Print("can't delete the profile you're using")
    else
      S:DeleteProfile(found)
      S.Print("deleted " .. found)
    end
  else
    local found = S:FindProfile(args)
    if not found then
      S.Print("no profile called " .. args)
    elseif found ~= S.root.profile then
      S:SetProfile(found)
    end
  end
end

SlashCmdList["SNAPUI"] = function(msg)
  local _, _, rest = string.find(msg or "", "^%s*[Pp][Rr][Oo][Ff][Ii][Ll][Ee]%s*(.-)%s*$")
  if rest then
    ProfileCommand(rest)
    return
  end
  msg = string.lower(msg or "")
  local _, _, roleArg = string.find(msg, "^%s*role%s*(%a*)%s*$")
  if roleArg and S.RoleCommand then
    S:RoleCommand(roleArg)
    return
  end
  if (msg == "bug" or msg == "report") and S.ShowBugReport then
    S:ShowBugReport()
    return
  end
  local _, _, errArg = string.find(msg, "^%s*errors?%s*(%a*)%s*$")
  if errArg and S.ErrorsCommand then
    S:ErrorsCommand(errArg)
    return
  end
  if (msg == "config" or msg == "options" or msg == "settings") and S.ToggleConfig then
    S:ToggleConfig()
    return
  elseif (msg == "kb" or msg == "keybind" or msg == "bind") and S.ToggleKeybind then
    S:ToggleKeybind()
    return
  end
  if msg == "reset" then
    S:ResetPositions()
    S.Print("everything moved back to its default spot")
  elseif msg == "debug" then
    -- where the UI thinks the screen is, for when things won't reach an edge
    local function Rect(f)
      return string.format("%s L%.0f B%.0f W%.0f H%.0f scale %.3f", f:GetName(), f:GetLeft() or -1, f:GetBottom() or -1,
        f:GetWidth(), f:GetHeight(), f:GetEffectiveScale())
    end
    S.Print(Rect(UIParent))
    S.Print(Rect(WorldFrame))
    local l, r, b, t = S.ScreenBounds()
    S.Print(string.format("screen bounds L%.0f R%.0f B%.0f T%.0f, profile %s", l, r, b, t, S.root.profile))
    -- anything still drawing on the chat input box
    if ChatFrameEditBox then
      local names = {}
      for _, f in ipairs({ ChatFrameEditBox:GetChildren() }) do
        table.insert(names, (f:GetName() or "?") .. (f:IsShown() and "" or " (hidden)"))
      end
      for _, r in ipairs({ ChatFrameEditBox:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r:IsShown() then
          table.insert(names, "texture " .. (r:GetName() or "?"))
        end
      end
      S.Print("chat input parts: " .. (table.getn(names) > 0 and table.concat(names, ", ") or "none"))
    end
  elseif msg == "reat" then
    S:ApplyReatLayout()
    ReloadUI()
  elseif (msg == "cooldowns" or msg == "keybinds" or msg == "macros") and S.ToggleBarText then
    local key = ({ cooldowns = "cooldowns", keybinds = "hotkeys", macros = "macros" })[msg]
    local on = S:ToggleBarText(key)
    S.Print(msg .. " " .. (on and "shown" or "hidden") .. " on all action bars")
  elseif msg == "reveal" and S.ToggleMapReveal then
    local on = S:ToggleMapReveal()
    S.Print("world map " .. (on and "shows unexplored areas" or "hides unexplored areas again"))
  elseif msg == "cursor" and S.ToggleTooltipCursor then
    local on = S:ToggleTooltipCursor()
    S.Print("tooltip " .. (on and "follows the cursor" or "opens at its Tooltip box"))
  elseif msg == "help" then
    S.Print("/snap  toggle edit mode (drag to move, right-click for options, Shift-drag to skip snapping)")
    S.Print("/snap config  the settings window (also in the Esc menu): every element's settings, profiles, theme, modules")
    S.Print("/snap kb  keybind mode: hover a button and press a key")
    S.Print("/snap reset  put everything back where it started")
    S.Print("/snap reat  re-apply this profile's ReatUI layout (reloads)")
    S.Print("/snap profile  list profiles, switch, copy or delete")
    S.Print("/snap cooldowns | keybinds | macros  show or hide that text on all action bars")
    S.Print("/snap reveal  show or hide unexplored areas on the world map")
    S.Print("/snap cursor  tooltip follows the mouse cursor, or goes back to its box")
    S.Print("/snap role tank | healer | dps | auto  your target's role icon (or Alt-right-click a party/raid cell)")
    S.Print("/snap errors  recent SnapUI Lua errors (all: every addon, clear: empty the log)")
    S.Print("/snap bug  a report of versions and recent errors to copy into a GitHub issue")
  else
    S:ToggleEdit()
  end
end

-- update notices (version.lua)
if SnapVersions then SnapVersions.Register("SnapUI") end
