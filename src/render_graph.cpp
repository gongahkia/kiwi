#include "render_graph.hpp"

#include <algorithm>
#include <cstddef>
#include <deque>
#include <map>
#include <set>
#include <sstream>
#include <unordered_set>

namespace strok {
namespace {

std::unordered_map<std::string, std::any>::iterator findBuffer(std::unordered_map<std::string, std::any>& buffers, std::string_view name) {
  return buffers.find(std::string(name));
}

std::unordered_map<std::string, std::any>::const_iterator findBuffer(const std::unordered_map<std::string, std::any>& buffers, std::string_view name) {
  return buffers.find(std::string(name));
}

bool containsBackend(std::span<const Backend> backends, Backend backend) {
  return std::find(backends.begin(), backends.end(), backend) != backends.end();
}

Backend chooseBackend(const Pass& pass, std::span<const Backend> preference, std::span<const Backend> available) {
  if (pass.supports.empty()) {
    return Backend::Cpu;
  }
  for (const Backend backend : preference) {
    if (backend != Backend::Auto && containsBackend(pass.supports, backend) && containsBackend(available, backend)) {
      return backend;
    }
  }
  for (const Backend backend : pass.supports) {
    if (backend != Backend::Auto && containsBackend(available, backend)) {
      return backend;
    }
  }
  if (containsBackend(pass.supports, Backend::Cpu)) {
    return Backend::Cpu;
  }
  throw GraphError("no available backend for pass: " + pass.id);
}

std::string describePort(const PassPort& port) {
  std::ostringstream out;
  out << port.name << ':' << bufferKindName(port.desc.kind);
  if (port.desc.width > 0 || port.desc.height > 0) {
    out << '[' << port.desc.width << 'x' << port.desc.height << ']';
  }
  if (port.desc.sample_x != 1 || port.desc.sample_y != 1) {
    out << "@" << port.desc.sample_x << 'x' << port.desc.sample_y;
  }
  if (!port.desc.label.empty()) {
    out << '<' << port.desc.label << '>';
  }
  return out.str();
}

bool isExternal(const GraphBuildOptions& options, const std::string& input) {
  return std::find(options.external_inputs.begin(), options.external_inputs.end(), input) != options.external_inputs.end();
}

}  // namespace

PassContext::PassContext(Backend backend) : backend_(backend) {}

Backend PassContext::backend() const noexcept {
  return backend_;
}

void PassContext::setBackend(Backend backend) noexcept {
  backend_ = backend;
}

bool PassContext::hasBuffer(std::string_view name) const {
  return findBuffer(buffers_, name) != buffers_.end();
}

void PassContext::eraseBuffer(std::string_view name) {
  const auto found = findBuffer(buffers_, name);
  if (found != buffers_.end()) {
    buffers_.erase(found);
  }
}

std::any& PassContext::bufferAny(std::string_view name) {
  const auto found = findBuffer(buffers_, name);
  if (found == buffers_.end()) {
    throw GraphError("missing buffer: " + std::string(name));
  }
  return found->second;
}

const std::any& PassContext::bufferAny(std::string_view name) const {
  const auto found = findBuffer(buffers_, name);
  if (found == buffers_.end()) {
    throw GraphError("missing buffer: " + std::string(name));
  }
  return found->second;
}

void Graph::run(PassContext& context) const {
  for (const Pass& pass : ordered) {
    context.setBackend(pass.backend);
    if (pass.run) {
      pass.run(context);
    }
  }
}

void Graph::run(PassContext& context, const PassCallbackMap& callbacks) const {
  if (callbacks.size() != ordered.size()) {
    throw GraphError("render callback set does not match graph topology");
  }
  for (const Pass& pass : ordered) {
    const auto callback = callbacks.find(pass.id);
    if (callback == callbacks.end()) {
      throw GraphError("missing render callback for pass: " + pass.id);
    }
    context.setBackend(pass.backend);
    if (callback->second) {
      callback->second(context);
    }
  }
}

std::string Graph::dump() const {
  std::ostringstream out;
  for (const Pass& pass : ordered) {
    out << pass.id << '(' << backendName(pass.backend) << ')';
    out << "  ";
    for (std::size_t i = 0; i < pass.inputs.size(); ++i) {
      if (i > 0) {
        out << ", ";
      }
      out << describePort(pass.inputs[i]);
    }
    out << " -> ";
    for (std::size_t i = 0; i < pass.outputs.size(); ++i) {
      if (i > 0) {
        out << ", ";
      }
      out << describePort(pass.outputs[i]);
    }
    out << '\n';
  }
  return out.str();
}

Graph buildGraph(std::vector<Pass> passes, const GraphBuildOptions& options) {
  std::unordered_set<std::string> pass_ids;
  struct ProducedBuffer {
    std::size_t pass_index = 0;
    BufferDesc desc;
  };
  std::map<std::string, ProducedBuffer> producer_by_output;
  for (std::size_t index = 0; index < passes.size(); ++index) {
    Pass& pass = passes[index];
    if (pass.id.empty()) {
      throw GraphError("pass id must not be empty");
    }
    if (!pass_ids.insert(pass.id).second) {
      throw GraphError("duplicate pass id: " + pass.id);
    }
    pass.backend = chooseBackend(pass, options.backend_preference, options.available_backends);
    for (const PassPort& output : pass.outputs) {
      if (output.name.empty()) {
        throw GraphError("pass output name must not be empty: " + pass.id);
      }
      const auto inserted = producer_by_output.emplace(output.name, ProducedBuffer{.pass_index = index, .desc = output.desc});
      if (!inserted.second) {
        throw GraphError("duplicate graph output: " + output.name);
      }
    }
  }

  std::vector<std::set<std::size_t>> dependencies(passes.size());
  std::vector<std::vector<std::size_t>> consumers(passes.size());
  for (std::size_t index = 0; index < passes.size(); ++index) {
    for (const PassPort& input : passes[index].inputs) {
      if (input.name.empty()) {
        throw GraphError("pass input name must not be empty: " + passes[index].id);
      }
      const auto producer = producer_by_output.find(input.name);
      if (producer == producer_by_output.end()) {
        if (isExternal(options, input.name)) {
          continue;
        }
        throw GraphError("missing graph input: " + input.name);
      }
      if (input.desc != producer->second.desc) {
        const PassPort produced_port{.name = input.name, .desc = producer->second.desc};
        throw GraphError("graph descriptor mismatch: " + passes[producer->second.pass_index].id + " output " +
                         describePort(produced_port) + " does not satisfy " + passes[index].id + " input " +
                         describePort(input));
      }
      dependencies[index].insert(producer->second.pass_index);
    }
  }
  for (std::size_t consumer = 0; consumer < dependencies.size(); ++consumer) {
    for (const std::size_t producer : dependencies[consumer]) {
      consumers[producer].push_back(consumer);
    }
  }

  std::deque<std::size_t> ready;
  std::vector<int> indegree(passes.size(), 0);
  std::vector<bool> enqueued(passes.size(), false);
  for (std::size_t index = 0; index < passes.size(); ++index) {
    indegree[index] = static_cast<int>(dependencies[index].size());
    if (indegree[index] == 0) {
      ready.push_back(index);
      enqueued[index] = true;
    }
  }

  Graph graph;
  graph.ordered.reserve(passes.size());
  while (!ready.empty()) {
    const std::size_t index = ready.front();
    ready.pop_front();
    graph.ordered.push_back(std::move(passes[index]));
    for (const std::size_t consumer : consumers[index]) {
      --indegree[consumer];
      if (indegree[consumer] == 0 && !enqueued[consumer]) {
        ready.push_back(consumer);
        enqueued[consumer] = true;
      }
    }
  }
  if (graph.ordered.size() != passes.size()) {
    throw GraphError("render graph contains a cycle");
  }
  return graph;
}

std::string_view bufferKindName(BufferKind kind) noexcept {
  switch (kind) {
    case BufferKind::RgbFrame:
      return "RgbFrame";
    case BufferKind::LuminanceField:
      return "LuminanceField";
    case BufferKind::GradientField:
      return "GradientField";
    case BufferKind::EdgeField:
      return "EdgeField";
    case BufferKind::CellGlyphs:
      return "CellGlyphs";
    case BufferKind::CellColors:
      return "CellColors";
    case BufferKind::CellShapeVectors:
      return "CellShapeVectors";
    case BufferKind::OpticalFlow:
      return "OpticalFlow";
    case BufferKind::DepthBuffer:
      return "DepthBuffer";
    case BufferKind::NormalBuffer:
      return "NormalBuffer";
    case BufferKind::Custom:
      return "Custom";
  }
  return "Custom";
}

std::string_view backendName(Backend backend) noexcept {
  switch (backend) {
    case Backend::Cpu:
      return "cpu";
    case Backend::Metal:
      return "metal";
    case Backend::Vulkan:
      return "vulkan";
    case Backend::Auto:
      return "auto";
  }
  return "auto";
}

}  // namespace strok
