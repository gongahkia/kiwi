local ffi = require("ffi")

ffi.cdef[[
typedef unsigned char GifByteType;
typedef int GifWord;
typedef struct {
  GifByteType Red;
  GifByteType Green;
  GifByteType Blue;
} GifColorType;
typedef struct {
  int ColorCount;
  int BitsPerPixel;
  bool SortFlag;
  GifColorType *Colors;
} ColorMapObject;
typedef struct {
  GifWord Left;
  GifWord Top;
  GifWord Width;
  GifWord Height;
  bool Interlace;
  ColorMapObject *ColorMap;
} GifImageDesc;
typedef struct {
  int ByteCount;
  GifByteType *Bytes;
  int Function;
} ExtensionBlock;
typedef struct {
  GifImageDesc ImageDesc;
  GifByteType *RasterBits;
  int ExtensionBlockCount;
  ExtensionBlock *ExtensionBlocks;
} SavedImage;
typedef struct GifFileType {
  GifWord SWidth;
  GifWord SHeight;
  GifWord SColorResolution;
  GifWord SBackGroundColor;
  GifByteType AspectByte;
  ColorMapObject *SColorMap;
  int ImageCount;
  GifImageDesc Image;
  SavedImage *SavedImages;
} GifFileType;
GifFileType *DGifOpenFileHandle(int FileHandle, int *Error);
int DGifSlurp(GifFileType *GifFile);
int DGifCloseFile(GifFileType *GifFile, int *Error);
int memfd_create(const char *name, unsigned int flags);
int mkstemp(char *template);
int unlink(const char *path);
long write(int fd, const void *buffer, unsigned long count);
long lseek(int fd, long offset, int whence);
int close(int fd);
]]

local loaded, library = pcall(ffi.load, "gif")
if not loaded then
  loaded, library = pcall(ffi.load, "libgif.so.7")
end
if not loaded then
  error("Unable to load giflib. Install giflib-devel (Fedora): " .. tostring(library))
end

local Gif = {}

local function temporary_descriptor()
  if ffi.os ~= "OSX" then return ffi.C.memfd_create("kiwi-gif", 1) end
  local template = ffi.new("char[?]", #"/tmp/kiwi-gif-XXXXXX" + 1)
  ffi.copy(template, "/tmp/kiwi-gif-XXXXXX")
  local descriptor = ffi.C.mkstemp(template)
  if descriptor >= 0 then ffi.C.unlink(template) end
  return descriptor
end

function Gif.with_file(bytes, callback)
  local descriptor = temporary_descriptor()
  if descriptor < 0 then return nil, "gif-open" end
  local offset = 1
  while offset <= #bytes do
    local written = ffi.C.write(descriptor, bytes:sub(offset), #bytes - offset + 1)
    if written <= 0 then
      ffi.C.close(descriptor)
      return nil, "gif-read"
    end
    offset = offset + tonumber(written)
  end
  if ffi.C.lseek(descriptor, 0, 0) < 0 then
    ffi.C.close(descriptor)
    return nil, "gif-read"
  end
  local error_code = ffi.new("int[1]")
  local file = library.DGifOpenFileHandle(descriptor, error_code)
  if file == nil then return nil, "gif-open" end
  if library.DGifSlurp(file) == 0 then
    library.DGifCloseFile(file, error_code)
    return nil, "gif-decode"
  end
  local result = { xpcall(callback, debug.traceback, file) }
  library.DGifCloseFile(file, error_code)
  if not result[1] then
    if type(result[2]) == "table" and type(result[2].reason) == "string" then return nil, result[2].reason end
    return nil, result[2]
  end
  return unpack(result, 2)
end

return Gif
