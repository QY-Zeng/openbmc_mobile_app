import asyncio
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, Request, WebSocket, WebSocketDisconnect
from app.services.telemetry_override import TelemetryOverrideStore



from app.core.config import settings
from app.mappers.redfish import (
    simplify_chassis_detail,
    simplify_chassis_telemetry,
    simplify_chassis_summary,
    simplify_temperature_reading,
    simplify_system_detail,
    simplify_system_summary,
)
from app.schemas.alerts import AlertListResponse
from app.schemas.redfish import (
    ChassisDetail,
    ChassisListResponse,
    ChassisSummary,
    SystemDetail,
    SystemListResponse,
    SystemPowerResetRequest,
    SystemPowerResetResponse,
    SystemSummary,
)
from app.schemas.script_jobs import (
    ScriptJobListResponse,
    ScriptJobResponse,
    ScriptJobSubmitRequest,
)
from app.schemas.telemetry import (
    ChassisTelemetryCurrentResponse,
    ChassisTelemetryHistoryResponse,
    TemperatureReading,
    TemperatureThresholdsUpdateRequest,
)
from app.services.monitoring_store import MonitoringStore
from app.services.redfish import RedfishService
from app.services.script_jobs import ScriptJobService

router = APIRouter()


def get_redfish_service() -> RedfishService:
    return RedfishService(
        base_url=settings.redfish_base_url,
        timeout_seconds=settings.redfish_timeout_seconds,
    )


def get_monitoring_store(request: Request) -> MonitoringStore:
    return request.app.state.monitoring_store


def get_script_job_service(request: Request) -> ScriptJobService:
    return request.app.state.script_job_service

"""
async def fetch_chassis_telemetry_payload(
    *,
    chassis_id: str,
    redfish_service: RedfishService,
    override_store: TelemetryOverrideStore | None = None, 
) -> dict[str, object]:
    thermal, power = await asyncio.gather(
        redfish_service.get_chassis_thermal(chassis_id),
        redfish_service.get_chassis_power(chassis_id),
    )
    return simplify_chassis_telemetry(
        chassis_id=chassis_id,
        thermal=thermal,
        power=power,
        timestamp=datetime.now(timezone.utc).isoformat(),
    )
"""


# NEW ADD
async def fetch_chassis_telemetry_payload(
    *,
    chassis_id: str,
    redfish_service: RedfishService,
    override_store: TelemetryOverrideStore | None = None,
) -> dict[str, object]:

    thermal, power = await asyncio.gather(
        redfish_service.get_chassis_thermal(chassis_id),
        redfish_service.get_chassis_power(chassis_id),
    )

    # App Override（只修改回傳資料，不修改 Emulator）
    if override_store is not None:
        override = override_store.get(chassis_id)

        temperatures = thermal.get("Temperatures") or []

        print("========== Temperature List ==========")

        for i, t in enumerate(temperatures):
            print(
                i,
                t.get("MemberId"),
                t.get("Name"),
                t.get("ReadingCelsius"),
            )





        # CPU1 Temperature (Sensor 0)
        if override.cpu1_temp is not None and len(temperatures) > 0:
            temperatures[0]["ReadingCelsius"] = override.cpu1_temp
            temperatures[0]["ReadingCelcius"] = override.cpu1_temp

        # CPU1 Temperature (Sensor 1)
        if override.cpu2_temp is not None and len(temperatures) > 0:
            temperatures[1]["ReadingCelsius"] = override.cpu2_temp
            temperatures[1]["ReadingCelcius"] = override.cpu2_temp

        # Intake Temperature (Sensor 2)
        if override.intake_temp is not None and len(temperatures) > 2:
            temperatures[2]["ReadingCelsius"] = override.intake_temp
            temperatures[2]["ReadingCelcius"] = override.intake_temp

        fans = thermal.get("Fans") or []

        # Fan 1
        if override.fan1_rpm is not None and len(fans) > 0:
            fans[0]["ReadingRPM"] = override.fan1_rpm
            fans[0]["Reading"] = override.fan1_rpm

        # Fan 2
        if override.fan2_rpm is not None and len(fans) > 1:
            fans[1]["ReadingRPM"] = override.fan2_rpm
            fans[1]["Reading"] = override.fan2_rpm

        power_controls = power.get("PowerControl") or []

        # Power
        if override.power_watts is not None and len(power_controls) > 0:
            control = power_controls[0]

            control["PowerConsumedWatts"] = override.power_watts

            metrics = control.setdefault("PowerMetrics", {})
            metrics["AverageConsumedWatts"] = override.power_watts
            metrics["MinConsumedWatts"] = override.power_watts
            metrics["MaxConsumedWatts"] = override.power_watts

    return simplify_chassis_telemetry(
        chassis_id=chassis_id,
        thermal=thermal,
        power=power,
        timestamp=datetime.now(timezone.utc).isoformat(),
    )





