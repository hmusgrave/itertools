const std = @import("std");
const expectEqual = std.testing.expectEqual;
const create = @import("create.zig");

test "create tests" {
    _ = create;
}

// Rules:
//   1. If next() outputs ?T, null always signals the end of values

fn ExtractFnT(comptime f: anytype) type {
    return switch (@typeInfo(@TypeOf(f))) {
        .Fn => @TypeOf(f),
        .Struct => |st| {
            inline for (st.decls) |decl| {
                return @TypeOf(@field(f, decl.name));
            }
        },
        .Type => {
            switch (@typeInfo(f)) {
                .Struct => |st| {
                    inline for (st.decls) |decl| {
                        return @TypeOf(@field(f, decl.name));
                    }
                },
                else => @compileError("Unsupported lambda type"),
            }
        },
        else => @compileError("Unsupported lambda type"),
    };
}

fn ExtractFn(comptime f: anytype) ExtractFnT(f) {
    return switch (@typeInfo(@TypeOf(f))) {
        .Fn => f,
        .Struct => |st| {
            inline for (st.decls) |decl| {
                return @field(f, decl.name);
            }
        },
        .Type => {
            switch (@typeInfo(f)) {
                .Struct => |st| {
                    inline for (st.decls) |decl| {
                        return @field(f, decl.name);
                    }
                },
                else => @compileError("Unsupported lambda type"),
            }
        },
        else => @compileError("Unsupported lambda type"),
    };
}

fn MapT(comptime ChildT: type, comptime _f: anytype) type {
    const f = ExtractFn(_f);

    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    const FInT = switch (@typeInfo(NextOptT)) {
        .Optional => |opt| opt.child,
        else => NextOptT,
    };

    // TODO:
    // If they have E!?T, do we really want to output ?E!?T
    const FOutT = @TypeOf(f(@as(FInT, undefined)));

    return struct {
        child: ChildT,

        pub inline fn init(child: anytype) @This() {
            return .{ .child = child };
        }

        pub inline fn next(self: *@This()) ?FOutT {
            var inp = self.child.next() orelse return null;
            return f(inp);
        }
    };
}

fn FilterMapT(comptime ChildT: type, comptime _f: anytype) type {
    const f = ExtractFn(_f);

    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    const FInT = switch (@typeInfo(NextOptT)) {
        .Optional => |opt| opt.child,
        else => NextOptT,
    };

    // TODO:
    // If they have E!?T, do we really want to output ?E!?T
    const FOutT = @TypeOf(f(@as(FInT, undefined)));

    // Simplifies remaining code, minor perf improvement
    // TODO: Name might be confusing in logs
    if (@typeInfo(FOutT) != .Optional)
        return MapT(ChildT, _f);

    return struct {
        child: ChildT,

        pub inline fn init(child: anytype) @This() {
            return .{ .child = child };
        }

        pub inline fn next(self: *@This()) FOutT {
            while (true) {
                var inp = self.child.next() orelse return null;
                if (f(inp)) |val|
                    return val;
            }
        }
    };
}

fn EnumerateT(comptime ChildT: type) type {
    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    const FInT = switch (@typeInfo(NextOptT)) {
        .Optional => |opt| opt.child,
        else => NextOptT,
    };

    const PairT = struct {
        i: usize,
        val: FInT,
    };

    return struct {
        child: ChildT,
        i: usize,

        pub inline fn init(child: anytype) @This() {
            return .{ .child = child, .i = 0 };
        }

        pub inline fn next(self: *@This()) ?PairT {
            if (self.child.next()) |val| {
                defer self.i += 1;
                return PairT{ .i = self.i, .val = val };
            }
            return null;
        }
    };
}

fn ChainT(comptime FirstT: type, comptime SecondT: type) type {
    const T0 = @typeInfo(@TypeOf(FirstT.next)).Fn.return_type.?;
    const T1 = @typeInfo(@TypeOf(SecondT.next)).Fn.return_type.?;

    return struct {
        first: FirstT,
        second: SecondT,
        finished_first: bool,

        pub inline fn init(first: FirstT, second: SecondT) @This() {
            return .{ .first = first, .second = second, .finished_first = false };
        }

        pub inline fn next(self: *@This()) @TypeOf(@as(T0, undefined), @as(T1, undefined)) {
            if (self.finished_first) {
                return self.second.next();
            } else if (self.first.next()) |result| {
                return result;
            } else {
                self.finished_first = true;
                return self.second.next();
            }
        }
    };
}

