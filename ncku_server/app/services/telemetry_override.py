from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class TelemetryOverride:
    cpu1_temp: Optional[float] = None
    cpu2_temp: Optional[float] = None
    intake_temp: Optional[float] = None

    fan1_rpm: Optional[int] = None
    fan2_rpm: Optional[int] = None

    power_watts: Optional[float] = None


class TelemetryOverrideStore:
    def __init__(self) -> None:
        self._data: dict[str, TelemetryOverride] = {}

    def get(self, chassis_id: str) -> TelemetryOverride:
        return self._data.setdefault(chassis_id, TelemetryOverride())

    def update(
        self,
        chassis_id: str,
        *,
        cpu1_temp: float | None = None,
        cpu2_temp: float | None = None,
        intake_temp: float | None = None,
        fan1_rpm: int | None = None,
        fan2_rpm: int | None = None,
        power_watts: float | None = None,
    ) -> TelemetryOverride:

        item = self.get(chassis_id)

        if cpu1_temp is not None:
            item.cpu1_temp = cpu1_temp

        if cpu2_temp is not None:
            item.cpu2_temp = cpu2_temp

        if intake_temp is not None:
            item.intake_temp = intake_temp

        if fan1_rpm is not None:
            item.fan1_rpm = fan1_rpm

        if fan2_rpm is not None:
            item.fan2_rpm = fan2_rpm

        if power_watts is not None:
            item.power_watts = power_watts

        return item