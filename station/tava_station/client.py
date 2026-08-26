from __future__ import annotations

from typing import Any

import httpx


class StationClient:
    """GoTrue + PostgREST client for the arrival-station account only."""

    def __init__(self, url: str, anon_key: str) -> None:
        self._url = url.rstrip("/")
        self._anon_key = anon_key
        self._access_token: str | None = None
        self._user_id: str | None = None

    @property
    def user_id(self) -> str | None:
        return self._user_id

    def sign_in(self, email: str, password: str) -> str:
        response = httpx.post(
            f"{self._url}/auth/v1/token",
            params={"grant_type": "password"},
            headers={
                "apikey": self._anon_key,
                "Content-Type": "application/json",
            },
            json={"email": email, "password": password},
            timeout=20.0,
        )
        response.raise_for_status()
        payload = response.json()
        self._access_token = payload["access_token"]
        self._user_id = payload.get("user", {}).get("id")
        return self._user_id or ""

    def tap(self, chip_uid: str) -> dict[str, Any]:
        if not self._access_token:
            raise RuntimeError("Station is not signed in.")
        response = httpx.post(
            f"{self._url}/rest/v1/rpc/arrival_station_tap",
            headers={
                "apikey": self._anon_key,
                "Authorization": f"Bearer {self._access_token}",
                "Content-Type": "application/json",
            },
            json={"p_chip_uid": chip_uid},
            timeout=20.0,
        )
        if response.status_code >= 400:
            detail = response.text
            raise RuntimeError(f"Tap failed ({response.status_code}): {detail}")
        payload = response.json()
        if not isinstance(payload, dict):
            raise RuntimeError("Tap returned an unexpected payload.")
        return payload
