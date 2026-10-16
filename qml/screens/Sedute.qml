import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Theme
import "../components"

Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2

    property bool mostraGestioneMenu: false

    // Landing "Sedute di questo gruppo" sempre come primo stato all'apertura
    // (stesso pattern di Macrociclo/vistaGruppi): prima la schermata apriva
    // subito il dettaglio dell'ultima seduta, spesso non quella cercata -
    // "scomodo", segnalato da Luca. Entrare in una seduta passa a false
    // senza deselezionarla lato VM, cosi' "← Torna alle sedute" non perde i
    // dati gia' caricati. E' uno stato solo-QML perche' la schermata viene
    // comunque ricreata da zero a ogni navigazione (vedi sotto).
    // FIX (stesso bug segnalato da Luca per Macrociclo, identico qui): era
    // "property bool vistaElenco: true" fisso - tornare qui con "indietro"
    // da un'altra sezione dopo aver gia' aperto una seduta specifica la
    // trovava sempre sull'elenco, perdendo il dettaglio su cui si stava
    // lavorando. seduteVM.sedutaCaricata resta vera sull'oggetto Python
    // (mai azzerata dalla sola navigazione) finche' non si elimina/chiude
    // davvero la seduta: il binding entra quindi subito nel dettaglio
    // quando ce n'e' uno gia' aperto in questa sessione.
    property bool vistaElenco: !seduteVM.sedutaCaricata
    // Stesso meccanismo di Macrociclo.qml: il tasto "‹" globale in App.qml
    // legge queste due proprieta' per far tornare "indietro" prima
    // all'elenco sedute, poi (un secondo clic) alla sezione precedente.
    readonly property bool puoIndietroLocale: !vistaElenco
    function indietroLocale() { vistaElenco = true }

    // La schermata viene ricreata da zero (stack.replace) ogni volta che la
    // si riapre, ma seduteVM e' lo stesso oggetto Python per tutta la
    // sessione e non rilegge mai i gruppi da solo: senza questo refresh, un
    // gruppo creato altrove (es. in Anagrafica) non compariva mai qui finche'
    // non si riavviava l'app.
    Component.onCompleted: {
        seduteVM.ricaricaGruppi()
        // Navigazione da Macrociclo ("Apri seduta collegata") o dalla
        // ricerca globale: la seduta giusta e' gia' stata selezionata prima
        // di aprire questa schermata, quindi si entra subito nel dettaglio
        // invece di passare comunque dall'elenco.
        if (seduteVM.consumaSaltaLanding()) root.vistaElenco = false
    }

    FolderDialog {
        id: dialogoCartellaPdf
        title: "Scegli la cartella per il PDF"
        onAccepted: {
            var percorso = selectedFolder.toString()
            var prefisso = "file:///"
            if (percorso.indexOf(prefisso) === 0) percorso = percorso.substring(prefisso.length)
            seduteVM.esportaPdfInCartella(decodeURIComponent(percorso))
        }
    }

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        Text {
            visible: seduteVM.errore !== ""
            text: seduteVM.errore
            color: Theme.colors.danger
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
            wrapMode: Text.WordWrap
            width: parent.width
        }
        Text {
            visible: seduteVM.messaggio !== ""
            text: seduteVM.messaggio
            color: Theme.colors.positive
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }

        Column {
            id: vistaElencoColonna
            visible: root.vistaElenco
            width: parent.width
            spacing: Theme.spacing.lg

            FMPannelloCollassabile {
                id: pannelloGruppo
                width: parent.width
                title: "Gruppo (cartella in cui viene salvata la seduta)"
                riepilogo: (seduteVM.indiceGruppo >= 0 && seduteVM.indiceGruppo < seduteVM.gruppi.length) ? seduteVM.gruppi[seduteVM.indiceGruppo].label : ""
                azioni: [
                    FMButton {
                        text: seduteVM.modalitaGk ? "Modo: Portieri" : "Modo: Standard"
                        onClicked: seduteVM.impostaModalitaGk(!seduteVM.modalitaGk)
                    }
                ]

                Text {
                    visible: seduteVM.gruppi.length === 0
                    text: "Nessun gruppo disponibile."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }
                FMAlberoGruppi {
                    width: parent.width
                    gruppi: seduteVM.gruppi
                    indiceSelezionato: seduteVM.indiceGruppo
                    onSelezionato: function(indice) { seduteVM.selezionaGruppo(indice); pannelloGruppo.espanso = false }
                }
            }

            Text {
                text: "Sedute di questo gruppo"
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }

            Text {
                visible: seduteVM.sedute.length === 0
                text: "Nessuna seduta in questo gruppo. Creane una qui sotto."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Repeater {
                model: seduteVM.sedute
                delegate: Rectangle {
                    width: parent.width
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
                            width: parent.width - 90 - 90 - Theme.spacing.sm * 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            elide: Text.ElideRight
                        }
                        FMButton {
                            width: 90
                            anchors.verticalCenter: parent.verticalCenter
                            primary: true
                            text: "Apri"
                            onClicked: { seduteVM.selezionaSeduta(index); root.vistaElenco = false }
                        }
                        FMButton {
                            width: 90
                            anchors.verticalCenter: parent.verticalCenter
                            destructive: true
                            text: "Elimina"
                            onClicked: dialogoConferma.apri(
                                "Elimina seduta",
                                "Eliminare definitivamente la seduta \"" + modelData.label + "\"? Tutti i blocchi e le presenze collegate andranno persi. L'operazione non si può annullare.",
                                "Elimina",
                                function() { seduteVM.selezionaSeduta(index); seduteVM.eliminaSedutaCorrente() }
                            )
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2
                Text { text: "Crea una nuova seduta in questo gruppo"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                Flow {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    FMSelettoreData {
                        id: campoNuovaData
                        formato: "it"
                        placeholder: "GG-MM-AAAA"
                    }
                    FMButton {
                        primary: true
                        text: "Crea nuova seduta"
                        onClicked: {
                            seduteVM.nuovaSeduta(campoNuovaData.valore)
                            if (seduteVM.errore === "") {
                                campoNuovaData.valore = ""
                                // Creata apposta per lavorarci subito: entra
                                // direttamente nel dettaglio invece di
                                // lasciare l'utente sull'elenco a doverla
                                // ritrovare e riaprire.
                                root.vistaElenco = false
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2
                Text { text: "Zona pericolosa"; color: Theme.colors.danger; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                FMButton {
                    destructive: true
                    text: "Elimina tutte le sedute del gruppo (" + seduteVM.sedute.length + ")"
                    enabled: seduteVM.sedute.length > 0
                    onClicked: dialogoConferma.apri(
                        "Elimina tutte le sedute",
                        "Eliminare definitivamente tutte le " + seduteVM.sedute.length + " sedute di questo gruppo? Blocchi e presenze collegate andranno persi. L'operazione non si può annullare.",
                        "Elimina tutte",
                        function() { seduteVM.eliminaTutteLeSeduteDelGruppo() }
                    )
                }
            }
        }

        Column {
            id: vistaDettaglioColonna
            visible: !root.vistaElenco
            width: parent.width
            spacing: Theme.spacing.lg

            Row {
                width: parent.width
                spacing: Theme.spacing.md
                FMButton {
                    text: "← Torna alle sedute"
                    onClicked: root.vistaElenco = true
                }
                Text {
                    text: (seduteVM.indiceGruppo >= 0 && seduteVM.indiceGruppo < seduteVM.gruppi.length) ? seduteVM.gruppi[seduteVM.indiceGruppo].label : ""
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.subtitle
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Column {
                width: parent.width
                spacing: 2
                Text { text: "Duplica o sposta la seduta selezionata"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                Flow {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    FMButton {
                        text: "Duplica seduta (stessa data)"
                        onClicked: seduteVM.duplicaSedutaCorrente()
                    }
                    FMSelettoreData {
                        id: campoSpostaData
                        formato: "it"
                        placeholder: "GG-MM-AAAA"
                    }
                    FMButton {
                        text: "Sposta a questa data"
                        onClicked: { seduteVM.spostaSedutaCorrente(campoSpostaData.valore); campoSpostaData.valore = "" }
                    }
                }
            }

            FMCard {
                width: parent.width
                visible: seduteVM.sedutaCaricata
                title: "Dettaglio seduta — " + seduteVM.dataSeduta + " (" + seduteVM.numeroSeduta + ")"

                Column {
                    width: parent.width
                    spacing: 4
                    Text { text: "Obiettivo principale:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small }
                    TextField {
                        width: parent.width
                        text: seduteVM.obiettivoPrincipale
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        placeholderText: "Cosa si allena oggi — esce in alto nel PDF esportato"
                        placeholderTextColor: Theme.colors.textSecondary
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        onEditingFinished: seduteVM.impostaObiettivoPrincipale(text)
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    Text { text: "N. seduta:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; anchors.verticalCenter: parent.verticalCenter }
                    TextField {
                        width: 90
                        text: seduteVM.numeroSeduta
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        onEditingFinished: seduteVM.impostaNumeroSeduta(text)
                    }
                    Text { text: "Giocatori:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; anchors.verticalCenter: parent.verticalCenter }
                    TextField {
                        width: 60
                        text: String(seduteVM.giocatoriPresenti)
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        onEditingFinished: seduteVM.impostaGiocatoriPresenti(text)
                    }
                    Text { text: "Società:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; anchors.verticalCenter: parent.verticalCenter }
                    TextField {
                        width: 160
                        text: seduteVM.societaStampa
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        onEditingFinished: seduteVM.impostaSocietaStampa(text)
                    }
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    FMButton { text: "Aggiungi blocco"; onClicked: seduteVM.aggiungiBlocco() }
                    FMButton { primary: true; text: "Salva seduta"; onClicked: seduteVM.salvaSeduta() }
                    FMButton {
                        text: "Esporta PDF"
                        onClicked: {
                            // Prima esportava sempre nella cartella fissa
                            // PDF_Sedute senza possibilita' di scegliere:
                            // il selettore riparte dall'ultima cartella usata
                            // con successo (persistita in QSettings).
                            var base = seduteVM.cartellaEsportazionePdfDefault().replace(/\\/g, "/")
                            dialogoCartellaPdf.currentFolder = "file:///" + base
                            dialogoCartellaPdf.open()
                        }
                    }
                    FMButton { text: root.mostraGestioneMenu ? "Chiudi voci menu" : "Gestisci voci menu"; onClicked: root.mostraGestioneMenu = !root.mostraGestioneMenu }
                    FMButton {
                        destructive: true
                        text: "Elimina questa seduta"
                        onClicked: dialogoConferma.apri(
                            "Elimina seduta",
                            "Eliminare definitivamente la seduta del " + seduteVM.dataSeduta + "? Tutti i blocchi e le presenze collegate andranno persi. L'operazione non si può annullare.",
                            "Elimina",
                            function() { seduteVM.eliminaSedutaCorrente(); root.vistaElenco = true }
                        )
                    }
                }

                // Posizionato QUI, subito dopo i pulsanti e PRIMA dei blocchi:
                // se creato come card separata in coda alla colonna, con piu'
                // di un blocco compilato finiva fuori dalla vista visibile e
                // serviva scorrere parecchio per ritrovarlo ogni volta che si
                // voleva aggiungere una voce al vocabolario.
                FMPanel {
                    width: parent.width
                    visible: root.mostraGestioneMenu
                    title: "Gestisci voci menu" + (seduteVM.modalitaGk ? " (Portieri)" : "")

                    Row {
                        width: parent.width
                        spacing: Theme.spacing.lg

                        Repeater {
                            model: [
                                { categoria: "Mezzi", etichetta: "Mezzi", voci: seduteVM.listaMezzi },
                                { categoria: "Tecnici", etichetta: "Obiettivi tecnici", voci: seduteVM.listaTecnici },
                                { categoria: "Tattici", etichetta: "Obiettivi tattici", voci: seduteVM.listaTattici },
                            ]
                            delegate: FMPanel {
                                id: pannelloCategoria
                                width: (parent.width - Theme.spacing.lg * 2) / 3
                                title: modelData.etichetta
                                // Salvate come property proprie: il Repeater interno
                                // sotto ha un proprio "modelData" (la singola voce di
                                // testo) che nasconde questo, quindi le voci lette da
                                // li' devono passare da qui e non da modelData diretto.
                                property string categoria: modelData.categoria
                                property var voci: modelData.voci

                                Column {
                                    width: parent.width
                                    spacing: Theme.spacing.xs

                                    Repeater {
                                        model: pannelloCategoria.voci
                                        delegate: Row {
                                            width: parent.width
                                            spacing: Theme.spacing.xs
                                            Text {
                                                width: parent.width - 30
                                                text: modelData
                                                color: Theme.colors.textPrimary
                                                font.family: Theme.typography.family
                                                font.pixelSize: Theme.typography.small
                                                elide: Text.ElideRight
                                            }
                                            FMButton {
                                                width: 30; height: 26
                                                destructive: true
                                                text: "×"
                                                onClicked: {
                                                    var categoria = pannelloCategoria.categoria
                                                    var voce = modelData
                                                    dialogoConferma.apri(
                                                        "Rimuovi voce",
                                                        "Rimuovere \"" + voce + "\" dall'elenco " + pannelloCategoria.title + "?",
                                                        "Rimuovi",
                                                        function() { seduteVM.rimuoviVoceMenu(categoria, voce) }
                                                    )
                                                }
                                            }
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacing.xs
                                        TextField {
                                            id: campoNuovaVoce
                                            width: parent.width - 40
                                            placeholderText: "Nuova voce…"
                                            placeholderTextColor: Theme.colors.textSecondary
                                            color: Theme.colors.textPrimary
                                            font.family: Theme.typography.family
                                            font.pixelSize: Theme.typography.small
                                            background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                            onAccepted: { seduteVM.aggiungiVoceMenu(pannelloCategoria.categoria, text); text = "" }
                                        }
                                        FMButton {
                                            width: 34; height: 26
                                            primary: true
                                            text: "+"
                                            onClicked: { seduteVM.aggiungiVoceMenu(pannelloCategoria.categoria, campoNuovaVoce.text); campoNuovaVoce.text = "" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacing.md

                    Repeater {
                        model: seduteVM.fasi
                        delegate: FMPanel {
                            id: blocco
                            width: colonna.width - Theme.spacing.lg * 2
                            property var faseDati: modelData
                            property int indiceBlocco: index
                            title: "Blocco " + faseDati.ordine_blocco

                            // Disposizione stile "vecchio widget": la grafica
                            // dell'esercizio (foto/lavagna) a sinistra, tutti i
                            // campi testuali impilati a destra - non l'inverso.
                            Row {
                                width: parent.width
                                spacing: Theme.spacing.sm

                                FMEditorImmagineEsercizio {
                                    width: 220
                                    height: 230
                                    percorsoImmagine: blocco.faseDati.esercitazione.immagine || ""
                                    onRichiestaImposta: function(percorso) { seduteVM.impostaCampoEsercitazione(blocco.indiceBlocco, "immagine", percorso) }
                                    onRichiestaRimozione: seduteVM.impostaCampoEsercitazione(blocco.indiceBlocco, "immagine", "")
                                    onRichiestaCreaConLavagna: seduteVM.apriLavagnaPerBlocco(blocco.indiceBlocco)
                                }

                                Column {
                                    width: parent.width - 220 - Theme.spacing.sm
                                    spacing: Theme.spacing.sm

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacing.sm

                                        Column {
                                            width: 230
                                            spacing: 2
                                            Text { text: "Fase"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                                            Flow {
                                                width: parent.width
                                                spacing: Theme.spacing.xs
                                                readonly property var attivi: (blocco.faseDati.fase || "").split(",")

                                                Repeater {
                                                    model: [
                                                        { c: "attivazione", l: "Attivazione" },
                                                        { c: "centrale", l: "Fase centrale" },
                                                        { c: "finale", l: "Fase finale" },
                                                    ]
                                                    delegate: Rectangle {
                                                        readonly property bool selezionata: parent.attivi.indexOf(modelData.c) !== -1
                                                        width: etichettaFase.implicitWidth + Theme.spacing.sm * 2
                                                        height: 26
                                                        radius: Theme.radius.sm
                                                        color: selezionata ? Theme.colors.primario : Theme.colors.bgSurface3
                                                        border.width: 1
                                                        border.color: selezionata ? Theme.colors.primario : Theme.colors.border
                                                        Text {
                                                            id: etichettaFase
                                                            anchors.centerIn: parent
                                                            text: modelData.l
                                                            color: selezionata ? "#ffffff" : Theme.colors.textSecondary
                                                            font.family: Theme.typography.family
                                                            font.pixelSize: Theme.typography.caption
                                                            font.bold: selezionata
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: seduteVM.impostaFaseBlocco(blocco.indiceBlocco, modelData.c, !parent.selezionata)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Column {
                                            width: 80
                                            spacing: 2
                                            Text { text: "Minuti"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                                            TextField {
                                                objectName: "campoMinutiBlocco"
                                                width: parent.width
                                                placeholderText: "Minuti"
                                                placeholderTextColor: Theme.colors.textSecondary
                                                color: Theme.colors.textPrimary
                                                font.family: Theme.typography.family
                                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                                onEditingFinished: seduteVM.impostaCampoBlocco(blocco.indiceBlocco, "durata_minuti", text)
                                                // FIX: stesso motivo di descrizione/obiettivi/mezzo sopra
                                                // ("text" era un binding LIVE a blocco.faseDati.durata_minuti).
                                                // Modificare un qualunque altro campo dello stesso blocco fa
                                                // ricreare tutti i delegate di questo Repeater (model: seduteVM.fasi,
                                                // QVariantList rimpiazzata per intero ad ogni dettaglioCambiato):
                                                // un binding live rilegge il vecchio valore (es. 10 di default)
                                                // se il rebuild arriva prima che l'utente abbia tolto il focus da
                                                // qui. Component.onCompleted imposta il valore una sola volta,
                                                // rendendo questo campo immune ai rebuild innescati da altri campi.
                                                Component.onCompleted: text = String(blocco.faseDati.durata_minuti)
                                            }
                                        }
                                        FMButton {
                                            width: 36
                                            text: "▲"
                                            enabled: blocco.indiceBlocco > 0
                                            onClicked: seduteVM.spostaBloccoSu(blocco.indiceBlocco)
                                        }
                                        FMButton {
                                            width: 36
                                            text: "▼"
                                            enabled: blocco.indiceBlocco < seduteVM.fasi.length - 1
                                            onClicked: seduteVM.spostaBloccoGiu(blocco.indiceBlocco)
                                        }
                                        FMButton {
                                            width: 100
                                            destructive: true
                                            text: "Rimuovi"
                                            onClicked: {
                                                // Conferma solo se il blocco ha gia' dati (nome, esercitazione
                                                // o obiettivi): un blocco appena aggiunto e ancora vuoto puo'
                                                // essere rimosso senza chiedere nulla, come nel vecchio widget.
                                                var f = blocco.faseDati
                                                var es = f.esercitazione
                                                var compilato = (f.nome_blocco && f.nome_blocco.trim() !== "")
                                                    || (es.nome_esercizio && es.nome_esercizio.trim() !== "")
                                                    || (es.mezzo_allenamento && es.mezzo_allenamento.trim() !== "")
                                                    || (es.obiettivo_tecnico && es.obiettivo_tecnico.trim() !== "")
                                                    || (es.obiettivo_tattico && es.obiettivo_tattico.trim() !== "")
                                                    || (es.descrizione && es.descrizione.trim() !== "")
                                                if (compilato) {
                                                    dialogoConferma.apri(
                                                        "Rimuovi blocco",
                                                        "Questo blocco contiene già dei dati (nome, esercitazione o obiettivi): rimuoverlo li cancellerà tutti. Continuare?",
                                                        "Rimuovi",
                                                        function() { seduteVM.rimuoviBlocco(blocco.indiceBlocco) }
                                                    )
                                                } else {
                                                    seduteVM.rimuoviBlocco(blocco.indiceBlocco)
                                                }
                                            }
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacing.sm

                                        // NOTA: editText e' impostato UNA SOLA VOLTA in
                                        // Component.onCompleted, non con un binding live
                                        // (editText: blocco.faseDati...). Con un binding
                                        // live, ogni modifica a QUALUNQUE campo del
                                        // blocco fa ricreare tutti i delegate del
                                        // Repeater sopra (il modello e' un array
                                        // semplice, non un modello incrementale): ogni
                                        // ComboBox editabile appena ricreato puo'
                                        // normalizzare il proprio editText (es.
                                        // auto-selezionando la prima voce quando il
                                        // testo e' vuoto), il che riscrive la property
                                        // Python e fa ripartire il ciclo - un loop di
                                        // binding rilevato da Qt (visto con lo smoke
                                        // test: decine di warning aggiungendo un
                                        // blocco). Inizializzare una volta sola spezza
                                        // il ciclo alla radice.
                                        Column {
                                            width: (parent.width - Theme.spacing.sm * 2) / 3
                                            spacing: 2
                                            Text { text: "Mezzo"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                                            FMComboBox {
                                                id: comboMezzo
                                                width: parent.width
                                                editable: true
                                                model: seduteVM.listaMezzi
                                                // FIX (loop di binding): un ComboBox editabile con model non
                                                // vuoto auto-seleziona l'indice 0 (e quindi editText) in fase
                                                // di costruzione, PRIMA che Component.onCompleted sotto possa
                                                // impostare il valore vero - quell'auto-selezione emette
                                                // comunque onEditTextChanged con un valore che non e' quello
                                                // salvato, scatenando lo stesso loop che Component.onCompleted
                                                // voleva evitare. currentIndex: -1 sopprime l'auto-selezione.
                                                currentIndex: -1
                                                onEditTextChanged: seduteVM.impostaCampoEsercitazione(blocco.indiceBlocco, "mezzo_allenamento", editText)
                                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                                Component.onCompleted: editText = blocco.faseDati.esercitazione.mezzo_allenamento
                                            }
                                        }
                                        Column {
                                            width: (parent.width - Theme.spacing.sm * 2) / 3
                                            spacing: 2
                                            Text { text: "Obiettivo tecnico"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                                            FMComboBox {
                                                id: comboTecnico
                                                width: parent.width
                                                editable: true
                                                model: seduteVM.listaTecnici
                                                currentIndex: -1
                                                onEditTextChanged: seduteVM.impostaCampoEsercitazione(blocco.indiceBlocco, "obiettivo_tecnico", editText)
                                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                                Component.onCompleted: editText = blocco.faseDati.esercitazione.obiettivo_tecnico
                                            }
                                        }
                                        Column {
                                            width: (parent.width - Theme.spacing.sm * 2) / 3
                                            spacing: 2
                                            Text { text: "Obiettivo tattico"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                                            FMComboBox {
                                                id: comboTattico
                                                width: parent.width
                                                editable: true
                                                model: seduteVM.listaTattici
                                                currentIndex: -1
                                                onEditTextChanged: seduteVM.impostaCampoEsercitazione(blocco.indiceBlocco, "obiettivo_tattico", editText)
                                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                                Component.onCompleted: editText = blocco.faseDati.esercitazione.obiettivo_tattico
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: 2
                                        Text { text: "Descrizione / focus esercizio"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                                        // FIX (segnalato da Luca: scrivendo oltre la quarta riga non
                                        // si legge piu' cosa si sta scrivendo): l'altezza fissa (76)
                                        // era sul TextArea stesso, che senza scroll proprio si limita
                                        // a tagliare il testo oltre quella altezza - il cursore finiva
                                        // fuori dall'area visibile. ScrollView tiene fissa l'altezza
                                        // del riquadro ma lascia il TextArea crescere con il contenuto
                                        // (contentHeight), scorrendolo invece di tagliarlo.
                                        ScrollView {
                                            width: parent.width
                                            height: 76
                                            clip: true
                                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                            TextArea {
                                                width: parent.width
                                                wrapMode: TextEdit.WordWrap
                                                placeholderText: "Descrivi l'esercizio…"
                                                placeholderTextColor: Theme.colors.textSecondary
                                                color: Theme.colors.textPrimary
                                                font.family: Theme.typography.family
                                                background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                                // FIX (segnalato da un collega di Luca: "se metto la
                                                // descrizione e poi metto l'obiettivo, mi cancella la
                                                // descrizione"): "text" era un binding LIVE a
                                                // blocco.faseDati.esercitazione.descrizione. Impostare un
                                                // qualunque altro campo dello stesso blocco (es. Obiettivo
                                                // Tecnico) fa ricreare TUTTI i delegate di questo Repeater
                                                // (stesso motivo gia' spiegato sopra per i ComboBox - il
                                                // modello e' un array intero, non incrementale): se il testo
                                                // appena digitato qui non era ancora stato commesso al VM
                                                // (accade solo alla perdita del focus, vedi sotto), il nuovo
                                                // TextArea appena ricreato si ri-legava al valore VECCHIO,
                                                // cancellando visivamente quanto scritto. Stessa correzione
                                                // gia' applicata ai ComboBox: inizializzare "text" una sola
                                                // volta a Component.onCompleted invece di un binding live
                                                // rende questo campo immune ai rebuild innescati da altri
                                                // campi del blocco.
                                                Component.onCompleted: text = blocco.faseDati.esercitazione.descrizione
                                                // TextArea non ha "editingFinished" (a differenza di
                                                // TextField): serve per il testo multi-riga, dove Invio
                                                // deve andare a capo, non confermare - si salva quindi alla
                                                // perdita del focus.
                                                onActiveFocusChanged: if (!activeFocus) seduteVM.impostaCampoEsercitazione(blocco.indiceBlocco, "descrizione", text)
                                            }
                                        }
                                    }
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
}
