const std = @import("std");
const chunk = @import("chunk.zig");
const OpCode = @import("chunk.zig").OpCode;
const Vm = @import("vm.zig").Vm;
const InterpretErr = @import("./vm.zig").InterpretErr;

pub fn main() anyerror!void {
    const errout = std.io.getStdErr().writer();

    // Create a general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var vm = Vm.init(allocator);
    defer vm.deinit();

    if (args.len == 1) {
        repl(&vm) catch unreachable;
    }
    if (args.len == 2) {
        runFile(args[1], &vm, allocator) catch |err| {
            try errout.print("Error: {}\n", .{err});
            std.process.exit(74);
        };
    } else {
        try errout.print("Usage: Zoxl [path]\n", .{});
        std.process.exit(64);
    }
}

fn repl(vm: *Vm) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var buf: [1024]u8 = undefined;

    while (true) {
        try stdout.writeAll("> ");

        if (stdin.readUntilDelimiterOrEof(&buf, '\n') catch |err| {
            std.debug.print("Error reading input: {}\n", .{err});
            continue;
        }) |line| {
            vm.interpret(line) catch |err| {
                std.debug.print("Error: {}\n", .{err});
            };
        } else {
            break;
        }
    }
}

fn runFile(fileName: []const u8, vm: *Vm, allocator: std.mem.Allocator) !void {
    const source = try readFile(fileName, allocator);
    defer allocator.free(source);

    try vm.interpret(source);
}

fn readFile(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, 100_000_000);
}
//______________________ WINDOWS TOOLS ___________________________//
