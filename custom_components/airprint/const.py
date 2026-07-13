import re

DOMAIN = "airprint"
DEFAULT_PORT = 8099
UPDATE_INTERVAL = 60
SUPERVISOR = "http://supervisor"
SUBENTRY = "printer"
DEVICE_NAME = "Printer"

ICONS = ["🖨️", "📠", "📄", "📁", "☁️", "🏢", "🏠"]
DEFAULT_ICON = "🖨️"


def device_id(device: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", device).strip("_")


def device_name(device: str) -> str:
    if device.startswith("dnssd://"):
        return device.removeprefix("dnssd://").split("._", 1)[0] or DEVICE_NAME
    if "://" in device:
        return device.split("://", 1)[1].strip("/") or DEVICE_NAME
    return device or DEVICE_NAME
