LUAJIT ?= luajit

export LUA_PATH := src/?.lua;src/?/init.lua;;
export KIWI_ROOT := $(CURDIR)

.PHONY: bootstrap native run test smoke bench check clean

bootstrap:
	./script/bootstrap

native: bootstrap
	./script/build-native

run: native
	$(LUAJIT) src/kiwi/app/main.lua

test:
	$(LUAJIT) src/kiwi/test.lua

smoke: native
	./script/smoke

bench:
	$(LUAJIT) src/kiwi/bench/main.lua

check: test
	./script/check

clean:
	./script/clean
