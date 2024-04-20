const std = @import("std");
const mem = std.mem;

/// Comptime string map optimized for small sets of disparate string keys.
/// Works by separating the keys by length at comptime and only checking strings of
/// equal length at runtime.
///
/// `kvs_list` expects a list of `struct { []const u8, V }` (key-value pair) tuples.
/// You can pass `struct { []const u8 }` (only keys) tuples if `V` is `void`.
pub fn ComptimeStringMap(comptime V: type) type {
    return ComptimeStringMapWithEql(V, defaultEql);
}

/// Like `std.mem.eql`, but takes advantage of the fact that the lengths
/// of `a` and `b` are known to be equal.
pub fn defaultEql(a: []const u8, b: []const u8) bool {
    if (a.ptr == b.ptr) return true;
    for (a, b) |a_elem, b_elem| {
        if (a_elem != b_elem) return false;
    }
    return true;
}

/// Like `std.ascii.eqlIgnoreCase` but takes advantage of the fact that
/// the lengths of `a` and `b` are known to be equal.
pub fn eqlAsciiIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.ptr == b.ptr) return true;
    for (a, b) |a_c, b_c| {
        if (std.ascii.toLower(a_c) != std.ascii.toLower(b_c)) return false;
    }
    return true;
}

/// ComptimeStringMap, but accepts an equality function (`eql`).
/// The `eql` function is only called to determine the equality
/// of equal length strings. Any strings that are not equal length
/// are never compared using the `eql` function.
pub fn ComptimeStringMapWithEql(
    comptime V: type,
    comptime eql: fn (a: []const u8, b: []const u8) bool,
) type {
    return struct {
        sorted_kvs: []const KV = &.{},
        len_indexes: []const usize = &.{},
        min_len: usize = std.math.maxInt(usize),
        max_len: usize = 0,

        pub const KV = struct {
            key: []const u8,
            value: V,
        };

        const Self = @This();

        /// returns a map backed by static, comptime allocated memory
        pub inline fn init(comptime kvs_list: anytype) Self {
            comptime {
                @setEvalBranchQuota(1500);
                var self = Self{};
                if (kvs_list.len == 0)
                    return self;

                var sorted_kvs: [kvs_list.len]KV = undefined;
                self.initSortedKVs(kvs_list, &sorted_kvs);
                const kvs = sorted_kvs;
                self.sorted_kvs = &kvs;

                var len_indexes: [self.max_len + 1]usize = undefined;
                self.initLenIndexes(&len_indexes);
                const lis = len_indexes;
                self.len_indexes = &lis;
                return self;
            }
        }

        /// returns a map backed by memory allocated with `allocator`
        pub fn initRuntime(kvs_list: anytype, allocator: mem.Allocator) !Self {
            var self = Self{};
            if (kvs_list.len == 0)
                return self;

            const sorted_kvs = try allocator.alloc(KV, kvs_list.len);
            errdefer allocator.free(self.sorted_kvs);
            self.initSortedKVs(kvs_list, sorted_kvs);
            self.sorted_kvs = sorted_kvs;

            const len_indexes = try allocator.alloc(usize, self.max_len + 1);
            self.initLenIndexes(len_indexes);
            self.len_indexes = len_indexes;
            return self;
        }

        /// this method should only be used with initRuntime() and not with init().
        pub fn deinit(self: Self, allocator: mem.Allocator) void {
            allocator.free(self.len_indexes);
            allocator.free(self.sorted_kvs);
        }

        const SortContext = struct {
            kvs: []KV,

            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return ctx.kvs[a].key.len < ctx.kvs[b].key.len;
            }

            pub fn swap(ctx: @This(), a: usize, b: usize) void {
                return std.mem.swap(KV, &ctx.kvs[a], &ctx.kvs[b]);
            }
        };

        fn initSortedKVs(self: *Self, kvs_list: anytype, sorted_kvs: []KV) void {
            for (kvs_list, 0..) |kv, i| {
                sorted_kvs[i] = if (V == void)
                    .{ .key = kv.@"0", .value = {} }
                else
                    .{ .key = kv.@"0", .value = kv.@"1" };
                self.min_len = @min(self.min_len, kv.@"0".len);
                self.max_len = @max(self.max_len, kv.@"0".len);
            }
            mem.sortUnstableContext(0, sorted_kvs.len, SortContext{ .kvs = sorted_kvs });
        }

        fn initLenIndexes(self: Self, len_indexes: []usize) void {
            var len: usize = 0;
            var i: usize = 0;
            while (len <= self.max_len) : (len += 1) {
                // find the first keyword len == len
                while (len > self.sorted_kvs[i].key.len) {
                    i += 1;
                }
                len_indexes[len] = i;
            }
        }

        /// Checks if the map has a value for the key.
        pub fn has(self: *const Self, str: []const u8) bool {
            return self.get(str) != null;
        }

        /// Returns the value for the key if any, else null.
        pub fn get(self: *const Self, str: []const u8) ?V {
            if (self.sorted_kvs.len == 0)
                return null;

            return self.sorted_kvs[self.getIndex(str) orelse return null].value;
        }

        pub fn getIndex(self: *const Self, str: []const u8) ?usize {
            if (self.sorted_kvs.len == 0)
                return null;

            if (str.len < self.min_len or str.len > self.max_len)
                return null;

            var i = self.len_indexes[str.len];
            while (true) {
                const kv = self.sorted_kvs[i];
                if (kv.key.len != str.len)
                    return null;
                if (eql(kv.key, str))
                    return i;
                i += 1;
                if (i >= self.sorted_kvs.len)
                    return null;
            }
        }

        /// Returns the longest partially matching key, value pair for `str`
        /// else null.  A partial match means that `str` starts with key.
        pub fn getPartial(self: *const Self, str: []const u8) ?KV {
            if (self.sorted_kvs.len == 0)
                return null;

            return self.sorted_kvs[self.getIndexPartial(str) orelse return null];
        }

        pub fn getIndexPartial(self: *const Self, str: []const u8) ?usize {
            if (self.sorted_kvs.len == 0)
                return null;

            if (str.len < self.min_len)
                return null;

            var len = @min(self.max_len, str.len);
            while (len >= self.min_len) : (len -= 1) {
                if (self.getIndex(str[0..len])) |i|
                    return i;
            }
            return null;
        }
    };
}

