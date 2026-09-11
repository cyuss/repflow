import Toybox.Lang;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Math;

//! Shared drawing constants and helpers.
//!
//! RepFlow draws its screens in code rather than from XML layouts: the screens
//! are simple, and code scales cleanly from a 240x240 Fenix 6 Pro to a 454x454
//! Fenix 8 without a per-device layout file for each one.
module Theme {

    const COLOR_BG = Graphics.COLOR_BLACK;
    const COLOR_TEXT = Graphics.COLOR_WHITE;
    const COLOR_DIM = Graphics.COLOR_LT_GRAY;
    const COLOR_ACCENT = 0x00A8E8;      // RepFlow blue
    const COLOR_DONE = Graphics.COLOR_GREEN;
    const COLOR_PENDING = Graphics.COLOR_ORANGE;
    const COLOR_SKIPPED = Graphics.COLOR_DK_GRAY;

    //! Colour used for an exercise state in lists and headers.
    public function stateColor(state as ExerciseState) as Number {
        switch (state) {
            case EX_COMPLETED:
                return COLOR_DONE;
            case EX_ACTIVE:
                return COLOR_ACCENT;
            case EX_PENDING:
                return COLOR_PENDING;
            case EX_SKIPPED:
                return COLOR_SKIPPED;
            default:
                return COLOR_DIM;
        }
    }

    public function clear(dc as Graphics.Dc) as Void {
        dc.setColor(COLOR_TEXT, COLOR_BG);
        dc.clear();
    }

    //! Draw text centred horizontally, shrinking through a font ladder until it
    //! fits the available width. Avoids per-device layout tweaking.
    public function drawFitted(
        dc as Graphics.Dc,
        y as Number,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        color as Number,
        maxWidth as Number
    ) as Number {
        var w = dc.getWidth();
        var font = fonts[fonts.size() - 1];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                font = fonts[i];
                break;
            }
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        return dc.getFontHeight(font);
    }

    //! Format a weight without a pointless trailing ".0": 55 / 57.5
    public function formatWeight(weight as Float) as String {
        // Work in tenths as integers: Math.floor/round return Double, and
        // comparing those against a Float trips the type checker.
        var tenths = Math.round(weight * 10.0).toNumber();
        var whole = tenths / 10;
        var frac = tenths % 10;
        if (frac == 0) {
            return whole.toString();
        }
        return whole.toString() + "." + frac.toString();
    }

    //! "1:05:23" or "42:07"
    public function formatDuration(seconds as Number) as String {
        var h = seconds / 3600;
        var m = (seconds % 3600) / 60;
        var s = seconds % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }
}
