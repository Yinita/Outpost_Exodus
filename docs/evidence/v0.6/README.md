# 0.6 candidate functional evidence

This directory records display-motion correctness, focus/title recovery, casualty-aware opening guidance and the existing UI regression suites. `candidate.json` hashes the current source/configuration/audio snapshot and retained records, with separate physical/nonblank code counts. It is a source snapshot before final export, not an executable or Git-commit provenance claim. Final native packaging supplies exact committed-tree and executable/PCK binding separately.

| Record | Passing checks | Scope |
| --- | ---: | --- |
| render-motion-headless.txt | 28 | 120actual-step moving twin-state/RNG pairs; bounded sub-step positions, real controller movement/selection, pause/load/mission reset,3×speed |
| render-motion-native.txt | 33 | The same behavior plus actual nonempty0/50/100percent pose renders and changed actor pixels |
| motion-review-probe.txt | 20actual steps | Independent read-only moving midpoint, pause and campaign-reset probe; not a timed benchmark |
| focus-title-final.txt | 63 | Final combined candidate; actual externalX11 focus exit/entry, minimize/restore, held-action cleanup, modal/pause/state/save preservation, genuine blockedAUTO title failure and exact-state retry |
| engine-input.txt / exit-recovery.txt | 48 /43 | Existing engine event dispatch and actual failedAUTO exit recovery |
| canyon-guide-full.txt | 211 | Read-only casualty/recovery fixtures and full paid/powered Canyon route at1590.0seconds with actual exit arrival |
| guide-quick.txt | 154 | Explicitly requested quick fixture run; skips full mission and says so |
| mission-guide.txt | 137 | Three map-specific fixture and real paid opening scenarios |
| ui.txt / macro-controls.txt / preferences.txt / selection.txt | 124 /268 /286 /114 | Final ordinary rendered UI/options/camp/training/campaign selection regression |
| diagnostic-preflight.txt | 40 | Fresh isolated diagnostic environment and workload setup validation |

`candidate-import.txt` records clean editor import and UID generation. The three `.gd.txt` probe sources preserve how the observations were obtained; they are not runtime modules. `pose-0.png`, `pose-50.png`, `pose-100.png` retain the native actor poses. `title-save-failed.png` shows the complete failure notice inside the pause panel at1152×648/120percentUI. Captures are evidence for those controlled conditions, not final art or human playability acceptance.

## Motion boundary

Positions and gait interpolate only between actual20Hz simulation samples. Maximum display delay is one50ms simulation step at1×speed; no extrapolation or future command prediction is used. Unit overlays, actor ordering/culling, logistics origins and click/drag selection use the displayed pose. Combat, inventory, outcomes, current commands, saves and RNG remain authoritative. Pause, load/reset, newly spawned IDs and discontinuous moves snap. Correctness/twin-state and pixel tests do not establish perceived smoothness or exported frame pacing.

## Native focus boundary

`tests/native_focus_helper.py` creates its own temporary independentX11 window using standard-libraryctypes/libX11, releases it on request and restores prior focus. It is required only by this native regression suite, not by the game. Actual native focus and minimize signals are exercised; keyboard/mouse dispatch and simulation-frame calls are controlled by the harness. The suite does not prove Windows, Wayland, physicalAlt+Tab input, every window manager or device behavior.

## Retained rejected evidence

`onboarding-baseline-rejected.txt` records the original guide requesting four combat units after only three survive, and also reproduces failedAUTO return-to-title replacement. `focus-title-baseline-rejected.txt` records a synthetic realWindowfocus-exit signal that previously failed to suspend simulation/held gestures/world SFX, then a genuine failedAUTO write followed by title New resetting live time0.1to0. These describe the originalMain/Guide defect logic at the0.5 baseline; a complete contemporaneous working-tree hash was not captured during these probes. The relevant baseline reference is commit`a1f45b4f2e661023e960c25029840bd81861f4c4`.

The three `focus-fixture-attempt*-rejected.txt` files are separate test-fixture attempts, not shipping-game failures or passing evidence. Attempt1 changedWindow.force_native while visible and compared restored JSON numeric types without the existing canonical numeric roundtrip. Subsequent attempts exposed that a Godot child nativeWindow does not represent switching out of the application; waiting for its internal focus flag cannot verify main-application suspension. The final suite uses the independent externalX11 window and passes the original application-focus requirement. Intermediate fixture source snapshots were not retained; the diagnosed logs remain visible.

## Reproduction examples

Run from the project root with the pinned Godot runtime available to `run.sh`. Graphical tests refuse ordinary player-data directories.

```bash
XDG_DATA_HOME="$PWD/work/render-motion-data" ./run.sh --headless --script res://tests/test_render_motion.gd
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/render-motion-data" ./run.sh --script res://tests/test_render_motion.gd -- --require-rendered
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/focus-recovery-data" ./run.sh --script res://tests/test_focus_recovery.gd
./run.sh --headless --script res://tests/test_guide.gd
./run.sh --headless --script res://tests/test_guide.gd -- --quick
./run.sh --headless --script res://tests/test_mission_guide.gd
```

Do not run correctness jobs concurrently with native performance timing. Final0.6 export performance remains pending separately under the protocol in docs/benchmarks/v0.6. Human usability/listening, final art/accessibility/localization/licenses, nativeWindows/clean installs, named minimum hardware/stable frame pacing and actual Steam review remain open.

## Rejected first export

`export-first-rejected.txt` records the clean-tree guard rejecting first export after the editor generated four evidence-PNG import metadata files. These metadata files are now tracked. The premature native diagnostic attempt was terminated with143 and is not accepted; the fresh final measurement uses `native-v06-final`. Runtime and test sources did not change. The exact final binary/commit binding remains in the external release evidence.
