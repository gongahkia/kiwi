#include "render_graph.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

contourtty::PassPort port(std::string name, contourtty::BufferKind kind) {
  return contourtty::PassPort{
    .name = std::move(name),
    .desc = contourtty::BufferDesc{.kind = kind},
  };
}

std::vector<std::string> ids(const contourtty::Graph& graph) {
  std::vector<std::string> result;
  for (const contourtty::Pass& pass : graph.ordered) {
    result.push_back(pass.id);
  }
  return result;
}

bool throwsGraphError(const std::function<void()>& body) {
  try {
    body();
  } catch (const contourtty::GraphError&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  {
    std::vector<contourtty::Pass> passes;
    passes.push_back(contourtty::Pass{
      .id = "sobel",
      .inputs = {port("luma", contourtty::BufferKind::LuminanceField)},
      .outputs = {port("gradient", contourtty::BufferKind::GradientField)},
      .supports = {contourtty::Backend::Cpu},
    });
    passes.push_back(contourtty::Pass{
      .id = "luminance",
      .inputs = {port("frame", contourtty::BufferKind::RgbFrame)},
      .outputs = {port("luma", contourtty::BufferKind::LuminanceField)},
      .supports = {contourtty::Backend::Cpu},
    });
    passes.push_back(contourtty::Pass{
      .id = "decode",
      .outputs = {port("frame", contourtty::BufferKind::RgbFrame)},
      .supports = {contourtty::Backend::Cpu},
    });
    const contourtty::Graph graph = contourtty::buildGraph(std::move(passes));
    expect(ids(graph) == std::vector<std::string>({"decode", "luminance", "sobel"}), "topological sort orders dependencies");
  }

  {
    std::vector<contourtty::Pass> passes;
    passes.push_back(contourtty::Pass{
      .id = "a",
      .inputs = {port("b-out", contourtty::BufferKind::Custom)},
      .outputs = {port("a-out", contourtty::BufferKind::Custom)},
      .supports = {contourtty::Backend::Cpu},
    });
    passes.push_back(contourtty::Pass{
      .id = "b",
      .inputs = {port("a-out", contourtty::BufferKind::Custom)},
      .outputs = {port("b-out", contourtty::BufferKind::Custom)},
      .supports = {contourtty::Backend::Cpu},
    });
    expect(throwsGraphError([&] { (void)contourtty::buildGraph(std::move(passes)); }), "cycle detection rejects cyclic graph");
  }

  {
    std::vector<contourtty::Pass> passes;
    passes.push_back(contourtty::Pass{
      .id = "reader",
      .inputs = {port("external-frame", contourtty::BufferKind::RgbFrame)},
      .outputs = {port("luma", contourtty::BufferKind::LuminanceField)},
      .supports = {contourtty::Backend::Cpu},
    });
    const contourtty::Graph graph = contourtty::buildGraph(std::move(passes), contourtty::GraphBuildOptions{.external_inputs = {"external-frame"}});
    expect(ids(graph) == std::vector<std::string>({"reader"}), "declared external input accepted");
    expect(throwsGraphError([&] {
      std::vector<contourtty::Pass> missing;
      missing.push_back(contourtty::Pass{
        .id = "reader",
        .inputs = {port("missing-frame", contourtty::BufferKind::RgbFrame)},
        .outputs = {port("luma", contourtty::BufferKind::LuminanceField)},
        .supports = {contourtty::Backend::Cpu},
      });
      (void)contourtty::buildGraph(std::move(missing));
    }), "missing input rejected");
  }

  {
    std::vector<std::string> executed;
    std::vector<contourtty::Pass> passes;
    passes.push_back(contourtty::Pass{
      .id = "first",
      .outputs = {port("x", contourtty::BufferKind::Custom)},
      .supports = {contourtty::Backend::Cpu},
      .run = [&](contourtty::PassContext& context) {
        executed.push_back("first");
        context.setBuffer("x", 7);
      },
    });
    passes.push_back(contourtty::Pass{
      .id = "second",
      .inputs = {port("x", contourtty::BufferKind::Custom)},
      .outputs = {port("y", contourtty::BufferKind::Custom)},
      .supports = {contourtty::Backend::Cpu},
      .run = [&](contourtty::PassContext& context) {
        executed.push_back("second");
        context.setBuffer("y", context.buffer<int>("x") + 5);
      },
    });
    const contourtty::Graph graph = contourtty::buildGraph(std::move(passes));
    contourtty::PassContext context;
    graph.run(context);
    expect(executed == std::vector<std::string>({"first", "second"}), "graph run follows topological order");
    expect(context.buffer<int>("y") == 12, "pass context stores buffers");
  }

  {
    std::vector<contourtty::Pass> passes;
    passes.push_back(contourtty::Pass{
      .id = "gpu-capable",
      .outputs = {port("x", contourtty::BufferKind::Custom)},
      .supports = {contourtty::Backend::Metal, contourtty::Backend::Cpu},
    });
    const contourtty::Graph graph = contourtty::buildGraph(std::move(passes), contourtty::GraphBuildOptions{.backend_preference = {contourtty::Backend::Vulkan, contourtty::Backend::Cpu}});
    expect(graph.ordered.front().backend == contourtty::Backend::Cpu, "backend fallback picks supported preferred backend");
    expect(graph.dump() == "gpu-capable(cpu)   -> x:Custom\n", "deterministic graph dump");
  }
}