fn MethodMapT(comptime BaseT: type, comptime MethodName: []const u8) type {
    const T0 = @typeInfo(@typeInfo(@TypeOf(BaseT.next)).Fn.return_type.?).Optional.child;
    const RT = @typeInfo(@TypeOf(@field(T0, MethodName))).Fn.return_type.?;

    return struct {
        base: BaseT,

        pub inline fn init(base: BaseT) @This() {
            return .{ .base = base };
        }

        pub inline fn next(self: *@This()) ?RT {
            if (self.base.next()) |item| {
                var z = item;
                return @field(z, MethodName)();
            }
            return null;
        }
    };
}

pub fn IteratorT(comptime ChildT: type) type {
    // TODO: handle pointers and whatnot
    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    return struct {
        child: ChildT,

        pub inline fn init(child: anytype) @This() {
            return switch (@typeInfo(@TypeOf(child))) {
                .Pointer => .{ .child = child.* },
                else => .{ .child = child },
            };
        }

        pub inline fn next(self: *@This()) NextOptT {
            return self.child.next();
        }

        pub inline fn map(self: @This(), comptime f: anytype) IteratorT(MapT(@This(), f)) {
            return Iterator(MapT(@This(), f).init(self));
        }

        pub inline fn filter_map(self: @This(), comptime f: anytype) IteratorT(FilterMapT(@This(), f)) {
            return Iterator(FilterMapT(@This(), f).init(self));
        }

        pub inline fn enumerate(self: @This()) IteratorT(EnumerateT(@This())) {
            return Iterator(EnumerateT(@This()).init(self));
        }

        pub inline fn then(self: @This(), other: anytype) IteratorT(ChainT(@This(), @TypeOf(other))) {
            return Iterator(ChainT(@This(), @TypeOf(other)).init(self, other));
        }

        pub inline fn following(self: @This(), other: anytype) IteratorT(ChainT(@TypeOf(other), @This())) {
            return Iterator(ChainT(@TypeOf(other), @This()).init(other, self));
        }

        pub inline fn method_map(self: @This(), comptime MethodName: []const u8) IteratorT(MethodMapT(@This(), MethodName)) {
            return Iterator(MethodMapT(@This(), MethodName).init(self));
        }
    };
}

pub fn Iterator(child: anytype) IteratorT(@TypeOf(child)) {
    return IteratorT(@TypeOf(child)).init(child);
}

const TestIter = struct {
    val: ?usize,

    pub fn init(val: usize) @This() {
        return .{ .val = val };
    }

    pub fn next(self: *@This()) ?usize {
        defer {
            if (self.val) |v| {
                if (v == 0) {
                    self.val = null;
                } else {
                    self.val = v - 1;
                }
            }
        }
        return self.val;
    }
};

test "doesn't crash" {
    var it = Iterator(TestIter.init(3))
        .map(struct {
        fn add_one(x: anytype) @TypeOf(x) {
            return x + 1;
        }
    })
        .filter_map(struct {
        fn remove_odd_add_one(x: anytype) ?@TypeOf(x) {
            if (x & 1 == 1)
                return null;
            return x + 1;
        }
    })
        .enumerate();
    var i: usize = 0;
    while (it.next()) |z| : (i += 1) {
        if (i == 0) {
            try expectEqual(i, z.i);
            try expectEqual(@as(usize, 5), z.val);
        } else if (i == 1) {
            try expectEqual(i, z.i);
            try expectEqual(@as(usize, 3), z.val);
        } else {
            return error.TooManyIterations;
        }
    }
}

test "chain" {
    var it = Iterator(TestIter.init(3))
        .then(TestIter.init(2));
    var results = [_]usize{ 3, 2, 1, 0, 2, 1, 0 };
    var i: usize = 0;
    while (it.next()) |val| : (i += 1) {
        try expectEqual(results[i], val);
    }
}

test "following" {
    var it = Iterator(TestIter.init(2))
        .following(TestIter.init(3));
    var results = [_]usize{ 3, 2, 1, 0, 2, 1, 0 };
    var i: usize = 0;
    while (it.next()) |val| : (i += 1) {
        try expectEqual(results[i], val);
    }
}

const TestMethodIter = struct {
    const Rtn = struct {
        pub fn foo(_: *@This()) usize {
            return 42;
        }
    };

    done: bool,

    pub fn init() @This() {
        return .{ .done = false };
    }

    pub fn next(self: *@This()) ?Rtn {
        defer self.done = true;
        if (self.done)
            return null;
        return Rtn{};
    }
};

test "method_map" {
    var it = Iterator(TestMethodIter.init())
        .method_map("foo");
    var results = [_]usize{42};
    var i: usize = 0;
    while (it.next()) |val| : (i += 1) {
        try expectEqual(results[i], val);
    }
}
