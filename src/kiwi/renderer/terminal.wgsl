struct GpuCell {
  position: vec2<f32>,
  uv_min: vec2<f32>,
  uv_max: vec2<f32>,
  fg: u32,
  bg: u32,
  flags: u32,
  glyph: u32,
}

struct GpuTextGlyph {
  position: vec2<f32>,
  size: vec2<f32>,
  uv_min: vec2<f32>,
  uv_max: vec2<f32>,
  fg: u32,
  flags: u32,
  glyph: u32,
  cluster: u32,
}

struct FrameData {
  columns: f32,
  rows: f32,
  cursor_column: f32,
  cursor_row: f32,
  time: f32,
  show_dirty: f32,
  show_boundaries: f32,
  cursor_visible: f32,
  cursor_shape: f32,
  cursor_blink: f32,
  padding0: f32,
  padding1: f32,
  selection_start_column: f32,
  selection_start_row: f32,
  selection_finish_column: f32,
  selection_finish_row: f32,
  selection_red: f32,
  selection_green: f32,
  selection_blue: f32,
  selection_alpha: f32,
  search_start_column: f32,
  search_start_row: f32,
  search_finish_column: f32,
  search_finish_row: f32,
  search_red: f32,
  search_green: f32,
  search_blue: f32,
  search_alpha: f32,
  hyperlink_red: f32,
  hyperlink_green: f32,
  hyperlink_blue: f32,
  hyperlink_alpha: f32,
  command_region_count: f32,
  command_region_red: f32,
  command_region_green: f32,
  command_region_blue: f32,
  command_region_alpha: f32,
  command_region_padding0: f32,
  command_region_padding1: vec2<f32>,
  command_region_boundaries: array<vec4<f32>, 32>,
}

struct RasterOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) local_position: vec2<f32>,
  @location(2) fg: vec4<f32>,
  @location(3) bg: vec4<f32>,
  @interpolate(flat) @location(4) flags: u32,
  @interpolate(flat) @location(5) glyph: u32,
  @interpolate(flat) @location(6) cell_position: vec2<f32>,
}

@group(0) @binding(0) var<storage, read> cells: array<GpuCell>;
@group(0) @binding(1) var<storage, read> glyphs: array<GpuTextGlyph>;
@group(0) @binding(2) var glyph_atlas: texture_2d<f32>;
@group(0) @binding(3) var glyph_sampler: sampler;
@group(0) @binding(4) var<uniform> frame: FrameData;

fn unpack_rgba(value: u32) -> vec4<f32> {
  let r = f32((value >> 16u) & 255u) / 255.0;
  let g = f32((value >> 8u) & 255u) / 255.0;
  let b = f32(value & 255u) / 255.0;
  let a = f32((value >> 24u) & 255u) / 255.0;
  return vec4<f32>(r, g, b, a);
}

fn quad_corner(vertex_index: u32) -> vec2<f32> {
  let corners = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
  );
  return corners[vertex_index];
}

fn raster_out(position: vec2<f32>, size: vec2<f32>, uv_min: vec2<f32>, uv_max: vec2<f32>, fg: u32, bg: u32, flags: u32, glyph: u32, vertex_index: u32) -> RasterOut {
  let local_position = quad_corner(vertex_index);
  let upper_left = vec2<f32>(position.x / frame.columns, position.y / frame.rows);
  let lower_right = vec2<f32>((position.x + size.x) / frame.columns, (position.y + size.y) / frame.rows);
  let normalized_position = upper_left + local_position * (lower_right - upper_left);
  var result: RasterOut;
  result.position = vec4<f32>(normalized_position.x * 2.0 - 1.0, 1.0 - normalized_position.y * 2.0, 0.0, 1.0);
  result.uv = uv_min + local_position * (uv_max - uv_min);
  result.local_position = local_position;
  result.fg = unpack_rgba(fg);
  result.bg = unpack_rgba(bg);
  result.flags = flags;
  result.glyph = glyph;
  result.cell_position = position;
  return result;
}

@vertex
fn background_vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> RasterOut {
  let cell = cells[instance_index];
  return raster_out(cell.position, vec2<f32>(1.0, 1.0), cell.uv_min, cell.uv_max, cell.fg, cell.bg, cell.flags, cell.glyph, vertex_index);
}

@fragment
fn background_fs(input: RasterOut) -> @location(0) vec4<f32> {
  var color = input.bg;
  if ((input.flags & 2u) != 0u) {
    color = vec4<f32>(mix(color.rgb, vec3<f32>(0.45, 0.72, 0.86), 0.24), color.a);
  }
  if (frame.show_dirty > 0.5 && (input.flags & 4u) != 0u) {
    color = vec4<f32>(mix(color.rgb, vec3<f32>(1.0, 0.75, 0.20), 0.42), color.a);
  }
  if (frame.show_boundaries > 0.5 && (input.local_position.x < 0.025 || input.local_position.y < 0.035)) {
    color = vec4<f32>(0.18, 0.52, 0.61, color.a);
  }
  return color;
}

@vertex
fn glyph_vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> RasterOut {
  let glyph = glyphs[instance_index];
  return raster_out(glyph.position, glyph.size, glyph.uv_min, glyph.uv_max, glyph.fg, 0u, glyph.flags, glyph.glyph, vertex_index);
}

