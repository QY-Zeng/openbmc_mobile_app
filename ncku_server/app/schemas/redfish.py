from pydantic import BaseModel, Field


class StatusInfo(BaseModel):
    state: str | None = None
    health: str | None = None
    healthRollup: str | None = None


class SystemBootInfo(BaseModel):
    overrideEnabled: str | None = None
    overrideTarget: str | None = None
    overrideMode: str | None = None


class SystemLinks(BaseModel):
    biosUri: str | None = None
    processorsUri: str | None = None
    memoryUri: str | None = None
    ethernetInterfacesUri: str | None = None
    chassisUris: list[str] = Field(default_factory=list)


class SystemResetAction(BaseModel):
    target: str | None = None
    allowableValues: list[str] = Field(default_factory=list)


class SystemActions(BaseModel):
    reset: SystemResetAction = Field(default_factory=SystemResetAction)


class SystemSummary(BaseModel):
    id: str
    name: str | None = None
    hostName: str | None = None
    manufacturer: str | None = None
    model: str | None = None
    systemType: str | None = None
    serialNumber: str | None = None
    powerState: str | None = None
    indicatorLed: str | None = None
    status: StatusInfo = Field(default_factory=StatusInfo)
    processorCount: int | None = None
    processorModel: str | None = None
    memoryGiB: float | None = None
    redfishUri: str | None = None


class SystemDetail(SystemSummary):
    assetTag: str | None = None
    description: str | None = None
    biosVersion: str | None = None
    lastResetTime: str | None = None
    boot: SystemBootInfo = Field(default_factory=SystemBootInfo)
    links: SystemLinks = Field(default_factory=SystemLinks)
    actions: SystemActions = Field(default_factory=SystemActions)


class SystemPowerResetRequest(BaseModel):
    resetType: str


class SystemPowerResetResponse(BaseModel):
    systemId: str
    resetType: str
    powerState: str | None = None
    message: str | None = None


class SystemListResponse(BaseModel):
    count: int
    items: list[SystemSummary]


class ChassisSummary(BaseModel):
    id: str
    name: str | None = None
    chassisType: str | None = None
    manufacturer: str | None = None
    model: str | None = None
    serialNumber: str | None = None
    powerState: str | None = None
    indicatorLed: str | None = None
    status: StatusInfo = Field(default_factory=StatusInfo)
    thermalUri: str | None = None
    powerUri: str | None = None
    sensorsUri: str | None = None
    environmentMetricsUri: str | None = None
    computerSystemIds: list[str] = Field(default_factory=list)
    redfishUri: str | None = None


class ChassisDetail(ChassisSummary):
    assetTag: str | None = None
    heightMm: float | None = None
    widthMm: float | None = None
    depthMm: float | None = None
    weightKg: float | None = None
    rack: str | None = None
    row: str | None = None
    managedByUris: list[str] = Field(default_factory=list)
    managerUris: list[str] = Field(default_factory=list)


class ChassisListResponse(BaseModel):
    count: int
    items: list[ChassisSummary]
