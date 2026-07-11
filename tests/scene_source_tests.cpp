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

bool anyFiniteDepth(const strok::SceneGBuffer& buffer) {
  for (const double depth : buffer.depth) {
    if (std::isfinite(depth)) {
      return true;
    }
  }
  return false;
}

bool anyNormal(const strok::SceneGBuffer& buffer) {
  for (const strok::SceneVec3 normal : buffer.normals) {
    if (std::abs(normal.x) > 0.0 || std::abs(normal.y) > 0.0 || std::abs(normal.z) > 0.0) {
      return true;
    }
  }
  return false;
}

bool albedoDiffers(const strok::SceneGBuffer& lhs, const strok::SceneGBuffer& rhs) {
  return lhs.albedo.rgb != rhs.albedo.rgb;
}

}  // namespace

int main() {
  expect(strok::parseSceneCameraPreset("turntable") == strok::SceneCameraPreset::Turntable, "turntable camera parses");
  expect(strok::parseSceneCameraPreset("orbit") == strok::SceneCameraPreset::Orbit, "orbit camera parses");
  expect(strok::parseSceneCameraPreset("fly") == strok::SceneCameraPreset::Fly, "fly camera parses");
  expect(!strok::parseSceneCameraPreset("bad").has_value(), "bad camera rejected");

  const std::optional<std::filesystem::path> bundled = strok::resolveBundledScene("strok:scene:cube");
  expect(bundled.has_value(), "bundled cube resolves");
  const strok::SceneMesh cube = strok::loadObjScene(*bundled);
  expect(cube.triangles.size() == 12, "bundled cube loads");

  const std::optional<std::filesystem::path> suzanne_path = strok::resolveBundledScene("strok:scene:suzanne");
  expect(suzanne_path.has_value(), "bundled suzanne resolves");
  const strok::SceneMesh suzanne = strok::loadObjScene(*suzanne_path);
  expect(suzanne.positions.size() == 505, "bundled suzanne vertex count");
  expect(suzanne.triangles.size() == 968, "bundled suzanne triangle count");

  const strok::SceneMesh triangle = strok::parseObjScene(
    "v -1 -1 0\n"
    "v 1 -1 0\n"
    "v 0 1 0\n"
    "vn 0 0 1\n"
    "f 1//1 2//1 3//1\n");
  expect(triangle.positions.size() == 3, "OBJ parser stores vertices");
  expect(triangle.normals.size() == 1, "OBJ parser stores normals");
  expect(triangle.triangles.size() == 1, "OBJ parser stores triangle");

  const strok::SceneMesh quad = strok::parseObjScene(
    "v -1 -1 0\n"
    "v 1 -1 0\n"
    "v 1 1 0\n"
    "v -1 1 0\n"
    "f 1 2 3 4\n");
  expect(quad.triangles.size() == 2, "OBJ parser triangulates quad");

  const strok::SceneGBuffer rendered = strok::renderSceneGBuffer(triangle, strok::SceneRenderOptions{.width = 16, .height = 16});
  expect(rendered.albedo.w == 16 && rendered.albedo.h == 16, "scene render output dimensions");
  expect(rendered.albedo.rgb.size() == 16U * 16U * 3U, "scene render albedo size");
  expect(rendered.depth.size() == 16U * 16U, "scene render depth size");
  expect(rendered.normals.size() == 16U * 16U, "scene render normal size");
  expect(anyFiniteDepth(rendered), "scene render writes depth");
  expect(anyNormal(rendered), "scene render writes normals");

  const strok::SceneGBuffer rotated = strok::renderSceneGBuffer(triangle, strok::SceneRenderOptions{.width = 16, .height = 16, .time_seconds = 0.5});
  expect(anyFiniteDepth(rotated), "rotated scene render writes depth");

  const strok::SceneGBuffer turntable = strok::renderSceneGBuffer(cube, strok::SceneRenderOptions{.width = 20, .height = 18, .time_seconds = 0.75, .camera_preset = strok::SceneCameraPreset::Turntable});
  const strok::SceneGBuffer orbit = strok::renderSceneGBuffer(cube, strok::SceneRenderOptions{.width = 20, .height = 18, .time_seconds = 0.75, .camera_preset = strok::SceneCameraPreset::Orbit});
  const strok::SceneGBuffer fly = strok::renderSceneGBuffer(cube, strok::SceneRenderOptions{.width = 20, .height = 18, .time_seconds = 0.75, .camera_preset = strok::SceneCameraPreset::Fly});
  expect(anyFiniteDepth(turntable) && anyFiniteDepth(orbit) && anyFiniteDepth(fly), "camera presets render depth");
  expect(albedoDiffers(turntable, orbit), "orbit camera changes rendered view");
  expect(albedoDiffers(turntable, fly), "fly camera changes rendered view");

  const strok::SceneGBuffer suzanne_render = strok::renderSceneGBuffer(suzanne, strok::SceneRenderOptions{.width = 48, .height = 32, .time_seconds = 0.25, .camera_preset = strok::SceneCameraPreset::Turntable});
  expect(anyFiniteDepth(suzanne_render), "bundled suzanne renders depth");
  expect(anyNormal(suzanne_render), "bundled suzanne renders normals");
}
