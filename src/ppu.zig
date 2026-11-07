const std = @import("std");
const cartridge_mod = @import("cartridge.zig");

const MEM_MAP_16MASK: u16 = 0x3FFF;

const VER_MASK: u16 = 0x07FF; // 2Kb
const HOR_MASK: u16 = 0x03FF; // 1Kb
const HOR_OFFSET: u16 = 0x0400;
const PALETTE_START_ADDR: u16 = 0x3F00;
const S_PALETTE_START_ADDR: u16 = 0x3F10;
const PALETTE_MASK: u16 = 0x001F; // 32bytes
const ATTRIBUTE_START_ADDR: u16 = 0x23C0; // after nametable 0

const MAX_DOT: u16 = 341;
const MAX_SCANLINE: i16 = 262;

const NES_PALETTE = [64]u32{
    0xFF666666, 0xFF002A88, 0xFF1412A7, 0xFF3B00A4,
    0xFF5C007E, 0xFF6E0040, 0xFF6C0600, 0xFF561D00,
    0xFF333500, 0xFF0B4800, 0xFF005200, 0xFF004F08,
    0xFF00404D, 0xFF000000, 0xFF000000, 0xFF000000,

    0xFFADADAD, 0xFF155FD9, 0xFF4240FF, 0xFF7527FE,
    0xFFA01ACC, 0xFFB71E7B, 0xFFB53120, 0xFF994E00,
    0xFF6B6D00, 0xFF388700, 0xFF0C9300, 0xFF008F32,
    0xFF007C8D, 0xFF000000, 0xFF000000, 0xFF000000,

    0xFFFFFEFF, 0xFF64B0FF, 0xFF9290FF, 0xFFC676FF,
    0xFFF36AFF, 0xFFFE6ECC, 0xFFFE8170, 0xFFEA9E22,
    0xFFBCBE00, 0xFF88D800, 0xFF5CE430, 0xFF45E082,
    0xFF48CDDE, 0xFF4F4F4F, 0xFF000000, 0xFF000000,

    0xFFFFFEFF, 0xFFC0DFFF, 0xFFD3D2FF, 0xFFE8C8FF,
    0xFFFBC2FF, 0xFFFEC4EA, 0xFFFECCC5, 0xFFF7D8A5,
    0xFFE4E594, 0xFFCFEE96, 0xFFBDF4AB, 0xFFB3F3CC,
    0xFFB5EBF2, 0xFFB8B8B8, 0xFF000000, 0xFF000000,
};

