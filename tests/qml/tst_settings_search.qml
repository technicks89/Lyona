import QtQuick
import QtTest
import "../../config/quickshell/settings/SettingsSearch.js" as SettingsSearch

/*
 * Settings search: a section matches its name, its description or one of its
 * keywords. Searching "weather" or "battery" found nothing when only the name
 * and description were searched.
 *
 * Run: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "SettingsSearch"

    function ids(query) {
        return SettingsSearch.filter(SettingsSearch.sections, query).map(section => section.id);
    }

    function test_keywords() {
        compare(ids("weather"), ["appearance"]);
        compare(ids("battery"), ["power"]);
        compare(ids("Wallpaper"), ["appearance"]);
        verify(ids("wifi").indexOf("network") >= 0);
        verify(ids("timezone").indexOf("system") >= 0);
    }

    function test_names_and_descriptions() {
        compare(ids(""), SettingsSearch.sections.map(section => section.id));
        compare(ids("  audio "), ["audio"]);
        // "disp" is Displays' alone; the Responsiveness harness relies on it.
        compare(ids("disp"), ["displays"]);
        compare(ids("no such setting"), []);
    }

    function test_every_section_has_keywords() {
        for (const section of SettingsSearch.sections) {
            verify(section.keywords.length > 0, section.id);
            for (const keyword of section.keywords)
                compare(keyword, keyword.toLowerCase(), section.id + ": " + keyword);
        }
    }
}
