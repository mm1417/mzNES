# mzNES

A lightweight, educational Nintendo Entertainment System (NES) emulator written in **Zig 0.17.0** + **SDL3**.  
  
Project started: `Sep.1.2026`  

[![Zig Version](https://img.shields.io/badge/Zig-0.17.0-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


## Status & Features

- [x] **iNES Format Parsing**: Header validation, Mapper ID extraction, PRG/CHR ROM loading.
- [x] **CPU Core (Ricoh 2A03)**: MOS 6502 instruction decoding, address modes, and interrupt handling.
- [ ] **PPU (Picture Processing Unit)**: Background rendering, OAM sprite rendering, and NMI logic.
- [ ] **APU (Audio Processing Unit)**: Pulse, Triangle, Noise, and DMC channel synthesis.
- [ ] **Mappers**:
  - [ ] Mapper 0 (NROM)
  - [ ] Mapper 1 (MMC1)
  - [ ] Mapper 3 (CNROM)
