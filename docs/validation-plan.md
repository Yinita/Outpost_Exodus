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


## 0.4 construction feedback and actor overlays

The construction planner and fresh try_build share the original acceptance order, local supply camp, cost and road/path rules. Roads still branch before building-only spacing/pursuit/distant-connection checks; builder presence remains advisory; exit power remains a progress gate. New query/status methods are read-only except transient navigation metadata. The controller caches preview calculations on simulation time/hover/type/relevant input and always re-queries on click. A727comparison legacy/current run matches seven actual order commits plus720canonical ticks exactly, including encoded entry order, with2996candidate-only preview/status operations. Three complete routes retain1590.0/1654.3/1782.5seconds and6/5/6evacuees.

Construction/production187 checks cover atomic rejection, read-only queries, nearest local inventory, whole-route costs, alias safety, fractional deficits, no-crew order acceptance, worker recovery, production and power diagnoses, and unpowered exit funding then powered progress. Rendered controller/HUD31checks cover stale-preview funds revalidation, exact current click feedback, continuous roads, same-time reset readout invalidation and compact controls at1280x720/1152x648 with120percentUI. Initial test assumptions about Canyon having no existing workshop were corrected: it starts with one working workshop, so a newly ordered second workshop should not block its output. Compact tests exposed overlapping resource/time and pause/preview titles; corrected screenshots are retained locally. ExistingUI124,preferences286,selection114 and actual engine-input48 pass.

Movement-only ABBA CPU runs retain all canonical workload/cost/save verification and reduce mean12.790→11.129ms,p9515.495→13.536. Exact720canonical full states and89dense/cache/live-death cases match. Typed sidecars were slower and are not shipped. Staged source snapshots and hashes identify what each measurement tested.

Four previously unused actor-atlas cells contain grounded shadows and selected/unselected rings for people/trucks; atlas dimensions are unchanged. Isolated132actor/32selected native redraw medians2695→541microseconds at1.05and2659→535at.35, drawcalls1342→139. Actual cyan-ring pixels are tested independently of body/HP overlays; selection/deselection, cargo, HP, facing, position and bob remain live. Positive pixels34 and existing world-cache23 pass. Foreground mean RGB raster-resampling error is2.75/255and2.70/255; maximum differences81/79occur at resampled overlay edges. These are local draw/CPU measurements, not whole-game FPS. Native diagnostic source manifests now include all runtime helpers/caches; preflight40passes. Exact-payload native frame reports ship with Linux builds and do not establish minimum hardware or stable60FPS.


## 0.5 macro controls, recruitment, audio and exit recovery

The candidate snapshot and complete raw logs are under [docs/evidence/v0.5](evidence/v0.5/README.md). This iteration records recruitment219, macro controls268, native audio200, exit recovery43, renderedUI124, engine-input48, preferences286, constructionUI31, diagnostic preflight40 and the full original Canyon guide102. Ordinary and accelerated campaign-selection runs each pass114 with clean audio shutdown. These recorded suite results are functional evidence, not a new minimum-hardware benchmark or human-playability acceptance.

Recruitment queries report local costs, missing resources, facility and power reasons, global population including queued units and the local four-entry queue. Clicks re-query before payment; stale previews cannot spend nonexistent stock. Focused tests compare accepted legacy/candidate encoded states and entry order, complete the real four unit types, continue queues after save/load and preserve two-camp ownership. Read-only calls may warm navigation caches but do not allocate power, spend resources or advance training. Normal evacuation still cancels all queued recruits and refunds half their costs; the UI discloses this existing rule. A retained inactive queue from an older/manual valid state pauses rather than progressing.

The macro suite uses actual controller/HUD input with explicit completion guards and a deadline. Its controlled six-camp fixture covers pagination, no snapback while browsing, same-ID focus, real world selection, cycling and rebinding. It checks four training cards and queue/status visibility at1600×900,1152×648 and1152×648 at120%UI (960×540 logical), persistent targeting feedback after notification expiry and a coverage toggle near the minimap. The fixtures and synthetic events do not demonstrate that a new player will understand the interface.

