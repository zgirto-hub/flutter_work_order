"""
Train the AI assistant by bulk-loading verified Q&A pairs with paraphrase variants.

Usage:
    cd backend
    python train_ai.py                          # Process all entries in training_data.json
    python train_ai.py --file my_data.json      # Use a custom data file
    python train_ai.py --dry-run                # Preview without saving

Each entry in the JSON file should have:
    {
        "question": "The original question text",
        "answer": "The verified answer to store"
    }

For each entry the script will:
    1. Create a verified answer in validated_qa (with embedding)
    2. Generate 4 paraphrase variants via the AI provider
    3. Save each variant as an additional validated_qa row (retro_expand)

This means each Q&A pair gets ~5 embeddings in the cache, so the AI can
match questions asked in different ways.
"""

import asyncio
import json
import sys
import os
import argparse
import logging

# Add backend to path so imports work when running from backend/
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dotenv import load_dotenv
load_dotenv()

from db import supabase
from services.ollama_embedder import embed_single
from services.ai_providers.resolver import generate as provider_generate
from prompts.paraphrase_prompt import PARAPHRASE_PROMPT_TEMPLATE, parse_paraphrase_output
import services.validated_qa_service as vqa_service

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "zgirto@gmail.com")


async def generate_paraphrases(question: str) -> list[str]:
    """Generate paraphrase variants for a question using the AI provider."""
    prompt = PARAPHRASE_PROMPT_TEMPLATE.format(q=question)
    raw = await provider_generate(prompt, timeout=30.0)
    variants = parse_paraphrase_output(raw, question)
    return variants


async def check_duplicate(question: str) -> bool:
    """Check if a very similar question already exists in validated_qa."""
    try:
        embedding = await embed_single(question)
        embedding_str = "[" + ",".join(str(x) for x in embedding) + "]"
        result = supabase.rpc(
            "search_validated_qa",
            {"q_embedding": embedding_str, "match_count": 1},
        ).execute()
        if result.data and len(result.data) > 0:
            distance = result.data[0].get("distance", 1.0)
            similarity = 1.0 - distance
            if similarity >= 0.90:
                logger.warning(
                    "  SKIP (duplicate, similarity=%.2f): existing Q = '%s'",
                    similarity,
                    result.data[0].get("question_text", "")[:80],
                )
                return True
    except Exception as e:
        logger.warning("  Duplicate check failed (continuing): %s", e)
    return False


async def train_entry(entry: dict, dry_run: bool = False) -> dict:
    """Process a single training entry: create verified answer + paraphrases."""
    question = entry["question"].strip()
    answer = entry["answer"].strip()

    logger.info("Processing: '%s'", question[:80])

    # Step 1: Check for duplicates
    if await check_duplicate(question):
        return {"question": question, "status": "skipped", "reason": "duplicate"}

    if dry_run:
        # Just generate paraphrases to show what would happen
        variants = await generate_paraphrases(question)
        logger.info("  [DRY RUN] Would create 1 original + %d variants", len(variants))
        for i, v in enumerate(variants, 1):
            logger.info("    Variant %d: %s", i, v)
        return {
            "question": question,
            "status": "dry_run",
            "variants": variants,
        }

    # Step 2: Create the primary verified answer
    logger.info("  Creating verified answer...")
    primary = await vqa_service.create_verified_answer(question, answer, ADMIN_EMAIL)
    primary_id = primary["id"]
    logger.info("  Created primary entry: %s", primary_id)

    # Step 3: Generate paraphrase variants
    logger.info("  Generating paraphrases...")
    variants = await generate_paraphrases(question)
    logger.info("  Got %d paraphrase variants", len(variants))

    # Step 4: Save variants via retro_expand
    variant_count = 0
    if variants:
        logger.info("  Saving variants via retro_expand...")
        result = await vqa_service._retro_expand_multi(
            existing_validated_qa_id=primary_id,
            reviewer_email=ADMIN_EMAIL,
            variant_texts=variants,
        )
        variant_count = result["inserted_count"]
        logger.info("  Saved %d variant(s)", variant_count)

    return {
        "question": question,
        "status": "created",
        "primary_id": primary_id,
        "variant_count": variant_count,
        "variants": variants,
    }


async def main():
    parser = argparse.ArgumentParser(description="Train AI with verified Q&A pairs")
    parser.add_argument(
        "--file",
        default="training_data.json",
        help="Path to training data JSON file (default: training_data.json)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview paraphrases without saving to database",
    )
    args = parser.parse_args()

    # Load training data
    data_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.file)
    if not os.path.exists(data_path):
        logger.error("Training data file not found: %s", data_path)
        sys.exit(1)

    with open(data_path, "r", encoding="utf-8") as f:
        entries = json.load(f)

    logger.info("=" * 60)
    logger.info("AI Training Script")
    logger.info("=" * 60)
    logger.info("Data file: %s", data_path)
    logger.info("Entries to process: %d", len(entries))
    logger.info("Mode: %s", "DRY RUN" if args.dry_run else "LIVE")
    logger.info("Admin email: %s", ADMIN_EMAIL)
    logger.info("=" * 60)

    results = {"created": 0, "skipped": 0, "failed": 0, "dry_run": 0}
    details = []

    for i, entry in enumerate(entries, 1):
        logger.info("\n[%d/%d] Processing entry...", i, len(entries))
        try:
            result = await train_entry(entry, dry_run=args.dry_run)
            results[result["status"]] = results.get(result["status"], 0) + 1
            details.append(result)
        except Exception as e:
            logger.error("  FAILED: %s", e)
            results["failed"] += 1
            details.append({
                "question": entry.get("question", "?")[:80],
                "status": "failed",
                "error": str(e),
            })

    # Summary
    logger.info("\n" + "=" * 60)
    logger.info("TRAINING COMPLETE")
    logger.info("=" * 60)
    logger.info("Created: %d", results["created"])
    logger.info("Skipped (duplicate): %d", results["skipped"])
    logger.info("Failed: %d", results["failed"])
    if args.dry_run:
        logger.info("Dry-run previewed: %d", results["dry_run"])

    total_variants = sum(
        d.get("variant_count", 0) for d in details if d["status"] == "created"
    )
    total_embeddings = results["created"] + total_variants
    logger.info("Total new embeddings: %d (originals) + %d (variants) = %d",
                results["created"], total_variants, total_embeddings)
    logger.info("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
