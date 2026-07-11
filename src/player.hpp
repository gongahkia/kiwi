#pragma once

#include "cli.hpp"
#include "log.hpp"

namespace strok {

int exportMedia(const CliOptions& options, Logger& logger);
int writeCaptionSidecar(const CliOptions& options, Logger& logger);
int writeStillSnapshot(const CliOptions& options, Logger& logger);
int playMedia(const CliOptions& options, Logger& logger);

}  // namespace strok
