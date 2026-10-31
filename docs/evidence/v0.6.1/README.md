# 0.6.1 candidate campaign-validation evidence

This is a source-candidate snapshot before final export and full native execution. The new bundled validator and independent launcher target actual normal Main 20 Hz advancement and a complete Canyon public-command route. Full native campaign acceptance and performance remain pending; no historical FPS is relabeled. `candidate.json` will be generated only after source freeze, with exact source/config/evidence hashes and separate code categories.

## Scope and acceptance

The normal Main loop stays enabled. Engine time scale remains1;3× speed is selected through normal UI actions. The route issues public move/task, production, paid build, evacuation and seal commands, preserves minimum economic windows and waits for real states. It never injects inventory, health, units, terrain, pursuit or outcomes and never manually calls simulation or controller process steps. Native focus suspension remains enabled.

A real loaded outbound withdrawal is saved and immediately loaded through Main's file layer. Full normalized simulation/RNG and UI must match, after a read-only guide-cache refresh that matches normal loading. Actual continued deliveries, stock abandonment, paid/funded/powered exit completion, truck arrival and four or more survivors are required. Main-loop tick/time coherence, automatic-save/backup validity, exact EXE/PCK/provenance identities and clean process/log exit are independent checks.

The Linux validator reads actual process arguments from `/proc/self/cmdline`, with a bounded buffer because virtual proc files report zero length. Godot's public argument array omits recognized engine flags; it is not sufficient evidence against forced fixed FPS. This helper is developer validation; ordinary gameplay has no Python or proc dependency.

## Present evidence and limitations

The final editor-capable prepare probe reached20 actual Main ticks/one simulation second with no errors and performed a real disk save/load with equal complete simulation/RNG and UI. Its native and complete-campaign flags remain false; it did not exercise the loaded-withdrawal route. The final headless preflight records73 checks/0 failures, including13 delivery-observer facade checks; it does not create Main or advance a real campaign. Three actual engine flags before the separator are rejected with expected exit 2. Wrapper-only synthetic report gating38 checks and disposable-filesystem guards9 checks pass; no native game was launched by those checks. Their raw records remain separate. A prepare-only success proves startup and small real-loop progress only, never full victory or FPS.


| Record | Recorded result | Scope |
| --- | --- | --- |
| campaign-preflight-parcels.txt | 73 checks/0 failures | Latest static parse/isolation and delivery-observer facade suite; no Main or real campaign |
| campaign-preflight.txt | 60 checks/0 failures | Earlier pre-observer static guard run, retained historically |
| engine-negative-summary.json and engine-*-rejected.txt | Three expected exit 2 rejections | Actual fixed FPS/time-scale/disabled-render engine arguments before `--`, headless only |
| wrapper-checks.json | 38 report gates +9 filesystem guards,0 failures | Synthetic verifier/disposable filesystem checks, not native execution |
| editor-prepare-final.json/.txt | 20 Main ticks/1 simulation second; real disk roundtrip equal | Editor prepare before startup-refusal and diagnostic-record fixes, native/full flags false; no loaded withdrawal |
| engine-input-final.txt | 48 checks/0 failures | Existing engine-event dispatch before startup-refusal fix |
| engine-input-isolation-refused.txt | Expected exit2 refusal | Preliminary wrong test XDG path, not a product failure |
| candidate-final-import.txt | Exit0 | Import/UID generation before the narrow Main startup-refusal and diagnostic-record fixes |
| startup-rejection-source-final.json and startup-source-*.txt | 3 actual Main source cases,15 checks pass; all expected exit2 | Campaign/render missing-isolation and unknown-mission exits; no script errors/leaks, player files or source drift |
| editor-prepare-earlier.json/.txt | 20Main ticks/1 simulation second | Earlier editor-capable prepare snapshot, native/full flags false |
| runner-compile.txt / route-compile.txt / candidate-import.txt | Exit0 compilation/import snapshots | Syntax/import evidence at the recorded stage; final native route still pending |

The delivery facade represents an outbound loaded truck whose `camp_id` still names its origin while the empty return transition occurs at the forward receiver. It checks one actual-shape event, no double count on repeated frames, and rejection of empty parcels, away-from-receiver changes and ordinary hauling. These controlled observations cannot prove a real native parcel arrived; the full route must supply that evidence.

## Rejected diagnostic/capability baselines

The native release help does not expose an external `--script` entry. A bounded external-script marker probe timed out after five seconds (launcher exit 124) without the unique marker, so this work uses an explicit bundled validation entry rather than assuming editor CLI features exist in release templates. This is a capability observation, not a shipping-game failure or a claim of complete campaign execution.

An initial negative fixed FPS test incorrectly passed60static checks because `OS.get_cmdline_args()` omitted the recognized engine flag. Its original raw log is retained as rejected guard evidence. A separate raw-process probe records the missing public flag and the actual `/proc/self/cmdline` fixed FPS/time-scale arguments. The corrected guard and final negative test must be recorded separately; the earlier pass is not promoted to valid clock verification.

