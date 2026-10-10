const std = @import("std");
const MAPPER0_MASK: u16 = 0xC000;
// const MAPPER0_MASK: u16 = 0x8000;

pub const Mirroring = enum {
    horizontal,
    vertical,
};

pub const INESHeader = struct {
    prg_banks: u8,
    chr_banks: u8,
    mapper: u8,
    mirroring: Mirroring,
    has_battery: bool,
    has_trainer: bool,
};

// ======== Cartridge ========
pub const Cartridge = struct {
    prg_rom: []u8,
    chr_rom: []u8,
    mapper: u8,
    mirroring: Mirroring,

    pub fn cpuRead(self: *const Cartridge, addr: u16) u8 {
        // 切换不同mapper
        switch (self.mapper) {
            0 => return self.prg_rom[addr - MAPPER0_MASK],

            else => unreachable,
        }
    }

    pub fn deinit(self: Cartridge, allocator: std.mem.Allocator) void {
        allocator.free(self.prg_rom);
        allocator.free(self.chr_rom);
    }
};

pub fn parseHeader(header: [16]u8) !INESHeader {
    if (!std.mem.eql(u8, header[0..4], &.{ 0x4E, 0x45, 0x53, 0x1A })) {
        return error.InvalidHeader;
    }

    const inh: INESHeader = .{
        .prg_banks = header[4],
        .chr_banks = header[5],
        .mapper = (header[7] & 0xF0) | (header[6] >> 4),

        .mirroring = if (header[6] & 0x01 != 0)
            .vertical
        else
            .horizontal,

        .has_battery = (header[6] & 0x02 != 0),
        .has_trainer = (header[6] & 0x04 != 0),
    };

    std.debug.print("PRG ROM: {d} banks \n", .{inh.prg_banks});
    std.debug.print("CHR ROM: {d} banks \n", .{inh.chr_banks});

    return inh;
}

pub fn loadCartridge(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Cartridge {
    // ======== 读取文件 ========
    var ctrd_file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer ctrd_file.close(io);

    var header: [16]u8 = undefined;
    const header_read = try ctrd_file.readStreaming(io, &.{&header});
    if (header_read != header.len) {
        return error.ReadHeaerError;
    }
    // -------- 读取文件 --------

    const inesheader = try parseHeader(header);
    if (inesheader.has_trainer) {
        return error.NotSupportTrainer;
    }

    // ======== 有切片结构体的初始化方法！非常重要！！ ========
    const prg_size = @as(usize, inesheader.prg_banks) * 16 * 1024; // u8升格为usize，否则会以u8进行计算
    const prg_rom = try allocator.alloc(u8, prg_size);
    errdefer allocator.free(prg_rom);
    const chr_size = @as(usize, inesheader.chr_banks) * 8 * 1024;
    const chr_rom = try allocator.alloc(u8, chr_size);
    errdefer allocator.free(chr_rom);

    const ctrd: Cartridge = .{
        .prg_rom = prg_rom,
        .chr_rom = chr_rom,
        .mapper = inesheader.mapper,
        .mirroring = inesheader.mirroring,
    };

    const prg_read = try ctrd_file.readStreaming(io, &.{ctrd.prg_rom});
    if (prg_read != ctrd.prg_rom.len) {
        return error.InvalidPRGROM;
    }

    const chr_read = try ctrd_file.readStreaming(io, &.{ctrd.chr_rom});
    if (chr_read != ctrd.chr_rom.len) {
        return error.InvalidCHRROM;
    }
    // -------- 有切片结构体的初始化方法！非常重要！！ --------

    std.debug.print("READ PRG ROM: {d} bytes \n", .{ctrd.prg_rom.len});
    std.debug.print("READ CHR ROM: {d} bytes \n", .{ctrd.chr_rom.len});
    return ctrd;
}
