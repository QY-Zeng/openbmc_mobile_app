from __future__ import annotations

from dataclasses import dataclass

ABSOLUTE_OVERHEAT_CRITICAL_CELSIUS = 80.0


@dataclass(frozen=True, slots=True)
class AlertCandidate:
    source_key: str
    chassis_id: str
    severity: str
    category: str
    title: str
    message: str


def build_alert_candidates(telemetry: dict) -> list[AlertCandidate]:
    chassis_id = telemetry["chassisId"]
    alerts: list[AlertCandidate] = []

    for temperature in telemetry.get("temperatures", []):
        if not _is_enabled(temperature.get("state")):
            continue

        severity = _temperature_severity(temperature)
        if severity is None:
            continue

        current = temperature.get("celsius")
        alerts.append(
            AlertCandidate(
                source_key=f"temperature:{chassis_id}:{temperature['id']}",
                chassis_id=chassis_id,
                severity=severity,
                category="temperature",
                title=f"Temperature alert: {temperature.get('name') or temperature['id']}",
                message=(
                    f"{temperature.get('name') or temperature['id']} is "
                    f"{_format_temperature(current)} on {chassis_id}."
                ),
            )
        )

    for fan in telemetry.get("fans", []):
        if not _is_enabled(fan.get("state")):
            continue

        severity = _health_to_severity(fan.get("health"))
        if severity is None:
            continue

        alerts.append(
            AlertCandidate(
                source_key=f"fan:{chassis_id}:{fan['id']}",
                chassis_id=chassis_id,
                severity=severity,
                category="fan",
                title=f"Fan alert: {fan.get('name') or fan['id']}",
                message=(
                    f"{fan.get('name') or fan['id']} is at "
                    f"{_format_rpm(fan.get('rpm'))} on {chassis_id}."
                ),
            )
        )

    for power_control in telemetry.get("powerControls", []):
        if not _is_enabled(power_control.get("state")):
            continue

        severity = _health_to_severity(power_control.get("health"))
        if severity is None:
            continue

        alerts.append(
            AlertCandidate(
                source_key=f"power-control:{chassis_id}:{power_control['id']}",
                chassis_id=chassis_id,
                severity=severity,
                category="power",
                title=f"Power alert: {power_control.get('name') or power_control['id']}",
                message=(
                    f"{power_control.get('name') or power_control['id']} is consuming "
                    f"{_format_watts(power_control.get('consumedWatts'))} on {chassis_id}."
                ),
            )
        )

    for power_supply in telemetry.get("powerSupplies", []):
        if not _is_enabled(power_supply.get("state")):
            continue

        severity = _health_to_severity(power_supply.get("health"))
        if severity is None:
            continue

        alerts.append(
            AlertCandidate(
                source_key=f"power-supply:{chassis_id}:{power_supply['id']}",
                chassis_id=chassis_id,
                severity=severity,
                category="power-supply",
                title=f"Power supply alert: {power_supply.get('name') or power_supply['id']}",
                message=(
                    f"{power_supply.get('name') or power_supply['id']} output is "
                    f"{_format_watts(power_supply.get('lastOutputWatts'))} on {chassis_id}."
                ),
            )
        )

    return alerts


def _temperature_severity(temperature: dict) -> str | None:
    by_health = _health_to_severity(temperature.get("health"))
    current = temperature.get("celsius")

    upper_fatal = temperature.get("upperFatal")
    upper_critical = temperature.get("upperCritical")
    upper_caution = temperature.get("upperCaution")

    threshold_severity: str | None = None
    if current is not None and current >= ABSOLUTE_OVERHEAT_CRITICAL_CELSIUS:
        threshold_severity = "critical"
    elif current is not None and upper_fatal is not None and current >= upper_fatal:
        threshold_severity = "critical"
    elif current is not None and upper_critical is not None and current >= upper_critical:
        threshold_severity = "critical"
    elif current is not None and upper_caution is not None and current >= upper_caution:
        threshold_severity = "warning"

    return _higher_severity(by_health, threshold_severity)


def _higher_severity(*values: str | None) -> str | None:
    severity_rank = {"warning": 1, "critical": 2}
    best_rank = 0
    best: str | None = None

    for value in values:
        if value is None:
            continue
        rank = severity_rank.get(value.lower(), 0)
        if rank > best_rank:
            best_rank = rank
            best = value.lower()

    return best


def _health_to_severity(health: str | None) -> str | None:
    if health is None:
        return None

    normalized = health.upper()
    if normalized == "WARNING":
        return "warning"
    if normalized == "CRITICAL":
        return "critical"
    return None


def _is_enabled(state: str | None) -> bool:
    return (state or "").upper() == "ENABLED"


def _format_temperature(value: float | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:.1f} C"


def _format_watts(value: float | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:.1f} W"


def _format_rpm(value: float | None) -> str:
    if value is None:
        return "unknown"
    return f"{value:.0f} RPM"