Eight original deterministic PCM16/22050Hz effects total88,992filebytes, reproduced byte-for-byte by `python3 tools/generate_sfx.py --check`. Their raw bundle SHA-256 is `32d9c5b7baec23394eb3ccbc50221db8d89893e977f90d824482c5878dd6ec3c`. No external samples or composition are used. Six world and two reserved UI voices cap playback; real-time cooldowns, camera attenuation and menu/pause/load/mute priming prevent old event bursts. A120tick full-simulation/save/RNG twin test stays identical. Native PulseAudio reports a nonzero SFX mixer peak (−28.5501dB in the recorded run), with eight preloaded streams. This proves routing/playback in that environment, not acceptable human listening, speaker/headphone behavior or final mix balance.

The actual imported music is QOA compressed. Its compressed214,184bytes previously implied107,092PCMframes and a short loop. The corrected endpoint is529,200decodedframes at22050Hz, matching the original RIFF file's24seconds; the test independently parses source frames. Accelerated shutdown initially passed114selection assertions but leaked twoObjectDB instances and one resource. That raw failure is retained. Processing/input stop before releasing players, then cleanup awaits at least120ms of actual `Time.get_ticks_usec()` time. Ordinary133.48ms and accelerated120.227ms post-fix runs pass114 with clean logs, and a separate actual quit probe records120.739ms, stopped processing and released streams. A simulation timer alone could finish before the audio thread under fixed-FPS acceleration.

Exit recovery first reproduces the real failure by placing a directory at the AUTO save destination, preserving prior real slot bytes for restoration. The baseline records11checks/twofailures: the old controller quit despite the failed write. The corrected suite records43/0 and verifies unchanged live state/selection/orders, preserved manual/backup/AUTO bytes, modal-only input, return to the original menu, repeated close/retry, successful exact-byte retry, explicit discard and title exit. It overrides only the final quit operation to keep the harness alive. It does not simulate every filesystem, power loss or native Windows close behavior.

Final0.5 export performance must use a fresh isolated root and the actual committed executable/PCK. Use120warmup plus3600measuredframes per zoom so a completed real haul and the normal45second autosave are observed; retain failed measurements as failures. Native Linux/Windows packaging and asset provenance remain separate from full human play, clean-machine/nativeWindows, minimum hardware, accessibility/listening and actual Steam review.

### Next fresh-player observation

Give a new player a fresh Canyon campaign with the in-game guide, without spoken coaching. Observe whether they can select a squad, use the minimap/zoom, order the first road and powered camp, diagnose a blocked training order and evacuate before the rear pursuit arrives. Record the first point of confusion, repeated misclicks, idle time and the reason for any loss. Later play should test whether camp overview, groups, transport and power allocation reduce repeated unit-level attention while the player chooses routes and abandonment timing. Compare observed behavior with actual replay/state evidence before changing costs or pursuit timing. Completion by a scripted route is not a substitute for this session.


## 0.6 display motion, focus/title recovery and casualty guidance

The candidate snapshot and recorded logs are under [docs/evidence/v0.6](evidence/v0.6/README.md). Motion correctness passes28headless and33nativeX11, focus/title recovery63, existing engine-input48 and exit recovery43, and the full Canyon guide211at1590.0seconds with actual exit arrival. The explicitly requested quick guide154 skips the full mission and is labeled accordingly; mission-guide137 covers the three real map openings. Scripted fixtures and native event dispatch do not constitute an uncoached human playtest.

