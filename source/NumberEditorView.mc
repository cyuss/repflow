import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;

//! One number, edited with the two buttons that are already under your fingers.
//!
//!            SETS
//!             +
//!       ┌───────────┐
//!       │     4     │
//!       │   SETS    │
//!       └───────────┘
//!             -
//!         START OK
//!
//! The same shape as the set editor, deliberately: an athlete who has learned
//! that screen has learned this one. Plus above, minus below, where the buttons
//! physically are, drawn from rectangles so no device's font set can turn them
//! into "?" boxes.
//!
//! Holding a button accelerates, by the same rule the set editor uses — presses
//! arriving faster than a person taps are a hold.
//!
//! `tenths` is how a weight fits an editor that counts in whole numbers: the
//! value travels as tenths of a unit and only the label divides by ten.
class NumberEditorView extends WatchUi.View {

    private var _title as String;
    private var _unit as String;
    private var _value as Number;
    private var _min as Number;
    private var _max as Number;
    private var _step as Number;
    private var _tenths as Boolean;
    private var _onDone as Method(value as Number) as Void;
    private var _onCancel as Method() as Void;
    private var _lastAdjustMs as Number;

    public function initialize(
        title as String,
        unit as String,
        value as Number,
        min as Number,
        max as Number,
        step as Number,
        tenths as Boolean,
        onDone as Method(value as Number) as Void,
        onCancel as Method() as Void
    ) {
        View.initialize();
        _title = title;
        _unit = unit;
        _value = value;
        _min = min;
        _max = max;
        _step = step;
        _tenths = tenths;
        _onDone = onDone;
        _onCancel = onCancel;
        _lastAdjustMs = 0;
        _clamp();
    }

    public function adjust(direction as Number) as Void {
        var now = System.getTimer();
        var held = _lastAdjustMs != 0 && (now - _lastAdjustMs) < Tuning.COARSE_WINDOW_MS;
        _lastAdjustMs = now;
        var move = _step * direction * (held ? Tuning.COARSE_MULTIPLIER : 1);
        var before = _value;
        _value += move;
        _clamp();
        if (_value == before) {
            Haptics.refused();      // it is already at its limit
        }
        WatchUi.requestUpdate();
    }

    public function confirm() as Void {
        _onDone.invoke(_value);
    }

    public function cancel() as Void {
        _onCancel.invoke();
    }

    function _clamp() as Void {
        if (_value < _min) { _value = _min; }
        if (_value > _max) { _value = _max; }
    }

    function _text() as String {
        if (!_tenths) {
            return _value.toString();
        }
        return Theme.formatNumber(_value.toFloat() / 10.0);
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        Theme.clear(dc);
        var h = dc.getHeight();

        var y = Theme.drawFitted(dc, h / 9, _title,
            [Graphics.FONT_TINY, Graphics.FONT_XTINY] as Array<Graphics.FontDefinition>,
            Theme.COLOR_ACCENT);

        var signBand = h / 8;
        var bottom = h - h / 7;
        var cellTop = y + signBand;
        var cellBottom = bottom - signBand;
        var height = cellBottom - cellTop;
        if (height <= 0) {
            return;
        }

        var width = Theme.bandWidth(dc, cellTop, height);
        var left = (dc.getWidth() - width) / 2;
        var inset = width / 8;

        dc.setPenWidth(Device.stroke(11));
        dc.setColor(Theme.COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(left + inset, cellTop, width - inset * 2, height, height / 4);
        dc.setPenWidth(1);

        var pad = height / 12;
        FieldGrid.drawCell(dc, left, cellTop + pad, width, height - pad * 2,
            _text(), _unit, Theme.COLOR_TEXT);

        var signSize = (signBand * 55) / 100;
        var cx = dc.getWidth() / 2;
        Theme.drawSign(dc, cx, y + signBand / 2, signSize, true, Theme.COLOR_ACCENT);
        Theme.drawSign(dc, cx, cellBottom + signBand / 2, signSize, false, Theme.COLOR_ACCENT);
    }
}

class NumberEditorDelegate extends WatchUi.BehaviorDelegate {

    private var _view as NumberEditorView;

    public function initialize(view as NumberEditorView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    public function onPreviousPage() as Boolean {
        _view.adjust(1);
        return true;
    }

    public function onNextPage() as Boolean {
        _view.adjust(-1);
        return true;
    }

    public function onSelect() as Boolean {
        _view.confirm();
        return true;
    }

    public function onBack() as Boolean {
        _view.cancel();
        return true;
    }
}
