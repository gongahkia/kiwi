local ffi = require("ffi")

ffi.cdef[[
typedef signed long FT_Long;
typedef unsigned long FT_ULong;
typedef signed long FT_Pos;
typedef signed long FT_Fixed;
typedef signed int FT_Int;
typedef signed int FT_Int32;
typedef unsigned int FT_UInt;
typedef signed short FT_Short;
typedef unsigned short FT_UShort;
typedef unsigned char FT_Byte;
typedef char FT_String;
typedef int FT_Error;
typedef struct FT_LibraryRec_* FT_Library;
typedef struct FT_FaceRec_* FT_Face;
typedef struct FT_GlyphSlotRec_* FT_GlyphSlot;
typedef struct FT_SizeRec_* FT_Size;
typedef struct FT_CharMapRec_* FT_CharMap;
typedef struct FT_DriverRec_* FT_Driver;
typedef struct FT_MemoryRec_* FT_Memory;
typedef struct FT_StreamRec_* FT_Stream;
typedef struct FT_Face_InternalRec_* FT_Face_Internal;
typedef struct FT_Slot_InternalRec_* FT_Slot_Internal;
typedef struct FT_SubGlyphRec_* FT_SubGlyph;
typedef void (*FT_Generic_Finalizer)(void* object);
typedef struct { void* data; FT_Generic_Finalizer finalizer; } FT_Generic;
typedef struct { FT_Pos xMin; FT_Pos yMin; FT_Pos xMax; FT_Pos yMax; } FT_BBox;
typedef struct { FT_Pos x; FT_Pos y; } FT_Vector;
typedef struct { FT_Pos width; FT_Pos height; FT_Pos horiBearingX; FT_Pos horiBearingY; FT_Pos horiAdvance; FT_Pos vertBearingX; FT_Pos vertBearingY; FT_Pos vertAdvance; } FT_Glyph_Metrics;
typedef struct { FT_UInt rows; FT_UInt width; FT_Int pitch; FT_Byte* buffer; FT_UShort num_grays; FT_Byte pixel_mode; FT_Byte palette_mode; void* palette; } FT_Bitmap;
typedef struct { FT_Short n_contours; FT_Short n_points; FT_Vector* points; FT_Byte* tags; FT_Short* contours; FT_Int flags; } FT_Outline;
typedef struct { void* head; void* tail; } FT_ListRec;
typedef struct FT_FaceRec_ {
  FT_Long num_faces; FT_Long face_index; FT_Long face_flags; FT_Long style_flags; FT_Long num_glyphs;
  FT_String* family_name; FT_String* style_name; FT_Int num_fixed_sizes; void* available_sizes;
  FT_Int num_charmaps; FT_CharMap* charmaps; FT_Generic generic; FT_BBox bbox;
  FT_UShort units_per_EM; FT_Short ascender; FT_Short descender; FT_Short height;
  FT_Short max_advance_width; FT_Short max_advance_height; FT_Short underline_position; FT_Short underline_thickness;
  FT_GlyphSlot glyph; FT_Size size; FT_CharMap charmap; FT_Driver driver; FT_Memory memory; FT_Stream stream;
  FT_ListRec sizes_list; FT_Generic autohint; void* extensions; FT_Face_Internal internal;
} FT_FaceRec;
typedef struct FT_GlyphSlotRec_ {
  FT_Library library; FT_Face face; FT_GlyphSlot next; FT_UInt glyph_index; FT_Generic generic;
  FT_Glyph_Metrics metrics; FT_Fixed linearHoriAdvance; FT_Fixed linearVertAdvance; FT_Vector advance;
  FT_ULong format; FT_Bitmap bitmap; FT_Int bitmap_left; FT_Int bitmap_top; FT_Outline outline;
  FT_UInt num_subglyphs; FT_SubGlyph subglyphs; void* control_data; FT_Long control_len;
  FT_Pos lsb_delta; FT_Pos rsb_delta; void* other; FT_Slot_Internal internal;
} FT_GlyphSlotRec;
FT_Error FT_Init_FreeType(FT_Library* alibrary);
FT_Error FT_Done_FreeType(FT_Library library);
FT_Error FT_New_Face(FT_Library library, const char* filepathname, FT_Long face_index, FT_Face* aface);
FT_Error FT_Done_Face(FT_Face face);
FT_Error FT_Set_Pixel_Sizes(FT_Face face, FT_UInt pixel_width, FT_UInt pixel_height);
FT_Error FT_Load_Char(FT_Face face, FT_ULong char_code, FT_Int32 load_flags);
]]

local ok, freetype = pcall(ffi.load, "freetype")
if not ok then
  error("Unable to load FreeType. Install freetype-devel (Fedora): " .. tostring(freetype))
end

return {
  ffi = ffi,
  lib = freetype,
  load_render = 0x4,
}
