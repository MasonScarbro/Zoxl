const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Opc = @import("chunk.zig").OpCode;
const printValue = @import("value.zig").printValue;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) !void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.count) : (offset = disassembleInstruction(chunk, offset)) {}
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{d:0>4}", .{offset});

    const lines = chunk.lines;
    const instruction = Opc.fromU8(chunk.code.items[offset]);

    if (offset > 0 and lines.items[offset] == lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d: >4} ", .{lines.items[offset]});
    }

    return switch (instruction) {
        .op_return => simpleInstruction(instruction.toString(), offset),
        .op_constant => constInstruction(instruction.toString(), chunk, offset),
    };
}

pub fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print(" {s} \n", .{name});
    return offset + 1;
}
pub fn constInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const constant_idx = chunk.code.items[offset + 1];
    const constant = chunk.constants.items[constant_idx];

    std.debug.print("{s: <16} '{}'\n", .{ name, constant });
    return offset + 2;
}
