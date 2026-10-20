import hashlib
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

import source_inventory as inv


def blob(data):
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def fixture():
    sha = "a" * 40
    payloads = {
        "A.json": b'{ "name": "A", "version": "1.0" }\r\n',
        "B.json": b'{"name":"B","version":"1.0"}',
    }
    index = json.dumps([{"name": n, "version": "1.0"} for n in ["A", "B"]]).encode()
    tree = {"tree": [{"path": name, "type": "blob", "sha": blob(data)}
                     for name, data in {**payloads, "index.json": index}.items()]}
    resources = {
        inv.API: json.dumps({"full_name": inv.REPOSITORY, "default_branch": "main"}).encode(),
        f"{inv.API}/commits/main": json.dumps({"sha": sha}).encode(),
        f"{inv.API}/git/trees/{sha}?recursive=1": json.dumps(tree).encode(),
        f"https://raw.githubusercontent.com/{inv.REPOSITORY}/{sha}/index.json": index,
        **{f"https://raw.githubusercontent.com/{inv.REPOSITORY}/{sha}/{name}": data
           for name, data in payloads.items()},
    }
    return sha, payloads, resources


def inventory(count=2):
    return {"upstream_commit": "a" * 40, "entries": [
        {"name": f"S{i}", "validation": "qualified", "normalized_sha256": f"hash{i}",
         "captcha_declared_enabled": i == 1,
         "candidate_cases": [{"id": f"s{i}-q{j}"} for j in range(1, 4)]}
        for i in range(count)]}


def result(i=0, candidate=1, stage="no_match", **kwargs):
    return {"id": f"s{i}-q{candidate}", "key": f"k{i}-{candidate}", "engine": "app",
            "stage": stage, "cleanup": "confirmed",
            "host_cleanup": {"status": "confirmed"},
            "observed_rule_snapshot": {"effective_sha256": f"hash{i}"}, **kwargs}


class SnapshotTests(unittest.TestCase):
    def test_raw_bytes_are_preserved_and_resume_does_not_refetch_successes(self):
        sha, payloads, resources = fixture()
        calls = []
        def fetch(url):
            calls.append(url)
            return resources[url]
        with tempfile.TemporaryDirectory() as tmp:
            first = inv.capture(Path(tmp), sha, fetch)
            self.assertEqual([e["fetch_status"] for e in first["entries"]],
                             ["downloaded", "downloaded"])
            self.assertEqual((Path(tmp) / "rules/A.json").read_bytes(), payloads["A.json"])
            calls.clear()
            inv.capture(Path(tmp), sha, fetch)
            self.assertEqual(calls, [])

    def test_moving_head_and_blob_mismatch_are_not_accepted(self):
        sha, _, resources = fixture()
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                inv.capture(Path(tmp), "b" * 40, resources.__getitem__)
            resources[f"https://raw.githubusercontent.com/{inv.REPOSITORY}/{sha}/A.json"] = b"wrong"
            captured = inv.capture(Path(tmp), sha, resources.__getitem__)
            self.assertEqual(captured["entries"][0]["fetch_status"], "download_failed")

    def test_catalog_duplicates_and_traversal_are_retained_as_invalid(self):
        rows = inv.catalog_entries([{"name": "A"}, {"name": "a"},
                                    {"name": "../secret"}, None])
        self.assertEqual(len(rows), 4)
        self.assertEqual(sum(r["fetch_status"] == "pending" for r in rows), 1)


