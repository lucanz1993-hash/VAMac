import QtQuick
import Theme

// Cella di tabella dati in stile FM: badge colorato per lo stato (presente/
// assente, W/D/L, ecc.) su sfondo pieno, mai un colore di brand.
Rectangle {
    id: root

    property string text: ""
    // "positive" | "negative" | "neutral" | "none"
    property string status: "none"

    readonly property color _bg: {
        switch (status) {
        case "positive": return Theme.colors.success
        case "negative": return Theme.colors.danger
        case "neutral": return Theme.colors.warning
        default: return "transparent"
        }
    }

    implicitWidth: label.implicitWidth + Theme.spacing.md * 2
    implicitHeight: 24
    radius: Theme.radius.sm
    color: status === "none" ? "transparent" : Qt.rgba(_bg.r, _bg.g, _bg.b, 0.18)
    border.width: status === "none" ? 0 : 1
    border.color: _bg

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.status === "none" ? Theme.colors.textPrimary : root._bg
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.small
        font.bold: root.status !== "none"
    }
}
