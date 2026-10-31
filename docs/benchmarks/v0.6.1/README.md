# 0.6.1 exact-payload validation boundary

This candidate introduces complete native campaign verification separately from frame profiling. Source/static/editor-prepare evidence under docs/evidence/v0.6.1 does not prove a full native campaign or native FPS. Historical0.6 payload measurements stay bound to0.6.

First commit/export a clean candidate. Run the native frame measurement and startup smoke separately, then package. Unpack the actual Linux ZIP into a fresh directory with executable permissions preserved, and run `tools/run_native_campaign.py` with that directory as `--build-dir` and a fresh `CAMPAIGN_VALIDATION_ROOT` created by the wrapper. A direct native build directory is also supported for narrower setup probes. Preserve actual Main 20 Hz simulation, normal engine time, standard3× speed, original campaign resources/HP/rules and active focus pause. Require the complete public route, real loaded-withdrawal disk continuation, actual exit/truck/survivor victory and unchanged EXE/PCK/provenance. Prepare-only is a different, narrower record.

```bash
DISPLAY=:0 python3 tools/run_native_campaign.py \
  --build-dir "$PWD/builds/linux-release" \
  --isolation-root "$PWD/work/native-campaign-v061-full" \
  --max-seconds 900
```

The independent native frame measurement uses:120 warmup plus3600 measured frames per zoom,max-seconds300, real32 friendly / 100 enemy busy fixture, actual completed deliveries/construction and valid forced saves. Do not run other correctness or performance jobs concurrently.

```bash
BENCH_ISOLATION_ROOT="$PWD/work/benchmarks/native-v061-full" \
XDG_DATA_HOME="$PWD/work/benchmarks/native-v061-full/data" \
XDG_CONFIG_HOME="$PWD/work/benchmarks/native-v061-full/config" \
XDG_CACHE_HOME="$PWD/work/benchmarks/native-v061-full/cache" \
DISPLAY=:0 ./builds/linux-release/outpost-exodus.x86_64 -- \
  --render-diagnostics --frames=3600 --warmup=120 --max-seconds=300
```

Bind final frame/soak reports to their unchanged executable/PCK hashes and source commit/tree, and re-read the ordinary automatic primary/rotated backup using the current schema. Preserve any failed attempt and diagnose it without weakening workload, clock or victory checks. No0.6.1 full-native or performance pass exists at this source-candidate snapshot. These checks do not close human playability/listening, Windows/clean-machine, minimum hardware/frame pacing, final asset/accessibility/license or Steam gates.

Run full-campaign and frame jobs sequentially; the order above permits the complete route to exercise the actual packaged download. The EXE/PCK hashes must remain identical across export, measurement, packaging, extraction and route acceptance. Archive metadata/CRC and native executable permissions are separate installation checks.
