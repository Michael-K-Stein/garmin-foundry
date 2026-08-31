import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! What the lines got through while the watch was in a pocket. One tap on
//! CLAIM banks the lot and drops the player back on the board.
class WelcomeView extends WatchUi.View {

    private var mGame as GameState or Null = null;

    private var mBtnX as Number = 0;
    private var mBtnY as Number = 0;
    private var mBtnW as Number = 0;
    private var mBtnH as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        Layout.measure(dc);
        mBtnH = Layout.s(62);
        mBtnY = Layout.s(288);
        var row = Layout.fitRow(mBtnY, mBtnH, Layout.s(16));
        mBtnX = row[0];
        mBtnW = row[1];
    }

    function onShow() as Void {
        mGame = FoundryApp.game();
    }

    function claim() as Void {
        var game = mGame;
        if (game != null) {
            game.claimOffline();
            game.save();
        }
        Haptics.confirm();
    }

    function onUpdate(dc as Dc) as Void {
        Layout.measure(dc);
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();

        var game = mGame;
        if (game == null) {
            return;
        }

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(58), Graphics.FONT_XTINY, "WELCOME BACK",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(Layout.cx, Layout.s(84), Graphics.FONT_XTINY,
            Fmt.duration(game.offlineSecs) + " away", Graphics.TEXT_JUSTIFY_CENTER);

        Theme.bigCash(dc, Layout.cx, Layout.s(120), game.offlineGold, Theme.GOLD,
            Graphics.FONT_NUMBER_MEDIUM);

        var open = game.factoriesOpen();
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(208), Graphics.FONT_SMALL,
            open.toString() + ((open == 1) ? " line kept running"
                : " lines kept running"),
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(250), Graphics.FONT_XTINY,
            "unattended lines run at 60%", Graphics.TEXT_JUSTIFY_CENTER);

        Theme.button(dc, mBtnX, mBtnY, mBtnW, mBtnH, "CLAIM", Theme.GOLD_DIM,
            Theme.TEXT);
    }
}
