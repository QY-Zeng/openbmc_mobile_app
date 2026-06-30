from pydantic import BaseModel


class AlertItem(BaseModel):
    id: int
    sourceKey: str
    chassisId: str
    severity: str
    category: str
    title: str
    message: str
    status: str
    firstSeenAt: str
    lastSeenAt: str
    resolvedAt: str | None = None


class AlertListResponse(BaseModel):
    count: int
    items: list[AlertItem]


class AlertStreamEvent(BaseModel):
    eventType: str
    alert: AlertItem
    emittedAt: str
