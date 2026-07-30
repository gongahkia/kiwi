local prng = require("src.util.prng")

return function(test)
  test.case("prng has a stable xorshift32 sequence", function()
    local rng = assert(prng.new(1))
    test.equals(rng:next_u32(), 270369)
    test.equals(rng:next_u32(), 67634689)
  end)

  test.case("prng streams are reproducible and named", function()
    local left = assert(prng.new(99)):fork("weapon_spread")
    local right = assert(prng.new(99)):fork("weapon_spread")
    local other = assert(prng.new(99)):fork("perception_noise")
    test.equals(left:next_u32(), right:next_u32())
    test.truthy(left:next_u32() ~= other:next_u32())
  end)

  test.case("prng bounds integer output", function()
    local rng = assert(prng.new(7))
    for _ = 1, 32 do
      local value, err = rng:next_int(3, 7)
      test.equals(err, nil)
      test.truthy(value >= 3 and value <= 7)
    end
  end)

  test.case("prng rejects a zero seed", function()
    local rng, err = prng.new(0)
    test.equals(rng, nil)
    test.error_code(err, "invalid_seed")
  end)

  test.case("prng rejects non-finite ranges", function()
    local rng = assert(prng.new(1))
    local value, err = rng:next_int(0, math.huge)
    test.equals(value, nil)
    test.error_code(err, "invalid_range")
  end)
end
