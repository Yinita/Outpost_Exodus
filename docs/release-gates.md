# Release gates

Status baseline: 2026-10-31. This project is an implementation in progress. A running scene, an exported executable, passing simulation tests, and an approved Steam product are different milestones. **The current project must not be described as Steam-ready.**

The gates below are this project's quality bar, not a claim that every item is a mandatory Valve rule. A gate is complete only when its evidence is recorded for the exact candidate build. `Unverified` is not a pass.

| Gate | Acceptance evidence | Current status |
| --- | --- | --- |
| Campaign rules | Headless tests cover terrain crossings, paid construction, local fuel/power, production inputs, actual barracks training and population limits, transport/packing, camp loss, pursuit, delaying barriers, real exit construction and evacuation. | 170 automated checks passed on 2026-10-30; full playable-mission/manual gates remain open |
| Complete playable mission | A fresh player can start, choose a northern or southern resource route, establish a forward camp, abandon a rear camp, delay pursuit, prepare the exit and reach a truthful victory/defeat result. Restart and return to menu work. | Current public-command mission and full-guide route both win in 1590.0 seconds; fresh-human and alternate-route playthroughs remain open |
| Early-to-late attention transition | Early squad movement and combat matter. Later clear/escort/guard/repair orders and camp priorities allow meaningful macro decisions without repetitive individual-unit babysitting. | Requires external playtest |
| Onboarding | In-game, dismissible instruction teaches selection, movement, attack/task orders, road building, supplies/power, packing, sealing, and the actual exit requirements. All critical failure causes are explained. | Read-only 11-step contextual guide implemented and tested; fresh-player discovery, failure explanations and pacing remain open |
| Input | Every essential action can be rebound, conflicts are explained, cancel/back always works, remaps persist, and UI receives focus correctly. No gameplay action leaks through menus. Controller support is tested only if advertised. | 23 actions rebindable with conflict checks; rendered options suite and 48 engine-event dispatch checks pass. Native human interaction and wider devices remain open |
| Options and accessibility | Master/music/effects levels, mute, resolution/window mode, scale/readability and pause behavior work and persist. Critical ownership, power and threat states have a non-color-only signal. | Rendered persisted audio/display/scale checks pass on this Linux machine; listening, focus policy, high-DPI/wider hardware and accessibility review remain open |
| Saves | Versioned saves preserve mission, inventories, construction, combat units, orders, pursuit, barriers and RNG state. Roundtrip continues the same simulation. Invalid, truncated and incompatible data fail before replacing the current state. File writes are atomic and a last-known-good save can be recovered. | 134 file-layer checks and 90 two-process continuation checks pass; rendered explicit backup/auto recovery and confirmation-before-restart pass. Power-loss durability and platform-specific filesystems remain open |
| Technical reliability | No parser errors, unhandled script errors, invalid indexes, NaN coordinates, negative inventories, duplicate IDs, stuck workers, or guaranteed-unreachable mission objectives across the supported scenarios. | 170 baseline simulation checks plus 125 navigation/combat/evacuation checks pass; broader seeds/routes and soak remain open |
| Performance | A named minimum machine and scene budget are published. Exported builds are profiled at 1080p through the peak pursuit/evacuation section, including saves and strategic zoom. Proposed target: stable 60 FPS, no repeated >100 ms gameplay stalls; hardware limits remain provisional until measured. | No minimum hardware claim yet |
| Art, sound and text | Every shipping asset has a provenance/license record, including fonts, generated content, sound effects, music and localization. Required notices ship. Art direction and UI remain legible at normal play zoom. | Procedural/temporary assets are not a complete shipping asset audit |
| Windows and Linux builds | Both native release exports install and launch on a clean machine without the editor, have correct icons/version, save to writable user data, handle missing devices, and include required runtime/licenses. Full mission and save/load smoke tests pass on each OS. | Official release-template exports assemble on Linux; Windows execution, clean-machine full mission, final icon/version metadata and device tests remain open |
| Steam distribution | Correct App ID, packages, launch options, depots and release branches are configured and tested by a non-developer account. Store claims match the delivered build and languages/platforms. Required content survey, store/build reviews and release tasks are completed in Steamworks. | Not configured/verified in this project |
| Steam features | Any advertised overlay, achievements, stats, cloud saves, Steam Input or Deck support is implemented and tested. Offline launch has an explicit supported behavior. Cloud, if enabled, excludes machine-specific display settings and has account/cross-platform conflict tests. These features are not all prerequisites for publishing. | Not integrated; do not advertise |
| External validation | Target players outside the development team complete the mission without live coaching; issues are recorded by build ID, severity and reproduction. Blocking usability, progress-loss and soft-lock defects are resolved and rechecked. | Not started |

## Candidate sign-off

Record candidate version/commit, export checksums, Godot version, OS/hardware, test commands and logs, playthrough result, known issues, and named reviewer for each gate. Keep failures visible rather than replacing them with a successful screenshot. Any save-loss, impossible route, fake outcome, crash, or advertised-feature failure blocks release. Balance and presentation findings receive an explicit fix or documented product decision.

The first internal milestone is **a verified complete mission**. It does not close the Steam-release objective or the external-test gates.

## Steam sources

Official references checked 2026-10-30:

- [Steamworks review process](https://partner.steamgames.com/doc/store/review_process): store presence and the product build require review; approval is separate from local build validation.
- [Steamworks content survey](https://partner.steamgames.com/doc/gettingstarted/contentsurvey): complete the applicable general, mature and generative-AI content questions before review. Track AI-created player-facing assets in the provenance inventory so the answers can be accurate.
- [Steam Cloud](https://partner.steamgames.com/doc/features/cloud): optional cloud configuration requires deliberate save paths and cross-platform behavior; avoid synchronizing machine-specific video settings.

Recheck these official pages when preparing a real submission because platform policy and tooling can change.
