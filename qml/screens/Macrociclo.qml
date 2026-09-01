import QtQuick
import QtQuick.Controls.Basic
import Theme
import "../components"

Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    readonly property var giorni: ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]
    readonly property var etichetteGiorni: ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
    readonly property var tipiImpegno: [
        { c: "", l: "—" },
        { c: "A", l: "Allenamento" },
        { c: "C", l: "Campionato" },
        { c: "TM", l: "Test Match" },
        { c: "TA", l: "Torneo Amichevole" },
    ]
    function etichettaTipoImpegno(codice) {
        for (var i = 0; i < root.tipiImpegno.length; i++) {
            if (root.tipiImpegno[i].c === codice) return root.tipiImpegno[i].l
        }
        return codice
    }
    // Colore di sfondo per tipo di impegno: aiuta a distinguere a colpo
    // d'occhio allenamenti/partite senza dover leggere il testo di ogni
    // cella - verde/rosso restano riservati agli indicatori di stato
    // altrove nell'app. Torneo Amichevole usa "terziario" (viola) invece di
    // "warning": con "warning" era troppo simile a Campionato (identica in
    // Alto Contrasto, #ffd400 == #ffd400 - segnalato da Luca).
    function coloreSfondoTipo(codice) {
        if (codice === "C") return Qt.rgba(Theme.colors.accent.r, Theme.colors.accent.g, Theme.colors.accent.b, 0.22)
        if (codice === "TM") return Qt.rgba(Theme.colors.primario.r, Theme.colors.primario.g, Theme.colors.primario.b, 0.28)
        if (codice === "TA") return Qt.rgba(Theme.colors.terziario.r, Theme.colors.terziario.g, Theme.colors.terziario.b, 0.24)
        if (codice === "A") return Theme.colors.bgSurface3
        return Theme.colors.bgSurface2
    }

    // La schermata viene ricreata da zero (stack.replace) ogni volta che la
    // si riapre, ma macrocicloVM e' lo stesso oggetto Python per tutta la
    // sessione e non rilegge mai i gruppi da solo: senza questo refresh, un
    // gruppo creato altrove (es. in Anagrafica) non compariva mai qui finche'
    // non si riavviava l'app.
    Component.onCompleted: macrocicloVM.ricaricaGruppi()

    // Landing "Gruppi" sempre come primo stato all'apertura (creare/eliminare
    // un gruppo vive solo qui): entrare in un gruppo passa a false senza
    // deselezionarlo lato VM, cosi' "← Torna ai gruppi" non perde i dati gia'
    // caricati. E' uno stato solo-QML (non persistito nel VM) perche' la
    // schermata viene comunque ricreata da zero a ogni navigazione.
    property bool vistaGruppi: true

    readonly property string voceNuovaCategoria: "+ Nuova categoria…"
    // Base standard settore giovanile italiano, sempre in tendina anche a DB
    // vuoto (senza, su un'installazione nuova la tendina aveva SOLO
    // "+ Nuova categoria…", inutilizzabile - segnalato da Luca).
    readonly property var categorieDefault: [
        "Under 6", "Under 7", "Under 8", "Under 9", "Under 10", "Under 11", "Under 12",
        "Under 13", "Under 14", "Under 15", "Under 16", "Under 17", "Under 18", "Under 19",
        "Prima Squadra",
    ]
    // Tendina, non testo libero (richiesta di Luca): le voci sono la base
    // standard sopra piu' le categorie gia' in uso in DB (da qualunque
    // gruppo/societa', per club con nomenclatura propria) - una
    // "+ Nuova categoria…" resta l'unico punto dove si puo' ancora digitare
    // un nome mai visto prima.
    function elencoCategorieEsistenti() {
        var viste = {}, elenco = []
        for (var i = 0; i < root.categorieDefault.length; i++) {
            var c = root.categorieDefault[i]
            if (!viste[c]) { viste[c] = true; elenco.push(c) }
        }
        for (var j = 0; j < macrocicloVM.gruppi.length; j++) {
            var c2 = macrocicloVM.gruppi[j].cat
            if (!viste[c2]) { viste[c2] = true; elenco.push(c2) }
        }
        elenco.push(root.voceNuovaCategoria)
        return elenco
    }
    readonly property var categorieEsistenti: root.elencoCategorieEsistenti()

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        Text {
            visible: macrocicloVM.errore !== ""
            text: macrocicloVM.errore
            color: Theme.colors.danger
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
            wrapMode: Text.WordWrap
            width: parent.width
        }
        Text {
            visible: macrocicloVM.messaggio !== ""
            text: macrocicloVM.messaggio
            color: Theme.colors.positive
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }

        Column {
            id: vistaGruppiColonna
            visible: root.vistaGruppi
            width: parent.width
            spacing: Theme.spacing.lg

            Text {
                text: "Gruppi"
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }

            FMAlberoGruppi {
                width: parent.width
                gruppi: macrocicloVM.gruppi
                indiceSelezionato: macrocicloVM.indiceGruppo
                onSelezionato: function(indice) {
                    macrocicloVM.selezionaGruppo(indice)
                    root.vistaGruppi = false
                }
            }
            Row {
                width: parent.width
                spacing: Theme.spacing.sm
                FMComboBox {
                    id: campoNuovaCategoria
                    width: 170
                    model: root.categorieEsistenti
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    contentItem: Text {
                        leftPadding: Theme.spacing.sm
                        text: campoNuovaCategoria.displayText
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
                TextField {
                    id: campoCategoriaLibera
                    width: 150
                    visible: campoNuovaCategoria.currentText === root.voceNuovaCategoria
                    placeholderText: "Nome nuova categoria"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                TextField {
                    id: campoNuovaStagione
                    width: 120
                    placeholderText: "Stagione (2025/2026)"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                TextField {
                    id: campoNuovaSocieta
                    width: 160
                    placeholderText: "Società (vuoto = Spazio Personale)"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                FMButton {
                    primary: true
                    text: "+ Nuovo gruppo"
                    onClicked: {
                        var categoriaScelta = campoNuovaCategoria.currentText === root.voceNuovaCategoria ? campoCategoriaLibera.text : campoNuovaCategoria.currentText
                        var stagioneScelta = campoNuovaStagione.text
                        var societaScelta = campoNuovaSocieta.text
                        macrocicloVM.creaGruppo(categoriaScelta, stagioneScelta, societaScelta)
                        if (macrocicloVM.errore === "") {
                            campoNuovaStagione.text = ""; campoNuovaSocieta.text = ""; campoCategoriaLibera.text = ""
                            root.vistaGruppi = false
                            // Gruppo appena creato, senza giocatori: apre subito
                            // il popup di inserimento rosa invece di lasciare
                            // che il mister debba navigare a mano su Anagrafica.
                            anagraficaVM.selezionaGruppoPer(categoriaScelta.trim(), stagioneScelta.trim(), societaScelta.trim())
                            dialogoInserisciGiocatori.apri()
                        }
                    }
                }
                FMButton {
                    destructive: true
                    text: "Elimina gruppo"
                    enabled: macrocicloVM.indiceGruppo !== -1
                    onClicked: dialogoConferma.apri(
                        "Elimina gruppo",
                        "Eliminare definitivamente questo gruppo? Verranno cancellati macrociclo, sedute e giocatori (con le relative presenze). L'operazione non si può annullare.",
                        "Elimina",
                        function() { macrocicloVM.eliminaGruppoCorrente() }
                    )
                }
            }
        }

        Column {
            id: vistaSettimaneColonna
            visible: !root.vistaGruppi
            width: parent.width
            spacing: Theme.spacing.lg

            Row {
                width: parent.width
                spacing: Theme.spacing.md
                FMButton {
                    text: "← Torna ai gruppi"
                    onClicked: root.vistaGruppi = true
                }
                Text {
                    text: (macrocicloVM.indiceGruppo >= 0 && macrocicloVM.indiceGruppo < macrocicloVM.gruppi.length) ? macrocicloVM.gruppi[macrocicloVM.indiceGruppo].label : ""
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.subtitle
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                FMButton { text: "Aggiungi settimana"; onClicked: macrocicloVM.aggiungiSettimana() }
                FMButton { primary: true; text: "Salva tutto"; onClicked: macrocicloVM.salva() }
            }

            Text {
                visible: macrocicloVM.settimane.length === 0
                text: "Nessuna settimana. Usa \"Aggiungi settimana\" per iniziare."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Repeater {
                model: macrocicloVM.settimane
                delegate: FMCard {
                    id: cardSettimana
                    width: vistaSettimaneColonna.width
                    property var settimana: modelData
                    property bool espansa: false
                    title: "Settimana " + settimana.id_settimana

                    Row {
                        width: parent.width
                        spacing: Theme.spacing.sm

                        TextField {
                            width: parent.width - btnEspandi.width - btnEliminaSettimana.width - Theme.spacing.sm * 2
                            placeholderText: "Periodo (es. Pre-campionato)"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: cardSettimana.settimana.periodo
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            onEditingFinished: macrocicloVM.impostaCampo(cardSettimana.settimana.id_settimana, "periodo", text)
                        }
                        FMButton {
                            id: btnEspandi
                            text: cardSettimana.espansa ? "▾" : "▸"
                            onClicked: cardSettimana.espansa = !cardSettimana.espansa
                        }
                        FMButton {
                            id: btnEliminaSettimana
                            destructive: true
                            text: "🗑"
                            onClicked: dialogoConferma.apri(
                                "Elimina settimana",
                                "Eliminare la Settimana " + cardSettimana.settimana.id_settimana + "? Diventerà effettivo al prossimo \"Salva tutto\".",
                                "Elimina",
                                function() { macrocicloVM.eliminaSettimana(cardSettimana.settimana.id_settimana) }
                            )
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacing.xs

                    Repeater {
                        model: root.giorni
                        delegate: Column {
                            id: colonnaGiorno
                            width: (cardSettimana.width - Theme.spacing.lg * 2 - Theme.spacing.xs * 6) / 7
                            spacing: 2
                            property bool collegata: cardSettimana.settimana["idSeduta_" + modelData] > 0

                            Text {
                                text: root.etichetteGiorni[index]
                                color: Theme.colors.textSecondary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.caption
                                font.bold: true
                            }
                            FMComboBox {
                                id: comboTipoGiorno
                                width: parent.width
                                model: root.tipiImpegno
                                textRole: "l"
                                font.pixelSize: Theme.typography.small
                                currentIndex: {
                                    for (var i = 0; i < root.tipiImpegno.length; i++) {
                                        if (root.tipiImpegno[i].c === cardSettimana.settimana[modelData]) return i
                                    }
                                    return 0
                                }
                                background: Rectangle {
                                    color: root.coloreSfondoTipo(cardSettimana.settimana[modelData])
                                    radius: Theme.radius.sm
                                    border.width: colonnaGiorno.collegata ? 2 : 1
                                    border.color: colonnaGiorno.collegata ? Theme.colors.accent : Theme.colors.border
                                }
                                contentItem: Text {
                                    leftPadding: Theme.spacing.xs
                                    text: comboTipoGiorno.displayText
                                    color: Theme.colors.textPrimary
                                    font.family: Theme.typography.family
                                    font.pixelSize: Theme.typography.small
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                onActivated: function(indice) {
                                    var nuovoValore = root.tipiImpegno[indice].c
                                    if (nuovoValore === cardSettimana.settimana[modelData]) return
                                    // Se la cella e' gia' collegata a una seduta reale, chiedere
                                    // conferma prima di scollegare (senza eliminarla): cambiare
                                    // tipo lasciava in precedenza un disallineamento silenzioso
                                    // tra la cella e la seduta a cui restava agganciata.
                                    if (colonnaGiorno.collegata) {
                                        var idSett = cardSettimana.settimana.id_settimana
                                        var gg = modelData
                                        var indicePrecedente = comboTipoGiorno.currentIndex
                                        currentIndex = Qt.binding(function() {
                                            for (var i = 0; i < root.tipiImpegno.length; i++) {
                                                if (root.tipiImpegno[i].c === cardSettimana.settimana[gg]) return i
                                            }
                                            return 0
                                        })
                                        dialogoConferma.apri(
                                            "Cambia tipo impegno",
                                            "Questa cella è collegata a una seduta esistente. Cambiare il tipo la scollegherà (la seduta non verrà eliminata, resterà consultabile in Sedute/Presenze). Continuare?",
                                            "Scollega e cambia",
                                            function() {
                                                macrocicloVM.impostaGiorno(idSett, gg, nuovoValore)
                                                macrocicloVM.scollegaSeduta(idSett, gg)
                                            }
                                        )
                                    } else {
                                        macrocicloVM.impostaGiorno(cardSettimana.settimana.id_settimana, modelData, nuovoValore)
                                    }
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: 2
                                FMButton {
                                    width: colonnaGiorno.collegata ? (parent.width - 2) / 2 : parent.width
                                    text: "⋮"
                                    onClicked: {
                                        dialogoGiorno.idSettimanaCorrente = cardSettimana.settimana.id_settimana
                                        dialogoGiorno.giornoCorrente = modelData
                                        dialogoGiorno.etichettaGiorno = root.etichetteGiorni[index]
                                        dialogoGiorno.settimanaCorrente = cardSettimana.settimana
                                        dialogoGiorno.open()
                                    }
                                }
                                FMButton {
                                    width: (parent.width - 2) / 2
                                    visible: colonnaGiorno.collegata
                                    text: "📋"
                                    onClicked: macrocicloVM.apriPresenzeCollegate(cardSettimana.settimana.id_settimana, modelData)
                                }
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    visible: cardSettimana.espansa

                    Column {
                        width: (parent.width - Theme.spacing.sm * 2) / 3
                        spacing: 2
                        Text { text: "Obiettivo tecnico"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        TextField {
                            width: parent.width
                            placeholderText: "es. Passaggio corto"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: cardSettimana.settimana.obiettivo_tecnico
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            onEditingFinished: macrocicloVM.impostaCampo(cardSettimana.settimana.id_settimana, "obiettivo_tecnico", text)
                        }
                    }
                    Column {
                        width: (parent.width - Theme.spacing.sm * 2) / 3
                        spacing: 2
                        Text { text: "Obiettivo tattico"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        TextField {
                            width: parent.width
                            placeholderText: "es. Fuorigioco"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: cardSettimana.settimana.obiettivo_tattico
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            onEditingFinished: macrocicloVM.impostaCampo(cardSettimana.settimana.id_settimana, "obiettivo_tattico", text)
                        }
                    }
                    Column {
                        width: (parent.width - Theme.spacing.sm * 2) / 3
                        spacing: 2
                        Text { text: "Obiettivo condizionale"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        TextField {
                            width: parent.width
                            placeholderText: "es. Resistenza"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: cardSettimana.settimana.obiettivo_condizionale
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            onEditingFinished: macrocicloVM.impostaCampo(cardSettimana.settimana.id_settimana, "obiettivo_condizionale", text)
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 2
                    visible: cardSettimana.espansa
                    Text { text: "Note della settimana"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    TextField {
                        width: parent.width
                        placeholderText: "Note libere…"
                        placeholderTextColor: Theme.colors.textSecondary
                        text: cardSettimana.settimana.note
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        onEditingFinished: macrocicloVM.impostaCampo(cardSettimana.settimana.id_settimana, "note", text)
                    }
                }
            }
        }
        }
    }

    FMConfirmDialog {
        id: dialogoConferma
    }

    FMInserisciGiocatoriDialog {
        id: dialogoInserisciGiocatori
    }

    FMBoardPartitaDialog {
        id: boardPartitaDialog
        onRichiestaSalvataggio: function(datiJson) {
            macrocicloVM.salvaBoardPartita(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente, datiJson)
        }
    }

    Popup {
        id: dialogoGiorno
        // FIX: senza riparentare esplicitamente all'Overlay, il popup si
        // apriva fuori dai bordi della finestra, in basso (segnalato da
        // Luca) - stesso principio gia' applicato a dialogoArchivio
        // (FMEditorImmagineEsercizio.qml) e FMSelettoreData.qml. Il clamp
        // Math.max(0, ...) sotto evita inoltre y negativa se il contenuto
        // (molti pulsanti condizionali) risultasse piu' alto della finestra.
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        width: 420
        padding: Theme.spacing.lg

        property int idSettimanaCorrente: -1
        property string giornoCorrente: ""
        property string etichettaGiorno: ""
        property var settimanaCorrente: ({})

        readonly property string tipoCorrente: settimanaCorrente ? (settimanaCorrente[giornoCorrente] || "") : ""
        readonly property bool collegata: settimanaCorrente ? (settimanaCorrente["idSeduta_" + giornoCorrente] || 0) > 0 : false
        readonly property bool eImpegnoPartita: ["C", "TM", "TA"].indexOf(tipoCorrente) !== -1

        background: Rectangle {
            color: Theme.colors.bgSurface
            radius: Theme.radius.lg
            border.width: 1
            border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: dialogoGiorno }
        }
        Overlay.modal: Rectangle { color: "#000000aa" }

        contentItem: Column {
            width: dialogoGiorno.width - dialogoGiorno.padding * 2
            spacing: Theme.spacing.md

            Text {
                text: dialogoGiorno.etichettaGiorno + " — Settimana " + dialogoGiorno.idSettimanaCorrente
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }
            Text {
                text: dialogoGiorno.collegata
                    ? "Collegata a una seduta esistente."
                    : (dialogoGiorno.tipoCorrente ? "Nessuna seduta collegata." : "Imposta prima un tipo di impegno (es. A, TM, TA, C).")
                color: Theme.colors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            FMButton {
                width: parent.width
                primary: true
                // Solo per un allenamento: una partita/test/torneo non e' una
                // "seduta d'allenamento" generica, si gestisce con Board
                // Partita e Presenze (sotto), che creano da soli l'evento
                // collegato se non esiste ancora.
                visible: !dialogoGiorno.collegata && dialogoGiorno.tipoCorrente === "A"
                text: "Crea e collega seduta"
                onClicked: {
                    macrocicloVM.creaEColrgaSeduta(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    dialogoGiorno.close()
                }
            }
            FMButton {
                width: parent.width
                // Solo "Crea e collega" esisteva: una seduta gia' creata a
                // parte (es. in Sedute) non aveva modo di essere agganciata
                // a questa cella se non ricreandola duplicata - segnalato
                // da Luca ("o ne crea una nuova anche se ne esistono gia'").
                visible: !dialogoGiorno.collegata && dialogoGiorno.tipoCorrente === "A"
                text: "Collega seduta esistente"
                onClicked: {
                    dialogoCollegaSeduta.apri(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    dialogoGiorno.close()
                }
            }
            FMButton {
                width: parent.width
                // Non per le celle Partita/Campionato/Test Match: la seduta
                // collegata li' e' solo un ancoraggio per presenze/risultato
                // (niente blocchi di allenamento da editare) - Sedute.qml
                // non la elenca piu' (segnalato da Luca), quindi aprirla da
                // qui non porterebbe piu' a nulla di utile.
                visible: dialogoGiorno.collegata && !dialogoGiorno.eImpegnoPartita
                text: "Apri seduta collegata"
                onClicked: {
                    macrocicloVM.apriSedutaCollegata(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    dialogoGiorno.close()
                }
            }
            FMButton {
                width: parent.width
                primary: !dialogoGiorno.collegata && dialogoGiorno.eImpegnoPartita
                visible: dialogoGiorno.collegata || dialogoGiorno.eImpegnoPartita
                text: dialogoGiorno.collegata ? "Apri presenze" : "Crea evento e apri presenze"
                onClicked: {
                    if (!dialogoGiorno.collegata) macrocicloVM.creaEColrgaSeduta(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    macrocicloVM.apriPresenzeCollegate(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    dialogoGiorno.close()
                }
            }
            FMButton {
                width: parent.width
                visible: dialogoGiorno.eImpegnoPartita
                text: dialogoGiorno.collegata ? "Board Partita" : "Crea evento e apri Board Partita"
                onClicked: {
                    if (!dialogoGiorno.collegata) macrocicloVM.creaEColrgaSeduta(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    var convocati = macrocicloVM.convocatiPerCella(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    var dati = macrocicloVM.datiBoardPartita(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    boardPartitaDialog.apri(dialogoGiorno.tipoCorrente, convocati, dati)
                    dialogoGiorno.close()
                }
            }
            FMButton {
                width: parent.width
                visible: dialogoGiorno.eImpegnoPartita
                text: dialogoGiorno.collegata ? "Formazione" : "Crea evento e apri Formazione"
                onClicked: {
                    if (!dialogoGiorno.collegata) macrocicloVM.creaEColrgaSeduta(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    macrocicloVM.apriFormazioneCollegata(dialogoGiorno.idSettimanaCorrente, dialogoGiorno.giornoCorrente)
                    dialogoGiorno.close()
                }
            }
            FMButton {
                width: parent.width
                destructive: true
                visible: dialogoGiorno.collegata
                text: "Scollega seduta"
                onClicked: {
                    var idSett = dialogoGiorno.idSettimanaCorrente
                    var gg = dialogoGiorno.giornoCorrente
                    dialogoGiorno.close()
                    dialogoConferma.apri(
                        "Scollega seduta",
                        "Scollegare la seduta da questa cella? La seduta NON verrà eliminata: resterà consultabile in Sedute/Presenze, ma non più agganciata al Macrociclo.",
                        "Scollega",
                        function() { macrocicloVM.scollegaSeduta(idSett, gg) }
                    )
                }
            }
            FMButton {
                width: parent.width
                text: "Chiudi"
                onClicked: dialogoGiorno.close()
            }
        }
    }

    Popup {
        id: dialogoCollegaSeduta
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        width: 420
        height: Math.min(420, (Overlay.overlay ? Overlay.overlay.height - 40 : 420))
        padding: Theme.spacing.lg

        property int idSettimanaCorrente: -1
        property string giornoCorrente: ""
        property var elenco: []

        function apri(idSett, gg) {
            idSettimanaCorrente = idSett
            giornoCorrente = gg
            elenco = macrocicloVM.sedutePerCollegamento(idSett, gg)
            open()
        }

        background: Rectangle {
            color: Theme.colors.bgSurface
            radius: Theme.radius.lg
            border.width: 1
            border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: dialogoCollegaSeduta }
        }
        Overlay.modal: Rectangle { color: "#000000aa" }

        contentItem: Column {
            width: dialogoCollegaSeduta.width - dialogoCollegaSeduta.padding * 2
            spacing: Theme.spacing.md

            Text {
                text: "Collega seduta esistente"
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }
            Text {
                visible: dialogoCollegaSeduta.elenco.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Nessuna seduta esistente per questo gruppo. Usa \"Crea e collega seduta\" per crearne una nuova."
                color: Theme.colors.textTertiary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Flickable {
                width: parent.width
                height: 260
                clip: true
                contentWidth: width
                contentHeight: colonnaSedute.implicitHeight

                Column {
                    id: colonnaSedute
                    width: parent.width
                    spacing: Theme.spacing.xs

                    Repeater {
                        model: dialogoCollegaSeduta.elenco
                        delegate: Rectangle {
                            width: colonnaSedute.width
                            height: 46
                            radius: Theme.radius.sm
                            color: Theme.colors.bgSurface2
                            border.width: 1
                            border.color: Theme.colors.border

                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacing.xs
                                spacing: Theme.spacing.sm

                                Text {
                                    width: parent.width - 100 - Theme.spacing.sm
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: Theme.colors.textPrimary
                                    font.family: Theme.typography.family
                                    elide: Text.ElideRight
                                }
                                FMButton {
                                    width: 100
                                    anchors.verticalCenter: parent.verticalCenter
                                    primary: true
                                    text: "Collega"
                                    onClicked: {
                                        macrocicloVM.collegaSedutaEsistente(dialogoCollegaSeduta.idSettimanaCorrente, dialogoCollegaSeduta.giornoCorrente, modelData.id_seduta)
                                        dialogoCollegaSeduta.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            FMButton { width: parent.width; text: "Chiudi"; onClicked: dialogoCollegaSeduta.close() }
        }
    }
}
