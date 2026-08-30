#!/usr/bin/env python3
"""Deterministic, evidence-preserving staging for APEX food composition data.

Publisher bundles are supplied through an external directory. This tool emits
canonical JSON Lines into another external staging directory; it never copies a
raw publisher bundle into the repository or into an application client.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from typing import Any, Iterable
import unicodedata
import uuid

from adapters import SUPPORTED_PARSERS, parse_source, search_projection


SCRIPT_PATH = Path(__file__).resolve()
REPOSITORY_ROOT = SCRIPT_PATH.parents[2]
REGISTRY_PATH = SCRIPT_PATH.with_name("sources.json")
SOURCE_ROOT_ENV = "APEX_FOOD_CORPUS_SOURCE_ROOT"
STAGING_FILES = (
    "sources.ndjson",
    "batches.ndjson",
    "records.ndjson",
    "names.ndjson",
    "nutrients.ndjson",
    "search.ndjson",
)
SEARCH_PROJECTION_ORDER_FIELD = "source_priority"

TRACE_MARKERS = {"tr", "tr.", "trace", "traces"}
NOT_MEASURED_MARKERS = {"n", "nd", "n/a", "na", "not measured", "not analysed", "not analyzed"}
MISSING_MARKERS = {"", "-", "—", "..", "...", "null", "none"}


def assert_external_path(path: Path, label: str) -> Path:
    """Reject repository-owned raw inputs and staging outputs."""

    resolved = path.expanduser().resolve()
    try:
        resolved.relative_to(REPOSITORY_ROOT)
    except ValueError:
        return resolved
    raise ValueError(f"{label} must remain outside the repository: {resolved}")


def load_registry() -> list[dict[str, Any]]:
    with REGISTRY_PATH.open(encoding="utf-8") as handle:
        sources = json.load(handle)
    if not isinstance(sources, list):
        raise ValueError("sources.json must contain a list")
    return sources


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def registered_artifacts(source: dict[str, Any]) -> list[dict[str, str]]:
    return [
        {"path": source["path"], "checksum": source["checksum"]},
        *source.get("companions", []),
    ]


def verify_source_artifacts(root: Path, source: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    for registered in registered_artifacts(source):
        relative_path = registered["path"]
        artifact = root / relative_path
        expected = registered["checksum"].removeprefix("sha256:")
        if not artifact.is_file():
            failures.append(f"{source['key']}: missing {relative_path}")
            continue
        actual = sha256(artifact)
        if actual != expected:
            failures.append(f"{source['key']}: {relative_path} checksum {actual} != {expected}")
            continue
        print(f"verified {source['key']} {relative_path} {actual}")
    return failures


def normalize_text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip())


def normalized_search_text(value: Any) -> str:
    decomposed = unicodedata.normalize("NFKD", normalize_text(value)).casefold()
    without_marks = "".join(char for char in decomposed if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", " ", without_marks).strip()


def parse_observation(raw_value: Any) -> tuple[str, float | None, str]:
    original = "" if raw_value is None else str(raw_value).strip()
    folded = original.casefold()

    if folded in MISSING_MARKERS:
        return "missing", None, original
    if folded in TRACE_MARKERS:
        return "trace", None, original
    if folded in NOT_MEASURED_MARKERS:
        return "not_measured", None, original
    if original.startswith("<"):
        return "below_detection", None, original

    numeric = original.replace("\u00a0", "").replace(" ", "")
    if numeric.count(",") == 1 and "." not in numeric:
        numeric = numeric.replace(",", ".")
    try:
        return "measured", float(numeric), original
    except ValueError as error:
        raise ValueError(f"unsupported nutrient observation: {original!r}") from error


def canonical_fixture_records(payload: dict[str, Any]) -> Iterable[dict[str, Any]]:
    records = payload.get("records")
    if not isinstance(records, list):
        raise ValueError("fixture must contain a records list")

    for raw_record in records:
        basis = raw_record.get("basis") or {}
        basis_kind = basis.get("kind")
        basis_unit = basis.get("unit")
        allowed_basis = {
            "per_100g": "g",
            "per_100ml": "ml",
            "per_serving": "serving",
            "edible_portion": "g_edible",
            "dry_matter": "g_dry_matter",
        }
        if basis_kind not in allowed_basis or basis_unit != allowed_basis[basis_kind]:
            raise ValueError(f"invalid basis: {basis!r}")

        canonical_nutrients = []
        for nutrient in raw_record.get("nutrients", []):
            status, value, original = parse_observation(nutrient.get("raw_value"))
            canonical_nutrients.append(
                {
                    "code": normalize_text(nutrient.get("code")),
                    "name": normalize_text(nutrient.get("name")),
                    "unit": normalize_text(nutrient.get("unit")),
                    "value": value,
                    "observation_status": status,
                    "original_value_text": original,
                }
            )

        yield {
            "schema_version": 1,
            "source_key": normalize_text(raw_record.get("source_key")),
            "source_record_id": normalize_text(raw_record.get("source_record_id")),
            "name": normalize_text(raw_record.get("name")),
            "basis": {
                "kind": basis_kind,
                "amount": basis.get("amount"),
                "unit": basis_unit,
            },
            "nutrients": canonical_nutrients,
        }


def command_parse_fixture(args: argparse.Namespace) -> int:
    with Path(args.input).open(encoding="utf-8") as handle:
        payload = json.load(handle)
    for record in canonical_fixture_records(payload):
        print(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


def resolve_source_root(value: str | None) -> Path:
    configured = value or os.environ.get(SOURCE_ROOT_ENV)
    if not configured:
        raise ValueError(
            f"provide --source-root or set {SOURCE_ROOT_ENV}; raw data is never inferred from a user directory"
        )
    root = assert_external_path(Path(configured), "source root")
    if not root.is_dir():
        raise ValueError(f"source root does not exist: {root}")
    return root


def command_validate_registry(args: argparse.Namespace) -> int:
    root = resolve_source_root(args.source_root)
    failures: list[str] = []
    for source in load_registry():
        failures.extend(verify_source_artifacts(root, source))
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    return 0


def command_stage_source(args: argparse.Namespace) -> int:
    root = resolve_source_root(args.source_root)
    output = assert_external_path(Path(args.output), "staging output")
    sources = {source["key"]: source for source in load_registry()}
    source = sources.get(args.source)
    if source is None:
        raise ValueError(f"unknown source: {args.source}")
    if source["status"] != "approved":
        raise ValueError(f"source is quarantined by its licence gate: {args.source}")

    artifact = root / source["path"]
    artifact_failures = verify_source_artifacts(root, source)
    if artifact_failures:
        raise ValueError("; ".join(artifact_failures))

    stage_directory = output / args.source
    stage_directory.mkdir(parents=True, exist_ok=True)
    checksum = source["checksum"].removeprefix("sha256:")
    batch_id = str(
        uuid.uuid5(
            uuid.UUID("cf87d423-ad7c-506f-928b-1867ac050761"),
            f"batch:{source['key']}:{checksum}:{source['parser']}",
        )
    )
    source_row = {
        "source_key": source["key"],
        "dataset_name": source["dataset_name"],
        "publisher": source["publisher"],
        "version": source["version"],
        "source_url": source.get("source_url") or source["licence_url"],
        "licence_id": source["licence"],
        "licence_url": source["licence_url"],
        "attribution": source["attribution"],
        "checksum_sha256": checksum,
        "parser_version": source["parser"],
        "redistribution_scope": (
            "permissive"
            if source["licence"] == "CC0-1.0"
            else "share_alike_isolated"
            if source["licence"] == "ODbL-1.0"
            else "attribution"
        ),
        "ingest_status": "registered",
        "metadata": {
            "artifact": source["path"],
            "companions": source.get("companions", []),
        },
    }
    batch_row = {
        "id": batch_id,
        "source_key": source["key"],
        "source_checksum_sha256": checksum,
        "parser_version": source["parser"],
        "status": "validated",
    }

    paths = {name: stage_directory / name for name in STAGING_FILES}
    handles = {name: path.open("w", encoding="utf-8") for name, path in paths.items()}
    records_seen = 0
    nutrients_seen = 0
    macro_complete = 0
    macro_partial = 0
    try:
        write_ndjson(handles["sources.ndjson"], source_row)
        write_ndjson(handles["batches.ndjson"], batch_row)
        for record in parse_source(
            artifact,
            source,
            max_records=args.max_records,
            brands=args.brand,
        ):
            records_seen += 1
            projection = search_projection(record)
            required_macros = (
                projection["kcal"],
                projection["protein_g"],
                projection["carbs_g"],
                projection["fat_g"],
            )
            if all(value is not None for value in required_macros):
                macro_complete += 1
            elif any(value is not None for value in required_macros):
                macro_partial += 1

            record_row = {
                key: value
                for key, value in record.items()
                if key not in {"aliases", "nutrients"}
            }
            record_row["batch_id"] = batch_id
            write_ndjson(handles["records.ndjson"], record_row)

            names = [
                {
                    "record_id": record["id"],
                    "language": record["primary_language"],
                    "name": record["canonical_name"],
                    "normalized_name": normalized_search_text(record["canonical_name"]),
                    "name_kind": "canonical",
                    "market": record.get("market"),
                }
            ]
            names.extend(
                {
                    "record_id": record["id"],
                    "language": record["primary_language"],
                    "name": alias,
                    "normalized_name": normalized_search_text(alias),
                    "name_kind": "alias",
                    "market": record.get("market"),
                }
                for alias in record["aliases"]
            )
            for name in names:
                write_ndjson(handles["names.ndjson"], name)

            source_code_counts: dict[str, int] = {}
            for nutrient in record["nutrients"]:
                nutrients_seen += 1
                source_code = nutrient["source_nutrient_code"]
                source_code_counts[source_code] = source_code_counts.get(source_code, 0) + 1
                nutrient_row = dict(nutrient)
                if source_code_counts[source_code] > 1:
                    nutrient_row["source_nutrient_code"] = (
                        f"{source_code}:{source_code_counts[source_code]}"
                    )
                nutrient_row["record_id"] = record["id"]
                write_ndjson(handles["nutrients.ndjson"], nutrient_row)
            write_ndjson(handles["search.ndjson"], projection)
    finally:
        for handle in handles.values():
            handle.close()

    batch_row.update(
        {
            "records_seen": records_seen,
            "records_accepted": records_seen,
            "records_rejected": 0,
            "validation_report": {
                "macro_complete": macro_complete,
                "macro_partial": macro_partial,
                "nutrient_observations": nutrients_seen,
            },
        }
    )
    with paths["batches.ndjson"].open("w", encoding="utf-8") as handle:
        write_ndjson(handle, batch_row)

    manifest = {
        "schema_version": 1,
        "source": source,
        "artifact": artifact.name,
        "checksum_verified": True,
        "state": "validated",
        "batch_id": batch_id,
        "records": records_seen,
        "nutrient_observations": nutrients_seen,
        "macro_complete": macro_complete,
        "macro_partial": macro_partial,
        "max_records": args.max_records,
        "brands": args.brand,
        "files": list(STAGING_FILES),
    }
    manifest_path = stage_directory / "manifest.json"
    with manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print(manifest_path)
    return 0


def write_ndjson(handle, value: dict[str, Any]) -> None:
    handle.write(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    handle.write("\n")


def command_list_parsers(args: argparse.Namespace) -> int:
    names = sorted(SUPPORTED_PARSERS)
    if args.json:
        print(json.dumps(names, separators=(",", ":")))
    else:
        for name in names:
            print(name)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    fixture = commands.add_parser("parse-fixture", help="normalize a small evidence fixture")
    fixture.add_argument("--input", required=True)
    fixture.set_defaults(handler=command_parse_fixture)

    validate = commands.add_parser("validate-registry", help="verify every registered source artifact")
    validate.add_argument("--source-root")
    validate.set_defaults(handler=command_validate_registry)

    stage = commands.add_parser("stage-source", help="checksum-gate a source into external staging")
    stage.add_argument("--source-root")
    stage.add_argument("--source", required=True)
    stage.add_argument("--output", required=True)
    stage.add_argument("--max-records", type=int)
    stage.add_argument("--brand", action="append", default=[])
    stage.set_defaults(handler=command_stage_source)

    list_parsers = commands.add_parser("list-parsers", help="list deterministic source adapters")
    list_parsers.add_argument("--json", action="store_true")
    list_parsers.set_defaults(handler=command_list_parsers)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return int(args.handler(args))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"food-corpus: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
