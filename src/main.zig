const std = @import("std");
const fs = std.fs;
const io = std.io;
const debug = std.debug;
const process = std.process;
const testing = std.testing;
const pow = std.math.pow;

const ArrayList = std.ArrayList;

const alloc = testing.allocator;

// this should be printed if the user didn't enter the expected arguments
const help_text =
    \\Usage: ./main [-h] -s <s> -E <E> -b <b> -t <tracefile>
    \\-h: Optional help flag that prints usage info
    \\-v: Optional verbose flag that displays trace info
    \\-s <s>: Number of set index bits (S = 2^s is the number of sets)
    \\-E <E>: Associativity (number of lines per set)
    \\-b <b>: Number of block bits (B = 2^b is the block size)
    \\-t <tracefile>: Name of the valgrind trace to replay
;

// enum for three different possible actions for an instruction
pub const Act = enum {
    load,
    store,
    modify,
};

// struct representing a line from the input file
pub const Instruction = struct {
    act: Act,
    addr: u64,
    size: u64,
};

/// struct representing a set, which is a
/// collection of cache lines.
///
/// The set is given an `ArrayList` and must have `Set.deinit()` called
/// to clean up the `ArrayList` used.
pub const Set = struct {
    lines: std.ArrayList(u64),

    pub fn deinit(self: *Set) void {
        self.lines.deinit();
    }
};

