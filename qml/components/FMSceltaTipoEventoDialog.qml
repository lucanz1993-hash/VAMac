import QtQuick
import QtQuick.Controls.Basic
import Theme

// Piccolo selettore "che tipo di evento e'?" per una data del Calendario &
// Eventi senza alcuna pianificazione a Macrociclo (stesso QInputDialog del
// vecchio DialogCalendario, "Nuovo Evento Extra").
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
    width: 320
    padding: Theme.spacing.md

    property string dataScelta: ""
    readonly property var tipi: [
        { c: "A", l: "Allenamento" },
        { c: "C", l: "Campionato" },
        { c: "TM", l: "Test Match / Amichevole" },
        { c: "TA", l: "Torneo" },
    ]

    signal tipoScelto(string dataStr, string tipo)

    function apriPer(dataStr) {
        root.dataScelta = dataStr
        open()
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

        Text {
            width: 280
            text: "Nessun evento pianificato in questa data.\nChe tipo di evento vuoi creare?"
            wrapMode: Text.WordWrap
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.small
        }

        Repeater {
            model: root.tipi
            delegate: FMButton {
                width: 280
                text: modelData.l
                onClicked: {
                    root.tipoScelto(root.dataScelta, modelData.c)
                    root.close()
                }
            }
        }

        FMButton { width: 280; text: "Annulla"; onClicked: root.close() }
    }
}
