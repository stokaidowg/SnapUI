-- SnapUI world map: OctoWoW's windowed map (the client's own minimize button) in the
-- SnapUI look. Blizzard keeps all the map logic; this turns windowed mode on, swaps the
-- parchment border for a flat panel with a title bar, shows player and cursor coordinates,
-- remembers where you dragged it, and Ctrl+wheel sizes it, Shift+wheel fades it.
-- The + button still gives Blizzard's fullscreen map, and its minimize button comes back here.
-- Reveal draws the areas you haven't explored yet as if you had (title bar button, /snap reveal).

local S = SnapUI
local s
local HEADER, PAD = 22, 4
local INNER = WORLDMAP_WINDOWED_SCALE or 0.7 -- the map's own scale inside the window
local bar, coords, revealButton

local function Windowed()
  return WORLDMAP_WINDOWED == 1
end

-- position as the window's centre in UIParent units, so a new size keeps it in place
local function SavePosition()
  local x, y = WorldMapFrame:GetCenter()
  if x then
    local k = WorldMapFrame:GetScale()
    s.pos = { x * k, y * k }
  end
end

local function Place()
  local k = WorldMapFrame:GetScale()
  WorldMapFrame:ClearAllPoints()
  if s.pos then
    WorldMapFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", s.pos[1] / k, s.pos[2] / k)
  else
    WorldMapFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20 / k)
  end
end

local function TextButton(label, tip, onClick)
  local b = CreateFrame("Button", nil, bar)
  b:SetWidth(18)
  b:SetHeight(18)
  b.text = S.Text(b, 14, "CENTER")
  b.text:SetPoint("CENTER", 0, 0)
  b.text:SetText(label)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function()
    this.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3])
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(tip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    this.text:SetTextColor(1, 1, 1)
    GameTooltip:Hide()
  end)
  return b
end

-- unexplored areas: ClassicAPI's C_Map.GetMapOverlays lists every overlay of the shown zone,
-- explored or not, already cut into tiles. Ours sit on BORDER under Blizzard's own explored
-- overlays (ARTWORK), so only the missing pieces show through.
local revealPool, revealUsed = {}, 0

local function DrawReveal()
  for i = 1, revealUsed do
    revealPool[i]:Hide()
  end
  revealUsed = 0
  if not (s.reveal and C_Map and C_Map.GetMapOverlays) then
    return
  end
  local overlays = C_Map.GetMapOverlays()
  if not overlays then
    return
  end
  for _, overlay in ipairs(overlays) do
    for _, tile in ipairs(overlay.tiles or {}) do
      revealUsed = revealUsed + 1
      local tex = revealPool[revealUsed]
      if not tex then
        tex = WorldMapDetailFrame:CreateTexture(nil, "BORDER")
        revealPool[revealUsed] = tex
      end
      tex:SetTexture(tile.file)
      tex:SetWidth(tile.width)
      tex:SetHeight(tile.height)
      tex:SetTexCoord(0, tile.texCoordX, 0, tile.texCoordY)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPLEFT", tile.offsetX, -tile.offsetY)
      tex:Show()
    end
  end
end

local function PaintRevealButton()
  if revealButton then
    if s.reveal then
      revealButton.text:SetTextColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3])
    else
      revealButton.text:SetTextColor(0.5, 0.5, 0.5)
    end
  end
end

function S:ToggleMapReveal()
  if not s then
    return false
  end
  s.reveal = not s.reveal
  PaintRevealButton()
  if WorldMapFrame:IsShown() then
    WorldMapFrame_Update()
  else
    DrawReveal()
  end
  return s.reveal
end

local function Build()
  -- title bar items live on their own frame so fullscreen mode can drop them in one go
  bar = CreateFrame("Frame", nil, WorldMapFrame)
  bar:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", 0, 0)
  bar:SetHeight(HEADER)
  local band = bar:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints(bar)
  band:SetTexture(S.TEX)
  band:SetVertexColor(0, 0, 0, 0.35)

  local close = TextButton("x", "Close", function() ToggleWorldMap() end)
  close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, -2)
  local full = TextButton("+", "Full screen map", function() WorldMapFrame_Maximize() end)
  full:SetPoint("RIGHT", close, "LEFT", -2, 0)
  revealButton = TextButton("Reveal", "Show unexplored areas", function() S:ToggleMapReveal() end)
  revealButton:SetWidth(44)
  S.SetFont(revealButton.text, 12)
  revealButton:SetPoint("RIGHT", full, "LEFT", -4, 0)
  revealButton:SetScript("OnLeave", function()
    PaintRevealButton()
    GameTooltip:Hide()
  end)
  PaintRevealButton()

  -- player and cursor coordinates: in the title bar when windowed, under the map in fullscreen
  coords = CreateFrame("Frame", nil, WorldMapFrame)
  coords:SetWidth(260)
  coords:SetHeight(16)
  coords.text = S.Text(coords, 12, "RIGHT")
  coords.text:SetAllPoints(coords)
  local t = 0
  coords:SetScript("OnUpdate", function()
    t = t + arg1
    if t < 0.1 then
      return
    end
    t = 0
    local out = ""
    local px, py = GetPlayerMapPosition("player")
    if px and px > 0 then
      out = string.format("|cff%02x%02x%02xYou|r %.1f, %.1f", S.ACCENT[1] * 255, S.ACCENT[2] * 255, S.ACCENT[3] * 255,
        px * 100, py * 100)
    end
    local x, y = GetCursorPosition()
    local k = WorldMapButton:GetEffectiveScale()
    local left, top = WorldMapButton:GetLeft(), WorldMapButton:GetTop()
    local w, h = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
    if left and w > 0 and h > 0 then
      local cx, cy = (x / k - left) / w, (top - y / k) / h
      if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
        out = out .. (out ~= "" and "    " or "") .. string.format("|cffaaaaaaCursor|r %.1f, %.1f", cx * 100, cy * 100)
      end
    end
    this.text:SetText(out)
  end)

  WorldMapFrame:EnableMouseWheel(true)
  WorldMapFrame:SetScript("OnMouseWheel", function()
    if not Windowed() then
      return
    end
    if IsControlKeyDown() then
      SavePosition()
      s.scale = math.max(0.5, math.min(2, s.scale + arg1 * 0.05))
      WorldMapFrame:SetScale(s.scale)
      Place()
    elseif IsShiftKeyDown() then
      s.alpha = math.max(0.2, math.min(1, s.alpha + arg1 * 0.05))
      WorldMapFrame:SetAlpha(s.alpha)
    end
  end)
