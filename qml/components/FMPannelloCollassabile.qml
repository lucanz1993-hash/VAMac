import QtQuick
import QtQuick.Effects
import Theme

// Card GRUPPO (e simili) riducibile a una riga compatta una volta fatta una
// scelta, per non occupare sempre tutto lo spazio verticale in cima alla
// schermata - richiesto su Macrociclo/Anagrafica/Sedute, che prima usavano
// tre pattern diversi e non riusabili (mostraAlberoGruppi in Macrociclo,
// nulla in Anagrafica, sempre visibile in Sedute). Non fa il wrap di FMCard
// per evitare di annidare due volte l'aliasing di default property/contentData.
//
// Comportamento: se "riepilogo" e' vuoto (nulla ancora selezionato) il
// contenuto resta sempre visibile, qualunque sia "espanso" - non avrebbe
// senso collassare un pannello che non ha nulla da riassumere. Una volta che
// "riepilogo" diventa non vuoto, il pannello si collassa da solo (espanso
// default false) mostrando solo la riga compatta; il pulsante "Cambia"
// riapre il contenuto pieno. Per ri-collassare dopo una nuova scelta, la
// schermata chiamante imposta esplicitamente "espanso: false" nel proprio
// handler di selezione (un'unica riga in piu' per schermata).
Rectangle {
    id: root

    default property alias contenuto: corpo.data
    // Pulsanti d'azione (es. "Aggiungi settimana"/"Salva tutto") che restano
    // SEMPRE visibili anche a pannello collassato, a differenza di
    // "contenuto" (tipicamente l'albero gruppi): assegnati con la sintassi a
    // lista, es. `azioni: [FMButton {...}, FMButton {...}]`.
    property alias azioni: rigaAzioni.data
    property string title: ""
    property string riepilogo: ""
    property bool espanso: false

    readonly property bool mostraContenuto: root.espanso || root.riepilogo === ""
    readonly property bool haAzioni: rigaAzioni.children.length > 0

    color: Theme.colors.bgSurface
    radius: Theme.radius.lg
    border.width: 1
    border.color: Theme.colors.border
    implicitHeight: Theme.spacing.lg * 2 + intestazione.height
        + (root.haAzioni ? Theme.spacing.sm + rigaAzioni.implicitHeight : 0)
        + (root.mostraContenuto ? Theme.spacing.sm + corpo.implicitHeight : 0)

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: Theme.elevation.level1.opacity
        shadowBlur: Theme.elevation.level1.blurRadius / 32
        shadowVerticalOffset: Theme.elevation.level1.offsetY
    }

    Item {
        id: intestazione
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.lg
        height: Math.max(titolo.implicitHeight, bottoneEspandi.implicitHeight)

        Text {
            id: titolo
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.title.toUpperCase()
            color: Theme.colors.accent
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
            font.bold: true
            font.letterSpacing: 0.5
        }
        Text {
            visible: !root.mostraContenuto && root.riepilogo !== ""
            anchors.left: titolo.right
            anchors.leftMargin: Theme.spacing.sm
            anchors.right: bottoneEspandi.left
            anchors.rightMargin: Theme.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: "· " + root.riepilogo
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            font.bold: true
            font.pixelSize: Theme.typography.small
        }
        FMButton {
            id: bottoneEspandi
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.riepilogo !== ""
            text: root.mostraContenuto ? "▴ Chiudi" : "▾ Cambia"
            onClicked: root.espanso = !root.mostraContenuto
        }
    }

    Flow {
        id: rigaAzioni
        anchors.top: intestazione.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.lg
        anchors.topMargin: Theme.spacing.sm
        spacing: Theme.spacing.xs
    }

    Column {
        id: corpo
        visible: root.mostraContenuto
        anchors.top: root.haAzioni ? rigaAzioni.bottom : intestazione.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacing.lg
        anchors.topMargin: Theme.spacing.sm
        spacing: Theme.spacing.sm
    }
}
