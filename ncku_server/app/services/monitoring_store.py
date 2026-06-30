from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path

from app.services.alert_rules import AlertCandidate


@dataclass(frozen=True, slots=True)
class AlertEvent:
    event_type: str
    alert: dict
    emitted_at: str

    def to_payload(self) -> dict:
        return {
            "eventType": self.event_type,
            "alert": self.alert,
            "emittedAt": self.emitted_at,
        }


class MonitoringStore:
    def __init__(self, db_path: str, telemetry_retention_per_chassis: int) -> None:
        self._db_path = Path(db_path)
        self._telemetry_retention_per_chassis = telemetry_retention_per_chassis

    def initialize(self) -> None:
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS telemetry_snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    chassis_id TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    summary_health TEXT,
                    summary_temperature_celsius REAL,
                    summary_power_watts REAL
                );

                CREATE INDEX IF NOT EXISTS idx_telemetry_snapshots_chassis_timestamp
                ON telemetry_snapshots (chassis_id, timestamp DESC);

                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_key TEXT NOT NULL,
                    chassis_id TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    category TEXT NOT NULL,
                    title TEXT NOT NULL,
                    message TEXT NOT NULL,
                    status TEXT NOT NULL,
                    first_seen_at TEXT NOT NULL,
                    last_seen_at TEXT NOT NULL,
                    resolved_at TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_alerts_status_last_seen
                ON alerts (status, last_seen_at DESC);

                CREATE UNIQUE INDEX IF NOT EXISTS idx_alerts_open_source_key
                ON alerts (source_key) WHERE status = 'open';

                CREATE TABLE IF NOT EXISTS script_jobs (
                    job_id TEXT PRIMARY KEY,
                    script_name TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    started_at TEXT,
                    completed_at TEXT,
                    duration_ms INTEGER,
                    exit_code INTEGER,
                    stdout TEXT,
                    stderr TEXT,
                    structured_output_json TEXT,
                    error TEXT,
                    working_directory TEXT,
                    input_json TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_script_jobs_created_at
                ON script_jobs (created_at DESC);
                """
            )

    def save_telemetry_snapshot(self, telemetry: dict) -> None:
        summary = telemetry.get("summary", {})
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO telemetry_snapshots (
                    chassis_id,
                    timestamp,
                    payload_json,
                    summary_health,
                    summary_temperature_celsius,
                    summary_power_watts
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    telemetry["chassisId"],
                    telemetry["timestamp"],
                    json.dumps(telemetry),
                    summary.get("health"),
                    summary.get("temperatureCelsius"),
                    summary.get("powerWatts"),
                ),
            )

            if self._telemetry_retention_per_chassis > 0:
                connection.execute(
                    """
                    DELETE FROM telemetry_snapshots
                    WHERE chassis_id = ?
                      AND id NOT IN (
                          SELECT id
                          FROM telemetry_snapshots
                          WHERE chassis_id = ?
                          ORDER BY timestamp DESC
                          LIMIT ?
                      )
                    """,
                    (
                        telemetry["chassisId"],
                        telemetry["chassisId"],
                        self._telemetry_retention_per_chassis,
                    ),
                )

    def list_telemetry_history(self, chassis_id: str, limit: int) -> list[dict]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT payload_json
                FROM telemetry_snapshots
                WHERE chassis_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
                """,
                (chassis_id, limit),
            ).fetchall()

        return [json.loads(row["payload_json"]) for row in rows]

    def sync_alerts(
        self,
        chassis_id: str,
        candidates: list[AlertCandidate],
        seen_at: str,
    ) -> list[AlertEvent]:
        candidate_keys = {candidate.source_key for candidate in candidates}
        events: list[AlertEvent] = []

        with self._connect() as connection:
            open_rows = connection.execute(
                """
                SELECT
                    id,
                    source_key,
                    chassis_id,
                    severity,
                    category,
                    title,
                    message,
                    status,
                    first_seen_at,
                    last_seen_at,
                    resolved_at
                FROM alerts
                WHERE chassis_id = ? AND status = 'open'
                """,
                (chassis_id,),
            ).fetchall()
            open_by_key = {row["source_key"]: row for row in open_rows}

            for candidate in candidates:
                existing_row = open_by_key.get(candidate.source_key)
                if existing_row is None:
                    cursor = connection.execute(
                        """
                        INSERT INTO alerts (
                            source_key,
                            chassis_id,
                            severity,
                            category,
                            title,
                            message,
                            status,
                            first_seen_at,
                            last_seen_at,
                            resolved_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, 'open', ?, ?, NULL)
                        """,
                        (
                            candidate.source_key,
                            candidate.chassis_id,
                            candidate.severity,
                            candidate.category,
                            candidate.title,
                            candidate.message,
                            seen_at,
                            seen_at,
                        ),
                    )
                    events.append(
                        AlertEvent(
                            event_type="opened",
                            alert={
                                "id": int(cursor.lastrowid),
                                "sourceKey": candidate.source_key,
                                "chassisId": candidate.chassis_id,
                                "severity": candidate.severity,
                                "category": candidate.category,
                                "title": candidate.title,
                                "message": candidate.message,
                                "status": "open",
                                "firstSeenAt": seen_at,
                                "lastSeenAt": seen_at,
                                "resolvedAt": None,
                            },
                            emitted_at=seen_at,
                        )
                    )
                else:
                    connection.execute(
                        """
                        UPDATE alerts
                        SET severity = ?,
                            category = ?,
                            title = ?,
                            message = ?,
                            last_seen_at = ?
                        WHERE id = ?
                        """,
                        (
                            candidate.severity,
                            candidate.category,
                            candidate.title,
                            candidate.message,
                            seen_at,
                            existing_row["id"],
                        ),
                    )
                    if existing_row["severity"] != candidate.severity:
                        events.append(
                            AlertEvent(
                                event_type="severity_changed",
                                alert={
                                    "id": existing_row["id"],
                                    "sourceKey": candidate.source_key,
                                    "chassisId": candidate.chassis_id,
                                    "severity": candidate.severity,
                                    "category": candidate.category,
                                    "title": candidate.title,
                                    "message": candidate.message,
                                    "status": "open",
                                    "firstSeenAt": existing_row["first_seen_at"],
                                    "lastSeenAt": seen_at,
                                    "resolvedAt": None,
                                },
                                emitted_at=seen_at,
                            )
                        )

            stale_keys = set(open_by_key) - candidate_keys
            if stale_keys:
                placeholders = ", ".join("?" for _ in stale_keys)
                connection.execute(
                    f"""
                    UPDATE alerts
                    SET status = 'resolved',
                        last_seen_at = ?,
                        resolved_at = ?
                    WHERE chassis_id = ?
                      AND status = 'open'
                      AND source_key IN ({placeholders})
                    """,
                    (seen_at, seen_at, chassis_id, *stale_keys),
                )
                for source_key in stale_keys:
                    existing_row = open_by_key[source_key]
                    events.append(
                        AlertEvent(
                            event_type="resolved",
                            alert={
                                "id": existing_row["id"],
                                "sourceKey": existing_row["source_key"],
                                "chassisId": existing_row["chassis_id"],
                                "severity": existing_row["severity"],
                                "category": existing_row["category"],
                                "title": existing_row["title"],
                                "message": existing_row["message"],
                                "status": "resolved",
                                "firstSeenAt": existing_row["first_seen_at"],
                                "lastSeenAt": seen_at,
                                "resolvedAt": seen_at,
                            },
                            emitted_at=seen_at,
                        )
                    )

        return events

    def list_alerts(self, limit: int, status: str | None) -> list[dict]:
        sql = """
            SELECT
                id,
                source_key,
                chassis_id,
                severity,
                category,
                title,
                message,
                status,
                first_seen_at,
                last_seen_at,
                resolved_at
            FROM alerts
        """
        params: list[object] = []

        if status is not None:
            sql += " WHERE status = ?"
            params.append(status)

        sql += " ORDER BY CASE status WHEN 'open' THEN 0 ELSE 1 END, last_seen_at DESC LIMIT ?"
        params.append(limit)

        with self._connect() as connection:
            rows = connection.execute(sql, params).fetchall()

        return [
            {
                "id": row["id"],
                "sourceKey": row["source_key"],
                "chassisId": row["chassis_id"],
                "severity": row["severity"],
                "category": row["category"],
                "title": row["title"],
                "message": row["message"],
                "status": row["status"],
                "firstSeenAt": row["first_seen_at"],
                "lastSeenAt": row["last_seen_at"],
                "resolvedAt": row["resolved_at"],
            }
            for row in rows
        ]

    def upsert_script_job(self, payload: dict) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO script_jobs (
                    job_id,
                    script_name,
                    status,
                    created_at,
                    started_at,
                    completed_at,
                    duration_ms,
                    exit_code,
                    stdout,
                    stderr,
                    structured_output_json,
                    error,
                    working_directory,
                    input_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(job_id) DO UPDATE SET
                    script_name = excluded.script_name,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    started_at = excluded.started_at,
                    completed_at = excluded.completed_at,
                    duration_ms = excluded.duration_ms,
                    exit_code = excluded.exit_code,
                    stdout = excluded.stdout,
                    stderr = excluded.stderr,
                    structured_output_json = excluded.structured_output_json,
                    error = excluded.error,
                    working_directory = excluded.working_directory,
                    input_json = excluded.input_json
                """,
                (
                    payload["jobId"],
                    payload["scriptName"],
                    payload["status"],
                    payload["createdAt"],
                    payload.get("startedAt"),
                    payload.get("completedAt"),
                    payload.get("durationMs"),
                    payload.get("exitCode"),
                    payload.get("stdout"),
                    payload.get("stderr"),
                    self._json_text(payload.get("structuredOutput")),
                    payload.get("error"),
                    payload.get("workingDirectory"),
                    self._json_text(payload.get("inputJson")),
                ),
            )

    def get_script_job(self, job_id: str) -> dict | None:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT
                    job_id,
                    script_name,
                    status,
                    created_at,
                    started_at,
                    completed_at,
                    duration_ms,
                    exit_code,
                    stdout,
                    stderr,
                    structured_output_json,
                    error,
                    working_directory,
                    input_json
                FROM script_jobs
                WHERE job_id = ?
                """,
                (job_id,),
            ).fetchone()

        return self._script_job_row_to_payload(row) if row is not None else None

    def list_script_jobs(self, limit: int) -> list[dict]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT
                    job_id,
                    script_name,
                    status,
                    created_at,
                    started_at,
                    completed_at,
                    duration_ms,
                    exit_code,
                    stdout,
                    stderr,
                    structured_output_json,
                    error,
                    working_directory,
                    input_json
                FROM script_jobs
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()

        return [self._script_job_row_to_payload(row) for row in rows]

    def mark_incomplete_script_jobs_cancelled(
        self,
        *,
        seen_at: str,
        message: str,
    ) -> int:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT
                    job_id,
                    created_at
                FROM script_jobs
                WHERE status IN ('queued', 'running')
                """
            ).fetchall()

            if not rows:
                return 0

            connection.executemany(
                """
                UPDATE script_jobs
                SET status = 'cancelled',
                    completed_at = COALESCE(completed_at, ?),
                    error = COALESCE(error, ?)
                WHERE job_id = ?
                """,
                [(seen_at, message, row["job_id"]) for row in rows],
            )

        return len(rows)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._db_path)
        connection.row_factory = sqlite3.Row
        return connection

    @staticmethod
    def _json_text(value: object | None) -> str | None:
        if value is None:
            return None
        return json.dumps(value)

    @staticmethod
    def _json_value(raw: str | None) -> object | None:
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except ValueError:
            return None

    def _script_job_row_to_payload(self, row: sqlite3.Row) -> dict:
        return {
            "jobId": row["job_id"],
            "scriptName": row["script_name"],
            "status": row["status"],
            "createdAt": row["created_at"],
            "startedAt": row["started_at"],
            "completedAt": row["completed_at"],
            "durationMs": row["duration_ms"],
            "exitCode": row["exit_code"],
            "stdout": row["stdout"],
            "stderr": row["stderr"],
            "structuredOutput": self._json_value(row["structured_output_json"]),
            "error": row["error"],
            "workingDirectory": row["working_directory"],
            "inputJson": self._json_value(row["input_json"]),
        }
