import QtQuick
import QtQuick.Controls.Basic
import Theme

// "Griglia Mensile": report presenze/convocazioni di tutto il gruppo per un
// mese intero (una colonna per giorno, colorata per stato), con totali per
// giocatore e per giorno ed esportazione CSV - stessa vista del vecchio
// pagina_report_mensile di interfaccia_presenze.py (QTableWidget), qui
// ricostruita come griglia dichiarativa scorrevole orizzontalmente.
Column {
    id: root
    width: parent.width
    spacing: Theme.spacing.sm

    readonly property int largNome: 90
    readonly property int largCognome: 90
    readonly property int largGiorno: 26
    readonly property int largStat: 66
    readonly property var griglia: presenzeVM.grigliaMensile
    readonly property int largezzaTotale: largNome + largCognome + griglia.giorniTotali * largGiorno + largStat * 6

    function coloreStato(stato) {
        if (stato === "P") return Theme.colors.success
        if (stato === "A") return Theme.colors.danger
        if (stato === "C") return Theme.colors.positive
        if (stato === "NC") return Theme.colors.warning
        return "transparent"
    }
    function colorePercentuale(v) {
        if (v < 0) return Theme.colors.textTertiary
        if (v >= 80) return Theme.colors.success
        if (v >= 50) return Theme.colors.warning
        return Theme.colors.danger
    }

    Row {
        width: parent.width
        spacing: Theme.spacing.sm

        FMComboBox {
            width: 160
            model: presenzeVM.mesiNomi
            currentIndex: presenzeVM.meseReport - 1
            onActivated: function(indice) { presenzeVM.impostaMeseAnnoReport(indice + 1, presenzeVM.annoReport) }
            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
            contentItem: Text {
                leftPadding: Theme.spacing.sm
                text: parent.displayText
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                verticalAlignment: Text.AlignVCenter
            }
        }
        TextField {
            id: campoAnnoReport
            width: 80
            text: String(presenzeVM.annoReport)
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
            onEditingFinished: presenzeVM.impostaMeseAnnoReport(presenzeVM.meseReport, parseInt(text) || presenzeVM.annoReport)
        }
        FMButton { text: "Aggiorna"; onClicked: presenzeVM.calcolaGrigliaMensile() }
        FMButton { text: "Esporta CSV"; onClicked: presenzeVM.esportaGrigliaCsv() }
    }

    Text {
        visible: root.griglia.righe.length === 0
        text: "Nessun giocatore in questo gruppo, o nessun dato per il mese selezionato."
        color: Theme.colors.textTertiary
        font.family: Theme.typography.family
        font.pixelSize: Theme.typography.small
    }

    Flickable {
        width: root.width
        height: Math.min(420, (root.griglia.righe.length + 4) * 30 + 10)
        visible: root.griglia.righe.length > 0
        contentWidth: root.largezzaTotale
        contentHeight: (root.griglia.righe.length + 4) * 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: colonnaGriglia
            width: root.largezzaTotale

            // Intestazione
            Row {
                height: 30
                Rectangle {
                    width: root.largNome + root.largCognome; height: 30
                    color: Theme.colors.bgSurface2
                    Text { anchors.centerIn: parent; text: "Nome / Cognome"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                }
                Repeater {
                    model: root.griglia.giorniTotali
                    delegate: Rectangle {
                        width: root.largGiorno; height: 30
                        color: Theme.colors.bgSurface2
                        Text { anchors.centerIn: parent; text: String(index + 1); color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                    }
                }
                Repeater {
                    model: ["Tot P", "Tot A", "% P", "Tot Conv", "Tot Rip", "% Conv"]
                    delegate: Rectangle {
                        width: root.largStat; height: 30
                        color: Theme.colors.bgSurface2
                        Text { anchors.centerIn: parent; text: modelData; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    }
                }
            }

            // Tipologia impegno del giorno
            Row {
                height: 30
                Rectangle {
                    width: root.largNome + root.largCognome; height: 30
                    color: Theme.colors.bgSurface
                    Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: "Tipologia impegno"; color: Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                }
                Repeater {
                    model: root.griglia.tipiGiorno
                    delegate: Rectangle {
                        width: root.largGiorno; height: 30
                        color: Theme.colors.bgSurface
                        Text { anchors.centerIn: parent; text: modelData; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                    }
                }
                Rectangle { width: root.largStat * 6; height: 30; color: Theme.colors.bgSurface }
            }

            // Righe giocatori
            Repeater {
                model: root.griglia.righe
                delegate: Row {
                    height: 30
                    Rectangle {
                        width: root.largNome; height: 30
                        color: index % 2 === 0 ? "transparent" : Theme.colors.bgSurface2
                        // Giocatore eliminato (soft-delete): resta in griglia con
                        // le presenze storiche, colore attenuato per distinguerlo.
                        Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: modelData.nome; color: modelData.attivo ? Theme.colors.textPrimary : Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.italic: !modelData.attivo; elide: Text.ElideRight; width: parent.width - 8 }
                    }
                    Rectangle {
                        width: root.largCognome; height: 30
                        color: index % 2 === 0 ? "transparent" : Theme.colors.bgSurface2
                        Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: modelData.cognome; color: modelData.attivo ? Theme.colors.textPrimary : Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.italic: !modelData.attivo; elide: Text.ElideRight; width: parent.width - 8 }
                    }
                    Repeater {
                        model: modelData.giorni
                        delegate: Rectangle {
                            width: root.largGiorno; height: 30
                            color: root.coloreStato(modelData)
                            Text { anchors.centerIn: parent; text: modelData; color: modelData !== "" ? "#0a0a0a" : "transparent"; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        }
                    }
                    Rectangle { width: root.largStat; height: 30; Text { anchors.centerIn: parent; text: modelData.totalePresenze; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption } }
                    Rectangle { width: root.largStat; height: 30; Text { anchors.centerIn: parent; text: modelData.totaleAssenze; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption } }
                    Rectangle { width: root.largStat; height: 30; Text { anchors.centerIn: parent; text: modelData.percPresenza >= 0 ? (modelData.percPresenza + "%") : "-"; color: root.colorePercentuale(modelData.percPresenza); font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true } }
                    Rectangle { width: root.largStat; height: 30; Text { anchors.centerIn: parent; text: modelData.totaleConvocazioni; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption } }
                    Rectangle { width: root.largStat; height: 30; Text { anchors.centerIn: parent; text: modelData.totaleRiposo; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption } }
                    Rectangle { width: root.largStat; height: 30; Text { anchors.centerIn: parent; text: modelData.percConvocazioni >= 0 ? (modelData.percConvocazioni + "%") : "-"; color: root.colorePercentuale(modelData.percConvocazioni); font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true } }
                }
            }

            // Riepilogo: presenti/convocati per giorno
            Row {
                height: 30
                Rectangle {
                    width: root.largNome + root.largCognome; height: 30
                    color: Theme.colors.bgSurface2
                    Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: "Presenti / Convocati"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                }
                Repeater {
                    model: root.griglia.totalePresentiGiorno
                    delegate: Rectangle {
                        width: root.largGiorno; height: 30
                        color: Theme.colors.bgSurface2
                        Text { anchors.centerIn: parent; text: modelData >= 0 ? modelData : ""; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                    }
                }
                Rectangle { width: root.largStat * 6; height: 30; color: Theme.colors.bgSurface2 }
            }

            // Riepilogo: percentuale per giorno
            Row {
                height: 30
                Rectangle {
                    width: root.largNome + root.largCognome; height: 30
                    color: Theme.colors.bgSurface2
                    Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: "% Pres/Conv Giornaliera"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                }
                Repeater {
                    model: root.griglia.percPresentiGiorno
                    delegate: Rectangle {
                        width: root.largGiorno; height: 30
                        color: Theme.colors.bgSurface2
                        Text { anchors.centerIn: parent; text: modelData >= 0 ? (modelData + "%") : "-"; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                    }
                }
                Rectangle { width: root.largStat * 6; height: 30; color: Theme.colors.bgSurface2 }
            }
        }
    }
}
