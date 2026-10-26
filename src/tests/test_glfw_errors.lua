local Assert = require("tests.assert")
local ffi = require("ffi")
local glfw = require("kiwi.ffi.glfw").lib
return {
  glfw_error_binding_returns_integer_code_and_pointer_description = function()
    -- This suite does not initialize GLFW. Reading its platform must yield
    -- NOT_INITIALIZED, and the diagnostic must be an actual valid C string.
    glfw.glfwGetError(nil)
    Assert.equal(glfw.glfwGetPlatform(), 0)
    local description = ffi.new("const char*[1]")
    Assert.equal(glfw.glfwGetError(description), 0x00010001)
    Assert.truthy(description[0] ~= nil)
    Assert.truthy(#ffi.string(description[0]) > 0)
    Assert.equal(glfw.glfwGetError(nil), 0)
  end,
}
