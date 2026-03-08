import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("Pamac Kirigami")
    width: 1000
    height: 800

    // Set a larger default font size and clean font family
    font.pointSize: 14
    font.family: "sans-serif"

    property bool isSearching: false
    property string lastSearchText: ""
    property int currentSearchSeq: 0

    Component {
        id: detailsPage
        Kirigami.Page {
            property var pkg: null
            title: pkg ? pkg.name : ""

            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing

                Kirigami.Heading {
                    text: pkg ? pkg.version : ""
                    level: 2
                    Layout.fillWidth: true
                    font.pointSize: 18
                }

                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        Kirigami.FormData.label: qsTr("Description:")
                        text: pkg ? (pkg.description || "") : ""
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pointSize: 15
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("Repository:")
                        text: pkg ? (pkg.repository || "") : ""
                        font.pointSize: 14
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("URL:")
                        text: pkg ? (pkg.url || "") : ""
                        color: Kirigami.Theme.highlightColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        font.pointSize: 14
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (pkg && pkg.url) pamacBackend.open_url(pkg.url)
                        }
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("License:")
                        text: pkg ? (pkg.license || "") : ""
                        font.pointSize: 14
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("Maintainer:")
                        text: pkg ? (pkg.maintainer || "") : ""
                        font.pointSize: 14
                    }
                    Label {
                        visible: pkg && pkg.repository === "AUR"
                        Kirigami.FormData.label: qsTr("Votes:")
                        text: pkg ? (pkg.votes || "0") : ""
                        font.pointSize: 14
                    }
                    Label {
                        visible: pkg && pkg.repository === "AUR"
                        Kirigami.FormData.label: qsTr("Popularity:")
                        text: pkg ? (pkg.popularity || "0.00") : ""
                        font.pointSize: 14
                    }
                }

                Kirigami.Heading {
                    text: qsTr("Dependencies")
                    level: 4
                    visible: pkg && pkg.depends && pkg.depends.length > 0
                    font.pointSize: 16
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: pkg && pkg.depends && pkg.depends.length > 0
                    Repeater {
                        model: pkg ? pkg.depends : []
                        delegate: Label {
                            text: modelData
                            padding: Kirigami.Units.smallSpacing
                            font.pointSize: 12
                            background: Rectangle {
                                color: Kirigami.Theme.highlightColor
                                opacity: 0.2
                                radius: Kirigami.Units.smallSpacing
                            }
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
            }
        }
    }

    pageStack.initialPage: Kirigami.Page {
        id: mainPage
        title: qsTr("Software Management")

        footer: ToolBar {
            z: 10
            contentItem: Label {
                id: statusLabel
                text: qsTr("Ready")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.pointSize: 12
            }
            Connections {
                target: pamacBackend
                function onStatus_message(msg) {
                    statusLabel.text = msg
                }
            }
        }

        header: Kirigami.SearchField {
            id: searchField
            focus: true
            placeholderText: qsTr("Search for packages...")
            font.pointSize: 16
            onTextChanged: {
                if (text === root.lastSearchText) return;
                if (text.length > 2) {
                    searchDelay.restart()
                } else {
                    root.isSearching = false
                    packageModel.clear()
                    root.lastSearchText = ""
                    root.currentSearchSeq++
                }
            }
            onAccepted: {
                if (text === root.lastSearchText) return;
                if (text.length > 2) {
                    console.log("DEBUG: Search accepted for: " + text)
                    root.isSearching = true
                    searchDelay.stop()
                    root.lastSearchText = text
                    root.currentSearchSeq++
                    pamacBackend.search_packages_async(text)
                }
            }
        }

        Timer {
            interval: 200
            running: true
            repeat: false
            onTriggered: searchField.forceActiveFocus()
        }

        Timer {
            id: searchDelay
            interval: 600
            repeat: false
            onTriggered: {
                console.log("DEBUG: searchDelay triggered for: " + searchField.text)
                root.isSearching = true
                root.lastSearchText = searchField.text
                root.currentSearchSeq++
                pamacBackend.search_packages_async(searchField.text)
            }
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: packageModel.count === 0 && !root.isSearching
            text: searchField.text.length > 2 ? qsTr("No results found") : qsTr("Start typing to search...")
        }

        ListView {
            id: packageList
            anchors.fill: parent
            model: ListModel { id: packageModel }
            clip: true
            
            // Overlays BusyIndicator on top of list
            BusyIndicator {
                anchors.centerIn: parent
                running: root.isSearching
                visible: running
                z: 1000
            }
            
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            
            ScrollBar.vertical: ScrollBar {
                active: true
            }

            Connections {
                target: pamacBackend
                function onSearch_results_ready(results, seq) {
                    console.log("DEBUG: QML received " + results.length + " results for seq " + seq + " (current: " + root.currentSearchSeq + ")")
                    if (seq >= root.currentSearchSeq) {
                        packageModel.clear()
                        for (var i = 0; i < results.length; i++) {
                            packageModel.append(results[i])
                        }
                        root.isSearching = false
                        root.currentSearchSeq = seq
                    } else {
                        console.log("DEBUG: Ignoring outdated results for seq " + seq)
                    }
                }
                function onSearch_started() {
                    console.log("DEBUG: QML Search started")
                    root.isSearching = true
                }
            }

            delegate: Kirigami.AbstractCard {
                contentItem: ColumnLayout {
                    Kirigami.Heading {
                        text: model.name || ""
                        level: 2
                        Layout.fillWidth: true
                        font.pointSize: 17
                    }
                    Label {
                        text: (model.version || "") + " (" + (model.repository || "") + ")"
                        font.italic: true
                        font.pointSize: 13
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                    Label {
                        text: model.description || ""
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        visible: text !== ""
                        font.pointSize: 14
                    }
                }
                onClicked: {
                    console.log("DEBUG: Clicked " + model.name)
                    var details = pamacBackend.get_package_details(model.name, model.repository)
                    if (details && details.name) {
                        pageStack.push(detailsPage, { "pkg": details })
                    }
                }
            }
        }
    }
}
