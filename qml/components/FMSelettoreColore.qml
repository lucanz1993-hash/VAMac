import QtQuick
import Theme

// Selettore colore a tavolozza fissa: alternativa leggera a un vero
// color-picker (QColorDialog non e' disponibile in QtQuick.Controls.Basic
// senza un modulo aggiuntivo) - copre comunque lo stesso bisogno pratico
// del vecchio editor (assegnare un colore a un elemento/al campo) con una
// manciata di colori ben distinguibili invece di una ruota HSV completa.
Row {
    id: root
    spacing: 4

    property string coloreAttuale: ""
    readonly property var tavolozza: ["#3d5afe", "#e0544f", "#ffd400", "#4fd17a", "#ffffff", "#0a0a0a", "#e0a94a", "#8b008b", "#4fa3d1", "#d2691e"]

    signal colorScelto(string colore)

    Repeater {
        model: root.tavolozza
        delegate: Rectangle {
            width: 20; height: 20
            radius: 4
            color: modelData
            border.width: root.coloreAttuale === modelData ? 2 : 1
            border.color: root.coloreAttuale === modelData ? Theme.colors.accent : Theme.colors.border
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.colorScelto(modelData)
            }
        }
    }
}
