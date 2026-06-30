from typing import Any


def _extract_resource_id(resource: dict[str, Any]) -> str:
    return (
        resource.get("Id")
        or _extract_id_from_uri(resource.get("@odata.id"))
        or "unknown"
    )


def _extract_id_from_uri(uri: str | None) -> str | None:
    if not uri:
        return None
    return uri.rstrip("/").split("/")[-1]


def _extract_link_uri(resource: dict[str, Any] | None) -> str | None:
    if not isinstance(resource, dict):
        return None
    return resource.get("@odata.id")


def _simplify_status(status: dict[str, Any] | None) -> dict[str, str | None]:
    status = status or {}
    return {
        "state": status.get("State"),
        "health": status.get("Health"),
        "healthRollup": status.get("HealthRollup"),
    }


def _simplify_system_reset_action(system: dict[str, Any]) -> dict[str, Any]:
    reset_action = ((system.get("Actions") or {}).get("#ComputerSystem.Reset")) or {}
    allowable_values = (
        reset_action.get("ResetType@Redfish.AllowableValues")
        or reset_action.get("ResetType@DMTF.AllowableValues")
        or []
    )
    return {
        "target": reset_action.get("target"),
        "allowableValues": [
            value for value in allowable_values if isinstance(value, str)
        ],
    }


def simplify_system_summary(system: dict[str, Any]) -> dict[str, Any]:
    processor_summary = system.get("ProcessorSummary") or {}
    memory_summary = system.get("MemorySummary") or {}

    return {
        "id": _extract_resource_id(system),
        "name": system.get("Name"),
        "hostName": system.get("HostName"),
        "manufacturer": system.get("Manufacturer"),
        "model": system.get("Model"),
        "systemType": system.get("SystemType"),
        "serialNumber": system.get("SerialNumber"),
        "powerState": system.get("PowerState"),
        "indicatorLed": system.get("IndicatorLED"),
        "status": _simplify_status(system.get("Status")),
        "processorCount": processor_summary.get("Count"),
        "processorModel": processor_summary.get("Model"),
        "memoryGiB": memory_summary.get("TotalSystemMemoryGiB"),
        "redfishUri": system.get("@odata.id"),
    }


def simplify_system_detail(system: dict[str, Any]) -> dict[str, Any]:
    boot = system.get("Boot") or {}
    detail = simplify_system_summary(system)
    detail.update(
        {
            "assetTag": system.get("AssetTag"),
            "description": system.get("Description"),
            "biosVersion": system.get("BiosVersion"),
            "lastResetTime": system.get("LastResetTime"),
            "boot": {
                "overrideEnabled": boot.get("BootSourceOverrideEnabled"),
                "overrideTarget": boot.get("BootSourceOverrideTarget"),
                "overrideMode": boot.get("BootSourceOverrideMode"),
            },
            "links": {
                "biosUri": _extract_link_uri(system.get("Bios")),
                "processorsUri": _extract_link_uri(system.get("Processors")),
                "memoryUri": _extract_link_uri(system.get("Memory")),
                "ethernetInterfacesUri": _extract_link_uri(
                    system.get("EthernetInterfaces")
                ),
                "chassisUris": [
                    link.get("@odata.id")
                    for link in (system.get("Links") or {}).get("Chassis", [])
                    if link.get("@odata.id")
                ],
            },
            "actions": {
                "reset": _simplify_system_reset_action(system),
            },
        }
    )
    return detail


def simplify_chassis_summary(chassis: dict[str, Any]) -> dict[str, Any]:
    links = chassis.get("Links") or {}
    computer_system_uris = [
        link.get("@odata.id")
        for link in links.get("ComputerSystems", [])
        if link.get("@odata.id")
    ]

    return {
        "id": _extract_resource_id(chassis),
        "name": chassis.get("Name"),
        "chassisType": chassis.get("ChassisType"),
        "manufacturer": chassis.get("Manufacturer"),
        "model": chassis.get("Model"),
        "serialNumber": chassis.get("SerialNumber"),
        "powerState": chassis.get("PowerState"),
        "indicatorLed": chassis.get("IndicatorLED"),
        "status": _simplify_status(chassis.get("Status")),
        "thermalUri": _extract_link_uri(chassis.get("ThermalSubsystem"))
        or _extract_link_uri(chassis.get("Thermal")),
        "powerUri": _extract_link_uri(chassis.get("PowerSubsystem"))
        or _extract_link_uri(chassis.get("Power")),
        "sensorsUri": _extract_link_uri(chassis.get("Sensors")),
        "environmentMetricsUri": _extract_link_uri(chassis.get("EnvironmentMetrics")),
        "computerSystemIds": [
            system_id
            for uri in computer_system_uris
            if (system_id := _extract_id_from_uri(uri)) is not None
        ],
        "redfishUri": chassis.get("@odata.id"),
    }


