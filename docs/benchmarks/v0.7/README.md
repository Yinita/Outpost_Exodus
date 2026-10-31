# 0.7 exact-payload native protocol

Current headless state replays and controlled tests under docs/evidence/v0.7 are functional evidence, not new FPS or whole-native acceptance. Accepted 0.6.1 reports remain bound to their original `3f8` payload. The changed barrier approach can affect timing and combat; do not relabel the old victory as 0.7.

Freeze and commit source, export with tools/export_release.sh, and use separate fresh directories for frame profiling, smoke, prepare and full-campaign runs. Do not contend native frame timing with other correctness/performance jobs. Keep the canonical 32-friendly/100-enemy busy fixture, actual 20 Hz simulation, completed real hauling/construction, 120 warmup and 3,600 measured frames per zoom and validated real saves. Product focus suspension remains enabled.

```bash
BENCH_ISOLATION_ROOT="$PWD/work/benchmarks/native-v07-full" \
XDG_DATA_HOME="$PWD/work/benchmarks/native-v07-full/data" \
XDG_CONFIG_HOME="$PWD/work/benchmarks/native-v07-full/config" \
XDG_CACHE_HOME="$PWD/work/benchmarks/native-v07-full/cache" \
DISPLAY=:0 ./builds/linux-release/outpost-exodus.x86_64 -- \
  --render-diagnostics --frames=3600 --warmup=120 --max-seconds=300
```

After that process is terminal, separately re-read the actual 45-second automatic primary/backup, run native smoke, package the same unchanged payload and unpack the Linux ZIP. Prefer that unpacked directory for the full public-command route:

```bash
DISPLAY=:0 python3 tools/run_native_campaign.py \
  --build-dir "$PWD/work/native-campaign-v07-unpacked/outpost-exodus-linux" \
  --isolation-root "$PWD/work/native-campaign-v07-full" \
  --max-seconds 900
```

A prepare-only result is narrower and uses another fresh root. Full acceptance requires normal engine time, standard 3× UI speed, actual Main 0.05-second steps, loaded-withdrawal disk/RNG/UI equality, continued actual deliveries, deliberate stock abandonment, funded/completed/powered exit and real truck plus at least four arrivals. Bind the final reports to unchanged EXE/PCK/provenance before/after and retain rejected attempts. No 0.7 full native, native frame/soak, Windows/clean-machine, minimum hardware, human playability/listening, license or Steam-review pass exists in this candidate snapshot.
