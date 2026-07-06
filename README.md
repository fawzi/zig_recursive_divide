# Recursive divide
Simple project to explore parallel execution of recursive divide & conquer
calculations.

All the code is in `src/recursive_divide.zig`, so that it can be easily executed with
```
zig run -O ReleaseSafe recursive_divide.zig -- --pwork=32
```
This tool has the following command line parameters
```
 -h --help          print this description
 --io[=]<impl>      Uses the given io implementation (threaded|evented)
 --seed[=]<seed>    Uses the given seed for the random number gereators
 --pwork[=]<amount> Sets the amount of parallel work to do to <amount>. The work
                    is performed subdividing with a divide and conquer schema
                    halving it until it is small enough (a single number in
                    this case)
 --swork[=]<amount> Sets the sequential amount of work to do to <amount>.
                    The work is the number of rng to xor together
                    (defaults to 100000)
 --wait[=<ms>]      Waits for the requested number of seconds in the leaf work
                    tasks
```
The output is something like
```
[clariden][fmohamed@clariden-ln001 src]$ zig run recursive_divide.zig -O ReleaseSafe -- --pwork=20048 --swork=1000000
[{
  "io": "threaded",
  "depth": 15,
  "pwork": 20048,
  "swork": 1000000,
  "wait_ms": 0,
  "core_tree": 10024,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 2016,
  "actual_max_in_flight": 763,
  "in_flight_now": 0,
  "checksum": 13428737357497032989,
  "time": 0.265849246,
  "sequential_leaf_time": 19.996510852,
  "parallel_speedup": 75.21748191078187
}]
```
This means that the amount of potentially parallel leaf async tasks is 20048, which comes
from a tree of tasks bisecting the range 15 times.
* `sequential_leaf_time` is the sum of the execution time of all leaf tasks,
* `time` is the real time of execution for all the tasks, the subdividing ones and and leaf
tasks
* `swork` controls the amount of work performed in the leaf 
* `wait_ms` is the amount of ms of sleep in the leaf tasks, evented io should parallelize
this almost completely (single wait loop for all tasks)
* `parallel_speedup` is `sequential_leaf_time/time` i.e. how much the leaf tasks were
parallelized (assuming that the leaf tasks are large enough and thus the time used by the
subdividing tasks is negligible) and the main indicator one should look at

# Selected Results

On node with 4 GH200, 288 logical CPUs

## Pure wait
### Threaded
Good parallelization initially, but each wait occupies a thread, so parallelization crashes when
you hit the limits of the threads the blocking of tasks becomes apparent, with 256 at least one
thread executes 6 leaf elements, ideal work stealing would limit that to at most 2, but probably
the "skipped" async cannot be recovered

| pwork | time| speedup |
|-------|-----|---------|
| 1    | 1.00 | 1.00 |
| 4    | 1.00 | 4.00 |
| 16   | 1.00 | 15.95 |
| 64   | 1.01 | 63.24 |
| 256  | 6.03 | 42.47 |
| 1024 | 13.03 | 78.58 |

### Evented
When it works speedup well beyond the number of CPUs (as expected sharing a single wait
thread for all waits), but leaks, and panics in release.
But definitely still bugs to iron out.

in debug mode
| pwork | time| speedup |
|-------|-----|---------|
| 1    | 1.64 | 632.02 |

## Work
with `--swork=10000000` that corresponds to ~9ms with ReleaseSafe

### Threaded

As the task is so short the speedup is slower

| pwork | time| speedup |
|-------|-----|---------|
| 1    | 0.0098 | 1.00 |
| 4    | 0.0104 | 3.74 |
| 16   | 0.0127 | 12.32 |
| 64   | 0.0216 | 29.12 |
| 256  | 0.0398 | 63.03 |
| 1024 | 0.1918 | 52.10 |
| 4096 | 0.4801 | 83.20 |
| 16384 | 1.7262 | 92.59 |
| 65536 | 6.0361 | 105.65829062585708 |

### Evented

Also in this case only Debug version works, the task is ~66ms

| pwork | time| speedup |
|-------|-----|---------|
| 1    | 0.085 | 1.00 |
| 4    | 0.206 | 1.64 |
| 16   | 0.268 | 4.95 |
| 64   | 0.390 | 13.74 |
| 256  | 0.518 | 41.41 |
| 1024 | 1.289 | 66.29 |

# Appendix: Runs
## Pure wait - threaed
```
[clariden][fmohamed@clariden-ln001 src]$ zig run recursive_divide.zig -O ReleaseSafe -- --pwork=1  --swork=0 --wait
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 1,
  "pwork": 1,
  "swork": 0,
  "wait_ms": 1000,
  "core_tree": 0,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 1,
  "actual_max_in_flight": 1,
  "in_flight_now": 0,
  "checksum": 0,
  "time": 1.000073123,
  "sequential_leaf_time": 1.000071875,
  "parallel_speedup": 0.9999987520912508
}]
```

