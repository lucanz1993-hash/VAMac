import QtQuick
import QtQuick.Controls.Basic
import Theme

// Si apre da sola subito dopo aver creato un nuovo gruppo in Macrociclo
// (vedi Macrociclo.qml, bottone "+ Nuovo gruppo"): stesso inserimento
// nome/cognome ripetuto gia' presente in Anagrafica.qml, qui in un Popup
// cosi' il mister puo' popolare subito la rosa senza dover navigare via.
// Opera sul gruppo GIA' selezionato in anagraficaVM (il chiamante deve
// avere gia' fatto anagraficaVM.selezionaGruppoPer(...) prima di apri()).
Popup {
    id: root
    // Stesso reparent gia' applicato a FMConfirmDialog.qml/FMSelettoreData.qml:
    // senza, x/y sotto sono relativi al parent QML di dichiarazione invece
    // che alla finestra, e il dialogo puo' aprirsi fuori schermo.
    parent: Overlay.overlay
    modal: true
    focus: true
    x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
    y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
    width: 420
    padding: Theme.spacing.lg

    function apri() {
        campoNome.text = ""
        campoCognome.text = ""
        open()
    }

    background: Rectangle {
        color: Theme.colors.bgSurface; radius: Theme.radius.lg; border.width: 1; border.color: Theme.colors.border
        FMManigliaTrascinamento { bersaglio: root }
    }
    Overlay.modal: Rectangle { color: "#000000aa" }

    contentItem: Column {
        width: root.width - root.padding * 2
        spacing: Theme.spacing.md
        focus: true
        Keys.onEscapePressed: root.close()

        Text {
            text: "Inserisci giocatori"
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            font.bold: true
            font.pixelSize: Theme.typography.title
        }
        Text {
            text: "Gruppo creato. Aggiungi subito la rosa - potrai modificarla in qualunque momento da Anagrafica."
            color: Theme.colors.textSecondary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.sm

            TextField {
                id: campoNome
                width: (parent.width - btnAggiungi.width - Theme.spacing.sm * 2) / 2
                placeholderText: "Nome"
                placeholderTextColor: Theme.colors.textSecondary
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                KeyNavigation.tab: campoCognome
                Keys.onReturnPressed: campoCognome.forceActiveFocus()
            }
            TextField {
                id: campoCognome
                width: campoNome.width
                placeholderText: "Cognome"
                placeholderTextColor: Theme.colors.textSecondary
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                KeyNavigation.tab: campoNome
                Keys.onReturnPressed: btnAggiungi.clicked()
            }
            FMButton {
                id: btnAggiungi
                primary: true
                text: "Aggiungi"
                onClicked: {
                    anagraficaVM.aggiungiGiocatore(campoNome.text, campoCognome.text)
                    campoNome.text = ""
                    campoCognome.text = ""
                    campoNome.forceActiveFocus()
                }
            }
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

        Flickable {
            width: parent.width
            height: Math.min(220, colonnaLista.implicitHeight)
            contentWidth: width
            contentHeight: colonnaLista.implicitHeight
            clip: true

            Column {
                id: colonnaLista
                width: parent.width
                spacing: Theme.spacing.xs

                Text {
                    visible: anagraficaVM.giocatori.length === 0
                    text: "Nessun giocatore ancora aggiunto."
                    color: Theme.colors.textTertiary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }

                Repeater {
                    model: anagraficaVM.giocatori
                    delegate: Text {
                        width: colonnaLista.width
                        text: "• " + modelData.cognome + " " + modelData.nome
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                    }
                }
            }
        }

        Row {
            width: parent.width
            layoutDirection: Qt.RightToLeft
            FMButton {
                primary: true
                text: "Fatto"
                onClicked: root.close()
            }
        }
    }
}
