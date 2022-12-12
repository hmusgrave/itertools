### stuff from ziter
[ziter](https://github.com/Hejsil/ziter/blob/master/ziter.zig) looks nice enough at first glance. What follows is a brain-dump:

- testing utilities
- the length-hint thing actually looks really nice if you want to reify into a slice or anything
  - we'll definitely want to reify into slices as an option
    - looks like they call this "collect"
    - with zkwargs we can support arrays/allocators
- the "pipe" concept doesn't seem necessary; we can do the same with a bit more metaprogramming on a God object, sort of like LINQ's IEnumerable
- initializers
  - has next method -> noop
  - slice/arr -> span
  - has iterator method -> iterator()
  - I think we can do sentinel-terminated slices and whatnot pretty easily too. Will that take extra work?
  - range
    - rangeex (we can just use zkwargs)
  - spanbyref (we can just use zkwargs)
- chain (maybe we want a '.then()' method?)
  - ooh, or maybe also `.following()`
- utility mapping functions
  - dereference pointers
  - enumerate
    - enumerateex (zkwargs)
  - errInner (E!?T -> ?E!T)
- filterMap (haven't seen this much; is it a good primitive?)
- filter
- interleave
- map
  - method_map (it.method_map("first") would call `item.first()`)
- sliding_window (neat! gut reaction, can `scan` do this easily?)
  - Yeah, so this is a specialization of map/scan where we transform the sequence into
    slc/new/old and can combine that with the previous value to produce a new value
- repeat (this is dangerous; relies on cloning being safe -- probably mostly is safe the way we'll be using this, but it deserves a big scare warning)
- skip (we can write `islice` instead)
- takewhile
- take (also just `islice`)
- dedup (same as bash `uniq`)
  - really this is a groupby/reduce
  - one sort of groupby is to rely on a key function, but that makes it impossible to, e.g., look
    at a sequence like 112211 and group it into 1122, 11 because you only want to group into
    ascending sequences, at least not without other chicanery
  - you could support an edge comparator (group (1,1), (1,2), (2,2), but not (2,1))
  - you could support a general comparator on the whole group and the next element
  - zkwargs can take care of these options nicely
  - with cloning (and scare warnings), we can return iterators over groups by default
- unwrap
  - ha! I was already thinking about something like this. Basically you use null to short-circuit
    errors, then store the last error.
  - I think any code samples involving this should have an explicit `defer it.check()` or similar
    somewhere to encourage not forgetting about the error check. That ruins the fluent syntax
    a bit though.
  - Also need to think carefully about what happens when people wrap this and return an iterator
    based on it. This almost feels like something that needs to poison the rest of the types.
    Otherwise this code is only correct if decomposed exactly on `unwrap` boundaries.
  - going in the todo
- reduce
  - they call it `fold`
- utility reducing functions
  - all
  - any
  - count
- find

### python itertools (just the stuff we haven't covered yet)
- repeat (they call ziter's "repeat" "cycle")
- more reduce/scan helpers
  - accumulate
- chain.from_iterable
  - can we support this with type introspection on the normal chain? Like, if the type is incompatible, try to do a nested chain?
    - no, via pointers that could actually have ambiguous/wrong behavior
  - zkwargs on the ordinary chain
- compress
  - this takes two iterables, one of which is a mask, and uses it to select from the first
  - I think this is really a zip->map
- dropwhile
  - opposite of takewhile
  - do we want a stateful keep/discard primitive?
    - actually, that could just be `filter` with zkwargs
- tee
  - we're already thinking about `clone`. That actually seems safer here than python
- pairwise
  - sugar for `scan`
- starmap
  - name would need to change
  - could actually be really nice
- zip_longest
  - annoying to actually do with other primitives
  - could be zkwargs on zip
- combinatorics
  - product
  - permutations
  - combinations
  - combinations_with_replacement
    - zkwargs
- extras:
  - prepend
    - dunno if we want it, but it's worth noting that we probably want to be able to
      easily turn single values into iterators
    - related, it might be nice to coerce arguments into iterators if that would
      make sense
      - potential type ambiguity, but on the other hand they could write the long version
        in those cases
  - take
  - tabulate
  - tail
  - consume
  - nth
  - all_equal
    - also seems useful; I think we want a reducer of some sort as the default way to interact with groupbys
  - quantify
  - pad_none
  - ncycles
    - this one actually seems useful, use it as zkwargs on the repeat/cycle
  - dotproduct
    - zip+starmap
  - convolve
    - eh, we have windows
  - iter_index
    - enumerate -> filter -> map
  - flatten
    - this one is actually useful
    - zkwargs to flatten arbitrarily?
  - grouper
    - could just allow (with zkwargs) arbitrary context to our groupby?
    - also `batched`
  - triplewise
    - we can just make pairwise generic
    - really it's just a generic window
  - partition
    - if we don't mind double iteration this is cheap enough to do without allocation
  - before_and_after
    - just a variant of our groupby
  - subslices
  - powerset
  - unique_everseen
    - requires allocation
    - in general, do we want allocating/context variants of some other primitives like filtermap?
      - related, a contextual filtermap seems perfect here
  - tabulate

### linq methods (if we haven't seen it yet)
- generally we want a lot of ways to turn these into concrete types
  - toimmutablearray
  - toimmutabledictionary
  - toimmutablehashset
  - toimmutablelist
  - ...
- sort
  - I _kind of_ think they should reify it into a type, sort it themselves, and give us
    another iterator. We could wrap that convenience method though?
- append
- average
- cast
- contains
  - really a map/reduce -- can reduce short-circuit?
    - zkwargs
- except
  - set difference, requires allocation
- first (sugar for nth)
- intersect (requires allocation)
- join (optional allocation and hashmap)
- last (the islice methods in general with negative inputs might require a circular buffer)
- longcount
  - types for our aggregations?
  - zkwargs
- max
- min
- reverse
- selectmany
- sequenceequal
- single
- skip
- skiplast
- sum
- union (requires allocation)

### more linq
- backsert/insert (can replace prepend/append/before/after/then)
- evaluate (apply iter of functions to an object)
- lag
- lead
- ordered_merge
- pad
- partial_sort (groupby map sort?)
- partition (needs allocation)
- prescan
- shuffle
- split
- transpose (just zip()?)
- unfold (no clue what this is for yet)

# more itertools
- sliced
- constrained_batches
- distribute/divide/...
  - tee should allow slow (multi-iteration) or fast (allocation) based on provided parameters
  - ooh, can we use skip-lists or something to seek without much cloning?
    - no, not really, not in general
- spy
- peekable
- seekable
- stagger
- intersperse
- mark_ends
- repeat_last
- zip_broadcast (zkwargs?)
- convolve
- symmetric difference
- sample (must require allocation)
- run_length
- map_reduce
- all_unique
- minmax
- iequals
- first_true
- strip
- filter/map_err (how do we want to handle errors?)
- nth_or_last
- unique_in_window
- longest common prefix
- distinct combinations
- circular shifts
- partitions
- set_partitions
- product_index
- combination_index
- permutation_index
- random (permutation/combination/product/combination_with_replacement/...)
- nth (permutation/combination/product/combination_with_replacement/...)
- with_iter (we can use this to support auto-closing or auto-error-checking maybe?)
- locate
- rlocate
- replace
- numeric_range
- side_effect (dangerous since we might multi-iterate!!!)
- difference
- time_limited

### notes
- can we get away with inlining everything? with all the metaprogramming we're doing we might
  not have much in the way of duplicated functions anyway, so the ability to easily compile down
  into something efficient might be more important.
- length hints can come later. let's get the rest of the design right
- we definitely want `scan`
- mapping functions need some care with respect to nulls/errs. It needs to be convenient to handle errors properly (`while (try it.next()) |_| {}` seems reasonable), but we also want to be faithful to the original types (can we provide easy wrapper utilities?), and we also want to be explicit about, e.g., when a mapped function returns a null and the underlying data didn't, is that an actual null we're supposed to communicate, is that assumed unreachable, does that allow for easy short-circuiting (an implementation of takeWhile perhaps?)?
- `unwrap` probably needs to poison everything. defer it just like length hints for v1.
- linq and more-linq have added node/tree-related functions. Should we support those?

### more notes -- errs
- The interface is fundamentally lazy. Developers can only interact with an intermediate error by explicitly handling it inside the pipeline, doing something special at the `next` call, or examining some global state after the fact.
- Developers need to be able to handle it inside the pipeline to respond to handlable errors.
- To do that, the pipeline must be able to pass error unions on unimpeded.
- If we're using global state, we still need to know what to do with the intermediate errors (drop, stop, nullify, ...), so the inside of the pipeline is still complicated
- So the only thing global state might make nice is the ability to check for errors at the end of a computation. That's already easy though with other approaches; you could have `next` support the `while (try ...)` syntax by default, or if you need something more fine-grained you build that into the pipeline and check if the result is an error. The iterator doesn't need to know about that.
- So, errors are being handled internally and getting bubbled up to results (when an iterator is reduced), and to yielded valus (when next is called). To make that latter thing nice but unsurprising, we should just offer a transform that rotates the null/err types in the next values.

### more notes -- map/filter
- We can probably do isinstance and cast functionality pretty easily

### more notes -- sugar
- Till Zig supports lambdas we should accept single-function structs

### more notes -- type signatures
- We need some sort of Iterator(T) type to hold all the fluent methods.
- For that to work seamlessly without allocation, it needs to reference the underlying iterator.
- And again, for that to be known at compile time we need to know the type of the underlying iterator at comptime.
- The most straightforward solution is for T to be the type of the underlying iterator.
- This implies a linked list of types. Great for common cases, but what happens when people want to return these or pass them around? We're punting the problem down the road to somebody who will finally have to deal with the ambiguity.
- Orrrr, we can add a convenience method to let people wrap their iterator type into something more generic and break the type chain, with optional (default?) allocation.
