const std = @import("std");
const memanage = @import("utils.mem.zig"); // Ensure this path is correct
const List = @import("list.zig").List;
const Value = @import("value.zig").Value;
const ValuesList = @import("valueslist.zig").ValuesList;

pub const OpCode = enum(u8) {
    const Self = @This();

    op_return,
    op_constant,

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

    pub fn writeConstant(self: *Self, value: Value) !u9 {
        const idx: u9 = @truncate(self.constants.count);

        self.constants.appendValue(value);

        return idx;
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
