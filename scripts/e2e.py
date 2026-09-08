#!/usr/bin/env python3

"""Local helpers for the E2E stack that the bublik-e2e CLI does not cover.

Campaign parsing, validation and seeding all live in the ``bublik-e2e`` CLI
(``bublik-e2e plan/generate/run --plan e2e/plan.yaml``). What is left here is
specific to this repository's layout:

``clean``                  remove generated artifacts, refusing paths outside
                           the directories E2E is allowed to write to
``guard-compose-project``  refuse destructive Compose actions when the E2E and
                           production project names collide
``seeded``                 exit 0 when the running stack already has the
                           manifest's runs, so ``task e2e:seed`` can skip
                           reseeding
"""

import json
import os
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
# Playwright writes its reports and traces here, and its auth setup project
# caches a logged-in storage state. Both survive a Compose teardown, so a reset
# has to clear them explicitly.
PLAYWRIGHT_ARTIFACTS = (
    Path("bublik-ui/dist/.playwright"),
    Path("bublik-ui/e2e/.auth"),
)
PROBE_TIMEOUT_SECONDS = 5


class E2EError(ValueError):
    pass


def _required_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise E2EError(f"{name} is required")
    return value


def _resolve_allowed(path: Path, allowed_root: Path, kind: str) -> Path:
    """Return ``path`` only if it stays inside ``allowed_root``.

    Every deletion below goes through here first: a typo or a stray symlink in
    BUBLIK_E2E_PUBLISH_DIR must not turn into an rmtree somewhere else.
    """
    candidate = path.expanduser()
    if ".." in candidate.parts:
        raise E2EError(f"{kind} must not contain parent path components: {path}")
    if not candidate.is_absolute():
        candidate = ROOT / candidate
    candidate = candidate.absolute()
    try:
        resolved = candidate.resolve()
    except (OSError, RuntimeError) as error:
        raise E2EError(f"cannot resolve {kind}: {candidate}: {error}") from error
    allowed_root = allowed_root.absolute()
    try:
        resolved.relative_to(allowed_root)
    except ValueError as error:
        raise E2EError(
            f"{kind} must resolve under {allowed_root}, got {resolved}"
        ) from error
    return candidate


def _artifact_paths() -> tuple[Path, Path]:
    """The publish directory and manifest, both checked before anything is removed."""
    data_dir = Path(_required_environment("BUBLIK_DOCKER_DATA_DIR"))
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    try:
        data_dir = data_dir.expanduser().resolve()
    except (OSError, RuntimeError) as error:
        raise E2EError(f"cannot resolve BUBLIK_DOCKER_DATA_DIR: {error}") from error

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
        raise E2EError("manifest must be a file below ROOT/.e2e")
    if (
        publish_dir.exists()
        and not publish_dir.is_dir()
        and not publish_dir.is_symlink()
    ):
        raise E2EError(f"expected a publish directory: {publish_dir.resolve()}")
    if manifest.exists() and manifest.is_dir() and not manifest.is_symlink():
        raise E2EError(f"expected a manifest file: {manifest.resolve()}")
    return publish_dir, manifest


def _remove_directory(path: Path) -> None:
    if path.is_symlink():
        path.unlink()
    elif path.exists():
        if not path.is_dir():
            raise E2EError(f"expected a directory: {path}")
        shutil.rmtree(path)


def clean_artifacts() -> None:
    """Remove generated fixtures, the manifest, and Playwright's output."""
    publish_dir, manifest = _artifact_paths()
    _remove_directory(publish_dir)
    manifest.unlink(missing_ok=True)
    for relative in PLAYWRIGHT_ARTIFACTS:
        _remove_directory(_resolve_allowed(relative, ROOT.resolve(), "test output"))


def guard_compose_project() -> None:
    normal = _required_environment("BUBLIK_NORMAL_COMPOSE_PROJECT_NAME")
    e2e = _required_environment("BUBLIK_E2E_COMPOSE_PROJECT_NAME")
    if normal == e2e:
        raise E2EError(
            "refusing destructive cleanup because the E2E Compose project "
            f"equals the normal project: {normal!r}"
        )


def _api_bundles(manifest: Path) -> list[dict[str, Any]]:
    """Bundles the CLI is responsible for importing (the +ui ones are Playwright's)."""
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise E2EError(f"cannot read manifest {manifest}: {error}") from error
    bundles = data.get("bundles")
    if not isinstance(bundles, list):
        raise E2EError("manifest bundles must be an array")
    return [
        bundle
        for bundle in bundles
        if isinstance(bundle, dict) and bundle.get("importVia") != "ui"
    ]


def _run_exists(url: str) -> bool:
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=PROBE_TIMEOUT_SECONDS) as response:
            return 200 <= response.status < 300
    except (urllib.error.URLError, OSError, ValueError):
        return False


def is_seeded() -> bool:
    """True when the running instance already has this manifest's runs.

    A manifest full of run ids is not enough on its own: the database may have
    been wiped underneath it, in which case those ids point at nothing and the
    stack still needs seeding. So one id is probed against the live API.
    """
    manifest = Path(os.environ.get("BUBLIK_E2E_MANIFEST", "")).expanduser()
    if not manifest.is_file():
        return False
    bundles = _api_bundles(manifest)
    if not bundles:
        return False
    run_ids = [bundle.get("runId") for bundle in bundles]
    if any(run_id is None for run_id in run_ids):
        return False
    base_url = _required_environment("BUBLIK_E2E_URL").rstrip("/")
    return _run_exists(f"{base_url}/api/v2/runs/{run_ids[0]}/")


def main() -> int:
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else ""
        if command == "clean":
            clean_artifacts()
            return 0
        if command == "guard-compose-project":
            guard_compose_project()
            return 0
        if command == "seeded":
            return 0 if is_seeded() else 1
        raise E2EError("usage: e2e.py clean | guard-compose-project | seeded")
    except E2EError as error:
        print(f"e2e: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
