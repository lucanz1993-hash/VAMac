import QtQuick
import Theme
import "../components"

// Home: layout "a mosaico" di card piccole (come da screenshot Football
// Manager reali), non un singolo pannello unico.
Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        FMCard {
            width: parent.width
            title: "Benvenuto"
            Text {
                text: "Ciao, " + dashboardVM.nomeUtente
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }
            Text {
                text: dashboardVM.nomeSocieta
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.body
            }
        }

        Text {
            visible: dashboardVM.errore !== ""
            text: dashboardVM.errore
            color: Theme.colors.danger
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.lg

            FMCard {
                width: (parent.width - Theme.spacing.lg) / 2
                title: "Prossima seduta"
                Text {
                    visible: !dashboardVM.haProssimaSeduta
                    text: "Nessuna seduta o impegno in programma nei prossimi giorni."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Column {
                    visible: dashboardVM.haProssimaSeduta
                    width: parent.width
                    spacing: Theme.spacing.xs
                    Text {
                        text: dashboardVM.prossimaSedutaConteggio
                        color: Theme.colors.accent
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.title
                        font.bold: true
                    }
                    Text {
                        text: dashboardVM.prossimaSedutaData
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.body
                    }
                    Text {
                        text: dashboardVM.prossimaSedutaEtichetta
                        color: Theme.colors.textSecondary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
            }
            FMCard {
                width: (parent.width - Theme.spacing.lg) / 2
                title: "Presenze da registrare"
                Text {
                    visible: dashboardVM.sedutePresenzeMancanti === 0
                    text: "Tutte le sedute recenti hanno le presenze registrate."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Column {
                    visible: dashboardVM.sedutePresenzeMancanti > 0
                    width: parent.width
                    spacing: Theme.spacing.xs
                    Text {
                        text: dashboardVM.sedutePresenzeMancanti
                        color: Theme.colors.warning
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.title
                        font.bold: true
                    }
                    Text {
                        text: "sedute delle ultime due settimane senza presenze registrate:"
                        color: Theme.colors.textSecondary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    Repeater {
                        // Quali, non solo quante (segnalato da Luca): un'etichetta
                        // gia' pronta per riga, costruita lato VM (stesso principio
                        // di prossimaSedutaEtichetta sopra).
                        model: dashboardVM.sedutePresenzeMancantiElenco
                        delegate: Text {
                            width: parent.width
                            text: "• " + modelData.etichetta
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
