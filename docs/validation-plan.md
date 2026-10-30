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
