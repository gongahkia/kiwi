# ADR 0032: bounded command-region render resource

## Context

The terminal model retains opaque command-region lifecycle records so history
navigation can resolve prompt, command, and output boundaries. Render passes
and trusted local extensions need a typed semantic view, but exposing the
records directly would disclose CWD identity, internal IDs, status, recovery
facts, offscreen history, and a larger correlation surface than a visible
decoration requires.

## Decision

Renderer ABI v1 adds the read-only `terminal.command_regions` resource. It is
derived afresh from the active screen's viewport and contains at most 32
deduplicated boundaries, sorted by row, column, and role. A boundary has only
viewport-relative `row`, `column`, and one of `prompt`, `command`, `output`,
or `finish`. `boundary_count` and `omitted_boundary_count` state exactly how
much of that bounded view is present.

The descriptor deliberately excludes terminal text, command/output data,
directory/URI/host data, opaque region and stable-row IDs, exit status,
recovery/interruption facts, timestamps, other-screen data, offscreen rows,
and native renderer handles. The resource registry clones it for every
extension callback, which has no mutating access or renderer reference.

`Renderer:update_model` compares the current descriptor with the last one and
requests a distinct `command_regions` invalidation when visible metadata or
viewport movement changes it. `KIWI_COMMAND_REGIONS=1` opts into one built-in
alpha-blended command/output separator pass after search and before glyphs.
The pass reads the declared resource and frame viewport and has a stable
ordering dependency. It never changes terminal state or runs when the option
is absent. API v1 extension passes may observe the resource but cannot draw;
the command-region observer sample demonstrates that boundary.

## Consequences

An absent shell integration produces an empty descriptor and no visual pass by
default. The optional separator is a reference treatment, not a command
timeline or a required terminal theme. Extensions cannot reconstruct command
text, path data, historical lifecycle records, or a native GPU capability from
this resource contract. A future richer command visual or extension drawing
surface must be separately versioned with its own privacy and ownership review.

## References

- [ADR 0027](0027-bounded-shell-integration-metadata.md)
- [ADR 0028](0028-stable-command-region-lifecycle.md)
- [ADR 0029](0029-command-region-retention-and-snapshot-boundary.md)
- [Renderer API v1](../RENDERER_API.md)
