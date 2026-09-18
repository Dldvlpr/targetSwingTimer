-- Target Swing Timer, addon World of Warcraft.
-- Copyright (C) 2026 Ludovic
--
-- This program is free software; you can redistribute it and/or modify it under the terms
-- of the GNU General Public License as published by the Free Software Foundation; either
-- version 2 of the License, or (at your option) any later version. See the LICENSE file.
--
-- Panneau d'options natif (Settings API Retail / Classic, repli InterfaceOptions).

local TST = TargetSwingTimer
local L = TST.L
local panel = CreateFrame("Frame", "TargetSwingTimerOptions")
panel.name = "Target Swing Timer"

local controls = {}     -- rafraîchis à l'ouverture du panneau
local lastAnchor
local columnX = 16
local function column(x)          -- démarre une nouvelle colonne en haut du panneau
    lastAnchor, columnX = nil, x
end
local function anchor(frame, gapY)
    if lastAnchor then
        frame:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -(gapY or 8))
    else
        frame:SetPoint("TOPLEFT", columnX, -60)
    end
    lastAnchor = frame
    table.insert(controls, frame)
end

local function refreshAll()
    for _, c in ipairs(controls) do
        if c.Refresh then c:Refresh() end
    end
end

local function apply()
    TST:ApplySettings()
end

------------------------------------------------------------------------
-- Fabriques de contrôles
------------------------------------------------------------------------
local function Check(label, key, tooltip)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb.text = cb.text or cb.Text or _G[cb:GetName() and cb:GetName() .. "Text"]
    if not cb.text then
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    end
    cb.text:SetText(label)
    cb.tooltipText = tooltip
    cb:SetScript("OnClick", function(self)
        TST.db[key] = self:GetChecked() and true or false
        apply()
        refreshAll()
    end)
    cb.Refresh = function(self) self:SetChecked(TST.db[key]) end
    anchor(cb, 2)
    return cb
end

local function Slider(label, key, min, max, step, fmt)
    local s = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    s:SetWidth(220)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText(min)
    s.High:SetText(max)
    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        TST.db[key] = value
        self.Text:SetFormattedText(fmt or "%s : %d", label, value)
        apply()
    end)
    s.Refresh = function(self) self:SetValue(TST.db[key]) end
    anchor(s, 22)
    return s
end

local function ColorSwatch(label, key)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(20, 20)
    btn.swatch = btn:CreateTexture(nil, "OVERLAY")
    btn.swatch:SetAllPoints()
    btn.border = btn:CreateTexture(nil, "BACKGROUND")
    btn.border:SetPoint("TOPLEFT", -1, 1)
    btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.border:SetColorTexture(1, 1, 1, 0.8)
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.label:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    btn.label:SetText(label)

    local function set(r, g, b, a)
        local c = TST.db[key]
        c.r, c.g, c.b, c.a = r, g, b, a
        btn.swatch:SetColorTexture(r, g, b, 1)
        apply()
    end

    btn:SetScript("OnClick", function()
        local c = TST.db[key]
        local prev = { r = c.r, g = c.g, b = c.b, a = c.a }
        local function onColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()
                or (1 - OpacitySliderFrame:GetValue())
            set(r, g, b, a)
        end
        local function onCancel() set(prev.r, prev.g, prev.b, prev.a) end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b, opacity = c.a, hasOpacity = true,
                swatchFunc = onColor, opacityFunc = onColor, cancelFunc = onCancel,
            })
        else
            ColorPickerFrame.hasOpacity = true
            ColorPickerFrame.opacity = 1 - c.a
            ColorPickerFrame.func = onColor
            ColorPickerFrame.opacityFunc = onColor
            ColorPickerFrame.cancelFunc = onCancel
            ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
            ColorPickerFrame:Show()
        end
    end)
    btn.Refresh = function(self)
        local c = TST.db[key]
        self.swatch:SetColorTexture(c.r, c.g, c.b, 1)
    end
    anchor(btn, 10)
    return btn
end

-- Bouton qui fait défiler une liste de { libellé, valeur }.
local function Cycle(label, key, values)
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(220, 24)
    local function index()
        for i, v in ipairs(values) do
            if v[2] == TST.db[key] then return i end
        end
        return 1
    end
    btn:SetScript("OnClick", function(self, mouse)
        local i = index() + (mouse == "RightButton" and -1 or 1)
        if i > #values then i = 1 elseif i < 1 then i = #values end
        TST.db[key] = values[i][2]
        apply()
        self:Refresh()
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.Refresh = function(self)
        self:SetFormattedText("%s : %s", label, values[index()][1])
    end
    anchor(btn, 8)
    return btn
end

------------------------------------------------------------------------
-- Contenu
------------------------------------------------------------------------
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Target Swing Timer")
local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
sub:SetText(L.SUBTITLE)

local textures = {}
for _, t in ipairs(TST.textures) do textures[#textures + 1] = t end
-- LibSharedMedia si un autre addon l'a chargée.
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM then
    for name, path in pairs(LSM:HashTable("statusbar")) do
        textures[#textures + 1] = { name, path }
    end
    table.sort(textures, function(a, b) return a[1] < b[1] end)
end

Check(L.OPT_LOCK, "locked", L.TIP_LOCK)
Check(L.OPT_SHOW_TEXT, "showText")
Check(L.OPT_SHOW_SPARK, "showSpark")
Check(L.OPT_REVERSE, "reverse")
Cycle(L.OPT_MODE, "fillMode", { { L.MODE_DRAIN, "drain" }, { L.MODE_FILL, "fill" } })
Cycle(L.OPT_TEXTURE, "texture", textures)
ColorSwatch(L.OPT_BAR_COLOR, "color")
ColorSwatch(L.OPT_BG_COLOR, "bgColor")
Slider(L.OPT_WIDTH, "width", 80, 600, 5)
Slider(L.OPT_HEIGHT, "height", 8, 60, 1)
Slider(L.OPT_FONT_SIZE, "fontSize", 8, 24, 1)

column(320)
Check(L.OPT_PARRY, "parryHaste", L.TIP_PARRY)
Check(L.OPT_AUTO_LATENCY, "autoLatency", L.TIP_AUTO_LATENCY)
Check(L.OPT_LATENCY_TICK, "showLatencyTick", L.TIP_LATENCY_TICK)
local home = Slider(L.OPT_LATENCY_HOME, "latencyHome", 0, 500, 5)
local world = Slider(L.OPT_LATENCY_WORLD, "latencyWorld", 0, 500, 5)
local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", world, "BOTTOMLEFT", 0, -18)
hint:SetWidth(280)
hint:SetJustifyH("LEFT")
hint:SetText(L.HINT_LATENCY)

local function refreshLatencyState()
    local manual = not TST.db.autoLatency
    for _, s in ipairs({ home, world }) do
        s:SetEnabled(manual)
        s:SetAlpha(manual and 1 or 0.4)
    end
end
panel:SetScript("OnShow", function()
    refreshAll()
    refreshLatencyState()
end)
local origRefresh = refreshAll
refreshAll = function()
    origRefresh()
    refreshLatencyState()
end

------------------------------------------------------------------------
-- Enregistrement
------------------------------------------------------------------------
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function TST:OpenOptions()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)   -- double appel : bug connu du premier affichage
    end
end
