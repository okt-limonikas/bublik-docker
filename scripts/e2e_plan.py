#!/usr/bin/env python3

import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PLAN = ROOT / "e2e" / "plan.json"
ALLOWED_KEYS = {"version", "runs", "mixes", "days"}
MIX_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
MIX_KEY = re.compile(
    r"^(?:expected|unexpected|notRun|not_run)"
    r"(?:Passed|Failed|Killed|Cored|Skipped|Faked|Incomplete)$"
)
BUNDLED_FIXTURE_PROJECTS = {
    "basic": "bublik-e2e",
    "dpdk-ethdev-ts": "tsf/dpdk-ethdev",
    "net-drv-ts": "tsf/net-drv",
}
BUNDLED_FIXTURES = set(BUNDLED_FIXTURE_PROJECTS)
CONCLUSIONS = {
    "ok",
    "nok-warning",
    "nok-error",
    "warning",
    "error",
    "running",
    "busy",
    "stopped",
    "interrupted",
    "compromised",
}
BUILTIN_MIXES = {"all-ok", "fixture-default"}


class PlanError(ValueError):
    pass


def _object(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PlanError(f"{name} must be a JSON object")
    return value


def _non_empty_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{name} must be a non-empty string")
    return value


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise PlanError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def _parse_mix_values(specification: str, separator: str, name: str) -> None:
    items = specification.split(separator)
    if not items or any(not item.strip() for item in items):
        raise PlanError(f"{name} contains an empty mix item")

    keys: set[str] = set()
    percent_total = 0.0
    for item in items:
        key, found, raw_value = item.strip().partition("=")
        if not found or not key or not raw_value:
            raise PlanError(f"invalid mix item in {name}: {item!r}")
        if not MIX_KEY.fullmatch(key):
            raise PlanError(f"invalid mix key in {name}: {key!r}")
        canonical_key = key.replace("not_run", "notRun", 1)
        if canonical_key in keys:
            raise PlanError(f"duplicate mix key in {name}: {key!r}")
        keys.add(canonical_key)

        is_percent = raw_value.endswith("%")
        number = raw_value[:-1] if is_percent else raw_value
        try:
            value = float(number)
        except ValueError as error:
            raise PlanError(f"invalid mix value in {name}: {raw_value!r}") from error
        if not math.isfinite(value) or value < 0:
            raise PlanError(f"mix value must be finite and non-negative in {name}")
        if is_percent:
            if value > 100:
                raise PlanError(
                    f"percentage cannot exceed 100 in {name}: {raw_value!r}"
                )
            percent_total += value
        elif not value.is_integer():
            raise PlanError(f"absolute mix count must be an integer in {name}")

    if percent_total > 100:
        raise PlanError(f"mix percentages exceed 100 in {name}")


def _parse_day(day: str, specification: str, named_mixes: set[str]) -> int:
    try:
        parsed_day = datetime.strptime(day, "%Y-%m-%d").date().isoformat()
    except ValueError as error:
        raise PlanError(f"invalid ISO date: {day!r}") from error
    if parsed_day != day:
        raise PlanError(f"invalid ISO date: {day!r}")
    if not isinstance(specification, str):
        raise PlanError(f"days.{day} must be a string")
    if not specification:
        return 0

    items = specification.split(",")
    if any(not item.strip() for item in items):
        raise PlanError(f"days.{day} contains an empty run item")

    run_count = 0
    for item in items:
        lhs, found, raw_count = item.strip().rpartition("=")
        lhs = lhs.strip()
        raw_count = raw_count.strip()
        if not found or not lhs or not raw_count:
            raise PlanError(f"invalid run item in days.{day}: {item!r}")
        try:
            count = int(raw_count)
        except ValueError as error:
            raise PlanError(
                f"invalid run count in days.{day}: {raw_count!r}"
            ) from error
        if count < 0:
            raise PlanError(f"run count cannot be negative in days.{day}: {item!r}")

        if "+ui" in lhs:
            if lhs.count("+ui") != 1 or not lhs.endswith("+ui"):
                raise PlanError(
                    f"+ui must appear once at the end in days.{day}: {item!r}"
                )
            lhs = lhs[: -len("+ui")]
        if "+" in lhs:
            raise PlanError(f"invalid import marker in days.{day}: {item!r}")

        if lhs.count("@") > 1:
            raise PlanError(f"invalid mix reference in days.{day}: {item!r}")
        run_target, marker, mix_reference = lhs.partition("@")
        run_target = run_target.strip()
        mix_reference = mix_reference.strip()
        if marker:
            if not mix_reference:
                raise PlanError(f"empty mix reference in days.{day}: {item!r}")
            if "=" in mix_reference:
                _parse_mix_values(mix_reference, ";", f"inline mix in days.{day}")
            elif mix_reference not in named_mixes:
                raise PlanError(
                    f"unknown mix reference in days.{day}: {mix_reference!r}"
                )

        fixture = None
        conclusion = run_target
        if "." in run_target:
            fixture, conclusion = run_target.split(".", 1)
            fixture = fixture.strip()
            conclusion = conclusion.strip()
            if fixture not in BUNDLED_FIXTURES:
                raise PlanError(f"unknown fixture in days.{day}: {fixture!r}")
        if conclusion not in CONCLUSIONS:
            raise PlanError(f"unknown conclusion in days.{day}: {conclusion!r}")
        run_count += count if fixture else count * len(BUNDLED_FIXTURES)

    return run_count


def load_plan(path: Path) -> list[str]:
    try:
        data = _object(
            json.loads(
                path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object
            ),
            "plan",
        )
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}: {error}") from error

    unknown = set(data) - ALLOWED_KEYS
    if unknown:
        raise PlanError(f"unknown plan keys: {', '.join(sorted(unknown))}")
    if data.get("version") != 1:
        raise PlanError("plan version must be 1")

    runs = data.get("runs")
    if not isinstance(runs, int) or isinstance(runs, bool) or runs < 1:
        raise PlanError("runs must be a positive integer")

    arguments = ["--runs", str(runs)]
    mixes = _object(data.get("mixes"), "mixes")
    for name, specification in mixes.items():
        if not isinstance(name, str) or not MIX_NAME.fullmatch(name):
            raise PlanError(f"invalid mix name: {name!r}")
        specification = _non_empty_string(specification, f"mixes.{name}")
        _parse_mix_values(specification, ",", f"mixes.{name}")
        arguments.extend(("--mix", f"{name}:{specification}"))

    days = _object(data.get("days"), "days")
    if not days:
        raise PlanError("days must not be empty")
    derived_runs = 0
    named_mixes = set(mixes) | BUILTIN_MIXES
    for day, specification in days.items():
        if not isinstance(day, str):
            raise PlanError(f"invalid day: {day!r}")
        derived_runs += _parse_day(day, specification, named_mixes)
        arguments.extend(("--day", f"{day}:{specification}"))

    if derived_runs != runs:
        raise PlanError(
            f"runs={runs} but day specifications derive {derived_runs} runs"
        )

    return arguments


