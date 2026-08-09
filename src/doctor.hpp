#pragma once

#include "cli.hpp"

#include <filesystem>
#include <optional>
#include <string>

namespace strok {

// Produces a read-only diagnostic report. It never opens an input stream or
// enters a terminal session.
std::string formatDoctorReport(const CliOptions& options,
                               std::optional<std::filesystem::path> config_path);

}  // namespace strok
