# Validation plan

This plan separates simulation correctness, human playability and distribution evidence. Passing one layer does not imply the others pass. Use the version in `docs/implementation-contract.md` and record the exact runtime/build for every run.

## Recorded automated result

On 2026-10-30, the working-tree simulation and `tests/test_campaign.gd` passed **10 behavioral groups, 170 checks, 0 failures**, with process exit code 0 and no script errors in the test output. Runtime: `Godot Engine v4.7.2.stable.official.ed1daf0bf`, Linux x86_64. No tagged release/export checksum had been assigned to this working-tree test.

Command actually used from the project directory:

```bash
/home/sti/Documents/Codex/2026-10-29/x20-s/work/runtime/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tests/test_campaign.gd
```

The groups cover reset/pause; walkable terrain, cliffs and explicit ramps; paid worker construction; production ingredients and local fuel/power; barracks training, population reservation and training-save continuation; disconnected camp operation, physical evacuation delivery and urgent abandonment without inventory teleportation; command-camp destruction with/without a fallback, canceled work and real defeat; pursuit versus a destructible sealed choke; actual exit construction/arrival versus a fifteen-minute wait; and JSON roundtrip/invalid-state rejection without live-state replacement. The save-continuation checks include active construction, movement and training.

The simulation result alone does **not** verify graphical interaction, audio/options, key rebinding, clean-machine exports, a human full-mission playthrough, performance targets, external player acceptance, or Steam configuration/review. Additional rendered integration evidence is recorded below. Rerun the suites after relevant changes and keep results associated with the candidate build.

## Rendered UI integration suite

`tests/test_ui.gd` creates the actual main scene in a 1600×900 rendered window. Run it from the project directory on a working display with isolated game data:

```bash
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/test-ui-data" /home/sti/Documents/Codex/2026-10-29/x20-s/work/runtime/Godot_v4.7.2-stable_linux.x86_64 --path . --script tests/test_ui.gd
```

The script refuses to run unless `user://` resolves below that project-local test-data directory. It clicks the HUD's drawn hotspots, sends key/wheel events through the main input controller, and uses the controller's world-coordinate drag-box interface for selection. It checks new game, groups, zoom limits, minimap camera/orders, placement cancellation, targeted clear/guard/escort selection and cancellation, production and training orders, pause/resume, real F5/F9 disk state, corrupt saves, and settings rebinding across scene reconstruction. Clear uses an actual minimap hotspot target; guard additionally exercises the controller's explicit context-target entry point. It saves `work/ui-test.png` and `work/ui-settings-test.png` for visual inspection.

On 2026-10-31 this suite passed **124 checks, 0 failures**, exit code 0, with no `ERROR` or `SCRIPT ERROR` in the final run. The real window used the OpenGL compatibility renderer on an NVIDIA GeForce RTX 5060. The macro-task checks confirm that choosing a task does not immediately mutate simulation orders, clear/guard target the selected forward area rather than the camp center, and Escape/world-right-click cancellation leaves orders unchanged. A malformed-UI-metadata save initially exposed partial state replacement; the final rerun verified the corrected transactional rejection, and malformed JSON now returns a user-facing load error without an engine-error stack.

This combination verifies UI-to-controller-to-simulation wiring and actual rendering. It does not emulate a human using native mouse input, prove discovery/accessibility, measure input latency, or demonstrate that a person can complete the campaign. Both final 1600×900 screenshots were visually inspected: no obvious button overflow or major panel collision was found, and the rebound production key appeared as `[U]` consistently in the settings and bottom dock. Wider resolution/hardware and human usability tests remain open.

## Automated simulation suite

Run from the project directory with the downloaded Godot executable:

```bash
/absolute/path/to/Godot --headless --path . -s tests/test_campaign.gd
```

The suite exits nonzero on a failed check and prints the failed invariant. It may create small controlled fixtures using the public simulation state to isolate rules; it must not call a different implementation or weaken an assertion to accommodate a defect. Test counts and logs are evidence only for this simulation layer.

