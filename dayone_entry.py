import subprocess
import sys
from datetime import datetime
from typing import List, Optional, Tuple


def add_post(
        text: str,
        journal: Optional[str] = None,
        tags: Optional[List[str]] = None,
        date_time: Optional[datetime] = None,
        coordinate: Optional[Tuple[float, float]] = None,
        attachments: Optional[List[str]] = None,
) -> bool:
    """
    Creates a new entry in the Day One app using the CLI.

    Args:
        text: The main body text of the journal entry.
        journal: Optional: The name of the journal to add the entry to.
        tags: Optional: A list of tags to apply to the entry.
        date_time: Optional: The specific date and time for the entry.
        coordinate: Optional: A tuple of (latitude, longitude) for the entry's location.

    Returns:
        True if the command was executed successfully, otherwise False.
    """
    # The base command is "new" followed by the entry text.
    # Building a list of arguments is safer than formatting a single string.
    command = ["dayone2", "new", text]

    # Append optional arguments
    if journal:
        command.extend(["--journal", journal])

    if tags:
        command.append("--tags")
        command.extend(tags)

    if date_time:
        # Day One CLI expects a specific format, e.g., "2024-01-15 14:30:00"
        formatted_date = date_time.strftime("%Y-%m-%d %H:%M:%S")
        command.extend(["--date", formatted_date])

    if coordinate:
        # Day One CLI expects latitude then longitude
        lat, lon = coordinate
        command.extend(["--coordinate", str(lat), str(lon)])

    if attachments:
        command.append("--attachments")
        command.extend(attachments)

    return _execute_command(command)


def _execute_command(command: List[str]) -> bool:
    """
    A private helper function to execute a command.

    Args:
        command: The command and its arguments as a list of strings.

    Returns:
        True on success, False on failure.
    """
    try:
        # Using subprocess.run is the modern and recommended approach.
        # capture_output=True prevents command output from printing to the console
        # unless we want it to. text=True decodes stdout/stderr as strings.
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False  # We will check the return code manually
        )

        if result.returncode == 0:
            print("Successfully created Day One entry.")
            # The CLI outputs the UUID of the new entry on success
            print(f"Output: {result.stdout.strip()}")
            return True
        else:
            print(f"Error executing Day One command. Exit Code: {result.returncode}")
            print(f"Error Details: {result.stderr.strip()}")
            return False

    except FileNotFoundError:
        print(
            "Error: Could not find the 'dayone2' command.",
            file=sys.stderr
        )
        print(
            "Please ensure the Day One CLI is installed and in your system's PATH.",
            file=sys.stderr
        )
        return False
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return False