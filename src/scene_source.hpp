#pragma once

#include "frame.hpp"

#include <filesystem>
#include <string>
#include <vector>

namespace contourtty {

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

struct SceneRenderOptions {
  int width = 0;
  int height = 0;
  double time_seconds = 0.0;
};

struct SceneGBuffer {
  Frame albedo;
  std::vector<double> depth;
  std::vector<SceneVec3> normals;
};

SceneMesh parseObjScene(std::string_view text);
SceneMesh loadObjScene(const std::filesystem::path& path);
SceneGBuffer renderSceneGBuffer(const SceneMesh& mesh, SceneRenderOptions options);

}  // namespace contourtty
