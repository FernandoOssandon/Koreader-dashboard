import asyncio
import socket
import statistics
import threading
import time

import httpx
import uvicorn
from helpers import make_cal, make_store, vevent

from app.main import create_app


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def test_p95_under_50ms_against_real_uvicorn():
    body = "".join(vevent(f"e{i}", f"20260923T{10 + i}0000", f"20260923T{10 + i}3000", f"Evento {i}") for i in range(8))
    store, _, _, _, settings = make_store([make_cal(body)])
    await store.refresh_weather()
    await store.refresh_calendar()

    port = _free_port()
    server = uvicorn.Server(uvicorn.Config(create_app(settings, store), port=port, log_level="error", access_log=False))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    try:
        deadline = time.time() + 10
        while not server.started and time.time() < deadline:
            await asyncio.sleep(0.05)
        assert server.started
        headers = {"Authorization": "Bearer test-token"}
        times = []
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", headers=headers) as c:
            for _ in range(200):
                t = time.perf_counter()
                assert c.get("/api/dashboard").status_code == 200
                times.append((time.perf_counter() - t) * 1000)
        p95 = statistics.quantiles(times, n=20)[-1]
        assert p95 < 50, f"p95={p95:.1f} ms"
    finally:
        server.should_exit = True
        thread.join(5)
