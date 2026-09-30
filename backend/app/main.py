import asyncio
import hmac
import json
import logging
import time
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime

import httpx
from fastapi import FastAPI, Query, Request, Response
from pydantic import ValidationError

from app.adapters.calendar_ics import IcsCalendarAdapter
from app.adapters.weather_openmeteo import OpenMeteoAdapter
from app.config import Settings
from app.snapshot import SnapshotStore

access_log = logging.getLogger("dashboard.access")
JSON_TYPE = "application/json; charset=utf-8"


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        d = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname, "logger": record.name, "msg": record.getMessage(),
        }
        d.update(getattr(record, "fields", {}))
        return json.dumps(d, ensure_ascii=False)


def setup_logging() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.INFO)
    # httpx/httpcore registran la URL completa de cada petición, y las URLs ICS son secretas
    for name in ("httpx", "httpcore"):
        logging.getLogger(name).setLevel(logging.WARNING)


def load_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as e:
        lines = [f"  DASH_{'.'.join(map(str, err['loc'])).upper()}: {err['msg']}" for err in e.errors()]
        raise SystemExit("Configuración inválida (revisa las variables DASH_*):\n" + "\n".join(lines))


def _json(status: int, body: dict, headers: dict | None = None) -> Response:
    content = json.dumps(body, separators=(",", ":")).encode()
    return Response(content, status_code=status, media_type=JSON_TYPE, headers=headers)


def create_app(settings: Settings | None = None, store: SnapshotStore | None = None) -> FastAPI:
    """`store` inyectado (tests) desactiva los refreshers en segundo plano."""
    settings = settings or load_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if store is not None:
            yield
            return
        async with httpx.AsyncClient() as client:
            app.state.store = SnapshotStore(
                settings,
                OpenMeteoAdapter(settings, client),
                IcsCalendarAdapter(settings.ics_url_list, settings.zone, client),
            )
            task = asyncio.create_task(app.state.store.run_refreshers())
            try:
                yield
            finally:
                task.cancel()

    app = FastAPI(title="KOReader Dashboard BFF", version="1.0.0", lifespan=lifespan)
    app.state.settings = settings
    app.state.store = store
    token = settings.token.encode()

    @app.middleware("http")
    async def access_logging(request: Request, call_next):
        t0 = time.perf_counter()
        rid = uuid.uuid4().hex[:8]
        response = await call_next(request)
        access_log.info("request", extra={"fields": {
            "request_id": rid, "method": request.method, "path": request.url.path,
            "status": response.status_code,
            "latency_ms": round((time.perf_counter() - t0) * 1000, 2),
            "etag_hit": response.status_code == 304,
        }})
        return response

    @app.get("/api/dashboard")
    async def dashboard(request: Request, max_events: int | None = Query(None, ge=1, le=8)):
        auth = request.headers.get("authorization", "")
        scheme, _, given = auth.partition(" ")
        if scheme.lower() != "bearer" or not hmac.compare_digest(given.strip().encode(), token):
            return _json(401, {"error": "unauthorized"})
        n = min(max_events or settings.max_events, settings.max_events)
        snap = app.state.store.get(n) if app.state.store else None
        if snap is None:
            return _json(503, {"error": "no_snapshot"}, {"Retry-After": "30"})
        body, etag = snap
        inm = [t.strip() for t in request.headers.get("if-none-match", "").split(",")]
        if etag in inm:
            return Response(status_code=304, headers={"ETag": etag})
        return Response(body, media_type=JSON_TYPE, headers={"ETag": etag})

    @app.get("/healthz")
    async def healthz():
        st = app.state.store
        if st is None:
            return {"status": "degraded", "weather_age_s": None, "calendar_age_s": None}
        w, c = st.ages()
        return {"status": "degraded" if st.degraded() else "ok", "weather_age_s": w, "calendar_age_s": c}

    return app


setup_logging()
app = create_app()  # `uvicorn app.main:app`
