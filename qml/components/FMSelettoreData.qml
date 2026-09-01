import QtQuick
import QtQuick.Controls.Basic
import Theme

// Selettore data generico a month-grid (stessa logica di generazione griglia
// di FMCalendarioEventi.qml, spogliata della logica eventi/presenze), per
// sostituire i TextField a testo libero sparsi per il programma (Statistiche
// Periodo, Sedute crea/sposta) con un click su un vero calendario invece di
// dover digitare una data a mano in un formato preciso.
Item {
    id: root

    // Valore corrente, gia' nel formato scelto da "formato" (es. "2026-01-15"
    // se formato === "iso", "15-01-2026" se formato === "it"). Il chiamante
    // lo passa/legge cosi' com'e', senza bisogno di conversioni proprie.
    property string valore: ""
    property string formato: "iso"  // "iso" | "it"
    property string placeholder: "Seleziona data"
    implicitWidth: 140
    implicitHeight: 34

    signal scelta(string testo)

    function formattaData(anno, mese, giorno) {
        var mm = (mese < 10 ? "0" : "") + mese
        var dd = (giorno < 10 ? "0" : "") + giorno
        return root.formato === "it" ? (dd + "-" + mm + "-" + anno) : (anno + "-" + mm + "-" + dd)
    }

    function dataParsataOOggi() {
        if (root.valore !== "") {
            var parti = root.formato === "it" ? root.valore.split("-").reverse() : root.valore.split("-")
            if (parti.length === 3) {
                var d = new Date(parseInt(parti[0]), parseInt(parti[1]) - 1, parseInt(parti[2]))
                if (!isNaN(d.getTime())) return d
            }
        }
        return new Date()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.sm
        color: Theme.colors.bgSurface2
        border.width: 1
        border.color: Theme.colors.border

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.spacing.sm
            elide: Text.ElideRight
            text: root.valore !== "" ? root.valore : root.placeholder
            color: root.valore !== "" ? Theme.colors.textPrimary : Theme.colors.textTertiary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.body
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.apri()
        }
    }

    Popup {
        id: popup
        // FIX: FMSelettoreData e' un widget compatto (140x34) usato annidato
        // dentro form/liste scorrevoli - senza riparentare il popup
        // all'Overlay, x/y sotto (calcolate sulle dimensioni della finestra)
        // venivano applicate rispetto al piccolo widget invece che alla
        // finestra, aprendo il calendario fuori dalla vista o del tutto
        // irraggiungibile (segnalato da Luca). Stesso principio gia'
        // applicato a dialogoArchivio in FMEditorImmagineEsercizio.qml.
        parent: Overlay.overlay
        modal: true
        focus: true
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        width: 320
        height: 360
        padding: Theme.spacing.lg

        property int mese: 1
        property int anno: 2026

        readonly property var nomiMesi: ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"]

        function apri() {
            var d = root.dataParsataOOggi()
            popup.mese = d.getMonth() + 1
            popup.anno = d.getFullYear()
            open()
        }

        function generaGriglia() {
            var primoGiorno = new Date(popup.anno, popup.mese - 1, 1)
            var offset = (primoGiorno.getDay() + 6) % 7  // 0 = lunedi'
            var giorniMese = new Date(popup.anno, popup.mese, 0).getDate()
            var celle = []
            for (var i = 0; i < offset; i++) celle.push({ giorno: 0 })
            for (var g = 1; g <= giorniMese; g++) celle.push({ giorno: g })
            while (celle.length % 7 !== 0) celle.push({ giorno: 0 })
            return celle
        }

        background: Rectangle {
            color: Theme.colors.bgSurface
            radius: Theme.radius.lg
            border.width: 1
            border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: popup }
        }
        Overlay.modal: Rectangle { color: "#000000aa" }

        contentItem: Column {
            spacing: Theme.spacing.sm

            Row {
                width: parent.width
                spacing: Theme.spacing.sm
                FMButton { width: 36; text: "‹"; onClicked: { if (popup.mese === 1) { popup.mese = 12; popup.anno -= 1 } else popup.mese -= 1 } }
                Text {
                    width: parent.width - 36 * 2 - Theme.spacing.sm * 2
                    horizontalAlignment: Text.AlignHCenter
                    text: popup.nomiMesi[popup.mese - 1] + " " + popup.anno
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    font.bold: true
                    font.pixelSize: Theme.typography.body
                }
                FMButton { width: 36; text: "›"; onClicked: { if (popup.mese === 12) { popup.mese = 1; popup.anno += 1 } else popup.mese += 1 } }
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
                property var celle: popup.generaGriglia()

                Repeater {
                    model: griglia.celle
                    delegate: Rectangle {
                        // MAI "visible: modelData.giorno !== 0" qui: Grid
                        // (positioner) ignora gli item invisibili nel layout,
                        // quindi le celle vuote iniziali collasserebbero a
                        // larghezza zero e il giorno 1 scivolerebbe sempre
                        // nella prima colonna (Lunedi'), qualunque sia il vero
                        // giorno della settimana. La cella resta sempre
                        // presente; solo il contenuto e' condizionale.
                        width: griglia.width / 7
                        height: 36
                        readonly property bool cellaVuota: modelData.giorno === 0
                        color: "transparent"
                        radius: Theme.radius.sm

                        Text {
                            anchors.centerIn: parent
                            text: parent.cellaVuota ? "" : modelData.giorno
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !parent.cellaVuota
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var testo = root.formattaData(popup.anno, popup.mese, modelData.giorno)
                                root.valore = testo
                                root.scelta(testo)
                                popup.close()
                            }
                        }
                    }
                }
            }

            FMButton { width: parent.width; text: "Chiudi"; onClicked: popup.close() }
        }
    }
}
