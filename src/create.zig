const std = @import("std");
const expectEqual = std.testing.expectEqual;
const zkwargs = @import("zkwargs");

const IterateTOpt = struct {
    pub fn by_ref(comptime _: ?type) ?type {
        return zkwargs.Default(false);
    }

    pub fn single_item(comptime _: ?type) ?type {
        return zkwargs.Default(false);
    }

    pub fn count(comptime _: ?type) ?type {
        return usize;
    }
};

fn IterateT(comptime ItemT: type, comptime single_item: bool, comptime has_count: bool, comptime by_ref: bool) type {
    if (single_item) {
        return SingleT(ItemT);
    }
    switch (@typeInfo(ItemT)) {
        .Pointer => |ptr| {
            return switch (ptr.size) {
                .One => SingleT(ItemT),
                .Many => if (has_count) PtrSpanT(ItemT, by_ref) else SingleT(ItemT),
                .Slice => return SpanT(ItemT, by_ref),
                else => @compileError("Unsupported pointer type " ++ @typeName(ItemT)),
            };
        },
        .Array, .Vector => {
            return SpanT(ItemT, by_ref);
        },
        .Struct => {
            if (@hasDecl(ItemT, "next")) {
                return PassThroughT(ItemT);
            } else if (@hasDecl(ItemT, "iterator")) {
                return GrabIteratorT(ItemT);
            }
            @compileError("Provided struct has neither `next` nor `iterator` method, and the `single_item` argument was not provided");
        },
        .Type, .ComptimeInt, .ComptimeFloat => @compileError("Comptime: TODO"),
        else => {
            return SingleT(ItemT);
        },
    }
    return void;
}

fn PassThroughT(comptime T: type) type {
    const TC = @typeInfo(@TypeOf(@field(T, "next"))).Fn.return_type.?;

    return struct {
        child: T,

        pub inline fn init(it: T, _: anytype) @This() {
            return .{ .child = it };
        }

        pub inline fn next(self: *@This()) TC {
            return self.child.next();
        }
    };
}

fn GrabIteratorT(comptime T: type) type {
    const ChildGenT = @typeInfo(@TypeOf(@field(T, "iterator"))).Fn.return_type.?;
    const TC = @typeInfo(@TypeOf(@field(ChildGenT, "next"))).Fn.return_type.?;

    return struct {
        child: ChildGenT,

        pub inline fn init(itgen: T, _: anytype) @This() {
            return .{ .child = itgen.iterator() };
        }

        pub inline fn next(self: *@This()) TC {
            return self.child.next();
        }
    };
}

fn PtrSpanT(comptime T: type, comptime by_ref: bool) type {
    const TC = @typeInfo(T).Pointer.child;
    const RTN = if (by_ref) *TC else TC;

    return struct {
        items: T,
        i: usize,
        len: usize,

        pub inline fn init(items: T, kwargs: anytype) @This() {
            return .{ .items = items, .i = 0, .len = kwargs.count };
        }

        pub inline fn next(self: *@This()) ?RTN {
            if (self.i >= self.len) {
                return null;
            } else {
                defer self.i += 1;
                if (by_ref) {
                    return &self.items[self.i];
                } else {
                    return self.items[self.i];
                }
            }
        }
    };
}

fn SpanT(comptime T: type, comptime by_ref: bool) type {
    const TC = switch (@typeInfo(T)) {
        .Pointer => |ptr| ptr.child,
        .Array => |arr| arr.child,
        .Vector => |vec| vec.child,
        else => @compileError("Passed non-array/slice to SpanT"),
    };
    const RTN = if (by_ref) *TC else TC;

    return struct {
        items: T,
        i: usize,
        len: usize,

        pub inline fn init(items: T, _: anytype) @This() {
            return switch (@typeInfo(T)) {
                .Pointer, .Array => .{ .items = items, .i = 0, .len = items.len },
                .Vector => |vec| .{ .items = items, .i = 0, .len = vec.len },
                else => @compileError("Passed non-array/slice to SpanT"),
            };
        }

        pub inline fn next(self: *@This()) ?RTN {
            if (self.i >= self.len) {
                return null;
            } else {
                defer self.i += 1;
                if (by_ref) {
                    return &self.items[self.i];
                } else {
                    return self.items[self.i];
                }
            }
        }
    };
}

