struct Parameters { resolution: vec2<f32>, time: f32, premultiply: f32 }
@group(0) @binding(0) var kiwi_texture: texture_2d<f32>;
@group(0) @binding(1) var kiwi_sampler: sampler;
@group(0) @binding(2) var<uniform> kiwi_parameters: Parameters;

// Terminal rendering uses premultiplied colour; effects receive straight colour.
fn kiwi_sample(uv: vec2<f32>) -> vec4<f32> {
  let color = textureSampleLevel(kiwi_texture, kiwi_sampler, uv, 0.0);
  if (color.a <= 0.0) { return vec4<f32>(0.0); }
  return vec4<f32>(color.rgb / color.a, color.a);
}
struct VertexOut { @builtin(position) position: vec4<f32>, @location(0) uv: vec2<f32> }
@vertex fn kiwi_vs(@builtin(vertex_index) index: u32) -> VertexOut {
  let positions = array<vec2<f32>, 3>(vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0));
  var output: VertexOut;
  output.position = vec4<f32>(positions[index], 0.0, 1.0);
  output.uv = positions[index] * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
  return output;
}
@fragment fn kiwi_fs(input: VertexOut) -> @location(0) vec4<f32> {
  let color = clamp(kiwi_effect(kiwi_sample(input.uv), input.uv, kiwi_parameters.time, kiwi_parameters.resolution), vec4<f32>(0.0), vec4<f32>(1.0));
  if (kiwi_parameters.premultiply > 0.5) { return vec4<f32>(color.rgb * color.a, color.a); }
  return color;
}
