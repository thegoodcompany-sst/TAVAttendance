from __future__ import annotations

import json
import os
import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class StationConfig:
    supabase_url: str
    supabase_anon_key: str
    station_email: str
    station_password: str
    http_host: str = "127.0.0.1"
    http_port: int = 8765
    debounce_seconds: float = 2.0


def load_config(path: str | os.PathLike[str] | None = None) -> StationConfig:
    env_path = os.environ.get("TAVA_STATION_CONFIG")
    config_path = Path(path or env_path or "station/config.toml")
    if not config_path.is_file():
        raise FileNotFoundError(
            f"Station config not found at {config_path}. "
            "Copy station/config.example.toml to station/config.toml."
        )
    with config_path.open("rb") as handle:
        data = tomllib.load(handle)

    station_password = str(
        data.get("station_password") or os.environ.get("TAVA_STATION_PASSWORD") or ""
    )
    if not station_password:
        raise ValueError(
            "station_password is empty. Set it in config.toml or TAVA_STATION_PASSWORD."
        )

    return StationConfig(
        supabase_url=str(data["supabase_url"]).rstrip("/"),
        supabase_anon_key=str(data["supabase_anon_key"]),
        station_email=str(data["station_email"]),
        station_password=station_password,
        http_host=str(data.get("http_host") or "127.0.0.1"),
        http_port=int(data.get("http_port") or 8765),
        debounce_seconds=float(data.get("debounce_seconds") or 2.0),
    )
