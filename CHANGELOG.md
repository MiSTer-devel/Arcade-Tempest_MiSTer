# Changelog

All notable changes to this project will be documented in this file.

## Release [20260720]

### Features

- **Hardware-Level Tempest Core**: Reconstructed the Tempest machine from the
  original Atari schematics, PROMs, and program sources.
- **PROM-Driven Vector Generator**: Implemented the Atari Analog Vector
  Generator with the original state PROM and four-bit Tempest color path.
- **Original Math Box**: Implemented the schematic-defined math hardware using
  the original command and microcode PROMs.
- **Ultra High Performance Renderer**: High-resolution vector output at
  240p, 480p, 720p, and 1080p, with optional 120Hz output at 720p.
- **CRT Effects Pipeline**: Bloom, halo, phosphor decay, color processing, dot
  scaling, and an adaptive, orientation-aware slot mask.
- **Cabinet Audio and POKEY**: Improved POKEY noise generation and accuracy,
  with a switchable model of the output filter.
- **Video Profiles**: Five presets and two independent custom slots that
  expose the complete advanced effects controls.
- **Spinner Controls**: Spinner, mouse, analog-stick, and digital left/right
  control with global direction and sensitivity settings, plus experimental
  circular-stick control.
- **Direct Video**: Explicit 15 kHz (240p) and 31 kHz (480p) output.
- **Geometry Controls**: Rotation, mirroring, and Near/Far framing for
  different monitor and cabinet orientations.
- **Cabinet Inputs**: The second coin mechanism, Service Mode, and
  Diagnostic Step controls.
- **EAROM**: Persistent loading plus optional automatic or manual saving of
  high scores and bookkeeping data.
