import QtQuick
import QtQuick.Controls.Basic
import Theme
import "../components"

Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2

    Component.onCompleted: anagraficaVM.ricaricaGruppi()

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        FMPannelloCollassabile {
            id: pannelloGruppo
            width: parent.width
            title: "Gruppo"
            riepilogo: (anagraficaVM.indiceGruppo >= 0 && anagraficaVM.indiceGruppo < anagraficaVM.gruppi.length) ? anagraficaVM.gruppi[anagraficaVM.indiceGruppo].label : ""

            Text {
                visible: anagraficaVM.gruppi.length === 0
                text: "Nessun gruppo disponibile."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            FMAlberoGruppi {
                width: parent.width
                gruppi: anagraficaVM.gruppi
                indiceSelezionato: anagraficaVM.indiceGruppo
                onSelezionato: function(indice) { anagraficaVM.selezionaGruppo(indice); pannelloGruppo.espanso = false }
            }

            // Creare/eliminare un gruppo si fa SOLO dalla schermata
            // Macrociclo (centralizzato li'): qui il gruppo e' solo
            // selezionabile tra quelli gia' esistenti, sempre sincronizzati
            // (vedi main.py, collegamento a macrocicloVM.gruppiCambiati).
            Text {
                visible: anagraficaVM.gruppi.length > 0
                text: "Per creare o eliminare un gruppo vai alla schermata Macrociclo."
                color: Theme.colors.textTertiary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.caption
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Text {
                visible: anagraficaVM.errore !== ""
                text: anagraficaVM.errore
                color: Theme.colors.danger
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
                wrapMode: Text.WordWrap
                width: parent.width
            }
            Text {
                visible: anagraficaVM.messaggio !== ""
                text: anagraficaVM.messaggio
                color: Theme.colors.positive
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
        }

        FMCard {
            width: parent.width
            title: "Nuovo giocatore"

            Row {
                width: parent.width
                spacing: Theme.spacing.sm

                TextField {
                    id: campoNomeNuovo
                    width: (parent.width - btnAggiungi.width - Theme.spacing.sm * 2) / 2
                    placeholderText: "Nome"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    KeyNavigation.tab: campoCognomeNuovo
                    Keys.onReturnPressed: campoCognomeNuovo.forceActiveFocus()
                }
                TextField {
                    id: campoCognomeNuovo
                    width: campoNomeNuovo.width
                    placeholderText: "Cognome"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    KeyNavigation.tab: campoNomeNuovo
                    Keys.onReturnPressed: btnAggiungi.clicked()
                }
                FMButton {
                    id: btnAggiungi
                    primary: true
                    text: "Aggiungi"
                    enabled: anagraficaVM.indiceGruppo !== -1
                    onClicked: {
                        anagraficaVM.aggiungiGiocatore(campoNomeNuovo.text, campoCognomeNuovo.text)
                        campoNomeNuovo.text = ""
                        campoCognomeNuovo.text = ""
                        campoNomeNuovo.forceActiveFocus()
                    }
                }
            }
        }

        FMCard {
            width: parent.width
            title: "Giocatori (" + anagraficaVM.giocatori.length + ")"

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Text {
                    visible: anagraficaVM.giocatori.length === 0
                    text: "Nessun giocatore in questo gruppo."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }

                Repeater {
                    model: anagraficaVM.giocatori
                    delegate: Rectangle {
                        id: rigaGiocatore
                        width: colonna.width - Theme.spacing.lg * 2
                        height: 40
                        radius: Theme.radius.sm
                        color: index % 2 === 0 ? "transparent" : Theme.colors.bgSurface2

                        property bool inModifica: false

                        Row {
                            visible: !rigaGiocatore.inModifica
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing.sm
                            spacing: Theme.spacing.sm
                            Text {
                                text: modelData.cognome + " " + modelData.nome
                                color: Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.body
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            visible: rigaGiocatore.inModifica
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Theme.spacing.sm
                            spacing: Theme.spacing.sm

                            TextField {
                                id: campoCognomeMod
                                width: 140
                                text: modelData.cognome
                                color: Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            }
                            TextField {
                                id: campoNomeMod
                                width: 140
                                text: modelData.nome
                                color: Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing.sm
                            spacing: Theme.spacing.xs

                            FMButton {
                                visible: rigaGiocatore.inModifica
                                primary: true
                                text: "Salva"
                                onClicked: {
                                    anagraficaVM.modificaGiocatore(modelData.id, campoNomeMod.text, campoCognomeMod.text)
                                    rigaGiocatore.inModifica = false
                                }
                            }
                            FMButton {
                                text: rigaGiocatore.inModifica ? "Annulla" : "Modifica"
                                onClicked: rigaGiocatore.inModifica = !rigaGiocatore.inModifica
                            }
                            FMButton {
                                visible: !rigaGiocatore.inModifica
                                destructive: true
                                text: "Elimina"
                                onClicked: dialogoConferma.apri(
                                    "Elimina giocatore",
                                    "Eliminare " + modelData.nome + " " + modelData.cognome + "? Non comparirà più tra i giocatori attivi, ma le sue presenze già registrate restano in archivio (statistiche e griglie presenze).",
                                    "Elimina",
                                    function() { anagraficaVM.eliminaGiocatore(modelData.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    FMConfirmDialog {
        id: dialogoConferma
    }
}
