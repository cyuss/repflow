#!/usr/bin/env python3
"""Render the Connect IQ Store artwork from the native screenshots.

    python3 store-assets/listing/render.py

Reads store-assets/screenshots/*.png (454x454 captures of a Fenix 9 Pro 47 mm,
taken from the simulator at native resolution) and writes, next to this file:

    hero-1440x720.png          the cover ("hero") image the Store asks for
    icon-512.png               the Store icon (the watch keeps its own launcher icon)
    screens/NN-name.png        one 1080x1080 marketing image per screenshot

Each image is laid out in HTML and rendered by headless Chrome at exactly its
pixel size, so the typography (Inter, installed locally) and the shadows are
real rather than approximated. The watch around each capture is drawn here — a
generic round case, not Garmin's device artwork.
"""
import base64
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent
SHOTS = ASSETS / "screenshots"
OUT_SCREENS = HERE / "screens"

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
]

ACCENT = "#0092E4"

# One headline per screen: what it does for the athlete, not what it shows.
SCREENS = [
    ("01-set-screen", "Every set, at a glance",
     "Load, reps, heart rate and both clocks — big enough to read under the bar."),
    ("02-overview", "Your workout. Your order.",
     "Station taken? Put it off, train something else, come back with every set intact."),
    ("03-rest", "Rest that knows what's next",
     "Countdown, heart-rate recovery, and the next set already filled in."),
    ("04-recap-session", "The session, summed up",
     "Time, sets against plan, reps and volume — and every record that fell."),
    ("05-recap-effort", "Effort, measured by Garmin",
     "Aerobic training effect, calories, and the Body Battery it cost."),
    ("06-recap-zones", "Time in every zone",
     "Average, peak and recovery heart rate at the end of every session."),
    ("07-recap-week", "Volume by muscle, this week",
     "See what you train — and what you have been skipping."),
    ("08-analytics-week", "Your training, analysed",
     "Week, month and 30 days, RepFlow and Garmin sessions together."),
    ("09-analytics-trend", "Consistency you can see",
     "Sessions per week, from RepFlow and your other Garmin activities."),
]

BASE_CSS = """
@font-face { font-family: "InterX"; src: local("Inter Display"), local("Inter"); }
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: %(w)dpx; height: %(h)dpx; overflow: hidden; }
body {
  background: #05070A;
  color: #F4F7FA;
  font-family: "Inter Display", "Inter", -apple-system, sans-serif;
  -webkit-font-smoothing: antialiased;
  position: relative;
}
.glow {
  position: absolute; border-radius: 50%%; filter: blur(60px);
  background: radial-gradient(circle, rgba(0,146,228,.30) 0%%, rgba(0,146,228,0) 70%%);
}
.watch {
  position: absolute; border-radius: 50%%;
  background:
    radial-gradient(circle at 32%% 22%%, #4A515B 0%%, #23272D 38%%, #121417 70%%, #0A0B0D 100%%);
  box-shadow:
    0 50px 90px rgba(0,0,0,.65),
    0 18px 30px rgba(0,0,0,.45),
    inset 0 2px 1px rgba(255,255,255,.18),
    inset 0 -3px 6px rgba(0,0,0,.6);
}
.watch .bezel {
  position: absolute; border-radius: 50%%; background: #000;
  box-shadow: inset 0 0 0 1px rgba(255,255,255,.07), 0 0 0 1px rgba(0,0,0,.8);
}
.watch img {
  position: absolute; border-radius: 50%%; display: block;
}
.watch .sheen {
  position: absolute; border-radius: 50%%; pointer-events: none;
  background: linear-gradient(155deg, rgba(255,255,255,.10) 0%%, rgba(255,255,255,0) 38%%);
}
"""


