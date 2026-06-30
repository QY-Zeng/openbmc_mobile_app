from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ScriptJobSubmitRequest(BaseModel):
    scriptName: str = Field(min_length=1, max_length=120)
    sourceCode: str = Field(min_length=1, max_length=200000)
    inputJson: Any | None = None


class ScriptJobResponse(BaseModel):
    jobId: str
    scriptName: str
    status: str
    createdAt: str
    startedAt: str | None = None
    completedAt: str | None = None
    durationMs: int | None = None
    exitCode: int | None = None
    stdout: str | None = None
    stderr: str | None = None
    structuredOutput: Any | None = None
    error: str | None = None
    workingDirectory: str | None = None
    inputJson: Any | None = None


class ScriptJobListResponse(BaseModel):
    count: int
    items: list[ScriptJobResponse]
