import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from scripts import e2e_plan


VALID_PLAN = {
    "version": 1,
    "runs": 2,
    "mixes": {"healthy": "expectedFailed=10%,expectedSkipped=1"},
    "days": {
        "2026-04-19": "",
        "2026-04-20": "basic.ok@healthy+ui=1,dpdk-ethdev-ts.warning=1",
    },
}


class PlanParsingTests(unittest.TestCase):
    def write_plan(self, directory: Path, plan: dict[str, object]) -> Path:
        path = directory / "plan.json"
        path.write_text(json.dumps(plan), encoding="utf-8")
        return path

    def test_valid_plan_includes_empty_day(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            arguments = e2e_plan.load_plan(self.write_plan(Path(temporary), VALID_PLAN))

        self.assertIn("2026-04-19:", arguments)
        self.assertIn(
            "2026-04-20:basic.ok@healthy+ui=1,dpdk-ethdev-ts.warning=1", arguments
        )

    def test_default_plan_keeps_report_capable_dpdk_fixture(self) -> None:
        plan = json.loads(e2e_plan.DEFAULT_PLAN.read_text(encoding="utf-8"))

        self.assertEqual(
            e2e_plan.BUNDLED_FIXTURE_PROJECTS["dpdk-ethdev-ts"],
            "tsf/dpdk-ethdev",
        )
        self.assertTrue(
            any(
                "dpdk-ethdev-ts.ok" in specification
                for specification in plan["days"].values()
            )
        )

    def test_generated_dpdk_bundle_uses_project_selected_by_ui(self) -> None:
        manifest = {
            "bundles": [{"fixture": "dpdk-ethdev-ts", "project": "tsf/dpdk-ethdev"}]
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")

            e2e_plan.validate_manifest_projects(path)

    def test_rejects_wrong_dpdk_project_in_generated_manifest(self) -> None:
        manifest = {"bundles": [{"fixture": "dpdk-ethdev-ts", "project": "wrong"}]}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaisesRegex(e2e_plan.PlanError, "tsf/dpdk-ethdev"):
                e2e_plan.validate_manifest_projects(path)

    def test_unscoped_item_counts_every_bundled_fixture(self) -> None:
        plan = {**VALID_PLAN, "runs": 3, "days": {"2026-04-20": "ok=1"}}
        with tempfile.TemporaryDirectory() as temporary:
            e2e_plan.load_plan(self.write_plan(Path(temporary), plan))

    def test_rejects_common_semantic_errors(self) -> None:
        cases = {
            "unknown fixture": {"days": {"2026-04-20": "other.ok=2"}},
            "unknown conclusion": {"days": {"2026-04-20": "basic.green=2"}},
            "unknown mix": {"days": {"2026-04-20": "basic.ok@missing=2"}},
            "misplaced ui": {"days": {"2026-04-20": "basic.ok+ui@healthy=2"}},
            "invalid count": {"days": {"2026-04-20": "basic.ok=-1"}},
            "wrong derived count": {"runs": 3},
            "invalid mix key": {"mixes": {"healthy": "surprisingFailed=10%"}},
            "excess percentages": {
                "mixes": {"healthy": "expectedFailed=60%,expectedSkipped=50%"}
            },
            "fractional absolute count": {"mixes": {"healthy": "expectedFailed=1.5"}},
        }
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name, changes in cases.items():
                with self.subTest(name=name):
                    plan = {**VALID_PLAN, **changes}
                    with self.assertRaises(e2e_plan.PlanError):
                        e2e_plan.load_plan(self.write_plan(directory, plan))

    def test_rejects_duplicate_json_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "plan.json"
            path.write_text(
                '{"version":1,"runs":1,"runs":2,"mixes":{},'
                '"days":{"2026-04-20":"basic.ok=1"}}',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(e2e_plan.PlanError, "duplicate JSON key"):
                e2e_plan.load_plan(path)


class CleanupSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        self.data_dir = self.root / "data" / "e2e"
        self.publish_root = self.data_dir / "logs" / "logs" / "e2e"
        self.manifest_root = self.root / ".e2e"
        self.publish_root.mkdir(parents=True)
        self.manifest_root.mkdir()
        self.environment = {
            "BUBLIK_DOCKER_DATA_DIR": str(self.data_dir),
            "BUBLIK_E2E_PUBLISH_DIR": str(self.publish_root / "campaign"),
            "BUBLIK_E2E_MANIFEST": str(self.manifest_root / "manifest.json"),
        }
        self.root_patch = patch.object(e2e_plan, "ROOT", self.root)
        self.root_patch.start()

    def tearDown(self) -> None:
        self.root_patch.stop()
        self.temporary.cleanup()

    def clean(self, **overrides: str) -> None:
        environment = {**self.environment, **overrides}
        with patch.dict(os.environ, environment, clear=True):
            e2e_plan.clean_artifacts()

    def test_removes_only_allowed_artifacts(self) -> None:
        publish_dir = Path(self.environment["BUBLIK_E2E_PUBLISH_DIR"])
        manifest = Path(self.environment["BUBLIK_E2E_MANIFEST"])
        sibling = self.data_dir / "keep.txt"
        publish_dir.mkdir()
        (publish_dir / "bundle.tar").write_text("fixture", encoding="utf-8")
        manifest.write_text("{}", encoding="utf-8")
        sibling.write_text("keep", encoding="utf-8")

        self.clean()

        self.assertFalse(publish_dir.exists())
        self.assertFalse(manifest.exists())
        self.assertEqual(sibling.read_text(encoding="utf-8"), "keep")

    def test_rejects_outside_publish_path_before_deleting_manifest(self) -> None:
        manifest = Path(self.environment["BUBLIK_E2E_MANIFEST"])
        manifest.write_text("keep", encoding="utf-8")

        with self.assertRaisesRegex(e2e_plan.PlanError, "publish directory"):
            self.clean(BUBLIK_E2E_PUBLISH_DIR=str(self.root / "outside"))

        self.assertTrue(manifest.exists())

    def test_rejects_outside_manifest_before_deleting_publish_dir(self) -> None:
        publish_dir = Path(self.environment["BUBLIK_E2E_PUBLISH_DIR"])
        publish_dir.mkdir()

        with self.assertRaisesRegex(e2e_plan.PlanError, "manifest"):
            self.clean(BUBLIK_E2E_MANIFEST=str(self.root / "outside.json"))

        self.assertTrue(publish_dir.exists())

    def test_rejects_parent_path_components(self) -> None:
        with self.assertRaisesRegex(e2e_plan.PlanError, "parent path components"):
            self.clean(BUBLIK_E2E_MANIFEST=str(self.manifest_root / "sub" / ".." / "x"))

    def test_rejects_publish_symlink_escape(self) -> None:
        outside = self.root / "outside"
        outside.mkdir()
        link = self.publish_root / "link"
        link.symlink_to(outside, target_is_directory=True)

        with self.assertRaisesRegex(e2e_plan.PlanError, "publish directory"):
            self.clean(BUBLIK_E2E_PUBLISH_DIR=str(link))

        self.assertTrue(outside.exists())
        self.assertTrue(link.is_symlink())

    def test_rejects_manifest_symlink_escape(self) -> None:
        outside = self.root / "outside.json"
        outside.write_text("keep", encoding="utf-8")
        link = self.manifest_root / "manifest.json"
        link.symlink_to(outside)

        with self.assertRaisesRegex(e2e_plan.PlanError, "manifest"):
            self.clean(BUBLIK_E2E_MANIFEST=str(link))

        self.assertEqual(outside.read_text(encoding="utf-8"), "keep")
        self.assertTrue(link.is_symlink())


class GenerationSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        self.data_dir = self.root / "data" / "e2e"
        self.publish_dir = self.data_dir / "logs" / "logs" / "e2e" / "campaign"
        self.manifest_dir = self.root / ".e2e"
        self.manifest = self.manifest_dir / "manifest.json"
        self.publish_dir.mkdir(parents=True)
        self.manifest_dir.mkdir()
        self.bundle = self.publish_dir / "existing.tar"
        self.bundle.write_text("existing bundle", encoding="utf-8")
        self.manifest.write_text("existing manifest", encoding="utf-8")
        self.environment = {
            "BUBLIK_DOCKER_DATA_DIR": str(self.data_dir),
            "BUBLIK_E2E_PUBLISH_DIR": str(self.publish_dir),
            "BUBLIK_E2E_MANIFEST": str(self.manifest),
            "BUBLIK_E2E_URL": "http://127.0.0.1",
            "BUBLIK_E2E_RUN_LOG_SCHEMA": "run-log.json",
            "BUBLIK_E2E_META_DATA_SCHEMA": "meta-data.json",
        }
        self.root_patch = patch.object(e2e_plan, "ROOT", self.root)
        self.root_patch.start()

    def tearDown(self) -> None:
        self.root_patch.stop()
        self.temporary.cleanup()

    def assert_artifacts_unchanged(self) -> None:
        self.assertEqual(self.bundle.read_text(encoding="utf-8"), "existing bundle")
        self.assertEqual(self.manifest.read_text(encoding="utf-8"), "existing manifest")

    def test_invalid_default_plan_preserves_existing_artifacts(self) -> None:
        plan = self.root / "invalid-plan.json"
        plan.write_text(
            json.dumps({**VALID_PLAN, "runs": 3}),
            encoding="utf-8",
        )
        environment = {**self.environment, "BUBLIK_E2E_PLAN_FILE": str(plan)}

        with (
            patch.dict(os.environ, environment, clear=True),
            patch.object(e2e_plan.subprocess, "run") as run,
            self.assertRaises(e2e_plan.PlanError),
        ):
            e2e_plan.run_cli("generate", [])

        run.assert_not_called()
        self.assert_artifacts_unchanged()

    def test_failed_custom_generator_preserves_existing_artifacts(self) -> None:
        environment = {**self.environment, "BUBLIK_E2E_BIN": "failing-generator"}

        with (
            patch.dict(os.environ, environment, clear=True),
            patch.object(
                e2e_plan.subprocess,
                "run",
                return_value=Mock(returncode=1),
            ) as run,
        ):
            return_code = e2e_plan.run_cli(
                "generate", ["--runs", "1", "--day", "2026-04-20:basic.ok=1"]
            )

        self.assertEqual(return_code, 1)
        run.assert_called_once()
        self.assert_artifacts_unchanged()


class ComposeGuardTests(unittest.TestCase):
    def test_rejects_normal_project_name(self) -> None:
        with patch.dict(
            os.environ,
            {
                "BUBLIK_NORMAL_COMPOSE_PROJECT_NAME": "bublik",
                "BUBLIK_E2E_COMPOSE_PROJECT_NAME": "bublik",
            },
            clear=True,
        ):
            with self.assertRaises(e2e_plan.PlanError):
                e2e_plan.guard_compose_project()

    def test_accepts_distinct_project_name(self) -> None:
        with patch.dict(
            os.environ,
            {
                "BUBLIK_NORMAL_COMPOSE_PROJECT_NAME": "bublik",
                "BUBLIK_E2E_COMPOSE_PROJECT_NAME": "bublik-e2e",
            },
            clear=True,
        ):
            e2e_plan.guard_compose_project()


if __name__ == "__main__":
    unittest.main()
