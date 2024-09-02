const std = @import("std");
const List = @import("list.zig");
const Chunk = @import("chunk.zig").Chunk;
var Allocator = std.testing.allocator;
const Value = @import("value.zig").Value;
const OpCode = @import("chunk.zig").OpCode;
const debug = @import("debugging.zig");

test "Chunk initialization and deinitialization" {
    const expect = std.testing.expect;
    var allocator = std.testing.allocator;

    var chunk = Chunk.init(&allocator);
    defer chunk.deinit();

    try chunk.writeChunk(OpCode.op_return.toU8(), 1);
    const value = Value.NumberValue(3.14);
    const idx = try chunk.writeConstant(value); // Handle potential errors
    _ = idx; // Explicitly ignore the returned value
    try expect(chunk.code.items[0] == OpCode.op_return.toU8());

    try expect(chunk.constants.count == 1);
    try debug.disassembleChunk(&chunk, "test chunk");
}
