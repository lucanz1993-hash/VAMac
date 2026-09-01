import QtQuick
import QtQuick.Controls.Basic
import Theme

// "Calendario & Eventi": mini month-grid cliccabile, colorata per tipo
// impegno (A/TM/TA/C), che sostituisce il vecchio DialogCalendario
// (QCalendarWidget di interfaccia_presenze.py). Cliccare un giorno con una
// seduta gia' collegata la seleziona; un giorno pianificato ma senza seduta
// chiede conferma per crearla; un giorno senza alcuna pianificazione chiede
// che tipo di evento creare - stesso comportamento a tre rami del dialogo
// originale, qui smistato al chiamante (Presenze.qml) tramite segnali
// invece di aprire altri Popup annidati qui dentro.
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
    width: 460
    height: 520
    padding: Theme.spacing.lg

    property int mese: 1
    property int anno: 2026

    readonly property var nomiMesi: ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"]
    readonly property var legenda: ({ "A": Theme.colors.accent, "TM": "#4fa3d1", "TA": "#d2691e", "C": "#8b008b" })

    signal richiestaConfermaCreazioneProgrammata(string dataStr, string tipo)
    signal richiestaSceltaTipoEvento(string dataStr)

    function apri() {
        var base = presenzeVM.dataSedutaCorrente
        var d = base ? new Date(base) : new Date()
        root.mese = d.getMonth() + 1
        root.anno = d.getFullYear()
        open()
    }

    function trovaEvento(dataStr) {
        var lista = presenzeVM.eventiCalendario
        for (var i = 0; i < lista.length; i++) {
            if (lista[i].data === dataStr) return lista[i]
        }
        return null
    }

    function generaGriglia() {
        var primoGiorno = new Date(root.anno, root.mese - 1, 1)
        var offset = (primoGiorno.getDay() + 6) % 7  // 0 = lunedi'
        var giorniMese = new Date(root.anno, root.mese, 0).getDate()
        var celle = []
        for (var i = 0; i < offset; i++) celle.push({ giorno: 0, data: "" })
        for (var g = 1; g <= giorniMese; g++) {
            var mm = (root.mese < 10 ? "0" : "") + root.mese
            var dd = (g < 10 ? "0" : "") + g
            celle.push({ giorno: g, data: root.anno + "-" + mm + "-" + dd })
        }
        while (celle.length % 7 !== 0) celle.push({ giorno: 0, data: "" })
        return celle
    }

    function onGiornoCliccato(dataStr) {
        var ev = root.trovaEvento(dataStr)
        if (ev && ev.idSeduta !== -1) {
            presenzeVM.selezionaSedutaPerId(ev.idSeduta)
            root.close()
        } else if (ev && ev.tipo !== "") {
            root.close()
            root.richiestaConfermaCreazioneProgrammata(dataStr, ev.tipo)
        } else {
            root.close()
            root.richiestaSceltaTipoEvento(dataStr)
        }
    }

    background: Rectangle {
        color: Theme.colors.bgSurface
        radius: Theme.radius.lg
        border.width: 1
        border.color: Theme.colors.border
        FMManigliaTrascinamento { bersaglio: root }
    }
    Overlay.modal: Rectangle { color: "#000000aa" }

    contentItem: Column {
        spacing: Theme.spacing.sm

        Row {
            width: parent.width
            spacing: Theme.spacing.sm
            FMButton { width: 40; text: "‹"; onClicked: { if (root.mese === 1) { root.mese = 12; root.anno -= 1 } else root.mese -= 1 } }
            Text {
                width: parent.width - 40 * 2 - Theme.spacing.sm * 2
                horizontalAlignment: Text.AlignHCenter
                text: root.nomiMesi[root.mese - 1] + " " + root.anno
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.bold: true
                font.pixelSize: Theme.typography.title
            }
            FMButton { width: 40; text: "›"; onClicked: { if (root.mese === 12) { root.mese = 1; root.anno += 1 } else root.mese += 1 } }
        }

        Row {
            width: parent.width
            Repeater {
                model: ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
                delegate: Text {
                    width: parent.width / 7
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.colors.textTertiary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.caption
                }
            }
        }

        Grid {
            id: griglia
            width: parent.width
            columns: 7
            property var celle: root.generaGriglia()

            Repeater {
                model: griglia.celle
                delegate: Rectangle {
                    // MAI "visible: modelData.giorno !== 0" qui: Grid (positioner)
                    // ignora gli item invisibili nel calcolo del layout, quindi le
                    // celle vuote iniziali del mese collasserebbero a larghezza
                    // zero e il giorno 1 scivolerebbe sempre nella prima colonna
                    // (Lunedi'), qualunque sia il vero giorno della settimana.
                    // La cella resta sempre presente nella griglia; solo il suo
                    // CONTENUTO e' condizionale su giorno !== 0.
                    width: griglia.width / 7
                    height: 54
                    readonly property bool cellaVuota: modelData.giorno === 0
                    property var evento: (!cellaVuota && modelData.data !== "") ? root.trovaEvento(modelData.data) : null
                    color: cellaVuota ? "transparent" : Theme.colors.bgSurface3
                    border.width: cellaVuota ? 0 : (evento ? 2 : 1)
                    border.color: evento ? (root.legenda[evento.tipo] || Theme.colors.accent) : Theme.colors.border
                    radius: Theme.radius.sm

                    Text {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 4
                        text: parent.cellaVuota ? "" : modelData.giorno
                        color: Theme.colors.textPrimary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.small
                    }
                    Rectangle {
                        visible: evento !== null
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 4
                        width: 32; height: 16
                        radius: Theme.radius.sm
                        color: evento ? (root.legenda[evento.tipo] || Theme.colors.accent) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: evento ? evento.tipo : ""
                            color: "white"
                            font.pixelSize: Theme.typography.caption
                            font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !parent.cellaVuota
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.onGiornoCliccato(modelData.data)
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.sm
            Repeater {
                model: ["A", "TM", "TA", "C"]
                delegate: Rectangle {
                    width: 40; height: 20
                    radius: Theme.radius.sm
                    color: root.legenda[modelData]
                    Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: Theme.typography.caption; font.bold: true }
                }
            }
        }

        FMButton { width: parent.width; text: "Chiudi"; onClicked: root.close() }
    }
}
