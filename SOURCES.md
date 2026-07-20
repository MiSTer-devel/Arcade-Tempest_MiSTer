# Source Provenance

## MiSTer Framework

- Repository: `https://github.com/MiSTer-devel/Template_MiSTer`
- Branch: `master`
- Commit: `69b8a2acc6d84dd313b5abcba6a17155287ed3d8`
- Imported: 2026-07-17

The repository was initialized with a fresh Git history after importing this
template snapshot. The `sys/` framework directory is retained unchanged.

## Black Widow Modules

- Repository: `https://github.com/Videodr0me/Arcade-BlackWidow_MiSTer`
- Commit: `e560fd8b83b22fc503c94d3221e11013ed41df0e`
- Imported modules: T65, PROM-driven AVG, vector drawer, framebuffer/effects
  pipeline, and game/video PLL configuration

Board wrappers, memory-map logic, ROM wrappers, and the placeholder EAROM were
deliberately not imported.

## Star Wars POKEY

- Repository: `https://github.com/Videodr0me/Arcade-StarWars_MiSTer`
- Commit: `5270c74394c3828500543845f76011f88226dbff`
- Imported module: `rtl/pokey.vhd`

This version contains the corrected polynomial-5 feedback tap and preserves
the full six-bit linear audio sum.

## Hardware References

- Atari Tempest DP-190 drawing package and TM-190 manuals
- Atari Analog Vector Generator Hardware Description
- Original Atari Tempest program sources
- MAME `tempest.cpp`, `avgdvg.cpp`, and `mathbox.cpp`

The Tempest electrical drawings are the source of truth for clocks, decoding,
bus ownership, state timing, and device behavior. Original Atari software is
used to establish how that hardware is exercised. MAME and prior FPGA cores
are secondary behavioral checks and do not override the drawings when they
disagree.

Reference material is maintained outside this repository under
`Tempest_Research/`. Game ROM data is never stored in the repository.
