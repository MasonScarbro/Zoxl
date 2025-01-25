const std = @import("std");
const Value = @import("./value.zig").Value;
const memutils = @import("./utils.mem.zig");
const Vm = @import("./vm.zig").Vm;
const Allocator = std.mem.Allocator;

pub const ObjectType = enum {
    STRING,
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
        }
    }

    pub inline fn asString(self: *Object) *StringObj {
        return @fieldParentPtr("obj", self);
    }

    pub inline fn isA(value: Value, objType: ObjectType) bool {
        return value == .obj and value.obj.objType == objType;
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

fn hashBytes(bytes: []const u8) u32 {
    var hash: u32 = 2166136261;

    for (bytes) |byte| {
        hash ^= byte;
        _ = @mulWithOverflow(hash, 16777619);
    }

    return hash;
}
