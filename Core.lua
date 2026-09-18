-- Target Swing Timer, addon World of Warcraft.
-- Copyright (C) 2026 Ludovic
--
-- This program is free software; you can redistribute it and/or modify it under the terms
-- of the GNU General Public License as published by the Free Software Foundation; either
-- version 2 of the License, or (at your option) any later version. See the LICENSE file.
--
-- Target Swing Timer : suit le swing d'auto-attaque (main droite) de la cible.
-- Hôte : World of Warcraft (Retail, Classic Era, MoP Classic) ; Lua 5.1.

local ADDON, NS = ...
local TST = CreateFrame("Frame", "TargetSwingTimerFrame", UIParent)
_G.TargetSwingTimer = TST
TST.L = NS.L
local L = NS.L
TST.data = {}   -- rempli par Data_<version>.lua : npcId -> vitesse de base en ms

------------------------------------------------------------------------
-- Réglages
------------------------------------------------------------------------
local IS_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

TST.defaults = {
    locked = true,
    point = "CENTER", x = 0, y = -180,
    width = 250, height = 22,
    texture = "Interface\\TargetingFrame\\UI-StatusBar",
    color = { r = 0.85, g = 0.25, b = 0.25, a = 1 },
    bgColor = { r = 0, g = 0, b = 0, a = 0.6 },
    fillMode = "drain",      -- "drain" : la barre se vide jusqu'au swing ; "fill" : elle se remplit
    reverse = false,         -- sens de remplissage inversé (droite vers gauche)
    showSpark = true,
    showText = true,
    fontSize = 12,
    -- Le parry haste des boss existe en Classic ; il a été retiré des joueurs en 4.0 et est
    -- quasiment absent en Retail. Actif par défaut hors Retail.
    parryHaste = not IS_RETAIL,
    autoLatency = true,
    latencyHome = 0,         -- ms, utilisé seulement si autoLatency = false
    latencyWorld = 0,
    showLatencyTick = true,
    speeds = {},             -- vitesses apprises par identifiant de créature
}

