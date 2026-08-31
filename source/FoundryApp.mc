import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Foundry - an idle production-chain game for the Venu 2 family.
//!
//! One factory is three stages in a line: harvest, craft, sell. You buy
//! machines for the stage that is holding the other two back, and when a
//! line runs itself you go and open the next one.
class FoundryApp extends Application.AppBase {

    private var mState as GameState or Null = null;

    //! Convenience accessor so views do not have to cast the app every time.
    static function game() as GameState or Null {
        return (Application.getApp() as FoundryApp).state();
    }

    function initialize() {
        AppBase.initialize();
    }

    function state() as GameState or Null {
        return mState;
    }

    function onStart(startState as Dictionary?) as Void {
        mState = new GameState();
        (mState as GameState).load();
    }

    function onStop(stopState as Dictionary?) as Void {
        if (mState != null) {
            (mState as GameState).save();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var state = mState as GameState;
        if (state.hasOffline()) {
            var welcome = new WelcomeView();
            return [welcome, new WelcomeDelegate(welcome)];
        }
        var view = new GameView();
        return [view, new GameDelegate(view)];
    }
}