| Area | Required positive case | Required negative/control case |
| --- | --- | --- |
| Terrain and paths | Squad/roads reach a valid destination by walkable routes and explicit crossings. | Outside-map, impassable and cliff-crossing construction/order cannot bypass terrain or consume resources for a rejected action. |
| Construction | A valid order deducts the declared cost once and workers/engineers perform the work before the structure functions. | Insufficient materials, duplicate placement and an impossible route are rejected; construction is not instantly complete. |
| Production | A supplied, powered workshop consumes the real recipe input and fuel while producing output. | Idle, no workshop, no local generator, no fuel, no raw input, and an abandoned camp cannot create resources. |
| Recruitment | A completed powered barracks takes a paid training order, progresses in simulation time and spawns the correct friendly unit only when training finishes; an active training save resumes correctly. | Missing barracks/power/resources, abandoned camp, invalid kind or a reached/reserved population cap cannot create units; power loss pauses rather than completes training. |
| Camp autonomy and transport | A disconnected forward camp can spend its own fuel/inventory; packing moves people/materials through a real transfer sequence. | Cutting one road does not remotely delete inventory or teleport it to a different camp. Material arrives only after physical transport. |
| Pursuit and sealing | Pursuit advances under normal play; a built choke barrier delays it while taking damage and eventually becomes passable. | Sealing cannot trap designated friendly survivors behind the choke; a barrier cannot freeze pursuit forever. |
| Exit/outcome | Cleared, connected, funded, powered and worked exit can finish; required survivors/vehicle reach it before victory. | Merely waiting, walking to an unbuilt exit, clearing it without supply, or losing all required survivors cannot yield victory. |
| State integrity | JSON save/load roundtrip preserves meaningful state and later simulation continuation. | Wrong version, missing fields, invalid types, duplicate IDs, out-of-bounds/NaN coordinates, impossible inventories and malformed links are refused without mutating the live state. |

## Full-mission playthroughs

### Recorded command-driven first mission

`tests/test_mission_playthrough.gd` is a reproducible full-mission run using reset, tick, move/attack, build, recipe, evacuation and sealing commands. It does not inject inventories, damage, terrain or pursuit timing. The run completed at simulation time 1547.2 seconds (25 minutes 47 seconds): three camps established, both resource branches cleared/connected, two evacuation transfers, urgent abandonment leaving raw fuel behind, west choke sealed, exit constructed/powered and command truck with five survivors at the exit. Final stocks were approximately 183 materials, 88 supplies and 52 fuel. The process exited 0. Log: `work/mission-playthrough.log`.

This proves at least one coherent mission/economic route is executable by public commands. It is an expert scripted route, not evidence that an unfamiliar human discovers the plan, enjoys it, can manage raw input, or can win on a different route. A rendered packed-resource smoke run also exited 0; clean-machine native export and full packed-build manual play remain open.

```bash
./run.sh --headless --script res://tests/test_mission_playthrough.gd
```

Perform these in an exported build as well as in the editor. Record route, timings, resource decisions, ending and any workaround.

1. **Northern materials route:** advance to the quarry, clear it, connect the road, establish production, move the camp forward and complete the exit.
2. **Southern fuel route:** secure fuel first, then obtain materials using a different ordering. Verify neither branch silently supplies the other branch's missing prerequisite.
3. **Rear evacuation:** leave people and inventory at the starting camp, prepare a forward camp, pack the rear camp, observe actual transfers, then seal the first choke. Confirm the UI describes any blocked sealing action.
4. **Energy shortage:** interrupt fuel delivery, observe local reserves and priorities, restore the road or deliver fuel, then recover without a broken mission state.
5. **Pressure failure:** overstay, allow the pursuing force to reach a rear site, and verify a clear, reachable defeat rather than a frozen or unfinishable session.
6. **Exit requirements:** reach the exit before preparation, inspect requirements, obtain the missing prerequisites, complete the work, and evacuate the required survivors/vehicle. Confirm the final report matches actual rescued/lost people.
7. **Save/resume:** save during construction, combat, packing and exit preparation; quit the process; reload and continue each case. Corrupt a copy of a save and verify recovery leaves the previous valid session/save intact.

