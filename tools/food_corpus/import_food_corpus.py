#!/usr/bin/env python3
"""Deterministic, evidence-preserving staging for APEX food composition data.

Publisher bundles are supplied through an external directory. This tool emits
canonical JSON Lines into another external staging directory; it never copies a
raw publisher bundle into the repository or into an application client.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
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

TRACE_MARKERS = {"tr", "tr.", "(tr)", "trace", "traces"}
NOT_MEASURED_MARKERS = {"n", "nd", "n/a", "na", "not measured", "not analysed", "not analyzed"}
MISSING_MARKERS = {"", "-", "—", "..", "...", "null", "none", "*"}


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

    parenthetical = original.startswith("(") and original.endswith(")")
    numeric = re.sub(r"[†‡]+$", "", original).strip()
    numeric = numeric.strip("() ").replace("\u00a0", "").replace(" ", "")
    if numeric.count(",") == 1 and "." not in numeric:
        numeric = numeric.replace(",", ".")
    try:
        return ("estimated" if parenthetical else "measured"), float(numeric), original
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
        "file_checksums": {
            filename: f"sha256:{sha256(paths[filename])}"
            for filename in STAGING_FILES
        },
    }
    manifest_path = stage_directory / "manifest.json"
    with manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print(manifest_path)
    return 0


def psql_copy_path(path: Path) -> str:
    return str(path).replace("\\", "\\\\").replace("'", "''")


def decoded_insert(
    *,
    payload_table: str,
    destination_table: str,
    columns: tuple[str, ...],
    conflict: str,
    update_columns: tuple[str, ...],
    distinct_on: tuple[str, ...] = (),
) -> str:
    selections = ",\n  ".join(f"(decoded).{column}" for column in columns)
    distinct = ""
    order = ""
    if distinct_on:
        keys = ", ".join(f"(decoded).{column}" for column in distinct_on)
        distinct = f"distinct on ({keys}) "
        order = f"\norder by {keys}"
    updates = ",\n  ".join(
        f"{column} = excluded.{column}" for column in update_columns
    )
    return f"""insert into public.{destination_table} (
  {', '.join(columns)}
)
select {distinct}{selections}
from (
  select jsonb_populate_record(null::public.{destination_table}, payload) as decoded
  from {payload_table}
) incoming{order}
on conflict {conflict} do update set
  {updates};
