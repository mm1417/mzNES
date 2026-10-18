const cartridge_mod = @import("cartridge.zig");
const VER_MASK: u16 = 0x07FF; // 2KB
const HOR_MASK: u16 = 0x03FF; // 1KB
const HOR_OFFSET: u16 = 0x0400;

pub const PPU = struct {
    data: [2048]u8 = undefined,
    cartridge: *const cartridge_mod.Cartridge,

    pub fn init(ctrd: *const cartridge_mod.Cartridge) PPU {
        var ppu = PPU{
            .cartridge = ctrd,
        };
        @memset(&ppu.data, 0);
        return ppu;
    }

    pub fn read(self: *const PPU, addr: u16) u8 {
        switch (addr) {
            0x0000...0x1FFF => return self.cartridge.ppuRead(addr),
            0x2000...0x2FFF => {
                switch (self.cartridge.mirroring) {
                    // A1 B2
                    // A3 B4
                    .vertical => return self.data[addr & VER_MASK],
                    // A1 A2
                    // B3 B4
                    .horizontal => {
                        if (addr <= 0x27FF) {
                            return self.data[addr & HOR_MASK];
                        } else {
                            return self.data[(addr & HOR_MASK) + HOR_OFFSET];
                        }
                    },
                }
            },
            else => return 0,
        }
    }

    pub fn write(self: *PPU, addr: u16, value: u8) void {
        switch (addr) {
            0x2000...0x2FFF => {
                switch (self.cartridge.mirroring) {
                    // A1 B2
                    // A3 B4
                    .vertical => self.data[addr & VER_MASK] = value,
                    // A1 A2
                    // B3 B4
                    .horizontal => {
                        if (addr <= 0x27FF) {
                            self.data[addr & HOR_MASK] = value;
                        } else {
                            self.data[(addr & HOR_MASK) + HOR_OFFSET] = value;
                        }
                    },
                }
            },
            else => {},
        }
    }
};