## Input and options matrix

Check mouse selection/drag, multi-selection, move/attack/task orders, road/structure placement and cancellation, priority/recipe controls, evacuation and choke orders, pause/speed, camera pan/zoom, menus and help. Rebind all essential actions, restart, and repeat one mission section. Test duplicate bindings, invalid resolution choices, 1280×720/1920×1080/high-DPI, window resize, focus loss, and UI scaling. Verify audio sliders by listening and after restart; label settings honestly if a sound channel is not present yet.

## Performance and soak

Profile an exported release build at normal and maximum strategic zoom during the largest planned simultaneous zombie wave, road construction, transport and evacuation. Log hardware/OS, renderer, resolution, friendly/enemy/building counts, frame times and memory. Run at least one continuous mission and a one-hour repeated start/save/load/finish soak. Measure pathfinding spikes and pursuit encounters rather than only an idle starting camp. Set a minimum-machine claim only after testing real representative hardware.

## External-playtest checklist

Recruit target players beyond the development team and hand over a clean build with the in-game tutorial. Observe without explaining the controls. Record whether they understand the forward objective and rear threat, can identify power/road failures, can explain when to abandon a camp, and can finish/restart independently. Record a voluntary retry and concrete decision explanations as directional design evidence; a small sample is not a sales prediction. Fix blockers and run another cohort before claiming onboarding is complete.

## Asset and release audit

Maintain a shipping-asset manifest with path, author/source, license/permission, modification and attribution requirements, generation tool where applicable, and whether the asset actually ships. Concept images outside the build are not a substitute for this audit. Verify all advertised screenshots show real delivered behavior.

On clean Windows and Linux machines: install the export, launch without Godot/editor dependencies, complete a mission, create/resume a save, change options, restart and uninstall. Steam configuration and optional advertised features require additional Steam-account/depot tests described in `docs/release-gates.md`; local automated tests do not close those gates.

## Evidence log format

For every candidate record: date, build/commit, runtime, command or manual scenario, OS/hardware, expected result, observed result, pass/fail, log/video path and remaining issue. Preserve failed observations. `Not run` and `not implemented` remain distinct from `passed`.

## Navigation/combat and busy-scene evidence — 2026-10-31

This section adds evidence for the navigation/combat iteration; it does not replace the earlier campaign, UI or public-command playthrough records.

`tests/test_navigation_combat.gd` checks observable positions, target arrival, inventory delivery, completed buildings, actual damage and subsequent state. It does not call private pathfinding, separation or line-of-sight helpers as the proof of correctness. The initial implementation exposed five failures: final infantry overlap, firing through a workshop, firing through an intervening solid high plateau, missing legal elevated fire across a canyon, and melee through an unconnected cliff edge. A further dense-pursuer regression correctly exposed separation bypassing the pursuit front. These failed observations led to product fixes rather than weaker assertions.

The expanded suite passed **9 scenarios, 86 checks, 0 failures**, process exit 0 and no script errors, on 2026-10-31 against simulation SHA-256 `68e07ddfb56e1c1b934d96028def730e74fa24e0ef4d42a5fe37221c88ba974c`. In addition to the original scenarios, it covers forty pursuers crowded against the front limit, a live workshop destroyed by actual pursuit damage ceasing to block subsequent fire without manual cache reset, and balanced evacuation loading. The latter verifies actual 50-fuel/40-food reserve shortfall loading, remaining material capacity, material-first behavior when the receiver already has reserves, partial dispatch when source stock is insufficient, source deductions and physical delivery. Ordinary food consumption is isolated in a separate staging camp for exact cargo-conservation checks; these are controlled rule fixtures, not a balanced full-campaign playthrough.