"""


def command_emit_psql(args: argparse.Namespace) -> int:
    stage_directory = assert_external_path(Path(args.stage_dir), "staging directory")
    output = assert_external_path(Path(args.output), "psql output")
    if not stage_directory.is_dir():
        raise ValueError(f"staging directory does not exist: {stage_directory}")

    manifest_path = stage_directory / "manifest.json"
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("state") != "validated" or manifest.get("checksum_verified") is not True:
        raise ValueError("staging manifest is not checksum-validated")

    expected_files = set(STAGING_FILES)
    if set(manifest.get("files", [])) != expected_files:
        raise ValueError("staging manifest does not contain the canonical file set")
    for filename in STAGING_FILES:
        path = stage_directory / filename
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"staging file is missing or empty: {filename}")

    source_rows = list(read_ndjson(stage_directory / "sources.ndjson"))
    batch_rows = list(read_ndjson(stage_directory / "batches.ndjson"))
    if len(source_rows) != 1 or len(batch_rows) != 1:
        raise ValueError("staging must contain exactly one source and one batch row")
    source_key = source_rows[0].get("source_key")
    batch_id = batch_rows[0].get("id")
    if source_key != manifest.get("source", {}).get("key"):
        raise ValueError("source key differs from the validated manifest")
    if batch_id != manifest.get("batch_id"):
        raise ValueError("batch id differs from the validated manifest")

    loads = (
        (
            "sources.ndjson",
            "apex_food_corpus_sources_payload",
            "food_corpus_sources",
            (
                "source_key", "dataset_name", "publisher", "version", "source_url",
                "licence_id", "licence_url", "attribution", "checksum_sha256",
                "parser_version", "redistribution_scope", "ingest_status", "metadata",
            ),
            "(source_key)",
            (
                "dataset_name", "publisher", "version", "source_url", "licence_id",
                "licence_url", "attribution", "checksum_sha256", "parser_version",
                "redistribution_scope", "metadata",
            ),
            (),
        ),
        (
            "batches.ndjson",
            "apex_food_corpus_batches_payload",
            "food_corpus_batches",
            (
                "id", "source_key", "source_checksum_sha256", "parser_version", "status",
                "records_seen", "records_accepted", "records_rejected", "validation_report",
            ),
            "(id)",
            (
                "source_key", "source_checksum_sha256", "parser_version",
                "records_seen", "records_accepted", "records_rejected", "validation_report",
            ),
            (),
        ),
        (
            "records.ndjson",
            "apex_food_corpus_records_payload",
            "food_corpus_records",
            (
                "id", "source_key", "source_record_id", "batch_id", "canonical_name",
                "scientific_name", "brand", "barcode", "market", "primary_language",
                "basis_kind", "basis_amount", "basis_unit", "preparation_state",
                "edible_portion_percent", "density_g_ml", "source_priority", "source_metadata",
            ),
            "(id)",
            (
                "source_key", "source_record_id", "batch_id", "canonical_name",
                "scientific_name", "brand", "barcode", "market", "primary_language",
                "basis_kind", "basis_amount", "basis_unit", "preparation_state",
                "edible_portion_percent", "density_g_ml", "source_priority", "source_metadata",
            ),
            (),
        ),
        (
            "names.ndjson",
            "apex_food_corpus_names_payload",
            "food_corpus_names",
            ("record_id", "language", "name", "normalized_name", "name_kind", "market"),
            "(record_id, language, normalized_name, name_kind)",
            ("name", "market"),
            ("record_id", "language", "normalized_name", "name_kind"),
        ),
        (
            "nutrients.ndjson",
            "apex_food_corpus_nutrients_payload",
            "food_corpus_nutrients",
            (
                "record_id", "nutrient_code", "source_nutrient_code",
                "original_nutrient_name", "value", "unit", "original_value_text",
                "observation_status", "derivation_method", "source_reference",
            ),
            "(record_id, source_nutrient_code)",
            (
                "nutrient_code", "original_nutrient_name", "value", "unit",
                "original_value_text", "observation_status", "derivation_method",
                "source_reference",
            ),
            ("record_id", "source_nutrient_code"),
        ),
        (
            "search.ndjson",
            "apex_food_corpus_search_payload",
            "food_corpus_search",
            (
                "record_id", "source_key", "source_record_id", "name", "names_i18n",
                "aliases", "brand", "barcode", "market", "basis_kind",
                "preparation_state", "kcal", "protein_g", "carbs_g", "fat_g",
                "fibre_g", "sugar_g", "saturated_fat_g", "salt_g", "water_g",
                "source_priority", "search_text",
            ),
            "(record_id)",
            (
                "source_key", "source_record_id", "name", "names_i18n", "aliases",
                "brand", "barcode", "market", "basis_kind", "preparation_state",
                "kcal", "protein_g", "carbs_g", "fat_g", "fibre_g", "sugar_g",
                "saturated_fat_g", "salt_g", "water_g", "source_priority", "search_text",
            ),
            (),
        ),
    )

    statements = [
        "\\set ON_ERROR_STOP on",
        "\\encoding UTF8",
        "begin;",
    ]
    for filename, payload_table, destination, columns, conflict, updates, distinct in loads:
        path = stage_directory / filename
        statements.extend(
            [
                f"create temp table {payload_table} (payload jsonb) on commit drop;",
                (
                    f"\\copy {payload_table}(payload) from '{psql_copy_path(path)}' "
                    "with (format csv, delimiter E'\\x01', quote E'\\x02', "
                    "escape E'\\x02', encoding 'UTF8')"
                ),
                decoded_insert(
                    payload_table=payload_table,
                    destination_table=destination,
                    columns=columns,
                    conflict=conflict,
                    update_columns=updates,
                    distinct_on=distinct,
                ),
            ]
        )

    source_literal = str(source_key).replace("'", "''")
    batch_literal = str(batch_id).replace("'", "''")
    statements.extend(
        [
            f"""update public.food_corpus_batches
