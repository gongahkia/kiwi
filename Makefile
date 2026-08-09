LUAJIT ?= luajit

export LUA_PATH := src/?.lua;src/?/init.lua;;
export KIWI_ROOT := $(CURDIR)

.PHONY: bootstrap native run test test-pty smoke bench check clean

bootstrap:
	./script/bootstrap

native: bootstrap
	./script/build-native

run: native
	$(LUAJIT) src/kiwi/app/main.lua

test:
	$(LUAJIT) src/kiwi/test.lua

test-pty: native
	$(LUAJIT) src/kiwi/test_pty.lua

smoke: native
	./script/smoke

bench:
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/main.lua

check: test test-pty
	./script/check

clean:
	./script/clean
