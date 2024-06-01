const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Pool = std.Thread.Pool;
const Value = std.atomic.Value;

const ResultTag = enum {
    ok,
    err,
    none,
};

pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();

        const Result = union(ResultTag) {
            ok: T,
            err: anyerror, // TODO: Investigate a way to have specific errors
            none: i32,
        };

        _result: Result = @unionInit(Result, "none", 0),
        _done: Value(bool) = Value(bool).init(false),
        _started: Value(bool) = Value(bool).init(false),

        /// Check if future is finished.
        pub fn done(self: *Self) bool {
            return self.*._done.load(.acquire);
        }

        /// Check if future has been started.
        pub fn started(self: *Self) bool {
            return self.*._started.load(.acquire);
        }

        /// Use to take ownership of the result, getting a Result union.
        pub fn take(self: *Self) Result {
            assert(self.done());

            const result = self.*._result;
            self.*._result = Result{ .none = 0 };
            return result;
        }

        /// Use to take ownership of the result, getting either []T or an error.
        pub fn takeUnwrapped(self: *Self) !T {
            assert(self.done());

            const result = self.*._result;
            self.*._result = Result{ .none = 0 };
            switch (result) {
                Result.ok => |ok| {
                    return ok;
                },
                Result.err => |err| {
                    return err;
                },
                Result.none => {
                    return error.NoneValue;
                },
            }
        }

        pub fn init(self: *Self, pool: *Pool, comptime pFn: anytype, pArgs: anytype) void {
            // Provide comptime clarification on `pFn` & `pArgs` expectations.
            const FnType = @TypeOf(pFn);
            const ArgsType = @TypeOf(pArgs);
            const fntype_info = @typeInfo(FnType);
            const argstype_info = @typeInfo(ArgsType);
            if (.Fn != fntype_info) {
                @compileError("`pFn` must be function, found " ++ @typeName(FnType));
            }
            if (.Struct != argstype_info or !argstype_info.Struct.is_tuple) {
                @compileError("`pArgs` must be tuple, found " ++ @typeName(ArgsType));
            }

            // could spawn on heap and allow `var fut = Future(T).init(..);`?
            const run_args = .{ self, pFn, pArgs };
            pool.spawn(run, run_args) catch |err| {
                self._result = Result{ .err = err };
                self._done.store(true, .release);
            };
            self._started.store(true, .release);
            return;
        }

        pub fn deinit(self: *Self) void {
            // TODO
            _ = self;
            return;
        }

        pub fn run(self: *Self, pFn: anytype, pArgs: anytype) void {
            if (@call(.auto, pFn, pArgs)) |ok| {
                self.*._result = Result{ .ok = ok };
            } else |err| {
                self.*._result = Result{ .err = err };
            }
            self.*._done.store(true, .release);
            return;
        }
    };
}

const testing = std.testing;

test "basic" {
    const Helper = struct {
        pub fn add_i32(a: i32, b: i32) !i32 {
            return a + b;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var pool: Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var fut_i32 = Future(i32){};
    defer fut_i32.deinit();
    fut_i32.init(&pool, Helper.add_i32, .{ 2, 40 });
    while (!fut_i32.done()) {}
    const value = try fut_i32.takeUnwrapped();
    try testing.expect(42 == value);
}

// TODO: See if this is worth it:
// During a normal test (zig build test) skip tests like the one below.
// Then run (manually? automatable?) specific tests that *should* fail / panic.
// Basically, something like: https://github.com/ziglang/zig/issues/1356
test "logic error" {
    return error.SkipZigTest;

    //const Helper = struct {
    //    pub fn wait(milliseconds: u64) !void {
    //        std.time.sleep(milliseconds * 1_000_000);
    //    }
    //};

    //var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    //defer _ = gpa.deinit();
    //const allocator = gpa.allocator();
    //var pool: Pool = undefined;
    //try pool.init(.{ .allocator = allocator });
    //defer pool.deinit();

    //var fvoid = Future(void){};
    //fvoid.start(&pool, Helper.wait, .{5000});
    //const result = fvoid.take(); // trigger a panic
    //_ = result;
}
