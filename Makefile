LUAJIT ?= luajit
STYLUA ?= stylua
LOVE ?= love
TEST_SEED ?= 20260730

.PHONY: bootstrap check lint run test

bootstrap:
	zsh tools/bootstrap.sh

check: lint test

lint:
	$(STYLUA) --check main.lua conf.lua src tests tools

run:
	$(LOVE) .

test:
	STANCZYK_TEST_SEED="$(TEST_SEED)" $(LUAJIT) tools/test.lua
