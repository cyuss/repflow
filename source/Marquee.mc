import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Timer;
import Toybox.System;

//! Text too long for its line, scrolled back and forth so all of it is read.
//!
//! "Bulgarian Split Squat" and "Romanian Deadlift" do not fit the width of a
//! 260 px round screen at a readable size, and until now they were simply shrunk
//! until they did. Past a point that stops being a name and becomes a smudge.
//!
//! **The name keeps its size; the line moves instead.** Shrinking was the old
//! answer and it is the one the athlete complained about: at arm's length, a
//! name reduced until it fits is a name you cannot read at all. So the first
//! font in the ladder is the one used, and if the text does not fit at that
//! size it scrolls rather than shrinking.
//!
//! A name that fits is still drawn still. Most are: on a 260 px screen almost
//! every movement in the catalogue fits, and the handful that do not are
//! exactly the ones worth moving — "Bulgarian Split Squat", "Single-Leg Calf
//! Raise".
//!
//! It pauses at each end. A marquee that loops without stopping is one you have
//! to wait for; one that rests on the beginning and the end lets you read either
//! half without waiting at all.
//!
//! **Cost.** Scrolling needs its own frames — the app's own tick is 1 Hz, which
//! would step rather than scroll. So a timer runs at 10 fps, and only while
//! something on screen is actually overflowing: every view calls `endFrame()`
//! after drawing, and the timer stops the moment a frame goes by with nothing
//! to move. A workout of short names never starts it at all.
module Marquee {

    //! 10 fps. Enough for legible motion, cheap enough for the slowest target.
    const FRAME_MS = 100;
    //! Rest at each end, in milliseconds.
    const PAUSE_MS = 1400;
    //! Milliseconds per pixel of travel — about 45 px a second.
    const MS_PER_PIXEL = 22;

    var _frames as MarqueeFrames = new MarqueeFrames();
    var _timer as Timer.Timer? = null;
    var _running as Boolean = false;
    var _neededThisFrame as Boolean = false;

    //! A heading that should use the space it has: the ladder is walked for the
    //! largest font that fits, exactly as `Theme.drawFitted` does, and the text
    //! only scrolls when even the smallest will not do.
    //!
    //! For a hero — the workout name on the picker, the recap's header — this
    //! is right: those lines have room, and a name that fills it reads better
    //! than one at a fixed size with space around it. For a line of fixed
    //! height in a band, `draw` is right instead.
    public function drawFitted(
        dc as Graphics.Dc,
        top as Number,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        color as Number,
        maxWidth as Number
    ) as Number {
        var font = Theme.pickFont(dc, text, fonts, maxWidth);
        return _draw(dc, top, text, font, color, maxWidth);
    }

    //! Draw `text` at the ladder's largest size, scrolling when it does not
    //! fit. Returns the y immediately below it.
    public function draw(
        dc as Graphics.Dc,
        top as Number,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        color as Number,
        maxWidth as Number
    ) as Number {
        // The largest font in the ladder, always. Width is no longer a reason
        // to go smaller — it is a reason to scroll.
        var font = fonts.size() > 0 ? fonts[0] : Graphics.FONT_XTINY;
        return _draw(dc, top, text, font, color, maxWidth);
    }

    //! Scroll `text` inside a window whose left edge is given, not derived.
    //!
    //! A list is read down its left edge, so its rows are left-aligned and the
    //! window they scroll in starts where the text starts. `draw` centres the
    //! window instead, which is right for a heading and wrong for a row.
    public function drawAt(
        dc as Graphics.Dc,
        left as Number,
        top as Number,
        text as String,
        fonts as Array<Graphics.FontDefinition>,
        color as Number,
        maxWidth as Number
    ) as Number {
        var font = fonts.size() > 0 ? fonts[0] : Graphics.FONT_XTINY;
        return _drawIn(dc, left, top, text, font, color, maxWidth, false);
    }

    function _draw(
        dc as Graphics.Dc,
        top as Number,
        text as String,
        font as Graphics.FontDefinition,
        color as Number,
        maxWidth as Number
    ) as Number {
        return _drawIn(dc, (dc.getWidth() - maxWidth) / 2, top, text, font, color,
            maxWidth, true);
    }

