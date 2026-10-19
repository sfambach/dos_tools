# LFNDEL

Lists or removes VFAT long file name (LFN) entries on a FAT12/FAT16 drive under DOS 3.x.

Disks written by Windows 9x or Linux carry extra LFN directory slots. DOS 3.x does not know them:
`CHKDSK` reports them as `0 bytes in N hidden files`, and `CHKDSK /F` may damage them. The 8.3 names
of all files are always present, so the LFN slots can simply be removed.

## Usage

```
LFNDEL E:       list every file that carries a long name
LFNDEL E: /D    list, ask (Y/N), then mark all LFN slots as deleted
```

Example output:

```
E:\GAMES = Games
E:\GAMES\README.TXT = Read me first.txt

Files with long names: 2, LFN entries: 3
```

Reboot after `/D` so DOS does not write back stale directory buffers.

## How it works

- Reads the boot sector and walks the root directory and all subdirectories with raw sector access
  (INT 25h/26h). Uses the large-partition form (`CX=FFFFh`, DOS 3.31+) and falls back to the old form.
- An entry with attribute `0Fh` is an LFN slot. `/D` sets its first byte to `E5h` (deleted); nothing
  else is changed.
- Supports FAT12 and FAT16 with 512-byte sectors. FAT32 is rejected.
- Runs on an 8088.

## Build

```
nasm -f bin -o LFNDEL.COM LFNDEL.ASM
```

## Status

Tested in an emulator against FAT12 and FAT16 test images (listing, deletion, unchanged 8.3 entries).
Not yet tested on real hardware. Make a backup before using `/D`.
