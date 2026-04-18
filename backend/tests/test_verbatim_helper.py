import pytest
from services.manual_rag_service import _should_return_verbatim


@pytest.mark.parametrize(
    "matches,expected",
    [
        ([], False),
        ([{"similarity": 0.80, "validated_answer": "a"}], False),
        ([{"similarity": 0.85, "validated_answer": "a"}], True),
        (
            [{"similarity": 0.90, "validated_answer": "a"}, {"similarity": 0.87, "validated_answer": "b"}],
            False,
        ),
        (
            [{"similarity": 0.92, "validated_answer": "a"}, {"similarity": 0.85, "validated_answer": "b"}],
            True,
        ),
        (
            [{"similarity": 0.80, "validated_answer": "a"}, {"similarity": 0.70, "validated_answer": "b"}],
            False,
        ),
    ],
    ids=["empty", "single_below_floor", "single_at_floor", "multi_gap_too_small", "multi_dominant", "multi_top1_below_floor"],
)
def test_should_return_verbatim(matches, expected):
    assert _should_return_verbatim(matches) is expected