set status = 'retired', completed_at = coalesce(completed_at, now())
where source_key = '{source_literal}'
  and id <> '{batch_literal}'::uuid
  and status = 'active';""",
            f"""update public.food_corpus_batches
set status = 'active', completed_at = now()
where id = '{batch_literal}'::uuid
  and source_key = '{source_literal}';""",
            f"""update public.food_corpus_sources
set ingest_status = 'active', updated_at = now()
where source_key = '{source_literal}';""",
            "commit;",
            "notify pgrst, 'reload schema';",
        ]
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n\n".join(statements) + "\n", encoding="utf-8")
    print(output)
    return 0


def read_ndjson(path: Path) -> Iterable[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            value = json.loads(stripped)
            if not isinstance(value, dict):
                raise ValueError(f"{path.name}:{line_number} is not a JSON object")
            yield value


QUERY_LOAD_SPECS = {
    "sources.ndjson": (
        "food_corpus_sources",
        ("source_key",),
        {"ingest_status"},
    ),
    "batches.ndjson": (
        "food_corpus_batches",
        ("id",),
        {"status"},
    ),
    "records.ndjson": (
        "food_corpus_records",
        ("id",),
        set(),
    ),
    "names.ndjson": (
        "food_corpus_names",
        ("record_id", "language", "normalized_name", "name_kind"),
        set(),
    ),
    "nutrients.ndjson": (
        "food_corpus_nutrients",
        ("record_id", "source_nutrient_code"),
        set(),
    ),
    "search.ndjson": (
        "food_corpus_search",
        ("record_id",),
        set(),
    ),
}


def iter_ndjson_chunks(path: Path, max_bytes: int) -> Iterable[list[dict[str, Any]]]:
    chunk: list[dict[str, Any]] = []
    chunk_bytes = 2
    for row in read_ndjson(path):
        encoded_bytes = len(
            json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        ) + 1
        if chunk and chunk_bytes + encoded_bytes > max_bytes:
            yield chunk
            chunk = []
            chunk_bytes = 2
        chunk.append(row)
        chunk_bytes += encoded_bytes
    if chunk:
        yield chunk


def embedded_json_insert(
    rows: list[dict[str, Any]],
    destination_table: str,
    conflict_keys: tuple[str, ...],
    protected_updates: set[str],
) -> str:
    columns = tuple(rows[0].keys())
    expected_columns = set(columns)
    for row in rows:
        if set(row.keys()) != expected_columns:
            raise ValueError(f"{destination_table}: staged rows have inconsistent columns")
    payload = json.dumps(rows, ensure_ascii=False, separators=(",", ":")).replace("'", "''")
    keys = ", ".join(conflict_keys)
    selections = ",\n  ".join(f"(decoded).{column}" for column in columns)
    updates = tuple(
        column
        for column in columns
        if column not in conflict_keys and column not in protected_updates
    )
    if not updates:
        conflict_action = "do nothing"
    else:
        assignments = ",\n  ".join(
            f"{column} = excluded.{column}" for column in updates
        )
        conflict_action = f"do update set\n  {assignments}"
    distinct = ""
    order = ""
    if destination_table in {"food_corpus_names", "food_corpus_nutrients"}:
        distinct_keys = ", ".join(f"(decoded).{column}" for column in conflict_keys)
        distinct = f"distinct on ({distinct_keys}) "
        order = f"\norder by {distinct_keys}"
    return f"""insert into public.{destination_table} (
  {', '.join(columns)}
)
select {distinct}{selections}
from (
  select jsonb_populate_record(
    null::public.{destination_table},
    payload
  ) as decoded
  from jsonb_array_elements('{payload}'::jsonb) payload
) incoming{order}
on conflict ({keys}) {conflict_action};"""


def write_query_script(path: Path, statements: list[str]) -> None:
    path.write_text(
        "begin;\n\n" + "\n\n".join(statements) + "\n\ncommit;\n",
        encoding="utf-8",
    )


def command_emit_query_sql(args: argparse.Namespace) -> int:
    stage_directory = assert_external_path(Path(args.stage_dir), "staging directory")
    output_directory = assert_external_path(Path(args.output_dir), "query output directory")
    if not stage_directory.is_dir():
        raise ValueError(f"staging directory does not exist: {stage_directory}")
    max_bytes = max(4_096, int(args.max_bytes))

    manifest_path = stage_directory / "manifest.json"
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("state") != "validated" or manifest.get("checksum_verified") is not True:
        raise ValueError("staging manifest is not checksum-validated")
    if set(manifest.get("files", [])) != set(STAGING_FILES):
        raise ValueError("staging manifest does not contain the canonical file set")

    source_rows = list(read_ndjson(stage_directory / "sources.ndjson"))
    batch_rows = list(read_ndjson(stage_directory / "batches.ndjson"))
    if len(source_rows) != 1 or len(batch_rows) != 1:
        raise ValueError("staging must contain exactly one source and one batch row")
    source_key = source_rows[0].get("source_key")
    batch_id = batch_rows[0].get("id")
    if source_key != manifest.get("source", {}).get("key"):
        raise ValueError("source key differs from the validated manifest")
    if batch_id != manifest.get("batch_id"):
        raise ValueError("batch id differs from the validated manifest")

    output_directory.mkdir(parents=True, exist_ok=True)
    emitted_files: list[str] = []
    counts: dict[str, int] = {}
    prefixes = {
        "records.ndjson": "010-records",
        "names.ndjson": "020-names",
        "nutrients.ndjson": "030-nutrients",
        "search.ndjson": "040-search",
    }

    register_path = output_directory / "000-register.sql"
    register_statements = []
    for filename in ("sources.ndjson", "batches.ndjson"):
        destination, conflict_keys, protected = QUERY_LOAD_SPECS[filename]
        rows = source_rows if filename == "sources.ndjson" else batch_rows
        register_statements.append(
            embedded_json_insert(rows, destination, conflict_keys, protected)
        )
        counts[filename] = len(rows)
    write_query_script(register_path, register_statements)
    emitted_files.append(register_path.name)

    for filename in ("records.ndjson", "names.ndjson", "nutrients.ndjson", "search.ndjson"):
        destination, conflict_keys, protected = QUERY_LOAD_SPECS[filename]
        counts[filename] = 0
        for chunk_index, rows in enumerate(
            iter_ndjson_chunks(stage_directory / filename, max_bytes),
            start=1,
        ):
            counts[filename] += len(rows)
            output_path = output_directory / f"{prefixes[filename]}-{chunk_index:05d}.sql"
            write_query_script(
                output_path,
                [embedded_json_insert(rows, destination, conflict_keys, protected)],
            )
            emitted_files.append(output_path.name)

    source_literal = str(source_key).replace("'", "''")
    batch_literal = str(batch_id).replace("'", "''")
    validations = (
        ("records", counts["records.ndjson"], "public.food_corpus_records where batch_id = v_batch_id"),
        ("names", counts["names.ndjson"], "public.food_corpus_names name join public.food_corpus_records record on record.id = name.record_id where record.batch_id = v_batch_id"),
        ("nutrients", counts["nutrients.ndjson"], "public.food_corpus_nutrients nutrient join public.food_corpus_records record on record.id = nutrient.record_id where record.batch_id = v_batch_id"),
        ("search", counts["search.ndjson"], "public.food_corpus_search search join public.food_corpus_records record on record.id = search.record_id where record.batch_id = v_batch_id"),
    )
    validation_sql = []
    for label, expected, from_clause in validations:
        validation_sql.append(
            f"""select count(*) into v_actual from {from_clause};
  if v_actual <> {expected} then
    raise exception 'food corpus {label} count mismatch: expected {expected}, found %', v_actual;
  end if;"""
        )
    validation_block = "\n  ".join(validation_sql)
    activation = f"""do $$
