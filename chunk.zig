const std = @import("std");
const memanage = @import("utils.mem.zig"); // Ensure this path is correct
const List = @import("list.zig").List;
const Value = @import("value.zig").Value;
const ValuesList = @import("valueslist.zig").ValuesList;

pub const OpCode = enum(u8) {
    const Self = @This();

    op_return,
    op_constant,
    op_negate,
    op_add,
    op_subtract,
    op_mult,
    op_divide,
    op_constant_long,

    pub fn toU8(self: Self) u8 {
        return @intFromEnum(self);
    }

    pub fn fromU8(n: u8) Self {
        return @enumFromInt(n);
    }

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .op_return => "OP_RETURN",
            .op_constant => "OP_CONSTANT",
            .op_add => "OP_ADD",
            .op_subtract => "OP_SUBTRACT",
            .op_mult => "OP_MULTIPLY",
            .op_divide => "OP_DIVIDE",
            .op_negate => "OP_NEGATE",
            .op_constant_long => "OP_CONSTANT_LONG",
        };
    }
};

pub const Chunk = struct {
    const Self = @This();
    const BytesList = List(u8);
    const ValueList = ValuesList(Value);
    const LinesList = List(usize);

    code: BytesList,
    lines: LinesList,
    constants: ValueList,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .code = BytesList.init(allocator),
            .lines = LinesList.init(allocator),
            .constants = ValueList.init(allocator),
        };
    }

    pub fn writeChunk(self: *Self, byte: u8, line: usize) !void {
        self.code.appendItem(byte);
        self.lines.appendItem(line);
    }

    pub fn addConstant(self: *Self, value: Value) usize {
        const idx: usize = self.constants.count;

        self.constants.appendValue(value);

        return idx;
    }

    pub fn writeConstant(self: *Self, value: Value, line: usize) void {
        // Add the constant to the chunk and get the index.
        const idx: usize = addConstant(self, value);
        if (idx < 256) {
            // If the index fits in one byte, use OP_CONSTANT.
            try writeChunk(self, OpCode.op_constant.toU8(), line);
            try writeChunk(self, @intCast(idx), line);
        } else {
            // If the index doesn't fit in one byte, use OP_CONSTANT_LONG.
            try writeChunk(self, OpCode.op_constant_long.toU8(), line);
            // Write the index as three separate bytes.
            try writeChunk(self, @intCast((idx & 0xff)), line);
            try writeChunk(self, @intCast((idx >> 8) & 0xff), line);
            try writeChunk(self, @intCast((idx >> 16) & 0xff), line);
        }
    }

    pub fn freeChunk(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }
};
