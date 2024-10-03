const std = @import("std");

pub const ValueType = enum {
    nil,
    boolean,
    number,
};

pub const Value = union(ValueType) {
    const Self = @This();

    number: f64,
    boolean: bool,
    nil: null,

    pub inline fn NumberValue(val: f64) Self {
        return Value{ .number = val };
    }

    pub inline fn BooleanValue(val: bool) Self {
        return Value{ .boolean = val };
    }

    pub inline fn NilValue() Self {
        return Value{ .nil = null };
    }

    pub inline fn isBool(self: Self) bool {
        return @as(ValueType, self) == ValueType.boolean;
    }

    pub inline fn isNil(self: Self) bool {
        return @as(ValueType, self) == ValueType.nil;
    }

    pub inline fn equals(self: Self, second: Value) bool {
        switch (self) {
            .nil => return second == .nil,
            .boolean => return (second == .boolean and self.boolean == second.boolean),
            .number => return (second == .number and self.number == second.number),
            else => return false,
        }
    }

    pub inline fn isNaN(self: Self) bool {
        return @as(ValueType, self) != ValueType.number;
    }
};

pub fn printValue(value: Value) void {
    const stdout = std.io.getStdOut().writer();

    const msg = "Panic while printing value printOperation\n ";
    switch (value) {
        .number => stdout.print("{d}\n", .{value.number}) catch @panic(msg),
        .boolean => stdout.print("{}\n", .{value.boolean}),
        .nil => stdout.print("nil\n", .{}),
    }
}
