import asyncio
from typing import Any

import httpx
from fastapi import HTTPException


class RedfishService:
    def __init__(self, base_url: str, timeout_seconds: float) -> None:
        self._base_url = base_url
        self._timeout_seconds = timeout_seconds

    async def get_systems(self) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            collection = await self._get_json(client, "/redfish/v1/Systems")
            member_paths = self._extract_member_paths(collection)
            return await self._fetch_many(client, member_paths)

    async def get_system(self, system_id: str) -> dict[str, Any]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            system = await self._get_json(client, f"/redfish/v1/Systems/{system_id}")
            await self._populate_system_reset_action_info(client, system)
            return system

    async def reset_system_power(
        self,
        system_id: str,
        reset_type: str,
    ) -> dict[str, Any]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            system = await self._get_json(client, f"/redfish/v1/Systems/{system_id}")
            await self._populate_system_reset_action_info(client, system)
            reset_action = ((system.get("Actions") or {}).get("#ComputerSystem.Reset")) or {}
            allowable_values = self._extract_reset_allowable_values(reset_action)
            if allowable_values and reset_type not in allowable_values:
                allowed = ", ".join(allowable_values)
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Unsupported reset type '{reset_type}' for system {system_id}. "
                        f"Allowed values: {allowed}"
                    ),
                )

            target = reset_action.get("target") or (
                f"/redfish/v1/Systems/{system_id}/Actions/ComputerSystem.Reset"
            )
            response_payload = await self._post_json(
                client,
                target,
                {"ResetType": reset_type},
            )

            message = None
            power_state = None
            if isinstance(response_payload, dict):
                message = response_payload.get("Message") or response_payload.get("message")
                power_state = response_payload.get("PowerState")

            if power_state is None:
                latest_system = await self._get_json(
                    client,
                    f"/redfish/v1/Systems/{system_id}",
                )
                power_state = latest_system.get("PowerState")

            return {
                "systemId": system_id,
                "resetType": reset_type,
                "powerState": power_state,
                "message": message or f"Requested {reset_type} for {system_id}",
            }

    async def get_chassis_collection(self) -> list[dict[str, Any]]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            collection = await self._get_json(client, "/redfish/v1/Chassis")
            member_paths = self._extract_member_paths(collection)
            return await self._fetch_many(client, member_paths)

    async def get_chassis(self, chassis_id: str) -> dict[str, Any]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            return await self._get_json(client, f"/redfish/v1/Chassis/{chassis_id}")

    async def get_chassis_thermal(self, chassis_id: str) -> dict[str, Any]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            return await self._get_json(
                client,
                f"/redfish/v1/Chassis/{chassis_id}/Thermal",
            )

    async def get_chassis_power(self, chassis_id: str) -> dict[str, Any]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            return await self._get_json(
                client,
                f"/redfish/v1/Chassis/{chassis_id}/Power",
            )

    async def update_chassis_temperature_thresholds(
        self,
        *,
        chassis_id: str,
        temperature_id: str,
        upper_caution: float | None = None,
        upper_critical: float | None = None,
        upper_fatal: float | None = None,
    ) -> dict[str, Any]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            timeout=self._timeout_seconds,
        ) as client:
            thermal = await self._get_json(
                client,
                f"/redfish/v1/Chassis/{chassis_id}/Thermal",
            )
            temperatures = list(thermal.get("Temperatures") or [])

            matched_index = None
            for index, temperature in enumerate(temperatures):
                if not isinstance(temperature, dict):
                    continue
                current_id = temperature.get("MemberId") or str(index)
                if current_id == temperature_id:
                    matched_index = index
                    break

            if matched_index is None:
                raise HTTPException(
                    status_code=404,
                    detail=(
                        f"Temperature sensor '{temperature_id}' was not found "
                        f"under chassis {chassis_id}"
                    ),
                )

            updated_temperature = dict(temperatures[matched_index])
            if upper_caution is not None:
                updated_temperature["UpperThresholdNonCritical"] = upper_caution
            if upper_critical is not None:
                updated_temperature["UpperThresholdCritical"] = upper_critical
            if upper_fatal is not None:
                updated_temperature["UpperThresholdFatal"] = upper_fatal

            self._validate_temperature_threshold_order(
                temperature=updated_temperature,
                chassis_id=chassis_id,
                temperature_id=temperature_id,
            )
            temperatures[matched_index] = updated_temperature

            updated_thermal = await self._patch_json(
                client,
                f"/redfish/v1/Chassis/{chassis_id}/Thermal",
                {"Temperatures": temperatures},
            )
            updated_temperatures = (
                (updated_thermal or {}).get("Temperatures") or temperatures
            )

            for index, temperature in enumerate(updated_temperatures):
                if not isinstance(temperature, dict):
                    continue
                current_id = temperature.get("MemberId") or str(index)
                if current_id == temperature_id:
                    return temperature

            return updated_temperature

    @staticmethod
    def _validate_temperature_threshold_order(
        *,
        temperature: dict[str, Any],
        chassis_id: str,
        temperature_id: str,
    ) -> None:
        upper_caution = temperature.get("UpperThresholdNonCritical")
        upper_critical = temperature.get("UpperThresholdCritical")
        upper_fatal = temperature.get("UpperThresholdFatal")

        if (
            upper_caution is not None
            and upper_critical is not None
            and upper_caution > upper_critical
        ):
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Invalid threshold order for temperature '{temperature_id}' on "
                    f"{chassis_id}: upperCaution cannot be greater than upperCritical."
                ),
            )

        if (
            upper_critical is not None
            and upper_fatal is not None
            and upper_critical > upper_fatal
        ):
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Invalid threshold order for temperature '{temperature_id}' on "
                    f"{chassis_id}: upperCritical cannot be greater than upperFatal."
                ),
            )

        if (
            upper_caution is not None
            and upper_fatal is not None
            and upper_caution > upper_fatal
        ):
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Invalid threshold order for temperature '{temperature_id}' on "
                    f"{chassis_id}: upperCaution cannot be greater than upperFatal."
                ),
            )

    async def _fetch_many(
        self,
        client: httpx.AsyncClient,
        paths: list[str],
    ) -> list[dict[str, Any]]:
        if not paths:
            return []
        tasks = [self._get_json(client, path) for path in paths]
        return await asyncio.gather(*tasks)

    async def _get_json(
        self,
        client: httpx.AsyncClient,
        path: str,
    ) -> dict[str, Any]:
        try:
            response = await client.get(path)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 404:
                raise HTTPException(
                    status_code=404,
                    detail=f"Redfish resource not found: {path}",
                ) from exc
            raise HTTPException(
                status_code=502,
                detail=f"Redfish service returned {exc.response.status_code} for {path}",
            ) from exc
        except httpx.RequestError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Unable to reach Redfish service at {self._base_url}",
            ) from exc

        try:
            return response.json()
        except ValueError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Redfish service returned invalid JSON for {path}",
            ) from exc

    async def _populate_system_reset_action_info(
        self,
        client: httpx.AsyncClient,
        system: dict[str, Any],
    ) -> None:
        reset_action = ((system.get("Actions") or {}).get("#ComputerSystem.Reset")) or {}
        if self._extract_reset_allowable_values(reset_action):
            return

        action_info_path = reset_action.get("@Redfish.ActionInfo")
        if not isinstance(action_info_path, str) or not action_info_path:
            return

        try:
            action_info = await self._get_json(client, action_info_path)
        except HTTPException:
            return

        allowable_values = self._extract_allowable_values_from_action_info(action_info)
        if allowable_values:
            reset_action["ResetType@Redfish.AllowableValues"] = allowable_values

    async def _post_json(
        self,
        client: httpx.AsyncClient,
        path: str,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        try:
            response = await client.post(path, json=payload)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            detail = self._extract_error_detail(exc.response)
            if exc.response.status_code == 400:
                raise HTTPException(
                    status_code=400,
                    detail=detail or f"Redfish service rejected POST {path}",
                ) from exc
            if exc.response.status_code == 404:
                raise HTTPException(
                    status_code=404,
                    detail=f"Redfish resource not found: {path}",
                ) from exc
            raise HTTPException(
                status_code=502,
                detail=detail or f"Redfish service returned {exc.response.status_code} for {path}",
            ) from exc
        except httpx.RequestError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Unable to reach Redfish service at {self._base_url}",
            ) from exc

        if response.status_code == 204 or not response.content:
            return None

        try:
            return response.json()
        except ValueError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Redfish service returned invalid JSON for {path}",
            ) from exc

    async def _patch_json(
        self,
        client: httpx.AsyncClient,
        path: str,
        payload: dict[str, Any],
    ) -> dict[str, Any] | None:
        try:
            response = await client.patch(path, json=payload)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            detail = self._extract_error_detail(exc.response)
            if exc.response.status_code in (400, 405):
                raise HTTPException(
                    status_code=400,
                    detail=detail or f"Redfish service rejected PATCH {path}",
                ) from exc
            if exc.response.status_code == 404:
                raise HTTPException(
                    status_code=404,
                    detail=f"Redfish resource not found: {path}",
                ) from exc
            raise HTTPException(
                status_code=502,
                detail=detail or f"Redfish service returned {exc.response.status_code} for {path}",
            ) from exc
        except httpx.RequestError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Unable to reach Redfish service at {self._base_url}",
            ) from exc

        if response.status_code == 204 or not response.content:
            return None

        try:
            return response.json()
        except ValueError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Redfish service returned invalid JSON for {path}",
            ) from exc

    @staticmethod
    def _extract_member_paths(collection: dict[str, Any]) -> list[str]:
        members = collection.get("Members") or []
        return [
            member.get("@odata.id")
            for member in members
            if isinstance(member, dict) and member.get("@odata.id")
        ]

    @staticmethod
    def _extract_reset_allowable_values(reset_action: dict[str, Any]) -> list[str]:
        allowable_values = (
            reset_action.get("ResetType@Redfish.AllowableValues")
            or reset_action.get("ResetType@DMTF.AllowableValues")
            or []
        )
        return [value for value in allowable_values if isinstance(value, str)]

    @staticmethod
    def _extract_allowable_values_from_action_info(
        action_info: dict[str, Any],
    ) -> list[str]:
        parameters = action_info.get("Parameters") or []
        for parameter in parameters:
            if not isinstance(parameter, dict):
                continue
            if parameter.get("Name") != "ResetType":
                continue
            allowable_values = parameter.get("AllowableValues") or []
            return [value for value in allowable_values if isinstance(value, str)]
        return []

    @staticmethod
    def _extract_error_detail(response: httpx.Response) -> str | None:
        try:
            payload = response.json()
        except ValueError:
            text = response.text.strip()
            return text or None

        if isinstance(payload, dict):
            detail = payload.get("detail") or payload.get("error")
            if isinstance(detail, str):
                return detail
        return None
