const cartridge_mod = @import("cartridge.zig");
const VER_MASK: u16 = 0x07FF; // 2KB
const HOR_MASK: u16 = 0x03FF; // 1KB
const HOR_OFFSET: u16 = 0x0400;
const PALETTE_OFFSET: u16 = 0x3F00;
const PALETTE_MASK: u16 = 0x001F;

pub const PPU = struct {
    data: [2048]u8 = undefined,
    palette: [32]u8 = undefined,
    cartridge: *const cartridge_mod.Cartridge,

    pub fn init(ctrd: *const cartridge_mod.Cartridge) PPU {
        var ppu = PPU{
            .cartridge = ctrd,
        };
        @memset(&ppu.data, 0);
        @memset(&ppu.palette, 0);
        return ppu;
    }

    pub fn read(self: *const PPU, addr: u16) u8 {
        const re_addr = resolve_addr(self, addr);
        switch (addr) {
            0x0000...0x1FFF => return self.cartridge.ppuRead(re_addr),
            0x2000...0x3EFF => return self.data[re_addr],
            0x3F00...0x3FFF => return self.palette[re_addr],
            else => return 0,
        }
    }

    pub fn write(self: *PPU, addr: u16, value: u8) void {
        const re_addr = resolve_addr(self, addr);
        switch (addr) {
            0x2000...0x3EFF => self.data[re_addr] = value,
            0x3F00...0x3FFF => self.palette[re_addr] = value,
            else => {},
        }
    }
};

pub fn resolve_addr(ppu: *const PPU, addr: u16) u16 {
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
