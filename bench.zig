const std = @import("std");
const ctmap = @import("comptime-string-map.zig");

const alphabet = "abcdefghijklmnopqrstuvwxyz";
const V = u8;
const KV = struct { []const u8, V };
const kvs_len = 400;
pub const Mode = enum {
    std,
    rev,
    // validate,
};

const kvs_and_indexes = blk: {
    @setEvalBranchQuota(kvs_len * 400);
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    var res: []const KV = &.{};
    const max_len = 15;
    const min_len = 2;
    for (0..kvs_len) |_| {
        const len = rand.intRangeAtMostBiased(u8, min_len, max_len);
        var buf: [max_len]u8 = undefined;
        for (0..len) |i| {
            buf[i] = alphabet[rand.intRangeLessThan(u8, 0, alphabet.len)];
        }
        const cbuf = buf;
        res = res ++ .{.{ cbuf[0..len], rand.int(u8) }};
    }
    var _indexes: [kvs_len]u16 = undefined;
    for (0..kvs_len) |i| _indexes[i] = i;
    rand.shuffle(u16, &_indexes);

    break :blk .{ res, _indexes };
};

/// a list if random keys from alphabet with length min_len..max_len and
/// random values
const kvs = kvs_and_indexes[0];
/// a random shuffled list of indexes from 0..kvs_len
const indexes = kvs_and_indexes[1];

fn validate(comptime num_kvs: usize, num_iters: usize) !void {
    @setEvalBranchQuota(num_kvs * 100);
    const kvs_list = kvs[0..num_kvs];
    const map1 = std.ComptimeStringMap(V, kvs_list);
    const map2 = ctmap.ComptimeStringMap(V).init(kvs_list);

    for (0..num_iters) |i| {
        // intentionally sample kvs[0..num_kvs * 2], not just kvs_list, so that
        // both 'key missing' and 'key found' situations are equally likely.
        const kv = kvs[indexes[i % kvs_len] % (num_kvs * 2)];

        if (map1.getIndex(kv[0]) != map2.getIndex(kv[0])) return error.Invalid;
        if (map1.get(kv[0]) != map2.get(kv[0])) return error.Invalid;
        if (map1.has(kv[0]) != map2.has(kv[0])) return error.Invalid;
    }
}

fn bench(comptime mode: Mode, comptime num_kvs: usize, num_iters: usize) void {
    @setEvalBranchQuota(num_kvs * 100);
    std.debug.assert(num_kvs * 2 <= kvs_len);

    const kvs_list = kvs[0..num_kvs];
    const map = comptime if (mode == .std)
        std.ComptimeStringMap(V, kvs_list)
    else
        ctmap.ComptimeStringMap(V).init(kvs_list);

    // var timer = try std.time.Timer.start();
    // var misses: usize = 0;
    for (0..num_iters) |i| {
        // intentionally sample kvs[0..num_kvs * 2], not just kvs_list, so that
        // both 'key missing' and 'key found' situations are equally likely.
        const kv = kvs[indexes[i % kvs_len] % (num_kvs * 2)];
        const index = map.getIndex(kv[0]);
        // misses += @intFromBool(index == null);
        std.mem.doNotOptimizeAway(index);
        std.mem.doNotOptimizeAway(map.get(kv[0]));
        std.mem.doNotOptimizeAway(map.has(kv[0]));
    }
    // std.debug.print("misses {}/{}\n", .{ misses, num_iters });
    // std.debug.print("{}kvs:{s} {}\n", .{ num_kvs, @tagName(mode), std.fmt.fmtDuration(timer.read()) });
}

pub fn main() void {
    // for (kvs) |kv| std.debug.print("{s}:{}\n", .{ kv[0], kv[1] });

    const mode = comptime std.enums.nameCast(Mode, @import("build_options").mode);

    inline for (.{ 5, 10, 20, 60, 100, 200 }) |num_kvs| {
        bench(mode, num_kvs, @import("build_options").num_iters);
    }
}
