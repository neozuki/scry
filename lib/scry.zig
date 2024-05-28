const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;
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
            ok: []T,
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

        /// Use this to take ownership of the result.
        /// Make sure to free the result with the same allocator passed in to `start`.
        /// The future will contain a `none` result afterwards.
        pub fn take(self: *Self) Result {
            const result = self.*._result;
            self.*._result = Result{ .none = 0 };
            return result;
        }

        /// Destructures the Result into the `[]T`, or throws an error (if present)
        pub fn takeUnwrapped(self: *Self) ![]T {
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

        /// Use this to start the future.
        pub fn start(self: *Self, pool: *Pool, pAlloc: Allocator, comptime pFn: anytype, pArgs: anytype) void {
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

            // TODO: maybe add some assertions (if we're in certain build modes?)

            self.*._done.store(false, .release); // reset
            self.*._started.store(false, .release); // reset

            const run_args = .{ self, pFn, .{pAlloc} ++ pArgs };
            pool.spawn(run, run_args) catch |err| {
                self.*._result = Result{ .err = err };
                self.*._done.store(true, .release);
            };
            self.*._started.store(true, .release);
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
        pub fn add_i32(allocator: Allocator, a: i32, b: i32) ![]i32 {
            var result = try allocator.alloc(i32, 1);
            result[0] = a + b;
            return result;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var pool: Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var fi32 = Future(i32){};

    fi32.start(&pool, allocator, Helper.add_i32, .{ 2, 40 });
    while (!fi32.done()) {}
    const value = try fi32.takeUnwrapped();
    try testing.expect(1 == value.len);
    try testing.expect(42 == value[0]);
    allocator.free(value);

    fi32.start(&pool, allocator, Helper.add_i32, .{ 5, 10 });
    while (!fi32.done()) {}
    const result = fi32.take();
    try testing.expect(.ok == result);
    try testing.expect(1 == result.ok.len);
    try testing.expect(15 == result.ok[0]);
    allocator.free(result.ok);
}