```bash
/home/sti/Documents/Codex/2026-10-29/x20-s/work/runtime/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tests/test_navigation_combat.gd
```

### Reproducible CPU simulation workload

```bash
/home/sti/Documents/Codex/2026-10-29/x20-s/work/runtime/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -s tests/benchmark_campaign.gd -- --runs=3 --warmup=120 --samples=600 --save-every=150
```

Hardware/runtime reported by the process: Intel Core i7-14700, 28 logical processors, Linux/Ubuntu 22.04, approximately 60.7 GB physical RAM, Godot 4.7.2 stable. This is the editor-capable development runtime in headless mode. Other OS activity, CPU scheduling and power policy are not controlled.

Each of three independently reset runs uses 120 warm-up ticks and 600 measured `sim.tick(0.05)` calls: 6 simulated seconds warm-up plus 30 measured simulated seconds per run, 1,800 measured calls in total. The actual mission terrain contains 32 live friendlies and 100 live enemies in near contact, powered production, paid construction, supply roads, workers/vehicle hauling and four real JSON save/write/read/validate cycles per run. Actor/existing-building HP is deliberately increased to preserve the requested workload; combat, movement, collision, construction and resource transfer still execute. This is a controlled stress fixture, not a balance or fair-difficulty playthrough.

The same benchmark source and parameters produced these valid snapshots; each retained the exact 32/100 population, observed three actual resource-parcel deliveries and completed two ordered buildings per run. The simulation source was unchanged during each complete measurement.

| Snapshot | Simulation SHA-256 prefix | Tick p50 | Tick p95 | Tick p99 | Maximum tick | Process RSS high-water |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Navigation implementation before connectivity/circle-check optimization | `bae9e0b4` | 23.056 ms | 27.941 ms | 30.798 ms | 37.387 ms | 130.6 MB |
| Cached connectivity and exact circle/grid intersection | `883a6fb6` | 20.793 ms | 25.827 ms | 28.242 ms | 35.715 ms | 131.0 MB |

Raw reports, including full hashes, each sample, per-run variation, memory measurements and workload counters:

- `docs/benchmarks/2026-10-31-navigation-before-cache.json`
- `docs/benchmarks/2026-10-31-navigation-cache.json`

These are curated copies of the original `work/benchmarks/` reports so the evidence remains available in version control and source packages; transient test saves are not included.

Percentiles use the nearest-rank method across individual measured calls. Tick timing excludes instrumentation, JSON serialization, disk I/O and validation; those operations are measured separately. In the cached snapshot, twelve save measurements had median serialization 7.888 ms, temporary-file close/rename 0.491 ms, and read/parse/semantic-validation 10.750 ms. These buffered-write timings are not an fsync/power-loss durability test. RSS/VmHWM comes from Linux procfs; Godot static allocation is recorded separately and is not presented as process RSS.

**These are CPU simulation timings, not 60 FPS evidence.** They omit rendering, GPU work, input, audio and platform integration, and do not establish minimum hardware or release-build frame pacing. The 20–28 ms typical/tail tick costs remain material and need full-frame profiling and further optimization. Each snapshot applies to its recorded source hash; later rule changes are not silently assigned the same measurement.


## Guide, input, settings and persistent recovery — 2026-10-31

The 0.2 development iteration adds actual runtime modules `campaign_guide.gd` and `campaign_save_store.gd`. The guide reads genuine capture, completed construction, transport and exit state; it cannot award progress by clicking a button. It can be hidden, expanded or camera-focused, and its state persists with the campaign. The file layer keeps manual and automatic slots independent, stages validated writes, preserves a valid last backup even when the primary is corrupt, and rolls back interrupted replacements within the tested filesystem scenarios.

