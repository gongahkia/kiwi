#include <errno.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int parse_hex_uuid(const char *text, uint8_t uuid[16]) {
  if (strlen(text) != 32) return 1;
  for (size_t index = 0; index < 16; index += 1) {
    char pair[3] = { text[index * 2], text[index * 2 + 1], '\0' };
    char *end = NULL;
    const unsigned long value = strtoul(pair, &end, 16);
    if (end == NULL || *end != '\0') return 1;
    uuid[index] = (uint8_t)value;
  }
  return 0;
}

int main(int argc, char *argv[]) {
  if (argc != 3) {
    fputs("usage: macos_macho_uuid PATH 32_HEX_CHARACTERS\n", stderr);
    return 2;
  }

  uint8_t uuid[16];
  if (parse_hex_uuid(argv[2], uuid) != 0) {
    fputs("macos_macho_uuid: UUID must contain exactly 32 hexadecimal characters\n", stderr);
    return 2;
  }

  const int descriptor = open(argv[1], O_RDWR);
  if (descriptor < 0) {
    fprintf(stderr, "macos_macho_uuid: could not open %s: %s\n", argv[1], strerror(errno));
    return 1;
  }
  struct stat status;
  if (fstat(descriptor, &status) != 0 || status.st_size < (off_t)sizeof(struct mach_header_64)) {
    fprintf(stderr, "macos_macho_uuid: invalid Mach-O input %s\n", argv[1]);
    close(descriptor);
    return 1;
  }

  struct mach_header_64 header;
  if (pread(descriptor, &header, sizeof(header), 0) != (ssize_t)sizeof(header) || header.magic != MH_MAGIC_64) {
    fprintf(stderr, "macos_macho_uuid: %s is not a native 64-bit Mach-O executable\n", argv[1]);
    close(descriptor);
    return 1;
  }

  off_t offset = (off_t)sizeof(header);
  const off_t commands_end = offset + (off_t)header.sizeofcmds;
  if (commands_end > status.st_size) {
    fprintf(stderr, "macos_macho_uuid: %s has invalid load-command bounds\n", argv[1]);
    close(descriptor);
    return 1;
  }

  off_t uuid_offset = -1;
  for (uint32_t index = 0; index < header.ncmds; index += 1) {
    struct load_command command;
    if (offset + (off_t)sizeof(command) > commands_end || pread(descriptor, &command, sizeof(command), offset) != (ssize_t)sizeof(command) || command.cmdsize < sizeof(command) || offset + command.cmdsize > commands_end) {
      fprintf(stderr, "macos_macho_uuid: %s has an invalid load command\n", argv[1]);
      close(descriptor);
      return 1;
    }
    if (command.cmd == LC_UUID) {
      if (command.cmdsize != sizeof(struct uuid_command) || uuid_offset >= 0) {
        fprintf(stderr, "macos_macho_uuid: %s has an invalid UUID load command\n", argv[1]);
        close(descriptor);
        return 1;
      }
      uuid_offset = offset + (off_t)offsetof(struct uuid_command, uuid);
    }
    offset += command.cmdsize;
  }
  if (uuid_offset < 0 || offset != commands_end) {
    fprintf(stderr, "macos_macho_uuid: %s has no unique UUID load command\n", argv[1]);
    close(descriptor);
    return 1;
  }
  int write_failed = pwrite(descriptor, uuid, sizeof(uuid), uuid_offset) != (ssize_t)sizeof(uuid);
  if (close(descriptor) != 0) write_failed = 1;
  if (write_failed) {
    fprintf(stderr, "macos_macho_uuid: could not write %s: %s\n", argv[1], strerror(errno));
    return 1;
  }
  return 0;
}
