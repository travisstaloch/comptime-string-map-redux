const std = @import("std");
const ctmap = @import("comptime-string-map.zig");

const alphabet = "abcdefghijklmnopqrstuvwxyz";
const V = u8;
const KV = struct { []const u8, V };
const kvs_len = 800;
const Mode = enum { std, rev };

const kvs = blk: {
    @setEvalBranchQuota(kvs_len * 400);
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    var res: []const KV = &.{};
    const max_len = 20;
    for (0..kvs_len) |_| {
        const len = rand.intRangeAtMost(u8, 1, max_len);
        var buf: [max_len]u8 = undefined;
        for (0..len) |i| {
            buf[i] = alphabet[rand.intRangeLessThan(u8, 0, alphabet.len)];
        }
        const cbuf = buf;
        res = res ++ .{.{ cbuf[0..len], rand.int(u8) }};
    }
    break :blk res;
};

fn testFn(comptime num_kvs: usize, comptime mode: Mode, num_iters: usize) !void {
    @setEvalBranchQuota(num_kvs * 100);

    const kvs_list = kvs[0..num_kvs];
    const map = if (mode == .std)
        std.ComptimeStringMap(V, kvs_list)
    else
        ctmap.ComptimeStringMap(V).init(kvs_list);

    // var timer = try std.time.Timer.start();
    for (0..num_iters) |i| {
        // intentionally use all kvs, not just kvs_list, so that we bench
        // both 'key missing' and 'key found' situations.
        const kv = kvs[i % kvs.len];
        std.mem.doNotOptimizeAway(map.getIndex(kv[0]));
        std.mem.doNotOptimizeAway(map.get(kv[0]));
        std.mem.doNotOptimizeAway(map.has(kv[0]));
    }
    // std.debug.print("{}kvs:{s} {}\n", .{ num_kvs, @tagName(mode), std.fmt.fmtDuration(timer.read()) });
}

pub fn main() !void {
    // for (kvs) |kv| std.debug.print("{s}:{}\n", .{ kv[0], kv[1] });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const args = try std.process.argsAlloc(alloc);
    if (args.len < 2) {
        std.log.err("expected first arg mode: {s}", .{std.meta.fieldNames(Mode)});
        return error.MissingMode;
    }
    const mode = std.meta.stringToEnum(Mode, args[1]) orelse {
        std.log.err("invalid mode arg. expected {s}", .{std.meta.fieldNames(Mode)});
        return error.InvalidMode;
    };
    const num_iters = if (args.len > 2) try std.fmt.parseUnsigned(usize, args[2], 10) else 1000;
    const num_kvs = .{ 5, 10, 20, 40, 60, 80, 100, 200, 400, 800 };
    if (mode == .std) {
        inline for (num_kvs) |x| testFn(x, .std, num_iters) catch unreachable;
    } else {
        inline for (num_kvs) |x| testFn(x, .rev, num_iters) catch unreachable;
    }
}
