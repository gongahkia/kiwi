#include "renderer_cli_adapter.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame frame() {
  return strok::Frame{
    .w = 2,
    .h = 2,
    .rgb = {0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64},
  };
}

}  // namespace

int main() {
  strok::CliOptions options;
  options.width = 2;
  options.height = 2;
  const strok::TerminalSize terminal{.cols = 2, .rows = 2};
  const strok::Frame input = frame();

  strok::CliRendererSession session;
  strok::CellBuffer first_cells;
  strok::RenderStats accumulated;
  const strok::RenderResult first = session.render(input, nullptr, options, terminal, &first_cells, &accumulated);
  expect(first.succeeded(), "first session render");
  expect(first.stats.graph_topology_builds == 0 && first.stats.graph_topology_reuses == 1, "first render reuses session graph");

  strok::CellBuffer second_cells;
  const strok::RenderResult second = session.render(input, nullptr, options, terminal, &second_cells, &accumulated);
  expect(second.succeeded(), "second session render");
  expect(second.stats.graph_topology_builds == 0 && second.stats.graph_topology_reuses == 1, "second render retains session graph");
  expect(first_cells == second_cells, "persistent session preserves output");
  expect(accumulated.graph_topology_builds == 0 && accumulated.graph_topology_reuses == 2, "accumulated graph metrics");

  session.reset();
  const strok::RenderResult after_reset = session.render(input, nullptr, options, terminal, &second_cells);
  expect(after_reset.succeeded() && after_reset.stats.graph_topology_reuses == 1, "reset creates and reuses a fresh graph");
}
