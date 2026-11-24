# Compact object headers

JDK 25 can shrink object headers with `-XX:+UseCompactObjectHeaders` (Project Lilliput). The flag stays **off** in `scripts/jvm-opts.sh` unless `COMPACT_OBJECT_HEADERS` is set. It is outside [Aikar's flags](https://docs.papermc.io/paper/aikars-flags). On a Minecraft heap it can cut memory use and can also change GC pauses and tick time. This page is how to measure that on a copy of a real world before anyone turns the opt-in on for a server people play.

The comparison is tracked in https://github.com/KevinTCoughlin/minecraft-server/issues/129.

## Opt-in

`scripts/jvm-opts.sh` appends the flag only when `COMPACT_OBJECT_HEADERS` is `true`, `1`, `yes`, or `on`. Any other value is an error. Unset, `false`, `0`, `no`, and `off` leave it off.

```bash
# One-off trial. Prefer the harness below; this starts whatever world
# server.properties names, which is the live world.
COMPACT_OBJECT_HEADERS=true ./scripts/start.sh
```

G1 already passes `-XX:+UnlockExperimentalVMOptions`. ZGC does not, so the opt-in adds that unlock only for ZGC, immediately before the compact-header flag. JDK 25 still treats the flag as experimental.

`docker/docker-compose.yml` does not read `COMPACT_OBJECT_HEADERS`. Its `JVM_XX_OPTS` list leaves the flag out. The custom image uses `scripts/jvm-opts.sh`, so the same environment variable is the opt-in there too.

## How to run it on the host

Run this on the machine that has the world, Java 25, and `server/paper.jar`. The harness is a host tool: it needs a local `java` and `jcmd` (or `jstat`) beside the world copy.

1. Stop the live server. The harness refuses to copy a world that sits inside `server/` while `server/server.pid` is a running `paper.jar` process. A copy taken from an open world is not a clean before/after.

   ```bash
   ./scripts/stop.sh
   ```

2. Confirm Java 25 and the Paper jar.

   ```bash
   java -version
   ls -lh server/paper.jar
   ```

   If the jar is missing, `./scripts/update-paper.sh` downloads the tracked Paper build.

3. Leave enough free disk for **two** full copies of the world (baseline and compact are copied separately, so the second run starts from the same files as the first). Peak RAM is one heap at a time: the runs are sequential, and `AlwaysPreTouch` touches the whole heap.

4. Run the harness against the world people actually play. `server/parkour-spiral` is the usual featured map; use `server/parkour` or another world directory the same way. The argument is the world directory (the folder that contains `level.dat`), not the server root.

   ```bash
   ./scripts/measure-compact-headers.sh --world server/parkour-spiral
   ```

   Defaults match a host start: G1, `-Xms4G -Xmx4G`, view distance 10, simulation distance 10, 120 seconds of warmup after Paper prints `Done`, then 180 seconds of soak. The measurement server listens on `127.0.0.1:25566` with no plugins, peaceful difficulty, mob spawning off, and an empty-server pause disabled, so the two idle soaks are the same kind of session. Override the heap if 4G is tight. Both runs get the same value:

   ```bash
   MIN_RAM=2G MAX_RAM=2G ./scripts/measure-compact-headers.sh --world server/parkour
   ```

5. Read the verdict. The script prints it at the end and writes it under `.compact-headers-measure/<timestamp>/`. The `latest` symlink points at that directory when the default work directory is used.

   ```bash
   cat .compact-headers-measure/latest/summary.md
   cat .compact-headers-measure/latest/verdict.txt
   ```

`verdict.txt` is one word: `ACCEPT`, `REJECT`, or `INCONCLUSIVE`. The process exits 0 when that file was written, including a rejection. Exit 1 means the harness refused to run or a server did not finish. A refusal is the safety check doing its job.

Useful overrides:

| Flag or variable | Default | Meaning |
| --- | --- | --- |
| `--world` | required | Directory copied twice. Never the server's world path. |
| `--work-dir` | `.compact-headers-measure/<timestamp>` | Copies, GC logs, and the summary. Must not overlap the original world. |
| `--warmup` / `WARMUP_SECONDS` | 120 | Seconds after `Done` before sampling. |
| `--soak` / `SOAK_SECONDS` | 180 | Sampling window. Keep this at 60 or more so the 1 minute TPS and MSPT windows sit inside the soak. |
| `--sample-interval` | 15 | Seconds between `jcmd GC.heap_info` samples. |
| `--min-ram` / `--max-ram` | 4G | Same `-Xms` / `-Xmx` for both runs. |
| `--gc` | `g1gc` | `g1gc` or `zgc`, passed through `scripts/jvm-opts.sh`. |
| `--view-distance` | 10 | Same for both runs. |
| `--port` | 25566 | Bound to `127.0.0.1`, so it stays off the live server's port. |
| `--startup-timeout` / `STARTUP_TIMEOUT` | 600 | Seconds to wait for Paper to print `Done`. A 4G pretouch plus a large world can take several minutes. |
| `--shutdown-timeout` / `SHUTDOWN_TIMEOUT` | 120 | Seconds to wait after the console `stop` command. |
| `--paper-jar` | `server/paper.jar` | Server jar linked into the copy. |

There is no flag that points the server at the original world.

## What each run records

Both runs call `scripts/jvm-opts.sh` with the same heap, GC, and dump settings. The compact run is the one with `COMPACT_OBJECT_HEADERS=true`. Each run also adds the same `-Xlog:gc*` options, with a different log path. `HeapDumpPath` differs only by run directory.

After warmup the harness samples the heap with `jcmd <pid> GC.heap_info` (falling back to `jstat -gc`) through the soak, then sends Paper's `tps` and `mspt` on the console and stops the server.

| File | Contents |
| --- | --- |
| `summary.md` | Side-by-side numbers, both flag lists, and the verdict. |
| `verdict.txt` | `ACCEPT`, `REJECT`, or `INCONCLUSIVE`. |
| `run.env` | World name, world size in KB, Java version, heap, distances, and the original path. |
| `baseline/flags.txt` and `compact/flags.txt` | Exact `jvm-opts.sh` output. |
| `baseline/command.txt` and `compact/command.txt` | Full `java` command, including the GC log flag. |
| `*/gc.log` | Unified GC log used for pause max and p99. |
| `*/heap-samples.txt` | Used heap in KB after warmup and through the soak. |
| `*/logs/latest.log` | Paper's `Done`, `tps`, and `mspt` lines. |

Pauses before the warmup mark are ignored, so startup GC does not decide the comparison. The 1 minute TPS figure is the one that counts. A `*` from Paper means that window is not full yet, and the verdict is inconclusive.

## Acceptance

Enable the flag in `scripts/jvm-opts.sh` and in the Compose `JVM_XX_OPTS` only if the copy shows a **smaller heap** and **pauses and TPS are no worse**.

The harness applies that rule as:

- **Heap.** The first sample after warmup and the high-water mark during the soak are both strictly lower with the flag.
- **GC pauses.** Soak max and p99 are less than or equal to the baseline. G1's target in the current flags is `-XX:MaxGCPauseMillis=200`. Zero pauses on both sides counts as equal.
- **TPS.** Paper's 1 minute TPS is greater than or equal to the baseline, with a 0.05 tolerance so a value Paper prints as one decimal place is not a false failure.
- **MSPT.** The 1 minute average from Paper's `/mspt` is less than or equal to the baseline, with the same 0.05 ms tolerance. TPS is capped at 20, so a slower tick can hide behind a perfect TPS number. MSPT is part of "TPS no worse".

`ACCEPT` means those gates passed. It does **not** change the default. Record `summary.md` on issue 129, repeat the run once if the high-water drop is under 1% (the summary says so), and turn the default on only in a follow-up that keeps the measured numbers. `REJECT` means leave the flag out and record the numbers on the issue. `INCONCLUSIVE` means a heap sample, a pause log, TPS, or MSPT was missing; fix that and run again before enabling anything.

One pair of idle soaks is noisy. A clear heap drop with flat TPS and MSPT is the result worth keeping. A few milliseconds of pause jitter either way is a reason to run it again, not a reason to flip the default from a single sample.

## Copy-only safety

The server directory is always `$work/baseline` or `$work/compact`, and `server.properties` sets `level-name=world` there. The harness checks the copy before it starts Java, and again immediately before the process is launched.

It refuses when:

- the work directory is the original world, is inside it, or contains it (including a symlink whose target is the world)
- the work directory is the live `server/` directory
- the copy's `level.dat` is missing, is a symlink, or is the same inode as the original
- any symlink inside the copy points at the original world
- any hardlink inside the copy is a file in the original world
- Paper is still running from `server/server.pid` and the world is inside that server directory
- the original `level.dat` checksum changes during the two runs

`check-copy` is the same check, for a copy you made yourself:

```bash
./scripts/measure-compact-headers.sh check-copy --source server/parkour-spiral --dest /tmp/parkour-copy
```

## Container

Copy the world directory out of the data volume and run the harness on the host against that copy. Leave Compose `JVM_XX_OPTS` unchanged until the summary's verdict is `ACCEPT` and a follow-up records the numbers. Adding the flag only in the running container, on the only copy of the world, skips the comparison this harness exists to make.
