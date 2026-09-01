import QtQuick
import Theme

// Esplorazione gerarchica Club/Spazio Personale: sostituisce la ComboBox
// piatta "società · categoria — stagione" con un vero albero (cartella "Il
// Mio Spazio Personale" + una cartella per club), indicatore attivo/archivio
// e conteggio elementi - stessa struttura del vecchio QTreeWidget
// (interfaccia_anagrafica.py/interfaccia_macrociclo.py/interfaccia_sedute.py)
// e del prototipo scartato, qui ricostruita come accordion dichiarativo
// invece che con un vero TreeView/modello Qt (non necessario per la
// profondita' a due soli livelli che serve qui).
//
// Semplificazione deliberata rispetto al vecchio widget: niente menu
// contestuale per creare/eliminare gruppi direttamente dall'albero - la
// creazione resta dove gia' vive oggi in ciascuna schermata (es. "Nuova
// seduta" in Sedute), l'eliminazione di un intero gruppo non era comunque
// mai stata ricostruita in questa sessione (gap segnalato a parte).
Column {
    id: root
    spacing: Theme.spacing.xs

    property var gruppi: []           // [{cat, stag, soc, isAttivo, conteggio}]
    property int indiceSelezionato: -1

    signal selezionato(int indice)

    function costruisciCartelle() {
        var personale = []
        var perClub = {}
        var ordineClub = []
        for (var i = 0; i < root.gruppi.length; i++) {
            var g = root.gruppi[i]
            var voce = { indice: i, cat: g.cat, stag: g.stag, soc: g.soc, isAttivo: g.isAttivo, conteggio: g.conteggio }
            if (g.soc) {
                if (!perClub[g.soc]) { perClub[g.soc] = []; ordineClub.push(g.soc) }
                perClub[g.soc].push(voce)
            } else {
                personale.push(voce)
            }
        }
        ordineClub.sort()
        var cartelle = [{ tipo: "personale", nome: "Il Mio Spazio Personale", voci: personale }]
        for (var j = 0; j < ordineClub.length; j++) {
            cartelle.push({ tipo: "club", nome: ordineClub[j], voci: perClub[ordineClub[j]] })
        }
        return cartelle
    }

    readonly property var cartelle: root.costruisciCartelle()

    Repeater {
        model: root.cartelle
        delegate: Column {
            id: cartellaDelegate
            width: root.width
            property bool espansa: true
            property var datiCartella: modelData

            Rectangle {
                width: parent.width
                height: 32
                radius: Theme.radius.sm
                color: Theme.colors.bgSurface2

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing.xs
                    Text {
                        text: cartellaDelegate.espansa ? "▾" : "▸"
                        color: Theme.colors.textTertiary
                        font.pixelSize: Theme.typography.caption
                    }
                    Text {
                        text: cartellaDelegate.datiCartella.tipo === "personale" ? "📁" : "🏢"
                        font.pixelSize: Theme.typography.small
                    }
                    Text {
                        text: cartellaDelegate.datiCartella.nome + " (" + cartellaDelegate.datiCartella.voci.length + ")"
                        color: cartellaDelegate.datiCartella.tipo === "personale" ? Theme.colors.textPrimary : Theme.colors.accent
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                        font.bold: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cartellaDelegate.espansa = !cartellaDelegate.espansa
                }
            }

            Column {
                width: parent.width
                visible: cartellaDelegate.espansa
                leftPadding: Theme.spacing.lg

                Text {
                    visible: cartellaDelegate.datiCartella.voci.length === 0
                    text: "Nessun gruppo qui."
                    color: Theme.colors.textTertiary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.caption
                }

                Repeater {
                    model: cartellaDelegate.datiCartella.voci
                    delegate: Rectangle {
                        width: cartellaDelegate.width - Theme.spacing.lg
                        height: 30
                        radius: Theme.radius.sm
                        property bool selezionata: modelData.indice === root.indiceSelezionato
                        color: selezionata ? Theme.colors.accentSoft : (mouseAreaVoce.containsMouse ? Theme.colors.bgSurface3 : "transparent")

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing.sm
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing.sm
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacing.xs

                            Text {
                                text: modelData.isAttivo ? "🟢" : "🗃️"
                                font.pixelSize: Theme.typography.caption
                            }
                            Text {
                                width: parent.width - 60
                                text: modelData.cat + " — " + modelData.stag
                                color: selezionata ? Theme.colors.accent : Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                                font.bold: selezionata
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "(" + modelData.conteggio + ")"
                                color: Theme.colors.textTertiary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.caption
                            }
                        }
                        MouseArea {
                            id: mouseAreaVoce
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selezionato(modelData.indice)
                        }
                    }
                }
            }
        }
    }
}
