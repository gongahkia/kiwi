from __future__ import annotations

import ast
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

SOURCE_ROOT = Path(__file__).resolve().parents[2] / "src" / "kiwi"
PRESENTATION_PACKAGES = ("kiwi.app", "kiwi.render", "kiwi.ui")
PYGAME_IMPORT_PACKAGES = frozenset(("app", "render"))
ALLOWED_INTERNAL_IMPORTS = {
    "domain": ("kiwi.domain",),
    "dsl": ("kiwi.domain", "kiwi.dsl"),
    "sim": ("kiwi.domain", "kiwi.dsl", "kiwi.sim"),
    "trace": ("kiwi.domain", "kiwi.dsl", "kiwi.sim", "kiwi.trace"),
    "replay": ("kiwi.domain", "kiwi.dsl", "kiwi.sim", "kiwi.replay"),
    "content": ("kiwi.content", "kiwi.domain", "kiwi.dsl"),
}
FORBIDDEN_IMPORT_ROOTS = frozenset(("datetime", "pickle", "pygame", "time"))
UNSEEDED_RANDOM_CALLS = frozenset(
    (
        "random.choice",
        "random.choices",
        "random.getrandbits",
        "random.randint",
        "random.randrange",
        "random.random",
        "random.shuffle",
        "random.uniform",
    )
)


@dataclass(frozen=True)
class SourceReference:
    path: Path
    line: int
    target: str


def source_files(package: str) -> list[Path]:
    return sorted((SOURCE_ROOT / package).rglob("*.py"))


def module_name(path: Path) -> str:
    parts = list(path.relative_to(SOURCE_ROOT).with_suffix("").parts)
    if parts[-1] == "__init__":
        parts.pop()
    return ".".join(("kiwi", *parts))


def module_package(path: Path) -> str:
    name = module_name(path)
    return name if path.name == "__init__.py" else name.rpartition(".")[0]


def import_targets(tree: ast.AST, path: Path) -> Iterator[SourceReference]:
    package = module_package(path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield SourceReference(path, node.lineno, alias.name)
        elif isinstance(node, ast.ImportFrom):
            base = relative_import_base(node, package)
            for alias in node.names:
                target = ".".join(part for part in (base, alias.name) if part)
                yield SourceReference(path, node.lineno, target)


def relative_import_base(node: ast.ImportFrom, package: str) -> str:
    if node.level == 0:
        return node.module or ""
    package_parts = package.split(".")
    base_parts = package_parts[: len(package_parts) - node.level + 1]
    return ".".join(part for part in (*base_parts, node.module) if part)


def is_within(target: str, package: str) -> bool:
    return target == package or target.startswith(f"{package}.")


def test_authoritative_imports_follow_dependency_direction() -> None:
    violations: list[str] = []
    for package, allowed in ALLOWED_INTERNAL_IMPORTS.items():
        for path in source_files(package):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for reference in import_targets(tree, path):
                if reference.target == "kiwi":
                    violations.append(
                        f"{reference.path}:{reference.line}: import an explicit kiwi package"
                    )
                elif reference.target.startswith("pygame"):
                    violations.append(f"{reference.path}:{reference.line}: imports pygame")
                elif any(is_within(reference.target, item) for item in PRESENTATION_PACKAGES):
                    violations.append(
                        f"{reference.path}:{reference.line}: imports presentation package"
                    )
                elif reference.target.startswith("kiwi.") and not any(
                    is_within(reference.target, item) for item in allowed
                ):
                    violations.append(
                        f"{reference.path}:{reference.line}: violates dependency direction"
                    )

    assert not violations, "\n".join(violations)


def test_authoritative_sources_reject_forbidden_apis() -> None:
    violations: list[str] = []
    for package in ALLOWED_INTERNAL_IMPORTS:
        for path in source_files(package):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            aliases = import_aliases(tree)
            for reference in import_targets(tree, path):
                if reference.target.split(".", maxsplit=1)[0] in FORBIDDEN_IMPORT_ROOTS:
                    violations.append(
                        f"{reference.path}:{reference.line}: imports {reference.target}"
                    )
            for node in ast.walk(tree):
                if isinstance(node, ast.Call):
                    target = call_target(node.func, aliases)
                    if target in {"eval", "exec", "builtins.eval", "builtins.exec"}:
                        violations.append(f"{path}:{node.lineno}: calls {target}")
                    elif target in UNSEEDED_RANDOM_CALLS:
                        violations.append(f"{path}:{node.lineno}: calls unseeded {target}")
                    elif target == "random.SystemRandom":
                        violations.append(f"{path}:{node.lineno}: uses OS randomness")
                    elif target == "random.Random" and not node.args and not node.keywords:
                        violations.append(f"{path}:{node.lineno}: creates unseeded random.Random")

    assert not violations, "\n".join(violations)


def test_repository_sources_do_not_execute_player_programs_as_python() -> None:
    violations: list[str] = []
    for path in sorted(SOURCE_ROOT.rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        aliases = import_aliases(tree)
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                target = call_target(node.func, aliases)
                if target in {"eval", "exec", "builtins.eval", "builtins.exec"}:
                    violations.append(f"{path}:{node.lineno}: calls {target}")

    assert not violations, "\n".join(violations)


def test_pygame_imports_are_restricted_to_application_and_render_packages() -> None:
    violations: list[str] = []
    for path in sorted(SOURCE_ROOT.rglob("*.py")):
        package = path.relative_to(SOURCE_ROOT).parts[0]
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for reference in import_targets(tree, path):
            if reference.target.startswith("pygame") and package not in PYGAME_IMPORT_PACKAGES:
                violations.append(
                    f"{reference.path}:{reference.line}: pygame import outside application/render"
                )

    assert not violations, "\n".join(violations)


def import_aliases(tree: ast.AST) -> dict[str, str]:
    aliases: dict[str, str] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                aliases[alias.asname or alias.name.split(".", maxsplit=1)[0]] = alias.name
        elif isinstance(node, ast.ImportFrom) and node.module is not None:
            for alias in node.names:
                aliases[alias.asname or alias.name] = f"{node.module}.{alias.name}"
    return aliases


def call_target(node: ast.expr, aliases: dict[str, str]) -> str:
    if isinstance(node, ast.Name):
        return aliases.get(node.id, node.id)
    if isinstance(node, ast.Attribute):
        parent = call_target(node.value, aliases)
        return f"{parent}.{node.attr}"
    return ""
