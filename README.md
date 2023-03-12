# itertools (non-functional, shelved for now)

tools for iterators in Zig

## Purpose

Iterators are a common enough pattern that it'd be nice to make them pleasant and fast. With liberal use of metaprogramming and inline evaluation we should be able to create an iteration library with a fluent syntax and minimal runtime overhead.

## Status

This is still in the ideation phase and very subject to change. It's missing basic tools you would expect from even the simplest of iteration libraries.

## TODO

I'm shelving this for a bit to think about return type inference. Most of the benefits from this come from the fact that it's operating on types rather than on values, and all the problems are coming from mixing those two. If we could move the fluent syntax to operate on types rather than values that would be immensely beneficial. Then just have a single `init` or other entrypoint to start using the thing.
