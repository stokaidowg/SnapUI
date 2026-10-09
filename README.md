# SnapUI

A complete UI replacement for vanilla WoW, in the spirit of pfUI and ElvUI. For **OctoWoW** (the 1.12 client). It may work on Turtle WoW and other 1.12 servers, but it was only made and tried on OctoWoW.

> [!WARNING]
> **Made with AI.** This add-on was written by an AI (Claude, by Anthropic) using Claude Code. I'm not a programmer: I described what I wanted, played with it on OctoWoW, and reported problems back for the AI to fix. It has automated tests against a simulated WoW API, but some features have only been tried by me, and a few not in game at all yet, so expect bugs. Please report them under **Issues**.

## What's in it

- **Themes**: font, bar texture, colours, pixel-perfect borders, shadows and accent strips, applied to every part of the UI.
- **Unit frames**: player, target, target of target, pet, with cast bars (showing who a spell is aimed at), heal prediction and a mana-cost preview of the spell you're casting.
- **Party and raid frames** (Grid-style): role icons (set them yourself, or let it guess from play), a coloured square when someone has a debuff you can remove, and optional pet and tank windows.
- **Action bars**, stance/pet bars, micro menu, XP bar.
- **Nameplates**, **buffs/debuffs**, **tooltips** (vendor prices, and an "upgrade" line for gear).
- **Bags and bank** in one window each, with search, bag slots and the keyring.
- **Chat**, **info bars**, **minimap**, a **damage/heal meter** (`/meter`).
- **Quality of life**: open all mail, notes on friends, a windowed world map with the unexplored areas revealed, restyled loot rolls, auto-sell greys, mouse-over fading per element.
- **Edit mode** with a snapping grid, and **profiles** per character.

## Requirements

- Turn **pfUI off**: SnapUI replaces it, and running both will clash.
- Some features use the OctoWoW launcher mods (**nampower**, **ClassicAPI**, **SuperWoW**): heal prediction, the mana-cost preview and cast targets need them. Everything else works without.

## Install

1. Download `SnapUI.zip` from the [Releases](../../releases) page. Don't use GitHub's green **Code → Download ZIP** button: it gives a folder named `SnapUI-main`, which WoW won't load until you rename it to `SnapUI`.
2. Extract it into `Interface\AddOns`, so you end up with `Interface\AddOns\SnapUI\SnapUI.toc`.
3. Restart the game, or type `/reload` if you're already logged in.

## Usage

- `/snap config`: settings
- `/snap`: edit mode (drag things around; they snap to a grid)
- `/meter`: damage/heal meter
- `/snap role tank|healer|dps|auto`: set your target's role (or Alt-right-click them on the party/raid frames)

## Credits

The textures and fonts in `media/` come from [pfUI](https://github.com/shagu/pfUI) by Shagu (MIT licence, see `media/pfUI-LICENSE.txt`). The fonts belong to their designers: Expressway, Continuum and Die Die Die (Ray Larabie / Typodermic), Big Noodle Titling (Sentinel Type), Homespun (Brian Kent), Hooge (Ralph Hoogeveen), PT Sans Narrow (ParaType, SIL Open Font Licence) and Roboto Mono (Google, Apache 2.0).

## Licence

MIT for the code, see [LICENSE](LICENSE).
