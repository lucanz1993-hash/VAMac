import QtQuick
import Theme

// Tessera selezionabile del pannello "Aspetto" in Profilo: tre chip colore
// (sfondo/superficie/accento) + nome + anello di selezione.
Rectangle {
    id: root

    property string temaId: ""
    property string nome: ""
    property color previewBg: "#000000"
    property color previewSurface: "#000000"
    property color previewAccent: "#000000"
    property bool selected: false

    signal clicked()

    implicitWidth: 128
    implicitHeight: 88
    radius: Theme.radius.md
    color: previewBg
    border.width: selected ? 2 : 1
    border.color: selected ? Theme.colors.accent : Theme.colors.border

    Behavior on border.color { ColorAnimation { duration: Theme.motion.micro } }

    Row {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.spacing.sm
        spacing: 4
        Rectangle { width: 16; height: 16; radius: 3; color: root.previewSurface }
        Rectangle { width: 16; height: 16; radius: 3; color: root.previewAccent }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.spacing.sm
        text: root.nome
        color: root.previewAccent
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.caption
        font.bold: true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
