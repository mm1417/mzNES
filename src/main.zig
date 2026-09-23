const std = @import("std");
const bus_mod = @import("bus.zig");
const cpu_mod = @import("cpu.zig");
const sdl = @import("sdl.zig");
const cartridge = @import("cartridge.zig");

const SCREEN_WIDTH: u16 = 256;
const SCREEN_HEIGHT: u16 = 240;

var framebuffer: [SCREEN_HEIGHT * SCREEN_WIDTH]u32 = undefined;
var frame: u32 = 0;

fn drawTextPattern(
    buf: []u32,
    frame_count: u32,
) void {
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

// ======== MAIN ========
pub fn main(init: std.process.Init) !void {
    var cart = try cartridge.loadCartridge(init.io, init.gpa, "roms/SMB.nes");
    defer cart.deinit(init.gpa);

    var bus = bus_mod.Bus.init(&cart);
    var cpu = cpu_mod.CPU.init(&bus);
    cpu.reset();
    try cpu.step();
    try cpu.step();
    try cpu.step();

    std.debug.print("PC: {X:0>4}\n", .{cpu.pc});
    std.debug.print("A: {X:0>4}\n", .{cpu.a});

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
        SCREEN_HEIGHT,
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
        drawTextPattern(&framebuffer, frame);
        frame += 1;
        _ = sdl.SDL_UpdateTexture(texture, null, &framebuffer, SCREEN_WIDTH * @sizeOf(u32));

        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderTexture(renderer, texture, null, null);
        _ = sdl.SDL_RenderPresent(renderer);

        sdl.SDL_Delay(16);
    }
    // -------- main loop here --------
}
