const std = @import("std");
const Bus = @import("bus.zig").Bus;
const STACK_BASE: u16 = 0x100;

const Operation = enum {
    // Load/store
    lda,
    ldx,
    ldy,
    sta,
    stx,
    sty,

    // Register
    tax,
    tay,
    txa,
    tya,
    tsx,
    txs,

    // Stack
    pha,
    php,
    pla,
    plp,

    // Arithmetic
    adc,
    sbc,

    // Logic
    and_,
    ora,
    eor,

    // Compare
    cmp,
    cpx,
    cpy,

    // Increment/decrement
    inc,
    inx,
    iny,
    dec,
    dex,
    dey,

    // Shift
    asl,
    lsr,
    rol,
    ror,

    // Jump
    jmp,
    jsr,
    rts,

    // Branch
    bcc,
    bcs,
    beq,
    bmi,
    bne,
    bpl,
    bvc,
    bvs,

    // Flags
    clc,
    cld,
    cli,
    clv,
    sec,
    sed,
    sei,

    // Other
    nop,
    brk,
    rti,
};

const Flags = struct {
    const Carry: u8 = 0x01;
    const Zero: u8 = 0x02;
    const InterruptDisable: u8 = 0x04;
    const Decimal: u8 = 0x08;
    const Break: u8 = 0x10;
    const Unused: u8 = 0x20;
    const Overflow: u8 = 0x40;
    const Negative: u8 = 0x80;
};

const AddressingMode = enum {
    accumulator,
    implied,
    immediate,
    absolute,
    absolute_x,
    absolute_y,
    zeropage,
    zeropage_x,
    zeropage_y,
    indexed_indirect,
    indirect_indexed,
    // 特殊控制流
    indirect,
    relative,
};

const Instruction = struct {
    operation: Operation,
    mode: AddressingMode,
    bytes: u8,
    cycles: u8,
    page_cycle_penalty: bool = false,
};

const AddressResult = struct {
    addr: u16,
    page_crossed: bool = false,
};