## Reproduction

After clean commit/export:

```bash
DISPLAY=:0 python3 tools/run_native_campaign.py \
  --build-dir "$PWD/builds/linux-release" \
  --isolation-root "$PWD/work/native-campaign-v061-full-corrected" \
  --max-seconds 900
```

The wrapper refuses nonempty or unsafe isolation roots rather than deleting runs. Progress is written to `output/campaign-progress.json`, final game proof to `output/campaign-validation.json`, and independent launcher verdict to `verification.json`. Exact full-campaign and native performance reports accompany their actual payload separately after this candidate snapshot. Human playability/listening, full physical input, nativeWindows/clean installs, final art/accessibility/license acceptance, minimum hardware/stable frame pacing and Steam review remain open.

The pre-startup/record-fix editor prepare report retains actual raw engine arguments, stable focus observations and source hashes. Its real disk continuation is an initial-state prepare check, not the loaded outbound withdrawal required by full native acceptance. The preliminary input-suite invocation used the wrong XDG directory and was refused before testing; the corrected invocation passes48checks and is kept separately.

The editor prepare and48check input records predate the later Main startup-refusal and diagnostic-record fixes; their original source/configuration binding is retained and they are not relabeled as exact final-runtime evidence. The negative engine-flag summary likewise retains its own earlier runner hash before later observer/prepare additions. Final native prepare/full checks must bind the actual exported payload.

## Rejected startup-entry defect

`startup-refusal-baseline-rejected.txt` is a real product startup defect, separate from a test fixture refusing an incorrect XDG directory: after the campaign guard correctly refused unsafe startup and queued exit2, Main still processed before its world existed and accessed nil `world.motion`. The correction disables processing/input before the queued quit. `startup-refusal-fixed.txt` records the actual Main negative entry returning expected exit2 without script/error/leak output. The original baseline remains rejected; focused source/packed startup cases are recorded separately as they complete. `startup-refusal-baseline.json` records the previously frozen Main hash and the limits of the retained source snapshot.

The final source startup regression executes actual Main for missing campaign isolation, missing render isolation and unknown mission. All three return expected exit2 with the correct refusal marker, no script/error/leak output and no settings/save artifacts; source hashes remain unchanged before/after. The native-build option of this Python test has not yet run at this candidate snapshot.

## Rejected actual packed full-campaign run at2a00

The actual unpacked Linux ZIP at commit`2a00c7e97ff7954b0756bc49445866d92aec6b07` ran the real Main loop for1574.15simulation seconds/525.582397game-wall seconds, observing31483fixed0.05second ticks with no invalid timestep. It retained the real loaded-withdrawal disk checkpoint at911.8seconds with full simulation/RNG/UI equality, three home/four middle deliveries and ten valid automatic-file changes. The exit actually completed and remained powered.

The complete run nevertheless failed: its route verifier read the public save's tagged encoded Dictionary as raw fields and falsely missed the paid exit job, stopping before the final move order. `native-full-2a00-final-state-rejected.json` retains actual job286/frontcamp210/building19, funded/delivered/done for140materials/45fuel/30supplies. Automatic primary/backup summary times were null for the same decoding reason; their actual saved times and hashes are decoded read-only in `native-full-2a00-failure-analysis.json`.

At stop the game was still`playing`, evacuated0, with the command truck17.117tiles from the exit. Therefore neither a completed powered exit nor this successful prefix proves final victory or a complete native campaign. Original game report, independent wrapper report, process log, full final encoded state and package identities remain unchanged. All three original source/Linux/Windows ZIPs and the entire failed run are separately retained under outer`outputs/rejected/outpost-exodus-0.6.1-dev-2a00c7e-native-verifier/`, with original checksums. The corrected diagnostic decoder must be committed/exported and the entire route rerun in fresh isolation; no campaign rule or acceptance scope is weakened.

The corrected diagnostic record checks load the unchanged actual failed final-state fixture and pass94checks/0failures. They recover the real paid exit job and saved time, reject16corrupted copies, and verify complete simulation/RNG is unchanged by observation. These are source-level record tests, not final native victory. The original fixture SHA is`94f0b5e4c623cc23af1c47c637792b05d8d999c9c89d8e3965035754c0080e4a`; its provenance is retained separately.

`candidate-corrected-import.txt` records clean import/UID generation after the diagnostic record correction. The current actual-fixture94check result is source-level evidence for the corrected helpers. A new commit/export, full native frame/smoke/package checks, extraction and complete native route are still pending this refreshed candidate; neither the old2a00 full failure nor its earlier valid frame report is relabeled. Fresh roots are`native-v061-corrected` and`native-campaign-v061-full-corrected`, with a new unpacked directory.
