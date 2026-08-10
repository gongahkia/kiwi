LUAJIT ?= luajit

export LUA_PATH := src/?.lua;src/?/init.lua;;
export KIWI_ROOT := $(CURDIR)

.PHONY: bootstrap native terminfo run demo text-demo text-corpus-demo text-corpus-review slug-feasibility timestamp-probe gpu-timing-smoke kitty-graphics-smoke budget-smoke replay vttest conformance-evidence test test-fuzz fuzz test-unicode generate-unicode test-pty smoke bench bench-burst bench-text bench-write bench-text-stress profile-text bench-compare check clean

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

text-corpus-demo: native terminfo
	KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-240} $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- $(LUAJIT) src/kiwi/bench/text_corpus_child.lua

timestamp-probe: native terminfo
	KIWI_TIMESTAMP_PROBE=1 KIWI_MAX_FRAMES=1 $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- /bin/true

gpu-timing-smoke: native terminfo
	KIWI_GPU_TIMESTAMPS=1 KIWI_GPU_TIMESTAMPS_REPORT=1 KIWI_MAX_FRAMES=10 $(LUAJIT) src/kiwi/app/main.lua -- /usr/bin/yes

kitty-graphics-smoke: native terminfo
	KIWI_GPU_TIMESTAMPS=1 KIWI_GPU_TIMESTAMPS_REPORT=1 KIWI_MAX_FRAMES=$${KIWI_MAX_FRAMES:-120} $(LUAJIT) src/kiwi/app/main.lua --no-extensions -- ./script/kitty-image-demo-child

budget-smoke: native terminfo
	KIWI_PASS_BUDGETS=1 KIWI_PASS_BUDGETS_REPORT=1 KIWI_RENDER_EXTENSIONS=tests.fixture_budget_extension KIWI_MAX_FRAMES=10 $(LUAJIT) src/kiwi/app/main.lua -- /usr/bin/yes

replay:
	$(LUAJIT) src/kiwi/replay.lua $(REPLAY)

vttest: native terminfo
	@command -v vttest >/dev/null || { echo "vttest is not installed; install it, then run make vttest in an interactive graphical session." >&2; exit 2; }
	$(LUAJIT) src/kiwi/app/main.lua -- vttest

conformance-evidence: native terminfo
	./script/conformance-evidence

test:
	$(LUAJIT) src/kiwi/test.lua

test-fuzz:
	$(LUAJIT) src/kiwi/test_fuzz.lua

fuzz:
	KIWI_FUZZ_CASES=4096 KIWI_FUZZ_MAX_BYTES=1024 $(LUAJIT) src/kiwi/test_fuzz.lua

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

text-corpus-review:
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text_corpus.lua

slug-feasibility:
	./script/slug-feasibility-probe

bench-write: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/write.lua

bench-text-stress: native
	mkdir -p bench/results
	$(LUAJIT) src/kiwi/bench/text_stress.lua

profile-text:
	mkdir -p bench/profiles
	./script/profile-text

bench-compare:
	./script/compare-bench "$(BASELINE)" "$(CANDIDATE)"

check: test test-fuzz test-pty terminfo
	./script/check

clean:
	./script/clean
