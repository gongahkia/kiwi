local ffi = require("ffi")

ffi.cdef[[
typedef struct png_control *png_controlp;
typedef unsigned int png_uint_32;
typedef signed int png_int_32;
typedef struct {
  png_controlp opaque;
  png_uint_32 version;
  png_uint_32 width;
  png_uint_32 height;
  png_uint_32 format;
  png_uint_32 flags;
  png_uint_32 colormap_entries;
  png_uint_32 warning_or_error;
  char message[64];
} png_image;
int png_image_begin_read_from_memory(png_image *image, const void *memory, size_t size);
int png_image_finish_read(png_image *image, const void *background, void *buffer, png_int_32 row_stride, void *colormap);
void png_image_free(png_image *image);
]]

local ok, libpng = pcall(ffi.load, "png16")
if not ok then
  ok, libpng = pcall(ffi.load, "png")
end
if not ok then
  error("Unable to load libpng. Install libpng-devel (Fedora): " .. tostring(libpng))
end

local Png = {}
Png.format_rgba = 3

function Png.decode_rgba(bytes, expected_width, expected_height, expected_bytes)
  local image = ffi.new("png_image")
  image.version = 1
  if libpng.png_image_begin_read_from_memory(image, bytes, #bytes) == 0 then
    return nil, "png-header"
  end

  if tonumber(image.width) ~= expected_width or tonumber(image.height) ~= expected_height then
    libpng.png_image_free(image)
    return nil, "png-dimensions"
  end

  image.format = Png.format_rgba
  local allocated, pixels = pcall(ffi.new, "uint8_t[?]", expected_bytes)
  if not allocated then
    libpng.png_image_free(image)
    return nil, "rgba-allocation"
  end

  local decoded = libpng.png_image_finish_read(image, nil, pixels, 0, nil) ~= 0
  libpng.png_image_free(image)
  if not decoded then return nil, "png-decode" end
  return pixels
end

return Png
