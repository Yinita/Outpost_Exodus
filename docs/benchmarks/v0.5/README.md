# 0.5 native measurement boundary

The0.5 functional evidence is under docs/evidence/v0.5. Those tests contain no final exported performance claim. The previous0.4 report must not be relabeled0.5.

After committing a clean candidate and exporting with tools/export_release.sh, measure the actual Linux executable and adjacent PCK in a fresh dedicated user root. Use120warmup plus3600measuredframes per zoom and max-seconds300. This duration covers actual completed hauling/construction and the normal45second autosave in addition to the forced checkpoint. No simulation frequency, actor count, resource price or workload check is relaxed. Keep any rejected measurement and inspect its explicit failure rather than restarting until a preferred number appears.

```bash
BENCH_ISOLATION_ROOT="$PWD/work/benchmarks/native-v05-full" \
XDG_DATA_HOME="$PWD/work/benchmarks/native-v05-full/data" \
XDG_CONFIG_HOME="$PWD/work/benchmarks/native-v05-full/config" \
XDG_CACHE_HOME="$PWD/work/benchmarks/native-v05-full/cache" \
DISPLAY=:0 ./builds/linux-release/outpost-exodus.x86_64 -- \
  --render-diagnostics --frames=3600 --warmup=120 --max-seconds=300
```

The root must be fresh. Record actual mean/p95/p99/max frame intervals, workload/save checks and unchanged executable/PCK hashes. Verify the real automatic primary/backup rotation separately. The final payload-specific report accompanies the Linux development package; source evidence remains tied to its source snapshot. A measured near60FPS mean does not pass stable60FPS/minimum hardware, clean/nativeWindows, human-playability/listening or Steam review gates.
