# Quickstart — Manual Verification

After implementing the tasks in `tasks.md`, verify the fix end-to-end against each Spec acceptance scenario.

## Setup

1. Apply the new migration to Supabase: `20260407_letter_header_formatting.sql`.
2. Restart the FastAPI backend so the updated `letters_v2.py` is loaded.
3. Run the Flutter frontend (`flutter run -d chrome` or use the deployed PWA).

## Scenario 1 — Reference Number bold + size 16

1. Open the letter generator and create a new letter.
2. In the Reference Number row, set font size to **16** and toggle **Bold** on.
3. Fill the other required fields with any text.
4. Save the letter.
5. Close the letter editor and reopen the same letter from the letters list.
6. **Expect**: Reference Number text is shown bold at font size 16.

## Scenario 2 — Subject underlined

1. Create a new letter; in the Subject row enable **Underline** (turn off bold so the change is visible).
2. Save → reopen.
3. **Expect**: Subject text is underlined; bold is off.

## Scenario 3 — Recipient bold + underlined + size 14

1. Create a new letter; on the Recipient row set size 14, bold on, underline on.
2. Save → reopen.
3. **Expect**: All three attributes restored together.

## Scenario 4 — Edit body, formatting preserved

1. Reopen any of the letters above.
2. Change only the body text.
3. Save again.
4. Reopen once more.
5. **Expect**: header field formatting unchanged from before this edit.

## Date field (new control)

1. Create a new letter; in the Date row use the new font-size / bold / underline controls (e.g., size 14, bold).
2. Save → reopen.
3. **Expect**: Date row reflects the chosen formatting.

## Edge cases

### Legacy letter (no formatting columns)

1. Pick a letter that was created **before** the migration was applied (it should still exist after the migration since columns are nullable).
2. Open it.
3. **Expect**: loads without error; header fields show the documented default styling (Subject bold + underlined, others plain). No console errors, no missing-key exceptions.

### PDF export reflects formatting

1. Reopen a letter from Scenario 3 and trigger the PDF export / regenerate path.
2. **Expect**: the produced PDF shows the same formatting on Reference Number, Date, Recipient, and Subject as the editor shows — not the hardcoded defaults.

### Cleared formatting persists

1. Reopen a bold-Subject letter, turn Bold off, save.
2. Reopen.
3. **Expect**: Subject is no longer bold (the cleared state persisted, not the previously-bold state).

## Pass criteria

All scenarios above behave as described, and no error is logged in the browser console or backend logs.