/// struct representing a cache simulator
pub const CacheSim = struct {
    const Self = @This();

    // this is a struct representing the argument info from
    // the command line and also the file buffer
    const ArgInfo = struct {
        filename: []const u8,
        file: []u8,
        set_bits: u6,
        lines_per_set: usize,
        block_bits: u6,

        pub fn deinit(self: *ArgInfo) void {
            ArrayList(u8).fromOwnedSlice(alloc, self.file).deinit();
        }
    };

    // this is a struct to represent the result of the simulation
    const CacheReport = struct {
        hits: u64,
        misses: u64,
        evictions: u64,
    };

    // store the instructions from the input file here
    instructions: ArrayList(Instruction),
    // create the cache here
    cache: ArrayList(Set),

    // these basically get copied over from the ArgInfo struct
    set_bits: u6,
    lines_per_set: usize,
    block_bits: u6,

    /// Create a `CacheSim` struct from command line arguments.
    pub fn init(args: []const [:0]const u8) !Self {
        var arginfo = try processInput(args);
        return build(&arginfo);
    }

    /// The allocated resources need to be deallocated (the fields you needed to allocate to add).
    pub fn deinit(self: *Self) void {
        for (self.cache.items) |*inner_set| {
            inner_set.deinit();
        }
        self.cache.deinit();
        self.instructions.deinit();
    }

    /// Once the `CacheSim.processInput()` has been called this method run the simulation
    /// running each of the instructions and collecting a `CacheReport`.
    pub fn runCacheSim(self: *Self) !CacheReport {
        // TODO: create report
        //debug.print("{s}\n",.{self.cache});

        // build cache 
        // cache size = args.lines_per_set * numberOfSets * blockSize
        var numberOfSets: u64 = pow(u64, 2, self.set_bits);
        //var blockSize: usize = @floatToInt(usize,@exp2(@intToFloat(f16, self.block_bits)));
        //var cacheSize: usize = self.lines_per_set * numberOfSets * blockSize;
        //try self.cache.ensureTotalCapacityPrecise(cacheSize);

        var curr_numberOfSets: usize = 0;
        while (curr_numberOfSets < numberOfSets){
            var tempSet = Set{
                .lines = ArrayList(u64).init(alloc)
            };
            try self.cache.append(tempSet);
            curr_numberOfSets += 1;
        }

 
        var report = CacheReport{
            .hits = 0,
            .misses = 0,
            .evictions = 0
        };
        for (self.instructions.items) |instruction| {
            var setIndex: u64 = getSetNumber(instruction.addr, self.set_bits, self.block_bits);
            var tag: u64 = getTag(instruction.addr, self.set_bits, self.block_bits);
            //debug.print("set index:{d}  -> {d}\n tag -> {d}\n",.{setIndex, self.cache.items[setIndex].lines.items, tag});
            //debug.print("{d}\n",.{instruction.act});
            try read(instruction, &self.cache.items[setIndex], tag, self.lines_per_set, &report);
        }
        //debug.print("{s}\n",.{self.cache.items[0]});
        return report;
    }

    /// this function creates a `CacheSim` from the parsed arguments and file
    /// create an `ArgInfo` and build the `CacheSim`.
    ///
    /// The `ArgInfo` must clean itself up!
    pub fn build(args: *ArgInfo) !Self {
        // remember to clean up memory
        defer args.deinit();
        // TODO: iterate over lines
        // parse `instructions` buffer into an ArrayList of Instruction structs
        var list = std.ArrayList(Instruction).init(alloc);

        var iterator = std.mem.tokenize(u8, args.file, "\r\n");

        while (true){
            // init
            var temp = Instruction{
                .act = Act.load,
                .addr = 0,
                .size = 0
            };
            var x: usize = 0;
            var line = iterator.next();
            if (line == null) break;

            var toCheck: u8 = line.?[0];
            
            if (toCheck == "I".*[0]) continue;

            var buffer = std.mem.tokenize(u8, line.?, " ");

            while (true){
                var y: usize = 0;
                var action = buffer.next();
                if (action == null) break;
                
                // if x == 0, action == action
                if (x == 0){
                    if (action.?[0] == "L".*[0]){
                        temp.act = Act.load;
                    }else if(action.?[0] == "S".*[0]){
                        temp.act = Act.store;
                    }else if(action.?[0] == "M".*[0]){
                        temp.act = Act.modify;
                    }
                }else{
                    var two = std.mem.tokenize(u8, action.?, ",");
                    while (true){
                        var token = two.next();
                        if (token == null) break;
                        // if y == 0, token == addr
                        // else, token == size
                        if (y == 0){
                            temp.addr = try std.fmt.parseInt(u64, token.?, 16);
                            //debug.print("addr: {d}\n",.{temp.addr});
                        }else{
                            temp.size = try std.fmt.parseInt(u64, token.?, 0);
                            //debug.print("size: {s}\n",.{token});
                        }
                        y += 1;
                    }
                }
                x += 1;
            }
            try list.append(temp);
        }

        // build cache
        var cache = std.ArrayList(Set).init(alloc);

        // TODO: return an instance of Self (that's this struct!)
        return Self{
            .instructions = list,
            .cache = cache,
            .set_bits = args.set_bits,
            .lines_per_set = args.lines_per_set,
            .block_bits = args.block_bits
        };
    }

    /// This function opens the file, reads everything into a buffer
    /// and then returns it, just like we did in A2
    pub fn processInput(args: []const [:0]const u8) !ArgInfo {
        var parse_args = try parseArgs(args);

        // open the file
        const infile = try fs.cwd().openFile(parse_args.filename, .{});
        // remember to clean up memory
        defer infile.close();

        // read in everything
        const stat = try infile.stat();
        parse_args.file = try io.bufferedReader(infile.reader()).reader().readAllAlloc(alloc, stat.size);

        // return the ArgsInfo struct with the file data in it
        return parse_args;
    }

    /// Helper function to parse the arguments given to `CacheSim`.
    ///
    /// This needs to return `error.Arguments` if there is not at least 8 arguments (args.len < 8)
    /// and if the arg is not one of t, s, E, b, h it should return `error.UnknownArgument`.
    pub fn parseArgs(args: []const [:0]const u8) !ArgInfo {

        // TODO: check for at least 8 arguments
        if (args.len < 8){
            // to check again
            return error.Arguments;                
        }
        // TODO: check for optional flag, h
        // TODO: check for unknown argument
        else{
            var i: usize = 0;
            while (i < args.len){
                var param = args[i];
                if (param[0] == "-".*[0]){
                    if (param[1] != "t".*[0] and param[1] != "s".*[0] and param[1] != "E".*[0] and param[1] != "b".*[0] and param[1] != "h".*[0]){
                        return error.UnknownArgument;
                    }
                }
                i += 1;
            }
        }

        //debug.print("{s}\n",.{args});
        // TODO: parse input arguments
        var filename = args[8];
        var set_bits = try std.fmt.parseInt(u6,args[2],10);
        var lines_per_set = try std.fmt.parseInt(usize,args[4],10);
        var block_bits = try std.fmt.parseInt(u6,args[6],10);
        
        // TODO: return an ArgInfo struct
        var val = try alloc.alloc(u8,100);
        return ArgInfo {
            .filename = filename,
            .file = val,
            .set_bits = set_bits,
            .lines_per_set = lines_per_set,
            .block_bits = block_bits
        };
    }

    /// this function is where the magic happens, you will be
    /// acting on the Instruction from the input file.
    ///
    /// you should have gotten a pointer to the correct Set to
    /// perform the memory read in, the tag and lines_per_set
    /// and report all need to be given to this function.
    ///
    /// remember that if a set has the maximum amount of lines
    /// that a cache eviction must happen if the tag was not found!
    pub fn read(instruction: Instruction, set: *Set, tag: u64, lines_per_set: usize, report: *CacheReport) !void {
        // TODO: attempt to hit cache, if it fails, load a new line
        //       possibly evicting in the process
        //debug.print("{d}\n",.{set.lines.items.len});
        if (instruction.act == Act.load){
            //debug.print("Loading: {d}\n",.{tag});
            if (scanForTag(&set.lines, tag) == true){
                report.hits += 1;
            }else{
                report.misses += 1;
                if (set.lines.items.len == lines_per_set){
                    report.evictions += 1;
                    const temp = set.lines.orderedRemove(0);
                    _=temp;
                    try set.lines.append(tag);
                }else{
                    try set.lines.append(tag);
                }
            }
        }
        else if (instruction.act == Act.store){
            //debug.print("Storing: {d}\n",.{tag});
            if (scanForTag(&set.lines, tag) == true){
                report.hits += 1;
            }else{
                report.misses += 1;
                if (set.lines.items.len == lines_per_set){
                    report.evictions += 1;
                    const temp = set.lines.orderedRemove(0);
                    _=temp;
                    try set.lines.append(tag);
                }else{
                    try set.lines.append(tag);
                }
            }
        }
        else {
            //debug.print("Modifying: {d}\n",.{tag});
            if (scanForTag(&set.lines, tag) == true){
                report.hits += 2;
            }else{
                report.misses += 1;
                report.hits += 1;
                if (set.lines.items.len == lines_per_set){
                    report.evictions += 1;
                    const temp = set.lines.orderedRemove(0);
                    _=temp;
                    try set.lines.append(tag);
                }else{
                    try set.lines.append(tag);
                }
                //debug.print("{d}\n",.{set.lines.items});
            }
        }
        //debug.print("{s}\n",.{report});
    }

    /// this function takes an address, set bits and block bits and
    /// returns the calculated set number from the address
    pub fn getSetNumber(address: u64, set_bits: u6, block_bits: u6) u64 {
        // TODO: return the set number from address
        var numberOfSets: u64 = pow(u64, 2, set_bits);
        var setMask: u64 = (numberOfSets-1) << block_bits;
        var set: u64 = (address&setMask) >> block_bits;

        //var set: u64 = (address >> block_bits) & (((block_bits - set_bits) << set_bits) - (block_bits - set_bits));
        return set;
    }

    /// this function takes an address, set bits and block bits and
    /// returns the calculated tag from the address
    pub fn getTag(address: u64, set_bits: u6, block_bits: u6) u64 {
        // TODO: return tag value from address
        // var numberOfSets: u64 = pow(u64, 2, set_bits);
        // var setMask: u64 = (numberOfSets - 1) << block_bits;
        // var blockSize: u64 = pow(u64, 2, block_bits);
        // var blockMask: u64 = blockSize - 1;
        // var tagMask: u64 = 0b11111111^setMask^blockMask;
        // var tag: u64 = ((address&tagMask) >> block_bits) >> set_bits;

        var tag: u64 = address >> (block_bits + set_bits);
        return tag;
    }

    /// this function takes a pointer to an ArrayList(u64) and a u64
    /// and scans for an entry in the list that matches, if a match
    /// is found it returns true, otherwise it returns false
    pub fn scanForTag(lines: *ArrayList(u64), tag: u64) bool {
        // TODO: scan over the array list looking for given tag
        for (lines.items) |item| {
            if (item == tag) return true;
        }
        return false;
    }
};

/// don't need to worry about the `main()` function again,
/// just read carefully how the CacheSim instance is created
/// and used to generate the simulation report
pub fn main() !void {
    // set up argument processing (cross-platform)
    const args = try process.argsAlloc(alloc);
    // remember to clean up memory
    defer process.argsFree(alloc, args);

    // create an instance of CacheSim
    var cache = try CacheSim.init(args);
    // remember to clean up memory
    defer cache.deinit();

    // iterate over actions and simulate cache behavior
    const report = try cache.runCacheSim();

    // got this far? output the result because we're done
    const writer = io.getStdOut().writer();
    try writer.print("hits: {d}, misses: {d}, evictions: {d}\n", .{ report.hits, report.misses, report.evictions });
}
