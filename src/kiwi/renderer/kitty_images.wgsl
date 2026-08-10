struct GpuKittyImage {
  position: vec2<f32>,
  size: vec2<f32>,
  uv_min: vec2<f32>,
  uv_max: vec2<f32>,
}

struct KittyImageOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
}

@group(0) @binding(0) var kitty_image: texture_2d<f32>;
@group(0) @binding(1) var kitty_image_sampler: sampler;
@group(0) @binding(2) var<storage, read> kitty_images: array<GpuKittyImage>;

fn kitty_quad_corner(vertex_index: u32) -> vec2<f32> {
  let corners = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
  );
  return corners[vertex_index];
}

@vertex
fn kitty_image_vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> KittyImageOut {
  let image = kitty_images[instance_index];
  let corner = kitty_quad_corner(vertex_index);
  let upper_left = image.position + corner * image.size;
  var output: KittyImageOut;
  output.position = vec4<f32>(upper_left.x, upper_left.y, 0.0, 1.0);
  output.uv = image.uv_min + corner * (image.uv_max - image.uv_min);
  return output;
}

@fragment
fn kitty_image_fs(input: KittyImageOut) -> @location(0) vec4<f32> {
  return textureSample(kitty_image, kitty_image_sampler, input.uv);
}
