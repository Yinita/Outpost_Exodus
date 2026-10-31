# 0.8 exact-payload and per-mission native protocol

Accepted 0.7 actual Linux Canyon and busy-frame evidence is retained under docs/evidence/v0.8 with its original `ede3c50` identity. Current 0.8 rendering and expanded mission diagnostics require a newly frozen, committed and exported payload. No new-payload complete-route or FPS acceptance is inferred from source tests or the older package.

After source regressions finish, freeze/count/hash/commit, export with `tools/export_release.sh`, and profile with fresh isolated directories. Keep normal engine time, the product focus-pause policy, canonical 32-friendly/100-enemy workload, actual 20 Hz Main, real hauling/construction, 120 warmup and 3,600 measured frames per zoom, and real save validation. Do not contend frame timing with native UI correctness or other performance jobs.

```bash
BENCH_ISOLATION_ROOT="$PWD/work/benchmarks/native-v08-full" \
XDG_DATA_HOME="$PWD/work/benchmarks/native-v08-full/data" \
XDG_CONFIG_HOME="$PWD/work/benchmarks/native-v08-full/config" \
XDG_CACHE_HOME="$PWD/work/benchmarks/native-v08-full/cache" \
DISPLAY=:0 ./builds/linux-release/outpost-exodus.x86_64 -- \
  --render-diagnostics --frames=3600 --warmup=120 --max-seconds=300
```

After that process is terminal, run native smoke and independent real automatic-primary/backup validation, package the unchanged payload and unpack the Linux ZIP. Run each mission from that actual unpacked directory, using a distinct fresh root for each attempt and another root for any prepare-only attempt:

```bash
DISPLAY=:0 python3 tools/run_native_campaign.py \
  --build-dir "$PWD/work/native-campaign-v08-unpacked/outpost-exodus-linux" \
  --mission delta \
  --isolation-root "$PWD/work/native-campaign-v08-delta-full" \
  --max-seconds 900
```

Repeat sequentially with `--mission ridge` and `--mission canyon` and corresponding fresh roots. Requested mission identity must agree across actual process argv, live/controller state, on-disk checkpoint, route, both automatic generations and final saved state. Each full route must prove normal clock/actual Main steps, both resources, paid/completed construction, continued deliveries after loaded-withdrawal disk/RNG/UI equality, sealing, deliberate stock abandonment, funded/powered exit and actual truck/survivor arrival. Prepare-only and synthetic verifier fixtures do not meet that bar. Bind clean process exit and final acceptance to unchanged actual EXE/PCK/provenance before/after; retain rejected attempts.

Per-mission native full-route records and frame measurements have different purposes. New HUD pixels or source regressions do not prove native frame pacing, minimum hardware, uncoached playability, listening, Windows/clean-machine installation or Steam readiness.