Motion uses actual20Hz simulation snapshots and bounded interpolation, with at most one50ms simulation-step display delay at1×speed and no extrapolation. One120step moving workload compares complete encoded state/RNG against an unobserved twin after every actual tick and checks five fractional poses. Controller checks use a real movement command and a drag-box whose edge separates the visible actor from its authoritative position, then exercise actual disk save/load, pause/resume, same-ID mission replacement and3×speed. Native0/50/100percent pose images require nonempty rendered pixels and changed actor regions. Rendering time/gait, unit position, selection, logistics origins and depth/culling share the visual pose. Health, outcomes, combat, economy and saved state stay authoritative. Spawn or discontinuous position changes and pause/load/reset snap immediately. The independent20actual-step review probe is additional correctness evidence, not a timing benchmark or human smoothness verdict.

Focus policy is verified with a test-owned external nativeX11 window, not by treating a Godot child window as leaving the application. Its standard-libraryPython/libX11 helper restores prior focus and exits, and is not loaded by the game. Actual root focus-exit/entry and minimize/restore verify paused combat, immediate world-SFX retirement, held-camera action release without mapping changes, held gesture cleanup, pending order/selection/tactical-pause preservation, existing modal preservation and explicit continuation. Background input cannot resume, save or issue orders; background frames do not advance simulation or autosave clocks. The fixture uses actual native focus events but synthetic key/mouse dispatch and controlled frame calls, so physical user input and nativeWindows behavior remain unverified.

Returning to title first performs the real AUTO write and stays in the existing run/menu if that fails. The regression preserves all previous save bytes while a directory blocks the actual AUTO target. It verifies unchanged full simulation, selections and pending orders across repeated failures, an in-menu notice at1152×648/120percentUI, then valid exact-state retry and unchanged manual/backup bytes. The baseline records the earlier failed write followed by a title New replacing live time0.1with0; it is rejected source behavior. This differs from the separate diagnostic fixture attempts: wrong child-window focus semantics, event-pump assumptions and pre-normalized JSON number types were fixture errors and are retained with explicit diagnosis, not labeled shipping regressions or passing runs.

The opening guide previously requested four combat units even when only three survived. Updated read-only tests cover casualty counts/selection, zero-fighter queued/admissible/blocked recovery paths and exact state preservation. Recovery hints consult actual training status and recruitment reasons instead of claiming workers/trucks can clear guards. If recovery is no longer possible, guidance suggests loading or restarting without manufacturing a victory or changing resources. Original terrain, combat, construction, training and pursuit rules are unchanged.

Final0.6 export performance remains separate. Use a fresh isolated root with120warmup and3600measuredframes per zoom, retain real completed hauling/construction plus forced and ordinary45second saves, and bind the report to unchanged executable/PCK hashes. Reports from earlier versions cannot prove this candidate's native performance. Steam, human playability/listening, clean-machine/nativeWindows, stable frame pacing and minimum hardware remain open.


The first0.6 export was rejected by the clean-tree guard when import created four evidencePNG metadata files. These are now tracked; the premature native-v06-full process was terminated and is not accepted. A subsequent verified export at1dec8b36a6cf3cf098046f88b8a98def72000a3a completed native-v06-final but failed its workload: normal view received an initial native-window focus exit after fixture installation and recorded0ticks/no actual workload; strategic view recorded1206ticks, three deliveries and three completed builds. The full report correctly sets performance_evidence=false and valid_workload=false. Raw logs, rejected report checksum and exact payload identities remain under the0.6 evidence record. Diagnostic setup must settle actual focus before installing the measured fixture, without changing product focus pause, automatically resuming a running campaign or weakening workload checks. New accepted evidence requires a new clean export and native-v06-focused isolation; failed data is not relabeled or replaced.


The diagnostic-only startup correction now records native focus samples and waits for12consecutive focused/non-suspended/non-minimized rendered frames before installing the measured scene; failure remains an explicit diagnostic error. Its explicit quick editor-capable probe settles in about282milliseconds and observes4normal/5strategic real ticks with32/100actors, while current isolated preflight40passes. These are functional startup checks, not accepted performance or completed-haul evidence. An unchanged1dec nativeMainCLI smoke reaches80ticks/30units, retained with its earlier payload identity. The next full measurement still requires a newly exported committed candidate and fresh isolation.


