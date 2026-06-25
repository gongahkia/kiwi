#include "structure_sampling.hpp"

#include "luminance.hpp"
#include "worker_count.hpp"

#include <algorithm>
#include <cstddef>
#include <stdexcept>
#include <thread>
#include <vector>

namespace contourtty {
namespace {

int workerCount(int rows, int items) {
  if (rows < 2 || items < 8192) {
    return 1;
  }
  const unsigned hardware = std::thread::hardware_concurrency();
  const int max_workers = boundedWorkerCount(static_cast<int>(hardware == 0 ? 2 : hardware));
  return std::min(rows, max_workers);
}

template <typename Function>
void parallelRows(int rows, int items, Function function) {
  const int workers = workerCount(rows, items);
  if (workers == 1) {
    function(0, rows);
    return;
  }

  std::vector<std::thread> threads;
  threads.reserve(static_cast<std::size_t>(workers - 1));
  for (int worker = 1; worker < workers; ++worker) {
    const int row_begin = (rows * worker) / workers;
    const int row_end = (rows * (worker + 1)) / workers;
    threads.emplace_back(function, row_begin, row_end);
  }
  function(0, rows / workers);
  for (std::thread& thread : threads) {
    thread.join();
  }
}

}  // namespace

double LuminanceField::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    throw std::out_of_range("luminance field index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x));
}

double CellLuminanceRegion::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width() || y >= height()) {
    throw std::out_of_range("cell luminance index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width()) + static_cast<std::size_t>(x));
}

LuminanceField makeLuminanceField(const Frame& frame) {
  if (frame.w <= 0 || frame.h <= 0) {
    throw std::invalid_argument("frame dimensions must be positive");
  }
  const std::size_t expected = static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3;
  if (frame.rgb.size() != expected) {
    throw std::invalid_argument("frame RGB data size does not match dimensions");
  }

  LuminanceField field;
  field.width = frame.w;
  field.height = frame.h;
  field.values.assign(static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h), 0.0);
  parallelRows(frame.h, frame.w * frame.h, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < frame.w; ++x) {
        const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3;
        field.values[index / 3] = relativeLuminance(Rgb{
          .r = frame.rgb[index],
          .g = frame.rgb[index + 1],
          .b = frame.rgb[index + 2],
        });
      }
    }
  });
  return field;
}

SourceRegion cellSourceRegion(int source_width, int source_height, int cols, int rows, int col, int row) {
  if (source_width <= 0 || source_height <= 0 || cols <= 0 || rows <= 0) {
    throw std::invalid_argument("source and grid dimensions must be positive");
  }
  if (col < 0 || row < 0 || col >= cols || row >= rows) {
    throw std::out_of_range("cell index out of range");
  }
  const int x0 = (col * source_width) / cols;
  const int x1 = ((col + 1) * source_width) / cols;
  const int y0 = (row * source_height) / rows;
  const int y1 = ((row + 1) * source_height) / rows;
  return SourceRegion{.x0 = x0, .x1 = x1, .y0 = y0, .y1 = y1};
}

CellLuminanceRegion sampleCellRegion(const LuminanceField& field, int cols, int rows, int col, int row) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  CellLuminanceRegion region;
  region.source = cellSourceRegion(field.width, field.height, cols, rows, col, row);
  region.values.reserve(static_cast<std::size_t>(region.width()) * static_cast<std::size_t>(region.height()));
  for (int y = region.source.y0; y < region.source.y1; ++y) {
    for (int x = region.source.x0; x < region.source.x1; ++x) {
      region.values.push_back(field.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x)]);
    }
  }
  return region;
}

}  // namespace contourtty
