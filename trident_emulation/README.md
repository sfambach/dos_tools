# Trident emulation switch (TRIEMU)

> ⚠️ **Untested on real hardware. Do not use `CGA`, `MDA`, `HGC` or `EGA` yet** – only the status display (`TRIEMU` without arguments) is safe. See *Findings from SVM89.EXE* below: Trident's emulation works through NMI traps that need a resident handler, which TRIEMU does not install. Without it the PC may stop with an NMI/parity error (reset fixes it).

Small DOS tool that switches the emulation mode of a Trident TVGA8800/8900 graphics card. Replacement for Trident's `SVM.EXE` (folder `TVGAUTIL` on the driver disk), which is hard to find for the 8800BR. Goal: get real CGA/MDA timing out of the card's 9-pin TTL output, e.g. for testing the MCE Blaster. Runs on DOS 2.0 and later (e.g. DOS 3.31, where `MODE MONO` is not available).

## Usage

```
TRIEMU            show chip ID, emulation and switch settings
TRIEMU VGA        back to VGA, BIOS mode 3
TRIEMU EGA        EGA emulation, 80x25 text with EGA timing (21.8 kHz)
TRIEMU CGA        CGA emulation, 80x25 text with CGA timing (15.5 kHz)
TRIEMU MDA        MDA emulation, 80x25 text with MDA timing (18.4 kHz)
TRIEMU HGC        same as MDA
/F                skip the Trident check
```

On the card, also set the output to TTL (jumper/DIP switches per the card's manual).

## How it works

| Step | Register (TRIDENT.TXT) |
|---|---|
| Detect chip | 3C4h index 0Bh: write 0 selects old mode registers, read returns the chip ID (01h = TVGA8800BR) |
| Switch emulation | 3C4h index 0Dh (old mode control 2), bits 0–2: 0 = VGA, 3 = EGA, 5 = CGA/MDA/Hercules |
| Switch settings | 3C4h index 0Fh, bits 0–3 |

Version 0.1.0 wrote the IBM 6845 values into the CRTC. A test on a TVGA8800BR (2026-10-12) showed that this does not work: `TRIEMU CGA` gave 200 lines at 31 kHz / 117 Hz, and `TRIEMU EGA` stayed at 32.4 kHz / 72 Hz. Neither the emulation bits nor the 6845 values change the clock.

Measurements on the 9-pin TTL output of a TVGA8800BR (MCE Blaster, 2026-10-12) show that the CRTC changes its behaviour with the emulation bits:

| Emulation | CRTC counts like | Evidence |
|---|---|---|
| 5 (CGA/MDA) | 6845: total = R0 + 1, rows × (R9 + 1) + R5 | IBM CGA values gave 114 characters × 264 lines at 28.322 MHz / 8 = 31.05 kHz / 117 Hz |
| 3 (EGA) | EGA: horizontal total = R0 + 2 | R0 = 139 gave 141 characters: 22.32 kHz instead of 21.85 kHz |

So since 0.3.0:

| | Registers | Expected |
|---|---|---|
| CGA | IBM CGA 6845 values, dot clock halved (sequencer index 01h = 09h) | 15.53 kHz / 59.3 Hz, 200 lines |
| MDA | IBM MDA 6845 values with R0 = 5Fh (96 characters), dot clock halved | 18.44 kHz / 49.8 Hz with 8-dot characters (16.4 kHz if the card keeps 9-dot characters) |
| EGA | VGA mode 3, 8x14 font, 25.175 MHz, R0 = 142 (144 characters), 364 lines | 21.85 kHz / 60.0 Hz, 350 lines |

Version 0.2.0 wrote VGA-style values in CGA and MDA emulation, which the 6845-like CRTC turned into no sync (CGA) or 34.2 kHz / 28.3 Hz (MDA).

The 9-pin TTL output carries the CRTC timing (confirmed by the measurements above).

## Findings from SVM89.EXE

Disassembly of `SVM89.EXE` 1.21 (Trident driver disk C3.0, for the TVGA8900):

- It stays resident and hooks INT 10h (old vector moved to INT 6Dh) and the NMI. It enables NMI on XT (port A0h) and AT (port 70h) and clears the parity latch (port 61h).
- Its NMI handler reads 3C4h index 0Ch, then the trapped CGA/MDA mode register (3D8h/3B8h), and reprograms the VGA CRTC itself (e.g. 3D4h R2 = 51h or 29h, 3B4h R4 = 2Eh, R5 = 0Fh). So "emulation" is register-level compatibility for software, done by the TSR, not a switch of the output timing.
- It writes 3C4h index 0Dh in old mode with 20h (VGA), 22h, 0Ch and 2Ch. The low three bits are 0, 2 and 4, not 3 and 5 as TRIDENT.TXT says, at least on the 8900.

Consequence: setting the emulation bits alone will most likely not produce 15.7 kHz on the TTL output. On the TG Expert EVGA the more likely path is the board's own pass-through (switch nibble `1100`, see above).

## Tested

| Where | Result |
|---|---|
| DOSBox (S3, CGA, Hercules) | argument parsing, status output, CGA/MDA register programming keep a working text screen |
| Trident TVGA8800BR | **not yet tested** |

![Status output in DOSBox](doc/status.png)

## Building

```sh
make   # needs nasm, produces bin/TRIEMU.COM
```

A ready-made `TRIEMU.COM` is attached to the GitHub releases (tag `trident_emulation-v*`) and to every CI run as a build artifact. 8086 instructions only.

## License

[MIT](../LICENSE)

## AI disclosure

Program and documentation were created with the help of AI (Claude, Anthropic).