```
[clariden][fmohamed@clariden-ln001 src]$ zig run recursive_divide.zig -O ReleaseSafe -- --pwork=4  --swork=0 --wait
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 3,
  "pwork": 4,
  "swork": 0,
  "wait_ms": 1000,
  "core_tree": 2,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 4,
  "actual_max_in_flight": 7,
  "in_flight_now": 0,
  "checksum": 0,
  "time": 1.000703101,
  "sequential_leaf_time": 4.000249541,
  "parallel_speedup": 3.997438937685474
}]
```

```
[clariden][fmohamed@clariden-ln001 src]$ zig run recursive_divide.zig -O ReleaseSafe -- --pwork=16  --swork=0 --wait
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 5,
  "pwork": 16,
  "swork": 0,
  "wait_ms": 1000,
  "core_tree": 8,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 16,
  "actual_max_in_flight": 31,
  "in_flight_now": 0,
  "checksum": 0,
  "time": 1.003104816,
  "sequential_leaf_time": 16.000994073,
  "parallel_speedup": 15.951467700858892
}]
```

```
[clariden][fmohamed@clariden-ln001 src]$ zig run recursive_divide.zig -O ReleaseSafe -- --pwork=32  --swork=0 --wait
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 6,
  "pwork": 32,
  "swork": 0,
  "wait_ms": 1000,
  "core_tree": 16,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 32,
  "actual_max_in_flight": 63,
  "in_flight_now": 0,
  "checksum": 0,
  "time": 1.00607096,
  "sequential_leaf_time": 32.00198344,
  "parallel_speedup": 31.808873044104164
}]
```

```
[clariden][fmohamed@clariden-ln001 src]$ zig run recursive_divide.zig -O ReleaseSafe -- --pwork=64  --swork=0 --wait
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 7,
  "pwork": 64,
  "swork": 0,
  "wait_ms": 1000,
  "core_tree": 32,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 64,
  "actual_max_in_flight": 127,
  "in_flight_now": 0,
  "checksum": 0,
  "time": 1.012112623,
  "sequential_leaf_time": 64.003852281,
  "parallel_speedup": 63.23787573292621
}]
```

```
[clariden][fmohamed@clariden-ln001 src]$ srun -A csstaff --pty zig run recursive_divide.zig -O ReleaseSafe -- --pwork=256  --swork=0 --wait
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 9,
  "pwork": 256,
  "swork": 0,
  "wait_ms": 1000,
  "core_tree": 128,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 256,
  "actual_max_in_flight": 319,
  "in_flight_now": 0,
  "checksum": 0,
  "time": 6.027223251,
  "sequential_leaf_time": 256.013956692,
  "parallel_speedup": 42.476269092823756
}]
```

```
./recursive_divide --pwork=1024 --swork=1 --wait
[{
  "io": "threaded",
  "depth": 11,
  "pwork": 1024,
  "swork": 1,
  "wait_ms": 1000,
  "core_tree": 512,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 864,
  "actual_max_in_flight": 364,
  "in_flight_now": 0,
  "checksum": 6974713799589896828,
  "time": 13.031879642,
  "sequential_leaf_time": 1024.051327506,
  "parallel_speedup": 78.5804776929968
}]
```

## Pure wait - evented - Debug

```
[clariden][fmohamed@nid007367 src]$ zig run -O Debug recursive_divide.zig --  --pwork=1024 --swork=1 --wait --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 11,
  "pwork": 1024,
  "swork": 1,
  "wait_ms": 1000,
  "core_tree": 512,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 864,
  "actual_max_in_flight": 2047,
  "in_flight_now": 0,
  "checksum": 6974713799589896828,
  "time": 1.636784139,
  "sequential_leaf_time": 1034.476783999,
  "parallel_speedup": 632.0178448399541
}]
```

