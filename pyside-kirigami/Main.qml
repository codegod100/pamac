import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("Pamac Kirigami")
    width: 800
    height: 600

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: qsTr("Software Management")

        footer: ToolBar {
            contentItem: Label {
                id: statusLabel
                text: qsTr("Ready")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
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
            placeholderText: qsTr("Search for packages...")
            onTextChanged: searchDelay.restart()
            Component.onCompleted: forceActiveFocus()
        }

        // Debounce search to keep UI snappy
        Timer {
            id: searchDelay
            interval: 300
            repeat: false
            onTriggered: {
                if (searchField.text.length > 2) {
                    pamacBackend.search_packages_async(searchField.text)
                } else {
                    packageModel.clear()
                }
            }
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            visible: packageModel.count === 0
            text: searchField.text.length > 2 ? qsTr("No results found") : qsTr("Start typing to search...")
        }

        ListView {
            id: packageList
            model: ListModel { id: packageModel }
            clip: true
            
            Connections {
                target: pamacBackend
                function onSearch_results_ready(results) {
                    packageModel.clear()
                    for (var i = 0; i < results.length; i++) {
                        packageModel.append(results[i])
                    }
                }
            }

            delegate: Kirigami.AbstractCard {
                contentItem: ColumnLayout {
                    Kirigami.Heading {
                        text: model.name
                        level: 2
                        Layout.fillWidth: true
                    }
                    Label {
                        text: model.version + " (" + model.repository + ")"
                        font.italic: true
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                    Label {
                        text: model.description
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        visible: model.description !== ""
                    }
                }
            }
        }
    }
}
