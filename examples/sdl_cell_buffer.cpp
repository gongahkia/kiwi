#include <strok/color_image_view.hpp>
#include <strok/render_input.hpp>
#include <strok/renderer.hpp>

#include <SDL.h>
#include <SDL_ttf.h>

#include <algorithm>
#include <cstdint>
#include <exception>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct Options {
  std::string font_path;
  bool smoke = false;
};

Options parseOptions(int argc, char** argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--smoke") {
      options.smoke = true;
    } else if (argument == "--font" && index + 1 < argc) {
      options.font_path = argv[++index];
    } else {
      throw std::invalid_argument("usage: strok_sdl_sample --font PATH [--smoke]");
    }
  }
  if (options.font_path.empty()) {
    throw std::invalid_argument("usage: strok_sdl_sample --font PATH [--smoke]");
  }
  return options;
}

std::vector<std::uint8_t> gradientImage(int width, int height) {
  std::vector<std::uint8_t> pixels(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 3U);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)) * 3U;
      pixels[index] = static_cast<std::uint8_t>(x * 255 / std::max(width - 1, 1));
      pixels[index + 1U] = static_cast<std::uint8_t>(y * 255 / std::max(height - 1, 1));
      pixels[index + 2U] = static_cast<std::uint8_t>((x + y) * 255 / std::max(width + height - 2, 1));
    }
  }
  return pixels;
}

void drawCells(SDL_Renderer* renderer, TTF_Font* font, const strok::CellBuffer& cells, int cell_width, int cell_height) {
  for (int row = 0; row < cells.rows(); ++row) {
    for (int col = 0; col < cells.cols(); ++col) {
      const strok::Cell& cell = cells.at(col, row);
      SDL_Rect destination{
        .x = col * cell_width,
        .y = row * cell_height,
        .w = cell_width,
        .h = cell_height,
      };
      SDL_SetRenderDrawColor(renderer, cell.bg.r, cell.bg.g, cell.bg.b, SDL_ALPHA_OPAQUE);
      SDL_RenderFillRect(renderer, &destination);
      if (cell.glyph == U' ') {
        continue;
      }

      const SDL_Color foreground{
        .r = cell.fg.r,
        .g = cell.fg.g,
        .b = cell.fg.b,
        .a = SDL_ALPHA_OPAQUE,
      };
      SDL_Surface* glyph_surface = TTF_RenderGlyph32_Blended(font, static_cast<Uint32>(cell.glyph), foreground);
      if (glyph_surface == nullptr) {
        continue;
      }
      const int glyph_width = glyph_surface->w;
      const int glyph_height = glyph_surface->h;
      SDL_Texture* glyph_texture = SDL_CreateTextureFromSurface(renderer, glyph_surface);
      SDL_FreeSurface(glyph_surface);
      if (glyph_texture == nullptr) {
        throw std::runtime_error(SDL_GetError());
      }
      SDL_Rect glyph_destination{
        .x = destination.x + (destination.w - glyph_width) / 2,
        .y = destination.y + (destination.h - glyph_height) / 2,
        .w = glyph_width,
        .h = glyph_height,
      };
      SDL_RenderCopy(renderer, glyph_texture, nullptr, &glyph_destination);
      SDL_DestroyTexture(glyph_texture);
    }
  }
}

}  // namespace

int main(int argc, char** argv) {
  bool sdl_initialized = false;
  bool ttf_initialized = false;
  try {
    const Options options = parseOptions(argc, argv);
    constexpr int source_width = 160;
    constexpr int source_height = 90;
    constexpr int cols = 64;
    constexpr int rows = 24;
    constexpr int cell_height = 20;
    constexpr int cell_width = 12;

    std::vector<std::uint8_t> pixels = gradientImage(source_width, source_height);
    const strok::ColorImageView image{
      .data = pixels.data(),
      .width = source_width,
      .height = source_height,
      .row_stride_bytes = static_cast<std::size_t>(source_width) * 3U,
      .pixel_format = strok::ColorPixelFormat::Rgb24,
    };
    strok::Renderer::CreateResult created = strok::Renderer::create(
        strok::RendererConfig{.cell_aspect = static_cast<double>(cell_width) / cell_height},
        strok::RenderGrid{.cols = cols, .rows = rows});
    if (!created.succeeded()) {
      throw std::runtime_error(created.result.message);
    }
    const strok::RenderResult rendered = created.renderer->render(strok::RenderInput{.color = image});
    if (!rendered.succeeded()) {
      throw std::runtime_error(rendered.message);
    }

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
      throw std::runtime_error(SDL_GetError());
    }
    sdl_initialized = true;
    if (TTF_Init() != 0) {
      throw std::runtime_error(TTF_GetError());
    }
    ttf_initialized = true;
    {
      const std::unique_ptr<TTF_Font, decltype(&TTF_CloseFont)> font(TTF_OpenFont(options.font_path.c_str(), cell_height), TTF_CloseFont);
      if (!font) {
        throw std::runtime_error(TTF_GetError());
      }
      const Uint32 window_flags = options.smoke ? SDL_WINDOW_HIDDEN : SDL_WINDOW_RESIZABLE;
      const std::unique_ptr<SDL_Window, decltype(&SDL_DestroyWindow)> window(
          SDL_CreateWindow("strok SDL CellBuffer sample", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, cols * cell_width, rows * cell_height, window_flags),
          SDL_DestroyWindow);
      if (!window) {
        throw std::runtime_error(SDL_GetError());
      }
      SDL_Renderer* raw_renderer = SDL_CreateRenderer(window.get(), -1, SDL_RENDERER_ACCELERATED);
      if (raw_renderer == nullptr) {
        raw_renderer = SDL_CreateRenderer(window.get(), -1, SDL_RENDERER_SOFTWARE);
      }
      const std::unique_ptr<SDL_Renderer, decltype(&SDL_DestroyRenderer)> sdl_renderer(raw_renderer, SDL_DestroyRenderer);
      if (!sdl_renderer) {
        throw std::runtime_error(SDL_GetError());
      }

      drawCells(sdl_renderer.get(), font.get(), created.renderer->cells(), cell_width, cell_height);
      SDL_RenderPresent(sdl_renderer.get());
      if (!options.smoke) {
        bool running = true;
        while (running) {
          SDL_Event event;
          while (SDL_PollEvent(&event) != 0) {
            running = event.type != SDL_QUIT;
          }
          SDL_Delay(16);
        }
      }
    }

    TTF_Quit();
    ttf_initialized = false;
    SDL_Quit();
    sdl_initialized = false;
    return 0;
  } catch (const std::exception& error) {
    if (ttf_initialized) {
      TTF_Quit();
    }
    if (sdl_initialized) {
      SDL_Quit();
    }
    std::cerr << "strok_sdl_sample: " << error.what() << '\n';
    return 1;
  }
}
