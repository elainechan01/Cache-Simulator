const std = @import("std");
const testing = std.testing;
const debug = std.debug;
const log = std.log;

const cache = @import("./main.zig");

const alloc = testing.allocator;

const ArrayList = std.ArrayList;

const CacheSim = cache.CacheSim;
const Instruction = cache.Instruction;
const Act = cache.Act;
const Set = cache.Set;

test "fails on to few arguments" {
    var args: []const [:0]const u8 = &.{ "-d", "-not real" };
    if (CacheSim.processInput(args)) |_| {
        log.err("args of `-d -no real` should fail\n", .{});
        unreachable;
    } else |err| {
        try testing.expect(err == error.Arguments);
    }
}

test "fails on bad input" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-x", "2", "-t", "input/yi.trace" };
    if (CacheSim.processInput(args)) |_| {
        log.err("args of `-s 6 -E 2 -x 2 -t input/yi.trace` should fail\n", .{});
        unreachable;
    } else |err| {
        try testing.expect(err == error.UnknownArgument);
    }
}

test "pass on good input" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/yi.trace" };
    const parsed_args = try CacheSim.parseArgs(args);
    try testing.expectEqualStrings(parsed_args.filename, "input/yi.trace");
    try testing.expect(parsed_args.set_bits == 6);
    try testing.expect(parsed_args.lines_per_set == 2);
    try testing.expect(parsed_args.block_bits == 2);
}

test "get tag value" {
    try testing.expectEqual(@as(u64, 6), CacheSim.getTag(25616, 8, 4));
    try testing.expectEqual(@as(u64, 100), CacheSim.getTag(102424, 3, 7));
    try testing.expectEqual(@as(u64, 16), CacheSim.getTag(256, 2, 2));
}

test "get set number" {
    try testing.expectEqual(@as(u64, 65), CacheSim.getSetNumber(25616, 8, 4));
    try testing.expectEqual(@as(u64, 0), CacheSim.getSetNumber(102424, 3, 7));
    try testing.expectEqual(@as(u64, 64), CacheSim.getSetNumber(256, 10, 2));
}

const INSTRUCTIONS: []const Instruction = &.{
    .{ .act = Act.load, .addr = 0x10, .size = 1 },
    .{ .act = Act.modify, .addr = 0x20, .size = 1 },
    .{ .act = Act.load, .addr = 0x22, .size = 1 },
    .{ .act = Act.store, .addr = 0x18, .size = 1 },
    .{ .act = Act.load, .addr = 0x110, .size = 1 },
    .{ .act = Act.load, .addr = 0x210, .size = 1 },
    .{ .act = Act.modify, .addr = 0x12, .size = 1 },
};
test "cache simulation (run only)" {
    var set_list = try ArrayList(Set).initCapacity(alloc, std.math.pow(u64, 2, 6));
    try set_list.appendNTimes(.{ .lines = ArrayList(u64).init(alloc) }, std.math.pow(u64, 2, 6));

    var instructions = ArrayList(Instruction).init(alloc);
    try instructions.appendSlice(INSTRUCTIONS);
    var csim: CacheSim = .{
        .instructions = instructions,
        .cache = set_list,
        .set_bits = 6,
        .lines_per_set = 2,
        .block_bits = 2,
    };
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 3), report.hits);
    try testing.expectEqual(@as(u64, 6), report.misses);
    try testing.expectEqual(@as(u64, 2), report.evictions);
}

test "cache full simulation run (no file reading)" {
    const infile = try std.fs.cwd().openFile("input/dave.trace", .{ });
    defer infile.close();

    const stat = try infile.stat();
    var csim = try CacheSim.build(&.{
        .filename = "doesn't matter",
        .file = try std.io.bufferedReader(infile.reader()).reader().readAllAlloc(alloc, stat.size),
        .set_bits = 6,
        .lines_per_set = 2,
        .block_bits = 2
    });
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 0), report.hits);
    try testing.expectEqual(@as(u64, 5), report.misses);
    try testing.expectEqual(@as(u64, 0), report.evictions);
}

test "create and run cache from arguments ('ex')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/ex.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 2), report.hits);
    try testing.expectEqual(@as(u64, 3), report.misses);
    try testing.expectEqual(@as(u64, 0), report.evictions);
}

test "create and run cache from arguments ('yi')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/yi.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 3), report.hits);
    try testing.expectEqual(@as(u64, 6), report.misses);
    try testing.expectEqual(@as(u64, 2), report.evictions);
}

test "create and run cache from arguments ('yi2')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/yi2.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 13), report.hits);
    try testing.expectEqual(@as(u64, 4), report.misses);
    try testing.expectEqual(@as(u64, 0), report.evictions);
}

test "create and run cache from arguments ('dave')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/dave.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 0), report.hits);
    try testing.expectEqual(@as(u64, 5), report.misses);
    try testing.expectEqual(@as(u64, 0), report.evictions);
}

test "create and run cache from arguments ('echo')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/echo.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 29448), report.hits);
    try testing.expectEqual(@as(u64, 36196), report.misses);
    try testing.expectEqual(@as(u64, 36068), report.evictions);
}

test "create and run cache from arguments ('long')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/long.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 198205), report.hits);
    try testing.expectEqual(@as(u64, 183354), report.misses);
    try testing.expectEqual(@as(u64, 183226), report.evictions);
}

test "create and run cache from arguments ('out')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/out.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 83), report.hits);
    try testing.expectEqual(@as(u64, 11), report.misses);
    try testing.expectEqual(@as(u64, 0), report.evictions);
}

test "create and run cache from arguments ('trans')" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "2", "-b", "2", "-t", "input/trans.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 197), report.hits);
    try testing.expectEqual(@as(u64, 40), report.misses);
    try testing.expectEqual(@as(u64, 0), report.evictions);
}

test "create and run cache from arguments ('echo' 8, 4, 1)" {
    var args: []const [:0]const u8 = &.{ "-s", "8", "-E", "4", "-b", "1", "-t", "input/echo.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 48842), report.hits);
    try testing.expectEqual(@as(u64, 16802), report.misses);
    try testing.expectEqual(@as(u64, 15778), report.evictions);
}

test "create and run cache from arguments ('long' 6, 12, 8)" {
    var args: []const [:0]const u8 = &.{ "-s", "6", "-E", "12", "-b", "8", "-t", "input/long.trace" };

    var csim = try CacheSim.init(args);
    defer csim.deinit();

    const report = try csim.runCacheSim();

    try testing.expectEqual(@as(u64, 379227), report.hits);
    try testing.expectEqual(@as(u64, 2332), report.misses);
    try testing.expectEqual(@as(u64, 1564), report.evictions);
}
