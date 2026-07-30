local types = require("src.dsl.types")

local function register(test)
  test.case("type registry returns canonical primitive types", function()
    local integer = assert(types.get("Int"))
    local second_integer = assert(types.get("Int"))
    local float = assert(types.get("Float"))

    test.equals(integer.kind, "primitive")
    test.equals(integer.name, "Int")
    test.equals(integer, second_integer)
    test.equals(types.equals(integer, second_integer), true)
    test.equals(types.equals(integer, float), false)
  end)

  test.case("type registry keeps documented domain types distinct", function()
    local duration = assert(types.get("Duration"))
    local distance = assert(types.get("Distance"))
    local position = assert(types.get("Position"))

    test.equals(duration.kind, "domain")
    test.equals(distance.kind, "domain")
    test.equals(position.kind, "domain")
    test.equals(types.equals(duration, distance), false)
    test.equals(types.describe(position), "Position")
  end)

  test.case("type registry maps quantity literal units to domain types", function()
    test.equals(types.quantity_type("ms"), assert(types.get("Duration")))
    test.equals(types.quantity_type("m"), assert(types.get("Distance")))
    test.equals(types.quantity_type("deg"), assert(types.get("Angle")))

    local value, err = types.quantity_type("kg")
    test.equals(value, nil)
    test.error_code(err, "unknown_quantity_unit")
  end)

  test.case("type registry rejects unknown names and immutable types", function()
    local value, err = types.get("Dynamic")
    test.equals(value, nil)
    test.error_code(err, "unknown_type")

    local integer = assert(types.get("Int"))
    local write_ok = pcall(function()
      integer.name = "Float"
    end)
    test.equals(write_ok, false)
  end)
end

return register
