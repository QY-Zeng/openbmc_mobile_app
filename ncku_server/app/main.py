import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routes import router
from app.core.config import settings
from app.services.alert_broker import AlertBroker
from app.services.monitoring import MonitoringService
from app.services.monitoring_store import MonitoringStore
from app.services.redfish import RedfishService
from app.services.script_jobs import ScriptJobService


@asynccontextmanager
async def lifespan(app: FastAPI):
    store = MonitoringStore(
        db_path=settings.sqlite_path,
        telemetry_retention_per_chassis=settings.telemetry_retention_per_chassis,
    )
    store.initialize()
    alert_broker = AlertBroker()
    script_job_service = ScriptJobService(
        store=store,
        jobs_dir=settings.script_jobs_dir,
        timeout_seconds=settings.script_job_timeout_seconds,
        max_source_bytes=settings.script_job_max_source_bytes,
        max_output_bytes=settings.script_job_max_output_bytes,
    )

    monitor = MonitoringService(
        redfish_service=RedfishService(
            base_url=settings.redfish_base_url,
            timeout_seconds=settings.redfish_timeout_seconds,
        ),
        store=store,
        alert_broker=alert_broker,
        poll_interval_seconds=settings.monitoring_poll_interval_seconds,
    )
    task = asyncio.create_task(monitor.run_forever())

    app.state.monitoring_store = store
    app.state.monitoring_service = monitor
    app.state.alert_broker = alert_broker
    app.state.script_job_service = script_job_service
    app.state.monitoring_task = task

    from app.services.telemetry_override import TelemetryOverrideStore # NEW ADD
    app.state.telemetry_override_store = TelemetryOverrideStore()      # NEW ADD





    try:
        yield
    finally:
        monitor.stop()
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        await script_job_service.shutdown()

app = FastAPI(
    title="NCKU Redfish Server",
    version="0.1.0",
    description="Middleware server for Flutter and OpenBMC Redfish integration.",
    lifespan=lifespan,
)

app.include_router(router)
