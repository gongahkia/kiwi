LUAJIT ?= luajit

export LUA_PATH := src/?.lua;src/?/init.lua;;
export KIWI_ROOT := $(CURDIR)

.PHONY: bootstrap native terminfo run demo text-demo replay vttest test test-unicode generate-unicode test-pty smoke bench bench-burst bench-text bench-text-stress bench-compare check clean

bootstrap:
	./script/bootstrap

native: bootstrap
	./script/build-native

terminfo: bootstrap
	./script/build-terminfo

run: native terminfo
	$(LUAJIT) src/kiwi/app/main.lua $(ARGS)

demo: native
	KIWI_DEMO=1 $(LUAJIT) src/kiwi/app/main.lua

text-demo: native terminfo
	KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-240} $(LUAJIT) src/kiwi/app/main.lua -- ./script/text-demo-child

replay:
	$(LUAJIT) src/kiwi/replay.lua $(REPLAY)

vttest: native terminfo
	@command -v vttest >/dev/null || { echo "vttest is not installed; install it, then run make vttest in an interactive graphical session." >&2; exit 2; }
	$(LUAJIT) src/kiwi/app/main.lua -- vttest

test:
	$(LUAJIT) src/kiwi/test.lua

test-unicode:
	$(LUAJIT) src/kiwi/test_unicode.lua

generate-unicode:
	./script/generate-unicode

test-pty: native
	$(LUAJIT) src/kiwi/test_pty.lua

smoke: native
	./script/smoke

bench:
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/main.lua

bench-burst: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/burst.lua

bench-text: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text.lua

bench-text-stress: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text_stress.lua

bench-compare:
	./script/compare-bench "$(BASELINE)" "$(CANDIDATE)"

check: test test-pty terminfo
	./script/check

clean:
	./script/clean