fn SingleT(comptime T: type) type {
    return struct {
        item: T,
        yielded: bool,

        pub inline fn init(item: T, _: anytype) @This() {
            return .{ .item = item, .yielded = false };
        }

        pub inline fn next(self: *@This()) ?T {
            defer self.yielded = true;
            return if (self.yielded) null else self.item;
        }
    };
}

// item: s->next(), s->iterator(), arr, slice, ptr, vector, other (not comptime)
// kwargs: .{
//   by_ref: bool,
//   single_item: bool,
//   count: usize,
// }
//
// Wraps naturally iterable types in an inlined iterator interface. Other
// types produce an iterable yielding a single value. The kwargs allow
// you to, e.g., iterate over a [*]T by passing a count.
pub fn iterate(item: anytype, _kwargs: anytype) IterateT(
    @TypeOf(item),
    zkwargs.Options(IterateTOpt).parse(_kwargs).single_item,
    @hasField(@TypeOf(zkwargs.Options(IterateTOpt).parse(_kwargs)), "count"),
    zkwargs.Options(IterateTOpt).parse(_kwargs).by_ref,
) {
    var kwargs = zkwargs.Options(IterateTOpt).parse(_kwargs);
    const KT = @TypeOf(kwargs);
    const RtnT = IterateT(@TypeOf(item), kwargs.single_item, @hasField(KT, "count"), kwargs.by_ref);
    return RtnT.init(item, kwargs);
}

test "pointer/slice/vector magic" {
    var w: usize = 3;
    var w_iter = iterate(w, .{});
    try expectEqual(w, w_iter.next().?);
    var w_ptr_iter = iterate(&w, .{});
    try expectEqual(w, w_ptr_iter.next().?.*);

    var x: [*]usize = @ptrCast([*]usize, &w);
    var x_iter = iterate(x, .{ .count = 1 });
    try expectEqual(w, x_iter.next().?);
    var x_ptr_iter = iterate(x, .{ .count = 1, .by_ref = true });
    try expectEqual(w, x_ptr_iter.next().?.*);

    var y: []usize = x[0..1];
    var y_iter = iterate(y, .{});
    try expectEqual(w, y_iter.next().?);
    var y_ptr_iter = iterate(y, .{ .by_ref = true });
    try expectEqual(w, y_ptr_iter.next().?.*);

    var z: [1]usize = y[0..1].*;
    var z_iter = iterate(z, .{});
    try expectEqual(w, z_iter.next().?);
    var z_ptr_iter = iterate(z, .{ .by_ref = true });
    try expectEqual(w, z_ptr_iter.next().?.*);

    var a: @Vector(1, usize) = z;
    var a_iter = iterate(a, .{});
    try expectEqual(w, a_iter.next().?);
    var a_ptr_iter = iterate(a, .{ .by_ref = true });
    try expectEqual(w, a_ptr_iter.next().?.*);
}

const Bar = struct { i: usize };

test "single_item" {
    var w: usize = 3;
    var x = @ptrCast([*]usize, &w);
    var y: []usize = x[0..1];
    var z: [1]usize = x[0..1].*;

    var x_single_iter = iterate(x, .{ .single_item = true });
    try expectEqual(x[0], x_single_iter.next().?[0]);

    var y_single_iter = iterate(y, .{ .single_item = true });
    try expectEqual(y[0], y_single_iter.next().?[0]);

    var z_single_iter = iterate(z, .{ .single_item = true });
    try expectEqual(z[0], z_single_iter.next().?[0]);

    var a_single_iter = iterate(Bar{ .i = 42 }, .{ .single_item = true });
    try expectEqual(@as(usize, 42), a_single_iter.next().?.i);
}

const FooIterator = struct {
    pub fn iterator(_: anytype) @TypeOf(iterate(@as(usize, 8), .{})) {
        return iterate(@as(usize, 8), .{});
    }
};

test "next/iterator passthrough" {
    var foo = FooIterator{};
    var fooIter = foo.iterator();
    var passthrough = iterate(fooIter, .{});
    var magicCallIterator = iterate(foo, .{});

    // store the right value
    var x = fooIter.next().?;

    // sanity check that things are initialized
    try expectEqual(x, 8);

    // check that when we wrap something that's already
    // an iterator we get the same results
    try expectEqual(x, passthrough.next().?);

    // check that when we wrap something capable of returning
    // an iterator we use that and return its `next()` results
    try expectEqual(x, magicCallIterator.next().?);
}
