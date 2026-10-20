"""Acquire only the current official catalog; never contacts streaming sites."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
from urllib.request import Request, urlopen

REPOSITORY = "Predidit/KazumiRules"
API = f"https://api.github.com/repos/{REPOSITORY}"
SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def fetch_bytes(url):
    with urlopen(Request(url, headers={"User-Agent": "KazumiTV-source-inventory"}),
                 timeout=25) as response:
        data = response.read(1024 * 1024 + 1)
    if len(data) > 1024 * 1024:
        raise ValueError("Snapshot response exceeds 1 MiB")
    return data


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def immutable_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError("Existing snapshot content differs")
        return
    with path.open("xb") as stream:
        stream.write(data)


def catalog_entries(index):
    if not isinstance(index, list):
        raise ValueError("Catalog must be an array")
    seen = set()
    entries = []
    for position, row in enumerate(index):
        item = {"catalog_position": position, "fetch_status": "invalid_catalog_entry"}
        if not isinstance(row, dict):
            item["reason"] = "not_object"
        else:
            name = row.get("name")
            item.update(name=name, index_version=row.get("version"))
            if not isinstance(name, str) or not SAFE_NAME.fullmatch(name):
                item["reason"] = "unsafe_or_missing_name"
            elif name.casefold() in seen:
                item["reason"] = "duplicate_name"
            else:
                seen.add(name.casefold())
                item["fetch_status"] = "pending"
        entries.append(item)
    return entries


def capture(output, expected_commit=None, fetch=fetch_bytes):
    output = Path(output)
    previous = output / "source_inventory_download.json"
    if previous.exists():
        prior = json.loads(previous.read_text(encoding="utf-8"))
        if prior.get("repository") != REPOSITORY:
            raise ValueError("Existing snapshot repository mismatch")
        # Resume the pinned capture, not a fresh moving-branch scan.
        metadata_raw = (output / "repository.json").read_bytes()
        commit_raw = (output / "commit.json").read_bytes()
        tree_raw = (output / "tree.json").read_bytes()
    else:
        metadata_raw = fetch(API)
        metadata = json.loads(metadata_raw)
        commit_raw = fetch(f"{API}/commits/{metadata['default_branch']}")
        commit = json.loads(commit_raw)["sha"]
        tree_raw = fetch(f"{API}/git/trees/{commit}?recursive=1")
    metadata = json.loads(metadata_raw)
    if metadata.get("full_name") != REPOSITORY:
        raise ValueError("Repository identity mismatch")
    branch = metadata["default_branch"]
    commit = json.loads(commit_raw)["sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid commit SHA")
    if expected_commit is not None and commit != expected_commit:
        raise ValueError("Default branch moved; review the new snapshot explicitly")
    tree = json.loads(tree_raw)
    if tree.get("truncated"):
        raise ValueError("Truncated tree cannot prove missing files")
    blobs = {row["path"]: row["sha"] for row in tree["tree"]
             if row.get("type") == "blob"}
    raw_root = f"https://raw.githubusercontent.com/{REPOSITORY}/{commit}"
    index_file = output / "index.json"
    index_raw = index_file.read_bytes() if previous.exists() else fetch(f"{raw_root}/index.json")
    expected_index_blob = blobs.get("index.json")
    actual_index_blob = hashlib.sha1(
        f"blob {len(index_raw)}\0".encode() + index_raw).hexdigest()
    if expected_index_blob != actual_index_blob:
        raise ValueError("Index Git blob mismatch")
    for name, data in (("repository.json", metadata_raw), ("commit.json", commit_raw),
                       ("tree.json", tree_raw), ("index.json", index_raw)):
        immutable_write(output / name, data)
    entries = catalog_entries(json.loads(index_raw.decode("utf-8-sig")))

    def download(item):
        if item["fetch_status"] != "pending":
            return item
        name = item["name"]
        filename = f"{name}.json"
        if filename not in blobs:
            return {**item, "fetch_status": "missing_from_commit"}
        path = output / "rules" / filename
        try:
            # Reuse verified raw files when resuming the same pinned snapshot.
            data = path.read_bytes() if path.exists() else fetch(f"{raw_root}/{filename}")
            blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
            if blob != blobs[filename]:
                raise ValueError("Rule Git blob mismatch")
            immutable_write(path, data)
            return {**item, "fetch_status": "downloaded",
                    "raw_path": f"rules/{filename}", "raw_sha256": sha256(data),
                    "git_blob_sha1": blob, "bytes": len(data)}
        except Exception as error:
            # Do not serialize exception messages/URLs/headers.
            return {**item, "fetch_status": "download_failed",
                    "error_type": type(error).__name__}

    with ThreadPoolExecutor(max_workers=4) as executor:
        entries = list(executor.map(download, entries))
    manifest = {"schema_version": 1, "repository": REPOSITORY,
                "default_branch": branch, "commit": commit,
                "index_sha256": sha256(index_raw),
                "catalog_rows": len(entries), "entries": entries,
                "source_verification": "https_snapshot_git_blob_checked_no_signature",
                "network_scope": "official_github_only"}
    # This manifest may be refreshed after a failed download; raw inputs remain immutable.
    (output / "source_inventory_download.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def next_plan(inventory, rows, engine="app", attempts=None):
    """Select at most one untried title per source, preserving coverage gaps."""
    entries = inventory["entries"]
    rows_by_id = {}
    for row in rows:
        if row.get("engine") == engine:
            rows_by_id.setdefault(row.get("id"), []).append(row)
    completed_keys = {(r.get("key"), r.get("id"), r.get("engine"))
                      for r in rows if r.get("key") is not None}
    unknown_ids = {a.get("id") for a in (attempts or [])
                   if a.get("engine") == engine and
                   (a.get("key") is None or
                    (a["key"], a.get("id"), a.get("engine")) not in completed_keys)}
    coverage, cases = [], []
    fallback_stages = {"no_match", "no_unique_match", "episode_missing"}
    for entry in entries:
        state = {"name": entry.get("name"), "validation": entry["validation"]}
        coverage.append(state)
        if entry["validation"] != "qualified":
            state["status"] = "preflight_excluded"
            continue
        candidates = entry["candidate_cases"]
        if any(c["id"] in unknown_ids for c in candidates):
            state["status"] = "attempt_without_terminal_result"
            continue
        if rows and attempts is None:
            state["status"] = "attempt_history_unknown"
            continue
        observed = [r for c in candidates for r in rows_by_id.get(c["id"], [])]
        matching = [r for r in observed if
                    isinstance(r.get("observed_rule_snapshot"), dict) and
                    r["observed_rule_snapshot"].get("effective_sha256")
                    == entry["normalized_sha256"]]
        state.update(attempts=len(observed), matching_identity_attempts=len(matching),
                     outcomes=[r.get("stage", "unknown") for r in observed])
        if len(matching) != len(observed):
            state["status"] = "identity_unknown_or_mismatch"
            continue
        if any(r.get("stage") in {"environment_invalid", "host_timeout", "host_error",
                                 "interrupted", "unknown"} or
               r.get("cleanup") != "confirmed" for r in matching):
            state["status"] = "infrastructure_or_cleanup_unknown"
            continue
        if any(r.get("stage") == "captcha" for r in matching):
            state["status"] = "skipped_actual_challenge"
            continue
        successes = [r for r in matching if r.get("stage") == "first_frame"
                     and isinstance(r.get("progress_ms"), (int, float))
                     and not isinstance(r["progress_ms"], bool)
                     and r["progress_ms"] > 0
                     and not r.get("from_confirmed_cache", False)]
        if successes:
            state["status"] = ("played_with_failures" if len(successes) != len(matching)
                               else "played")
            continue
        if any(r.get("stage") not in fallback_stages for r in matching):
            state["status"] = "failure_requires_diagnosis"
            continue
        tried = {r["id"] for r in observed}
        candidate = next((c for c in candidates if c["id"] not in tried), None)
        if candidate is None:
            state["status"] = "title_candidates_exhausted_coverage_insufficient"
        else:
            state["status"] = "not_attempted" if not observed else "fallback_title_pending"
            cases.append(candidate)
    counts = {}
    for entry in coverage:
        counts[entry["status"]] = counts.get(entry["status"], 0) + 1
    return {"schema_version": 1, "upstream_commit": inventory["upstream_commit"],
            "engine": engine, "catalog_rows": len(entries), "coverage": coverage,
            "counts": counts,
            "batches": [{"cases": cases[i:i + 24],
                         "inventory_commit": inventory["upstream_commit"],
                         "execution_policy": "filtered_one_candidate_per_source"}
                        for i in range(0, len(cases), 24)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-commit")
    parser.add_argument("--plan-from", type=Path)
    parser.add_argument("--results", type=Path, action="append", default=[])
    parser.add_argument("--attempts", type=Path, action="append", default=[])
    parser.add_argument("--engine", choices=["app", "webview", "gecko"], default="app")
    args = parser.parse_args()
    if args.plan_from:
        inventory = json.loads(args.plan_from.read_text(encoding="utf-8"))
        rows = []
        for path in args.results:
            # A truncated ledger is an unknown input, not permission to repeat it.
            for line in path.read_text(encoding="utf-8-sig").splitlines():
                if line.strip():
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        raise ValueError("Invalid result row")
                    rows.append(row)
        attempts = None
        if args.attempts:
            attempts = []
            for path in args.attempts:
                for line in path.read_text(encoding="utf-8-sig").splitlines():
                    if line.strip():
                        attempt = json.loads(line)
                        if not isinstance(attempt, dict):
                            raise ValueError("Invalid attempt row")
                        attempts.append(attempt)
        plan = next_plan(inventory, rows, args.engine, attempts)
        args.output.mkdir(parents=True, exist_ok=True)
        for i, batch in enumerate(plan["batches"], 1):
            immutable_write(args.output / f"batch-{i}.json",
                            (json.dumps(batch, ensure_ascii=False, indent=2) + "\n").encode())
        immutable_write(args.output / "source_coverage.json",
                        (json.dumps(plan, ensure_ascii=False, indent=2) + "\n").encode())
        print(json.dumps({"catalog_rows": plan["catalog_rows"], "counts": plan["counts"],
                          "batch_sizes": [len(b["cases"]) for b in plan["batches"]]}))
        return
    manifest = capture(args.output, args.expected_commit)
    counts = {}
    for entry in manifest["entries"]:
        status = entry["fetch_status"]
        counts[status] = counts.get(status, 0) + 1
    print(json.dumps({"commit": manifest["commit"],
                      "catalog_rows": manifest["catalog_rows"], "downloads": counts}))


if __name__ == "__main__":
    main()
