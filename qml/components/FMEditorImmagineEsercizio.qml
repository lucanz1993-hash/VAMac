import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Theme

// Editor grafica esercizio: stessa funzionalita' del vecchio widget
// (interfaccia_seduta.py, QLabel con menu contestuale + drag&drop) — carica
// da PC, crea disegnandola sulla Coaching Board, cerca tra le lavagne gia'
// salvate in archivio, o rimuove l'immagine collegata al blocco.
Item {
    id: root
    width: 220
    height: 140

    property string percorsoImmagine: ""

    signal richiestaImposta(string percorso)
    signal richiestaRimozione()
    signal richiestaCreaConLavagna()

    function urlAPercorso(url) {
        var s = url.toString()
        var prefisso = "file:///"
        if (s.indexOf(prefisso) === 0) s = s.substring(prefisso.length)
        return decodeURIComponent(s)
    }

    Rectangle {
        id: cornice
        anchors.fill: parent
        radius: Theme.radius.sm
        color: Theme.colors.bgSurface3
        border.width: 1
        border.color: areaTrascinamento.containsDrag ? Theme.colors.accent : Theme.colors.border

        Image {
            id: anteprima
            anchors.fill: parent
            anchors.margins: 3
            visible: root.percorsoImmagine !== "" && status !== Image.Error
            source: root.percorsoImmagine !== "" ? "file:///" + root.percorsoImmagine : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - Theme.spacing.md
            visible: root.percorsoImmagine === ""
            text: "Nessuna immagine\nclic per opzioni, o trascina un file qui"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.colors.textTertiary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - Theme.spacing.md
            visible: root.percorsoImmagine !== "" && anteprima.status === Image.Error
            text: "⚠️ File immagine eliminato o spostato dal PC"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.colors.warning
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }

        DropArea {
            id: areaTrascinamento
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: function(drop) {
                if (!drop.hasUrls || drop.urls.length === 0) return
                var percorso = root.urlAPercorso(drop.urls[0])
                if (/\.(png|jpg|jpeg)$/i.test(percorso)) root.richiestaImposta(percorso)
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                // Lo stile Basic non riposiziona da solo un Menu che
                // aprirebbe fuori dalla finestra: per un blocco vicino al
                // fondo della lista "Cerca in Archivio" finiva irraggiungibile
                // (segnalato da Luca). Si calcola il punto in coordinate
                // dell'Overlay e si blocca dentro i suoi bordi, stesso
                // principio gia' usato per centrare i Popup di questo
                // programma su Overlay.overlay.
                var overlay = Overlay.overlay
                if (overlay) {
                    var p = mapToItem(overlay, mouse.x, mouse.y)
                    menuOpzioni.parent = overlay
                    menuOpzioni.x = Math.max(0, Math.min(p.x, overlay.width - menuOpzioni.implicitWidth))
                    menuOpzioni.y = Math.max(0, Math.min(p.y, overlay.height - menuOpzioni.implicitHeight))
                }
                menuOpzioni.popup()
            }
        }
    }

    Menu {
        id: menuOpzioni
        MenuItem { text: "📂 Carica immagine da PC"; onTriggered: dialogoFile.open() }
        MenuItem { text: "🎨 Crea con Lavagna"; onTriggered: root.richiestaCreaConLavagna() }
        MenuItem { text: "📚 Cerca in Archivio"; onTriggered: dialogoArchivio.apri() }
        MenuSeparator {}
        MenuItem {
            text: "🗑️ Rimuovi immagine"
            enabled: root.percorsoImmagine !== ""
            onTriggered: dialogoConfermaRimozione.apri(
                "Rimuovi immagine",
                "Rimuovere l'immagine collegata a questo blocco?",
                "Rimuovi",
                function() { root.richiestaRimozione() }
            )
        }
    }

    FMConfirmDialog {
        id: dialogoConfermaRimozione
    }

    FileDialog {
        id: dialogoFile
        title: "Seleziona immagine esercizio"
        nameFilters: ["Immagini (*.png *.jpg *.jpeg)"]
        onAccepted: root.richiestaImposta(root.urlAPercorso(selectedFile))
    }

    Popup {
        id: dialogoArchivio
        // Senza reparent esplicito, x/y sotto sono relativi al parent QML di
        // dichiarazione (root di questo componente, profondamente annidato
        // dentro un blocco Sedute) invece che alla finestra: il popup si
        // apriva quasi fuori schermo (segnalato da Luca). Stesso principio
        // gia' applicato a FMConfirmDialog.
        parent: Overlay.overlay
        modal: true
        focus: true
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        width: 520
        height: Math.min(540, (Overlay.overlay ? Overlay.overlay.height - 40 : 540))
        padding: Theme.spacing.md

        property string filtroMezzo: ""
        property string filtroTesto: ""

        function apri() {
            filtroMezzo = ""
            filtroTesto = ""
            hubBoardVM.ricarica()
            open()
        }

        // Valori distinti di mezzo_allenamento presenti in archivio, per il
        // filtro a tendina (dinamico, non un elenco fisso: cambia con quello
        // che l'utente ha davvero salvato, stesso principio di Categoria).
        function mezziDisponibili() {
            var visti = {}
            var elenco = []
            for (var i = 0; i < hubBoardVM.boards.length; i++) {
                var m = hubBoardVM.boards[i].mezzo_allenamento
                if (m && !visti[m]) { visti[m] = true; elenco.push(m) }
            }
            elenco.sort()
            return elenco
        }

        // Letta dentro un binding (model: dialogoArchivio.elencoFiltrato()),
        // quindi si rivaluta da sola quando filtroMezzo/filtroTesto/boards
        // cambiano - QML traccia le property lette DENTRO la funzione come
        // dipendenze del binding, non serve altro collegamento esplicito.
        function elencoFiltrato() {
            var testo = filtroTesto.trim().toLowerCase()
            return hubBoardVM.boards.filter(function(b) {
                if (filtroMezzo !== "" && b.mezzo_allenamento !== filtroMezzo) return false
                if (testo !== "" && b.titolo.toLowerCase().indexOf(testo) === -1 && b.mezzo_allenamento.toLowerCase().indexOf(testo) === -1) return false
                return true
            })
        }

        background: Rectangle {
            color: Theme.colors.bgSurface
            radius: Theme.radius.lg
            border.width: 1
            border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: dialogoArchivio }
        }
        Overlay.modal: Rectangle { color: "#000000aa" }

        contentItem: Column {
            spacing: Theme.spacing.sm

            Text {
                text: "Archivio Grafiche Coaching Board"
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }
            Text {
                visible: hubBoardVM.boards.length === 0
                text: "Nessuna lavagna salvata in archivio."
                color: Theme.colors.textTertiary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Row {
                width: 500
                spacing: Theme.spacing.sm
                visible: hubBoardVM.boards.length > 0

                FMComboBox {
                    id: comboFiltroMezzo
                    width: 180
                    model: ["Tutti i mezzi"].concat(dialogoArchivio.mezziDisponibili())
                    currentIndex: 0
                    onActivated: dialogoArchivio.filtroMezzo = currentIndex === 0 ? "" : currentText
                }
                TextField {
                    width: 500 - 180 - Theme.spacing.sm
                    placeholderText: "Cerca per titolo o mezzo…"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    onTextChanged: dialogoArchivio.filtroTesto = text
                }
            }
            Text {
                visible: hubBoardVM.boards.length > 0 && dialogoArchivio.elencoFiltrato().length === 0
                text: "Nessun risultato per questo filtro."
                color: Theme.colors.textTertiary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Flickable {
                width: 500
                height: 350
                clip: true
                contentWidth: width
                contentHeight: colonnaArchivio.implicitHeight

                Column {
                    id: colonnaArchivio
                    width: parent.width
                    spacing: Theme.spacing.xs

                    Repeater {
                        // BUG: prima leggeva sempre hubBoardVM.boards (elenco
                        // completo, non filtrato) - i filtri mezzo/testo
                        // aggiornavano filtroMezzo/filtroTesto e il messaggio
                        // "Nessun risultato" (che usa elencoFiltrato()), ma
                        // la lista vera e propria restava quella intera:
                        // sembravano non fare nulla (segnalato da Luca).
                        model: dialogoArchivio.elencoFiltrato()
                        delegate: Rectangle {
                            width: colonnaArchivio.width
                            height: 70
                            radius: Theme.radius.sm
                            color: Theme.colors.bgSurface2
                            border.width: 1
                            border.color: Theme.colors.border

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacing.xs
                                spacing: Theme.spacing.sm

                                Image {
                                    width: 90; height: parent.height
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    source: modelData.percorso_immagine !== "" ? "file:///" + modelData.percorso_immagine : ""
                                }
                                Column {
                                    width: parent.width - 90 - 90 - Theme.spacing.sm * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: modelData.titolo !== "" ? modelData.titolo : "(senza titolo)"
                                        color: Theme.colors.textPrimary
                                        font.family: Theme.typography.family
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    Text {
                                        text: modelData.mezzo_allenamento + (modelData.categoria !== "" ? " · " + modelData.categoria : "")
                                        color: Theme.colors.textSecondary
                                        font.family: Theme.typography.family
                                        font.pixelSize: Theme.typography.small
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }
                                FMButton {
                                    width: 90
                                    anchors.verticalCenter: parent.verticalCenter
                                    primary: true
                                    text: "Usa questa"
                                    onClicked: {
                                        root.richiestaImposta(modelData.percorso_immagine)
                                        dialogoArchivio.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            FMButton { text: "Chiudi"; onClicked: dialogoArchivio.close() }
        }
    }
}
