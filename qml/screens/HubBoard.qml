import QtQuick
import QtQuick.Controls.Basic
import Theme
import "../components"

Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2

    property string filtroMezzo: "Tutti"

    // La schermata viene ricreata da zero ad ogni navigazione (stack.replace,
    // stesso pattern di Sedute/Macrociclo/Presenze), ma hubBoardVM e' lo
    // stesso oggetto Python per tutta la sessione e non si aggiornava mai da
    // solo dopo un salvataggio fatto altrove (nell'editor Lavagna Tattica):
    // tornando qui restavano visibili titolo/mezzo VECCHI (segnalato da
    // Luca). Mancava qui, a differenza di ogni altra schermata di questo
    // programma.
    Component.onCompleted: hubBoardVM.ricarica()

    function urlImmagine(percorso) {
        if (!percorso) return ""
        return "file:///" + percorso.replace(/\\/g, "/")
    }

    function mezziDisponibili() {
        var visti = {}
        var lista = ["Tutti"]
        for (var i = 0; i < hubBoardVM.boards.length; i++) {
            var m = hubBoardVM.boards[i].mezzo_allenamento
            if (m && !visti[m]) { visti[m] = true; lista.push(m) }
        }
        return lista
    }

    function boardsFiltrate() {
        if (root.filtroMezzo === "Tutti") return hubBoardVM.boards
        var risultato = []
        for (var i = 0; i < hubBoardVM.boards.length; i++) {
            if (hubBoardVM.boards[i].mezzo_allenamento === root.filtroMezzo) risultato.push(hubBoardVM.boards[i])
        }
        return risultato
    }

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        Row {
            width: parent.width
            spacing: Theme.spacing.md

            FMButton {
                primary: true
                text: "+ Nuova lavagna"
                onClicked: {
                    coachingBoardVM.nuovaLavagna()
                    navigazioneVM.vaiALavagnaEditor()
                }
            }

            Text { text: "Filtra per mezzo:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; anchors.verticalCenter: parent.verticalCenter }
            FMComboBox {
                id: comboFiltroMezzo
                width: 220
                model: root.mezziDisponibili()
                currentIndex: model.indexOf(root.filtroMezzo)
                onActivated: function(indice) { root.filtroMezzo = model[indice] }
                background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                contentItem: Text {
                    leftPadding: Theme.spacing.sm
                    text: comboFiltroMezzo.displayText
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            visible: hubBoardVM.messaggio !== ""
            text: hubBoardVM.messaggio
            color: Theme.colors.positive
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }

        FMCard {
            width: parent.width
            title: "Lavagne tattiche salvate (" + root.boardsFiltrate().length + " di " + hubBoardVM.boards.length + ")"

            Text {
                visible: hubBoardVM.boards.length === 0
                text: "Nessuna lavagna salvata. Usa \"+ Nuova lavagna\" per crearne una."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
                wrapMode: Text.WordWrap
                width: parent.width
            }
            Text {
                visible: hubBoardVM.boards.length > 0 && root.boardsFiltrate().length === 0
                text: "Nessuna lavagna per il mezzo selezionato."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Flow {
                width: parent.width
                spacing: Theme.spacing.md

                Repeater {
                    model: root.boardsFiltrate()
                    delegate: Rectangle {
                        width: 200
                        height: 250
                        radius: Theme.radius.md
                        color: Theme.colors.bgSurface2
                        border.width: 1
                        border.color: Theme.colors.border

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.sm
                            spacing: Theme.spacing.xs

                            Rectangle {
                                id: anteprimaMiniatura
                                width: parent.width
                                height: 120
                                radius: Theme.radius.sm
                                color: Theme.colors.bgSurface3
                                clip: true

                                Image {
                                    id: immagineMiniatura
                                    anchors.fill: parent
                                    source: root.urlImmagine(modelData.percorso_immagine)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                }
                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - Theme.spacing.sm
                                    visible: modelData.percorso_immagine !== "" && immagineMiniatura.status === Image.Error
                                    text: "⚠️ Immagine non trovata"
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    color: Theme.colors.warning
                                    font.family: Theme.typography.family
                                    font.pixelSize: Theme.typography.caption
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: immagineMiniatura.status === Image.Ready
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dialogoAnteprima.apri(root.urlImmagine(modelData.percorso_immagine), modelData.titolo)
                                }
                            }
                            Text {
                                width: parent.width
                                visible: (modelData.titolo || "") !== ""
                                text: modelData.titolo
                                color: Theme.colors.accent
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData.mezzo_allenamento || "Senza mezzo"
                                color: Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                                elide: Text.ElideRight
                            }
                            Flow {
                                width: parent.width
                                spacing: Theme.spacing.xs
                                FMButton { text: "Apri"; onClicked: hubBoardVM.apriBoard(modelData.id_board) }
                                FMButton { text: "Duplica"; onClicked: hubBoardVM.duplicaBoard(modelData.id_board) }
                                FMButton {
                                    destructive: true
                                    text: "Elimina"
                                    onClicked: dialogoConferma.apri(
                                        "Elimina lavagna",
                                        "Eliminare definitivamente questa grafica" + (modelData.titolo ? " (\"" + modelData.titolo + "\")" : "") + "? L'operazione non si può annullare.",
                                        "Elimina",
                                        function() { hubBoardVM.eliminaBoard(modelData.id_board) }
                                    )
                                }
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

    Popup {
        id: dialogoAnteprima
        parent: Overlay.overlay
        modal: true
        focus: true
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        width: Math.min(900, (Overlay.overlay ? Overlay.overlay.width - 60 : 900))
        height: Math.min(700, (Overlay.overlay ? Overlay.overlay.height - 60 : 700))
        padding: Theme.spacing.md

        property string titolo: ""

        function apri(sorgente, tit) {
            immagineGrande.source = sorgente
            dialogoAnteprima.titolo = tit || ""
            open()
        }

        background: Rectangle {
            color: Theme.colors.bgSurface; radius: Theme.radius.lg; border.width: 1; border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: dialogoAnteprima }
        }
        Overlay.modal: Rectangle { color: "#000000cc" }

        contentItem: Column {
            spacing: Theme.spacing.sm
            Text {
                visible: dialogoAnteprima.titolo !== ""
                text: dialogoAnteprima.titolo
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }
            Image {
                id: immagineGrande
                width: dialogoAnteprima.width - Theme.spacing.md * 2
                height: dialogoAnteprima.height - Theme.spacing.md * 2 - (dialogoAnteprima.titolo !== "" ? 40 : 0) - 44
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            FMButton { text: "Chiudi"; onClicked: dialogoAnteprima.close() }
        }
    }
}
