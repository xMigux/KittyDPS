# KittyDPS

KittyDPS is a feral **Cat Form** DPS helper addon for **WoW Classic+** servers that expand
the vanilla 1.12 feral talent tree with bleed-enhancing talents such as **Open Wounds**
and **Carnage**.

It provides a one-button rotation macro (`/kdps dps`), a two-tab in-game options UI,
and a minimap button. It is compatible with the vanilla 1.12 addon API.

---

## Compatibility

KittyDPS is built for **vanilla 1.12 addon API** servers that include an expanded feral
talent tree with the following talents:

| Talent | Effect |
|---|---|
| **Open Wounds** | Claw deals bonus damage when Rake is active; Rip grants a 15-second buff that further increases Claw damage per combo point spent |
| **Carnage** | Ferocious Bite has a chance to refresh Rake and Rip and to generate extra combo points |
| **Blood Frenzy** | Tiger's Fury also applies **Blood Frenzy**: +20% attack speed and +10 energy every 3 seconds for 18 seconds |

The rotation logic degrades gracefully if some of these talents are not taken —
toggle off the features you don't use via `/kdps cfg`.

---

## Features

- **One-button DPS rotation**
  Create a macro with `/kdps dps` and spam it in combat.

- **Open Wounds + Carnage aware**
  - Keeps **Rake** and **Rip** up for bleed synergy.
  - Uses **Ferocious Bite** aggressively via Carnage to refresh bleeds and generate extra combo points.
  - Optional **max-energy FB mode**: fires FB early when a bleed is about to expire or energy is about to cap.

- **Tiger's Fury + Blood Frenzy aware**
  - Uses TF whenever the **Blood Frenzy buff** is not active.
  - In melee range: fires TF when energy is too low to cast but not so low that Reshift is preferred.
  - Out of melee range: fires TF immediately when buff is missing (pre-pull / approaching).
  - **Powershift is blocked while Blood Frenzy is active** — shifting cancels the buff, and the 20% attack speed + energy regen is always worth more than the energy saved from a shift.

- **Bleed immunity handling**
  Detects targets that cannot bleed (Undead, Elemental, Mechanical, Totem) and switches
  to a Claw/Shred + FB rotation automatically.

- **Reshift-based powershift (optional)**
  Uses the **Reshift** ability when energy is low and mana is sufficient.
  Never fires while Blood Frenzy is active.

- **Energy cost overrides**
  A dedicated options tab lets you override the energy cost the addon assumes for each
  ability to match your actual setup (idols, talents). Examples:
  - Idol of Ferocity: Claw −3
  - Idol of Brutality: Claw −10

- **Auto-target, Faerie Fire, and minimap button**

---

## Requirements

- **Client version:** Vanilla 1.12 (TOC 11200).
- **Class / Spec:** Druid — Feral cat DPS.
- **Recommended talents:** Open Wounds, Carnage, Blood Frenzy 2/2.

---

## Installation

1. Download or clone this repository.
2. Copy the `KittyDPS` folder into:
   ```
   Interface/AddOns/KittyDPS/
   ```
3. The folder must contain both files:
   - `KittyDPS.toc`
   - `KittyDPS.lua`
4. Restart the WoW client.
5. On the character selection screen, click **AddOns** and enable **KittyDPS**.

---

## Usage

### DPS macro

Create a macro containing:

```
/kdps dps
```

Place it on your action bar in Cat Form and spam it in combat.  
KittyDPS executes one rotation step per key press — it is not an automation tool.

### Slash commands

| Command | Description |
|---|---|
| `/kdps dps` | Execute one rotation step |
| `/kdps cfg` | Open the options panel |
| `/kdps` | Print current state and command list |

---

## Rotation Logic

### When the target CAN bleed

Priority order:

1. **Max-energy Ferocious Bite** *(if enabled)*  
   Fires FB early when Rake or Rip will expire soon (≤ X seconds) or energy is about to cap (≥ Y).  
   Has higher priority than reapplying bleeds — with 5 CP, a Carnage proc will likely refresh the expiring bleed anyway.

2. **Tiger's Fury**  
   Used whenever the Blood Frenzy buff is not active and energy/position conditions are met.

3. **Rake**  
   Reapplied whenever it falls off.

4. **Rip**  
   Applied or refreshed when it has fewer than the configured seconds remaining.

5. **Ferocious Bite (standard)**  
   Used with both bleeds active at the configured combo point threshold (default 5 on bosses).

6. **Reshift** *(if enabled and Blood Frenzy is NOT active)*  
   Fires when energy is very low and mana is sufficient.

7. **Claw filler**  
   Default combo point builder when nothing else takes priority.

### When the target is BLEED IMMUNE