    //! `centred` only decides where still text sits. Text that overflows is
    //! always drawn from the window's left edge, because that is where reading
    //! starts and the scroll has to begin at the beginning.
    function _drawIn(
        dc as Graphics.Dc,
        left as Number,
        top as Number,
        text as String,
        font as Graphics.FontDefinition,
        color as Number,
        maxWidth as Number,
        centred as Boolean
    ) as Number {
        var height = dc.getFontHeight(font);
        var width = dc.getTextWidthInPixels(text, font);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (width <= maxWidth) {
            if (centred) {
                dc.drawText(left + maxWidth / 2, top, font, text,
                    Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                dc.drawText(left, top, font, text, Graphics.TEXT_JUSTIFY_LEFT);
            }
            return top + height;
        }

        var offset = _offset(width - maxWidth);
        _neededThisFrame = true;
        _ensureRunning();

        // Without clipping the overhang would paint over whatever sits beside
        // it, so a device that cannot clip gets the still, truncated text it
        // had before rather than a mess.
        if (dc has :setClip) {
            dc.setClip(left, top, maxWidth, height);
            dc.drawText(left - offset, top, font, text, Graphics.TEXT_JUSTIFY_LEFT);
            dc.clearClip();
        } else {
            dc.drawText(left, top, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        }
        return top + height;
    }

    //! How far along the travel we are, pausing at both ends.
    function _offset(overflow as Number) as Number {
        return offsetAt(System.getTimer(), overflow);
    }

    //! The same, with the clock passed in. Separate so the arithmetic — which
    //! is the whole of this module worth getting wrong — can be walked through
    //! a full cycle by a test rather than sampled at one instant.
    public function offsetAt(millis as Number, overflow as Number) as Number {
        return offsetPaced(millis, overflow, MS_PER_PIXEL, PAUSE_MS);
    }

    //! The same travel, at a pace the caller chooses.
    //!
    //! A line of text and a list of rows want different speeds. Text comes back
    //! round and you catch the word you missed; a list you are reading *down*,
    //! and a row that slides away mid-word is a row you have to wait a whole
    //! cycle for. Slower, and a longer rest at the top where reading starts.
    public function offsetPaced(
        millis as Number,
        overflow as Number,
        msPerPixel as Number,
        pauseMs as Number
    ) as Number {
        if (overflow <= 0) {
            return 0;
        }
        var travel = overflow * msPerPixel;
        var period = (pauseMs + travel) * 2;
        var t = millis % period;

        if (t < pauseMs) {
            return 0;                                   // resting at the start
        }
        t -= pauseMs;
        if (t < travel) {
            return (t * overflow) / travel;             // travelling out
        }
        t -= travel;
        if (t < pauseMs) {
            return overflow;                            // resting at the end
        }
        t -= pauseMs;
        return overflow - (t * overflow) / travel;      // travelling back
    }

    //! Ask for animation frames without drawing any text through this module.
    //!
    //! The recap's lists scroll vertically using this module's clock and its
    //! timer, but draw themselves — so they have to say they are still moving,
    //! or `endFrame` stops the timer underneath them on the very next frame.
    public function claimFrame() as Void {
        _neededThisFrame = true;
        _ensureRunning();
    }

    //! Called at the end of a view's onUpdate. Stops the timer when a whole
    //! frame went by with nothing overflowing.
    public function endFrame() as Void {
        if (!_neededThisFrame) {
            stop();
        }
        _neededThisFrame = false;
    }

    public function stop() as Void {
        if (!_running) {
            return;
        }
        _running = false;
        var timer = _timer;
        if (timer != null) {
            timer.stop();
        }
    }

    public function isRunning() as Boolean {
        return _running;
    }

    function _ensureRunning() as Void {
        if (_running) {
            return;
        }
        var timer = _timer;
        if (timer == null) {
            timer = new Timer.Timer();
            _timer = timer;
        }
        _running = true;
        timer.start(_frames.method(:onFrame), FRAME_MS, true);
    }

    public function onFrame() as Void {
        if (_running) {
            WatchUi.requestUpdate();
        }
    }
}

//! The Timer callback for the Marquee module: a module has no self to bind
//! `method(:onFrame)` to.
class MarqueeFrames {
    public function initialize() {
    }

    public function onFrame() as Void {
        Marquee.onFrame();
    }
}
