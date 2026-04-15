"""
Test-suite bootstrap.

Some backend modules (e.g. `services/manual_parser.py`) import `fitz` at
top-level for PDF parsing. `fitz` is only available when PyMuPDF is
installed and can be absent in CI / minimal dev environments. We stub it
with an empty module so imports succeed — tests that actually need PDF
parsing are out of scope for this suite and would mock `fitz.open` anyway.

Also registers pytest-asyncio's auto mode so plain `async def test_...`
functions run without an explicit `@pytest.mark.asyncio` decorator.
"""

import sys
import types

# Stub heavy / optional C-extension dependencies that some backend modules
# import at top level. Tests that actually need these behaviors would mock
# specific call sites — here we only ensure `import` succeeds so the
# target-under-test can be loaded at all. Without this shim the whole test
# suite collects zero items in minimal environments.
_STUB_MODULES = {
    "fitz": {},
    "docx": {"Document": object},
    "PyPDF2": {"PdfReader": object},
    "pytesseract": {"image_to_string": lambda *a, **k: ""},
    "pdf2image": {"convert_from_bytes": lambda *a, **k: []},
    "PIL": {},
    "PIL.Image": {"open": lambda *a, **k: None},
    "arabic_reshaper": {"reshape": lambda x: x},
    "bidi": {},
    "bidi.algorithm": {"get_display": lambda x: x},
    "reportlab": {},
    "reportlab.lib": {},
    "reportlab.lib.colors": {},
    "reportlab.lib.pagesizes": {},
    "reportlab.lib.styles": {},
    "reportlab.lib.units": {},
    "reportlab.pdfbase": {},
    "reportlab.pdfbase.pdfmetrics": {},
    "reportlab.pdfbase.ttfonts": {},
    "reportlab.pdfgen": {},
    "reportlab.platypus": {},
}

for _name, _attrs in _STUB_MODULES.items():
    if _name not in sys.modules:
        mod = types.ModuleType(_name)
        for _k, _v in _attrs.items():
            setattr(mod, _k, _v)
        sys.modules[_name] = mod


# Pre-register the `routers` package as an empty namespace so that
# importing `routers.manuals` directly does NOT trigger `routers/__init__.py`,
# which eagerly imports every sibling router and their heavy deps.
def _preregister_routers_package():
    import importlib
    from pathlib import Path

    if "routers" in sys.modules and getattr(sys.modules["routers"], "__file__", None):
        return  # Real __init__ already loaded — leave it.

    routers_dir = Path(__file__).resolve().parent.parent / "routers"
    if not routers_dir.is_dir():
        return

    pkg = types.ModuleType("routers")
    pkg.__path__ = [str(routers_dir)]  # makes it importable as a package
    sys.modules["routers"] = pkg


_preregister_routers_package()


def pytest_collection_modifyitems(config, items):
    import pytest

    for item in items:
        if "asyncio" in item.keywords:
            continue
        if _is_async(item):
            item.add_marker(pytest.mark.asyncio)


def _is_async(item):
    import inspect

    func = getattr(item, "function", None)
    return func is not None and inspect.iscoroutinefunction(func)
