local Errors = require("runtime.errors")

local Policy = {}

Policy.contract = {
  compare = "compare(measured, baseline) -> comparison | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function finite_nonnegative(value, name)
  if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
    return config_error(name .. " must be a finite non-negative number")
  end
  return value
end

local function counts(value, name)
  if type(value) ~= "table" then
    return config_error(name .. " must be a table")
  end
  local result = {}
  for _, field in ipairs({
    "canvases",
    "effect_instances",
    "fonts",
    "shader_compilations",
    "shaders",
    "temporary_canvases",
  }) do
    local count, count_error = finite_nonnegative(value[field], name .. " " .. field)
    if not count then
      return nil, count_error
    end
    if count % 1 ~= 0 then
      return config_error(name .. " " .. field .. " must be an integer")
    end
    result[field] = count
  end
  return result
end

local function measurement(value, name)
  if type(value) ~= "table" then
    return config_error(name .. " must be a table")
  end
  local frame_time_us, frame_error = finite_nonnegative(value.frame_time_us, name .. " frame time")
  if not frame_time_us or frame_time_us == 0 then
    return nil, frame_error or Errors.new("config_error", name .. " frame time must be positive")
  end
  local bytes_per_frame, bytes_error =
    finite_nonnegative(value.bytes_per_frame, name .. " bytes per frame")
  if not bytes_per_frame then
    return nil, bytes_error
  end
  local resources, resources_error = counts(value.resources, name .. " resources")
  if not resources then
    return nil, resources_error
  end
  return {
    bytes_per_frame = bytes_per_frame,
    frame_time_us = frame_time_us,
    resources = resources,
  }
end

function Policy.compare(measured, baseline)
  local actual, actual_error = measurement(measured, "benchmark measurement")
  if not actual then
    return nil, actual_error
  end
  local expected, expected_error = measurement(baseline, "benchmark baseline")
  if not expected then
    return nil, expected_error
  end
  local reasons = {}
  if actual.frame_time_us > expected.frame_time_us * 1.15 + 0.000001 then
    reasons[#reasons + 1] = "frame_time"
  end
  local allocation_limit = expected.bytes_per_frame + math.max(expected.bytes_per_frame * 0.15, 128)
  if actual.bytes_per_frame > allocation_limit + 0.000001 then
    reasons[#reasons + 1] = "bytes_per_frame"
  end
  for _, field in ipairs({ "canvases", "effect_instances", "fonts", "shaders" }) do
    if actual.resources[field] > expected.resources[field] then
      reasons[#reasons + 1] = "retained_" .. field
    end
  end
  if actual.resources.shader_compilations > 0 then
    reasons[#reasons + 1] = "shader_compilations"
  end
  if actual.resources.temporary_canvases > 0 then
    reasons[#reasons + 1] = "temporary_canvases"
  end
  return {
    allocation_limit = allocation_limit,
    passed = #reasons == 0,
    reasons = reasons,
  }
end

return Policy
