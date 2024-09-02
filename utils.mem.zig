const std = @import("std");

pub fn growCapacity(capacity: usize) usize {
    return if (capacity < 8) 8 else capacity * 2;
}

pub fn growArray(
    allocator: *std.mem.Allocator,
    code: []u8,
    oldCapacity: usize,
) ![]u8 {
    const newCapacity = growCapacity(oldCapacity);
    return try allocator.realloc(u8, code, oldCapacity, newCapacity);
}

pub fn reallocate(allocator: *std.mem.Allocator, pointer: ?[]u8, oldSize: usize, newSize: usize) !?[]u8 {
    if (newSize == 0) {
        if (pointer) |ptr| {
            allocator.free(ptr);
        }
        return null;
    }

    if (pointer) |ptr| {
        return try allocator.realloc(u8, ptr, oldSize, newSize);
    } else {
        return try allocator.alloc(u8, newSize);
    }
}

pub fn freeArray(allocator: *std.mem.Allocator, pointer: []u8, oldCount: usize) !void {
    _ = try reallocate(allocator, pointer, oldCount, 0);
}
