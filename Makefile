.PHONY: benchmark check doctor format format-check glasshouse lint test type

.PHONY: benchmark-effects benchmark-renderer bootstrap check inspect lint run screenshot-scenarios test

bootstrap:
	zsh tools/bootstrap.sh

benchmark:
	uv run --extra dev python -m kiwi.cli benchmark examples/policies/typed_core.dtr tests/fixtures/minimal.kfixture.json --entry choose --arg true

glasshouse:
	uv run --extra dev python -m kiwi.glasshouse

format:
	uv run --extra dev ruff format .

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