def _required_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise PlanError(f"{name} is required")
    return value


def _resolve_allowed(path: Path, allowed_root: Path, kind: str) -> Path:
    candidate = path.expanduser()
    if ".." in candidate.parts:
        raise PlanError(f"{kind} must not contain parent path components: {path}")
    if not candidate.is_absolute():
        candidate = ROOT / candidate
    candidate = candidate.absolute()
    try:
        resolved = candidate.resolve()
    except (OSError, RuntimeError) as error:
        raise PlanError(f"cannot resolve {kind}: {candidate}: {error}") from error
    allowed_root = allowed_root.absolute()
    try:
        resolved.relative_to(allowed_root)
    except ValueError as error:
        raise PlanError(
            f"{kind} must resolve under {allowed_root}, got {resolved}"
        ) from error
    return candidate


def _artifact_paths() -> tuple[Path, Path]:
    data_dir = Path(_required_environment("BUBLIK_DOCKER_DATA_DIR"))
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    try:
        data_dir = data_dir.expanduser().resolve()
    except (OSError, RuntimeError) as error:
        raise PlanError(f"cannot resolve BUBLIK_DOCKER_DATA_DIR: {error}") from error

    publish_root = data_dir / "logs" / "logs" / "e2e"
    publish_dir = _resolve_allowed(
        Path(_required_environment("BUBLIK_E2E_PUBLISH_DIR")),
        publish_root,
        "publish directory",
    )
    manifest_root = ROOT.resolve() / ".e2e"
    manifest = _resolve_allowed(
        Path(_required_environment("BUBLIK_E2E_MANIFEST")),
        manifest_root,
        "manifest",
    )
    if manifest.resolve() == manifest_root:
        raise PlanError("manifest must be a file below ROOT/.e2e")
    if (
        publish_dir.exists()
        and not publish_dir.is_dir()
        and not publish_dir.is_symlink()
    ):
        raise PlanError(f"expected a publish directory: {publish_dir.resolve()}")
    if manifest.exists() and manifest.is_dir() and not manifest.is_symlink():
        raise PlanError(f"expected a manifest file: {manifest.resolve()}")
    return publish_dir, manifest


