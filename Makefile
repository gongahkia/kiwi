LUAJIT ?= luajit
STYLUA ?= stylua
LOVE ?= love
TEST_SEED ?= 20260730
FRAMES ?= 1000
EFFECT_FRAMES ?= 30
WARMUP ?= 60
SAMPLES ?= 3

.PHONY: benchmark-effects benchmark-renderer bootstrap check inspect lint run screenshot-scenarios test

bootstrap:
	zsh tools/bootstrap.sh

benchmark-renderer:
	$(LUAJIT) tools/benchmark_renderer.lua --fixtures clean --frames "$(FRAMES)" --warmup "$(WARMUP)" --samples "$(SAMPLES)"

benchmark-effects:
	$(LUAJIT) tools/benchmark_renderer.lua --fixtures clean,crt --frames "$(EFFECT_FRAMES)" --warmup "$(WARMUP)" --samples "$(SAMPLES)"
	$(LUAJIT) tools/benchmark_renderer.lua --fixtures clean,kinetic --frames "$(EFFECT_FRAMES)" --warmup "$(WARMUP)" --samples "$(SAMPLES)"
	$(LUAJIT) tools/benchmark_renderer.lua --fixtures clean,combined --frames "$(EFFECT_FRAMES)" --warmup "$(WARMUP)" --samples "$(SAMPLES)"
	$(LUAJIT) tools/benchmark_renderer.lua --fixtures clean,effects_disabled --frames "$(EFFECT_FRAMES)" --warmup "$(WARMUP)" --samples "$(SAMPLES)"
	$(LUAJIT) tools/benchmark_renderer.lua --fixtures clean,quarantined --frames "$(EFFECT_FRAMES)" --warmup "$(WARMUP)" --samples "$(SAMPLES)"

check: lint test

lint:
	$(STYLUA) --check main.lua conf.lua src tests tools

run:
	$(LOVE) .

screenshot-scenarios:
	$(LUAJIT) tools/validate_screenshot_scenarios.lua

inspect:
	$(LUAJIT) tools/inspect_recording.lua "$(RECORDING)"

test:
	STANCZYK_TEST_SEED="$(TEST_SEED)" $(LUAJIT) tools/test.lua
