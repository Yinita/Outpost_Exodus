# 0.5 candidate functional evidence

This directory preserves recorded tests and the source/asset snapshot for the current0.5.0-dev development candidate. `candidate.json` provides exact file hashes and separate physical/nonblank counts. It does not identify a final binary or silently replace the export tools' Git-commit provenance.

| Record | Passing checks | Scope |
| --- | ---: | --- |
| recruitment-feedback.txt | 219 | Read-only admission/status, local costs/caps, real completion, save continuation, legacy state pairs and existing evacuation refund policy |
| macro-controls.txt | 268 | Synthetic real rendered input/layout, paging/cycling/rebinding, training status, mode cancellation and persistent cues |
| audio-native.txt | 200 | Actual PulseAudio mixer, imported clips/music endpoint, bounded players, state/RNG identity and menu/load/mute retirement |
| exit-recovery-after.txt | 43 | Actual isolated AUTO filesystem failure, state/slot preservation, modal input, return/retry/discard; final quit substituted by harness |
| ui.txt / input.txt / preferences.txt | 124 /48 /286 | Existing rendered UI, engine event dispatch, settings/recovery |
| construction-ui.txt / diagnostic-preflight.txt | 31 /40 | Existing construction controller/HUD and safe diagnostic setup |
| canyon-route.txt | 102 | Full real public-command Canyon guide to1590.0seconds; actual funded/powered exit and arrival |
| selection-normal-after.txt / selection-accelerated-after.txt | 114 each | Existing campaign selection with clean real-time audio retirement |

`sfx-reproduction.txt` records byte-identical deterministic original synthesis and the eight asset hashes. `quit-wall-probe.txt` checks actual≥120ms audio retirement, stopped processing and released streams. `quit-fixed-fps-smoke.txt` is an80tickMain smoke under accelerated execution; it is not a performance measurement.

## Retained failed baselines

`exit-recovery-baseline-failed.txt` has11checks/twofailures and demonstrates loss of the running application after a genuine failed AUTO write. `audio-shutdown-baseline-leak.txt` passes114logical assertions but reports twoObjectDB leaks and one resource still in use under accelerated execution. These are rejected baseline results, not passing evidence. Post-fix records are kept separately.

## Reproduction examples

Run from the project root with the pinned Godot runtime available to `run.sh`:

```bash
./run.sh --headless --script res://tests/test_recruitment_feedback.gd
./run.sh --headless --script res://tests/test_guide.gd
python3 tools/generate_sfx.py --check
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/audio-test-data" ./run.sh --script res://tests/test_game_audio.gd -- --require-rendered
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/macro-controls-data" ./run.sh --audio-driver Dummy --script res://tests/test_macro_controls.gd
DISPLAY=:0 XDG_DATA_HOME="$PWD/work/exit-recovery-data" ./run.sh --script res://tests/test_exit_recovery.gd
```

Graphical suites refuse ordinary player-data directories. Do not run new performance timing concurrently with tests. Command-line test fixtures and mixer assertions do not replace human hardware input, listening or uncoached play. Final exported0.5 payload performance, nativeWindows/clean installs, minimum hardware, final audio/art/accessibility, final licensing and actual Steam review remain separate open gates.
