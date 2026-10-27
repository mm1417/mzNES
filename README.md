# mzNES

A lightweight, educational Nintendo Entertainment System (NES) emulator written in **Zig 0.17.0** + **SDL3**.  
  
Project started: `Sep.1.2026`  

[![Zig Version](https://img.shields.io/badge/Zig-0.17.0-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Project Purpose
This project is built to learning, not for perfect NES emulation.
The goal is to understand how the NES works by implementing the core parts of an emulator step by step.
The project will focus on basic functionality only, with mapper support limited to: Mapper 0 and 1.

## TODO

- [x] **iNES Format Parsing**: Header validation, Mapper ID extraction, PRG/CHR ROM loading.
- [x] **CPU Core (Ricoh 2A03)**: MOS 6502 instruction decoding, address modes, and interrupt handling.
- [ ] **PPU (Picture Processing Unit)**: Background rendering, OAM sprite rendering, and NMI logic.
- [ ] **APU (Audio Processing Unit)**: Pulse, Triangle, Noise, and DMC channel synthesis.
- [ ] **Mappers**:
  - [ ] Mapper 0 (NROM)
  - [ ] Mapper 1 (MMC1)