def simplify_chassis_detail(chassis: dict[str, Any]) -> dict[str, Any]:
    links = chassis.get("Links") or {}
    detail = simplify_chassis_summary(chassis)
    detail.update(
        {
            "assetTag": chassis.get("AssetTag"),
            "heightMm": chassis.get("HeightMm"),
            "widthMm": chassis.get("WidthMm"),
            "depthMm": chassis.get("DepthMm"),
            "weightKg": chassis.get("WeightKg"),
            "rack": ((chassis.get("Location") or {}).get("Placement") or {}).get("Rack"),
            "row": ((chassis.get("Location") or {}).get("Placement") or {}).get("Row"),
            "managedByUris": [
                link.get("@odata.id")
                for link in links.get("ManagedBy", [])
                if link.get("@odata.id")
            ],
            "managerUris": [
                link.get("@odata.id")
                for link in links.get("ManagersInChassis", [])
                if link.get("@odata.id")
            ],
        }
    )
    return detail


def simplify_temperature_reading(
    temperature: dict[str, Any],
    *,
    default_id: str,
) -> dict[str, Any]:
    return {
        "id": temperature.get("MemberId") or default_id,
        "name": temperature.get("Name"),
        "celsius": temperature.get("ReadingCelsius")
        or temperature.get("ReadingCelcius"),
        "health": ((temperature.get("Status") or {}).get("Health")),
        "state": ((temperature.get("Status") or {}).get("State")),
        "physicalContext": temperature.get("PhysicalContext"),
        "upperCaution": temperature.get("UpperThresholdNonCritical"),
        "upperCritical": temperature.get("UpperThresholdCritical"),
        "upperFatal": temperature.get("UpperThresholdFatal"),
    }


def simplify_chassis_telemetry(
    chassis_id: str,
    thermal: dict[str, Any],
    power: dict[str, Any],
    timestamp: str,
) -> dict[str, Any]:
    temperatures = [
        simplify_temperature_reading(temperature, default_id=str(index))
        for index, temperature in enumerate(thermal.get("Temperatures") or [])
    ]

    fans = [
        {
            "id": fan.get("MemberId") or str(index),
            "name": fan.get("Name") or fan.get("FanName"),
            "rpm": fan.get("Reading") or fan.get("ReadingRPM"),
            "health": ((fan.get("Status") or {}).get("Health")),
            "state": ((fan.get("Status") or {}).get("State")),
            "physicalContext": fan.get("PhysicalContext"),
        }
        for index, fan in enumerate(thermal.get("Fans") or [])
    ]

    power_controls = [
        {
            "id": control.get("MemberId") or str(index),
            "name": control.get("Name"),
            "consumedWatts": control.get("PowerConsumedWatts"),
            "averageWatts": ((control.get("PowerMetrics") or {}).get("AverageConsumedWatts")),
            "peakWatts": ((control.get("PowerMetrics") or {}).get("MaxConsumedWatts")),
            "capacityWatts": control.get("PowerCapacityWatts"),
            "allocatedWatts": control.get("PowerAllocatedWatts"),
            "health": ((control.get("Status") or {}).get("Health")),
            "state": ((control.get("Status") or {}).get("State")),
        }
        for index, control in enumerate(power.get("PowerControl") or [])
    ]

    power_supplies = [
        {
            "id": supply.get("MemberId") or str(index),
            "name": supply.get("Name"),
            "lastOutputWatts": supply.get("LastPowerOutputWatts"),
            "capacityWatts": supply.get("PowerCapacityWatts"),
            "health": ((supply.get("Status") or {}).get("Health")),
            "state": ((supply.get("Status") or {}).get("State")),
            "model": supply.get("Model"),
            "firmwareVersion": supply.get("FirmwareVersion"),
        }
        for index, supply in enumerate(power.get("PowerSupplies") or [])
    ]

    summary_temperature = next(
        (item["celsius"] for item in temperatures if item["celsius"] is not None),
        None,
    )
    summary_power = next(
        (item["consumedWatts"] for item in power_controls if item["consumedWatts"] is not None),
        None,
    )

    return {
        "chassisId": chassis_id,
        "timestamp": timestamp,
        "summary": {
            "temperatureCelsius": summary_temperature,
            "powerWatts": summary_power,
            "health": _roll_up_health(
                [
                    item["health"] for item in temperatures
                ]
                + [item["health"] for item in fans]
                + [item["health"] for item in power_controls]
                + [item["health"] for item in power_supplies]
            ),
        },
        "temperatures": temperatures,
        "fans": fans,
        "powerControls": power_controls,
        "powerSupplies": power_supplies,
    }


def _roll_up_health(health_values: list[str | None]) -> str | None:
    severity = {"CRITICAL": 3, "WARNING": 2, "OK": 1}
    best = 0
    best_label: str | None = None
    for value in health_values:
        if value is None:
            continue
        score = severity.get(value.upper(), 0)
        if score > best:
            best = score
            best_label = value
    return best_label
