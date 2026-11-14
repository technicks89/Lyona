    // Runs inside an isolated copy of the production ShellRoot (#499). A title
    // that overflows scrolls across once after it changes and then rests at its
    // start; one that fits never moves; with reduced motion nothing moves, and
    // turning it on mid-scroll stops the scroll at once.
    property int titleStage: 0
    property double titleStageStarted: Date.now()
    property bool titleMoved: false
    property bool titleScrolled: false
    readonly property string longTitle: "A window title much too long for the space the panel gives it, ending here"

    function titleCheck(ok, detail) {
        if (!ok) {
            console.error("Scrolling title FAILED at stage " + root.titleStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function titleNext(text) {
        root.titleMoved = false;
        root.titleScrolled = false;
        root.titleStage++;
        root.titleStageStarted = Date.now();
        if (text !== undefined) scrollTitle.text = text;
    }

    FloatingWindow {
        visible: true
        implicitWidth: 200
        implicitHeight: 40

        ScrollingTitle {
            id: scrollTitle

            width: 100
            height: 30
            speed: 2000
            startPause: 50
            endPause: 50
            maxScrollDuration: 300
            onTextXChanged: if (textX < 0) root.titleMoved = true
            onScrollingChanged: if (scrolling) root.titleScrolled = true
        }
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const waited = Date.now() - root.titleStageStarted;
            root.titleCheck(waited < 10000, "timed out");
            switch (root.titleStage) {
            case 0:
                if (waited < 300) return;
                root.titleNext(root.longTitle);
                return;
            case 1:
                // Scrolls once, then rests at its start, elided.
                if (!root.titleMoved || scrollTitle.scrolling) return;
                root.titleCheck(scrollTitle.overflow > 0 && scrollTitle.textX === 0,
                    "rest after the scroll: x " + scrollTitle.textX);
                root.titleNext();
                return;
            case 2:
                // At rest it stays at rest: no second scroll.
                if (waited < 400) return;
                root.titleCheck(!root.titleScrolled, "it scrolled again without a change");
                root.titleNext("Short");
                return;
            case 3:
                if (waited < 400) return;
                root.titleCheck(scrollTitle.overflow === 0 && !root.titleScrolled && !root.titleMoved,
                    "a title that fits moved");
                Theme.applyAccessibility(Theme.highContrast, true);
                root.titleNext(root.longTitle + " (reduced motion)");
                return;
            case 4:
                if (waited < 400) return;
                root.titleCheck(scrollTitle.overflow > 0 && !root.titleScrolled && !root.titleMoved,
                    "it scrolled with reduced motion on");
                Theme.applyAccessibility(Theme.highContrast, false);
                scrollTitle.endPause = 5000;
                root.titleNext(root.longTitle + " (stopped)");
                return;
            case 5:
                // Reduced motion turned on mid-scroll stops it at once.
                if (!root.titleMoved) return;
                Theme.applyAccessibility(Theme.highContrast, true);
                root.titleCheck(!scrollTitle.scrolling && scrollTitle.textX === 0,
                    "reduced motion did not stop the scroll");
                Theme.applyAccessibility(Theme.highContrast, false);
                scrollTitle.endPause = 50;
                root.titleNext("x".repeat(16383));
                return;
            case 6:
                // A very long title arrives whole and still scrolls in bounded time.
                if (!root.titleMoved || scrollTitle.scrolling) return;
                root.titleCheck(scrollTitle.text.length === 16383 && scrollTitle.textX === 0
                    && waited < 2000, "a 16383-character title: " + waited + " ms");
                console.log("Scrolling title: PASS");
                Qt.quit();
                return;
            }
        }
    }
