#!/usr/bin/env python3
"""Render the Connect IQ Store artwork from the native screenshots.

    python3 store-assets/listing/render.py

Reads store-assets/screenshots/*.png (454x454 captures of a Fenix 9 Pro 47 mm,
taken from the simulator at native resolution) and writes, next to this file:

    hero-1440x720.jpg          the cover ("hero") image the Store asks for
    icon-512.png               the Store icon (the watch keeps its own launcher icon)
    screens/N-chapter.jpg      five 1080x1080 images, one chapter of the
                               workflow each (the Store takes five)

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

# The Store takes five images, so each tells one chapter of a workout, in the
# order the athlete lives it: plan the order, train, read the recap, see the
# week, track the trend. Each: an eyebrow (step and chapter), a headline that
# says what it does for the athlete, a one-line subtitle, the watches, and the
# features of that chapter as chips.
#
# Layouts: "duo" = a hero watch and a second one behind it;
#          "trio" = three fanned, the middle one forward;
#          "solo" = one watch, centred;
#          "progress" = two watches and the glance card floating over them.
STORY = [
    ("1-your-order", "01", "Your order", "Your workout.<br><em>Your order.</em>",
     "Station taken? Put it off, train something else, come back with every set intact.",
     "duo", ["02-overview", "01-set-screen"],
     ["Pick any exercise", "Put off & resume", "Swap or add mid-session"]),
    ("2-under-the-bar", "02", "Train", "Built for<br><em>under the bar.</em>",
     "Load, reps, heart rate and both clocks in one look. Rest with the next set ready.",
     "duo-even", ["01-set-screen", "03-rest"],
     ["Live HR zone", "Smart rest", "RPE", "Last time's numbers", "PR alerts"]),
    ("3-the-recap", "03", "Recap", "A recap<br><em>worth reading.</em>",
     "Every session ends with the numbers that matter, measured by your Garmin.",
     "trio", ["05-recap-effort", "04-recap-session", "06-recap-zones"],
     ["Training effect", "Body Battery", "HR zones", "Records"]),
    ("4-every-muscle", "04", "Balance", "See what<br><em>you're skipping.</em>",
     "This week's volume, muscle by muscle, at the end of every workout.",
     "solo", ["07-recap-week"],
     ["10 muscle groups", "82 movements", "Garmin Connect", "Hevy sync"]),
    ("5-progress", "05", "Progress", "Consistency<br><em>you can see.</em>",
     "Your week, month and trend, with your other Garmin activities counted too.",
     "progress", ["08-analytics-week", "09-analytics-trend", "10-glance"],
     ["Week · month · 30 days", "Glance", "Full history"]),
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


def chips(items: list) -> str:
    spans = "".join(
        f'<span style="padding:12px 22px;border-radius:999px;background:rgba(16,22,29,.92);'
        f'border:1px solid #223040;white-space:nowrap">{t}</span>' for t in items)
    return (f'<div style="position:absolute;left:60px;right:60px;bottom:96px;display:flex;'
            f'flex-wrap:wrap;justify-content:center;gap:12px;font-family:\'Inter\';font-size:22px;'
            f'font-weight:600;color:#D7DEE6;z-index:10">{spans}</div>')


def glance_card(img: pathlib.Path, cx: int, cy: int, w: int) -> str:
    h = w * 156 // 376
    return (f'<img src="{data_uri(img)}" style="position:absolute;left:{cx - w // 2}px;top:{cy - h // 2}px;'
            f'width:{w}px;height:{h}px;border-radius:{h // 4}px;z-index:6;'
            f'box-shadow:0 40px 80px rgba(0,0,0,.75),0 0 0 1px rgba(255,255,255,.08),'
            f'0 0 60px rgba(0,146,228,.18)">')


def story_html(step: str, eyebrow: str, title: str, sub: str, layout: str, shots: list, feats: list) -> str:
    w = h = 1080
    s = [SHOTS / f"{n}.png" for n in shots]
    cy = 610
    if layout == "duo":
        art = glow(470, cy, 760) + watch(s[1], 760, cy - 30, 330, 1, 0.55) + watch(s[0], 450, cy, 450, 3)
    elif layout == "duo-even":
        art = (glow(540, cy, 820) + watch(s[0], 350, cy - 12, 410, 3)
               + watch(s[1], 730, cy + 12, 410, 2))
    elif layout == "trio":
        art = (glow(540, cy, 820) + watch(s[0], 275, cy + 20, 310, 1, 0.7)
               + watch(s[2], 805, cy + 20, 310, 1, 0.7) + watch(s[1], 540, cy, 420, 3))
    elif layout == "solo":
        art = glow(540, cy, 820) + watch(s[0], 540, cy, 470, 3)
    else:  # progress: two charts, the glance card over their feet
        art = (glow(540, cy, 820) + watch(s[0], 350, cy - 70, 370, 2)
               + watch(s[1], 730, cy - 70, 370, 2) + glance_card(s[2], 540, cy + 190, 480))
    body = f"""
