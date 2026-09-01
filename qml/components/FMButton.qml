import QtQuick
import QtQuick.Controls.Basic
import Theme

// Pulsante stile FM: variante "primary" (Continue/Confirm, blu-viola pieno)
// e "secondary" (bordo sottile, sfondo superficie). Mai verde/rosso qui:
// quei colori sono riservati agli indicatori di stato altrove.
Button {
    id: root

    property bool primary: false
    property bool destructive: false
    property string iconSource: ""

    readonly property color _bg: {
        if (destructive) return down ? Theme.colors.dangerHover : Theme.colors.danger
        if (primary) return down ? Theme.colors.primarioPressed : (hovered ? Theme.colors.primarioHover : Theme.colors.primario)
        return down ? Theme.colors.bgSurface3 : (hovered ? Theme.colors.bgSurface3 : Theme.colors.bgSurface2)
    }
    readonly property color _text: (primary || destructive) ? "#ffffff" : Theme.colors.textPrimary
    readonly property color _border: (primary || destructive) ? "transparent" : Theme.colors.border

    implicitHeight: 38
    implicitWidth: contentRow.implicitWidth + Theme.spacing.lg * 2
    font.family: Theme.typography.family
    font.pixelSize: Theme.typography.body
    font.bold: primary || destructive

    background: Rectangle {
        radius: Theme.radius.md
        color: root._bg
        border.width: root.primary || root.destructive ? 0 : 1
        border.color: root._border
        Behavior on color { ColorAnimation { duration: Theme.motion.micro } }
    }

    contentItem: Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Theme.spacing.sm
        Image {
            visible: root.iconSource !== ""
            source: root.iconSource
            width: 16; height: 16
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
        }
        Text {
            text: root.text
            color: root._text
            font: root.font
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
