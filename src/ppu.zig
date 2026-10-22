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
    ctrl_s: u8 = 0b0000_0100,
    mask: u8 = 0,
    status: u8 = 0,

    vram_addr: u16 = 0,
    vram_addr_hi: u8 = 0,
    vram_addr_lo: u8 = 0,
    vram_step: u8 = 1,
    addr_latch: bool = false,

    pub fn init(ctrd: *const cartridge_mod.Cartridge) PPU {
        var ppu = PPU{
            .cartridge = ctrd,
        };
        @memset(&ppu.vram, 0);
        @memset(&ppu.palette_ram, 0);
        return ppu;
    }

    fn read(self: *const PPU, addr: u16) u8 {
        const re_addr = resolve_addr(self, addr);
        switch (addr) {
            0x0000...0x1FFF => return self.cartridge.ppuRead(re_addr),
            0x2000...0x3EFF => return self.vram[re_addr],
            0x3F00...0x3FFF => return self.palette_ram[re_addr],
            else => return 0,
        }
    }

    fn write(self: *PPU, addr: u16, value: u8) void {
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
            0x2007 => {
                const value = self.read(self.vram_addr);
                self.vram_addr +%= self.vram_step;
                self.vram_addr &= MEM_MAP_16MASK;
                return value;
            },
            else => return 0,
        }
    }

    pub fn cpuWrite(self: *PPU, addr: u16, value: u8) void {
        switch (addr) {
            0x2000 => {
                self.ctrl = value;
                if (self.ctrl & self.ctrl_s != 0) {
                    self.vram_step = 32;
                } else {
                    self.vram_step = 1;
                }
            },
            0x2001 => {},
            0x2006 => {
                if (self.addr_latch == false) {
                    self.vram_addr_hi = value & MEM_MAP_8MASK;
                    self.addr_latch = true;
                } else {
                    self.vram_addr_lo = value;
                    self.addr_latch = false;
                }
                self.vram_addr = (@as(u16, self.vram_addr_hi) << 8) | (@as(u16, self.vram_addr_lo));
            },
            0x2007 => {
                self.write(self.vram_addr, value);
                self.vram_addr +%= self.vram_step;
                self.vram_addr &= MEM_MAP_16MASK;
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
