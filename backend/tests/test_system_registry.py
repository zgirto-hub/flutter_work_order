from services.system_registry import SYSTEM_ALIASES, detect_system


def test_detect_system_cadas_ats_hyphenated():
    assert detect_system("CADAS-ATS backup") == "CADAS-ATS"


def test_detect_system_cadas_ats_space_variant_case_insensitive():
    assert detect_system("cadas ats backup") == "CADAS-ATS"


def test_detect_system_cadas_ims_does_not_match_cadas_ats():
    assert detect_system("CADAS-IMS restart") == "CADAS-IMS"


def test_detect_system_aida_ng_case_insensitive():
    assert detect_system("how to restart aida-ng?") == "AIDA-NG"


def test_detect_system_returns_none_for_general_question():
    assert detect_system("general question") is None


def test_detect_system_returns_none_for_bare_ambiguous_token():
    assert detect_system("CADAS backup procedure") is None


def test_alias_registry_has_no_long_prefix_aliases():
    alias_keys = set(SYSTEM_ALIASES)

    for alias in alias_keys:
        for prefix_length in range(4, len(alias)):
            assert alias[:prefix_length] not in alias_keys


def test_word_boundary_regression_partial_attachment():
    assert detect_system("CADAS-ATSxyz") is None
    assert detect_system("MYCADAS-ATS") is None
    assert detect_system("CADAS-ATSFOO") is None


def test_word_boundary_regression_adjacent_punctuation():
    assert detect_system("(CADAS-ATS)") == "CADAS-ATS"
    assert detect_system("CADAS-ATS.") == "CADAS-ATS"
    assert detect_system("CADAS-ATS,") == "CADAS-ATS"


# Follow-up detection: detect_system itself remains pure (operates on one string).
# The follow-up-via-rewrite behavior is wired in manual_rag_service.ask(), which
# re-runs detect_system on the history-aware rewritten query when the original
# had no system keyword. These tests document the contract detect_system
# provides to that caller: it must correctly identify the system when given
# either the bare follow-up or the rewritten-with-context form.
def test_follow_up_bare_question_has_no_match():
    # A bare follow-up like "any other steps?" has no system name on its own.
    assert detect_system("is there any other steps?") is None
    assert detect_system("what about restore?") is None


def test_follow_up_after_query_rewrite_matches():
    # The query rewriter (spec 042) turns "any other steps?" (with history about
    # CADAS-ATS) into a standalone query like the examples below. detect_system
    # must pick up the system name from the rewritten form.
    assert detect_system("are there other steps to restore the CADAS-ATS database?") == "CADAS-ATS"
    assert detect_system("what about restoring CADAS-ATS?") == "CADAS-ATS"
