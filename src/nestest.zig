const std = @import("std");
const bus_mod = @import("bus.zig");
const cpu_mod = @import("cpu.zig");
const ppu_mod = @import("ppu.zig");
const cartridge = @import("cartridge.zig");

test "official instruction" {
    // create allocator
    const allocator = std.testing.allocator;
    // create IO
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var cart = try cartridge.loadCartridge(io, allocator, "roms/nestest.nes");
    defer cart.deinit(allocator);

    var bus = bus_mod.Bus.init(&cart);
    var cpu = cpu_mod.CPU.init(&bus);
    cpu.reset();
    cpu.pc = 0xC000;
    cpu.cycles = 7;

    for (0..5003) |_| {
        try cpu.step();
    }

    // 检查 CPU 状态
    try std.testing.expectEqual(@as(u16, 0xC6BD), cpu.pc);
    try std.testing.expectEqual(@as(u8, 0xAA), cpu.a);
    try std.testing.expectEqual(@as(u8, 0x97), cpu.x);
    try std.testing.expectEqual(@as(u8, 0x4E), cpu.y);
    try std.testing.expectEqual(@as(u8, 0xEF), cpu.status);
    try std.testing.expectEqual(@as(u8, 0xF9), cpu.sp);
    try std.testing.expectEqual(@as(u64, 14579), cpu.cycles);
}

test "ppu read" {
    // create allocator
    const allocator = std.testing.allocator;
    // create IO
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var cart = try cartridge.loadCartridge(io, allocator, "roms/SMB.nes");
    defer cart.deinit(allocator);

    var ppu = ppu_mod.PPU.init(&cart);
    for (0..8) |addr| {
        const a: u16 = @intCast(addr);
        const value = ppu.read(a);
        std.debug.print("0x{X:0>2} ", .{value});
    }
}
