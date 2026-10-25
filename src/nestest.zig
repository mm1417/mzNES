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
        std.debug.print("0x{X:0>2}\n", .{value});
    }

    ppu.write(0x2000, 0xAA);
    var v1 = ppu.read(0x2000);
    var v2 = ppu.read(0x2800);
    std.debug.print("0x2000 is: {X:0>2}\n0x2800 is: {X:0>2}\n", .{ v1, v2 });

    ppu.write(0x2400, 0xBB);
    v1 = ppu.read(0x2400);
    v2 = ppu.read(0x2C00);
    std.debug.print("0x2400 is: {X:0>2}\n0x2C00 is: {X:0>2}\n", .{ v1, v2 });
}

test "ppu reg" {
    // create allocator
    const allocator = std.testing.allocator;
    // create IO
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var cart = try cartridge.loadCartridge(io, allocator, "roms/SMB.nes");
    defer cart.deinit(allocator);
    var bus = bus_mod.Bus.init(&cart);

    // ===== 测试读写功能 =====
    bus.write(0x2006, 0x3F);
    bus.write(0x2006, 0x00);
    bus.write(0x2007, 0x0F);
    // 每次读写2007，地址会自动加一，需要重新定位内存地址
    bus.write(0x200E, 0x3F);
    bus.write(0x200E, 0x00);

    std.debug.print("It's palette ram\n", .{});
    std.debug.print("address is {X:0>2}\n======\n", .{bus.ppu.ppu_addr});
    try std.testing.expectEqual(@as(u8, 0x0F), bus.read(0x2007));

    // ===== 测试VRAM increment =====
    bus.write(0x2000, 0x00);
    try std.testing.expectEqual(@as(u8, 1), bus.ppu.ppu_addr_step);

    bus.write(0x2000, 0x04);
    try std.testing.expectEqual(@as(u8, 32), bus.ppu.ppu_addr_step);

    bus.write(0x2006, 0x20);
    bus.write(0x2006, 0x00);

    std.debug.print("address is {X:0>2}\n", .{bus.ppu.ppu_addr});
    bus.write(0x2007, 0x11);
    std.debug.print("address is {X:0>2}\n=====\n", .{bus.ppu.ppu_addr});
    bus.write(0x2007, 0x22);

    bus.write(0x2006, 0x20);
    bus.write(0x2006, 0x00);
    std.debug.print("address is {X:0>2}\n", .{bus.ppu.ppu_addr});
    try std.testing.expectEqual(@as(u8, 0x00), bus.read(0x2007));
    std.debug.print("address is {X:0>2}\n", .{bus.ppu.ppu_addr});
    try std.testing.expectEqual(@as(u8, 0x11), bus.read(0x2007));
    std.debug.print("address is {X:0>2}\n", .{bus.ppu.ppu_addr});
    try std.testing.expectEqual(@as(u8, 0x22), bus.read(0x2007));
    std.debug.print("address is {X:0>2}\n", .{bus.ppu.ppu_addr});
}
