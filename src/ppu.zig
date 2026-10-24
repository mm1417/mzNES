const std = @import("std");
const cartridge_mod = @import("cartridge.zig");

const VER_MASK: u16 = 0x07FF; // 2Kb
const HOR_MASK: u16 = 0x03FF; // 1Kb
const HOR_OFFSET: u16 = 0x0400;
const PALETTE_OFFSET: u16 = 0x3F00;
const PALETTE_MASK: u16 = 0x001F; // 32bytes
const MEM_MAP_8MASK: u8 = 0x3F;
const MEM_MAP_16MASK: u16 = 0x3FFF;

pub const PPU = struct {
    vram: [2048]u8 = undefined,
    palette_ram: [32]u8 = undefined,
    cartridge: *const cartridge_mod.Cartridge,

    ctrl: u8 = 0,
    mask: u8 = 0,
    status: u8 = 0,

    scroll_x: u8 = 0,
    scroll_y: u8 = 0,

    ppu_addr: u16 = 0,
    ppu_addr_hi: u8 = 0,
    ppu_addr_lo: u8 = 0,
    ppu_addr_step: u8 = 1,

    addr_latch: bool = false,

    databuffer: u8 = 0,

    pub fn init(ctrd: *const cartridge_mod.Cartridge) PPU {
        var ppu = PPU{
            .cartridge = ctrd,
        };
        @memset(&ppu.vram, 0);
        @memset(&ppu.palette_ram, 0);
        return ppu;
    }

    fn readRam(self: *const PPU, addr: u16) u8 {
        const re_addr = resolve_addr(self, addr);
        switch (addr) {
            0x0000...0x1FFF => return self.cartridge.ppuRead(re_addr),
            0x2000...0x3EFF => return self.vram[re_addr],
            0x3F00...0x3FFF => return self.palette_ram[re_addr],
            else => return 0,
        }
    }

    fn writeRam(self: *PPU, addr: u16, value: u8) void {
        const re_addr = resolve_addr(self, addr);
        switch (addr) {
            0x2000...0x3EFF => self.vram[re_addr] = value,
            0x3F00...0x3FFF => self.palette_ram[re_addr] = value,
            else => {},
        }
    }

    // 给BUS的外部API
    pub fn cpuRead(self: *PPU, addr: u16) u8 {
        switch (addr) {
            0x2002 => {
                const value = self.status;
                self.status &= 0b0111_1111; // clear VBlank bit (7th bit)
                self.addr_latch = false;
                return value;
            },
            0x2007 => {
                const addr_tmp = self.ppu_addr;
                const value = self.readRam(self.ppu_addr);
                self.ppu_addr +%= self.ppu_addr_step;
                self.ppu_addr &= MEM_MAP_16MASK;

                if (addr_tmp >= PALETTE_OFFSET) {
                    return value;
                }

                const value_tmp = self.databuffer;
                self.databuffer = value;
                return value_tmp;
            },
            else => return 0,
        }
    }

    // 给BUS的外部API
    pub fn cpuWrite(self: *PPU, addr: u16, value: u8) void {
        switch (addr) {
            0x2000 => {
                self.ctrl = value;
                // check VRAM increment
                if (self.ctrl & 0b0000_0100 != 0) {
                    self.ppu_addr_step = 32;
                } else {
                    self.ppu_addr_step = 1;
                }
            },
            0x2001 => self.mask = value,
            0x2005 => {
                if (self.addr_latch == false) {
                    self.scroll_x = value;
                    self.addr_latch = true;
                } else {
                    self.scroll_y = value;
                    self.addr_latch = false;
                }
            },
            0x2006 => {
                if (self.addr_latch == false) {
                    self.ppu_addr_hi = value & MEM_MAP_8MASK;
                    self.addr_latch = true;
                } else {
                    self.ppu_addr_lo = value;
                    self.addr_latch = false;
                }
                self.ppu_addr = (@as(u16, self.ppu_addr_hi) << 8) | (@as(u16, self.ppu_addr_lo));
            },
            0x2007 => {
                self.writeRam(self.ppu_addr, value);
                self.ppu_addr +%= self.ppu_addr_step;
                self.ppu_addr &= MEM_MAP_16MASK;
            },
            else => {},
        }
    }
};

fn resolve_addr(ppu: *const PPU, addr: u16) u16 {
    switch (addr) {
        0x0000...0x1FFF => return addr,
        0x2000...0x2FFF => {
            switch (ppu.cartridge.mirroring) {
                // A1 B2
                // A3 B4
                .vertical => return addr & VER_MASK,
                // A1 A2
                // B3 B4
                .horizontal => {
                    // the first nametable end at 0x27FF
                    if (addr <= 0x27FF) {
                        return addr & HOR_MASK;
                    } else {
                        return (addr & HOR_MASK) + HOR_OFFSET;
                    }
                },
            }
        },
        0x3000...0x3EFF => {
            const mirror_addr = addr - 0x1000;
            switch (ppu.cartridge.mirroring) {
                .vertical => return mirror_addr & VER_MASK,
                .horizontal => {
                    if (mirror_addr <= 0x27FF) {
                        return mirror_addr & HOR_MASK;
                    } else {
                        return (mirror_addr & HOR_MASK) + HOR_OFFSET;
                    }
                },
            }
        },
        0x3F00...0x3FFF => {
            const final_addr = (addr - PALETTE_OFFSET) & PALETTE_MASK;
            return switch (final_addr) {
                0x10, 0x14, 0x18, 0x1C => final_addr - 0x10,
                else => final_addr,
            };
        },
        else => return 0,
    }
}

fn decodeTile(tile: []const u8) [8 * 8]u32 {
    var flat_arr: [8 * 8]u3 = undefined;
    var color_arr: [8 * 8]u32 = undefined;

    const lo_start = 0;
    const hi_start = lo_start + 8;
    const low_plane = tile[lo_start..hi_start];
    const high_plane = tile[hi_start .. hi_start + 8];

    for (0..8) |y| {
        for (0..8) |x| {
            const bit: u3 = @intCast(7 - x);
            const lo: u1 = @truncate((low_plane[y] >> bit) & 0x1);
            const hi: u1 = @truncate((high_plane[y] >> bit) & 0x1);
            flat_arr[y * 8 + x] = (@as(u3, hi) << 1) | @as(u3, lo);
        }
    }

    for (0..flat_arr.len) |v| {
        switch (flat_arr[v]) {
            1 => color_arr[v] = 0xFF54_5454,
            0 => color_arr[v] = 0xFF00_0000,
            2 => color_arr[v] = 0xFF98_9898,
            3 => color_arr[v] = 0xFFEC_ECEC,
            else => {},
        }
    }
    return color_arr;
}

fn renderBackground(ppu: *PPU, fb: *[256 * 240]u32) void {
    bus.write(0x2006, 0x20);
    bus.write(0x2006, 0x00);
    for (0..30) |tile_y| {
        for (0..32) |tile_x| {
            const tile_index = bus.read(0x2007);
            const pattern_base: u16 = @as(u16, (ppu.ctrl >> 4) & 0x1) * 0x1000;
            const tile_addr = pattern_base + tile_index * 16;

            var tile_arr: [16]u8 = undefined;
            for (0..16) |i| {
                tile_arr[i] = bus.cartridge.ppuRead(tile_addr + i);
            }
            const tile_color = decodeTile(&tile_arr);
            fb = tile_color;
        }
    }
}
