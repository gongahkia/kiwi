# 0047: Explicit context for hot terminal callbacks

Status: accepted.

The 10,000-line configuration benchmark failed its existing 4 MiB retained-Lua-
heap limit after rejecting font changes. Roughly 325 MiB remained beyond the
post-warmup baseline. Weak-reference diagnostics showed that the plans,
transactions, fonts and renderers were collected, but several candidate states
were still alive. Disabling JIT compilation removed the failure; flushing its
cache after the diagnostic released the remaining states.

Inspection with `jit.util.tracek` identified compiled function constants whose
upvalues reached candidate states, including palette traversal, cell projection,
blank-cell factories and reflow callbacks. This is consistent with LuaJIT's
[trace garbage-collection traversal](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_gc.c),
which marks collectable constants. The application must account for that
lifetime; this finding does not establish a compiler correctness defect.

Hot helpers now receive their operation context explicitly:

- Screen factories take an owner argument; transaction binding redirects that
  owner before adoption into the original state.
- Cell projections use one shared metatable and an owner field. Scrollback
  resolution likewise receives its owner explicitly.
- Palette traversal and the resize-fit check use shared functions.
- Reflow's segment/flush helpers take their document data as arguments. Optional
  callback context carries the state and destination screen without allocating
  callbacks that close over them. Existing context-free factories still work.

The implementation keeps JIT enabled and does not flush its cache, weaken the
memory gate, or clear a snapshot table that another consumer might reference.
State identity, independent staged cells, lazy palette history and commit/abort
semantics are preserved. Five native-free regression cases check collection
after palette rejection, full reflow rejection, height-only rejection, fast
width-resize rejection and successful adoption. They run first in both full and
core suites to exercise compilation from a fresh process. The regression fails
against the historical implementation.

This addresses discarded reload snapshots. It does not establish bounded
memory for every terminal callback or remove the cost of keeping both old and
candidate histories alive during a font change. Large-history font reloads
still allocate hundreds of MiB and can visibly pause the UI. Measurements and
qualification limits are in the [evidence record](../evidence/2026-10-26-reload-retention.md).
