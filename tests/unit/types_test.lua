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

  test.case("function types are immutable and structurally comparable", function()
    local integer = assert(types.get("Int"))
    local boolean = assert(types.get("Bool"))
    local string_type = assert(types.get("String"))
    local first = assert(types.function_type(integer, boolean))
    local second = assert(types.function_type(integer, boolean))
    local different = assert(types.function_type(integer, string_type))

    test.equals(first.kind, "function")
    test.equals(first.argument, integer)
    test.equals(first.result, boolean)
    test.equals(types.equals(first, second), true)
    test.equals(types.equals(first, different), false)
    test.equals(types.describe(first), "Int -> Bool")

    local higher_order = assert(types.function_type(first, string_type))
    test.equals(types.describe(higher_order), "(Int -> Bool) -> String")
    local write_ok = pcall(function()
      first.result = string_type
    end)
    test.equals(write_ok, false)
  end)

  test.case("function types reject invalid components structurally", function()
    local boolean = assert(types.get("Bool"))
    local value, err = types.function_type({}, boolean)
    test.equals(value, nil)
    test.error_code(err, "invalid_function_argument_type")

    value, err = types.function_type(boolean, {})
    test.equals(value, nil)
    test.error_code(err, "invalid_function_result_type")
  end)

  test.case("union types represent Option Result and selected domain unions", function()
    local integer = assert(types.get("Int"))
    local boolean = assert(types.get("Bool"))
    local option_integer = assert(types.union_type("Option", { integer }))
    local option_boolean = assert(types.union_type("Option", { boolean }))
    local result = assert(types.union_type("Result", { integer, boolean }))
    local stance = assert(types.get("Stance"))

    test.equals(option_integer.kind, "union")
    test.equals(option_integer.definition.name, "Option")
    test.equals(option_integer.arguments[1], integer)
    test.equals(types.equals(option_integer, option_boolean), false)
    test.equals(types.describe(option_integer), "Option Int")
    test.equals(types.describe(result), "Result Int Bool")
    test.equals(stance.kind, "union")
    test.equals(types.describe(stance), "Stance")
  end)

  test.case("union constructors retain stable declared order", function()
    local option = assert(types.union_type("Option", { assert(types.get("Int")) }))
    local stance = assert(types.get("Stance"))
    local urgency = assert(types.get("Urgency"))
    local contact_class = assert(types.get("ContactClass"))

    test.equals(table.concat(types.constructors(option), ","), "None,Some")
    test.equals(table.concat(types.constructors(stance), ","), "Standing,Crouched,Prone")
    test.equals(table.concat(types.constructors(urgency), ","), "Low,Normal,High,Critical")
    test.equals(
      table.concat(types.constructors(contact_class), ","),
      "Unknown,Civilian,Hostile,Friendly"
    )
  end)

  test.case("union types reject unknown names arity and mutable arguments", function()
    local integer = assert(types.get("Int"))
    local value, err = types.union_type("Unknown", {})
    test.equals(value, nil)
    test.error_code(err, "unknown_union_type")

    value, err = types.union_type("Option", {})
    test.equals(value, nil)
    test.error_code(err, "invalid_union_arity")

    value, err = types.union_type("Option", { {} })
    test.equals(value, nil)
    test.error_code(err, "invalid_union_argument_type")

    local option = assert(types.union_type("Option", { integer }))
    local write_ok = pcall(function()
      option.arguments[1] = assert(types.get("Bool"))
    end)
    test.equals(write_ok, false)
  end)
end

return register
