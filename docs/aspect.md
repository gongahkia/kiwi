# Aspect Correction

Terminal cells are taller than they are wide. contourtty uses `cell_aspect = cell_width / cell_height`, default `0.5`.

Given source size `src_w x src_h` and target columns `cols`:

```text
img_aspect = src_w / src_h
rows = round(cols * (1 / img_aspect) * cell_aspect)
```

If only rows are fixed:

```text
cols = round(rows * img_aspect / cell_aspect)
```

If both columns and rows are fixed, contourtty fits inside the requested bounds while preserving this corrected aspect ratio.
