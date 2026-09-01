import QtQuick
import QtQuick.Controls.Basic
import Theme

// Dialogo dedicato per un elemento "testo" della Coaching Board: testo,
// dimensione font (8-72pt), grassetto, colore - sostituisce il semplice
// TextField inline con stile fisso del primo editor.
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
    width: 360
    padding: Theme.spacing.md

    property int indiceElemento: -1

    signal applica(int indice, string testo, int fontSize, bool grassetto, string colore)

    function apriPer(indice, testoIniziale, fontSizeIniziale, grassettoIniziale, coloreIniziale) {
        root.indiceElemento = indice
        campoTesto.text = testoIniziale
        sliderFontSize.value = fontSizeIniziale
        checkGrassetto.checked = grassettoIniziale
        selettoreColore.coloreAttuale = coloreIniziale
        _coloreScelto = coloreIniziale
        open()
    }

    property string _coloreScelto: "#f4f6fb"

    background: Rectangle {
        color: Theme.colors.bgSurface; radius: Theme.radius.lg; border.width: 1; border.color: Theme.colors.border
        FMManigliaTrascinamento { bersaglio: root }
    }
    Overlay.modal: Rectangle { color: "#000000aa" }

    contentItem: Column {
        spacing: Theme.spacing.sm

        Text { text: "Modifica testo"; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.bold: true; font.pixelSize: Theme.typography.title }

        TextField {
            id: campoTesto
            width: parent.width
            placeholderText: "Testo"
            placeholderTextColor: Theme.colors.textSecondary
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.sm
            Text { text: "Dimensione:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small; anchors.verticalCenter: parent.verticalCenter }
            Slider { id: sliderFontSize; width: 160; from: 8; to: 72; stepSize: 1 }
            Text { text: Math.round(sliderFontSize.value) + "pt"; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small; anchors.verticalCenter: parent.verticalCenter }
        }

        Row {
            spacing: Theme.spacing.xs
            CheckBox { id: checkGrassetto }
            Text { text: "Grassetto"; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small; anchors.verticalCenter: parent.verticalCenter }
        }

        Text { text: "Colore:"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small }
        FMSelettoreColore {
            id: selettoreColore
            onColorScelto: function(colore) { root._coloreScelto = colore; selettoreColore.coloreAttuale = colore }
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.sm
            FMButton { text: "Annulla"; onClicked: root.close() }
            FMButton {
                primary: true
                text: "Applica"
                onClicked: {
                    root.applica(root.indiceElemento, campoTesto.text, Math.round(sliderFontSize.value), checkGrassetto.checked, root._coloreScelto)
                    root.close()
                }
            }
        }
    }
}
