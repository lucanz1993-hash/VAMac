import QtQuick
import Theme

// Mini-pannello interno, senza ombra: da usare DENTRO una FMCard per
// raggruppare un sotto-insieme di campi (es. una riga di statistiche).
Rectangle {
    id: root

    default property alias contentData: bodyColumn.data
    property string title: ""

    color: Theme.colors.bgSurface2
    radius: Theme.radius.md
    implicitHeight: (headerLabel.visible ? headerLabel.height + Theme.spacing.xs : 0) + bodyColumn.implicitHeight + Theme.spacing.md * 2

    Text {
        id: headerLabel
        visible: root.title !== ""
        text: root.title.toUpperCase()
        color: Theme.colors.textSecondary
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.caption
        font.bold: true
        font.letterSpacing: 0.5
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.md
    }

    Column {
        id: bodyColumn
        anchors.top: headerLabel.visible ? headerLabel.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.md
        anchors.topMargin: headerLabel.visible ? Theme.spacing.xs : Theme.spacing.md
        spacing: Theme.spacing.xs
    }
}