<style>em {{ font-style: normal; color: {ACCENT}; }}</style>
<div style="position:absolute;left:0;right:0;top:70px;text-align:center;padding:0 80px">
  <div style="font-family:'Inter';font-size:21px;font-weight:700;letter-spacing:4px;color:{ACCENT};text-transform:uppercase">
    <span style="color:#5B6775">{step}</span>&nbsp;&nbsp;{eyebrow}</div>
  <div style="margin-top:18px;font-size:66px;font-weight:700;letter-spacing:-1.8px;line-height:1.04">{title}</div>
  <div style="margin:20px auto 0;max-width:800px;font-family:'Inter';font-size:26px;line-height:1.42;color:#A3AEBC">{sub}</div>
</div>
{art}
{chips(feats)}
<div style="position:absolute;left:0;right:0;bottom:34px;display:flex;justify-content:center;align-items:center;gap:12px;font-size:22px;font-weight:600;color:#6E7A88">
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


# The Store refuses images over 150 KB. A 256-colour PNG fits but bands the
# glow into rings, so each image becomes a JPEG at the best quality that fits
# (4:4:4, so the blue type keeps its edges).
MAX_BYTES = 148_000


def shrink(png: pathlib.Path) -> pathlib.Path:
    jpg = png.with_suffix(".jpg")
    for q in range(95, 59, -1):
        subprocess.run(["magick", str(png), "-quality", str(q), "-sampling-factor", "4:4:4",
                        "-strip", str(jpg)], check=True)
        if jpg.stat().st_size <= MAX_BYTES:
            break
    png.unlink()
    print(f"    -> {jpg.name}, {jpg.stat().st_size // 1000} KB, quality {q}")
    return jpg


def main() -> int:
    chrome = next((c for c in CHROME_CANDIDATES if c and pathlib.Path(c).exists()), None)
    if not chrome:
        print("Needs Google Chrome (or Brave) to render.", file=sys.stderr)
        return 1
    needed = sorted({n for st in STORY for n in st[6]})
    missing = [n for n in needed if not (SHOTS / f"{n}.png").exists()]
    if missing:
        print("Missing screenshots: " + ", ".join(missing), file=sys.stderr)
        return 1
    print("Rendering Store artwork:")
    render(chrome, hero_html(), HERE / "hero-1440x720.png", 1440, 720)
    shrink(HERE / "hero-1440x720.png")
    render(chrome, icon_html(512), HERE / "icon-512.png", 512, 512)
    for old in list(OUT_SCREENS.glob("*.png")) + list(OUT_SCREENS.glob("*.jpg")):
        old.unlink()
    for name, step, eyebrow, title, sub, layout, shots, feats in STORY:
        render(chrome, story_html(step, eyebrow, title, sub, layout, shots, feats),
               OUT_SCREENS / f"{name}.png", 1080, 1080)
        shrink(OUT_SCREENS / f"{name}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
