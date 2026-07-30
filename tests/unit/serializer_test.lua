local serializer = require("src.util.serializer")

return function(test)
  test.case("serializer canonicalizes map key order", function()
    local encoded, err = serializer.encode({ z = 1, nested = { b = "x", a = false }, a = true })
    test.equals(err, nil)
    test.equals(encoded, '{"a":true,"nested":{"a":false,"b":"x"},"z":1}')
  end)

  test.case("serializer emits contiguous numeric tables as arrays", function()
    local encoded, err = serializer.encode({ "alpha", "beta" })
    test.equals(err, nil)
    test.equals(encoded, '["alpha","beta"]')
  end)

  test.case("serializer encodes empty tables as maps", function()
    local encoded, err = serializer.encode({})
    test.equals(err, nil)
    test.equals(encoded, "{}")
  end)

  test.case("serializer rejects cyclic tables", function()
    local value = {}
    value.self = value
    local encoded, err = serializer.encode(value)
    test.equals(encoded, nil)
    test.error_code(err, "cyclic_table")
  end)

  test.case("serializer rejects sparse arrays", function()
    local encoded, err = serializer.encode({ [1] = "a", [3] = "c" })
    test.equals(encoded, nil)
    test.error_code(err, "invalid_table_shape")
  end)
end
