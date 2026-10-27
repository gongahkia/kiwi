require('kiwi.runtime')
local System = require('kiwi.font.system')
local State = require('kiwi.terminal.state')
local Parser = require('kiwi.terminal.parser')
local Layout = require('kiwi.text.layout')
local Json = require('kiwi.bench.json')
local line = '\27[1;38;2;90;180;230m背景 café é Ελληνικά\27[0m \27[3m日本語\27[0m \27[4:3munderlined\27[0m\r\n'
local system = System.new({pixel_height=18, atlas={width=512,height=512,max_entries=1024}})
local state = State.new(72,22,{scrollback_limit=10000})
local parser, layout = Parser.new(state), Layout.new(system)
local count, observations = 0, {}
local batch = string.rep(line,32)
for _, checkpoint in ipairs({10016,20000,40000,80000}) do
 local started=os.clock()
 while count < checkpoint do
  parser:feed(batch)
  layout:update(state)
  count=count+32
 end
 local elapsed=os.clock()-started
 local before=collectgarbage('count')
 collectgarbage('collect')
 local after=collectgarbage('count')
 local observation={lines=count, history=state.scrollback:size(), before_collection_kib=before,
  retained_heap_kib=after, interval_cpu_seconds=elapsed,shape_entries=layout.shape_cache.count,
  shape_glyphs=layout.shape_cache.glyph_count,shape_text_bytes=layout.shape_cache.text_bytes}
 observations[#observations+1]=observation
 io.stdout:write(Json.encode(observation),'\n');io.stdout:flush()
end
layout:destroy();system:destroy()
