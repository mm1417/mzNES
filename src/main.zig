const std = @import("std");
const bus_mod = @import("bus.zig");
const cpu_mod = @import("cpu.zig");
const ppu_mod = @import("ppu.zig");
const sdl = @import("sdl.zig");
const cartridge = @import("cartridge.zig");

const SCREEN_WIDTH: u16 = 256;
const SCREEN_HEIGHT: u16 = 240;

var framebuffer: [SCREEN_HEIGHT * SCREEN_WIDTH]u32 = undefined;
var frame: u32 = 0;

fn drawTextPattern(buf: []u32, frame_count: u32) void {
    for (0..SCREEN_HEIGHT) |y| {
        for (0..SCREEN_WIDTH) |x| {
            const index = y * SCREEN_WIDTH + x;

            if (((x + frame_count) / 16 + y / 16) % 2 == 0) {
                buf[index] = 0xFFFF_0000;
            } else {
                buf[index] = 0xFF00_0000;
            }
        }
    }
}

// fn drawTile(buf: []u8) void {}

fn decodeTile(tile: []const u8) [64 * 512]u32 {
    const tile_count = tile.len / 16;
    var flat_arr: [64 * 512]u3 = undefined;
    var color_arr: [64 * 512]u32 = undefined;

    const TILE_PER_ROW = 32; // 一行32个tile

    var i: usize = 0;
    while (i < tile_count) : (i += 1) {
        const tile_x = i % TILE_PER_ROW;
        const tile_y = i / TILE_PER_ROW;

        const lo_start = i * 16;
        const hi_start = lo_start + 8;
        const low_plane = tile[lo_start..hi_start];
        const high_plane = tile[hi_start .. hi_start + 8];

        for (0..8) |y| {
            for (0..8) |x| {
                const bit: u3 = @intCast(7 - x);
                const lo: u1 = @truncate((low_plane[y] >> bit) & 0x1);
                const hi: u1 = @truncate((high_plane[y] >> bit) & 0x1);

                const px = tile_x * 8 + x;
                const py = tile_y * 8 + y;
                flat_arr[py * 256 + px] = (@as(u3, hi) << 1) | @as(u3, lo);
            }
        }
    }

    for (0..flat_arr.len) |v| {
        switch (flat_arr[v]) {
            1 => color_arr[v] = 0xFF54_5454,
            0 => color_arr[v] = 0xFF00_0000,
            2 => color_arr[v] = 0xFF98_9898,
            3 => color_arr[v] = 0xFFEC_ECEC,
            else => {},
        }
    }
    return color_arr;
}

// ======== MAIN ========
pub fn main(init: std.process.Init) !void {
    var cart = try cartridge.loadCartridge(init.io, init.gpa, "roms/SMB.nes");
    defer cart.deinit(init.gpa);

    var bus = bus_mod.Bus.init(&cart);
    var cpu = cpu_mod.CPU.init(&bus);
    var ppu = ppu_mod.PPU.init(&cart);
    _ = ppu.read(1);

    cpu.reset();
    const chr_exam: []const u8 = bus.cartridge.chr_rom;
    // std.debug.print("{any}", .{chr_exam});
    // std.debug.dumpHex(chr_exam);
    const tile = decodeTile(chr_exam);

    // ======== 初始化SDL ========
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("zmNES", 768, 720, 0) orelse return error.SDLCreateWindowFailed;
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, null) orelse return error.SDLCreateRendererFailed;
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTexture(
        renderer,
        sdl.SDL_PIXELFORMAT_ARGB8888,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        SCREEN_WIDTH,
        128,
    ) orelse return error.SDLCreateTextureFailed;
    defer sdl.SDL_DestroyTexture(texture);

    if (!sdl.SDL_SetTextureScaleMode(texture, .nearest)) {
        return error.SDLSetTextureScaleModeFailed;
    }
    // -------- 初始化SDL --------

    var running = true;

    // ======== main loop here ========
    while (running) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                running = false;
            }
        }

        // -------- SDL event --------
        // _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        // drawTextPattern(&framebuffer, frame);
        // frame += 1;

        // !!IMPORTANT!! 数据类型必须是f32！
        const DST = struct {
            x: f32 = 10,
            y: f32 = 10,
            w: f32 = 256 * 2,
            h: f32 = 128 * 2,
        };
        const dst = DST{};

        _ = sdl.SDL_UpdateTexture(texture, null, &tile, SCREEN_WIDTH * @sizeOf(u32));
        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderTexture(renderer, texture, null, &dst);
        _ = sdl.SDL_RenderPresent(renderer);

        sdl.SDL_Delay(16);
    }
    // -------- main loop here --------
}
