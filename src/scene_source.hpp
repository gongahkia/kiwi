#pragma once

#include "frame.hpp"
#include "../include/strok/render_input.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace strok {

struct SceneVec3 {
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;
};

struct SceneVertexRef {
  int position = -1;
  int normal = -1;
};

struct SceneTriangle {
  SceneVertexRef a;
  SceneVertexRef b;
  SceneVertexRef c;
};

struct SceneMesh {
  std::vector<SceneVec3> positions;
  std::vector<SceneVec3> normals;
  std::vector<SceneTriangle> triangles;
};

enum class SceneCameraPreset {
  Turntable,
  Orbit,
  Fly,
};

struct SceneRenderOptions {
  int width = 0;
  int height = 0;
  double time_seconds = 0.0;
  SceneCameraPreset camera_preset = SceneCameraPreset::Turntable;
};

struct SceneGBuffer {
  Frame albedo;
  std::vector<double> depth;
  std::vector<SceneVec3> normals;
};

std::optional<SceneCameraPreset> parseSceneCameraPreset(std::string_view value) noexcept;
std::optional<std::filesystem::path> resolveBundledScene(std::string_view input);
SceneMesh parseObjScene(std::string_view text);
SceneMesh loadObjScene(const std::filesystem::path& path);
SceneGBuffer renderSceneGBuffer(const SceneMesh& mesh, SceneRenderOptions options);
std::optional<RenderInput> renderInputFromSceneGBuffer(const SceneGBuffer& buffer) noexcept;

}  // namespace strok
