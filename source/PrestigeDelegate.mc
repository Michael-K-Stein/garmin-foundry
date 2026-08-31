import Toybox.Lang;
import Toybox.WatchUi;

//! Confirms a rebuild. Gold, machines, upgrades and every factory but the
//! first go; the blueprints just earned stay, and they are a permanent cut of
//! everything sold from here on - so the line the player lands back on is the
//! lumber yard again, worth more per plank than it has ever been. Worth one
//! second question: it is the only destructive thing in the game, and unlike
//! wiping a save it is progress rather than the loss of it.
class PrestigeDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response != WatchUi.CONFIRM_YES) {
            return true;
        }
        var game = FoundryApp.game();
        if (game != null && game.prestige()) {
            Haptics.confirm();
            var board = new GameView();
            WatchUi.switchToView(board, new GameDelegate(board), WatchUi.SLIDE_DOWN);
        } else {
            Haptics.deny();
        }
        return true;
    }
}
