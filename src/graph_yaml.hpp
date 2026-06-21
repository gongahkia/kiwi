#pragma once

#include "cli.hpp"

#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace contourtty {

struct GraphYamlPass {
  std::string id;
  std::unordered_map<std::string, std::string> params;
  std::string backend;
};

struct GraphYaml {
  std::vector<GraphYamlPass> passes;
};

class GraphYamlError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

GraphYaml parseGraphYaml(std::string_view text);
GraphYaml loadGraphYamlFile(const std::filesystem::path& path);
void applyGraphYamlToOptions(const GraphYaml& graph, CliOptions* options);

}  // namespace contourtty
