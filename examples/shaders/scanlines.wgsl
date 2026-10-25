// Save custom-shader = "/absolute/path/to/scanlines.wgsl" in Kiwi's config.
// Static: no continuous rendering is needed.
fn kiwi_effect(color: vec4<f32>, uv: vec2<f32>, time: f32, resolution: vec2<f32>) -> vec4<f32> {
  let stripe = 0.94 + 0.06 * cos(uv.y * resolution.y * 3.14159265);
  return vec4<f32>(color.rgb * stripe, color.a);
}
