"""Step 6 of the pipeline: hand a finished entry to the Day One CLI.

This is the only module that talks to Day One. add_post() builds the `dayone`
command line, stages the attachments where the sandboxed CLI can read them,
and runs it.
"""

import os
import shlex
import shutil
import subprocess
import sys
from datetime import datetime
from typing import List, Optional, Tuple

# The Day One CLI is sandboxed (com.apple.security.app-sandbox) and can only
# read files inside the app's group container. Attachments passed from anywhere
# else are silently dropped: the entry is created, exit code is 0, but the
# media bytes never arrive and the images stay blank forever. So every
# attachment is staged into this folder first, and cleaned up afterwards.
_STAGING_DIR = os.path.expanduser(
    "~/Library/Group Containers/5U8NS4GX82.dayoneapp2/twixodus-staging"
)


def _stage_attachments(attachments: List[str]) -> List[str]:
    """
    Copies attachments into the Day One group container so the sandboxed CLI
    can read them. Returns the staged paths. Files that can't be copied are
    passed through unstaged (the CLI will then skip their data, as before).
    """
    try:
        os.makedirs(_STAGING_DIR, exist_ok=True)
    except OSError as e:
        print(f"Warning: can't create staging dir {_STAGING_DIR}: {e}", file=sys.stderr)
        return attachments

    staged = []
    for i, path in enumerate(attachments):
        # The index prefix prevents collisions between same-named files.
        target = os.path.join(_STAGING_DIR, f"{i:02d}-{os.path.basename(path)}")
        try:
            shutil.copy2(path, target)
            staged.append(target)
        except OSError as e:
            print(f"Warning: couldn't stage attachment {path}: {e}", file=sys.stderr)
            staged.append(path)
    return staged


def _cleanup_staged(staged: List[str]):
    """Removes staged copies. The CLI copies them into its own PendingMedia
    queue synchronously, so they're disposable as soon as the command returns."""
    for path in staged:
        if path.startswith(_STAGING_DIR):
            try:
                os.remove(path)
            except OSError:
                pass


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

    If creating an entry with attachments fails, it automatically retries
    creating the same entry without the attachments.

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
    # Stage attachments inside the Day One group container — the sandboxed CLI
    # can't read them from anywhere else (see _STAGING_DIR).
    staged = _stage_attachments(attachments) if attachments else None

    try:
        # First attempt: execute the command as constructed.
        success = _execute_command(
            _build_command(text, journal, tags, date_time, coordinate, staged)
        )

        # If the first attempt failed AND we were trying to add attachments,
        # retry the command without the attachments.
        if not success and staged:
            print(
                "Warning: Failed to add entry with attachments. Retrying without them...",
                file=sys.stderr,
            )
            return _execute_command(
                _build_command(text, journal, tags, date_time, coordinate, None)
            )
    finally:
        if staged:
            _cleanup_staged(staged)

    # Return the result of the first attempt if it succeeded or if there were no attachments.
    return success


def _build_command(
    text: str,
    journal: Optional[str],
    tags: Optional[List[str]],
    date_time: Optional[datetime],
    coordinate: Optional[Tuple[float, float]],
    attachments: Optional[List[str]],
) -> List[str]:
    """
    Assembles the Day One CLI invocation.

    Per the CLI documentation, all options must come BEFORE the `new` command:
        dayone --journal J --attachments p1 p2 -- new <text>
    The `--` terminator is required after list-valued options such as
    --attachments and --tags, so the command isn't swallowed as another list
    item; it's harmless otherwise, so it is always included.

    Using a list for the command and its arguments is crucial for security,
    as it prevents shell injection vulnerabilities by ensuring each argument
    is treated as a distinct entity, not part of a single shell string.
    """
    command = ["dayone"]

    if journal:
        # --journal <journal_name>: Specifies the journal to which the entry will be added.
        command.extend(["--journal", journal])

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

    if tags:
        # --tags <tag1> <tag2> ...: Adds one or more tags to the entry.
        command.append("--tags")
        command.extend(tags)

    if attachments:
        # --attachments <path1> <path2> ...: Attaches one or more files to the entry.
        # Absolute paths to the files are required. The CLI supports at most 10.
        command.append("--attachments")
        command.extend(attachments)

    command.extend(["--", "new", text])
    return command


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
        if os.path.exists("tweets_to_debug"):
            # shlex.join quotes each argument, so the printed line can be
            # copy-pasted into a shell verbatim.
            print(f"Executing command: {shlex.join(command)}")
        result = subprocess.run(
            command,
            capture_output=True,  # Captures stdout and stderr.
            text=True,  # Decodes stdout and stderr as text using default encoding.
            check=False,  # Prevents subprocess.run from raising CalledProcessError
            # for non-zero exit codes. We handle the return code manually.
        )

        # Check the return code to determine if the command was successful.
        if result.returncode == 0:
            # The Day One CLI typically outputs the UUID of the new entry on success.
            print(f"Success: {result.stdout.strip()}")
            return True
        else:
            # If the command failed, print the exit code and any error messages from stderr.
            print(
                f"Error executing Day One command. Exit Code: {result.returncode}",
                file=sys.stderr,
            )
            print(f"Error Details: {result.stderr.strip()}", file=sys.stderr)
            return False

    except FileNotFoundError:
        # This exception is raised if the 'dayone2' command itself is not found.
        print("Error: Could not find the 'dayone2' command.", file=sys.stderr)
        print(
            "Please ensure the Day One CLI is installed and in your system's PATH.",
            file=sys.stderr,
        )
        return False
    except Exception as e:
        # Catch any other unexpected errors during command execution.
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return False
