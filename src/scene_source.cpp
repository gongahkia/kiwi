#include "scene_source.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <fstream>
#include <limits>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

struct ProjectedVertex {
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;
  SceneVec3 normal;
};

std::string trim(std::string_view value) {
  while (!value.empty() && (value.front() == ' ' || value.front() == '\t' || value.front() == '\r')) {
    value.remove_prefix(1);
  }
  while (!value.empty() && (value.back() == ' ' || value.back() == '\t' || value.back() == '\r')) {
    value.remove_suffix(1);
  }
  return std::string(value);
}

SceneVec3 sub(SceneVec3 lhs, SceneVec3 rhs) {
  return SceneVec3{.x = lhs.x - rhs.x, .y = lhs.y - rhs.y, .z = lhs.z - rhs.z};
}

SceneVec3 add(SceneVec3 lhs, SceneVec3 rhs) {
  return SceneVec3{.x = lhs.x + rhs.x, .y = lhs.y + rhs.y, .z = lhs.z + rhs.z};
}

SceneVec3 mul(SceneVec3 value, double scale) {
  return SceneVec3{.x = value.x * scale, .y = value.y * scale, .z = value.z * scale};
}

SceneVec3 cross(SceneVec3 lhs, SceneVec3 rhs) {
  return SceneVec3{
    .x = lhs.y * rhs.z - lhs.z * rhs.y,
    .y = lhs.z * rhs.x - lhs.x * rhs.z,
    .z = lhs.x * rhs.y - lhs.y * rhs.x,
  };
}

double dot(SceneVec3 lhs, SceneVec3 rhs) {
  return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
}

SceneVec3 normalize(SceneVec3 value) {
  const double length = std::sqrt(dot(value, value));
  if (length <= 1.0e-12) {
    return SceneVec3{.z = 1.0};
  }
  return mul(value, 1.0 / length);
}

SceneVec3 rotateY(SceneVec3 value, double radians) {
  const double c = std::cos(radians);
  const double s = std::sin(radians);
  return SceneVec3{
    .x = value.x * c + value.z * s,
    .y = value.y,
    .z = -value.x * s + value.z * c,
  };
}

int parseIndex(std::string_view text, int count) {
  if (text.empty()) {
    return -1;
  }
  int value = 0;
  std::string copy(text);
  std::istringstream input(copy);
  input >> value;
  if (!input || value == 0) {
    throw std::invalid_argument("invalid OBJ index");
  }
  const int index = value > 0 ? value - 1 : count + value;
  if (index < 0 || index >= count) {
    throw std::invalid_argument("OBJ index out of range");
  }
  return index;
}

SceneVertexRef parseVertexRef(const std::string& token, int position_count, int normal_count) {
  const std::size_t first = token.find('/');
  if (first == std::string::npos) {
    return SceneVertexRef{.position = parseIndex(token, position_count)};
  }
  const std::size_t second = token.find('/', first + 1);
  SceneVertexRef ref;
  ref.position = parseIndex(std::string_view(token).substr(0, first), position_count);
  if (second != std::string::npos) {
    ref.normal = parseIndex(std::string_view(token).substr(second + 1), normal_count);
  }
  return ref;
}

SceneVec3 triangleNormal(const SceneMesh& mesh, const SceneTriangle& triangle) {
  const SceneVec3 a = mesh.positions[static_cast<std::size_t>(triangle.a.position)];
  const SceneVec3 b = mesh.positions[static_cast<std::size_t>(triangle.b.position)];
  const SceneVec3 c = mesh.positions[static_cast<std::size_t>(triangle.c.position)];
  return normalize(cross(sub(b, a), sub(c, a)));
}

SceneVec3 vertexNormal(const SceneMesh& mesh, const SceneTriangle& triangle, const SceneVertexRef& ref) {
  if (ref.normal >= 0) {
    return normalize(mesh.normals[static_cast<std::size_t>(ref.normal)]);
  }
  return triangleNormal(mesh, triangle);
}

double edge(double ax, double ay, double bx, double by, double px, double py) {
  return (px - ax) * (by - ay) - (py - ay) * (bx - ax);
}

