const std = @import("std");
const chunk = @import("chunk.zig");
const OpCode = @import("chunk.zig").OpCode;

pub fn main() !void {
    // Create a general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize a Chunk with an allocator and initial capacity
    var theChunk = chunk.init(&allocator);
    defer theChunk.deinit();

    try theChunk.writeChunk(OpCode.op_return.toU8());
}
