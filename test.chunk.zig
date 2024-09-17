const std = @import("std");
const List = @import("list.zig");
const Chunk = @import("chunk.zig").Chunk;
var Allocator = std.testing.allocator;
const Value = @import("value.zig").Value;
const printValue = @import("value.zig").printValue;
const OpCode = @import("chunk.zig").OpCode;
const debug = @import("debugging.zig");
const Vm = @import("vm.zig").Vm;
const InterpretResult = @import("vm.zig").InterpretResult;

test "Chunk initialization and deinitialization" {
    //const expect = std.testing.expect;
    var allocator = std.testing.allocator;

    var chunk = Chunk.init(&allocator);
    var vm = Vm.init(&allocator);
    defer vm.deinit();
    // Adding a dummy constant to the chunk
    var value = Value.NumberValue(3.14);

    // Adding dummy instructions to the chunk
    //chunk.writeConstant(value, 1);
    //try chunk.writeChunk(OpCode.op_negate.toU8(), 1);

    // TEST for 3.4 + 5.6
    value = Value.NumberValue(3.4);
    chunk.writeConstant(value, 1);

    value = Value.NumberValue(5.6);
    chunk.writeConstant(value, 1);

    try chunk.writeChunk(OpCode.op_add.toU8(), 1); //add
    //

    try chunk.writeChunk(OpCode.op_return.toU8(), 1);

    vm.interpret(&chunk);

    const result = vm.pop();
    std.debug.print("result: \n", .{});
    printValue(result);
}