void putPixel(SceneGBuffer* buffer, int width, int x, int y, double depth, SceneVec3 normal) {
  const std::size_t index = static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x);
  if (depth >= buffer->depth[index]) {
    return;
  }
  buffer->depth[index] = depth;
  buffer->normals[index] = normalize(normal);
  const SceneVec3 n = buffer->normals[index];
  buffer->albedo.rgb[index * 3U] = static_cast<uint8_t>(std::clamp((n.x * 0.5 + 0.5) * 255.0, 0.0, 255.0));
  buffer->albedo.rgb[index * 3U + 1U] = static_cast<uint8_t>(std::clamp((n.y * 0.5 + 0.5) * 255.0, 0.0, 255.0));
  buffer->albedo.rgb[index * 3U + 2U] = static_cast<uint8_t>(std::clamp((n.z * 0.5 + 0.5) * 255.0, 0.0, 255.0));
}

}  // namespace

std::optional<SceneCameraPreset> parseSceneCameraPreset(std::string_view value) noexcept {
  if (value == "turntable") {
    return SceneCameraPreset::Turntable;
  }
  if (value == "orbit") {
    return SceneCameraPreset::Orbit;
  }
  if (value == "fly") {
    return SceneCameraPreset::Fly;
  }
  return std::nullopt;
}

std::optional<std::filesystem::path> resolveBundledScene(std::string_view input) {
  constexpr std::string_view prefix = "contourtty:scene:";
  if (!input.starts_with(prefix)) {
    return std::nullopt;
  }
  const std::string name(input.substr(prefix.size()));
  if (name.empty() || name.find('/') != std::string::npos || name.find('\\') != std::string::npos) {
    throw std::invalid_argument("invalid bundled scene name");
  }
  std::filesystem::path path = std::filesystem::path(CONTOURTTY_SOURCE_DIR) / "share" / "contourtty" / "scenes" / (name + ".obj");
  if (!std::filesystem::exists(path)) {
    throw std::invalid_argument("unknown bundled scene: " + name);
  }
  return path;
}

SceneMesh parseObjScene(std::string_view text) {
  SceneMesh mesh;
  std::istringstream input{std::string(text)};
  std::string line;
  while (std::getline(input, line)) {
    line = trim(line);
    if (line.empty() || line.front() == '#') {
      continue;
    }
    std::istringstream fields(line);
    std::string tag;
    fields >> tag;
    if (tag == "v") {
      SceneVec3 position;
      fields >> position.x >> position.y >> position.z;
      if (!fields) {
        throw std::invalid_argument("invalid OBJ vertex");
      }
      mesh.positions.push_back(position);
    } else if (tag == "vn") {
      SceneVec3 normal;
      fields >> normal.x >> normal.y >> normal.z;
      if (!fields) {
        throw std::invalid_argument("invalid OBJ normal");
      }
      mesh.normals.push_back(normalize(normal));
    } else if (tag == "f") {
      std::vector<SceneVertexRef> refs;
      std::string token;
      while (fields >> token) {
        refs.push_back(parseVertexRef(token, static_cast<int>(mesh.positions.size()), static_cast<int>(mesh.normals.size())));
      }
      if (refs.size() < 3) {
        throw std::invalid_argument("OBJ face must have at least 3 vertices");
      }
      for (std::size_t index = 1; index + 1 < refs.size(); ++index) {
        mesh.triangles.push_back(SceneTriangle{.a = refs[0], .b = refs[index], .c = refs[index + 1]});
      }
    }
  }
  if (mesh.positions.empty() || mesh.triangles.empty()) {
    throw std::invalid_argument("OBJ scene must contain vertices and faces");
  }
  return mesh;
}

