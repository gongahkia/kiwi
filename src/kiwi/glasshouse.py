"""Launch the local pygame-ce Glasshouse causal drill."""

from __future__ import annotations

from kiwi.render.glasshouse_demo import run_glasshouse_demo


def main() -> int:
    """Run the manually testable Glasshouse vertical-slice flow."""
    return run_glasshouse_demo()


if __name__ == "__main__":
    raise SystemExit(main())
