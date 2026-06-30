from pydantic import BaseModel, Field, model_validator


class TelemetrySummary(BaseModel):
    temperatureCelsius: float | None = None
    powerWatts: float | None = None
    health: str | None = None


class TemperatureReading(BaseModel):
    id: str
    name: str | None = None
    celsius: float | None = None
    health: str | None = None
    state: str | None = None
    physicalContext: str | None = None
    upperCaution: float | None = None
    upperCritical: float | None = None
    upperFatal: float | None = None


class TemperatureThresholdsUpdateRequest(BaseModel):
    upperCaution: float | None = Field(default=None, gt=-273.15)
    upperCritical: float | None = Field(default=None, gt=-273.15)
    upperFatal: float | None = Field(default=None, gt=-273.15)

    @model_validator(mode="after")
    def validate_thresholds(self) -> "TemperatureThresholdsUpdateRequest":
        if (
            self.upperCaution is None
            and self.upperCritical is None
            and self.upperFatal is None
        ):
            raise ValueError("At least one temperature threshold must be provided.")

        if (
            self.upperCaution is not None
            and self.upperCritical is not None
            and self.upperCaution > self.upperCritical
        ):
            raise ValueError("upperCaution cannot be greater than upperCritical.")

        if (
            self.upperCritical is not None
            and self.upperFatal is not None
            and self.upperCritical > self.upperFatal
        ):
            raise ValueError("upperCritical cannot be greater than upperFatal.")

        if (
            self.upperCaution is not None
            and self.upperFatal is not None
            and self.upperCaution > self.upperFatal
        ):
            raise ValueError("upperCaution cannot be greater than upperFatal.")

        return self


class FanReading(BaseModel):
    id: str
    name: str | None = None
    rpm: float | None = None
    health: str | None = None
    state: str | None = None
    physicalContext: str | None = None


class PowerControlReading(BaseModel):
    id: str
    name: str | None = None
    consumedWatts: float | None = None
    averageWatts: float | None = None
    peakWatts: float | None = None
    capacityWatts: float | None = None
    allocatedWatts: float | None = None
    health: str | None = None
    state: str | None = None


class PowerSupplyReading(BaseModel):
    id: str
    name: str | None = None
    lastOutputWatts: float | None = None
    capacityWatts: float | None = None
    health: str | None = None
    state: str | None = None
    model: str | None = None
    firmwareVersion: str | None = None


class ChassisTelemetryCurrentResponse(BaseModel):
    chassisId: str
    timestamp: str
    summary: TelemetrySummary
    temperatures: list[TemperatureReading] = Field(default_factory=list)
    fans: list[FanReading] = Field(default_factory=list)
    powerControls: list[PowerControlReading] = Field(default_factory=list)
    powerSupplies: list[PowerSupplyReading] = Field(default_factory=list)


class ChassisTelemetryHistoryResponse(BaseModel):
    count: int
    items: list[ChassisTelemetryCurrentResponse] = Field(default_factory=list)
