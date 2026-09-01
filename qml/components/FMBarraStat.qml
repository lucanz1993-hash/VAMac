import QtQuick
import Theme

// Barra orizzontale per confronti relativi (percentuale presenze, minuti
// per mezzo di allenamento, ecc.) - alternativa leggera a un grafico
// dedicato, nello spirito FM di dati densi ma leggibili a colpo d'occhio.
Item {
    id: root

    property string etichetta: ""
    property string valoreTesto: ""
    property real percentuale: 0 // 0-100

    implicitHeight: 28
    implicitWidth: 260

    Text {
        id: label
        text: root.etichetta
        color: Theme.colors.textPrimary
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.small
        width: 140
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
        id: sfondoBarra
        anchors.left: label.right
        anchors.leftMargin: Theme.spacing.sm
        anchors.right: valoreLabel.left
        anchors.rightMargin: Theme.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        height: 14
        radius: Theme.radius.sm
        color: Theme.colors.bgSurface3

        Rectangle {
            height: parent.height
            radius: Theme.radius.sm
            color: Theme.colors.primario
            width: parent.width * Math.max(0, Math.min(100, root.percentuale)) / 100
            Behavior on width { NumberAnimation { duration: Theme.motion.transition; easing.type: Theme.motion.easeStandard } }
        }
    }

    Text {
        id: valoreLabel
        text: root.valoreTesto
        color: Theme.colors.textSecondary
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.caption
        width: 56
        horizontalAlignment: Text.AlignRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }
}
