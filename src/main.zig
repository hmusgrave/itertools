const std = @import("std");
const expectEqual = std.testing.expectEqual;
const create = @import("create.zig");
const zkwargs = @import("zkwargs");

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

fn ScanT(comptime ChildT: type, comptime _f_carry: anytype, comptime _f_rtn: anytype, comptime CarryT: type) type {
    const f_carry = ExtractFn(_f_carry);
    const f_rtn = ExtractFn(_f_rtn);

    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    const FInT = switch (@typeInfo(NextOptT)) {
        .Optional => |opt| opt.child,
        else => NextOptT,
    };

    const FOutT = @TypeOf(f_rtn(@as(CarryT, undefined), @as(FInT, undefined)));

    return struct {
        child: ChildT,
        carry: CarryT,

        pub inline fn init(child: anytype, carry: CarryT) @This() {
            return .{ .child = child, .carry = carry };
        }

        pub inline fn next(self: *@This()) ?FOutT {
            if (self.child.next()) |_val| {
                var val = _val;
                var rtn = f_rtn(self.carry, val);
                self.carry = f_carry(self.carry, val);
                return rtn;
            }
            return null;
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

fn InterleaveT(comptime FirstT: type, comptime SecondT: type) type {
    const T0 = @typeInfo(@TypeOf(FirstT.next)).Fn.return_type.?;
    const T1 = @typeInfo(@TypeOf(SecondT.next)).Fn.return_type.?;

    return struct {
        first: FirstT,
        second: SecondT,
        which: bool,

        pub inline fn init(first: FirstT, second: SecondT) @This() {
            return .{ .first = first, .second = second, .which = true };
        }

        pub inline fn next(self: *@This()) @TypeOf(@as(T0, undefined), @as(T1, undefined)) {
            if (self.which) {
                if (self.first.next()) |result| {
                    self.which = !self.which;
                    return result;
                }
                return self.second.next();
            } else {
                if (self.second.next()) |result| {
                    self.which = !self.which;
                    return result;
                }
                return self.first.next();
            }
        }
    };
}

fn FilterT(comptime BaseT: type, comptime _f: anytype) type {
    const f = ExtractFn(_f);
    const T0 = @typeInfo(@TypeOf(BaseT.next)).Fn.return_type.?;
    return struct {
        base: BaseT,

        pub inline fn init(base: BaseT) @This() {
            return .{ .base = base };
        }

        pub inline fn next(self: *@This()) ?T0 {
            while (self.base.next()) |val| {
                if (f(val)) {
                    return val;
                }
            }
            return null;
        }
    };
}

fn SkipT(comptime ChildT: type) type {
    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    return struct {
        child: ChildT,

        pub inline fn init(_child: anytype, count: usize) @This() {
            var child = _child;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                _ = child.next();
            }
            return .{ .child = child };
        }

        pub inline fn next(self: *@This()) ?NextOptT {
            return self.child.next();
        }
    };
}

const RepeatTOptions = struct {
    pub fn n(comptime _: ?type) type {
        return usize;
    }
};

fn RepeatT(comptime ChildT: type, comptime KwargsT: type) type {
    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    if (@hasField(KwargsT, "n")) {
        return struct {
            initial: ChildT,
            child: ChildT,
            loop_i: usize,
            loop_count: usize,

            pub inline fn init(child: anytype, loop_count: usize) @This() {
                return .{ .initial = child, .child = child, .loop_i = 0, .loop_count = loop_count };
            }

            pub inline fn next(self: *@This()) NextOptT {
                if (self.loop_i >= self.loop_count)
                    return null;
                if (self.child.next()) |val| {
                    return val;
                } else {
                    self.child = self.initial;
                    self.loop_i += 1;
                    if (self.loop_i < self.loop_count) {
                        var rtn = self.child.next();
                        if (rtn == null) {
                            self.child = self.initial;
                            self.loop_i += 1;
                        }
                        return rtn;
                    } else {
                        return null;
                    }
                }
            }
        };
    } else {
        return struct {
            initial: ChildT,
            child: ChildT,

            pub inline fn init(child: anytype) @This() {
                return .{ .initial = child, .child = child };
            }

            pub inline fn next(self: *@This()) NextOptT {
                if (self.child.next()) |val| {
                    return val;
                } else {
                    self.child = self.initial;
                    return self.child.next();
                }
            }
        };
    }
}

fn ReduceT(comptime ChildT: type, comptime _f: anytype) type {
    const f = ExtractFn(_f);
    const T0 = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;
    const FInT = switch (@typeInfo(T0)) {
        .Optional => |opt| opt.child,
        else => T0,
    };

    const FOutT = @TypeOf(f(@as(FInT, undefined), @as(FInT, undefined)));

    return struct {
        child: ChildT,
        finished: bool,
        carry: FInT,

        pub inline fn init(child: anytype, carry: anytype) @This() {
            return .{ .child = child, .finished = false, .carry = carry };
        }

        pub inline fn next(self: *@This()) ?FOutT {
            if (self.finished) {
                return null;
            }
            while (self.child.next()) |next_val| {
                self.carry = f(self.carry, next_val);
            }
            self.finished = true;
            return self.carry;
        }
    };
}

fn TakewhileT(comptime ChildT: type, comptime _f: anytype) type {
    const f = ExtractFn(_f);

    const NextOptT = @typeInfo(@TypeOf(ChildT.next)).Fn.return_type.?;

    return struct {
        child: ChildT,
        should_stop: bool,

        pub inline fn init(child: anytype) @This() {
            return .{ .child = child, .should_stop = false };
        }

        pub inline fn next(self: *@This()) NextOptT {
            if (self.should_stop)
                return null;
            if (self.child.next()) |inp| {
                if (f(inp))
                    return inp;
            }
            self.should_stop = true;
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

        pub inline fn interleave(self: @This(), other: anytype) IteratorT(InterleaveT(@This(), @TypeOf(other))) {
            return Iterator(InterleaveT(@This(), @TypeOf(other)).init(self, other));
        }

        pub inline fn filter(self: @This(), comptime filter_fn: anytype) IteratorT(FilterT(@This(), filter_fn)) {
            return Iterator(FilterT(@This(), filter_fn).init(self));
        }

        pub inline fn skip(self: @This(), n: usize) IteratorT(SkipT(@This())) {
            return Iterator(SkipT(@This()).init(self, n));
        }

        pub inline fn take_while(self: @This(), comptime f: anytype) IteratorT(TakewhileT(@This(), f)) {
            return Iterator(TakewhileT(@This(), f).init(self));
        }

        pub inline fn repeat(self: @This(), _kwargs: anytype) IteratorT(RepeatT(@This(), @TypeOf(zkwargs.Options(RepeatTOptions).parse(_kwargs)))) {
            var kwargs = zkwargs.Options(RepeatTOptions).parse(_kwargs);
            if (@hasField(@TypeOf(kwargs), "n")) {
                return Iterator(RepeatT(@This(), @TypeOf(kwargs)).init(self, kwargs.n));
            } else {
                return Iterator(RepeatT(@This(), @TypeOf(kwargs)).init(self));
            }
        }

        pub inline fn scan(self: @This(), comptime f_carry: anytype, comptime f_rtn: anytype, carry: anytype) IteratorT(ScanT(@This(), f_carry, f_rtn, @TypeOf(carry))) {
            return Iterator(ScanT(@This(), f_carry, f_rtn, @TypeOf(carry)).init(self, carry));
        }

        pub inline fn reduce(self: @This(), comptime f: anytype, initial: anytype) IteratorT(ReduceT(@This(), f)) {
            return Iterator(ReduceT(@This(), f).init(self, initial));
        }
    };
}

pub fn Iterator(child: anytype) IteratorT(@TypeOf(child)) {
    return IteratorT(@TypeOf(child)).init(child);
}

// TODO: This should be the main entrypoint. Clean everything up around this function.
pub fn iterate(child: anytype, kwargs: anytype) @TypeOf(Iterator(create.iterate(child, kwargs))) {
    return Iterator(create.iterate(child, kwargs));
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

test "interleave" {
    var it = Iterator(TestIter.init(3))
        .interleave(TestIter.init(2));
    var results = [_]usize{ 3, 2, 2, 1, 1, 0, 0 };
    var i: usize = 0;
    while (it.next()) |val| : (i += 1) {
        try expectEqual(results[i], val);
    }
}

const TestFilterIter = struct {
    done: bool,
    pub fn init() @This() {
        return .{ .done = false };
    }
    pub fn next(self: *@This()) ?usize {
        defer self.done = true;
        if (self.done)
            return null;
        return 3;
    }
};

test "filter" {
    var it = Iterator(TestFilterIter.init())
        .filter(struct {
        fn foo(x: usize) bool {
            return x % 2 == 1;
        }
    });
    var i: usize = 0;
    while (it.next()) |val| : (i += 1) {
        try expectEqual(val, 3);
    }
    try expectEqual(i, 1);
}

test "skip" {
    var iter = Iterator(TestIter.init(3));
    var skipped_iter = iter.skip(2);

    try expectEqual(skipped_iter.next(), 1);
    try expectEqual(skipped_iter.next(), 0);
    try expectEqual(skipped_iter.next(), @as(?usize, null));
}

test "take_while" {
    var iter = Iterator(TestIter.init(3))
        .take_while(struct {
        pub fn small(x: usize) bool {
            return x > 2;
        }
    });

    try expectEqual(iter.next(), 3);
    try expectEqual(iter.next(), @as(?usize, null));
}

test "repeat" {
    var iter = Iterator(TestIter.init(2)).repeat(.{});

    try expectEqual(iter.next(), 2);
    try expectEqual(iter.next(), 1);
    try expectEqual(iter.next(), 0);
    try expectEqual(iter.next(), 2);
    try expectEqual(iter.next(), 1);
    try expectEqual(iter.next(), 0);
    try expectEqual(iter.next(), 2);
    try expectEqual(iter.next(), 1);
    try expectEqual(iter.next(), 0);
}

test "repeat n" {
    var iter = Iterator(TestIter.init(2)).repeat(.{ .n = 2 });

    try expectEqual(iter.next(), 2);
    try expectEqual(iter.next(), 1);
    try expectEqual(iter.next(), 0);
    try expectEqual(iter.next(), 2);
    try expectEqual(iter.next(), 1);
    try expectEqual(iter.next(), 0);
    try expectEqual(iter.next(), @as(?usize, null));
}

test "scan" {
    var iter = iterate([_]usize{ 4, 3, 2, 1, 0 }, .{})
        .scan(struct {
        pub fn running_sum(carry: usize, cur: usize) usize {
            return carry + cur;
        }
    }, struct {
        pub fn add(carry: usize, cur: usize) usize {
            return carry + cur;
        }
    }, @as(usize, 0));

    try expectEqual(iter.next(), 4);
    try expectEqual(iter.next(), 7);
    try expectEqual(iter.next(), 9);
    try expectEqual(iter.next(), 10);
    try expectEqual(iter.next(), 10);
    try expectEqual(iter.next(), @as(?usize, null));
}

test "reduce" {
    var iter = iterate([_]usize{ 4, 3, 2, 1, 0 }, .{})
        .reduce(struct {
        pub fn add(carry: usize, cur: usize) usize {
            return carry + cur;
        }
    }, @as(usize, 0));
    try expectEqual(iter.next(), 10);
    try expectEqual(iter.next(), @as(?usize, null));
}
