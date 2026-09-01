import QtQuick
import Theme

// Side Bar: metodo primario di navigazione tra le sezioni del proprio club
// (terminologia del manuale ufficiale FM). Crest/logo in alto, voci di
// navigazione, voce Profilo/Impostazioni ancorata in fondo.
Rectangle {
    id: root

    property var voci: []            // [{ label, iconSource }]
    property int currentIndex: 0
    property string labelProfilo: "Profilo"
    property string iconProfilo: ""
    property bool profiloAttivo: false
    // Badge permanente modalita'/ruolo (es. "MODALITA' OFFLINE - TUTTI I
    // PERMESSI" o "CLOUD - MASTER"): nel vecchio widget era sempre visibile
    // in home, non solo navigando apposta dentro Profilo.
    property string testoBadge: ""
    property color coloreBadge: Theme.colors.warning

    signal selezionato(int index)
    signal profiloClicked()
    signal esciProgrammaClicked()

    implicitWidth: 220
    color: Theme.colors.bgSurface

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.colors.border
    }

    Column {
        id: logoArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.lg
        spacing: Theme.spacing.xs

        Text {
            text: "FC MANAGER"
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.subtitle
            font.bold: true
            font.letterSpacing: 1
        }

        Rectangle {
            visible: root.testoBadge !== ""
            width: parent.width
            height: badgeText.implicitHeight + Theme.spacing.xs * 2
            radius: Theme.radius.sm
            color: Qt.darker(root.coloreBadge, 2.6)
            border.width: 1
            border.color: root.coloreBadge

            Text {
                id: badgeText
                anchors.centerIn: parent
                width: parent.width - Theme.spacing.sm
                text: root.testoBadge
                color: root.coloreBadge
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.caption
                font.bold: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Rectangle {
        anchors.top: logoArea.bottom
        anchors.topMargin: Theme.spacing.md
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.colors.border
    }

    Column {
        id: vociColumn
        anchors.top: logoArea.bottom
        anchors.topMargin: Theme.spacing.lg
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
            model: root.voci
            delegate: FMSidebarItem {
                width: vociColumn.width
                label: modelData.label
                iconSource: modelData.iconSource
                active: !root.profiloAttivo && index === root.currentIndex
                onClicked: root.selezionato(index)
            }
        }
    }

    FMSidebarItem {
        id: esciProgrammaItem
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        label: "Esci dal Programma"
        active: false
        onClicked: root.esciProgrammaClicked()
    }

    Rectangle {
        anchors.bottom: profiloItem.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.colors.border
    }

    FMSidebarItem {
        id: profiloItem
        anchors.bottom: esciProgrammaItem.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: root.labelProfilo
        iconSource: root.iconProfilo
        active: root.profiloAttivo
        onClicked: root.profiloClicked()
    }
}
