const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("./value.zig").Value;
const ValueType = @import("./value.zig").ValueType;
const printValue = @import("value.zig").printValue;
const OpCode = @import("chunk.zig").OpCode;
const Allocator = std.mem.Allocator;
const disassembleInstruction = @import("./debugging.zig").disassembleInstruction;
const printStack = @import("debugging.zig").printStack;
const compile = @import("./compiler.zig").compile;
const DEBUG_TRACE_EXECUTION = true;
const STACK_MAX = 256;

pub const InterpretErr = error{
    interpret_compile_error,
    interpret_runtime_error,
};

pub const InterpretResult = enum(u8) {
    const Self = @This();

    interpret_ok,
};

pub const Vm = struct {
    const Self = @This();

    chunk: *Chunk,
    ip: usize = 0,
    stack: [STACK_MAX]Value = undefined,
    stack_top: usize = 0,
    allocator: *Allocator,

    pub fn test_init(allocator: *Allocator, chunk: *Chunk) Self {
        var vm = Self{ .chunk = chunk, .ip = 0, .stack_top = 0, .allocator = allocator };
        vm.reset_stack();

        return vm;
    }

    pub fn init(allocator: *Allocator) Self {
        return Self{ .ip = 0, .chunk = undefined, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn test_interpret(self: *Self, chunk: *Chunk) InterpretErr!void {
        self.chunk = chunk;
        self.ip = 0;
        self.run();
    }

    pub fn interpret(self: *Self, source: []const u8) InterpretErr!void {
        //self.chunk = chunk;

        var chunk = Chunk.init(self.allocator);
        defer chunk.deinit();

        compile(source, &chunk) catch return InterpretErr.interpret_compile_error;

        self.ip = 0;
        self.chunk = &chunk;
        return self.run();
    }

    pub fn run(self: *Self) InterpretErr!void {
        while (true) {
            if (comptime DEBUG_TRACE_EXECUTION) {
                //printStack(&self.stack);
                _ = disassembleInstruction(self.chunk, self.ip);
            }

            const instruction = self.read_instruction();
            switch (instruction) {
                .op_return => {
                    std.debug.print("RETURNED \n", .{});
                    return;
                },
                .op_constant => {
                    const constant: Value = self.read_constant();
                    std.debug.print("Added Value: ", .{});
                    printValue(constant);
                    self.push(constant);
                },
                .op_constant_long => {
                    const constant: Value = self.read_constant();
                    self.push(constant);
                },
                .op_nil => self.push(Value.NilValue()),
                .op_true => self.push(Value.BooleanValue(true)),
                .op_false => self.push(Value.BooleanValue(false)),
                .op_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.BooleanValue(b.equals(a)));
                },
                .op_greater => self.binaryOp(instruction),
                .op_less => self.binaryOp(instruction),
                .op_not => {
                    self.push(Value.BooleanValue(isFalsey(self.pop())));
                },
                .op_negate => {
                    const val = self.pop();

                    switch (val) {
                        .number => |value| {
                            const negatedValue = Value.NumberValue(-value);
                            self.push(negatedValue);
                            std.debug.print("Pushed negated value: {}\n", .{negatedValue});
                        },
                        else => return self.runtimeErr("Operand Must Be A Number"),
                    }
                },
                .op_add => {
                    self.binaryOp(instruction);
                },
                .op_subtract => {
                    self.binaryOp(instruction);
                },
                .op_mult => {
                    self.binaryOp(instruction);
                },
                .op_divide => {
                    self.binaryOp(instruction);
                },
            }
        }
    }

    //just read_byte but with u8 -> opcode zig translation
    inline fn read_instruction(self: *Self) OpCode {
        return OpCode.fromU8(self.read_byte());
    }

    inline fn read_byte(self: *Self) u8 {
        const byte = self.chunk.code.items[self.ip];
        self.ip += 1;
        return byte;
    }

    inline fn read_constant(self: *Self) Value {
        const idx = self.read_byte();
        return self.chunk.constants.items[idx];
    }

    inline fn reset_stack(self: *Self) void {
        self.stack_top = 0;
    }

    pub inline fn push(self: *Self, value: Value) void {
        self.stack[self.stack_top] = value; // Store the value at the current top of the stack
        self.stack_top += 1; // Increment stack_top to point to the next available position
    }

    pub inline fn peek(self: *Self) Value {
        return self.stack[self.stack_top - 1];
    }

    //returns the item at the index, if negative it traces back from the top
    pub inline fn peekAt(self: *Self, idx: isize) Value {
        if (idx < 0) {
            return self.stack[self.stack_top - 1 + (idx)];
        }
        return self.stack[idx];
    }

    pub inline fn binaryOp(self: *Self, op: OpCode) InterpretErr!void {
        std.debug.print("In Binary Op Func\n", .{});
        if (self.peek().isNaN() and self.peekAt(-1).isNaN()) {
            return self.runtimeErr("Operands Must Be Numbers");
        }
        //else
        const b = self.pop().number;
        std.debug.print("b is: {d}\n", .{b});

        const a = self.pop().number;
        std.debug.print("a is: {d}\n", .{a});

        switch (op) {
            .op_add => self.push(Value.NumberValue(a + b)),
            .op_mult => self.push(Value.NumberValue(a * b)),
            .op_divide => self.push(Value.NumberValue(a / b)),
            .op_subtract => self.push(Value.NumberValue(a - b)),
            .op_greater => self.push(Value.BooleanValue(a > b)),
            .op_less => self.push(Value.BooleanValue(a < b)),
            else => {
                return InterpretErr.interpret_runtime_error;
            }, // bettter messages later
        }
    }
    pub inline fn pop(self: *Self) Value {
        // stack_top always points to the next value, so the last value is one index behind.
        // stack = [1, 2, 3, 4, null...]
        // stack_top would point to the position after the last element, so decrementing stack_top
        // gives the actual last element, which is returned.

        self.stack_top -= 1; // Decrement stack_top to point to the last pushed value
        return self.stack[self.stack_top]; // Return the value at the new stack_top position
    }

    //_______________ ERR ______________ //
    inline fn runtimeErr(self: *Self, msg: []const u8) InterpretErr {
        const err_writer = std.io.getStdErr().writer();

        err_writer.print("{s}.\n", .{msg}) catch {};

        const instruction = self.ip - 1;
        const line = self.chunk.lines.items[instruction];

        err_writer.print("[line {d}] in ", .{line}) catch {};

        self.reset_stack();
        return InterpretErr.interpret_runtime_error;
    }

    pub fn isFalsey(value: Value) bool {
        return switch (value) {
            .nil => true,
            .boolean => |val| !val,
            else => false,
        };
    }
};
