    // Runs inside an isolated copy of the production ShellRoot (#480). The stub
    // helper answers, in order: ok 21.5 Berlin, fail, fail, ok 10 Paris, fail.
    // A failure after a good report keeps it, stale; a failure with no report is
    // Unavailable; a location change and turning the widget off drop the report.
    property int weatherStage: 0
    property double weatherStageStarted: Date.now()

    function weatherCheck(ok, detail) {
        if (!ok) {
            console.error("Weather retain FAILED at stage " + root.weatherStage + ": " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function weatherNext() {
        root.weatherStage++;
        root.weatherStageStarted = Date.now();
    }
    function weatherSummary(model) {
        return model.weatherState + "/" + model.temperature + "/" + model.stale
            + "/" + model.panelText + "/" + model.detail;
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            const model = weatherModel;
            const waited = Date.now() - root.weatherStageStarted;
            root.weatherCheck(waited < 10000, "timed out: " + root.weatherSummary(model));
            switch (root.weatherStage) {
            case 0:
                // The settings are read at start; then the widget is turned on.
                if (model.location !== "Berlin") return;
                model.enabled = true;
                root.weatherNext();
                return;
            case 1:
                // A good report.
                if (model.weatherState !== "available") return;
                root.weatherCheck(model.temperature === "21.5" && !model.stale
                    && model.panelText === "22°C" && model.place === "Berlin",
                    "first report: " + root.weatherSummary(model));
                model.refresh();
                root.weatherNext();
                return;
            case 2:
                // Success, then failure: the report is kept, marked stale.
                if (!model.stale) return;
                root.weatherCheck(model.weatherState === "available" && model.temperature === "21.5"
                    && model.panelText === "22°C" && model.place === "Berlin"
                    && model.detail === "Could not reach the weather service",
                    "kept report: " + root.weatherSummary(model));
                model.setLocation("Paris");
                root.weatherNext();
                return;
            case 3:
                // A new location: the old report is dropped, and the failure
                // that follows, with no report, is Unavailable.
                if (model.busy || model.weatherState !== "unavailable") return;
                root.weatherCheck(model.location === "Paris" && model.temperature === ""
                    && !model.stale && model.panelText === "Unavailable" && model.place === "",
                    "after the location change: " + root.weatherSummary(model));
                model.refresh();
                root.weatherNext();
                return;
            case 4:
                // A good report for the new place.
                if (model.weatherState !== "available") return;
                root.weatherCheck(model.temperature === "10" && model.place === "Paris" && !model.stale,
                    "Paris report: " + root.weatherSummary(model));
                // Off drops the report; on again with a failure is Unavailable.
                model.enabled = false;
                root.weatherCheck(model.temperature === "" && model.place === "" && !model.stale,
                    "off kept the report: " + root.weatherSummary(model));
                model.enabled = true;
                root.weatherNext();
                return;
            case 5:
                if (model.weatherState !== "unavailable") return;
                root.weatherCheck(model.temperature === "" && model.panelText === "Unavailable",
                    "on again: " + root.weatherSummary(model));
                console.log("Weather retain: PASS");
                Qt.quit();
                return;
            }
        }
    }
