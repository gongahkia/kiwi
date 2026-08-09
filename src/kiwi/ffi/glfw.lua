local ffi = require("ffi")

ffi.cdef[[
typedef struct GLFWwindow GLFWwindow;
typedef void (*GLFWframebuffersizefun)(GLFWwindow* window, int width, int height);
typedef void (*GLFWkeyfun)(GLFWwindow* window, int key, int scancode, int action, int mods);
int glfwInit(void);
void glfwTerminate(void);
void glfwWindowHint(int hint, int value);
GLFWwindow* glfwCreateWindow(int width, int height, const char* title, void* monitor, GLFWwindow* share);
void glfwDestroyWindow(GLFWwindow* window);
void glfwPollEvents(void);
void glfwWaitEventsTimeout(double timeout);
int glfwWindowShouldClose(GLFWwindow* window);
void glfwSetWindowShouldClose(GLFWwindow* window, int value);
void glfwGetFramebufferSize(GLFWwindow* window, int* width, int* height);
void glfwGetWindowContentScale(GLFWwindow* window, float* xscale, float* yscale);
GLFWframebuffersizefun glfwSetFramebufferSizeCallback(GLFWwindow* window, GLFWframebuffersizefun callback);
GLFWkeyfun glfwSetKeyCallback(GLFWwindow* window, GLFWkeyfun callback);
double glfwGetTime(void);
int glfwGetPlatform(void);
const char* glfwGetError(int* code);
]]

local ok, glfw = pcall(ffi.load, "glfw")
if not ok then
  error("Unable to load GLFW. Install glfw-devel (Fedora) and run make bootstrap: " .. tostring(glfw))
end

return {
  lib = glfw,
  constants = {
    client_api = 0x00022001,
    no_api = 0,
    resizable = 0x00020003,
    yes = 1,
    no = 0,
    press = 1,
    key_escape = 256,
    key_f2 = 291,
    key_f3 = 292,
  },
}
