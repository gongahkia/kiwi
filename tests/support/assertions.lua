local assertions = {}

function assertions.equal(expected, actual, context)
  if expected ~= actual then
    error(
      (context or "values differ")
        .. ": expected "
        .. tostring(expected)
        .. ", got "
        .. tostring(actual),
      2
    )
  end
end

function assertions.truthy(value, context)
  if not value then
    error(context or "expected truthy value", 2)
  end
end

function assertions.falsy(value, context)
  if value then
    error(context or "expected falsy value", 2)
  end
end

return assertions
