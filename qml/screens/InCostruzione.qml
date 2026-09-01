import QtQuick
import Theme
import "../components"

// Segnaposto TEMPORANEO per le sezioni non ancora ricostruite in QML
// (Anagrafica, Presenze, Statistiche, Macrociclo, Sedute, HubBoard,
// Coaching Board). A differenza del vecchio InArrivo.qml (cancellato con
// tutto il prototipo precedente), qui il nome/commento dichiara
// esplicitamente lo scopo: man mano che ogni schermata viene ricostruita,
// va tolta dalla mappa sezione->componente in App.qml, non lasciata
// raggiungibile "per sempre" come accadeva prima.
Item {
    property string nomeSezione: ""

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacing.md
        Text {
            text: nomeSezione.toUpperCase()
            color: Theme.colors.accent
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.title
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "Questa sezione non e' ancora stata ricostruita nel nuovo redesign."
            color: Theme.colors.textSecondary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.body
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
