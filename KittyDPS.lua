-- KittyDPS v1.1
-- Feral Cat one-button DPS rotation helper for WoW Classic+ servers
-- that expand the vanilla 1.12 feral talent tree with bleed-enhancing talents
-- (Open Wounds, Carnage, Blood Frenzy).
--
-- Usage: create a macro with "/kdps dps" and spam it in combat.
--
-- Inspired by HolyShift (https://github.com/ZachM89/HolyShift) by Maulbatross.

-- Vanilla 1.12 compatibility alias
local strfind = string.find

local cos = math.cos
local sin = math.sin
local rad = math.rad
local deg = math.deg
local pi = math.pi
local atan = math.atan

local function Atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return atan(y / x) end
  if x < 0 then return atan(y / x) + (y >= 0 and pi or -pi) end
  if y > 0 then return pi / 2 end
  if y < 0 then return -pi / 2 end
  return 0
end

-- ============================================================
-- Spell / buff name constants
-- Adjust these strings if your server uses a non-English client.
-- ============================================================
local SPELL_CAT_FORM       = "Cat Form"
local SPELL_RAKE           = "Rake"
local SPELL_RIP            = "Rip"
local SPELL_CLAW           = "Claw"
local SPELL_SHRED          = "Shred"
local SPELL_FEROCIOUS_BITE = "Ferocious Bite"
local SPELL_TIGERS_FURY    = "Tiger's Fury"
local SPELL_FAERIE_FIRE    = "Faerie Fire (Feral)"
local SPELL_RESHIFT        = "Reshift"
local BUFF_BLOOD_FRENZY    = "Blood Frenzy"
-- NOTE: Blood Frenzy talent enhances Tiger's Fury. The attack-speed buff may be
-- named "Tiger's Fury" rather than "Blood Frenzy" in-game. If powershift / TF
-- guards never trigger, change this constant to "Tiger's Fury" and test.
local BUFF_CLEARCASTING    = "Clearcasting"
-- Error message used by the doclaw state machine to detect that Shred failed
-- because the player is not behind the target. Adjust for non-English clients.
local ERR_NOT_BEHIND       = "You must be behind"
-- Combat log prefixes used by the doclaw state machine to confirm a Shred or
-- Claw landed. Adjust for non-English clients (same as spell name constants).
local MSG_SHRED_HIT        = "Your Shred"
local MSG_CLAW_HIT         = "Your Claw"

-- ============================================================
-- Base energy costs (vanilla spell cost before any talents)
-- ============================================================
local BASE_COSTS = {
  Rake  = 35,
  Claw  = 40,
  Rip   = 30,
  Shred = 60,
}

-- Shred position tracking (pattern from HolyShift):
--   0 = attempt Shred
--   1 = Shred failed (not behind target), fall back to Claw
--   2 = one Claw landed after failure, retry Shred next cycle
local doclaw = 0

-- Shapeshift form indices cached at login — these never change during a
-- session, so scanning every key press is wasteful.
local catFormIdx    = nil
local reshiftFormIdx = nil

-- ============================================================
-- SavedVariables and defaults
-- ============================================================
local defaults = {
  minEnergyForFB              = 35,
  ripRefreshThreshold         = 3,
  minComboForRipBoss          = 5,
  minComboForRipTrash         = 3,
  minComboForBossFB           = 5,
  minComboForTrashFB          = 3,
  useFerociousBiteOnTrash     = true,
  autoTargetEnabled           = true,
  useFaerieFire               = true,
  useTigersFury               = true,
  autoDetectBleedImmune       = true,
  usePowershift               = false,
  powershiftEnergyThreshold   = 20,
  powershiftMana              = 231,
  costRake                    = 31,   -- 35 - 4 (Ferocity 4/5)
  costClaw                    = 36,   -- 40 - 4 (Ferocity 4/5)
  costRip                     = 30,   -- unchanged (Ferocity does not affect Rip)
  costShred                   = 48,   -- 60 - 12 (Improved Shred 2/2)
  minimapAngle                = 225,
}

local cfg = {}

local function CopyDefaults(src, dst)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do
    if dst[k] == nil then dst[k] = v end
  end
  return dst
end

local function CostRake()  return cfg.costRake  or BASE_COSTS.Rake  end
local function CostClaw()  return cfg.costClaw  or BASE_COSTS.Claw  end
local function CostRip()   return cfg.costRip   or BASE_COSTS.Rip   end
local function CostShred() return cfg.costShred or BASE_COSTS.Shred end

-- ============================================================
-- Utility functions
-- ============================================================
local function KPrint(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
end

local function GetCatFormIndex()
  for i = 1, GetNumShapeshiftForms() do
    local _, name, _, _ = GetShapeshiftFormInfo(i)
    if name and strfind(name, SPELL_CAT_FORM) then return i end
  end
  return nil
end

local function GetReshiftIndex()
  for i = 1, GetNumShapeshiftForms() do
    local _, name, _, _ = GetShapeshiftFormInfo(i)
    if name and strfind(name, SPELL_RESHIFT) then return i end
  end
  return nil
end

local function IsCatForm()
  -- GetShapeshiftFormInfo returns active as 1 or nil, not a boolean.
  -- catFormIdx is cached at login — no form scan needed here.
  if not catFormIdx then return false end
  local _, _, active = GetShapeshiftFormInfo(catFormIdx)
  return active == 1 or active == true
end

local function PlayerEnergy()
  return UnitMana("player")
end

local function PlayerHasBuff(buffName)
  local i = 1
  while true do
    local name = UnitBuff("player", i)
    if not name then break end
    if name == buffName then return true end
    i = i + 1
  end
  return false
end

local function TargetHasDebuff(debuffName)
  local i = 1
  while true do
    local name = UnitDebuff("target", i)
    if not name then break end
    if name == debuffName then return true end
    i = i + 1
  end
  return false
end

local function TargetDebuffRemaining(debuffName)
  -- expirationTime is available in 1.12 for debuffs cast by the player.
  -- Guard against nil for debuffs cast by others.
  local i = 1
  while true do
    local name, _, _, _, _, _, expirationTime = UnitDebuff("target", i)
    if not name then break end
    if name == debuffName then
      if type(expirationTime) == "number" and expirationTime > 0 then
        local now = GetTime()
        if expirationTime > now then
          return expirationTime - now  -- always > 0, guard already checked above
        end
        return 0
      end
      return nil
    end
    i = i + 1
  end
  return nil
end

local function SpellOnCooldown(spellName)
  local start, duration = GetSpellCooldown(spellName)
  if not start or start == 0 then return false end
  if duration == 0 then return false end
  return (start + duration - GetTime()) > 0.1
end

local function SafeCast(spellName)
  if spellName then CastSpellByName(spellName) end
end

local function IsBossOrElite()
  local c = UnitClassification("target")
  return c == "worldboss" or c == "elite" or c == "rareelite"
end

-- ============================================================
-- Blood Frenzy (Tiger's Fury buff)
-- ============================================================
local function HasBloodFrenzyBuff()
  return PlayerHasBuff(BUFF_BLOOD_FRENZY)
end

-- ============================================================
-- Bleed immunity detection
-- ============================================================
local function CanBleed()
  if not cfg.autoDetectBleedImmune then return true end
  local ct = UnitCreatureType("target")
  if ct == "Undead" or ct == "Elemental"
     or ct == "Mechanical" or ct == "Totem" then
    return false
  end
  return true
end

-- ============================================================
-- Powershift — NEVER fires while Blood Frenzy is active.
-- Shifting out of Cat Form cancels Blood Frenzy immediately,
-- and losing 20% attack speed + energy regen is never worth
-- the energy recovered from a shift.
-- ============================================================
local function TryPowershift()
  if not cfg.usePowershift then return false end
  if HasBloodFrenzyBuff() then return false end
  if UnitMana("player") < cfg.powershiftMana then return false end
  -- reshiftFormIdx is cached at login — no form scan needed here.
  if not reshiftFormIdx then return false end
  -- GetShapeshiftFormInfo returns (texture, name, isActive, isCastable).
  -- isCastable is nil when the form is on cooldown or otherwise unavailable.
  local _, _, _, castable = GetShapeshiftFormInfo(reshiftFormIdx)
  if not castable then return false end
  CastShapeshiftForm(reshiftFormIdx)
  return true
end

-- ============================================================
-- Tiger's Fury — Blood Frenzy aware
--
-- Uses TF whenever the Blood Frenzy buff is not active.
-- CheckInteractDistance index 2 = Trade range (~11 yards),
-- the closest melee-range proxy available in the 1.12 API.
--
-- In melee range:  fire TF when energy < CostClaw (nothing
--   useful to cast) but > 30 (not so empty that Reshift wins).
-- Out of melee:    always fire TF if buff is down
--   (pre-pull / approaching target).
-- ============================================================
local function TryTigersFury(energy)
  if not cfg.useTigersFury then return false end
  if SpellOnCooldown(SPELL_TIGERS_FURY) then return false end
  if HasBloodFrenzyBuff() then return false end

  local inMeleeRange = CheckInteractDistance("target", 2)

  if inMeleeRange then
    if energy < CostClaw() and energy > 30 then
      SafeCast(SPELL_TIGERS_FURY)
      return true
    end
  else
    -- Out of melee: use TF pre-pull but only if not already energy-capped
    if energy < 80 then
      SafeCast(SPELL_TIGERS_FURY)
      return true
    end
  end

  return false
end

-- ============================================================
-- Core rotation
-- ============================================================
local function DoDPS()

  -- 1. Auto-target nearest attackable enemy if needed
  if cfg.autoTargetEnabled then
    if not UnitExists("target") or UnitIsDeadOrGhost("target")
       or UnitIsFriend("player", "target") then
      TargetNearestEnemy()
    end
  end

  -- 2. Abort if still no valid target
  if not UnitExists("target") or UnitIsDeadOrGhost("target")
     or UnitIsFriend("player", "target") then
    return
  end

  -- 3. Ensure Cat Form
  if not IsCatForm() then
    if catFormIdx then CastShapeshiftForm(catFormIdx) else SafeCast(SPELL_CAT_FORM) end
    return
  end

  local energy  = PlayerEnergy()
  local combo   = GetComboPoints() or 0
  local isBoss  = IsBossOrElite()
  local bleedOk = CanBleed()

  -- 4. Omen of Clarity — checked before Faerie Fire so that FF does not
  -- consume the Clearcasting proc (FF is a spell that triggers the GCD).
  -- Priority: FB (bleeds + CP) > Shred if behind > Rake if missing > Claw.
  -- Shred beats Rake when behind: higher immediate damage and free.
  -- Rake beats Claw when not behind and Rake is missing: without an active
  -- bleed, Claw has no Open Wounds bonus, making a free Rake setup the
  -- higher-value option.
  if PlayerHasBuff(BUFF_CLEARCASTING) then
    local hasRakeCC = TargetHasDebuff(SPELL_RAKE)
    local hasRipCC  = TargetHasDebuff(SPELL_RIP)
    local minCP = isBoss and cfg.minComboForBossFB or cfg.minComboForTrashFB
    if hasRakeCC and hasRipCC and combo >= minCP then
      SafeCast(SPELL_FEROCIOUS_BITE)
      return
    end
    if doclaw == 0 then
      SafeCast(SPELL_SHRED)
    elseif not hasRakeCC then
      -- Not behind target and Rake is missing: free Rake > free Claw
      -- (Claw without a bleed has no Open Wounds bonus).
      SafeCast(SPELL_RAKE)
    else
      SafeCast(SPELL_CLAW)
    end
    return
  end

  -- 5. Faerie Fire (Feral)
  if cfg.useFaerieFire and not SpellOnCooldown(SPELL_FAERIE_FIRE) then
    if not TargetHasDebuff(SPELL_FAERIE_FIRE) then
      SafeCast(SPELL_FAERIE_FIRE)
      return
    end
  end

  -- ==========================================================
  -- BRANCH A: target can bleed
  --
  -- Open Wounds is a passive talent — no buff or debuff to track.
  -- It automatically increases Claw damage whenever the target
  -- has Rake active. Keeping Rake up (step 3 below) is all that
  -- is needed for Open Wounds to be active.
  -- ==========================================================
  if bleedOk then

    -- 1. Tiger's Fury (Blood Frenzy)
    if TryTigersFury(energy) then return end

    -- 2. Rake — keep active so Open Wounds bonus is always up
    local hasRake = TargetHasDebuff(SPELL_RAKE)
    if not hasRake and energy >= CostRake() then
      SafeCast(SPELL_RAKE)
      return
    end

    -- 3. Rip — apply or refresh before it falls off.
    -- On bosses, skip the refresh if combo points are already at the FB
    -- threshold: FB + Carnage will refresh Rip for free, so recasting it
    -- here would waste energy and a GCD.
    local hasRip = TargetHasDebuff(SPELL_RIP)
    local ripRemain = TargetDebuffRemaining(SPELL_RIP)

    if isBoss then
      if combo >= cfg.minComboForRipBoss and energy >= CostRip() then
        if not hasRip or (ripRemain and ripRemain < cfg.ripRefreshThreshold
                          and combo < cfg.minComboForBossFB) then
          SafeCast(SPELL_RIP)
          return
        end
      end
    else
      if combo >= cfg.minComboForRipTrash and not hasRip and energy >= CostRip() then
        SafeCast(SPELL_RIP)
        return
      end
    end

    -- 4. Ferocious Bite — requires both bleeds active.
    -- At minComboForBossFB CPs (default 5), Carnage guarantees a bleed
    -- refresh, so FB is always the right finisher when bleeds are ticking.
    if energy >= cfg.minEnergyForFB and hasRake and hasRip then
      if isBoss and combo >= cfg.minComboForBossFB then
        SafeCast(SPELL_FEROCIOUS_BITE)
        return
      elseif not isBoss and cfg.useFerociousBiteOnTrash
             and combo >= cfg.minComboForTrashFB then
        SafeCast(SPELL_FEROCIOUS_BITE)
        return
      end
    end

    -- 5. Powershift if energy is low (never during Blood Frenzy)
    if energy <= cfg.powershiftEnergyThreshold then
      if TryPowershift() then return end
    end

    -- 6. Claw filler
    -- With Rake active, Open Wounds bonus applies automatically.
    if energy >= CostClaw() then
      SafeCast(SPELL_CLAW)
    end

  -- ==========================================================
  -- BRANCH B: bleed-immune target
  -- Skip Rake and Rip entirely; use Shred/Claw + FB.
  -- ==========================================================
  else

    if energy >= cfg.minEnergyForFB then
      local minCP = isBoss and cfg.minComboForBossFB or cfg.minComboForTrashFB
      if combo >= minCP then
        SafeCast(SPELL_FEROCIOUS_BITE)
        return
      end
    end

    if TryTigersFury(energy) then return end

    if energy <= cfg.powershiftEnergyThreshold then
      if TryPowershift() then return end
    end

    -- Shred if behind (doclaw == 0), Claw otherwise
    if doclaw == 0 then
      if energy >= CostShred() then SafeCast(SPELL_SHRED) end
    else
      if energy >= CostClaw() then SafeCast(SPELL_CLAW) end
    end

  end
end

-- ============================================================
-- Options UI
-- Built as a plain movable frame — InterfaceOptions API does
-- not exist in vanilla 1.12.
-- ============================================================

local optionsRoot = nil

local function CreateSlider(name, parent, label, minVal, maxVal, step, x, y, getter, setter)
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", x, y)
  s:SetWidth(220)
  s:SetMinMaxValues(minVal, maxVal)
  s:SetValueStep(step)
  -- SetObeyStepOnDrag does not exist in 1.12 — omitted
  _G[name .. "Low"]:SetText(minVal)
  _G[name .. "High"]:SetText(maxVal)
  local function Refresh()
    local v = getter()
    s:SetValue(v)
    _G[name .. "Text"]:SetText(string.format("%s: %d", label, v))
  end
  Refresh()
  s:SetScript("OnValueChanged", function()
    local v = math.floor(this:GetValue() + 0.5)
    setter(v)
    _G[name .. "Text"]:SetText(string.format("%s: %d", label, v))
  end)
  return s
end

local function CreateCB(name, parent, label, anchorFrame, offsetY, getter, setter)
  local cb = CreateFrame("CheckButton", name, parent, "ChatConfigCheckButtonTemplate")
  if anchorFrame then
    cb:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, offsetY or -8)
  else
    cb:SetPoint("TOPLEFT", 0, 0)
  end
  local textFS = cb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  textFS:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  textFS:SetText(label)
  cb:SetChecked(getter())
  cb:SetScript("OnClick", function()
    -- GetChecked() returns 1 or nil in 1.12, not a boolean
    setter(this:GetChecked() == 1)
  end)
  return cb
end

local function SetTabSelected(btn, selected)
  -- Manual tab highlight — PanelTemplates API does not exist in 1.12
  if selected then
    btn:SetAlpha(1.0)
    btn:LockHighlight()
  else
    btn:SetAlpha(0.6)
    btn:UnlockHighlight()
  end
end

local minimapButton = nil

local function UpdateMinimapButtonPosition()
  if not minimapButton then return end
  local angle = cfg.minimapAngle or 225
  local radius = 80
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", cos(rad(angle)) * radius, sin(rad(angle)) * radius)
end

local function CreateOptionsUI()
  if optionsRoot then return end

  local root = CreateFrame("Frame", "KittyDPSOptionsRoot", UIParent)
  root:SetWidth(600)
  root:SetHeight(580)
  root:SetPoint("CENTER", UIParent, "CENTER")
  root:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true, tileSize = 32, edgeSize = 32,
    insets   = { left=11, right=12, top=12, bottom=11 },
  })
  root:SetMovable(true)
  root:EnableMouse(true)
  root:RegisterForDrag("LeftButton")
  root:SetScript("OnDragStart", function() this:StartMoving() end)
  root:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
  root:SetFrameStrata("DIALOG")
  root:Hide()

  local titleFS = root:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  titleFS:SetPoint("TOP", 0, -16)
  titleFS:SetText("|cffffa500KittyDPS|r  Options")

  local closeBtn = CreateFrame("Button", nil, root, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() root:Hide() end)

  local tab1 = CreateFrame("Frame", nil, root)
  tab1:SetPoint("TOPLEFT", 16, -60)
  tab1:SetPoint("BOTTOMRIGHT", -16, 40)
  tab1:Show()

  local tab2 = CreateFrame("Frame", nil, root)
  tab2:SetPoint("TOPLEFT", 16, -60)
  tab2:SetPoint("BOTTOMRIGHT", -16, 40)
  tab2:Hide()

  local btn1 = CreateFrame("Button", "KittyDPS_TabBtn1", root, "UIPanelButtonTemplate")
  btn1:SetPoint("TOPLEFT", 16, -36)
  btn1:SetWidth(120)
  btn1:SetText("Rotation")

  local btn2 = CreateFrame("Button", "KittyDPS_TabBtn2", root, "UIPanelButtonTemplate")
  btn2:SetPoint("LEFT", btn1, "RIGHT", 4, 0)
  btn2:SetWidth(140)
  btn2:SetText("Energy Costs")

  local function SelectTab(id)
    if id == 1 then
      tab1:Show() ; tab2:Hide()
      SetTabSelected(btn1, true)
      SetTabSelected(btn2, false)
    else
      tab1:Hide() ; tab2:Show()
      SetTabSelected(btn1, false)
      SetTabSelected(btn2, true)
    end
  end

  btn1:SetScript("OnClick", function() SelectTab(1) end)
  btn2:SetScript("OnClick", function() SelectTab(2) end)
  SelectTab(1)

  -- ── Tab 1: Rotation ────────────────────────────────────────

  local secGen = tab1:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  secGen:SetPoint("TOPLEFT", 0, 0)
  secGen:SetText("|cffecd226General")

  local cbAT = CreateCB("KittyDPS_CB_AutoTarget", tab1,
    "Auto-target nearest enemy when no target",
    secGen, -10,
    function() return cfg.autoTargetEnabled end,
    function(v) cfg.autoTargetEnabled = v ; KittyDPSDB.autoTargetEnabled = v end)

  local cbFF = CreateCB("KittyDPS_CB_FF", tab1,
    "Apply Faerie Fire (Feral)",
    cbAT, -8,
    function() return cfg.useFaerieFire end,
    function(v) cfg.useFaerieFire = v ; KittyDPSDB.useFaerieFire = v end)

  local cbTF = CreateCB("KittyDPS_CB_TF", tab1,
    "Use Tiger's Fury / Blood Frenzy — never fires while buff is active",
    cbFF, -8,
    function() return cfg.useTigersFury end,
    function(v) cfg.useTigersFury = v ; KittyDPSDB.useTigersFury = v end)

  local cbFBT = CreateCB("KittyDPS_CB_FBTrash", tab1,
    "Ferocious Bite on trash (requires Rake + Rip active)",
    cbTF, -8,
    function() return cfg.useFerociousBiteOnTrash end,
    function(v) cfg.useFerociousBiteOnTrash = v ; KittyDPSDB.useFerociousBiteOnTrash = v end)

  local secBld = tab1:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  secBld:SetPoint("TOPLEFT", cbFBT, "BOTTOMLEFT", 0, -16)
  secBld:SetText("|cffecd226Bleeds & Immunity")

  local cbBI = CreateCB("KittyDPS_CB_BleedImm", tab1,
    "Skip bleeds on immune targets (Undead / Elemental / Mechanical / Totem)",
    secBld, -10,
    function() return cfg.autoDetectBleedImmune end,
    function(v) cfg.autoDetectBleedImmune = v ; KittyDPSDB.autoDetectBleedImmune = v end)

  local secPS = tab1:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  secPS:SetPoint("TOPLEFT", cbBI, "BOTTOMLEFT", 0, -16)
  secPS:SetText("|cffecd226Powershift (Reshift)")

  local cbPS = CreateCB("KittyDPS_CB_PS", tab1,
    "Auto-Reshift when energy is low — never fires during Blood Frenzy",
    secPS, -10,
    function() return cfg.usePowershift end,
    function(v) cfg.usePowershift = v ; KittyDPSDB.usePowershift = v end)

  local function RS(name, label, minV, maxV, step, yOff, getter, setter)
    return CreateSlider(name, tab1, label, minV, maxV, step, 290, yOff, getter, setter)
  end

  local secThr = tab1:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  secThr:SetPoint("TOPLEFT", 290, 0)
  secThr:SetText("|cffecd226Thresholds")

  RS("KittyDPS_Sl_FBE",   "Min energy for FB",             20, 80,  5, -25,
    function() return cfg.minEnergyForFB end,
    function(v) cfg.minEnergyForFB = v ; KittyDPSDB.minEnergyForFB = v end)

  RS("KittyDPS_Sl_RipT",  "Rip refresh threshold (secs)",   1, 6,   1, -80,
    function() return cfg.ripRefreshThreshold end,
    function(v) cfg.ripRefreshThreshold = v ; KittyDPSDB.ripRefreshThreshold = v end)

  RS("KittyDPS_Sl_RipCP", "Min CP for Rip (boss)",          3, 5,   1, -135,
    function() return cfg.minComboForRipBoss end,
    function(v) cfg.minComboForRipBoss = v ; KittyDPSDB.minComboForRipBoss = v end)

  RS("KittyDPS_Sl_RipCPT","Min CP for Rip (trash)",         2, 4,   1, -190,
    function() return cfg.minComboForRipTrash end,
    function(v) cfg.minComboForRipTrash = v ; KittyDPSDB.minComboForRipTrash = v end)

  RS("KittyDPS_Sl_FBCP",  "Min CP for FB (boss)",           3, 5,   1, -245,
    function() return cfg.minComboForBossFB end,
    function(v) cfg.minComboForBossFB = v ; KittyDPSDB.minComboForBossFB = v end)

  RS("KittyDPS_Sl_FBCPT", "Min CP for FB (trash)",          2, 4,   1, -300,
    function() return cfg.minComboForTrashFB end,
    function(v) cfg.minComboForTrashFB = v ; KittyDPSDB.minComboForTrashFB = v end)

  RS("KittyDPS_Sl_PSE",   "Max energy to trigger Reshift",  10, 40, 5, -355,
    function() return cfg.powershiftEnergyThreshold end,
    function(v) cfg.powershiftEnergyThreshold = v ; KittyDPSDB.powershiftEnergyThreshold = v end)

  RS("KittyDPS_Sl_PSM",   "Min mana for Reshift",           100, 500, 10, -410,
    function() return cfg.powershiftMana end,
    function(v) cfg.powershiftMana = v ; KittyDPSDB.powershiftMana = v end)

  local resetBtn1 = CreateFrame("Button", nil, tab1, "UIPanelButtonTemplate")
  resetBtn1:SetPoint("BOTTOMLEFT", 0, 0)
  resetBtn1:SetWidth(160)
  resetBtn1:SetText("Reset to defaults")
  resetBtn1:SetScript("OnClick", function()
    KittyDPSDB = CopyDefaults(defaults, {})
    cfg = KittyDPSDB
    UpdateMinimapButtonPosition()
    KPrint("|cffffa500KittyDPS: all settings reset to defaults.")
    root:Hide()
    optionsRoot = nil
  end)

  -- ── Tab 2: Energy Costs ────────────────────────────────────────

  local costTitle = tab2:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  costTitle:SetPoint("TOPLEFT", 0, 0)
  costTitle:SetText("|cffecd226Spell Energy Costs")

  local costSub = tab2:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  costSub:SetPoint("TOPLEFT", costTitle, "BOTTOMLEFT", 0, -6)
  costSub:SetWidth(560)
  costSub:SetJustifyH("LEFT")
  costSub:SetText(
    "Override the energy cost the rotation assumes for each spell.\n" ..
    "Examples: Idol of Ferocity  -3 Claw  |  Idol of Brutality  -10 Claw.\n" ..
    "Ferocious Bite has no entry here — use 'Min energy for FB' on the Rotation tab."
  )

  local function CS(name, label, minV, maxV, step, yOff, getter, setter)
    return CreateSlider(name, tab2, label, minV, maxV, step, 0, yOff, getter, setter)
  end

  CS("KittyDPS_Sl_CRake",  "Rake cost",  20, 50, 1, -80,
    function() return cfg.costRake end,
    function(v) cfg.costRake = v ; KittyDPSDB.costRake = v end)

  CS("KittyDPS_Sl_CClaw",  "Claw cost",  20, 55, 1, -135,
    function() return cfg.costClaw end,
    function(v) cfg.costClaw = v ; KittyDPSDB.costClaw = v end)

  CS("KittyDPS_Sl_CRip",   "Rip cost",   20, 50, 1, -190,
    function() return cfg.costRip end,
    function(v) cfg.costRip = v ; KittyDPSDB.costRip = v end)

  CS("KittyDPS_Sl_CShred", "Shred cost", 40, 70, 1, -245,
    function() return cfg.costShred end,
    function(v) cfg.costShred = v ; KittyDPSDB.costShred = v end)

  local resetBtn2 = CreateFrame("Button", nil, tab2, "UIPanelButtonTemplate")
  resetBtn2:SetPoint("BOTTOMLEFT", 0, 0)
  resetBtn2:SetWidth(180)
  resetBtn2:SetText("Reset costs to base values")
  resetBtn2:SetScript("OnClick", function()
    for _, k in ipairs({"costRake", "costClaw", "costRip", "costShred"}) do
      cfg[k] = defaults[k]
      KittyDPSDB[k] = defaults[k]
    end
    KPrint("|cffffa500KittyDPS: energy costs reset to base values.")
    root:Hide()
    optionsRoot = nil
  end)

  optionsRoot = root
