LUA ?= luajit
LOVE ?= love
STYLUA ?= stylua
LUA_FILES := $(shell find main.lua conf.lua src tests tools -type f -name '*.lua' -print | LC_ALL=C sort)

.PHONY: run test headless content fmt lint check smoke

run:
	$(LOVE) .

test:
	$(LUA) tests/test_runner.lua

headless:
	$(LUA) tools/headless_runner.lua

content:
	$(LUA) tools/content_validator.lua

fmt:
	$(STYLUA) $(LUA_FILES)

lint:
	$(STYLUA) --check $(LUA_FILES)

check: lint test headless content

smoke:
	$(LOVE) . --smoke
