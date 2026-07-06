const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const log = std.log;

fn enumName(T: type, value: []const u8) ?T {
    inline for (@typeInfo(T).@"enum".field_names) |enumField| {
        if (std.mem.eql(u8, value, enumField)) {
            return @field(T, enumField);
        }
    }
    return null;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    // This is appropriate for anything that lives as long as the process.

    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();
    const allocator = if (builtin.mode != .ReleaseFast) debug_allocator.allocator() else std.heap.smp_allocator;
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena: std.mem.Allocator = arena_allocator.allocator();

    // Accessing command line arguments:
    const help =
        \\ -h --help          print this description
        \\ --io[=]<impl>      Uses the given io implementation (threaded|evented)
        \\ --seed[=]<seed>    Uses the given seed for the random number gereators
        \\ --pwork[=]<amount> Sets the amount of parallel work to do to <amount>. The work
        \\                    is performed subdividing with a divide and conquer schema
        \\                    halving it until it is small enough (a single number in
        \\                    this case)
        \\ --swork[=]<amount> Sets the sequential amount of work to do to <amount>.
        \\                    The work is the number of rng to xor together
        \\                    (defaults to 100000)
        \\ --wait[=<ms>]      Waits for the requested number of seconds in the leaf work
        \\                    tasks
    ;
    const args = try minimal.args.toSlice(arena);
    var iarg: usize = 1;
    var io_impl: IoImplementation = .threaded;
    var seed: ?u64 = null;
    var pwork: u64 = 0;
    var swork: u64 = 100000;
    var wait_ms: u64 = 0;
    while (iarg < args.len) {
        const arg = args[iarg];
        const splitPos: usize = std.mem.findScalar(u8, arg, '=') orelse arg.len;
        const core_arg = arg[0..splitPos];
        if (std.ascii.eqlIgnoreCase(args[iarg], "-h") or std.ascii.eqlIgnoreCase(args[iarg], "--help")) {
            log.info("{s}\n{s}\n", .{ std.fs.path.basename(args[0]), help });
            std.process.exit(0);
        } else if (std.ascii.eqlIgnoreCase(core_arg, "--io")) {
            const impl = if (splitPos < arg.len) arg[splitPos + 1 .. arg.len] else blk: {
                iarg += 1;
                if (iarg >= args.len) {
                    log.err("Error: expected argument after --io\n", .{});
                    std.process.exit(2);
                }
                break :blk args[iarg];
            };
            if (enumName(IoImplementation, impl)) |v| {
                io_impl = v;
            } else {
                log.err("Invalid io implementation specified in {s}, known values: {any}", .{ arg, std.enums.values(IoImplementation) });
                std.process.exit(2);
            }
        } else if (std.ascii.eqlIgnoreCase(core_arg, "--seed")) {
            const seed_str = if (splitPos < arg.len) arg[splitPos + 1 .. arg.len] else blk: {
                iarg += 1;
                if (iarg >= args.len) {
                    log.err("Error: expected argument after --seed\n", .{});
                    std.process.exit(2);
                }
                break :blk args[iarg];
            };
            seed = try std.fmt.parseUnsigned(u64, seed_str, 10);
        } else if (std.ascii.eqlIgnoreCase(core_arg, "--pwork")) {
            const str_val = if (splitPos < arg.len) arg[splitPos + 1 .. arg.len] else blk: {
                iarg += 1;
                if (iarg >= args.len) {
                    log.err("Error: expected argument after --pwork\n", .{});
                    std.process.exit(2);
                }
                break :blk args[iarg];
            };
            pwork = try std.fmt.parseUnsigned(u64, str_val, 10);
        } else if (std.ascii.eqlIgnoreCase(core_arg, "--swork")) {
            const str_val = if (splitPos < arg.len) arg[splitPos + 1 .. arg.len] else blk: {
                iarg += 1;
                if (iarg >= args.len) {
                    log.err("Error: expected argument after --swork\n", .{});
                    std.process.exit(2);
                }
                break :blk args[iarg];
            };
            swork = try std.fmt.parseUnsigned(u64, str_val, 10);
        } else if (std.ascii.eqlIgnoreCase(core_arg, "--wait")) {
            const str_val: ?[]const u8 = if (splitPos < arg.len) arg[splitPos + 1 .. arg.len] else null;
            wait_ms = if (str_val) |v| try std.fmt.parseUnsigned(u64, v, 10) else 1000;
        } else {
            log.err("Error: Unknown argument {} ('{s}').\n\n{s}\n{s}\n", .{ iarg, args[iarg], std.fs.path.basename(args[0]), help });
            std.process.exit(1);
        }
        iarg += 1;
    }
    var threaded: std.Io.Threaded = undefined;
    var evented: std.Io.Evented = undefined;
    const io = switch (io_impl) {
        .threaded => blk1: {
            threaded = .init(allocator, .{
                .argv0 = .init(minimal.args),
                .environ = minimal.environ,
            });
            break :blk1 threaded.io();
        },
        .evented => blk2: {
            try evented.init(allocator, .{
                .argv0 = .init(minimal.args),
                .environ = minimal.environ,
                .backing_allocator_needs_mutex = false,
            });
            break :blk2 evented.io();
        },
    };
    defer switch (io_impl) {
        .threaded => threaded.deinit(),
        .evented => switch (builtin.os.tag) {
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .linux => {},
            // deint triggers a compilation bug on macos with zig 0.16.0 see
            // https://codeberg.org/ziglang/zig/commit/4d5721214f31684e3bed3624878d8903fabe8e39
            else => evented.deinit(),
        },
    };
    var buf1: [256]u8 = undefined;
    var stderr_w = Io.File.stderr().writer(io, &buf1);
    defer stderr_w.end() catch {};
    const stderr = &stderr_w.interface;
    var buf2: [256]u8 = undefined;
    var stdout_w = Io.File.stdout().writer(io, &buf2);
    defer stdout_w.end() catch {};
    const stdout = &stdout_w.interface;
    try stdout.writeByte('[');
    try stderr.writeByte('\n');
    try stderr.flush();
    var c_env: CalcEnv = .{
        .work_per_block = swork,
        .wait_ms = wait_ms,
    };
    const res = try c_env.calc(io, allocator, seed orelse 0, pwork);
    const bits_work: u6 =  @intCast(63 - @clz(pwork));
    const ncpu: u64 = try std.Thread.getCpuCount();
    const bit_ncpu: u6 = @intCast(63 - @clz(ncpu));
    const ideal_in_flight_max: u64 = if (bits_work > bit_ncpu)
        (bits_work - bit_ncpu + 1) * ncpu
    else
        @min(pwork, 2 * ncpu);
    const core_tree: u64 = pwork >> 1;
    const time_ns = c_env.duration.toNanoseconds();
    const time: f64 = @as(f64, @floatFromInt(time_ns)) / @as(f64, @floatFromInt(1_000_000_000));
    const stime: f64 = @as(f64, @floatFromInt(c_env.seq_time_ns.load(.acquire))) / @as(f64, @floatFromInt(1_000_000_000));
    try std.json.fmt(.{
        .depth = bits_work + 1,
        .pwork = pwork,
        .swork = swork,
        .wait_ms = wait_ms,
        .core_tree = core_tree,
        .ncpu = ncpu,
        .perfect_parallel_in_flight_max = ideal_in_flight_max,
        .actual_max_in_flight = c_env.max_in_flight.load(.acquire),
        .in_flight_now = c_env.in_flight.load(.acquire),
        .checksum = res,
        .time = time,
        .sequential_leaf_time = stime,
        .parallel_speedup = stime / time,
    }, .{ .whitespace = .indent_2 }).format(stdout);
    try stdout.writeAll("]\n");
    try stdout.flush();
}

