"""Choosing from a list in a terminal, with the arrow keys.

Every command here acts on one activity out of several, and "it picked the
wrong one" has already happened once — the listing endpoint is documented as
newest-first and is not. Guessing and then printing the guess is not the same as
being asked.

So when there is a choice and a terminal to make it in, the choice is offered.
Where there is no terminal — a cron job, a pipe, `--yes` — the first item wins
and the caller says which one it took.
"""

from __future__ import annotations

import sys
from collections.abc import Sequence
from typing import TypeVar

T = TypeVar("T")

#: How many rows to show at once. A watch owner has a few dozen activities and
#: a terminal has a few dozen lines; showing all of them scrolls the prompt off
#: the screen, which is the one thing a picker must not do.
WINDOW = 10


def interactive() -> bool:
    """Is there a person at a keyboard to ask?"""
    return sys.stdin.isatty() and sys.stdout.isatty()


def choose(
    items: Sequence[T],
    render: "callable[[T], str]",
    title: str = "Choose one",
    hint: str = "up/down to move, Enter to choose, q to cancel",
) -> T | None:
    """Pick one of `items`. None means the person cancelled.

    Arrow keys where the terminal allows it, a numbered prompt where it does
    not — some terminals, and every CI runner, cannot be put into raw mode, and
    a picker that crashes there would be worse than no picker.
    """
    if not items:
        return None
    if len(items) == 1:
        return items[0]
    if not interactive():
        return items[0]

    try:
        return _arrows(items, render, title, hint)
    except (ImportError, OSError, ValueError):
        return _numbered(items, render, title)


def _numbered(items: Sequence[T], render, title: str) -> T | None:
    print(f"\n{title}:\n")
    for index, item in enumerate(items, start=1):
        print(f"  {index:>2}. {render(item)}")
    while True:
        answer = input(f"\nNumber [1-{len(items)}], or q to cancel: ").strip().lower()
        if answer in {"q", "quit", ""}:
            return None
        if answer.isdigit() and 1 <= int(answer) <= len(items):
            return items[int(answer) - 1]
        print("  Not one of those.")


def _arrows(items: Sequence[T], render, title: str, hint: str) -> T | None:
    import termios
    import tty

    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    cursor = 0
    drawn = 0

    def paint() -> int:
        # A window that follows the cursor, so a long list scrolls rather than
        # filling the screen.
        first = max(0, min(cursor - WINDOW // 2, len(items) - WINDOW))
        if len(items) <= WINDOW:
            first = 0
        last = min(first + WINDOW, len(items))

        lines = [f"\r\n  {title}   \x1b[2m{hint}\x1b[0m\r\n"]
        if first > 0:
            lines.append(f"    \x1b[2m... {first} more above\x1b[0m\r\n")
        for index in range(first, last):
            mark = "\x1b[7m >" if index == cursor else "  "
            end = "\x1b[0m" if index == cursor else ""
            lines.append(f"{mark} {render(items[index])} {end}\r\n")
        if last < len(items):
            lines.append(f"    \x1b[2m... {len(items) - last} more below\x1b[0m\r\n")
        sys.stdout.write("".join(lines))
        sys.stdout.flush()
        return len(lines)

    def erase(count: int) -> None:
        if count:
            sys.stdout.write(f"\x1b[{count}A\x1b[J")
            sys.stdout.flush()

    try:
        # cbreak, not raw: Ctrl-C stays a Ctrl-C, so the picker cannot trap
        # someone in a list.
        tty.setcbreak(fd)
        # Hide the cursor while the list is redrawing under it.
        sys.stdout.write("\x1b[?25l")
        while True:
            erase(drawn)
            drawn = paint()
            key = sys.stdin.read(1)
            if key == "\x1b":
                # An escape on its own is a cancel; followed by "[A"/"[B" it is
                # an arrow. Reading the rest only when it is there is what keeps
                # a bare Escape from blocking.
                rest = sys.stdin.read(2) if _pending(fd) else ""
                if rest == "[A":
                    cursor = (cursor - 1) % len(items)
                elif rest == "[B":
                    cursor = (cursor + 1) % len(items)
                elif rest == "":
                    return None
            elif key in {"k", "p"}:
                cursor = (cursor - 1) % len(items)
            elif key in {"j", "n"}:
                cursor = (cursor + 1) % len(items)
            elif key in {"\r", "\n"}:
                return items[cursor]
            elif key in {"q", "\x03", "\x04"}:
                return None
    finally:
        erase(drawn)
        sys.stdout.write("\x1b[?25h")
        sys.stdout.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


def _pending(fd: int) -> bool:
    """Is there more of an escape sequence already waiting?"""
    import select

    ready, _, _ = select.select([fd], [], [], 0.05)
    return bool(ready)


def confirm(question: str, default: bool = False) -> bool:
    """A yes/no that reads the same everywhere, and defaults to the safe answer."""
    if not interactive():
        return default
    suffix = "[Y/n]" if default else "[y/N]"
    answer = input(f"{question} {suffix} ").strip().lower()
    if not answer:
        return default
    return answer in {"y", "yes"}