The subsequent0.6`native-v06-focused` export at`f2894b3bdc13be0c513bfe10b9ad8cb5d3655c00` passed both3600frame workloads and real saves, with means59.790/59.625FPS. Its accepted report is external exact-payload0.6evidence; the preceding failed attempts remain historical records. It does not establish0.6.1performance or minimum hardware.

## 0.6.1 actual-loop native campaign validation

The new validator addresses a separate open gate: an entire campaign must execute through the actual exported Main loop, renderer and file layer. Existing headless source-project routes remain useful rule evidence; they do not prove the packed game's complete20 Hz execution. The bundled `--campaign-validation` entry uses the unchanged Canyon rules and public player commands. It retains normal Engine.time_scale = 1, chooses3×through normal UI actions and never calls `sim.tick()` or Main._process manually. Minimum simulated economic windows remain in the route, with actual completion/capture/delivery conditions added.

Main validates a fresh dedicated `CAMPAIGN_VALIDATION_ROOT` and XDG children before reading settings. The Linux helper also reads the actual process command line from `/proc/self/cmdline`, since Godot strips recognized engine arguments from its public argument list. Fixed-FPS, engine time-scale, disabled render-loop and movie-writing switches are rejected. Native focus must settle before start; product focus suspension stays active and interruption rejects the run. A separate wall-clock watchdog prevents a paused or stalled scenario from appearing complete.

At loaded outbound middle withdrawal, real synchronous `save_campaign()` and `load_campaign()` must preserve normalized complete simulation/RNG and saved UI metadata. The guide's derived cache is refreshed read-only before saving because Main refreshes it on load. IDs are retained and dictionaries re-read after load. Continued delivery, three actual middle parcels, deliberate remaining-stock abandonment, paid140 materials/45 fuel / 30 supplies exit construction, local power, command-truck arrival and at least four evacuees are required. Final primary/backup automatic saves must also validate.

Run the wrapper after a clean committed export, from a source checkout that contains the tools. After separate native frame/smoke checks and packaging, prefer the actual unpacked Linux download as `--build-dir`; a direct export directory is also supported:

```bash
DISPLAY=:0 python3 tools/run_native_campaign.py \
  --build-dir "$PWD/builds/linux-release" \
  --isolation-root "$PWD/work/native-campaign-v061-full-corrected" \
  --max-seconds 900
```

Use a different fresh root for `--prepare-only`. The launcher verifies source-commit metadata and EXE/PCK identities before and after the owned native process, rejects script/error/leak output, and validates `output/campaign-validation.json`. `output/campaign-progress.json` is observation only; `verification.json` cannot become successful until the final report, clean process exit and all exact-payload checks pass. Neither mode produces FPS evidence. Final0.6.1 full native route and native frame measurement are pending this candidate snapshot; eventual reports must bind to their actual EXE/PCK.

`docs/evidence/v0.6.1` retains the editor-capable prepare check, static/compile results and diagnostic guard/capability baselines with explicit limits. NativeWindows, clean machines, mouse-driven full UI, human playability/listening, final asset/accessibility/license review, minimum hardware/frame pacing and actual Steam review remain open.

A subsequent actual Main negative startup probe exposed processing before world initialization after a queued diagnostic refusal. Main now disables processing/input before quitting for validation rejection or unknown mission. The original nil-access baseline and clean fixed expected-exit2 output remain separate. Editor-prepare and48input records before this narrow negative-path fix are not claimed as exact final-Main evidence.

The final actual-Main source startup regression runs three isolated cases: campaign validation without its dedicated root, render validation without its root, and an unknown mission. All15checks pass, each process returns expected exit2 with the intended marker, and no script/error/leak output, settings/saves or source drift occurs. The Python test can target a native build after export; that mode is not claimed by the source result.