TST.textures = {
    { "Blizzard",  "Interface\\TargetingFrame\\UI-StatusBar" },
    { "Uni",       "Interface\\Buttons\\WHITE8x8" },
    { "Raid",      "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { "Skills",    "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { "Target",    "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
}

------------------------------------------------------------------------
-- État de swing par GUID (toutes les unités vues dans le journal de combat,
-- pas seulement la cible : changer de cible affiche la barre sans attendre).
------------------------------------------------------------------------
local units = {}          -- guid -> { last, next, speed, samples, parried }
local targetGUID
local DEFAULT_SPEED = 2.0
local PRUNE_AGE = 60

local function npcKey(guid)
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if npcId and (unitType == "Creature" or unitType == "Vehicle") then
        return npcId
    end
end

local function getUnit(guid)
    local u = units[guid]
    if not u then
        local key = npcKey(guid)
        u = { speed = key and TST.db.speeds[key], samples = 0 }
        if not u.speed and key and TST.data[tonumber(key)] then
            -- Vitesse connue de la base de données : considérée fiable d'emblée.
            u.speed, u.samples = TST.data[tonumber(key)] / 1000, 3
        end
        units[guid] = u
    end
    return u
end

local function saveSpeed(guid, speed)
    local key = npcKey(guid)
    if key then TST.db.speeds[key] = speed end
end

local function prune(now)
    for guid, u in pairs(units) do
        if guid ~= targetGUID and u.last and now - u.last > PRUNE_AGE then
            units[guid] = nil
        end
    end
end

-- Latences en secondes (mesurées ou saisies).
function TST:GetLatency()
    local db = self.db
    if db.autoLatency then
        local _, _, home, world = GetNetStats()
        return (home or 0) / 1000, (world or 0) / 1000
    end
    return db.latencyHome / 1000, db.latencyWorld / 1000
end

-- Swing main droite observé pour ce GUID.
local function onSwing(guid, now)
    local u = getUnit(guid)
    if u.last then
        local interval = now - u.last
        -- Attaque supplémentaire (Double Attaque, procs) : elle ne relance pas le timer.
        -- ponytail: filtre activé seulement après 3 mesures, sinon une première mesure
        -- trop longue (mob en incantation) bloquerait l'apprentissage. `/tst reset` en secours.
        if u.speed and u.samples >= 3 and interval < u.speed * 0.5 then
            return
        end
        -- Le mob ne frappe jamais plus vite que sa vitesse d'arme, sauf parry haste :
        -- le plus petit intervalle sans parade est la meilleure estimation.
        if not u.parried and (not u.speed or interval < u.speed) then
            u.speed = interval
            saveSpeed(guid, interval)
        end
        u.samples = u.samples + 1
    end
    u.last = now
    u.parried = false
    u.next = now + (u.speed or DEFAULT_SPEED)
end

-- La cible a paré une attaque de mêlée : son prochain swing est avancé de 40 % de la
-- vitesse d'arme, sans descendre sous 20 % restant (aucun effet si déjà sous 20 %).
local function onParry(guid, now)
    local u = units[guid]
    if not u or not u.next then return end
    local speed = u.speed or DEFAULT_SPEED
    local remaining = u.next - now
    if remaining > speed * 0.2 then
        u.next = now + math.max(remaining - speed * 0.4, speed * 0.2)
        u.parried = true
    end
end

------------------------------------------------------------------------
-- Événements
------------------------------------------------------------------------
local function onCombatLog()
    local _, event, _, sourceGUID, _, _, _, destGUID, _, _, _, p12, p13, _, _, _, _, _, _, _, p21 =
        CombatLogGetCurrentEventInfo()
    local now = GetTime()

    if event == "SWING_DAMAGE" then
        if not p21 then onSwing(sourceGUID, now) end               -- p21 = isOffHand
    elseif event == "SWING_MISSED" then
        if not p13 then onSwing(sourceGUID, now) end               -- p13 = isOffHand
        if p12 == "PARRY" and TST.db.parryHaste then onParry(destGUID, now) end
    elseif event == "SPELL_MISSED" and TST.db.parryHaste then
        -- p15 = missType pour SPELL_MISSED (après spellId, spellName, spellSchool)
        local missType = select(15, CombatLogGetCurrentEventInfo())
        if missType == "PARRY" then onParry(destGUID, now) end
    elseif event == "UNIT_DIED" then
        units[destGUID] = nil
        if destGUID == targetGUID then TST:UpdateVisibility() end
    end
end

-- Moteur 12.x (Midnight, WoW Forever 1.60) : COMBAT_LOG_EVENT_UNFILTERED est interdit aux addons,
-- même sous pcall (popup ADDON_ACTION_FORBIDDEN). Repli sur UNIT_COMBAT : on ne voit que les coups
-- reçus par le joueur, donc la barre ne suit la cible que lorsqu'elle attaque le joueur.
local HAS_COMBAT_LOG = not (C_DamageMeter or issecretvalue or (C_CombatLog and C_CombatLog.SetFilteredEventsEnabled))

local MELEE_ACTIONS = { WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true }

local function onUnitCombat(unit, action, _, _, schoolMask)
    if issecretvalue and (issecretvalue(action) or issecretvalue(schoolMask)) then return end
    if not targetGUID then return end
    local now = GetTime()
    if unit == "player" then
        -- Coup physique reçu pendant que la cible me frappe : compté comme un swing de la cible.
        -- Les techniques physiques passent par le filtre « attaque supplémentaire » de onSwing.
        if MELEE_ACTIONS[action] and (schoolMask == nil or schoolMask == 1)
            and UnitIsUnit("targettarget", "player") then
            onSwing(targetGUID, now)
        end
    elseif unit == "target" and action == "PARRY" and TST.db.parryHaste then
        onParry(targetGUID, now)
    end
end

local function onTargetChanged()
    targetGUID = UnitGUID("target")
    prune(GetTime())
    TST:UpdateVisibility()
end

TST:RegisterEvent("ADDON_LOADED")
TST:RegisterEvent("PLAYER_TARGET_CHANGED")
TST:RegisterEvent("PLAYER_REGEN_ENABLED")
TST:RegisterEvent("PLAYER_REGEN_DISABLED")
if HAS_COMBAT_LOG then
    TST:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
elseif TST.RegisterUnitEvent then
    TST:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
else
    TST:RegisterEvent("UNIT_COMBAT")
end
TST:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        onCombatLog()
    elseif event == "UNIT_COMBAT" then
        onUnitCombat(arg1, ...)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_REGEN_DISABLED" then
        onTargetChanged()
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        self:InitDB()
        self:BuildBar()
        self:ApplySettings()
        onTargetChanged()
    end
end)

function TST:InitDB()
    TargetSwingTimerDB = TargetSwingTimerDB or {}
    self.db = TargetSwingTimerDB
    for k, v in pairs(self.defaults) do
        if self.db[k] == nil then
            self.db[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
end

------------------------------------------------------------------------
-- Barre
------------------------------------------------------------------------
function TST:BuildBar()
    self:SetMovable(true)
    self:SetClampedToScreen(true)
    self:EnableMouse(false)
    self:RegisterForDrag("LeftButton")
    self:SetScript("OnDragStart", function(f) f:StartMoving() end)
    self:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        self.db.point, self.db.x, self.db.y = point, x, y
    end)

    self.bg = self:CreateTexture(nil, "BACKGROUND")
    self.bg:SetAllPoints()

    self.bar = CreateFrame("StatusBar", nil, self)
    self.bar:SetAllPoints()
    self.bar:SetMinMaxValues(0, 1)

    self.spark = self.bar:CreateTexture(nil, "OVERLAY")
    self.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    self.spark:SetBlendMode("ADD")

    -- Repère « appuyer maintenant » : latence home avant le swing serveur.
    self.tick = self.bar:CreateTexture(nil, "OVERLAY")
    self.tick:SetColorTexture(1, 1, 1, 0.9)
    self.tick:SetWidth(2)

    self.text = self.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.text:SetPoint("CENTER")

    self:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
end

function TST:ApplySettings()
    local db = self.db
    self:ClearAllPoints()
    self:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    self:SetSize(db.width, db.height)
    self:EnableMouse(not db.locked)

    self.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a)
    self.bar:SetStatusBarTexture(db.texture)
    self.bar:SetStatusBarColor(db.color.r, db.color.g, db.color.b, db.color.a)
    self.bar:SetReverseFill(db.reverse)

    self.spark:SetSize(db.height * 0.8, db.height * 2.2)
    self.spark:SetShown(db.showSpark)
    self.tick:SetHeight(db.height)
    self.tick:SetShown(db.showLatencyTick)

    local font, _, flags = GameFontHighlight:GetFont()
    self.text:SetFont(font, db.fontSize, flags)
    self.text:SetShown(db.showText)

    self:UpdateVisibility()
