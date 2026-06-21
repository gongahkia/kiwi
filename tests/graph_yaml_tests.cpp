#include "graph_yaml.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool throwsUnknownPass() {
  try {
    (void)contourtty::parseGraphYaml("passes:\n  - id: nope\n");
  } catch (const contourtty::GraphYamlError&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  const contourtty::GraphYaml graph = contourtty::parseGraphYaml(
    "passes:\n"
    "  - id: kuwahara\n"
    "  - id: etf\n"
    "    params: { iters: 4 }\n"
    "  - id: crosshatch\n"
    "  - id: stipple\n");
  expect(graph.passes.size() == 4, "graph yaml pass count");
  expect(graph.passes[1].params.at("iters") == "4", "graph yaml inline params");

  contourtty::CliOptions options;
  contourtty::applyGraphYamlToOptions(graph, &options);
  expect(options.graph_passes.size() == 4, "graph yaml stores pass ids");
  expect(options.etf_iters.has_value() && *options.etf_iters == 4, "graph yaml applies etf params");
  expect(throwsUnknownPass(), "graph yaml rejects unknown pass");
}
