const std = @import("std");
const compile = @import("./compiler.zig").compile;
const Chunk = @import("chunk.zig").Chunk;
var Allocator = std.testing.allocator;
const Vm = @import("./vm.zig").Vm;

test "Compiler Correctly Compiles code" {
    const src = "4 + 4";
    var allocator = std.testing.allocator;

    var vm = Vm.init(&allocator);
    try vm.interpret(src);
    //try compile(src, &chunk);
}
