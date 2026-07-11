#include "graph_yaml.hpp"

#include <algorithm>
#include <charconv>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_set>

namespace strok {
namespace {

std::string trim(std::string_view value) {
  while (!value.empty() && (value.front() == ' ' || value.front() == '\t' || value.front() == '\r')) {
    value.remove_prefix(1);
  }
  while (!value.empty() && (value.back() == ' ' || value.back() == '\t' || value.back() == '\r')) {
    value.remove_suffix(1);
  }
  return std::string(value);
}

std::string stripQuotes(std::string value) {
  if (value.size() >= 2 && ((value.front() == '"' && value.back() == '"') || (value.front() == '\'' && value.back() == '\''))) {
    value.erase(value.begin());
    value.pop_back();
  }
  return value;
}

std::string stripComment(std::string_view line) {
  bool quoted = false;
  char quote = '\0';
  for (std::size_t index = 0; index < line.size(); ++index) {
    const char ch = line[index];
    if ((ch == '"' || ch == '\'') && (index == 0 || line[index - 1] != '\\')) {
      if (!quoted) {
        quoted = true;
        quote = ch;
      } else if (quote == ch) {
        quoted = false;
      }
    }
    if (ch == '#' && !quoted) {
      return trim(line.substr(0, index));
    }
  }
  return trim(line);
}

bool startsWith(std::string_view value, std::string_view prefix) {
  return value.substr(0, prefix.size()) == prefix;
}

bool knownPassId(const std::string& id) {
  static const std::unordered_set<std::string> ids{
    "decode", "kuwahara", "posterize", "luminance", "contrast", "dog", "sobel", "etf",
    "edge-field", "optical-flow", "cell-average", "ramp-pick", "cell-shape", "warp-history", "overlay-structure",
    "shape-match", "crosshatch", "lic", "stipple", "line-ligatures", "emit",
    "halfblock", "blocks", "octant", "sextant", "braille",
  };
  return ids.contains(id);
}

std::unordered_map<std::string, std::string> parseInlineParams(std::string value, int line_number) {
  value = trim(value);
  if (value.empty()) {
    return {};
  }
  if (value.front() != '{' || value.back() != '}') {
    throw GraphYamlError("line " + std::to_string(line_number) + ": params must use inline { key: value } syntax");
  }
  value = value.substr(1, value.size() - 2);
  std::unordered_map<std::string, std::string> params;
  std::size_t start = 0;
  while (start < value.size()) {
    const std::size_t comma = value.find(',', start);
    const std::string item = trim(value.substr(start, comma == std::string::npos ? std::string::npos : comma - start));
    if (!item.empty()) {
      const std::size_t colon = item.find(':');
      if (colon == std::string::npos) {
        throw GraphYamlError("line " + std::to_string(line_number) + ": invalid params entry");
      }
      params[trim(item.substr(0, colon))] = stripQuotes(trim(item.substr(colon + 1)));
    }
    if (comma == std::string::npos) {
      break;
    }
    start = comma + 1;
  }
  return params;
}

int parseIntParam(const std::unordered_map<std::string, std::string>& params, const std::string& key, int fallback) {
  const auto found = params.find(key);
  if (found == params.end()) {
    return fallback;
  }
  int value = 0;
  const std::string& text = found->second;
  const auto result = std::from_chars(text.data(), text.data() + text.size(), value);
  if (result.ec != std::errc{} || result.ptr != text.data() + text.size()) {
    throw GraphYamlError("invalid integer param " + key + ": " + text);
  }
  return value;
}

double parseDoubleParam(const std::unordered_map<std::string, std::string>& params, const std::string& key, double fallback) {
  const auto found = params.find(key);
  if (found == params.end()) {
    return fallback;
  }
  char* end = nullptr;
  const std::string copy = found->second;
  const double value = std::strtod(copy.c_str(), &end);
  if (end != copy.c_str() + copy.size()) {
    throw GraphYamlError("invalid numeric param " + key + ": " + copy);
  }
  return value;
}

bool hasGraphPass(const GraphYaml& graph, const std::string& id) {
  return std::any_of(graph.passes.begin(), graph.passes.end(), [&](const GraphYamlPass& pass) {
    return pass.id == id;
  });
}

}  // namespace

GraphYaml parseGraphYaml(std::string_view text) {
  GraphYaml graph;
  bool in_passes = false;
  GraphYamlPass* current = nullptr;
  std::istringstream input{std::string(text)};
  std::string raw_line;
  int line_number = 0;
  while (std::getline(input, raw_line)) {
    ++line_number;
    const std::string line = stripComment(raw_line);
    if (line.empty()) {
      continue;
    }
    if (line == "passes:") {
      in_passes = true;
      continue;
    }
    if (!in_passes) {
      throw GraphYamlError("line " + std::to_string(line_number) + ": expected passes:");
    }
    if (startsWith(line, "- id:")) {
      const std::string id = stripQuotes(trim(std::string_view(line).substr(5)));
      if (!knownPassId(id)) {
        throw GraphYamlError("line " + std::to_string(line_number) + ": unknown pass id " + id);
      }
      graph.passes.push_back(GraphYamlPass{.id = id});
      current = &graph.passes.back();
      continue;
    }
    if (current == nullptr) {
      throw GraphYamlError("line " + std::to_string(line_number) + ": pass property before id");
    }
    if (startsWith(line, "backend:")) {
      current->backend = stripQuotes(trim(std::string_view(line).substr(8)));
      if (current->backend != "cpu" && current->backend != "gpu" && current->backend != "metal" && current->backend != "vulkan") {
        throw GraphYamlError("line " + std::to_string(line_number) + ": invalid backend " + current->backend);
      }
      continue;
    }
    if (startsWith(line, "params:")) {
      current->params = parseInlineParams(trim(std::string_view(line).substr(7)), line_number);
      continue;
    }
    throw GraphYamlError("line " + std::to_string(line_number) + ": unsupported graph yaml syntax");
  }
  if (!in_passes || graph.passes.empty()) {
    throw GraphYamlError("graph yaml must contain at least one pass");
  }
  return graph;
}

GraphYaml loadGraphYamlFile(const std::filesystem::path& path) {
  std::ifstream input(path);
  if (!input) {
    throw GraphYamlError("could not read graph file: " + path.string());
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return parseGraphYaml(buffer.str());
}

void applyGraphYamlToOptions(const GraphYaml& graph, CliOptions* options) {
  if (options == nullptr) {
    throw GraphYamlError("options must not be null");
  }
  options->graph_passes.clear();
  for (const GraphYamlPass& pass : graph.passes) {
    options->graph_passes.push_back(pass.id);
    if (pass.id == "halfblock" || pass.id == "blocks" || pass.id == "octant" || pass.id == "sextant" || pass.id == "braille") {
      options->mode = pass.id;
    } else if (pass.id == "dog") {
      if (pass.params.contains("sigma1")) {
        options->dog_sigma = parseDoubleParam(pass.params, "sigma1", 0.0);
      }
      if (pass.params.contains("sigma2")) {
        options->dog_sigma2 = parseDoubleParam(pass.params, "sigma2", 0.0);
      }
      if (pass.params.contains("threshold")) {
        options->dog_threshold = parseDoubleParam(pass.params, "threshold", 0.0);
      }
    } else if (pass.id == "etf") {
      options->etf_iters = parseIntParam(pass.params, "iters", 2);
    } else if (pass.id == "contrast") {
      options->contrast = parseDoubleParam(pass.params, "amount", parseDoubleParam(pass.params, "gain", 0.0));
    } else if (pass.id == "edge-field") {
      if (pass.params.contains("threshold")) {
        options->edge_threshold = parseDoubleParam(pass.params, "threshold", 0.0);
      }
    } else if (pass.id == "posterize") {
      options->posterize = parseIntParam(pass.params, "levels", 4);
    } else if (pass.id == "lic") {
      options->lic_length = parseIntParam(pass.params, "length", 8);
    }
  }
  if (hasGraphPass(graph, "line-ligatures")) {
    options->line_ligatures = true;
  }
}

}  // namespace strok
