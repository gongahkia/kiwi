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

strok::PassPort port(std::string name, strok::BufferKind kind) {
  return strok::PassPort{
    .name = std::move(name),
    .desc = strok::BufferDesc{.kind = kind},
  };
}

std::vector<std::string> ids(const strok::Graph& graph) {
  std::vector<std::string> result;
  for (const strok::Pass& pass : graph.ordered) {
    result.push_back(pass.id);
  }
  return result;
}

bool throwsGraphError(const std::function<void()>& body) {
  try {
    body();
  } catch (const strok::GraphError&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  {
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "sobel",
      .inputs = {port("luma", strok::BufferKind::LuminanceField)},
      .outputs = {port("gradient", strok::BufferKind::GradientField)},
      .supports = {strok::Backend::Cpu},
    });
    passes.push_back(strok::Pass{
      .id = "luminance",
      .inputs = {port("frame", strok::BufferKind::RgbFrame)},
      .outputs = {port("luma", strok::BufferKind::LuminanceField)},
      .supports = {strok::Backend::Cpu},
    });
    passes.push_back(strok::Pass{
      .id = "decode",
      .outputs = {port("frame", strok::BufferKind::RgbFrame)},
      .supports = {strok::Backend::Cpu},
    });
    const strok::Graph graph = strok::buildGraph(std::move(passes));
    expect(ids(graph) == std::vector<std::string>({"decode", "luminance", "sobel"}), "topological sort orders dependencies");
  }

  {
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "a",
      .inputs = {port("b-out", strok::BufferKind::Custom)},
      .outputs = {port("a-out", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Cpu},
    });
    passes.push_back(strok::Pass{
      .id = "b",
      .inputs = {port("a-out", strok::BufferKind::Custom)},
      .outputs = {port("b-out", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Cpu},
    });
    expect(throwsGraphError([&] { (void)strok::buildGraph(std::move(passes)); }), "cycle detection rejects cyclic graph");
  }

  {
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "reader",
      .inputs = {port("external-frame", strok::BufferKind::RgbFrame)},
      .outputs = {port("luma", strok::BufferKind::LuminanceField)},
      .supports = {strok::Backend::Cpu},
    });
    const strok::Graph graph = strok::buildGraph(std::move(passes), strok::GraphBuildOptions{.external_inputs = {"external-frame"}});
    expect(ids(graph) == std::vector<std::string>({"reader"}), "declared external input accepted");
    expect(throwsGraphError([&] {
      std::vector<strok::Pass> missing;
      missing.push_back(strok::Pass{
        .id = "reader",
        .inputs = {port("missing-frame", strok::BufferKind::RgbFrame)},
        .outputs = {port("luma", strok::BufferKind::LuminanceField)},
        .supports = {strok::Backend::Cpu},
      });
      (void)strok::buildGraph(std::move(missing));
    }), "missing input rejected");
  }

  {
    std::vector<std::string> executed;
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "first",
      .outputs = {port("x", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Cpu},
      .run = [&](strok::PassContext& context) {
        executed.push_back("first");
        context.setBuffer("x", 7);
      },
    });
    passes.push_back(strok::Pass{
      .id = "second",
      .inputs = {port("x", strok::BufferKind::Custom)},
      .outputs = {port("y", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Cpu},
      .run = [&](strok::PassContext& context) {
        executed.push_back("second");
        context.setBuffer("y", context.buffer<int>("x") + 5);
      },
    });
    const strok::Graph graph = strok::buildGraph(std::move(passes));
    strok::PassContext context;
    graph.run(context);
    expect(executed == std::vector<std::string>({"first", "second"}), "graph run follows topological order");
    expect(context.buffer<int>("y") == 12, "pass context stores buffers");
  }

  {
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "gpu-capable",
      .outputs = {port("x", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Metal, strok::Backend::Cpu},
    });
    const strok::Graph graph = strok::buildGraph(std::move(passes), strok::GraphBuildOptions{.backend_preference = {strok::Backend::Vulkan, strok::Backend::Cpu}});
    expect(graph.ordered.front().backend == strok::Backend::Cpu, "backend fallback picks supported preferred backend");
    expect(graph.dump() == "gpu-capable(cpu)   -> x:Custom\n", "deterministic graph dump");
  }

  {
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "gpu-capable",
      .outputs = {port("x", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Metal, strok::Backend::Cpu},
    });
    const strok::Graph graph = strok::buildGraph(std::move(passes), strok::GraphBuildOptions{
      .backend_preference = {strok::Backend::Metal, strok::Backend::Cpu},
      .available_backends = {strok::Backend::Cpu},
    });
    expect(graph.ordered.front().backend == strok::Backend::Cpu, "unavailable requested gpu falls back to cpu");
  }

  {
    std::vector<strok::Pass> passes;
    passes.push_back(strok::Pass{
      .id = "gpu-capable",
      .outputs = {port("x", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Metal, strok::Backend::Cpu},
    });
    passes.push_back(strok::Pass{
      .id = "cpu-only",
      .inputs = {port("x", strok::BufferKind::Custom)},
      .outputs = {port("y", strok::BufferKind::Custom)},
      .supports = {strok::Backend::Cpu},
    });
    const strok::Graph graph = strok::buildGraph(std::move(passes), strok::GraphBuildOptions{
      .backend_preference = {strok::Backend::Metal, strok::Backend::Cpu},
      .available_backends = {strok::Backend::Cpu, strok::Backend::Metal},
    });
    expect(graph.ordered[0].backend == strok::Backend::Metal, "gpu-capable pass binds metal");
    expect(graph.ordered[1].backend == strok::Backend::Cpu, "cpu-only pass stays cpu");
    expect(graph.dump() ==
             "gpu-capable(metal)   -> x:Custom\n"
             "cpu-only(cpu)  x:Custom -> y:Custom\n",
           "per-pass backend dump");
  }
}
