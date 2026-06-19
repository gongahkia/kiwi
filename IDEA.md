# WAT Acronym Deconstructor

## Concept
Offline-first CLI/web tool that expands technical acronyms and explains overloaded buzzwords.

## MVP scope
- Maintain curated glossary entries.
- Search acronyms by exact match and fuzzy match.
- Return expansion, domain, plain-English meaning, examples, source, and confidence.
- Provide CLI first, web UI second.

## Non-goals
- No AI-only unsourced definitions.
- No broad dictionary clone.
- No external API dependency for core lookup.

## Target stack
- Go or Python CLI.
- JSON/YAML glossary as source of truth.
- SQLite FTS optional after glossary grows.
- Small local web server for browser lookup.

## Pi constraints
- Baseline: Raspberry Pi 5 4GB, 56GB microSD.
- Fully offline by default.
- Keep glossary human-editable.
- Avoid large model dependency for MVP.

## Optional HW
- None required.
- Portable Pi server can host the web UI.

## Research links
- [Raspberry Pi 5 specs](https://www.raspberrypi.com/products/raspberry-pi-5/)
- [Raspberry Pi OS downloads](https://www.raspberrypi.com/software/operating-systems/)

## Acceptance checks
- Lookup works offline.
- Results include source and confidence.

## Rename note
Folder can be renamed; keep `rough-idea.md` and `todo.md` at project root.