@fragment
fn glyph_fs(input: RasterOut) -> @location(0) vec4<f32> {
  if (input.glyph == 0u) { discard; }
  let coverage = textureSample(glyph_atlas, glyph_sampler, input.uv).r;
  let hyperlink_underline = (input.flags & 512u) != 0u && frame.hyperlink_alpha > 0.0 && input.local_position.y > 0.91;
  let decoration = ((input.flags & 32u) != 0u && input.local_position.y > 0.88)
    || ((input.flags & 256u) != 0u && input.local_position.y > 0.46 && input.local_position.y < 0.54);
  if (hyperlink_underline) { return vec4<f32>(frame.hyperlink_red, frame.hyperlink_green, frame.hyperlink_blue, frame.hyperlink_alpha); }
  var color = input.fg;
  if ((input.flags & 1u) != 0u) { color = vec4<f32>(min(vec3<f32>(1.0), color.rgb * 1.16), color.a); }
  if ((input.flags & 8u) != 0u) { color = vec4<f32>(color.rgb * 0.65, color.a); }
  if (decoration) { return color; }
  if (coverage <= 0.0) { discard; }
  return vec4<f32>(color.rgb, color.a * coverage);
}

fn selection_contains(column: f32, row: f32) -> bool {
  let after_start = row > frame.selection_start_row
    || (row == frame.selection_start_row && column >= frame.selection_start_column);
  let before_finish = row < frame.selection_finish_row
    || (row == frame.selection_finish_row && column < frame.selection_finish_column);
  return after_start && before_finish;
}

fn search_contains(column: f32, row: f32) -> bool {
  let after_start = row > frame.search_start_row
    || (row == frame.search_start_row && column >= frame.search_start_column);
  let before_finish = row < frame.search_finish_row
    || (row == frame.search_finish_row && column < frame.search_finish_column);
  return after_start && before_finish;
}

fn command_region_separator_row(row: f32) -> bool {
  for (var index = 0u; index < 32u; index = index + 1u) {
    if (f32(index) >= frame.command_region_count) { break; }
    let boundary = frame.command_region_boundaries[index];
    if (boundary.y == row && (boundary.z == 2.0 || boundary.z == 3.0)) { return true; }
  }
  return false;
}

@vertex
fn selection_vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> RasterOut {
  let row = floor(f32(instance_index) / frame.columns);
  let column = f32(instance_index) - row * frame.columns;
  return raster_out(vec2<f32>(column, row), vec2<f32>(1.0, 1.0), vec2<f32>(0.0), vec2<f32>(0.0), 0u, 0u, 0u, 0u, vertex_index);
}

@fragment
fn selection_fs(input: RasterOut) -> @location(0) vec4<f32> {
  if (!selection_contains(input.cell_position.x, input.cell_position.y)) { discard; }
  return vec4<f32>(frame.selection_red, frame.selection_green, frame.selection_blue, frame.selection_alpha);
}

@vertex
fn search_vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> RasterOut {
  let row = floor(f32(instance_index) / frame.columns);
  let column = f32(instance_index) - row * frame.columns;
  return raster_out(vec2<f32>(column, row), vec2<f32>(1.0, 1.0), vec2<f32>(0.0), vec2<f32>(0.0), 0u, 0u, 0u, 0u, vertex_index);
}

@fragment
fn search_fs(input: RasterOut) -> @location(0) vec4<f32> {
  if (!search_contains(input.cell_position.x, input.cell_position.y)) { discard; }
  return vec4<f32>(frame.search_red, frame.search_green, frame.search_blue, frame.search_alpha);
}

@vertex
fn command_regions_vs(@builtin(vertex_index) vertex_index: u32, @builtin(instance_index) instance_index: u32) -> RasterOut {
  let row = floor(f32(instance_index) / frame.columns);
  let column = f32(instance_index) - row * frame.columns;
  return raster_out(vec2<f32>(column, row), vec2<f32>(1.0, 1.0), vec2<f32>(0.0), vec2<f32>(0.0), 0u, 0u, 0u, 0u, vertex_index);
}

@fragment
fn command_regions_fs(input: RasterOut) -> @location(0) vec4<f32> {
  if (frame.command_region_alpha <= 0.0 || input.local_position.y > 0.04 || !command_region_separator_row(input.cell_position.y)) { discard; }
  return vec4<f32>(frame.command_region_red, frame.command_region_green, frame.command_region_blue, frame.command_region_alpha);
}

@vertex
fn cursor_vs(@builtin(vertex_index) vertex_index: u32) -> RasterOut {
  let local_position = quad_corner(vertex_index);
  let upper_left = vec2<f32>(frame.cursor_column / frame.columns, frame.cursor_row / frame.rows);
  let lower_right = vec2<f32>((frame.cursor_column + 1.0) / frame.columns, (frame.cursor_row + 1.0) / frame.rows);
  let normalized_position = upper_left + local_position * (lower_right - upper_left);
  var result: RasterOut;
  result.position = vec4<f32>(normalized_position.x * 2.0 - 1.0, 1.0 - normalized_position.y * 2.0, 0.0, 1.0);
  result.local_position = local_position;
  result.uv = vec2<f32>(0.0);
  result.fg = vec4<f32>(0.55, 0.85, 0.88, 1.0);
  result.bg = result.fg;
  result.flags = 0u;
  result.glyph = 0u;
  result.cell_position = vec2<f32>(frame.cursor_column, frame.cursor_row);
  return result;
}

@fragment
fn cursor_fs(input: RasterOut) -> @location(0) vec4<f32> {
  if (frame.cursor_visible < 0.5 || (frame.cursor_blink > 0.5 && abs(sin(frame.time * 3.0)) < 0.15)) { discard; }
  if (frame.cursor_shape > 0.5 && frame.cursor_shape < 1.5 && input.local_position.y < 0.82) { discard; }
  if (frame.cursor_shape > 1.5 && input.local_position.x > 0.18) { discard; }
  return input.fg;
}
