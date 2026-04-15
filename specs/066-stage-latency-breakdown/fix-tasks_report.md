## Fix Implementation Report

### F6.1 pytest output

```
pytest: ModuleNotFoundError: No module named 'fitz'
Test env broken - cannot run endpoint tests
Direct Python tests: PASS
```

Direct verification (bypassing fitz import):
```
Test 1: all 7 keys - PASS
Test 2: None on exception - PASS
Test 3: records time on success - PASS  
Test 4: greeting bypass total elapsed - PASS
Test 5: generator_ms in ms not seconds - PASS
All direct tests passed!
```

### F6.2 / F6.3 live samples

Unable to start dev environment in CLI session - no live /manuals/ask samples available.

### F6.4 grep output

```
backend/services/ai_providers/resolver.py:6: from utils.activity import log_activity
backend/services/validated_qa_service.py:8: from utils.activity import log_activity
backend/services/validated_qa_service.py:192: log_activity(
backend/services/validated_qa_service.py:256: log_activity(
```

No new user_activity_log/log_activity calls added for latency - the existing ones are pre-existing (validated_qa unrelated).

### F6.5 backend diff summary

**Files changed:**
- `backend/routers/manuals.py`: +~40 lines (F2.1, F2.2, F3.1-3.4 wiring fixes)
- `backend/services/agentic_tools.py`: +~25 lines (F1.1, F1.2, F1.3, F1.4 timing parameter + transfer)
- `backend/services/manual_rag_service.py`: +~8 lines (F1.5 added latency_breakdown parameter)
- `backend/tests/test_manual_rag_latency.py`: rewritten

**Key fixes:**
1. Router creates breakdown dict BEFORE calling service (not synthesized after)
2. Breakdown passed via `latency_breakdown=` kwarg into run_agentic_loop
3. F2.2: `total_ms = round((time.perf_counter() - _req_start) * 1000)` (elapsed, not raw)
4. F3: No more synthesizing with wrong units
5. F1: Timing dict transferred to response at end of run_agentic_loop

### Deviations / Open Questions

1. **Test environment issue**: pytest fails due to missing `fitz` module - verified logic directly via Python. This is a pre-existing environment issue, not a code bug.

2. **F5 endpoint tests**: Cannot run full FastAPI endpoint tests without starting backend. Core timing logic verified via direct Python.

3. **Manual verification recommended**: Live backend test should verify:
   - POST `/manuals/ask` with normal question returns breakdown with millisecond integers
   - POST `/manuals/ask` with question="hi" returns bypass path with total_ms < 50

### Status

Fixes applied per F1-F4. Core timing logic verified. Ready for re-review.