import os
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class Settings:
    redfish_base_url: str
    redfish_timeout_seconds: float
    sqlite_path: str
    monitoring_poll_interval_seconds: float
    telemetry_retention_per_chassis: int
    websocket_telemetry_interval_seconds: float
    script_jobs_dir: str
    script_job_timeout_seconds: float
    script_job_max_source_bytes: int
    script_job_max_output_bytes: int


def _default_script_jobs_dir() -> str:
    return str(Path(tempfile.gettempdir()) / "openbmc_redfish_demo" / "script_jobs")


def _resolve_runtime_jobs_dir(raw_value: str) -> str:
    path = Path(raw_value)
    if path.is_absolute():
        return str(path)
    return str(Path(tempfile.gettempdir()) / "openbmc_redfish_demo" / path)


def get_settings() -> Settings:
    base_url = os.getenv("REDFISH_BASE_URL", "http://127.0.0.1:5001").rstrip("/")
    timeout_seconds = float(os.getenv("REDFISH_TIMEOUT_SECONDS", "10"))
    sqlite_path = os.getenv("SQLITE_PATH", "data/monitoring.sqlite3")
    monitoring_poll_interval_seconds = float(
        os.getenv("MONITORING_POLL_INTERVAL_SECONDS", "30")
    )
    telemetry_retention_per_chassis = int(
        os.getenv("TELEMETRY_RETENTION_PER_CHASSIS", "720")
    )
    websocket_telemetry_interval_seconds = float(
        os.getenv("WEBSOCKET_TELEMETRY_INTERVAL_SECONDS", "2")
    )
    script_jobs_dir = _resolve_runtime_jobs_dir(
        os.getenv("SCRIPT_JOBS_DIR", _default_script_jobs_dir())
    )
    script_job_timeout_seconds = float(
        os.getenv("SCRIPT_JOB_TIMEOUT_SECONDS", "20")
    )
    script_job_max_source_bytes = int(
        os.getenv("SCRIPT_JOB_MAX_SOURCE_BYTES", "200000")
    )
    script_job_max_output_bytes = int(
        os.getenv("SCRIPT_JOB_MAX_OUTPUT_BYTES", "40000")
    )
    return Settings(
        redfish_base_url=base_url,
        redfish_timeout_seconds=timeout_seconds,
        sqlite_path=sqlite_path,
        monitoring_poll_interval_seconds=monitoring_poll_interval_seconds,
        telemetry_retention_per_chassis=telemetry_retention_per_chassis,
        websocket_telemetry_interval_seconds=websocket_telemetry_interval_seconds,
        script_jobs_dir=script_jobs_dir,
        script_job_timeout_seconds=script_job_timeout_seconds,
        script_job_max_source_bytes=script_job_max_source_bytes,
        script_job_max_output_bytes=script_job_max_output_bytes,
    )


settings = get_settings()
