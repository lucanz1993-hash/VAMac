import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Theme
import "../components"

// Disposizione dei convocati in campo per un evento partita (C/TM/TA),
// aperta da una cella di Macrociclo gia' collegata (mai sfogliata
// autonomamente - vedi MacrocicloVM.apriFormazioneCollegata). Riusa
// pesantemente CoachingBoard.qml: stesso componente sagoma giocatore
// (FMGiocatoreForma, colore=maglia/coloreContorno=pantaloncini), stessa
// geometria di campo intero (duplicata qui, non estratta in un componente
// condiviso - vedi piano "Formazione", decisione 1: CoachingBoard.qml legge
// proprieta' proprie del suo VM e gestisce anche "meta' campo", che qui non
// serve mai), stesso pattern di salvataggio/esportazione a due fasi
// (grabToImage poi confermaSalvataggio).
Item {
    id: root
    focus: true

    // Campo sempre grande quanto possibile: stessa formula reattiva di
    // CoachingBoard.qml (rapporto 700:460), ma qui SOLO "intero" - niente
    // rami "meta'"/"nessuna" da considerare.
    readonly property real areaDisponibileW: flickableCampo.width - Theme.spacing.xl * 2
    readonly property real areaDisponibileH: flickableCampo.height - Theme.spacing.xl * 2
    readonly property real scalaCampo: Math.max(0.6, Math.min(root.areaDisponibileW / 700, root.areaDisponibileH / 460))
    readonly property real larghezzaCampo: 700 * root.scalaCampo
    readonly property real altezzaCampo: 460 * root.scalaCampo

    // Non piu' readonly: la sidebar convocati e' allargabile via lo
    // splitter tra sidebar e campo (drag orizzontale, vedi sotto) - a
    // finestra ridotta il nome/cognome elidevano e nascondevano la riga,
    // impedendo di distinguere i giocatori prima di trascinarli in campo.
    property real larghezzaSidebar: 260
    readonly property real larghezzaSidebarMin: 200
    readonly property real larghezzaSidebarMax: 560

    readonly property real boxProfondita: 110 * root.scalaCampo
    readonly property real boxSpan: 260 * root.scalaCampo
    readonly property real areaPiccolaProfondita: 45 * root.scalaCampo
    readonly property real areaPiccolaSpan: 140 * root.scalaCampo
    readonly property real segnoPortaProfondita: 8 * 1.25 * root.scalaCampo
    readonly property real segnoPortaSpan: 50 * 1.25 * root.scalaCampo
    readonly property real arcoAngoloRaggio: 61 * root.scalaCampo
    readonly property real cerchioCentrocampoRaggio: 45 * root.scalaCampo
    readonly property real margineEsportazione: root.segnoPortaProfondita + 4

    // Colore campo/linee fissi: a differenza della Coaching Board, qui non
    // c'e' alcuna superficie di personalizzazione (non richiesto).
    readonly property color coloreCampo: "#1e7d32"
    readonly property color coloreLinee: "#ffffff"

    readonly property int dimensioneMarcatore: Math.round(44.8 * 0.75 * root.scalaCampo)
    readonly property real dimensioneTestoMarcatore: Theme.typography.caption * 1.5

    function coloriKit(piazzato) {
        if (piazzato.portiere) return { maglia: "#ffd400", pantaloncini: "#000000" }
        if (piazzato.squadra === "sq1") return { maglia: "#e0544f", pantaloncini: "#e0544f" }
        if (piazzato.squadra === "sq2") return { maglia: "#ffffff", pantaloncini: "#ffffff" }
        return { maglia: "#9aa0a6", pantaloncini: "#9aa0a6" }
    }

    // Stesso principio di apriMenuContestualeA in CoachingBoard.qml: blocca
    // il punto dentro i bordi dell'Overlay, cosi' il menu non apre parzialmente
    // fuori dalla finestra vicino ai bordi del campo.
    function apriMenuContestualeA(puntoOverlay) {
        var overlay = Overlay.overlay
        if (overlay && puntoOverlay) {
            menuGiocatore.parent = overlay
            menuGiocatore.x = Math.max(0, Math.min(puntoOverlay.x, overlay.width - menuGiocatore.implicitWidth))
            menuGiocatore.y = Math.max(0, Math.min(puntoOverlay.y, overlay.height - menuGiocatore.implicitHeight))
        }
        menuGiocatore.popup()
    }

    Column {
        id: colonnaPrincipale
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.lg

        Row {
            width: parent.width
            height: parent.height - barraInferiore.height - Theme.spacing.lg
            spacing: Theme.spacing.lg

            // ------------------------------------------------------------
            // Sidebar sinistra: roster completo dei convocati (Luca: "ne
            // convoco 18, devono comparire 18 giocatori"). Un piazzato NON
            // sparisce dalla lista - resta, solo attenuato + etichetta "in
            // campo": la lista che si accorcia mentre si trascina
            // romperebbe proprio il riscontro numerico voluto e sposterebbe
            // le righe sotto il cursore durante il drag.
            // ------------------------------------------------------------
            Flickable {
                id: barraLaterale
                width: root.larghezzaSidebar
                height: parent.height
                contentWidth: width
                contentHeight: colonnaSidebar.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: colonnaSidebar
                    width: parent.width
                    spacing: Theme.spacing.lg

                    FMCard {
                        width: parent.width
                        title: "Convocati (" + formazioneVM.roster.length + ")"

                        Column {
                            width: parent.width
                            spacing: Theme.spacing.xs

                            Text {
                                visible: formazioneVM.roster.length === 0
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "Nessun convocato per questo evento. Segna le convocazioni in Presenze prima di comporre la formazione."
                                color: Theme.colors.textSecondary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                            }

                            Repeater {
                                model: formazioneVM.roster
                                delegate: Rectangle {
                                    id: rigaConvocato
                                    property var datiGiocatore: modelData
                                    width: colonnaSidebar.width
                                    height: 40
                                    radius: Theme.radius.sm
                                    color: index % 2 === 0 ? "transparent" : Theme.colors.bgSurface2
                                    opacity: datiGiocatore.piazzato ? 0.5 : 1.0

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacing.sm
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rigaConvocato.datiGiocatore.cognome + " " + rigaConvocato.datiGiocatore.nome
                                        color: Theme.colors.textPrimary
                                        font.family: Theme.typography.family
                                        font.pixelSize: Theme.typography.body
                                        elide: Text.ElideRight
                                        width: parent.width - etichettaInCampo.width - Theme.spacing.md
                                    }
                                    Text {
                                        id: etichettaInCampo
                                        visible: rigaConvocato.datiGiocatore.piazzato
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacing.sm
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "in campo"
                                        color: Theme.colors.textTertiary
                                        font.family: Theme.typography.family
                                        font.pixelSize: Theme.typography.caption
                                        font.italic: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.OpenHandCursor
                                        onPressed: function(mouse) {
                                            fantasmaDrag.idGiocatoreDrag = rigaConvocato.datiGiocatore.id
                                            fantasmaDrag.parent = Overlay.overlay
                                            var p = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                                            fantasmaDrag.x = p.x - fantasmaDrag.width / 2
                                            fantasmaDrag.y = p.y - fantasmaDrag.height / 2
                                            fantasmaDrag.visible = true
                                        }
                                        onPositionChanged: function(mouse) {
                                            if (!fantasmaDrag.visible) return
                                            var p = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                                            fantasmaDrag.x = p.x - fantasmaDrag.width / 2
                                            fantasmaDrag.y = p.y - fantasmaDrag.height / 2
                                        }
                                        onReleased: function(mouse) {
                                            if (!fantasmaDrag.visible) return
                                            var pCampo = mapToItem(campoTattico, mouse.x, mouse.y)
                                            if (pCampo.x >= 0 && pCampo.x <= campoTattico.width && pCampo.y >= 0 && pCampo.y <= campoTattico.height) {
                                                formazioneVM.piazzaGiocatore(fantasmaDrag.idGiocatoreDrag, pCampo.x / campoTattico.width, pCampo.y / campoTattico.height)
                                            }
                                            fantasmaDrag.visible = false
                                            fantasmaDrag.parent = root
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------------
            // Splitter: trascina per allargare/restringere la sidebar.
            // Stesso principio di un divisore standard - delta relativo del
            // mouse sommato alla larghezza corrente, clampato ai limiti.
            // ------------------------------------------------------------
            Rectangle {
                id: separatoreSidebar
                width: 6
                height: parent.height
                radius: Theme.radius.sm
                color: areaSeparatore.containsMouse || areaSeparatore.pressed ? Theme.colors.accent : Theme.colors.border

                MouseArea {
                    id: areaSeparatore
                    anchors.fill: parent
                    anchors.leftMargin: -3
                    anchors.rightMargin: -3
                    cursorShape: Qt.SizeHorCursor
                    hoverEnabled: true
                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var nuova = root.larghezzaSidebar + mouse.x
                        // Il campo deve restare sempre utilizzabile anche a
                        // finestra ridotta (minimumWidth 1100 in App.qml):
                        // il limite massimo si adegua alla larghezza reale
                        // disponibile, non solo alla costante fissa.
                        var massimoDisponibile = colonnaPrincipale.width - separatoreSidebar.width - Theme.spacing.lg * 2 - 320
                        var massimo = Math.min(root.larghezzaSidebarMax, Math.max(root.larghezzaSidebarMin, massimoDisponibile))
                        root.larghezzaSidebar = Math.max(root.larghezzaSidebarMin, Math.min(massimo, nuova))
                    }
                }
            }

            // ------------------------------------------------------------
            // Campo, a destra della sidebar - stesso pattern "areaEsportabile"
            // di CoachingBoard.qml (margine per i segni di porta sporgenti,
            // altrimenti tagliati fuori da grabToImage).
            // ------------------------------------------------------------
            Flickable {
                id: flickableCampo
                width: parent.width - barraLaterale.width - separatoreSidebar.width - Theme.spacing.lg * 2
                height: parent.height
                contentWidth: Math.max(width, areaEsportabile.width)
                contentHeight: Math.max(height, areaEsportabile.height)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                Item {
                    id: areaEsportabile
                    objectName: "areaEsportabile"
                    width: campoTattico.width + 2 * root.margineEsportazione
                    height: campoTattico.height + 2 * root.margineEsportazione
                    x: Math.max(0, (parent.width - width) / 2)
                    y: Math.max(0, (parent.height - height) / 2)

                    Rectangle {
                        anchors.fill: parent
                        color: root.coloreCampo
                        radius: Theme.radius.md
                    }

                    Rectangle {
                        id: campoTattico
                        width: root.larghezzaCampo
                        height: root.altezzaCampo
                        x: root.margineEsportazione
                        y: root.margineEsportazione
                        color: root.coloreCampo
                        radius: Theme.radius.md
                        border.width: 4
                        border.color: root.coloreLinee

                        Canvas {
                            id: telaErba
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var r = Theme.radius.md
                                ctx.beginPath()
                                ctx.moveTo(r, 0)
                                ctx.arcTo(width, 0, width, height, r)
                                ctx.arcTo(width, height, 0, height, r)
                                ctx.arcTo(0, height, 0, 0, r)
                                ctx.arcTo(0, 0, width, 0, r)
                                ctx.closePath()
                                ctx.clip()
                                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.06)
                                var passoX = Math.max(24, width / 14)
                                for (var x = 0, bandaX = 0; x < width; x += passoX, bandaX++) {
                                    if (bandaX % 2 === 0) ctx.fillRect(x, 0, passoX, height)
                                }
                            }
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: parent.height
                            color: root.coloreLinee
                            opacity: 0.8
                        }
                        Item {
                            anchors.fill: parent
                            Rectangle {
                                readonly property real r: root.cerchioCentrocampoRaggio
                                x: parent.width / 2 - r
                                y: parent.height / 2 - r
                                width: r * 2; height: r * 2
                                radius: r
                                color: "transparent"
                                border.width: 2
                                border.color: root.coloreLinee
                                opacity: 0.8
                            }
                        }

                        // Lato sinistro: area di rigore + area piccola + porta.
                        Rectangle {
                            x: 0; y: (campoTattico.height - root.boxSpan) / 2
                            width: root.boxProfondita; height: root.boxSpan
                            color: "transparent"; border.width: 2; border.color: root.coloreLinee; opacity: 0.8
                        }
                        Rectangle {
                            x: 0; y: (campoTattico.height - root.areaPiccolaSpan) / 2
                            width: root.areaPiccolaProfondita; height: root.areaPiccolaSpan
                            color: "transparent"; border.width: 2; border.color: root.coloreLinee; opacity: 0.8
                        }
                        FMPortaCampo {
                            x: -root.segnoPortaProfondita; y: (campoTattico.height - root.segnoPortaSpan) / 2
                            width: root.segnoPortaProfondita; height: root.segnoPortaSpan
                            colore: root.coloreLinee
                            opacity: 0.8
                        }
                        Item {
                            x: root.boxProfondita; y: (root.altezzaCampo - 120 * root.scalaCampo) / 2
                            width: 30 * root.scalaCampo; height: 120 * root.scalaCampo
                            clip: true
                            Rectangle {
                                x: -98 * root.scalaCampo; y: -1
                                width: 122 * root.scalaCampo; height: 122 * root.scalaCampo; radius: root.arcoAngoloRaggio
                                color: "transparent"; border.width: 2; border.color: root.coloreLinee; opacity: 0.8
                            }
                        }

                        // Lato destro (speculare).
                        Rectangle {
                            x: root.larghezzaCampo - root.boxProfondita; y: (root.altezzaCampo - root.boxSpan) / 2
                            width: root.boxProfondita; height: root.boxSpan
                            color: "transparent"; border.width: 2; border.color: root.coloreLinee; opacity: 0.8
                        }
                        Rectangle {
                            x: root.larghezzaCampo - root.areaPiccolaProfondita; y: (root.altezzaCampo - root.areaPiccolaSpan) / 2
                            width: root.areaPiccolaProfondita; height: root.areaPiccolaSpan
                            color: "transparent"; border.width: 2; border.color: root.coloreLinee; opacity: 0.8
                        }
                        FMPortaCampo {
                            x: root.larghezzaCampo; y: (root.altezzaCampo - root.segnoPortaSpan) / 2
                            width: root.segnoPortaProfondita; height: root.segnoPortaSpan
                            colore: root.coloreLinee
                            opacity: 0.8
                        }
                        Item {
                            x: root.larghezzaCampo - 140 * root.scalaCampo; y: (root.altezzaCampo - 120 * root.scalaCampo) / 2
                            width: 30 * root.scalaCampo; height: 120 * root.scalaCampo
                            clip: true
                            Rectangle {
                                x: 6 * root.scalaCampo; y: -1
                                width: 122 * root.scalaCampo; height: 122 * root.scalaCampo; radius: root.arcoAngoloRaggio
                                color: "transparent"; border.width: 2; border.color: root.coloreLinee; opacity: 0.8
                            }
                        }

                        // Marcatori dei giocatori piazzati.
                        Repeater {
                            model: formazioneVM.piazzati
                            delegate: Item {
                                id: marcatore
                                property var dati: modelData
                                // Un giocatore puo' ora comparire piu' volte
                                // in campo (Luca: "trascinato anche due
                                // volte"): idGiocatore non basta piu' a
                                // identificare QUALE marcatore spostare/
                                // modificare, serve la sua posizione nella
                                // lista (stabile finche' non si rimuove un
                                // marcatore PRIMA di questo, come gia' fatto
                                // per i blocchi di Sedute.qml).
                                property int indicePiazzato: index
                                width: root.dimensioneMarcatore
                                height: root.dimensioneMarcatore
                                x: dati.x * campoTattico.width - width / 2
                                y: dati.y * campoTattico.height - height / 2
                                z: index

                                FMGiocatoreForma {
                                    id: sagoma
                                    anchors.fill: parent
                                    colore: root.coloriKit(marcatore.dati).maglia
                                    coloreContorno: root.coloriKit(marcatore.dati).pantaloncini
                                }
                                Text {
                                    anchors.top: parent.bottom
                                    anchors.topMargin: 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: marcatore.dati.cognome
                                    color: Theme.colors.textPrimary
                                    font.family: Theme.typography.family
                                    font.pixelSize: root.dimensioneTestoMarcatore
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    drag.target: marcatore
                                    drag.axis: Drag.XAndYAxis
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            menuGiocatore.indicePiazzato = marcatore.indicePiazzato
                                            var overlayPunto = Overlay.overlay
                                            root.apriMenuContestualeA(overlayPunto ? mapToItem(overlayPunto, mouse.x, mouse.y) : null)
                                        } else if (mouse.button === Qt.LeftButton) {
                                            // Cambio squadra immediato con un click sinistro (Luca:
                                            // "col tasto destro e' scomodo") - alterna sq1/sq2, il
                                            // menu contestuale resta solo per Portiere/Rimuovi, azioni
                                            // piu' rare. Qt non emette onClicked se il click e' in
                                            // realta' un trascinamento (drag.target sopra), quindi
                                            // riposizionare un marcatore non alterna mai la squadra
                                            // per errore.
                                            var nuovaSquadra = marcatore.dati.squadra === "sq1" ? "sq2" : "sq1"
                                            formazioneVM.impostaSquadra(marcatore.indicePiazzato, nuovaSquadra)
                                        }
                                    }
                                    onReleased: {
                                        var nuovaX = (marcatore.x + marcatore.width / 2) / campoTattico.width
                                        var nuovaY = (marcatore.y + marcatore.height / 2) / campoTattico.height
                                        formazioneVM.spostaGiocatore(marcatore.indicePiazzato, nuovaX, nuovaY)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------
        // Barra inferiore: stato + azioni.
        // ------------------------------------------------------------
        Column {
            id: barraInferiore
            width: parent.width
            spacing: Theme.spacing.xs

            Text {
                visible: formazioneVM.errore !== ""
                text: formazioneVM.errore
                color: Theme.colors.danger
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Text {
                visible: formazioneVM.messaggio !== ""
                text: formazioneVM.messaggio
                color: Theme.colors.positive
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Row {
                spacing: Theme.spacing.sm
                FMButton { text: "Chiudi"; onClicked: navigazioneVM.vaiA(1) }
                FMButton {
                    text: "Esporta immagine"
                    enabled: formazioneVM.piazzati.length > 0
                    onClicked: {
                        var percorso = formazioneVM.percorsoImmaginePerSalvataggio()
                        areaEsportabile.grabToImage(function(risultato) {
                            risultato.saveToFile(percorso)
                            formazioneVM.confermaSalvataggio(percorso)
                        })
                    }
                }
                FMButton {
                    primary: true
                    text: "Salva formazione"
                    // Se apriPer() e' fallito a meta' (es. errore di lettura
                    // DB), formazioneVM.piazzati viene azzerato e l'errore
                    // impostato: salvare comunque in quello stato
                    // sovrascriverebbe silenziosamente una formazione gia'
                    // salvata con una vuota. Stessa cautela gia' applicata
                    // al bottone "Salva presenze" di Presenze.qml.
                    enabled: formazioneVM.errore === ""
                    onClicked: formazioneVM.salva()
                }
            }
        }
    }

    // Fantasma trascinato dalla sidebar al campo (vedi MouseArea nel
    // delegate del roster sopra): un solo Item statico riparentato
    // sull'Overlay durante il drag, stesso trucco di riuso gia' impiegato
    // in CoachingBoard.qml per il menu contestuale, invece di istanziare/
    // distruggere dinamicamente un componente ad ogni drag.
    Item {
        id: fantasmaDrag
        visible: false
        width: root.dimensioneMarcatore
        height: root.dimensioneMarcatore
        z: 1000
        property int idGiocatoreDrag: -1
        FMGiocatoreForma {
            anchors.fill: parent
            colore: "#9aa0a6"
            coloreContorno: "#9aa0a6"
            opacity: 0.85
        }
    }

    Menu {
        id: menuGiocatore
        // Indice in formazioneVM.piazzati, non piu' idGiocatore: un
        // giocatore puo' comparire piu' volte in campo, serve identificare
        // QUESTO marcatore (vedi indicePiazzato sul delegate sopra).
        property int indicePiazzato: -1
        readonly property var piazzatoMenu: (indicePiazzato >= 0 && indicePiazzato < formazioneVM.piazzati.length)
            ? formazioneVM.piazzati[indicePiazzato] : null
        // Niente "checkable"/"checked" legato allo stato live del VM qui: un
        // MenuItem checkable riscrive "checked" internamente al click (un
        // assegnamento diretto, non tramite il VM), il che spezzerebbe per
        // sempre questo binding e mostrerebbe uno stato non piu' sincronizzato
        // riaprendo il menu su un giocatore diverso. Il colore del marcatore
        // in campo e' gia' il riscontro visivo dello stato attuale - il menu
        // resta un semplice elenco di azioni.
        // Sq.1/Sq.2 restano anche qui (oltre al click sinistro diretto sul
        // marcatore) perche' dal grigio "non assegnato" raggiungono la
        // squadra voluta in un click solo, mentre il toggle sinistro deve
        // sempre passare prima per Sq.1.
        MenuItem {
            text: "Sq.1 (rosso)"
            onTriggered: formazioneVM.impostaSquadra(menuGiocatore.indicePiazzato, "sq1")
        }
        MenuItem {
            text: "Sq.2 (bianco)"
            onTriggered: formazioneVM.impostaSquadra(menuGiocatore.indicePiazzato, "sq2")
        }
        MenuItem {
            text: "Portiere (attiva/disattiva)"
            onTriggered: formazioneVM.impostaPortiere(menuGiocatore.indicePiazzato, !(menuGiocatore.piazzatoMenu && menuGiocatore.piazzatoMenu.portiere))
        }
        MenuSeparator {}
        MenuItem {
            text: "Rimuovi dal campo"
            onTriggered: formazioneVM.rimuoviDalCampo(menuGiocatore.indicePiazzato)
        }
    }
}
