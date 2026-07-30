local test = { cases = {} }

function test.case(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then
    error("test.case requires a name and function")
  end
  test.cases[#test.cases + 1] = { name = name, fn = fn }
end

function test.equals(actual, expected, message)
  if actual ~= expected then
    error(message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)), 2)
  end
end

function test.truthy(value, message)
  if not value then
    error(message or "expected truthy value", 2)
  end
end

function test.error_code(error_value, expected)
  test.equals(type(error_value), "table", "expected structured error")
  test.equals(error_value.code, expected, "unexpected error code")
end

function test.run()
  local failed = 0
  for _, case in ipairs(test.cases) do
    local ok, failure = xpcall(case.fn, debug.traceback)
    if ok then
      io.write("ok - " .. case.name .. "\n")
    else
      failed = failed + 1
      io.write("not ok - " .. case.name .. "\n" .. failure .. "\n")
    end
  end
  io.write(string.format("%d tests, %d failures\n", #test.cases, failed))
  return failed == 0 and 0 or 1
end

return test