def data_uri(path: pathlib.Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def watch(img: pathlib.Path, cx: int, cy: int, d: int, z: int = 1, opacity: float = 1.0) -> str:
    """A round case of outer diameter d around the capture, centred on (cx, cy)."""
    case = d
    bezel = int(d * 0.90)
    screen = int(d * 0.84)
    left, top = cx - case // 2, cy - case // 2
    bo = (case - bezel) // 2
    so = (case - screen) // 2
    return f"""
<div class="watch" style="left:{left}px;top:{top}px;width:{case}px;height:{case}px;z-index:{z};opacity:{opacity}">
  <div class="bezel" style="left:{bo}px;top:{bo}px;width:{bezel}px;height:{bezel}px"></div>
  <img src="{data_uri(img)}" style="left:{so}px;top:{so}px;width:{screen}px;height:{screen}px">
  <div class="sheen" style="left:{so}px;top:{so}px;width:{screen}px;height:{screen}px"></div>
</div>"""


def glow(cx: int, cy: int, d: int) -> str:
    return f'<div class="glow" style="left:{cx - d // 2}px;top:{cy - d // 2}px;width:{d}px;height:{d}px"></div>'


ICON_SVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="%(s)d" height="%(s)d">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#161B22"/>
      <stop offset="1" stop-color="#05070A"/>
    </linearGradient>
    <linearGradient id="arc" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#22C1FF"/>
      <stop offset="1" stop-color="#0072CE"/>
    </linearGradient>
    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#0092E4" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#0092E4" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="512" height="512" rx="%(rx)d" fill="url(#bg)"/>
  <circle cx="256" cy="256" r="230" fill="url(#halo)"/>
  <circle cx="256" cy="256" r="188" fill="none" stroke="#1C232C" stroke-width="20"/>
  <circle cx="256" cy="256" r="188" fill="none" stroke="url(#arc)" stroke-width="20"
          stroke-linecap="round" stroke-dasharray="886 1181" transform="rotate(-90 256 256)"/>
  <g transform="translate(256 256) scale(0.62) translate(-256 -256)" fill="#F4F7FA">
    <rect x="54"  y="210" width="44"  height="92"  rx="15"/>
    <rect x="112" y="160" width="64"  height="192" rx="22"/>
    <rect x="336" y="160" width="64"  height="192" rx="22"/>
    <rect x="414" y="210" width="44"  height="92"  rx="15"/>
    <rect x="164" y="228" width="184" height="56"  rx="19"/>
  </g>
</svg>"""


def icon_svg(size: int, rx: int = 112) -> str:
    return ICON_SVG % {"s": size, "rx": rx}


def hero_html() -> str:
    w, h = 1440, 720
    s = lambda name: SHOTS / f"{name}.png"
    body = f"""
{glow(1040, 360, 760)}
<div style="position:absolute;left:96px;top:0;height:{h}px;width:600px;display:flex;flex-direction:column;justify-content:center">
  <div style="display:flex;align-items:center;gap:22px;margin-bottom:34px">
    {icon_svg(92, 22)}
    <div style="font-size:76px;font-weight:700;letter-spacing:-2px">RepFlow</div>
  </div>
  <div style="font-size:50px;font-weight:700;letter-spacing:-1.2px;line-height:1.08">Your workout.<br><span style="color:{ACCENT}">Your order.</span></div>
  <div style="margin-top:26px;font-size:23px;line-height:1.5;color:#A3AEBC;font-family:'Inter';max-width:520px">
    Strength training for Garmin watches. Skip a busy station, come back to it later, and never lose a set.
  </div>
  <div style="margin-top:34px;display:flex;gap:12px;font-family:'Inter';font-size:17px;font-weight:600;color:#D7DEE6">
    <span style="padding:9px 16px;border-radius:999px;background:#10161D;border:1px solid #1E2731">Garmin Connect</span>
    <span style="padding:9px 16px;border-radius:999px;background:#10161D;border:1px solid #1E2731">Hevy sync</span>
    <span style="padding:9px 16px;border-radius:999px;background:#10161D;border:1px solid #1E2731">Analytics</span>
  </div>
</div>
{watch(s('02-overview'), 815, 430, 320, 1, 0.92)}
{watch(s('04-recap-session'), 1262, 296, 320, 1, 0.92)}
{watch(s('01-set-screen'), 1040, 360, 430, 3)}
"""
    return page(w, h, body)


def screen_html(name: str, title: str, sub: str) -> str:
    w = h = 1080
    body = f"""
{glow(540, 672, 820)}
<div style="position:absolute;left:0;right:0;top:92px;text-align:center;padding:0 90px">
  <div style="font-size:62px;font-weight:700;letter-spacing:-1.6px;line-height:1.08">{title}</div>
  <div style="margin:22px auto 0;max-width:820px;font-family:'Inter';font-size:30px;line-height:1.42;color:#A3AEBC">{sub}</div>
</div>
{watch(SHOTS / f'{name}.png', 540, 672, 580, 2)}
<div style="position:absolute;left:0;right:0;bottom:38px;display:flex;justify-content:center;align-items:center;gap:12px;font-size:22px;font-weight:600;color:#6E7A88">
  {icon_svg(34, 9)}<span>RepFlow</span>
</div>
"""
    return page(w, h, body)


def icon_html(size: int) -> str:
    # The Store crops or rounds its own icons, so the art fills the square.
    return page(size, size, f'<div style="position:absolute;inset:0">{icon_svg(size, 0)}</div>')


def page(w: int, h: int, body: str) -> str:
    css = BASE_CSS % {"w": w, "h": h}
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{css}</style></head><body>{body}</body></html>"


def render(chrome: str, html: str, out: pathlib.Path, w: int, h: int) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "page.html"
        src.write_text(html, encoding="utf-8")
        shot = pathlib.Path(tmp) / "shot.png"
        subprocess.run([
            chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=1", "--default-background-color=00000000",
            f"--window-size={w},{h}", f"--screenshot={shot}", src.as_uri(),
        ], check=True, capture_output=True, timeout=120)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(shot), out)
    print(f"  {out.relative_to(ASSETS.parent)}")


def main() -> int:
    chrome = next((c for c in CHROME_CANDIDATES if c and pathlib.Path(c).exists()), None)
    if not chrome:
        print("Needs Google Chrome (or Brave) to render.", file=sys.stderr)
        return 1
    missing = [n for n, _, _ in SCREENS if not (SHOTS / f"{n}.png").exists()]
    if missing:
        print("Missing screenshots: " + ", ".join(missing), file=sys.stderr)
        return 1
    print("Rendering Store artwork:")
    render(chrome, hero_html(), HERE / "hero-1440x720.png", 1440, 720)
    render(chrome, icon_html(512), HERE / "icon-512.png", 512, 512)
    for name, title, sub in SCREENS:
        render(chrome, screen_html(name, title, sub), OUT_SCREENS / f"{name}.png", 1080, 1080)
    return 0


if __name__ == "__main__":
    sys.exit(main())