const TestEnum = enum { A, B, C, D, E };
const TestMap = ComptimeStringMap(TestEnum);
const TestKV = struct { []const u8, TestEnum };
const TestMapVoid = ComptimeStringMap(void);
const TestKVVoid = struct { []const u8 };
const talloc = std.testing.allocator;

test "list literal of list literals" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };
    const map = ComptimeStringMap(TestEnum).init(slice);
    try testMap(map);
    // Default comparison is case sensitive
    try std.testing.expect(null == map.get("NOTHING"));

    const mapr = try ComptimeStringMap(TestEnum).initRuntime(slice, talloc);
    defer mapr.deinit(talloc);
    try testMap(mapr);
    // Default comparison is case sensitive
    try std.testing.expect(null == mapr.get("NOTHING"));
}

test "array of structs" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    try testMap(ComptimeStringMap(TestEnum).init(slice));

    const map = try ComptimeStringMap(TestEnum).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testMap(map);
}

test "slice of structs" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    try testMap(ComptimeStringMap(TestEnum).init(slice));

    const map = try ComptimeStringMap(TestEnum).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testMap(map);
}

fn testMap(map: anytype) !void {
    try std.testing.expectEqual(TestEnum.A, map.get("have").?);
    try std.testing.expectEqual(TestEnum.B, map.get("nothing").?);
    try std.testing.expect(null == map.get("missing"));
    try std.testing.expectEqual(TestEnum.D, map.get("these").?);
    try std.testing.expectEqual(TestEnum.E, map.get("samelen").?);

    try std.testing.expect(!map.has("missing"));
    try std.testing.expect(map.has("these"));

    try std.testing.expect(null == map.get(""));
    try std.testing.expect(null == map.get("averylongstringthathasnomatches"));
}

