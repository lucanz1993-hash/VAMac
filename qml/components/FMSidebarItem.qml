import QtQuick
import Theme

// Voce di navigazione della Side Bar: icona + etichetta, banda oro e barra
// laterale di accento quando attiva (come da screenshot FM24 reali).
Rectangle {
    id: root

    property string label: ""
    property string iconSource: ""
    property bool active: false
    property bool hoverEnabledExternally: true
    signal clicked()

    implicitHeight: 44
    color: active ? Theme.colors.accentSoft : (mouseArea.containsMouse ? Theme.colors.bgSurface2 : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.motion.micro } }

    Rectangle {
        // Barra laterale di accento sulla voce attiva.
        width: 3
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Theme.colors.accent
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.micro } }
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacing.lg
        spacing: Theme.spacing.md

        Image {
            source: root.iconSource
            width: 18; height: 18
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
            opacity: root.active ? 1 : 0.75
        }
        Text {
            text: root.label
            color: root.active ? Theme.colors.accent : Theme.colors.textPrimary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.body
            font.bold: root.active
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: root.hoverEnabledExternally
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