pub const PPU = struct {
    vram: [2048]u8 = undefined,
    palette_ram: [32]u8 = undefined,
    oam: [256]u8 = undefined,
    oam_addr: u8 = 0,
    cartridge: *const cartridge_mod.Cartridge,

    ctrl: u8 = 0,
    mask: u8 = 0,
    status: u8 = 0,

    // loopy registers
    v: u16 = 0, // current VRAM addr, 15bits
    t: u16 = 0, // temp VRAM addr, 15bits
    fine_x: u3 = 0, // fine X scroll, 3bits
    write_toggle: bool = false, // write toggle

    vram_step: u8 = 1,

    scroll_x: u8 = 0,
    scroll_y: u8 = 0,

    databuffer: u8 = 0,

    dot: u16 = 0, // 341 max (0..340)
    scanline: i16 = 0, // 262 max (0..261)
    nmi_pending: bool = false,
    frame_complete: bool = false,

    pub fn init(ctrd: *const cartridge_mod.Cartridge) PPU {
        var ppu = PPU{
            .cartridge = ctrd,
        };
        @memset(&ppu.vram, 0);
        @memset(&ppu.palette_ram, 0);
        @memset(&ppu.oam, 0);

        // ===== testing =====
        // ppu.writeRam(0x3F00, 0x0F);
        // ppu.writeRam(0x3F01, 0x16);
        // ppu.writeRam(0x3F02, 0x27);
        // ppu.writeRam(0x3F03, 0x30);
        // ppu.writeRam(0x3F05, 0x12);
        // ppu.writeRam(0x3F06, 0x22);
        // ppu.writeRam(0x3F07, 0x32);
        // ===== testing =====

        return ppu;
    }

    pub fn step(self: *PPU) void {
        // scanline 0-239    可见区域，PPU 在画像素
        // scanline 240      Post-render
        // scanline 241-260  VBlank
        // scanline 261      Pre-render 扫描线（为下一帧准备）
        self.dot += 1;

        if (self.dot == 1 and self.scanline == 241) {
            self.status |= 0b1000_0000; // enable VBlank bit (7th bit)
            self.status |= 0b0100_0000; // TMEP: enable 0 hit bit (6th bit)

            if (self.ctrl & 0b1000_0000 != 0) {
                self.nmi_pending = true;
                // std.debug.print("enter NMI\n", .{});
            }
            // std.debug.print("===== enter VBlank =====\n", .{});
        }
        if (self.dot == 1 and self.scanline == 261) {
            // self.status &= 0b0111_1111; // clear VBlank (7th)
            self.status &= 0b0001_1111; // TEMP: clear VBlank (7th), 0 Hit(6th), Sprite Overflow(5th)
        }

        if (self.dot >= MAX_DOT) {
            self.dot = 0;
            self.scanline += 1;

            if (self.scanline >= MAX_SCANLINE) {
                self.scanline = 0;
                self.frame_complete = true;
            }
        }
    }

    pub fn readRam(self: *const PPU, addr: u16) u8 {
        const re_addr = resolve_addr(self, addr);
        switch (addr) {
            0x0000...0x1FFF => return self.cartridge.ppuRead(addr),
            0x2000...0x3EFF => return self.vram[re_addr],
            0x3F00...0x3FFF => return self.palette_ram[re_addr],
            else => return 0,
        }
    }

    pub fn writeRam(self: *PPU, addr: u16, value: u8) void {
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
                self.write_toggle = false;
                return value;
            },
            0x2003 => return self.oam_addr,
            0x2004 => return self.oam[self.oam_addr],
            0x2007 => {
                const addr_tmp = self.v & 0x3FFF;
                const value = self.readRam(addr_tmp);
                self.v +%= self.vram_step;
                self.v &= MEM_MAP_16MASK;

                if (addr_tmp >= PALETTE_START_ADDR) {
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
                    self.vram_step = 32;
                } else {
                    self.vram_step = 1;
                }

                // set register t nametalbe, bit 10-11
                self.t = (self.t & 0b1111_0011_1111_1111) | (@as(u16, value & 0x03) << 10);
            },
            0x2001 => self.mask = value,
            0x2003 => self.oam_addr = value,
            0x2004 => {
                self.oam[self.oam_addr] = value;
                self.oam_addr +%= 1;
            },
            0x2005 => {
                if (self.write_toggle == false) {
                    // 第一次写入 coarse x (5位，且最高位是0)
                    self.t = (self.t & 0b0111_1111_1110_0000) | @as(u16, value >> 3);
                    // 第一次写入 fine x (单独寄存器，3位)
                    self.fine_x = @truncate(value & 0b111);
                    self.write_toggle = true;
                } else {
                    // 第二次写入 coarse y (5位，且最高位是0)
                    self.t =
                        (self.t & 0b0111_1100_0001_1111) |
                        @as(u16, value & 0b1111_1000) << 2 |
                        // fine y
                        @as(u16, value & 0b0000_0111) << 12;
                    self.write_toggle = false;
                }
            },
            0x2006 => {
                if (self.write_toggle == false) {
                    // 先写入高8位，PPU寻址最多14位，所以最高2位是0
                    self.t = (self.t & 0x00FF) | (@as(u16, value & 0b0011_1111) << 8);
                    self.write_toggle = true;
                } else {
                    // 再写入低8位
                    self.t = (self.t & 0xFF00) | @as(u16, value);
                    self.v = self.t;
                    self.write_toggle = false;
                }
            },
            0x2007 => {
                self.writeRam(self.v & 0x3FFF, value);
                self.v +%= self.vram_step;
                self.v &= MEM_MAP_16MASK;
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
            const final_addr = (addr - PALETTE_START_ADDR) & PALETTE_MASK;
            return switch (final_addr) {
                0x10, 0x14, 0x18, 0x1C => final_addr - 0x10,
                else => final_addr,
            };
        },
        else => return 0,
    }
}

