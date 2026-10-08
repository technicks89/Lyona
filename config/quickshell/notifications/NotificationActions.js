.pragma library

// The buttons a notification shows for its actions (#260): at most MAX_BUTTONS,
// each with text, cut to MAX_TEXT characters. The "default" action (a click on
// the notification itself) is not a button. Only the identifier and text are
// kept; the model invokes the live action by its identifier.

var MAX_BUTTONS = 3;
var MAX_TEXT = 40;

function buttons(actions) {
    var result = [];
    var list = actions || [];
    for (var i = 0; i < list.length && result.length < MAX_BUTTONS; i++) {
        var action = list[i];
        if (!action || action.identifier === "default") continue;
        var text = String(action.text || "").trim().slice(0, MAX_TEXT);
        if (text.length > 0) result.push({ "identifier": String(action.identifier), "text": text });
    }
    return result;
}

// The popups to keep when a new one arrives, newest first: only ordinary
// notifications count toward maxVisible. A question (one with buttons) is
// never pushed out unanswered; closing it would answer it (Cancel). Returns
// { kept, overflow }: overflow are the ordinary ones to close.
function fitPopups(candidates, maxVisible) {
    var kept = [];
    var overflow = [];
    var ordinary = 0;
    for (var i = 0; i < candidates.length; i++) {
        var item = candidates[i];
        if (item.actions && item.actions.length > 0) {
            kept.push(item);
        } else if (ordinary < maxVisible) {
            kept.push(item);
            ordinary++;
        } else {
            overflow.push(item);
        }
    }
    return { "kept": kept, "overflow": overflow };
}
