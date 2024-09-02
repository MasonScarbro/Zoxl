const std = @import("std");

pub const ValueType = enum {
    number,
};

pub const Value = union(ValueType) {
    const Self = @This();

    number: f64,

    pub inline fn NumberValue(val: f64) Self {
        return Value{ .number = val };
    }
};

pub fn printValue(value: Value) void {
    const stdout = std.io.getStdOut().writer();
    switch (value) {
        .number => stdout.print("{d}\n", .{value}),
    }
}
