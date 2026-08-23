local Assert = require("tests.assert")
local ffi = require("ffi")
local RenderModel = require("kiwi.renderer.render_model")

return {
  renderer_neutral_native_abi_has_stable_layouts = function()
    Assert.equal(RenderModel.version, 2)
    Assert.equal(RenderModel.command_region_limit, 32)
    RenderModel.assert_layout()
    Assert.equal(ffi.offsetof("KiwiTextGlyphInstance", "cluster"), 44)
    Assert.equal(ffi.offsetof("KiwiFrameUniform", "command_region_padding"), 156)
    Assert.equal(ffi.offsetof("KiwiFrameUniform", "scrollbar_visible"), 688)
  end,
}
