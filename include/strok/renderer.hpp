#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"
#include "renderer_config.hpp"
#include "render_grid.hpp"
#include "render_result.hpp"

#include <memory>
#include <string_view>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
class Renderer {
 public:
  struct CreateResult {
    std::unique_ptr<Renderer> renderer;
    RenderResult result;

    bool succeeded() const noexcept {
      return renderer != nullptr && result.succeeded();
    }
  };

  static CreateResult create(RendererConfig config, RenderGrid grid);

  Renderer(const Renderer&) = delete;
  Renderer& operator=(const Renderer&) = delete;
  Renderer(Renderer&&) = delete;
  Renderer& operator=(Renderer&&) = delete;
  ~Renderer();

  RenderResult render(const Frame& frame, std::u32string_view ramp, CellBuffer* output);
  void reset();

 private:
  struct State;

  explicit Renderer(RendererConfig config, RenderGrid grid);

  std::unique_ptr<State> state_;
};

}  // namespace strok