| Suite | Current passing evidence | Scope |
| --- | ---: | --- |
| `tests/test_ui.gd` | 124 checks | Real scene/HUD, production, training, groups, minimap, save/load and rebinding; rerun after the audio changes |
| `tests/test_preferences_recovery.gd` | 286 checks, 6 groups | Rendered guide focus/hide, bad-guide transaction rejection, explicit auto/backup recovery, restart confirmation/cancel/old-run recovery, all 23 action remaps/conflicts, persistent display and audio, master gain clamp and genuine zero-level mute, separate Music/SFX zero and restore |
| `tests/test_input_dispatch.gd` | 48 checks, 7 groups | Engine event dispatch for world selection/double-click, visible-kind selection, menu blocking, drag/pan ending over HUD, zoom and keyboard actions |
| `tests/test_save_store.gd` | 134 checks, 8 groups | Real isolated files: validated writes, exact-byte backup rotation, invalid/truncated/oversized reads, unwritable destinations, staged failures/rollback and preserving foreign temporary files |
| `tests/test_cross_process.gd` | 90 checks | Separate writer and reader OS processes; title-HUD load restores midway roads, production, movement, guide and integer-typed selections/groups; full payload continuation equals the writer baseline at 1/5/15/35 simulated seconds |
| `tests/test_guide.gd` | 102 checks | Read-only observation, click non-completion, preferences, malformed metadata rejection, and a full real mission through three deliveries, abandonment, powered exit work and actual arrival. The explicitly partial `-- --quick` run is 45 checks. |

Every listed run exited 0 without engine/script errors. Graphical runs used the Linux NVIDIA compatibility renderer described above. The cross-process artifacts are retained under `work/cross-process-data/` (summary, execution PIDs and baseline); each scenario refuses to operate outside its project-local isolated user directory. The writer and reader have different PIDs and the original writer exits before reader execution.

The rendered recovery tests first exposed and then verified fixes for two user-visible errors: restarting silently discarded a run, and JSON-decoded float IDs broke membership checks used by selection, groups and guide hints after a load. The product now asks for restart confirmation, writes the old run to the independent auto slot before reset, and normalizes restored IDs before guide observation. Audio tests also caught an unclamped master step above 100%; master levels now clamp and zero levels mute the real bus.

Engine input tests inject events through `Viewport.push_input` and `Input.parse_input_event` with OS cursor alignment; they do not call HUD/controller action helpers. They still are synthesized tests, not human hardware input or usability proof. Audio bus assertions do not replace listening. File failure/rollback checks do not simulate sudden power loss or every filesystem. Cross-process continuation does not yet cover every combat/packing/exit checkpoint or native Windows. Fresh-player onboarding, accessibility and broad device/platform acceptance remain open.

### Full-guide mission and evacuation congestion fix

The complete guide suite on simulation SHA-256 `9b918e3649df7e2a5d7a997417e798addd3b9752ff3f47063c9dcb0ba07e2d38` passed 102 checks with exit 0 and no engine/script warnings. It reached the genuine three-delivery forward-stock condition at 1011.6 simulated seconds, finished the powered exit at 1576.4, and achieved actual command-truck/survivor victory at **1590.0 seconds (26:30)**. Every guide milestone, hide/restore and final reset assertion remained active. Log: `work/guide-full-latest.log`.

The full-mission investigation exposed a gap missed by first-parcel tests: four evacuation workers stopped at the first position within 2.5 tiles of the depot, blocking its loading approach. A real recorded failure had an empty truck waiting 327.4 seconds, 3.2267 tiles from its origin, after only one delivered load. `tests/fixtures/evacuation-return-blocked.json` preserves that genuine state. The corrected simulation assigns distinct legal staging positions away from the loading approach and waits for each assigned target; a saved layout marker preserves resumed paths. Older packing saves migrate once. Resuming the unchanged failure fixture now loads the next 180-material parcel and starts its outbound trip after 7.6 simulated seconds, without injecting stock, moving actors directly, disabling collision or reducing costs. Broader regression and stress records follow below.

