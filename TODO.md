# WAT Acronym Deconstructor Todo

## Non-goals reminder
- No AI-only unsourced definitions, dictionary clone, or required external API.

## Pi constraints reminder
- Target Pi 5 4GB/56GB microSD; keep glossary offline and human-editable.

## P0 validation
- [ ] Decide glossary format: JSON or YAML.
- [ ] Define entry schema: acronym, expansions, domain, meaning, example, source, confidence.
- [ ] Seed 20-50 tech acronyms manually.
- [ ] Decide CLI language: Go for static binary or Python for faster iteration.

## P1 MVP
- [ ] Build exact lookup.
- [ ] Add fuzzy lookup for near misses.
- [ ] Print concise terminal output.
- [ ] Add local web lookup endpoint/page.

## P2 polish
- [ ] Add import/export commands.
- [ ] Add duplicate/acronym collision detection.
- [ ] Add "buzzword mode" for phrases, not just acronyms.
- [ ] Add offline docs bundle.

## Test/acceptance checks
- [ ] Lookup works offline.
- [ ] Unknown acronym returns no-match, not fabricated content.
- [ ] Each result includes source and confidence.
- [ ] CLI and web output use same glossary data.

## Rename note
Rename folder freely; keep `rough-idea.md` and `todo.md` at project root.
