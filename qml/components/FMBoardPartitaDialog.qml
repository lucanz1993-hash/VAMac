import QtQuick
import QtQuick.Controls.Basic
import Theme

// "Board Partita": registra avversario/luogo/risultato (partita singola,
// tipo C/TM) o piu' partite (torneo, tipo TA), con goal e note per ogni
// giocatore convocato. Stesso formato JSON gia' usato dal vecchio widget
// (interfaccia_macrociclo.py, DialogBoardPartita) e salvato nella colonna
// nota_<giorno> del macrociclo: era l'unico posto dove si registravano
// risultati/marcatori delle partite, sparito del tutto nella ricostruzione.
Popup {
    id: root
    // Stesso reparent gia' applicato a FMConfirmDialog.qml/FMSelettoreData.qml:
    // senza, x/y sotto sono relativi al parent QML di dichiarazione invece
    // che alla finestra, e il dialogo puo' aprirsi fuori schermo.
    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
    y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
    width: 680
    height: Math.min(600, (Overlay.overlay ? Overlay.overlay.height - 40 : 600))
    padding: Theme.spacing.lg

    property string tipoEvento: "C"        // "C" | "TM" | "TA"
    property var convocati: []             // [{id, nome, cognome}]
    property int numPartite: 1
    property var partiteIniziali: []       // [{avversario, risultato}]
    property var goalIniziali: ({})        // {idGiocatore(str): {goal, note} oppure {goal:[...], note}}
    property string nomeTorneoIniziale: ""
    property string avversarioIniziale: ""
    property string luogoIniziale: "C"
    property string risultatoIniziale: ""

    signal richiestaSalvataggio(string datiJson)

    function apri(tipo, listaConvocati, datiJsonIniziali) {
        tipoEvento = tipo
        convocati = listaConvocati
        var dati = {}
        try { dati = JSON.parse(datiJsonIniziali || "{}") } catch (e) { dati = {} }

        if (tipoEvento === "TA") {
            numPartite = dati.num_partite || 1
            nomeTorneoIniziale = dati.nome_torneo || ""
            partiteIniziali = dati.partite || []
        } else {
            avversarioIniziale = dati.avversario || ""
            luogoIniziale = dati.luogo || "C"
            risultatoIniziale = dati.risultato || ""
        }
        goalIniziali = dati.giocatori || {}
        open()
    }

    function esitoColore(risultato, luogo) {
        var sep = risultato.indexOf("-") !== -1 ? "-" : (risultato.indexOf(":") !== -1 ? ":" : "")
        if (!sep) return Theme.colors.textPrimary
        var parti = risultato.split(sep)
        if (parti.length !== 2 || isNaN(parseInt(parti[0])) || isNaN(parseInt(parti[1]))) return Theme.colors.textPrimary
        var g1 = parseInt(parti[0]), g2 = parseInt(parti[1])
        var nostri = g1, avversari = g2
        if (luogo === "T") { nostri = g2; avversari = g1 }
        if (nostri > avversari) return Theme.colors.success
        if (nostri < avversari) return Theme.colors.danger
        return Theme.colors.warning
    }

    function costruisciESalva() {
        var res = { tipo: tipoEvento }
        var giocatoriJson = {}

        if (tipoEvento === "TA") {
            res.num_partite = numPartite
            res.nome_torneo = campoNomeTorneo.text
            var partite = []
            for (var i = 0; i < numPartite; i++) {
                var itemPartita = repeaterPartite.itemAt(i)
                partite.push({ avversario: itemPartita ? itemPartita.avversario : "", risultato: itemPartita ? itemPartita.risultato : "" })
            }
            res.partite = partite

            for (var j = 0; j < convocati.length; j++) {
                var itemGiocatoreTa = repeaterConvocati.itemAt(j)
                if (!itemGiocatoreTa) continue
                giocatoriJson[String(convocati[j].id)] = { goal: itemGiocatoreTa.goalPerPartita(), note: itemGiocatoreTa.note }
            }
        } else {
            res.avversario = campoAvversarioSingola.text
            res.luogo = comboLuogoSingola.currentText
            res.risultato = campoRisultatoSingola.text

            for (var k = 0; k < convocati.length; k++) {
                var itemGiocatore = repeaterConvocati.itemAt(k)
                if (!itemGiocatore) continue
                giocatoriJson[String(convocati[k].id)] = { goal: itemGiocatore.goalSingolo, note: itemGiocatore.note }
            }
        }
        res.giocatori = giocatoriJson
        richiestaSalvataggio(JSON.stringify(res))
        root.close()
    }

    background: Rectangle {
        color: Theme.colors.bgSurface
        radius: Theme.radius.lg
        border.width: 1
        border.color: Theme.colors.border
        FMManigliaTrascinamento { bersaglio: root }
    }
    Overlay.modal: Rectangle { color: "#000000aa" }

    contentItem: Flickable {
        width: root.width - root.padding * 2
        height: root.height - root.padding * 2
        contentWidth: width
        contentHeight: colonnaContenuto.implicitHeight
        clip: true

        Column {
            id: colonnaContenuto
            width: parent.width
            spacing: Theme.spacing.md

            Text {
                text: "Board Partita"
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.title
                font.bold: true
            }

            // --- Intestazione: partita singola (C / TM) ---
            Row {
                visible: root.tipoEvento !== "TA"
                width: parent.width
                spacing: Theme.spacing.sm

                TextField {
                    id: campoAvversarioSingola
                    width: 220
                    placeholderText: "Avversario"
                    placeholderTextColor: Theme.colors.textSecondary
                    text: root.avversarioIniziale
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                FMComboBox {
                    id: comboLuogoSingola
                    width: 110
                    model: ["C", "T"]
                    currentIndex: root.luogoIniziale === "T" ? 1 : 0
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    contentItem: Text {
                        leftPadding: Theme.spacing.sm
                        text: comboLuogoSingola.displayText
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                TextField {
                    id: campoRisultatoSingola
                    width: 90
                    placeholderText: "2-1"
                    placeholderTextColor: Theme.colors.textSecondary
                    text: root.risultatoIniziale
                    horizontalAlignment: TextInput.AlignHCenter
                    color: root.esitoColore(text, comboLuogoSingola.currentText)
                    font.bold: true
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
            }

            // --- Intestazione: torneo (TA) ---
            Column {
                visible: root.tipoEvento === "TA"
                width: parent.width
                spacing: Theme.spacing.sm

                Row {
                    width: parent.width
                    spacing: Theme.spacing.sm
                    TextField {
                        id: campoNomeTorneo
                        width: 260
                        placeholderText: "Nome torneo"
                        placeholderTextColor: Theme.colors.textSecondary
                        text: root.nomeTorneoIniziale
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    }
                    Text { text: "Numero partite:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; anchors.verticalCenter: parent.verticalCenter }
                    SpinBox {
                        id: spinNumPartite
                        from: 1; to: 15
                        value: root.numPartite
                        onValueModified: root.numPartite = value
                    }
                }

                Repeater {
                    id: repeaterPartite
                    model: root.numPartite
                    delegate: Row {
                        width: colonnaContenuto.width
                        spacing: Theme.spacing.sm
                        property alias avversario: campoAvvT.text
                        property alias risultato: campoRisT.text

                        Text { text: "Gara " + (index + 1) + ":"; width: 60; color: Theme.colors.textSecondary; font.family: Theme.typography.family; anchors.verticalCenter: parent.verticalCenter }
                        TextField {
                            id: campoAvvT
                            width: 220
                            placeholderText: "Avversario"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: (root.partiteIniziali[index] && root.partiteIniziali[index].avversario) || ""
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        }
                        TextField {
                            id: campoRisT
                            width: 90
                            placeholderText: "2-1"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: (root.partiteIniziali[index] && root.partiteIniziali[index].risultato) || ""
                            horizontalAlignment: TextInput.AlignHCenter
                            color: root.esitoColore(text, "C")
                            font.bold: true
                            font.family: Theme.typography.family
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        }
                    }
                }
            }

            Text {
                visible: root.convocati.length === 0
                text: "⚠️ Nessun giocatore risulta Convocato per questo evento. Vai prima in Presenze."
                color: Theme.colors.warning
                wrapMode: Text.WordWrap
                width: parent.width
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }

            Text {
                visible: root.convocati.length > 0
                text: "Giocatori convocati"
                color: Theme.colors.accent
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
                font.bold: true
            }

            Repeater {
                id: repeaterConvocati
                model: root.convocati
                delegate: Row {
                    width: colonnaContenuto.width
                    spacing: Theme.spacing.sm

                    property var datiGiocatore: modelData
                    readonly property string idStr: String(datiGiocatore.id)
                    readonly property var datiGoalSalvati: root.goalIniziali[idStr] || {}
                    property int goalSingolo: root.tipoEvento !== "TA" ? (datiGoalSalvati.goal || 0) : 0
                    property alias note: campoNote.text

                    function goalPerPartita() {
                        var arr = []
                        for (var i = 0; i < root.numPartite; i++) arr.push(spinnerPerPartita.itemAt(i) ? spinnerPerPartita.itemAt(i).value : 0)
                        return arr
                    }

                    Text {
                        width: 160
                        text: datiGiocatore.cognome + " " + datiGiocatore.nome
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                        elide: Text.ElideRight
                    }
                    SpinBox {
                        visible: root.tipoEvento !== "TA"
                        from: 0; to: 99
                        value: goalSingolo
                        onValueModified: goalSingolo = value
                    }
                    Row {
                        visible: root.tipoEvento === "TA"
                        spacing: Theme.spacing.xs
                        Repeater {
                            id: spinnerPerPartita
                            model: root.numPartite
                            delegate: SpinBox {
                                width: 70
                                from: 0; to: 99
                                property var valoriSalvati: datiGoalSalvati.goal || []
                                value: valoriSalvati[index] || 0
                            }
                        }
                    }
                    TextField {
                        id: campoNote
                        width: 200
                        placeholderText: "Note"
                        placeholderTextColor: Theme.colors.textSecondary
                        text: datiGoalSalvati.note || ""
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                        background: Rectangle { color: Theme.colors.bgSurface3; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                    }
                }
            }

            Item {
                width: parent.width
                height: btnSalvaBoard.height
                FMButton {
                    anchors.left: parent.left
                    text: "Annulla"
                    onClicked: root.close()
                }
                FMButton {
                    id: btnSalvaBoard
                    anchors.right: parent.right
                    primary: true
                    text: "Salva Board Partita"
                    onClicked: root.costruisciESalva()
                }
            }
        }
    }
}