# Work

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=1 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 1,
  "pwork": 1,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 0,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 1,
  "actual_max_in_flight": 1,
  "in_flight_now": 0,
  "checksum": 5171585719137710762,
  "time": 0.009804915,
  "sequential_leaf_time": 0.009804595,
  "parallel_speedup": 0.9999673633070759
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=4 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 3,
  "pwork": 4,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 2,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 4,
  "actual_max_in_flight": 7,
  "in_flight_now": 0,
  "checksum": 925596614364162813,
  "time": 0.010428927,
  "sequential_leaf_time": 0.038976276,
  "parallel_speedup": 3.7373236959085054
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=16 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 5,
  "pwork": 16,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 8,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 16,
  "actual_max_in_flight": 31,
  "in_flight_now": 0,
  "checksum": 6718816695468879161,
  "time": 0.012724304,
  "sequential_leaf_time": 0.156731385,
  "parallel_speedup": 12.31748196207824
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=64 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 7,
  "pwork": 64,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 32,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 64,
  "actual_max_in_flight": 124,
  "in_flight_now": 0,
  "checksum": 17398572498442105668,
  "time": 0.021555176,
  "sequential_leaf_time": 0.62770098,
  "parallel_speedup": 29.120661320510674
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=256 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 9,
  "pwork": 256,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 128,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 256,
  "actual_max_in_flight": 279,
  "in_flight_now": 0,
  "checksum": 1766233289479275169,
  "time": 0.039847228,
  "sequential_leaf_time": 2.511727916,
  "parallel_speedup": 63.03394344018108
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=1024 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 11,
  "pwork": 1024,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 512,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 864,
  "actual_max_in_flight": 396,
  "in_flight_now": 0,
  "checksum": 8453898749801398098,
  "time": 0.191797034,
  "sequential_leaf_time": 9.992756054,
  "parallel_speedup": 52.10068083743151
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=4096 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 13,
  "pwork": 4096,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 2048,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 1440,
  "actual_max_in_flight": 574,
  "in_flight_now": 0,
  "checksum": 12775159940837603209,
  "time": 0.480142257,
  "sequential_leaf_time": 39.946148585,
  "parallel_speedup": 83.19648604684258
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=16384 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 15,
  "pwork": 16384,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 8192,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 2016,
  "actual_max_in_flight": 817,
  "in_flight_now": 0,
  "checksum": 14448447920267524035,
  "time": 1.726200927,
  "sequential_leaf_time": 159.829839918,
  "parallel_speedup": 92.5905191093667
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O ReleaseSafe recursive_divide.zig --  --pwork=65536 --swork=10000000
anyzig: .minimum_zig_version '0.17.0-dev.1099+7db2ef610' pulled from '/users/fmohamed/zig/recursive_divide/build.zig.zon'
anyzig: appdata '/users/fmohamed/.local/share/anyzig'
anyzig: zig '0.17.0-dev.1099+7db2ef610' already exists at '/users/fmohamed/.cache/zig/p/N-V-__8AAHO6VxWHSGCSavQJDXzK21CgLPNQx_PZiKl5Lszl'
[{
  "io": "threaded",
  "depth": 17,
  "pwork": 65536,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 32768,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 2592,
  "actual_max_in_flight": 952,
  "in_flight_now": 0,
  "checksum": 5255741376436437575,
  "time": 6.036144938,
  "sequential_leaf_time": 637.768756119,
  "parallel_speedup": 105.65829062585708
}]
```

### Evented

```
[clariden][fmohamed@nid007367 src]$ zig run -O Debug recursive_divide.zig --  --pwork=1 --swork=10000000 --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 1,
  "pwork": 1,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 0,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 1,
  "actual_max_in_flight": 1,
  "in_flight_now": 0,
  "checksum": 5171585719137710762,
  "time": 0.084756055,
  "sequential_leaf_time": 0.084754519,
  "parallel_speedup": 0.9999818774009716
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O Debug recursive_divide.zig --  --pwork=4 --swork=10000000 --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 3,
  "pwork": 4,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 2,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 4,
  "actual_max_in_flight": 7,
  "in_flight_now": 0,
  "checksum": 925596614364162813,
  "time": 0.205934068,
  "sequential_leaf_time": 0.33807094,
  "parallel_speedup": 1.6416464904680075
}]
```

```
[clariden][fmohamed@nid006922 src]$ zig run -O Debug recursive_divide.zig --  --pwork=16 --swork=10000000 --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 5,
  "pwork": 16,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 8,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 16,
  "actual_max_in_flight": 30,
  "in_flight_now": 0,
  "checksum": 6718816695468879161,
  "time": 0.26786267,
  "sequential_leaf_time": 1.325737373,
  "parallel_speedup": 4.949317398351924
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O Debug recursive_divide.zig --  --pwork=64 --swork=10000000 --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 7,
  "pwork": 64,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 32,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 64,
  "actual_max_in_flight": 108,
  "in_flight_now": 0,
  "checksum": 17398572498442105668,
  "time": 0.389722938,
  "sequential_leaf_time": 5.35822213,
  "parallel_speedup": 13.748798460510423
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O Debug recursive_divide.zig --  --pwork=256 --swork=10000000 --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 9,
  "pwork": 256,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 128,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 256,
  "actual_max_in_flight": 292,
  "in_flight_now": 0,
  "checksum": 1766233289479275169,
  "time": 0.517966598,
  "sequential_leaf_time": 21.451880596,
  "parallel_speedup": 41.41556748800238
}]
```

```
[clariden][fmohamed@nid007367 src]$ zig run -O Debug recursive_divide.zig --  --pwork=1024 --swork=10000000 --io=evented 2>/dev/null
[{
  "io": "evented",
  "depth": 11,
  "pwork": 1024,
  "swork": 10000000,
  "wait_ms": 0,
  "core_tree": 512,
  "ncpu": 288,
  "perfect_parallel_in_flight_max": 864,
  "actual_max_in_flight": 739,
  "in_flight_now": 0,
  "checksum": 8453898749801398098,
  "time": 1.289170771,
  "sequential_leaf_time": 85.458523278,
  "parallel_speedup": 66.28952905262541
}]
```