declare
  v_batch_id uuid := '{batch_literal}'::uuid;
  v_actual bigint;
begin
  {validation_block}
end
$$;

update public.food_corpus_batches
set status = 'retired', completed_at = coalesce(completed_at, now())
where source_key = '{source_literal}'
  and id <> '{batch_literal}'::uuid
  and status = 'active';

update public.food_corpus_batches
set status = 'active', completed_at = now()
where id = '{batch_literal}'::uuid
  and source_key = '{source_literal}';

update public.food_corpus_sources
set ingest_status = 'active', updated_at = now()
where source_key = '{source_literal}';

notify pgrst, 'reload schema';"""
    activation_path = output_directory / "999-activate.sql"
    write_query_script(activation_path, [activation])
    emitted_files.append(activation_path.name)

    load_manifest = {
        "schema_version": 1,
        "source_key": source_key,
        "batch_id": batch_id,
        "counts": counts,
        "files": emitted_files,
        "state": "ready",
    }
    (output_directory / "manifest.json").write_text(
        json.dumps(load_manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(output_directory / "manifest.json")
    return 0


def remote_http_insert(
    *,
    url: str,
    checksum: str,
    rows: list[dict[str, Any]],
    destination_table: str,
    conflict_keys: tuple[str, ...],
    protected_updates: set[str],
) -> list[str]:
    columns = tuple(rows[0].keys())
    expected_columns = set(columns)
    for row in rows:
        if set(row.keys()) != expected_columns:
            raise ValueError(f"{destination_table}: staged rows have inconsistent columns")
    keys = ", ".join(conflict_keys)
    selections = ",\n  ".join(f"(decoded).{column}" for column in columns)
    updates = tuple(
        column
        for column in columns
        if column not in conflict_keys and column not in protected_updates
    )
    assignments = ",\n  ".join(
        f"{column} = excluded.{column}" for column in updates
    )
    conflict_action = f"do update set\n  {assignments}" if assignments else "do nothing"
    distinct = ""
    order = ""
    if destination_table in {"food_corpus_names", "food_corpus_nutrients"}:
        distinct_keys = ", ".join(f"(decoded).{column}" for column in conflict_keys)
        distinct = f"distinct on ({distinct_keys}) "
        order = f"\norder by {distinct_keys}"

    response_table = "apex_food_corpus_remote_response"
    url_literal = url.replace("'", "''")
    return [
        "set http.curlopt_connecttimeout_ms = 10000;",
        "set http.curlopt_timeout_ms = 60000;",
        "select extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '10000');",
        "select extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '60000');",
        (
            f"create temp table {response_table} on commit drop as "
            f"select * from extensions.http_get('{url_literal}');"
        ),
        f"""do $$
