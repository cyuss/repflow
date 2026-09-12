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

    //! 10 fps. Enough for legible motion, cheap enough for a 128 KB watch.
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

    function _draw(
        dc as Graphics.Dc,
        top as Number,
        text as String,
        font as Graphics.FontDefinition,
        color as Number,
        maxWidth as Number
    ) as Number {
        var height = dc.getFontHeight(font);
        var width = dc.getTextWidthInPixels(text, font);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (width <= maxWidth) {
            dc.drawText(dc.getWidth() / 2, top, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return top + height;
        }

        var left = (dc.getWidth() - maxWidth) / 2;
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
            dc.drawText(dc.getWidth() / 2, top, font, text, Graphics.TEXT_JUSTIFY_CENTER);
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
        if (overflow <= 0) {
            return 0;
        }
        var travel = overflow * MS_PER_PIXEL;
        var period = (PAUSE_MS + travel) * 2;
        var t = millis % period;

        if (t < PAUSE_MS) {
            return 0;                                   // resting at the start
        }
        t -= PAUSE_MS;
        if (t < travel) {
            return (t * overflow) / travel;             // travelling out
        }
        t -= travel;
        if (t < PAUSE_MS) {
            return overflow;                            // resting at the end
        }
        t -= PAUSE_MS;
        return overflow - (t * overflow) / travel;      // travelling back
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
