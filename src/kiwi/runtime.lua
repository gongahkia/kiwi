-- A terminal's parser, layout and renderer share one compiled-code cache.
-- Older LuaJIT 2.1 builds default to 512 KiB; exhausting that cache flushes
-- every trace and repeatedly recompiles hot paths during sustained output.
-- Keep a finite 4 MiB ceiling without changing trace limits, optimization
-- flags, executable-memory protections, or an explicitly disabled JIT.
local Runtime = { machine_code_limit_kib = 4096 }
require("jit.opt").start("maxmcode=" .. Runtime.machine_code_limit_kib)
return Runtime
