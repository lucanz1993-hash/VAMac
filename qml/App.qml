import QtQuick
import QtQuick.Controls.Basic
import Theme
import "components"
import "screens"

ApplicationWindow {
    id: root
    width: 1440
    height: 900
    minimumWidth: 1100
    minimumHeight: 700
    visible: true
    title: "FC Manager"
    color: Theme.colors.bgMain

    property alias temaOverlay: overlay
    // Indice del blocco Sedute in attesa di un'immagine dalla Coaching
    // Board (flusso "Crea con Lavagna"): -1 quando la lavagna e' aperta
    // per un altro motivo (archivio HubBoard, nuova lavagna libera).
    property int bloccoLavagnaPendente: -1

    // Sezioni della Side Bar, nell'ordine in cui appaiono. "componente" e'
    // null per le sezioni non ancora ricostruite: la mappatura sotto le
    // mostra con InCostruzione.qml finche' non vengono rimpiazzate una per
    // volta, in ordine di rischio crescente, come da piano.
    // NOTA: i percorsi icona vanno risolti con Qt.resolvedUrl() qui, nel
    // file che li dichiara — passati come semplice string a componenti
    // annidati (FMSidebar -> FMSidebarItem -> Image), un url relativo si
    // risolverebbe altrimenti rispetto al file che CONSUMA la stringa
    // (qml/components/FMSidebarItem.qml), non a questo file, sbagliando di
    // un livello di cartella.
    readonly property var sezioni: [
        { label: "Dashboard", iconSource: Qt.resolvedUrl("../assets/icons/home.svg"), componente: dashboardComponent },
        { label: "Macrociclo", iconSource: Qt.resolvedUrl("../assets/icons/calendar.svg"), componente: macrocicloComponent },
        { label: "Sedute", iconSource: Qt.resolvedUrl("../assets/icons/activity.svg"), componente: seduteComponent },
        { label: "Anagrafica", iconSource: Qt.resolvedUrl("../assets/icons/users.svg"), componente: anagraficaComponent },
        { label: "Presenze", iconSource: Qt.resolvedUrl("../assets/icons/check-square.svg"), componente: presenzeComponent },
        { label: "Statistiche", iconSource: Qt.resolvedUrl("../assets/icons/bar-chart.svg"), componente: statisticheComponent },
        { label: "Lavagna", iconSource: Qt.resolvedUrl("../assets/icons/board.svg"), componente: hubBoardComponent },
    ]

    Component { id: dashboardComponent; Dashboard {} }
    Component { id: profiloComponent; Profilo {} }
    Component { id: anagraficaComponent; Anagrafica {} }
    Component { id: presenzeComponent; Presenze {} }
    Component { id: statisticheComponent; Statistiche {} }
    Component { id: macrocicloComponent; Macrociclo {} }
    Component { id: seduteComponent; Sedute {} }
    Component { id: hubBoardComponent; HubBoard {} }
    Component { id: coachingBoardComponent; CoachingBoard {} }
    Component { id: formazioneComponent; Formazione {} }
    Component {
        id: inCostruzioneComponent
        InCostruzione { nomeSezione: root.sezioni[navigazioneVM.corrente] ? root.sezioni[navigazioneVM.corrente].label : "" }
    }

    function componentePerCorrente() {
        if (navigazioneVM.profiloAttivo) return profiloComponent
        if (navigazioneVM.lavagnaAttiva) return coachingBoardComponent
        if (navigazioneVM.formazioneAttiva) return formazioneComponent
        var sezione = root.sezioni[navigazioneVM.corrente]
        if (sezione && sezione.componente) return sezione.componente
        return inCostruzioneComponent
    }

    Row {
        id: contenutoPrincipale
        anchors.fill: parent

        FMSidebar {
            id: sidebar
            height: parent.height
            voci: root.sezioni
            currentIndex: navigazioneVM.corrente
            profiloAttivo: navigazioneVM.profiloAttivo
            labelProfilo: "Profilo"
            iconProfilo: Qt.resolvedUrl("../assets/icons/user.svg")
            testoBadge: profiloVM.offline
                ? "MODALITA' OFFLINE — TUTTI I PERMESSI"
                : "CLOUD — " + profiloVM.ruolo.toUpperCase() + (profiloVM.nomeSocieta !== "Nessun club" ? " · " + profiloVM.nomeSocieta : "")
            coloreBadge: profiloVM.offline ? Theme.colors.warning : Theme.colors.accent
            onSelezionato: function(index) { navigazioneVM.vaiA(index) }
            onProfiloClicked: navigazioneVM.vaiAProfilo()
            onEsciProgrammaClicked: Qt.quit()
        }

        Column {
            width: parent.width - sidebar.width
            height: parent.height

            // Title Bar: frecce di navigazione, ricerca, azione principale —
            // terminologia e struttura dal manuale ufficiale FM.
            Rectangle {
                width: parent.width
                height: 56
                color: Theme.colors.bgSurface
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.colors.border }

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacing.lg
                    spacing: Theme.spacing.md

                    Text {
                        text: "‹"
                        color: navigazioneVM.puoIndietro ? Theme.colors.textPrimary : Theme.colors.textTertiary
                        font.pixelSize: Theme.typography.title
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: navigazioneVM.puoIndietro
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            // Alcune schermate (Macrociclo, Sedute) hanno un "drill" interno
                            // (lista gruppi/sedute -> dettaglio) che e' stato solo-QML, mai
                            // registrato nella storico di navigazioneVM: senza questo controllo,
                            // il tasto "indietro" saltava quello stato intermedio e andava
                            // sempre direttamente alla sezione precedente (es. Dashboard),
                            // ignorando che l'utente era "entrato in un gruppo" (segnalato da
                            // Luca). Se la schermata corrente espone puoIndietroLocale/
                            // indietroLocale() lo usiamo per il primo passo indietro; altrimenti
                            // (ogni altra schermata) si comporta come prima.
                            onClicked: {
                                if (stack.currentItem && stack.currentItem.puoIndietroLocale) stack.currentItem.indietroLocale()
                                else navigazioneVM.indietro()
                            }
                        }
                    }
                    Text {
                        text: "›"
                        color: navigazioneVM.puoAvanti ? Theme.colors.textPrimary : Theme.colors.textTertiary
                        font.pixelSize: Theme.typography.title
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: navigazioneVM.puoAvanti
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: navigazioneVM.avanti()
                        }
                    }
                    Item {
                        id: barraRicerca
                        width: 260; height: 32
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius.sm
                            color: Theme.colors.bgSurface2
                            border.width: 1
                            border.color: campoRicerca.activeFocus ? Theme.colors.accent : Theme.colors.border

                            Text {
                                visible: campoRicerca.text === ""
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacing.sm
                                anchors.verticalCenter: parent.verticalCenter
                                text: "🔍  Cerca giocatori, gruppi, sedute..."
                                color: Theme.colors.textTertiary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                            }
                            TextField {
                                id: campoRicerca
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacing.xs
                                anchors.rightMargin: Theme.spacing.xs
                                color: Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                                background: Item {}
                                onTextChanged: ricercaVM.cerca(text)
                                Keys.onEscapePressed: { text = ""; focus = false }
                            }
                        }

                        Popup {
                            id: popupRisultati
                            y: barraRicerca.height + 4
                            width: 360
                            padding: Theme.spacing.xs
                            visible: campoRicerca.activeFocus && ricercaVM.risultati.length > 0
                            background: Rectangle { color: Theme.colors.bgSurface; radius: Theme.radius.md; border.width: 1; border.color: Theme.colors.border }
                            contentItem: Column {
                                width: 360 - Theme.spacing.xs * 2
                                Repeater {
                                    model: ricercaVM.risultati
                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 36
                                        radius: Theme.radius.sm
                                        color: areaRisultato.containsMouse ? Theme.colors.bgSurface2 : "transparent"
                                        Text {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: Theme.spacing.sm
                                            anchors.rightMargin: Theme.spacing.sm
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            text: (modelData.tipo === "gruppo" ? "📁 " : modelData.tipo === "giocatore" ? "👤 " : "📅 ") + modelData.label
                                            color: Theme.colors.textPrimary
                                            font.family: Theme.typography.family
                                            font.pixelSize: Theme.typography.small
                                        }
                                        MouseArea {
                                            id: areaRisultato
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                ricercaVM.apriRisultato(index)
                                                campoRicerca.text = ""
                                                campoRicerca.focus = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StackView {
                id: stack
                width: parent.width
                height: parent.height - 56
                initialItem: root.componentePerCorrente()

                pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motion.transition; easing.type: Theme.motion.easeStandard } }
                pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motion.transition } }
                replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motion.transition; easing.type: Theme.motion.easeStandard } }
                replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.motion.transition } }
            }
        }
    }

    FMThemeTransitionOverlay {
        id: overlay
        // NON root.contentItem: e' il QQuickRootItem interno creato in C++
        // da ApplicationWindow, non dall'engine QML - grabToImage() ci
        // fallisce silenziosamente ("item has no QML engine"), il callback
        // non parte mai e ThemeManager.setThemeById() non viene mai
        // chiamato: risultato, le skin non si potevano selezionare
        // (segnalato da Luca). contenutoPrincipale e' un Item vero, creato
        // dall'engine caricando questo file: ha un QML engine associato.
        target: contenutoPrincipale
    }

    function aggiornaSchermata() {
        stack.replace(root.componentePerCorrente())
    }

    Connections {
        target: navigazioneVM
        function onCorrenteCambiata() { root.aggiornaSchermata() }
        function onProfiloAttivoCambiato() { root.aggiornaSchermata() }
        function onLavagnaAttivaCambiata() { root.aggiornaSchermata() }
        function onFormazioneAttivaCambiata() { root.aggiornaSchermata() }
    }

    Connections {
        target: hubBoardVM
        function onApriLavagnaRichiesta(idBoard, titolo, mezzo, datiVettoriali, descrizione, modalitaCampo, coloreCampo, coloreLinee) {
            coachingBoardVM.caricaLavagna(idBoard, titolo, mezzo, datiVettoriali, descrizione, modalitaCampo, coloreCampo, coloreLinee)
            navigazioneVM.vaiALavagnaEditor()
        }
    }

    // Collegamento cella-seduta in Macrociclo: "Apri seduta"/"Apri presenze"
    // su una cella gia' collegata naviga alla schermata giusta con lo stesso
    // gruppo e la stessa seduta gia' selezionati, invece di lasciare
    // l'utente a cercarla di nuovo manualmente.
    Connections {
        target: macrocicloVM
        function onRichiestaAperturaSeduta(cat, stag, soc, idSeduta) {
            seduteVM.selezionaGruppoPer(cat, stag, soc)
            seduteVM.selezionaSedutaPerId(idSeduta)
            navigazioneVM.vaiA(2)
        }
        function onRichiestaAperturaPresenze(cat, stag, soc, idSeduta) {
            presenzeVM.selezionaGruppoPer(cat, stag, soc)
            presenzeVM.selezionaSedutaPerId(idSeduta)
            navigazioneVM.vaiA(4)
        }
        function onRichiestaAperturaFormazione(cat, stag, soc, idSeduta) {
            formazioneVM.apriPer(cat, stag, soc, idSeduta)
            navigazioneVM.vaiAFormazione()
        }
    }

    // Ricerca globale (Title Bar): apre il gruppo/seduta trovato esattamente
    // come gia' fa il collegamento cella-seduta di Macrociclo qui sopra.
    Connections {
        target: ricercaVM
        function onRichiestaAperturaGruppo(indiceSezione, cat, stag, soc) {
            anagraficaVM.selezionaGruppoPer(cat, stag, soc)
            navigazioneVM.vaiA(indiceSezione)
        }
        function onRichiestaAperturaSeduta(indiceSezione, cat, stag, soc, idSeduta) {
            seduteVM.selezionaGruppoPer(cat, stag, soc)
            seduteVM.selezionaSedutaPerId(idSeduta)
            navigazioneVM.vaiA(indiceSezione)
        }
    }

    // "Crea con Lavagna" dall'editor immagine di un blocco Sedute: apre una
    // lavagna vuota; al salvataggio, l'immagine prodotta torna a riempire
    // proprio quel blocco e la navigazione rientra su Sedute da sola.
    Connections {
        target: seduteVM
        function onRichiestaAperturaLavagnaPerBlocco(indice) {
            root.bloccoLavagnaPendente = indice
            coachingBoardVM.nuovaLavagna()
            navigazioneVM.vaiALavagnaEditor()
        }
    }
    Connections {
        target: coachingBoardVM
        function onSalvataggioCompletato(percorsoImmagine) {
            // Aggiorna subito l'archivio anche SENZA navigare li' (Luca: "ogni
            // modifica salvata deve comparire ed essere sincronizzata") -
            // Component.onCompleted in HubBoard.qml copre gia' il rientro
            // navigando, questo copre anche il caso in cui non ci si torni.
            hubBoardVM.ricarica()
            if (root.bloccoLavagnaPendente >= 0) {
                seduteVM.impostaCampoEsercitazione(root.bloccoLavagnaPendente, "immagine", percorsoImmagine)
                root.bloccoLavagnaPendente = -1
                seduteVM.segnalaSaltaLanding()
                navigazioneVM.vaiA(2)
            }
        }
    }
}