The first actual unpacked0.6.1 run at2a00 is a retained failed full-campaign attempt, not a completed route. It advances31483normal0.05second Main ticks/1574.15simulation seconds without clock discrepancies, preserves a real loaded-withdrawal disk checkpoint at911.8seconds, observes3home/4middle deliveries and ten valid automatic-file changes, then stops at a finished powered exit. Diagnostic extraction incorrectly interpreted the tagged public save Dictionary, so the paid-job assertion failed before final movement. The final state isplaying, evacuated0, truck17.117tiles from exit. Its exact original report, wrapper, process log, encoded final state and package identities are retained under0.6.1 evidence and the outer rejected snapshot.

The original encoded job is funded/delivered/done with140materials/45fuel/30supplies; actual automatic-save times decode1452.0 and1316.95, while their old report summaries were null. The corrected source record suite passes94checks against the byte-identical real final-state fixture, verifies observation leaves complete simulation/RNG unchanged, and rejects16corrupted copies. This proves the diagnostic correction against actual data, not native victory. The entire native route must be rerun from a fresh exported/unpacked payload, with a fresh frame report for that payload; acceptance requirements remain unchanged.


## 0.7 enemy barrier approach, terminal guidance and asset records

The fallback applies only when an enemy's requested path is empty and an intact sealed choke lies between the enemy to the west and its target to the east. It selects a body-valid approach on the western face within the actor's current walk component. A normal reachable path bypasses the fallback. The two real approach/melee failures stay separate from the earlier test-only last-ULP JSON comparison failure. Complete saved tagged structures, fields and RNG strings remain checked; JSON int/float values are compared numerically, and only roundtrip error up to `1e-12` absolute or `2e-15` relative is permitted.

The distant-barrier controlled baseline has 26 checks/two failures; candidate 26/0, navigation 151/0 and campaign 170/0 are recorded. The complete Canyon guide passes 211 checks with confirmed process exit 0 and actual victory at 1590.0 simulated seconds; no evacuee count is inferred from that log. The actual 911.8-second snapshot replay advances baseline/candidate clones for 36 simulated seconds. Some baseline actors still move or attack older structures, and actors die in both runs. The candidate's original-cohort path count of 91→81 is not a fixed-population workload or a universal baseline-stall claim. Source, snapshot and replay-probe hashes accompany the records. This is headless state evidence, not a new native full route or frame benchmark.

Main updates victory/defeat guidance on the actual terminal frame without waiting for the ordinary 0.25-second refresh. Visibility preferences survive. Terminal tests cover visible, hidden and disabled settings, no duplicate terminal refresh, simulation/RNG observation safety, and ordinary/small native layouts. The earlier logs retain their tested snapshots. Separate final combined-source runs pass 76 headless and 78 native checks, retaining unchanged simulation `329f98a8…` and Main `889a4b7d…` hashes before/after. Final import exits 0. The ordinary/small-layout stage logs remain separately scoped. A separate ignored source probe explicitly calls actual Main in 0.05-second steps and passes the existing full simulation/UI disk save/reload oracle at 27 checkpoints from 0.05 to 29.95 simulated seconds. The diagnostic comparison was not changed. This is a short source check, not normal-time native execution or loaded-withdrawal full-route acceptance.

The font notice identifies the Noto CJK 2.004 collection's 10 embedded faces, Adobe 2014–2021 metadata, actual font SHA and complete official tagged OFL. Font bytes are unchanged. `python3 tools/generate_audio.py --check` regenerates the 24-second ambience in memory, encodes PCM explicitly as little-endian and refuses missing/corrupt targets without creating or repairing them. Temporary generation, import safety, metadata stability and original WAV digest were checked without playback. Native/human listening remains separate.

`docs/asset-inventory.json` and `docs/steam-content-survey-draft.md` record production methods and remaining decisions. An unsubmitted draft is not Steam approval, a rights grant or legal sign-off. The inventory owner refreshes final hashes after runtime/config changes. No new package, complete native route or FPS result is claimed by this pre-export 0.7 snapshot. Follow docs/benchmarks/v0.7 against the final clean export with fresh directories and bind reports to the actual EXE/PCK and source commit.


