#include "split.hpp"

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
    const auto parsed = strok::parseSplitSpec("luminance:structure");
    expect(parsed.has_value(), "split parses");
    expect(parsed->left == "luminance", "split left");
    expect(parsed->right == "structure", "split right");
    expect(!strok::parseSplitSpec("luminance").has_value(), "split rejects missing side");
    expect(!strok::parseSplitSpec("luminance:bad").has_value(), "split rejects bad branch");
  }

  {
    const auto parsed = strok::parseSplitGraphSpec("a.yaml,b.yaml");
    expect(parsed.has_value(), "graph split parses");
    expect(parsed->left == "a.yaml", "graph split left");
    expect(parsed->right == "b.yaml", "graph split right");
    expect(!strok::parseSplitGraphSpec("a.yaml,b.yaml,c.yaml").has_value(), "graph split rejects triples");
  }

  {
    expect(strok::defaultSplitSeam(9) == 4, "default seam");
    expect(strok::clampSplitSeam(-4, 9) == 1, "clamp seam low");
    expect(strok::clampSplitSeam(99, 9) == 7, "clamp seam high");
    const strok::SplitLayout layout = strok::splitLayout(9, 4);
    expect(layout.left_cols == 4 && layout.seam_col == 4 && layout.right_cols == 4, "layout halves");
  }

  {
    strok::CellBuffer left(2, 1);
    strok::CellBuffer right(2, 1);
    left.at(0, 0).glyph = U'L';
    left.at(1, 0).glyph = U'l';
    right.at(0, 0).glyph = U'R';
    right.at(1, 0).glyph = U'r';
    strok::CellBuffer output;
    strok::composeSplitCells(left, right, strok::splitLayout(5, 2), &output);
    expect(output.cols() == 5 && output.rows() == 1, "compose size");
    expect(output.at(0, 0).glyph == U'L', "compose left first");
    expect(output.at(1, 0).glyph == U'l', "compose left second");
    expect(output.at(2, 0).glyph == U'┃', "compose seam");
    expect(output.at(3, 0).glyph == U'R', "compose right first");
    expect(output.at(4, 0).glyph == U'r', "compose right second");
  }

  {
    strok::CliOptions options;
    strok::applySplitBranch("structure", &options);
    expect(options.mode == "structure", "apply split mode");
    expect(options.pipeline.has_value() && *options.pipeline == "structure", "apply split pipeline");
  }
}