end

function TST:UpdateVisibility()
    local show = not self.db.locked
        or (targetGUID and not UnitIsDead("target")
            and (UnitAffectingCombat("target") or UnitAffectingCombat("player")))
    self:SetShown(show and true or false)
end

-- Place spark et repère à une fraction [0..1] de la barre, en tenant compte du sens.
local function placeAt(tex, bar, frac, width, reverse)
    local x = (reverse and (1 - frac) or frac) * width
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", bar, "LEFT", x, 0)
end

function TST:OnUpdate()
    local db = self.db
    local u = targetGUID and units[targetGUID]
    local width = db.width

    -- Déverrouillé sans donnée : aperçu statique pour positionner la barre.
    if not u or not u.next then
        self.bar:SetValue(db.locked and 0 or 0.6)
        self.text:SetText(db.locked and "" or "Target Swing Timer")
        self.spark:Hide()
        self.tick:Hide()
        return
    end

    local home, world = self:GetLatency()
    local speed = u.speed or DEFAULT_SPEED
    -- Le journal de combat arrive avec la latence world de retard : le vrai swing
    -- serveur a lieu `world` avant que le client ne l'apprenne.
    local remaining = u.next - world - GetTime()
    if remaining < 0 then remaining = 0 end
    local progress = 1 - remaining / speed
    if progress < 0 then progress = 0 end

    local value = db.fillMode == "fill" and progress or (1 - progress)
    self.bar:SetValue(value)

    if db.showSpark and remaining > 0 then
        self.spark:Show()
        placeAt(self.spark, self.bar, value, width, db.reverse)
    else
        self.spark:Hide()
    end

    if db.showLatencyTick and home > 0 then
        -- Position du swing moins la latence home, dans le repère de la barre.
        local tickProgress = 1 - home / speed
        local tickValue = db.fillMode == "fill" and tickProgress or (1 - tickProgress)
        self.tick:Show()
        placeAt(self.tick, self.bar, tickValue, width, db.reverse)
    else
        self.tick:Hide()
    end

    if db.showText then
        self.text:SetFormattedText("%.1f / %.2f", remaining, speed)
    end
end

------------------------------------------------------------------------
-- Commandes
------------------------------------------------------------------------
SLASH_TARGETSWINGTIMER1 = "/tst"
SlashCmdList.TARGETSWINGTIMER = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    cmd = cmd:lower()
    if cmd == "lock" or cmd == "unlock" then
        TST.db.locked = cmd == "lock"
        TST:ApplySettings()
        print("|cff33ff99TST|r " .. (TST.db.locked and L.MSG_LOCKED or L.MSG_UNLOCKED))
    elseif cmd == "reset" and targetGUID then
        units[targetGUID] = nil
        local key = npcKey(targetGUID)
        if key then TST.db.speeds[key] = nil end
        print("|cff33ff99TST|r " .. L.MSG_SPEED_FORGOTTEN)
    elseif cmd == "speed" and targetGUID and tonumber(arg) then
        local u = getUnit(targetGUID)
        u.speed, u.samples = tonumber(arg), 3
        saveSpeed(targetGUID, u.speed)
        print("|cff33ff99TST|r " .. string.format(L.MSG_SPEED_FORCED, arg))
    else
        TST:OpenOptions()
    end
end
