#pragma once

#include <any>
#include <functional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace contourtty {

enum class BufferKind {
  RgbFrame,
  LuminanceField,
  GradientField,
  EdgeField,
  CellGlyphs,
  CellColors,
  CellShapeVectors,
  OpticalFlow,
  DepthBuffer,
  NormalBuffer,
  Custom,
};

struct BufferDesc {
  BufferKind kind = BufferKind::Custom;
  int width = 0;
  int height = 0;
  int sample_x = 1;
  int sample_y = 1;
  std::string label;

  bool operator==(const BufferDesc& other) const = default;
};

struct PassPort {
  std::string name;
  BufferDesc desc;

  bool operator==(const PassPort& other) const = default;
};

enum class Backend {
  Cpu,
  Metal,
  Vulkan,
  Auto,
};

class PassContext {
 public:
  explicit PassContext(Backend backend = Backend::Cpu);

  Backend backend() const noexcept;
  void setBackend(Backend backend) noexcept;
  bool hasBuffer(std::string_view name) const;
  void eraseBuffer(std::string_view name);

  template <typename T>
  void setBuffer(std::string name, T value) {
    buffers_[std::move(name)] = std::move(value);
  }

  template <typename T>
  T& buffer(std::string_view name) {
    return std::any_cast<T&>(bufferAny(name));
  }

  template <typename T>
  const T& buffer(std::string_view name) const {
    return std::any_cast<const T&>(bufferAny(name));
  }

 private:
  std::any& bufferAny(std::string_view name);
  const std::any& bufferAny(std::string_view name) const;

  Backend backend_ = Backend::Cpu;
  std::unordered_map<std::string, std::any> buffers_;
};

struct Pass {
  std::string id;
  std::vector<PassPort> inputs;
  std::vector<PassPort> outputs;
  std::vector<Backend> supports;
  Backend backend = Backend::Auto;
  std::function<void(PassContext&)> run;
};

struct GraphBuildOptions {
  std::vector<std::string> external_inputs;
  std::vector<Backend> backend_preference = {Backend::Cpu};
  std::vector<Backend> available_backends = {Backend::Cpu};
};

struct Graph {
  std::vector<Pass> ordered;

  void run(PassContext& context) const;
  std::string dump() const;
};

class GraphError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

Graph buildGraph(std::vector<Pass> passes, const GraphBuildOptions& options = {});

std::string_view bufferKindName(BufferKind kind) noexcept;
std::string_view backendName(Backend backend) noexcept;

}  // namespace contourtty
