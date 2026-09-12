import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

//! The exercise-state icon used in the workout overview.
//!
//!   completed    filled green disc with a tick
//!   active       filled accent disc
//!   pending      thick amber ring, deliberately open — work left to do
//!   skipped      grey ring struck through
//!   not started  thin grey ring
//!
//! Drawn rather than shipped as bitmaps: five states times six launcher sizes
//! would be thirty PNGs to keep in step, and a circle costs nothing to draw.
//!
//! It replaces the ASCII markers the list used to prefix its labels with. Those
//! were themselves a fix for Unicode glyphs rendering as "?" boxes on the Fenix
//! 6 Pro — see ExerciseStateUtil. Shapes sidestep the font question entirely.
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

        var cx = x + w / 2;
        var cy = y + h / 2;
        var r = (w < h ? w : h) / 2 - 1;
        if (r < 3) {
            return;
        }

        switch (_state) {
            case EX_COMPLETED:
                dc.setColor(Theme.COLOR_DONE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r);
                _drawTick(dc, cx, cy, r);
                break;

            case EX_ACTIVE:
                dc.setColor(Theme.COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, r);
                break;

            case EX_PENDING:
                dc.setPenWidth(r / 2 > 2 ? r / 2 : 2);
                dc.setColor(Theme.COLOR_PENDING, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(cx, cy, r - r / 4);
                dc.setPenWidth(1);
                break;

            case EX_SKIPPED:
                dc.setPenWidth(2);
                dc.setColor(Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(cx, cy, r);
                dc.drawLine(cx - r / 2, cy + r / 2, cx + r / 2, cy - r / 2);
                dc.setPenWidth(1);
                break;

            default:
                dc.setPenWidth(2);
                dc.setColor(Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(cx, cy, r);
                dc.setPenWidth(1);
                break;
        }
    }

    //! A tick, in the background colour, inside the filled disc.
    private function _drawTick(dc as Graphics.Dc, cx as Number, cy as Number, r as Number) as Void {
        dc.setColor(Theme.COLOR_BG, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r / 3 > 2 ? r / 3 : 2);
        dc.drawLine(cx - r / 2, cy, cx - r / 8, cy + r / 2);
        dc.drawLine(cx - r / 8, cy + r / 2, cx + r / 2, cy - r / 2);
        dc.setPenWidth(1);
    }
}
