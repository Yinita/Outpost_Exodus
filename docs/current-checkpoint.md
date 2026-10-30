# Current development checkpoint

Project: 逐营突围 / Outpost Exodus, **0.3.1-dev**. The objective remains a highly playable game that meets Steam release standards. This internal candidate is not release acceptance.

## Proven work

- Three selectable independent campaigns: Canyon/裂谷突围, Delta/双桥湿地 and Ridge/山脊换防. They have different legal terrain/ramp/bridge routes, resource placement, retreat positions and pursuit timing. Each begins with its own inventory and forces. Wetland water/bridges and ridge rock palettes are rendered from mission visual metadata.
- Public-command victories: Canyon 1590.0 seconds/6 evacuees; Delta 1654.3/5; Ridge 1782.5/6. New routes complete both resource branches, three camps, real deliveries, west-gate sealing and deliberate abandonment. Each new route actually serializes/loads during middle-camp evacuation, then pays 140 materials/45 fuel/30 supplies and completes the real six-power exit before vehicle/survivor arrival.
- Catalog reset/save integration preserves the original Canyon creation order, initial encoded state and rift_escape_01 save tag. New mission tags are validated before live-state replacement. Invalid mission IDs fail atomically; mission definitions are returned as defensive copies.
- Read-only guide targets, branch text and safe gate checks follow actual mission landmarks. Existing north/south save values retain material/fuel meanings even where geographic directions reverse. Old v1 guide states remain readable. Partial-road hints now identify the remaining extension rather than prompting a duplicate order or unreachable camp.
- Campaign selection from title/pause/end menus, confirmation before replacing a live run, old-run AUTO recovery and manual/backup preservation. Short screens at 1280x720/120% keep selection, guide, settings, help and confirmation usable; controls paginate six per page there, ten on normal screens.
- Exact-state simulation optimization reduces the canonical 1800-tick CPU median from 20.987 to 14.756 ms. A 600-tick baseline/candidate pair compares complete encoded state after every tick. Campaign170, navigation132 and real full-mission victory remain passing.
- Static ground/cliffs, transparent decorations and minimap terrain are cached; roads, actors, cargo, selection, health, orders and effects remain live. Original procedural actors now also render into a reusable eight-frame atlas, retaining vector fallback. Native GPU tests cover read-only rendering, cargo/selection changes, actual completed roads, camera movement and three-map cache invalidation.
- Full editor-runtime rendered measurements established the original busy 1080p baseline (about 14.66 FPS normal/9.98 strategic), then staged improvements. These were real 32/100 actor workloads, not idle scenes. Final native exported performance and 60-FPS/minimum-hardware acceptance remain separate evidence.
- New original SVG app icon and generated PNG/ICO layers. Build-time LIEF/pefile tooling writes and independently re-parses Windows icons/version resources; all non-resource bytes, imports, manifest, entrypoint and subsystem are preserved. Native Windows execution remains open.
- Dedicated native render diagnostics runs only in a fresh isolated data root, measures actual main-loop frames and one real save per zoom, and records executable/PCK hashes. It is not a player-facing game mode and does not alter normal saves/settings.
- Earlier working input, construction, power, recruitment, convoy, pursuit, atomic save/backup, settings and native-launch behavior remain in place. Local Git only; no GitHub remote has been created or pushed.

- The 0.3.1 collision broadphase rejects only neighbors beyond the maximum configured radius before doing the unchanged exact contact checks. A further720-tick full encoded-state/order pair is identical; standalone canonical3x600 means15.044→12.645ms. All original rules, simulation frequency and actor counts remain unchanged. The permanent navigation suite now checks all seven configured radii against the prefilter bound.
- HUD caches only exact text layouts and panel styles, with bounded storage and font invalidation. Live state, hover, hotspots, camera/minimap and every-frame drawing remain. NativeRGBA is identical across five HUD modes; clean isolated gameplay HUD median1.978→1.275ms. Reused oval geometry retains exact native pixels including caller transforms and alpha.

## Evidence

See docs/evidence/v0.3.1 and docs/benchmarks/v0.3.1 for this performance iteration, plus earlier v0.3 evidence and validation-plan.md. Linux build bundles also carry the exact-payload native frame report; a measurement does not pass the60-FPS/minimum-hardware gate. Passing counts include campaign170, navigation132, file-store134, catalog152, variants115, new full routes116 each, original guide102, mission guide137, campaign-selection114, UI124, preferences286, separate-process90, GPU cache23, new HUD layout286, native oval5 and diagnostic preflight40. Fixture, synthetic event and scripted route scopes do not prove uncoached human playability.

## Still required

Fresh-player observation and alternative human routes; difficulty/pacing and failure recovery tuning; final animation/audio mix/localization/accessibility/focus review; full native frame pacing/soak/minimum hardware; clean Windows/Linux installation and full packed-build play; final asset/license audit; and actual Steam account/store/depot/build review and any advertised Steam features. No open gate is silently passed, and the goal remains active.
