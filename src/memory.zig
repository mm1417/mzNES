pub const Memory = struct {
    data: [2048]u8 = undefined,

    pub fn init() Memory {
        var mem = Memory{};
        @memset(&mem.data, 0);
        return mem;
    }

    pub fn read(self: *const Memory, addr: u16) u8 {
        return self.data[addr];
    }

    pub fn write(self: *Memory, addr: u16, value: u8) void {
        self.data[addr] = value;
    }

    // const切片不能返回可变切片！！！
    pub fn oamRead(self: *const Memory, addr: u16) []const u8 {
        return self.data[addr .. addr + 256];
    }
};
