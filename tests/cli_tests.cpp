#include "cli.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  {
    const char* argv[] = {"contourtty", "--dog-sigma", "0"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "dog sigma 0 parses");
    expect(parsed.options.dog_sigma.has_value() && *parsed.options.dog_sigma == 0.0, "dog sigma disables");
    expect(!parsed.options.dog_sigma2.has_value(), "dog sigma2 absent for disable");
  }

  {
    const char* argv[] = {"contourtty", "--dog-sigma", "0.8,1.6", "--dog-threshold", "0.04"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "dog sigma pair parses");
    expect(parsed.options.dog_sigma.has_value() && *parsed.options.dog_sigma == 0.8, "dog sigma1 stored");
    expect(parsed.options.dog_sigma2.has_value() && *parsed.options.dog_sigma2 == 1.6, "dog sigma2 stored");
    expect(parsed.options.dog_threshold.has_value() && *parsed.options.dog_threshold == 0.04, "dog threshold stored");
  }

  {
    const char* argv[] = {"contourtty", "--dog-sigma", "1.0,0.5"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "dog sigma rejects reversed pair");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "structure", "--charset", ".#"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "mode and charset parse");
    expect(parsed.options.mode == "structure", "mode stored");
    expect(parsed.options.charset.has_value() && *parsed.options.charset == ".#", "charset stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "invalid"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "mode rejects invalid value");
  }

  {
    const char* argv[] = {"contourtty", "--charset", ""};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "charset rejects empty value");
  }

  {
    const char* argv[] = {"contourtty", "--edge-threshold", "0.25", "--contrast", "2"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "edge threshold and contrast parse");
    expect(parsed.options.edge_threshold.has_value() && *parsed.options.edge_threshold == 0.25, "edge threshold stored");
    expect(parsed.options.contrast.has_value() && *parsed.options.contrast == 2.0, "contrast stored");
  }

  {
    const char* argv[] = {"contourtty", "--edge-strength", "1.5"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "edge strength parses");
    expect(parsed.options.edge_strength.has_value() && *parsed.options.edge_strength == 1.5, "edge strength stored");
  }

  {
    const char* argv[] = {"contourtty", "--edge-strength", "-1"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "edge strength rejects negative");
  }
}
