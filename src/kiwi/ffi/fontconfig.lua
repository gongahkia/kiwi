local ffi = require("ffi")

ffi.cdef[[
typedef int FcBool;
typedef unsigned int FcChar32;
typedef unsigned char FcChar8;
typedef struct _FcConfig FcConfig;
typedef struct _FcPattern FcPattern;
typedef struct _FcCharSet FcCharSet;
typedef struct { int nfont; int sfont; FcPattern **fonts; } FcFontSet;
FcBool FcInit(void);
FcPattern *FcPatternCreate(void);
void FcPatternDestroy(FcPattern *p);
FcBool FcPatternAddString(FcPattern *p, const char *object, const FcChar8 *s);
FcBool FcPatternAddInteger(FcPattern *p, const char *object, int i);
FcBool FcPatternAddBool(FcPattern *p, const char *object, FcBool b);
FcBool FcPatternAddCharSet(FcPattern *p, const char *object, const FcCharSet *c);
FcBool FcConfigSubstitute(FcConfig *config, FcPattern *p, int kind);
void FcDefaultSubstitute(FcPattern *p);
FcPattern *FcFontMatch(FcConfig *config, FcPattern *p, int *result);
FcFontSet *FcFontSort(FcConfig *config, FcPattern *p, FcBool trim, FcCharSet **csp, int *result);
void FcFontSetDestroy(FcFontSet *s);
int FcPatternGetString(const FcPattern *p, const char *object, int n, FcChar8 **s);
int FcPatternGetInteger(const FcPattern *p, const char *object, int n, int *i);
int FcPatternGetCharSet(const FcPattern *p, const char *object, int n, FcCharSet **c);
FcCharSet *FcCharSetCreate(void);
void FcCharSetDestroy(FcCharSet *fcs);
FcBool FcCharSetAddChar(FcCharSet *fcs, FcChar32 ucs4);
FcBool FcCharSetHasChar(const FcCharSet *fcs, FcChar32 ucs4);
]]

local ok, fontconfig = pcall(require("kiwi.ffi.library").load, "fontconfig", "fontconfig")
if not ok then
  error("Unable to load Fontconfig. Install fontconfig-devel (Fedora): " .. tostring(fontconfig))
end

return {
  ffi = ffi,
  lib = fontconfig,
  match_pattern = 0,
  result_match = 0,
  object = { family = "family", file = "file", index = "index", spacing = "spacing", charset = "charset", weight = "weight", slant = "slant" },
  mono_spacing = 100,
  weight_regular = 80,
  weight_bold = 200,
  slant_roman = 0,
  slant_italic = 100,
}