test "void value type, slice of structs" {
    const slice = [_]TestKVVoid{
        .{"these"},
        .{"have"},
        .{"nothing"},
        .{"incommon"},
        .{"samelen"},
    };
    const map = ComptimeStringMap(void).init(slice);
    try testSet(map);
    // Default comparison is case sensitive
    try std.testing.expect(null == map.get("NOTHING"));

    const mapr = try ComptimeStringMap(void).initRuntime(slice, talloc);
    defer mapr.deinit(talloc);
    try testSet(mapr);
    try std.testing.expect(null == mapr.get("NOTHING"));
}

test "void value type, list literal of list literals" {
    const slice = [_]TestKVVoid{
        .{"these"},
        .{"have"},
        .{"nothing"},
        .{"incommon"},
        .{"samelen"},
    };

    try testSet(ComptimeStringMap(void).init(slice));

    const map = try ComptimeStringMap(void).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testSet(map);
}

fn testSet(map: TestMapVoid) !void {
    try std.testing.expectEqual({}, map.get("have").?);
    try std.testing.expectEqual({}, map.get("nothing").?);
    try std.testing.expect(null == map.get("missing"));
    try std.testing.expectEqual({}, map.get("these").?);
    try std.testing.expectEqual({}, map.get("samelen").?);

    try std.testing.expect(!map.has("missing"));
    try std.testing.expect(map.has("these"));

    try std.testing.expect(null == map.get(""));
    try std.testing.expect(null == map.get("averylongstringthathasnomatches"));
}

fn testComptimeStringMapWithEql(map: ComptimeStringMapWithEql(TestEnum, eqlAsciiIgnoreCase)) !void {
    try testMap(map);
    try std.testing.expectEqual(TestEnum.A, map.get("HAVE").?);
    try std.testing.expectEqual(TestEnum.E, map.get("SameLen").?);
    try std.testing.expect(null == map.get("SameLength"));
    try std.testing.expect(map.has("ThESe"));
}

test "ComptimeStringMapWithEql" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    try testComptimeStringMapWithEql(ComptimeStringMapWithEql(TestEnum, eqlAsciiIgnoreCase).init(slice));

    const map = try ComptimeStringMapWithEql(TestEnum, eqlAsciiIgnoreCase).initRuntime(slice, talloc);
    try testComptimeStringMapWithEql(map);
    defer map.deinit(talloc);
}

test "empty" {
    const m1 = ComptimeStringMap(usize).init(.{});
    try std.testing.expect(null == m1.get("anything"));

    const m2 = ComptimeStringMapWithEql(usize, eqlAsciiIgnoreCase).init(.{});
    try std.testing.expect(null == m2.get("anything"));

    const m3 = try ComptimeStringMap(usize).initRuntime(.{}, talloc);
    try std.testing.expect(null == m3.get("anything"));

    const m4 = try ComptimeStringMapWithEql(usize, eqlAsciiIgnoreCase).initRuntime(.{}, talloc);
    try std.testing.expect(null == m4.get("anything"));
}

fn testRedundantEntries(map: TestMap) !void {
    // No promises about which one you get:
    try std.testing.expect(null != map.get("redundant"));

    // Default map is not case sensitive:
    try std.testing.expect(null == map.get("REDUNDANT"));

    try std.testing.expectEqual(TestEnum.A, map.get("theNeedle").?);
}

test "redundant entries" {
    const slice = [_]TestKV{
        .{ "redundant", .D },
        .{ "theNeedle", .A },
        .{ "redundant", .B },
        .{ "re" ++ "dundant", .C },
        .{ "redun" ++ "dant", .E },
    };

    try testRedundantEntries(ComptimeStringMap(TestEnum).init(slice));

    const map = try ComptimeStringMap(TestEnum).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testRedundantEntries(map);
}