The independent `test_mission_playthrough.gd` also passed against that same source hash at **1590.0 simulated seconds**, exit 0. This revised public strategy uses observed inventories and completed deliveries rather than the historical fixed-time abandonment schedule. It retains paid defenses, both cleared resource branches, three built camps, real sealing and an explicit urgent abandonment. The home convoy delivered three times and the middle convoy five times. Abandonment left 83.73 supplies, 43.9291 fuel and 84 crude; no inventories or HP were injected. The powered exit completed at 1576.4 seconds, then six survivors and the command truck actually arrived. Final stocks were approximately 104.96 materials, 19.81 supplies and 17.4426 fuel, with no unfinished buildings. The physical elapsed time was 161.73 seconds on the development runtime; it is not a rendered-FPS result. Versioned logs are retained as `docs/evidence/mission-0.2.txt` and `docs/evidence/guide-0.2.txt`. The older 1547.2-second run above remains historical evidence for the earlier implementation.


## Final staging candidate regression and stress snapshot

On simulation SHA-256 `9b918e3649df7e2a5d7a997417e798addd3b9752ff3f47063c9dcb0ba07e2d38`, the complete navigation/combat suite passed **11 scenarios, 125 checks, 0 failures**, exit 0. It includes three successive physical flat-terrain deliveries at 21.4/56.2/91.0 seconds, recovery of the unchanged real blocked-return fixture, distinct packing targets, preservation of layout version/targets/paths over JSON saves and repeated loads, deterministic subsequent cargo continuation, and atomic rejection of a malformed layout version. The dense pursuer-front concern described in the earlier snapshot is now included and passing. Baseline campaign checks (170) and the two-process continuation suite (90) were also rerun successfully after the staging fix. Logs are local `work/navigation-final.log`, `work/campaign-final.log` and `work/cross-process-final.log`.

The final three-run busy workload completed with **1,800 measured ticks**, unchanged source throughout, and no benchmark errors. Each run retained 32/32 friendlies and 100/100 enemies, three actual resource deliveries, two completed paid buildings and 5,670 observed combat-effect samples. Tick p50 was **20.987 ms**, p95 **25.896 ms**, p99 **28.335 ms**, maximum **33.863 ms**; process RSS high-water was **132.604 MB** (decimal). Twelve saves had median serialization 7.906 ms, buffered write/rename 0.450 ms, and read/parse/semantic validation 15.853 ms. The older and final measurements are separate observations, not a statistically controlled comparison.

The complete raw final record, sample timings, workload counters, runtime details and source hashes ship with the source as `docs/benchmarks/2026-10-31-navigation-staging-final.json`. This remains a development-runtime, headless CPU workload. It does not establish rendered frame time, native release performance, minimum hardware, input/audio behavior or clean-machine support. The full-frame 60-FPS target remains an open release gate.

The final rendered UI rerun also exposed a notification timing race: the passive simulation-message pulse could overwrite a newly displayed load error. Passive notices now wait while explicit action feedback is visible. The corrupt-save test waits across the 250 ms pulse and still sees the load error; the full 124-check UI suite passes with no errors or audio-resource leaks. Preferences/recovery (286) and separate-process recovery (90) also passed in the final staging iteration.


## Official native development exports

The candidate exports use the pinned official Godot 4.7.2 Linux/Windows x86_64 release templates, with editor/test/work/build files excluded and Godot/font notices beside the binary. The Linux native template executable and its adjacent PCK were run from their own build directory in isolated user directories, without launching the editor: fixed-60-step headless smoke performed 80 simulation ticks with 30 live actors, and the real compatibility-rendered run produced a 1440×810 campaign image. Both processes exited 0 without engine/script errors or leaked-resource reports. The native screenshot was visually inspected for obvious layout failures. Full machine/runtime arguments, binary/PCK/image hashes and the narrow verification scope are retained in `docs/evidence/native-smoke-0.2.json`.

