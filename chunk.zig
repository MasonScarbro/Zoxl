const std = @import("std");
const memanage = @import("utils.mem.zig"); // Ensure this path is correct
const List = @import("list.zig").List;

pub const OpCode = enum(u8) {
    const Self = @This();

    op_return,

    pub fn toU8(self: Self) u8 {
        return @intFromEnum(self);
    }

    pub fn fromU8(n: u8) Self {
        return @enumFromInt(n);
    }
};

pub const Chunk = struct {
    const Self = @This();
    const BytesList = List(u8);

    code: BytesList,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .code = BytesList.init(allocator),
        };
    }

    pub fn writeChunk(self: *Self, byte: u8) !void {
        self.code.appendItem(byte);
    }

    pub fn freeChunk(self: *Chunk) void {
        self.code.deinit();
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
    }
};
