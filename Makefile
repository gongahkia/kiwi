LUAJIT ?= luajit
STYLUA ?= stylua
LOVE ?= love
TEST_SEED ?= 20260730
FRAMES ?= 1000

.PHONY: benchmark-renderer bootstrap check inspect lint run test

bootstrap:
	zsh tools/bootstrap.sh

benchmark-renderer:
	$(LUAJIT) tools/benchmark_renderer.lua "$(FRAMES)"

check: lint test

lint:
	$(STYLUA) --check main.lua conf.lua src tests tools

run:
	$(LOVE) .

inspect:
	$(LUAJIT) tools/inspect_recording.lua "$(RECORDING)"

test:
	STANCZYK_TEST_SEED="$(TEST_SEED)" $(LUAJIT) tools/test.lua
