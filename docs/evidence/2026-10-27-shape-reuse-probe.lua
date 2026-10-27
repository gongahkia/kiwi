require('kiwi.runtime')
local System = require('kiwi.font.system')
local State = require('kiwi.terminal.state')
local Parser = require('kiwi.terminal.parser')
local Layout = require('kiwi.text.layout')
local Face = require('kiwi.font.face')
local line = '\27[1;38;2;90;180;230m背景 café é Ελληνικά\27[0m \27[3m日本語\27[0m \27[4:3munderlined\27[0m\r\n'
local system = System.new({pixel_height=18, atlas={width=512,height=512,max_entries=1024}})
local state = State.new(80,24,{scrollback_limit=10000})
local parser = Parser.new(state)
for _=1,10024 do parser:feed(line) end
local layout = Layout.new(system)
for _=1,20 do state.text_damage:mark_all(); layout:update(state) end
collectgarbage('collect')
local started = os.clock()
for _=1,200 do state.text_damage:mark_all(); layout:update(state) end
local elapsed = (os.clock()-started)*1000
collectgarbage('collect'); collectgarbage('stop')
local before = collectgarbage('count')
for _=1,20 do state.text_damage:mark_all(); layout:update(state) end
local allocation=collectgarbage('count')-before
collectgarbage('restart')
local calls, unique, keys = 0,0,{}
local original = Face.shape
Face.shape=function(self,text,options)
 calls=calls+1
 local key=self.id..':'..text
 if not keys[key] then keys[key]=true;unique=unique+1 end
 return original(self,text,options)
end
for _=1,20 do state.text_damage:mark_all(); layout:update(state) end
Face.shape=original
print(string.format('frames=200 cpu_ms=%.3f allocation_20_frames_kib=%.3f shape_calls_20_frames=%d unique_face_text=%d',elapsed,allocation,calls,unique))
layout:destroy(); system:destroy()
