import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("Pamac Kirigami")
    width: 800
    height: 600

    // Set a larger default font size and clean font family
    font.pointSize: 12
    font.family: "sans-serif"

    property bool isSearching: false

    Component {
        id: detailsPage
        Kirigami.Page {
            property var pkg: null
            title: pkg ? pkg.name : ""

            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Heading {
                    text: pkg ? pkg.version : ""
                    level: 2
                    Layout.fillWidth: true
                    font.pointSize: 16
                }

                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    
                    Label {
                        Kirigami.FormData.label: qsTr("Description:")
                        text: pkg ? (pkg.description || "") : ""
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pointSize: 13
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("Repository:")
                        text: pkg ? (pkg.repository || "") : ""
                        font.pointSize: 12
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("URL:")
                        text: pkg ? (pkg.url || "") : ""
                        color: Kirigami.Theme.highlightColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        font.pointSize: 12
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (pkg && pkg.url) pamacBackend.open_url(pkg.url)
                        }
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("License:")
                        text: pkg ? (pkg.license || "") : ""
                        font.pointSize: 12
                    }
                    Label {
                        Kirigami.FormData.label: qsTr("Maintainer:")
                        text: pkg ? (pkg.maintainer || "") : ""
                        font.pointSize: 12
                    }
                    Label {
                        visible: pkg && pkg.repository === "AUR"
                        Kirigami.FormData.label: qsTr("Votes:")
                        text: pkg ? (pkg.votes || "0") : ""
                        font.pointSize: 12
                    }
                    Label {
                        visible: pkg && pkg.repository === "AUR"
                        Kirigami.FormData.label: qsTr("Popularity:")
                        text: pkg ? (pkg.popularity || "0.00") : ""
                        font.pointSize: 12
                    }
                }

                Kirigami.Heading {
                    text: qsTr("Dependencies")
                    level: 4
                    visible: pkg && pkg.depends && pkg.depends.length > 0
                    font.pointSize: 14
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
                            font.pointSize: 11
                            background: Rectangle {
                                color: Kirigami.Theme.highlightColor
                                opacity: 0.2
                                radius: Kirigami.Units.smallSpacing
                            }
                        }
                    }
                }
            }
        }
    }

    pageStack.initialPage: Kirigami.ScrollablePage {
        id: mainPage
        title: qsTr("Software Management")

        footer: ToolBar {
            contentItem: Label {
                id: statusLabel
                text: qsTr("Ready")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.pointSize: 10
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
            font.pointSize: 14
            onTextChanged: {
                if (text.length > 2) {
                    searchDelay.restart()
                } else {
                    root.isSearching = false
                    packageModel.clear()
                }
            }
            onAccepted: {
                if (text.length > 2) {
                    root.isSearching = true
                    searchDelay.stop()
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
                root.isSearching = true
                pamacBackend.search_packages_async(searchField.text)
            }
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: packageModel.count === 0 && !root.isSearching
            text: searchField.text.length > 2 ? qsTr("No results found") : qsTr("Start typing to search...")
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: root.isSearching
            visible: running
            z: 100
        }

        ListView {
            id: packageList
            model: ListModel { id: packageModel }
            clip: true
            visible: !root.isSearching || packageModel.count > 0
            
            Connections {
                target: pamacBackend
                function onSearch_results_ready(results) {
                    packageModel.clear()
                    for (var i = 0; i < results.length; i++) {
                        packageModel.append(results[i])
                    }
                    root.isSearching = false
                }
                function onSearch_started() {
                    root.isSearching = true
                }
            }

            delegate: Kirigami.AbstractCard {
                contentItem: ColumnLayout {
                    Kirigami.Heading {
                        text: model.name || ""
                        level: 2
                        Layout.fillWidth: true
                        font.pointSize: 15
                    }
                    Label {
                        text: (model.version || "") + " (" + (model.repository || "") + ")"
                        font.italic: true
                        font.pointSize: 11
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                    Label {
                        text: model.description || ""
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        visible: text !== ""
                        font.pointSize: 12
                    }
                }
                onClicked: {
                    var details = pamacBackend.get_package_details(model.name, model.repository)
                    if (details && details.name) {
                        pageStack.push(detailsPage, { "pkg": details })
                    }
                }
            }
        }
    }
}
