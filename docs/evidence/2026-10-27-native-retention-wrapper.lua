-- Diagnostic launcher only: forces GC at the first full-history post-warmup
-- observation and at the final observation while the native app is still live.
-- Its latency/resource results MUST NOT qualify an ordinary no-forced-GC soak.
require('kiwi.runtime')
local Sustained = require('kiwi.bench.sustained')
local Json = require('kiwi.bench.json')
local Metrics = require('kiwi.bench.process_metrics')
local original = Sustained.observe
local captured = false
Sustained.observe = function(self, now, rss, heap, cpu, final, history)
  local result = original(self, now, rss, heap, cpu, final, history)
  if (not captured and history and history.retained == history.limit) or final then
    local label = captured and 'final' or 'initial'
    captured = true
    local started = Metrics.monotonic_seconds()
    local before = collectgarbage('count')
    collectgarbage('collect')
    local after = collectgarbage('count')
    local elapsed = Metrics.monotonic_seconds()-started
    local item = { checkpoint=label, heap_before_kib=before, heap_after_kib=after,
      collection_seconds=elapsed, at=now, history=history,
      rss_before_kib=rss, rss_after_kib=Metrics.resident_kib() }
    io.stdout:write('KIWI_RETENTION_DIAGNOSTIC ',Json.encode(item),'\n');io.stdout:flush()
  end
  return result
end
local main = assert(arg[1])
dofile(main)
