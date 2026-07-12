import re

DOMAIN = "airprint"
DEFAULT_PORT = 8099
UPDATE_INTERVAL = 60
SUPERVISOR = "http://supervisor"
SUBENTRY = "printer"
DEVICE_NAME = "Printer"

EMOJI = ["🖨️", "📠", "📄", "📁", "☁️", "🏢", "🏠"]
DEFAULT_EMOJI = "🖨️"


def device_id(device: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", device).strip("_")