fn decodeTile(tile: []const u8) [8 * 8]u3 {
    const low_plane = tile[0..8];
    const high_plane = tile[8..16];
    var arr: [8 * 8]u3 = undefined;

    for (0..8) |y| {
        for (0..8) |x| {
            const bit: u3 = @intCast(7 - x);
            const lo: u1 = @truncate((low_plane[y] >> bit) & 0x1);
            const hi: u1 = @truncate((high_plane[y] >> bit) & 0x1);
            const pixel = (@as(u3, hi) << 1) | @as(u3, lo);
            const index = y * 8 + x;

            arr[index] = pixel;
        }
    }
    return arr;
}

pub fn renderBackground(ppu: *PPU, fb: *[256 * 240]u32) void {
    for (0..30) |tile_y| {
        for (0..32) |tile_x| {
            // 1. Nametalbe中找到tile编号
            const nt_addr: u16 = 0x2000 + @as(u16, @intCast(tile_y * 32 + tile_x));
            const tile_index = ppu.readRam(nt_addr);

            // 2. PPUCTRL bit4 决定Pattern Table
            const pattern_base: u16 = @as(u16, (ppu.ctrl >> 4) & 0x1) * 0x1000;

            // 3. 找到tile的16 bytes
            const tile_addr: u16 = pattern_base + @as(u16, tile_index) * 16;

            var tile_arr: [16]u8 = undefined;
            for (0..16) |i| {
                // i是usize类型，@as不做类型检查！！！
                tile_arr[i] = ppu.readRam(tile_addr + @as(u16, @intCast(i)));
            }
            const decoded_tile = decodeTile(&tile_arr);
            var colored_tile: [64]u32 = undefined;

            // 4. 找到属于第几快palette
            const palette_id: u16 = @as(u16, getBackgroundPaletteID(ppu, @intCast(tile_x), @intCast(tile_y)));
            for (0..64) |i| {
                var palette_addr: u16 = undefined;
                if (decoded_tile[i] == 0) {
                    palette_addr = 0;
                } else {
                    palette_addr = palette_id * 4 + @as(u16, decoded_tile[i]);
                }

                const nes_color_index = ppu.palette_ram[palette_addr];
                colored_tile[i] = NES_PALETTE[nes_color_index];
            }

            // 5. 转换成屏幕数组
            for (0..8) |pixel_y| {
                for (0..8) |pixel_x| {
                    const screen_x = tile_x * 8 + pixel_x;
                    const screen_y = tile_y * 8 + pixel_y;
                    const framebuffer_index = screen_y * 256 + screen_x;
                    const arr_index = pixel_y * 8 + pixel_x;
                    fb[framebuffer_index] = colored_tile[arr_index];
                }
            }
        }
    }
}

// 得到这是第几组Palette
pub fn getBackgroundPaletteID(ppu: *const PPU, tile_x: u8, tile_y: u8) u8 {
    // 4x4 个tile公用一个 attribute table
    const attribute_x = tile_x / 4;
    const attribute_y = tile_y / 4;

    // 一屏有 8x8 个 attribute table, 64 bytes attr_addr after nametable
    const attribute_addr = ATTRIBUTE_START_ADDR + @as(u16, attribute_y * 8 + attribute_x);

    const attr = ppu.readRam(attribute_addr);
    const local_x = tile_x % 4;
    const local_y = tile_y % 4;

    // 左上 0
    // 右上 2
    // 左下 4
    // 右下 6
    // 横向贡献 左 0，右 2
    // 纵向贡献 上 0，下 4
    const shift = (local_x / 2) * 2 + (local_y / 2) * 4;

    return (attr >> @intCast(shift)) & 0b11;
}

