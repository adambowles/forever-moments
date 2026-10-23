# Forever Moments 1.0.1

A standalone World of Warcraft: Forever addon that automatically takes screenshots of milestones and small discoveries. Designed to capture generously rather than miss moments. No dependencies, telemetry, or third-party libraries.

## Install and update with instawow

Configure an instawow profile pointing at Forever's `_forever_/Interface/AddOns` directory. If Forever is not detected automatically, select the directory manually.

```sh
instawow install github:adambowles/forever-moments
```

Once installed, use `instawow update` to receive future GitHub Releases. Alternatively, enter the repository URL into an add-on manager that supports GitHub Releases.

**Important:** instawow requires a published GitHub Release with an attached installable ZIP. The source-code ZIP generated automatically by GitHub is not an installable release asset. The release workflow builds the required ZIP containing `ForeverMoments/ForeverMoments.toc`, Lua files, README and LICENSE.

## Install

Extract `ForeverMoments/` to:

`World of Warcraft/_forever_/Interface/AddOns/ForeverMoments/`

That directory must directly contain `ForeverMoments.toc`, `Core.lua`, and `Options.lua`. Restart the client and enable **Forever Moments** in the character-select AddOns menu.

Target: World of Warcraft: Forever interface **16001** (modern client, *not* WotLK 3.3.5a). In-game compatibility has not yet been verified.

## Commands

- `/fm` or `/moments`: open the category settings window.
- `/fm snap`: queue a manual screenshot (obeys the active spacing interval).
- `/fm on` and `/fm off`: enable/disable automatic screenshots.
- `/fm status`: show successes, failures, queued triggers and periodic interval.

All settings persist account-wide; visited zones are recorded per character.

## Screenshot categories

| Enabled by default | Optional / disabled by default |
| --- | --- |
| Level-ups, personal achievements, criteria | Subzones |
| Boss victories, boss wipes, deaths | Reputation messages |
| PvP matches, PvP kills, duels | Guild achievements |
| Quest turn-ins, new main zones | Login / world entry |
| High-quality loot, learned recipes | Periodic screenshots (5 to 60 min) |
| Renown / PvP ranks, collections, instance completions | |

The **Capture everything** preset opts into *all* categories (including subzones, reputation, and logins), lowers the gap to 1 second, saves Uncommon+ loot, enables a screenshot every five minutes and removes first-visit-only zone restrictions. The **Default** and **Only big milestones** presets are also available.

Other settings: loot quality threshold, time between screenshot attempts, event delay, UI hiding (outside combat), chat notices and first-visit-only zone discovery.

## Where screenshots go

Screenshots are stored by the game at `_forever_/Screenshots` under your WoW install directory. The addon cannot choose the filenames or read screenshot files. For high-quality JPGs you can run `/console screenshotQuality 10` or change screenshot format in the game settings.

## Known limitations

- Forever uses modern WoW event hooks and protected combat data. Low-health triggers, combat-log triggers and automated rare-enemy kill detection are deliberately not implemented because they cannot reliably examine protected combat information.
- Collection and certain instance events might not be emitted in every Forever client version. Unknown events are skipped safely rather than causing load errors.
- Item-loot capture uses item messages and quality. It may include loot awarded to other nearby players, and uncached item details are deliberately captured to avoid misses.
- Many events can happen close together. The addon spaces out screenshots, deduplicates identical triggers for six seconds, and discards very old queued moments. Several different milestones close together can still produce several screenshots.
- When hiding the UI, the addon restores it after the game's screenshot event or a three-second safety timeout. It will not hide the interface during combat.
- If the client does not fire SCREENSHOT_SUCCEEDED/FAILED, the timeout prevents lock-ups but successful captures are not counted as successes.
- Screenshots are timestamped by the game. The one-second spacing in Capture everything avoids identical time-based filenames.

## Release automation

The workflow at [`.github/workflows/release.yml`](.github/workflows/release.yml) runs after changes to the add-on on `main`, on version-tag pushes and when started manually from GitHub Actions.

It validates the version in `ForeverMoments.toc` against `addon.version` in `Core.lua`, packages a single top-level `ForeverMoments/` directory into `ForeverMoments-vX.Y.Z.zip`, tests the archive, uploads it as a workflow artifact, and publishes a **GitHub Release with the ZIP attached**.

For a subsequent release:

1. Update `## Version` in `ForeverMoments.toc` and `addon.version` in `Core.lua` to the same new version.
2. Commit and push to `main`.
3. The workflow creates the `vX.Y.Z` tag, release and ZIP asset if that version has not already been published.

Existing release assets are deliberately not overwritten by a same-version commit. To distribute an update through instawow, **increase the version**.

## Notes for debugging

Enable `Display Lua Errors` in WoW's options if a future game update changes interface functions. Check `/fm status` after `/fm snap` to confirm the screenshot success event fires, and verify a new image in your Screenshots folder.

License: MIT. Unofficial fan addon, not associated with Blizzard Entertainment.
