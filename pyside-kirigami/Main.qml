import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("Pamac Kirigami")
    width: 800
    height: 600

    pageStack.initialPage: Kirigami.Page {
        title: qsTr("Software Management")

        actions: [
            Kirigami.Action {
                text: qsTr("Search")
                icon.name: "search"
                onTriggered: searchField.forceActiveFocus()
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("Search for packages...")
                onTextChanged: {
                    if (text.length > 2) {
                        packageModel.clear()
                        var results = pamacBackend.search_packages(text)
                        for (var i = 0; i < results.length; i++) {
                            packageModel.append(results[i])
                        }
                    }
                }
            }

            ListView {
                id: packageList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: ListModel { id: packageModel }
                delegate: Kirigami.AbstractCard {
                    contentItem: Item {
                        implicitHeight: delegateLayout.implicitHeight
                        ColumnLayout {
                            id: delegateLayout
                            anchors.fill: parent
                            Kirigami.Heading {
                                text: model.name
                                level: 2
                            }
                            Label {
                                text: model.version
                                font.italic: true
                            }
                            Label {
                                text: model.description
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
