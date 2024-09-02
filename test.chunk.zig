const std = @import("std");
const List = @import("list.zig");
const Chunk = @import("chunk.zig").Chunk;
var Allocator = std.testing.allocator;
const OpCode = @import("chunk.zig").OpCode;

test "Chunk initialization and deinitialization" {
    const expect = std.testing.expect;
    var allocator = std.testing.allocator;

    var chunk = Chunk.init(&allocator);
    defer chunk.deinit();

    try chunk.writeChunk(OpCode.op_return.toU8());
    try expect(chunk.code.items[0] == OpCode.op_return.toU8());
}