## Accepted 0.7 payload and current 0.8 boundary

The actual unpacked Linux 0.7 payload at `ede3c504f74843ca36dce6bff75d5d9107cb76da` subsequently passed the full Canyon route. It records 1595.65 simulated seconds, 532.757052 wall seconds, 31,913 actual 0.05-second Main ticks, zero invalid steps, five evacuees plus truck, three home/four middle deliveries, and complete simulation/RNG/UI equality through an actual loaded-withdrawal disk roundtrip. Funded construction, deliberate abandonment and actual powered-exit arrival remain required. Unchanged copies of its authoritative release summary, actual report/verifier and automatic-cycle result ship under `docs/evidence/v0.8/historical-v07-*`. Earlier v0.7 pre-export pending records remain historical.

Exact 0.7 busy-frame means are 59.7343464278487 FPS normal and 59.5384086408754 FPS strategic, each with 120 warmup/3,600 measured frames and the real 32-friendly/100-enemy hauling, construction and save workload. Native smoke, automatic-file validation and archive/package finalization passed. These development-machine results do not establish stable 60 FPS or minimum hardware and are not 0.8 measurements.

### 0.8 mission identity and complete source routes

The expanded runner/launcher requires agreement among requested mission, actual process argv, live/controller state, on-disk checkpoint, route, both automatic generations and final saved state. Stage preflight passes 79 checks, route configuration 103 and the read-only real Simulation mission-helper probe 30. The Python launcher suite passes 10 synthetic acceptance/rejection tests; it does not launch the native game. An initial preflight invocation omitting `--campaign-validation` correctly refused with exit 2 and remains an invocation correction.

The same production route also runs through an ignored source observer that calls public `Simulation.tick(0.05)`. Delta completes at 1664.4 simulated seconds/33,288 steps with five evacuees plus truck; Ridge at 1780.35/35,607 with six. Both record three home/four middle deliveries, both captured resource sites, deliberate abandonment and actual paid 140-material/45-fuel/30-supply exits at six-power demand. Actual disk checkpoints at 964.5/998.45 preserve complete normalized simulation/RNG and mission; exits complete at 1650.2/1766.35. Simulation `54e85c71…` and route `1f9b9e6c…` remain unchanged before/after each run. Reports, final states, actual checkpoints, logs and observer source are retained.

Those source probes do not instantiate Main or a real UI, and their capture entries are explicitly `rendered=false`; they do not prove actual-Main/native clock, controller/UI continuation, frame performance or human play. An earlier Ridge probe recorded victory but correctly failed overall because its source changed from `329f98a8…` to `54e85c71…` during execution. That mixed-source report/log/final state remains rejected verification evidence.

### 0.8 actual receiving-depot blockage

The real Delta source route initially failed at 1330.1 seconds: engineer 9 carried eight already-paid materials for road job 276 but three automatic idle workers and idle command truck 13 blocked receiving depot `(54,27)`. The unchanged 181,732-byte `tests/fixtures/delta-arrival-blocked.json` has SHA-256 `06846340fad76c74e3c0684d0255b893bcd6751471f5d2287c9a31f7ab0a1f6c`; its sidecar identifies the source, route, job and original failure. This was a genuine source-only product blockage, not native/Main-clock/performance evidence.

Baseline replay `329f98a8…` stays at zero road progress through another 60 simulated seconds. Candidate `54e85c71…` moves eligible automatic idle arrivals to separate legal waiting cells when a nearby crew/transport is stalled. The road is complete at the 10.05-second observation, through ordinary physical movement and the original paid cargo, without extra camp charge or manual route workaround. The regression passes 2,329 checks for real cargo/cost, static geometry, protected manual/guard/active-crew/moving-transport orders and disk continuation.

