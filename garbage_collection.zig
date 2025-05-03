const std = @import("std");
const Value = @import("./value.zig").Value;
const memutils = @import("./utils.mem.zig");
const Vm = @import("./vm.zig").Vm;
const Allocator = std.mem.Allocator;
const Object = @import("./object.zig").Object;
const HashTable = @import("./hashTable.zig").HashTable;
const Compiler = @import("./compiler.zig").Compiler;
const DEBUG_STRESS_GC = true;
const List = @import("list.zig").List;
const ValuesList = @import("valueslist.zig").ValuesList;
const GrayObjects = List(*Object);

// Maybe use this?
pub const GarbageCollector = struct {
    const Self = @This();

    vm: *Vm,
    compiler: ?*Compiler,
    grayObjs: GrayObjects,

    pub fn init(vm: *Vm, compiler: *Compiler) Self {
        return .{ .vm = vm, .compiler = compiler, .grayObjs = GrayObjects.init(&vm.allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.grayObjs.deinit();
    }

    pub fn collectGarbage(self: *Self) void {
        if (comptime DEBUG_STRESS_GC) {
            std.debug.print("--Collecting garbage...\n", .{});
        }
        self.markRoots();
        self.traceReferences();
        self.removeWhite(&self.vm.strings);
        self.sweep();
        if (comptime DEBUG_STRESS_GC) {
            std.debug.print("--End Collecting garbage...\n", .{});
        }
    }

    fn sweep(self: *Self) void {
        var previous: ?*Object = null;
        var current: ?*Object = self.vm.objects;

        while (current != null) {
            if (current.?.isMarked) {
                current.?.isMarked = false;
                previous = current;
                current = current.?.next;
            } else {
                const unreached = current.?;
                current = current.?.next;
                if (previous != null) {
                    previous.?.next = current;
                } else {
                    self.vm.objects = current;
                }
                unreached.freeObject(self.vm);
            }
        }
    }

    fn removeWhite(self: *Self, table: *HashTable) void {
        _ = self;
        for (0..table.capacity) |i| {
            const entry = &table.entries[i];
            if (entry.key != null and !entry.key.?.obj.isMarked) {
                _ = table.delete(entry.key.?);
            }
        }
    }

    pub fn markRoots(self: *Self) void {
        for (0..self.vm.frameCount) |i| {
            self.markValue(&self.vm.stack[i]);
        }

        for (0..self.vm.frameCount) |i| {
            self.markObject(&self.vm.frames[i].closure.obj);
        }

        var upvalue = self.vm.openUpvalues;
        while (upvalue != null) : (upvalue = upvalue.?.next) {
            self.markObject(&upvalue.?.obj);
        }

        self.markTable(&self.vm.globals);
        self.markCompilerRoots();
    }

    pub fn traceReferences(self: *Self) void {
        for (self.grayObjs.items) |obj| {
            if (comptime DEBUG_STRESS_GC) {
                std.debug.print("Tracing object: ", .{});
                obj.printObj();
            }
            self.blacken(obj);
        }
    }

    fn blacken(self: *Self, obj: *Object) void {
        switch (obj.objType) {
            .CLOSURE => {
                self.markObject(&obj.asClosure().func.obj);
                for (0..obj.asClosure().upvalueCount) |i| {
                    self.markObject(&obj.asClosure().upvalues[i].*.obj);
                }
            },
            .FUNCTION => {
                const function = obj.asFunction();
                self.markObject(&function.name.?.obj);
                self.markArray(&function.chunk.constants);
            },
            .UPVALUE => self.markValue(&obj.asUpValue().closed),
            .STRING => return,
            .NATIVE_FUNC => return,
        }
    }
    fn markCompilerRoots(self: *Self) void {
        while (self.compiler != null) {
            self.markObject(&self.compiler.?.function.obj);
            self.compiler.? = self.compiler.?.enclosing.?;
        }
    }

    fn markValue(self: *Self, value: *Value) void {
        switch (value.*) {
            .boolean, .number, .nil => return,
            .obj => self.markObject(value.obj),
        }
    }

    fn markObject(self: *Self, obj: *Object) void {
        if (obj.isMarked) return;
        if (comptime DEBUG_STRESS_GC) {
            std.debug.print("Marking object: ", .{});
            obj.printObj();
        }
        obj.isMarked = true;
        self.grayObjs.appendItem(obj);
    }

    fn markTable(self: *Self, table: *HashTable) void {
        for (0..table.capacity) |i| {
            const entry = &table.entries[i];

            self.markObject(&entry.key.?.obj);
            self.markValue(&entry.value);
        }
    }

    fn markArray(self: *Self, array: *ValuesList(Value)) void {
        for (array.items) |*item| {
            self.markValue(item);
        }
    }
};
