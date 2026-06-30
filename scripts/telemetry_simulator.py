#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import random
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass


@dataclass(slots=True)
class TelemetryState:
    chassis_id: str
    load_ratio: float
    cpu1_temp_c: float
    cpu2_temp_c: float
    intake_temp_c: float
    fan1_rpm: float
    fan2_rpm: float
    power_watts: float


@dataclass(frozen=True, slots=True)
class ChassisProfile:
    chassis_id: str
    phase_offset: float
    load_bias: float
    temp_bias: float
    fan_bias: float
    power_bias: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Continuously PATCH Redfish emulator thermal and power values.",
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:5001",
        help="Base URL of the Redfish emulator.",
    )
    parser.add_argument(
        "--chassis-id",
        action="append",
        default=None,
        help=(
            "Chassis identifier to simulate. Repeat the flag or pass a comma-separated "
            "list. Defaults to all chassis in the collection."
        ),
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="Seconds between updates.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for repeatable jitter.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Apply a single update and exit.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    simulator = TelemetrySimulator(
        base_url=args.base_url.rstrip("/"),
        chassis_ids=args.chassis_id,
        interval=args.interval,
        seed=args.seed,
    )
    return simulator.run(once=args.once)


class TelemetrySimulator:
    def __init__(
        self,
        *,
        base_url: str,
        chassis_ids: list[str] | None,
        interval: float,
        seed: int,
    ) -> None:
        self.base_url = base_url
        self.requested_chassis_ids = _normalize_requested_chassis_ids(chassis_ids)
        self.profiles: list[ChassisProfile] = []
        self.interval = interval
        self.random = random.Random(seed)
        self.seed = seed
        self.tick = 0

    def run(self, *, once: bool) -> int:
        chassis_ids = self.requested_chassis_ids or self._detect_chassis_ids()
        self.profiles = self._build_profiles(chassis_ids)
        print(
            f"Telemetry simulator -> {self.base_url} chassis={','.join(chassis_ids)} interval={self.interval}s"
        )
        try:
            while True:
                states: list[TelemetryState] = []
                for profile in self.profiles:
                    thermal = self._get_json(self._thermal_path(profile.chassis_id))
                    power = self._get_json(self._power_path(profile.chassis_id))
                    state = self._next_state(profile)
                    self._apply_state(thermal, power, state)
                    self._patch_json(self._thermal_path(profile.chassis_id), thermal)
                    self._patch_json(self._power_path(profile.chassis_id), power)
                    states.append(state)
                self._log_states(states)
                self.tick += 1
                if once:
                    return 0
                time.sleep(self.interval)
        except KeyboardInterrupt:
            print("\nTelemetry simulator stopped.")
            return 0
        except Exception as exc:
            print(f"Telemetry simulator failed: {exc}", file=sys.stderr)
            return 1

    def _thermal_path(self, chassis_id: str) -> str:
        return f"/redfish/v1/Chassis/{chassis_id}/Thermal"

    def _power_path(self, chassis_id: str) -> str:
        return f"/redfish/v1/Chassis/{chassis_id}/Power"

    def _get_json(self, path: str) -> dict:
        request = urllib.request.Request(f"{self.base_url}{path}", method="GET")
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))

    def _patch_json(self, path: str, payload: dict) -> None:
        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            method="PATCH",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=10):
                return
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code == 405:
                raise RuntimeError(
                    "PATCH is not allowed on this backend. Start "
                    "./scripts/run_redfish_emulator.sh dynamic-populate "
                    "and point the simulator at that emulator."
                ) from exc
            raise RuntimeError(f"PATCH {path} failed: {exc.code} {body}") from exc

    def _detect_chassis_ids(self) -> list[str]:
        collection = self._get_json("/redfish/v1/Chassis")
        members = collection.get("Members") or []
        chassis_ids: list[str] = []
        for member in members:
            if not isinstance(member, dict):
                continue
            uri = member.get("@odata.id")
            chassis_id = _extract_id_from_uri(uri)
            if chassis_id is not None:
                chassis_ids.append(chassis_id)
        if not chassis_ids:
            raise RuntimeError("No chassis resources were found under /redfish/v1/Chassis")
        return chassis_ids

    def _build_profiles(self, chassis_ids: list[str]) -> list[ChassisProfile]:
        profiles: list[ChassisProfile] = []
        for index, chassis_id in enumerate(chassis_ids):
            profiles.append(
                ChassisProfile(
                    chassis_id=chassis_id,
                    phase_offset=index * 0.8,
                    load_bias=((index % 5) - 2) * 0.045,
                    temp_bias=((index % 4) - 1.5) * 1.2,
                    fan_bias=((index % 3) - 1) * 130,
                    power_bias=((index % 6) - 2.5) * 22,
                )
            )
        return profiles

    def _next_state(self, profile: ChassisProfile) -> TelemetryState:
        phase = self.tick / 6.0 + profile.phase_offset
        load_ratio = 0.5 + 0.35 * math.sin(phase) + 0.1 * math.sin(phase / 3.0)
        load_ratio = _clamp(
            load_ratio + profile.load_bias + self.random.uniform(-0.04, 0.04),
            0.12,
            0.96,
        )

        cpu1_temp_c = _clamp(
            34 + load_ratio * 14 + profile.temp_bias + self.random.uniform(-0.8, 0.8),
            30,
            52,
        )
        cpu2_temp_c = _clamp(
            34 + load_ratio * 14 + profile.temp_bias + self.random.uniform(-0.8, 0.8),
            30,
            52,
        )
        intake_temp_c = _clamp(
            22 + load_ratio * 6 + profile.temp_bias * 0.35 + self.random.uniform(-0.5, 0.5),
            18,
            38,
        )
        fan1_rpm = _clamp(
            1650 + load_ratio * 1700 + profile.fan_bias + self.random.uniform(-60, 60),
            1400,
            4400,
        )
        fan2_rpm = _clamp(fan1_rpm - 80 + self.random.uniform(-40, 40), 1300, 4300)
        power_watts = _clamp(
            250 + load_ratio * 230 + profile.power_bias + self.random.uniform(-12, 12),
            180,
            620,
        )

        return TelemetryState(
            chassis_id=profile.chassis_id,
            load_ratio=load_ratio,
            cpu1_temp_c=cpu1_temp_c,
            cpu2_temp_c=cpu2_temp_c,
            intake_temp_c=intake_temp_c,
            fan1_rpm=fan1_rpm,
            fan2_rpm=fan2_rpm,
            power_watts=power_watts,
        )

    def _apply_state(
        self,
        thermal: dict,
        power: dict,
        state: TelemetryState,
    ) -> None:
        temperatures = thermal.get("Temperatures") or []
        if len(temperatures) >= 1:
            temp = temperatures[0]
            temp["ReadingCelsius"] = round(state.cpu1_temp_c, 1)
            temp["Status"] = {
                "State": "Enabled",
                "Health": _health_for_temperature(state.cpu1_temp_c),
            }

        if len(temperatures) >= 2:
            temp = temperatures[1]
            temp["ReadingCelsius"] = round(state.cpu2_temp_c, 1)
            temp["Status"] = {
                "State": "Enabled",
                "Health": _health_for_temperature(state.cpu2_temp_c),
            }



        if len(temperatures) >= 3:
            intake = temperatures[2]
            intake["ReadingCelsius"] = round(state.intake_temp_c, 1)
            intake["Status"] = {
                "State": "Enabled",
                "Health": "OK" if state.intake_temp_c < 32 else "Warning",
            }

        fans = thermal.get("Fans") or []
        fan_rpms = [state.fan1_rpm, state.fan2_rpm]
        for fan, rpm in zip(fans, fan_rpms):
            fan["Reading"] = round(rpm)
            fan["ReadingRPM"] = round(rpm)
            fan["Status"] = {
                "State": "Enabled",
                "Health": _health_for_fan(rpm),
            }

        power_controls = power.get("PowerControl") or []
        if power_controls:
            control = power_controls[0]
            control["PowerConsumedWatts"] = round(state.power_watts, 1)
            control["PowerAllocatedWatts"] = max(
                round(state.power_watts + 25, 1),
                control.get("PowerAllocatedWatts") or 0,
            )
            metrics = control.setdefault("PowerMetrics", {})
            metrics["AverageConsumedWatts"] = round(state.power_watts * 0.94, 1)
            metrics["MinConsumedWatts"] = round(state.power_watts * 0.82, 1)
            metrics["MaxConsumedWatts"] = round(state.power_watts * 1.08, 1)
            control["Status"] = {
                "State": "Enabled",
                "Health": _health_for_power(state.power_watts),
            }

        power_supplies = power.get("PowerSupplies") or []
        if power_supplies:
            supply = power_supplies[0]
            supply["LastPowerOutputWatts"] = round(state.power_watts * 0.95, 1)
            supply["Status"] = {
                "State": "Enabled",
                "Health": _health_for_power(state.power_watts),
            }

    def _log_states(self, states: list[TelemetryState]) -> None:
        details = " | ".join(
            (
                "{chassis}: cpu1={cpu1:.1f}C cpu2={cpu2:.1f}C fan={fan1:.0f}/{fan2:.0f}rpm power={power:.1f}W "
                "load={load:.2f}"
            ).format(
                chassis=state.chassis_id,
                cpu1=state.cpu1_temp_c,
                cpu2=state.cpu2_temp_c,
                fan1=state.fan1_rpm,
                fan2=state.fan2_rpm,
                power=state.power_watts,
                load=state.load_ratio,
            )
            for state in states
        )
        print(f"tick={self.tick:03d} {details}")


def _health_for_temperature(temp_c: float) -> str:
    if temp_c >= 46:
        return "Critical"
    if temp_c >= 42:
        return "Warning"
    return "OK"


def _health_for_fan(rpm: float) -> str:
    if rpm < 1500:
        return "Critical"
    if rpm < 1750:
        return "Warning"
    return "OK"


def _health_for_power(power_watts: float) -> str:
    if power_watts >= 520:
        return "Critical"
    if power_watts >= 470:
        return "Warning"
    return "OK"


def _clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def _extract_id_from_uri(uri: str | None) -> str | None:
    if not uri:
        return None
    return uri.rstrip("/").split("/")[-1]


def _normalize_requested_chassis_ids(chassis_ids: list[str] | None) -> list[str]:
    if not chassis_ids:
        return []

    normalized: list[str] = []
    for value in chassis_ids:
        normalized.extend(
            item.strip()
            for item in value.split(",")
            if item.strip()
        )
    return normalized


if __name__ == "__main__":
    raise SystemExit(main())
