import re

DOMAIN = "airprint"
DEFAULT_PORT = 8099
UPDATE_INTERVAL = 60
SUPERVISOR = "http://supervisor"
SUBENTRY = "printer"

EMOJI = ["🖨️", "📠", "📄", "📁", "☁️", "🏢", "🏠"]
DEFAULT_EMOJI = "🖨️"


def queue_id(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_")