@router.get("/", tags=["meta"])
def read_root() -> dict[str, str]:
    return {"message": "NCKU Redfish server is running"}


@router.get("/health", tags=["meta"])
def read_health() -> dict[str, str]:
    return {"status": "ok"}


@router.post(
    "/api/python-jobs",
    response_model=ScriptJobResponse,
    tags=["python-jobs"],
)
async def submit_python_job(
    payload: ScriptJobSubmitRequest,
    script_job_service: ScriptJobService = Depends(get_script_job_service),
) -> ScriptJobResponse:
    job = script_job_service.submit_job(
        script_name=payload.scriptName,
        source_code=payload.sourceCode,
        input_json=payload.inputJson,
    )
    return ScriptJobResponse.model_validate(job)


@router.get(
    "/api/python-jobs",
    response_model=ScriptJobListResponse,
    tags=["python-jobs"],
)
async def list_python_jobs(
    limit: int = Query(default=20, ge=1, le=100),
    script_job_service: ScriptJobService = Depends(get_script_job_service),
) -> ScriptJobListResponse:
    items = [
        ScriptJobResponse.model_validate(item)
        for item in script_job_service.list_jobs(limit)
    ]
    return ScriptJobListResponse(count=len(items), items=items)


@router.get(
    "/api/python-jobs/{job_id}",
    response_model=ScriptJobResponse,
    tags=["python-jobs"],
)
async def get_python_job(
    job_id: str,
    script_job_service: ScriptJobService = Depends(get_script_job_service),
) -> ScriptJobResponse:
    job = script_job_service.get_job(job_id)
    return ScriptJobResponse.model_validate(job)