// ======== CPU ========
pub const CPU = struct {
    a: u8,
    x: u8,
    y: u8,

    sp: u8,
    pc: u16,
    status: u8,

    cycles: u64,

    bus: *Bus,

    pub fn init(bus: *Bus) CPU {
        return .{
            .a = 0,
            .x = 0,
            .y = 0,
            .sp = 0,
            .pc = 0,
            .status = 0,
            .cycles = 0,
            .bus = bus,
        };
    }

    pub fn reset(self: *CPU) void {
        const reset_low = self.bus.read(0xFFFC);
        const reset_high = self.bus.read(0xFFFD);
        const reset_addr = readU16LE(reset_low, reset_high);
        self.pc = reset_addr;
    }

    pub fn fetchByte(self: *CPU) u8 {
        const code = self.bus.read(self.pc);
        self.pc +%= 1;
        return code;
    }

    pub fn fetchWord(self: *CPU) u16 {
        const addr_low = self.fetchByte();
        const addr_high = self.fetchByte();
        const final_addr: u16 = readU16LE(addr_low, addr_high);
        return final_addr;
    }

    pub fn getFlag(self: *CPU, flag: u8) bool {
        return self.status & flag != 0;
    }

    pub fn setFlag(self: *CPU, flag: u8, value: bool) void {
        if (value) {
            self.status |= flag;
        } else {
            self.status &= ~flag;
        }
    }

    pub fn setFlagZN(self: *CPU, value: u8) void {
        self.setFlag(Flags.Zero, value == 0);
        self.setFlag(Flags.Negative, value & 0x80 != 0);
    }

    // important!!
    pub fn setAdcOverflow(self: *CPU, a: u8, m: u8, result: u8) void {
        self.setFlag(Flags.Overflow, ((a ^ m) & 0x80 == 0) and ((a ^ result) & 0x80 != 0));
    }

    pub fn setSbcOverflow(self: *CPU, a: u8, m: u8, result: u8) void {
        self.setFlag(Flags.Overflow, ((a ^ m) & 0x80 != 0) and ((a ^ result) & 0x80 != 0));
    }

    pub fn pushStack(self: *CPU, value: u8) void {
        const sp_addr: u16 = STACK_BASE + @as(u16, self.sp);
        self.bus.write(sp_addr, value);
        self.sp -%= 1;
    }

    pub fn popStack(self: *CPU) u8 {
        self.sp +%= 1;
        const sp_addr: u16 = STACK_BASE + @as(u16, self.sp);
        return self.bus.read(sp_addr);
    }

    pub fn trace(self: *CPU, pc: u16, ins: Instruction) void {
        std.debug.print("{X:0>4}    ", .{pc});
        var i: u8 = 0;
        while (i < ins.bytes) : (i += 1) {
            std.debug.print("{X:0>2}  ", .{self.bus.read(pc + @as(u16, i))});
        }

        std.debug.print(
            "{s}  A:{X:0>2} X:{X:0>2} Y:{X:0>2} P:{X:0>2} SP:{X:0>2} CYC:{d}\n",
            .{
                @tagName(ins.operation),
                self.a,
                self.x,
                self.y,
                self.status,
                self.sp,
                self.cycles,
            },
        );
    }

    pub fn step(self: *CPU) !void {
        const pc_before = self.pc;

        const code = self.fetchByte();
        const ins = try decode(code);

        self.trace(pc_before, ins);

        self.execute(ins);
    }

    // ======== OPCODE TABLE ========
    pub fn decode(opcode: u8) !Instruction {
        return switch (opcode) {
            0x78 => .{
                .operation = .sei,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },

            0xD8 => .{
                .operation = .cld,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },

            // ===== load =====
            // LDA
            0xA9 => .{
                .operation = .lda,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0xA5 => .{
                .operation = .lda,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0xB5 => .{
                .operation = .lda,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0xAD => .{
                .operation = .lda,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0xBD => .{
                .operation = .lda,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0xB9 => .{
                .operation = .lda,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0xA1 => .{
                .operation = .lda,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0xB1 => .{
                .operation = .lda,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 5,
                .page_cycle_penalty = true,
            },
            //LDX
            0xA2 => .{
                .operation = .ldx,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0xA6 => .{
                .operation = .ldx,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0xB6 => .{
                .operation = .ldx,
                .mode = .zeropage_y,
                .bytes = 2,
                .cycles = 4,
            },
            0xAE => .{
                .operation = .ldx,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0xBE => .{
                .operation = .ldx,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            //LDY
            0xA0 => .{
                .operation = .ldy,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0xA4 => .{
                .operation = .ldy,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0xB4 => .{
                .operation = .ldy,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0xAC => .{
                .operation = .ldy,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0xBC => .{
                .operation = .ldy,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },

            // ===== store =====
            // STA
            0x85 => .{
                .operation = .sta,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x95 => .{
                .operation = .sta,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0x8D => .{
                .operation = .sta,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0x9D => .{
                .operation = .sta,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 5,
            },
            0x99 => .{
                .operation = .sta,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 5,
            },
            0x81 => .{
                .operation = .sta,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0x91 => .{
                .operation = .sta,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 6,
            },
            //STX
            0x86 => .{
                .operation = .stx,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x96 => .{
                .operation = .stx,
                .mode = .zeropage_y,
                .bytes = 2,
                .cycles = 4,
            },
            0x8E => .{
                .operation = .stx,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            //STY
            0x84 => .{
                .operation = .sty,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x94 => .{
                .operation = .sty,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0x8C => .{
                .operation = .sty,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            // ===== register =====
            // TAX
            0xAA => .{
                .operation = .tax,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // TAY
            0xA8 => .{
                .operation = .tay,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // TSX
            0xBA => .{
                .operation = .tsx,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // TXA
            0x8A => .{
                .operation = .txa,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // TXS
            0x9A => .{
                .operation = .txs,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // TYA
            0x98 => .{
                .operation = .tya,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // INX
            0xE8 => .{
                .operation = .inx,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // INY
            0xC8 => .{
                .operation = .iny,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // DEX
            0xCA => .{
                .operation = .dex,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },
            // DEY
            0x88 => .{
                .operation = .dey,
                .mode = .implied,
                .bytes = 1,
                .cycles = 2,
            },

            // ===== stack =====
            // PHA
            0x48 => .{
                .operation = .pha,
                .mode = .implied,
                .bytes = 1,
                .cycles = 3,
            },
            // PHP
            0x08 => .{
                .operation = .php,
                .mode = .implied,
                .bytes = 1,
                .cycles = 3,
            },
            // PLA
            0x68 => .{
                .operation = .pla,
                .mode = .implied,
                .bytes = 1,
                .cycles = 4,
            },
            // PLP
            0x28 => .{
                .operation = .plp,
                .mode = .implied,
                .bytes = 1,
                .cycles = 4,
            },

            // ===== Artihmetic ====
            // ADC
            0x69 => .{
                .operation = .adc,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0x65 => .{
                .operation = .adc,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x75 => .{
                .operation = .adc,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0x6D => .{
                .operation = .adc,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0x7D => .{
                .operation = .adc,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x79 => .{
                .operation = .adc,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x61 => .{
                .operation = .adc,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0x71 => .{
                .operation = .adc,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 5,
                .page_cycle_penalty = true,
            },
            // SBC
            0xE9 => .{
                .operation = .sbc,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0xE5 => .{
                .operation = .sbc,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0xF5 => .{
                .operation = .sbc,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0xED => .{
                .operation = .sbc,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0xFD => .{
                .operation = .sbc,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0xF9 => .{
                .operation = .sbc,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0xE1 => .{
                .operation = .sbc,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0xF1 => .{
                .operation = .sbc,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 5,
                .page_cycle_penalty = true,
            },

            // ===== logic =====
            // AND
            0x29 => .{
                .operation = .and_,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0x25 => .{
                .operation = .and_,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x35 => .{
                .operation = .and_,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0x2D => .{
                .operation = .and_,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0x3D => .{
                .operation = .and_,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x39 => .{
                .operation = .and_,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x21 => .{
                .operation = .and_,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0x31 => .{
                .operation = .and_,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 5,
                .page_cycle_penalty = true,
            },
            // ORA
            0x09 => .{
                .operation = .ora,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0x05 => .{
                .operation = .ora,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x15 => .{
                .operation = .ora,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0x0D => .{
                .operation = .ora,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0x1D => .{
                .operation = .ora,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x19 => .{
                .operation = .ora,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x01 => .{
                .operation = .ora,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0x11 => .{
                .operation = .ora,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 5,
                .page_cycle_penalty = true,
            },
            // EOR
            0x49 => .{
                .operation = .eor,
                .mode = .immediate,
                .bytes = 2,
                .cycles = 2,
            },
            0x45 => .{
                .operation = .eor,
                .mode = .zeropage,
                .bytes = 2,
                .cycles = 3,
            },
            0x55 => .{
                .operation = .eor,
                .mode = .zeropage_x,
                .bytes = 2,
                .cycles = 4,
            },
            0x4D => .{
                .operation = .eor,
                .mode = .absolute,
                .bytes = 3,
                .cycles = 4,
            },
            0x5D => .{
                .operation = .eor,
                .mode = .absolute_x,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x59 => .{
                .operation = .eor,
                .mode = .absolute_y,
                .bytes = 3,
                .cycles = 4,
                .page_cycle_penalty = true,
            },
            0x41 => .{
                .operation = .eor,
                .mode = .indexed_indirect,
                .bytes = 2,
                .cycles = 6,
            },
            0x51 => .{
                .operation = .eor,
                .mode = .indirect_indexed,
                .bytes = 2,
                .cycles = 5,
                .page_cycle_penalty = true,
            },
            else => error.UnknownOperation,
        };
    }
    // -------- OPCODE TABLE --------

    // ======== Resolve addressing mode ========
    pub fn resolveAddrMode(self: *CPU, mode: AddressingMode) AddressResult {
        return switch (mode) {
            .accumulator => .{ .addr = 0 },
            .implied => .{ .addr = 0 },

            .immediate => blk: {
                const final_addr = self.pc;
                self.pc += 1;
                break :blk .{ .addr = final_addr };
            },

            .absolute => blk: {
                const final_addr = self.fetchWord();
                break :blk .{ .addr = final_addr };
            },

            .absolute_x => blk: {
                const base_addr = self.fetchWord();
                const final_addr = base_addr +% @as(u16, self.x);
                // check page crossed
                const pagecros: bool = (base_addr & 0xFF00) != (final_addr & 0xFF00);

                break :blk .{
                    .addr = final_addr,
                    .page_crossed = pagecros,
                };
            },

            .absolute_y => blk: {
                const base_addr = self.fetchWord();
                const final_addr = base_addr +% @as(u16, self.y);
                // check page crossed
                const pagecros: bool = (base_addr & 0xFF00) != (final_addr & 0xFF00);

                break :blk .{
                    .addr = final_addr,
                    .page_crossed = pagecros,
                };
            },

            .zeropage => .{ .addr = @as(u16, self.fetchByte()) },
            .zeropage_x => .{ .addr = @as(u16, self.fetchByte() +% self.x) },
            .zeropage_y => .{ .addr = @as(u16, self.fetchByte() +% self.y) },

            .indexed_indirect => blk: {
                const base_addr = self.fetchByte() +% self.x;
                const indirect_low = self.bus.read(base_addr);
                const indirect_high = self.bus.read(base_addr +% 1);
                const final_addr = readU16LE(indirect_low, indirect_high);
                break :blk .{ .addr = final_addr };
            },

            .indirect_indexed => blk: {
                const base_addr = self.fetchByte();
                const indirect_low = self.bus.read(base_addr);
                const indirect_high = self.bus.read(base_addr +% 1);
                const final_addr_before = readU16LE(indirect_low, indirect_high);
                const final_addr = final_addr_before +% @as(u16, self.y);
                // check page crossed
                const pagecros: bool = (final_addr_before & 0xFF00) != (final_addr & 0xFF00);

                break :blk .{
                    .addr = final_addr,
                    .page_crossed = pagecros,
                };
            },

            // 特殊控制流
            .indirect => blk: {
                const base_addr = self.fetchWord();
                const indirect_low = self.bus.read(base_addr);
                // 6502经典bug。JMP跳转时，低位为0x02FF时，+1 后等于 0x0200
                const indirect_high = if (base_addr & 0x00FF == 0x00FF)
                    self.bus.read(base_addr & 0xFF00)
                else
                    self.bus.read(base_addr + 1);

                const final_addr = readU16LE(indirect_low, indirect_high);
                break :blk .{ .addr = final_addr };
            },

            .relative => blk: {
                const raw_offset = self.fetchByte();
                const offset: i8 = @bitCast(raw_offset);
                const offset_u16: u16 = @bitCast(@as(i16, offset));
                const final_addr_before = self.pc;
                const final_addr = final_addr_before +% offset_u16;
                // check page crossed
                const pagecros = (final_addr_before & 0xFF00) != (final_addr & 0xFF00);

                break :blk .{
                    .addr = final_addr,
                    .page_crossed = pagecros,
                };
            },
        };
    }

    // -------- Resolve addressing mode --------

    // ======== OPCODE EXCUTION ========
    pub fn execute(self: *CPU, ins: Instruction) void {
        const addr_res = self.resolveAddrMode(ins.mode);
        switch (ins.operation) {
            .sei => {
                self.setFlag(Flags.InterruptDisable, true);
            },
            .cld => {
                self.setFlag(Flags.Decimal, false);
            },

            // load
            .lda => {
                const value = self.bus.read(addr_res.addr);
                self.a = value;
                self.setFlagZN(self.a);
            },
            .ldx => {
                const value = self.bus.read(addr_res.addr);
                self.x = value;
                self.setFlagZN(self.x);
            },
            .ldy => {
                const value = self.bus.read(addr_res.addr);
                self.y = value;
                self.setFlagZN(self.y);
            },

            // store
            .sta => {
                const value = self.a;
                self.bus.write(addr_res.addr, value);
            },
            .stx => {
                const value = self.x;
                self.bus.write(addr_res.addr, value);
            },
            .sty => {
                const value = self.y;
                self.bus.write(addr_res.addr, value);
            },

            // register
            .tax => {
                self.x = self.a;
                self.setFlagZN(self.x);
            },
            .tay => {
                self.y = self.a;
                self.setFlagZN(self.y);
            },
            .txa => {
                self.a = self.x;
                self.setFlagZN(self.a);
            },
            .tya => {
                self.a = self.y;
                self.setFlagZN(self.a);
            },
            .tsx => {
                self.x = self.sp;
                self.setFlagZN(self.x);
            },
            .txs => {
                self.sp = self.x;
            },

            // stack
            .pha => self.pushStack(self.a),
            .pla => {
                self.a = self.popStack();
                self.setFlagZN(self.a);
            },
            .php => self.pushStack(self.status | Flags.Break | Flags.Unused), // important!! B,U 为 1
            .plp => {
                self.status = (self.popStack() & ~Flags.Break) | Flags.Unused; // B 为 0，U 为 1
            },

            // arithmetic
            .adc => {
                const value = self.bus.read(addr_res.addr);
                const a_before = self.a;
                const c_in = if (self.getFlag(Flags.Carry)) 1 else 0;
                const pre_result = @as(u16, a_before) + @as(u16, value) + c_in;

                self.setFlag(Flags.Carry, pre_result > 0xFF);

                self.a = @truncate(pre_result & 0xFF);
                self.setAdcOverflow(a_before, value, self.a);
                self.setFlag(Flags.Zero, self.a == 0);
                self.setFlag(Flags.Negative, self.a & 0x80 != 0);
            },
            .sbc => {
                const a_before = self.a;
                const value = self.bus.read(addr_res.addr);
                const invert_value = ~value; // 取反，再 + C 组成补码
                const c_in = if (self.getFlag(Flags.Carry)) 1 else 0;
                const pre_result = @as(u16, a_before) + @as(u16, invert_value) + c_in;

                self.setFlag(Flags.Carry, pre_result > 0xFF);

                self.a = @truncate(pre_result & 0xFF);
                self.setSbcOverflow(a_before, value, self.a);
                self.setFlag(Flags.Zero, self.a == 0);
                self.setFlag(Flags.Negative, self.a & 0x80 != 0);
            },

            // logic
            .and_ => {
                self.a &= self.bus.read(addr_res.addr);
                self.setFlagZN(self.a);
            },
            .ora => {
                self.a |= self.bus.read(addr_res.addr);
                self.setFlagZN(self.a);
            },
            .eor => {
                self.a ^= self.bus.read(addr_res.addr);
                self.setFlagZN(self.a);
            },
        }
        self.cycles += ins.cycles;
        if (ins.page_cycle_penalty and addr_res.page_crossed)
            self.cycles += 1;
    }
    // -------- OPCODE EXCUTION --------
};

pub fn readU16LE(low: u8, high: u8) u16 {
    const temp: u16 = (@as(u16, high) << 8) | (@as(u16, low));
    return temp;
}