/// Specifies the io implementation
pub const IoImplementation = enum {
    threaded,
    evented,
};

/// Builds a unique random sequence that can be easily evaluated in random order
/// by creating a tree of seeds. This can be used to initialize an rng with
/// log_4 levels, the rng at each level initializes the 4 options of the level below
/// requires that std.Random.DefaultPrng (currently backed by Xoshiro256) can be
/// initialized with a u64 as seed
const SeedTree = struct {
    seeds: [30]u64 = @splat(0xbadadabe_badabeef),
    valid_index: u1 = 0,
    depth: u6 = 0,
    index: u57 = 0,

    pub fn desc(self: *const SeedTree, writer: *std.Io.Writer) !void {
        try writer.writeAll("SeedTree{{\n");
        try writer.print("  .depth = {},\n", .{self.depth});
        try writer.print("  .index = {b},\n", .{self.index});
        try writer.writeAll("  .seeds = {");
        const levels: usize = self.n_levels();
        for (0..levels + 1) |i| {
            if (i % 4 == 0)
                try writer.writeAll("\n    ");
            try writer.print("{:2}:{x},", .{ levels - i, self.seeds[levels - i] });
            if (self.valid_index == 0)
                break;
        }
        try writer.writeAll("\n  },\n");
        try writer.writeAll("}\n");
    }

    fn mask(self: *const SeedTree) u64 {
        return (@as(u64, 1) << self.depth) - 1;
    }

    fn r_depth(self: *const SeedTree) usize {
        const depth: usize = self.depth;
        const add_more: usize = if ((depth & 3) != 0) 4 else 0;
        return (depth & ~@as(usize, 3)) + add_more;
    }

    fn n_levels(self: *const SeedTree) usize {
        return self.r_depth() >> 1;
    }

    pub fn init(root_seed: u64, depth: usize) !SeedTree {
        if (depth > 57)
            return error.DepthTooLarge;
        // round up to the closest multiple of 4
        const add_more: usize = if ((depth & @as(usize, 3)) != 0) 4 else 0;
        const r_depth_: usize = (depth & ~@as(usize, 3)) + add_more;
        const n_levels_: usize = (r_depth_ >> 1);
        var seeds: [30]u64 = @splat(0);
        seeds[n_levels_] = root_seed;
        return SeedTree{
            .depth = @intCast(depth),
            .valid_index = 0,
            .seeds = seeds,
        };
    }

    pub fn rngForIndex(self: *SeedTree, index: u64) !std.Random.DefaultPrng {
        if (index > self.mask())
            return error.IndexTooLarge;
        const i_start: usize = if (self.valid_index == 1)
            // position of first different bit between old self.index, and the new index
            64 - @clz(@as(u64, @intCast(self.index)) ^ index)
        else
            self.r_depth();
        self.valid_index = 1;
        // round up to the closest multiple of 4
        const add_more: usize = if ((i_start & 3) != 0) 4 else 0;
        const idepth: usize = (i_start & ~@as(usize, 3)) + add_more;
        var ilevel = idepth >> 1;
        var rng: std.Random.DefaultPrng = .init(self.seeds[ilevel]);
        var new_seeds: [4]u64 = undefined;
        new_seeds[0] = 0;
        const rbuf: []u8 = @as([*]u8, @ptrCast((&new_seeds).ptr))[0 .. 4 * 8];
        while (ilevel > 0) {
            rng.fill(rbuf);
            ilevel -= 1;
            const shift: u6 = @intCast(ilevel << 1);
            const seed_index: usize = @intCast((index >> shift) & 3);
            self.seeds[ilevel] = new_seeds[seed_index];
            rng.seed(new_seeds[seed_index]);
        }
        self.index = @intCast(index);
        return rng;
    }
};

