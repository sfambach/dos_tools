# bench – unattended DOS benchmarks

Runs a fixed set of DOS benchmarks on a retro PC without anyone at the keyboard,
collects the raw output and hands it to a server, where `bench2apply.py` turns it
into measurement records for the Taxonomy Modeller (`taxmod/apply` change list).

> **Status: probe.** The batch logic, `CHKCFG` and the Doom test ran in DOSBox 0.74
> (see *Tested* below). Nothing has run on real hardware yet.

## How it works

```
AUTOEXEC.BAT ─ CALL C:\BENCH\BENCH
   │  CHKCFG: BIOS setup or config changed? → start a new run
   │  RUNTEST <name> for each test, skips tests already done in this run
   ▼
C:\BENCH\RAW\*.*  ──copy──▶  N:\RESULTS\<HOST>\NEW\   (EtherDFS share on the server)
                                     │
                         bench2apply.py on the server
                                     ▼
                       change list for taxmod/apply
```

## Restarting the tests

A run is the set of all tests for one configuration of the PC.

| Situation | What happens |
|---|---|
| `BENCH` after a finished run | nothing, the results are already on the server |
| `BENCH` after a crash or reboot | continues with the next test that has not run yet |
| a test hung the PC | it is still marked as running on the next start, so it is skipped and written to `ERRORS.INI` |
| BIOS setup, `CONFIG.SYS`, `AUTOEXEC.BAT` or `HOST.BAT` changed | **new run**: all markers and raw files are deleted, all tests run again |
| `BENCH NEU` | new run, whatever changed |

`CHKCFG.COM` decides whether the setup changed. It builds a CRC-16 over the CMOS
setup bytes 10h–3Fh (no clock bytes) and the files given on the command line, and
compares it with the value stored in `C:\BENCH\STATE\CFG.FP`:

```
CHKCFG statefile [file ...]
ERRORLEVEL 0 unchanged, 1 changed or first run (state file rewritten), 2 error
```

Chipset settings beyond CMOS 3Fh are not covered: a board that keeps a setting
there needs `BENCH NEU`.

## Installation on the PC

1. Copy `dos\*.*` to `C:\BENCH`, the benchmarks to `C:\BENCH\<name>` (paths in `TESTS\*.BAT`).
2. Copy `HOST.SMP` to `HOST.BAT` and set `HOST`, `SETUP` (record id of the PC
   configuration in the Taxonomy Modeller) and `NETDRV`.
3. Add `CALL C:\BENCH\BENCH` to the end of `AUTOEXEC.BAT`. Without `CALL`, DOS
   does not return to `AUTOEXEC.BAT` after the batch ends.
4. A test is one batch file in `TESTS\`; delete a file to leave that test out, the
   order is the list in `BENCH.BAT`.

## Tests

| Test | Output | Unattended | Notes |
|---|---|---|---|
| `DOOM` | `DOOM1..3.TXT` (`timed 2134 gametics in N realtics`) | yes | FPS = 2134 × 35 / realtics; three runs, averaged |
| `QUAKE` | `QUAKE.TXT` from `-condebug` | not verified | Quake may wait in the console after the demo |
| `SPEEDSYS` | `SPEEDSYS.TXT` via `REP:` | not verified | needs the 4.79 beta from the source archive; 4.78 has no `REP:`. Crashes in DOSBox 0.74 (divide overflow while measuring the CPU clock) |
| `TOPBENCH` | `TOPBENCH.INI` from `TOPBSTUB` | not verified | the stub writes `OUTPUT.INI` without input, but is not part of the public 4.0a archive |
| `CHKCPU`, `CACHECHK` | text | not verified | switches taken from their documentation |

Benchmarks that only show their result on screen (Landmark, 3DBench, Chris 3D,
PC Player) are not covered yet; they need a screen capture TSR.

## Server

```
python3 server/bench2apply.py /srv/dos/RESULTS server/bench-map.json changes.json
```

* Renames every `RESULTS/<HOST>/NEW` that holds `READY.TXT` to a timestamp folder.
* Parses the raw files and averages repeated runs.
* Writes one new measurement record per mapped value: test setup, measured
  quantity, value and a note with the single values.
* Values without an entry in `bench-map.json` are listed on stderr and skipped.

`bench-map.json` holds the node id of the measurements and the record id of each
measured quantity; both come from the Modeller (`taxmod/read-tree`).

## Tested

DOSBox 0.74-3, `cycles=fixed 60000`, headless (Xvfb):

* first run: Doom ×3, results copied to the mounted `N:` (`realtics` 1166/1167/1167)
* second start without changes: `CHKCFG: setup unchanged`, nothing runs
* `HOST.BAT` changed: new run with the new `SETUP`
* marker of a hung test left behind: test skipped, `SPEEDSYS=hung` in `ERRORS.INI`
* `BENCH NEU`: new run
* `bench2apply.py` on that output: one change list with the Doom mean (64.02 FPS)

## Building

`make` in this folder rebuilds `dos/CHKCFG.COM` with NASM.
