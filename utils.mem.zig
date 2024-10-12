const std = @import("std");
const Allocator = std.mem.Allocator;
var global_allocator = std.mem.Allocator;
// Function to set the global allocator if needed
pub fn setGlobalAllocator(allocator: *Allocator) void {
    global_allocator = allocator;
}

pub fn get_global_allocator() Allocator {
    if (global_allocator == null) {
        @panic("Global allocator is not set");
    }
    return global_allocator;
}
// Function to allocate memory using the global allocator
pub fn alloc(size: usize) !*u8 {
    return global_allocator.alloc(u8, size);
}

// Function to free memory using the global allocator
pub fn free(ptr: *u8) void {
    global_allocator.free(ptr); // Adjust size handling if needed
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