test "SeedTree" {
    var rng: std.Random.DefaultPrng = .init(std.testing.random_seed);
    const r: std.Random = rng.random();
    const depth = 40;
    const io = std.testing.io;
    for (0..10) |_| {
        var buf1: [32]u8 = undefined;
        var buf2: [32]u8 = undefined;
        var buf_stderr: [256]u8 = undefined;
        const n0 = r.int(u64);
        var stdErrFile = std.Io.File.stderr();
        var stdErrFileWriter = stdErrFile.writer(io, &buf_stderr);
        defer stdErrFileWriter.end() catch {};
        const stderr = &stdErrFileWriter.interface;
        var sTree1: SeedTree = try .init(n0, depth);
        const n1 = r.uintAtMostBiased(u64, sTree1.mask());
        const rng1 = try sTree1.rngForIndex(n1);
        const rng1b: std.Random.DefaultPrng = rng1;
        try std.testing.expectEqual(rng1.s, rng1b.s);
        const n2 = r.uintAtMostBiased(u64, 100);
        const n3 = (n1 + n2) & sTree1.mask();
        var rng2 = try sTree1.rngForIndex(n3);
        var sTree2: SeedTree = try .init(n0, depth);
        var rng3 = try sTree2.rngForIndex(n3);
        try std.testing.expectEqual(rng2.s, rng3.s);
        try std.testing.expect((n2 == 0 and std.mem.eql(u64, &rng1b.s, &rng2.s)) or !std.mem.eql(u64, &rng1b.s, &rng2.s));
        rng2.fill(&buf1);
        rng3.fill(&buf2);
        try std.testing.expectEqual(buf1, buf2);
        try std.testing.expectEqual(sTree1.seeds, sTree2.seeds);
        var rng4 = try sTree1.rngForIndex(n1);
        var rng5 = try sTree2.rngForIndex(n1);
        try stderr.flush();
        try std.testing.expectEqual(rng4.s, rng5.s);
        try std.testing.expectEqual(rng1b.s, rng5.s);
        rng4.fill(&buf1);
        rng5.fill(&buf2);
        try std.testing.expectEqual(buf1, buf2);
        try std.testing.expectEqual(sTree1.seeds, sTree2.seeds);
        const n4 = r.uintAtMostBiased(u64, sTree2.mask());
        var rng6 = try sTree1.rngForIndex(n4);
        var rng7 = try sTree2.rngForIndex(n4);
        try std.testing.expectEqual(rng6.s, rng7.s);
        rng6.fill(&buf1);
        rng7.fill(&buf2);
        try std.testing.expectEqual(buf1, buf2);
        try std.testing.expectEqual(sTree1.seeds, sTree2.seeds);
    }
}

