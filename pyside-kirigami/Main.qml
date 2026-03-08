import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("Pamac Kirigami")
    width: 800
    height: 600

    property var selectedPackage: null

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
            focus: true
            placeholderText: qsTr("Search for packages...")
            onTextChanged: searchDelay.restart()
        }

        Timer {
            interval: 200
            running: true
            repeat: false
            onTriggered: searchField.forceActiveFocus()
        }

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
                onClicked: {
                    var details = pamacBackend.get_package_details(model.name, model.repository)
                    if (details) {
                        root.selectedPackage = details
                        detailsSheet.open()
                    }
                }
            }
        }
    }

    Kirigami.OverlaySheet {
        id: detailsSheet
        title: selectedPackage ? selectedPackage.name : ""
        
        // Fix binding loop by using a fixed or maximum width instead of relying on root.width
        width: Math.min(root.width * 0.9, Kirigami.Units.gridUnit * 30)
        
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                text: selectedPackage ? selectedPackage.version : ""
                level: 3
                Layout.fillWidth: true
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                
                Label {
                    Kirigami.FormData.label: qsTr("Description:")
                    text: selectedPackage ? selectedPackage.description : ""
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    Kirigami.FormData.label: qsTr("Repository:")
                    text: selectedPackage ? selectedPackage.repository : ""
                }
                Label {
                    Kirigami.FormData.label: qsTr("URL:")
                    text: selectedPackage ? selectedPackage.url : ""
                    // Avoid linkByMouseColor which might be undefined
                    color: Kirigami.Theme.highlightColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    Kirigami.FormData.label: qsTr("License:")
                    text: selectedPackage ? selectedPackage.license : ""
                }
                Label {
                    Kirigami.FormData.label: qsTr("Maintainer:")
                    text: selectedPackage ? selectedPackage.maintainer : ""
                }
                Label {
                    visible: selectedPackage && selectedPackage.repository === "AUR"
                    Kirigami.FormData.label: qsTr("Votes:")
                    text: selectedPackage ? selectedPackage.votes : ""
                }
                Label {
                    visible: selectedPackage && selectedPackage.repository === "AUR"
                    Kirigami.FormData.label: qsTr("Popularity:")
                    text: selectedPackage ? selectedPackage.popularity : ""
                }
            }

            Kirigami.Heading {
                text: qsTr("Dependencies")
                level: 4
                visible: selectedPackage && selectedPackage.depends && selectedPackage.depends.length > 0
            }

            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: selectedPackage && selectedPackage.depends && selectedPackage.depends.length > 0
                Repeater {
                    model: selectedPackage ? selectedPackage.depends : []
                    delegate: Label {
                        text: modelData
                        padding: Kirigami.Units.smallSpacing
                        background: Rectangle {
                            // Safely use highlightColor
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
