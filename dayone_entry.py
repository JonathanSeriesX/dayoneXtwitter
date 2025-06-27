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
        attachments: Optional: A list of absolute file paths to attach to the entry.

    Returns:
        True if the command was executed successfully, otherwise False.
    """
    # The base command for creating a new entry, with the text as the primary content.
    # Using a list for the command and its arguments is crucial for security,
    # as it prevents shell injection vulnerabilities by ensuring each argument
    # is treated as a distinct entity, not part of a single shell string.
    command = ["dayone2", "new", text]

    # Append optional arguments based on the provided parameters.
    # Each 'if' block adds the corresponding Day One CLI flag and its value(s).
    if journal:
        # --journal <journal_name>: Specifies the journal to which the entry will be added.
        command.extend(["--journal", journal])

    if tags:
        # --tags <tag1> <tag2> ...: Adds one or more tags to the entry.
        command.append("--tags")
        command.extend(tags)

    if date_time:
        # --date "YYYY-MM-DD HH:MM:SS": Sets the creation date and time of the entry.
        # The datetime object is formatted to match the CLI's expected string format.
        formatted_date = date_time.strftime("%Y-%m-%d %H:%M:%S")
        command.extend(["--date", formatted_date])
        command.extend(["-z", "UTC"])

    if coordinate:
        # --coordinate <latitude> <longitude>: Sets the geographical coordinates for the entry.
        # Latitude and longitude are passed as separate string arguments.
        lat, lon = coordinate
        command.extend(["--coordinate", str(lat), str(lon)])

    if attachments:
        # --attachments <path1> <path2> ...: Attaches one or more files to the entry.
        # Absolute paths to the files are required.
        command.append("--attachments")
        command.extend(attachments)

    # Execute the constructed command using a helper function.
    return _execute_command(command)


def _execute_command(command: List[str]) -> bool:
    """
    A private helper function to execute a command using subprocess.run.

    This function encapsulates the execution logic, error handling, and output capture
    for commands sent to the Day One CLI.

    Args:
        command: The command and its arguments as a list of strings.
                 Example: ["dayone2", "new", "My entry text"]

    Returns:
        True on successful command execution (exit code 0), False otherwise.
    """
    try:
        # subprocess.run is the recommended way to run external commands.
        # It waits for the command to complete and captures its output.
        result = subprocess.run(
            command,
            capture_output=True,  # Captures stdout and stderr.
            text=True,            # Decodes stdout and stderr as text using default encoding.
            check=False           # Prevents subprocess.run from raising CalledProcessError
                                  # for non-zero exit codes. We handle the return code manually.
        )

        # Check the return code to determine if the command was successful.
        if result.returncode == 0:
            # print("Successfully created Day One entry.")
            # The Day One CLI typically outputs the UUID of the new entry on success.
            print(f"Command: {command}")
            print(f"{result.stdout.strip()}")
            return True
        else:
            # If the command failed, print the exit code and any error messages from stderr.
            print(f"Command: {command}")
            print(f"Error executing Day One command. Exit Code: {result.returncode}")
            print(f"Error Details: {result.stderr.strip()}")
            return False

    except FileNotFoundError:
        # This exception is raised if the 'dayone2' command itself is not found.
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
        # Catch any other unexpected errors during command execution.
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return False