SceneMesh loadObjScene(const std::filesystem::path& path) {
  std::ifstream input(path);
  if (!input) {
    throw std::invalid_argument("could not read OBJ scene: " + path.string());
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return parseObjScene(buffer.str());
}

SceneGBuffer renderSceneGBuffer(const SceneMesh& mesh, SceneRenderOptions options) {
  if (options.width <= 0 || options.height <= 0) {
    throw std::invalid_argument("scene render dimensions must be positive");
  }
  SceneGBuffer buffer;
  buffer.albedo.w = options.width;
  buffer.albedo.h = options.height;
  buffer.albedo.rgb.assign(static_cast<std::size_t>(options.width) * static_cast<std::size_t>(options.height) * 3U, 0);
  buffer.depth.assign(static_cast<std::size_t>(options.width) * static_cast<std::size_t>(options.height), std::numeric_limits<double>::infinity());
  buffer.normals.assign(static_cast<std::size_t>(options.width) * static_cast<std::size_t>(options.height), SceneVec3{});

  std::vector<SceneVec3> rotated;
  rotated.reserve(mesh.positions.size());
  for (const SceneVec3 position : mesh.positions) {
    rotated.push_back(rotateY(position, options.time_seconds));
  }
  double min_x = rotated[0].x;
  double max_x = rotated[0].x;
  double min_y = rotated[0].y;
  double max_y = rotated[0].y;
  for (const SceneVec3 position : rotated) {
    min_x = std::min(min_x, position.x);
    max_x = std::max(max_x, position.x);
    min_y = std::min(min_y, position.y);
    max_y = std::max(max_y, position.y);
  }
  const double span_x = std::max(max_x - min_x, 1.0e-6);
  const double span_y = std::max(max_y - min_y, 1.0e-6);
  const double scale = 0.8 * std::min(static_cast<double>(options.width - 1) / span_x, static_cast<double>(options.height - 1) / span_y);
  const double offset_x = (static_cast<double>(options.width - 1) - (min_x + max_x) * scale) * 0.5;
  const double offset_y = (static_cast<double>(options.height - 1) + (min_y + max_y) * scale) * 0.5;

  for (const SceneTriangle& triangle : mesh.triangles) {
    const SceneVertexRef refs[3] = {triangle.a, triangle.b, triangle.c};
    ProjectedVertex vertices[3];
    for (int i = 0; i < 3; ++i) {
      const SceneVec3 position = rotated[static_cast<std::size_t>(refs[i].position)];
      vertices[i] = ProjectedVertex{
        .x = position.x * scale + offset_x,
        .y = offset_y - position.y * scale,
        .z = position.z,
        .normal = rotateY(vertexNormal(mesh, triangle, refs[i]), options.time_seconds),
      };
    }
    const double area = edge(vertices[0].x, vertices[0].y, vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y);
    if (std::abs(area) <= 1.0e-9) {
      continue;
    }
    const int min_px = std::clamp(static_cast<int>(std::floor(std::min({vertices[0].x, vertices[1].x, vertices[2].x}))), 0, options.width - 1);
    const int max_px = std::clamp(static_cast<int>(std::ceil(std::max({vertices[0].x, vertices[1].x, vertices[2].x}))), 0, options.width - 1);
    const int min_py = std::clamp(static_cast<int>(std::floor(std::min({vertices[0].y, vertices[1].y, vertices[2].y}))), 0, options.height - 1);
    const int max_py = std::clamp(static_cast<int>(std::ceil(std::max({vertices[0].y, vertices[1].y, vertices[2].y}))), 0, options.height - 1);
    for (int y = min_py; y <= max_py; ++y) {
      for (int x = min_px; x <= max_px; ++x) {
        const double px = static_cast<double>(x) + 0.5;
        const double py = static_cast<double>(y) + 0.5;
        const double w0 = edge(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, px, py) / area;
        const double w1 = edge(vertices[2].x, vertices[2].y, vertices[0].x, vertices[0].y, px, py) / area;
        const double w2 = edge(vertices[0].x, vertices[0].y, vertices[1].x, vertices[1].y, px, py) / area;
        if (w0 < 0.0 || w1 < 0.0 || w2 < 0.0) {
          continue;
        }
        const double depth = w0 * vertices[0].z + w1 * vertices[1].z + w2 * vertices[2].z;
        const SceneVec3 normal = add(add(mul(vertices[0].normal, w0), mul(vertices[1].normal, w1)), mul(vertices[2].normal, w2));
        putPixel(&buffer, options.width, x, y, depth, normal);
      }
    }
  }
  return buffer;
}

}  // namespace contourtty
