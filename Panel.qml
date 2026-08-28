import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "io.github.rafzzzzzz.distrowatch"

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root
    property var rankings: []
    property bool loading: false
    property bool stale: false
    property string error: ""
    property double updatedAt: 0
    property bool outputReceived: false

    readonly property int rankColumnWidth: Style.space(32)
    readonly property int hpdColumnWidth: Style.space(56)
    readonly property int trendColumnWidth: Style.space(16)

    readonly property string pageUrl: "https://distrowatch.com/dwres.php?resource=popularity"
    readonly property string helperPath: String(Qt.resolvedUrl("fetch_rankings.py")).replace(/^file:\/\//, "")
    readonly property string cachePath: Quickshell.env("HOME") + "/.cache/omarchy/distrowatch-rankings.json"
    readonly property string tooltipText: rankings.length > 0
        ? "#1 " + rankings[0].name + " · " + rankings[0].hpd + " HPD"
        : "DistroWatch Page Hit Ranking"

    function openFromHotkey() {
        root.controller.show();
        if (root.rankings.length === 0 || Date.now() / 1000 - root.updatedAt > 21600)
            root.refresh();
    }

    function close() {
        root.controller.hide();
    }

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.openFromHotkey();
    }

    function closeForPopoutSwitch() {
        root.close();
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction);
        return false;
    }

    function refresh() {
        if (fetchProc.running)
            return;
        root.loading = true;
        root.outputReceived = false;
        fetchProc.running = true;
    }

    function applyOutput(raw) {
        root.outputReceived = true;
        root.loading = false;
        try {
            var payload = JSON.parse(String(raw || "{}"));
            if (!Array.isArray(payload.rankings))
                throw new Error("invalid ranking data");
            root.rankings = payload.rankings.slice(0, 20);
            root.updatedAt = Number(payload.updatedAt || 0);
            root.stale = payload.stale === true;
            root.error = String(payload.error || "");
        } catch (error) {
            root.stale = true;
            root.error = "Could not read DistroWatch data";
        }
    }

    function openUrl(url) {
        if (browserProc.running)
            return;
        browserProc.command = ["omarchy-launch-browser", String(url)];
        browserProc.running = true;
    }

    function updatedLabel() {
        if (root.updatedAt <= 0)
            return root.loading ? "FETCHING SIX-MONTH DATA" : "SIX-MONTH AVERAGE";
        var stamp = new Date(root.updatedAt * 1000);
        var prefix = root.stale ? "CACHED" : "UPDATED";
        return prefix + " " + Qt.formatDateTime(stamp, "MMM d · HH:mm").toUpperCase();
    }

    function trendGlyph(trend) {
        if (trend === "up")
            return "▲";
        if (trend === "down")
            return "▼";
        return "•";
    }

    function trendColor(trend) {
        if (trend === "up")
            return Color.accent;
        if (trend === "down")
            return root.bar.urgent;
        return Qt.darker(root.bar.foreground, 1.6);
    }

    Process {
        id: fetchProc
        command: ["python3", root.helperPath, root.cachePath]
        onRunningChanged: {
            if (running)
                fetchDeadline.restart();
            else
                fetchDeadline.stop();
        }
        onExited: {
            if (!root.outputReceived) {
                root.loading = false;
                root.stale = true;
                root.error = "DistroWatch request failed";
            }
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyOutput(text)
        }
    }

    Process {
        id: browserProc
    }

    Timer {
        id: fetchDeadline
        interval: 25000
        onTriggered: {
            if (fetchProc.running)
                fetchProc.running = false;
            root.loading = false;
            root.stale = true;
            root.error = "DistroWatch request timed out";
        }
    }

    Timer {
        interval: 21600000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: false
        contentWidth: panel.fittedContentWidth(Style.space(380))
        contentHeight: panel.fittedContentHeight(rankingColumn.implicitHeight)

        PanelKeyCatcher {
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) {
                root.switchPanel(direction);
            }

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: rankingColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: rankingColumn
                    width: parent.width
                    spacing: Style.space(8)

                    Row {
                        width: parent.width
                        leftPadding: Style.space(16)
                        rightPadding: Style.space(16)
                        spacing: Style.space(10)

                        Text {
                            text: ""
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.display
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - Style.space(112)
                            spacing: Style.space(2)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: "PAGE HIT RANKING"
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }

                            Text {
                                text: root.updatedLabel()
                                color: Qt.darker(root.bar.foreground, 1.5)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.bodySmall
                            }
                        }

                        Rectangle {
                            width: Style.space(36)
                            height: Style.space(36)
                            radius: Style.cornerRadius
                            color: refreshArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: root.loading ? "…" : ""
                                color: root.loading ? Qt.darker(root.bar.foreground, 1.5) : root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                            }

                            MouseArea {
                                id: refreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !root.loading
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.refresh()
                            }
                        }

                        Rectangle {
                            width: Style.space(36)
                            height: Style.space(36)
                            radius: Style.cornerRadius
                            color: siteArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                            }

                            MouseArea {
                                id: siteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUrl(root.pageUrl)
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - Style.space(32)
                        x: Style.space(16)
                        height: Style.spacing.hairline
                        color: root.bar.foreground
                        opacity: 0.12
                    }

                    Row {
                        visible: root.rankings.length > 0
                        width: parent.width - Style.space(48)
                        x: Style.space(24)

                        Text {
                            width: root.rankColumnWidth
                            text: "RANK"
                            color: Qt.darker(root.bar.foreground, 1.5)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                        }

                        Text {
                            width: parent.width - root.rankColumnWidth - root.hpdColumnWidth - root.trendColumnWidth
                            text: "DISTRIBUTION"
                            color: Qt.darker(root.bar.foreground, 1.5)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                        }

                        Text {
                            width: root.hpdColumnWidth
                            text: "HPD"
                            horizontalAlignment: Text.AlignRight
                            color: Qt.darker(root.bar.foreground, 1.5)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                        }

                        Item {
                            width: root.trendColumnWidth
                            height: 1
                        }
                    }

                    ListView {
                        id: rankingList
                        visible: root.rankings.length > 0
                        width: parent.width
                        height: count * Style.space(36)
                        interactive: false
                        model: root.rankings

                        delegate: Rectangle {
                            id: rankingRow
                            required property int index
                            required property var modelData

                            width: rankingList.width
                            height: Style.space(36)
                            color: "transparent"

                            Rectangle {
                                id: rowBackground
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(16)
                                anchors.rightMargin: Style.space(16)
                                radius: Style.cornerRadius
                                color: rowArea.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(24)
                                anchors.rightMargin: Style.space(24)

                                Text {
                                    width: root.rankColumnWidth
                                    text: rankingRow.modelData.rank
                                    color: rankingRow.index === 0 ? Color.accent : Qt.darker(root.bar.foreground, 1.35)
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: rankingRow.index === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    width: parent.width - root.rankColumnWidth - root.hpdColumnWidth - root.trendColumnWidth
                                    text: rankingRow.modelData.name
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: rankingRow.index === 0
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    width: root.hpdColumnWidth
                                    text: rankingRow.modelData.hpd
                                    horizontalAlignment: Text.AlignRight
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.body
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    width: root.trendColumnWidth
                                    text: root.trendGlyph(rankingRow.modelData.trend)
                                    horizontalAlignment: Text.AlignRight
                                    color: root.trendColor(rankingRow.modelData.trend)
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: rowBackground
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUrl(rankingRow.modelData.url)
                            }
                        }
                    }

                    Text {
                        visible: root.rankings.length === 0
                        width: parent.width
                        topPadding: Style.space(24)
                        bottomPadding: Style.space(24)
                        horizontalAlignment: Text.AlignHCenter
                        text: root.loading ? "Loading rankings…" : "Rankings unavailable"
                        color: Qt.darker(root.bar.foreground, 1.5)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                        font.italic: true
                    }

                    Text {
                        visible: root.stale && root.error !== ""
                        width: parent.width - Style.space(32)
                        x: Style.space(16)
                        text: root.rankings.length > 0 ? "Offline · showing cached rankings" : root.error
                        color: root.bar.urgent
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.rankings.length > 0
                        width: parent.width - Style.space(32)
                        x: Style.space(16)
                        bottomPadding: Style.space(4)
                        text: "Average page hits per day · not market share"
                        color: Qt.darker(root.bar.foreground, 1.6)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }
            }
        }
    }
}
