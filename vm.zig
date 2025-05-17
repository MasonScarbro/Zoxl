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
const GC = @import("./garbage_collection.zig").GarbageCollector;

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
    closure: *Object.ClosureObj,
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
    openUpvalues: ?*Object.UpValueObj = null,
    bytesAllocated: usize = 0,
    nextGC: usize = 1024 * 1204,
    collector: ?*GC = null,

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
        //self.collector.?.collectGarbage(); here?
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

        const closure = Object.ClosureObj.newClosure(self, function);
        _ = self.pop();
        self.push(Value.ObjectValue(&closure.obj));

        _ = self.call(closure, 0); // 'main' function everything is wrapped in
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
                    const slots = frame.slots;
                    self.frameCount -= 1;
                    if (self.frameCount == 0) {
                        _ = self.pop();
                        return;
                    }
                    std.debug.print("stack_top: {}\nslots: {}\n", .{ self.stack_top, self.currentFrame().slots });

                    self.stack_top = slots;
                    self.push(result);
                },
                .op_class => {
                    const name = self.read_constant().obj.asString();
                    const class = Object.ClassObj.newClass(self, name);
                    self.push(Value.ObjectValue(&class.obj));
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
                .op_closure => {
                    const func = self.read_constant().obj.asFunction();
                    const closure = Object.ClosureObj.newClosure(self, func);
                    self.push(Value.ObjectValue(&closure.obj));
                    for (0..closure.upvalueCount) |i| {
                        const isLocal = self.read_byte() == 1;
                        const index = self.read_byte();
                        if (isLocal) {
                            closure.upvalues[i] = self.captureUpvalue(&self.stack[self.currentFrame().slots + index]);
                        } else {
                            closure.upvalues[i] = self.currentFrame().closure.upvalues[index];
                        }
                    }
                },
                .op_close_upvalue => {
                    self.closeUpvalue(&self.stack[self.stack_top - 1]);
                    _ = self.pop();
                },
                .op_get_upvalue => {
                    std.debug.print("In OP_GET_UPVALUE", .{});
                    const slot = self.read_byte();
                    self.push(self.currentFrame().closure.upvalues[slot].location.*);
                },
                .op_set_upvalue => {
                    const slot = self.read_byte();
                    self.currentFrame().closure.upvalues[slot].location.* = self.peek();
                },
                .op_get_property => {
                    var val = self.peek();
                    if (val.isObjType(.INSTANCE)) {
                        const instance = val.obj.asInstance();
                        const name = self.read_constant().obj.asString();

                        if (instance.fields.get(name)) |value| {
                            _ = self.pop(); // pop the instance
                            self.push(value.*);
                        } else {
                            _ = self.runtimeErrW("Undefined property '{s}'", .{name.chars}) catch {};
                            return InterpretErr.interpret_runtime_error;
                        }
                    } else {
                        return self.runtimeErr("Only an Instance can have properties and it thins its a get???");
                    }
                },
                .op_set_property => {
                    var val = self.peekBack(1);
                    std.debug.print("In OP_SET_PROPERTY\n", .{});
                    std.debug.print("val is: {}\n", .{val});
                    std.debug.print("val type is: {}\n", .{val.obj.objType});
                    if (val.isObjType(.INSTANCE)) {
                        const instance = val.obj.asInstance();
                        const name = self.read_constant().obj.asString();
                        _ = instance.fields.set(name, self.peek());
                        const value = self.pop(); // pop the instance
                        _ = self.pop(); // pop the value
                        self.push(value);
                    } else {
                        return self.runtimeErr("Only an Instance can have properties");
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
                    const slot = self.read_byte();
                    self.push(self.stack[self.currentFrame().slots + slot]);
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

    inline fn closeUpvalue(self: *Self, last: *Value) void {
        while (self.openUpvalues) |openUpvalues| {
            if (@intFromPtr(openUpvalues.location) < @intFromPtr(last)) break;
            const upvalue = openUpvalues;
            upvalue.closed = upvalue.location.*;
            upvalue.location = &upvalue.closed;
            self.openUpvalues = upvalue.next;
        }
    }

    inline fn captureUpvalue(self: *Self, local: *Value) *Object.UpValueObj {
        var prevUpvalue: ?*Object.UpValueObj = null;
        var maybeUpvalue = self.openUpvalues;

        while (maybeUpvalue) |upvalue| {
            if (@intFromPtr(upvalue.location) <= @intFromPtr(local)) break;
            prevUpvalue = upvalue;
            maybeUpvalue = upvalue.next;
        }

        if (maybeUpvalue) |upvalue| {
            if (upvalue.location == local) return upvalue;
        }
        const created = Object.UpValueObj.newUpValue(self, local.*);
        created.next = maybeUpvalue;

        if (prevUpvalue == null) {
            self.openUpvalues = created;
        } else {
            prevUpvalue.?.next = created;
        }
        return created;
    }

    inline fn currentFrame(self: *Self) *CallFrame {
        return &self.frames[self.frameCount - 1];
    }

    inline fn currentChunk(self: *Self) *Chunk {
        return &self.currentFrame().closure.func.chunk;
    }

    inline fn call(self: *Self, closure: *Object.ClosureObj, argCount: u8) bool {
        std.debug.print("INSIDE CALL", .{});
        if (closure.func.arity != argCount) {
            _ = self.runtimeErrW("Expected {d} arguments but got {d}", .{ closure.func.arity, argCount }) catch {};
            return false;
        }

        var frame = &self.frames[self.frameCount];
        self.frameCount += 1;

        frame.closure = closure;
        frame.ip = 0;
        frame.slots = self.stack_top - argCount - 1; // Reserve the first slot for the function object
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
        self.frameCount = 0;
        self.openUpvalues = null;
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
        //std.debug.print("\nCALLEE is OBJECT {b}", .{Value.isObj()});
        switch (callee) {
            .obj => |obj| {
                switch (obj.objType) {
                    .CLOSURE => {
                        return self.call(obj.asClosure(), argc);
                    },
                    .CLASS => {
                        std.debug.print("Inside call value making a new class instancce\n", .{});
                        const class = obj.asClass();
                        const instance = Object.InstanceObj.newInstance(self, class);
                        self.stack[self.stack_top - argc - 1] = Value.ObjectValue(&instance.obj);
                        std.debug.print("ok top of the stack should have that instance  {}", .{self.peek().obj.objType});
                        return true;
                    },
                    .NATIVE_FUNC => {
                        const args = self.stack[self.stack_top - argc - 1]; // retrieves the arguments from the stack
                        const result = callee.obj.asNativeFunc().function(self, argc, args); // call the zig function
                        self.stack_top -= argc + 1; //Stack Cleanup:  removes: All the arguments (argc), The function object itself (+ 1)
                        self.push(result);
                        return true;
                    },
                    else => {
                        _ = self.runtimeErr("Can only call functions and classes this was a") catch {};
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
            const function = frame.closure.func;
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
            const function = frame.closure.func;
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
