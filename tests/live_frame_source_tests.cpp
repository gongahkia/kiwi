#include "live_frame_source.hpp"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::LiveFrame frame(int64_t pts_us) {
  return strok::LiveFrame{
    .frame = strok::Frame{
      .w = 1,
      .h = 1,
      .rgb = {0, 0, 0},
      .pts_us = pts_us,
    },
    .decoded_at = std::chrono::steady_clock::now(),
  };
}

}  // namespace

int main() {
  bool rejected_zero_capacity = false;
  try {
    strok::LatestFrameQueue invalid(0);
  } catch (const std::invalid_argument&) {
    rejected_zero_capacity = true;
  }
  expect(rejected_zero_capacity, "zero capacity rejected");

  strok::LatestFrameQueue queue(2);
  expect(queue.capacity() == 2, "queue capacity");
  expect(!queue.waitForLatestFor(std::chrono::milliseconds(0)).has_value(), "empty queue timed wait");
  expect(queue.push(frame(1000)), "first frame accepted");
  expect(queue.push(frame(2000)), "second frame accepted");
  expect(queue.push(frame(3000)), "third frame replaces oldest");

  const std::optional<strok::LiveFrameBatch> batch = queue.waitForLatest();
  expect(batch.has_value(), "latest batch available");
  expect(batch->latest.frame.pts_us == 3000, "newest frame selected");
  expect(batch->producer_replaced == 1, "producer replacement counted");
  expect(batch->consumer_discarded == 1, "consumer discard counted");

  expect(queue.push(frame(4000)), "queue remains usable after drain");
  const std::optional<strok::LiveFrameBatch> second = queue.waitForLatest();
  expect(second.has_value() && second->latest.frame.pts_us == 4000, "fresh frame selected");
  expect(second->producer_replaced == 0 && second->consumer_discarded == 0, "counts reset after drain");

  queue.close();
  expect(queue.closed(), "queue reports closure");
  expect(!queue.push(frame(5000)), "closed queue rejects frames");
  expect(!queue.waitForLatest().has_value(), "closed empty queue finishes");
}
