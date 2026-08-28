import json
import os
import sys
import tempfile
import unittest
from unittest import mock


PLUGIN_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PLUGIN_DIR)

import fetch_rankings


def ranking_document(count=20):
    rows = []
    trends = ["aup", "adown", "alevel"]
    for index in range(1, count + 1):
        rows.append(
            '<tr><th class="phr1">{rank}</th>'
            '<td class="phr2"><a title="Based on: Test" href="distro{rank}">'
            'Distro {rank}</a></td>'
            '<td class="phr3" title="Yesterday: 1">{hits}'
            '<img src="images/other/{trend}.png"></td></tr>'.format(
                rank=index,
                hits=2000 - index,
                trend=trends[(index - 1) % len(trends)],
            )
        )
    return "Last 6 months" + "".join(rows) + "Last 3 months"


class ParseRankingsTests(unittest.TestCase):
    def test_parses_top_twenty_rows(self):
        rankings = fetch_rankings.parse_rankings(ranking_document())

        self.assertEqual(len(rankings), 20)
        self.assertEqual(rankings[0]["name"], "Distro 1")
        self.assertEqual(rankings[0]["trend"], "up")
        self.assertEqual(rankings[-1]["rank"], 20)
        self.assertEqual(rankings[-1]["url"], "https://distrowatch.com/distro20")

    def test_rejects_an_incomplete_table(self):
        with self.assertRaisesRegex(ValueError, "incomplete"):
            fetch_rankings.parse_rankings(ranking_document(19))

    def test_rejects_a_missing_six_month_table(self):
        with self.assertRaisesRegex(ValueError, "not found"):
            fetch_rankings.parse_rankings("Last 12 months")

    def test_rejects_encoded_markup_in_a_distribution_name(self):
        document = ranking_document().replace("Distro 1", "&lt;img src=/tmp/payload&gt;")
        with self.assertRaisesRegex(ValueError, "incomplete"):
            fetch_rankings.parse_rankings(document)


class CacheTests(unittest.TestCase):
    def test_successful_fetch_updates_cache(self):
        rankings = fetch_rankings.parse_rankings(ranking_document())
        with tempfile.TemporaryDirectory() as directory:
            cache_path = os.path.join(directory, "rankings.json")
            with mock.patch.object(fetch_rankings, "fetch_rankings", return_value=rankings), mock.patch.object(
                fetch_rankings.time, "time", return_value=1234
            ):
                payload = fetch_rankings.get_payload(cache_path)

            self.assertFalse(payload["stale"])
            self.assertEqual(payload["updatedAt"], 1234)
            with open(cache_path, "r", encoding="utf-8") as cache_file:
                self.assertEqual(json.load(cache_file), payload)

    def test_failed_fetch_returns_cached_rankings(self):
        rankings = fetch_rankings.parse_rankings(ranking_document())
        cached = {"rankings": rankings, "updatedAt": 1234, "stale": False, "error": ""}
        with tempfile.TemporaryDirectory() as directory:
            cache_path = os.path.join(directory, "rankings.json")
            fetch_rankings.write_cache(cache_path, cached)
            with mock.patch.object(fetch_rankings, "fetch_rankings", side_effect=OSError("offline")):
                payload = fetch_rankings.get_payload(cache_path)

        self.assertTrue(payload["stale"])
        self.assertEqual(payload["rankings"], rankings)
        self.assertEqual(payload["error"], "offline")

    def test_cache_read_rejects_a_symlink(self):
        rankings = fetch_rankings.parse_rankings(ranking_document())
        cached = {"rankings": rankings, "updatedAt": 1234, "stale": False, "error": ""}
        with tempfile.TemporaryDirectory() as directory:
            target_path = os.path.join(directory, "target.json")
            cache_path = os.path.join(directory, "rankings.json")
            fetch_rankings.write_cache(target_path, cached)
            os.symlink(target_path, cache_path)

            self.assertIsNone(fetch_rankings.load_cache(cache_path))

    def test_cache_read_rejects_an_oversized_file(self):
        with tempfile.TemporaryDirectory() as directory:
            cache_path = os.path.join(directory, "rankings.json")
            with open(cache_path, "wb") as cache_file:
                cache_file.write(b" " * (fetch_rankings.MAX_CACHE_BYTES + 1))

            self.assertIsNone(fetch_rankings.load_cache(cache_path))

    def test_cache_read_rejects_a_file_owned_by_another_uid(self):
        rankings = fetch_rankings.parse_rankings(ranking_document())
        cached = {"rankings": rankings, "updatedAt": 1234, "stale": False, "error": ""}
        with tempfile.TemporaryDirectory() as directory:
            cache_path = os.path.join(directory, "rankings.json")
            fetch_rankings.write_cache(cache_path, cached)
            with mock.patch.object(fetch_rankings.os, "getuid", return_value=os.getuid() + 1):
                self.assertIsNone(fetch_rankings.load_cache(cache_path))


class UiSafetyTests(unittest.TestCase):
    def test_remote_text_surfaces_are_plain_text(self):
        panel_path = os.path.join(PLUGIN_DIR, "Panel.qml")
        with open(panel_path, "r", encoding="utf-8") as panel_file:
            panel = panel_file.read()

        name_binding = "text: rankingRow.modelData.name\n                                    textFormat: Text.PlainText"
        rank_binding = "text: rankingRow.modelData.rank\n                                    textFormat: Text.PlainText"
        hpd_binding = "text: rankingRow.modelData.hpd\n                                    textFormat: Text.PlainText"
        error_binding = 'text: root.rankings.length > 0 ? "Offline · showing cached rankings" : root.error\n                        textFormat: Text.PlainText'
        self.assertIn(name_binding, panel)
        self.assertIn(rank_binding, panel)
        self.assertIn(hpd_binding, panel)
        self.assertIn(error_binding, panel)
        self.assertNotIn('"#1 " + rankings[0].name', panel)


if __name__ == "__main__":
    unittest.main()
