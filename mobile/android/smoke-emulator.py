#!/usr/bin/env python3
"""UI smoke against an explicitly selected Android emulator, never a physical device.

Assumes the debug APK is installed. Outputs screenshots, XML and a result JSON.
The emulator app data is reset before this deterministic smoke run.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = "com.consegvida.app"
ACTIVITY = PACKAGE + "/.MainActivity"
MISSION = "Dê quinze minutos ao que importa"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="build/smoke-artifacts")
    args = parser.parse_args()
    serial = os.environ.get("ANDROID_SERIAL", "")
    if not re.fullmatch(r"emulator-[0-9]+", serial):
        raise SystemExit("ANDROID_SERIAL must explicitly select emulator-NNNN; physical devices are refused.")
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    events: list[str] = []

    def adb(*parts: str, timeout: float = 20, binary: bool = False):
        result = subprocess.run(["adb", "-s", serial, *parts], capture_output=True,
                                text=not binary, timeout=timeout, check=True)
        return result.stdout

    if adb("shell", "getprop", "ro.kernel.qemu").strip() != "1":
        raise SystemExit("Selected target does not identify itself as an emulator.")
    api_level = int(adb("shell", "getprop", "ro.build.version.sdk").strip())
    if api_level >= 33:
        # Emulator-only configuration: exercise the platform gesture callback rather
        # than merely sending KEYCODE_BACK, which has different API 36 behavior.
        gesture_overlay = "com.android.internal.systemui.navbar.gestural"
        if gesture_overlay not in adb("shell", "cmd", "overlay", "list"):
            raise AssertionError("The selected emulator lacks the gesture-navigation overlay required by this smoke.")
        adb("shell", "cmd", "overlay", "enable-exclusive", "--category", gesture_overlay)

    def dump():
        adb("shell", "uiautomator", "dump", "/sdcard/consegvida-smoke-ui.xml")
        xml = adb("exec-out", "cat", "/sdcard/consegvida-smoke-ui.xml")
        return ET.fromstring(xml), xml

    def matching(tree, label: str):
        for node in tree.iter("node"):
            if label.casefold() in ((node.get("text") or "").casefold(), (node.get("content-desc") or "").casefold()):
                bounds = [int(x) for x in re.findall(r"\d+", node.get("bounds", ""))]
                if len(bounds) == 4 and bounds[2] > bounds[0] and bounds[3] > bounds[1]:
                    return node
        return None

    def wait(label: str, timeout: float = 35):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            try:
                tree, xml = dump()
                last = xml
                node = matching(tree, label)
                if node is not None:
                    return node
            except (subprocess.SubprocessError, ET.ParseError) as error:
                last = str(error)
            time.sleep(0.25)
        (output / "timeout.txt").write_text(str(last), encoding="utf-8")
        raise AssertionError(f"UI deadline exceeded waiting for {label!r}")

    def tap_node(node):
        left, top, right, bottom = map(int, re.findall(r"\d+", node.attrib["bounds"]))
        adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))

    def tap(label: str):
        tap_node(wait(label))

    size_text = adb("shell", "wm", "size")
    sizes = re.findall(r"(\d+)x(\d+)", size_text)
    if not sizes:
        raise AssertionError("Cannot determine emulator screen size")
    width, height = map(int, sizes[-1])

    def scroll_to(label: str, attempts: int = 14):
        for _ in range(attempts):
            tree, _ = dump()
            node = matching(tree, label)
            if node is not None:
                return node
            adb("shell", "input", "swipe", str(width // 2), str(height * 78 // 100),
                str(width // 2), str(height * 30 // 100), "320")
        raise AssertionError(f"Could not reveal {label!r} within {attempts} scrolls")

    def capture(name: str):
        _, xml = dump()
        (output / f"{name}.xml").write_text(xml, encoding="utf-8")
        (output / f"{name}.png").write_bytes(adb("exec-out", "screencap", "-p", binary=True))

    def launch():
        adb("shell", "am", "start", "-W", "-n", ACTIVITY)

    try:
        cleared = adb("shell", "pm", "clear", PACKAGE)
        if "Success" not in cleared:
            raise AssertionError("Could not reset isolated emulator application")
        launch()
        wait("Escolher um cuidado")
        capture("01-home")
        events.append("fresh home rendered")

        tap("Missões")
        mental_action = "Ver missão: " + MISSION
        tap_node(scroll_to(mental_action))
        wait("← Voltar às missões")
        if api_level >= 33:
            adb("shell", "input", "swipe", "1", str(height // 2),
                str(width * 3 // 5), str(height // 2), "350")
        else:
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
        wait("Escolha uma missão. Ao terminar, registre o que você fez neste aparelho.")
        events.append("platform back gesture returned from mission to list" if api_level >= 33 else "legacy back returned from mission to list")
        tap_node(scroll_to(mental_action))
        tap_node(scroll_to("Começar esta missão"))
        tap_node(scroll_to("Concluir este cuidado"))
        wait("1 cuidado registrado por você.")
        wait(MISSION)
        capture("02-journey-completed")
        events.append("mental mission started and completed through native controls")

        adb("shell", "am", "force-stop", PACKAGE)
        launch()
        tap("Hoje")
        wait("Escolher um cuidado")
        tap("Jornada")
        wait("1 cuidado registrado por você.")
        wait(MISSION)
        capture("03-journey-after-restart")
        events.append("completion survived force-stop and relaunch")

        tap_node(scroll_to("Apagar meu progresso"))
        wait("Apagar o progresso deste aparelho?")
        tap("Manter meu progresso")
        # Screen may remain scrolled down; switching tab brings the summary into view.
        tap("Hoje")
        tap("Jornada")
        wait("1 cuidado registrado por você.")
        events.append("cancelling reset preserved the completion")

        tap_node(scroll_to("Apagar meu progresso"))
        wait("Apagar o progresso deste aparelho?")
        tap("Apagar progresso")
        wait("Escolher um cuidado")
        tap("Jornada")
        wait("Ainda não há cuidados registrados. Sua jornada pode começar com cinco minutos.")
        capture("04-journey-reset")
        events.append("confirmed reset removed active and completed progress")

        adb("shell", "am", "force-stop", PACKAGE)
        launch()
        tap("Hoje")
        wait("Escolher um cuidado")
        tap("Jornada")
        wait("Ainda não há cuidados registrados. Sua jornada pode começar com cinco minutos.")
        events.append("reset survived relaunch")
        (output / "result.json").write_text(json.dumps({"status": "PASS", "serial": serial,
            "checks": events, "scope": "Android emulator UI; no physical-device or store validation"},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("PASS: " + "; ".join(events))
    except Exception as failure:
        try:
            capture("failure")
            (output / "logcat.txt").write_text(adb("logcat", "-d", "-t", "500"), encoding="utf-8")
        except Exception:
            pass
        (output / "result.json").write_text(json.dumps({"status": "FAIL", "serial": serial,
            "checks_completed": events, "error": str(failure)}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise


if __name__ == "__main__":
    main()
