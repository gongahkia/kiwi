local ffi = require("ffi")

ffi.cdef[[
typedef struct GLFWwindow GLFWwindow;
typedef void (*GLFWframebuffersizefun)(GLFWwindow* window, int width, int height);
typedef void (*GLFWkeyfun)(GLFWwindow* window, int key, int scancode, int action, int mods);
typedef void (*GLFWcharfun)(GLFWwindow* window, unsigned int codepoint);
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
GLFWcharfun glfwSetCharCallback(GLFWwindow* window, GLFWcharfun callback);
void glfwSetWindowTitle(GLFWwindow* window, const char* title);
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
    release = 0,
    press = 1,
    repeat_action = 2,
    mod_shift = 0x0001,
    mod_control = 0x0002,
    mod_alt = 0x0004,
    key_escape = 256,
    key_enter = 257,
    key_tab = 258,
    key_backspace = 259,
    key_insert = 260,
    key_delete = 261,
    key_right = 262,
    key_left = 263,
    key_down = 264,
    key_up = 265,
    key_page_up = 266,
    key_page_down = 267,
    key_home = 268,
    key_end = 269,
    key_f2 = 291,
    key_f3 = 292,
    key_f4 = 293,
    key_f5 = 294,
  },
}
