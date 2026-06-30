from pydantic import BaseModel


class TelemetryOverrideUpdateRequest(BaseModel):
    cpu1Temp: float | None = None
    cpu2Temp: float | None = None
    intakeTemp: float | None = None

    fan1Rpm: int | None = None
    fan2Rpm: int | None = None

    powerWatts: float | None = None


class TelemetryOverrideResponse(BaseModel):
    cpu1Temp: float | None
    cpu2Temp: float | None
    intakeTemp: float | None

    fan1Rpm: int | None
    fan2Rpm: int | None

    powerWatts: float | None