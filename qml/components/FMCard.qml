import QtQuick
import QtQuick.Effects
import Theme

// Card FM: intestazione maiuscola oro/ambra opzionale, corpo su sfondo pieno
// e opaco (mai trasparente/immagine di sfondo dietro il pannello), bordo
// sottile, angolo arrotondato, ombra leggera.
Rectangle {
    id: root

    default property alias contentData: bodyColumn.data
    property string title: ""
    property int elevationLevel: 1
    readonly property QtObject elevationTokens: elevationLevel === 2 ? Theme.elevation.level2 : Theme.elevation.level1

    color: Theme.colors.bgSurface
    radius: Theme.radius.lg
    border.width: 1
    border.color: Theme.colors.border
    implicitHeight: headerLabel.visible ? (headerLabel.height + bodyColumn.implicitHeight + Theme.spacing.lg * 3) : (bodyColumn.implicitHeight + Theme.spacing.lg * 2)

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: root.elevationTokens.opacity
        shadowBlur: root.elevationTokens.blurRadius / 32
        shadowVerticalOffset: root.elevationTokens.offsetY
    }

    Text {
        id: headerLabel
        visible: root.title !== ""
        text: root.title.toUpperCase()
        color: Theme.colors.accent
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.small
        font.bold: true
        font.letterSpacing: 0.5
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.lg
    }

    Column {
        id: bodyColumn
        anchors.top: headerLabel.visible ? headerLabel.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.lg
        anchors.topMargin: headerLabel.visible ? Theme.spacing.sm : Theme.spacing.lg
        spacing: Theme.spacing.sm
    }
}
