import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Theme
import "../components"

Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2

    function urlAPercorso(url) {
        var s = url.toString()
        var prefisso = "file:///"
        if (s.indexOf(prefisso) === 0) s = s.substring(prefisso.length)
        return decodeURIComponent(s)
    }
    // Solo le sedute di tipo Partita/Torneo/Test Match (C/TM/TA) hanno lo
    // stato "Convocato" - un Allenamento usa P/A e non ha nulla da esportare qui.
    readonly property bool sedutaCorrenteEPartita: presenzeVM.statiPerSedutaCorrente.indexOf("C") !== -1

    readonly property var etichetteStati: ({ "P": "Presente", "A": "Assente", "C": "Convocato", "NC": "Non conv.", "": "—" })
    function statoColore(stato) {
        if (stato === "P") return Theme.colors.success
        if (stato === "A") return Theme.colors.danger
        if (stato === "C") return Theme.colors.positive
        if (stato === "NC") return Theme.colors.warning
        return Theme.colors.textTertiary
    }
    // Stati mostrati come badge per una riga: solo quelli pertinenti al tipo
    // di seduta (Allenamento -> P/A, Partita/Torneo -> C/NC), piu' quello
    // eventualmente gia' salvato per questo giocatore anche se non piu'
    // pertinente (es. tipo cambiato dopo aver gia' segnato qualcosa), cosi'
    // resta visibile e correggibile invece di sparire senza spiegazione.
    function statiApplicabiliPerRiga(statoAttuale) {
        var base = presenzeVM.statiPerSedutaCorrente.slice()
        if (statoAttuale && base.indexOf(statoAttuale) === -1) base.push(statoAttuale)
        return base
    }

    property bool mostraGrigliaMensile: false

    function etichettaAutoRiempi() {
        var stati = presenzeVM.statiPerSedutaCorrente
        return (stati.length > 0 && stati[0] === "C") ? "Segna tutti Convocati" : "Segna tutti Presenti"
    }

    // La schermata viene ricreata da zero (stack.replace) ogni volta che la
    // si riapre, ma presenzeVM e' lo stesso oggetto Python per tutta la
    // sessione: ricaricaGruppi() qui e' rete di sicurezza in aggiunta al
    // segnale gruppiCambiati di Macrociclo gia' collegato in main.py, per
    // gruppi creati/eliminati prima che questo VM esistesse.
    Component.onCompleted: {
        presenzeVM.ricaricaGruppi()
        presenzeVM.aggiornaTutto()
    }

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        Row {
            width: parent.width
            spacing: Theme.spacing.lg

            FMCard {
                width: (parent.width - Theme.spacing.lg) / 2
                title: "Gruppo"
                FMComboBox {
                    id: comboGruppo
                    width: parent.width
                    model: presenzeVM.gruppi
                    textRole: "label"
                    currentIndex: presenzeVM.indiceGruppo
                    onActivated: function(indice) { presenzeVM.selezionaGruppo(indice) }
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    contentItem: Text {
                        leftPadding: Theme.spacing.sm
                        text: comboGruppo.displayText
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            FMCard {
                width: (parent.width - Theme.spacing.lg) / 2
                title: "Evento"
                // L'evento non si sceglie piu' da una lista qui: si sceglie
                // dal Macrociclo (la cella settimanale), che resta l'unico
                // punto d'ingresso per decidere QUALE evento aggiornare -
                // qui si vede solo quello gia' selezionato, con un
                // collegamento diretto per cambiarlo.
                Row {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    Text {
                        width: parent.width - btnVaiAlMacrociclo.width - Theme.spacing.sm
                        elide: Text.ElideRight
                        text: (presenzeVM.indiceSeduta >= 0 && presenzeVM.indiceSeduta < presenzeVM.sedute.length)
                            ? presenzeVM.sedute[presenzeVM.indiceSeduta].label
                            : "Nessun evento selezionato"
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    FMButton {
                        id: btnVaiAlMacrociclo
                        text: "Cambia → Macrociclo"
                        onClicked: navigazioneVM.vaiA(1)
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.sm
            FMButton { text: "📅 Calendario & Eventi"; onClicked: dialogoCalendario.apri() }
            FMButton { text: root.mostraGrigliaMensile ? "Chiudi Griglia Mensile" : "📊 Griglia Mensile"; onClicked: root.mostraGrigliaMensile = !root.mostraGrigliaMensile }
        }

        Text {
            visible: presenzeVM.errore !== ""
            text: presenzeVM.errore
            color: Theme.colors.danger
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }
        Text {
            visible: presenzeVM.messaggio !== ""
            text: presenzeVM.messaggio
            color: Theme.colors.positive
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }

        FMCard {
            width: parent.width
            title: "Presenze (" + presenzeVM.righe.length + ")"

            Row {
                width: parent.width
                visible: presenzeVM.righe.length > 0
                FMButton {
                    text: root.etichettaAutoRiempi()
                    onClicked: presenzeVM.impostaTuttiPositivi()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacing.xs

                Text {
                    visible: presenzeVM.righe.length === 0
                    text: "Seleziona un gruppo e un evento con giocatori disponibili."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }

                Repeater {
                    model: presenzeVM.righe
                    delegate: Rectangle {
                        id: rigaDelegate
                        // Catturati con nomi propri: dentro il Repeater
                        // annidato sotto, "modelData"/"index" si riferiscono
                        // al modello INTERNO (root.stati), non piu' a questo
                        // giocatore - serve un nome diverso per non perderlo.
                        property var rigaGiocatore: modelData
                        property int indiceRiga: index

                        width: colonna.width - Theme.spacing.lg * 2
                        height: 40
                        radius: Theme.radius.sm
                        color: indiceRiga % 2 === 0 ? "transparent" : Theme.colors.bgSurface2

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing.sm
                            anchors.verticalCenter: parent.verticalCenter
                            // Un giocatore eliminato (soft-delete) resta qui con
                            // le sue presenze storiche - etichetta attenuata per
                            // distinguerlo da chi e' ancora in rosa.
                            text: rigaDelegate.rigaGiocatore.cognome + " " + rigaDelegate.rigaGiocatore.nome + (rigaDelegate.rigaGiocatore.attivo ? "" : " (eliminato)")
                            color: rigaDelegate.rigaGiocatore.attivo ? Theme.colors.textPrimary : Theme.colors.textTertiary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.body
                            font.italic: !rigaDelegate.rigaGiocatore.attivo
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing.sm
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacing.xs

                            Repeater {
                                model: root.statiApplicabiliPerRiga(rigaDelegate.rigaGiocatore.stato)
                                delegate: Rectangle {
                                    property string codiceStato: modelData
                                    readonly property bool selezionato: rigaDelegate.rigaGiocatore.stato === codiceStato
                                    width: 56; height: 26
                                    radius: Theme.radius.sm
                                    color: selezionato ? root.statoColore(codiceStato) : Theme.colors.bgSurface3
                                    border.width: 1
                                    border.color: selezionato ? root.statoColore(codiceStato) : Theme.colors.border

                                    Text {
                                        anchors.centerIn: parent
                                        text: codiceStato
                                        color: selezionato ? "#0a0a0a" : Theme.colors.textSecondary
                                        font.family: Theme.typography.family
                                        font.pixelSize: Theme.typography.caption
                                        font.bold: selezionato
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: presenzeVM.impostaStato(rigaDelegate.rigaGiocatore.id, codiceStato)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.sm

            FMButton {
                width: root.sedutaCorrenteEPartita ? (parent.width - Theme.spacing.sm) / 2 : parent.width
                primary: true
                text: "Salva presenze"
                enabled: presenzeVM.righe.length > 0
                onClicked: presenzeVM.salva()
            }
            FMButton {
                visible: root.sedutaCorrenteEPartita
                width: (parent.width - Theme.spacing.sm) / 2
                text: "📄 Esporta convocati (txt)"
                enabled: presenzeVM.righe.length > 0
                onClicked: dialogoEsportaConvocati.open()
            }
        }

        FMCard {
            width: parent.width
            visible: root.mostraGrigliaMensile
            title: "Griglia Mensile"

            FMGrigliaMensilePresenze {}
        }
    }

    FMCalendarioEventi {
        id: dialogoCalendario
        onRichiestaConfermaCreazioneProgrammata: function(dataStr, tipo) {
            dialogoConfermaCalendario.apri(
                "Crea registro presenze",
                "In questa data e' previsto un evento pianificato (" + tipo + ") senza ancora un registro collegato. Vuoi crearlo adesso?",
                "Crea",
                function() { presenzeVM.creaEventoProgrammato(dataStr) }
            )
        }
        onRichiestaSceltaTipoEvento: function(dataStr) { dialogoSceltaTipoEvento.apriPer(dataStr) }
    }
    FMConfirmDialog { id: dialogoConfermaCalendario }
    FMSceltaTipoEventoDialog {
        id: dialogoSceltaTipoEvento
        onTipoScelto: function(dataStr, tipo) { presenzeVM.creaEventoExtra(dataStr, tipo) }
    }

    // Lista convocati su file di testo (C/TM/TA), come nel vecchio programma
    // - li' finiva negli appunti, qui su file per poterla archiviare/inviare.
    FileDialog {
        id: dialogoEsportaConvocati
        title: "Esporta lista convocati"
        fileMode: FileDialog.SaveFile
        nameFilters: ["File di testo (*.txt)"]
        onAccepted: {
            var destinazione = root.urlAPercorso(dialogoEsportaConvocati.selectedFile)
            if (destinazione.toLowerCase().lastIndexOf(".txt") !== destinazione.length - 4) destinazione += ".txt"
            presenzeVM.esportaConvocatiTesto(destinazione)
        }
    }
}
