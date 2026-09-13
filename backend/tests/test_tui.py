"""Choosing from a list, and what happens when there is nobody to ask.

The picker exists because this tool once acted on the wrong session. So the
cases that matter are the ones where it must *not* ask and must still be right:
a pipe, a cron job, `--yes`.
"""

from __future__ import annotations

import io

import pytest

from repflow_garmin import tui


class TestWhenThereIsNobodyToAsk:
    def test_a_pipe_takes_the_first_item(self, monkeypatch) -> None:
        # Not a prompt into a closed stdin, and not a crash: the first item,
        # which every caller orders newest-first.
        monkeypatch.setattr(tui, "interactive", lambda: False)
        assert tui.choose(["newest", "older"], str) == "newest"

    def test_a_single_item_is_not_a_choice(self, monkeypatch) -> None:
        monkeypatch.setattr(tui, "interactive", lambda: True)
        assert tui.choose(["only"], str) == "only"

    def test_an_empty_list_chooses_nothing(self) -> None:
        assert tui.choose([], str) is None

    def test_confirm_takes_its_default_without_a_terminal(self, monkeypatch) -> None:
        monkeypatch.setattr(tui, "interactive", lambda: False)
        # Writing is the dangerous direction, so the safe default is no.
        assert tui.confirm("Write?", default=False) is False
        assert tui.confirm("Keep going?", default=True) is True


class TestTheNumberedFallback:
    """Terminals that cannot go into raw mode, and CI runners, land here."""

    def test_a_number_picks_that_row(self, monkeypatch, capsys) -> None:
        monkeypatch.setattr("builtins.input", lambda _: "2")
        assert tui._numbered(["a", "b", "c"], str, "Pick") == "b"
        assert "1. a" in capsys.readouterr().out

    def test_q_cancels(self, monkeypatch) -> None:
        monkeypatch.setattr("builtins.input", lambda _: "q")
        assert tui._numbered(["a", "b"], str, "Pick") is None

    def test_an_empty_answer_cancels_rather_than_guessing(self, monkeypatch) -> None:
        monkeypatch.setattr("builtins.input", lambda _: "")
        assert tui._numbered(["a", "b"], str, "Pick") is None

    def test_rubbish_asks_again(self, monkeypatch) -> None:
        answers = iter(["nine", "0", "7", "1"])
        monkeypatch.setattr("builtins.input", lambda _: next(answers))
        # Out of range and non-numeric are both refused, not rounded to
        # something plausible.
        assert tui._numbered(["a", "b"], str, "Pick") == "a"

    def test_a_terminal_that_refuses_raw_mode_falls_back(self, monkeypatch) -> None:
        monkeypatch.setattr(tui, "interactive", lambda: True)
        monkeypatch.setattr(tui, "_arrows", lambda *a: (_ for _ in ()).throw(OSError()))
        monkeypatch.setattr("builtins.input", lambda _: "2")
        assert tui.choose(["a", "b"], str) == "b"


def test_confirm_reads_yes_and_no(monkeypatch) -> None:
    monkeypatch.setattr(tui, "interactive", lambda: True)
    for answer, expected in (("y", True), ("yes", True), ("n", False), ("no", False)):
        monkeypatch.setattr("builtins.input", lambda _, a=answer: a)
        assert tui.confirm("Write?", default=False) is expected

    # Enter alone is the default, whichever way it points.
    monkeypatch.setattr("builtins.input", lambda _: "")
    assert tui.confirm("Write?", default=False) is False
    assert tui.confirm("Write?", default=True) is True