For Undead / Elemental / Mechanical / Totem targets:

- Skips Rake and Rip entirely.
- Uses **Ferocious Bite** at the configured CP threshold.
- Uses **Shred** when behind the target, **Claw** otherwise.  
  Position is detected automatically via combat error messages.

---

## Options: Rotation Tab

Open with `/kdps cfg` or via the minimap button.

**Toggles**

| Option | Default | Description |
|---|---|---|
| Auto-target nearest enemy | ON | Targets nearest enemy when no valid target exists |
| Apply Faerie Fire (Feral) | ON | Maintains Faerie Fire on the target |
| Use Tiger's Fury | ON | Uses Tiger's Fury via the Blood Frenzy logic |
| Ferocious Bite on trash | ON | Allows FB on non-elite targets |
| FB max-energy mode | ON | Uses FB early to avoid energy cap or save expiring bleeds |
| Detect bleed-immune targets | ON | Switches rotation on Undead/Elemental/Mechanical/Totem |
| Auto-Reshift | OFF | Uses Reshift when energy is low (never during Blood Frenzy) |

**Sliders**

| Slider | Default | Description |
|---|---|---|
| Min energy for FB | 35 | FB only fires at this energy or above |
| Energy cap trigger for FB | 80 | FB fires if energy ≥ this (max-energy mode) |
| Bleed seconds for urgent FB | 2 | FB fires if Rake or Rip has ≤ this many seconds left |
| Rip refresh threshold | 3 s | Refresh Rip when this many seconds remain |
| Min CP for Rip (boss) | 4 | Minimum combo points to cast Rip on bosses |
| Min CP for FB (boss) | 5 | Minimum combo points for Ferocious Bite on bosses |
| Max energy to trigger Reshift | 20 | Reshift fires when energy ≤ this value |
| Min mana for Reshift | 231 | Reshift only fires when mana ≥ this value |

---

## Options: Energy Costs Tab

Override the energy cost the addon assumes for each ability.  
Useful when idols or talents reduce costs below the base values.

| Ability | Base cost | Example reduction |
|---|---|---|
| Rake | 35 | — |
| Claw | 40 | Idol of Ferocity −3, Idol of Brutality −10 |
| Rip | 30 | — |
| Shred | 60 | Improved Shred talent |

**Ferocious Bite** does not appear here because it consumes all available energy above
its base cost by design. Control its behaviour via *Min energy for FB* on the Rotation tab.

---

## Minimap Button

- **Left-click:** Open the options panel.
- **Tooltip:** Shows addon name and `/kdps dps` usage reminder.

---

## Localisation

KittyDPS uses English spell names by default. If your server uses a different client
language, adjust the spell name strings at the top of `KittyDPS.lua`:

```lua
-- Spell names — adjust for your client language
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
```

---

## FAQ

**Q: Is this a bot or does it play for me?**  
No. KittyDPS only decides what to cast when you press your macro key.
You must press it yourself; nothing fires automatically.

**Q: Why should I never Reshift while Blood Frenzy is active?**  
Blood Frenzy gives +20% attack speed and +10 energy every 3 seconds for 18 seconds.
Reshifting cancels the buff immediately. Over the remaining duration you lose far more
DPS than the energy you regained from the shift.

**Q: Does it work in Bear Form or outside Cat Form?**  
The rotation only runs in Cat Form. If you are in any other form, the addon
will shift you to Cat Form and stop for that tick.

**Q: Can I disable individual features?**  
Yes — almost every feature has its own toggle in the options panel.

---

## Contributing

Pull requests and issues are welcome.  
Good candidates for future contributions:

- On-screen indicator showing active buffs/debuffs (Rake, Rip, Blood Frenzy timer).
- Encounter-specific overrides (e.g. disable autotarget in certain raids).
- Additional localisation strings for non-English clients.

---

## Acknowledgements

Inspired by [HolyShift](https://github.com/ZachM89/HolyShift) by **Maulbatross** —
the original feral cat one-button DPS addon for vanilla WoW 1.12.

KittyDPS was written from scratch with a fully updated rotation centred on the
Open Wounds and Carnage talents, but the one-button macro concept and the use of
combat event messages for Shred/Claw position detection were directly inspired by
that work.

---

## License

KittyDPS is released under the **GNU General Public License v3.0**.  
Copyright (C) 2026 [xMigux](https://github.com/xMigux)

This means you are free to use, study, modify, and redistribute this addon,
provided that any distributed version — including modified forks — is also
released under the GPL v3 and its source code is made available.

See the [LICENSE](LICENSE) file for the full licence text, or visit
[https://www.gnu.org/licenses/gpl-3.0.html](https://www.gnu.org/licenses/gpl-3.0.html).