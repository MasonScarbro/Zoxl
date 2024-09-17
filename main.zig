const std = @import("std");
const chunk = @import("chunk.zig");
const OpCode = @import("chunk.zig").OpCode;
const Vm = @import("vm.zig").Vm;
const InterpretErr = @import("./vm.zig").InterpretErr;

const errout = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

pub fn main() anyerror!void {
    // Create a general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var vm = Vm.init(&allocator);
    defer vm.deinit();

    if (args.len == 1) {
        repl(&vm);
    }
    if (args.len == 2) {
        runFile(args[0], &vm, allocator);
    } else {
        try errout.print("Usage: Zoxl [path]\n", .{});
        std.process.exit(64);
    }
}

fn repl(vm: *Vm) void {
    var reader = std.io.bufferedReader(std.io.getStdIn().reader()).reader();
    var line: u8[1024] = undefined;

    while (true) {
        stdout.writeAll("> ");

        line = reader.readUntilDelimiterOrEof(&line, '\n') catch {
            std.debug.panic("Couldnt Read????", .{});
        };

        vm.interpret(line) catch {};
    }
}

fn runFile(fileName: []const u8, vm: *Vm, allocator: std.mem.Allocator) void {
    const source = readFile(fileName, allocator);
    defer allocator.free(source);

    vm.interpret(source) catch |e| {
        switch (e) {
            InterpretErr.RuntimeError => std.process.exit(70),
            InterpretErr.CompileError => std.process.exit(65),
        }
    };
}

fn readFile(path: []const u8, allocator: std.mem.Allocator) []const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        errout.print("Could not open file \"{s}\", error: {any}.\n", .{ path, err }) catch {};
        std.process.exit(74);
    };
    defer file.close();

    return file.readToEndAlloc(allocator, 100_000_000) catch |err| {
        errout.print("Could not read file \"{s}\", error: {any}.\n", .{ path, err }) catch {};
        std.process.exit(74);
    };
}
