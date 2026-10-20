const memory_mod = @import("memory.zig");
const cartridge_mod = @import("cartridge.zig");
const ppu_mod = @import("ppu.zig");

const ADDR_MASK: u16 = 0x07FF;
const PPU_REG_MASK: u16 = 0x2007; // 8bytes

pub const Bus = struct {
    ram: memory_mod.Memory,
    ppu: ppu_mod.PPU,
    cartridge: *const cartridge_mod.Cartridge,

    pub fn init(ctrd: *const cartridge_mod.Cartridge) Bus {
        return Bus{
            .ram = memory_mod.Memory.init(),
            .ppu = ppu_mod.PPU.init(ctrd),
            .cartridge = ctrd,
        };
    }

    pub fn read(self: *Bus, addr: u16) u8 {
        switch (addr) {
            // RAM with mirrors
            0x0000...0x1FFF => return self.ram.read(addr & ADDR_MASK),

            // PPU registers with mirrors
            0x2000...0x3FFF => return self.ppu.cpuRead(addr & PPU_REG_MASK),

            // APU and IO
            0x4000...0x4017 => {
                return 0;
            },

            // disabled/test
            0x4018...0x401F => {
                return 0;
            },

            // mapper cartridge
            0x4020...0x7FFF => {
                return 0;
            },

            // cartridge
            0x8000...0xFFFF => return self.cartridge.cpuRead(addr),
        }
    }

    pub fn write(self: *Bus, addr: u16, value: u8) void {
        switch (addr) {
            // RAM with mirrors
            0x0000...0x1FFF => self.ram.write(addr & ADDR_MASK, value),

            // PPU registers with mirrors
            0x2000...0x3FFF => self.ppu.cpuWrite(addr & PPU_REG_MASK, value),

            // APU and IO
            0x4000...0x4017 => {},

            // disabled/test
            0x4018...0x401F => {},

            // cartridge
            0x4020...0xFFFF => {},
        }
    }
};
