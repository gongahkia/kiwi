#pragma once

#include "cell_buffer.hpp"
#include "color_image_view.hpp"
#include "frame.hpp"
#include "renderer_config.hpp"
#include "render_grid.hpp"
#include "render_input.hpp"
#include "render_result.hpp"

#include <memory>
#include <string_view>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
// A Renderer owns one ordered temporal stream. Its temporal features advance once per
// successful render call and use no wall clock, timestamp, or inferred delta; Frame
// PTS metadata remains frontend-owned. Use one Renderer per independent stream and
// call reset before a source discontinuity or when intentionally starting a sequence.
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

  // The returned reference remains valid until the next render, reset, or destruction.
  // All render overloads are fixed-step temporal samples; RenderInput intentionally
  // carries no timing and Frame::pts_us does not affect core reconstruction.
  RenderResult render(const Frame& frame);
  RenderResult render(const ColorImageView& image);
  RenderResult render(const RenderInput& input);
  const CellBuffer& cells() const noexcept;
  RenderResult render(const Frame& frame, CellBuffer* output);
  RenderResult render(const ColorImageView& image, CellBuffer* output);
  RenderResult render(const RenderInput& input, CellBuffer* output);
  // Clears temporal history without changing the most recently rendered cells.
  void reset();

 private:
  struct State;

  explicit Renderer(RendererConfig config, RenderGrid grid);

  std::unique_ptr<State> state_;
};

}  // namespace strok
