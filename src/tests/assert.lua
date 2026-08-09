local Assert = {}

function Assert.equal(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
  end
end

function Assert.truthy(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
end

function Assert.near(actual, expected, epsilon)
  if math.abs(actual - expected) > epsilon then
    error(string.format("expected %.8f near %.8f", actual, expected), 2)
  end
end

return Assert