declare
  v_status integer;
  v_checksum text;
begin
  select status, encode(extensions.digest(content, 'sha256'), 'hex')
    into v_status, v_checksum
  from {response_table};
  if v_status <> 200 then
    raise exception 'food corpus transfer returned HTTP %', v_status;
  end if;
  if v_checksum <> '{checksum}' then
    raise exception 'food corpus transfer checksum mismatch';
  end if;
end
$$;""",
        f"""insert into public.{destination_table} (
  {', '.join(columns)}
)
select {distinct}{selections}
from (
  select jsonb_populate_record(
    null::public.{destination_table},
    line::jsonb
  ) as decoded
  from {response_table}
  cross join lateral regexp_split_to_table(content, E'\\n') line
  where length(line) > 0
) incoming{order}
on conflict ({keys}) {conflict_action};""",
    ]


def command_emit_remote_sql(args: argparse.Namespace) -> int:
    stage_directory = assert_external_path(Path(args.stage_dir), "staging directory")
    output_directory = assert_external_path(Path(args.output_dir), "remote SQL output directory")
    if not stage_directory.is_dir():
        raise ValueError(f"staging directory does not exist: {stage_directory}")
    base_url = str(args.base_url).strip().rstrip("/")
    if not base_url.startswith("https://"):
        raise ValueError("remote transfer base URL must use HTTPS")
    max_bytes = max(4_096, int(args.max_bytes))

    with (stage_directory / "manifest.json").open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("state") != "validated" or manifest.get("checksum_verified") is not True:
        raise ValueError("staging manifest is not checksum-validated")
    if set(manifest.get("files", [])) != set(STAGING_FILES):
        raise ValueError("staging manifest does not contain the canonical file set")

    source_rows = list(read_ndjson(stage_directory / "sources.ndjson"))
    batch_rows = list(read_ndjson(stage_directory / "batches.ndjson"))
    if len(source_rows) != 1 or len(batch_rows) != 1:
        raise ValueError("staging must contain exactly one source and one batch row")
    source_key = source_rows[0].get("source_key")
    batch_id = batch_rows[0].get("id")
    if source_key != manifest.get("source", {}).get("key") or batch_id != manifest.get("batch_id"):
        raise ValueError("staging identity differs from the validated manifest")

    compact_evidence = bool(args.compact_evidence)
    evidence_archive: dict[str, Any] | None = None
    if compact_evidence:
        evidence_directory = output_directory / "evidence"
        evidence_directory.mkdir(parents=True, exist_ok=True)
        archive_path = evidence_directory / "nutrients.ndjson.gz"
        with (stage_directory / "nutrients.ndjson").open("rb") as source_handle:
            with archive_path.open("wb") as archive_handle:
                with gzip.GzipFile(
                    filename="",
                    mode="wb",
                    fileobj=archive_handle,
                    mtime=0,
                ) as compressed_handle:
                    shutil.copyfileobj(source_handle, compressed_handle)
        evidence_rows = sum(1 for _ in read_ndjson(stage_directory / "nutrients.ndjson"))
        archive_checksum = sha256(archive_path)
        object_path = f"food-corpus-evidence/{source_key}/{batch_id}/nutrients.ndjson.gz"
        source_metadata = dict(source_rows[0].get("metadata") or {})
        source_metadata.update(
            {
                "evidence_archive": object_path,
                "evidence_archive_format": "application/x-ndjson+gzip",
                "evidence_archive_rows": evidence_rows,
                "evidence_archive_sha256": archive_checksum,
            }
        )
        source_rows[0]["metadata"] = source_metadata
        evidence_archive = {
            "file": str(archive_path.relative_to(output_directory)),
            "object_path": object_path,
            "checksum": f"sha256:{archive_checksum}",
            "rows": evidence_rows,
        }

    payload_directory = output_directory / "payload"
    payload_directory.mkdir(parents=True, exist_ok=True)
    emitted_files: list[str] = []
    transfer_files: list[dict[str, Any]] = []
    counts: dict[str, int] = {"sources.ndjson": 1, "batches.ndjson": 1}

    register_statements = []
    for filename, rows in (("sources.ndjson", source_rows), ("batches.ndjson", batch_rows)):
        destination, conflict_keys, protected = QUERY_LOAD_SPECS[filename]
        register_statements.append(
            embedded_json_insert(rows, destination, conflict_keys, protected)
        )
    register_path = output_directory / "000-register.sql"
    write_query_script(register_path, register_statements)
    emitted_files.append(register_path.name)

    prefixes = {
        "records.ndjson": "010-records",
        "names.ndjson": "020-names",
        "nutrients.ndjson": "030-nutrients",
        "search.ndjson": "040-search",
    }
    load_filenames = ["records.ndjson", "names.ndjson", "search.ndjson"]
    if not compact_evidence:
        load_filenames.insert(2, "nutrients.ndjson")
    counts["nutrients.ndjson"] = 0
    for filename in load_filenames:
        destination, conflict_keys, protected = QUERY_LOAD_SPECS[filename]
        counts[filename] = 0
        for chunk_index, rows in enumerate(
            iter_ndjson_chunks(stage_directory / filename, max_bytes),
            start=1,
        ):
            counts[filename] += len(rows)
            stem = f"{prefixes[filename]}-{chunk_index:05d}"
            payload_path = payload_directory / f"{stem}.ndjson"
            with payload_path.open("w", encoding="utf-8") as handle:
                for row in rows:
                    write_ndjson(handle, row)
            checksum = sha256(payload_path)
            url = f"{base_url}/payload/{payload_path.name}"
            sql_path = output_directory / f"{stem}.sql"
            write_query_script(
                sql_path,
                remote_http_insert(
                    url=url,
                    checksum=checksum,
                    rows=rows,
                    destination_table=destination,
                    conflict_keys=conflict_keys,
                    protected_updates=protected,
                ),
            )
            emitted_files.append(sql_path.name)
            transfer_files.append(
                {
                    "file": payload_path.name,
                    "url": url,
                    "checksum": f"sha256:{checksum}",
                    "rows": len(rows),
                }
            )

    source_literal = str(source_key).replace("'", "''")
    batch_literal = str(batch_id).replace("'", "''")
    validations = [
        ("records", counts["records.ndjson"], "public.food_corpus_records where batch_id = v_batch_id"),
        ("names", counts["names.ndjson"], "public.food_corpus_names name join public.food_corpus_records record on record.id = name.record_id where record.batch_id = v_batch_id"),
        ("search", counts["search.ndjson"], "public.food_corpus_search search join public.food_corpus_records record on record.id = search.record_id where record.batch_id = v_batch_id"),
    ]
    if not compact_evidence:
        validations.insert(
            2,
            ("nutrients", counts["nutrients.ndjson"], "public.food_corpus_nutrients nutrient join public.food_corpus_records record on record.id = nutrient.record_id where record.batch_id = v_batch_id"),
        )
    validation_sql = []
    for label, expected, from_clause in validations:
        validation_sql.append(
            f"""select count(*) into v_actual from {from_clause};
  if v_actual <> {expected} then
    raise exception 'food corpus {label} count mismatch: expected {expected}, found %', v_actual;
  end if;"""
        )
    validation_block = "\n  ".join(validation_sql)
    activation = f"""do $$
