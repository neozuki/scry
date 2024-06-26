const std = @import("std");
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
            none: i32, // TODO: remove 'none' stuff
        };

        _result: Result = @unionInit(Result, "none", 0),
        _done: Value(bool) = Value(bool).init(false),
        _started: Value(bool) = Value(bool).init(false),

        /// Check if future is finished.
        pub fn done(self: *const Self) bool {
            return self.*._done.load(.acquire);
        }

        /// Check if future has been started.
        pub fn started(self: *const Self) bool {
            return self.*._started.load(.acquire);
        }

        /// Gets the Future.Result -- blocks if result is forthcoming.
        /// To avoid blocking do `if (fut.done()) { //use result }`
        pub fn get(self: *const Self) Result {
            while (!self.done()) {}
            return self.*._result;
        }

        /// Gets unwrapped result T or error -- blocks if result is forthcoming.
        /// To avoid blocking do `if (fut.done()) { //use result }`
        pub fn unwrap(self: *const Self) !T {
            while (!self.done()) {}
            switch (self._result) {
                .ok => |ok| {
                    return ok;
                },
                .err => |err| {
                    return err;
                },
                .none => |_| {
                    return error.NoneValue;
                }, // TODO: remove 'none' stuff
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

            // maybe: spawn on heap and allow `var fut = Future(T).init(..);`?
            const run_args = .{ self, pFn, pArgs };
            pool.spawn(run, run_args) catch |err| {
                self._result = Result{ .err = err };
                self._done.store(true, .release);
            };
            self._started.store(true, .release);
            return;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            // TODO: let tasks be cancelable and let Future deinit whenever
            assert(true == self.done());
            if (.ok == self._result) {
                allocator.free(self.*._result.ok);
            }
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
    fut_i32.init(&pool, Helper.add_i32, .{ 2, 40 });
    while (!fut_i32.done()) {}
    const result = fut_i32.get();
    switch (result) {
        .ok => |ok| {
            try testing.expect(42 == ok);
        },
        else => {
            unreachable;
        },
    }
}

test "blocking get" {
    const Helper = struct {
        pub fn wait(milliseconds: u64) !bool {
            std.time.sleep(milliseconds * 1_000_000);
            return true;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var pool: Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var fut_bool = Future(bool){};
    fut_bool.init(&pool, Helper.wait, .{1000});
    const value = fut_bool.unwrap() catch unreachable;
    try testing.expect(true == value);
}

test "deinit" {
    const Helper = struct {
        pub fn alloc(allocator: Allocator, comptime T: type, n: usize) ![]T {
            return try allocator.alloc(T, n);
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var pool: Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var fut_buf = Future([]u8){};
    fut_buf.init(&pool, Helper.alloc, .{ allocator, u8, @sizeOf(usize) * 64 });
    defer fut_buf.deinit(allocator);

    const result = fut_buf.get();
    try testing.expect(.ok == result);
}
