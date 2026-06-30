from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from app.mappers.redfish import simplify_chassis_telemetry
from app.services.alert_rules import build_alert_candidates
from app.services.alert_broker import AlertBroker
from app.services.monitoring_store import MonitoringStore
from app.services.redfish import RedfishService

logger = logging.getLogger(__name__)


class MonitoringService:
    def __init__(
        self,
        *,
        redfish_service: RedfishService,
        store: MonitoringStore,
        alert_broker: AlertBroker,
        poll_interval_seconds: float,
    ) -> None:
        self._redfish_service = redfish_service
        self._store = store
        self._alert_broker = alert_broker
        self._poll_interval_seconds = poll_interval_seconds
        self._stop_event = asyncio.Event()

    async def run_forever(self) -> None:
        logger.info(
            "Monitoring loop started with poll interval %.1fs",
            self._poll_interval_seconds,
        )
        while not self._stop_event.is_set():
            await self.poll_once()
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=self._poll_interval_seconds,
                )
            except asyncio.TimeoutError:
                continue

    async def poll_once(self) -> None:
        try:
            chassis_items = await self._redfish_service.get_chassis_collection()
        except Exception:
            logger.exception("Unable to fetch chassis collection for monitoring")
            return

        tasks = [
            self._poll_chassis(chassis.get("Id") or chassis.get("@odata.id", "").rstrip("/").split("/")[-1])
            for chassis in chassis_items
            if isinstance(chassis, dict)
        ]
        if not tasks:
            return

        await asyncio.gather(*tasks)

    def stop(self) -> None:
        self._stop_event.set()

    async def _poll_chassis(self, chassis_id: str) -> None:
        if not chassis_id:
            return

        try:
            thermal, power = await asyncio.gather(
                self._redfish_service.get_chassis_thermal(chassis_id),
                self._redfish_service.get_chassis_power(chassis_id),
            )
        except Exception:
            logger.exception("Unable to fetch telemetry for chassis %s", chassis_id)
            return

        timestamp = datetime.now(timezone.utc).isoformat()
        telemetry = simplify_chassis_telemetry(
            chassis_id=chassis_id,
            thermal=thermal,
            power=power,
            timestamp=timestamp,
        )
        self._store.save_telemetry_snapshot(telemetry)
        events = self._store.sync_alerts(
            chassis_id=chassis_id,
            candidates=build_alert_candidates(telemetry),
            seen_at=timestamp,
        )
        if events:
            await self._alert_broker.publish_many(
                event.to_payload() for event in events
            )
