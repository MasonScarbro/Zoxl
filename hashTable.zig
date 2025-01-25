const std = @import("std");
const Allocator = std.mem.Allocator;

const StringObj = @import("./object.zig").StringObj;
const Value = @import("./value.zig").Value;
const growCapacity = @import("./list.zig").growCapacity;

const max_load = 0.75;

const Object = @import("./object.zig").Object;

const Entry = struct {
    key: ?*StringObj = null,
    value: Value = Value.NilValue(),
};

pub const HashTable = struct {
    const Self = @This();
    count: usize = 0,
    capacity: usize = 0,
    entries: []Entry = &[_]Entry{},
    allocator: Allocator,

    pub inline fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub inline fn deinit(self: *Self) void {
        self.allocator.free(self.entries);
        self.capacity = 0;
        self.count = 0;
    }

    pub inline fn set(self: *Self, key: *StringObj, value: Value) bool {
        const new_size = 4 * (self.count + 1);
        const needed_cap = 3 * self.entries.len;
        if (new_size > needed_cap) {
            const new_cap = growCapacity(self.capacity);
            self.adjustCapacity(new_cap);
        }
        const entry = findEntry(self.entries, self.capacity, key);
        const isNewKey = entry.key == null;
        if (isNewKey and entry.value.isNil()) self.count += 1;

        entry.key = key;
        entry.value = value;

        return isNewKey;
    }

    pub inline fn get(self: *Self, key: *StringObj) ?Value {
        if (self.count == 0) return null;

        const entry = findEntry(self.entries, self.entries.len, key);
        if (entry.key) {
            return entry.value;
        } else return null;
    }

    pub inline fn delete(self: *Self, key: *StringObj) bool {
        if (self.count == 0) return false;

        const entry = findEntry(self.entries, self.capacity, key);
        if (entry.key == null) return false;
        entry.key = null;
        entry.value = Value.BooleanValue(true);
        return true;
    }

    inline fn adjustCapacity(self: *Self, cap: usize) void {
        const new_entries = self.allocator.alloc(Entry, cap) catch @panic("Error creating Entries");

        //create and empty array of buckets
        for (new_entries) |*e| {
            e.* = Entry{};
        }
        self.count = 0;

        for (self.entries) |entry| {
            if (entry.key) |key| {
                const dest = findEntry(new_entries, self.entries.len, key);
                dest.key = entry.key;
                dest.value = entry.value;
                self.count += 1; //non tombstone increment
            }
        }

        self.allocator.free(self.entries);
        self.capacity = cap;
        self.entries = new_entries;
    }

    pub inline fn findStr(self: *Self, chars: []const u8, hash: u64) ?*StringObj {
        if (self.count == 0) return null;
        var index = hash & (self.capacity - 1);

        while (true) {
            const entry = &self.entries[index];
            if (entry.key == null) {
                //non tombstone
                if (entry.value.isNil()) return null;
            } else if (entry.key.?.chars.len == chars.len and entry.key.?.hash == hash and std.mem.eql(u8, entry.key.?.chars, chars)) {
                return entry.key;
            }
            index = (index + 1) & (self.capacity - 1);
        }
    }

    inline fn findEntry(entries: []Entry, capacity: usize, key: *StringObj) *Entry {
        var index = key.hash % capacity;
        var tombstone: ?*Entry = null;
        while (true) {
            const entry = &entries[index];
            if (entry.key == null) {
                if (entry.value.isNil()) {
                    return tombstone orelse entry;
                } else if (tombstone == null) {
                    tombstone = entry;
                    return entry;
                }
            } else if (entry.key == key) {
                return entry;
            }
            index = (index + 1) % capacity;
        }
    }

    pub fn addAll(self: *Self, to: *HashTable) void {
        for (self.entries) |entry| {
            if (entry.key) |key| {
                _ = to.set(key, entry.value);
            }
        }
    }
};