The Windows file is a PE32+ x86_64 GUI executable and has been exported/checksummed; it has **not been executed on Windows**. Linux startup/capture does not establish clean-machine dependencies, a full native human mission, minimum hardware, final audio/art acceptance or Steam readiness. Source export provenance and each downloadable artifact's checksums are generated by the release tools; the packages remain explicitly marked development builds.

## 0.3 campaign and rendering iteration

Three independent missions now run through the same simulation and save layer. Catalog tests (152) cover legal routes, bridge cuts, valley alternatives, finite resource floors, original Canyon compatibility and malformed visual regions/colors. Variant tests (115) cover mission reset/load identity, atomic rejection, real construction/power and evacuation save continuation. Complete Delta/Ridge public routes each pass 116 checks: real three-camp progression, both resources, transport, deliberate abandonment, sealing, actual JSON checkpoint reload and funded/powered exit arrival. Times are 1654.3 seconds/5 evacuees and 1782.5/6; original Canyon remains 1590.0/6. Versioned route records are under docs/evidence/v0.3.

Mission guide tests (137) include actual paid opening roads/camps plus explicitly identified later-stage fixtures; original full guide102 still wins. Selection/short-screen114, original UI124, preferences286 and separate-process90 pass. Cache GPU23 checks verify read-only state, vector fallback, cargo/selection changes, live completed roads, pan/zoom, all-three-map geometry refresh and actual water/rock palette pixels. These are integration/renderer evidence, not human usability acceptance.

The simulation CPU optimization retained complete encoded state at every tick in a 600-tick pair. The unchanged canonical1800-tick workload improved median20.987→14.756ms, mean21.454→15.176, p9525.896→18.289 and p9928.335→20.699. All three optimized runs retained32/100 actors, real combat, hauling, construction and valid saves. Raw evidence: docs/benchmarks/v0.3/simulation-optimized.json and docs/evidence/v0.3/simulation-paired-state.txt.

Full1920x1080 editor-capable measurements used120 warmup+600 measured frames per zoom, the same controlled32/100 fixture and actual20Hz main loop. Original observed FPS was14.659 normal/9.979 strategic. Ground/minimap caching measured21.678/17.252; adding the original-art actor atlas measured32.846/25.270. Raw reports preserve each stage's source hashes, exact sample intervals and workload counters. Faster600-frame runs cover less simulated time, and source stages differ; this is not a fixed-simulation-time controlled experiment or native export proof. No minimum-machine or stable60-FPS claim follows.

An instrumented short attribution run identified scenery reconstruction as2.04/4.64ms per frame normal/strategic. Its short duration missed a full haul delivery, so the canonical workload verifier correctly rejected it; it is retained only as hotspot evidence (draw-hotspots.txt). Scenery now has a separate transparent cache after roads, invalidated by geometry and road-key changes. The final native runner adds an actual autosave at frame300; save/read verification wall time remains in frame301.

The native runner is `--render-diagnostics`. Set BENCH_ISOLATION_ROOT to a fresh absolute work directory and XDG_DATA_HOME/CONFIG_HOME/CACHE_HOME to separate children; it refuses existing game settings/saves, unsafe paths, symlink escapes and mixed/invalid parameters before Main reads settings. Example after export:

```bash
BENCH_ISOLATION_ROOT="$PWD/work/benchmarks/native-candidate-a" \
XDG_DATA_HOME="$PWD/work/benchmarks/native-candidate-a/data" \
XDG_CONFIG_HOME="$PWD/work/benchmarks/native-candidate-a/config" \
XDG_CACHE_HOME="$PWD/work/benchmarks/native-candidate-a/cache" \
DISPLAY=:0 ./builds/linux-release/outpost-exodus.x86_64 -- \
  --render-diagnostics --frames=600 --warmup=120 --max-seconds=180
```