def _remove_directory(path: Path) -> None:
    if path.is_symlink():
        path.unlink()
    elif path.exists():
        if not path.is_dir():
            raise PlanError(f"expected a directory: {path}")
        shutil.rmtree(path)


def clean_artifacts() -> None:
    publish_dir, manifest = _artifact_paths()
    _remove_directory(publish_dir)

    manifest.unlink(missing_ok=True)


def guard_compose_project() -> None:
    normal = _required_environment("BUBLIK_NORMAL_COMPOSE_PROJECT_NAME")
    e2e = _required_environment("BUBLIK_E2E_COMPOSE_PROJECT_NAME")
    if normal == e2e:
        raise PlanError(
            "refusing destructive cleanup because the E2E Compose project "
            f"equals the normal project: {normal!r}"
        )


def validate_manifest_projects(path: Path) -> None:
    try:
        manifest = _object(json.loads(path.read_text(encoding="utf-8")), "manifest")
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read generated manifest {path}: {error}") from error
    bundles = manifest.get("bundles")
    if not isinstance(bundles, list):
        raise PlanError("generated manifest bundles must be an array")
    for index, bundle_value in enumerate(bundles):
        bundle = _object(bundle_value, f"manifest.bundles[{index}]")
        fixture = bundle.get("fixture")
        expected_project = BUNDLED_FIXTURE_PROJECTS.get(fixture)
        if expected_project is not None and bundle.get("project") != expected_project:
            raise PlanError(
                f"generated {fixture!r} bundle has project {bundle.get('project')!r}; "
                f"expected {expected_project!r}"
            )


def run_cli(command: str, custom_arguments: list[str]) -> int:
    if not custom_arguments:
        plan_path = Path(os.environ.get("BUBLIK_E2E_PLAN_FILE", DEFAULT_PLAN))
        custom_arguments = load_plan(plan_path)

    publish_dir, manifest = _artifact_paths()
    arguments = [
        os.environ.get("BUBLIK_E2E_BIN", "bublik-e2e"),
        command,
        "--url",
        _required_environment("BUBLIK_E2E_URL"),
        "--publish-dir",
        str(publish_dir),
        "--manifest",
        str(manifest),
        "--run-log-schema",
        _required_environment("BUBLIK_E2E_RUN_LOG_SCHEMA"),
        "--meta-data-schema",
        _required_environment("BUBLIK_E2E_META_DATA_SCHEMA"),
    ]
    arguments.extend(custom_arguments)
    if command == "run":
        arguments.append("--setup-projects")
    try:
        return_code = subprocess.run(arguments, check=False).returncode
    except OSError as error:
        raise PlanError(f"cannot execute {arguments[0]!r}: {error}") from error
    if return_code == 0 and "--help" not in custom_arguments:
        validate_manifest_projects(manifest)
    return return_code


def main() -> int:
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else ""
        if command == "check":
            path = (
                Path(sys.argv[2])
                if len(sys.argv) > 2
                else Path(os.environ.get("BUBLIK_E2E_PLAN_FILE", DEFAULT_PLAN))
            )
            arguments = load_plan(path)
            print(f"Valid E2E plan: {path} ({len(arguments)} CLI arguments)")
            return 0
        if command == "clean":
            clean_artifacts()
            return 0
        if command == "guard-compose-project":
            guard_compose_project()
            return 0
        if command not in {"generate", "run"}:
            raise PlanError(
                "usage: e2e_plan.py check [PLAN] | clean | guard-compose-project "
                "| generate/run [CLI_ARGS]"
            )
        custom_arguments = sys.argv[2:]
        if not custom_arguments:
            try:
                custom_arguments = shlex.split(
                    os.environ.get("BUBLIK_E2E_CLI_ARGS", "")
                )
            except ValueError as error:
                raise PlanError(f"invalid CLI arguments: {error}") from error
        return run_cli(command, custom_arguments)
    except PlanError as error:
        print(f"e2e-plan: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
