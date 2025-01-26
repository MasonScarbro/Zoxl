const std = @import("std");
const compile = @import("./compiler.zig").compile;
const Chunk = @import("chunk.zig").Chunk;
var Allocator = std.testing.allocator;
const Vm = @import("./vm.zig").Vm;
const printValue = @import("value.zig").printValue;
test "Compiler Correctly Compiles a string" {
    const src = "\"string\";";
    const allocator = std.testing.allocator;

    var vm = Vm.init(allocator);
    try vm.interpret(src);
    // const result = vm.pop();

    // printValue(result);
    defer vm.deinit();
    //try compile(src, &chunk);
}

test "Compiler Correctly Compiles a comp expr" {
    const src = "4 + 3;";
    const allocator = std.testing.allocator;

    var vm = Vm.init(allocator);
    try vm.interpret(src);

    const result = vm.pop();

    printValue(result);
    defer vm.deinit();
    //try compile(src, &chunk);
}
test "Compiler Correctly prints result" {
    const src = "print (4+3);";
    const allocator = std.testing.allocator;

    var vm = Vm.init(allocator);
    try vm.interpret(src);

    // const result = vm.pop();

    // printValue(result);
    defer vm.deinit();
    //try compile(src, &chunk);
}
