# Tempest (Arcade, 1981) for MiSTer FPGA

An FPGA implementation of Atari's classic color vector arcade game
**Tempest** for the
[MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

Tempest sends the player racing around the rim of geometric tubes while enemies climb toward the screen. Its optical spinner, Superzapper, vivid color vectors, and relentless pace made it one of Atari's most distinctive arcade games.

This core reconstructs the original machine from Atari's schematics. It pairs
that hardware with an ultra high performance vector renderer and a complete
CRT-effects pipeline for high-resolution MiSTer output.

## Support the Project

Hey, Videodr0me here! If you enjoy reliving the golden age of arcade games,
please support my work and future updates:
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=flat-square&logo=buy-me-a-coffee)](https://buymeacoffee.com/Videodr0me)

---

## Original Hardware

The original Atari Tempest arcade machine (Atari part number 136002) uses the
following major components:

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main CPU** | MOS Technology 6502A at 1.512 MHz | T65-compatible 6502 core driven from the original 12.096 MHz clock family |
| **Vector Generator** | PROM-sequenced Atari Analog Vector Generator (AVG), vector RAM/ROM, color RAM, DACs, and analog integrators | PROM-driven digital AVG using the original state PROM and four-bit Tempest color path |
| **Math Processor** | Custom Atari TTL math box with command and microcode PROMs | Schematic-derived math box using the original PROMs |
| **Sound** | 2x Atari C012294 POKEY | Improved POKEY noise generation and accuracy, including Tempest protection behavior, with a switchable model of the output filter |
| **Audio Filter** | 10 kOhm / 15 nF output networks | Switchable model of the original low-pass response |
| **Display** | Vertical color XY vector monitor | High-resolution raster vector renderer with bloom, halo, phosphor decay, slot mask, and color processing |
| **Controls** | Optical spinner, Fire, and Superzapper buttons | Spinner, mouse, analog-stick, and digital-input support |
| **Non-volatile Memory** | 64-byte Atari ER2055 EAROM | Persistent MiSTer NVRAM with manual and optional automatic saving |

---

## Controls

Tempest was designed around a free-spinning optical rotary controller. A real
spinner gives the closest cabinet experience, but the core also supports a
mouse, an analog stick, and digital left/right controls.

**Circular Mode is experimental.** It replaces directional left/right
emulation with orbital analog-stick movement; spinner and mouse input remain
available.

| Input | Function |
|---|---|
| **Spinner / Mouse** | Move the ship clockwise or counterclockwise around the tube |
| **Analog Stick / Left and Right** | Directional spinner emulation |
| **Analog Stick / Circular** | Move by circling the stick around its outer edge (experimental) |
| **Fire (Button A)** | Fire along the current tube lane |
| **Superzapper (Button B)** | Activate the level's Superzapper |
| **Start 1 / Start 2** | Start a one-player or two-player game |
| **Coin / Coin Right** | Operate the left or right coin mechanism |

The **Input Controls** menu provides these adjustments:

| Option | Description |
|---|---|
| **Direction** | Reverses spinner, mouse, analog, circular-stick, and digital movement for alternate controller or cabinet wiring. |
| **Sensitivity** | Scales all rotation inputs from 0.125x through 2.0x. |
| **Analog Stick** | **Normal** uses horizontal movement. **Circular** derives rotation by circling the stick around its outer edge. |

For USB spinners, MiSTer's `spinner_throttle` setting can be used in addition
to the core's **Sensitivity** setting.

---

## Requirements

The CRT-style video pipeline uses MiSTer SDRAM and requires a 32MB SDRAM module
or larger. Use the included MRA so the program ROMs, original PROMs, controls,
DIP switches, and EAROM persistence are configured correctly.

---

## Recommended MiSTer Video Settings

The renderer supports 240p, 480p, 720p, and 1080p output. **1080p is
recommended** for the highest vector detail. Compatible 720p displays can use
the optional 120Hz mode for smoother frame presentation.

For high-resolution flat-panel output, add the following settings under the
exact `[Tempest]` header in `mister.ini`. MiSTer's scaler filters and shadow
mask are intentionally disabled because the core supplies its own CRT-effects
pipeline and slot mask.

```ini
[Tempest]
video_mode=8              ; 8 = 1080p, or use 0 = 720p
vsync_adjust=2            ; Try 0 or 1 if your display has compatibility issues
vscale_mode=0             ; Let the core provide its optimized aspect ratio
hdmi_limited=0            ; Use 1 only for displays expecting limited RGB range
hdr=1                     ; Recommended when the display supports HDR
vrr_mode=0                ; Try 1 or higher if required by your display
vfilter_default=          ; Leave scaler filters blank
vfilter_vertical_default=
vfilter_scanlines_default=
shmask_default=           ; Do not combine MiSTer's mask with the core slot mask
shmask_mode_default=0
```

The empty filter entries override filters inherited from the global `[MiSTer]`
section.

### Direct Video and CRT Output

When Direct Video is active, use **Direct Video Scan Rate** in Video Options to
select 15 kHz (240p) or 31 kHz (480p) output.

For 15 kHz CRT output through MiSTer's scaler rather than Direct Video, use an
exact 640x240 video mode and integer scaling:

```ini
[Tempest]
video_mode=640,240,60
vscale_mode=4
vsync_adjust=0
composite_sync=1
```

For 31 kHz scaler output, use the same settings with
`video_mode=640,480,60`. Monitor requirements vary, so verify the accepted scan
rate and sync type before connecting a CRT.

When using a real CRT, consider starting with **A Touch of CRT** or a
**Custom** profile. The stronger profiles recreate characteristics that the
tube may already provide, including mask structure, color response, bloom, and
halo. A Custom profile lets you disable duplicated effects while retaining the
processing that benefits your display.

---

## OSD Options

### Video Options

| Option | Description |
|---|---|
| **Aspect Ratio** | **Optimized** selects the intended core aspect, **Stretched** fills the display, and **Pixel Perfect** requests direct pixel mapping. |
| **120Hz (720p only)** | Enables approximately 120Hz output when the active video mode is 720p. |
| **Direct Video Scan Rate** | Selects 15 kHz (240p) or 31 kHz (480p) while Direct Video is active. |
| **Buffer Mode** | Selects whether completed vector frames are presented at EOF, VBLANK, or the recommended EOF + VBLANK combination. |
| **Profile** | Selects five fixed video presets, two independent custom slots, or the effects-filter bypass path. |

### Video Profiles

| Profile | Description |
|---|---|
| **Off** | Bypasses bloom, halo, color processing, and slot mask. Dot Scale, Tone Mapping, and Phosphor Decay remain available. |
| **A Touch of CRT** | Adds subtle CRT halo and bloom to modern anti-aliased vector drawing. |
| **80s Cruise Control** | Adds Amplifone color processing, richer halos, and more bloom. At 720p and 1080p it also enables the orientation-aware slot mask. This is the default profile. |
| **80s Overdrive** | Models a heavily driven arcade CRT with stronger glow and phosphor decay. |
| **Neon Fever Dream** | Stylized high-energy vector presentation with excessive flashing bright lights. |
| **Stranger Tempest** | A crazy, fun color-swap profile based on Neon Fever Dream. |
| **Custom 1 / Custom 2** | Two independent user-configurable slots exposing the complete advanced effects controls. |

> **Warning:** Neon Fever Dream and Stranger Tempest feature excessive
> flashing bright lights and should not be used by anyone sensitive to them.

### Custom Profile Controls

Selecting **Custom 1** or **Custom 2** exposes the complete effects controls:

| Option | Description |
|---|---|
| **Dot Scale** | Controls the apparent size of vector dots and particle endpoints: Auto, Pixel, 2x, or 2.5x. |
| **Tone Mapping** | Selects how the original vector intensity is mapped to the digital output range. |
| **Bloom Width** | Controls the radius of local bloom around bright vector pixels. |
| **Bloom Curve** | Controls how readily increasing intensity produces bloom. |
| **Halo** | Sets the strength of the broad CRT halo. |
| **Halo Spread** | Selects the spatial distribution of halo energy. |
| **Phosphor Decay** | Selects Off or one of three decay lookup tables applied according to each pixel's stored draw phase. |
| **Color Space** | Enables the Amp709 color-space conversion. |
| **Color Channels** | Selects RGB order, black and white, or Negative inversion. |
| **Slot Mask** | Enables the adaptive CRT-style slot mask aligned to the selected orientation. |

The fixed profiles are resolution-aware: 240p and 480p share one setting
table, while 720p and 1080p use separate settings. Both Custom slots preserve
their own complete set of controls. Their settings can be retained using
MiSTer's **Save Settings** command.

### Video Geometry

| Option | Description |
|---|---|
| **Orientation** | Provides the eight unique rotation and mirroring combinations for horizontal, vertical, and mirrored installations. |
| **Zoom** | **Near** frames normal gameplay tightly. **Far** makes the wider AVG area available. |

**Normal** is the intended presentation for a conventional landscape display.
The other orientations are applied relative to that correctly aligned image.

### Cabinet Audio Hardware

| Option | Default | Description |
|---|---|---|
| **POKEY RC Filter** | On | Models the nominal 10 kOhm / 15 nF low-pass network following each original POKEY output. |

Keep the filter enabled for the cabinet-style response. Disabling it provides
the unfiltered digital POKEY mix.

---

## High Scores and EAROM/NVRAM

Tempest displays eight high scores, but the original game retains only the top
three scores and their initials in its 64-byte EAROM. The other five entries
return to their built-in defaults after a cold start.

At the end of each completed game, Tempest updates bookkeeping data. If a
player earns a top-three score, the score and initials are updated after entry
is complete.

MiSTer stores the associated EAROM image under `/media/fat/config/nvram/` using
the MRA name.

- Enable **Autosave NVRAM** to save modified EAROM data when the OSD is opened.
- Select **Save NVRAM** to save it manually.

**Requirements:** EAROM/NVRAM persistence and DIP-switch mapping require
starting the core through the provided MRA file.

---

## ROMs

```text
                                *** Attention ***

ROMs are not included. Use the supplied Tempest MRA with the matching MAME
Tempest Rev 3 ROM set. The MRA verifies every program, vector, AVG state, and
math-box PROM by CRC.

Quick reference for MiSTer SD-card placement:

/_Arcade/Tempest.mra
/_Arcade/cores/Tempest.rbf
/games/mame/tempest.zip
```

See the
[MiSTer Arcade ROM guide](https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms)
for other supported ROM-folder layouts.

---

## Compilation

The project uses **Quartus Prime Lite** and targets the Cyclone V FPGA on the
Terasic DE10-Nano.

1. Open `Tempest.qpf` in Quartus.
2. Run the complete compilation flow.
3. Find the generated `Tempest.rbf` in `output_files/`.

Production source files are listed in `files.qip`. Core-specific RTL is under
`rtl/`; `sys/` contains the standard MiSTer framework.

---

## Credits and Acknowledgments

- **Tempest:** Designed and programmed by Dave Theurer, Atari, 1981.
- **MiSTer Tempest core, AVG, math box, renderer, and integration:** Videodr0me.
- **Vector drawer foundation:** Jeroen Domburg.
- **POKEY foundation:** MikeJ and FPGAArcade contributors.
- **T65 CPU core:** Daniel Wallner and subsequent T65 maintainers.
- **MiSTer platform:** Sorgelig and the MiSTer community.

---

## License

See [LICENSE](LICENSE) and the headers of individual source files for the terms
that apply to this project and its incorporated components.
