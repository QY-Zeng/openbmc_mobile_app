from __future__ import annotations

import asyncio
import json
import os
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import HTTPException

from app.services.monitoring_store import MonitoringStore


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(slots=True)
class ScriptJobRecord:
    job_id: str
    script_name: str
    status: str
    created_at: str
    input_json: Any | None = None
    started_at: str | None = None
    completed_at: str | None = None
    duration_ms: int | None = None
    exit_code: int | None = None
    stdout: str | None = None
    stderr: str | None = None
    structured_output: Any | None = None
    error: str | None = None
    working_directory: str | None = None

    def to_payload(self) -> dict[str, Any]:
        return {
            "jobId": self.job_id,
            "scriptName": self.script_name,
            "status": self.status,
            "createdAt": self.created_at,
            "startedAt": self.started_at,
            "completedAt": self.completed_at,
            "durationMs": self.duration_ms,
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "structuredOutput": self.structured_output,
            "error": self.error,
            "workingDirectory": self.working_directory,
            "inputJson": self.input_json,
        }


class ScriptJobService:
    def __init__(
        self,
        *,
        store: MonitoringStore,
        jobs_dir: str,
        timeout_seconds: float,
        max_source_bytes: int,
        max_output_bytes: int,
    ) -> None:
        self._store = store
        self._jobs_dir = Path(jobs_dir)
        self._timeout_seconds = timeout_seconds
        self._max_source_bytes = max_source_bytes
        self._max_output_bytes = max_output_bytes
        self._tasks: dict[str, asyncio.Task[None]] = {}
        self._jobs_dir.mkdir(parents=True, exist_ok=True)
        self._store.mark_incomplete_script_jobs_cancelled(
            seen_at=_utc_now_iso(),
            message="FastAPI restarted before the Python job completed.",
        )

    def submit_job(
        self,
        *,
        script_name: str,
        source_code: str,
        input_json: Any | None,
    ) -> dict[str, Any]:
        encoded_source = source_code.encode("utf-8")
        if len(encoded_source) > self._max_source_bytes:
            raise HTTPException(
                status_code=400,
                detail=(
                    "Python source exceeds the configured size limit of "
                    f"{self._max_source_bytes} bytes."
                ),
            )

        normalized_name = self._normalize_script_name(script_name)
        job_id = uuid.uuid4().hex[:12]
        record = ScriptJobRecord(
            job_id=job_id,
            script_name=normalized_name,
            status="queued",
            created_at=_utc_now_iso(),
            input_json=input_json,
        )
        self._store.upsert_script_job(record.to_payload())

        task = asyncio.create_task(
            self._run_job(
                record=record,
                source_code=source_code,
            )
        )
        self._tasks[job_id] = task
        task.add_done_callback(lambda _: self._tasks.pop(job_id, None))
        return record.to_payload()

    def get_job(self, job_id: str) -> dict[str, Any]:
        record = self._store.get_script_job(job_id)
        if record is None:
            raise HTTPException(status_code=404, detail=f"Script job {job_id} was not found")
        return record

    def list_jobs(self, limit: int) -> list[dict[str, Any]]:
        return self._store.list_script_jobs(limit)

    async def shutdown(self) -> None:
        tasks = list(self._tasks.values())
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _run_job(
        self,
        *,
        record: ScriptJobRecord,
        source_code: str,
    ) -> None:
        job_id = record.job_id
        script_name = record.script_name
        input_json = record.input_json
        started_at = datetime.now(timezone.utc)
        record.status = "running"
        record.started_at = started_at.isoformat()

        job_dir = self._jobs_dir / job_id
        job_dir.mkdir(parents=True, exist_ok=True)
        record.working_directory = str(job_dir)
        self._store.upsert_script_job(record.to_payload())

        script_path = job_dir / script_name
        input_path = job_dir / "input.json"
        output_path = job_dir / "output.json"
        stdin_payload = input_json if input_json is not None else {}

        script_path.write_text(source_code, encoding="utf-8")
        input_path.write_text(
            json.dumps(stdin_payload, ensure_ascii=True, indent=2),
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        env["JOB_INPUT_PATH"] = str(input_path)
        env["JOB_OUTPUT_PATH"] = str(output_path)
        env["SCRIPT_JOB_ID"] = job_id

        try:
            process = await asyncio.create_subprocess_exec(
                sys.executable,
                "-u",
                script_path.name,
                cwd=str(job_dir),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env,
            )
        except Exception as exc:
            self._finish_record(
                record,
                status="failed",
                started_at=started_at,
                exit_code=None,
                stdout="",
                stderr="",
                error=f"Unable to start Python job: {exc}",
                structured_output=None,
            )
            return

        try:
            stdout_bytes, stderr_bytes = await asyncio.wait_for(
                process.communicate(json.dumps(stdin_payload).encode("utf-8")),
                timeout=self._timeout_seconds,
            )
        except asyncio.TimeoutError:
            process.kill()
            stdout_bytes, stderr_bytes = await process.communicate()
            self._finish_record(
                record,
                status="timed_out",
                started_at=started_at,
                exit_code=None,
                stdout=self._truncate_output(stdout_bytes.decode("utf-8", errors="replace")),
                stderr=self._truncate_output(stderr_bytes.decode("utf-8", errors="replace")),
                error=f"Python job exceeded {self._timeout_seconds:.0f} seconds.",
                structured_output=self._load_structured_output(output_path),
            )
            return
        except asyncio.CancelledError:
            process.kill()
            stdout_bytes, stderr_bytes = await process.communicate()
            self._finish_record(
                record,
                status="cancelled",
                started_at=started_at,
                exit_code=None,
                stdout=self._truncate_output(stdout_bytes.decode("utf-8", errors="replace")),
                stderr=self._truncate_output(stderr_bytes.decode("utf-8", errors="replace")),
                error="Python job was cancelled during shutdown.",
                structured_output=self._load_structured_output(output_path),
            )
            raise

        exit_code = process.returncode
        stdout = self._truncate_output(stdout_bytes.decode("utf-8", errors="replace"))
        stderr = self._truncate_output(stderr_bytes.decode("utf-8", errors="replace"))
        structured_output = self._load_structured_output(output_path)

        status = "completed" if exit_code == 0 else "failed"
        error = None
        if exit_code != 0:
            error = f"Python job exited with code {exit_code}."

        self._finish_record(
            record,
            status=status,
            started_at=started_at,
            exit_code=exit_code,
            stdout=stdout,
            stderr=stderr,
            error=error,
            structured_output=structured_output,
        )

    def _finish_record(
        self,
        record: ScriptJobRecord,
        *,
        status: str,
        started_at: datetime,
        exit_code: int | None,
        stdout: str,
        stderr: str,
        error: str | None,
        structured_output: Any | None,
    ) -> None:
        completed_at = datetime.now(timezone.utc)
        record.status = status
        record.completed_at = completed_at.isoformat()
        record.duration_ms = int((completed_at - started_at).total_seconds() * 1000)
        record.exit_code = exit_code
        record.stdout = stdout
        record.stderr = stderr
        record.error = error
        record.structured_output = structured_output
        self._store.upsert_script_job(record.to_payload())

    def _load_structured_output(self, output_path: Path) -> Any | None:
        if not output_path.exists():
            return None
        try:
            return json.loads(output_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None

    def _truncate_output(self, text: str) -> str:
        encoded = text.encode("utf-8")
        if len(encoded) <= self._max_output_bytes:
            return text
        truncated = encoded[: self._max_output_bytes].decode("utf-8", errors="ignore")
        return f"{truncated}\n...[truncated]"

    @staticmethod
    def _normalize_script_name(script_name: str) -> str:
        cleaned = Path(script_name.strip()).name or "job.py"
        if not cleaned.endswith(".py"):
            cleaned = f"{cleaned}.py"
        if cleaned in {".py", "..py"}:
            cleaned = "job.py"
        return cleaned
