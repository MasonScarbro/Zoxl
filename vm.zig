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
const Object = @import("./object.zig");
const DEBUG_TRACE_EXECUTION = false;
const HashTable = @import("./hashTable.zig").HashTable;
const nativeFuncs = @import("./nativeFuncs.zig");

const STACK_MAX = 256;
const FRAMES_MAX = 64;

pub const InterpretErr = error{
    interpret_compile_error,
    interpret_runtime_error,
};

pub const InterpretResult = enum(u8) {
    const Self = @This();

    interpret_ok,
};

// each time a function is called we create this:
pub const CallFrame = struct {
    func: *Object.FuncObj,
    ip: usize = 0, // ip of the call
    slots: usize = 0,
};

pub const Vm = struct {
    const Self = @This();

    frames: [FRAMES_MAX]CallFrame = undefined,
    frameCount: usize = 0,
    stack: [STACK_MAX]Value = undefined,
    stack_top: usize = 0,
    objects: ?*Object.Object = null,
    allocator: Allocator,
    strings: HashTable,
    globals: HashTable,

    pub fn test_init(allocator: Allocator, chunk: *Chunk) Self {
        var vm = Self{ .chunk = chunk, .ip = 0, .stack_top = 0, .allocator = allocator };
        vm.reset_stack();

        return vm;
    }

    pub fn init(allocator: Allocator) Self {
        var vm = Self{ .allocator = allocator, .strings = HashTable.init(allocator), .globals = HashTable.init(allocator) };
        vm.defineNative("clock", nativeFuncs.clockNative);
        return vm;
    }

    pub fn deinit(self: *Self) void {
        self.freeObjects();
        self.strings.deinit();
        self.globals.deinit();
    }

    pub inline fn freeObjects(self: *Self) void {
        var object = self.objects;

        while (object) |obj| {
            std.debug.print("Freeing Object... {}\n", .{obj.objType});
            const next = obj.next;
            obj.freeObject(self);
            object = next;
        }
    }

    pub fn interpret(self: *Self, source: []const u8) InterpretErr!void {
        //self.chunk = chunk;
        const function = compile(self, source, self.allocator) catch return InterpretErr.interpret_compile_error;
        self.push(Value.ObjectValue(&function.obj));

        _ = self.call(function, 0); // 'main' function everything is wrapped in
        return self.run();
    }

    pub fn run(self: *Self) InterpretErr!void {
        while (true) {
            if (comptime DEBUG_TRACE_EXECUTION) {
                //printStack(&self.stack);
                _ = disassembleInstruction(self.currentChunk(), self.currentFrame().ip);
            }

            const instruction = self.read_instruction();
            try switch (instruction) {
                .op_return => {
                    const result = self.pop();
                    const frame = self.currentFrame();
                    self.frameCount -= 1;
                    if (self.frameCount == 0) {
                        _ = self.pop();
                        return;
                    }
                    std.debug.print("stack_top: {}\nslots: {}\n", .{ self.stack_top, self.currentFrame().slots });

                    self.stack_top = frame.slots;
                    self.push(result);
                },
                .op_print => {
                    std.debug.print("\nPrinting Value:\t", .{});

                    printValue(self.pop());
                    std.debug.print("\n", .{});
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
                .op_pop => _ = self.pop(),
                .op_duplicate => self.push(self.peek()),
                .op_define_global => {
                    const val = self.read_constant();
                    if (val.isObjType(Object.ObjectType.STRING)) {
                        const name = val.obj.asString();
                        _ = self.globals.set(name, self.peek());
                        _ = self.pop();
                    } else {
                        return self.runtimeErr("FAILURE in VM Value was not and object {}\n");
                    }
                },
                .op_get_global => {
                    const val = self.read_constant();
                    if (val.isObjType(Object.ObjectType.STRING)) {
                        const name = val.obj.asString();
                        const value = self.globals.get(name) orelse {
                            return self.runtimeErrW("Undefined variable '{s}'", .{name.chars});
                        };
                        self.push(value.*);
                    } else {
                        return self.runtimeErr("FAILURE in VM Value was not and object");
                    }
                },
                .op_set_global => {
                    const val = self.read_constant();
                    if (val.isObjType(Object.ObjectType.STRING)) {
                        const name = val.obj.asString();
                        if (self.globals.set(name, self.peek())) {
                            _ = self.globals.delete(name);
                            return self.runtimeErrW("Undefined variable '{s}'", .{name.chars});
                        }
                        //self.push(value.*);
                    } else {
                        return self.runtimeErr("FAILURE in VM Value was not and object");
                    }
                },
                .op_set_local => {
                    std.debug.print("Inside VM op_set_local", .{});
                    const slot = self.read_instruction().toU8();
                    self.stack[self.currentFrame().slots + slot] = self.peek();
                },
                .op_get_local => {
                    std.debug.print("Inside VM op_get_local", .{});
                    const slot = self.read_instruction().toU8();
                    self.push(self.stack[self.currentFrame().slots + slot + 1]);
                },
                .op_equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.BooleanValue(b.equals(a)));
                },
                .op_jump_if_false => {
                    const offset = self.read_twoBytes();
                    if (isFalsey(self.peek())) self.currentFrame().ip += offset;
                },
                .op_jump => {
                    const offset = self.read_twoBytes();
                    self.currentFrame().ip += offset;
                },
                .op_loop => {
                    const offset = self.read_twoBytes();
                    self.currentFrame().ip -= offset; //jump back the 16 bytes ('-' instead of '+')
                },
                .op_call => {
                    const argCount = self.read_byte();
                    if (!self.callValue(self.peekBack(argCount), argCount)) {
                        return InterpretErr.interpret_runtime_error;
                    }
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
                    self.binaryOp(instruction) catch return InterpretErr.interpret_runtime_error;
                },
                .op_subtract => {
                    self.binaryOp(instruction) catch return InterpretErr.interpret_runtime_error;
                },
                .op_mult => {
                    self.binaryOp(instruction) catch return InterpretErr.interpret_runtime_error;
                },
                .op_divide => {
                    self.binaryOp(instruction) catch return InterpretErr.interpret_runtime_error;
                },
            };
        }
    }

    inline fn currentFrame(self: *Self) *CallFrame {
        return &self.frames[self.frameCount - 1];
    }

    inline fn currentChunk(self: *Self) *Chunk {
        return &self.currentFrame().func.chunk;
    }

    inline fn call(self: *Self, func: *Object.FuncObj, argCount: u8) bool {
        std.debug.print("INSIDE CALL", .{});
        if (func.arity != argCount) {
            _ = self.runtimeErrW("Expected {d} arguments but got {d}", .{ func.arity, argCount }) catch {};
            return false;
        }

        var frame = &self.frames[self.frameCount];
        self.frameCount += 1;

        frame.func = func;
        frame.ip = 0;
        frame.slots = self.stack_top - argCount - 1; // - 1 is to account for stack slot zero which the compiler set aside
        return true;
    }

    //just read_byte but with u8 -> opcode zig translation
    inline fn read_instruction(self: *Self) OpCode {
        return OpCode.fromU8(self.read_byte());
    }

    inline fn read_byte(self: *Self) u8 {
        const byte = self.currentChunk().code.items[self.currentFrame().ip];
        self.currentFrame().ip += 1;
        return byte;
    }

    inline fn read_twoBytes(self: *Self) u16 {
        const b1 = self.read_byte();
        const b2 = self.read_byte();
        return (@as(u16, @intCast(b1)) << 8 | @as(u16, @intCast(b2)));
    }

    inline fn read_constant(self: *Self) Value {
        const idx = self.read_byte();
        return self.currentChunk().constants.items[idx];
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

    fn peekBack(self: *Self, back: usize) Value {
        return self.stack[self.stack_top - 1 - back];
    }

    pub inline fn binaryOp(self: *Self, op: OpCode) InterpretErr!void {
        std.debug.print("In Binary Op Func\n", .{});
        if (self.peek().isObjType(.STRING) and self.peekBack(1).isObjType(.STRING)) {
            self.concate();
            return;
        }
        if (self.peek().isNaN() and self.peekBack(1).isNaN()) {
            return self.runtimeErr("Operands Must Be Numbers");
        }
        //else
        const b = self.pop().asNumber();
        std.debug.print("b is: {d}\n", .{b});
        const a = self.pop().asNumber();
        std.debug.print("a is: {d}\n", .{a});
        std.debug.print("op is: {}\n", .{op});

        switch (op) {
            .op_add => {
                self.push(Value.NumberValue(a + b));
                std.debug.print("pushed value : {d} to {}\n", .{ a + b, self.stack_top - 1 });
            },
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

    pub inline fn callValue(self: *Self, callee: Value, argc: u8) bool {
        std.debug.print("CALLING values with args ", .{});
        switch (callee) {
            .obj => |obj| {
                switch (obj.objType) {
                    .FUNCTION => return self.call(obj.asFunction(), argc),
                    .NATIVE_FUNC => {
                        const args = self.stack[self.stack_top - argc - 1]; // retrieves the arguments from the stack
                        const result = callee.obj.asNativeFunc().function(self, argc, args); // call the zig function
                        self.stack_top -= argc + 1; //Stack Cleanup:  removes: All the arguments (argc), The function object itself (+ 1)
                        self.push(result);
                        return true;
                    },
                    else => {
                        _ = self.runtimeErr("Can only call functions and classes") catch {};
                        return false;
                    },
                }
            },
            else => {
                _ = self.runtimeErr("Can only call functions and classes") catch {};
                return false;
            },
        }
        _ = self.runtimeErr("Can only call functions and classes") catch {};
        return false;
    }

    pub inline fn concate(self: *Self) void {
        std.debug.print("INSIDE CONCATE\n", .{});
        const b = self.peek().obj.asString();
        const a = self.peekBack(1).obj.asString();

        const heap = std.mem.concat(self.allocator, u8, &[_][]const u8{ a.chars, b.chars }) catch unreachable;
        const obj = Object.StringObj.takeStr(self, heap);

        //std.debug.print("Concated: {s}\n", .{heap});

        _ = self.pop();
        _ = self.pop();
        self.push(Value.ObjectValue(&obj.obj));
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

        var i = self.frameCount;
        while (i > 0) {
            i -= 1;

            const frame = &self.frames[i];
            const function = frame.func;
            const instruction = frame.ip - 1;

            err_writer.print("[line {d}] in ", .{function.chunk.lines.items[instruction]}) catch {};
            const name = if (function.name) |name| name.chars else "script";
            err_writer.print("{s}\n", .{name}) catch {};
        }

        self.reset_stack();
        return InterpretErr.interpret_runtime_error;
    }

    // probably just meld this to one func
    pub inline fn runtimeErrW(self: *Self, msg: []const u8, args: anytype) InterpretErr {
        const err_writer = std.io.getStdErr().writer();

        err_writer.print(msg ++ "\n", args) catch {};

        var i = self.frameCount;
        while (i > 0) {
            i -= 1;

            const frame = &self.frames[i];
            const function = frame.func;
            const instruction = frame.ip - 1;

            err_writer.print("[line {d}] in ", .{function.chunk.lines.items[instruction]}) catch {};
            const name = if (function.name) |name| name.chars else "script";
            err_writer.print("{s}\n", .{name}) catch {};
        }

        self.reset_stack();
        return InterpretErr.interpret_runtime_error;
    }

    pub fn defineNative(self: *Self, name: []const u8, function: Object.NativeFunc.Fn) void {
        self.push(Value.ObjectValue(&Object.StringObj.copyStr(self, name).obj));
        self.push(Value.ObjectValue(&Object.NativeFunc.newNativeFunc(self, function).obj));
        _ = self.globals.set(self.stack[0].obj.asString(), self.stack[1]);
        _ = self.pop();
        _ = self.pop();
    }

    pub fn isFalsey(value: Value) bool {
        return switch (value) {
            .nil => true,
            .boolean => |val| !val,
            else => false,
        };
    }
};
