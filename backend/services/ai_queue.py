import asyncio
from dataclasses import dataclass, field
from typing import Any, Callable

PRIORITY_HIGH = 1
PRIORITY_LOW = 2

_queue: asyncio.PriorityQueue = asyncio.PriorityQueue()
_seq = 0
_initialized = False


@dataclass(order=True)
class AIJob:
    priority: int
    seq: int
    func: Callable = field(compare=False)
    args: tuple = field(compare=False)
    kwargs: dict = field(compare=False)
    future: asyncio.Future | None = field(default=None, compare=False)


def is_initialized() -> bool:
    return _initialized


def initialize() -> None:
    global _initialized
    _initialized = True


def shutdown() -> None:
    global _initialized
    _initialized = False


async def submit(
    func: Callable,
    *args,
    priority: int = PRIORITY_HIGH,
    fire_and_forget: bool = False,
    **kwargs,
) -> Any:
    global _seq
    _seq += 1
    job = AIJob(
        priority=priority,
        seq=_seq,
        func=func,
        args=args,
        kwargs=kwargs,
    )

    if fire_and_forget:
        await _queue.put(job)
        return None

    loop = asyncio.get_event_loop()
    job.future = loop.create_future()
    await _queue.put(job)
    return await job.future


async def worker() -> None:
    while True:
        job = await _queue.get()
        try:
            print(f"[ai_queue] Starting job seq={job.seq} priority={job.priority}")
            result = await job.func(*job.args, **job.kwargs)
            if job.future is not None:
                job.future.set_result(result)
            print(f"[ai_queue] Completed job seq={job.seq}")
        except Exception as e:
            print(f"[ai_queue] Error in job seq={job.seq}: {e}")
            if job.future is not None:
                job.future.set_exception(e)
        finally:
            _queue.task_done()
