import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! The exercise-state icon used in the workout overview.
//!
//!   completed    green disc, tick          done
//!   active       amber disc, play          you are on this one now
//!   pending      amber ring, pause bars    you parked it, come back
//!   skipped      grey ring, cross          abandoned for today
//!   not started  thin grey ring            untouched
//!
//! The icon carries the meaning in its **shape**, not its colour. Five coloured
//! dots need a legend; play / pause / tick / cross do not, and they survive
//! being glanced at from a bench at arm's length.
//!
//! Active used to be a plain blue disc. Blue reads as "information" on a Garmin
//! — it is the accent colour the rest of the app uses for labels and values —
//! so it said nothing about state. Amber is the colour of unfinished work here,
//! which makes active and pending one family: **filled + play** is the one in
//! your hands, **hollow + pause** is the one you set aside. That is exactly the
//! distinction this app exists to make.
//!
//! Drawn rather than shipped as bitmaps: five states times six launcher sizes
//! would be thirty PNGs to keep in step, and a circle costs nothing to draw.
//!
//! Shapes also sidestep the font question entirely — the Fenix 6 Pro has no
//! glyph for U+2713 and renders it as a "?" box. See ExerciseStateUtil.
class StateIcon extends WatchUi.Drawable {

    private var _state as ExerciseState;

    public function initialize(state as ExerciseState, size as Number) {
        Drawable.initialize({ :width => size, :height => size });
        _state = state;
    }

    //! A size that suits the running device's menu rows.
    public static function sizeFor(dc as Graphics.Dc) as Number {
        var size = dc.getHeight() / 9;
        return size < 14 ? 14 : size;
    }

    public function draw(dc as Graphics.Dc) as Void {
        // Drawable's geometry is typed as a numeric poly type; the drawing
        // calls want plain Numbers.
        var x = locX.toNumber();
        var y = locY.toNumber();
        var w = width.toNumber();
        var h = height.toNumber();

        // Menu2 anchors the icon area at the very left of the row — locX comes
        // back as 0 — and it does not centre a Drawable inside the area it
        // reserved. So the dot is placed by hand: right of the canvas centre,
        // which puts clear space between it and the bezel without closing the
        // gap to the label.
        // Left of the canvas centre, and not much more than half of it across.
        // Menu2 clips the icon to the column it reserved, which is narrower
        // than the Drawable it was handed: a dot pushed towards the right of
        // the canvas came back with a flat side. Verified in the simulator.
        var cx = x + (w * 44) / 100;
        // A menu row is two lines — name over "1/4  55 kg" — but the icon area
        // is anchored to the first of them, which leaves the dot reading high
        // against the row as a whole. A nudge down centres it on the pair.
        var cy = y + h / 2 + h / 10;
        var r = ((w < h ? w : h) * 28) / 100;
        if (r < 4) {
            return;
        }

        switch (_state) {
            case EX_COMPLETED:
                _disc(dc, cx, cy, r, Theme.colorDone());
                _tick(dc, cx, cy, r);
                break;

            case EX_ACTIVE:
                _disc(dc, cx, cy, r, Theme.colorWarm());
                _play(dc, cx, cy, r);
                break;

            case EX_PENDING:
                _ring(dc, cx, cy, r, Theme.colorPending(), r / 3);
                _pause(dc, cx, cy, r, Theme.colorPending());
                break;

            case EX_SKIPPED:
                _ring(dc, cx, cy, r, Theme.colorFaint(), r / 5);
                _cross(dc, cx, cy, r, Theme.colorFaint());
                break;

            default:
                _ring(dc, cx, cy, r, Theme.colorFaint(), r / 6);
                break;
        }
    }

    private function _disc(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        color as Number
    ) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
    }

    //! A ring drawn inside radius `r`, so a thick pen cannot spill past it.
    private function _ring(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        color as Number,
        pen as Number
    ) as Void {
        var width = pen < 2 ? 2 : pen;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(width);
        dc.drawCircle(cx, cy, r - width / 2);
        dc.setPenWidth(1);
    }

    //! A tick, in the background colour, inside the filled disc.
    private function _tick(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        dc.setColor(Theme.colorBg(), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r / 3 > 2 ? r / 3 : 2);
        dc.drawLine(cx - r / 2, cy, cx - r / 8, cy + r / 2);
        dc.drawLine(cx - r / 8, cy + r / 2, cx + r / 2, cy - r / 2);
        dc.setPenWidth(1);
    }

    //! A play triangle, in the background colour, inside the filled disc.
    //!
    //! Nudged right of centre: a triangle's visual centre of mass sits behind
    //! its apex, so geometric centring makes it look like it is sliding left.
    private function _play(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        var back = cx - (r * 30) / 100;
        var apex = cx + (r * 50) / 100;
        var half = (r * 45) / 100;
        dc.setColor(Theme.colorBg(), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [back, cy - half],
            [apex, cy],
            [back, cy + half]
        ] as Array<[Numeric, Numeric]>);
    }

    //! Two pause bars inside the ring.
    private function _pause(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        color as Number
    ) as Void {
        var barWidth = (r * 22) / 100;
        if (barWidth < 2) {
            barWidth = 2;
        }
        var barHeight = r;
        var gap = barWidth;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - gap / 2 - barWidth, cy - barHeight / 2, barWidth, barHeight);
        dc.fillRectangle(cx + gap / 2, cy - barHeight / 2, barWidth, barHeight);
    }

    //! A cross inside the ring.
    private function _cross(
        dc as Graphics.Dc,
        cx as Number,
        cy as Number,
        r as Number,
        color as Number
    ) as Void {
        var arm = (r * 42) / 100;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r / 4 > 2 ? r / 4 : 2);
        dc.drawLine(cx - arm, cy - arm, cx + arm, cy + arm);
        dc.drawLine(cx - arm, cy + arm, cx + arm, cy - arm);
        dc.setPenWidth(1);
    }
}
