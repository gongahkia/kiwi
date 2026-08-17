local ffi = require("ffi")

ffi.cdef[[
typedef struct KiwiAccessibility KiwiAccessibility;
KiwiAccessibility *kiwi_accessibility_new(void *window);
void kiwi_accessibility_destroy(KiwiAccessibility *adapter);
int kiwi_accessibility_update(KiwiAccessibility *adapter, const char *text, size_t text_bytes, int32_t character_count, int32_t caret_offset, int32_t selection_start, int32_t selection_end, int focused, const char *title);
void kiwi_accessibility_poll(KiwiAccessibility *adapter);
int kiwi_accessibility_active(const KiwiAccessibility *adapter);
const char *kiwi_accessibility_bus_name(const KiwiAccessibility *adapter);
const char *kiwi_accessibility_last_error(void);
]]

local root = os.getenv("KIWI_ROOT") or "."
local library_path = os.getenv("KIWI_SURFACE_LIB") or root .. "/.build/native/libkiwi_surface.so"
local loaded, library = pcall(ffi.load, library_path)

local Accessibility = {}
Accessibility.__index = Accessibility

function Accessibility.new(window)
  if os.getenv("KIWI_ACCESSIBILITY") == "0" then return nil, "disabled by KIWI_ACCESSIBILITY=0" end
  if not loaded then return nil, "could not load the Kiwi native accessibility bridge: " .. tostring(library) end
  local adapter = library.kiwi_accessibility_new(window and window.handle or nil)
  if adapter == nil then return nil, ffi.string(library.kiwi_accessibility_last_error()) end
  return setmetatable({ adapter = adapter, library = library }, Accessibility)
end

function Accessibility:update(projection, title, focused)
  assert(type(projection) == "table" and type(projection.text) == "string", "AT-SPI update needs a text projection")
  assert(type(title) == "string" and not title:find("\0", 1, true), "AT-SPI title must be NUL-free")
  assert(type(focused) == "boolean", "AT-SPI focus state must be a boolean")
  local success = self.library.kiwi_accessibility_update(
    self.adapter,
    projection.text,
    #projection.text,
    projection.character_count,
    projection.caret_offset,
    projection.selection_start,
    projection.selection_end,
    focused and 1 or 0,
    title
  )
  if success == 0 then return nil, ffi.string(self.library.kiwi_accessibility_last_error()) end
  return true
end

function Accessibility:poll()
  self.library.kiwi_accessibility_poll(self.adapter)
end

function Accessibility:active()
  return self.library.kiwi_accessibility_active(self.adapter) ~= 0
end

function Accessibility:bus_name()
  return ffi.string(self.library.kiwi_accessibility_bus_name(self.adapter))
end

function Accessibility:destroy()
  if self.adapter ~= nil then
    self.library.kiwi_accessibility_destroy(self.adapter)
    self.adapter = nil
  end
end

return Accessibility
