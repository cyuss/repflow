import Toybox.Lang;
import Toybox.Graphics;

//! A Garmin-style data field grid, laid out for a round display.
//!
//! Garmin's native activity screens follow a small number of layouts, and they
//! all obey the same rule: **only the middle band is ever split into columns.**
//! The top and bottom of a circle are narrow, so a cell up there has very little
//! usable width — which is why Garmin keeps those bands full width and reserves
//! side-by-side cells for the middle, where the glass is widest.
//!
//!   2 fields            3 fields            4 fields
//!   +-----------+       +-----------+       +-----------+
//!   |    ...    |       |    ...    |       |    ...    |
//!   +-----------+       +-----+-----+       +-----+-----+
//!   |    ...    |       | ... | ... |       | ... | ... |
//!   +-----------+       +-----+-----+       +-----+-----+
//!                                           |    ...    |
//!                                           +-----------+
//!
//! The second rule is about content: a **wide** value ("1:02:34", "137.5") needs
//! a full-width band or it gets shrunk to nothing in a half cell. Short values
//! ("55", "10", "132") are what belong side by side. The views choose their
//! bands accordingly.
//!
//! Widths here are the chord of the display at the band's *narrowest* edge, not
//! its centre, so nothing can spill past the bezel at the top or bottom of a
//! band.
module FieldGrid {

    //! Usable width of a horizontal band on a round screen.
    //!
    //! A band spans a range of heights and the circle narrows towards its ends,
    //! so the safe width is the chord at whichever edge is furthest from the
    //! vertical centre — not the chord at the band's middle.
    public function bandWidth(dc as Graphics.Dc, top as Number, height as Number) as Number {
        return Theme.bandWidth(dc, top, height);
    }

    //! Draw one value + caption cell inside the given rectangle.
    //!
    //! The value is centred in the space above the caption so that cells in the
    //! same band align with one another even when their fonts differ.
    //! Height available to a cell's value, once its caption is accounted for.
    //!
    //! Exposed because the layout tests measure against it — they check the real
    //! arithmetic rather than a copy of it.
    public function valueArea(dc as Graphics.Dc, height as Number) as Number {
        var captionHeight = dc.getFontHeight(Theme.captionFont());
        var area = height - captionHeight - height / 16 - height / 20;
        if (area < captionHeight) {
            return height;   // no room for a caption; the value takes the cell
        }
        return area;
    }

    public function drawCell(
        dc as Graphics.Dc,
        x as Number,
        y as Number,
        width as Number,
        height as Number,
        value as String,
        caption as String,
        valueColor as Number
    ) as Void {
        var captionFont = Theme.captionFont();
        var captionHeight = dc.getFontHeight(captionFont);
        var area = valueArea(dc, height);

        var valueFont = Theme.pickFontFitting(dc, value, Theme.fontsCell(),
            (width * 92) / 100, area);
        var valueHeight = dc.getFontHeight(valueFont);

        var cx = x + width / 2;
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + (area - valueHeight) / 2, valueFont, value,
            Graphics.TEXT_JUSTIFY_CENTER);

        if (area != height) {
            // Keep the caption clear of the band's bottom edge; a caption
            // sitting on the separating rule reads as a collision.
            var bottomInset = height / 20;
            dc.setColor(Theme.COLOR_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + height - captionHeight - bottomInset, captionFont, caption,
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! A full-width band holding one field. Use this for wide values, and for
    //! the top and bottom bands of a round screen.
    public function drawSingle(
        dc as Graphics.Dc,
        top as Number,
        height as Number,
        value as String,
        caption as String,
        valueColor as Number
    ) as Void {
        var width = bandWidth(dc, top, height);
        drawCell(dc, (dc.getWidth() - width) / 2, top, width, height,
            value, caption, valueColor);
    }

    //! A band split into two cells, with a divider between them.
    //!
    //! Reserve this for the middle of the screen and for short values — that is
    //! what the geometry of a circle allows.
    public function drawPair(
        dc as Graphics.Dc,
        top as Number,
        height as Number,
        leftValue as String,
        leftCaption as String,
        leftColor as Number,
        rightValue as String,
        rightCaption as String,
        rightColor as Number
    ) as Void {
        var width = bandWidth(dc, top, height);
        var left = (dc.getWidth() - width) / 2;
        var half = width / 2;

        drawCell(dc, left, top, half, height, leftValue, leftCaption, leftColor);
        drawCell(dc, left + half, top, half, height, rightValue, rightCaption, rightColor);

        // Divider, inset top and bottom so it reads as a separator, not a box.
        var inset = height / 6;
        dc.setColor(Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(left + half, top + inset, 1, height - inset * 2);
    }

    //! Hairline across the usable width at `y`. Separates bands.
    public function drawRule(dc as Graphics.Dc, y as Number) as Void {
        var width = Theme.usableWidth(dc, y);
        dc.setColor(Theme.COLOR_SKIPPED, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle((dc.getWidth() - width) / 2, y, width, 1);
    }

    //! Top of band `index` when [top, bottom) is split into `count` bands.
    public function bandTop(
        top as Number,
        bottom as Number,
        count as Number,
        index as Number
    ) as Number {
        return top + ((bottom - top) * index) / count;
    }

    //! Height of one band when [top, bottom) is split into `count`.
    public function bandHeight(top as Number, bottom as Number, count as Number) as Number {
        return (bottom - top) / count;
    }

    //! Height of the top and bottom bands in Garmin's four-field round layout.
    //!
    //! The middle keeps the remainder — it is the widest part of the glass and
    //! carries two values, so it earns the extra height. Callers compose the
    //! layout themselves with drawSingle/drawRule/drawPair, which keeps each
    //! screen's structure visible at its call site (and stays inside Monkey C's
    //! nine-argument limit per method).
    public function edgeHeight(top as Number, bottom as Number) as Number {
        return ((bottom - top) * 32) / 100;
    }
}
