"""One-shot backfill: populate validated_qa.manual_ids where it's empty.

Background (2026-04-20): the topic filter in services.validated_qa_service.
check_validated_match keys off `manual_ids`. Almost every row in production
has `manual_ids = []` because prior creation paths only set the field when
the rating originated from a manual-scoped query. This script uses the new
_derive_manual_ids helper (detect_system -> get_manual_ids_for_system) to
populate the field from each row's question_text.

Idempotent — skips rows that already have a non-empty manual_ids. Safe to
re-run.

Usage (from backend/ directory on the server):
    python -m scripts.backfill_validated_qa_manual_ids           # dry-run
    python -m scripts.backfill_validated_qa_manual_ids --apply   # perform updates
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys

from db import supabase
from services.validated_qa_service import _derive_manual_ids

logger = logging.getLogger("backfill_validated_qa_manual_ids")


async def _run(apply_changes: bool) -> int:
    # Pull only the rows we might touch. `manual_ids` is a jsonb array in the
    # schema; `is.null` catches NULLs and `eq.[]` catches empty arrays.
    resp = (
        supabase.table("validated_qa")
        .select("id, question_text, manual_ids")
        .execute()
    )
    rows = resp.data or []
    logger.info("fetched %d validated_qa rows", len(rows))

    to_update: list[tuple[str, str, list[str]]] = []
    skipped = 0
    untaggable = 0

    for row in rows:
        existing = row.get("manual_ids") or []
        if existing:
            skipped += 1
            continue
        derived = await _derive_manual_ids(row.get("question_text") or "")
        if not derived:
            untaggable += 1
            logger.info(
                "untaggable id=%s q=%r (no system detected or no manuals)",
                row["id"], (row.get("question_text") or "")[:60],
            )
            continue
        to_update.append((row["id"], row.get("question_text") or "", derived))

    logger.info(
        "plan: %d to update, %d already tagged, %d untaggable, %d total",
        len(to_update), skipped, untaggable, len(rows),
    )

    if not apply_changes:
        logger.info("dry-run — no writes. Pass --apply to perform updates.")
        for row_id, q, ids in to_update[:10]:
            logger.info("  would update id=%s q=%r -> manual_ids=%s", row_id, q[:60], ids)
        if len(to_update) > 10:
            logger.info("  ... +%d more", len(to_update) - 10)
        return 0

    updated = 0
    failed = 0
    for row_id, q, ids in to_update:
        try:
            supabase.table("validated_qa").update({"manual_ids": ids}).eq(
                "id", row_id
            ).execute()
            updated += 1
        except Exception as e:
            failed += 1
            logger.warning("failed id=%s: %s", row_id, e)

    logger.info("done: updated=%d failed=%d", updated, failed)
    return 0 if failed == 0 else 1


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="perform updates (default: dry-run)"
    )
    args = parser.parse_args()
    return asyncio.run(_run(apply_changes=args.apply))


if __name__ == "__main__":
    sys.exit(main())
