import glob
import os
import re
import subprocess
from datetime import datetime

import functions

# Paths to Day One CLI on macOS
DAYONE_PATH = "/usr/local/bin/dayone2"


# Journals
REPLY_JOURNAL = "Twitter Replies Test"
TWEET_JOURNAL = "Tweets Test"


class DayOneEntryCreator:
    @staticmethod
    def __create_entry(
        content,
        date,
        journal_name,
        title=None,
        tags=None,
        photos=None,
        location=None,
    ):
        """
        Helper function to create a Day One entry with options for title, tags, photos, location, and custom UUID.

        Parameters:
            content (str): The main content of the entry.
            date (datetime): The date of the entry.
            journal_name (str): The name of the journal to add the entry to.
            title (str, optional): Title for the entry (first line of content).
            tags (List of str, optional): Tags to categorize the entry.
            photos (list of str, optional): File paths to photos to attach.
            location (tuple, optional): Location as (latitude, longitude).
        """

        # Construct the base command
        dayone_cmd = [
            DAYONE_PATH,
            "--isoDate=" + date.isoformat().replace("+00:00", "Z"),
            "--journal",
            journal_name,
        ]

        # Prepend the title to the content if provided
        if title:
            content = f"{title}\n\n{content}"

        # Add tags if provided
        if tags:
            dayone_cmd.extend(["--tag", *tags])

        # Attach photos if provided
        if photos:
            dayone_cmd.extend(["-p", *photos, "--"])

        # Add location if provided
        if location and len(location) == 2:
            latitude, longitude = location
            dayone_cmd.extend(["--coordinate", f"{latitude},{longitude}"])

        dayone_cmd.extend(["new", content])

        # Execute the command and handle errors
        try:
            print(dayone_cmd)
            subprocess.run(dayone_cmd, check=True)
            print(f"Added following entry to {journal_name} journal")
            # print(content + "\n" + "_______")
        except subprocess.CalledProcessError as e:
            print(f"Error adding entry from {date}: {e}")

    @staticmethod
    def create_reply(tweet):
        """Formats and adds a single tweet as a Day One entry in the specified journal."""
        tweet_content = tweet["tweet"].get("full_text", "")
        timestamp = tweet["tweet"].get("created_at", "")
        tweet_date = datetime.strptime(timestamp, "%a %b %d %H:%M:%S %z %Y")

        mentions = re.findall(r"@\w+", tweet_content)
        if len(mentions) > 1:
            title = (
                "A conversation with users "
                + ", ".join(mentions[:-1])
                + f" and {mentions[-1]}"
            )
        else:
            title = "A conversation with user " + mentions[0]

        clean_content = re.sub(r"@\w+\s*", "", tweet_content).strip()

        # Use helper to create the entry
        DayOneEntryCreator.__create_entry(
            content=clean_content,
            date=tweet_date,
            journal_name=REPLY_JOURNAL,
            title=title,
            photos=None,
            # TODO pass photos too
        )

    @staticmethod
    def create_thread(thread):
        """Combines tweets in a thread and creates a single Day One entry."""
        combined_text = "\n\n".join(
            f"{tweet['tweet']['full_text']}" for tweet in thread
        )
        first_tweet_date = datetime.strptime(
            thread[0]["tweet"]["created_at"], "%a %b %d %H:%M:%S %z %Y"
        )

        # Use helper to create the entry
        DayOneEntryCreator.__create_entry(
            content=combined_text,
            date=first_tweet_date,
            journal_name=TWEET_JOURNAL,
            title="A thread",
            photos=None,
            # TODO pass photos too
        )

    def find_media_files(tweet_id, media_directory="archive/data/tweets_media"):
        """Finds all media files associated with a given tweet ID."""
        # Construct the pattern to match files that start with tweet_id
        pattern = os.path.join(media_directory, f"{tweet_id}*")

        # Find all matching files for both .jpg and .png extensions
        files = glob.glob(pattern)

        return files
