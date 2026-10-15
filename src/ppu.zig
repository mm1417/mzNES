pub const PPU = struct {
    data: [2048]u8 = undefined,

    pub fn init() PPU {
        var ppu = PPU{};
        @memset(&ppu.data, 0);
        return ppu;
    }
};
