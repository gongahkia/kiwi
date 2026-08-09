local ffi = require("ffi")

ffi.cdef[[
typedef int FcBool;
typedef unsigned int FcChar32;
typedef unsigned char FcChar8;
typedef struct _FcConfig FcConfig;
typedef struct _FcPattern FcPattern;
typedef struct _FcCharSet FcCharSet;
FcBool FcInit(void);
FcPattern *FcPatternCreate(void);
void FcPatternDestroy(FcPattern *p);
FcBool FcPatternAddString(FcPattern *p, const char *object, const FcChar8 *s);
FcBool FcPatternAddInteger(FcPattern *p, const char *object, int i);
FcBool FcPatternAddCharSet(FcPattern *p, const char *object, const FcCharSet *c);
FcBool FcConfigSubstitute(FcConfig *config, FcPattern *p, int kind);
void FcDefaultSubstitute(FcPattern *p);
FcPattern *FcFontMatch(FcConfig *config, FcPattern *p, int *result);
int FcPatternGetString(const FcPattern *p, const char *object, int n, FcChar8 **s);
int FcPatternGetInteger(const FcPattern *p, const char *object, int n, int *i);
FcCharSet *FcCharSetCreate(void);
void FcCharSetDestroy(FcCharSet *fcs);
FcBool FcCharSetAddChar(FcCharSet *fcs, FcChar32 ucs4);
]]

local ok, fontconfig = pcall(ffi.load, "fontconfig")
if not ok then
  error("Unable to load Fontconfig. Install fontconfig-devel (Fedora): " .. tostring(fontconfig))
end

return {
  ffi = ffi,
  lib = fontconfig,
  match_pattern = 0,
  result_match = 0,
  object = { family = "family", file = "file", index = "index", spacing = "spacing", charset = "charset" },
  mono_spacing = 100,
}
