local ffi = require("ffi")

ffi.cdef[[
typedef unsigned char GifByteType;
typedef unsigned short GifWord;
typedef int GifBooleanType;
typedef struct {
  GifByteType Red;
  GifByteType Green;
  GifByteType Blue;
} GifColorType;
typedef struct {
  int ColorCount;
  int BitsPerPixel;
  GifBooleanType SortFlag;
  GifColorType *Colors;
} ColorMapObject;
typedef struct {
  int Left;
  int Top;
  int Width;
  int Height;
  GifBooleanType Interlace;
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
  GifByteType SBackGroundColor;
  GifByteType AspectByte;
  ColorMapObject *SColorMap;
  int ImageCount;
  SavedImage *SavedImages;
} GifFileType;
typedef int (*InputFunc)(GifFileType *GifFile, GifByteType *GifByte, int GifSize);
GifFileType *DGifOpen(void *UserPtr, InputFunc ReadFunc, int *Error);
int DGifSlurp(GifFileType *GifFile);
int DGifCloseFile(GifFileType *GifFile, int *Error);
]]

local loaded, library = pcall(ffi.load, "gif")
if not loaded then
  loaded, library = pcall(ffi.load, "libgif.so.7")
end
if not loaded then
  error("Unable to load giflib. Install giflib-devel (Fedora): " .. tostring(library))
end

local Gif = {}

function Gif.with_file(bytes, callback)
  local cursor = { bytes = bytes, offset = 1 }
  local reader = ffi.cast("InputFunc", function(_, destination, requested)
    if requested <= 0 then return 0 end
    local remaining = #cursor.bytes - cursor.offset + 1
    if remaining <= 0 then return 0 end
    local count = math.min(requested, remaining)
    ffi.copy(destination, cursor.bytes:sub(cursor.offset, cursor.offset + count - 1), count)
    cursor.offset = cursor.offset + count
    return count
  end)
  local error_code = ffi.new("int[1]")
  local file = library.DGifOpen(nil, reader, error_code)
  if file == nil then
    pcall(reader.free, reader)
    return nil, "gif-open"
  end
  if library.DGifSlurp(file) == 0 then
    library.DGifCloseFile(file, error_code)
    pcall(reader.free, reader)
    return nil, "gif-decode"
  end
  local result = { xpcall(callback, debug.traceback, file) }
  library.DGifCloseFile(file, error_code)
  pcall(reader.free, reader)
  if not result[1] then
    if type(result[2]) == "table" and type(result[2].reason) == "string" then return nil, result[2].reason end
    return nil, result[2]
  end
  return unpack(result, 2)
end

return Gif