end

local function OpenOptions()
  if not optionsRoot then CreateOptionsUI() end
  if optionsRoot:IsShown() then
    optionsRoot:Hide()
  else
    optionsRoot:Show()
  end
end

-- ============================================================
-- Minimap button
-- ============================================================
local function CreateMinimapButton()
  if minimapButton then return end

  local btn = CreateFrame("Button", "KittyDPS_MinimapButton", Minimap)
  btn:SetWidth(32)
  btn:SetHeight(32)
  btn:SetFrameStrata("MEDIUM")
  btn:SetNormalTexture("Interface\\Icons\\Ability_Druid_CatForm")
  btn:SetPushedTexture("Interface\\Icons\\Ability_Druid_CatForm")
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  btn:RegisterForDrag("RightButton")

  btn:SetScript("OnClick", function()
    OpenOptions()
  end)

  btn:SetScript("OnDragStart", function()
    this.isMoving = true
  end)

  btn:SetScript("OnDragStop", function()
    this.isMoving = nil
  end)

  btn:SetScript("OnHide", function()
    this.isMoving = nil
  end)

  btn:SetScript("OnUpdate", function()
    if not this.isMoving then return end
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    mx = mx / scale
    my = my / scale
    cfg.minimapAngle = deg(Atan2(my - cy, mx - cx))
    KittyDPSDB.minimapAngle = cfg.minimapAngle
    UpdateMinimapButtonPosition()
  end)

  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("KittyDPS", 1, 0.65, 0)
    GameTooltip:AddLine("Left Click: open options", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Right Drag: move button", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("/kdps dps  — run rotation step", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  minimapButton = btn
  UpdateMinimapButtonPosition()
end

-- ============================================================
-- Status print
-- ============================================================
local function PrintStatus()
  local function Flag(v) return v and "|cff24D040ON|r" or "|cffD02424OFF|r" end
  KPrint("|cffffa500KittyDPS v1.1|r loaded — /kdps for help")
  KPrint("  Auto-target:          " .. Flag(cfg.autoTargetEnabled))
  KPrint("  Faerie Fire:          " .. Flag(cfg.useFaerieFire))
  KPrint("  Tiger's Fury:         " .. Flag(cfg.useTigersFury))
  KPrint("  FB on trash:          " .. Flag(cfg.useFerociousBiteOnTrash))
  KPrint("  Bleed immune detect:  " .. Flag(cfg.autoDetectBleedImmune))
  KPrint("  Powershift (Reshift): " .. Flag(cfg.usePowershift))
end

-- ============================================================
-- Event handler
-- Vanilla 1.12: SetScript("OnEvent", function()) with no args.
-- Event name and arg1..arg9 are implicit globals inside handler.
-- PLAYER_ENTERING_WORLD fires after SavedVariables are loaded
-- and is the standard init event for 1.12 addons.
-- ============================================================
-- Prevents PrintStatus from firing on every zone change.
-- PLAYER_ENTERING_WORLD fires on each load screen, not only on first login.
local loaded = false

local eventFrame = CreateFrame("Frame", "KittyDPS_EventFrame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

eventFrame:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    KittyDPSDB = CopyDefaults(defaults, KittyDPSDB or {})
    cfg = KittyDPSDB
    catFormIdx    = GetCatFormIndex()
    reshiftFormIdx = GetReshiftIndex()
    CreateMinimapButton()
    if not loaded then
      PrintStatus()
      loaded = true
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    doclaw = 0
  elseif event == "PLAYER_REGEN_ENABLED" then
    doclaw = 0
  elseif event == "UI_ERROR_MESSAGE" then
    -- Shred failed: player is not behind target
    if arg1 and strfind(arg1, ERR_NOT_BEHIND) then
      if doclaw == 0 then doclaw = 1 end
    end
  elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    if arg1 then
      if strfind(arg1, MSG_SHRED_HIT) then
        doclaw = 0
      elseif strfind(arg1, MSG_CLAW_HIT) then
        if doclaw == 1 then
          doclaw = 2
        elseif doclaw == 2 then
          doclaw = 0
        end
      end
    end
  end
end)

-- ============================================================
-- Slash commands
-- ============================================================
SLASH_KITTYDPS1 = "/kdps"
SlashCmdList["KITTYDPS"] = function(msg)
  msg = msg or ""
  msg = string.lower(msg)

  if msg == "dps" then
    DoDPS()
    return
  end

  if msg == "cfg" or msg == "config" or msg == "options" then
    OpenOptions()
    return
  end

  local function Flag(v) return v and "|cff24D040ON|r" or "|cffD02424OFF|r" end
  KPrint("|cffffa500───── KittyDPS v1.1 ─────")
  KPrint("|cffecd226/kdps dps|r     Execute one rotation step  |cff999999(spam this in combat)|r")
  KPrint("|cffecd226/kdps cfg|r     Open the options panel")
  KPrint("|cffffa500Current state:")
  KPrint("  Auto-target:          " .. Flag(cfg.autoTargetEnabled))
  KPrint("  Faerie Fire:          " .. Flag(cfg.useFaerieFire))
  KPrint("  Tiger's Fury:         " .. Flag(cfg.useTigersFury))
  KPrint("  FB on trash:          " .. Flag(cfg.useFerociousBiteOnTrash))
  KPrint("  Bleed immune detect:  " .. Flag(cfg.autoDetectBleedImmune))
  KPrint("  Powershift (Reshift): " .. Flag(cfg.usePowershift))
  KPrint("|cffffa500──────────────────────────────")
end