Assigned targets/paths and immediate normalized full-save equality remain exact. Subsequent full tagged state, entry order and RNG remain compared, with only numeric values under the existing `max(1e-12 absolute, 2e-15 relative)` JSON bound. The retained original strict mismatch states differ only in enemy 251 `nav_wait` (`0.49999999999999994`/`0.5`) and enemy 256 (`1.0000000000000002`/`1.0000000000000004`), one binary ULP each. A separate read-only structural analysis traverses every key/order/array shape and records those two differences. This numeric fixture diagnosis is separate from the product blockage; the actual-Main disk oracle was not weakened.

### 0.8 HUD and final source regressions

Construction thumbnails reuse actual world atlas regions, retaining road/missing-atlas fallback and real planner/cost checks. Different resource/exit shapes reduce reliance on color; the guide minimap marker follows actual started/visible state. Abandoned camps say “已弃守”, matching stock that can remain behind. Stage and final combined rendered UI each pass 124 checks.

A clean paused-source probe retains five capture records: title 1920×1080, Delta with guide at 1920×1080, guide visible/hidden at 1152×648/120% UI, and atlas fallback. Metadata records unchanged simulation. Assistant visual inspection and a 75-changed-pixel minimap-region comparison support the shown/hidden marker behavior; this is not an uncoached human playtest. PNGs stay outside source. The initial capture harness's audio teardown warnings and subsequent wrong-isolation assertion remain rejected fixture/invocation records, separate from the clean final capture and Delta's product bug.

Final navigation 151, campaign 170, variants 115, full Canyon guide 211, encoded-job extraction 94 and native-rendered terminal guide 78 all pass with confirmed clean exit 0. The full guide reaches actual victory at 1590.0 seconds; no evacuee count is inferred from its log. Terminal simulation `54e85c71…` and Main `889a4b7d…` remain unchanged before/after. Final editor import exits 0, generating normal metadata for the two new GDScript tests. Line counts include the actual Python launcher test separately from build/generation tools and exclude copied probe text.

This frozen source candidate precedes the new export. Current actual-Main full native missions, loaded-withdrawal UI continuation and exact-payload frame acceptance remain pending. Human playability/listening, Windows/clean machines, minimum hardware, final own-code/art terms and Steam account/store/content-survey/depot/review gates remain open.


## Accepted 0.8 payload and current 0.9 work

The same actual unpacked Linux 0.8 payload at `d1c24ce113f276b785ffb90d54fd774716c4fee8` subsequently passed all three strict actual-Main routes. Canyon: 1580.40 simulated seconds/527.721882 wall seconds/31,608 ticks/five evacuees; Delta: 1664.35/561.578633/33,287/seven; Ridge: 1774.75/592.617775/35,495/six. Each uses normal engine time, standard UI 3× and actual 0.05-second Main steps with zero invalid increments. Each preserves full simulation/RNG/UI and mission identity on actual loaded-withdrawal disk reload, observes three home/four middle deliveries and original funded/completed/powered exit plus real truck/survivor arrival.

Busy native frame means are 59.7606863395305/59.6196583767077 FPS with 120 warmup/3,600 measured frames and actual hauling/construction/saves; maximum intervals are 67.456/80.865 ms. Smoke, automatic-file checks, archives and finalization passed. This does not establish stable 60 FPS, minimum hardware, one-hour reliability, Windows, human playability or Steam approval. Unchanged copies of the authoritative release report and three report/verifier pairs are under v0.9 evidence; committed v0.8 pre-export files remain unchanged.

The initial outer Delta launcher ended 143 while its game continued to victory. Its pending verifier was not accepted; original interrupted records remain separate, and a later managed strict run provides Delta acceptance. No game-only success or unfinished wrapper is promoted to complete validation.

