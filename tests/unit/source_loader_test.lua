local source_loader = require("src.dsl.source_loader")

local function register(test)
  test.case("source loader reads the initial fixture through its boundary", function()
    local requested_path
    local source, err = source_loader.load("initial_policy", function(path)
      requested_path = path
      return "act = 1"
    end)

    test.equals(err, nil)
    test.equals(source, "act = 1")
    test.equals(requested_path, "content/doctrines/initial_policy.dsl")
  end)

  test.case("source loader rejects unregistered fixture identifiers", function()
    local called = false
    local source, err = source_loader.load("../outside", function()
      called = true
      return "act = 1"
    end)

    test.equals(source, nil)
    test.error_code(err, "unknown_source_fixture")
    test.equals(called, false)
  end)

  test.case("source loader returns structured reader errors", function()
    local source, err = source_loader.load("initial_policy", function()
      return nil, "missing fixture"
    end)
    test.equals(source, nil)
    test.error_code(err, "source_read_failed")

    source, err = source_loader.load("initial_policy", function()
      error("reader failure")
    end)
    test.equals(source, nil)
    test.error_code(err, "source_read_failed")
  end)
end

return register