class PlanTests(unittest.TestCase):
    def test_unconfirmed_host_cleanup_cannot_be_counted_as_played(self):
        row = result(stage="first_frame", progress_ms=1500,
                     host_cleanup={"status": "unconfirmed"})
        before = deepcopy(row)
        plan = inv.next_plan(inventory(1), [row], attempts=[])
        self.assertEqual(plan["counts"], {"infrastructure_or_cleanup_unknown": 1})
        self.assertEqual(plan["batches"], [])
        state = plan["coverage"][0]
        self.assertTrue(state["fresh_playback_observed"])
        self.assertEqual(state["cleanup_evidence"][0]["app_cleanup"], "confirmed")
        self.assertEqual(state["cleanup_evidence"][0]["host_cleanup"],
                         {"status": "unconfirmed"})
        self.assertEqual(row, before)

    def test_legacy_missing_host_cleanup_stays_unknown_without_forced_retry(self):
        for stage in ["first_frame", "no_match"]:
            with self.subTest(stage=stage):
                row = result(stage=stage, progress_ms=1500)
                del row["host_cleanup"]
                before = deepcopy(row)
                plan = inv.next_plan(inventory(1), [row], attempts=[])
                self.assertEqual(plan["counts"], {"legacy_host_cleanup_unknown": 1})
                self.assertEqual(plan["batches"], [])
                state = plan["coverage"][0]
                self.assertEqual(state["fresh_playback_observed"], stage == "first_frame")
                self.assertEqual(state["cleanup_evidence"][0]["host_cleanup_format"],
                                 "legacy_missing")
                self.assertEqual(row, before)

    def test_host_cleanup_null_malformed_or_contradictory_is_unknown(self):
        for host in [None, "confirmed", {},
                     {"status": "confirmed", "process_exit": "unconfirmed"},
                     {"status": "confirmed", "errors": {}},
                     {"status": "confirmed", "errors": None},
                     {"status": "confirmed", "errors": [{"step": "sampler_exit"}]}]:
            with self.subTest(host=host):
                plan = inv.next_plan(inventory(1), [
                    result(stage="first_frame", progress_ms=1500, host_cleanup=host)
                ], attempts=[])
                self.assertEqual(plan["counts"], {"infrastructure_or_cleanup_unknown": 1})
                self.assertEqual(plan["batches"], [])

    def test_declared_captcha_is_attempted_and_batches_are_bounded(self):
        plan = inv.next_plan(inventory(25), [])
        self.assertEqual([len(b["cases"]) for b in plan["batches"]], [24, 1])
        self.assertEqual(plan["counts"], {"not_attempted": 25})

    def test_no_match_advances_but_actual_challenge_skips(self):
        plan = inv.next_plan(inventory(), [result(), result(1, stage="captcha")], attempts=[])
        self.assertEqual(plan["batches"][0]["cases"], [{"id": "s0-q2"}])
        self.assertEqual(plan["counts"]["skipped_actual_challenge"], 1)

    def test_success_and_media_failure_are_not_blindly_retried_with_other_titles(self):
        plan = inv.next_plan(inventory(), [
            result(stage="first_frame", progress_ms=1500),
            result(1, stage="resolve_timeout")], attempts=[])
        self.assertEqual(plan["batches"], [])
        self.assertEqual(plan["counts"], {"played": 1, "failure_requires_diagnosis": 1})

    def test_missing_snapshot_cleanup_or_attempt_journal_stays_unknown(self):
        for row in [result(observed_rule_snapshot=None), result(cleanup="unconfirmed")]:
            plan = inv.next_plan(inventory(1), [row], attempts=[])
            self.assertEqual(plan["batches"], [])
            self.assertNotIn("played", plan["counts"])
        self.assertEqual(inv.next_plan(inventory(1), [result()])["counts"],
                         {"attempt_history_unknown": 1})

    def test_started_without_terminal_row_is_not_requeued(self):
        pending = {"id": "s0-q1", "engine": "app", "key": "new-attempt"}
        plan = inv.next_plan(inventory(1), [result()], attempts=[pending])
        self.assertEqual(plan["batches"], [])
        self.assertEqual(plan["counts"], {"attempt_without_terminal_result": 1})

    def test_exhausted_titles_are_coverage_gap_not_broken_source(self):
        plan = inv.next_plan(inventory(1), [result(candidate=i) for i in range(1, 4)],
                             attempts=[])
        self.assertEqual(plan["counts"],
                         {"title_candidates_exhausted_coverage_insufficient": 1})


if __name__ == "__main__":
    unittest.main()