pub fn renderSprite(ppu: *PPU, fb: *[256 * 240]u32) void {
    // maximum 64 sprites per screen
    var sprite_index: usize = 64;
    while (sprite_index > 0) : (sprite_index -= 1) {
        const base = sprite_index * 4;
        const y = ppu.oam[base - 4];
        const tile_index = ppu.oam[base - 3];
        const attribute = ppu.oam[base - 2];
        const x = ppu.oam[base - 1];

        // ===== DEBUG =====
        // if (y < 0xEF) {
        //     std.debug.print(
        //         "sprite {d}: Y={X:0>2} T={X:0>2} A={X:0>2} X={X:0>2}\n",
        //         .{ sprite_index - 1, y, tile_index, attribute, x },
        //     );
        // }

        // 处理attribute
        const flip_v = attribute & 0b1000_0000 != 0;
        const flip_h = attribute & 0b0100_0000 != 0;
        const palette_id = attribute & 0b0000_0011;

        // 处理tile_index，找到tile的16bytes
        const pattern_base: u16 = @as(u16, (ppu.ctrl >> 3) & 0x01) * 0x1000;
        const tile_addr: u16 = pattern_base + @as(u16, tile_index) * 16;

        var tile_arr: [16]u8 = undefined;
        for (0..16) |i| {
            // i是usize类型，@as不做类型检查！！！
            tile_arr[i] = ppu.readRam(tile_addr + @as(u16, @intCast(i)));
        }
        const decoded_tile = decodeTile(&tile_arr);

        // ===== DEBUG =====
        // if (sprite_index == 1) {
        //     var visible_pixels: usize = 0;

        //     for (decoded_tile) |pixel| {
        //         if (pixel != 0) {
        //             visible_pixels += 1;
        //         }
        //     }

        //     std.debug.print(
        //         \\===== SPRITE 0 DEBUG =====
        //         \\PPUCTRL: {b:0>8}
        //         \\PPUMASK: {b:0>8}
        //         \\Sprite size: {s}
        //         \\Pattern base: ${X:0>4}
        //         \\Tile address: ${X:0>4}
        //         \\Visible pixels: {d}/64
        //         \\Palette: {X:0>2} {X:0>2} {X:0>2}
        //         \\
        //     , .{
        //         ppu.ctrl,
        //         ppu.mask,
        //         if (ppu.ctrl & 0x20 != 0) "8x16" else "8x8",
        //         pattern_base,
        //         tile_addr,
        //         visible_pixels,
        //         ppu.readRam(0x3F1D),
        //         ppu.readRam(0x3F1E),
        //         ppu.readRam(0x3F1F),
        //     });
        // }

        for (0..8) |pixel_y| {
            for (0..8) |pixel_x| {
                const src_x =
                    if (flip_h) 7 - pixel_x else pixel_x;

                const src_y =
                    if (flip_v) 7 - pixel_y else pixel_y;

                const pixel = decoded_tile[src_y * 8 + src_x];
                if (pixel == 0) continue;
                const palette_addr = S_PALETTE_START_ADDR + @as(u16, palette_id) * 4 + @as(u16, pixel);
                const color_index = ppu.readRam(palette_addr) & 0x3F;

                const screen_x = @as(usize, x) + pixel_x;
                const screen_y = @as(usize, y) + 1 + pixel_y;
                if (screen_x >= 256 or screen_y >= 240) continue;

                const framebuffer_index = screen_y * 256 + screen_x;
                fb[framebuffer_index] = NES_PALETTE[color_index];
            }
        }
    }
}

pub fn renderScanline(ppu: *PPU, fb: [256 * 240]u32, scanline: usize) void {}