pub const CalcEnv = struct {
    in_flight: std.atomic.Value(i64) = .init(0),
    max_in_flight: std.atomic.Value(i64) = .init(0),
    seq_time_ns: std.atomic.Value(i64) = .init(0),
    duration: std.Io.Duration = .zero,
    work_per_block: u64,
    wait_ms: u64,

    pub fn calc(self: *CalcEnv, io: std.Io, allocator: std.mem.Allocator, seed: u64, blocks_to_read: u64) !u64 {
        if (blocks_to_read == 0)
            return 0
        else if (blocks_to_read > (@as(u64, 1) << 63))
            return error.blocks_to_read_too_large;
        const start = std.Io.Clock.awake.now(io);
        defer {
            const end = std.Io.Clock.awake.now(io);
            self.duration = start.durationTo(end);
        }
        const depth0: u6 = @intCast(63 - @clz(blocks_to_read));
        const more: u6 = if (blocks_to_read != (@as(u64, 1) << depth0)) 1 else 0;
        const depth: u6 = depth0 + more;
        const seed_tree: SeedTree = try .init(seed, depth);
        const in_flight: i64 = self.in_flight.fetchAdd(1, .monotonic);
        _ = self.max_in_flight.fetchMax(in_flight, .monotonic);
        return self.calc_some(io, allocator, seed_tree, 0, blocks_to_read);
    }

    fn calc_some(self: *CalcEnv, io: std.Io, allocator: std.mem.Allocator, seed_tree: SeedTree, offset: u64, blocks_to_read: u64) !u64 {
        defer {
            const in_flight: i64 = self.in_flight.fetchAdd(-1, .monotonic);
            _ = self.max_in_flight.fetchMax(in_flight, .monotonic);
        }
        if (blocks_to_read > 1) {
            const to_read = blocks_to_read >> 1;
            const in_flight: i64 = self.in_flight.fetchAdd(1, .monotonic);
            _ = self.max_in_flight.fetchMax(in_flight, .monotonic);
            var f1 = io.async(calc_some, .{ self, io, allocator, seed_tree, offset, to_read });
            defer _ = f1.cancel(io) catch 0;
            const offset2: u64 = offset + to_read;
            var seed_tree2: SeedTree = seed_tree;
            _ = try seed_tree2.rngForIndex(offset2);
            const in_flight2: i64 = self.in_flight.fetchAdd(1, .monotonic);
            _ = self.max_in_flight.fetchMax(in_flight2, .monotonic);
            var f2 = io.async(calc_some, .{ self, io, allocator, seed_tree, offset2, blocks_to_read - to_read });
            defer _ = f2.cancel(io) catch 0;
            const r1: u64 = try f1.await(io);
            const r2: u64 = try f2.await(io);
            return r1 ^ r2;
        }
        const start = std.Io.Clock.awake.now(io);
        defer {
            const end = std.Io.Clock.awake.now(io);
            const duration = start.durationTo(end);
            _ = self.seq_time_ns.fetchAdd(@intCast(duration.nanoseconds), .monotonic);
        }
        var seed_tree2: SeedTree = seed_tree;
        var rng = try seed_tree2.rngForIndex(offset);
        var res: u64 = 0;
        for (0..self.work_per_block) |_| {
            res ^= rng.next();
        }
        if (self.wait_ms != 0)
            try io.sleep(.fromMilliseconds(@intCast(self.wait_ms)), .awake);
        return res;
    }
};
