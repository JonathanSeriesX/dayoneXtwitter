import unittest
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from thread_selection import (
    partition_threads_by_date,
    count_tweets_before,
    format_reimport_report,
    parse_date_range,
)

START_DATE = datetime(2025, 6, 30)
END_DATE = datetime(2025, 12, 5)


def make_thread(*dates, first_id="100"):
    """Builds a minimal thread out of creation dates."""
    return [
        {
            "tweet": {
                "id_str": first_id if i == 0 else f"{first_id}{i}",
                "created_at": date,
            }
        }
        for i, date in enumerate(dates)
    ]


class TestPartitionThreadsByDate(unittest.TestCase):

    def test_thread_started_in_range_is_in_range(self):
        thread = make_thread(datetime(2025, 7, 1), datetime(2025, 7, 2))
        in_range, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(in_range, [thread])
        self.assertEqual(extended, [])

    def test_older_thread_extended_in_range_is_extended(self):
        thread = make_thread(
            datetime(2025, 1, 15),  # started long before the range
            datetime(2025, 1, 15),
            datetime(2025, 8, 20),  # extended within the range
        )
        in_range, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(in_range, [])
        self.assertEqual(extended, [thread])

    def test_older_thread_not_extended_is_dropped(self):
        thread = make_thread(datetime(2025, 1, 15), datetime(2025, 2, 1))
        in_range, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(in_range, [])
        self.assertEqual(extended, [])

    def test_older_thread_extended_only_after_range_is_dropped(self):
        thread = make_thread(datetime(2025, 1, 15), datetime(2026, 3, 1))
        in_range, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(in_range, [])
        self.assertEqual(extended, [])

    def test_thread_started_after_range_is_dropped(self):
        thread = make_thread(datetime(2026, 1, 5), datetime(2026, 1, 6))
        in_range, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(in_range, [])
        self.assertEqual(extended, [])

    def test_thread_started_in_range_and_continued_past_it_stays_in_range(self):
        thread = make_thread(datetime(2025, 12, 1), datetime(2026, 2, 1))
        in_range, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(in_range, [thread])
        self.assertEqual(extended, [])

    def test_threads_without_dates_are_skipped(self):
        in_range, extended = partition_threads_by_date(
            [[{"tweet": {"id_str": "1"}}], []], START_DATE, END_DATE
        )
        self.assertEqual(in_range, [])
        self.assertEqual(extended, [])

    def test_timezone_aware_dates_are_comparable(self):
        from datetime import timezone

        thread = make_thread(
            datetime(2025, 1, 15, tzinfo=timezone.utc),
            datetime(2025, 8, 20, tzinfo=timezone.utc),
        )
        _, extended = partition_threads_by_date([thread], START_DATE, END_DATE)
        self.assertEqual(extended, [thread])


class TestCountTweetsBefore(unittest.TestCase):

    def test_counts_only_tweets_before_start(self):
        thread = make_thread(
            datetime(2025, 1, 15),
            datetime(2025, 1, 16),
            datetime(2025, 8, 20),
            datetime(2025, 9, 1),
        )
        self.assertEqual(count_tweets_before(thread, START_DATE), 2)


class TestFormatReimportReport(unittest.TestCase):

    def _entry(self, **overrides):
        entry = {
            "tweet_id": "1234567890",
            "title": "Wrote a thread about Formula 1",
            "category": "Wrote a thread",
            "journal": "Tweets",
            "date": datetime(2025, 1, 15, 14, 3),
            "tweet_count": 7,
            "previous_tweet_count": 2,
        }
        entry.update(overrides)
        return entry

    def test_report_mentions_counts_dates_and_link(self):
        report = format_reimport_report(
            [self._entry()], START_DATE, username="JonathanSeriesX"
        )
        self.assertIn("1 thread(s) were re-imported in full", report)
        self.assertIn("Wrote a thread about Formula 1", report)
        self.assertIn("15 January 2025, 14:03", report)
        self.assertIn("≈2 tweets", report)
        self.assertIn("30 June 2025", report)
        self.assertIn("New entry: 7 tweets", report)
        self.assertIn(
            "https://twitter.com/JonathanSeriesX/status/1234567890", report
        )

    def test_report_falls_back_to_anonymous_tweet_url(self):
        report = format_reimport_report([self._entry()], START_DATE, username=None)
        self.assertIn("https://twitter.com/i/web/status/1234567890", report)

    def test_report_handles_unknown_previous_count(self):
        report = format_reimport_report(
            [self._entry(previous_tweet_count=0)], START_DATE
        )
        self.assertIn("previously imported copy", report)


class TestParseDateRange(unittest.TestCase):

    def test_parses_config_format(self):
        start, end = parse_date_range("30 June 2025", "5 December 2025")
        self.assertEqual(start, datetime(2025, 6, 30))
        self.assertEqual(end, datetime(2025, 12, 5))

    def test_raises_on_bad_format(self):
        with self.assertRaises(ValueError):
            parse_date_range("2025-06-30", "5 December 2025")


if __name__ == "__main__":
    unittest.main()