The report and both screenshots are written under that root/output. Quick checks are explicitly not performance evidence. Release reports identify compiled/imported source rather than treating missing.gd hashes as verification; executable/adjacent PCK hashes and runtime workload checks bind native observations to the actual artifact. The packaging tool requires both zooms, full sample coverage and a successful actual save for the current Linux payload; measuring does not automatically pass the60-FPS/minimum-hardware gate.

Recognized mission tags are also bound to an inner identity marker for the new levels. Variants115 includes all six known-tag swaps, missing/wrong-type markers and atomic rejection; original Canyon legacy payloads remain byte-compatible. Both complete new routes were rerun after this change, each116/0, with real checkpoint loading and the same recorded victories. Their latest evidence replaces the earlier pre-marker temporary logs.


The first native 0.3 measurement was rejected: strategic zoom stored a legal minimum as float32 0.349999994, just outside the former double-precision validation bound. The maximum 1.6 endpoint can round outward too. A narrow 0.000001 validation tolerance plus clamped restoration preserves real endpoint saves while rejecting 0.3499/1.6001. Actual minimum/maximum zoom disk roundtrips add eight assertions; selection now passes114/0. The failed native attempt is retained in docs/evidence/v0.3/native-candidate-a-rejected.json. It is not passing performance evidence. A fresh native measurement of the corrected export is required before packaging.


## 0.3.1 behavior-preserving performance iteration

No simulation frequency, unit budget, AI cadence or workload changes. Conservative axis rejection reduces unnecessary per-neighbor radius/distance work, with exact contact math and neighbor order retained. The complete encoded state and serialized entry order match the0.3 baseline at every one of720ticks. Canonical standalone3x600timed ticks plus120warmup per run retain all32/100 actors, real combat, hauling, two completed buildings and four validated periodic saves per run: mean15.043647→12.644658ms,p9518.298→15.354. Raw reports, source hashes and reproduction helper texts are under docs/benchmarks/v0.3.1.

Campaign170 and navigation132 pass; the latter includes seven configuration-bound assertions. All three real public-command routes were rerun: original guide102 wins at1590.0seconds/6evacuees; Delta116 at1654.3/5; Ridge116 at1782.5/6. The new-map routes still serialize/load during evacuation and actually fund/power/complete the exit. These remain scripted route evidence, not uncoached human acceptance.

HUD caches only immutable presentation inputs. The new layout286 checks cover changed text/size/width/punctuation/fonts and bounded eviction. Existing renderedUI124, preferences286 and selection114 pass. Clean verbose isolated120frame-per-mode HUD runs have byte-identical decodedRGBA across gameplay,campaigns,settings,help,guide; gameplay draw CPU median1.978→1.275ms. A prior ignored probe's music-playback teardown leak was diagnosed and corrected; fresh measurements have clean exits.

Native oval5 checks require nonempty rendered pixels and preserve exactRGBA for193shapes, including reflected/rotated caller transforms, alpha and eviction/reconstruction. The corrected isolated median is802→580microseconds. GPU cache23 still passes with the shared primitive change. Whole-game native FPS is measured separately for the actual export and attached to that build; none of these isolated CPU values prove stable60FPS.

The first0.3.1native export measured50.239normal/48.608strategicFPS with successful real saves; strategic maximum122.172ms exposed remaining synchronous-save cost. That pre-formatting stage is retained with its own payload hashes. Compact JSON formatting then shrinks the same canonical420tick payload398196→146158bytes. Twelve fresh pairedAB/BA slots with six writes each use the actual Main validator: first-write p5032.364→24.883ms, repeated p5075.817→54.143,p9580.213→56.357. Full precision, sorting, schema validation, limits, backup bytes, staging and rollback stay enabled. Save-store134 and cross-process90 were rerun after the one-line change and pass. Final native frame report ships with the actual Linux build and exact payload hashes.
