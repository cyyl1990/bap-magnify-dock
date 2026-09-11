#!/usr/bin/env python3
"""Relay com.canonical.Unity.LauncherEntry badge updates as JSON lines.

Apps such as Telegram, Thunderbird, Discord and Slack announce unread counts
and progress on the session bus with this signal. The dock reads one JSON
object per line: {"app": "telegramdesktop", "count": 3, "visible": true,
"urgent": false, "progress": 0.0, "progressVisible": false}.
"""
import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402


def emit(app_uri, props):
    key = str(app_uri)
    if key.startswith("application://"):
        key = key[len("application://"):]
    if key.endswith(".desktop"):
        key = key[: -len(".desktop")]
    payload = {
        "app": key.lower(),
        "count": int(props.get("count", 0) or 0),
        "visible": bool(props.get("count-visible", False)),
        "urgent": bool(props.get("urgent", False)),
        "progress": float(props.get("progress", 0.0) or 0.0),
        "progressVisible": bool(props.get("progress-visible", False)),
    }
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def on_update(_conn, _sender, _path, _iface, _signal, params):
    try:
        app_uri, props = params.unpack()
        emit(app_uri, props or {})
    except Exception:  # keep relaying on malformed signals
        pass


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    bus.signal_subscribe(
        None,
        "com.canonical.Unity.LauncherEntry",
        "Update",
        None,
        None,
        Gio.DBusSignalFlags.NONE,
        on_update,
    )
    sys.stdout.write(json.dumps({"ready": True}) + "\n")
    sys.stdout.flush()
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