@router.get("/api/systems", response_model=SystemListResponse, tags=["systems"])
async def list_systems(
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> SystemListResponse:
    systems = await redfish_service.get_systems()
    items = [SystemSummary.model_validate(simplify_system_summary(system)) for system in systems]
    return SystemListResponse(count=len(items), items=items)


@router.get(
    "/api/systems/{system_id}",
    response_model=SystemDetail,
    tags=["systems"],
)
async def get_system(
    system_id: str,
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> SystemDetail:
    system = await redfish_service.get_system(system_id)
    return SystemDetail.model_validate(simplify_system_detail(system))


@router.post(
    "/api/systems/{system_id}/power/reset",
    response_model=SystemPowerResetResponse,
    tags=["systems"],
)
async def reset_system_power(
    system_id: str,
    request: SystemPowerResetRequest,
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> SystemPowerResetResponse:
    payload = await redfish_service.reset_system_power(
        system_id=system_id,
        reset_type=request.resetType,
    )
    return SystemPowerResetResponse.model_validate(payload)


@router.get("/api/chassis", response_model=ChassisListResponse, tags=["chassis"])
async def list_chassis(
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> ChassisListResponse:
    chassis_items = await redfish_service.get_chassis_collection()
    items = [
        ChassisSummary.model_validate(simplify_chassis_summary(chassis))
        for chassis in chassis_items
    ]
    return ChassisListResponse(count=len(items), items=items)


@router.get(
    "/api/chassis/{chassis_id}",
    response_model=ChassisDetail,
    tags=["chassis"],
)
async def get_chassis(
    chassis_id: str,
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> ChassisDetail:
    chassis = await redfish_service.get_chassis(chassis_id)
    return ChassisDetail.model_validate(simplify_chassis_detail(chassis))

"""
@router.get(
    "/api/chassis/{chassis_id}/telemetry/current",
    response_model=ChassisTelemetryCurrentResponse,
    tags=["telemetry"],
)
async def get_chassis_telemetry(
    chassis_id: str,
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> ChassisTelemetryCurrentResponse:
    payload = await fetch_chassis_telemetry_payload(
        chassis_id=chassis_id,
        redfish_service=redfish_service,
    )
    return ChassisTelemetryCurrentResponse.model_validate(payload)
"""


# NEW ADD

print("Telemetry Override Route Loaded")


def get_telemetry_override_store(
    request: Request,
) -> TelemetryOverrideStore:
    return request.app.state.telemetry_override_store


from app.schemas.telemetry_override import (
    TelemetryOverrideUpdateRequest,
    TelemetryOverrideResponse,
)


@router.patch(
    "/api/chassis/{chassis_id}/override",
    response_model=TelemetryOverrideResponse,
    tags=["telemetry"],
)
async def update_telemetry_override(
    chassis_id: str,
    payload: TelemetryOverrideUpdateRequest,
    override_store: TelemetryOverrideStore = Depends(
        get_telemetry_override_store
    ),
):
    item = override_store.update(
        chassis_id,
        cpu1_temp=payload.cpu1Temp,
        cpu2_temp=payload.cpu2Temp,
        intake_temp=payload.intakeTemp,
        fan1_rpm=payload.fan1Rpm,
        fan2_rpm=payload.fan2Rpm,
        power_watts=payload.powerWatts,
    )

    return TelemetryOverrideResponse(
        cpu1Temp=item.cpu1_temp,
        cpu2Temp=item.cpu2_temp,
        intakeTemp=item.intake_temp,
        fan1Rpm=item.fan1_rpm,
        fan2Rpm=item.fan2_rpm,
        powerWatts=item.power_watts,
    )



# NEW ADD
@router.get(
    "/api/chassis/{chassis_id}/telemetry/current",
    response_model=ChassisTelemetryCurrentResponse,
    tags=["telemetry"],
)
async def get_chassis_telemetry(
    chassis_id: str,
    redfish_service: RedfishService = Depends(get_redfish_service),
    override_store: TelemetryOverrideStore = Depends(
        get_telemetry_override_store
    ),
) -> ChassisTelemetryCurrentResponse:

    payload = await fetch_chassis_telemetry_payload(
        chassis_id=chassis_id,
        redfish_service=redfish_service,
        override_store=override_store,
    )

    return ChassisTelemetryCurrentResponse.model_validate(payload)



async def _apply_temperature_threshold_update(
    chassis_id: str,
    temperature_id: str,
    payload: TemperatureThresholdsUpdateRequest,
    request: Request,
    redfish_service: RedfishService,
) -> TemperatureReading:
    temperature = await redfish_service.update_chassis_temperature_thresholds(
        chassis_id=chassis_id,
        temperature_id=temperature_id,
        upper_caution=payload.upperCaution,
        upper_critical=payload.upperCritical,
        upper_fatal=payload.upperFatal,
    )

    monitoring_service = getattr(request.app.state, "monitoring_service", None)
    if monitoring_service is not None:
        await monitoring_service.poll_once()

    return TemperatureReading.model_validate(
        simplify_temperature_reading(temperature, default_id=temperature_id)
    )


@router.patch(
    "/api/chassis/{chassis_id}/temperatures/{temperature_id}/thresholds",
    response_model=TemperatureReading,
    tags=["telemetry"],
)
async def update_temperature_thresholds(
    chassis_id: str,
    temperature_id: str,
    payload: TemperatureThresholdsUpdateRequest,
    request: Request,
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> TemperatureReading:
    return await _apply_temperature_threshold_update(
        chassis_id=chassis_id,
        temperature_id=temperature_id,
        payload=payload,
        request=request,
        redfish_service=redfish_service,
    )


@router.patch(
    "/api/chassis/{chassis_id}/temperatures/{temperature_id}/warning-threshold",
    response_model=TemperatureReading,
    tags=["telemetry"],
)
async def update_temperature_warning_threshold(
    chassis_id: str,
    temperature_id: str,
    payload: TemperatureThresholdsUpdateRequest,
    request: Request,
    redfish_service: RedfishService = Depends(get_redfish_service),
) -> TemperatureReading:
    return await _apply_temperature_threshold_update(
        chassis_id=chassis_id,
        temperature_id=temperature_id,
        payload=payload,
        request=request,
        redfish_service=redfish_service,
    )


@router.websocket("/ws/chassis/{chassis_id}/telemetry")
async def stream_chassis_telemetry(
    websocket: WebSocket,
    chassis_id: str,
) -> None:
    await websocket.accept()
    redfish_service = get_redfish_service()
    override_store = websocket.app.state.telemetry_override_store

    try:
        while True:
            override = override_store.get(chassis_id)
            print("CPU1 Override   =", override.cpu1_temp)
            print("CPU2 Override   =", override.cpu2_temp)
            print("Intake Override =", override.intake_temp)

            
            payload = await fetch_chassis_telemetry_payload(
                chassis_id=chassis_id,
                redfish_service=redfish_service,
                override_store=override_store,
                
            )
            telemetry = ChassisTelemetryCurrentResponse.model_validate(payload)
            await websocket.send_json(telemetry.model_dump(mode="json"))
            await asyncio.sleep(settings.websocket_telemetry_interval_seconds)
    except WebSocketDisconnect:
        return
    except Exception:
        await websocket.close(code=1011, reason="Telemetry stream failed")


@router.websocket("/ws/alerts")
async def stream_alerts(
    websocket: WebSocket,
) -> None:
    await websocket.accept()
    alert_broker = websocket.app.state.alert_broker
    queue = await alert_broker.subscribe()

    try:
        while True:
            event = await queue.get()
            await websocket.send_json(event)
    except WebSocketDisconnect:
        return
    except Exception:
        await websocket.close(code=1011, reason="Alert stream failed")
    finally:
        await alert_broker.unsubscribe(queue)


@router.get(
    "/api/chassis/{chassis_id}/telemetry/history",
    response_model=ChassisTelemetryHistoryResponse,
    tags=["telemetry"],
)
def get_chassis_telemetry_history(
    chassis_id: str,
    limit: int = Query(default=60, ge=1, le=1000),
    monitoring_store: MonitoringStore = Depends(get_monitoring_store),
) -> ChassisTelemetryHistoryResponse:
    items = [
        ChassisTelemetryCurrentResponse.model_validate(item)
        for item in monitoring_store.list_telemetry_history(chassis_id, limit)
    ]
    return ChassisTelemetryHistoryResponse(count=len(items), items=items)


@router.get("/api/alerts", response_model=AlertListResponse, tags=["alerts"])
def list_alerts(
    limit: int = Query(default=100, ge=1, le=500),
    status: str | None = Query(default=None, pattern="^(open|resolved)$"),
    monitoring_store: MonitoringStore = Depends(get_monitoring_store),
) -> AlertListResponse:
    items = monitoring_store.list_alerts(limit=limit, status=status)
    return AlertListResponse(count=len(items), items=items)



@router.delete(
    "/api/chassis/{chassis_id}/override",
    tags=["telemetry"],
)
async def clear_telemetry_override(
    chassis_id: str,
    override_store: TelemetryOverrideStore = Depends(
        get_telemetry_override_store
    ),
):
    override_store._data.pop(chassis_id, None)
    return {"status": "cleared"}
