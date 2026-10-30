# Current development checkpoint

Project: 逐营突围 / Outpost Exodus, version **0.2.0-dev**. The active objective remains a highly playable game that meets Steam release standards. This is a substantial internal first-campaign build; the objective is not complete.

## Implemented and verified

- Actual Godot 4.7.2 project with original 2D cartoon terrain/characters, generated transparent building sprites and Chinese UI. Runtime logic is separate from rendering and controls. Six game scripts total 5,989 physical lines, including comments/blank lines; tests and tools are counted separately.
- Real selection/groups, 23 rebindable commands, minimap, camera zoom/pan, paid construction, independent camp stocks, local fuel/power, production, training, physical transport, pursuit, staged evacuation, destructible sealing and genuine exit work/arrival requirements.
- Body separation, legal cliff/ramp movement and formation slots; solid high terrain/buildings block shots, open canyon air permits elevated fire, and melee cannot attack through disconnected cliff edges.
- A dismissible 11-step contextual guide follows actual state. Its complete public-command mission passes 102 checks and wins at 1590.0 simulated seconds (26:30), after both resource branches, three camps, real multi-load transfers, abandonment, a sealed rear choke, powered exit construction and vehicle/survivor arrival.
- 170 baseline simulation checks, 124 rendered UI checks, 286 rendered preferences/recovery checks, 48 engine-event dispatch checks, 134 isolated file-layer checks and 90 separate-process continuation checks pass. Detailed scopes and limits are in validation-plan.md.
- Manual and auto slots are independent. Validated staged writes preserve exact-byte backups and tested rollback behavior. Explicit menu recovery and restart confirmation preserve progress. Integer selection/group IDs remain valid after JSON load. Mid-road/production/movement save continuation matches a separate process through 35 simulated seconds.
- Full-mission replay caught evacuation workers parking in the loading lane. The original failed state is retained as a regression fixture. Distinct staging slots fix both new evacuations and old packing saves; the unchanged stuck snapshot resumes its next physical 180-material load within 7.6 simulated seconds. Navigation/combat regression includes that case and repeated multi-load delivery.
- Real Music/SFX buses, independent levels and zero-volume mute, an original synthesized background loop, persisted window/fullscreen/resolution/UI scale, conflict-safe remapping, safe restart and clean audio shutdown are implemented. Bus tests do not substitute for listening/accessibility testing.
- Official Linux and Windows x86_64 release templates are pinned and verified by file digest. Export tooling requires committed source, records export provenance, ships font/Godot notices and excludes editor/test/work assets. Native Linux headless/rendered smoke is tied to current exe/pck hashes before packaging. Windows execution remains unverified.
- Local Git is initialized. No GitHub remote repository has been created or pushed. Source archives are local deliverables, not remote backups or a settled public license grant.

## Remaining work toward the full objective

1. Observe fresh players using the delivered guide and actual hardware input without coaching. Validate the early micro/later macro transition, power/road clarity, abandonment decisions, alternative routes and difficulty pacing.
2. Improve terrain landmarks, character animation, effects, audio mix and UI readability while retaining the cartoon direction. Complete provenance/license and accessibility review.
3. Add genuinely different independent campaigns once first-mission decisions and pacing are tested. One campaign is currently implemented.
4. Profile full rendered native frames at 1080p, strategic zoom and peak evacuation. CPU-only stress measurements are not 60-FPS or minimum-hardware proof. Add extended start/save/load/finish soak and wider seeds/layouts.
5. Test native Windows and clean Linux machines, full packed-build playthrough/save recovery, final icons/version metadata and missing-device behavior.
6. Complete actual Steam account/App ID/store/depot/build review and any explicitly advertised Steam features. This project does not yet configure or verify those external steps.

No open gate above is treated as passed. See release-gates.md and validation-plan.md for recorded evidence, historical failures and practical limits.
