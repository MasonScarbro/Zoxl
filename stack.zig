// FOR LATER USE NOT WORKING RIGHT NOW???

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

pub const Stack = struct {
    const Self = @This();
    values: []Value = undefined,
    stack_top: usize = 0,
    capacity: usize = 0,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator, initial_capacity: usize) Self {
        return Self{
            .allocator = allocator,
            .stack_top = 0,
            .values = try allocator.alloc(Value, initial_capacity),
            .capacity = initial_capacity,
        };
    }

    pub fn reset(self: *Self) void {
        self.stack_top = 0;
    }

    pub inline fn push(self: *Self, value: Value) void {
        if (self.capacity < self.stack_top + 1) {
            const oldcap = self.capacity;
            self.capacity = growCapacity(oldcap);
            self.values = self.allocator.realloc(self.values, self.capacity) catch @panic("Error allocating new memory");
        }
        self.values[self.stack_top] = value; // Store the value at the current top of the stack
        self.stack_top += 1; // Increment stack_top to point to the next available position
    }

    pub inline fn peek(self: *Self) Value {
        return self.values[self.stack_top - 1];
    }

    //returns the item at the index, if negative it traces back from the top
    pub inline fn peekAt(self: *Self, idx: isize) Value {
        if (idx < 0) {
            return self.values[self.stack_top - 1 + (idx)];
        }
        return self.values[idx];
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.values);
    }

    pub inline fn pop(self: *Self) Value {
        // stack_top always points to the next value, so the last value is one index behind.
        // stack = [1, 2, 3, 4, null...]
        // stack_top would point to the position after the last element, so decrementing stack_top
        // gives the actual last element, which is returned.

        self.stack_top -= 1; // Decrement stack_top to point to the last pushed value
        return self.values[self.stack_top]; // Return the value at the new stack_top position
    }

    pub fn size(self: *Self) usize {
        return self.stack_top; // Return the current size of the stack
    }
};

pub fn growCapacity(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * 2;
}
