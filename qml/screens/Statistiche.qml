import QtQuick
import QtQuick.Controls.Basic
import Theme
import "../components"

Flickable {
    id: root
    contentWidth: width
    contentHeight: colonna.implicitHeight + Theme.spacing.xl * 2

    readonly property var nomiViste: ["Presenze Allenamenti", "Convocazioni Partite", "Risultati e Goal", "Obiettivi e Mezzi Allenamento"]

    // Stessa rete di sicurezza di Presenze.qml: ricaricaGruppi() qui in
    // aggiunta al segnale gruppiCambiati di Macrociclo collegato in main.py.
    Component.onCompleted: {
        statisticheVM.ricaricaGruppi()
        statisticheVM.aggiorna()
    }

    Column {
        id: colonna
        x: Theme.spacing.xl
        y: Theme.spacing.xl
        width: root.width - Theme.spacing.xl * 2
        spacing: Theme.spacing.lg

        FMCard {
            width: parent.width
            title: "Gruppo"
            FMComboBox {
                id: comboGruppo
                width: 400
                model: statisticheVM.gruppi
                textRole: "label"
                currentIndex: statisticheVM.indiceGruppo
                onActivated: function(indice) { statisticheVM.selezionaGruppo(indice) }
                background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                contentItem: Text {
                    leftPadding: Theme.spacing.sm
                    text: comboGruppo.displayText
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                text: statisticheVM.numeroSedute + " sedute considerate nel periodo selezionato."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Text {
                visible: statisticheVM.errore !== ""
                text: statisticheVM.errore
                color: Theme.colors.danger
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Text {
                visible: statisticheVM.messaggio !== ""
                text: statisticheVM.messaggio
                color: Theme.colors.positive
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
        }

        FMCard {
            width: parent.width
            title: "Filtri"

            Row {
                width: parent.width
                spacing: Theme.spacing.lg

                Column {
                    spacing: Theme.spacing.xs
                    Text { text: "Vista"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    FMComboBox {
                        id: comboVista
                        width: 220
                        model: root.nomiViste
                        currentIndex: statisticheVM.vistaCorrente
                        onActivated: function(indice) { statisticheVM.selezionaVista(indice) }
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        contentItem: Text {
                            leftPadding: Theme.spacing.sm
                            text: comboVista.displayText
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Column {
                    spacing: Theme.spacing.xs
                    Text { text: "Periodo"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    Row {
                        spacing: Theme.spacing.xs
                        FMSelettoreData {
                            id: campoDataInizio
                            formato: "iso"
                            valore: statisticheVM.dataInizio
                            onScelta: function(testo) { statisticheVM.impostaPeriodo(testo, campoDataFine.valore) }
                        }
                        Text { text: "—"; color: Theme.colors.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                        FMSelettoreData {
                            id: campoDataFine
                            formato: "iso"
                            valore: statisticheVM.dataFine
                            onScelta: function(testo) { statisticheVM.impostaPeriodo(campoDataInizio.valore, testo) }
                        }
                    }
                }

                Column {
                    spacing: Theme.spacing.xs
                    visible: statisticheVM.vistaCorrente === 1 || statisticheVM.vistaCorrente === 2
                    Text { text: "Filtra impegni"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    Row {
                        spacing: Theme.spacing.xs
                        Repeater {
                            model: ["C", "TM", "TA"]
                            delegate: Rectangle {
                                property bool attivo: statisticheVM.tipiSelezionati.indexOf(modelData) !== -1
                                width: 46; height: 28
                                radius: Theme.radius.sm
                                color: attivo ? Theme.colors.accent : Theme.colors.bgSurface3
                                border.width: 1
                                border.color: attivo ? Theme.colors.accent : Theme.colors.border
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: attivo ? "#0a0a0a" : Theme.colors.textSecondary
                                    font.family: Theme.typography.family
                                    font.pixelSize: Theme.typography.caption
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: statisticheVM.impostaTipoSelezionato(modelData, !parent.attivo)
                                }
                            }
                        }
                    }
                }

                Column {
                    spacing: Theme.spacing.xs
                    visible: statisticheVM.opzioniOrdinamento.length > 0
                    Text { text: "Ordina per"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    FMComboBox {
                        id: comboOrdinamento
                        width: 220
                        model: statisticheVM.opzioniOrdinamento
                        currentIndex: Math.max(0, statisticheVM.opzioniOrdinamento.indexOf(statisticheVM.ordinamentoCorrente))
                        onActivated: function(indice) { statisticheVM.impostaOrdinamento(statisticheVM.opzioniOrdinamento[indice]) }
                        background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                        contentItem: Text {
                            leftPadding: Theme.spacing.sm
                            text: comboOrdinamento.displayText
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                FMButton {
                    anchors.bottom: parent.bottom
                    text: "📄 Esporta Report PDF"
                    primary: true
                    onClicked: statisticheVM.esportaReportPdf()
                }
            }
        }

        // --- Vista 0: Presenze Allenamenti ---
        FMCard {
            width: parent.width
            visible: statisticheVM.vistaCorrente === 0
            title: "Presenze Allenamenti"
            Text {
                visible: statisticheVM.presenzePerGiocatore.length === 0
                text: "Nessun dato disponibile per il periodo selezionato."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Column {
                width: parent.width
                spacing: Theme.spacing.xs
                Repeater {
                    model: statisticheVM.presenzePerGiocatore
                    delegate: FMBarraStat {
                        width: parent.width
                        etichetta: modelData.nome + (modelData.attivo ? "" : " (eliminato)")
                        valoreTesto: modelData.presenze + "P / " + modelData.assenze + "A"
                        percentuale: Math.max(0, modelData.percentuale)
                    }
                }
            }
        }

        // --- Vista 1: Convocazioni Partite ---
        FMCard {
            width: parent.width
            visible: statisticheVM.vistaCorrente === 1
            title: "Convocazioni Partite"
            Text {
                visible: statisticheVM.convocazioniPerGiocatore.length === 0
                text: "Nessun dato disponibile per il periodo/filtro selezionato."
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.small
            }
            Column {
                width: parent.width
                spacing: Theme.spacing.xs
                Repeater {
                    model: statisticheVM.convocazioniPerGiocatore
                    delegate: FMBarraStat {
                        width: parent.width
                        etichetta: modelData.nome + (modelData.attivo ? "" : " (eliminato)")
                        valoreTesto: modelData.convocazioni + "C / " + modelData.nonConvocazioni + "NC"
                        percentuale: Math.max(0, modelData.percentuale)
                    }
                }
            }
        }

        // --- Vista 2: Risultati e Goal ---
        FMCard {
            width: parent.width
            visible: statisticheVM.vistaCorrente === 2
            title: "Risultati e Goal (Partite/Tornei)"

            Row {
                width: parent.width
                spacing: Theme.spacing.lg
                Repeater {
                    model: [
                        { etichetta: "Vittorie", valore: statisticheVM.vittorie, colore: Theme.colors.success },
                        { etichetta: "Pareggi", valore: statisticheVM.pareggi, colore: Theme.colors.warning },
                        { etichetta: "Sconfitte", valore: statisticheVM.sconfitte, colore: Theme.colors.danger },
                    ]
                    delegate: Rectangle {
                        width: 140; height: 64
                        radius: Theme.radius.sm
                        color: Theme.colors.bgSurface2
                        border.width: 1
                        border.color: modelData.colore
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { text: modelData.valore; color: modelData.colore; font.family: Theme.typography.family; font.pixelSize: Theme.typography.title; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.etichetta; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacing.lg
                Column {
                    width: (parent.width - Theme.spacing.lg) / 2
                    spacing: Theme.spacing.xs
                    Text { text: "Goal fatti"; color: Theme.colors.accent; font.family: Theme.typography.family; font.bold: true; font.pixelSize: Theme.typography.small }
                    Repeater {
                        model: statisticheVM.goalPerGiocatore
                        delegate: FMBarraStat {
                            width: parent.width
                            etichetta: modelData.nome + (modelData.attivo ? "" : " (eliminato)")
                            valoreTesto: String(modelData.goal)
                            percentuale: modelData.percentualeGoal
                        }
                    }
                }
                Column {
                    width: (parent.width - Theme.spacing.lg) / 2
                    spacing: Theme.spacing.xs
                    Text { text: "Media goal / partite giocate"; color: Theme.colors.accent; font.family: Theme.typography.family; font.bold: true; font.pixelSize: Theme.typography.small }
                    Repeater {
                        model: statisticheVM.goalPerGiocatore
                        delegate: FMBarraStat {
                            width: parent.width
                            etichetta: modelData.nome + (modelData.attivo ? "" : " (eliminato)")
                            valoreTesto: modelData.mediaGoal.toFixed(2)
                            percentuale: modelData.percentualeMedia
                        }
                    }
                }
            }
        }

        // --- Vista 3: Obiettivi e Mezzi Allenamento ---
        Row {
            width: parent.width
            spacing: Theme.spacing.lg
            visible: statisticheVM.vistaCorrente === 3

            FMCard {
                width: (parent.width - Theme.spacing.lg * 2) / 3
                title: "Mezzi di allenamento"
                Text {
                    visible: statisticheVM.minutiPerMezzo.length === 0
                    text: "Nessun dato disponibile."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }
                Column {
                    width: parent.width
                    spacing: Theme.spacing.xs
                    Repeater {
                        model: statisticheVM.minutiPerMezzo
                        delegate: FMBarraStat { width: parent.width; etichetta: modelData.nome; valoreTesto: modelData.valore + "'"; percentuale: modelData.percentuale }
                    }
                }
            }
            FMCard {
                width: (parent.width - Theme.spacing.lg * 2) / 3
                title: "Obiettivi tecnici"
                Text {
                    visible: statisticheVM.minutiPerTecnico.length === 0
                    text: "Nessun dato disponibile."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }
                Column {
                    width: parent.width
                    spacing: Theme.spacing.xs
                    Repeater {
                        model: statisticheVM.minutiPerTecnico
                        delegate: FMBarraStat { width: parent.width; etichetta: modelData.nome; valoreTesto: modelData.valore + "'"; percentuale: modelData.percentuale }
                    }
                }
            }
            FMCard {
                width: (parent.width - Theme.spacing.lg * 2) / 3
                title: "Obiettivi tattici"
                Text {
                    visible: statisticheVM.minutiPerTattico.length === 0
                    text: "Nessun dato disponibile."
                    color: Theme.colors.textSecondary
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }
                Column {
                    width: parent.width
                    spacing: Theme.spacing.xs
                    Repeater {
                        model: statisticheVM.minutiPerTattico
                        delegate: FMBarraStat { width: parent.width; etichetta: modelData.nome; valoreTesto: modelData.valore + "'"; percentuale: modelData.percentuale }
                    }
                }
            }
        }
    }
}
