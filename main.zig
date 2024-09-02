const std = @import("std");
const chunk = @import("chunk.zig");

pub fn main() !void {
    // Create a general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize a Chunk with an allocator and initial capacity
    var myChunk = try chunk.Chunk.initWithAlloc(&allocator, 8);
    defer myChunk.freeChunk(&allocator);

    // Write data to the chunk
    const opCode: chunk.OpCode = .op_return;
    try myChunk.writeChunk(&allocator, opCode.toU8());

    // Optionally, print out the contents of the chunk for verification
    std.debug.print("Chunk contents:\n");
    for (myChunk.code) |byte| {
        std.debug.print("  {d}\n", .{byte});
    }
}
