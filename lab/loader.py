import json
from pathlib import Path

def load_tool_catalogue():
    """Load raw tool catalogue JSON."""
    catalogue_path = Path(__file__).parent.parent / "data" / "tool_catalogue.json"
    with open(catalogue_path, "r") as f:
        return json.load(f)


# Note: Text-based tool catalog generation functions have been removed.
# Tool catalog is now injected as structured JSON directly from tool_catalogue.json
# into the 'tools' key during data processing. See data_processor.py for details.



