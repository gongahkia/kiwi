local hash = require("src.util.hash")

return function(test)
  test.case("hash uses the documented FNV-1a 32 algorithm", function()
    local digest = assert(hash.string("hello"))
    test.equals(digest, "4f9f2cab")
  end)

  test.case("hash is stable across insertion order", function()
    local left = assert(hash.of({ alpha = 1, beta = true }))
    local right = assert(hash.of({ beta = true, alpha = 1 }))
    test.equals(left, right)
    test.truthy(left:match("^[0-9a-f]+$") ~= nil)
    test.equals(#left, 8)
  end)
end
