-- SnapUI panels: plain themed backgrounds you can place anywhere, for the big bottom "art"
-- panel of SpartanUI or MayronUI, Tukui's boxes behind the chat and the action bars, LUI's
-- side panels and so on. Four of them, all off until a profile (or you) turns one on.
-- They sit on the lowest layer, so bars, frames and chat draw on top of them.

local S = SnapUI

local function CreatePanel(n)
  local key = "panel" .. n
  local s = S:Settings("frames", key, { enabled = false, width = 420, height = 140, alpha = 0.7, strip = false, border = true })
  local holder = S:Holder(key, "Panel " .. n, { "BOTTOM", nil, 0, 0 }, {})
  holder.isOff = function() return not s.enabled end
  local f = CreateFrame("Frame", "SnapUI_" .. key, holder)
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  f:SetFrameStrata("BACKGROUND")
  f:SetFrameLevel(1)
  f.accent = f:CreateTexture(nil, "OVERLAY")
  f.accent:SetTexture(S.TEX)
  f.accent:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  f.accent:SetHeight(2)

  local function Layout()
    f:SetWidth(s.width)
    f:SetHeight(s.height)
    S.Backdrop(f, s.alpha)
    if not s.border then
      f:SetBackdropBorderColor(0, 0, 0, 0)
    end
    f.accent:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
    if s.strip then f.accent:Show() else f.accent:Hide() end
    if s.enabled then f:Show() else f:Hide() end
    S:Fit(holder, f)
  end
  local function Num(label, k, min, max, step)
    table.insert(holder.options, { label = label, get = function() return s[k] end, set = function(v) s[k] = v; Layout() end, min = min, max = max, step = step })
  end
  local function Toggle(label, k)
    table.insert(holder.options, { label = label, toggle = true, get = function() return s[k] end, set = function(v) s[k] = v; Layout() end })
  end
  Toggle("Enabled", "enabled")
  Num("Width", "width", 20, 2560, 10)
  Num("Height", "height", 4, 1440, 2)
  Num("Opacity", "alpha", 0, 1, 0.05)
  Toggle("Border", "border")
  Toggle("Accent line", "strip")
  Layout()
end

S:RegisterModule("panels", function()
  for n = 1, 4 do
    CreatePanel(n)
  end
end, "Panels", "Plain backgrounds you can place anywhere (SpartanUI- and Tukui-style art panels).")
