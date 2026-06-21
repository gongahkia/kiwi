#include "scene_source.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool anyFiniteDepth(const contourtty::SceneGBuffer& buffer) {
  for (const double depth : buffer.depth) {
    if (std::isfinite(depth)) {
      return true;
    }
  }
  return false;
}

bool anyNormal(const contourtty::SceneGBuffer& buffer) {
  for (const contourtty::SceneVec3 normal : buffer.normals) {
    if (std::abs(normal.x) > 0.0 || std::abs(normal.y) > 0.0 || std::abs(normal.z) > 0.0) {
      return true;
    }
  }
  return false;
}

bool albedoDiffers(const contourtty::SceneGBuffer& lhs, const contourtty::SceneGBuffer& rhs) {
  return lhs.albedo.rgb != rhs.albedo.rgb;
}

}  // namespace

int main() {
  expect(contourtty::parseSceneCameraPreset("turntable") == contourtty::SceneCameraPreset::Turntable, "turntable camera parses");
  expect(contourtty::parseSceneCameraPreset("orbit") == contourtty::SceneCameraPreset::Orbit, "orbit camera parses");
  expect(contourtty::parseSceneCameraPreset("fly") == contourtty::SceneCameraPreset::Fly, "fly camera parses");
  expect(!contourtty::parseSceneCameraPreset("bad").has_value(), "bad camera rejected");

  const std::optional<std::filesystem::path> bundled = contourtty::resolveBundledScene("contourtty:scene:cube");
  expect(bundled.has_value(), "bundled cube resolves");
  const contourtty::SceneMesh cube = contourtty::loadObjScene(*bundled);
  expect(cube.triangles.size() == 12, "bundled cube loads");

  const contourtty::SceneMesh triangle = contourtty::parseObjScene(
    "v -1 -1 0\n"
    "v 1 -1 0\n"
    "v 0 1 0\n"
    "vn 0 0 1\n"
    "f 1//1 2//1 3//1\n");
  expect(triangle.positions.size() == 3, "OBJ parser stores vertices");
  expect(triangle.normals.size() == 1, "OBJ parser stores normals");
  expect(triangle.triangles.size() == 1, "OBJ parser stores triangle");

  const contourtty::SceneMesh quad = contourtty::parseObjScene(
    "v -1 -1 0\n"
    "v 1 -1 0\n"
    "v 1 1 0\n"
    "v -1 1 0\n"
    "f 1 2 3 4\n");
  expect(quad.triangles.size() == 2, "OBJ parser triangulates quad");

  const contourtty::SceneGBuffer rendered = contourtty::renderSceneGBuffer(triangle, contourtty::SceneRenderOptions{.width = 16, .height = 16});
  expect(rendered.albedo.w == 16 && rendered.albedo.h == 16, "scene render output dimensions");
  expect(rendered.albedo.rgb.size() == 16U * 16U * 3U, "scene render albedo size");
  expect(rendered.depth.size() == 16U * 16U, "scene render depth size");
  expect(rendered.normals.size() == 16U * 16U, "scene render normal size");
  expect(anyFiniteDepth(rendered), "scene render writes depth");
  expect(anyNormal(rendered), "scene render writes normals");

  const contourtty::SceneGBuffer rotated = contourtty::renderSceneGBuffer(triangle, contourtty::SceneRenderOptions{.width = 16, .height = 16, .time_seconds = 0.5});
  expect(anyFiniteDepth(rotated), "rotated scene render writes depth");

  const contourtty::SceneGBuffer turntable = contourtty::renderSceneGBuffer(cube, contourtty::SceneRenderOptions{.width = 20, .height = 18, .time_seconds = 0.75, .camera_preset = contourtty::SceneCameraPreset::Turntable});
  const contourtty::SceneGBuffer orbit = contourtty::renderSceneGBuffer(cube, contourtty::SceneRenderOptions{.width = 20, .height = 18, .time_seconds = 0.75, .camera_preset = contourtty::SceneCameraPreset::Orbit});
  const contourtty::SceneGBuffer fly = contourtty::renderSceneGBuffer(cube, contourtty::SceneRenderOptions{.width = 20, .height = 18, .time_seconds = 0.75, .camera_preset = contourtty::SceneCameraPreset::Fly});
  expect(anyFiniteDepth(turntable) && anyFiniteDepth(orbit) && anyFiniteDepth(fly), "camera presets render depth");
  expect(albedoDiffers(turntable, orbit), "orbit camera changes rendered view");
  expect(albedoDiffers(turntable, fly), "fly camera changes rendered view");
}
