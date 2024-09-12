const std = @import("std");
const chunk = @import("chunk.zig");
const OpCode = @import("chunk.zig").OpCode;
const Vm = @import("vm.zig").Vm;

pub fn main() anyerror!void {
    // Create a general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var vm = Vm.init(&allocator);
    defer vm.deinit();
}