declare
  v_batch_id uuid := '{batch_literal}'::uuid;
  v_actual bigint;
begin
  {validation_block}
end
$$;

update public.food_corpus_batches
set status = 'retired', completed_at = coalesce(completed_at, now())
where source_key = '{source_literal}'
  and id <> '{batch_literal}'::uuid
  and status = 'active';

update public.food_corpus_batches
set status = 'active', completed_at = now()
where id = '{batch_literal}'::uuid
  and source_key = '{source_literal}';

update public.food_corpus_sources
set ingest_status = 'active', updated_at = now()
where source_key = '{source_literal}';

notify pgrst, 'reload schema';"""
    activation_path = output_directory / "999-activate.sql"
    write_query_script(activation_path, [activation])
    emitted_files.append(activation_path.name)

    load_manifest = {
        "schema_version": 1,
        "source_key": source_key,
        "batch_id": batch_id,
        "counts": counts,
        "files": emitted_files,
        "transfers": transfer_files,
        "evidence_archive": evidence_archive,
        "state": "ready",
    }
    (output_directory / "manifest.json").write_text(
        json.dumps(load_manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(output_directory / "manifest.json")
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

    emit_psql = commands.add_parser(
        "emit-psql",
        help="emit an atomic psql loader from one validated external staging directory",
    )
    emit_psql.add_argument("--stage-dir", required=True)
    emit_psql.add_argument("--output", required=True)
    emit_psql.set_defaults(handler=command_emit_psql)

    emit_query_sql = commands.add_parser(
        "emit-query-sql",
        help="emit bounded SQL chunks for the linked Supabase query API",
    )
    emit_query_sql.add_argument("--stage-dir", required=True)
    emit_query_sql.add_argument("--output-dir", required=True)
    emit_query_sql.add_argument("--max-bytes", type=int, default=2_000_000)
    emit_query_sql.set_defaults(handler=command_emit_query_sql)

    emit_remote_sql = commands.add_parser(
        "emit-remote-sql",
        help="emit checksum-verified HTTPS pull scripts for a temporary server transfer",
    )
    emit_remote_sql.add_argument("--stage-dir", required=True)
    emit_remote_sql.add_argument("--output-dir", required=True)
    emit_remote_sql.add_argument("--base-url", required=True)
    emit_remote_sql.add_argument("--max-bytes", type=int, default=12_000_000)
    emit_remote_sql.add_argument(
        "--compact-evidence",
        action="store_true",
        help="archive full nutrient evidence for private object storage instead of row-wise Postgres loading",
    )
    emit_remote_sql.set_defaults(handler=command_emit_remote_sql)
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
