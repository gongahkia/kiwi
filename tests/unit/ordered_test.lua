local ordered = require("src.util.ordered")

return function(test)
  test.case("ordered.sorted_keys uses explicit numeric then string order", function()
    local keys, err = ordered.sorted_keys({ beta = 1, [10] = "ten", alpha = 2, [2] = "two" })
    test.equals(err, nil)
    test.equals(#keys, 4)
    test.equals(keys[1], 2)
    test.equals(keys[2], 10)
    test.equals(keys[3], "alpha")
    test.equals(keys[4], "beta")
  end)

  test.case("ordered.sorted_keys rejects unsupported key types", function()
    local keys, err = ordered.sorted_keys({ [true] = "invalid" })
    test.equals(keys, nil)
    test.error_code(err, "unsupported_key_type")
  end)
end
