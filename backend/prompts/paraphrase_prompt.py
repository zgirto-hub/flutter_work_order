PARAPHRASE_PROMPT_TEMPLATE = """Generate exactly 4 alternative phrasings of the following technical question. Keep the same meaning and language. Do not add explanations. Return one phrasing per line, no numbering, no bullets.

Question: {q}
"""


def parse_paraphrase_output(raw: str, original_question: str) -> list[str]:
    """Parse the raw output from the paraphrase generator.

    Rules:
    1. Split on newline
    2. Strip each line
    3. Drop empty lines
    4. Drop lines that start with a digit+delimiter (e.g., "1.", "2)", "3 -")
    5. Drop lines that start with a bullet (e.g., "-", "*")
    6. Drop lines that are case-insensitive matches to the original question
       after whitespace normalization
    7. Cap at 5 variants
    """
    normalized_original = " ".join(original_question.lower().split())

    lines = raw.split("\n")
    variants = []

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        stripped_lower = stripped.lower()

        if stripped_lower[0].isdigit() and len(stripped) > 1 and stripped[1] in ". )-":
            continue
        if stripped_lower.startswith("-") or stripped_lower.startswith("*"):
            continue

        normalized_candidate = " ".join(stripped_lower.split())
        if normalized_candidate == normalized_original:
            continue

        variants.append(stripped)

    return variants[:5]
