const Value = @import("./value.zig").Value;
const std = @import("std");
const Vm = @import("./vm.zig").Vm;

pub fn clockNative(vm: *Vm, argCount: usize, args: Value) Value {
    if (argCount != 0) {
        _ = vm.runtimeErrW("Expected 0 args got: {}", .{argCount}) catch {}; //  this is basically useless find a way to safley return error unioin and report
    }
    _ = args;
    return Value.NumberValue(@as(f64, @floatFromInt(std.time.milliTimestamp())) / 1000);
}
