#include "diff_emitter.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Cell cell(char32_t glyph, uint8_t r, uint8_t g, uint8_t b) {
  return strok::Cell{
    .glyph = glyph,
    .fg = strok::Rgb{.r = r, .g = g, .b = b},
    .bg = strok::Rgb{.r = 0, .g = 0, .b = 0},
  };
}

}  // namespace

int main() {
  strok::CellBuffer frame(3, 1);
  frame.at(0, 0) = cell(U'A', 255, 0, 0);
  frame.at(1, 0) = cell(U'B', 255, 0, 0);
  frame.at(2, 0) = cell(U'C', 0, 255, 0);

  strok::DiffEmitter emitter;
  const auto first = emitter.emit(frame);
  expect(first.changed_cells == 3, "first frame full repaint");
  expect(first.bytes.find("\x1b[1;1H") != std::string::npos, "first cursor");
  expect(first.bytes.find("\x1b[1;2H") == std::string::npos && first.bytes.find("\x1b[1;3H") == std::string::npos,
         "adjacent dirty cells share one cursor run");
  expect(first.bytes.find("\x1b[38;2;255;0;0m") != std::string::npos, "red fg");
  expect(first.bytes.find("\x1b[48;2;0;0;0m") != std::string::npos, "black bg");

  const auto unchanged = emitter.emit(frame);
  expect(unchanged.changed_cells == 0, "unchanged frame emits no cells");
  expect(unchanged.bytes.empty(), "unchanged frame emits no bytes");

  frame.at(1, 0).glyph = U'Z';
  const auto changed = emitter.emit(frame);
  expect(changed.changed_cells == 1, "single changed cell");
  expect(changed.bytes.find("\x1b[1;2H") != std::string::npos, "changed cursor");
  expect(changed.bytes.find('Z') != std::string::npos, "changed glyph");
  expect(changed.bytes.size() < first.bytes.size(), "near-static frame emits fewer bytes");

  strok::CellBuffer resized(1, 1);
  resized.at(0, 0) = cell(U'X', 1, 2, 3);
  const auto resize_emit = emitter.emit(resized);
  expect(resize_emit.changed_cells == 1, "resized full repaint");
  expect(resize_emit.bytes.find("\x1b[2J") != std::string::npos, "resize clears");

  strok::DiffEmitter positioned_emitter;
  const auto positioned = positioned_emitter.emit(resized, strok::EmissionOptions{.origin_row = 3, .origin_col = 4});
  expect(positioned.bytes.find("\x1b[3;4H") != std::string::npos, "positioned cursor");

  strok::DiffEmitter mono_emitter;
  strok::CellBuffer mono(1, 1);
  mono.at(0, 0) = cell(U'M', 255, 0, 0);
  const auto mono_first = mono_emitter.emit(mono, strok::EmissionOptions{.color_mode = strok::ColorMode::Mono});
  expect(mono_first.changed_cells == 1, "mono first emits glyph");
  expect(mono_first.bytes.find("\x1b[38;2;") == std::string::npos, "mono has no fg sgr");
  expect(mono_first.bytes.find('M') != std::string::npos, "mono glyph");

  mono.at(0, 0).fg = strok::Rgb{.r = 0, .g = 255, .b = 0};
  const auto mono_color_only = mono_emitter.emit(mono, strok::EmissionOptions{.color_mode = strok::ColorMode::Mono});
  expect(mono_color_only.changed_cells == 0, "mono ignores color-only changes");

  mono.at(0, 0).glyph = U'N';
  const auto mono_glyph = mono_emitter.emit(mono, strok::EmissionOptions{.color_mode = strok::ColorMode::Mono});
  expect(mono_glyph.changed_cells == 1, "mono emits glyph changes");
  expect(mono_glyph.bytes.find('N') != std::string::npos, "mono changed glyph");

  strok::DiffEmitter indexed_emitter;
  const auto indexed_first = indexed_emitter.emit(mono, strok::EmissionOptions{.color_mode = strok::ColorMode::Color256});
  expect(indexed_first.changed_cells == 1, "256 emits glyph");
  expect(indexed_first.bytes.find("\x1b[38;5;") != std::string::npos, "256 emits indexed fg");
  expect(indexed_first.bytes.find("\x1b[38;2;") == std::string::npos, "256 has no truecolor sgr");

  strok::DiffEmitter ansi16_emitter;
  const auto ansi16_first = ansi16_emitter.emit(mono, strok::EmissionOptions{.color_mode = strok::ColorMode::Color16});
  expect(ansi16_first.changed_cells == 1, "16 emits glyph");
  expect(ansi16_first.bytes.find("\x1b[") != std::string::npos, "16 emits sgr");
  expect(ansi16_first.bytes.find("\x1b[38;2;") == std::string::npos, "16 has no truecolor sgr");

  strok::DiffEmitter fs_emitter;
  strok::CellBuffer gradient(2, 1);
  gradient.at(0, 0) = cell(U'0', 160, 160, 160);
  gradient.at(1, 0) = cell(U'1', 160, 160, 160);
  const auto fs_first = fs_emitter.emit(gradient, strok::EmissionOptions{.color_mode = strok::ColorMode::Color16, .dither_mode = strok::DitherMode::FloydSteinberg});
  expect(fs_first.changed_cells == 2, "fs emits full frame");
  expect(fs_first.bytes.find("\x1b[90m") != std::string::npos, "fs emits dark gray first");
  expect(fs_first.bytes.find("\x1b[37m") != std::string::npos, "fs emits diffused light gray");

  strok::DiffEmitter perceptual_emitter;
  strok::CellBuffer subtle(1, 1);
  subtle.at(0, 0) = cell(U'P', 100, 100, 100);
  (void)perceptual_emitter.emit(subtle, strok::EmissionOptions{.diff_oklab_eps = 0.01});
  subtle.at(0, 0) = cell(U'P', 101, 101, 101);
  const auto subthreshold = perceptual_emitter.emit(subtle, strok::EmissionOptions{.diff_oklab_eps = 0.01});
  expect(subthreshold.changed_cells == 0, "OKLab diff suppresses subthreshold color-only change");
  subtle.at(0, 0) = cell(U'P', 160, 160, 160);
  const auto above_threshold = perceptual_emitter.emit(subtle, strok::EmissionOptions{.diff_oklab_eps = 0.01});
  expect(above_threshold.changed_cells == 1, "OKLab diff emits accumulated visible color change");

  strok::DiffEmitter reset_emitter;
  const auto reset_first = reset_emitter.emit(frame);
  const auto reset_unchanged = reset_emitter.emit(frame);
  reset_emitter.reset();
  const auto reset_repaint = reset_emitter.emit(frame);
  expect(reset_first.changed_cells == frame.size(), "reset fixture first frame paints all cells");
  expect(reset_unchanged.changed_cells == 0 && reset_unchanged.bytes.empty(), "reset fixture remembers prior frame");
  expect(reset_repaint.changed_cells == frame.size() && !reset_repaint.bytes.empty(), "reset repaints all cells");

  strok::DiffEmitter first_emitter;
  strok::DiffEmitter second_emitter;
  (void)first_emitter.emit(frame);
  const auto first_emitter_unchanged = first_emitter.emit(frame);
  const auto second_emitter_first = second_emitter.emit(frame);
  expect(first_emitter_unchanged.changed_cells == 0, "emitter instances keep independent prior frames");
  expect(second_emitter_first.changed_cells == frame.size(), "new emitter paints independently");

  strok::CellBuffer run_frame(3, 1);
  run_frame.at(0, 0) = cell(U'A', 255, 0, 0);
  run_frame.at(1, 0) = cell(U'B', 255, 0, 0);
  run_frame.at(2, 0) = cell(U'C', 255, 0, 0);
  strok::DiffEmitter run_emitter;
  (void)run_emitter.emit(run_frame);
  run_frame.at(0, 0).glyph = U'X';
  run_frame.at(1, 0).glyph = U'Y';
  const auto contiguous_changes = run_emitter.emit(run_frame);
  expect(contiguous_changes.changed_cells == 2, "contiguous dirty fixture emits two cells");
  expect(contiguous_changes.bytes.find("\x1b[1;1H") != std::string::npos, "contiguous dirty fixture positions run start");
  expect(contiguous_changes.bytes.find("\x1b[1;2H") == std::string::npos, "contiguous dirty fixture omits second cursor move");
  const std::string uncoalesced_bytes = "\x1b[1;1H\x1b[38;2;255;0;0m\x1b[48;2;0;0;0mX\x1b[1;2HY";
  expect(contiguous_changes.bytes.size() < uncoalesced_bytes.size(), "cursor run reduces dense update bytes");

  strok::CellBuffer wide_frame(2, 1);
  wide_frame.at(0, 0) = cell(U'界', 255, 0, 0);
  wide_frame.at(1, 0) = cell(U'A', 255, 0, 0);
  const auto wide_frame_emit = strok::DiffEmitter{}.emit(wide_frame);
  expect(wide_frame_emit.bytes.find("\x1b[1;2H") != std::string::npos, "wide glyph forces an absolute cursor move");
}
