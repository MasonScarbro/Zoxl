const std = @import("std");
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;

pub fn ValuesList(comptime T: type) type {
    return struct {
        const Self = @This();
        count: usize,
        capacity: usize,
        items: []Value,
        allocator: *Allocator,

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .count = 0,
                .capacity = 0,
                .items = &[_]Value{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.capacity == 0) return;
            self.allocator.free(self.items);
            self.* = Self.init(self.allocator);
        }

        pub fn appendValue(self: *Self, item: T) void {
            if (self.capacity < self.count + 1) {
                self.capacity = growCapacity(self.capacity);
                self.items = self.allocator.realloc(self.items, self.capacity) catch @panic("Error reallocating memory");
            }
            self.items[self.count] = item;
            self.count += 1;
        }
    };
}

pub fn growCapacity(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * 2;
}
