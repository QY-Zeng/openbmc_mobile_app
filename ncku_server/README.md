# NCKU Redfish Server

Minimal FastAPI scaffold for the middleware server.

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

The backend now defaults to the official Redfish Interface Emulator at
`http://127.0.0.1:5001`.

If your Redfish backend is running elsewhere, set:

```bash
export REDFISH_BASE_URL=http://127.0.0.1:5001
```

The monitoring worker now runs inside FastAPI itself. It polls Redfish on a
timer, stores telemetry snapshots in SQLite, and opens/resolves alerts based on
temperature, fan, and power health. Temperature alerts also include a hard
critical safeguard at `80 C`, even if user-editable thresholds are set higher.

Useful environment variables:

```bash
export SQLITE_PATH=data/monitoring.sqlite3
export MONITORING_POLL_INTERVAL_SECONDS=30
export TELEMETRY_RETENTION_PER_CHASSIS=720
export WEBSOCKET_TELEMETRY_INTERVAL_SECONDS=2
export SCRIPT_JOBS_DIR=/tmp/openbmc_redfish_demo/script_jobs
export SCRIPT_JOB_TIMEOUT_SECONDS=20
export SCRIPT_JOB_MAX_SOURCE_BYTES=200000
export SCRIPT_JOB_MAX_OUTPUT_BYTES=40000
```

## Python Runner

FastAPI also includes a lightweight background Python job runner for trusted
demo scripts. Submit Python source plus optional JSON input, then poll the job
status until it completes. Scripts receive JSON on `stdin`, and the same payload
is written to `JOB_INPUT_PATH`. If the script writes JSON to `JOB_OUTPUT_PATH`,
that structured result is returned to Flutter. Job metadata and results are
persisted in the same SQLite database as monitoring data, so submitted jobs can
still be queried after FastAPI reloads or restarts.

The default script job workspace lives under `/tmp/openbmc_redfish_demo` so
`uvicorn --reload` does not restart the API every time a submitted script is
written to disk.

## Redfish Emulator

Use the project wrapper scripts to run the official DMTF Redfish Interface Emulator:

```bash
./scripts/setup_redfish_emulator.sh
./scripts/run_redfish_emulator.sh dynamic-populate
```

Available modes:

- `static`: emulator-backed replacement for the old mockup server
- `dynamic-populate`: start the emulator in dynamic mode with the sample populate config
- `dynamic-empty`: start the emulator in dynamic mode without pre-populated systems

The emulator still does not auto-generate time-varying telemetry by itself. It
does support dynamic resources and PATCH/POST/DELETE for the resources that
have API implementations, which is the right base for adding your own changing
sensor values later.

To run the local telemetry simulator against the emulator:

```bash
./scripts/run_telemetry_simulator.sh
```

By default, the simulator patches every chassis under `/redfish/v1/Chassis`
and gives each chassis a different telemetry curve.

If you point the simulator at a static/mock backend, it will fail with `405`.
Use `dynamic-populate` for changing temperature, fan, and power values.

## Endpoints

- `GET /`
- `GET /health`
- `GET /api/systems`
- `GET /api/systems/{system_id}`
- `POST /api/systems/{system_id}/power/reset`
- `GET /api/chassis`
- `GET /api/chassis/{chassis_id}`
- `GET /api/chassis/{chassis_id}/telemetry/current`
- `GET /api/chassis/{chassis_id}/telemetry/history`
- `PATCH /api/chassis/{chassis_id}/temperatures/{temperature_id}/thresholds`
- `PATCH /api/chassis/{chassis_id}/temperatures/{temperature_id}/warning-threshold`
- `GET /api/alerts`
- `POST /api/python-jobs`
- `GET /api/python-jobs`
- `GET /api/python-jobs/{job_id}`
- `WS /ws/chassis/{chassis_id}/telemetry`
- `WS /ws/alerts`
