const std = @import("std");
const Value = @import("./value.zig").Value;
const memutils = @import("./utils.mem.zig");
const Vm = @import("./vm.zig").Vm;
const Allocator = std.mem.Allocator;
const Chunk = @import("./chunk.zig").Chunk;

pub const ObjectType = enum {
    STRING,
    FUNCTION,
    NATIVE_FUNC,
};

pub const Object = struct {
    objType: ObjectType,
    next: ?*Object,

    pub fn create(vm: *Vm, comptime T: type, objectType: ObjectType) *T {
        // Allocate memory for type T using the allocator
        const object = vm.allocator.create(T) catch @panic("err creating Obj\n");
        object.obj = Object{ .objType = objectType, .next = vm.objects }; // Initialize the Object part
        vm.objects = &object.obj;
        return object;
    }

    pub fn freeObject(self: *Object, vm: *Vm) void {
        //std.debug.print("Inside freeObject\n", .{});
        switch (self.objType) {
            .STRING => self.asString().free(vm),
            .FUNCTION => self.asFunction().free(vm),
            .NATIVE_FUNC => self.asNativeFunc().free(vm),
        }
    }

    pub inline fn asString(self: *Object) *StringObj {
        return @fieldParentPtr("obj", self);
    }

    pub inline fn asFunction(self: *Object) *FuncObj {
        return @fieldParentPtr("obj", self);
    }

    pub inline fn asNativeFunc(self: *Object) *NativeFunc {
        return @fieldParentPtr("obj", self);
    }

    pub inline fn isA(value: Value, objType: ObjectType) bool {
        return value == .obj and value.obj.objType == objType;
    }

    pub inline fn printObj(self: *Object) void {
        switch (self.objType) {
            .STRING => self.asString().printSelf(),
            .FUNCTION => self.asFunction().printSelf(),
            .NATIVE_FUNC => self.asNativeFunc().printSelf(),
        }
    }
};

//-------------- OBJECT TYPES ---------------//
pub const StringObj = struct {
    //pub usingnamespace Object;
    obj: Object,
    len: usize,
    chars: []const u8,
    hash: u64,

    pub fn tag() ObjectType {
        return .STRING;
    }

    pub fn free(self: *StringObj, vm: *Vm) void {
        if (self.chars.len > 0) {
            //std.debug.print("Trying to free {s}\n", .{self.chars});
            vm.allocator.free(self.chars);
            //std.debug.print("Freed self.chars succesfully\n", .{});
        }

        //std.debug.print("Trying to destroy self\n", .{});
        vm.allocator.destroy(self);
        //std.debug.print("Destroyed self succesfully\n", .{});
    }

    pub fn printSelf(self: *StringObj) void {
        std.debug.print("%s", .{self.chars});
    }

    pub fn copyStr(vm: *Vm, chars: []const u8) *StringObj {
        const hash = std.hash.Wyhash.hash(0, chars);
        const interned = vm.strings.findStr(chars, hash);
        if (interned) |interneded| {
            return interneded;
        }
        const heap = vm.allocator.alloc(u8, chars.len) catch @panic("Err Copying String\n");
        @memcpy(heap, chars);

        return allocateStr(vm, heap, hash);
    }

    fn allocateStr(vm: *Vm, bytes: []const u8, hash: u64) *StringObj {
        const str = Object.create(vm, StringObj, ObjectType.STRING);
        str.chars = bytes;
        str.len = bytes.len;
        str.hash = hash;
        _ = vm.strings.set(str, Value.NilValue());
        return str;
    }

    pub fn takeStr(vm: *Vm, chars: []const u8) *StringObj {
        const hash = std.hash.Wyhash.hash(0, chars);
        const interned = vm.strings.findStr(chars, hash);
        if (interned) |interneded| {
            vm.allocator.free(chars);
            return interneded;
        }
        return allocateStr(vm, chars, hash);
    }
};

pub const FuncObj = struct {
    obj: Object,
    arity: usize,
    chunk: Chunk,
    name: ?*StringObj,

    pub fn newFunc(vm: *Vm) *FuncObj {
        std.debug.print("\nMaking object\n", .{});
        var func: *FuncObj = Object.create(vm, FuncObj, .FUNCTION);
        func.arity = 0;
        func.name = null;
        func.chunk = Chunk.init(&vm.allocator);
        return func;
    }

    pub fn free(self: *FuncObj, vm: *Vm) void {
        self.chunk.deinit();
        vm.allocator.destroy(self);
    }

    pub fn printSelf(self: *FuncObj) void {
        if (self.name.?.chars.len == 0) {
            std.debug.print("<script>", .{});
            return;
        }
        std.debug.print("<fn %s>", .{self.name.?.chars});
    }
};

pub const NativeFunc = struct {
    pub const Fn = *const fn (vm: *Vm, argCount: usize, args: Value) Value;

    obj: Object,
    function: Fn,

    pub fn newNativeFunc(vm: *Vm, function: Fn) *NativeFunc {
        var nativeFunc: *NativeFunc = Object.create(vm, NativeFunc, .NATIVE_FUNC);
        nativeFunc.function = function;
        return nativeFunc;
    }

    pub fn free(self: *NativeFunc, vm: *Vm) void {
        vm.allocator.destroy(self);
    }

    pub fn printSelf(self: *NativeFunc) void {
        _ = self;
        std.debug.print("<native fn>", .{});
    }
};

fn hashBytes(bytes: []const u8) u32 {
    var hash: u32 = 2166136261;

    for (bytes) |byte| {
        hash ^= byte;
        _ = @mulWithOverflow(hash, 16777619);
    }

    return hash;
}