end

-- after Blizzard's WorldMapFrame_Minimize: our size, look, spot and drag handling
-- the windowed map would otherwise share a layer with unit frames, bars and the guide
-- arrow, and they draw over it; DIALOG keeps it above all of those (tooltips still on top)
local function OnTop()
  WorldMapFrame:SetFrameStrata("DIALOG")
end

local function ApplyWindowed()
  s.windowed = true
  OnTop()
  local w, h = 1002 * INNER, 668 * INNER
  WorldMapFrame:SetScale(s.scale)
  WorldMapFrame:SetAlpha(s.alpha)
  WorldMapFrame:SetWidth(w + 2 * PAD)
  WorldMapFrame:SetHeight(h + HEADER + PAD)
  WorldMapDetailFrame:ClearAllPoints()
  WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", PAD / INNER, -HEADER / INNER)
  S.Backdrop(WorldMapFrame, 0.95)
  for i = 1, 8 do
    local tex = getglobal("WorldMapFrameMinimizedTexture" .. i)
    if tex then
      tex:SetAlpha(0)
    end
  end
  WorldMapFrameCloseButton:Hide()
  WorldMapFrameMaximizeButton:Hide()
  bar:Show()

  S.SetFont(WorldMapFrameTitle, 13)
  WorldMapFrameTitle:ClearAllPoints()
  WorldMapFrameTitle:SetPoint("LEFT", bar, "LEFT", PAD + 4, 0)
  WorldMapFrameTitle:SetJustifyH("LEFT")

  coords:ClearAllPoints()
  coords:SetPoint("RIGHT", revealButton, "LEFT", -6, 0)
  coords:SetFrameLevel(bar:GetFrameLevel() + 1)

  WorldMapFrame:SetScript("OnDragStart", function()
    this:StartMoving()
  end)
  WorldMapFrame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    SavePosition()
    Place()
  end)
  Place()
end

-- after WorldMapFrame_Maximize: Blizzard's fullscreen map, coordinates under it
local function ApplyFull()
  s.windowed = false
  OnTop()
  WorldMapFrame:SetScale(1)
  WorldMapFrame:SetAlpha(1)
  WorldMapFrame:SetBackdrop(nil)
  WorldMapFrameCloseButton:Show()
  bar:Hide()
  WorldMapFrameTitle:SetJustifyH("CENTER")
  coords:ClearAllPoints()
  coords:SetPoint("TOPRIGHT", WorldMapDetailFrame, "BOTTOMRIGHT", 0, -4)
  coords:SetFrameLevel(WorldMapButton:GetFrameLevel() + 5)
end

S:RegisterModule("worldmap", function()
  -- the windowed mode comes with OctoWoW's client; on a plain 1.12 one leave the map alone
  if not (WorldMapFrame and WorldMapFrame_Minimize and WorldMapFrame_Maximize and WorldMapDetailFrame) then
    return
  end
  s = S:Settings("frames", "worldmap", { windowed = true, scale = 1, alpha = 1, reveal = true })
  Build()
  S.PostHook("WorldMapFrame_Minimize", ApplyWindowed)
  S.PostHook("WorldMapFrame_Maximize", ApplyFull)
  S.PostHook("WorldMapFrame_Update", DrawReveal)
  -- and every time it opens, in case the client put it back on its old layer
  local onShow = WorldMapFrame:GetScript("OnShow")
  WorldMapFrame:SetScript("OnShow", function()
    if onShow then onShow() end
    OnTop()
  end)
  if Windowed() then
    -- the client already went windowed at login (it remembers): just restyle it
    ApplyWindowed()
  elseif s.windowed then
    -- with WORLDMAP_WINDOWED already 1, Minimize switches without opening the map
    WORLDMAP_WINDOWED = 1
    WorldMapFrame_Minimize()
  else
    ApplyFull()
  end
end, "World map", "A smaller, movable world map you can walk around with, in the SnapUI look, with player and cursor coordinates. Ctrl+wheel sizes it, Shift+wheel fades it, + for full screen. Reveal shows unexplored areas.")
