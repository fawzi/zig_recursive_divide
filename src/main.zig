const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const log = std.log;

const recursive_divide = @import("recursive_divide");

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
        \\                    (defaults to 1000)
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
        .evented => evented.deinit(),
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
    var c_env: recursive_divide.CalcEnv = .{
        .work_per_block = swork,
        .wait_ms = wait_ms,
    };
    const res = try c_env.calc(io, allocator, seed orelse 0, pwork);
    const bits_work0: u6 = @intCast(63 - @clz(pwork));
    const bits_work: u6 = if (pwork == (@as(u64, 1) << bits_work0)) bits_work0 + 1 else bits_work0 + 2;
    const ncpu: u64 = try std.Thread.getCpuCount();
    const bit_ncpu0: u6 = @intCast(63 - @clz(ncpu));
    const bit_ncpu1: u6 = if ((@as(u64, 1) << bit_ncpu0) != ncpu) bit_ncpu0 + 2 else bit_ncpu0 + 1;
    const ideal_in_flight_max: u64 = if (bits_work > bit_ncpu1)
        (bits_work - bit_ncpu1 + 1) * ncpu
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
        .ideal_in_flight_max = ideal_in_flight_max,
        .max_in_flight = c_env.max_in_flight.load(.acquire),
        .in_flight_now = c_env.in_flight.load(.acquire),
        .checksum = res,
        .time = time,
        .sequential_time = stime,
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
