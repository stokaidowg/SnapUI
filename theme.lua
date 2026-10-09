-- SnapUI theme: the look every module draws with. A profile's `theme` table picks the font,
-- bar texture, panel and border colours, border style (pixel / thick / none), drop shadows,
-- BenikUI-style accent strips, and how health bars are coloured. The shared helpers in core
-- (S.Backdrop, S.Text, S.StatusBar) read it, so a theme change reaches every module.
-- Themes apply at login; switching profile or theme reloads the UI.

local S = SnapUI
local M = "Interface\\AddOns\\SnapUI\\media\\"

-- [[ media ]] --
-- { key, label, path }
S.FONTS = {
  { "expressway", "Expressway", M .. "Expressway.ttf" },
  { "ptsans", "PT Sans Narrow", M .. "PT-Sans-Narrow-Regular.ttf" },
  { "ptsansbold", "PT Sans Narrow Bold", M .. "PT-Sans-Narrow-Bold.ttf" },
  { "friz", "Friz Quadrata (Blizzard)", "Fonts\\FRIZQT__.TTF" },
  { "arialn", "Arial Narrow", "Fonts\\ARIALN.TTF" },
  { "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF" },
  { "skurri", "Skurri", "Fonts\\skurri.ttf" },
  { "bignoodle", "Big Noodle Titling", M .. "BigNoodleTitling.ttf" },
  { "continuum", "Continuum", M .. "Continuum.ttf" },
  { "homespun", "Homespun (pixel)", M .. "Homespun.ttf" },
  { "hooge", "Hooge (pixel)", M .. "Hooge.ttf" },
  { "roboto", "Roboto Mono", M .. "RobotoMono.ttf" },
  { "diediedie", "Die Die Die", M .. "DieDieDie.ttf" },
}
S.BARS = {
  { "flat", "Flat", "Interface\\Buttons\\WHITE8X8" },
  { "elvui", "ElvUI Norm", M .. "bar_elvui.tga" },
  { "tukui", "Tukui", M .. "bar_tukui.tga" },
  { "smooth", "Smooth", M .. "bar.tga" },
  { "gradient", "Gradient", M .. "bar_gradient.tga" },
  { "striped", "Striped", M .. "bar_striped.tga" },
  { "blizzard", "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
}
S.GLOW = M .. "glow2.tga"
S.CLASS_ICONS = M .. "classicons.tga"
S.CLASS_ICON_COORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 },
}

local function Find(list, key)
  for _, m in ipairs(list) do
    if m[1] == key then return m end
  end
  return list[1]
end
function S.FontPath(key) return Find(S.FONTS, key)[3] end
function S.BarPath(key) return Find(S.BARS, key)[3] end

-- [[ the theme ]] --
S.THEME_DEFAULTS = {
  font = "expressway",
  fontScale = 1,
  outline = "OUTLINE",        -- "", "OUTLINE", "THICKOUTLINE"
  bar = "flat",
  bg = { 0.05, 0.05, 0.05 },  -- panel colour
  bgAlpha = 1,                -- multiplies every panel's own transparency
  border = { 0, 0, 0, 1 },
  borderStyle = "pixel",      -- "pixel", "thick" (Tukui: dark, light, dark), "none"
  shadow = false,
  shadowAlpha = 0.7,
  strip = false,              -- BenikUI: a thin accent line along the top of panels
  accent = { 0.31, 0.76, 0.97 },
  accentClass = false,        -- accent in your class colour instead
  barBg = { 0.12, 0.12, 0.12 },
  shade = true,               -- soft dark gradient over bars
  health = "class",           -- "class", "dark", "gradient", "blizzard", "custom"
  healthCustom = { 0.8, 0.15, 0.15 },
  classBackdrop = false,      -- dark mode: the missing part of the bar in class colour
  nameClass = false,          -- class-coloured names on unit frames
  castColor = nil,            -- nil = accent; { r, g, b } for one fixed colour
  castClass = false,          -- your cast bar in your class colour
}

local function Copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and Copy(v) or v
  end
  return c
end
S.CopyTable = Copy

