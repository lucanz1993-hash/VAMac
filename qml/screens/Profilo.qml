import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Window
import Theme
import "../components"

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
            title: "Il mio profilo"

            Text {
                text: profiloVM.email
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Text {
                text: profiloVM.ruolo + " — " + profiloVM.nomeSocieta
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Row {
                width: parent.width
                spacing: Theme.spacing.sm
                enabled: !profiloVM.offline

                TextField {
                    id: campoNome
                    width: parent.width - btnSalva.width - Theme.spacing.sm
                    text: profiloVM.nomeCognome
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                FMButton {
                    id: btnSalva
                    text: "Salva"
                    primary: true
                    onClicked: profiloVM.salvaNome(campoNome.text.trim())
                }
            }

            Text {
                visible: profiloVM.offline
                text: "In modalita' offline il profilo non e' modificabile."
                color: Theme.colors.textTertiary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.caption
            }
            Text {
                visible: profiloVM.messaggio !== ""
                text: profiloVM.messaggio
                color: Theme.colors.positive
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Text {
                visible: profiloVM.errore !== ""
                text: profiloVM.errore
                color: Theme.colors.danger
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
        }

        FMCard {
            // Scelta deliberata: NON gated su profiloVM.offline. Il tema e'
            // una preferenza puramente locale (QSettings), non un dato di
            // account — deve restare utilizzabile anche offline, a
            // differenza dei campi cloud-only della card sopra.
            width: parent.width
            title: "Aspetto"

            Text {
                text: "Scegli lo stile dell'interfaccia."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Flow {
                width: parent.width
                spacing: Theme.spacing.md

                Repeater {
                    model: ThemeManager.availableThemes
                    delegate: FMThemeSwatch {
                        temaId: modelData.id
                        nome: modelData.nome
                        previewBg: modelData.previewBg
                        previewSurface: modelData.previewSurface
                        previewAccent: modelData.previewAccent
                        selected: index === ThemeManager.currentIndex
                        onClicked: root.Window.window.temaOverlay.play(temaId)
                    }
                }
            }
        }

        FMCard {
            width: parent.width
            visible: profiloVM.puoGestireAccessi
            title: "Gestione Accessi: " + profiloVM.nomeSocieta

            Text {
                text: "Utenti con accesso a questo club:"
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Text {
                    visible: profiloVM.utentiClub.length === 0
                    text: "Nessun altro utente ha accesso a questo club."
                    color: Theme.colors.textTertiary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }

                Repeater {
                    model: profiloVM.utentiClub
                    delegate: Row {
                        width: parent.width
                        spacing: Theme.spacing.xs
                        Text {
                            width: parent.width - 90 - Theme.spacing.xs
                            text: "👤 " + modelData.email + "  [" + modelData.ruolo + "]"
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                            elide: Text.ElideRight
                        }
                        FMButton {
                            width: 90
                            destructive: true
                            text: "Rimuovi"
                            onClicked: dialogoConfermaAccessi.apri(
                                "Rimuovi accesso",
                                "Rimuovere l'accesso di " + modelData.email + " a questo club?",
                                "Rimuovi",
                                function() { profiloVM.rimuoviUtenteClub(modelData.email) }
                            )
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacing.sm
                TextField {
                    id: campoEmailInvito
                    width: parent.width - 110 - 90 - Theme.spacing.sm * 2
                    placeholderText: "Email utente da invitare…"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                FMComboBox {
                    id: comboRuoloInvito
                    width: 110
                    model: ["User", "Master", "Viewer"]
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    contentItem: Text {
                        leftPadding: Theme.spacing.sm
                        text: comboRuoloInvito.displayText
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                FMButton {
                    width: 90
                    primary: true
                    text: "Invita"
                    onClicked: {
                        profiloVM.invitaUtenteClub(campoEmailInvito.text, comboRuoloInvito.currentText)
                        campoEmailInvito.text = ""
                    }
                }
            }

            FMConfirmDialog { id: dialogoConfermaAccessi }
        }

        FMButton {
            width: parent.width
            text: "Esci"
            destructive: true
            onClicked: profiloVM.logout()
        }
    }
}