For the new 0.9 work, the actual-engine-input pager baseline on the old 0.8 worktree records 23 checks/six failures. Disabled/blank pagination clicks can leak world-task behavior or break targeting isolation. Candidate focused23/0 and final combined macro309/0 pass with their own controlled-input scopes. Final readout117, rules187/219 and UI124 cover the new read-only/click-commit/pause/input behavior, with retained raw root records.

The new long-run diagnostic must prove at least 3,600 actual wall seconds of meaningful normal-Main campaign activity across the supported missions without padding time in idle menus or terminal screens. A running PID, partial progress or prepare-only pass is not a successful full long run. The frozen CLI/protocol is recorded under docs/benchmarks/v0.9; actual package/source identity, clock/save/mission truth and final independent launcher verification remain pending the later export/run. New 0.9 full-native, long-run and frame acceptance remain pending and may continue across turns. Human/Windows/minimum-hardware/rights/Steam gates remain open.


### 0.9 readouts, pager isolation and diagnostic lifecycle

Camp summaries observe existing authoritative production/training queries and actual packing stages, with 117 passing source/helper/Main-cache integration checks. Optional `include_pause: bool = true` preserves old query defaults; the summary passes false to retain real blockers under tactical pause, without changing the live flag or advancing allocator/queue state. Derived rows remain absent from saves, and full saved state/RNG stays unchanged. Main refreshes at relevant public actions/start/load/pause or the quarter-second presentation interval. The first construction187/recruitment219 reports were tool-output-only stages; root then retained clean final-source rerun logs for187/0 and219/0.

The original pager baseline's 23 checks/six failures are actual engine-input fixture evidence for world-task/targeting leakage. Candidate focused23/0, initial macro stage291/0 and added paused-shortage/detail18/0 retain separate scope; the final combined macro309/0 now passes with clean exit0. Rendered UI 124/0 and assistant inspection at 1600 and 1152/120% concern controlled source UI fixtures; they are not uncoached human play, actual full routes or store screenshot proof. The initial readout invocation's 104 checks/one isolation refusal is retained separately from the corrected 117/0 result.

The new fixed seven-cycle `--soak` mode must retain the same actual Main process/scene/audio instances across real public title/selection/new/restart transitions and complete all three economic routes, with actual disk/mission/UI continuity and at least 3,600 independently measured wall seconds. Partial progress or prepare-only does not pass. An independent audit rejected the diagnostic's original eight-player expectation: actual Main has six world SFX players, two UI players and one music player, nine total. Bad-eight source/logs remain retained, including its insufficient synthetic successes; corrected Python tests pass 26 and explicitly reject bad counts/music identities.

The separate actual-Main source-rendered lifecycle fixture passes 22 checks by loading retained actual 0.8 victory saves, invoking real title/select/new/restart/autosave paths and verifying persistent scene/voice identities. It does not run the economic routes or advance Main ticks and cannot prove a native export or elapsed hour. Unavailable release object/allocator/GPU monitors are reported null with availability flags; null is not a zero-memory or leak-free measurement. New 0.9 native/hour/FPS acceptance is still pending and not yet started in this source snapshot.


Final 0.9 source collection passes combined macro309, raw root construction187/recruitment219, readout117, renderedUI124 and import with normal new script/test metadata. Final diagnostic Python28 and source compile pass. The earlier Python26/audio9 and Main22 lifecycle records keep their original source scope. Final controlled actual-Main display/lifecycle25/0 records 1920×1080 client and actual Image/PNG pixels at requested UI scale1; no economic route or Main tick advancement is inferred.

The retained previous25/1 run is a diagnostic measurement false positive: Texture metadata reported2304×1296 while actual client and Image/PNG were1920×1080. Its original source/log/result manifest is preserved; PNGs remain in work. The corrected readback uses actual Image pixels and keeps the 1080 gate, exposing logical/Texture sizes separately. It is not a gameplay failure, resolution downgrade, native export proof or elapsed-hour result. Runner/launcher/test freeze hashes are retained with the final record. Current0.9 full native/hour/FPS acceptance remains pending and not yet started in this candidate snapshot.