-- fill in missing theme fields (each profile has its own theme table)
function S:ThemeFor(db)
  db.theme = db.theme or {}
  for k, v in pairs(S.THEME_DEFAULTS) do
    if db.theme[k] == nil then
      db.theme[k] = type(v) == "table" and Copy(v) or v
    end
  end
  return db.theme
end

-- called by core once the profile is loaded, before any module builds itself
function S:ApplyTheme()
  local t = self:ThemeFor(self.db)
  self.theme = t
  self.FONT = S.FontPath(t.font)
  self.TEX = "Interface\\Buttons\\WHITE8X8"
  self.BAR = S.BarPath(t.bar)
  if t.accentClass then
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
      self.ACCENT[1], self.ACCENT[2], self.ACCENT[3] = c.r, c.g, c.b
    end
  else
    self.ACCENT[1], self.ACCENT[2], self.ACCENT[3] = t.accent[1], t.accent[2], t.accent[3]
  end
  local size = t.borderStyle == "none" and 0 or 1
  self.BACKDROP = {
    bgFile = self.TEX, tile = false, tileSize = 0,
    edgeFile = size > 0 and self.TEX or nil, edgeSize = size,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
end

-- [[ pixel-exact edges ]] --
-- A border 1 UI unit wide covers 1 or 2 screen pixels depending on where it lands (at 1080p
-- and a 0.92 UI scale a unit is ~1.29 pixels), so some sides look thicker. An edge exactly
-- one screen pixel wide always covers exactly one pixel. That size depends on the frame's
-- own effective scale, so every bordered frame is remembered and re-measured after layout
-- changes (bars and unit frames get scaled after they're made).
local bordered = {}
setmetatable(bordered, { __mode = "k" })
local backdrops = {}

local function ScreenHeight()
  local res = GetCVar and GetCVar("gxResolution")
  local _, _, _, h = string.find(res or "", "(%d+)x(%d+)")
  return tonumber(h) or 768
end

-- one screen pixel in the frame's own units
function S.Pixel(frame)
  local eff = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  if not eff or eff <= 0 then eff = 1 end
  return 768 / ScreenHeight() / eff
end

local function BackdropFor(edge, withBg)
  local key = (withBg and "b" or "e") .. math.floor(edge * 10000 + 0.5)
  if not backdrops[key] then
    backdrops[key] = {
      bgFile = withBg and S.TEX or nil, tile = false, tileSize = 0,
      edgeFile = edge > 0 and S.TEX or nil, edgeSize = edge,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
  end
  return backdrops[key]
end

-- set (or re-set) a frame's backdrop with a one-pixel edge, keeping its colours
local function ApplyEdge(frame)
  local info = bordered[frame]
  local edge = info.none and 0 or S.Pixel(frame)
  if info.edge and math.abs(info.edge - edge) < 0.0005 then
    return
  end
  info.edge = edge
  frame:SetBackdrop(BackdropFor(edge, info.bg))
  -- SetBackdrop resets the colours: put back the last ones set (remembered below, so this
  -- doesn't rely on GetBackdropColor existing on 1.12)
  if info.bgc then info.setBg(frame, info.bgc[1], info.bgc[2], info.bgc[3], info.bgc[4]) end
  if info.bdc then info.setBd(frame, info.bdc[1], info.bdc[2], info.bdc[3], info.bdc[4]) end
end

-- what every module calls instead of SetBackdrop(S.BACKDROP)
function S.PixelBackdrop(frame, edgeOnly)
  if not bordered[frame] then
    -- remember every colour set on it, through its own methods
    local info = {}
    info.setBg, info.setBd = frame.SetBackdropColor, frame.SetBackdropBorderColor
    frame.SetBackdropColor = function(self, r, g, b, a) info.bgc = { r, g, b, a }; info.setBg(self, r, g, b, a) end
    frame.SetBackdropBorderColor = function(self, r, g, b, a) info.bdc = { r, g, b, a }; info.setBd(self, r, g, b, a) end
    bordered[frame] = info
  end
  bordered[frame].bg = not edgeOnly
  bordered[frame].none = S.theme and S.theme.borderStyle == "none" and not edgeOnly
  bordered[frame].edge = nil
  ApplyEdge(frame)
end

-- re-measure everything (after a layout change, or a new scale)
function S.FixPixels()
  for frame in pairs(bordered) do
    ApplyEdge(frame)
  end
end

local pixelDriver = CreateFrame("Frame")
pixelDriver:SetScript("OnUpdate", function()
  if S.pixelDirty then
    S.pixelDirty = nil
    S.FixPixels()
  end
end)
pixelDriver:RegisterEvent("PLAYER_ENTERING_WORLD")
pixelDriver:SetScript("OnEvent", function() S.pixelDirty = true end)

-- [[ drawing helpers ]] --
function S.BorderColor()
  local b = S.theme and S.theme.border or { 0, 0, 0, 1 }
  return b[1], b[2], b[3], b[4] or 1
end

-- put a frame's border back to the theme colour (after a highlight)
function S.ResetBorder(frame)
  frame:SetBackdropBorderColor(S.BorderColor())
end

local function Shadow(frame)
  if frame.snapShadow then
    return
  end
  local s = CreateFrame("Frame", nil, frame)
  s:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
  s:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
  s:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
  s:SetBackdrop({ edgeFile = S.GLOW, edgeSize = 5, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
  s:SetBackdropBorderColor(0, 0, 0, S.theme.shadowAlpha)
  frame.snapShadow = s
end

-- Tukui's thick border: the 1px dark edge, a 1px light line inside it, then dark again
local function Thick(frame)
  if frame.snapInner then
    return
  end
  local px = S.Pixel(frame)
  local i = CreateFrame("Frame", nil, frame)
  i:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
  i:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
  i:SetFrameLevel(frame:GetFrameLevel())
  S.PixelBackdrop(i, true)
  i:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  local o = CreateFrame("Frame", nil, frame)
  o:SetPoint("TOPLEFT", frame, "TOPLEFT", 2 * px, -2 * px)
  o:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2 * px, 2 * px)
  o:SetFrameLevel(frame:GetFrameLevel())
  S.PixelBackdrop(o, true)
  o:SetBackdropBorderColor(0, 0, 0, 1)
  frame.snapInner = i
end

-- the dark panel with its border; `alpha` is the panel's own see-through-ness
function S.Backdrop(frame, alpha)
  local t = S.theme or S.THEME_DEFAULTS
  S.PixelBackdrop(frame)
  frame:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], (alpha or 0.85) * t.bgAlpha)
  frame:SetBackdropBorderColor(S.BorderColor())
  if t.borderStyle == "thick" and (alpha or 0.85) > 0 then
    Thick(frame)
  end
  if t.shadow and (alpha or 0.85) > 0 then
    Shadow(frame)
  end
end

-- a bigger panel (unit frames, windows, info bars): Backdrop plus the BenikUI strip
function S.Panel(frame, alpha)
  S.Backdrop(frame, alpha)
  if S.theme and S.theme.strip and not frame.snapStrip then
    local strip = frame:CreateTexture(nil, "OVERLAY")
    strip:SetTexture(S.TEX)
    strip:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
    strip:SetHeight(3)
    strip:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
    frame.snapStrip = strip
  end
end

function S.FontFlags()
  return S.theme and S.theme.outline or "OUTLINE"
end

function S.FontSize(size)
  local scale = S.theme and S.theme.fontScale or 1
  return math.max(6, math.floor((size or 12) * scale + 0.5))
end

-- set a font string in the theme font
function S.SetFont(fs, size, flags)
  fs:SetFont(S.FONT, S.FontSize(size), flags or S.FontFlags())
  if (flags or S.FontFlags()) == "" then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
  end
end

-- [[ bars that fill from the right ]] --
-- 1.12 status bars only fill left to right. A reversed bar keeps its own value and colour
-- (so all the usual calls still work) but draws its fill as a texture anchored to the right.
local function UpdateReverse(bar)
  local min, max = bar:GetMinMaxValues()
  local frac = max > min and (bar:GetValue() - min) / (max - min) or 0
  frac = math.max(0, math.min(1, frac))
  local w = bar:GetWidth()
  if frac <= 0 or w <= 0 then
    bar.rfill:Hide()
    return
  end
  bar.rfill:SetWidth(math.max(0.5, w * frac))
  bar.rfill:SetTexCoord(1 - frac, 1, 0, 1)
  bar.rfill:Show()
end

function S.SetReverse(bar, on)
  on = on and true or false
  if on == (bar.snapReverse or false) then
    return
  end
  if not bar.rfill then
    local t = bar:CreateTexture(nil, "ARTWORK")
    t:SetTexture(S.BAR or S.TEX)
    t:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.rfill = t
    bar.snapSetValue, bar.snapSetMinMax, bar.snapSetColor = bar.SetValue, bar.SetMinMaxValues, bar.SetStatusBarColor
  end
  bar.snapReverse = on
  if on then
    bar:SetStatusBarTexture("")
    bar.SetValue = function(self, v) self.snapSetValue(self, v); UpdateReverse(self) end
    bar.SetMinMaxValues = function(self, a, b) self.snapSetMinMax(self, a, b); UpdateReverse(self) end
    bar.SetStatusBarColor = function(self, r, g, b, a)
      self.snapSetColor(self, r, g, b, a)
      self.rfill:SetVertexColor(r, g, b, a or 1)
    end
    UpdateReverse(bar)
  else
    bar.SetValue, bar.SetMinMaxValues, bar.SetStatusBarColor = bar.snapSetValue, bar.snapSetMinMax, bar.snapSetColor
    bar:SetStatusBarTexture(S.BAR or S.TEX)
    bar.rfill:Hide()
  end
end

-- [[ health colours ]] --
local REACTION = {
  hostile = { 0.85, 0.2, 0.2 },
  neutral = { 0.95, 0.8, 0.25 },
  friendly = { 0.25, 0.75, 0.3 },
  tapped = { 0.5, 0.5, 0.5 },
}
S.REACTION = REACTION

-- class colour for players, reaction colour for everything else
function S.UnitColor(unit)
  if UnitIsPlayer(unit) then
    local _, class = UnitClass(unit)
    return S.CLASS[class] or REACTION.friendly
  end
  if UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) then
    return REACTION.tapped
  end
  local r = UnitReaction(unit, "player") or 4
  if r <= 3 then
    return REACTION.hostile
  elseif r == 4 then
    return REACTION.neutral
  end
  return REACTION.friendly
end

-- red at empty, yellow at half, green at full
function S.GradientColor(frac)
  frac = math.max(0, math.min(1, frac or 1))
  if frac < 0.5 then
    return { 1, frac * 2, 0 }
  end
  return { 2 - frac * 2, 1, 0 }
end

local DARK = { 0.22, 0.22, 0.22 }
local GREEN = { 0, 0.8, 0 }

-- colour a health bar (and its background) for `unit` at `frac` health, by the theme
function S.ColorHealth(bar, unit, frac)
  local t = S.theme or S.THEME_DEFAULTS
  local mode = t.health
  local c
  if mode == "dark" then
    c = DARK
  elseif mode == "gradient" then
    c = S.GradientColor(frac)
  elseif mode == "blizzard" then
    c = GREEN
  elseif mode == "custom" then
    c = t.healthCustom
  else
    c = S.UnitColor(unit)
  end
  bar:SetStatusBarColor(c[1], c[2], c[3])
  if bar.bg then
    if mode == "dark" and t.classBackdrop then
      local u = S.UnitColor(unit)
      bar.bg:SetVertexColor(u[1] * 0.6, u[2] * 0.6, u[3] * 0.6, 1)
    else
      bar.bg:SetVertexColor(t.barBg[1], t.barBg[2], t.barBg[3], 1)
    end
  end
end

-- the colour for a unit's name text
function S.NameColor(unit)
  if S.theme and (S.theme.nameClass or S.theme.health == "dark") then
    local c = S.UnitColor(unit)
    return c[1], c[2], c[3]
  end
  return 1, 1, 1
end
