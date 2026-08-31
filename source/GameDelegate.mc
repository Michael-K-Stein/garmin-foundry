import Toybox.Lang;
import Toybox.WatchUi;

//! Input for the board. Taps land on full-width rows, a swipe up opens the
//! management pages, a swipe sideways changes factory, and the physical
//! select key does whatever the bottom button is offering - so the game is
//! playable without looking.
class GameDelegate extends WatchUi.BehaviorDelegate {

    private var mView as GameView;

    function initialize(view as GameView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        var coords = event.getCoordinates();
        mView.onTapAt(coords[0], coords[1]);
        return true;
    }

    function onSelect() as Boolean {
        mView.doAction(mView.action());
        return true;
    }

    function onSwipe(event as WatchUi.SwipeEvent) as Boolean {
        var direction = event.getDirection();
        if (direction == WatchUi.SWIPE_UP) {
            var manage = new ManageView(Page.UPGRADES);
            WatchUi.pushView(manage, new ManageDelegate(manage), WatchUi.SLIDE_UP);
            return true;
        }
        // Sideways walks to the next factory, unbuilt ones included: the
        // price of a line you cannot afford yet is the point of showing it.
        if (direction == WatchUi.SWIPE_LEFT) {
            mView.changeFactory(1);
            return true;
        }
        if (direction == WatchUi.SWIPE_RIGHT) {
            mView.changeFactory(-1);
            return true;
        }
        return false;
    }
}
