#include <cstring>
#include <iostream>

#ifndef CONTOURTTY_VERSION
#define CONTOURTTY_VERSION "0.0.0"
#endif

int main(int argc, char** argv) {
  if (argc > 1 && std::strcmp(argv[1], "--version") == 0) {
    std::cout << "contourtty " << CONTOURTTY_VERSION << '\n';
    return 0;
  }

  std::cout << "contourtty " << CONTOURTTY_VERSION << '\n';
  return 0;
}
