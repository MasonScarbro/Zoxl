const std = @import("std");
const Object = @import("./object.zig").Object;
const ObjectType = @import("./object.zig").ObjectType;
pub const ValueType = enum { number, boolean, nil, obj };

pub const Value = union(ValueType) {
    const Self = @This();

    number: f64,
    boolean: bool,
    nil,
    obj: *Object,

    pub inline fn NumberValue(val: f64) Self {
        return Value{ .number = val };
    }

    pub inline fn BooleanValue(val: bool) Self {
        return Value{ .boolean = val };
    }

    pub inline fn NilValue() Self {
        return Value.nil;
    }

    pub inline fn ObjectValue(val: *Object) Self {
        return Value{ .obj = val };
    }
    pub inline fn isBool(self: Self) bool {
        return @as(ValueType, self) == ValueType.boolean;
    }

    pub inline fn isObj(self: Self) bool {
        return @as(ValueType, self) == ValueType.obj;
    }

    pub inline fn asNumber(self: Self) f64 {
        return self.number;
    }

    pub inline fn isObjType(self: Self, objType: ObjectType) bool {
        if (!self.isObj()) return false;

        switch (self.obj.objType) {
            .STRING => return objType == .STRING,
            .FUNCTION => return objType == .FUNCTION,
            .NATIVE_FUNC => return objType == .NATIVE_FUNC,
            .CLOSURE => return objType == .CLOSURE,
            //else => return false,
        }
    }

    pub inline fn isNil(self: Self) bool {
        return @as(ValueType, self) == ValueType.nil;
    }

    pub inline fn equals(self: Self, second: Value) bool {
        switch (self) {
            .nil => return second == .nil,
            .boolean => return (second == .boolean and self.boolean == second.boolean),
            .number => return (second == .number and self.number == second.number),
            .obj => return second == .obj and self.obj == second.obj,
            //else => return false,
        }
    }

    pub inline fn isNaN(self: Self) bool {
        return @as(ValueType, self) != ValueType.number;
    }
};

pub fn printValue(value: Value) void {
    switch (value) {
        .number => std.debug.print("{d}\n", .{value.number}),
        .boolean => std.debug.print("{}\n", .{value.boolean}),
        .obj => |objVal| {
            switch (objVal.objType) {
                .STRING => std.debug.print("{s}\n", .{objVal.asString().chars}),
                .FUNCTION => {
                    const name = if (objVal.asFunction().name) |name| name.chars else "script";
                    std.debug.print("<fn {s}>\n", .{name});
                },
                .NATIVE_FUNC => objVal.printObj(),
                .CLOSURE => objVal.printObj(),
                //else => unreachable,
            }
        },
        .nil => std.debug.print("nil\n", .{}),
    }
}
