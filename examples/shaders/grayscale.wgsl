fn kiwi_effect(color: vec4<f32>, uv: vec2<f32>, time: f32, resolution: vec2<f32>) -> vec4<f32> {
  let luminance = dot(color.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  return vec4<f32>(vec3<f32>(luminance), color.a);
}
