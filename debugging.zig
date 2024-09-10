const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Opc = @import("chunk.zig").OpCode;
const Value = @import("value.zig").Value;
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
        .op_negate => simpleInstruction(instruction.toString(), offset),
        .op_constant_long => longConstInstruction(instruction.toString(), chunk, offset),
    };
}

pub fn simpleInstruction(name: []const u8, offset: usize) usize {
    std.debug.print(" {s} \n", .{name});
    return offset + 1;
}

pub fn longConstInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const constant: u32 = @as(u32, chunk.code.items[offset + 1]) |
        @as(u32, (chunk.code.items[offset + 2])) << 8 |
        @as(u32, (chunk.code.items[offset + 3])) << 16;

    const stdout = std.io.getStdOut().writer();

    // Use try to handle potential errors when printing the name
    _ = stdout.print("{s}\n", .{name}) catch |err| {
        std.debug.print("Failed to print name: {}\n", .{err});
    };

    const tag = @TypeOf(chunk.constants.items[constant]);
    std.debug.print("Type: {}\n", .{tag});
    printValue(chunk.constants.items[constant]);
    // Call the Zig equivalent of printValue
    //printValue(chunk.constants.items[constant]);

    // Print the ending quote and newline
    _ = stdout.print("'\n", .{}) catch |err| {
        std.debug.print("Failed to print ending quote: {}\n", .{err});
    };
    return offset + 4;
}

pub fn constInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const constant_idx = chunk.code.items[offset + 1];
    const constant = chunk.constants.items[constant_idx];
    printValue(constant);
    std.debug.print("{s: <16} '{}'\n", .{ name, constant });
    return offset + 2;
}

pub fn printStack(stack: []Value) void {
    std.debug.print("          ", .{});

    for (stack) |value| {
        std.debug.print("[{}]", .{value});
    }

    std.debug.print("\n", .{});
}