fn testRedundantInsensitive(map: ComptimeStringMapWithEql(TestEnum, eqlAsciiIgnoreCase)) !void {
    // No promises about which result you'll get ...
    try std.testing.expect(null != map.get("REDUNDANT"));
    try std.testing.expect(null != map.get("ReDuNdAnT"));
    try std.testing.expectEqual(TestEnum.A, map.get("theNeedle").?);
}
test "redundant insensitive" {
    const slice = [_]TestKV{
        .{ "redundant", .D },
        .{ "theNeedle", .A },
        .{ "redundanT", .B },
        .{ "RE" ++ "dundant", .C },
        .{ "redun" ++ "DANT", .E },
    };

    try testRedundantInsensitive(ComptimeStringMapWithEql(TestEnum, eqlAsciiIgnoreCase).init(slice));

    const map = try ComptimeStringMapWithEql(TestEnum, eqlAsciiIgnoreCase).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testRedundantInsensitive(map);
}

test "comptime-only value" {
    const map = ComptimeStringMap(type).init(.{
        .{ "a", struct {
            pub const foo = 1;
        } },
        .{ "b", struct {
            pub const foo = 2;
        } },
        .{ "c", struct {
            pub const foo = 3;
        } },
    });

    try std.testing.expect(map.get("a").?.foo == 1);
    try std.testing.expect(map.get("b").?.foo == 2);
    try std.testing.expect(map.get("c").?.foo == 3);
    try std.testing.expect(map.get("d") == null);
}

fn testGetPartial(map: TestMap) !void {
    try std.testing.expectEqual(null, map.getPartial(""));
    try std.testing.expectEqual(null, map.getPartial("bar"));
    try std.testing.expectEqualStrings("aaaa", map.getPartial("aaaabar").?.key);
    try std.testing.expectEqualStrings("aaa", map.getPartial("aaabar").?.key);
}
test "getPartial" {
    const slice = [_]TestKV{
        .{ "a", .A },
        .{ "aa", .B },
        .{ "aaa", .C },
        .{ "aaaa", .D },
    };

    try testGetPartial(ComptimeStringMap(TestEnum).init(slice));

    const map = try ComptimeStringMap(TestEnum).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testGetPartial(map);
}

fn testGetPartial2(map: ComptimeStringMap(usize)) !void {
    try std.testing.expectEqual(1, map.get("one"));
    try std.testing.expectEqual(null, map.get("o"));
    try std.testing.expectEqual(null, map.get("onexxx"));
    try std.testing.expectEqual(9, map.get("nine"));
    try std.testing.expectEqual(null, map.get("n"));
    try std.testing.expectEqual(null, map.get("ninexxx"));
    try std.testing.expectEqual(null, map.get("xxx"));

    try std.testing.expectEqual(1, map.getPartial("one").?.value);
    try std.testing.expectEqual(1, map.getPartial("onexxx").?.value);
    try std.testing.expectEqual(null, map.getPartial("o"));
    try std.testing.expectEqual(null, map.getPartial("on"));
    try std.testing.expectEqual(9, map.getPartial("nine").?.value);
    try std.testing.expectEqual(9, map.getPartial("ninexxx").?.value);
    try std.testing.expectEqual(null, map.getPartial("n"));
    try std.testing.expectEqual(null, map.getPartial("xxx"));
}

test "getPartial2" {
    const slice = [_]struct { []const u8, usize }{
        .{ "one", 1 },
        .{ "two", 2 },
        .{ "three", 3 },
        .{ "four", 4 },
        .{ "five", 5 },
        .{ "six", 6 },
        .{ "seven", 7 },
        .{ "eight", 8 },
        .{ "nine", 9 },
    };
    try testGetPartial2(ComptimeStringMap(usize).init(slice));

    const map = try ComptimeStringMap(usize).initRuntime(slice, talloc);
    defer map.deinit(talloc);
    try testGetPartial2(map);
}
