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
